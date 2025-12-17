/**
 * OpenAI Service for VoiceSwap
 *
 * Natural language intent parsing for voice-activated payments.
 * Handles commands like:
 * - "Paga 50 dólares al café"
 * - "Send 100 USDC to the merchant"
 * - "Cuánto tengo en mi wallet?"
 * - "Swap my ETH to USDC"
 */

import OpenAI from 'openai';

// Initialize OpenAI client
const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

/**
 * Intent types that VoiceSwap can handle
 */
export type IntentType =
  | 'payment'        // Send payment to merchant
  | 'balance'        // Check wallet balance
  | 'swap'           // Swap tokens
  | 'confirm'        // Confirm pending transaction
  | 'cancel'         // Cancel pending transaction
  | 'help'           // Request help/information
  | 'unknown';       // Unrecognized intent

/**
 * Parsed intent from natural language
 */
export interface ParsedIntent {
  type: IntentType;
  confidence: number; // 0-1 confidence score
  amount?: string;    // Amount in original currency
  currency?: string;  // Currency mentioned (USD, USDC, ETH, etc.)
  recipient?: string; // Merchant name or identifier
  tokenIn?: string;   // Token to swap from
  tokenOut?: string;  // Token to swap to
  rawText: string;    // Original transcript
  language: 'en' | 'es' | 'other';
}

/**
 * System prompt for intent parsing
 */
const SYSTEM_PROMPT = `You are a voice command parser for VoiceSwap, a crypto payment app for Meta Ray-Ban smart glasses.

Your job is to parse natural language commands and extract structured intent data.

The app operates on Unichain blockchain and supports:
- USDC (stablecoin, primary payment currency)
- ETH/WETH (Ethereum)

Common command patterns:
1. PAYMENT: "pay X dollars to merchant", "send X USDC", "paga X dólares", "envía X al vendedor"
2. BALANCE: "what's my balance", "how much do I have", "cuánto tengo", "mi saldo"
3. SWAP: "swap ETH to USDC", "convert my ETH", "cambiar ETH por USDC"
4. CONFIRM: "yes", "confirm", "do it", "sí", "confirmar", "dale"
5. CANCEL: "no", "cancel", "stop", "cancelar", "no quiero"
6. HELP: "help", "how does this work", "ayuda", "cómo funciona"

When amounts mention "dollars" or "dólares", treat as USDC.
When amounts are just numbers in payment context, assume USDC.

Respond ONLY with valid JSON matching this schema:
{
  "type": "payment" | "balance" | "swap" | "confirm" | "cancel" | "help" | "unknown",
  "confidence": 0.0-1.0,
  "amount": "string or null",
  "currency": "USD" | "USDC" | "ETH" | "WETH" | null,
  "recipient": "string or null",
  "tokenIn": "string or null",
  "tokenOut": "string or null",
  "language": "en" | "es" | "other"
}`;

/**
 * Parse natural language voice command into structured intent
 */
export async function parseIntent(transcript: string): Promise<ParsedIntent> {
  try {
    const response = await openai.chat.completions.create({
      model: 'gpt-4o-mini', // Fast and cheap for simple parsing
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: transcript },
      ],
      temperature: 0.1, // Low temperature for consistent parsing
      max_tokens: 200,
      response_format: { type: 'json_object' },
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      throw new Error('No response from OpenAI');
    }

    const parsed = JSON.parse(content);

    return {
      type: parsed.type || 'unknown',
      confidence: parsed.confidence || 0,
      amount: parsed.amount || undefined,
      currency: parsed.currency || undefined,
      recipient: parsed.recipient || undefined,
      tokenIn: parsed.tokenIn || undefined,
      tokenOut: parsed.tokenOut || undefined,
      rawText: transcript,
      language: parsed.language || 'other',
    };
  } catch (error) {
    console.error('[OpenAI] Parse intent error:', error);

    // Fallback to basic keyword matching
    return fallbackParse(transcript);
  }
}

/**
 * Fallback parser using keyword matching
 * Used when OpenAI API is unavailable
 */
