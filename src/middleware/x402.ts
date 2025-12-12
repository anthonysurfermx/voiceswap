/**
 * x402 Payment Middleware using Thirdweb
 *
 * Handles micropayments for API endpoints using x402 protocol
 * Payments in USDC on Unichain (mainnet: 130, sepolia: 1301)
 */

import { Request, Response, NextFunction } from 'express';
import { createThirdwebClient } from 'thirdweb';
import { facilitator, settlePayment } from 'thirdweb/x402';
import { defineChain } from 'thirdweb/chains';

// Thirdweb client configuration
const client = createThirdwebClient({
  secretKey: process.env.THIRDWEB_SECRET_KEY!,
});

// Network configuration - Unichain
const isProduction = process.env.NETWORK === 'unichain';
const UNICHAIN_MAINNET_ID = 130;
const UNICHAIN_SEPOLIA_ID = 1301;

// USDC addresses on Unichain
const USDC_UNICHAIN_MAINNET = '0x078D782b760474a361dDA0AF3839290b0EF57AD6';
const USDC_UNICHAIN_SEPOLIA = '0x31d0220469e10c4E71834a79b1f276d740d3768F'; // Testnet USDC

// Payment network configuration
const paymentChainId = isProduction ? UNICHAIN_MAINNET_ID : UNICHAIN_SEPOLIA_ID;
const paymentNetwork = defineChain(paymentChainId);
const usdcAddress = isProduction ? USDC_UNICHAIN_MAINNET : USDC_UNICHAIN_SEPOLIA;

// Server wallet address for receiving payments
const serverWalletAddress = process.env.PAYMENT_RECEIVER_ADDRESS || process.env.BACKEND_WALLET_ADDRESS!;

// x402 facilitator configuration
const thirdwebX402Facilitator = facilitator({
  client,
  serverWalletAddress,
  waitUntil: 'simulated', // Use simulated for faster testing
});

/**
 * Price map for different API endpoints (in USDC micro-units)
 * 1 USDC = 1,000,000 micro-units (6 decimals)
 */
export const API_PRICES = {
  '/quote': { display: '$0.001', amount: '1000' },      // 0.001 USDC
  '/route': { display: '$0.005', amount: '5000' },      // 0.005 USDC
  '/execute': { display: '$0.02', amount: '20000' },    // 0.02 USDC
  '/status': { display: '$0.001', amount: '1000' },     // 0.001 USDC
} as const;

/**
 * Convert price string to USDC micro-units
 */
function priceToAmount(price: string): string {
  // Check if it's a known endpoint price
  const endpoint = Object.entries(API_PRICES).find(([_, p]) => p.display === price);
  if (endpoint) {
    return endpoint[1].amount;
  }

  // Parse price string like "$0.02" to micro-units
  const match = price.match(/\$?([\d.]+)/);
  if (match) {
    const usdValue = parseFloat(match[1]);
    return Math.round(usdValue * 1_000_000).toString();
  }

  return '1000'; // Default: 0.001 USDC
}

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
      console.log(`[x402] Network: Unichain ${isProduction ? 'Mainnet' : 'Sepolia'} (${paymentChainId})`);
      console.log(`[x402] USDC: ${usdcAddress}`);

      // In development mode with strict mode disabled, allow access
      if (process.env.X402_STRICT_MODE !== 'true') {
        console.log(`[x402] Development mode - allowing access without payment`);
        next();
        return;
      }

      // Convert price to USDC micro-units
      const amountInMicroUnits = priceToAmount(price);

      // Settle the payment using Thirdweb x402 on Unichain
      const result = await settlePayment({
        resourceUrl,
        method: req.method as 'GET' | 'POST',
        paymentData,
        payTo: serverWalletAddress,
        network: paymentNetwork,
        price: {
          amount: amountInMicroUnits,
          asset: {
            address: usdcAddress,
          },
        },
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
    'X-Payment-Network': `unichain-${isProduction ? 'mainnet' : 'sepolia'}`,
    'X-Payment-Chain-Id': paymentChainId.toString(),
    'X-Payment-Asset': 'USDC',
    'X-Payment-Asset-Address': usdcAddress,
    'X-Payment-Receiver': serverWalletAddress,
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
      'Access-Control-Expose-Headers': 'X-Payment-Required, X-Payment-Price, X-Payment-Network, X-Payment-Chain-Id, X-Payment-Asset, X-Payment-Asset-Address, X-Payment-Receiver',
    });

    next();
  };
}

/**
 * Get x402 configuration info
 */
export function getX402Config() {
  return {
    network: isProduction ? 'unichain' : 'unichain-sepolia',
    chainId: paymentChainId,
    asset: 'USDC',
    assetAddress: usdcAddress,
    receiver: serverWalletAddress,
    prices: API_PRICES,
  };
}

export default {
  requireX402Payment,
  checkGasTank,
  addPaymentInfo,
  createPaymentInfoHeader,
  getX402Config,
  API_PRICES,
};
