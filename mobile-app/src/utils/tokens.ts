/**
 * Token configuration for Unichain
 */

// Unichain Mainnet tokens
export const TOKENS_MAINNET = {
  WETH: '0x4200000000000000000000000000000000000006',
  USDC: '0x078D782b760474a361dDA0AF3839290b0EF57AD6',
} as const;

// Unichain Sepolia (testnet) tokens
export const TOKENS_TESTNET = {
  WETH: '0x4200000000000000000000000000000000000006',
  USDC: '0x31d0220469e10c4E71834a79b1f276d740d3768F',
} as const;

// Current network tokens (change based on environment)
export const TOKENS = TOKENS_TESTNET;

// Token metadata
export const TOKEN_INFO: Record<string, { symbol: string; decimals: number; name: string }> = {
  [TOKENS.WETH]: { symbol: 'WETH', decimals: 18, name: 'Wrapped Ether' },
  [TOKENS.USDC]: { symbol: 'USDC', decimals: 6, name: 'USD Coin' },
};

// Voice command aliases -> token addresses
export const TOKEN_ALIASES: Record<string, string> = {
  // ETH variants
  eth: TOKENS.WETH,
  ether: TOKENS.WETH,
  ethereum: TOKENS.WETH,
  weth: TOKENS.WETH,
  'wrapped ether': TOKENS.WETH,
  'wrapped eth': TOKENS.WETH,

  // USDC variants
  usdc: TOKENS.USDC,
  usd: TOKENS.USDC,
  dollars: TOKENS.USDC,
  dollar: TOKENS.USDC,
  'usd coin': TOKENS.USDC,
  stablecoin: TOKENS.USDC,
  stable: TOKENS.USDC,
};

/**
 * Resolve a spoken token name to its address
 */
export function resolveToken(spoken: string): string | null {
  const normalized = spoken.toLowerCase().trim();

  // Direct alias match
  if (TOKEN_ALIASES[normalized]) {
    return TOKEN_ALIASES[normalized];
  }

  // Check if it's already an address
  if (normalized.startsWith('0x') && normalized.length === 42) {
    return normalized;
  }

  return null;
}

/**
 * Get token symbol from address
 */
export function getTokenSymbol(address: string): string {
  return TOKEN_INFO[address]?.symbol || 'UNKNOWN';
}

/**
 * Format token amount for display
 */
export function formatTokenAmount(amount: string, address: string): string {
  const info = TOKEN_INFO[address];
  if (!info) return amount;

  const num = parseFloat(amount);
  if (isNaN(num)) return amount;

  // Format based on value
  if (num < 0.0001) return num.toExponential(2);
  if (num < 1) return num.toFixed(6);
  if (num < 1000) return num.toFixed(4);
  return num.toLocaleString(undefined, { maximumFractionDigits: 2 });
}
