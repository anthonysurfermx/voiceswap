/**
 * VoiceSwap API Routes
 *
 * Endpoints for voice-activated payments on Monad
 */

import { Router } from 'express';
import { ethers } from 'ethers';

// Helper function to validate Ethereum addresses
// Uses regex as primary method (more reliable in serverless environments)
function isValidAddress(address: string): boolean {
  if (!address || typeof address !== 'string') {
    return false;
  }
  // Regex validation: 0x followed by 40 hex characters
  return /^0x[a-fA-F0-9]{40}$/.test(address);
}
import {
  parseQRCode,
  getWalletBalances,
  determineSwapToken,
  getMaxPayableAmount,
  generateVoicePrompt,
  parseVoiceCommand,
  VOICE_COMMANDS,
  VOICE_PROMPTS,
  SUPPORTED_TOKENS,
  NETWORK_CONFIG,
  type PaymentSession,
  createPaymentSession,
  updateSessionState,
  generateMerchantQRData,
  generatePaymentWebURL,
} from '../services/voiceswap.js';
import { getUniswapService } from '../services/uniswap.js';
import {
  saveTransaction,
  saveMerchantPayment,
  getMerchantPayments,
  getMerchantPaymentByTxHash,
  updatePaymentConcept,
  getMerchantStats,
  getUserPayments,
  setAddressLabel,
  resolveAddressLabels,
} from '../services/database.js';
import { getPriceInfo, getEthPrice } from '../services/priceOracle.js';

const router = Router();

/**
 * GET /voiceswap/info
 * Get VoiceSwap service information
 */
router.get('/info', (_req, res) => {
  res.json({
    service: 'VoiceSwap',
    description: 'Voice-activated crypto payments for Meta Ray-Ban glasses',
    version: '1.0.0',
    network: NETWORK_CONFIG,
    supportedTokens: {
      input: ['MON', 'WMON', 'USDC'],
      output: 'USDC',
    },
    tokens: SUPPORTED_TOKENS,
    endpoints: {
      '/voiceswap/parse-qr': {
        method: 'POST',
        description: 'Parse QR code to extract merchant wallet',
      },
      '/voiceswap/balance/:address': {
        method: 'GET',
        description: 'Get wallet balances on Monad',
      },
      '/voiceswap/prepare': {
        method: 'POST',
        description: 'Prepare payment (check balances, determine swap)',
      },
      '/voiceswap/execute': {
        method: 'POST',
        description: 'Execute the payment (swap if needed + transfer)',
      },
    },
  });
});

/**
 * GET /voiceswap/price
 * Get current ETH price in USD
 */
router.get('/price', async (_req, res) => {
  try {
    const priceInfo = await getPriceInfo();
    res.json({
      success: true,
      data: priceInfo,
    });
  } catch (error) {
    console.error('[VoiceSwap] Price fetch error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch ETH price',
    });
  }
});

/**
 * POST /voiceswap/parse-qr
 * Parse QR code data to extract payment request
 */
router.post('/parse-qr', (req, res) => {
  try {
    const { qrData } = req.body;

    if (!qrData) {
      return res.status(400).json({
        success: false,
        error: 'Missing qrData in request body',
      });
    }

    const paymentRequest = parseQRCode(qrData);

    if (!paymentRequest) {
      return res.status(400).json({
        success: false,
        error: 'Invalid QR code format. Expected Ethereum address or payment URI.',
      });
    }

    res.json({
      success: true,
      data: paymentRequest,
    });
  } catch (error) {
    console.error('[VoiceSwap] Parse QR error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to parse QR code',
    });
  }
});

/**
 * GET /voiceswap/balance/:address
 * Get wallet balances on Monad
 */
router.get('/balance/:address', async (req, res) => {
  try {
    const { address } = req.params;

    if (!address) {
      return res.status(400).json({
        success: false,
        error: 'Missing address parameter',
      });
    }

    const balances = await getWalletBalances(address);

    res.json({
      success: true,
      data: balances,
    });
  } catch (error) {
    console.error('[VoiceSwap] Balance check error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch wallet balances',
    });
  }
});

/**
 * POST /voiceswap/prepare
 * Prepare a payment - check balances, determine if swap is needed
 *
 * Body:
 * - userAddress: User's wallet address
 * - qrData: QR code data (or merchantWallet directly)
 * - amount?: Amount in USDC (optional)
 */
