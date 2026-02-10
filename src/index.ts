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
  const appUrl = `voiceswap://${req.path.replace('/app/', '')}`;
  res.redirect(appUrl);
});

// Payment deep link (for QR codes)
app.get('/pay/:wallet', (req, res) => {
  const { wallet } = req.params;
  const amount = req.query.amount as string;
  const name = req.query.name as string;

  const appUrl = `voiceswap://pay?wallet=${wallet}${amount ? `&amount=${amount}` : ''}${name ? `&name=${name}` : ''}`;

  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>VoiceSwap Payment</title>
      <meta http-equiv="refresh" content="0;url=${appUrl}">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; padding: 50px; background: #1a1a1a; color: white; }
        .container { max-width: 400px; margin: 0 auto; }
        h1 { font-size: 24px; color: #836EF9; }
        p { color: #999; }
        a { color: #836EF9; }
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

// Network configuration (Monad mainnet)
const NETWORK = 'monad';
const CHAIN_ID = 143;

// Mount routes
app.use('/', swapRoutes);
app.use('/events', eventsRoutes);
app.use('/voiceswap', voiceswapRoutes);

// Root endpoint - service info
app.get('/', (_req, res) => {
  res.json({
    service: 'VoiceSwap',
    description: 'Voice-activated crypto payments with Uniswap V3 on Monad',
    version: '3.0.0',
    network: NETWORK,
    chainId: CHAIN_ID,
    endpoints: {
      '/quote': { method: 'GET | POST', description: 'Get a swap quote' },
      '/route': { method: 'POST', description: 'Calculate optimal route with calldata' },
      '/execute': { method: 'POST', description: 'Execute swap on-chain' },
      '/status/:txHash': { method: 'GET', description: 'Check transaction status' },
      '/tokens': { method: 'GET', description: 'List supported tokens' },
      '/health': { method: 'GET', description: 'Health check' },
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
    await initDatabase();
    console.log('[Database] SQLite initialized successfully');

    app.listen(PORT, () => {
      console.log(`
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║   🔄 VoiceSwap v3.0 (Uniswap V3 on Monad)                    ║
║   Voice-activated crypto payments                            ║
║                                                               ║
╠═══════════════════════════════════════════════════════════════╣
║                                                               ║
║   Server running at: http://localhost:${PORT}                   ║
║   Network: ${NETWORK.padEnd(23)}                             ║
║   Chain ID: ${String(CHAIN_ID).padEnd(22)}                             ║
║                                                               ║
╠═══════════════════════════════════════════════════════════════╣
║   Endpoints:                                                  ║
║   ├─ GET  /quote              - Get swap quote                ║
║   ├─ POST /route              - Calculate optimal route       ║
║   ├─ POST /execute            - Execute swap on-chain         ║
║   ├─ GET  /status             - Check transaction status      ║
║   ├─ GET  /tokens             - List supported tokens         ║
║   ├─ GET  /events             - SSE transaction monitoring    ║
║   └─ GET  /health             - Health check                  ║
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
