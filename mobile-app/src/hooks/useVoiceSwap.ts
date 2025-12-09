/**
 * useVoiceSwap Hook - Main orchestrator for voice-activated swaps
 *
 * Integrates Session Keys (ERC-4337) for gasless, signature-less swaps.
 * User authorizes a session once, then can execute swaps without
 * signing each transaction individually.
 */

import { useCallback, useEffect, useRef, useState } from 'react';
import { useAppStore } from '../store/appStore';
import { speechService } from '../services/SpeechService';
import { swapService, PaymentRequiredError, InsufficientGasTankError } from '../services/SwapService';
import { metaGlassesService } from '../services/MetaGlassesService';
import { sessionKeyService, type SessionKeyConfig } from '../services/SessionKeyService';
import { gasTankService } from '../services/GasTankService';
import {
  parseVoiceCommand,
  parseVoiceCommandAsync,
  describeIntent,
  validateIntent,
  type SwapIntent,
} from '../services/IntentParser';
import SpeechService from '../services/SpeechService';

export function useVoiceSwap() {
  const {
    conversationState,
    currentIntent,
    currentQuote,
    walletAddress,
    setConversationState,
    setCurrentIntent,
    setCurrentQuote,
    setError,
    addToHistory,
    reset,
  } = useAppStore();

  // Keep track of pending confirmation
  const pendingSwapRef = useRef<SwapIntent | null>(null);

  // Session Key state
  const [sessionInfo, setSessionInfo] = useState<{
    active: boolean;
    expiresIn?: string;
    remaining?: { perTx: number; total: number };
  }>({ active: false });

  /**
   * Update session info periodically
   */
  const updateSessionInfo = useCallback(() => {
    const info = sessionKeyService.getSessionInfo();
    setSessionInfo(info);
  }, []);

  /**
   * Initialize services
   */
  useEffect(() => {
    const init = async () => {
      await speechService.initialize();
      await metaGlassesService.initialize();

      // Initialize session key service if wallet is connected
      if (walletAddress) {
        await sessionKeyService.initialize(walletAddress);
      }

      // Welcome message
      await speechService.speak(SpeechService.RESPONSES.WELCOME);
    };

    init();

    // Update session info every 30 seconds
    const sessionInterval = setInterval(updateSessionInfo, 30000);
    return () => clearInterval(sessionInterval);
  }, [walletAddress, updateSessionInfo]);

  /**
   * Create or extend session for seamless swaps
   * This should be called when user wants to enable "quick swap" mode
   */
  const createSession = useCallback(async (options?: {
    maxAmountPerTx?: number;
    maxTotalAmount?: number;
    durationMs?: number;
  }) => {
    if (!walletAddress) {
      await speechService.speak("Please connect your wallet first to create a session.");
      return null;
    }

    try {
      // Initialize service if needed
      await sessionKeyService.initialize(walletAddress);

      // Create session (in production, this would require biometric auth)
      const session = await sessionKeyService.createSession(options);

      updateSessionInfo();

      await speechService.speak(
        `Session created. You can now swap up to $${session.permissions.maxTotalAmount} ` +
        `without signing each transaction. Session expires in 2 hours.`
      );

      return session;
    } catch (error) {
      console.error('[useVoiceSwap] Session creation failed:', error);
      await speechService.speak("Failed to create session. Please try again.");
      return null;
    }
  }, [walletAddress, updateSessionInfo]);

  /**
   * Revoke current session
   */
  const revokeSession = useCallback(async () => {
    sessionKeyService.revokeSession();
    updateSessionInfo();
    await speechService.speak("Session revoked. You'll need to confirm each swap individually.");
  }, [updateSessionInfo]);

  /**
   * Handle voice transcription result
   * Uses async LLM parser for better accuracy with Spanish, spoken numbers, etc.
   */
  const handleTranscription = useCallback(async (text: string) => {
    console.log(`[useVoiceSwap] Transcription: "${text}"`);

    // Parse the voice command using regex + LLM fallback
    // This handles Spanish, Spanglish, spoken numbers ("cien"), "all" amounts
    const intent = await parseVoiceCommandAsync(text);
    console.log(`[useVoiceSwap] Intent (${intent.parsedBy}):`, intent);

    // Handle based on current state and intent
    await processIntent(intent);
  }, [conversationState, currentIntent]);

  /**
   * Process a parsed intent
   */
  const processIntent = async (intent: SwapIntent) => {
    setCurrentIntent(intent);

    switch (intent.action) {
      case 'swap':
        await handleSwapIntent(intent);
        break;

      case 'quote':
        await handleQuoteIntent(intent);
        break;

      case 'confirm':
        await handleConfirmation();
        break;

      case 'cancel':
        await handleCancellation();
        break;

      case 'status':
        await handleStatusCheck();
        break;

      case 'balance':
        await handleBalanceCheck();
        break;

      case 'help':
        await speechService.speak(SpeechService.RESPONSES.HELP);
        setConversationState('idle');
        break;

      case 'enable_session':
        await handleEnableSession();
        break;

      case 'disable_session':
        await handleDisableSession();
        break;

      case 'session_status':
        await handleSessionStatus();
        break;

      case 'gas_tank_status':
        await handleGasTankStatus();
        break;

      case 'gas_tank_refill':
        await handleGasTankRefill();
        break;

      case 'unknown':
      default:
        await speechService.speak(SpeechService.RESPONSES.NOT_UNDERSTOOD);
        setConversationState('idle');
        break;
    }
  };

  /**
   * Handle Gas Tank status command
   */
  const handleGasTankStatus = async () => {
    const statusText = gasTankService.formatBalanceForSpeech();
    await speechService.speak(statusText);
    setConversationState('idle');
  };

  /**
   * Handle Gas Tank refill instructions
   */
  const handleGasTankRefill = async () => {
    const instructionsText = gasTankService.formatDepositInstructionsForSpeech();
    await speechService.speak(instructionsText);
    setConversationState('idle');
  };

  /**
   * Handle enable session command
   */
  const handleEnableSession = async () => {
    if (sessionKeyService.hasValidSession()) {
      const info = sessionKeyService.getSessionInfo();
      await speechService.speak(
        `Quick swap is already enabled. You have $${info.remaining?.total} remaining. ` +
        `Session expires in ${info.expiresIn}.`
      );
      setConversationState('idle');
      return;
    }

    await speechService.speak(
      "Enabling quick swap mode. This will allow swaps up to $100 each, " +
      "$500 total, without confirming each one. Please authenticate."
    );

    // Create session (in production, triggers FaceID/TouchID)
    await createSession();
    setConversationState('idle');
  };

  /**
   * Handle disable session command
   */
  const handleDisableSession = async () => {
    if (!sessionKeyService.hasValidSession()) {
      await speechService.speak("Quick swap mode is not active.");
      setConversationState('idle');
      return;
    }

    await revokeSession();
    setConversationState('idle');
  };

  /**
   * Handle session status command
   */
  const handleSessionStatus = async () => {
    const info = sessionKeyService.getSessionInfo();

    if (!info.active) {
      await speechService.speak(
        "Quick swap mode is not active. Say 'enable quick swap' to turn it on."
      );
    } else {
      await speechService.speak(
        `Quick swap is active. You have $${info.remaining?.total.toFixed(2)} remaining ` +
        `out of your session limit. Maximum $${info.remaining?.perTx} per swap. ` +
        `Session expires in ${info.expiresIn}.`
      );
    }

    setConversationState('idle');
  };

  /**
   * Handle swap intent
   */
  const handleSwapIntent = async (intent: SwapIntent) => {
    // Validate intent parameters
    const validation = validateIntent(intent);
    if (!validation.valid) {
      await speechService.speak(
        `I need more information. Please specify: ${validation.missing.join(', ')}.`
      );
      setConversationState('idle');
      return;
    }

    setConversationState('processing');

    try {
      // Optimistic feedback - don't wait
      speechService.speak(SpeechService.RESPONSES.GETTING_QUOTE);

      // Get quote first
      const quote = await swapService.getQuote(
        intent.tokenIn!,
        intent.tokenOut!,
        intent.amountIn!
      );

      setCurrentQuote(quote);

      // Estimate USD value for session key validation
      // In production, get actual USD price from oracle
      const estimatedUSD = parseFloat(intent.amountIn!) * (intent.tokenIn === 'USDC' ? 1 : 2000);

      // Check if we have a valid session that can execute this swap
      if (sessionKeyService.hasValidSession()) {
        const canExec = sessionKeyService.canExecute(estimatedUSD, 'swap');

        if (canExec.allowed) {
          // Session is valid and amount is within limits - execute immediately!
          await speechService.speak(
            `Quick swap: ${swapService.formatQuoteForSpeech(quote)}. Executing now.`
          );

          // Execute with session key (no manual confirmation needed)
          pendingSwapRef.current = intent;
          await executeWithSessionKey(intent, quote, estimatedUSD);
          return;
        } else {
          // Session exists but this swap exceeds limits
          await speechService.speak(
            `${canExec.reason} Would you like to confirm this swap manually?`
          );
        }
      }

      // No valid session or exceeds limits - ask for confirmation
      const quoteText = swapService.formatQuoteForSpeech(quote);
      await speechService.speak(SpeechService.RESPONSES.CONFIRM_SWAP(quoteText));

      // Store pending swap
      pendingSwapRef.current = intent;
      setConversationState('confirming');

    } catch (error) {
      handleError(error);
    }
  };

  /**
   * Execute swap using session key (no manual confirmation)
   */
  const executeWithSessionKey = async (
    intent: SwapIntent,
    quote: any,
    estimatedUSD: number
  ) => {
    if (!walletAddress) {
      await speechService.speak("Wallet not connected.");
      setConversationState('idle');
      return;
    }

    setConversationState('executing');

    try {
      // Get the swap calldata
      const route = await swapService.getRoute(
        intent.tokenIn!,
        intent.tokenOut!,
        intent.amountIn!,
        walletAddress,
        0.5
      );

      // Sign with session key
      const { signature, userOp } = await sessionKeyService.signUserOperation(
        route.calldata,
        estimatedUSD
      );

      // Execute the swap (in production, this would go through a bundler)
      const result = await swapService.executeSwap({
        tokenIn: intent.tokenIn!,
        tokenOut: intent.tokenOut!,
        amountIn: intent.amountIn!,
        recipient: walletAddress,
        slippageTolerance: 0.5,
        // Include session signature for bundler
        sessionSignature: signature,
      });

      // Update session info after spending
      updateSessionInfo();

      // Add to history
      addToHistory({
        id: Date.now().toString(),
        timestamp: Date.now(),
        intent,
        quote,
        txHash: result.txHash,
        status: result.status === 'submitted' ? 'pending' : 'failed',
      });

      // Announce result
      const resultText = swapService.formatExecutionForSpeech(result);
      await speechService.speak(resultText);

      // Reset state
      pendingSwapRef.current = null;
      setConversationState('complete');

      // Start polling for confirmation
      if (result.txHash) {
        pollTransactionStatus(result.txHash);
      }

    } catch (error) {
      handleError(error);
    }
  };

  /**
   * Handle quote-only intent
   */
  const handleQuoteIntent = async (intent: SwapIntent) => {
    const validation = validateIntent(intent);
    if (!validation.valid) {
      await speechService.speak(
        `I need more information. Please specify: ${validation.missing.join(', ')}.`
      );
      setConversationState('idle');
      return;
    }

    setConversationState('processing');

    try {
      const quote = await swapService.getQuote(
        intent.tokenIn!,
        intent.tokenOut!,
        intent.amountIn!
      );

      setCurrentQuote(quote);

      const quoteText = swapService.formatQuoteForSpeech(quote);
      await speechService.speak(quoteText);

      setConversationState('idle');

    } catch (error) {
      handleError(error);
    }
  };

  /**
   * Handle confirmation
   */
  const handleConfirmation = async () => {
    const pending = pendingSwapRef.current;

    if (!pending || conversationState !== 'confirming') {
      await speechService.speak("There's nothing to confirm.");
      setConversationState('idle');
      return;
    }

    if (!walletAddress) {
      await speechService.speak("Please connect your wallet first.");
      setConversationState('idle');
      return;
    }

    setConversationState('executing');

    // Optimistic feedback - don't wait, start executing immediately
    speechService.speak(SpeechService.RESPONSES.SWAP_EXECUTING);

    try {
      const result = await swapService.executeSwap({
        tokenIn: pending.tokenIn!,
        tokenOut: pending.tokenOut!,
        amountIn: pending.amountIn!,
        recipient: walletAddress,
        slippageTolerance: 0.5,
      });

      // Add to history
      addToHistory({
        id: Date.now().toString(),
        timestamp: Date.now(),
        intent: pending,
        quote: currentQuote || undefined,
        txHash: result.txHash,
        status: result.status === 'submitted' ? 'pending' : 'failed',
      });

      // Announce result with amount info if available
      const resultText = swapService.formatExecutionForSpeech(
        result,
        currentQuote?.tokenOut.amount,
        currentQuote?.tokenOut.symbol
      );
      await speechService.speak(resultText);

      // Reset state
      pendingSwapRef.current = null;
      setConversationState('complete');

      // Start polling for confirmation
      if (result.txHash) {
        pollTransactionStatus(result.txHash);
      }

    } catch (error) {
      handleError(error);
    }
  };

  /**
   * Handle cancellation
   */
  const handleCancellation = async () => {
    pendingSwapRef.current = null;
    await speechService.speak(SpeechService.RESPONSES.SWAP_CANCELLED);
    reset();
  };

  /**
   * Handle status check
   */
  const handleStatusCheck = async () => {
    setConversationState('processing');

    try {
      const status = await swapService.getStatus();
      const statusText = swapService.formatStatusForSpeech(status);
      await speechService.speak(statusText);
      setConversationState('idle');

    } catch (error) {
      await speechService.speak("I don't have a recent transaction to check.");
      setConversationState('idle');
    }
  };

  /**
   * Handle balance check
   */
  const handleBalanceCheck = async () => {
    // TODO: Implement wallet balance check
    await speechService.speak(
      "Balance checking is not yet implemented. Please check your wallet app."
    );
    setConversationState('idle');
  };

  /**
   * Poll transaction status until confirmed
   */
  const pollTransactionStatus = async (txHash: string, attempts = 0) => {
    if (attempts > 30) return; // Stop after 30 attempts (~5 minutes)

    try {
      const status = await swapService.getStatus(txHash);

      if (status.status === 'confirmed') {
        await speechService.speak(SpeechService.RESPONSES.TX_CONFIRMED);
        useAppStore.getState().updateHistoryStatus(txHash, 'confirmed');
        return;
      }

      if (status.status === 'failed') {
        await speechService.speak(SpeechService.RESPONSES.TX_FAILED);
        useAppStore.getState().updateHistoryStatus(txHash, 'failed');
        return;
      }

      // Still pending, check again in 10 seconds
      setTimeout(() => pollTransactionStatus(txHash, attempts + 1), 10000);

    } catch (error) {
      console.error('[useVoiceSwap] Status poll error:', error);
    }
  };

  /**
   * Handle errors
   */
  const handleError = async (error: unknown) => {
    console.error('[useVoiceSwap] Error:', error);

    if (error instanceof InsufficientGasTankError) {
      // Gas Tank is empty - prompt user to refill
      const swapsRemaining = gasTankService.getSwapsRemaining();
      if (swapsRemaining === 0) {
        await speechService.speak(
          "Your Gas Tank is empty and cannot process this request. " +
          "Say 'refill gas tank' for deposit instructions."
        );
      } else {
        await speechService.speak(
          `Your Gas Tank is low. You have ${swapsRemaining} swaps remaining. ` +
          "Say 'refill gas tank' to add more funds."
        );
      }
    } else if (error instanceof PaymentRequiredError) {
      await speechService.speak(SpeechService.RESPONSES.PAYMENT_REQUIRED);
      // Suggest using Gas Tank
      await speechService.speak(
        "Tip: Deposit USDC to your Gas Tank for faster, cheaper payments."
      );
    } else if (error instanceof Error) {
      setError(error.message);
      await speechService.speak(`Error: ${error.message}`);
    } else {
      await speechService.speak(SpeechService.RESPONSES.NETWORK_ERROR);
    }

    setConversationState('error');
  };

  /**
   * Start listening for voice commands
   */
  const startListening = useCallback(async () => {
    if (conversationState === 'listening') return;

    setConversationState('listening');
    await speechService.speak(SpeechService.RESPONSES.LISTENING, true);

    await speechService.startListening(
      (result) => {
        if (result.isFinal) {
          handleTranscription(result.text);
        }
      },
      (error) => {
        handleError(error);
      }
    );
  }, [conversationState, handleTranscription]);

  /**
   * Stop listening
   */
  const stopListening = useCallback(async () => {
    await speechService.stopListening();
    if (conversationState === 'listening') {
      setConversationState('idle');
    }
  }, [conversationState]);

  /**
   * Simulate voice input (for testing)
   */
  const simulateVoiceInput = useCallback((text: string) => {
    handleTranscription(text);
  }, [handleTranscription]);

  // Gas Tank state
  const gasTankState = gasTankService.getState();

  return {
    // State
    conversationState,
    currentIntent,
    currentQuote,
    isListening: conversationState === 'listening',
    isProcessing: conversationState === 'processing' || conversationState === 'executing',

    // Session Key state
    sessionInfo,
    hasActiveSession: sessionInfo.active,

    // Gas Tank state
    gasTankBalance: gasTankState.balance,
    gasTankSwapsRemaining: gasTankService.getSwapsRemaining(),
    isGasTankLow: gasTankService.isBalanceLow(),

    // Actions
    startListening,
    stopListening,
    simulateVoiceInput,
    reset,

    // Session Key actions
    createSession,
    revokeSession,

    // Gas Tank actions
    getGasTankDepositInfo: () => gasTankService.getDepositInfo(),
  };
}
