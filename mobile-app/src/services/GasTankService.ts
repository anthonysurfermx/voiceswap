/**
 * Gas Tank Service - Prepaid x402 Balance Management
 *
 * Instead of paying for each API call individually, the user deposits
 * USDC into a "Gas Tank" and the app deducts from this balance.
 * This reduces friction and latency.
 *
 * Flow:
 * 1. User deposits USDC to Gas Tank (one-time transaction)
 * 2. Each x402 API call deducts from the tank balance
 * 3. When balance is low, prompt user to refill
 */

import { ethers } from 'ethers';

// x402 pricing for each endpoint
export const X402_PRICING = {
  '/quote': 0.001,    // $0.001
  '/route': 0.005,    // $0.005
  '/execute': 0.02,   // $0.02
  '/status': 0.001,   // $0.001
} as const;

// Total cost for a full swap flow
export const SWAP_TOTAL_COST =
  X402_PRICING['/quote'] +
  X402_PRICING['/route'] +
  X402_PRICING['/execute'] +
  X402_PRICING['/status']; // ~$0.027

export interface GasTankState {
  // Current balance in USD
  balance: number;

  // Total deposited over time
  totalDeposited: number;

  // Total spent on x402 calls
  totalSpent: number;

  // Deposit address for USDC
  depositAddress: string;

  // Last deposit timestamp
  lastDeposit?: number;

  // Last usage timestamp
  lastUsage?: number;
}

export interface DepositInfo {
  address: string;
  network: string;
  token: string;
  minimumDeposit: number;
  suggestedDeposit: number;
}

/**
 * GasTankService - Manages prepaid x402 balance
 */
class GasTankService {
  private state: GasTankState;
  private readonly MIN_BALANCE_WARNING = 0.10; // Warn when below $0.10
  private readonly MIN_DEPOSIT = 0.50; // Minimum $0.50 deposit
  private readonly SUGGESTED_DEPOSIT = 5.00; // Suggest $5 deposit (~185 swaps)

  // For demo: deposit address on Base
  private readonly DEPOSIT_ADDRESS = '0x742d35Cc6634C0532925a3b844Bc9e7595f5bA2a';

  constructor() {
    // Initialize with mock balance for demo
    this.state = {
      balance: 1.00, // Start with $1 for demo
      totalDeposited: 1.00,
      totalSpent: 0,
      depositAddress: this.DEPOSIT_ADDRESS,
    };

    // In production, load from secure storage
    this.loadState();
  }

  /**
   * Load state from storage
   */
  private async loadState(): Promise<void> {
    // In production: load from AsyncStorage or secure keychain
    // For now, use in-memory state
    console.log('[GasTank] Loaded state:', this.state);
  }

  /**
   * Save state to storage
   */
  private async saveState(): Promise<void> {
    // In production: save to AsyncStorage or secure keychain
    console.log('[GasTank] Saved state:', this.state);
  }

  /**
   * Get current Gas Tank state
   */
  getState(): GasTankState {
    return { ...this.state };
  }

  /**
   * Get current balance
   */
  getBalance(): number {
    return this.state.balance;
  }

  /**
   * Check if we have enough balance for an operation
   */
  canAfford(endpoint: keyof typeof X402_PRICING): boolean {
    const cost = X402_PRICING[endpoint];
    return this.state.balance >= cost;
  }

  /**
   * Check if we can afford a full swap flow
   */
  canAffordSwap(): boolean {
    return this.state.balance >= SWAP_TOTAL_COST;
  }

  /**
   * Get number of swaps remaining at current balance
   */
  getSwapsRemaining(): number {
    return Math.floor(this.state.balance / SWAP_TOTAL_COST);
  }

  /**
   * Check if balance is low
   */
  isBalanceLow(): boolean {
    return this.state.balance < this.MIN_BALANCE_WARNING;
  }

