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
 */
router.get('/quote', validateRequest(QuoteRequestSchema), async (req: Request, res: Response) => {
  try {
    const { tokenIn, tokenOut, amountIn } = req.body;
    const uniswap = getUniswapService();

    const quote = await uniswap.getQuote(tokenIn, tokenOut, amountIn);

    res.json({
      success: true,
      data: { ...quote, routingType: 'v3' },
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
      data: { ...quote, routingType: 'v3' },
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
 */
router.post('/route', validateRequest(RouteRequestSchema), async (req: Request, res: Response) => {
  try {
    const { tokenIn, tokenOut, amountIn, recipient, slippageTolerance } = req.body;
    const uniswap = getUniswapService();

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
      data: { ...route, routingType: 'v3' },
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
 * Execute a swap on-chain (requires relayer wallet)
 */
router.post('/execute', validateRequest(ExecuteRequestSchema), async (req: Request, res: Response) => {
  try {
    const { tokenIn, tokenOut, amountIn, recipient, slippageTolerance } = req.body as any;

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
 */
router.get('/status/:txHash', async (req: Request, res: Response) => {
  try {
    const { txHash } = req.params;

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
 * Get list of supported tokens
 */
router.get('/tokens', async (_req: Request, res: Response) => {
  const network = process.env.NETWORK || 'monad';

  const tokens = {
    WMON: {
      address: '0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A',
      symbol: 'WMON',
      decimals: 18,
    },
    USDC: {
      address: '0x754704Bc059F8C67012fEd69BC8A327a5aafb603',
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
 * Health check endpoint
 */
router.get('/health', async (_req: Request, res: Response) => {
  res.json({
    status: 'ok',
    service: 'voiceswap',
    version: '3.0.0',
    network: process.env.NETWORK || 'monad',
    protocol: 'Uniswap V3 on Monad',
    timestamp: new Date().toISOString(),
  });
});

export default router;
