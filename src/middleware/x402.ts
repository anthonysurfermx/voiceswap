/**
 * x402 Payment Middleware using Thirdweb
 *
 * Handles micropayments for API endpoints using x402 protocol
 * Integrated with Thirdweb for payment facilitation
 */

import { Request, Response, NextFunction } from 'express';
import { createThirdwebClient } from 'thirdweb';
import { facilitator, settlePayment } from 'thirdweb/x402';
import { arbitrumSepolia, arbitrum } from 'thirdweb/chains';

// Thirdweb client configuration
const client = createThirdwebClient({
  secretKey: process.env.THIRDWEB_SECRET_KEY!,
});

// x402 facilitator configuration
const thirdwebX402Facilitator = facilitator({
  client,
  serverWalletAddress: process.env.PAYMENT_RECEIVER_ADDRESS || process.env.BACKEND_WALLET_ADDRESS!,
});

// Use Arbitrum Sepolia for testnet, Arbitrum for mainnet
const isProduction = process.env.NODE_ENV === 'production';
const paymentNetwork = isProduction ? arbitrum : arbitrumSepolia;

/**
 * Price map for different API endpoints
 */
export const API_PRICES = {
  '/quote': '$0.001',      // Get quote
  '/route': '$0.005',      // Get route with calldata
  '/execute': '$0.02',     // Execute swap
  '/status': '$0.001',     // Check status
} as const;

/**
 * x402 payment middleware factory
 * Creates middleware that requires payment for API access
 */
export function requireX402Payment(price: string) {
  return async (req: Request, res: Response, next: NextFunction) => {
    try {
      // Get payment data from request header
      const paymentData = req.headers['x-payment'] as string | undefined;

      // Construct the full resource URL
      const protocol = req.protocol;
      const host = req.get('host');
      const path = req.originalUrl;
      const resourceUrl = `${protocol}://${host}${path}`;

      console.log(`[x402] Processing payment for ${resourceUrl} (${price})`);

      // In development mode with strict mode disabled, allow access
      if (process.env.X402_STRICT_MODE !== 'true') {
        console.log(`[x402] Development mode - allowing access without payment`);
        next();
        return;
      }

      // Settle the payment using Thirdweb
      const result = await settlePayment({
        resourceUrl,
        method: req.method as 'GET' | 'POST',
        paymentData,
        network: paymentNetwork,
        price,
        facilitator: thirdwebX402Facilitator,
      });

      // Check payment result
      if (result.status === 200) {
        console.log(`[x402] Payment successful for ${resourceUrl}`);
        // Payment successful, continue to next middleware/handler
        next();
      } else {
        // Payment failed or required
        console.log(`[x402] Payment required for ${resourceUrl}:`, result.status);

        res
          .status(result.status)
          .set(result.responseHeaders)
          .json(result.responseBody);
      }
    } catch (error) {
      console.error('[x402] Payment processing error:', error);

      // If x402 fails, we can choose to either:
      // 1. Block access (strict mode)
      // 2. Allow access (fallback mode) - useful during development

      if (process.env.X402_STRICT_MODE === 'true') {
        res.status(500).json({
          error: 'Payment processing failed',
          code: 'X402_ERROR',
          details: error instanceof Error ? error.message : 'Unknown error',
        });
      } else {
        console.warn('[x402] Allowing access despite payment error (strict mode disabled)');
        next();
      }
    }
  };
}

/**
 * Optional: Gas Tank support
 * Allows users to pre-fund a gas tank for multiple API calls
 */
export function checkGasTank() {
  return async (req: Request, res: Response, next: NextFunction) => {
    try {
      const gasTankId = req.headers['x-gas-tank'] as string | undefined;

      if (gasTankId) {
        // TODO: Implement gas tank balance checking
        // For now, just log and continue
        console.log(`[x402] Gas tank detected: ${gasTankId}`);
      }

      next();
    } catch (error) {
      console.error('[x402] Gas tank check error:', error);
      next();
    }
  };
}

/**
 * Helper to create x402 payment info header
 * Used in API responses to inform clients about payment requirements
 */
export function createPaymentInfoHeader(price: string, endpoint: string): Record<string, string> {
  return {
    'X-Payment-Required': 'true',
    'X-Payment-Price': price,
    'X-Payment-Network': paymentNetwork.name ?? 'arbitrum-sepolia',
    'X-Payment-Receiver': process.env.PAYMENT_RECEIVER_ADDRESS || process.env.BACKEND_WALLET_ADDRESS || '',
    'X-Payment-Endpoint': endpoint,
  };
}

/**
 * Middleware to add payment info headers to free endpoints
 * Helps clients discover which endpoints require payment
 */
export function addPaymentInfo() {
  return (req: Request, res: Response, next: NextFunction) => {
    // Add CORS headers for x402
    res.set({
      'Access-Control-Expose-Headers': 'X-Payment-Required, X-Payment-Price, X-Payment-Network, X-Payment-Receiver',
    });

    next();
  };
}

export default {
  requireX402Payment,
  checkGasTank,
  addPaymentInfo,
  createPaymentInfoHeader,
  API_PRICES,
};
