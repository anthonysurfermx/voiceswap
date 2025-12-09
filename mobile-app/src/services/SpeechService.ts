/**
 * Speech Service - Text-to-Speech and Speech-to-Text
 *
 * Handles voice input/output for the app
 */

import * as Speech from 'expo-speech';
import { Platform } from 'react-native';

// Types
export interface SpeechConfig {
  language?: string;
  pitch?: number;
  rate?: number;
  voice?: string;
}

export interface TranscriptionResult {
  text: string;
  confidence: number;
  isFinal: boolean;
}

export type SpeechEventCallback = (result: TranscriptionResult) => void;
export type SpeechErrorCallback = (error: Error) => void;

// Default configuration
const DEFAULT_CONFIG: SpeechConfig = {
  language: 'en-US',
  pitch: 1.0,
  rate: Platform.OS === 'ios' ? 0.5 : 0.9, // iOS speaks faster
};

/**
 * SpeechService class for TTS and STT
 */
class SpeechService {
  private config: SpeechConfig;
  private isSpeaking: boolean = false;
  private isListening: boolean = false;
  private speechQueue: string[] = [];

  // Voice recognition (will be connected to @react-native-voice/voice)
  private onTranscription: SpeechEventCallback | null = null;
  private onError: SpeechErrorCallback | null = null;

  constructor(config: SpeechConfig = {}) {
    this.config = { ...DEFAULT_CONFIG, ...config };
  }

  /**
   * Initialize the speech service
   */
  async initialize(): Promise<void> {
    // Check if TTS is available
    const voices = await Speech.getAvailableVoicesAsync();
    console.log(`[SpeechService] Available voices: ${voices.length}`);

    // Select best voice for English
    const englishVoice = voices.find(
      (v) => v.language.startsWith('en') && v.quality === 'Enhanced'
    ) || voices.find(
      (v) => v.language.startsWith('en')
    );

    if (englishVoice) {
      this.config.voice = englishVoice.identifier;
      console.log(`[SpeechService] Selected voice: ${englishVoice.name}`);
    }
  }

  /**
   * Speak text using TTS
   */
  async speak(text: string, interrupt: boolean = false): Promise<void> {
    if (interrupt) {
      await this.stopSpeaking();
      this.speechQueue = [];
    }

    // Add to queue if currently speaking
    if (this.isSpeaking && !interrupt) {
      this.speechQueue.push(text);
      return;
    }

    return this.speakNow(text);
  }

  /**
   * Internal method to speak immediately
   */
  private async speakNow(text: string): Promise<void> {
    this.isSpeaking = true;

    return new Promise((resolve, reject) => {
      Speech.speak(text, {
        language: this.config.language,
        pitch: this.config.pitch,
        rate: this.config.rate,
        voice: this.config.voice,
        onStart: () => {
          console.log(`[SpeechService] Speaking: "${text.substring(0, 50)}..."`);
        },
        onDone: () => {
          this.isSpeaking = false;
          this.processQueue();
          resolve();
        },
        onStopped: () => {
          this.isSpeaking = false;
          resolve();
        },
        onError: (error) => {
          this.isSpeaking = false;
          console.error('[SpeechService] Error:', error);
          reject(new Error('Speech synthesis failed'));
        },
      });
    });
  }

  /**
   * Process queued speech
   */
  private processQueue(): void {
    if (this.speechQueue.length > 0 && !this.isSpeaking) {
      const next = this.speechQueue.shift();
      if (next) {
        this.speakNow(next);
      }
    }
  }

  /**
   * Stop speaking
   */
  async stopSpeaking(): Promise<void> {
    if (this.isSpeaking) {
      await Speech.stop();
      this.isSpeaking = false;
    }
  }

  /**
   * Check if currently speaking
   */
  getIsSpeaking(): boolean {
    return this.isSpeaking;
  }

  /**
   * Start listening for voice input
   * Note: This requires @react-native-voice/voice to be properly configured
   */
  async startListening(
    onTranscription: SpeechEventCallback,
    onError?: SpeechErrorCallback
  ): Promise<void> {
    if (this.isListening) {
      console.warn('[SpeechService] Already listening');
      return;
    }

    this.onTranscription = onTranscription;
    this.onError = onError || null;
    this.isListening = true;

    // In a real implementation, this would use @react-native-voice/voice:
    // Voice.onSpeechResults = this.handleSpeechResults.bind(this);
    // Voice.onSpeechPartialResults = this.handlePartialResults.bind(this);
    // Voice.onSpeechError = this.handleSpeechError.bind(this);
    // await Voice.start(this.config.language);

    console.log('[SpeechService] Started listening (mock mode)');
  }

  /**
   * Stop listening for voice input
   */
  async stopListening(): Promise<void> {
    if (!this.isListening) return;

    this.isListening = false;
    this.onTranscription = null;
    this.onError = null;

    // In a real implementation:
    // await Voice.stop();

    console.log('[SpeechService] Stopped listening');
  }

  /**
   * Check if currently listening
   */
  getIsListening(): boolean {
    return this.isListening;
  }

  /**
   * Simulate voice input (for testing without hardware)
   */
  simulateVoiceInput(text: string): void {
    if (this.onTranscription) {
      this.onTranscription({
        text,
        confidence: 0.95,
        isFinal: true,
      });
    }
  }

