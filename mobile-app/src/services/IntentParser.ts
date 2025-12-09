/**
 * Intent Parser - Converts voice commands to structured intents
 *
 * Uses a two-layer approach:
 * 1. Fast regex for common patterns (~60% of commands)
 * 2. LLM fallback for complex/ambiguous cases
 *
 * This handles:
 * - Spanish/Spanglish ("cambia cien dolares a ether")
 * - Spoken numbers ("cero punto cinco")
 * - "all" amounts
 * - Noise and STT errors
 */

import { resolveToken, getTokenSymbol } from '../utils/tokens';
import { parseWithLLM, llmResultToSwapIntent, isLLMParserAvailable, type LLMParsedIntent } from './LLMParser';

export type ActionType =
  | 'swap'
  | 'quote'
  | 'status'
  | 'balance'
  | 'help'
  | 'confirm'
  | 'cancel'
  | 'enable_session'  // Enable quick swap mode (session keys)
  | 'disable_session' // Disable quick swap mode
  | 'session_status'  // Check session status
  | 'gas_tank_status' // Check Gas Tank balance
  | 'gas_tank_refill' // Get refill instructions
  | 'unknown';

export interface SwapIntent {
  action: ActionType;
  tokenIn?: string;
  tokenOut?: string;
  amountIn?: string;
  txHash?: string;
  confidence: number;
  rawText: string;
  parsedBy?: 'regex' | 'llm' | 'llm-fallback';
}

// Confidence threshold below which we use LLM
const LLM_FALLBACK_THRESHOLD = 0.8;

