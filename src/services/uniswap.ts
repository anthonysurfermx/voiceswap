import { ethers } from 'ethers';
import { getNetworkConfig, FEE_TIERS, type NetworkType } from '../config/networks.js';
import type { QuoteResponse, RouteResponse, ExecuteResponse, StatusResponse } from '../types/api.js';

// V4 Quoter ABI
const V4_QUOTER_ABI = [
  'function quoteExactInputSingle((tuple(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks) poolKey, bool zeroForOne, uint128 exactAmount, bytes hookData)) external returns (uint256 amountOut, uint256 gasEstimate)',
];

// Simplified pool key struct ABI for encoding
const POOL_KEY_ABI = [
  'tuple(address currency0, address currency1, uint24 fee, int24 tickSpacing, address hooks)',
];

// Universal Router ABI
const UNIVERSAL_ROUTER_ABI = [
  'function execute(bytes commands, bytes[] inputs, uint256 deadline) external payable returns (bytes[] memory)',
];

// ERC20 ABI
const ERC20_ABI = [
  'function symbol() view returns (string)',
  'function decimals() view returns (uint8)',
  'function name() view returns (string)',
  'function balanceOf(address) view returns (uint256)',
  'function approve(address spender, uint256 amount) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)',
];

// StateView ABI (for reading pool state)
const STATE_VIEW_ABI = [
  'function getSlot0(bytes32 poolId) external view returns (uint160 sqrtPriceX96, int24 tick, uint8 protocolFee, uint24 lpFee)',
  'function getLiquidity(bytes32 poolId) external view returns (uint128 liquidity)',
];

// V4 Actions enum values
const Actions = {
  SWAP_EXACT_IN_SINGLE: 0x06,
  SETTLE_ALL: 0x0c,
  TAKE_ALL: 0x0d,
} as const;

// Universal Router command types
const CommandType = {
  V4_SWAP: 0x10,
} as const;

// PoolKey interface for V4
interface PoolKey {
  currency0: string;
  currency1: string;
  fee: number;
  tickSpacing: number;
  hooks: string;
}

export class UniswapService {
  private provider: ethers.providers.JsonRpcProvider;
  private networkConfig: ReturnType<typeof getNetworkConfig>;
  private wallet?: ethers.Wallet;

  constructor(network: NetworkType = 'unichain-sepolia') {
    this.networkConfig = getNetworkConfig(network);
    this.provider = new ethers.providers.JsonRpcProvider(this.networkConfig.rpcUrl);

    // Initialize wallet if private key is provided (for executing swaps)
    if (process.env.RELAYER_PRIVATE_KEY) {
      this.wallet = new ethers.Wallet(process.env.RELAYER_PRIVATE_KEY, this.provider);
    }
  }

  /**
   * Get token info from contract
   */
  async getTokenInfo(address: string): Promise<{ symbol: string; decimals: number; name: string }> {
    const contract = new ethers.Contract(address, ERC20_ABI, this.provider);
    const [symbol, decimals, name] = await Promise.all([
      contract.symbol(),
      contract.decimals(),
      contract.name(),
    ]);
    return { symbol, decimals, name };
  }

  /**
   * Sort tokens to get currency0 < currency1 (required for V4)
   */
  private sortTokens(tokenA: string, tokenB: string): { currency0: string; currency1: string; zeroForOne: boolean } {
    const addressA = tokenA.toLowerCase();
    const addressB = tokenB.toLowerCase();

    if (addressA < addressB) {
      return { currency0: tokenA, currency1: tokenB, zeroForOne: true };
    } else {
      return { currency0: tokenB, currency1: tokenA, zeroForOne: false };
    }
  }

  /**
   * Build a PoolKey for the token pair
   */
  private buildPoolKey(tokenIn: string, tokenOut: string, feeTier: { fee: number; tickSpacing: number } = FEE_TIERS.MEDIUM): PoolKey {
    const { currency0, currency1 } = this.sortTokens(tokenIn, tokenOut);

    return {
      currency0,
      currency1,
      fee: feeTier.fee,
      tickSpacing: feeTier.tickSpacing,
      hooks: ethers.constants.AddressZero, // No hooks for standard pools
    };
  }

  /**
   * Calculate Pool ID from PoolKey (keccak256 of encoded PoolKey)
   */
  private getPoolId(poolKey: PoolKey): string {
    const abiCoder = new ethers.utils.AbiCoder();
    const encoded = abiCoder.encode(
      ['address', 'address', 'uint24', 'int24', 'address'],
      [poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks]
    );
    return ethers.utils.keccak256(encoded);
  }

