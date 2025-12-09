/**
 * Swap Service - x402 Backend Client
 *
 * Handles communication with the x402 Swap Executor backend.
 * Integrates with Gas Tank for prepaid balance management.
 * Uses idempotency keys to prevent double charges on retries.
 */

import { getTokenSymbol, formatTokenAmount } from '../utils/tokens';
import { gasTankService, X402_PRICING } from './GasTankService';

/**
 * Generate a unique idempotency key for a request
 * Format: timestamp-random (ensures uniqueness even with fast retries)
 */
function generateIdempotencyKey(): string {
  const timestamp = Date.now().toString(36);
  const random = Math.random().toString(36).substring(2, 10);
  return `${timestamp}-${random}`;
}

/**
 * Generate a request ID for tracking
 */
function generateRequestId(): string {
  return `req-${Date.now()}-${Math.random().toString(36).substring(2, 8)}`;
}

// Backend configuration
const BACKEND_URL = process.env.EXPO_PUBLIC_BACKEND_URL || 'http://localhost:4021';

// Types
export interface TokenInfo {
  address: string;
  symbol: string;
  decimals: number;
  amount: string;
  amountRaw: string;
}

export interface QuoteResponse {
  tokenIn: TokenInfo;
  tokenOut: TokenInfo;
  priceImpact: string;
  route: string[];
  estimatedGas: string;
  timestamp: number;
}

export interface RouteResponse extends QuoteResponse {
  calldata?: string;
  value?: string;
  to?: string;
  slippageTolerance: number;
  deadline: number;
}

export interface ExecuteResponse {
  status: 'pending' | 'submitted' | 'confirmed' | 'failed';
  txHash?: string;
  error?: string;
}

export interface StatusResponse {
  status: 'pending' | 'confirmed' | 'failed' | 'not_found';
  txHash: string;
  blockNumber?: number;
  confirmations?: number;
  gasUsed?: string;
  effectiveGasPrice?: string;
}

export interface SwapParams {
  tokenIn: string;
  tokenOut: string;
  amountIn: string;
  recipient: string;
  slippageTolerance?: number;
}

export interface ApiResponse<T> {
  success: boolean;
  data?: T;
  error?: string;
  code?: string;
}

/**
 * Extract endpoint path from URL for Gas Tank pricing
 */
function extractEndpoint(url: string): keyof typeof X402_PRICING | null {
  const path = new URL(url).pathname;
  if (path.startsWith('/quote')) return '/quote';
  if (path.startsWith('/route')) return '/route';
  if (path.startsWith('/execute')) return '/execute';
  if (path.startsWith('/status')) return '/status';
  return null;
}

/**
 * Custom error for insufficient Gas Tank balance
 */
export class InsufficientGasTankError extends Error {
  public required: number;
  public available: number;

  constructor(required: number, available: number) {
    super(`Insufficient Gas Tank balance. Required: $${required}, Available: $${available.toFixed(4)}`);
    this.name = 'InsufficientGasTankError';
    this.required = required;
    this.available = available;
  }
}

/**
 * Custom fetch wrapper that handles x402 payment flow using Gas Tank
 *
 * Instead of paying per-request, we deduct from the prepaid Gas Tank balance.
 * If Gas Tank is empty, we fall back to on-demand x402 payment.
 *
 * Features:
 * - Idempotency keys to prevent double charges on retries
 * - Request IDs for tracking/debugging
 * - Gas Tank integration for prepaid balance
 */
