/**
 * LLM Parser - OpenAI-powered intent extraction
 *
 * Uses GPT-4o-mini with Structured Outputs to parse voice commands
 * into strict JSON intents. Falls back to GPT-4o for ambiguous cases.
 *
 * Benefits over regex:
 * - Handles Spanish/Spanglish ("cien USDC", "cambia todo mi ETH")
 * - Normalizes spoken numbers ("cero punto cinco" -> "0.5")
 * - Handles "all" / "todo" / "max" amounts
 * - Better with noise and speech-to-text errors
 */

import OpenAI from 'openai';
import { resolveToken } from '../utils/tokens';
import type { SwapIntent, ActionType } from './IntentParser';

// Initialize OpenAI client
const client = new OpenAI({
  apiKey: process.env.EXPO_PUBLIC_OPENAI_API_KEY,
});

// Supported tokens for the schema enum
const SUPPORTED_TOKENS = ['USDC', 'WETH', 'ETH', 'DAI', 'USDbC', 'USDT'] as const;

// Supported actions
const SUPPORTED_ACTIONS = [
  'swap',
  'quote',
  'status',
  'balance',
  'help',
  'confirm',
  'cancel',
  'enable_session',
  'disable_session',
  'session_status',
  'gas_tank_status',
  'gas_tank_refill',
  'unknown',
] as const;

// JSON Schema for Structured Outputs
const SwapIntentSchema = {
  name: 'swap_intent',
  strict: true,
  schema: {
    type: 'object',
    additionalProperties: false,
    properties: {
      action: {
        type: 'string',
        enum: SUPPORTED_ACTIONS,
        description: 'The action the user wants to perform',
      },
      amount: {
        type: ['string', 'null'],
        description: 'Amount to swap/quote. Use "all" for max balance. Normalize spoken numbers.',
      },
      tokenIn: {
        type: ['string', 'null'],
        enum: [...SUPPORTED_TOKENS, null],
        description: 'Source token. Normalize aliases (ETH=WETH, dollars/usd=USDC)',
      },
      tokenOut: {
        type: ['string', 'null'],
        enum: [...SUPPORTED_TOKENS, null],
        description: 'Destination token',
      },
      confidence: {
        type: 'number',
        minimum: 0,
        maximum: 1,
        description: 'Confidence in the parsed intent (0-1)',
      },
      needsConfirmation: {
        type: 'boolean',
        description: 'True if missing info or ambiguous',
      },
      clarificationNeeded: {
        type: ['string', 'null'],
        description: 'What info is missing, if any',
      },
    },
    required: [
      'action',
      'amount',
      'tokenIn',
      'tokenOut',
      'confidence',
      'needsConfirmation',
      'clarificationNeeded',
    ],
  },
};

// System prompt for intent extraction
const SYSTEM_PROMPT = `You are a voice command parser for a crypto swap app. Extract trading intents from user speech and return ONLY valid JSON.

RULES:
1. Normalize token aliases:
   - "ETH", "ether", "ethereum" -> "ETH" (use ETH, not WETH for user-facing)
   - "dollars", "usd", "usdc", "stablecoins" -> "USDC"
   - "dai" -> "DAI"
   - "wrapped eth" -> "WETH"

2. Normalize amounts:
   - Spanish numbers: "cien" -> "100", "mil" -> "1000", "cero punto cinco" -> "0.5"
   - "all", "todo", "max", "everything", "all my X" -> "all"
   - "half", "mitad" -> use actual number if possible, else null with clarification

3. Action mapping:
   - "swap", "exchange", "trade", "convert", "change", "cambia" -> "swap"
   - "quote", "price", "how much", "cuanto" -> "quote"
   - "status", "check", "is it done", "esta listo" -> "status"
   - "balance", "how much do I have", "cuanto tengo" -> "balance"
   - "help", "ayuda", "what can you do" -> "help"
   - "yes", "yeah", "sure", "ok", "si", "dale" -> "confirm"
   - "no", "cancel", "stop", "cancelar" -> "cancel"
   - "enable quick swap", "skip confirmations" -> "enable_session"
   - "disable quick swap", "require confirmations" -> "disable_session"
   - "session status", "quick swap status" -> "session_status"
   - "gas tank", "credits", "prepaid balance" -> "gas_tank_status"
   - "refill", "add funds", "deposit" -> "gas_tank_refill"

4. Confidence scoring:
   - 1.0: Clear command with all params ("swap 100 USDC to ETH")
   - 0.8-0.9: Clear but informal ("trade my hundred bucks for eth")
   - 0.5-0.7: Missing some info or ambiguous
   - <0.5: Very unclear, likely noise

5. If missing critical info for swap/quote (amount OR tokens), set needsConfirmation=true and explain in clarificationNeeded.

EXAMPLES:
- "swap 100 USDC to ETH" -> action:"swap", amount:"100", tokenIn:"USDC", tokenOut:"ETH", confidence:1.0
- "cambia cien dolares a ether" -> action:"swap", amount:"100", tokenIn:"USDC", tokenOut:"ETH", confidence:0.9
- "how much ETH for 50 bucks" -> action:"quote", amount:"50", tokenIn:"USDC", tokenOut:"ETH", confidence:0.9
- "swap all my ETH" -> action:"swap", amount:"all", tokenIn:"ETH", tokenOut:null, needsConfirmation:true, clarificationNeeded:"What token do you want to receive?"
- "yes" -> action:"confirm", confidence:1.0
- "check status" -> action:"status", confidence:1.0
- "gas tank balance" -> action:"gas_tank_status", confidence:1.0`;

