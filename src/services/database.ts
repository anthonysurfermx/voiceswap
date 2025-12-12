/**
 * SQLite Database Service
 *
 * Lightweight persistence for transaction history and user data
 */

import sqlite3 from 'sqlite3';
import { open, Database } from 'sqlite';
import path from 'path';

let db: Database | null = null;

/**
 * Initialize database and create tables
 */
export async function initDatabase(): Promise<void> {
  const dbPath = process.env.DATABASE_PATH || path.join(process.cwd(), 'voiceswap.db');

  db = await open({
    filename: dbPath,
    driver: sqlite3.Database,
  });

  // Create tables
  await db.exec(`
    CREATE TABLE IF NOT EXISTS transactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      queue_id TEXT UNIQUE NOT NULL,
      user_address TEXT NOT NULL,
      tx_hash TEXT,
      token_in TEXT NOT NULL,
      token_out TEXT NOT NULL,
      amount_in TEXT NOT NULL,
      amount_out TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      routing_type TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      confirmed_at INTEGER,

      INDEX idx_user_address (user_address),
      INDEX idx_status (status),
      INDEX idx_created_at (created_at)
    );

    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      wallet_address TEXT UNIQUE NOT NULL,
      email TEXT,
      created_at INTEGER NOT NULL,
      last_login INTEGER NOT NULL,

      INDEX idx_wallet_address (wallet_address)
    );
  `);

  console.log('[Database] Initialized at:', dbPath);
}

/**
 * Get database instance
 */
export function getDb(): Database {
  if (!db) {
    throw new Error('Database not initialized. Call initDatabase() first.');
  }
  return db;
}

/**
 * Save transaction
 */
export async function saveTransaction(data: {
  queueId: string;
  userAddress: string;
  tokenIn: string;
  tokenOut: string;
  amountIn: string;
  routingType?: string;
}): Promise<void> {
  const db = getDb();
  const now = Date.now();

  await db.run(
    `INSERT INTO transactions (queue_id, user_address, token_in, token_out, amount_in, routing_type, status, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, 'pending', ?, ?)`,
    [
      data.queueId,
      data.userAddress,
      data.tokenIn,
      data.tokenOut,
      data.amountIn,
      data.routingType || 'v4',
      now,
      now,
    ]
  );
}

/**
 * Update transaction status
 */
export async function updateTransactionStatus(
  queueId: string,
  status: 'pending' | 'confirmed' | 'failed',
  txHash?: string,
  amountOut?: string
): Promise<void> {
  const db = getDb();
  const now = Date.now();

  const updates: string[] = ['status = ?', 'updated_at = ?'];
  const params: any[] = [status, now];

  if (txHash) {
    updates.push('tx_hash = ?');
    params.push(txHash);
  }

  if (amountOut) {
    updates.push('amount_out = ?');
    params.push(amountOut);
  }

  if (status === 'confirmed') {
    updates.push('confirmed_at = ?');
    params.push(now);
  }

  params.push(queueId);

  await db.run(
    `UPDATE transactions SET ${updates.join(', ')} WHERE queue_id = ?`,
    params
  );
}

/**
 * Get transaction by queueId
 */
export async function getTransaction(queueId: string): Promise<any | null> {
  const db = getDb();

  return await db.get(
    'SELECT * FROM transactions WHERE queue_id = ?',
    [queueId]
  );
}

/**
 * Get user transaction history
 */
export async function getUserTransactions(
  userAddress: string,
  limit: number = 50
): Promise<any[]> {
  const db = getDb();

  return await db.all(
    `SELECT * FROM transactions
     WHERE user_address = ?
     ORDER BY created_at DESC
     LIMIT ?`,
    [userAddress, limit]
  );
}

/**
 * Get or create user
 */
export async function getOrCreateUser(walletAddress: string, email?: string): Promise<any> {
  const db = getDb();
  const now = Date.now();

  // Try to get existing user
  let user = await db.get(
    'SELECT * FROM users WHERE wallet_address = ?',
    [walletAddress]
  );

  if (!user) {
    // Create new user
    await db.run(
      'INSERT INTO users (wallet_address, email, created_at, last_login) VALUES (?, ?, ?, ?)',
      [walletAddress, email, now, now]
    );

    user = await db.get(
      'SELECT * FROM users WHERE wallet_address = ?',
      [walletAddress]
    );
  } else {
    // Update last login
    await db.run(
      'UPDATE users SET last_login = ? WHERE wallet_address = ?',
      [now, walletAddress]
    );
  }

  return user;
}

/**
 * Get analytics
 */
export async function getAnalytics() {
  const db = getDb();

  const [stats] = await Promise.all([
    db.get(`
      SELECT
        COUNT(*) as total_swaps,
        COUNT(DISTINCT user_address) as unique_users,
        SUM(CASE WHEN status = 'confirmed' THEN 1 ELSE 0 END) as successful_swaps,
        SUM(CASE WHEN status = 'failed' THEN 1 ELSE 0 END) as failed_swaps
      FROM transactions
    `),
  ]);

  return stats;
}

/**
 * Close database connection
 */
export async function closeDatabase(): Promise<void> {
  if (db) {
    await db.close();
    db = null;
    console.log('[Database] Closed');
  }
}