router.post('/prepare', async (req, res) => {
  try {
    const { userAddress, qrData, merchantWallet, amount } = req.body;

    if (!userAddress) {
      return res.status(400).json({
        success: false,
        error: 'Missing userAddress in request body',
      });
    }

    // Parse QR or use direct wallet
    let paymentRequest;
    if (qrData) {
      paymentRequest = parseQRCode(qrData);
      if (!paymentRequest) {
        return res.status(400).json({
          success: false,
          error: 'Invalid QR code format',
        });
      }
    } else if (merchantWallet) {
      paymentRequest = { merchantWallet, amount };
    } else {
      return res.status(400).json({
        success: false,
        error: 'Missing qrData or merchantWallet',
      });
    }

    // Override amount if provided
    if (amount) {
      paymentRequest.amount = amount;
    }

    // Get user balances
    const balances = await getWalletBalances(userAddress);

    // Determine swap requirements
    const swapInfo = paymentRequest.amount
      ? determineSwapToken(balances, paymentRequest.amount)
      : { needsSwap: false, hasEnoughUSDC: true, hasEnoughMON: true, hasEnoughWMON: false };

    // Get max payable if no amount specified
    const maxPayable = getMaxPayableAmount(balances);

    // Generate voice prompt
    const voicePrompt = generateVoicePrompt(paymentRequest, balances, swapInfo);

    res.json({
      success: true,
      data: {
        paymentRequest,
        userBalances: balances,
        swapInfo,
        maxPayable,
        voicePrompt,
        ready: swapInfo.hasEnoughUSDC || (swapInfo.needsSwap && swapInfo.swapFrom !== undefined),
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] Prepare error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to prepare payment',
    });
  }
});

/**
 * POST /voiceswap/prepare-tx
 * Prepare transaction data for client-side signing via WalletConnect
 *
 * This endpoint returns the raw transaction data that the iOS app
 * will send to the user's wallet for signing via WalletConnect.
 * This ensures the user controls their own funds.
 *
 * When the user has enough USDC: returns a single transfer step.
 * When the user needs a swap (has MON/WMON but not USDC):
 *   returns multiple steps: [wrap?] → [approve?] → swap → transfer
 *
 * Body:
 * - userAddress: User's wallet address
 * - merchantWallet: Merchant's wallet address
 * - amount: Amount in USDC
 *
 * Returns:
 * - steps: Array of transaction steps to execute sequentially
 * - transaction: Single tx (backward compat, first/only step)
 * - needsSwap: Whether a swap is required
 * - swapInfo: Details about the swap if needed
 */
