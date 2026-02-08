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
 * Body:
 * - userAddress: User's wallet address
 * - merchantWallet: Merchant's wallet address
 * - amount: Amount in USDC
 *
 * Returns:
 * - transaction: { to, value, data } ready to be signed
 * - tokenAddress: USDC contract address
 * - needsApproval: If token approval is needed first
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

    // For MVP: Only support direct USDC transfers
    // Users deposit USDC directly, no swap needed
    if (!swapInfo.hasEnoughUSDC) {
      return res.status(400).json({
        success: false,
        error: 'Insufficient USDC balance. Please deposit USDC to your wallet.',
        currentBalance: balances.totalUSDC,
        requiredAmount: amount,
      });
    }

    // Build ERC20 transfer calldata
    // transfer(address to, uint256 amount)
    const iface = new ethers.utils.Interface([
      'function transfer(address to, uint256 amount) returns (bool)',
    ]);
    const transferData = iface.encodeFunctionData('transfer', [merchantWallet, amountInUnits]);

    // Return transaction data for WalletConnect
    res.json({
      success: true,
      data: {
        transaction: {
          to: SUPPORTED_TOKENS.USDC,  // USDC contract address
          value: '0x0',               // No ETH value for ERC20 transfer
          data: transferData,         // Encoded transfer call
          from: userAddress,          // User's address
          chainId: 143,               // Monad mainnet
        },
        tokenAddress: SUPPORTED_TOKENS.USDC,
        tokenSymbol: 'USDC',
        amount: amount,
        recipient: merchantWallet,
        recipientShort: `${merchantWallet.slice(0, 6)}...${merchantWallet.slice(-4)}`,
        message: `Transfer ${amount} USDC to ${merchantWallet.slice(0, 6)}...${merchantWallet.slice(-4)}`,
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
    const { merchantWallet, txHash, fromAddress, amount, concept, blockNumber } = req.body;

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
 * GET /voiceswap/merchant/transactions/:wallet
 * Get real blockchain transactions for a merchant wallet from Blockscout
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

    // Fetch token transfers from Blockscout API
    const blockscoutUrl = `https://monad.socialscan.io/api/v2/addresses/${wallet}/token-transfers`;
    const response = await fetch(blockscoutUrl);

    if (!response.ok) {
      throw new Error(`Blockscout API error: ${response.status}`);
    }

    const data = await response.json() as { items?: any[] };

    // Filter and format incoming USDC transfers
    const usdcAddress = '0x078D782b760474a361dDA0AF3839290b0EF57AD6'.toLowerCase();
    const transactions = (data.items || [])
      .filter((tx: any) => {
        // Only incoming transfers to this wallet
        const isIncoming = tx.to?.hash?.toLowerCase() === wallet.toLowerCase();
        // Only USDC transfers
        const isUsdc = tx.token?.address_hash?.toLowerCase() === usdcAddress;
        return isIncoming && isUsdc;
      })
      .slice(Number(offset), Number(offset) + Number(limit))
      .map((tx: any) => ({
        txHash: tx.transaction_hash,
        fromAddress: tx.from?.hash || 'Unknown',
        amount: (Number(tx.total?.value || 0) / 1e6).toFixed(2), // USDC has 6 decimals
        timestamp: tx.timestamp,
        token: tx.token?.symbol || 'USDC',
        blockNumber: tx.block_number,
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
