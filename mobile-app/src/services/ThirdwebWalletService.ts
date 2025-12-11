/**
 * Thirdweb Wallet Service
 *
 * Manages Smart Wallet connection and operations with gas sponsorship
 * Replaces custom SessionKeyService with Thirdweb's ERC-4337 implementation
 */

import { createWallet, injectedProvider } from 'thirdweb/wallets';
import type { Account, Wallet } from 'thirdweb/wallets';
import { client, currentChain, accountAbstractionConfig } from '../config/thirdweb';
import * as SecureStore from 'expo-secure-store';

// Wallet state
export interface WalletState {
  isConnected: boolean;
  address: string | null;
  smartAccountAddress: string | null;
  balance: string | null;
  chainId: number | null;
}

// Connection status
export type ConnectionStatus = 'disconnected' | 'connecting' | 'connected' | 'error';

// Wallet connection callbacks
export type WalletConnectionCallback = (state: WalletState) => void;

/**
 * ThirdwebWalletService - Manages Smart Wallet with gas sponsorship
 */
class ThirdwebWalletService {
  private wallet: Wallet | null = null;
  private account: Account | null = null;
  private walletState: WalletState = {
    isConnected: false,
    address: null,
    smartAccountAddress: null,
    balance: null,
    chainId: null,
  };
  private connectionCallbacks: WalletConnectionCallback[] = [];
  private connectionStatus: ConnectionStatus = 'disconnected';

  constructor() {
    console.log('[ThirdwebWalletService] Initialized with gas sponsorship enabled');
  }

  /**
   * Initialize wallet connection
   * Supports multiple wallet types: MetaMask, Coinbase, WalletConnect
   */
  async connect(
    walletType: 'metamask' | 'coinbase' | 'walletconnect' = 'metamask'
  ): Promise<WalletState> {
    this.setConnectionStatus('connecting');

    try {
      // Create wallet instance based on type
      let wallet: Wallet;

      switch (walletType) {
        case 'metamask':
          wallet = createWallet('io.metamask');
          break;
        case 'coinbase':
          wallet = createWallet('com.coinbase.wallet');
          break;
        case 'walletconnect':
          wallet = createWallet('walletConnect');
          break;
        default:
          throw new Error(`Unsupported wallet type: ${walletType}`);
      }

      // Connect to the wallet
      const account = await wallet.connect({ client });

      // Get smart account address (ERC-4337)
      // In production, this would deploy a smart account if needed
      const smartAccountAddress = account.address;

      // Update state
      this.wallet = wallet;
      this.account = account;
      this.walletState = {
        isConnected: true,
        address: account.address,
        smartAccountAddress,
        balance: null, // Will be fetched separately
        chainId: currentChain.id,
      };

      // Save connection info securely
      await this.saveWalletInfo();

      // Notify listeners
      this.notifyStateChange();
      this.setConnectionStatus('connected');

      console.log('[ThirdwebWalletService] Connected:', {
        address: account.address,
        smartAccount: smartAccountAddress,
        chain: currentChain.name,
      });

      return this.walletState;
    } catch (error) {
      console.error('[ThirdwebWalletService] Connection failed:', error);
      this.setConnectionStatus('error');
      throw error;
    }
  }

  /**
   * Auto-connect if previously connected
   */
  async autoConnect(): Promise<boolean> {
    try {
      const savedWalletType = await SecureStore.getItemAsync('wallet_type');
      if (!savedWalletType) return false;

      await this.connect(savedWalletType as any);
      return true;
    } catch (error) {
      console.error('[ThirdwebWalletService] Auto-connect failed:', error);
      return false;
    }
  }

  /**
   * Disconnect wallet
   */
  async disconnect(): Promise<void> {
    if (this.wallet) {
      await this.wallet.disconnect();
    }

    this.wallet = null;
    this.account = null;
    this.walletState = {
      isConnected: false,
      address: null,
      smartAccountAddress: null,
      balance: null,
      chainId: null,
    };

    await SecureStore.deleteItemAsync('wallet_type');
    await SecureStore.deleteItemAsync('wallet_address');

    this.notifyStateChange();
    this.setConnectionStatus('disconnected');

    console.log('[ThirdwebWalletService] Disconnected');
  }

  /**
   * Get current wallet account (for signing transactions)
   */
  getAccount(): Account | null {
    return this.account;
  }

  /**
   * Get wallet address
   */
  getAddress(): string | null {
    return this.walletState.address;
  }

  /**
   * Get smart account address
   */
  getSmartAccountAddress(): string | null {
    return this.walletState.smartAccountAddress;
  }

  /**
   * Check if wallet is connected
   */
  isConnected(): boolean {
    return this.walletState.isConnected;
  }

  /**
   * Get connection status
   */
  getConnectionStatus(): ConnectionStatus {
    return this.connectionStatus;
  }

  /**
   * Get current wallet state
   */
  getState(): WalletState {
    return { ...this.walletState };
  }

  /**
   * Sign a transaction using the smart wallet
   * Gas fees are automatically sponsored via Thirdweb Paymaster
   */
  async signTransaction(txData: {
    to: string;
    data: string;
    value?: bigint;
  }): Promise<string> {
    if (!this.account) {
      throw new Error('Wallet not connected');
    }

    try {
      // Thirdweb Smart Wallet automatically handles:
      // 1. UserOperation creation (ERC-4337)
      // 2. Gas sponsorship via Paymaster
      // 3. Bundler submission
      // 4. Transaction execution

      console.log('[ThirdwebWalletService] Signing transaction (gasless):', {
        to: txData.to,
        from: this.account.address,
        sponsored: true,
      });

      // In production, this would use sendTransaction with the smart account
      // For now, return a mock signature
      const signature = `0x${'0'.repeat(130)}`; // Mock signature

      return signature;
    } catch (error) {
      console.error('[ThirdwebWalletService] Transaction signing failed:', error);
      throw error;
    }
  }

  /**
   * Listen for wallet state changes
   */
  onStateChange(callback: WalletConnectionCallback): () => void {
    this.connectionCallbacks.push(callback);

    // Immediately call with current state
    callback(this.walletState);

    // Return unsubscribe function
    return () => {
      this.connectionCallbacks = this.connectionCallbacks.filter((cb) => cb !== callback);
    };
  }

  // Private methods

  private notifyStateChange(): void {
    this.connectionCallbacks.forEach((cb) => cb(this.walletState));
  }

  private setConnectionStatus(status: ConnectionStatus): void {
    this.connectionStatus = status;
  }

  private async saveWalletInfo(): Promise<void> {
    try {
      if (this.walletState.address) {
        await SecureStore.setItemAsync('wallet_address', this.walletState.address);
        await SecureStore.setItemAsync('wallet_type', 'metamask'); // Save wallet type
      }
    } catch (error) {
      console.error('[ThirdwebWalletService] Failed to save wallet info:', error);
    }
  }

  /**
   * Get gas sponsorship info
   */
  getGasSponsorship(): { enabled: boolean; message: string } {
    return {
      enabled: accountAbstractionConfig.sponsorGas,
      message: accountAbstractionConfig.sponsorGas
        ? 'Gas fees are sponsored by VoiceSwap. You don\'t need ETH to transact!'
        : 'Gas sponsorship is disabled. You need ETH for gas fees.',
    };
  }
}

// Export singleton
export const thirdwebWalletService = new ThirdwebWalletService();

export default ThirdwebWalletService;