router.post('/prepare-tx', async (req, res) => {
  try {
    const { userAddress, merchantWallet, amount } = req.body;

    if (!userAddress || !merchantWallet || !amount) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: userAddress, merchantWallet, amount',
      });
    }

    // Validate addresses
    if (!isValidAddress(userAddress) || !isValidAddress(merchantWallet)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid wallet address format',
      });
    }

    console.log(`[VoiceSwap] Preparing tx: ${amount} USDC from ${userAddress} to ${merchantWallet}`);

    // Get current balances to check if user has enough USDC
    const balances = await getWalletBalances(userAddress);
    const swapInfo = determineSwapToken(balances, amount);

    // Convert amount to USDC units (6 decimals)
    const amountInUnits = ethers.utils.parseUnits(amount.toString(), 6);

    const erc20Iface = new ethers.utils.Interface([
      'function transfer(address to, uint256 amount) returns (bool)',
      'function approve(address spender, uint256 amount) returns (bool)',
      'function allowance(address owner, address spender) view returns (uint256)',
    ]);

    const recipientShort = `${merchantWallet.slice(0, 6)}...${merchantWallet.slice(-4)}`;

    // ---- PATH A: Direct USDC transfer (no swap needed) ----
    if (swapInfo.hasEnoughUSDC) {
      const transferData = erc20Iface.encodeFunctionData('transfer', [merchantWallet, amountInUnits]);

      const transferStep = {
        type: 'transfer',
        tx: {
          to: SUPPORTED_TOKENS.USDC,
          value: '0x0',
          data: transferData,
          from: userAddress,
          chainId: 143,
        },
        description: `Send ${amount} USDC to ${recipientShort}`,
      };

      return res.json({
        success: true,
        data: {
          steps: [transferStep],
          needsSwap: false,
          // Backward compatibility
          transaction: transferStep.tx,
          tokenAddress: SUPPORTED_TOKENS.USDC,
          tokenSymbol: 'USDC',
          amount: amount,
          recipient: merchantWallet,
          recipientShort,
          message: `Transfer ${amount} USDC to ${recipientShort}`,
          explorerBaseUrl: 'https://monadscan.com/tx/',
        },
      });
    }

    // ---- PATH B: Swap MON/WMON → USDC, then transfer ----
    if (!swapInfo.swapFrom) {
      return res.status(400).json({
        success: false,
        error: 'Insufficient funds. You need MON, WMON, or USDC to make a payment.',
        currentBalance: balances.totalUSDC,
        requiredAmount: amount,
      });
    }

    console.log(`[VoiceSwap] Swap needed: ${swapInfo.swapFromSymbol} → USDC`);

    const steps: Array<{
      type: string;
      tx: { to: string; value: string; data: string; from: string; chainId: number };
      description: string;
    }> = [];

    const uniswap = getUniswapService();
    const WMON_ADDRESS = SUPPORTED_TOKENS.WMON || '0x3bd359C1119dA7Da1D913D1C4D2B7c461115433A';
    const ROUTER_ADDRESS = '0xfe31f71c1b106eac32f1a19239c9a9a72ddfb900';

    // Get quote: how much WMON needed to get `amount` USDC
    // We quote WMON → USDC. Since getQuote takes amountIn (WMON),
    // we need to estimate. We'll get a quote for a reasonable amount
    // and calculate the ratio, then add a buffer.
    const testQuote = await uniswap.getQuote(WMON_ADDRESS, SUPPORTED_TOKENS.USDC, '1');
    const usdcPerWmon = parseFloat(testQuote.tokenOut.amount);

    if (usdcPerWmon <= 0) {
      return res.status(400).json({
        success: false,
        error: 'Unable to get swap quote. WMON/USDC pool may have insufficient liquidity.',
      });
    }

    // Calculate WMON needed with 2% buffer for slippage
    const wmonNeeded = (parseFloat(amount) / usdcPerWmon) * 1.02;
    const wmonNeededStr = wmonNeeded.toFixed(18);
    const wmonNeededWei = ethers.utils.parseEther(wmonNeededStr);

    console.log(`[VoiceSwap] Quote: 1 WMON = ${usdcPerWmon} USDC, need ~${wmonNeeded.toFixed(4)} WMON for ${amount} USDC`);

    // Step 1 (conditional): Wrap MON → WMON
    if (swapInfo.swapFrom === 'NATIVE_MON') {
      const wmonIface = new ethers.utils.Interface(['function deposit() payable']);
      const wrapData = wmonIface.encodeFunctionData('deposit', []);

      steps.push({
        type: 'wrap',
        tx: {
          to: WMON_ADDRESS,
          value: ethers.utils.hexValue(wmonNeededWei),
          data: wrapData,
          from: userAddress,
          chainId: 143,
        },
        description: `Wrap ${wmonNeeded.toFixed(4)} MON to WMON`,
      });
    }

    // Step 2 (conditional): Approve WMON for Uniswap Router
    const wmonContract = new ethers.Contract(WMON_ADDRESS, [
      'function allowance(address owner, address spender) view returns (uint256)',
    ], new ethers.providers.JsonRpcProvider(NETWORK_CONFIG.rpcUrl));

    const currentAllowance = await wmonContract.allowance(userAddress, ROUTER_ADDRESS);
    if (currentAllowance.lt(wmonNeededWei)) {
      const approveData = erc20Iface.encodeFunctionData('approve', [
        ROUTER_ADDRESS,
        ethers.constants.MaxUint256, // Infinite approval (one-time)
      ]);

      steps.push({
        type: 'approve',
        tx: {
          to: WMON_ADDRESS,
          value: '0x0',
          data: approveData,
          from: userAddress,
          chainId: 143,
        },
        description: 'Approve WMON for swap',
      });
    }

    // Step 3: Swap WMON → USDC via Uniswap V3
    const route = await uniswap.getRoute(
      WMON_ADDRESS,
      SUPPORTED_TOKENS.USDC,
      wmonNeeded.toFixed(18),
      userAddress, // USDC goes to user's wallet
      1.0, // 1% slippage tolerance
    );

    steps.push({
      type: 'swap',
      tx: {
        to: route.to!,
        value: '0x0',
        data: route.calldata!,
        from: userAddress,
        chainId: 143,
      },
      description: `Swap ${wmonNeeded.toFixed(4)} WMON → ${amount} USDC`,
    });

    // Step 4: Transfer USDC to merchant
    const transferData = erc20Iface.encodeFunctionData('transfer', [merchantWallet, amountInUnits]);
    steps.push({
      type: 'transfer',
      tx: {
        to: SUPPORTED_TOKENS.USDC,
        value: '0x0',
        data: transferData,
        from: userAddress,
        chainId: 143,
      },
      description: `Send ${amount} USDC to ${recipientShort}`,
    });

    res.json({
      success: true,
      data: {
        steps,
        needsSwap: true,
        swapInfo: {
          fromToken: swapInfo.swapFromSymbol,
          toToken: 'USDC',
          amountIn: wmonNeeded.toFixed(4),
          estimatedOut: amount,
          priceImpact: route.priceImpact,
          slippage: '1.0',
        },
        // Backward compatibility: first step's tx
        transaction: steps[0].tx,
        tokenAddress: SUPPORTED_TOKENS.USDC,
        tokenSymbol: 'USDC',
        amount: amount,
        recipient: merchantWallet,
        recipientShort,
        message: `Swap ${swapInfo.swapFromSymbol} → USDC, then pay ${recipientShort}`,
        explorerBaseUrl: 'https://monadscan.com/tx/',
      },
    });

  } catch (error) {
    console.error('[VoiceSwap] Prepare-tx error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to prepare transaction',
    });
  }
});

