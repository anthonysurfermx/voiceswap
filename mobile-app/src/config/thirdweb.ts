/**
 * Thirdweb Configuration
 *
 * Setup for Smart Wallets with Gas Sponsorship on Monad
 * Using EIP-7702 for gasless transactions
 */

import { createThirdwebClient } from 'thirdweb';
import { defineChain } from 'thirdweb/chains';

// Thirdweb Client
export const client = createThirdwebClient({
  clientId: process.env.EXPO_PUBLIC_THIRDWEB_CLIENT_ID!,
});

// Chain IDs
export const MONAD_MAINNET_ID = 143;

// Monad Mainnet (Chain ID: 143)
export const monadMainnet = defineChain(MONAD_MAINNET_ID);

// Current chain
export const currentChain = monadMainnet;

// Current chain ID for easy access
export const currentChainId = MONAD_MAINNET_ID;

// Smart Account Configuration with Gas Sponsorship
// Using EIP-7702 execution mode for gasless transactions
export const accountAbstractionConfig = {
  chain: currentChain,
  sponsorGas: true, // Enable gas sponsorship via Thirdweb Paymaster
};

/**
 * Wallet Execution Mode Configuration
 *
 * EIP-7702: For In-App Wallets (email, social, phone auth)
 * - Gas sponsorship enabled by default
 * - Same address as EOA
 *
 * ERC-4337: For Smart Contract Wallets
 * - Creates new smart account address
 * - Use for chains without EIP-7702 support
 */
export const walletExecutionConfig = {
  // EIP-7702 mode (recommended for most cases)
  eip7702: {
    mode: 'EIP7702' as const,
    sponsorGas: true,
  },
  // ERC-4337 mode (for smart contract wallets)
  erc4337: {
    mode: 'EIP4337' as const,
    smartAccount: {
      chain: currentChain,
      sponsorGas: true,
    },
  },
};

// Token addresses on Monad Mainnet
export const TOKENS_MAINNET = {
  WMON: '0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A',
  USDC: '0x754704Bc059F8C67012fEd69BC8A327a5aafb603',
};

export const TOKENS = TOKENS_MAINNET;
