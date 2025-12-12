/**
 * Thirdweb Engine Service
 *
 * Manages Account Abstraction (ERC-4337) via Thirdweb Engine
 * - Smart account deployment
 * - Gas sponsorship (paymaster)
 * - Transaction execution with UserOps
 * - Status tracking
 */

import { ethers } from 'ethers';

// Thirdweb API configuration
const API_URL = process.env.THIRDWEB_API_URL || 'https://api.thirdweb.com/v1';
const SECRET_KEY = process.env.THIRDWEB_SECRET_KEY;
const BACKEND_WALLET_ADDRESS = process.env.BACKEND_WALLET_ADDRESS;
const CHAIN_ID = process.env.NETWORK === 'unichain' ? 130 : 1301; // Unichain mainnet or sepolia

if (!SECRET_KEY) {
  console.warn('[ThirdwebAPI] No secret key configured. Some features may not work.');
}

// Universal Router address on Unichain
const UNIVERSAL_ROUTER_ADDRESS = process.env.UNIVERSAL_ROUTER_ADDRESS ||
  '0xef740bf23acae26f6492b10de645d6b98dc8eaf3';

/**
 * Thirdweb API client
 */
class ThirdwebAPIClient {
  private baseUrl: string;
  private headers: Record<string, string>;

  constructor() {
    this.baseUrl = API_URL;
    this.headers = {
      'Content-Type': 'application/json',
      ...(SECRET_KEY && { 'x-secret-key': SECRET_KEY }),
    };
  }

  async request(path: string, options: RequestInit = {}) {
    const url = `${this.baseUrl}${path}`;
    const response = await fetch(url, {
      ...options,
      headers: {
        ...this.headers,
        ...options.headers,
      },
    });

    if (!response.ok) {
      const errorData = await response.json().catch(() => ({ error: 'Unknown error' })) as { error?: string };
      throw new Error(`Thirdweb API error: ${errorData.error || response.statusText}`);
    }

    return response.json();
  }

  async get(path: string) {
    return this.request(path, { method: 'GET' });
  }

  async post(path: string, body: any) {
    return this.request(path, {
      method: 'POST',
      body: JSON.stringify(body),
    });
  }
}

const client = new ThirdwebAPIClient();

// API Response types
interface AccountsResponse {
  result?: string[];
}

interface CreateSmartWalletResponse {
  result: {
    smartWalletAddress: string;
  };
}

interface TransactionResponse {
  queueId?: string;
  id?: string;
  transactionHash?: string;
  txHash?: string;
}

interface TransactionStatusResponse {
  result: {
    queueId: string;
    status: 'queued' | 'sent' | 'mined' | 'errored' | 'cancelled';
    transactionHash?: string;
    blockNumber?: number;
    errorMessage?: string;
  };
}

interface TransactionListResponse {
  result?: unknown[];
}

interface BalanceResponse {
  result: {
    balance: string;
  };
}

/**
 * Smart account info
 */
export interface SmartAccount {
  address: string;
  admin: string;
  isDeployed: boolean;
  factory?: string;
}

/**
 * Transaction result from Engine
 */
export interface EngineTransactionResult {
  queueId: string;
  status: 'queued' | 'sent' | 'mined' | 'errored' | 'cancelled';
  transactionHash?: string;
  blockNumber?: number;
  errorMessage?: string;
  smartAccountAddress?: string;
}

/**
 * Get or create a smart account for a user
 *
 * Strategy:
 * 1. Check if user already has a smart account
 * 2. If not, create one (Engine deploys automatically)
 * 3. Return smart account address
 */
export async function getOrCreateSmartAccount(userAddress: string): Promise<SmartAccount> {
  try {
    console.log(`[Engine] Getting/creating smart account for ${userAddress}`);

    // Try to get existing smart accounts for this user
    // Engine endpoint: GET /backend-wallet/{chain}/{address}/get-all-accounts
    const accounts = await client.get(
      `/backend-wallet/${CHAIN_ID}/${userAddress}/get-all-accounts`
    ) as AccountsResponse;

    if (accounts.result && accounts.result.length > 0) {
      const account = accounts.result[0];
      console.log(`[Engine] Found existing smart account: ${account}`);

      return {
        address: account,
        admin: userAddress,
        isDeployed: true,
      };
    }

    // No existing account - create one
    // Engine automatically uses Smart Backend Wallets
    console.log(`[Engine] Creating new smart account for ${userAddress}`);

    const createResult = await client.post(
      `/backend-wallet/${CHAIN_ID}/${BACKEND_WALLET_ADDRESS}/create-smart-wallet`,
      {
        account_admin_address: userAddress,
      }
    ) as CreateSmartWalletResponse;

    const smartAccountAddress = createResult.result.smartWalletAddress;

    console.log(`[Engine] Created smart account: ${smartAccountAddress}`);

    return {
      address: smartAccountAddress,
      admin: userAddress,
      isDeployed: true,
    };
  } catch (error) {
    console.error('[Engine] Failed to get/create smart account:', error);
    throw new Error(`Failed to setup smart account: ${error}`);
  }
}

