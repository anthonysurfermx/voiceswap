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
import { getEthPrice } from './priceOracle.js';

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
  totalUSDC: string; // USDC balance only
  totalUSD: string;  // Total value in USD (USDC + ETH converted)
  ethPriceUSD: number; // Current ETH price used for calculation
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
 * - Deep link: "voiceswap://pay?wallet=0x...&amount=10.00"
 * - EIP-681: "ethereum:0x...@130" or "ethereum:0x...@130/transfer?address=...&uint256=..."
 *   (Standard format used by Zerion, MetaMask, Rainbow, etc.)
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

    // Check if it's EIP-681 format (ethereum:0x...@chainId or ethereum:0x...@chainId/transfer?...)
    // This is the standard format used by Zerion, MetaMask, Rainbow, etc.
    // Examples:
    //   ethereum:0x1234...@130 (simple address on Unichain)
    //   ethereum:0x1234...@130?value=1000000000000000000 (send ETH)
    //   ethereum:0xUSDC@130/transfer?address=0xRecipient&uint256=1000000 (ERC20 transfer)
    const eip681Match = qrData.match(/^ethereum:(0x[a-fA-F0-9]{40})(?:@(\d+))?(?:\/([a-zA-Z]+))?(?:\?(.*))?$/);
    if (eip681Match) {
      const targetAddress = eip681Match[1];
      const chainId = eip681Match[2] ? parseInt(eip681Match[2]) : undefined;
      const functionName = eip681Match[3]; // e.g., "transfer" for ERC20
      const queryString = eip681Match[4];
      const params = new URLSearchParams(queryString || '');

      // Log for debugging
      console.log('[VoiceSwap] EIP-681 QR parsed:', { targetAddress, chainId, functionName, params: Object.fromEntries(params) });

      // If it's an ERC20 transfer call (ethereum:TOKEN_CONTRACT/transfer?address=RECIPIENT&uint256=AMOUNT)
      if (functionName === 'transfer') {
        const recipientAddress = params.get('address');
        const amountWei = params.get('uint256');

        if (recipientAddress && ethers.utils.isAddress(recipientAddress)) {
          // Convert uint256 (wei for USDC = 6 decimals) to readable amount
          let amount: string | undefined;
          if (amountWei) {
            try {
              // USDC has 6 decimals
              amount = ethers.utils.formatUnits(amountWei, 6);
            } catch {
              // If parsing fails, leave amount undefined
            }
          }

          return {
            merchantWallet: ethers.utils.getAddress(recipientAddress),
            amount,
          };
        }
      }

      // Simple ethereum:ADDRESS format (direct payment to address)
      // or ethereum:ADDRESS?value=X (ETH payment)
      if (ethers.utils.isAddress(targetAddress)) {
        let amount: string | undefined;
        const valueWei = params.get('value');
        if (valueWei) {
          try {
            // ETH has 18 decimals - store as ETH, convert in API layer
            const ethAmount = parseFloat(ethers.utils.formatEther(valueWei));
            // Mark as ETH amount with prefix for later conversion
            amount = `ETH:${ethAmount}`;
          } catch {
            // Ignore parsing errors
          }
        }

        return {
          merchantWallet: ethers.utils.getAddress(targetAddress),
          amount,
        };
      }
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

    // Check if it's a deep link format (voiceswap://pay?wallet=...)
    const deepLinkMatch = qrData.match(/^(?:voiceswap|unichain):\/\/pay\?(.*)$/);
    if (deepLinkMatch) {
      const params = new URLSearchParams(deepLinkMatch[1]);
      const wallet = params.get('wallet');
      if (!wallet || !ethers.utils.isAddress(wallet)) {
        return null;
      }

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

  // Calculate total USD value (USDC + ETH) using live price
  const ethPriceUSD = await getEthPrice();
  const ethValue = parseFloat(ethFormatted);
  const wethValue = parseFloat(wethFormatted);
  const usdcValue = parseFloat(usdcFormatted);
  const totalETHValue = (ethValue + wethValue) * ethPriceUSD;
  const totalUSD = (usdcValue + totalETHValue).toFixed(2);

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
    totalUSDC: usdcFormatted,
    totalUSD: totalUSD,
    ethPriceUSD: ethPriceUSD,
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
export async function getMaxPayableAmount(balances: WalletBalances): Promise<{
  tokenSymbol: string;
  tokenAddress: string;
  maxAmount: string;
  estimatedUSDC: string;
}> {
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

  // Get live ETH price
  const ethPrice = await getEthPrice();

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

// ============================================
// QR Code Generation for Merchant Web Page
// ============================================

/**
 * QR Code data for merchant payment page
 * Contains multiple formats for maximum compatibility
 */
export interface MerchantQRData {
  // VoiceSwap native format (for VoiceSwap app)
  voiceswap: string;
  // EIP-681 format (for Zerion, MetaMask, Rainbow, etc.)
  eip681: string;
  // Simple address (fallback)
  address: string;
  // Display info
  displayAmount: string;
  displayMerchant: string;
}

/**
 * Generate QR code data for a merchant payment request
 *
 * Creates multiple formats:
 * 1. VoiceSwap deep link (voiceswap://pay?...) - for VoiceSwap app
 * 2. EIP-681 URI (ethereum:...) - for standard wallets like Zerion, MetaMask
 * 3. Plain address - as fallback
 *
 * @param merchantWallet - Merchant's wallet address
 * @param amount - Amount in USDC (human readable, e.g., "10.00")
 * @param merchantName - Optional merchant display name
 * @returns QR code data in multiple formats
 */
export function generateMerchantQRData(
  merchantWallet: string,
  amount?: string,
  merchantName?: string
): MerchantQRData {
  const checksumWallet = ethers.utils.getAddress(merchantWallet);

  // VoiceSwap native format
  const voiceswapParams = new URLSearchParams();
  voiceswapParams.set('wallet', checksumWallet);
  if (amount) voiceswapParams.set('amount', amount);
  if (merchantName) voiceswapParams.set('name', merchantName);
  const voiceswapUri = `voiceswap://pay?${voiceswapParams.toString()}`;

  // EIP-681 format for USDC transfer on Unichain (chain ID 130)
  // Format: ethereum:USDC_CONTRACT@130/transfer?address=RECIPIENT&uint256=AMOUNT_IN_WEI
  let eip681Uri: string;
  if (amount) {
    // Convert USDC amount to wei (6 decimals)
    const amountWei = ethers.utils.parseUnits(amount, 6).toString();
    eip681Uri = `ethereum:${TOKENS.USDC}@${CHAIN_ID}/transfer?address=${checksumWallet}&uint256=${amountWei}`;
  } else {
    // Simple address format without amount
    eip681Uri = `ethereum:${checksumWallet}@${CHAIN_ID}`;
  }

  return {
    voiceswap: voiceswapUri,
    eip681: eip681Uri,
    address: checksumWallet,
    displayAmount: amount ? `$${amount} USDC` : 'Any amount',
    displayMerchant: merchantName || `${checksumWallet.slice(0, 6)}...${checksumWallet.slice(-4)}`,
  };
}

/**
 * Generate a web URL for payment (redirects to app or shows fallback)
 * This URL can be shared directly or embedded in a QR code
 */
export function generatePaymentWebURL(
  merchantWallet: string,
  amount?: string,
  merchantName?: string
): string {
  const checksumWallet = ethers.utils.getAddress(merchantWallet);
  const params = new URLSearchParams();
  if (amount) params.set('amount', amount);
  if (merchantName) params.set('name', merchantName);

  const queryString = params.toString();
  return `https://voiceswap.cc/pay/${checksumWallet}${queryString ? `?${queryString}` : ''}`;
}