  /**
   * Find the best pool for the pair by checking liquidity across tiers
   */
  private async findBestPool(tokenIn: string, tokenOut: string): Promise<PoolKey> {
    const stateView = new ethers.Contract(
      this.networkConfig.contracts.STATE_VIEW,
      STATE_VIEW_ABI,
      this.provider
    );

    let bestPoolKey: PoolKey | null = null;
    let maxLiquidity = ethers.BigNumber.from(0);

    // Check all fee tiers
    const tiers = Object.values(FEE_TIERS);

    await Promise.all(tiers.map(async (tier) => {
      try {
        const poolKey = this.buildPoolKey(tokenIn, tokenOut, tier);
        const poolId = this.getPoolId(poolKey);

        // Check if pool has liquidity
        const liquidity = await stateView.getLiquidity(poolId);

        if (liquidity.gt(maxLiquidity)) {
          maxLiquidity = liquidity;
          bestPoolKey = poolKey;
        }
      } catch (error) {
        // Pool might not exist or error fetching, ignore
        // console.debug(`Failed to check pool for tier ${tier.fee}`, error);
      }
    }));

    if (!bestPoolKey) {
      // Default to MEDIUM if no liquidity found anywhere (fallback)
      return this.buildPoolKey(tokenIn, tokenOut, FEE_TIERS.MEDIUM);
    }

    return bestPoolKey;
  }

  /**
   * Compute Price Impact
   */
  private async calculatePriceImpact(
    poolKey: PoolKey,
    amountIn: ethers.BigNumber,
    amountOut: ethers.BigNumber,
    tokenInDecimals: number,
    tokenOutDecimals: number,
    zeroForOne: boolean
  ): Promise<number> {
    try {
      const stateView = new ethers.Contract(
        this.networkConfig.contracts.STATE_VIEW,
        STATE_VIEW_ABI,
        this.provider
      );

      const poolId = this.getPoolId(poolKey);
      const slot0 = await stateView.getSlot0(poolId);
      const sqrtPriceX96 = slot0.sqrtPriceX96;

      // Calculate spot price from sqrtPriceX96
      // price = (sqrtPriceX96 / 2^96)^2
      const Q96 = ethers.BigNumber.from(2).pow(96);

      // We calculate prices with high precision
      // Execution Price = amountOut / amountIn
      const executionPrice = parseFloat(ethers.utils.formatUnits(amountOut, tokenOutDecimals)) /
        parseFloat(ethers.utils.formatUnits(amountIn, tokenInDecimals));

      // Spot Price calculation
      // If zeroForOne (Token0 -> Token1), price is Token1/Token0
      // If oneForZero (Token1 -> Token0), price is Token0/Token1 = 1 / (Token1/Token0)

      // Calculate Token1/Token0 price
      // price = (sqrtPrice / Q96) ** 2
      // To improve precision handling with BN, we can use a library or simplified float math for estimation
      const sqrtPriceFloat = parseFloat(sqrtPriceX96.toString()) / parseFloat(Q96.toString());
      const rawPrice = sqrtPriceFloat * sqrtPriceFloat;

      // Adjust for decimal difference: price * 10^(decimals0 - decimals1)
      const decimals0 = zeroForOne ? tokenInDecimals : tokenOutDecimals;
      const decimals1 = zeroForOne ? tokenOutDecimals : tokenInDecimals;
      const spotPriceToken1PerToken0 = rawPrice * Math.pow(10, decimals0 - decimals1);

      let spotPrice;
      if (zeroForOne) {
        // We are selling Token0 (In) for Token1 (Out) -> we want Price of Token0 in terms of Token1
        spotPrice = spotPriceToken1PerToken0;
      } else {
        // We are selling Token1 (In) for Token0 (Out) -> we want Price of Token1 in terms of Token0
        spotPrice = 1 / spotPriceToken1PerToken0;
      }

      // Price Impact = (Spot Price - Execution Price) / Spot Price
      const impact = (spotPrice - executionPrice) / spotPrice;

      // Return percentage (e.g., 0.05 for 5%)
      // If negative (execution better than spot due to math/rounding), return 0
      return Math.max(0, impact);

    } catch (error) {
      console.warn('Failed to calculate price impact:', error);
      return 0.0; // Fallback
    }
  }

