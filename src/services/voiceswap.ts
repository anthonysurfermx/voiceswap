/**
 * VoiceSwap Service
 *
 * Simplified flow for voice-activated payments:
 * 1. Scan QR code to get merchant wallet
 * 2. Detect user's token balances
 * 3. Swap to USDC if needed
 * 4. Transfer USDC to merchant
 *
 * Network: Unichain Mainnet (Chain ID: 130) or Sepolia (Chain ID: 1301)
 * Output Token: USDC only
 */

import { ethers } from 'ethers';

// Network Configuration - support both mainnet and sepolia
const IS_SEPOLIA = process.env.NETWORK === 'unichain-sepolia';
const UNICHAIN_RPC = IS_SEPOLIA
  ? (process.env.UNICHAIN_SEPOLIA_RPC_URL || 'https://sepolia.unichain.org')
  : (process.env.UNICHAIN_RPC_URL || 'https://mainnet.unichain.org');
const CHAIN_ID = IS_SEPOLIA ? 1301 : 130;

// Token Addresses - different on mainnet vs sepolia
const TOKENS_MAINNET = {
  USDC: '0x078D782b760474a361dDA0AF3839290b0EF57AD6',
  WETH: '0x4200000000000000000000000000000000000006',
} as const;

// Sepolia tokens (may need to deploy test tokens or use existing ones)
const TOKENS_SEPOLIA = {
  USDC: '0x31d0220469e10c4E71834a79b1f276d740d3768F', // Unichain Sepolia USDC
  WETH: '0x4200000000000000000000000000000000000006', // WETH is same address
} as const;

const TOKENS = IS_SEPOLIA ? TOKENS_SEPOLIA : TOKENS_MAINNET;

console.log(`[VoiceSwap] Network: ${IS_SEPOLIA ? 'Unichain Sepolia' : 'Unichain Mainnet'} (Chain ID: ${CHAIN_ID})`);

// ERC20 ABI (minimal)
const ERC20_ABI = [
  'function balanceOf(address) view returns (uint256)',
  'function decimals() view returns (uint8)',
  'function symbol() view returns (string)',
  'function transfer(address to, uint256 amount) returns (bool)',
  'function approve(address spender, uint256 amount) returns (bool)',
];

// Provider
const provider = new ethers.providers.JsonRpcProvider(UNICHAIN_RPC);

/**
 * Token balance with metadata
 */
export interface TokenBalance {
  symbol: string;
  address: string;
  balance: string;
  balanceRaw: string;
  decimals: number;
  valueUSD?: string;
}

/**
 * User wallet balances
 */
export interface WalletBalances {
  address: string;
  chainId: number;
  nativeETH: TokenBalance;
  tokens: TokenBalance[];
  totalUSDC: string; // Total value if converted to USDC
}

/**
 * Payment request from QR code
 */
export interface PaymentRequest {
  merchantWallet: string;
  amount?: string; // Amount in USDC (optional, if not specified user chooses)
  merchantName?: string;
  orderId?: string;
}

/**
 * Payment result
 */
export interface PaymentResult {
  success: boolean;
  txHash?: string;
  amountUSDC: string;
  merchantWallet: string;
  error?: string;
}

/**
 * Parse QR code data to extract payment request
 *
 * Supported formats:
 * - Simple: "0x..." (just wallet address)
 * - JSON: {"wallet": "0x...", "amount": "10.00", "name": "Store"}
 * - URI: "unichain:0x...?amount=10.00&name=Store"
 */
