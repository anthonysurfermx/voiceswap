import { z } from 'zod';

// Request schemas
export const QuoteRequestSchema = z.object({
  tokenIn: z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'Invalid token address'),
  tokenOut: z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'Invalid token address'),
  amountIn: z.string().regex(/^\d+(\.\d+)?$/, 'Invalid amount format'),
  slippageTolerance: z.number().min(0).max(50).optional().default(0.5), // percentage
});

export const RouteRequestSchema = QuoteRequestSchema.extend({
  recipient: z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'Invalid recipient address').optional(),
});

export const ExecuteRequestSchema = RouteRequestSchema.extend({
  recipient: z.string().regex(/^0x[a-fA-F0-9]{40}$/, 'Invalid recipient address'),
  deadline: z.number().optional(), // Unix timestamp
});

export const StatusRequestSchema = z.object({
  txHash: z.string().regex(/^0x[a-fA-F0-9]{64}$/, 'Invalid transaction hash'),
});

// Response types
export interface QuoteResponse {
  tokenIn: {
    address: string;
    symbol: string;
    decimals: number;
    amount: string;
    amountRaw: string;
  };
  tokenOut: {
    address: string;
    symbol: string;
    decimals: number;
    amount: string;
    amountRaw: string;
  };
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
  blockNumber?: number;
  gasUsed?: string;
  effectiveGasPrice?: string;
  error?: string;
}

export interface StatusResponse {
  status: 'pending' | 'confirmed' | 'failed' | 'not_found';
  txHash: string;
  blockNumber?: number;
  confirmations?: number;
  gasUsed?: string;
  effectiveGasPrice?: string;
  tokenIn?: {
    address: string;
    amount: string;
  };
  tokenOut?: {
    address: string;
    amount: string;
  };
}

export interface ErrorResponse {
  error: string;
  code: string;
  details?: unknown;
}

// Inferred types from schemas
export type QuoteRequest = z.infer<typeof QuoteRequestSchema>;
export type RouteRequest = z.infer<typeof RouteRequestSchema>;
export type ExecuteRequest = z.infer<typeof ExecuteRequestSchema>;
export type StatusRequest = z.infer<typeof StatusRequestSchema>;
