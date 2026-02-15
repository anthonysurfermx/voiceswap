/**
 * VoiceSwap API Routes
 *
 * Endpoints for voice-activated payments on Monad
 */

import { Router } from 'express';
import { ethers } from 'ethers';
import { generateJwt } from '@coinbase/cdp-sdk/auth';

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
  savePaymentReceipt,
  getReceiptByTxHash,
  getReceiptByHash,
  getPayerReceipts,
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
    version: '3.0.0',
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

    // Optimized swap paths: native MON uses payable router (auto-wraps), skipping wrap+approve
    // Before: wrap(tx1) → approve(tx2) → swap(tx3) → transfer(tx4) = 4 txs
    // After:  swap with native value(tx1) → transfer(tx2) = 2 txs

    let routePriceImpact = '0';

    if (swapInfo.swapFrom === 'NATIVE_MON') {
      // Native MON path: send MON as value to SwapRouter02 (auto-wraps internally)
      // No separate wrap or approve needed — 1 swap tx instead of 3
      const route = await uniswap.getRoute(
        WMON_ADDRESS,
        SUPPORTED_TOKENS.USDC,
        wmonNeeded.toFixed(18),
        userAddress,
        1.0,
      );
      routePriceImpact = route.priceImpact || '0';

      steps.push({
        type: 'swap',
        tx: {
          to: route.to!,
          value: ethers.utils.hexValue(wmonNeededWei), // Native MON — router wraps automatically
          data: route.calldata!,
          from: userAddress,
          chainId: 143,
        },
        description: `Swap ${wmonNeeded.toFixed(4)} MON → ${amount} USDC`,
      });
    } else {
      // WMON path: check approval, then swap (2 txs max instead of 3)
      const wmonContract = new ethers.Contract(WMON_ADDRESS, [
        'function allowance(address owner, address spender) view returns (uint256)',
      ], new ethers.providers.JsonRpcProvider(NETWORK_CONFIG.rpcUrl));

      const currentAllowance = await wmonContract.allowance(userAddress, ROUTER_ADDRESS);
      if (currentAllowance.lt(wmonNeededWei)) {
        const approveData = erc20Iface.encodeFunctionData('approve', [
          ROUTER_ADDRESS,
          ethers.constants.MaxUint256,
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

      const route = await uniswap.getRoute(
        WMON_ADDRESS,
        SUPPORTED_TOKENS.USDC,
        wmonNeeded.toFixed(18),
        userAddress,
        1.0,
      );
      routePriceImpact = route.priceImpact || '0';

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
    }

    // Final step: Transfer USDC to merchant
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

    console.log(`[VoiceSwap] Optimized: ${steps.length} steps (was up to 4)`);

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
          priceImpact: routePriceImpact,
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

    if (!merchantWallet || !txHash || !fromAddress || !amount) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: merchantWallet, txHash, fromAddress, amount',
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
      blockNumber: blockNumber || 0,
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

// In-memory rate limit for gas faucet: 1 airdrop per address per 24h
const gasAirdropLog = new Map<string, number>();
const GAS_COOLDOWN_MS = 24 * 60 * 60 * 1000; // 24 hours

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

    // Rate limit: 1 airdrop per address per 24h
    const normalizedAddr = userAddress.toLowerCase();
    const lastAirdrop = gasAirdropLog.get(normalizedAddr);
    if (lastAirdrop && Date.now() - lastAirdrop < GAS_COOLDOWN_MS) {
      const hoursLeft = Math.ceil((GAS_COOLDOWN_MS - (Date.now() - lastAirdrop)) / (60 * 60 * 1000));
      return res.status(429).json({
        success: false,
        error: `Rate limited. Try again in ~${hoursLeft} hour${hoursLeft === 1 ? '' : 's'}.`,
      });
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

    // Record successful airdrop for rate limiting
    gasAirdropLog.set(normalizedAddr, Date.now());

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
 * Get merchant payment history from database (saved by iOS app after each payment)
 * Falls back to Monadscan API if available for additional on-chain discovery
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

    // Primary source: database (saved by iOS app after each confirmed payment)
    const payments = await getMerchantPayments(wallet, {
      limit: Number(limit),
      offset: Number(offset),
    });

    let transactions = payments.map((p: any) => ({
      txHash: p.tx_hash,
      fromAddress: p.from_address || 'Unknown',
      amount: p.amount,
      timestamp: p.created_at || new Date().toISOString(),
      token: 'USDC',
      blockNumber: p.block_number || 0,
      concept: p.concept || undefined,
      explorerUrl: `https://monadscan.com/tx/${p.tx_hash}`,
    }));

    // Fallback: fetch USDC transfers on-chain if DB is empty
    if (transactions.length === 0) {
      try {
        const rpcUrl = process.env.MONAD_RPC_URL || 'https://rpc.monad.xyz';
        const USDC_ADDRESS = '0x754704Bc059F8C67012fEd69BC8A327a5aafb603';
        const TRANSFER_TOPIC = ethers.utils.id('Transfer(address,address,uint256)');
        const recipientPadded = ethers.utils.hexZeroPad(wallet.toLowerCase(), 32);
        const monadscanKey = process.env.MONADSCAN_API_KEY;

        let allLogs: any[] = [];

        if (monadscanKey) {
          // Preferred: Etherscan V2 multichain API (Monadscan migrated here)
          try {
            const url = `https://api.etherscan.io/v2/api?chainid=143&module=account&action=tokentx&address=${wallet}&contractaddress=${USDC_ADDRESS}&startblock=0&endblock=99999999&sort=desc&page=1&offset=${limit}&apikey=${monadscanKey}`;
            const resp = await fetch(url);
            const data = await resp.json() as { status: string; result: any[] };
            if (data.status === '1' && Array.isArray(data.result)) {
              const onChainTxs = data.result
                .filter((tx: any) => tx.to?.toLowerCase() === wallet.toLowerCase())
                .map((tx: any) => ({
                  txHash: tx.hash,
                  fromAddress: ethers.utils.getAddress(tx.from),
                  amount: parseFloat(ethers.utils.formatUnits(tx.value || '0', parseInt(tx.tokenDecimal) || 6)).toFixed(2),
                  timestamp: parseInt(tx.timeStamp) * 1000,
                  token: tx.tokenSymbol || 'USDC',
                  blockNumber: parseInt(tx.blockNumber),
                  concept: undefined,
                  explorerUrl: `https://monadscan.com/tx/${tx.hash}`,
                }));
              transactions = onChainTxs;
              console.log(`[VoiceSwap] Etherscan V2: ${onChainTxs.length} USDC transfers for ${wallet}`);
            }
          } catch (scanErr) {
            console.error('[VoiceSwap] Etherscan V2 API failed, falling back to RPC:', scanErr);
          }
        }

        // RPC fallback: batch eth_getLogs in chunks of 100 blocks (Monad RPC limit)
        if (transactions.length === 0) {
          const provider = new ethers.providers.JsonRpcProvider(rpcUrl);
          const latestBlock = await provider.getBlockNumber();
          // Scan last 50,000 blocks in chunks of 100 (500 parallel requests)
          const CHUNK_SIZE = 100;
          const TOTAL_RANGE = 50000;
          const chunks: { from: number; to: number }[] = [];

          for (let i = 0; i < TOTAL_RANGE; i += CHUNK_SIZE) {
            const from = Math.max(0, latestBlock - TOTAL_RANGE + i);
            const to = Math.min(latestBlock, from + CHUNK_SIZE - 1);
            chunks.push({ from, to });
          }

          // Run in batches of 50 concurrent requests to avoid overwhelming RPC
          const BATCH_SIZE = 50;
          for (let b = 0; b < chunks.length; b += BATCH_SIZE) {
            const batch = chunks.slice(b, b + BATCH_SIZE);
            const results = await Promise.allSettled(
              batch.map(({ from, to }) =>
                provider.getLogs({
                  address: USDC_ADDRESS,
                  topics: [TRANSFER_TOPIC, null, recipientPadded],
                  fromBlock: from,
                  toBlock: to,
                })
              )
            );
            for (const r of results) {
              if (r.status === 'fulfilled' && r.value.length > 0) {
                allLogs.push(...r.value);
              }
            }
            // Stop early if we found enough
            if (allLogs.length >= Number(limit)) break;
          }

          if (allLogs.length > 0) {
            // Sort by block descending, take latest
            allLogs.sort((a, b) => b.blockNumber - a.blockNumber);
            const uniqueLogs = allLogs.filter((log, i, arr) =>
              arr.findIndex(l => l.transactionHash === log.transactionHash) === i
            );

            const onChainTxs = uniqueLogs.slice(0, Number(limit)).map((log) => {
              const from = ethers.utils.getAddress('0x' + (log.topics[1] || '').slice(26));
              const rawAmount = ethers.BigNumber.from(log.data);
              const amount = ethers.utils.formatUnits(rawAmount, 6);
              return {
                txHash: log.transactionHash,
                fromAddress: from,
                amount: parseFloat(amount).toFixed(2),
                timestamp: Date.now(), // approximate — no block timestamp lookup to stay fast
                token: 'USDC',
                blockNumber: log.blockNumber,
                concept: undefined,
                explorerUrl: `https://monadscan.com/tx/${log.transactionHash}`,
              };
            });

            transactions = onChainTxs;
            console.log(`[VoiceSwap] RPC batch: ${onChainTxs.length} USDC transfers for ${wallet} (scanned ${TOTAL_RANGE} blocks)`);
          }
        }
      } catch (chainErr) {
        console.error('[VoiceSwap] On-chain fallback failed:', chainErr);
        // Continue with empty transactions — don't fail the whole request
      }
    }

    // Calculate stats
    const totalAmount = transactions.reduce((sum: number, tx: any) => sum + parseFloat(tx.amount || '0'), 0);
    const uniquePayers = new Set(transactions.map((tx: any) => (tx.fromAddress || '').toLowerCase())).size;

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
    console.error('[VoiceSwap] Get merchant transactions error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get transactions',
    });
  }
});