  /**
   * Deduct cost for an API call
   * Returns true if deduction successful, false if insufficient funds
   */
  deduct(endpoint: keyof typeof X402_PRICING): boolean {
    const cost = X402_PRICING[endpoint];

    if (this.state.balance < cost) {
      console.log(`[GasTank] Insufficient funds for ${endpoint}. Need $${cost}, have $${this.state.balance}`);
      return false;
    }

    this.state.balance -= cost;
    this.state.totalSpent += cost;
    this.state.lastUsage = Date.now();

    console.log(`[GasTank] Deducted $${cost} for ${endpoint}. New balance: $${this.state.balance.toFixed(4)}`);

    this.saveState();
    return true;
  }

  /**
   * Add funds to the Gas Tank (after on-chain deposit confirmed)
   */
  deposit(amountUSD: number): void {
    this.state.balance += amountUSD;
    this.state.totalDeposited += amountUSD;
    this.state.lastDeposit = Date.now();

    console.log(`[GasTank] Deposited $${amountUSD}. New balance: $${this.state.balance.toFixed(4)}`);

    this.saveState();
  }

  /**
   * Get deposit information for user
   */
  getDepositInfo(): DepositInfo {
    return {
      address: this.DEPOSIT_ADDRESS,
      network: 'Base',
      token: 'USDC',
      minimumDeposit: this.MIN_DEPOSIT,
      suggestedDeposit: this.SUGGESTED_DEPOSIT,
    };
  }

  /**
   * Generate a payment for an x402 request
   * In production, this would create a proper x402 payment header
   */
  async generatePayment(endpoint: keyof typeof X402_PRICING): Promise<{
    success: boolean;
    paymentHeader?: string;
    error?: string;
  }> {
    const cost = X402_PRICING[endpoint];

    if (this.state.balance < cost) {
      return {
        success: false,
        error: `Insufficient Gas Tank balance. Need $${cost}, have $${this.state.balance.toFixed(4)}`,
      };
    }

    // Deduct from balance
    if (!this.deduct(endpoint)) {
      return {
        success: false,
        error: 'Failed to deduct from Gas Tank',
      };
    }

    // In production, this would generate a proper x402 payment signature
    // For now, we'll create a mock payment header that the backend can validate
    const paymentData = {
      from: this.DEPOSIT_ADDRESS,
      amount: cost,
      timestamp: Date.now(),
      endpoint,
      nonce: Math.random().toString(36).substring(7),
    };

    const paymentHeader = Buffer.from(JSON.stringify(paymentData)).toString('base64');

    return {
      success: true,
      paymentHeader: `GasTank ${paymentHeader}`,
    };
  }

  /**
   * Format balance for speech
   */
  formatBalanceForSpeech(): string {
    const balance = this.state.balance;
    const swapsRemaining = this.getSwapsRemaining();

    if (balance <= 0) {
      return "Your Gas Tank is empty. Please deposit USDC to continue using VoiceSwap.";
    }

    if (this.isBalanceLow()) {
      return `Your Gas Tank is low. You have $${balance.toFixed(2)}, enough for about ${swapsRemaining} more swaps. Consider adding funds.`;
    }

    return `Your Gas Tank has $${balance.toFixed(2)}, enough for approximately ${swapsRemaining} swaps.`;
  }

  /**
   * Format deposit instructions for speech
   */
  formatDepositInstructionsForSpeech(): string {
    const info = this.getDepositInfo();
    return (
      `To add funds to your Gas Tank, send USDC on ${info.network} to your deposit address. ` +
      `Minimum deposit is $${info.minimumDeposit}. I recommend depositing $${info.suggestedDeposit} for about 185 swaps.`
    );
  }

  /**
   * Watch for deposits (in production, would monitor blockchain)
   */
  async watchForDeposits(callback: (amount: number) => void): Promise<() => void> {
    // In production: connect to provider and watch for Transfer events to deposit address
    // For demo: simulate periodic deposit checks

    const checkInterval = setInterval(async () => {
      // Simulate checking for new deposits
      // In production, query blockchain for new transfers
    }, 30000);

    return () => clearInterval(checkInterval);
  }
}

// Export singleton
export const gasTankService = new GasTankService();

export default GasTankService;
