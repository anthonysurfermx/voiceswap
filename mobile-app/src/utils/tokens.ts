/**
 * Token configuration for Monad
 */

// Monad Mainnet tokens
export const TOKENS_MAINNET = {
  WMON: '0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A',
  USDC: '0x754704Bc059F8C67012fEd69BC8A327a5aafb603',
} as const;

// Current network tokens
export const TOKENS = TOKENS_MAINNET;

// Token metadata
export const TOKEN_INFO: Record<string, { symbol: string; decimals: number; name: string }> = {
  [TOKENS.WMON]: { symbol: 'WMON', decimals: 18, name: 'Wrapped Monad' },
  [TOKENS.USDC]: { symbol: 'USDC', decimals: 6, name: 'USD Coin' },
};

// Voice command aliases -> token addresses
export const TOKEN_ALIASES: Record<string, string> = {
  // MON variants
  mon: TOKENS.WMON,
  monad: TOKENS.WMON,
  wmon: TOKENS.WMON,
  'wrapped monad': TOKENS.WMON,
  'wrapped mon': TOKENS.WMON,

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
