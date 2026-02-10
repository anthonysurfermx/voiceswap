/**
 * Price Oracle Service
 *
 * Fetches real-time MON (Monad) prices from multiple sources with caching
 */

interface PriceCache {
  price: number;
  timestamp: number;
}

// Cache duration: 60 seconds
const CACHE_DURATION_MS = 60 * 1000;
let monPriceCache: PriceCache | null = null;

/**
 * Get MON price in USD from CoinGecko
 */
async function fetchFromCoinGecko(): Promise<number | null> {
  try {
    const response = await fetch(
      'https://api.coingecko.com/api/v3/simple/price?ids=monad&vs_currencies=usd',
      { headers: { 'Accept': 'application/json' } }
    );

    if (!response.ok) {
      console.warn('[PriceOracle] CoinGecko API error:', response.status);
      return null;
    }

    const data = await response.json() as { monad?: { usd?: number } };
    return data.monad?.usd ?? null;
  } catch (error) {
    console.warn('[PriceOracle] CoinGecko fetch failed:', error);
    return null;
  }
}

/**
 * Get MON price in USD from DeFiLlama
 */
async function fetchFromDeFiLlama(): Promise<number | null> {
  try {
    const response = await fetch(
      'https://coins.llama.fi/prices/current/coingecko:monad',
      { headers: { 'Accept': 'application/json' } }
    );

    if (!response.ok) {
      console.warn('[PriceOracle] DeFiLlama API error:', response.status);
      return null;
    }

    const data = await response.json() as { coins?: { 'coingecko:monad'?: { price?: number } } };
    return data.coins?.['coingecko:monad']?.price ?? null;
  } catch (error) {
    console.warn('[PriceOracle] DeFiLlama fetch failed:', error);
    return null;
  }
}

/**
 * Get current MON price in USD with caching and fallback
 */
export async function getMonPrice(): Promise<number> {
  // Check cache first
  if (monPriceCache && Date.now() - monPriceCache.timestamp < CACHE_DURATION_MS) {
    return monPriceCache.price;
  }

  // Try CoinGecko first
  let price = await fetchFromCoinGecko();

  // Fallback to DeFiLlama
  if (!price) {
    price = await fetchFromDeFiLlama();
  }

  // Fallback to hardcoded if all APIs fail
  if (!price) {
    console.warn('[PriceOracle] All APIs failed, using fallback MON price');
    price = 0.40; // Conservative fallback for MON
  }

  // Update cache
  monPriceCache = {
    price,
    timestamp: Date.now(),
  };

  console.log(`[PriceOracle] MON price: $${price.toFixed(4)}`);
  return price;
}

// Keep backward-compatible alias
export const getEthPrice = getMonPrice;

/**
 * Convert MON amount to USD
 */
export async function monToUsd(monAmount: number): Promise<number> {
  const price = await getMonPrice();
  return monAmount * price;
}

/**
 * Convert USD amount to MON
 */
export async function usdToMon(usdAmount: number): Promise<number> {
  const price = await getMonPrice();
  return usdAmount / price;
}

// Keep backward-compatible aliases
export const ethToUsd = monToUsd;
export const usdToEth = usdToMon;

/**
 * Get price info for API response
 */
export async function getPriceInfo(): Promise<{
  monPriceUSD: number;
  ethPriceUSD: number;
  source: string;
  cachedAt: string;
  cacheAge: number;
}> {
  const price = await getMonPrice();
  return {
    monPriceUSD: price,
    ethPriceUSD: price, // backward compat
    source: 'coingecko/defillama',
    cachedAt: monPriceCache ? new Date(monPriceCache.timestamp).toISOString() : new Date().toISOString(),
    cacheAge: monPriceCache ? Math.floor((Date.now() - monPriceCache.timestamp) / 1000) : 0,
  };
}
