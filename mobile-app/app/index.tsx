import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  SafeAreaView,
  TextInput,
  ScrollView,
  ActivityIndicator,
} from 'react-native';
import { Link } from 'expo-router';
import { useAppStore, selectIsConnected } from '../src/store/appStore';
import { useVoiceSwap } from '../src/hooks/useVoiceSwap';
import { metaGlassesService } from '../src/services/MetaGlassesService';
import { describeIntent } from '../src/services/IntentParser';

export default function HomeScreen() {
  const {
    conversationState,
    currentIntent,
    currentQuote,
    isListening,
    isProcessing,
    startListening,
    stopListening,
    simulateVoiceInput,
    reset,
    // Session Key features
    sessionInfo,
    hasActiveSession,
    createSession,
    revokeSession,
    // Gas Tank features
    gasTankBalance,
    gasTankSwapsRemaining,
    isGasTankLow,
  } = useVoiceSwap();

  const glassesState = useAppStore((s) => s.glassesState);
  const glassesDevice = useAppStore((s) => s.glassesDevice);
  const lastError = useAppStore((s) => s.lastError);
  const isConnected = useAppStore(selectIsConnected);

  // For testing without voice
  const [testInput, setTestInput] = useState('');

  const handleMicPress = () => {
    if (isListening) {
      stopListening();
    } else {
      startListening();
    }
  };

  const handleTestSubmit = () => {
    if (testInput.trim()) {
      simulateVoiceInput(testInput.trim());
      setTestInput('');
    }
  };

  const handleConnectGlasses = () => {
    if (isConnected) {
      metaGlassesService.mockDisconnect();
    } else {
      metaGlassesService.startScanning();
    }
  };

  return (
    <SafeAreaView style={styles.container}>
      {/* Header */}
      <View style={styles.header}>
        <Text style={styles.title}>🎙️ VoiceSwap</Text>
        <Text style={styles.subtitle}>Voice Payments on Monad</Text>

        <View style={styles.headerButtons}>
          <Link href="/history" asChild>
            <TouchableOpacity style={styles.headerButton}>
              <Text style={styles.headerButtonText}>📜 History</Text>
            </TouchableOpacity>
          </Link>
          <Link href="/settings" asChild>
            <TouchableOpacity style={styles.headerButton}>
              <Text style={styles.headerButtonText}>⚙️ Settings</Text>
            </TouchableOpacity>
          </Link>
        </View>
      </View>

      {/* Connection Status */}
      <TouchableOpacity style={styles.connectionCard} onPress={handleConnectGlasses}>
        <View style={styles.connectionStatus}>
          <View
            style={[
              styles.statusDot,
              { backgroundColor: isConnected ? '#836EF9' : '#f87171' },
            ]}
          />
          <Text style={styles.connectionText}>
            {isConnected
              ? `Connected: ${glassesDevice?.name}`
              : 'Tap to connect Meta Glasses'}
          </Text>
        </View>
        {glassesState === 'connecting' && (
          <ActivityIndicator size="small" color="#818cf8" />
        )}
      </TouchableOpacity>

      {/* Session Key Status */}
      <TouchableOpacity
        style={[styles.sessionCard, hasActiveSession && styles.sessionCardActive]}
        onPress={() => hasActiveSession ? revokeSession() : createSession()}
      >
        <View style={styles.sessionHeader}>
          <Text style={styles.sessionIcon}>{hasActiveSession ? '⚡' : '🔒'}</Text>
          <Text style={styles.sessionTitle}>
            {hasActiveSession ? 'Quick Swap Active' : 'Quick Swap Disabled'}
          </Text>
        </View>
        {hasActiveSession && sessionInfo.remaining && (
          <View style={styles.sessionDetails}>
            <Text style={styles.sessionLimit}>
              ${sessionInfo.remaining.total.toFixed(2)} remaining
            </Text>
            <Text style={styles.sessionExpiry}>
              Expires in {sessionInfo.expiresIn}
            </Text>
          </View>
        )}
        <Text style={styles.sessionHint}>
          {hasActiveSession
            ? 'Tap to disable • Swaps execute without confirmation'
            : 'Tap to enable • Skip confirmation for small swaps'}
        </Text>
      </TouchableOpacity>

      {/* Gas Tank Status */}
      <View style={[styles.gasTankCard, isGasTankLow && styles.gasTankCardLow]}>
        <View style={styles.gasTankHeader}>
          <Text style={styles.gasTankIcon}>{isGasTankLow ? '⛽' : '🔋'}</Text>
          <Text style={styles.gasTankTitle}>Gas Tank</Text>
          {isGasTankLow && (
            <View style={styles.gasTankWarning}>
              <Text style={styles.gasTankWarningText}>LOW</Text>
            </View>
          )}
        </View>
        <View style={styles.gasTankDetails}>
          <Text style={styles.gasTankBalance}>${gasTankBalance.toFixed(3)}</Text>
          <Text style={styles.gasTankSwaps}>
            ~{gasTankSwapsRemaining} swaps remaining
          </Text>
        </View>
        <Text style={styles.gasTankHint}>
          Say "refill gas tank" to add funds • Powers x402 API calls
        </Text>
      </View>

      {/* Main Content */}
      <ScrollView style={styles.content} contentContainerStyle={styles.contentContainer}>
        {/* State Display */}
        <View style={styles.stateCard}>
          <Text style={styles.stateLabel}>Status</Text>
          <Text style={styles.stateValue}>{conversationState.toUpperCase()}</Text>
        </View>

        {/* Current Intent */}
        {currentIntent && (
          <View style={styles.intentCard}>
            <Text style={styles.cardTitle}>Current Command</Text>
            <Text style={styles.intentText}>{describeIntent(currentIntent)}</Text>
            <Text style={styles.rawText}>"{currentIntent.rawText}"</Text>
          </View>
        )}

        {/* Quote Display */}
        {currentQuote && (
          <View style={styles.quoteCard}>
            <Text style={styles.cardTitle}>Quote</Text>
            <View style={styles.quoteRow}>
              <Text style={styles.quoteLabel}>From:</Text>
              <Text style={styles.quoteValue}>
                {currentQuote.tokenIn.amount} {currentQuote.tokenIn.symbol}
              </Text>
            </View>
            <View style={styles.quoteRow}>
              <Text style={styles.quoteLabel}>To:</Text>
              <Text style={styles.quoteValue}>
                {currentQuote.tokenOut.amount} {currentQuote.tokenOut.symbol}
              </Text>
            </View>
            <View style={styles.quoteRow}>
              <Text style={styles.quoteLabel}>Impact:</Text>
              <Text style={styles.quoteValue}>{currentQuote.priceImpact}%</Text>
            </View>
          </View>
        )}

        {/* Error Display */}
        {lastError && (
          <View style={styles.errorCard}>
            <Text style={styles.errorText}>⚠️ {lastError}</Text>
            <TouchableOpacity onPress={reset}>
              <Text style={styles.errorDismiss}>Dismiss</Text>
            </TouchableOpacity>
          </View>
        )}

        {/* Test Input (for development) */}
        <View style={styles.testSection}>
          <Text style={styles.testLabel}>Test Voice Command:</Text>
          <View style={styles.testInputRow}>
            <TextInput
              style={styles.testInput}
              value={testInput}
              onChangeText={setTestInput}
              placeholder="e.g., Swap 100 USDC to ETH"
              placeholderTextColor="#6b7280"
              onSubmitEditing={handleTestSubmit}
            />
            <TouchableOpacity style={styles.testButton} onPress={handleTestSubmit}>
              <Text style={styles.testButtonText}>Send</Text>
            </TouchableOpacity>
          </View>

          {/* Quick test buttons */}
          <View style={styles.quickButtons}>
            <TouchableOpacity
              style={styles.quickButton}
              onPress={() => simulateVoiceInput('Swap 100 USDC to ETH')}
            >
              <Text style={styles.quickButtonText}>Swap 100 USDC → ETH</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.quickButton}
              onPress={() => simulateVoiceInput('yes')}
            >
              <Text style={styles.quickButtonText}>Confirm</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.quickButton}
              onPress={() => simulateVoiceInput('check status')}
            >
              <Text style={styles.quickButtonText}>Check Status</Text>
            </TouchableOpacity>
            <TouchableOpacity
              style={styles.quickButton}
              onPress={() => simulateVoiceInput('help')}
            >
              <Text style={styles.quickButtonText}>Help</Text>
            </TouchableOpacity>
          </View>
        </View>
      </ScrollView>

      {/* Microphone Button */}
      <View style={styles.micContainer}>
        <TouchableOpacity
          style={[
            styles.micButton,
            isListening && styles.micButtonActive,
            isProcessing && styles.micButtonProcessing,
          ]}
          onPress={handleMicPress}
          disabled={isProcessing}
        >
          {isProcessing ? (
            <ActivityIndicator size="large" color="#fff" />
          ) : (
            <Text style={styles.micIcon}>{isListening ? '🛑' : '🎤'}</Text>
          )}
        </TouchableOpacity>
        <Text style={styles.micHint}>
          {isListening
            ? 'Listening... Tap to stop'
            : isProcessing
            ? 'Processing...'
            : 'Tap to speak'}
        </Text>
      </View>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#1a1a2e',
  },
  header: {
    paddingHorizontal: 20,
    paddingTop: 20,
    paddingBottom: 10,
  },
  title: {
    fontSize: 32,
    fontWeight: 'bold',
    color: '#fff',
  },
  subtitle: {
    fontSize: 14,
    color: '#818cf8',
    marginTop: 4,
  },
  headerButtons: {
    flexDirection: 'row',
    marginTop: 12,
    gap: 10,
  },
  headerButton: {
    backgroundColor: '#2d2d44',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
  },
  headerButtonText: {
    color: '#fff',
    fontSize: 14,
  },
  connectionCard: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: '#2d2d44',
    marginHorizontal: 20,
    marginVertical: 10,
    padding: 16,
    borderRadius: 12,
  },
  connectionStatus: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusDot: {
    width: 10,
    height: 10,
    borderRadius: 5,
    marginRight: 10,
  },
  connectionText: {
    color: '#fff',
    fontSize: 14,
  },
  sessionCard: {
    backgroundColor: '#2d2d44',
    marginHorizontal: 20,
    marginVertical: 6,
    padding: 14,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#3d3d54',
  },
  sessionCardActive: {
    backgroundColor: '#2a1e4a',
    borderColor: '#836EF9',
  },
  sessionHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 6,
  },
  sessionIcon: {
    fontSize: 18,
    marginRight: 8,
  },
  sessionTitle: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  sessionDetails: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 6,
  },
  sessionLimit: {
    color: '#836EF9',
    fontSize: 14,
    fontWeight: '600',
  },
  sessionExpiry: {
    color: '#9ca3af',
    fontSize: 12,
  },
  sessionHint: {
    color: '#6b7280',
    fontSize: 11,
  },
  gasTankCard: {
    backgroundColor: '#2d2d44',
    marginHorizontal: 20,
    marginVertical: 6,
    padding: 14,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: '#3d3d54',
  },
  gasTankCardLow: {
    backgroundColor: '#3a2d1e',
    borderColor: '#f59e0b',
  },
  gasTankHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: 6,
  },
  gasTankIcon: {
    fontSize: 16,
    marginRight: 8,
  },
  gasTankTitle: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
    flex: 1,
  },
  gasTankWarning: {
    backgroundColor: '#f59e0b',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 4,
  },
  gasTankWarningText: {
    color: '#000',
    fontSize: 10,
    fontWeight: 'bold',
  },
  gasTankDetails: {
    flexDirection: 'row',
    alignItems: 'baseline',
    marginBottom: 4,
  },
  gasTankBalance: {
    color: '#836EF9',
    fontSize: 20,
    fontWeight: 'bold',
    marginRight: 8,
  },
  gasTankSwaps: {
    color: '#9ca3af',
    fontSize: 12,
  },
  gasTankHint: {
    color: '#6b7280',
    fontSize: 10,
  },
  content: {
    flex: 1,
  },
  contentContainer: {
    padding: 20,
    paddingBottom: 150,
  },
  stateCard: {
    backgroundColor: '#2d2d44',
    padding: 16,
    borderRadius: 12,
    marginBottom: 16,
    alignItems: 'center',
  },
  stateLabel: {
    color: '#9ca3af',
    fontSize: 12,
    textTransform: 'uppercase',
  },
  stateValue: {
    color: '#818cf8',
    fontSize: 24,
    fontWeight: 'bold',
    marginTop: 4,
  },
  intentCard: {
    backgroundColor: '#2d2d44',
    padding: 16,
    borderRadius: 12,
    marginBottom: 16,
  },
  cardTitle: {
    color: '#9ca3af',
    fontSize: 12,
    textTransform: 'uppercase',
    marginBottom: 8,
  },
  intentText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
  },
  rawText: {
    color: '#6b7280',
    fontSize: 12,
    marginTop: 8,
    fontStyle: 'italic',
  },
  quoteCard: {
    backgroundColor: '#1e3a5f',
    padding: 16,
    borderRadius: 12,
    marginBottom: 16,
  },
  quoteRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: 8,
  },
  quoteLabel: {
    color: '#9ca3af',
    fontSize: 14,
  },
  quoteValue: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
  },
  errorCard: {
    backgroundColor: '#7f1d1d',
    padding: 16,
    borderRadius: 12,
    marginBottom: 16,
  },
  errorText: {
    color: '#fecaca',
    fontSize: 14,
  },
  errorDismiss: {
    color: '#fff',
    fontSize: 12,
    marginTop: 8,
    textDecorationLine: 'underline',
  },
  testSection: {
    marginTop: 20,
    paddingTop: 20,
    borderTopWidth: 1,
    borderTopColor: '#2d2d44',
  },
  testLabel: {
    color: '#9ca3af',
    fontSize: 12,
    textTransform: 'uppercase',
    marginBottom: 8,
  },
  testInputRow: {
    flexDirection: 'row',
    gap: 10,
  },
  testInput: {
    flex: 1,
    backgroundColor: '#2d2d44',
    color: '#fff',
    padding: 12,
    borderRadius: 8,
    fontSize: 16,
  },
  testButton: {
    backgroundColor: '#818cf8',
    paddingHorizontal: 20,
    borderRadius: 8,
    justifyContent: 'center',
  },
  testButtonText: {
    color: '#fff',
    fontWeight: '600',
  },
  quickButtons: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginTop: 12,
  },
  quickButton: {
    backgroundColor: '#374151',
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 6,
  },
  quickButtonText: {
    color: '#d1d5db',
    fontSize: 12,
  },
  micContainer: {
    position: 'absolute',
    bottom: 30,
    left: 0,
    right: 0,
    alignItems: 'center',
  },
  micButton: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: '#818cf8',
    justifyContent: 'center',
    alignItems: 'center',
    shadowColor: '#818cf8',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.5,
    shadowRadius: 10,
    elevation: 10,
  },
  micButtonActive: {
    backgroundColor: '#ef4444',
    shadowColor: '#ef4444',
  },
  micButtonProcessing: {
    backgroundColor: '#6366f1',
    shadowColor: '#6366f1',
  },
  micIcon: {
    fontSize: 32,
  },
  micHint: {
    color: '#9ca3af',
    fontSize: 12,
    marginTop: 8,
  },
});