async function x402Fetch(
  url: string,
  options: RequestInit = {},
  idempotencyKey?: string
): Promise<Response> {
  const endpoint = extractEndpoint(url);

  // Generate idempotency key if not provided (for paid endpoints)
  const idemKey = idempotencyKey || (endpoint ? generateIdempotencyKey() : undefined);
  const requestId = generateRequestId();

  // Check if this is a paid endpoint
  if (endpoint) {
    // Try to pay from Gas Tank first
    const payment = await gasTankService.generatePayment(endpoint);

    if (payment.success && payment.paymentHeader) {
      // We have prepaid balance - send with Gas Tank payment header
      const response = await fetch(url, {
        ...options,
        headers: {
          'Content-Type': 'application/json',
          'X-Payment': payment.paymentHeader,
          'X-Idempotency-Key': idemKey!,
          'X-Request-Id': requestId,
          ...options.headers,
        },
      });

      // If payment was accepted, return response
      if (response.status !== 402) {
        return response;
      }

      // Gas Tank payment not accepted, fall through to on-demand payment
      console.log('[SwapService] Gas Tank payment not accepted, trying on-demand');
    } else {
      // No Gas Tank balance - check if we should throw or try on-demand
      const cost = X402_PRICING[endpoint];
      const balance = gasTankService.getBalance();

      console.log(`[SwapService] Gas Tank empty. Need $${cost} for ${endpoint}`);

      // For now, throw error to prompt user to refill
      throw new InsufficientGasTankError(cost, balance);
    }
  }

  // Make request without prepaid payment (for free endpoints or on-demand)
  const response = await fetch(url, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(idemKey && { 'X-Idempotency-Key': idemKey }),
      'X-Request-Id': requestId,
      ...options.headers,
    },
  });

  // Handle 402 Payment Required (fallback to on-demand payment)
  if (response.status === 402) {
    // In production, this would trigger the x402 payment flow:
    // 1. Parse payment requirements from response headers
    // 2. Sign payment with user's wallet
    // 3. Retry request with payment proof

    // For now, throw an error that the UI can handle
    const paymentInfo = {
      address: response.headers.get('X-Payment-Address'),
      amount: response.headers.get('X-Payment-Amount'),
      network: response.headers.get('X-Payment-Network'),
    };

    throw new PaymentRequiredError('Payment required for this endpoint', paymentInfo);
  }

  return response;
}

/**
 * Custom error for x402 payment requirements
 */
export class PaymentRequiredError extends Error {
  public paymentInfo: {
    address: string | null;
    amount: string | null;
    network: string | null;
  };

  constructor(message: string, paymentInfo: PaymentRequiredError['paymentInfo']) {
    super(message);
    this.name = 'PaymentRequiredError';
    this.paymentInfo = paymentInfo;
  }
}

/**
 * SwapService class for interacting with the backend
 */
class SwapService {
  private baseUrl: string;
  private lastTxHash: string | null = null;

  constructor(baseUrl: string = BACKEND_URL) {
    this.baseUrl = baseUrl;
  }

  /**
   * Get a quote for a swap
   * Cost: $0.001
   */
  async getQuote(tokenIn: string, tokenOut: string, amountIn: string): Promise<QuoteResponse> {
    const url = new URL(`${this.baseUrl}/quote`);
    url.searchParams.set('tokenIn', tokenIn);
    url.searchParams.set('tokenOut', tokenOut);
    url.searchParams.set('amountIn', amountIn);

    const response = await x402Fetch(url.toString());
    const data: ApiResponse<QuoteResponse> = await response.json();

    if (!data.success || !data.data) {
      throw new Error(data.error || 'Failed to get quote');
    }

    return data.data;
  }

  /**
   * Calculate optimal route with calldata
   * Cost: $0.005
   */
  async getRoute(params: SwapParams): Promise<RouteResponse> {
    const response = await x402Fetch(`${this.baseUrl}/route`, {
      method: 'POST',
      body: JSON.stringify(params),
    });

    const data: ApiResponse<RouteResponse> = await response.json();

    if (!data.success || !data.data) {
      throw new Error(data.error || 'Failed to calculate route');
    }

    return data.data;
  }

  /**
   * Execute a swap on-chain
   * Cost: $0.02
   *
   * Uses idempotency key to prevent double charges on retries.
   * If you need to retry the same swap, pass the same idempotencyKey.
   */
  async executeSwap(params: SwapParams, idempotencyKey?: string): Promise<ExecuteResponse> {
    // Generate stable idempotency key based on swap params if not provided
    // This ensures the same swap won't be charged twice even on app restart
    const idemKey = idempotencyKey || this.generateSwapIdempotencyKey(params);

    const response = await x402Fetch(
      `${this.baseUrl}/execute`,
      {
        method: 'POST',
        body: JSON.stringify({
          ...params,
          slippageTolerance: params.slippageTolerance || 0.5,
        }),
      },
      idemKey
    );

    const data: ApiResponse<ExecuteResponse> = await response.json();

    if (!data.success || !data.data) {
      throw new Error(data.error || 'Failed to execute swap');
    }

    // Store the tx hash for status checks
    if (data.data.txHash) {
      this.lastTxHash = data.data.txHash;
    }

    return data.data;
  }