function fallbackParse(transcript: string): ParsedIntent {
  const text = transcript.toLowerCase().trim();
  const language = detectLanguage(text);

  // Confirm patterns
  const confirmPatterns = ['confirm', 'yes', 'do it', 'ok', 'sí', 'si', 'dale', 'confirmar', 'hazlo'];
  if (confirmPatterns.some(p => text.includes(p))) {
    return {
      type: 'confirm',
      confidence: 0.8,
      rawText: transcript,
      language,
    };
  }

  // Cancel patterns
  const cancelPatterns = ['cancel', 'no', 'stop', 'cancelar', 'parar', 'detener'];
  if (cancelPatterns.some(p => text.includes(p))) {
    return {
      type: 'cancel',
      confidence: 0.8,
      rawText: transcript,
      language,
    };
  }

  // Balance patterns
  const balancePatterns = ['balance', 'how much', 'cuánto', 'cuanto', 'saldo', 'tengo'];
  if (balancePatterns.some(p => text.includes(p))) {
    return {
      type: 'balance',
      confidence: 0.7,
      rawText: transcript,
      language,
    };
  }

  // Payment patterns with amount extraction
  const payPatterns = ['pay', 'send', 'paga', 'pagar', 'envía', 'enviar', 'transfer'];
  if (payPatterns.some(p => text.includes(p))) {
    const amountMatch = text.match(/(\d+(?:\.\d+)?)/);
    return {
      type: 'payment',
      confidence: 0.6,
      amount: amountMatch ? amountMatch[1] : undefined,
      currency: 'USDC',
      rawText: transcript,
      language,
    };
  }

  // Swap patterns
  const swapPatterns = ['swap', 'convert', 'exchange', 'cambiar', 'intercambiar'];
  if (swapPatterns.some(p => text.includes(p))) {
    return {
      type: 'swap',
      confidence: 0.6,
      rawText: transcript,
      language,
    };
  }

  // Help patterns
  const helpPatterns = ['help', 'how', 'what', 'ayuda', 'cómo', 'como', 'qué', 'que'];
  if (helpPatterns.some(p => text.includes(p))) {
    return {
      type: 'help',
      confidence: 0.5,
      rawText: transcript,
      language,
    };
  }

  return {
    type: 'unknown',
    confidence: 0,
    rawText: transcript,
    language,
  };
}

/**
 * Detect language from text
 */
function detectLanguage(text: string): 'en' | 'es' | 'other' {
  const spanishIndicators = [
    'pagar', 'enviar', 'cuánto', 'cuanto', 'saldo', 'confirmar',
    'cancelar', 'ayuda', 'cómo', 'qué', 'dólares', 'dolares',
    'hazlo', 'dale', 'sí', 'quiero', 'tengo', 'mi', 'el', 'la',
  ];

  const englishIndicators = [
    'pay', 'send', 'how much', 'balance', 'confirm', 'cancel',
    'help', 'what', 'the', 'my', 'do it', 'yes', 'no',
  ];

  const spanishCount = spanishIndicators.filter(w => text.includes(w)).length;
  const englishCount = englishIndicators.filter(w => text.includes(w)).length;

  if (spanishCount > englishCount) return 'es';
  if (englishCount > spanishCount) return 'en';
  return 'other';
}

/**
 * Generate natural language response based on intent
 */
