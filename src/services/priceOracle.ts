/**
 * Price Oracle Service
 *
 * Fetches real-time ETH prices from multiple sources with caching
 */

interface PriceCache {
  price: number;
  timestamp: number;
}

// Cache duration: 60 seconds
const CACHE_DURATION_MS = 60 * 1000;
let ethPriceCache: PriceCache | null = null;

/**
 * Get ETH price in USD from CoinGecko
 */
async function fetchFromCoinGecko(): Promise<number | null> {
  try {
    const response = await fetch(
      'https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd',
      { headers: { 'Accept': 'application/json' } }
    );

    if (!response.ok) {
      console.warn('[PriceOracle] CoinGecko API error:', response.status);
      return null;
    }

    const data = await response.json() as { ethereum?: { usd?: number } };
    return data.ethereum?.usd ?? null;
  } catch (error) {
    console.warn('[PriceOracle] CoinGecko fetch failed:', error);
    return null;
  }
}

/**
 * Get ETH price in USD from Uniswap via DeFiLlama
 */
async function fetchFromDeFiLlama(): Promise<number | null> {
  try {
    const response = await fetch(
      'https://coins.llama.fi/prices/current/coingecko:ethereum',
      { headers: { 'Accept': 'application/json' } }
    );

    if (!response.ok) {
      console.warn('[PriceOracle] DeFiLlama API error:', response.status);
      return null;
    }

    const data = await response.json() as { coins?: { 'coingecko:ethereum'?: { price?: number } } };
    return data.coins?.['coingecko:ethereum']?.price ?? null;
  } catch (error) {
    console.warn('[PriceOracle] DeFiLlama fetch failed:', error);
    return null;
  }
}

/**
 * Get current ETH price in USD with caching and fallback
 */
export async function getEthPrice(): Promise<number> {
  // Check cache first
  if (ethPriceCache && Date.now() - ethPriceCache.timestamp < CACHE_DURATION_MS) {
    return ethPriceCache.price;
  }

  // Try CoinGecko first
  let price = await fetchFromCoinGecko();

  // Fallback to DeFiLlama
  if (!price) {
    price = await fetchFromDeFiLlama();
  }

  // Fallback to hardcoded if all APIs fail
  if (!price) {
    console.warn('[PriceOracle] All APIs failed, using fallback price');
    price = 3500; // Conservative fallback
  }

  // Update cache
  ethPriceCache = {
    price,
    timestamp: Date.now(),
  };

  console.log(`[PriceOracle] ETH price: $${price.toFixed(2)}`);
  return price;
}

/**
 * Convert ETH amount to USD
 */
export async function ethToUsd(ethAmount: number): Promise<number> {
  const price = await getEthPrice();
  return ethAmount * price;
}

/**
 * Convert USD amount to ETH
 */
export async function usdToEth(usdAmount: number): Promise<number> {
  const price = await getEthPrice();
  return usdAmount / price;
}

/**
 * Get price info for API response
 */
export async function getPriceInfo(): Promise<{
  ethPriceUSD: number;
  source: string;
  cachedAt: string;
  cacheAge: number;
}> {
  const price = await getEthPrice();
  return {
    ethPriceUSD: price,
    source: 'coingecko/defillama',
    cachedAt: ethPriceCache ? new Date(ethPriceCache.timestamp).toISOString() : new Date().toISOString(),
    cacheAge: ethPriceCache ? Math.floor((Date.now() - ethPriceCache.timestamp) / 1000) : 0,
  };
}
