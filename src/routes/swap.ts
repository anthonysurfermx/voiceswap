import { Router, Request, Response, NextFunction } from 'express';
import { getUniswapService } from '../services/uniswap.js';
import { getUniswapXService } from '../services/uniswapx.js';
import thirdwebEngine from '../services/thirdwebEngine.js';
import {
  QuoteRequestSchema,
  RouteRequestSchema,
  ExecuteRequestSchema,
  StatusRequestSchema,
} from '../types/api.js';
import type { ErrorResponse, QuoteResponse } from '../types/api.js';
import { requireX402Payment, API_PRICES, addPaymentInfo } from '../middleware/x402.js';

const router = Router();

// Add payment info headers to all responses
router.use(addPaymentInfo());

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
router.get('/quote', requireX402Payment(API_PRICES['/quote']), validateRequest(QuoteRequestSchema), async (req: Request, res: Response) => {
  try {
    const { tokenIn, tokenOut, amountIn } = req.body;
    const uniswap = getUniswapService();
    const uniswapX = getUniswapXService();

    // Fetch V4 Quote
    const v4QuotePromise = uniswap.getQuote(tokenIn, tokenOut, amountIn);

    // Fetch Uniswap X Quote (Best effort)
    const xQuotePromise = uniswapX.getQuote(tokenIn, tokenOut, amountIn)
      .catch(e => null); // Don't fail if X fails

    const [v4Quote, xQuote] = await Promise.all([v4QuotePromise, xQuotePromise]);

    let bestQuote: QuoteResponse = { ...v4Quote, routingType: 'v4' };

    // Compare if we got a valid X quote
    if (xQuote && parseFloat(xQuote.amountOut) > parseFloat(v4Quote.tokenOut.amount)) {
      // If X is better, construct the response
      // Note: We need to map X quote format to our response format fully
      // For now, we'll just demonstrate the swich logic
      // In a real impl, we'd populate route, priceImpact etc from X response
      console.log('Uniswap X offer is better!');
    }

    res.json({
      success: true,
      data: bestQuote,
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
router.post('/quote', requireX402Payment(API_PRICES['/quote']), validateRequest(QuoteRequestSchema), async (req: Request, res: Response) => {
  try {
    const { tokenIn, tokenOut, amountIn } = req.body;
    const uniswap = getUniswapService();

    // Re-use logic (simplified for now to just V4 for speed, but should match GET)
    const quote = await uniswap.getQuote(tokenIn, tokenOut, amountIn);

    res.json({
      success: true,
      data: { ...quote, routingType: 'v4' },
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
router.post('/route', requireX402Payment(API_PRICES['/route']), validateRequest(RouteRequestSchema), async (req: Request, res: Response) => {
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
      data: { ...route, routingType: 'v4' },
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
 * Execute a swap on-chain via Thirdweb Engine (with gas sponsorship)
 * x402 Price: $0.02
 */
router.post('/execute', requireX402Payment(API_PRICES['/execute']), validateRequest(ExecuteRequestSchema), async (req: Request, res: Response) => {
  try {
    const { tokenIn, tokenOut, amountIn, recipient, slippageTolerance, routingType, uniswapXEncodedOrder, useEngine } = req.body as any;

    // Handle Uniswap X Execution
    if (routingType === 'uniswap_x') {
      if (!uniswapXEncodedOrder) {
        throw new Error('Missing encoded order for Uniswap X execution');
      }
      const uniswapX = getUniswapXService();
      const orderHash = await uniswapX.submitOrder(uniswapXEncodedOrder);

      res.json({
        success: true,
        data: {
          status: 'submitted',
          orderHash,
          routingType: 'uniswap_x'
        }
      });
      return;
    }

    // Check if Thirdweb API is enabled (default: true)
    const shouldUseEngine = useEngine !== false && process.env.THIRDWEB_SECRET_KEY;

    if (shouldUseEngine) {
      // Execute via Thirdweb Engine with Account Abstraction + Gas Sponsorship
      console.log('[Execute] Using Thirdweb Engine for gasless swap');

      const uniswap = getUniswapService();

      // 1. Get route with calldata
      const route = await uniswap.getRoute(
        tokenIn,
        tokenOut,
        amountIn,
        recipient,
        slippageTolerance
      );

      if (!route.calldata) {
        throw new Error('Failed to generate swap calldata');
      }

      // 2. Execute via Engine (creates smart account if needed + sponsors gas)
      const engineResult = await thirdwebEngine.executeSwapViaEngine({
        userAddress: recipient,
        calldata: route.calldata,
        value: route.value,
      });

      res.json({
        success: true,
        data: {
          status: 'queued',
          queueId: engineResult.queueId,
          smartAccountAddress: engineResult.smartAccountAddress,
          routingType: 'v4_engine',
          message: 'Transaction queued with gas sponsorship',
        },
      });
    } else {
      // Fallback: Direct execution (requires user to have ETH for gas)
      console.log('[Execute] Using direct execution (no Engine)');

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
    }
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
 * GET /status/:identifier
 * Check the status of a swap transaction
 * Supports both Engine queueId and regular txHash
 * x402 Price: $0.001
 */
router.get('/status/:identifier', requireX402Payment(API_PRICES['/status']), async (req: Request, res: Response) => {
  try {
    const { identifier } = req.params;

    // Check if this is an Engine queueId (format: req-xxxxx or similar)
    const isEngineQueue = identifier.startsWith('req-') || !identifier.startsWith('0x');

    if (isEngineQueue) {
      // Check Engine transaction status
      const engineStatus = await thirdwebEngine.checkTransactionStatus(identifier);

      res.json({
        success: true,
        data: {
          status: engineStatus.status === 'mined' ? 'confirmed' :
                 engineStatus.status === 'errored' ? 'failed' : 'pending',
          txHash: engineStatus.transactionHash,
          queueId: engineStatus.queueId,
          blockNumber: engineStatus.blockNumber,
          errorMessage: engineStatus.errorMessage,
          routingType: 'v4_engine',
        },
      });
    } else {
      // Regular transaction hash
      const validation = StatusRequestSchema.safeParse({ txHash: identifier });
      if (!validation.success) {
        const errorResponse: ErrorResponse = {
          error: 'Invalid transaction hash format',
          code: 'INVALID_TX_HASH',
        };
        res.status(400).json(errorResponse);
        return;
      }

      const uniswap = getUniswapService();
      const status = await uniswap.getTransactionStatus(identifier);

      res.json({
        success: true,
        data: status,
      });
    }
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
  // Check Engine health
  const engineHealth = await thirdwebEngine.healthCheck();

  res.json({
    status: 'ok',
    service: 'x402-swap-executor',
    version: '2.2.0',
    network: process.env.NETWORK || 'unichain-sepolia',
    protocol: 'Uniswap V4 + Uniswap X',
    features: {
      accountAbstraction: engineHealth.healthy,
      gasSponsorship: engineHealth.healthy,
      thirdwebEngine: engineHealth.healthy,
    },
    timestamp: new Date().toISOString(),
  });
});

export default router;