/**
 * POST /voiceswap/execute
 * DEPRECATED: Use /voiceswap/prepare-tx + WalletConnect for client-side signing.
 */
router.post('/execute', async (_req, res) => {
  res.status(410).json({
    success: false,
    error: 'This endpoint is deprecated. Use /voiceswap/prepare-tx with WalletConnect for client-side signing.',
  });
});

/**
 * POST /voiceswap/confirm
 * Process voice confirmation command
 *
 * Body:
 * - transcript: Voice transcript from speech recognition
 * - sessionId: Payment session ID (optional, for tracking)
 */
router.post('/confirm', (req, res) => {
  try {
    const { transcript, sessionId } = req.body;

    if (!transcript) {
      return res.status(400).json({
        success: false,
        error: 'Missing transcript in request body',
      });
    }

    // Parse the voice command
    const command = parseVoiceCommand(transcript);

    // Generate appropriate response
    let voiceResponse: string;
    let shouldProceed = false;

    switch (command) {
      case 'confirm':
        voiceResponse = VOICE_PROMPTS.confirming();
        shouldProceed = true;
        break;
      case 'cancel':
        voiceResponse = VOICE_PROMPTS.cancelled();
        shouldProceed = false;
        break;
      default:
        voiceResponse = VOICE_PROMPTS.invalidCommand();
        shouldProceed = false;
    }

    res.json({
      success: true,
      data: {
        command,
        transcript,
        shouldProceed,
        voiceResponse,
        sessionId,
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] Confirm error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to process voice command',
    });
  }
});

/**
 * GET /voiceswap/voice-commands
 * Get list of supported voice commands
 */
router.get('/voice-commands', (_req, res) => {
  res.json({
    success: true,
    data: {
      confirm: VOICE_COMMANDS.confirm,
      cancel: VOICE_COMMANDS.cancel,
      description: {
        confirm: 'Commands to confirm and execute the payment',
        cancel: 'Commands to cancel the payment',
      },
      languages: ['English', 'Spanish'],
    },
  });
});

/**
 * POST /voiceswap/session
 * Create a new payment session
 */
router.post('/session', (req, res) => {
  try {
    const { userAddress } = req.body;

    if (!userAddress) {
      return res.status(400).json({
        success: false,
        error: 'Missing userAddress in request body',
      });
    }

    const session = createPaymentSession(userAddress);

    res.json({
      success: true,
      data: session,
    });
  } catch (error) {
    console.error('[VoiceSwap] Session creation error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to create payment session',
    });
  }
});

/**
 * PUT /voiceswap/session/:sessionId
 * Update payment session state
 */
router.put('/session/:sessionId', (req, res) => {
  try {
    const { sessionId } = req.params;
    const { session, newState, updates } = req.body;

    if (!session || !newState) {
      return res.status(400).json({
        success: false,
        error: 'Missing session or newState in request body',
      });
    }

    const updatedSession = updateSessionState(session, newState, updates);

    res.json({
      success: true,
      data: {
        sessionId,
        session: updatedSession,
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] Session update error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update payment session',
    });
  }
});