  /**
   * Get a quote for a swap using V4 Quoter
   */
  async getQuote(
    tokenInAddress: string,
    tokenOutAddress: string,
    amountIn: string
  ): Promise<QuoteResponse> {
    try {
      // Get token info
      const [tokenInInfo, tokenOutInfo] = await Promise.all([
        this.getTokenInfo(tokenInAddress),
        this.getTokenInfo(tokenOutAddress),
      ]);

      // Dynamically find the best pool
      const poolKey = await this.findBestPool(tokenInAddress, tokenOutAddress);
      const { zeroForOne } = this.sortTokens(tokenInAddress, tokenOutAddress);

      // Parse amount with correct decimals
      const amountInParsed = ethers.utils.parseUnits(amountIn, tokenInInfo.decimals);

      // Create quoter contract
      const quoter = new ethers.Contract(
        this.networkConfig.contracts.QUOTER,
        V4_QUOTER_ABI,
        this.provider
      );

      // Build quote params struct
      // The quoter expects the poolKey as a struct, not encoded bytes
      const quoteParams = {
        poolKey: {
          currency0: poolKey.currency0,
          currency1: poolKey.currency1,
          fee: poolKey.fee,
          tickSpacing: poolKey.tickSpacing,
          hooks: poolKey.hooks,
        },
        zeroForOne,
        exactAmount: amountInParsed,
        hookData: '0x',
      };

      let amountOut: ethers.BigNumber;
      let gasEstimate: ethers.BigNumber;

      try {
        // Call quoter using callStatic (doesn't modify state)
        const result = await quoter.callStatic.quoteExactInputSingle(quoteParams);
        amountOut = result.amountOut || result[0];
        gasEstimate = result.gasEstimate || result[1] || ethers.BigNumber.from(150000);
      } catch (error) {
        // Fallback for different ABI variations or errors
        throw new Error(`Quoter failed: ${(error as Error).message}`);
      }

      // Calculate REAL price impact
      const priceImpactRaw = await this.calculatePriceImpact(
        poolKey,
        amountInParsed,
        amountOut,
        tokenInInfo.decimals,
        tokenOutInfo.decimals,
        zeroForOne
      );

      return {
        tokenIn: {
          address: tokenInAddress,
          symbol: tokenInInfo.symbol,
          decimals: tokenInInfo.decimals,
          amount: amountIn,
          amountRaw: amountInParsed.toString(),
        },
        tokenOut: {
          address: tokenOutAddress,
          symbol: tokenOutInfo.symbol,
          decimals: tokenOutInfo.decimals,
          amount: ethers.utils.formatUnits(amountOut, tokenOutInfo.decimals),
          amountRaw: amountOut.toString(),
        },
        priceImpact: (priceImpactRaw * 100).toFixed(4), // Convert to percentage string
        route: [tokenInAddress, tokenOutAddress],
        estimatedGas: gasEstimate.toString(),
        timestamp: Date.now(),
      };
    } catch (e) {
      throw e;
    }
  }

  /**
   * Get route with calldata for execution via Universal Router
   */
  async getRoute(
    tokenInAddress: string,
    tokenOutAddress: string,
    amountIn: string,
    recipient: string,
    slippageTolerance: number = 0.5,
    deadlineMinutes: number = 30
  ): Promise<RouteResponse> {
    // First get the quote (this will now use findBestPool internally)
    const quote = await this.getQuote(tokenInAddress, tokenOutAddress, amountIn);

    // Calculate minimum amount out with slippage
    const amountOutMin = ethers.BigNumber.from(quote.tokenOut.amountRaw)
      .mul(10000 - Math.floor(slippageTolerance * 100))
      .div(10000);

    // Deadline timestamp
    const deadline = Math.floor(Date.now() / 1000) + deadlineMinutes * 60;

    // We must rebuild the pool key that matched the quote (best pool)
    const bestPoolKey = await this.findBestPool(tokenInAddress, tokenOutAddress);
    const { zeroForOne } = this.sortTokens(tokenInAddress, tokenOutAddress);

    // Encode V4 swap actions
    const calldata = this.encodeV4SwapCalldata(
      bestPoolKey,
      zeroForOne,
      ethers.BigNumber.from(quote.tokenIn.amountRaw),
      amountOutMin,
      recipient,
      deadline
    );

    return {
      ...quote,
      calldata,
      value: '0', // Only needed if swapping from native ETH
      to: this.networkConfig.contracts.UNIVERSAL_ROUTER,
      slippageTolerance,
      deadline,
    };
  }

