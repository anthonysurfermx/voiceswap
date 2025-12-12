import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import path from 'path';
import { fileURLToPath } from 'url';
import swapRoutes from './routes/swap.js';
import eventsRoutes from './routes/events.js';
import voiceswapRoutes from './routes/voiceswap.js';
import { initDatabase, closeDatabase } from './services/database.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = process.env.PORT || 4021;

// Security middleware
app.use(helmet());
app.use(cors());
app.use(express.json());

// Serve Apple App Site Association for Universal Links (Meta Ray-Ban integration)
app.get('/.well-known/apple-app-site-association', (_req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.sendFile(path.join(__dirname, '../public/.well-known/apple-app-site-association'));
});

// Deep link handler for VoiceSwap app
app.get('/app/*', (req, res) => {
  // Redirect to app or show web fallback
  const appUrl = `voiceswap://${req.path.replace('/app/', '')}`;
  res.redirect(appUrl);
});

// Payment deep link (for QR codes)
app.get('/pay/:wallet', (req, res) => {
  const { wallet } = req.params;
  const amount = req.query.amount as string;
  const name = req.query.name as string;

  // Try to open app, fallback to web
  const appUrl = `voiceswap://pay?wallet=${wallet}${amount ? `&amount=${amount}` : ''}${name ? `&name=${name}` : ''}`;

  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>VoiceSwap Payment</title>
      <meta http-equiv="refresh" content="0;url=${appUrl}">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; padding: 50px; background: #1a1a2e; color: white; }
        .container { max-width: 400px; margin: 0 auto; }
        h1 { font-size: 24px; }
        p { color: #888; }
        a { color: #4a9eff; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>VoiceSwap Payment</h1>
        <p>Opening VoiceSwap app...</p>
        <p>If the app doesn't open, <a href="https://apps.apple.com/app/voiceswap">download it here</a>.</p>
        <p style="margin-top: 30px; font-size: 14px;">
          Payment to: ${wallet.slice(0, 10)}...${wallet.slice(-8)}<br>
          ${amount ? `Amount: $${amount} USDC` : ''}
        </p>
      </div>
    </body>
    </html>
  `);
});

// Get payment receiver address from env
const PAYMENT_RECEIVER = process.env.PAYMENT_RECEIVER_ADDRESS ?? '';
if (!PAYMENT_RECEIVER) {
  console.error('❌ PAYMENT_RECEIVER_ADDRESS not set in environment variables');
  console.error('   Please set your Ethereum address to receive x402 payments');
  process.exit(1);
}

// Network configuration (Unichain for both swaps and x402 payments)
const NETWORK = (process.env.NETWORK || 'unichain-sepolia') as 'unichain' | 'unichain-sepolia';
const CHAIN_ID = NETWORK === 'unichain' ? 130 : 1301;

// Mount swap routes (x402 middleware is applied per-route in swap.ts)
app.use('/', swapRoutes);

// Mount SSE events routes for real-time transaction monitoring
app.use('/events', eventsRoutes);

// Mount VoiceSwap routes for voice-activated payments
app.use('/voiceswap', voiceswapRoutes);

// Root endpoint - service info
app.get('/', (_req, res) => {
  res.json({
    service: 'x402 Swap Executor',
    description: 'Swap-as-a-Service: x402-powered Uniswap V4 swap execution for AI agents on Unichain',
    version: '2.0.0',
    network: NETWORK,
    chainId: CHAIN_ID,
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
      paymentNetwork: NETWORK,
      chainId: CHAIN_ID,
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
║   Network: ${NETWORK.padEnd(23)}                             ║
║   Chain ID: ${String(CHAIN_ID).padEnd(22)}                             ║
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