export function parseQRCode(qrData: string): PaymentRequest | null {
  try {
    // Check if it's a simple Ethereum address
    if (qrData.match(/^0x[a-fA-F0-9]{40}$/)) {
      return {
        merchantWallet: ethers.utils.getAddress(qrData),
      };
    }

    // Check if it's JSON
    if (qrData.startsWith('{')) {
      const data = JSON.parse(qrData);
      if (!data.wallet || !ethers.utils.isAddress(data.wallet)) {
        return null;
      }
      return {
        merchantWallet: ethers.utils.getAddress(data.wallet),
        amount: data.amount,
        merchantName: data.name || data.merchantName,
        orderId: data.orderId,
      };
    }

    // Check if it's a URI format (voiceswap:0x... or unichain:0x...)
    const uriMatch = qrData.match(/^(?:voiceswap|unichain):([0-9a-fA-Fx]+)(?:\?(.*))?$/);
    if (uriMatch) {
      const wallet = uriMatch[1];
      if (!ethers.utils.isAddress(wallet)) {
        return null;
      }

      const params = new URLSearchParams(uriMatch[2] || '');
      return {
        merchantWallet: ethers.utils.getAddress(wallet),
        amount: params.get('amount') || undefined,
        merchantName: params.get('name') || undefined,
        orderId: params.get('orderId') || undefined,
      };
    }

    // Check if wallet address is embedded in text
    const addressMatch = qrData.match(/0x[a-fA-F0-9]{40}/);
    if (addressMatch) {
      return {
        merchantWallet: ethers.utils.getAddress(addressMatch[0]),
      };
    }

    return null;
  } catch (error) {
    console.error('[VoiceSwap] Failed to parse QR code:', error);
    return null;
  }
}

/**
 * Get wallet balances for a user on Unichain
 * Returns ETH, WETH, and USDC balances
 */
export async function getWalletBalances(userAddress: string): Promise<WalletBalances> {
  const checksumAddress = ethers.utils.getAddress(userAddress);

  // Get native ETH balance
  const ethBalance = await provider.getBalance(checksumAddress);

  // Get WETH balance
  const wethContract = new ethers.Contract(TOKENS.WETH, ERC20_ABI, provider);
  const wethBalance = await wethContract.balanceOf(checksumAddress);

  // Get USDC balance
  const usdcContract = new ethers.Contract(TOKENS.USDC, ERC20_ABI, provider);
  const usdcBalance = await usdcContract.balanceOf(checksumAddress);

  // Format balances
  const ethFormatted = ethers.utils.formatEther(ethBalance);
  const wethFormatted = ethers.utils.formatEther(wethBalance);
  const usdcFormatted = ethers.utils.formatUnits(usdcBalance, 6);

  return {
    address: checksumAddress,
    chainId: CHAIN_ID,
    nativeETH: {
      symbol: 'ETH',
      address: ethers.constants.AddressZero,
      balance: ethFormatted,
      balanceRaw: ethBalance.toString(),
      decimals: 18,
    },
    tokens: [
      {
        symbol: 'WETH',
        address: TOKENS.WETH,
        balance: wethFormatted,
        balanceRaw: wethBalance.toString(),
        decimals: 18,
      },
      {
        symbol: 'USDC',
        address: TOKENS.USDC,
        balance: usdcFormatted,
        balanceRaw: usdcBalance.toString(),
        decimals: 6,
      },
    ],
    totalUSDC: usdcFormatted, // For now, just USDC balance (later we can add price conversion)
  };
}

/**
 * Determine which token to swap based on user's balances
 * Priority: USDC (no swap needed) > WETH > ETH
 */
export function determineSwapToken(balances: WalletBalances, amountUSDC: string): {
  needsSwap: boolean;
  swapFrom?: string;
  swapFromSymbol?: string;
  hasEnoughUSDC: boolean;
  hasEnoughETH: boolean;
  hasEnoughWETH: boolean;
} {
  const requiredUSDC = parseFloat(amountUSDC);
  const currentUSDC = parseFloat(balances.tokens.find(t => t.symbol === 'USDC')?.balance || '0');
  const currentWETH = parseFloat(balances.tokens.find(t => t.symbol === 'WETH')?.balance || '0');
  const currentETH = parseFloat(balances.nativeETH.balance);

  // Minimum ETH to keep for gas
  const gasReserve = 0.001;

  return {
    needsSwap: currentUSDC < requiredUSDC,
    swapFrom: currentUSDC >= requiredUSDC ? undefined :
              currentWETH > 0 ? TOKENS.WETH :
              currentETH > gasReserve ? 'NATIVE_ETH' : undefined,
    swapFromSymbol: currentUSDC >= requiredUSDC ? undefined :
                    currentWETH > 0 ? 'WETH' :
                    currentETH > gasReserve ? 'ETH' : undefined,
    hasEnoughUSDC: currentUSDC >= requiredUSDC,
    hasEnoughETH: currentETH > gasReserve,
    hasEnoughWETH: currentWETH > 0,
  };
}

