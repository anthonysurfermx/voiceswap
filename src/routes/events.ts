/**
 * Server-Sent Events for Real-Time Transaction Updates
 *
 * Replaces polling with push-based updates
 */

import { Router, Request, Response } from 'express';
import { getUniswapService } from '../services/uniswap.js';

const router = Router();

// Store active SSE connections
const connections = new Map<string, Response>();

/**
 * SSE endpoint for transaction status updates
 *
 * Usage:
 * const eventSource = new EventSource('/events/tx-123456');
 * eventSource.onmessage = (event) => {
 *   const data = JSON.parse(event.data);
 *   console.log('Status:', data.status);
 * };
 */
router.get('/tx/:queueId', (req: Request, res: Response) => {
  const { queueId } = req.params;

  // Set SSE headers
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');
  res.setHeader('Access-Control-Allow-Origin', '*');

  // Send initial connection confirmation
  res.write(`data: ${JSON.stringify({ status: 'connected', queueId })}\n\n`);

  // Store connection
  connections.set(queueId, res);

  console.log(`[SSE] Client connected for tx: ${queueId}`);

  // Start monitoring transaction
  monitorTransaction(queueId);

  // Handle client disconnect
  req.on('close', () => {
    connections.delete(queueId);
    console.log(`[SSE] Client disconnected for tx: ${queueId}`);
  });
});

/**
 * Monitor transaction and push updates
 */
async function monitorTransaction(queueId: string) {
  const connection = connections.get(queueId);
  if (!connection) return;

  try {
    const uniswap = getUniswapService();

    // Poll blockchain every 2 seconds (but only on server-side)
    const interval = setInterval(async () => {
      try {
        const status = await uniswap.getTransactionStatus(queueId);

        // Push update to client
        const connection = connections.get(queueId);
        if (connection) {
          connection.write(`data: ${JSON.stringify(status)}\n\n`);
        }

        // Stop monitoring if final state
        if (status.status === 'confirmed' || status.status === 'failed') {
          clearInterval(interval);

          // Send final event
          if (connection) {
            connection.write(`event: complete\ndata: ${JSON.stringify(status)}\n\n`);
            connection.end();
          }

          connections.delete(queueId);
        }
      } catch (error) {
        console.error(`[SSE] Error monitoring tx ${queueId}:`, error);
        clearInterval(interval);

        const connection = connections.get(queueId);
        if (connection) {
          connection.write(`event: error\ndata: ${JSON.stringify({ error: 'Monitoring failed' })}\n\n`);
          connection.end();
        }

        connections.delete(queueId);
      }
    }, 2000); // Poll every 2 seconds server-side

    // Cleanup after 5 minutes max
    setTimeout(() => {
      clearInterval(interval);
      const connection = connections.get(queueId);
      if (connection) {
        connection.write(`event: timeout\ndata: ${JSON.stringify({ status: 'timeout' })}\n\n`);
        connection.end();
      }
      connections.delete(queueId);
    }, 5 * 60 * 1000);

  } catch (error) {
    console.error(`[SSE] Failed to start monitoring for ${queueId}:`, error);
  }
}

/**
 * Manual push endpoint (for webhook integration)
 *
 * External services can call this when tx status changes
 */
router.post('/push/:queueId', (req: Request, res: Response) => {
  const { queueId } = req.params;
  const status = req.body;

  const connection = connections.get(queueId);
  if (connection) {
    connection.write(`data: ${JSON.stringify(status)}\n\n`);

    // Close connection if final state
    if (status.status === 'confirmed' || status.status === 'failed') {
      connection.write(`event: complete\ndata: ${JSON.stringify(status)}\n\n`);
      connection.end();
      connections.delete(queueId);
    }
  }

  res.json({ success: true, pushed: !!connection });
});

export default router;