/**
 * LLM-parsed intent result
 */
export interface LLMParsedIntent {
  action: ActionType;
  amount: string | null;
  tokenIn: string | null;
  tokenOut: string | null;
  confidence: number;
  needsConfirmation: boolean;
  clarificationNeeded: string | null;
  rawText: string;
  parsedBy: 'llm' | 'llm-fallback';
}

/**
 * Parse a voice command using GPT-4o-mini with Structured Outputs
 */
export async function parseWithLLM(text: string): Promise<LLMParsedIntent> {
  try {
    const response = await client.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: text },
      ],
      response_format: {
        type: 'json_schema',
        json_schema: SwapIntentSchema,
      },
      temperature: 0.1, // Low temperature for consistent parsing
      max_tokens: 200,
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      throw new Error('No response from LLM');
    }

    const parsed = JSON.parse(content);

    // Normalize token addresses if needed
    const tokenIn = parsed.tokenIn ? normalizeToken(parsed.tokenIn) : null;
    const tokenOut = parsed.tokenOut ? normalizeToken(parsed.tokenOut) : null;

    return {
      action: parsed.action as ActionType,
      amount: parsed.amount,
      tokenIn,
      tokenOut,
      confidence: parsed.confidence,
      needsConfirmation: parsed.needsConfirmation,
      clarificationNeeded: parsed.clarificationNeeded,
      rawText: text,
      parsedBy: 'llm',
    };
  } catch (error) {
    console.error('[LLMParser] Error with gpt-4o-mini:', error);

    // Fallback to GPT-4o for complex cases
    return parseWithLLMFallback(text);
  }
}

/**
 * Fallback parser using GPT-4o for ambiguous cases
 */
async function parseWithLLMFallback(text: string): Promise<LLMParsedIntent> {
  try {
    const response = await client.chat.completions.create({
      model: 'gpt-4o',
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: text },
      ],
      response_format: {
        type: 'json_schema',
        json_schema: SwapIntentSchema,
      },
      temperature: 0.1,
      max_tokens: 200,
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      throw new Error('No response from fallback LLM');
    }

    const parsed = JSON.parse(content);

    return {
      action: parsed.action as ActionType,
      amount: parsed.amount,
      tokenIn: parsed.tokenIn ? normalizeToken(parsed.tokenIn) : null,
      tokenOut: parsed.tokenOut ? normalizeToken(parsed.tokenOut) : null,
      confidence: parsed.confidence,
      needsConfirmation: parsed.needsConfirmation,
      clarificationNeeded: parsed.clarificationNeeded,
      rawText: text,
      parsedBy: 'llm-fallback',
    };
  } catch (error) {
    console.error('[LLMParser] Fallback also failed:', error);

    // Return unknown intent
    return {
      action: 'unknown',
      amount: null,
      tokenIn: null,
      tokenOut: null,
      confidence: 0,
      needsConfirmation: true,
      clarificationNeeded: 'Could not understand the command',
      rawText: text,
      parsedBy: 'llm-fallback',
    };
  }
}

/**
 * Normalize token symbol to address
 */
function normalizeToken(symbol: string): string {
  // Use the existing token resolver
  const resolved = resolveToken(symbol);
  return resolved || symbol.toUpperCase();
}

/**
 * Convert LLM result to SwapIntent format (for compatibility)
 */
export function llmResultToSwapIntent(result: LLMParsedIntent): SwapIntent {
  return {
    action: result.action,
    amountIn: result.amount || undefined,
    tokenIn: result.tokenIn || undefined,
    tokenOut: result.tokenOut || undefined,
    confidence: result.confidence,
    rawText: result.rawText,
  };
}

/**
 * Check if LLM parsing is available (API key configured)
 */
export function isLLMParserAvailable(): boolean {
  return !!process.env.EXPO_PUBLIC_OPENAI_API_KEY;
}

export default {
  parseWithLLM,
  llmResultToSwapIntent,
  isLLMParserAvailable,
};