// ============================================
// Payment Receipts (On-Chain Proof of Purchase)
// ============================================

/**
 * POST /voiceswap/receipt
 * Generate a signed payment receipt (cryptographic proof of purchase)
 *
 * The receipt is a server-signed attestation that a payment occurred.
 * It contains: payer, merchant, amount, concept, txHash, timestamp.
 * The receipt hash is a keccak256 of the structured data, signed by the server.
 *
 * Body:
 * - txHash: Transaction hash of the confirmed payment
 * - payerAddress: Payer's wallet address
 * - merchantWallet: Merchant's wallet address
 * - amount: Amount in USDC
 * - concept: What was purchased (optional)
 */
router.post('/receipt', async (req, res) => {
  try {
    const { txHash, payerAddress, merchantWallet, amount, concept } = req.body;

    if (!txHash || !payerAddress || !merchantWallet || !amount) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: txHash, payerAddress, merchantWallet, amount',
      });
    }

    if (!isValidAddress(payerAddress) || !isValidAddress(merchantWallet)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid wallet address format',
      });
    }

    // Check if receipt already exists
    const existing = await getReceiptByTxHash(txHash);
    if (existing) {
      return res.json({
        success: true,
        data: {
          receiptHash: existing.receipt_hash,
          txHash: existing.tx_hash,
          timestamp: existing.timestamp,
          signature: existing.signature,
          verifyUrl: `https://voiceswap.cc/receipt/${existing.receipt_hash}`,
          message: 'Receipt already exists',
        },
      });
    }

    const sponsorKey = process.env.GAS_SPONSOR_KEY;
    if (!sponsorKey) {
      return res.status(503).json({
        success: false,
        error: 'Receipt signing not configured',
      });
    }

    const timestamp = Math.floor(Date.now() / 1000);

    // Build receipt data structure (EIP-712 style)
    const receiptData = ethers.utils.defaultAbiCoder.encode(
      ['address', 'address', 'string', 'string', 'bytes32', 'uint256', 'uint256'],
      [
        payerAddress,
        merchantWallet,
        amount,
        concept || '',
        txHash,
        timestamp,
        143, // chainId (Monad)
      ]
    );

    const receiptHash = ethers.utils.keccak256(receiptData);

    // Sign the receipt hash with the server's key
    const signer = new ethers.Wallet(sponsorKey);
    const signature = await signer.signMessage(ethers.utils.arrayify(receiptHash));

    // Get block number from tx if possible
    let blockNumber: number | undefined;
    try {
      const provider = new ethers.providers.JsonRpcProvider(NETWORK_CONFIG.rpcUrl);
      const receipt = await provider.getTransactionReceipt(txHash);
      if (receipt) {
        blockNumber = receipt.blockNumber;
      }
    } catch {
      // Non-critical — receipt works without block number
    }

    // Save to database
    await savePaymentReceipt({
      txHash,
      receiptHash,
      payerAddress,
      merchantWallet,
      amount,
      concept,
      blockNumber,
      timestamp,
      signature,
    });

    console.log(`[VoiceSwap] Receipt generated: ${receiptHash.slice(0, 16)}... for tx ${txHash.slice(0, 16)}...`);

    res.json({
      success: true,
      data: {
        receiptHash,
        txHash,
        payer: payerAddress,
        merchant: merchantWallet,
        amount,
        concept: concept || null,
        chainId: 143,
        blockNumber: blockNumber || null,
        timestamp,
        signature,
        signer: signer.address,
        verifyUrl: `https://voiceswap.cc/receipt/${receiptHash}`,
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] Receipt generation error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to generate receipt',
    });
  }
});