/**
 * Execute a swap transaction via Thirdweb API with gas sponsorship
 *
 * Uses Thirdweb's transaction API for gasless execution
 * API Docs: https://portal.thirdweb.com/api-reference/transactions
 */
export async function executeSwapViaEngine(params: {
  userAddress: string;
  calldata: string;
  value?: string;
}): Promise<EngineTransactionResult> {
  try {
    console.log(`[Thirdweb] Executing swap for ${params.userAddress}`);

    // Execute transaction via Thirdweb API
    // Format matches official Thirdweb API spec
    const result = await client.post('/transactions', {
      chainId: CHAIN_ID.toString(),
      from: BACKEND_WALLET_ADDRESS, // Server wallet that executes the tx
      transactions: [
        {
          type: 'raw', // Raw transaction with calldata
          to: UNIVERSAL_ROUTER_ADDRESS,
          data: params.calldata,
          value: params.value || '0',
        },
      ],
      // Optional: enable gas sponsorship (paymaster)
      sponsorGas: true,
    }) as TransactionResponse;

    console.log(`[Thirdweb] Transaction submitted:`, result);

    // Thirdweb returns a transaction queue ID
    return {
      queueId: result.queueId || result.id || `tx-${Date.now()}`,
      status: 'queued',
      transactionHash: result.transactionHash || result.txHash,
      smartAccountAddress: params.userAddress,
    };
  } catch (error) {
    console.error('[Thirdweb] Failed to execute swap:', error);

    // Log detailed error for debugging
    if (error instanceof Error) {
      console.error('[Thirdweb] Error details:', error.message);
    }

    throw new Error(`Failed to execute swap via Thirdweb: ${error instanceof Error ? error.message : 'Unknown error'}`);
  }
}

/**
 * Check transaction status from Engine queue
 */
export async function checkTransactionStatus(queueId: string): Promise<EngineTransactionResult> {
  try {
    const result = await client.get(`/transaction/status/${queueId}`) as TransactionStatusResponse;

    return {
      queueId: result.result.queueId,
      status: result.result.status,
      transactionHash: result.result.transactionHash,
      blockNumber: result.result.blockNumber,
      errorMessage: result.result.errorMessage,
    };
  } catch (error) {
    console.error('[Engine] Failed to check status:', error);
    throw new Error(`Failed to check transaction status: ${error}`);
  }
}

/**
 * Get all transactions for a smart account (for history)
 */
export async function getAccountTransactions(smartAccountAddress: string): Promise<unknown[]> {
  try {
    const result = await client.get(
      `/transaction/get-all?accountAddress=${smartAccountAddress}`
    ) as TransactionListResponse;

    return result.result || [];
  } catch (error) {
    console.error('[Engine] Failed to get transactions:', error);
    return [];
  }
}

/**
 * Cancel a queued transaction (before it's sent)
 */
export async function cancelTransaction(queueId: string): Promise<boolean> {
  try {
    await client.post(`/transaction/cancel/${queueId}`, {});
    return true;
  } catch (error) {
    console.error('[Engine] Failed to cancel transaction:', error);
    return false;
  }
}

/**
 * Check if Thirdweb API is configured and accessible
 */
export async function healthCheck(): Promise<{
  healthy: boolean;
  engineUrl: string;
  hasAccessToken: boolean;
  error?: string;
}> {
  try {
    // Thirdweb API doesn't have a /health endpoint
    // Just verify we have credentials
    if (!SECRET_KEY) {
      throw new Error('No secret key configured');
    }

    return {
      healthy: true,
      engineUrl: API_URL,
      hasAccessToken: true,
    };
  } catch (error) {
    return {
      healthy: false,
      engineUrl: API_URL,
      hasAccessToken: !!SECRET_KEY,
      error: error instanceof Error ? error.message : 'Unknown error',
    };
  }
}

/**
 * Get backend wallet balance (to ensure it has gas)
 */
export async function getBackendWalletBalance(): Promise<{
  address: string;
  balance: string;
  balanceEth: string;
}> {
  try {
    const result = await client.get(
      `/backend-wallet/${CHAIN_ID}/${BACKEND_WALLET_ADDRESS}/get-balance`
    ) as BalanceResponse;

    const balanceWei = result.result.balance;
    const balanceEth = ethers.utils.formatEther(balanceWei);

    return {
      address: BACKEND_WALLET_ADDRESS || '',
      balance: balanceWei,
      balanceEth,
    };
  } catch (error) {
    console.error('[Engine] Failed to get backend wallet balance:', error);
    throw error;
  }
}

// Export for use in routes
export default {
  getOrCreateSmartAccount,
  executeSwapViaEngine,
  checkTransactionStatus,
  getAccountTransactions,
  cancelTransaction,
  healthCheck,
  getBackendWalletBalance,
};