// Regex patterns for different commands
const PATTERNS = {
  // "Swap 100 USDC to ETH" / "Exchange 50 dollars for ether" / "Convert 0.5 ETH to USDC"
  swap: [
    /(?:swap|exchange|convert|trade|change)\s+(\d+(?:\.\d+)?)\s+(\w+(?:\s+\w+)?)\s+(?:to|for|into)\s+(\w+(?:\s+\w+)?)/i,
    /(?:buy|get)\s+(\w+(?:\s+\w+)?)\s+(?:with|using)\s+(\d+(?:\.\d+)?)\s+(\w+(?:\s+\w+)?)/i,
    /(?:sell)\s+(\d+(?:\.\d+)?)\s+(\w+(?:\s+\w+)?)\s+(?:for)\s+(\w+(?:\s+\w+)?)/i,
  ],

  // "Get quote for 100 USDC to ETH"
  quote: [
    /(?:quote|price|how much)\s+(?:for\s+)?(\d+(?:\.\d+)?)\s+(\w+(?:\s+\w+)?)\s+(?:to|for|into)\s+(\w+(?:\s+\w+)?)/i,
    /(?:what|how much)\s+(?:is|would)\s+(\d+(?:\.\d+)?)\s+(\w+(?:\s+\w+)?)\s+(?:get|be|worth)/i,
  ],

  // "Check status" / "What's the status of my swap"
  status: [
    /(?:check|what'?s?|get)\s+(?:the\s+)?status/i,
    /(?:is|did)\s+(?:my|the)\s+(?:swap|transaction|tx)\s+(?:complete|done|finished)/i,
    /(?:last|recent)\s+(?:swap|transaction)/i,
  ],

  // "What's my balance" / "Check balance"
  balance: [
    /(?:what'?s?|check|show|get)\s+(?:my\s+)?balance/i,
    /(?:how much)\s+(?:do i have|in my wallet)/i,
  ],

  // "Help" / "What can you do"
  help: [
    /^help$/i,
    /what\s+can\s+(?:you|i)\s+(?:do|say)/i,
    /(?:show|list)\s+commands/i,
  ],

  // Confirmation
  confirm: [
    /^(?:yes|yeah|yep|sure|ok|okay|confirm|do it|proceed|go ahead|execute)$/i,
    /(?:sounds good|let'?s? do it|make it happen)/i,
  ],

  // Cancellation
  cancel: [
    /^(?:no|nope|cancel|stop|nevermind|never mind|abort)$/i,
    /(?:don'?t|do not)\s+(?:do it|proceed|execute)/i,
  ],

  // Enable quick swap (session keys)
  enableSession: [
    /(?:enable|turn on|start|activate)\s+(?:quick\s+)?(?:swap|session|auto)/i,
    /(?:quick|fast)\s+(?:swap|mode)\s+(?:on|enable)/i,
    /(?:no|skip|without)\s+(?:confirm|confirmation)/i,
  ],

  // Disable quick swap
  disableSession: [
    /(?:disable|turn off|stop|deactivate)\s+(?:quick\s+)?(?:swap|session|auto)/i,
    /(?:quick|fast)\s+(?:swap|mode)\s+(?:off|disable)/i,
    /(?:require|need)\s+confirm/i,
    /(?:revoke|end)\s+session/i,
  ],

  // Session status
  sessionStatus: [
    /(?:session|quick swap)\s+(?:status|info|remaining)/i,
    /(?:how much|what'?s?)\s+(?:left|remaining)\s+(?:in|on)\s+(?:session|quick)/i,
  ],

  // Gas Tank status
  gasTankStatus: [
    /(?:gas\s*tank|credits?|prepaid)\s+(?:status|balance|remaining)/i,
    /(?:how much|what'?s?)\s+(?:in|left|remaining)\s+(?:my\s+)?(?:gas\s*tank|credits?)/i,
    /(?:how many)\s+swaps?\s+(?:can i|do i|remaining)/i,
  ],

  // Gas Tank refill
  gasTankRefill: [
    /(?:refill|add|deposit|top up)\s+(?:gas\s*tank|credits?|funds?)/i,
    /(?:gas\s*tank|credits?)\s+(?:refill|deposit|add)/i,
    /(?:how|where)\s+(?:to|can i)\s+(?:refill|add|deposit)/i,
  ],
};

/**
 * Parse a voice command using regex (fast path)
 * Returns intent with parsedBy: 'regex'
 */
function parseWithRegex(text: string): SwapIntent {
  const normalized = text.toLowerCase().trim();

  // Check for confirmation first (short responses)
  for (const pattern of PATTERNS.confirm) {
    if (pattern.test(normalized)) {
      return {
        action: 'confirm',
        confidence: 0.95,
        rawText: text,
      };
    }
  }

  // Check for cancellation
  for (const pattern of PATTERNS.cancel) {
    if (pattern.test(normalized)) {
      return {
        action: 'cancel',
        confidence: 0.95,
        rawText: text,
      };
    }
  }

  // Check for swap commands
  for (const pattern of PATTERNS.swap) {
    const match = normalized.match(pattern);
    if (match) {
      // Handle different pattern capture groups
      let amountIn: string;
      let tokenInRaw: string;
      let tokenOutRaw: string;

      if (pattern.source.includes('buy|get')) {
        // "buy ETH with 100 USDC" -> tokenOut, amount, tokenIn
        tokenOutRaw = match[1];
        amountIn = match[2];
        tokenInRaw = match[3];
      } else {
        // "swap 100 USDC to ETH" -> amount, tokenIn, tokenOut
        amountIn = match[1];
        tokenInRaw = match[2];
        tokenOutRaw = match[3];
      }

      const tokenIn = resolveToken(tokenInRaw);
      const tokenOut = resolveToken(tokenOutRaw);

      if (tokenIn && tokenOut && amountIn) {
        return {
          action: 'swap',
          amountIn,
          tokenIn,
          tokenOut,
          confidence: 0.9,
          rawText: text,
        };
      }

      // Partial match - tokens not recognized
      return {
        action: 'swap',
        amountIn,
        confidence: 0.5,
        rawText: text,
      };
    }
  }

  // Check for quote commands
  for (const pattern of PATTERNS.quote) {
    const match = normalized.match(pattern);
    if (match) {
      const amountIn = match[1];
      const tokenIn = resolveToken(match[2]);
      const tokenOut = match[3] ? resolveToken(match[3]) : undefined;

      return {
        action: 'quote',
        amountIn,
        tokenIn: tokenIn || undefined,
        tokenOut: tokenOut || undefined,
        confidence: tokenIn && tokenOut ? 0.85 : 0.5,
        rawText: text,
      };
    }
  }

  // Check for status commands
  for (const pattern of PATTERNS.status) {
    if (pattern.test(normalized)) {
      return {
        action: 'status',
        confidence: 0.9,
        rawText: text,
      };
    }
  }

  // Check for balance commands
  for (const pattern of PATTERNS.balance) {
    if (pattern.test(normalized)) {
      return {
        action: 'balance',
        confidence: 0.9,
        rawText: text,
      };
    }
  }

  // Check for help commands
  for (const pattern of PATTERNS.help) {
    if (pattern.test(normalized)) {
      return {
        action: 'help',
        confidence: 0.95,
        rawText: text,
      };
    }
  }

  // Check for session enable commands
  for (const pattern of PATTERNS.enableSession) {
    if (pattern.test(normalized)) {
      return {
        action: 'enable_session',
        confidence: 0.9,
        rawText: text,
      };
    }
  }

  // Check for session disable commands
  for (const pattern of PATTERNS.disableSession) {
    if (pattern.test(normalized)) {
      return {
        action: 'disable_session',
        confidence: 0.9,
        rawText: text,
      };
    }
  }

  // Check for session status commands
  for (const pattern of PATTERNS.sessionStatus) {
    if (pattern.test(normalized)) {
      return {
        action: 'session_status',
        confidence: 0.9,
        rawText: text,
      };
    }
  }

  // Check for Gas Tank status commands
  for (const pattern of PATTERNS.gasTankStatus) {
    if (pattern.test(normalized)) {
      return {
        action: 'gas_tank_status',
        confidence: 0.9,
        rawText: text,
      };
    }
  }

  // Check for Gas Tank refill commands
  for (const pattern of PATTERNS.gasTankRefill) {
    if (pattern.test(normalized)) {
      return {
        action: 'gas_tank_refill',
        confidence: 0.9,
        rawText: text,
      };
    }
  }

  // Unknown command
  return {
    action: 'unknown',
    confidence: 0,
    rawText: text,
    parsedBy: 'regex',
  };
}

/**
 * Main parser function - combines regex (fast) with LLM (smart) fallback
 *
 * Strategy:
 * 1. Try regex first (fast, handles ~60% of clear commands)
 * 2. If confidence < 0.8 OR action is 'unknown', use LLM
 * 3. LLM handles Spanish, spoken numbers, ambiguous phrasing
 */
export async function parseVoiceCommandAsync(text: string): Promise<SwapIntent> {
  // Try regex first (synchronous, fast)
  const regexResult = parseWithRegex(text);

  // If regex is confident enough, use it
  if (regexResult.confidence >= LLM_FALLBACK_THRESHOLD && regexResult.action !== 'unknown') {
    console.log(`[IntentParser] Regex parsed with confidence ${regexResult.confidence}: ${regexResult.action}`);
    return { ...regexResult, parsedBy: 'regex' };
  }

  // Check if LLM is available
  if (!isLLMParserAvailable()) {
    console.log('[IntentParser] LLM not available, using regex result');
    return { ...regexResult, parsedBy: 'regex' };
  }

  // Use LLM for low-confidence or unknown commands
  console.log(`[IntentParser] Regex confidence ${regexResult.confidence}, falling back to LLM`);

  try {
    const llmResult = await parseWithLLM(text);
    const intent = llmResultToSwapIntent(llmResult);

    console.log(`[IntentParser] LLM parsed: ${intent.action} (confidence: ${intent.confidence})`);

    return {
      ...intent,
      parsedBy: llmResult.parsedBy,
    };
  } catch (error) {
    console.error('[IntentParser] LLM failed, using regex result:', error);
    return { ...regexResult, parsedBy: 'regex' };
  }
}

/**
 * Synchronous parser (regex only) - for backwards compatibility
 * Use parseVoiceCommandAsync when possible for better accuracy
 */
export function parseVoiceCommand(text: string): SwapIntent {
  const result = parseWithRegex(text);
  return { ...result, parsedBy: 'regex' };
}

/**
 * Generate a human-readable description of the intent
 */
export function describeIntent(intent: SwapIntent): string {
  switch (intent.action) {
    case 'swap':
      if (intent.tokenIn && intent.tokenOut && intent.amountIn) {
        return `Swap ${intent.amountIn} ${getTokenSymbol(intent.tokenIn)} to ${getTokenSymbol(intent.tokenOut)}`;
      }
      return 'Swap (incomplete parameters)';

    case 'quote':
      if (intent.tokenIn && intent.tokenOut && intent.amountIn) {
        return `Get quote for ${intent.amountIn} ${getTokenSymbol(intent.tokenIn)} to ${getTokenSymbol(intent.tokenOut)}`;
      }
      return 'Get quote (incomplete parameters)';

    case 'status':
      return 'Check swap status';

    case 'balance':
      return 'Check wallet balance';

    case 'help':
      return 'Show help';

    case 'confirm':
      return 'Confirm action';

    case 'cancel':
      return 'Cancel action';

    case 'enable_session':
      return 'Enable quick swap mode';

    case 'disable_session':
      return 'Disable quick swap mode';

    case 'session_status':
      return 'Check session status';

    case 'gas_tank_status':
      return 'Check Gas Tank balance';

    case 'gas_tank_refill':
      return 'Get Gas Tank refill instructions';

    default:
      return `Unknown command: "${intent.rawText}"`;
  }
}

/**
 * Validate that an intent has all required parameters
 */
export function validateIntent(intent: SwapIntent): { valid: boolean; missing: string[] } {
  const missing: string[] = [];

  if (intent.action === 'swap' || intent.action === 'quote') {
    if (!intent.amountIn) missing.push('amount');
    if (!intent.tokenIn) missing.push('source token');
    if (!intent.tokenOut) missing.push('destination token');
  }

  return {
    valid: missing.length === 0,
    missing,
  };
}
