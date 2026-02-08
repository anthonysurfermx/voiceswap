import { Token } from '@uniswap/sdk-core';

// Network IDs
export const CHAIN_IDS = {
  MONAD_MAINNET: 143,
} as const;

// Uniswap V3 Contract Addresses on Monad
export const UNISWAP_V3_CONTRACTS = {
  [CHAIN_IDS.MONAD_MAINNET]: {
    FACTORY: '0x204faca1764b154221e35c0d20abb3c525710498',
    SWAP_ROUTER_02: '0xfe31f71c1b106eac32f1a19239c9a9a72ddfb900',
    UNIVERSAL_ROUTER: '0x0d97dc33264bfc1c226207428a79b26757fb9dc3',
    QUOTER_V2: '0x661e93cca42afacb172121ef892830ca3b70f08d',
    POSITION_MANAGER: '0x7197e214c0b767cfb76fb734ab638e2c192f4e53',
    PERMIT2: '0x000000000022D473030F116dDEE9F6B43aC78BA3',
  },
} as const;

// Common tokens on Monad Mainnet
export const TOKENS_MONAD_MAINNET = {
  WMON: new Token(
    CHAIN_IDS.MONAD_MAINNET,
    '0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A',
    18,
    'WMON',
    'Wrapped Monad'
  ),
  USDC: new Token(
    CHAIN_IDS.MONAD_MAINNET,
    '0x754704Bc059F8C67012fEd69BC8A327a5aafb603',
    6,
    'USDC',
    'USD Coin'
  ),
} as const;

// Pool fee tiers for Uniswap V3
export const FEE_TIERS = {
  LOWEST: { fee: 100 },    // 0.01%
  LOW: { fee: 500 },       // 0.05%
  MEDIUM: { fee: 3000 },   // 0.30%
  HIGH: { fee: 10000 },    // 1.00%
} as const;

export type NetworkType = 'monad';

export const getNetworkConfig = (network: NetworkType = 'monad') => {
  const chainId = CHAIN_IDS.MONAD_MAINNET;

  return {
    chainId,
    isMainnet: true,
    contracts: UNISWAP_V3_CONTRACTS[chainId],
    tokens: TOKENS_MONAD_MAINNET,
    rpcUrl: process.env.MONAD_RPC_URL || 'https://rpc.monad.xyz',
  };
};