export function generateResponse(intent: ParsedIntent, context?: {
  balance?: string;
  ethBalance?: string;
  merchantName?: string;
  txHash?: string;
  error?: string;
}): string {
  const isSpanish = intent.language === 'es';

  switch (intent.type) {
    case 'payment':
      if (intent.amount && context?.merchantName) {
        return isSpanish
          ? `Preparando pago de ${intent.amount} ${intent.currency || 'USDC'} a ${context.merchantName}. Di "confirmar" para continuar.`
          : `Preparing payment of ${intent.amount} ${intent.currency || 'USDC'} to ${context.merchantName}. Say "confirm" to proceed.`;
      }
      return isSpanish
        ? 'Por favor escanea el código QR del vendedor para continuar.'
        : 'Please scan the merchant QR code to continue.';

    case 'balance':
      if (context?.balance !== undefined || context?.ethBalance !== undefined) {
        const usdc = parseFloat(context.balance || '0');
        const eth = parseFloat(context.ethBalance || '0');
        // ETH price approximation (could use price feed API later)
        const ETH_PRICE_USD = 3900;
        const ethValueUSD = eth * ETH_PRICE_USD;
        const totalUSD = Math.round(ethValueUSD + usdc);

        // Build a natural response with total USD value
        if (eth > 0 && usdc > 0) {
          return isSpanish
            ? `Tienes aproximadamente ${totalUSD} dólares disponibles: ${usdc.toFixed(2)} USDC y ${eth.toFixed(4)} ETH.`
            : `You have about ${totalUSD} dollars available: ${usdc.toFixed(2)} USDC and ${eth.toFixed(4)} ETH.`;
        } else if (eth > 0) {
          return isSpanish
            ? `Tienes aproximadamente ${totalUSD} dólares en ETH. Puedo intercambiarlo a USDC para pagos.`
            : `You have about ${totalUSD} dollars in ETH. I can swap it to USDC for payments.`;
        } else if (usdc > 0) {
          return isSpanish
            ? `Tienes ${usdc.toFixed(2)} dólares en USDC disponibles para pagar.`
            : `You have ${usdc.toFixed(2)} dollars in USDC available to pay.`;
        }
        return isSpanish
          ? 'Tu wallet está vacía. Deposita ETH o USDC para hacer pagos.'
          : 'Your wallet is empty. Deposit ETH or USDC to make payments.';
      }
      return isSpanish
        ? 'Consultando tu saldo...'
        : 'Checking your balance...';

    case 'swap':
      return isSpanish
        ? `Preparando swap de ${intent.tokenIn || 'ETH'} a ${intent.tokenOut || 'USDC'}. Di "confirmar" para continuar.`
        : `Preparing swap from ${intent.tokenIn || 'ETH'} to ${intent.tokenOut || 'USDC'}. Say "confirm" to proceed.`;

    case 'confirm':
      return isSpanish
        ? 'Procesando tu transacción...'
        : 'Processing your transaction...';

    case 'cancel':
      return isSpanish
        ? 'Transacción cancelada. No se enviaron fondos.'
        : 'Transaction cancelled. No funds were sent.';

    case 'help':
      return isSpanish
        ? 'VoiceSwap te permite pagar con cripto usando tu voz. Escanea un QR y di cuánto quieres pagar.'
        : 'VoiceSwap lets you pay with crypto using your voice. Scan a QR and say how much you want to pay.';

    case 'unknown':
    default:
      return isSpanish
        ? 'No entendí el comando. Puedes decir "pagar", "saldo", o "ayuda".'
        : 'I didn\'t understand that. You can say "pay", "balance", or "help".';
  }
}

/**
 * Extract payment amount from complex natural language
 */
export async function extractPaymentDetails(transcript: string): Promise<{
  amount?: string;
  currency?: string;
  recipient?: string;
  notes?: string;
}> {
  try {
    const response = await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: `Extract payment details from the text. Return JSON with:
{
  "amount": "numeric amount as string",
  "currency": "USD/USDC/ETH",
  "recipient": "merchant name or description",
  "notes": "any additional context"
}
If "dollars" or "dólares" is mentioned, currency is "USD" (will be converted to USDC).
Return null for fields that cannot be determined.`,
        },
        { role: 'user', content: transcript },
      ],
      temperature: 0,
      max_tokens: 150,
      response_format: { type: 'json_object' },
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      return {};
    }

    return JSON.parse(content);
  } catch (error) {
    console.error('[OpenAI] Extract payment details error:', error);
    return {};
  }
}

/**
 * Check if OpenAI API is configured and working
 */
export async function healthCheck(): Promise<{
  configured: boolean;
  working: boolean;
  error?: string;
}> {
  if (!process.env.OPENAI_API_KEY) {
    return {
      configured: false,
      working: false,
      error: 'OPENAI_API_KEY not set',
    };
  }

  try {
    await openai.chat.completions.create({
      model: 'gpt-4o-mini',
      messages: [{ role: 'user', content: 'test' }],
      max_tokens: 1,
    });

    return {
      configured: true,
      working: true,
    };
  } catch (error: any) {
    return {
      configured: true,
      working: false,
      error: error.message,
    };
  }
}

export default {
  parseIntent,
  generateResponse,
  extractPaymentDetails,
  healthCheck,
};