/**
 * Get the best available balance for payment
 * Used when no specific amount is requested
 */
export function getMaxPayableAmount(balances: WalletBalances): {
  tokenSymbol: string;
  tokenAddress: string;
  maxAmount: string;
  estimatedUSDC: string;
} {
  const usdcBalance = parseFloat(balances.tokens.find(t => t.symbol === 'USDC')?.balance || '0');

  // If user has USDC, use it directly
  if (usdcBalance > 0) {
    return {
      tokenSymbol: 'USDC',
      tokenAddress: TOKENS.USDC,
      maxAmount: usdcBalance.toFixed(2),
      estimatedUSDC: usdcBalance.toFixed(2),
    };
  }

  const wethBalance = parseFloat(balances.tokens.find(t => t.symbol === 'WETH')?.balance || '0');
  const ethBalance = parseFloat(balances.nativeETH.balance);

  // TODO: Get actual ETH/USDC price from Uniswap
  const ethPrice = 3900; // Placeholder

  if (wethBalance > 0) {
    return {
      tokenSymbol: 'WETH',
      tokenAddress: TOKENS.WETH,
      maxAmount: wethBalance.toFixed(6),
      estimatedUSDC: (wethBalance * ethPrice).toFixed(2),
    };
  }

  // Keep some ETH for gas
  const gasReserve = 0.001;
  const availableETH = Math.max(0, ethBalance - gasReserve);

  return {
    tokenSymbol: 'ETH',
    tokenAddress: ethers.constants.AddressZero,
    maxAmount: availableETH.toFixed(6),
    estimatedUSDC: (availableETH * ethPrice).toFixed(2),
  };
}

/**
 * Generate voice response for payment confirmation
 */
export function generateVoicePrompt(
  paymentRequest: PaymentRequest,
  _balances: WalletBalances,
  swapInfo: ReturnType<typeof determineSwapToken>
): string {
  const merchantName = paymentRequest.merchantName || 'the merchant';
  const amount = paymentRequest.amount || 'the full amount';

  if (swapInfo.hasEnoughUSDC || !swapInfo.needsSwap) {
    return `Ready to pay ${amount} USDC to ${merchantName}. Say "confirm" to proceed or "cancel" to stop.`;
  }

  if (swapInfo.swapFromSymbol) {
    return `You don't have enough USDC. I'll swap your ${swapInfo.swapFromSymbol} to USDC and pay ${amount} to ${merchantName}. Say "confirm" to proceed or "cancel" to stop.`;
  }

  return `Sorry, you don't have enough funds to complete this payment. You need more ETH or USDC on Unichain.`;
}

/**
 * Voice command confirmation system
 * Supported commands for confirming or canceling transactions
 */
export const VOICE_COMMANDS = {
  confirm: [
    // English
    'confirm',
    'yes',
    'do it',
    'execute',
    'send it',
    'go ahead',
    'approve',
    'ok',
    'okay',
    // Spanish
    'confirmar',
    'sí',
    'si',
    'hazlo',
    'ejecutar',
    'enviar',
    'dale',
    'adelante',
    'aprobar',
    'vale',
  ],
  cancel: [
    // English
    'cancel',
    'no',
    'stop',
    'abort',
    'never mind',
    'wait',
    // Spanish
    'cancelar',
    'no',
    'parar',
    'detener',
    'abortar',
    'espera',
  ],
} as const;

