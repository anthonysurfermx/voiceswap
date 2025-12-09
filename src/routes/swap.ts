import { Router, Request, Response, NextFunction } from 'express';
import { getUniswapService } from '../services/uniswap.js';
import {
  QuoteRequestSchema,
  RouteRequestSchema,
  ExecuteRequestSchema,
  StatusRequestSchema,
} from '../types/api.js';
import type { ErrorResponse } from '../types/api.js';

const router = Router();

// Middleware for request validation
const validateRequest = (schema: typeof QuoteRequestSchema | typeof RouteRequestSchema | typeof ExecuteRequestSchema) => {
  return (req: Request, res: Response, next: NextFunction) => {
    try {
      const data = { ...req.query, ...req.body };
      schema.parse(data);
      req.body = data;
      next();
    } catch (error) {
      const errorResponse: ErrorResponse = {
        error: 'Validation failed',
        code: 'INVALID_REQUEST',
        details: error,
      };
      res.status(400).json(errorResponse);
    }
  };
};

/**
 * GET /quote
 * Get a quote for a token swap
 * x402 Price: $0.001
 */
router.get('/quote', validateRequest(QuoteRequestSchema), async (req: Request, res: Response) => {
  try {
    const { tokenIn, tokenOut, amountIn } = req.body;
    const uniswap = getUniswapService();
    
    const quote = await uniswap.getQuote(tokenIn, tokenOut, amountIn);
    
    res.json({
      success: true,
      data: quote,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to get quote';
    const errorResponse: ErrorResponse = {
      error: message,
      code: 'QUOTE_FAILED',
    };
    res.status(500).json(errorResponse);
  }
});

/**
 * POST /quote
 * Alternative POST endpoint for quote
 */
router.post('/quote', validateRequest(QuoteRequestSchema), async (req: Request, res: Response) => {
  try {
    const { tokenIn, tokenOut, amountIn } = req.body;
    const uniswap = getUniswapService();
    
    const quote = await uniswap.getQuote(tokenIn, tokenOut, amountIn);
    
    res.json({
      success: true,
      data: quote,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to get quote';
    const errorResponse: ErrorResponse = {
      error: message,
      code: 'QUOTE_FAILED',
    };
    res.status(500).json(errorResponse);
  }
});

/**
 * POST /route
 * Get optimal route with calldata for swap execution
 * x402 Price: $0.005
 */
router.post('/route', validateRequest(RouteRequestSchema), async (req: Request, res: Response) => {
  try {
    const { tokenIn, tokenOut, amountIn, recipient, slippageTolerance } = req.body;
    const uniswap = getUniswapService();
    
    // Use a placeholder recipient if not provided (for quote purposes)
    const routeRecipient = recipient || '0x0000000000000000000000000000000000000000';
    
    const route = await uniswap.getRoute(
      tokenIn,
      tokenOut,
      amountIn,
      routeRecipient,
      slippageTolerance
    );
    
    res.json({
      success: true,
      data: route,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to calculate route';
    const errorResponse: ErrorResponse = {
      error: message,
      code: 'ROUTE_FAILED',
    };
    res.status(500).json(errorResponse);
  }
});

/**
 * POST /execute
 * Execute a swap on-chain
 * x402 Price: $0.02
 * 
 * NOTE: This endpoint requires the relayer wallet to have:
 * 1. Sufficient ETH for gas
 * 2. Approval to spend the input token
 * 
 * In production, you'd implement a more sophisticated system
 * where users sign transactions or use account abstraction.
 */
router.post('/execute', validateRequest(ExecuteRequestSchema), async (req: Request, res: Response) => {
  try {
    const { tokenIn, tokenOut, amountIn, recipient, slippageTolerance } = req.body;
    const uniswap = getUniswapService();
    
    const result = await uniswap.executeSwap(
      tokenIn,
      tokenOut,
      amountIn,
      recipient,
      slippageTolerance
    );
    
    if (result.status === 'failed') {
      const errorResponse: ErrorResponse = {
        error: result.error || 'Swap execution failed',
        code: 'EXECUTION_FAILED',
      };
      res.status(500).json(errorResponse);
      return;
    }
    
    res.json({
      success: true,
      data: result,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to execute swap';
    const errorResponse: ErrorResponse = {
      error: message,
      code: 'EXECUTION_FAILED',
    };
    res.status(500).json(errorResponse);
  }
});

/**
 * GET /status/:txHash
 * Check the status of a swap transaction
 * x402 Price: $0.001
 */
router.get('/status/:txHash', async (req: Request, res: Response) => {
  try {
    const { txHash } = req.params;
    
    // Validate txHash format
    const validation = StatusRequestSchema.safeParse({ txHash });
    if (!validation.success) {
      const errorResponse: ErrorResponse = {
        error: 'Invalid transaction hash format',
        code: 'INVALID_TX_HASH',
      };
      res.status(400).json(errorResponse);
      return;
    }
    
    const uniswap = getUniswapService();
    const status = await uniswap.getTransactionStatus(txHash);
    
    res.json({
      success: true,
      data: status,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Failed to get transaction status';
    const errorResponse: ErrorResponse = {
      error: message,
      code: 'STATUS_FAILED',
    };
    res.status(500).json(errorResponse);
  }
});

/**
 * GET /tokens
 * Get list of supported tokens (free endpoint, no x402 payment required)
 */
router.get('/tokens', async (_req: Request, res: Response) => {
  const network = process.env.NETWORK || 'unichain-sepolia';

  const tokens = network === 'unichain' ? {
    WETH: {
      address: '0x4200000000000000000000000000000000000006',
      symbol: 'WETH',
      decimals: 18,
    },
    USDC: {
      address: '0x078D782b760474a361dDA0AF3839290b0EF57AD6',
      symbol: 'USDC',
      decimals: 6,
    },
  } : {
    // Unichain Sepolia testnet tokens
    WETH: {
      address: '0x4200000000000000000000000000000000000006',
      symbol: 'WETH',
      decimals: 18,
    },
    USDC: {
      address: '0x31d0220469e10c4E71834a79b1f276d740d3768F',
      symbol: 'USDC',
      decimals: 6,
    },
  };

  res.json({
    success: true,
    network,
    data: tokens,
  });
});

/**
 * GET /health
 * Health check endpoint (free, no x402)
 */
router.get('/health', async (_req: Request, res: Response) => {
  res.json({
    status: 'ok',
    service: 'x402-swap-executor',
    version: '2.0.0',
    network: process.env.NETWORK || 'unichain-sepolia',
    protocol: 'Uniswap V4',
    timestamp: new Date().toISOString(),
  });
});

export default router;
