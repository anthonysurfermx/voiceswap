import { ethers } from 'ethers';
import { getNetworkConfig, FEE_TIERS, type NetworkType } from '../config/networks.js';
import type { QuoteResponse, RouteResponse, ExecuteResponse, StatusResponse } from '../types/api.js';
import { multicall, encodeCall, decodeResult } from './multicall.js';

// Uniswap V3 QuoterV2 ABI
const QUOTER_V2_ABI = [
  'function quoteExactInputSingle(tuple(address tokenIn, address tokenOut, uint256 amountIn, uint24 fee, uint160 sqrtPriceLimitX96) params) external returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)',
];

// Uniswap V3 SwapRouter02 ABI
const SWAP_ROUTER_ABI = [
  'function exactInputSingle(tuple(address tokenIn, address tokenOut, uint24 fee, address recipient, uint256 amountIn, uint256 amountOutMinimum, uint160 sqrtPriceLimitX96) params) external payable returns (uint256 amountOut)',
  'function multicall(uint256 deadline, bytes[] data) external payable returns (bytes[] memory)',
];

// Uniswap V3 Factory ABI
const FACTORY_ABI = [
  'function getPool(address tokenA, address tokenB, uint24 fee) external view returns (address pool)',
];

// Uniswap V3 Pool ABI
const POOL_ABI = [
  'function slot0() external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked)',
  'function liquidity() external view returns (uint128)',
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

export class UniswapService {
  private provider: ethers.providers.JsonRpcProvider;
  private networkConfig: ReturnType<typeof getNetworkConfig>;
  private wallet?: ethers.Wallet;

  constructor(network: NetworkType = 'monad') {
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
   * Find the best pool for a token pair by checking liquidity across fee tiers
   * Uses Multicall3 to batch all pool lookups in a single RPC call
   */
  private async findBestPool(tokenIn: string, tokenOut: string): Promise<{ pool: string; fee: number }> {
    const factory = new ethers.Contract(
      this.networkConfig.contracts.FACTORY,
      FACTORY_ABI,
      this.provider
    );

    const tiers = Object.values(FEE_TIERS);

    // Get pool addresses for all fee tiers via multicall
    const factoryInterface = new ethers.utils.Interface(FACTORY_ABI);
    const calls = tiers.map(tier => ({
      target: this.networkConfig.contracts.FACTORY,
      allowFailure: true,
      callData: encodeCall(factoryInterface, 'getPool', [tokenIn, tokenOut, tier.fee]),
    }));

    try {
      const results = await multicall(this.provider, calls);

      // Find pools that exist (non-zero address)
      const poolAddresses: { address: string; fee: number }[] = [];
      results.forEach((result, index) => {
        if (result.success) {
          try {
            const [poolAddress] = decodeResult(factoryInterface, 'getPool', result.returnData);
            if (poolAddress !== ethers.constants.AddressZero) {
              poolAddresses.push({ address: poolAddress, fee: tiers[index].fee });
            }
          } catch {
            // Ignore decode errors
          }
        }
      });

      if (poolAddresses.length === 0) {
        // Default to MEDIUM fee tier
        return { pool: ethers.constants.AddressZero, fee: FEE_TIERS.MEDIUM.fee };
      }

      if (poolAddresses.length === 1) {
        return { pool: poolAddresses[0].address, fee: poolAddresses[0].fee };
      }

      // Check liquidity for each pool to find the best one
      const poolInterface = new ethers.utils.Interface(POOL_ABI);
      const liquidityCalls = poolAddresses.map(p => ({
        target: p.address,
        allowFailure: true,
        callData: encodeCall(poolInterface, 'liquidity', []),
      }));

      const liquidityResults = await multicall(this.provider, liquidityCalls);

      let bestPool = poolAddresses[0];
      let maxLiquidity = ethers.BigNumber.from(0);

      liquidityResults.forEach((result, index) => {
        if (result.success) {
          try {
            const [liquidity] = decodeResult(poolInterface, 'liquidity', result.returnData);
            if (liquidity.gt(maxLiquidity)) {
              maxLiquidity = liquidity;
              bestPool = poolAddresses[index];
            }
          } catch {
            // Ignore
          }
        }
      });

      return { pool: bestPool.address, fee: bestPool.fee };
    } catch (error) {
      console.warn('Multicall failed for pool lookup, falling back to MEDIUM tier:', error);
      const poolAddress = await factory.getPool(tokenIn, tokenOut, FEE_TIERS.MEDIUM.fee);
      return { pool: poolAddress, fee: FEE_TIERS.MEDIUM.fee };
    }
  }

  /**
   * Calculate price impact from quote results
   */
  private async calculatePriceImpact(
    poolAddress: string,
    amountIn: ethers.BigNumber,
    amountOut: ethers.BigNumber,
    tokenInDecimals: number,
    tokenOutDecimals: number,
    tokenIn: string,
    tokenOut: string
  ): Promise<number> {
    try {
      const pool = new ethers.Contract(poolAddress, POOL_ABI, this.provider);
      const slot0 = await pool.slot0();
      const sqrtPriceX96 = slot0.sqrtPriceX96;

      const Q96 = ethers.BigNumber.from(2).pow(96);
      const sqrtPriceFloat = parseFloat(sqrtPriceX96.toString()) / parseFloat(Q96.toString());
      const rawPrice = sqrtPriceFloat * sqrtPriceFloat;

      // Determine token ordering (V3 pools sort by address)
      const token0 = tokenIn.toLowerCase() < tokenOut.toLowerCase() ? tokenIn : tokenOut;
      const isToken0In = token0.toLowerCase() === tokenIn.toLowerCase();

      const decimals0 = isToken0In ? tokenInDecimals : tokenOutDecimals;
      const decimals1 = isToken0In ? tokenOutDecimals : tokenInDecimals;
      const spotPriceToken1PerToken0 = rawPrice * Math.pow(10, decimals0 - decimals1);

      const executionPrice = parseFloat(ethers.utils.formatUnits(amountOut, tokenOutDecimals)) /
        parseFloat(ethers.utils.formatUnits(amountIn, tokenInDecimals));

      let spotPrice: number;
      if (isToken0In) {
        spotPrice = spotPriceToken1PerToken0;
      } else {
        spotPrice = 1 / spotPriceToken1PerToken0;
      }

      const impact = (spotPrice - executionPrice) / spotPrice;
      return Math.max(0, impact);
    } catch (error) {
      console.warn('Failed to calculate price impact:', error);
      return 0.0;
    }
  }

  /**
   * Get a quote for a swap using V3 QuoterV2
   */
  async getQuote(
    tokenInAddress: string,
    tokenOutAddress: string,
    amountIn: string
  ): Promise<QuoteResponse> {
    try {
      const [tokenInInfo, tokenOutInfo] = await Promise.all([
        this.getTokenInfo(tokenInAddress),
        this.getTokenInfo(tokenOutAddress),
      ]);

      const { pool: poolAddress, fee } = await this.findBestPool(tokenInAddress, tokenOutAddress);
      const amountInParsed = ethers.utils.parseUnits(amountIn, tokenInInfo.decimals);

      const quoter = new ethers.Contract(
        this.networkConfig.contracts.QUOTER_V2,
        QUOTER_V2_ABI,
        this.provider
      );

      const quoteParams = {
        tokenIn: tokenInAddress,
        tokenOut: tokenOutAddress,
        amountIn: amountInParsed,
        fee: fee,
        sqrtPriceLimitX96: 0,
      };

      let amountOut: ethers.BigNumber;
      let gasEstimate: ethers.BigNumber;

      try {
        const result = await quoter.callStatic.quoteExactInputSingle(quoteParams);
        amountOut = result.amountOut || result[0];
        gasEstimate = result.gasEstimate || result[3] || ethers.BigNumber.from(150000);
      } catch (error) {
        throw new Error(`QuoterV2 failed: ${(error as Error).message}`);
      }

      const priceImpactRaw = poolAddress !== ethers.constants.AddressZero
        ? await this.calculatePriceImpact(
            poolAddress,
            amountInParsed,
            amountOut,
            tokenInInfo.decimals,
            tokenOutInfo.decimals,
            tokenInAddress,
            tokenOutAddress
          )
        : 0;

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
        priceImpact: (priceImpactRaw * 100).toFixed(4),
        route: [tokenInAddress, tokenOutAddress],
        estimatedGas: gasEstimate.toString(),
        timestamp: Date.now(),
      };
    } catch (e) {
      throw e;
    }
  }

  /**
   * Get route with calldata for execution via SwapRouter02
   */
  async getRoute(
    tokenInAddress: string,
    tokenOutAddress: string,
    amountIn: string,
    recipient: string,
    slippageTolerance: number = 0.5,
    deadlineMinutes: number = 30
  ): Promise<RouteResponse> {
    const quote = await this.getQuote(tokenInAddress, tokenOutAddress, amountIn);
    const { fee } = await this.findBestPool(tokenInAddress, tokenOutAddress);

    const amountOutMin = ethers.BigNumber.from(quote.tokenOut.amountRaw)
      .mul(10000 - Math.floor(slippageTolerance * 100))
      .div(10000);

    const deadline = Math.floor(Date.now() / 1000) + deadlineMinutes * 60;

    const routerInterface = new ethers.utils.Interface(SWAP_ROUTER_ABI);

    const swapParams = {
      tokenIn: tokenInAddress,
      tokenOut: tokenOutAddress,
      fee: fee,
      recipient: recipient,
      amountIn: ethers.BigNumber.from(quote.tokenIn.amountRaw),
      amountOutMinimum: amountOutMin,
      sqrtPriceLimitX96: 0,
    };

    const swapCalldata = routerInterface.encodeFunctionData('exactInputSingle', [swapParams]);

    // Wrap in multicall with deadline
    const calldata = routerInterface.encodeFunctionData('multicall', [
      deadline,
      [swapCalldata],
    ]);

    return {
      ...quote,
      calldata,
      value: '0',
      to: this.networkConfig.contracts.SWAP_ROUTER_02,
      slippageTolerance,
      deadline,
    };
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
      const balance = await this.wallet.getBalance();
      const minBalance = ethers.utils.parseEther("0.01");
      if (balance.lt(minBalance)) {
        throw new Error('Relayer wallet has insufficient MON for gas');
      }

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

      const gasEstimate = await this.wallet.estimateGas({
        to: route.to,
        data: route.calldata,
        value: route.value,
      });

      const gasLimit = gasEstimate.mul(120).div(100);

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
    uniswapService = new UniswapService(network || (process.env.NETWORK as NetworkType) || 'monad');
  }
  return uniswapService;
};