/**
 * GET /voiceswap/receipt/:hash
 * Verify and retrieve a payment receipt by its hash
 */
router.get('/receipt/:hash', async (req, res) => {
  try {
    const { hash } = req.params;

    // Try by receipt hash first, then by tx hash
    let receipt = await getReceiptByHash(hash);
    if (!receipt) {
      receipt = await getReceiptByTxHash(hash);
    }

    if (!receipt) {
      return res.status(404).json({
        success: false,
        error: 'Receipt not found',
      });
    }

    // Verify signature
    const receiptData = ethers.utils.defaultAbiCoder.encode(
      ['address', 'address', 'string', 'string', 'bytes32', 'uint256', 'uint256'],
      [
        receipt.payer_address,
        receipt.merchant_wallet,
        receipt.amount,
        receipt.concept || '',
        receipt.tx_hash,
        receipt.timestamp,
        receipt.chain_id,
      ]
    );

    const expectedHash = ethers.utils.keccak256(receiptData);
    const recoveredAddress = ethers.utils.verifyMessage(
      ethers.utils.arrayify(expectedHash),
      receipt.signature
    );

    res.json({
      success: true,
      data: {
        receiptHash: receipt.receipt_hash,
        txHash: receipt.tx_hash,
        payer: receipt.payer_address,
        merchant: receipt.merchant_wallet,
        amount: receipt.amount,
        concept: receipt.concept,
        chainId: receipt.chain_id,
        blockNumber: receipt.block_number,
        timestamp: receipt.timestamp,
        signature: receipt.signature,
        signer: recoveredAddress,
        verified: expectedHash === receipt.receipt_hash,
        explorerUrl: `https://monadscan.com/tx/${receipt.tx_hash}`,
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] Receipt verification error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to verify receipt',
    });
  }
});