/**
 * GET /voiceswap/tx/:txHash
 * Get transaction status and receipt from Monad
 *
 * Returns:
 * - status: 'pending' | 'confirmed' | 'failed'
 * - confirmations: Number of block confirmations
 * - receipt: Transaction receipt if confirmed
 */
router.get('/tx/:txHash', async (req, res) => {
  try {
    const { txHash } = req.params;

    if (!txHash || !txHash.startsWith('0x')) {
      return res.status(400).json({
        success: false,
        error: 'Invalid transaction hash',
      });
    }

    console.log(`[VoiceSwap] Checking tx status: ${txHash}`);

    // Create provider for Monad
    const provider = new ethers.providers.JsonRpcProvider(
      NETWORK_CONFIG.rpcUrl,
      { name: 'monad', chainId: NETWORK_CONFIG.chainId }
    );

    // Get transaction receipt
    const receipt = await provider.getTransactionReceipt(txHash);

    if (!receipt) {
      // Transaction not yet mined
      // Check if it exists in the mempool
      const tx = await provider.getTransaction(txHash);

      if (!tx) {
        return res.json({
          success: true,
          data: {
            txHash,
            status: 'not_found',
            message: 'Transaction not found. It may have been dropped or not yet broadcasted.',
          },
        });
      }

      return res.json({
        success: true,
        data: {
          txHash,
          status: 'pending',
          message: 'Transaction is pending confirmation',
          from: tx.from,
          to: tx.to,
          value: tx.value.toString(),
          nonce: tx.nonce,
        },
      });
    }

    // Transaction was mined
    const currentBlock = await provider.getBlockNumber();
    const confirmations = currentBlock - receipt.blockNumber;

    // Check if transaction was successful
    const isSuccess = receipt.status === 1;

    res.json({
      success: true,
      data: {
        txHash,
        status: isSuccess ? 'confirmed' : 'failed',
        confirmations,
        blockNumber: receipt.blockNumber,
        gasUsed: receipt.gasUsed.toString(),
        effectiveGasPrice: receipt.effectiveGasPrice?.toString(),
        from: receipt.from,
        to: receipt.to,
        explorerUrl: `https://monadscan.com/tx/${txHash}`,
        message: isSuccess
          ? `Transaction confirmed with ${confirmations} confirmations`
          : 'Transaction failed on-chain',
      },
    });

  } catch (error) {
    console.error('[VoiceSwap] Tx status error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to check transaction status',
    });
  }
});

// ============================================
// Merchant QR Code Generation
// ============================================

/**
 * POST /voiceswap/generate-qr
 * Generate QR code data for a merchant payment request
 *
 * This endpoint is used by the merchant's "Receive" page to generate
 * QR codes that customers can scan with VoiceSwap or any standard wallet.
 *
 * Body:
 * - merchantWallet: Merchant's wallet address (required)
 * - amount: Amount in USDC, e.g., "10.00" (optional)
 * - merchantName: Display name for the merchant (optional)
 *
 * Returns multiple QR code formats:
 * - voiceswap: Deep link for VoiceSwap app (voiceswap://pay?...)
 * - eip681: Standard format for Zerion, MetaMask, etc. (ethereum:...)
 * - webUrl: Shareable web link (https://voiceswap.cc/pay/...)
 * - address: Plain wallet address (fallback)
 */
router.post('/generate-qr', (req, res) => {
  try {
    const { merchantWallet, amount, merchantName } = req.body;

    if (!merchantWallet) {
      return res.status(400).json({
        success: false,
        error: 'Missing merchantWallet in request body',
      });
    }

    // Validate wallet address
    if (!isValidAddress(merchantWallet)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid wallet address format',
      });
    }

    // Validate amount if provided
    if (amount) {
      const amountNum = parseFloat(amount);
      if (isNaN(amountNum) || amountNum <= 0) {
        return res.status(400).json({
          success: false,
          error: 'Invalid amount. Must be a positive number.',
        });
      }
    }

    // Save merchant label if name provided
    if (merchantName) {
      setAddressLabel(merchantWallet, merchantName).catch(() => {});
    }

    // Generate QR data in multiple formats
    const qrData = generateMerchantQRData(merchantWallet, amount, merchantName);
    const webUrl = generatePaymentWebURL(merchantWallet, amount, merchantName);

    console.log(`[VoiceSwap] Generated QR for merchant ${qrData.displayMerchant}: ${qrData.displayAmount}`);

    res.json({
      success: true,
      data: {
        // QR code content options (frontend chooses which to display)
        qrFormats: {
          // For VoiceSwap app - includes all payment details
          voiceswap: qrData.voiceswap,
          // For standard wallets (Zerion, MetaMask, Rainbow)
          eip681: qrData.eip681,
          // Plain address (universal fallback)
          address: qrData.address,
        },
        // Web URL for sharing
        webUrl,
        // Display info for the merchant's screen
        display: {
          amount: qrData.displayAmount,
          merchant: qrData.displayMerchant,
          network: 'Monad',
          token: 'USDC',
        },
        // Instructions for the merchant to show customers
        instructions: {
          voiceswap: 'Scan with VoiceSwap app on Meta Ray-Ban glasses',
          standard: 'Scan with any crypto wallet (Zerion, MetaMask, Rainbow)',
        },
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] Generate QR error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to generate QR code data',
    });
  }
});

