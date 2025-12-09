/**
 * App State Store - Zustand
 */

import { create } from 'zustand';
import type { ConnectionState, MetaDevice } from '../services/MetaGlassesService';
import type { SwapIntent } from '../services/IntentParser';
import type { QuoteResponse, StatusResponse } from '../services/SwapService';

// Conversation state
export type ConversationState =
  | 'idle'           // Waiting for user
  | 'listening'      // Recording voice
  | 'processing'     // Parsing intent
  | 'confirming'     // Waiting for confirmation
  | 'executing'      // Running swap
  | 'complete'       // Done
  | 'error';         // Error state

// Transaction history item
export interface SwapHistoryItem {
  id: string;
  timestamp: number;
  intent: SwapIntent;
  quote?: QuoteResponse;
  txHash?: string;
  status: 'pending' | 'confirmed' | 'failed';
}

// App state interface
interface AppState {
  // Connection
  glassesState: ConnectionState;
  glassesDevice: MetaDevice | null;

  // Conversation
  conversationState: ConversationState;
  currentIntent: SwapIntent | null;
  currentQuote: QuoteResponse | null;
  lastError: string | null;

  // History
  swapHistory: SwapHistoryItem[];
  lastTxHash: string | null;

  // User settings
  walletAddress: string | null;
  backendUrl: string;

  // Actions
  setGlassesConnection: (state: ConnectionState, device?: MetaDevice) => void;
  setConversationState: (state: ConversationState) => void;
  setCurrentIntent: (intent: SwapIntent | null) => void;
  setCurrentQuote: (quote: QuoteResponse | null) => void;
  setError: (error: string | null) => void;
  addToHistory: (item: SwapHistoryItem) => void;
  updateHistoryStatus: (txHash: string, status: SwapHistoryItem['status']) => void;
  setWalletAddress: (address: string | null) => void;
  setBackendUrl: (url: string) => void;
  reset: () => void;
}

// Initial state
const initialState = {
  glassesState: 'disconnected' as ConnectionState,
  glassesDevice: null,
  conversationState: 'idle' as ConversationState,
  currentIntent: null,
  currentQuote: null,
  lastError: null,
  swapHistory: [],
  lastTxHash: null,
  walletAddress: null,
  backendUrl: 'http://localhost:4021',
};

// Create store
export const useAppStore = create<AppState>((set, get) => ({
  ...initialState,

  setGlassesConnection: (state, device) =>
    set({
      glassesState: state,
      glassesDevice: device || null,
    }),

  setConversationState: (state) =>
    set({ conversationState: state }),

  setCurrentIntent: (intent) =>
    set({ currentIntent: intent }),

  setCurrentQuote: (quote) =>
    set({ currentQuote: quote }),

  setError: (error) =>
    set({
      lastError: error,
      conversationState: error ? 'error' : get().conversationState,
    }),

  addToHistory: (item) =>
    set((state) => ({
      swapHistory: [item, ...state.swapHistory].slice(0, 50), // Keep last 50
      lastTxHash: item.txHash || state.lastTxHash,
    })),

  updateHistoryStatus: (txHash, status) =>
    set((state) => ({
      swapHistory: state.swapHistory.map((item) =>
        item.txHash === txHash ? { ...item, status } : item
      ),
    })),

  setWalletAddress: (address) =>
    set({ walletAddress: address }),

  setBackendUrl: (url) =>
    set({ backendUrl: url }),

  reset: () =>
    set({
      conversationState: 'idle',
      currentIntent: null,
      currentQuote: null,
      lastError: null,
    }),
}));

// Selectors
export const selectIsConnected = (state: AppState) =>
  state.glassesState === 'connected';

export const selectCanSwap = (state: AppState) =>
  state.walletAddress !== null && state.glassesState === 'connected';

export const selectLastSwap = (state: AppState) =>
  state.swapHistory[0] || null;
