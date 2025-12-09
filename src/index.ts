import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import { paymentMiddleware } from 'x402-express';
import swapRoutes from './routes/swap.js';

const app = express();
const PORT = process.env.PORT || 4021;

// Security middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// Get payment receiver address from env
const PAYMENT_RECEIVER = process.env.PAYMENT_RECEIVER_ADDRESS;
if (!PAYMENT_RECEIVER) {
  console.error('❌ PAYMENT_RECEIVER_ADDRESS not set in environment variables');
  console.error('   Please set your Ethereum address to receive x402 payments');
  process.exit(1);
}

// Swap execution network (Unichain)
const SWAP_NETWORK = (process.env.NETWORK || 'unichain-sepolia') as 'unichain' | 'unichain-sepolia';

// x402 payment network (Base - x402 payments happen on Base, swaps happen on Unichain)
const PAYMENT_NETWORK: 'base' | 'base-sepolia' = SWAP_NETWORK === 'unichain' ? 'base' : 'base-sepolia';

// x402 route pricing configuration
const x402Routes = {
  'GET /quote': {
    price: '$0.001',
    network: PAYMENT_NETWORK,
    config: {
      description: 'Get a swap quote for any token pair on Uniswap V4',
    },
  },
  'POST /quote': {
    price: '$0.001',
    network: PAYMENT_NETWORK,
    config: {
      description: 'Get a swap quote for any token pair on Uniswap V4 (POST)',
    },
  },
  'POST /route': {
    price: '$0.005',
    network: PAYMENT_NETWORK,
    config: {
      description: 'Calculate optimal swap route with calldata for execution',
    },
  },
  'POST /execute': {
    price: '$0.02',
    network: PAYMENT_NETWORK,
    config: {
      description: 'Execute a swap on-chain via the relayer',
    },
  },
  'GET /status/:txHash': {
    price: '$0.001',
    network: PAYMENT_NETWORK,
    config: {
      description: 'Check the status of a swap transaction',
    },
  },
};

// Facilitator configuration
// For testnet, use the public facilitator URL
// For mainnet, import and use the facilitator from @coinbase/x402
const facilitator = PAYMENT_NETWORK === 'base-sepolia'
  ? { url: 'https://x402.org/facilitator' as const }
  : undefined; // Will use CDP facilitator with API keys for mainnet

// Apply x402 payment middleware to protected routes
app.use(paymentMiddleware(
  PAYMENT_RECEIVER as `0x${string}`,
  x402Routes,
  facilitator
));

// Mount swap routes
app.use('/', swapRoutes);

// Root endpoint - service info
app.get('/', (_req, res) => {
  res.json({
    service: 'x402 Swap Executor',
    description: 'Swap-as-a-Service: x402-powered Uniswap V4 swap execution for AI agents on Unichain',
    version: '2.0.0',
    swapNetwork: SWAP_NETWORK,
    paymentNetwork: PAYMENT_NETWORK,
    endpoints: {
      '/quote': {
        method: 'GET | POST',
        price: '$0.001',
        description: 'Get a swap quote',
      },
      '/route': {
        method: 'POST',
        price: '$0.005',
        description: 'Calculate optimal route with calldata',
      },
      '/execute': {
        method: 'POST',
        price: '$0.02',
        description: 'Execute swap on-chain',
      },
      '/status/:txHash': {
        method: 'GET',
        price: '$0.001',
        description: 'Check transaction status',
      },
      '/tokens': {
        method: 'GET',
        price: 'FREE',
        description: 'List supported tokens',
      },
      '/health': {
        method: 'GET',
        price: 'FREE',
        description: 'Health check',
      },
    },
    documentation: 'https://github.com/your-repo/x402-swap-executor',
    x402: {
      protocol: 'https://x402.org',
      paymentToken: 'USDC',
      paymentNetwork: PAYMENT_NETWORK,
    },
  });
});

// Error handling middleware
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('Server error:', err);
  res.status(500).json({
    error: 'Internal server error',
    code: 'INTERNAL_ERROR',
  });
});

// Start server
app.listen(PORT, () => {
  console.log(`
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   🔄 x402 Swap Executor v2.0 (Uniswap V4 on Unichain)        ║
║   Swap-as-a-Service for AI Agents                            ║
║                                                               ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║   Server running at: http://localhost:${PORT}                   ║
║   Swap Network: ${SWAP_NETWORK.padEnd(17)}                             ║
║   Payment Network: ${PAYMENT_NETWORK.padEnd(15)}                             ║
║   Payment receiver: ${PAYMENT_RECEIVER.slice(0, 10)}...${PAYMENT_RECEIVER.slice(-8)}            ║
║                                                               ║
╠═══════════════════════════════════════════════════════════════╣
║   Endpoints:                                                  ║
║   ├─ GET  /quote    ($0.001) - Get swap quote                ║
║   ├─ POST /route    ($0.005) - Calculate optimal route       ║
║   ├─ POST /execute  ($0.02)  - Execute swap on-chain         ║
║   ├─ GET  /status   ($0.001) - Check transaction status      ║
║   ├─ GET  /tokens   (FREE)   - List supported tokens         ║
║   └─ GET  /health   (FREE)   - Health check                  ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
  `);
});

export default app;