  // Pre-built responses for common scenarios
  static readonly RESPONSES = {
    // Optimistic, concise responses
    WELCOME: 'Voice Swap ready. Try "swap 100 USDC to ETH".',
    LISTENING: 'Listening.',
    NOT_UNDERSTOOD: 'Sorry, try again. Say "swap" plus amount and tokens.',
    CONFIRM_SWAP: (quote: string) => `${quote} Confirm?`,
    SWAP_CANCELLED: 'Cancelled.',
    SWAP_EXECUTING: 'Swapping now...', // Short, optimistic
    SWAP_SUBMITTED: 'Done! Confirming on chain.',
    NETWORK_ERROR: 'Connection issue. Trying again.',
    HELP: 'Say: Swap amount token to token. Like: Swap 100 USDC to ETH. Or: Check status, gas tank balance.',
    GLASSES_CONNECTED: 'Glasses connected.',
    GLASSES_DISCONNECTED: 'Glasses disconnected.',
    PAYMENT_REQUIRED: 'Authorizing payment.',

    // Optimistic feedback during processing
    GETTING_QUOTE: 'Getting price...',
    QUOTE_READY: 'Got it.',
    PREPARING_SWAP: 'Preparing swap...',
    SENDING_TX: 'Sending to blockchain...',
    TX_PENDING: 'Submitted. Waiting for confirmation.',
    TX_CONFIRMED: 'Confirmed!',
    TX_FAILED: 'Transaction failed. Try again.',
  };

  /**
   * Humanize large numbers for speech
   * Examples:
   *   1234567 -> "1.23 million"
   *   12345 -> "12.3 thousand"
   *   1234 -> "twelve hundred thirty four"
   *   123.456789 -> "123.46"
   */
  static humanizeNumber(value: number | string, decimals: number = 2): string {
    const num = typeof value === 'string' ? parseFloat(value) : value;

    if (isNaN(num)) return String(value);

    const absNum = Math.abs(num);
    const sign = num < 0 ? 'negative ' : '';

    // Very large numbers
    if (absNum >= 1_000_000_000) {
      return `${sign}${(num / 1_000_000_000).toFixed(decimals)} billion`;
    }
    if (absNum >= 1_000_000) {
      return `${sign}${(num / 1_000_000).toFixed(decimals)} million`;
    }
    if (absNum >= 10_000) {
      return `${sign}${(num / 1_000).toFixed(decimals)} thousand`;
    }

    // Medium numbers - use commas mentally but speak naturally
    if (absNum >= 1_000) {
      const whole = Math.floor(absNum);
      const decimal = absNum - whole;
      const thousands = Math.floor(whole / 1000);
      const hundreds = whole % 1000;

      if (decimal > 0) {
        return `${sign}${whole.toLocaleString()}.${decimal.toFixed(decimals).split('.')[1]}`;
      }
      if (hundreds === 0) {
        return `${sign}${thousands} thousand`;
      }
      return `${sign}${whole.toLocaleString()}`;
    }

    // Small numbers - round to reasonable precision
    if (absNum < 0.001) {
      return `${sign}${num.toExponential(2)}`;
    }
    if (absNum < 1) {
      return `${sign}${num.toFixed(Math.max(decimals, 4))}`;
    }

    return `${sign}${num.toFixed(decimals)}`;
  }

  /**
   * Humanize token amounts based on token type
   */
  static humanizeTokenAmount(amount: string, symbol: string): string {
    const num = parseFloat(amount);

    // Stablecoins - use dollars
    if (['USDC', 'USDT', 'DAI', 'BUSD'].includes(symbol.toUpperCase())) {
      if (num >= 1000) {
        return `${SpeechService.humanizeNumber(num, 0)} ${symbol}`;
      }
      return `${num.toFixed(2)} ${symbol}`;
    }

    // ETH - show more precision for small amounts
    if (['ETH', 'WETH'].includes(symbol.toUpperCase())) {
      if (num >= 10) {
        return `${num.toFixed(2)} ${symbol}`;
      }
      if (num >= 1) {
        return `${num.toFixed(3)} ${symbol}`;
      }
      if (num >= 0.01) {
        return `${num.toFixed(4)} ${symbol}`;
      }
      return `${num.toFixed(6)} ${symbol}`;
    }

    // BTC - always show precision
    if (['BTC', 'WBTC'].includes(symbol.toUpperCase())) {
      if (num >= 1) {
        return `${num.toFixed(4)} ${symbol}`;
      }
      return `${num.toFixed(6)} ${symbol}`;
    }

    // Default handling
    if (num >= 1000) {
      return `${SpeechService.humanizeNumber(num, 1)} ${symbol}`;
    }
    return `${num.toFixed(4)} ${symbol}`;
  }

  /**
   * Create optimistic swap confirmation message
   */
  static formatOptimisticQuote(
    amountIn: string,
    symbolIn: string,
    amountOut: string,
    symbolOut: string,
    priceImpact?: string
  ): string {
    const humanIn = SpeechService.humanizeTokenAmount(amountIn, symbolIn);
    const humanOut = SpeechService.humanizeTokenAmount(amountOut, symbolOut);

    let message = `${humanIn} gets you ${humanOut}.`;

    // Only mention price impact if significant
    if (priceImpact) {
      const impact = parseFloat(priceImpact);
      if (impact > 1) {
        message += ` ${impact.toFixed(1)}% impact.`;
      }
    }

    return message;
  }

  /**
   * Create short execution confirmation
   */
  static formatSwapResult(txHash: string, amountOut: string, symbolOut: string): string {
    const humanOut = SpeechService.humanizeTokenAmount(amountOut, symbolOut);
    return `Sent! You're getting ${humanOut}.`;
  }
}

// Export singleton instance
export const speechService = new SpeechService();

// Export class for testing/customization
export default SpeechService;