  /**
   * Generate a stable idempotency key based on swap parameters
   * This ensures the same swap won't be charged twice
   */
  private generateSwapIdempotencyKey(params: SwapParams): string {
    // Create a deterministic key from swap params + 5-minute window
    const timeWindow = Math.floor(Date.now() / (5 * 60 * 1000)); // 5-minute buckets
    const paramsHash = `${params.tokenIn}-${params.tokenOut}-${params.amountIn}-${params.recipient}`;
    return `swap-${timeWindow}-${this.simpleHash(paramsHash)}`;
  }

  /**
   * Simple hash function for idempotency key generation
   */
  private simpleHash(str: string): string {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32bit integer
    }
    return Math.abs(hash).toString(36);
  }

  /**
   * Check transaction status
   * Cost: $0.001
   */
  async getStatus(txHash?: string): Promise<StatusResponse> {
    const hash = txHash || this.lastTxHash;

    if (!hash) {
      throw new Error('No transaction hash available');
    }

    const response = await x402Fetch(`${this.baseUrl}/status/${hash}`);
    const data: ApiResponse<StatusResponse> = await response.json();

    if (!data.success || !data.data) {
      throw new Error(data.error || 'Failed to get status');
    }

    return data.data;
  }

  /**
   * Get list of supported tokens (FREE)
   */
  async getTokens(): Promise<Record<string, { address: string; symbol: string; decimals: number }>> {
    const response = await fetch(`${this.baseUrl}/tokens`);
    const data = await response.json();

    if (!data.success || !data.data) {
      throw new Error('Failed to get tokens');
    }

    return data.data;
  }

  /**
   * Health check (FREE)
   */
  async healthCheck(): Promise<{ status: string; network: string; version: string }> {
    const response = await fetch(`${this.baseUrl}/health`);
    return response.json();
  }

  /**
   * Get the last transaction hash
   */
  getLastTxHash(): string | null {
    return this.lastTxHash;
  }

  /**
   * Format a quote for speech output (humanized, concise)
   */
  formatQuoteForSpeech(quote: QuoteResponse): string {
    // Import dynamically to avoid circular deps
    const { default: SpeechService } = require('./SpeechService');

    return SpeechService.formatOptimisticQuote(
      quote.tokenIn.amount,
      quote.tokenIn.symbol,
      quote.tokenOut.amount,
      quote.tokenOut.symbol,
      quote.priceImpact
    );
  }

  /**
   * Format execution result for speech (optimistic, short)
   */
  formatExecutionForSpeech(result: ExecuteResponse, amountOut?: string, symbolOut?: string): string {
    const { default: SpeechService } = require('./SpeechService');

    if (result.status === 'submitted' && result.txHash) {
      if (amountOut && symbolOut) {
        return SpeechService.formatSwapResult(result.txHash, amountOut, symbolOut);
      }
      return SpeechService.RESPONSES.SWAP_SUBMITTED;
    }

    if (result.status === 'failed') {
      return result.error ? `Failed: ${result.error}` : SpeechService.RESPONSES.TX_FAILED;
    }

    return `Status: ${result.status}`;
  }

  /**
   * Format status for speech (concise)
   */
  formatStatusForSpeech(status: StatusResponse): string {
    const { default: SpeechService } = require('./SpeechService');

    switch (status.status) {
      case 'confirmed':
        return status.confirmations && status.confirmations > 1
          ? `Confirmed! ${status.confirmations} blocks.`
          : SpeechService.RESPONSES.TX_CONFIRMED;
      case 'pending':
        return SpeechService.RESPONSES.TX_PENDING;
      case 'failed':
        return SpeechService.RESPONSES.TX_FAILED;
      case 'not_found':
        return 'Transaction not found.';
      default:
        return `Status: ${status.status}`;
    }
  }
}

// Export singleton instance
export const swapService = new SwapService();

// Export class for testing/customization
export default SwapService;
