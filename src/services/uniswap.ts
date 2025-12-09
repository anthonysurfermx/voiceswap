import { ethers } from 'ethers';
import { getNetworkConfig, FEE_TIERS, type NetworkType } from '../config/networks.js';
import type { QuoteResponse, RouteResponse, ExecuteResponse, StatusResponse } from '../types/api.js';

// V4 Quoter ABI
const V4_QUOTER_ABI = [
  'function quoteExactInputSingle((address poolKey, bool zeroForOne, uint128 exactAmount, bytes hookData)) external returns (uint256 amountOut, uint256 gasEstimate)',
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
  private buildPoolKey(tokenIn: string, tokenOut: string, feeTier: typeof FEE_TIERS.MEDIUM = FEE_TIERS.MEDIUM): PoolKey {
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
   * Encode PoolKey for contract calls
   */
  private encodePoolKey(poolKey: PoolKey): string {
    const abiCoder = new ethers.utils.AbiCoder();
    return abiCoder.encode(
      ['tuple(address,address,uint24,int24,address)'],
      [[poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks]]
    );
  }

  /**
   * Get a quote for a swap using V4 Quoter
   */
  async getQuote(
    tokenInAddress: string,
    tokenOutAddress: string,
    amountIn: string
  ): Promise<QuoteResponse> {
    // Get token info
    const [tokenInInfo, tokenOutInfo] = await Promise.all([
      this.getTokenInfo(tokenInAddress),
      this.getTokenInfo(tokenOutAddress),
    ]);

    // Sort tokens and determine swap direction
    const { zeroForOne } = this.sortTokens(tokenInAddress, tokenOutAddress);
    const poolKey = this.buildPoolKey(tokenInAddress, tokenOutAddress);

    // Parse amount with correct decimals
    const amountInParsed = ethers.utils.parseUnits(amountIn, tokenInInfo.decimals);

    // Create quoter contract
    const quoter = new ethers.Contract(
      this.networkConfig.contracts.QUOTER,
      V4_QUOTER_ABI,
      this.provider
    );

    // Encode the quote params
    const abiCoder = new ethers.utils.AbiCoder();
    const encodedPoolKey = abiCoder.encode(
      ['tuple(address,address,uint24,int24,address)'],
      [[poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks]]
    );

    // Build quote params struct
    const quoteParams = {
      poolKey: encodedPoolKey,
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
      // Fallback: try alternative quoter interface
      // V4 Quoter might have different param structure depending on version
      const altQuoterABI = [
        'function quoteExactInputSingle(tuple(tuple(address,address,uint24,int24,address) poolKey, bool zeroForOne, uint128 exactAmount, bytes hookData) params) external returns (uint256 amountOut, uint256 gasEstimate)',
      ];

      const altQuoter = new ethers.Contract(
        this.networkConfig.contracts.QUOTER,
        altQuoterABI,
        this.provider
      );

      const altParams = {
        poolKey: [poolKey.currency0, poolKey.currency1, poolKey.fee, poolKey.tickSpacing, poolKey.hooks],
        zeroForOne,
        exactAmount: amountInParsed,
        hookData: '0x',
      };

      const result = await altQuoter.callStatic.quoteExactInputSingle(altParams);
      amountOut = result.amountOut || result[0];
      gasEstimate = result.gasEstimate || result[1] || ethers.BigNumber.from(150000);
    }

    // Calculate price impact (simplified)
    const priceImpact = this.calculatePriceImpact(amountInParsed, amountOut, tokenInInfo.decimals, tokenOutInfo.decimals);

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
      priceImpact: priceImpact.toFixed(4),
      route: [tokenInAddress, tokenOutAddress],
      estimatedGas: gasEstimate.toString(),
      timestamp: Date.now(),
    };
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
    // First get the quote
    const quote = await this.getQuote(tokenInAddress, tokenOutAddress, amountIn);

    // Calculate minimum amount out with slippage
    const amountOutMin = ethers.BigNumber.from(quote.tokenOut.amountRaw)
      .mul(10000 - Math.floor(slippageTolerance * 100))
      .div(10000);

    // Deadline timestamp
    const deadline = Math.floor(Date.now() / 1000) + deadlineMinutes * 60;

    // Build pool key and determine swap direction
    const { zeroForOne } = this.sortTokens(tokenInAddress, tokenOutAddress);
    const poolKey = this.buildPoolKey(tokenInAddress, tokenOutAddress);

    // Encode V4 swap actions
    const calldata = this.encodeV4SwapCalldata(
      poolKey,
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
      // Get the route with calldata
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

  /**
   * Calculate approximate price impact
   */
  private calculatePriceImpact(
    amountIn: ethers.BigNumber,
    amountOut: ethers.BigNumber,
    decimalsIn: number,
    decimalsOut: number
  ): number {
    // Simplified price impact calculation
    // In production, you'd compare against the pool's spot price
    return 0.1; // Placeholder - actual implementation would query pool state
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
