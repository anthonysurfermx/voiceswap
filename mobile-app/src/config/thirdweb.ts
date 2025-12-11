/**
 * Thirdweb Configuration
 *
 * Setup for Smart Wallets with Gas Sponsorship on Unichain
 */

import { createThirdwebClient } from 'thirdweb';
import { defineChain } from 'thirdweb/chains';

// Thirdweb Client
export const client = createThirdwebClient({
  clientId: process.env.EXPO_PUBLIC_THIRDWEB_CLIENT_ID!,
});

// Unichain Mainnet (Chain ID: 130)
export const unichainMainnet = defineChain({
  id: 130,
  name: 'Unichain',
  nativeCurrency: {
    name: 'Ether',
    symbol: 'ETH',
    decimals: 18,
  },
  rpc: 'https://mainnet.unichain.org',
  blockExplorers: [
    {
      name: 'Unichain Explorer',
      url: 'https://uniscan.xyz',
    },
  ],
  testnet: false,
});

// Unichain Sepolia Testnet (Chain ID: 1301)
export const unichainSepolia = defineChain({
  id: 1301,
  name: 'Unichain Sepolia',
  nativeCurrency: {
    name: 'Ether',
    symbol: 'ETH',
    decimals: 18,
  },
  rpc: 'https://sepolia.unichain.org',
  blockExplorers: [
    {
      name: 'Unichain Sepolia Explorer',
      url: 'https://sepolia.uniscan.xyz',
    },
  ],
  testnet: true,
});

// Current chain (based on environment)
export const currentChain =
  process.env.EXPO_PUBLIC_NETWORK === 'unichain'
    ? unichainMainnet
    : unichainSepolia;

// Smart Account Configuration
export const accountAbstractionConfig = {
  chain: currentChain,
  sponsorGas: true, // Enable gas sponsorship via Thirdweb Paymaster
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
