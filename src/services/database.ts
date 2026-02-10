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
  // Use /tmp for Vercel serverless, otherwise use cwd
  const isVercel = process.env.VERCEL === '1';
  const dbPath = process.env.DATABASE_PATH ||
    (isVercel ? '/tmp/voiceswap.db' : path.join(process.cwd(), 'voiceswap.db'));

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
      confirmed_at INTEGER
    );

    CREATE INDEX IF NOT EXISTS idx_tx_user_address ON transactions(user_address);
    CREATE INDEX IF NOT EXISTS idx_tx_status ON transactions(status);
    CREATE INDEX IF NOT EXISTS idx_tx_created_at ON transactions(created_at);

    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      wallet_address TEXT UNIQUE NOT NULL,
      email TEXT,
      created_at INTEGER NOT NULL,
      last_login INTEGER NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_users_wallet ON users(wallet_address);

    -- Merchant payments table for tracking received payments with concepts
    CREATE TABLE IF NOT EXISTS merchant_payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      merchant_wallet TEXT NOT NULL,
      tx_hash TEXT UNIQUE NOT NULL,
      from_address TEXT NOT NULL,
      amount TEXT NOT NULL,
      concept TEXT,
      block_number INTEGER NOT NULL,
      created_at INTEGER NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_merchant_wallet ON merchant_payments(merchant_wallet);
    CREATE INDEX IF NOT EXISTS idx_merchant_tx_hash ON merchant_payments(tx_hash);
    CREATE INDEX IF NOT EXISTS idx_merchant_block ON merchant_payments(block_number);

    -- Address labels for human-readable names
    CREATE TABLE IF NOT EXISTS address_labels (
      address TEXT PRIMARY KEY NOT NULL,
      label TEXT NOT NULL,
      updated_at INTEGER NOT NULL
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
      data.routingType || 'v3',
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

// ============================================
// Merchant Payments
// ============================================

export interface MerchantPayment {
  id?: number;
  merchant_wallet: string;
  tx_hash: string;
  from_address: string;
  amount: string;
  concept: string | null;
  block_number: number;
  created_at: number;
}

/**
 * Save or update a merchant payment
 * If txHash already exists, updates the concept
 */
export async function saveMerchantPayment(data: {
  merchantWallet: string;
  txHash: string;
  fromAddress: string;
  amount: string;
  concept?: string;
  blockNumber: number;
}): Promise<void> {
  const db = getDb();
  const now = Date.now();

  await db.run(
    `INSERT INTO merchant_payments (merchant_wallet, tx_hash, from_address, amount, concept, block_number, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(tx_hash) DO UPDATE SET concept = excluded.concept`,
    [
      data.merchantWallet.toLowerCase(),
      data.txHash.toLowerCase(),
      data.fromAddress.toLowerCase(),
      data.amount,
      data.concept || null,
      data.blockNumber,
      now,
    ]
  );
}

/**
 * Get merchant payments with optional concept filter
 */
export async function getMerchantPayments(
  merchantWallet: string,
  options: {
    limit?: number;
    offset?: number;
    concept?: string;
  } = {}
): Promise<MerchantPayment[]> {
  const db = getDb();
  const { limit = 50, offset = 0, concept } = options;

  let query = `SELECT * FROM merchant_payments WHERE merchant_wallet = ?`;
  const params: any[] = [merchantWallet.toLowerCase()];

  if (concept) {
    query += ` AND concept = ?`;
    params.push(concept);
  }

  query += ` ORDER BY block_number DESC LIMIT ? OFFSET ?`;
  params.push(limit, offset);

  return await db.all(query, params);
}

/**
 * Get user payment history (payments sent by a user)
 */
export async function getUserPayments(
  userAddress: string,
  options: {
    limit?: number;
    offset?: number;
  } = {}
): Promise<MerchantPayment[]> {
  const db = getDb();
  const { limit = 50, offset = 0 } = options;

  return await db.all(
    `SELECT * FROM merchant_payments WHERE from_address = ? ORDER BY created_at DESC LIMIT ? OFFSET ?`,
    [userAddress.toLowerCase(), limit, offset]
  );
}

/**
 * Get payment by txHash
 */
export async function getMerchantPaymentByTxHash(txHash: string): Promise<MerchantPayment | null> {
  const db = getDb();
  const result = await db.get(
    'SELECT * FROM merchant_payments WHERE tx_hash = ?',
    [txHash.toLowerCase()]
  );
  return result ?? null;
}

/**
 * Update concept for a payment
 */
export async function updatePaymentConcept(txHash: string, concept: string): Promise<void> {
  const db = getDb();
  await db.run(
    'UPDATE merchant_payments SET concept = ? WHERE tx_hash = ?',
    [concept, txHash.toLowerCase()]
  );
}

/**
 * Get merchant payment stats
 */
export async function getMerchantStats(merchantWallet: string): Promise<{
  totalPayments: number;
  totalAmount: string;
  uniquePayers: number;
  conceptBreakdown: { concept: string; count: number; total: string }[];
}> {
  const db = getDb();

  const stats = await db.get(
    `SELECT
      COUNT(*) as totalPayments,
      COALESCE(SUM(CAST(amount AS REAL)), 0) as totalAmount,
      COUNT(DISTINCT from_address) as uniquePayers
    FROM merchant_payments
    WHERE merchant_wallet = ?`,
    [merchantWallet.toLowerCase()]
  );

  const conceptBreakdown = await db.all(
    `SELECT
      COALESCE(concept, 'Sin concepto') as concept,
      COUNT(*) as count,
      COALESCE(SUM(CAST(amount AS REAL)), 0) as total
    FROM merchant_payments
    WHERE merchant_wallet = ?
    GROUP BY concept
    ORDER BY total DESC`,
    [merchantWallet.toLowerCase()]
  );

  return {
    totalPayments: stats?.totalPayments || 0,
    totalAmount: (stats?.totalAmount || 0).toFixed(2),
    uniquePayers: stats?.uniquePayers || 0,
    conceptBreakdown: conceptBreakdown.map(c => ({
      concept: c.concept,
      count: c.count,
      total: c.total.toFixed(2),
    })),
  };
}

/**
 * Save or update an address label
 */
export async function setAddressLabel(address: string, label: string): Promise<void> {
  const db = getDb();
  await db.run(
    `INSERT INTO address_labels (address, label, updated_at) VALUES (?, ?, ?)
     ON CONFLICT(address) DO UPDATE SET label = ?, updated_at = ?`,
    [address.toLowerCase(), label, Date.now(), label, Date.now()]
  );
}

/**
 * Get label for an address
 */
export async function getAddressLabel(address: string): Promise<string | null> {
  const db = getDb();
  const row = await db.get(
    'SELECT label FROM address_labels WHERE address = ?',
    [address.toLowerCase()]
  );
  return row?.label ?? null;
}

/**
 * Resolve multiple addresses to labels at once
 */
export async function resolveAddressLabels(addresses: string[]): Promise<Record<string, string>> {
  const db = getDb();
  if (addresses.length === 0) return {};

  const placeholders = addresses.map(() => '?').join(',');
  const rows = await db.all(
    `SELECT address, label FROM address_labels WHERE address IN (${placeholders})`,
    addresses.map(a => a.toLowerCase())
  );

  const result: Record<string, string> = {};
  for (const row of rows) {
    result[row.address] = row.label;
  }
  return result;
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
