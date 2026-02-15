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
import { ethers } from 'ethers';
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
const NETWORK = (process.env.NETWORK || 'monad') as 'monad';
const CHAIN_ID = 143;

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
          appID: "QZRTV6CMTT.com.voiceswap.app",
          paths: ["/pay/*", "/app/*", "/wc/*"]
        }
      ]
    },
    webcredentials: {
      apps: ["QZRTV6CMTT.com.voiceswap.app"]
    }
  });
});

// Deep link handler for VoiceSwap app
app.get('/app/*', (req, res) => {
  const appUrl = `voiceswap://${req.path.replace('/app/', '')}`;
  res.redirect(appUrl);
});

// HTML-escape to prevent XSS
function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

// Payment deep link (for QR codes)
app.get('/pay/:wallet', (req, res) => {
  const wallet = req.params.wallet;
  const amount = req.query.amount as string;
  const name = req.query.name as string;

  // Validate wallet is a valid hex address
  if (!/^0x[a-fA-F0-9]{40}$/.test(wallet)) {
    return res.status(400).send('Invalid wallet address');
  }

  // Validate amount is a number if provided
  if (amount && (isNaN(Number(amount)) || Number(amount) <= 0)) {
    return res.status(400).send('Invalid amount');
  }

  const safeWallet = escapeHtml(wallet);
  const safeAmount = amount ? escapeHtml(amount) : '';
  const safeName = name ? escapeHtml(name) : '';

  const appUrl = `voiceswap://pay?wallet=${encodeURIComponent(wallet)}${amount ? `&amount=${encodeURIComponent(amount)}` : ''}${safeName ? `&name=${encodeURIComponent(name)}` : ''}`;

  res.send(`
    <!DOCTYPE html>
    <html>
    <head>
      <title>VoiceSwap Payment</title>
      <meta http-equiv="refresh" content="0;url=${escapeHtml(appUrl)}">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; padding: 50px; background: #1a1a1a; color: white; }
        .container { max-width: 400px; margin: 0 auto; }
        h1 { font-size: 24px; font-weight: 900; color: #836EF9; }
        p { color: #999; }
        a { color: #836EF9; font-weight: bold; }
        .card { background: #2a2a2a; padding: 20px; border: 2px solid #836EF9; border-radius: 12px; margin-top: 20px; }
      </style>
    </head>
    <body>
      <div class="container">
        <h1>VOICESWAP</h1>
        <p>Opening VoiceSwap app...</p>
        <div class="card">
          <p>Payment to: ${safeWallet.slice(0, 10)}...${safeWallet.slice(-8)}</p>
          ${safeAmount ? `<p><strong>$${safeAmount} USDC</strong></p>` : ''}
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
    version: '3.0.0',
    network: NETWORK,
    chainId: CHAIN_ID,
    endpoints: {
      '/voiceswap/info': 'Service information',
      '/voiceswap/balance/:address': 'Get wallet balances',
      '/voiceswap/prepare': 'Prepare payment',
      '/voiceswap/execute': 'Execute payment',
      '/voiceswap/ai/parse': 'Parse voice command',
      '/voiceswap/ai/process': 'Process voice with context',
      '/voiceswap/onramp/session-token': 'Generate Coinbase Onramp session token',
      '/health': 'Health check',
    },
  });
});

// Health check with RPC connectivity
app.get('/health', async (_req, res) => {
  const rpcUrl = process.env.MONAD_RPC_URL || 'https://rpc.monad.xyz';
  let rpcStatus = 'unknown';
  let blockNumber: number | null = null;

  try {
    const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
    blockNumber = await provider.getBlockNumber();
    rpcStatus = 'connected';
  } catch {
    rpcStatus = 'error';
  }

  const healthy = rpcStatus === 'connected';
  res.status(healthy ? 200 : 503).json({
    status: healthy ? 'ok' : 'degraded',
    timestamp: Date.now(),
    network: NETWORK,
    chainId: CHAIN_ID,
    rpc: {
      status: rpcStatus,
      blockNumber,
    },
    gasSponsorship: process.env.GAS_SPONSOR_KEY ? 'configured' : 'not_configured',
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
