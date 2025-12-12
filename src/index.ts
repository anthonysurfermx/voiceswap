import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import swapRoutes from './routes/swap.js';
import eventsRoutes from './routes/events.js';
import { initDatabase, closeDatabase } from './services/database.js';

const app = express();
const PORT = process.env.PORT || 4021;

// Security middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// Get payment receiver address from env
const PAYMENT_RECEIVER = process.env.PAYMENT_RECEIVER_ADDRESS ?? '';
if (!PAYMENT_RECEIVER) {
  console.error('❌ PAYMENT_RECEIVER_ADDRESS not set in environment variables');
  console.error('   Please set your Ethereum address to receive x402 payments');
  process.exit(1);
}

// Swap execution network (Unichain)
const SWAP_NETWORK = (process.env.NETWORK || 'unichain-sepolia') as 'unichain' | 'unichain-sepolia';

// x402 payment network (Arbitrum - x402 payments via Thirdweb)
const PAYMENT_NETWORK: 'arbitrum' | 'arbitrum-sepolia' = SWAP_NETWORK === 'unichain' ? 'arbitrum' : 'arbitrum-sepolia';

// Mount swap routes (x402 middleware is applied per-route in swap.ts)
app.use('/', swapRoutes);

// Mount SSE events routes for real-time transaction monitoring
app.use('/events', eventsRoutes);

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

// Initialize database and start server
async function startServer() {
  try {
    // Initialize SQLite database
    await initDatabase();
    console.log('[Database] SQLite initialized successfully');

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
║   ├─ GET  /events   (FREE)   - SSE transaction monitoring    ║
║   └─ GET  /health   (FREE)   - Health check                  ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
      `);
    });

    // Graceful shutdown
    process.on('SIGINT', async () => {
      console.log('\n[Server] Shutting down gracefully...');
      await closeDatabase();
      process.exit(0);
    });

    process.on('SIGTERM', async () => {
      console.log('\n[Server] Received SIGTERM, shutting down...');
      await closeDatabase();
      process.exit(0);
    });

  } catch (error) {
    console.error('[Server] Failed to start:', error);
    process.exit(1);
  }
}

startServer();

export default app;