/**
 * GET /voiceswap/qr/:wallet
 * Quick QR code data generation via GET request
 *
 * Query params:
 * - amount: Amount in USDC (optional)
 * - name: Merchant name (optional)
 */
router.get('/qr/:wallet', (req, res) => {
  try {
    const { wallet } = req.params;
    const amount = req.query.amount as string | undefined;
    const merchantName = req.query.name as string | undefined;

    if (!isValidAddress(wallet)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid wallet address',
      });
    }

    const qrData = generateMerchantQRData(wallet, amount, merchantName);
    const webUrl = generatePaymentWebURL(wallet, amount, merchantName);

    res.json({
      success: true,
      data: {
        voiceswap: qrData.voiceswap,
        eip681: qrData.eip681,
        address: qrData.address,
        webUrl,
        display: {
          amount: qrData.displayAmount,
          merchant: qrData.displayMerchant,
        },
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] QR GET error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to generate QR code data',
    });
  }
});

// ============================================
// Merchant Payments Management
// ============================================

/**
 * POST /voiceswap/merchant/payment
 * Save a payment received by merchant with concept
 *
 * Body:
 * - merchantWallet: Merchant's wallet address
 * - txHash: Transaction hash
 * - fromAddress: Payer's address
 * - amount: Amount in USDC
 * - concept: Payment concept/category (optional)
 * - blockNumber: Block number
 */
router.post('/merchant/payment', async (req, res) => {
  try {
    const { merchantWallet, txHash, fromAddress, amount, concept, blockNumber, merchantName } = req.body;

    if (!merchantWallet || !txHash || !fromAddress || !amount || blockNumber === undefined) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: merchantWallet, txHash, fromAddress, amount, blockNumber',
      });
    }

    if (!isValidAddress(merchantWallet) || !isValidAddress(fromAddress)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid wallet address format',
      });
    }

    await saveMerchantPayment({
      merchantWallet,
      txHash,
      fromAddress,
      amount: amount.toString(),
      concept,
      blockNumber,
    });

    // Save merchant name label if provided
    if (merchantName) {
      setAddressLabel(merchantWallet, merchantName).catch(() => {});
    }

    console.log(`[VoiceSwap] Saved merchant payment: ${amount} USDC, concept: ${concept || 'none'}`);

    res.json({
      success: true,
      data: {
        txHash,
        concept,
        message: 'Payment saved successfully',
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] Save merchant payment error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to save payment',
    });
  }
});

/**
 * GET /voiceswap/merchant/payments/:wallet
 * Get merchant payment history with concepts
 *
 * Query params:
 * - limit: Number of results (default 50)
 * - offset: Pagination offset (default 0)
 * - concept: Filter by concept (optional)
 */
router.get('/merchant/payments/:wallet', async (req, res) => {
  try {
    const { wallet } = req.params;
    const limit = parseInt(req.query.limit as string) || 50;
    const offset = parseInt(req.query.offset as string) || 0;
    const concept = req.query.concept as string | undefined;

    if (!isValidAddress(wallet)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid wallet address',
      });
    }

    const payments = await getMerchantPayments(wallet, { limit, offset, concept });

    res.json({
      success: true,
      data: {
        payments,
        pagination: {
          limit,
          offset,
          count: payments.length,
        },
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] Get merchant payments error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get payments',
    });
  }
});

/**
 * PUT /voiceswap/merchant/payment/:txHash/concept
 * Update the concept of an existing payment
 *
 * Body:
 * - concept: New concept value
 */
