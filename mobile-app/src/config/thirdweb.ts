/**
 * Thirdweb Configuration
 *
 * Setup for Smart Wallets with Gas Sponsorship on Unichain
 * Using EIP-7702 for gasless transactions
 */

import { createThirdwebClient } from 'thirdweb';
import { defineChain } from 'thirdweb/chains';

// Thirdweb Client
export const client = createThirdwebClient({
  clientId: process.env.EXPO_PUBLIC_THIRDWEB_CLIENT_ID!,
});

// Chain IDs
export const UNICHAIN_MAINNET_ID = 130;
export const UNICHAIN_SEPOLIA_ID = 1301;

// Unichain Mainnet (Chain ID: 130)
// Using defineChain with just the ID - Thirdweb will fetch chain details
export const unichainMainnet = defineChain(UNICHAIN_MAINNET_ID);

// Unichain Sepolia Testnet (Chain ID: 1301)
export const unichainSepolia = defineChain(UNICHAIN_SEPOLIA_ID);

// Current chain (based on environment)
export const currentChain =
  process.env.EXPO_PUBLIC_NETWORK === 'unichain'
    ? unichainMainnet
    : unichainSepolia;

// Current chain ID for easy access
export const currentChainId =
  process.env.EXPO_PUBLIC_NETWORK === 'unichain'
    ? UNICHAIN_MAINNET_ID
    : UNICHAIN_SEPOLIA_ID;

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

// Token addresses on Unichain Sepolia
export const TOKENS_SEPOLIA = {
  WETH: '0x4200000000000000000000000000000000000006',
  USDC: '0x31d0220469e10c4E71834a79b1f276d740d3768F',
};

// Token addresses on Unichain Mainnet
export const TOKENS_MAINNET = {
  WETH: '0x4200000000000000000000000000000000000006',
  USDC: '0x078D782b760474a361dDA0AF3839290b0EF57AD6',
};

export const TOKENS =
  process.env.EXPO_PUBLIC_NETWORK === 'unichain'
    ? TOKENS_MAINNET
    : TOKENS_SEPOLIA;