/**
 * GET /voiceswap/receipts/:address
 * Get all receipts for a payer address
 */
router.get('/receipts/:address', async (req, res) => {
  try {
    const { address } = req.params;
    const limit = parseInt(req.query.limit as string) || 50;

    if (!isValidAddress(address)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid wallet address',
      });
    }

    const receipts = await getPayerReceipts(address, limit);

    res.json({
      success: true,
      data: {
        receipts: receipts.map(r => ({
          receiptHash: r.receipt_hash,
          txHash: r.tx_hash,
          merchant: r.merchant_wallet,
          amount: r.amount,
          concept: r.concept,
          timestamp: r.timestamp,
          verifyUrl: `https://voiceswap.cc/receipt/${r.receipt_hash}`,
        })),
        count: receipts.length,
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] Get receipts error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get receipts',
    });
  }
});

// ============================================
// Coinbase Onramp Session Token
// ============================================

/**
 * POST /voiceswap/onramp/session-token
 * Generate a Coinbase Onramp session token for secure initialization.
 *
 * As of July 31 2025, Coinbase Onramp requires a server-generated
 * sessionToken instead of the deprecated appId URL parameter.
 * The session token embeds the destination wallet address(es) and
 * supported assets, so the client only needs to pass the token in the URL.
 *
 * Flow:
 *   1. Client calls this endpoint with wallet address + desired assets/blockchains
 *   2. Server generates a CDP JWT using the API key credentials
 *   3. Server calls POST https://api.developer.coinbase.com/onramp/v1/token
 *   4. Returns the one-time-use session token (expires in 5 minutes)
 *
 * Required env vars:
 *   CDP_API_KEY_ID     - CDP API Key ID (UUID)
 *   CDP_API_KEY_SECRET - CDP API Key Secret (EC PEM or Ed25519 base64)
 *
 * Body:
 *   - address:      Destination wallet address (required)
 *   - blockchains:  Array of blockchain identifiers, e.g. ["monad", "base"] (optional, defaults to ["monad"])
 *   - assets:       Array of asset tickers, e.g. ["USDC", "ETH"] (optional, defaults to ["USDC"])
 *
 * Returns:
 *   - token:      One-time-use session token for Coinbase Onramp URL
 *   - onrampUrl:  Ready-to-use Coinbase Onramp URL with the session token
 */