router.put('/merchant/payment/:txHash/concept', async (req, res) => {
  try {
    const { txHash } = req.params;
    const { concept } = req.body;

    if (!concept) {
      return res.status(400).json({
        success: false,
        error: 'Missing concept in request body',
      });
    }

    // Check if payment exists
    const existing = await getMerchantPaymentByTxHash(txHash);
    if (!existing) {
      return res.status(404).json({
        success: false,
        error: 'Payment not found',
      });
    }

    await updatePaymentConcept(txHash, concept);

    res.json({
      success: true,
      data: {
        txHash,
        concept,
        message: 'Concept updated successfully',
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] Update payment concept error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to update concept',
    });
  }
});

/**
 * GET /voiceswap/merchant/stats/:wallet
 * Get merchant payment statistics
 */
router.get('/merchant/stats/:wallet', async (req, res) => {
  try {
    const { wallet } = req.params;

    if (!isValidAddress(wallet)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid wallet address',
      });
    }

    const stats = await getMerchantStats(wallet);

    res.json({
      success: true,
      data: stats,
    });
  } catch (error) {
    console.error('[VoiceSwap] Get merchant stats error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get stats',
    });
  }
});

/**
 * GET /voiceswap/user/payments/:address
 * Get payment history for a user (payer) address
 *
 * Query params:
 * - limit: Number of results (default 50)
 * - offset: Pagination offset (default 0)
 */
router.get('/user/payments/:address', async (req, res) => {
  try {
    const { address } = req.params;
    const limit = parseInt(req.query.limit as string) || 50;
    const offset = parseInt(req.query.offset as string) || 0;

    if (!isValidAddress(address)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid wallet address',
      });
    }

    const payments = await getUserPayments(address, { limit, offset });

    // Resolve merchant names for all unique merchant addresses
    const merchantAddresses = [...new Set(payments.map(p => p.merchant_wallet))];
    const labels = await resolveAddressLabels(merchantAddresses);

    // Enrich payments with merchant labels
    const enrichedPayments = payments.map(p => ({
      ...p,
      merchant_name: labels[p.merchant_wallet.toLowerCase()] || null,
    }));

    res.json({
      success: true,
      data: {
        payments: enrichedPayments,
        pagination: {
          limit,
          offset,
          count: payments.length,
        },
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] Get user payments error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get payment history',
    });
  }
});

/**
 * POST /voiceswap/resolve-names
 * Resolve wallet addresses to human-readable labels
 */
router.post('/resolve-names', async (req, res) => {
  try {
    const { addresses } = req.body;

    if (!Array.isArray(addresses) || addresses.length === 0) {
      return res.status(400).json({ success: false, error: 'addresses must be a non-empty array' });
    }

    const labels = await resolveAddressLabels(addresses.slice(0, 100));
    res.json({ success: true, data: { labels } });
  } catch (error) {
    console.error('[VoiceSwap] Resolve names error:', error);
    res.status(500).json({ success: false, error: 'Failed to resolve names' });
  }
});

/**
 * POST /voiceswap/set-label
 * Set a label for a wallet address
 */
router.post('/set-label', async (req, res) => {
  try {
    const { address, label } = req.body;
    if (!address || !label) {
      return res.status(400).json({ success: false, error: 'address and label required' });
    }
    if (!isValidAddress(address)) {
      return res.status(400).json({ success: false, error: 'Invalid address' });
    }
    await setAddressLabel(address, label);
    res.json({ success: true, data: { address: address.toLowerCase(), label } });
  } catch (error) {
    console.error('[VoiceSwap] Set label error:', error);
    res.status(500).json({ success: false, error: 'Failed to set label' });
  }
});

/**
 * POST /voiceswap/gas/request
 * Request a small MON gas airdrop for new users
 * This is a simple "gas tank" pattern for hackathon demo
 * Requires GAS_SPONSOR_KEY env var (private key of funded wallet)
 */