/**
 * Parse voice command to determine user intent
 */
export function parseVoiceCommand(transcript: string): 'confirm' | 'cancel' | 'unknown' {
  const normalized = transcript.toLowerCase().trim();

  // Check for confirmation commands
  for (const cmd of VOICE_COMMANDS.confirm) {
    if (normalized.includes(cmd)) {
      return 'confirm';
    }
  }

  // Check for cancel commands
  for (const cmd of VOICE_COMMANDS.cancel) {
    if (normalized.includes(cmd)) {
      return 'cancel';
    }
  }

  return 'unknown';
}

/**
 * Generate voice prompts for different states
 */
export const VOICE_PROMPTS = {
  // Payment preparation prompts
  readyToPayDirect: (amount: string, merchant: string) =>
    `Ready to pay ${amount} USDC to ${merchant}. Say "confirm" to proceed or "cancel" to stop.`,

  readyToPayWithSwap: (amount: string, fromToken: string, merchant: string) =>
    `I'll swap your ${fromToken} to ${amount} USDC and send it to ${merchant}. Say "confirm" to proceed or "cancel" to stop.`,

  insufficientFunds: () =>
    `Sorry, you don't have enough funds to complete this payment. You need more ETH or USDC on Unichain.`,

  // Confirmation prompts
  confirming: () =>
    `Processing your payment. Please wait...`,

  success: (amount: string, txHash: string) =>
    `Payment complete! ${amount} USDC sent successfully. Transaction hash: ${txHash.slice(0, 10)}.`,

  failed: (error: string) =>
    `Payment failed: ${error}. Please try again.`,

  // Cancel prompts
  cancelled: () =>
    `Payment cancelled. No funds were sent.`,

  // Error prompts
  invalidCommand: () =>
    `I didn't understand that. Say "confirm" to proceed or "cancel" to stop.`,

  qrNotFound: () =>
    `I couldn't detect a valid wallet address in the QR code. Please try scanning again.`,

  // Balance prompts
  balanceCheck: (eth: string, usdc: string) =>
    `Your balance on Unichain: ${eth} ETH and ${usdc} USDC.`,
};

/**
 * Payment state machine for voice flow
 */
export type PaymentState =
  | 'idle'           // No active payment
  | 'scanning'       // Scanning QR code
  | 'preparing'      // Checking balances
  | 'awaiting_confirm' // Waiting for voice confirmation
  | 'executing'      // Processing swap/transfer
  | 'success'        // Payment complete
  | 'failed'         // Payment failed
  | 'cancelled';     // User cancelled

/**
 * Payment session for tracking state
 */
export interface PaymentSession {
  id: string;
  state: PaymentState;
  userAddress: string;
  merchantWallet?: string;
  merchantName?: string;
  amount?: string;
  needsSwap: boolean;
  swapFromToken?: string;
  createdAt: number;
  updatedAt: number;
  txHash?: string;
  error?: string;
}

/**
 * Create a new payment session
 */
export function createPaymentSession(userAddress: string): PaymentSession {
  return {
    id: `pay_${Date.now()}_${Math.random().toString(36).substring(2, 11)}`,
    state: 'idle',
    userAddress,
    needsSwap: false,
    createdAt: Date.now(),
    updatedAt: Date.now(),
  };
}

/**
 * Update session state
 */
export function updateSessionState(
  session: PaymentSession,
  newState: PaymentState,
  updates: Partial<PaymentSession> = {}
): PaymentSession {
  return {
    ...session,
    ...updates,
    state: newState,
    updatedAt: Date.now(),
  };
}

// Export tokens config
export const SUPPORTED_TOKENS = TOKENS;
export const NETWORK_CONFIG = {
  chainId: CHAIN_ID,
  rpcUrl: UNICHAIN_RPC,
  name: 'Unichain Mainnet',
};