router.post('/onramp/session-token', async (req, res) => {
  try {
    const { address, blockchains, assets } = req.body;

    // --- Validate input ---
    if (!address || typeof address !== 'string') {
      return res.status(400).json({
        success: false,
        error: 'Missing or invalid "address" in request body',
      });
    }

    if (!isValidAddress(address)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid wallet address format',
      });
    }

    // --- Check CDP credentials ---
    const cdpApiKeyId = process.env.CDP_API_KEY_ID;
    const cdpApiKeySecret = process.env.CDP_API_KEY_SECRET;

    if (!cdpApiKeyId || !cdpApiKeySecret) {
      console.error('[Onramp] Missing CDP_API_KEY_ID or CDP_API_KEY_SECRET env vars');
      return res.status(503).json({
        success: false,
        error: 'Coinbase Onramp not configured. CDP API credentials are missing.',
      });
    }

    // --- Resolve the private key (handle escaped newlines from env) ---
    const resolvedSecret = cdpApiKeySecret.replace(/\\n/g, '\n');

    // --- Build the request payload ---
    const targetBlockchains = Array.isArray(blockchains) && blockchains.length > 0
      ? blockchains
      : ['monad'];

    const targetAssets = Array.isArray(assets) && assets.length > 0
      ? assets
      : ['USDC'];

    const tokenRequestBody = {
      addresses: [
        {
          address,
          blockchains: targetBlockchains,
        },
      ],
      assets: targetAssets,
    };

    // Optionally include the client's real IP for Coinbase quote restrictions.
    // Extract from the TCP socket, NOT from X-Forwarded-For (spoofable).
    const clientIp = req.socket.remoteAddress;
    if (clientIp && !clientIp.startsWith('::') && clientIp !== '127.0.0.1') {
      (tokenRequestBody as any).clientIp = clientIp;
    }

    // --- Step 1: Generate CDP JWT ---
    const REQUEST_HOST = 'api.developer.coinbase.com';
    const REQUEST_PATH = '/onramp/v1/token';

    console.log('[Onramp] Generating CDP JWT for session token request...');

    const jwt = await generateJwt({
      apiKeyId: cdpApiKeyId,
      apiKeySecret: resolvedSecret,
      requestMethod: 'POST',
      requestHost: REQUEST_HOST,
      requestPath: REQUEST_PATH,
      expiresIn: 120,
    });

    // --- Step 2: Call Coinbase Onramp token API ---
    console.log('[Onramp] Requesting session token from Coinbase...');

    const tokenResponse = await fetch(`https://${REQUEST_HOST}${REQUEST_PATH}`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${jwt}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(tokenRequestBody),
    });

    if (!tokenResponse.ok) {
      const errorText = await tokenResponse.text();
      console.error(`[Onramp] Coinbase API error (${tokenResponse.status}):`, errorText);
      return res.status(tokenResponse.status >= 500 ? 502 : 400).json({
        success: false,
        error: `Coinbase Onramp API error: ${tokenResponse.status}`,
        details: errorText,
      });
    }

    const tokenData = await tokenResponse.json() as { token: string; channel_id?: string };

    if (!tokenData.token) {
      console.error('[Onramp] No token in Coinbase response:', tokenData);
      return res.status(502).json({
        success: false,
        error: 'Coinbase Onramp API returned an empty token',
      });
    }

    console.log(`[Onramp] Session token generated for ${address.slice(0, 10)}...`);

    // --- Step 3: Build the ready-to-use Onramp URL ---
    const onrampUrl = `https://pay.coinbase.com/buy/select-asset?sessionToken=${tokenData.token}`;

    res.json({
      success: true,
      data: {
        token: tokenData.token,
        onrampUrl,
        expiresInSeconds: 300, // 5 minutes
        note: 'Token is single-use and expires in 5 minutes.',
      },
    });
  } catch (error) {
    console.error('[Onramp] Session token generation error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to generate Coinbase Onramp session token',
    });
  }
});

export default router;