router.post('/gas/request', async (req, res) => {
  try {
    const { userAddress } = req.body;

    if (!userAddress || !isValidAddress(userAddress)) {
      return res.status(400).json({ success: false, error: 'Invalid userAddress' });
    }

    const sponsorKey = process.env.GAS_SPONSOR_KEY;
    if (!sponsorKey) {
      return res.status(503).json({
        success: false,
        error: 'Gas sponsorship not configured',
      });
    }

    // Check user's current MON balance
    const provider = new ethers.providers.JsonRpcProvider(NETWORK_CONFIG.rpcUrl);
    const balance = await provider.getBalance(userAddress);
    const minGas = ethers.utils.parseEther('0.001'); // 0.001 MON minimum
    const airdropAmount = ethers.utils.parseEther('0.01'); // Send 0.01 MON (~enough for 100+ txs)

    if (balance.gte(minGas)) {
      return res.json({
        success: true,
        data: {
          status: 'sufficient',
          balance: ethers.utils.formatEther(balance),
          message: 'User already has enough MON for gas',
        },
      });
    }

    // Send gas airdrop
    const sponsor = new ethers.Wallet(sponsorKey, provider);
    const tx = await sponsor.sendTransaction({
      to: userAddress,
      value: airdropAmount,
    });

    console.log(`[GasSponsor] Sent 0.01 MON to ${userAddress}: ${tx.hash}`);

    res.json({
      success: true,
      data: {
        status: 'funded',
        txHash: tx.hash,
        amount: '0.01',
        message: 'Gas funded! You can now make payments.',
      },
    });
  } catch (error) {
    console.error('[GasSponsor] Error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to sponsor gas',
    });
  }
});

/**
 * GET /voiceswap/merchant/transactions/:wallet
 * Get real blockchain transactions for a merchant wallet from Monadscan (Etherscan-compatible API)
 */
router.get('/merchant/transactions/:wallet', async (req, res) => {
  try {
    const { wallet } = req.params;
    const { limit = '50', offset = '0' } = req.query;

    if (!isValidAddress(wallet)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid wallet address',
      });
    }

    const apiKey = process.env.MONADSCAN_API_KEY;
    if (!apiKey) {
      return res.status(503).json({
        success: false,
        error: 'Monadscan API key not configured',
      });
    }

    // Monad USDC contract address
    const usdcAddress = '0x754704Bc059F8C67012fEd69BC8A327a5aafb603';

    // Fetch token transfers from Monadscan (Etherscan-compatible API)
    const page = Math.floor(Number(offset) / Number(limit)) + 1;
    const monadscanUrl = `https://api.monadscan.com/api?module=account&action=tokentx&address=${wallet}&contractaddress=${usdcAddress}&page=${page}&offset=${limit}&sort=desc&apikey=${apiKey}`;
    const response = await fetch(monadscanUrl);

    if (!response.ok) {
      throw new Error(`Monadscan API error: ${response.status}`);
    }

    const data = await response.json() as { status: string; message: string; result: any[] | string };

    if (data.status !== '1' || !Array.isArray(data.result)) {
      // status "0" with "No transactions found" is not an error
      const noTxs = typeof data.result === 'string' && data.result.includes('No transactions found');
      if (noTxs) {
        return res.json({
          success: true,
          data: {
            transactions: [],
            stats: { totalPayments: 0, totalAmount: '0.00', uniquePayers: 0 },
            pagination: { limit: Number(limit), offset: Number(offset), count: 0 },
          },
        });
      }
      throw new Error(`Monadscan API: ${data.message} - ${data.result}`);
    }

    // Filter and format incoming USDC transfers
    const transactions = (data.result as any[])
      .filter((tx: any) => {
        // Only incoming transfers to this wallet
        return tx.to?.toLowerCase() === wallet.toLowerCase();
      })
      .map((tx: any) => ({
        txHash: tx.hash,
        fromAddress: tx.from || 'Unknown',
        amount: (Number(tx.value || 0) / 1e6).toFixed(2), // USDC has 6 decimals
        timestamp: new Date(Number(tx.timeStamp) * 1000).toISOString(),
        token: tx.tokenSymbol || 'USDC',
        blockNumber: Number(tx.blockNumber),
        explorerUrl: `https://monadscan.com/tx/${tx.hash}`,
      }));

    // Calculate stats
    const totalAmount = transactions.reduce((sum: number, tx: any) => sum + parseFloat(tx.amount), 0);
    const uniquePayers = new Set(transactions.map((tx: any) => tx.fromAddress.toLowerCase())).size;

    res.json({
      success: true,
      data: {
        transactions,
        stats: {
          totalPayments: transactions.length,
          totalAmount: totalAmount.toFixed(2),
          uniquePayers,
        },
        pagination: {
          limit: Number(limit),
          offset: Number(offset),
          count: transactions.length,
        },
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] Get blockchain transactions error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get transactions from blockchain',
    });
  }
});

export default router;
