import { Token } from '@uniswap/sdk-core';

// Network IDs
export const CHAIN_IDS = {
  UNICHAIN_MAINNET: 130,
  UNICHAIN_SEPOLIA: 1301,
} as const;

// Uniswap V4 Contract Addresses on Unichain
export const UNISWAP_V4_CONTRACTS = {
  [CHAIN_IDS.UNICHAIN_MAINNET]: {
    POOL_MANAGER: '0x1f98400000000000000000000000000000000004',
    UNIVERSAL_ROUTER: '0xef740bf23acae26f6492b10de645d6b98dc8eaf3',
    QUOTER: '0x333e3c607b141b18ff6de9f258db6e77fe7491e0',
    POSITION_MANAGER: '0x4529a01c7a0410167c5740c487a8de60232617bf',
    STATE_VIEW: '0x86e8631a016f9068c3f085faf484ee3f5fdee8f2',
    PERMIT2: '0x000000000022D473030F116dDEE9F6B43aC78BA3',
  },
  [CHAIN_IDS.UNICHAIN_SEPOLIA]: {
    POOL_MANAGER: '0x00B036B58a818B1BC34d502D3fE730Db729e62AC',
    UNIVERSAL_ROUTER: '0xf70536B3bcC1bD1a972dc186A2cf84cC6da6Be5D',
    QUOTER: '0x6687DB12db706dfd1Ad4C394a4F1053BBe4349e8',
    POSITION_MANAGER: '0x9149D1DB249A4CCe622989829e7886b72cF95B9D',
    STATE_VIEW: '0xc199F1072a74D4e905ABa1A84d9a45E2546B6222',
    PERMIT2: '0x000000000022D473030F116dDEE9F6B43aC78BA3',
  },
} as const;

// Common tokens on Unichain Mainnet
export const TOKENS_UNICHAIN_MAINNET = {
  WETH: new Token(
    CHAIN_IDS.UNICHAIN_MAINNET,
    '0x4200000000000000000000000000000000000006',
    18,
    'WETH',
    'Wrapped Ether'
  ),
  USDC: new Token(
    CHAIN_IDS.UNICHAIN_MAINNET,
    '0x078D782b760474a361dDA0AF3839290b0EF57AD6',
    6,
    'USDC',
    'USD Coin'
  ),
} as const;

// Common tokens on Unichain Sepolia (testnet)
export const TOKENS_UNICHAIN_SEPOLIA = {
  WETH: new Token(
    CHAIN_IDS.UNICHAIN_SEPOLIA,
    '0x4200000000000000000000000000000000000006',
    18,
    'WETH',
    'Wrapped Ether'
  ),
  USDC: new Token(
    CHAIN_IDS.UNICHAIN_SEPOLIA,
    '0x31d0220469e10c4E71834a79b1f276d740d3768F',
    6,
    'USDC',
    'USD Coin'
  ),
} as const;

// x402 Pricing for our endpoints
export const ENDPOINT_PRICES = {
  '/quote': '$0.001',      // Get a quote
  '/route': '$0.005',      // Calculate optimal route
  '/execute': '$0.02',     // Execute swap on-chain
  '/status/:txHash': '$0.001', // Check transaction status
} as const;

// Pool fee tiers and their corresponding tick spacings in Uniswap V4
export const FEE_TIERS = {
  LOWEST: { fee: 100, tickSpacing: 1 },     // 0.01%
  LOW: { fee: 500, tickSpacing: 10 },       // 0.05%
  MEDIUM: { fee: 3000, tickSpacing: 60 },   // 0.30%
  HIGH: { fee: 10000, tickSpacing: 200 },   // 1.00%
} as const;

export type NetworkType = 'unichain' | 'unichain-sepolia';

export const getNetworkConfig = (network: NetworkType) => {
  const isMainnet = network === 'unichain';
  const chainId = isMainnet ? CHAIN_IDS.UNICHAIN_MAINNET : CHAIN_IDS.UNICHAIN_SEPOLIA;

  return {
    chainId,
    isMainnet,
    contracts: UNISWAP_V4_CONTRACTS[chainId],
    tokens: isMainnet ? TOKENS_UNICHAIN_MAINNET : TOKENS_UNICHAIN_SEPOLIA,
    rpcUrl: isMainnet
      ? process.env.UNICHAIN_RPC_URL || 'https://mainnet.unichain.org'
      : process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org',
  };
};