  /**
   * Encode V4 swap calldata for Universal Router
   */
  private encodeV4SwapCalldata(
    poolKey: PoolKey,
    zeroForOne: boolean,
    amountIn: ethers.BigNumber,
    amountOutMin: ethers.BigNumber,
    recipient: string,
    deadline: number
  ): string {
    const abiCoder = new ethers.utils.AbiCoder();

    // Encode the actions sequence: SWAP_EXACT_IN_SINGLE, SETTLE_ALL, TAKE_ALL
    const actions = ethers.utils.hexConcat([
      ethers.utils.hexlify([Actions.SWAP_EXACT_IN_SINGLE]),
      ethers.utils.hexlify([Actions.SETTLE_ALL]),
      ethers.utils.hexlify([Actions.TAKE_ALL]),
    ]);

    // Encode parameters for each action
    // Action 1: SWAP_EXACT_IN_SINGLE params
    const swapParams = abiCoder.encode(
      ['tuple(tuple(address,address,uint24,int24,address),bool,uint128,uint128,bytes)'],
      [[
        [poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks],
        zeroForOne,
        amountIn,
        amountOutMin,
        '0x', // hookData
      ]]
    );

    // Action 2: SETTLE_ALL params (currency, maxAmount)
    const settleParams = abiCoder.encode(
      ['address', 'uint256'],
      [zeroForOne ? poolKey.currency0 : poolKey.currency1, amountIn]
    );

    // Action 3: TAKE_ALL params (currency, minAmount)
    const takeParams = abiCoder.encode(
      ['address', 'uint256'],
      [zeroForOne ? poolKey.currency1 : poolKey.currency0, amountOutMin]
    );

    // Combine all params
    const params = abiCoder.encode(
      ['bytes[]'],
      [[swapParams, settleParams, takeParams]]
    );

    // Encode the V4_SWAP command for Universal Router
    const commands = ethers.utils.hexlify([CommandType.V4_SWAP]);

    // Encode the V4 swap input (actions + params)
    const v4SwapInput = abiCoder.encode(
      ['bytes', 'bytes[]'],
      [actions, [swapParams, settleParams, takeParams]]
    );

    // Encode the full Universal Router execute call
    const universalRouterInterface = new ethers.utils.Interface(UNIVERSAL_ROUTER_ABI);
    return universalRouterInterface.encodeFunctionData('execute', [
      commands,
      [v4SwapInput],
      deadline,
    ]);
  }

  /**
   * Execute a swap (requires relayer wallet)
   */
  async executeSwap(
    tokenInAddress: string,
    tokenOutAddress: string,
    amountIn: string,
    recipient: string,
    slippageTolerance: number = 0.5
  ): Promise<ExecuteResponse> {
    if (!this.wallet) {
      throw new Error('Relayer wallet not configured. Set RELAYER_PRIVATE_KEY in environment.');
    }

    try {
      // Validation: Check ETH balance for gas
      const balance = await this.wallet.getBalance();
      const minBalance = ethers.utils.parseEther("0.001"); // Minimal buffer
      if (balance.lt(minBalance)) {
        throw new Error('Relayer wallet has insufficient ETH for gas');
      }

      // Get the route with calldata
      // NOTE: In production, you might want to re-check the quote here to ensure it hasn't expired or moved significantly
      const route = await this.getRoute(
        tokenInAddress,
        tokenOutAddress,
        amountIn,
        recipient,
        slippageTolerance
      );

      if (!route.calldata || !route.to) {
        throw new Error('Failed to generate swap calldata');
      }

      // Estimate gas
      const gasEstimate = await this.wallet.estimateGas({
        to: route.to,
        data: route.calldata,
        value: route.value,
      });

      // Add 20% buffer to gas estimate
      const gasLimit = gasEstimate.mul(120).div(100);

      // Send transaction
      const tx = await this.wallet.sendTransaction({
        to: route.to,
        data: route.calldata,
        value: route.value,
        gasLimit,
      });

      return {
        status: 'submitted',
        txHash: tx.hash,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Unknown error';
      console.error('Execute Error:', error);
      return {
        status: 'failed',
        error: message,
      };
    }
  }

  /**
   * Check transaction status
   */
  async getTransactionStatus(txHash: string): Promise<StatusResponse> {
    try {
      const receipt = await this.provider.getTransactionReceipt(txHash);

      if (!receipt) {
        // Transaction might be pending
        const tx = await this.provider.getTransaction(txHash);
        if (tx) {
          return {
            status: 'pending',
            txHash,
          };
        }
        return {
          status: 'not_found',
          txHash,
        };
      }

      const currentBlock = await this.provider.getBlockNumber();
      const confirmations = currentBlock - receipt.blockNumber;

      return {
        status: receipt.status === 1 ? 'confirmed' : 'failed',
        txHash,
        blockNumber: receipt.blockNumber,
        confirmations,
        gasUsed: receipt.gasUsed.toString(),
        effectiveGasPrice: receipt.effectiveGasPrice?.toString(),
      };
    } catch (error) {
      return {
        status: 'not_found',
        txHash,
      };
    }
  }
}

// Export singleton instance
let uniswapService: UniswapService | null = null;

export const getUniswapService = (network?: NetworkType): UniswapService => {
  if (!uniswapService) {
    uniswapService = new UniswapService(network || (process.env.NETWORK as NetworkType) || 'unichain-sepolia');
  }
  return uniswapService;
};
