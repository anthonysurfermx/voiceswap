/**
 * Vercel Serverless Function Entry Point
 *
 * This wraps our Express app for Vercel deployment.
 * Note: SQLite is stored in /tmp for ephemeral storage in serverless.
 */

import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import swapRoutes from '../src/routes/swap.js';
import eventsRoutes from '../src/routes/events.js';
import voiceswapRoutes from '../src/routes/voiceswap.js';
import { initDatabase } from '../src/services/database.js';

const app = express();

// Security middleware
app.use(helmet({
  contentSecurityPolicy: false, // Disable for API
}));
app.use(cors());
app.use(express.json());

// Initialize database (will use /tmp in Vercel)
let dbInitialized = false;
app.use(async (_req, _res, next) => {
  if (!dbInitialized) {
    try {
      await initDatabase();
      dbInitialized = true;
    } catch (e) {
      console.error('[DB] Init error:', e);
    }
  }
  next();
});

// Get payment receiver address from env
const PAYMENT_RECEIVER = process.env.PAYMENT_RECEIVER_ADDRESS ?? '';
const NETWORK = (process.env.NETWORK || 'unichain') as 'unichain' | 'unichain-sepolia';
const CHAIN_ID = NETWORK === 'unichain' ? 130 : 1301;

// Mount routes
app.use('/', swapRoutes);
app.use('/events', eventsRoutes);
app.use('/voiceswap', voiceswapRoutes);

// Apple App Site Association for Universal Links
app.get('/.well-known/apple-app-site-association', (_req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.json({
    applinks: {
      apps: [],
      details: [
        {
          appID: "TEAMID.com.voiceswap.app",
          paths: ["/pay/*", "/app/*", "/wc/*"]
        }
      ]
    },
    webcredentials: {
      apps: ["TEAMID.com.voiceswap.app"]
    }
  });
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
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; padding: 50px; background: #FFE135; color: black; }
        .container { max-width: 400px; margin: 0 auto; }
        h1 { font-size: 24px; font-weight: 900; }
        p { color: #333; }
        a { color: black; font-weight: bold; }
        .card { background: white; padding: 20px; border: 3px solid black; box-shadow: 4px 4px 0 black; margin-top: 20px; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>VOICESWAP</h1>
        <p>Opening VoiceSwap app...</p>
        <div class="card">
          <p>Payment to: ${wallet.slice(0, 10)}...${wallet.slice(-8)}</p>
          ${amount ? `<p><strong>$${amount} USDC</strong></p>` : ''}
        </div>
        <p style="margin-top: 30px; font-size: 14px;">
          App not installed? <a href="https://apps.apple.com/app/voiceswap">Download here</a>
        </p>
      </div>
    </body>
    </html>
  `);
});

// Root endpoint - service info
app.get('/', (_req, res) => {
  res.json({
    service: 'VoiceSwap API',
    description: 'Voice-activated crypto payments for Meta Ray-Ban glasses',
    version: '1.0.0',
    network: NETWORK,
    chainId: CHAIN_ID,
    endpoints: {
      '/voiceswap/info': 'Service information',
      '/voiceswap/balance/:address': 'Get wallet balances',
      '/voiceswap/prepare': 'Prepare payment',
      '/voiceswap/execute': 'Execute payment',
      '/voiceswap/ai/parse': 'Parse voice command',
      '/voiceswap/ai/process': 'Process voice with context',
      '/health': 'Health check',
    },
  });
});

// Health check
app.get('/health', (_req, res) => {
  res.json({
    status: 'ok',
    timestamp: Date.now(),
    network: NETWORK,
    chainId: CHAIN_ID,
  });
});

// Error handling
app.use((err: Error, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  console.error('Server error:', err);
  res.status(500).json({
    error: 'Internal server error',
    code: 'INTERNAL_ERROR',
  });
});

export default app;
