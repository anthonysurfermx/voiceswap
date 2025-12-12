/**
 * VoiceSwap API Routes
 *
 * Endpoints for voice-activated payments on Unichain
 */

import { Router } from 'express';
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
} from '../services/voiceswap.js';
import {
  parseIntent,
  generateResponse,
  extractPaymentDetails,
  healthCheck as openaiHealthCheck,
} from '../services/openai.js';

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
      input: ['ETH', 'WETH', 'USDC'],
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
        description: 'Get wallet balances on Unichain',
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
 * Get wallet balances on Unichain
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
      : { needsSwap: false, hasEnoughUSDC: true, hasEnoughETH: true, hasEnoughWETH: false };

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
 * POST /voiceswap/execute
 * Execute the payment (this will be called from the iOS app with user's signed transaction)
 *
 * For now, this endpoint prepares the transaction data.
 * The actual signing and submission happens on the client side.
 *
 * Body:
 * - userAddress: User's wallet address
 * - merchantWallet: Merchant's wallet address
 * - amount: Amount in USDC
 * - swapFrom?: Token to swap from (if needed)
 */
router.post('/execute', async (req, res) => {
  try {
    const { userAddress, merchantWallet, amount } = req.body;

    if (!userAddress || !merchantWallet || !amount) {
      return res.status(400).json({
        success: false,
        error: 'Missing required fields: userAddress, merchantWallet, amount',
      });
    }

    // Get current balances
    const balances = await getWalletBalances(userAddress);
    const swapInfo = determineSwapToken(balances, amount);

    // If user has enough USDC, just prepare transfer
    if (swapInfo.hasEnoughUSDC) {
      // Direct USDC transfer
      res.json({
        success: true,
        data: {
          action: 'transfer',
          token: SUPPORTED_TOKENS.USDC,
          amount,
          to: merchantWallet,
          from: userAddress,
          // Transaction data would be prepared here for client signing
          message: `Transfer ${amount} USDC to ${merchantWallet}`,
        },
      });
      return;
    }

    // Need to swap first
    if (!swapInfo.swapFrom) {
      return res.status(400).json({
        success: false,
        error: 'Insufficient funds. No swappable tokens available.',
      });
    }

    // For now, return the swap + transfer instructions
    // The actual swap execution will use the existing /execute endpoint
    res.json({
      success: true,
      data: {
        action: 'swap_and_transfer',
        steps: [
          {
            step: 1,
            action: 'swap',
            tokenIn: swapInfo.swapFrom,
            tokenInSymbol: swapInfo.swapFromSymbol,
            tokenOut: SUPPORTED_TOKENS.USDC,
            tokenOutSymbol: 'USDC',
            amountOut: amount,
          },
          {
            step: 2,
            action: 'transfer',
            token: SUPPORTED_TOKENS.USDC,
            amount,
            to: merchantWallet,
          },
        ],
        message: `Swap ${swapInfo.swapFromSymbol} to USDC, then transfer ${amount} USDC to ${merchantWallet}`,
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] Execute error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to execute payment',
    });
  }
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

// ============================================
// OpenAI-powered Natural Language Processing
// ============================================

/**
 * POST /voiceswap/ai/parse
 * Parse natural language voice command using OpenAI
 *
 * Body:
 * - transcript: Voice transcript to parse
 *
 * Examples:
 * - "Paga 50 dólares al café" → payment intent with amount: 50, currency: USD
 * - "Cuánto tengo en mi wallet?" → balance intent
 * - "Swap my ETH to USDC" → swap intent
 */
router.post('/ai/parse', async (req, res) => {
  try {
    const { transcript } = req.body;

    if (!transcript) {
      return res.status(400).json({
        success: false,
        error: 'Missing transcript in request body',
      });
    }

    const intent = await parseIntent(transcript);
    const voiceResponse = generateResponse(intent);

    res.json({
      success: true,
      data: {
        intent,
        voiceResponse,
        timestamp: Date.now(),
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] AI parse error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to parse voice command',
    });
  }
});

/**
 * POST /voiceswap/ai/payment-details
 * Extract detailed payment information from natural language
 *
 * Body:
 * - transcript: Voice transcript with payment intent
 *
 * Returns structured payment details:
 * - amount: Payment amount
 * - currency: Currency (USD, USDC, ETH)
 * - recipient: Merchant name or description
 * - notes: Additional context
 */
router.post('/ai/payment-details', async (req, res) => {
  try {
    const { transcript } = req.body;

    if (!transcript) {
      return res.status(400).json({
        success: false,
        error: 'Missing transcript in request body',
      });
    }

    const details = await extractPaymentDetails(transcript);

    res.json({
      success: true,
      data: details,
    });
  } catch (error) {
    console.error('[VoiceSwap] AI payment details error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to extract payment details',
    });
  }
});

/**
 * POST /voiceswap/ai/process
 * Full AI-powered voice command processing
 * Combines intent parsing with wallet balance checking
 *
 * Body:
 * - transcript: Voice transcript
 * - userAddress: User's wallet address (optional, needed for balance/payment)
 * - merchantWallet: Merchant wallet (optional, for payment context)
 */
router.post('/ai/process', async (req, res) => {
  try {
    const { transcript, userAddress, merchantWallet } = req.body;

    if (!transcript) {
      return res.status(400).json({
        success: false,
        error: 'Missing transcript in request body',
      });
    }

    // Parse the intent
    const intent = await parseIntent(transcript);

    // Build context for response generation
    const context: {
      balance?: string;
      merchantName?: string;
    } = {};

    // If it's a balance or payment intent and we have an address, get balances
    if (userAddress && (intent.type === 'balance' || intent.type === 'payment')) {
      try {
        const balances = await getWalletBalances(userAddress);
        const usdcBalance = balances.tokens.find(t => t.symbol === 'USDC');
        context.balance = usdcBalance?.balance || '0';
      } catch (e) {
        console.error('[VoiceSwap] Failed to get balances:', e);
      }
    }

    // Add merchant context if available
    if (merchantWallet) {
      context.merchantName = `${merchantWallet.slice(0, 6)}...${merchantWallet.slice(-4)}`;
    } else if (intent.recipient) {
      context.merchantName = intent.recipient;
    }

    // Generate voice response with context
    const voiceResponse = generateResponse(intent, context);

    // Determine next action based on intent
    let nextAction: string;
    switch (intent.type) {
      case 'payment':
        nextAction = merchantWallet ? 'await_confirmation' : 'scan_qr';
        break;
      case 'balance':
        nextAction = 'show_balance';
        break;
      case 'swap':
        nextAction = 'prepare_swap';
        break;
      case 'confirm':
        nextAction = 'execute_transaction';
        break;
      case 'cancel':
        nextAction = 'cancel_transaction';
        break;
      case 'help':
        nextAction = 'show_help';
        break;
      default:
        nextAction = 'await_command';
    }

    res.json({
      success: true,
      data: {
        intent,
        voiceResponse,
        nextAction,
        context,
        timestamp: Date.now(),
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] AI process error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to process voice command',
    });
  }
});

/**
 * GET /voiceswap/ai/health
 * Check OpenAI API health and configuration
 */
router.get('/ai/health', async (_req, res) => {
  try {
    const health = await openaiHealthCheck();

    res.json({
      success: true,
      data: {
        openai: health,
        service: 'VoiceSwap AI',
        features: ['intent_parsing', 'payment_extraction', 'multilingual'],
        supportedLanguages: ['en', 'es'],
      },
    });
  } catch (error) {
    console.error('[VoiceSwap] AI health check error:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to check AI health',
    });
  }
});

export default router;
