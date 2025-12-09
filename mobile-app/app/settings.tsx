import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  SafeAreaView,
  ScrollView,
  Alert,
} from 'react-native';
import { useAppStore } from '../src/store/appStore';

export default function SettingsScreen() {
  const walletAddress = useAppStore((s) => s.walletAddress);
  const backendUrl = useAppStore((s) => s.backendUrl);
  const setWalletAddress = useAppStore((s) => s.setWalletAddress);
  const setBackendUrl = useAppStore((s) => s.setBackendUrl);

  const [wallet, setWallet] = useState(walletAddress || '');
  const [backend, setBackend] = useState(backendUrl);

  const handleSave = () => {
    if (wallet && !wallet.startsWith('0x')) {
      Alert.alert('Invalid Address', 'Wallet address must start with 0x');
      return;
    }

    setWalletAddress(wallet || null);
    setBackendUrl(backend);
    Alert.alert('Saved', 'Settings have been saved');
  };

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.content}>
        {/* Wallet Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Wallet</Text>
          <Text style={styles.label}>Your Ethereum Address</Text>
          <TextInput
            style={styles.input}
            value={wallet}
            onChangeText={setWallet}
            placeholder="0x..."
            placeholderTextColor="#6b7280"
            autoCapitalize="none"
            autoCorrect={false}
          />
          <Text style={styles.hint}>
            This address will receive swapped tokens and pay for x402 fees
          </Text>
        </View>

        {/* Backend Section */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Backend</Text>
          <Text style={styles.label}>Swap Executor URL</Text>
          <TextInput
            style={styles.input}
            value={backend}
            onChangeText={setBackend}
            placeholder="http://localhost:4021"
            placeholderTextColor="#6b7280"
            autoCapitalize="none"
            autoCorrect={false}
            keyboardType="url"
          />
          <Text style={styles.hint}>
            URL of the x402 Swap Executor backend
          </Text>
        </View>

        {/* Network Info */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Network Info</Text>
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>Swap Network:</Text>
            <Text style={styles.infoValue}>Unichain</Text>
          </View>
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>Protocol:</Text>
            <Text style={styles.infoValue}>Uniswap V4</Text>
          </View>
          <View style={styles.infoRow}>
            <Text style={styles.infoLabel}>Payment Network:</Text>
            <Text style={styles.infoValue}>Base (x402)</Text>
          </View>
        </View>

        {/* Pricing Info */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>x402 Pricing</Text>
          <View style={styles.priceRow}>
            <Text style={styles.priceEndpoint}>/quote</Text>
            <Text style={styles.priceAmount}>$0.001</Text>
          </View>
          <View style={styles.priceRow}>
            <Text style={styles.priceEndpoint}>/route</Text>
            <Text style={styles.priceAmount}>$0.005</Text>
          </View>
          <View style={styles.priceRow}>
            <Text style={styles.priceEndpoint}>/execute</Text>
            <Text style={styles.priceAmount}>$0.02</Text>
          </View>
          <View style={styles.priceRow}>
            <Text style={styles.priceEndpoint}>/status</Text>
            <Text style={styles.priceAmount}>$0.001</Text>
          </View>
          <Text style={styles.hint}>
            Total cost per swap: ~$0.027 in USDC
          </Text>
        </View>

        {/* Save Button */}
        <TouchableOpacity style={styles.saveButton} onPress={handleSave}>
          <Text style={styles.saveButtonText}>Save Settings</Text>
        </TouchableOpacity>

        {/* About */}
        <View style={styles.about}>
          <Text style={styles.aboutText}>VoiceSwap v1.0.0</Text>
          <Text style={styles.aboutText}>Built for x402 Hackathon</Text>
          <Text style={styles.aboutText}>Powered by Uniswap V4 on Unichain</Text>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#1a1a2e',
  },
  content: {
    padding: 20,
  },
  section: {
    marginBottom: 30,
  },
  sectionTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#fff',
    marginBottom: 16,
  },
  label: {
    fontSize: 14,
    color: '#9ca3af',
    marginBottom: 8,
  },
  input: {
    backgroundColor: '#2d2d44',
    color: '#fff',
    padding: 16,
    borderRadius: 12,
    fontSize: 16,
  },
  hint: {
    fontSize: 12,
    color: '#6b7280',
    marginTop: 8,
  },
  infoRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: '#2d2d44',
  },
  infoLabel: {
    color: '#9ca3af',
    fontSize: 14,
  },
  infoValue: {
    color: '#818cf8',
    fontSize: 14,
    fontWeight: '600',
  },
  priceRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 8,
  },
  priceEndpoint: {
    color: '#fff',
    fontSize: 14,
    fontFamily: 'monospace',
  },
  priceAmount: {
    color: '#4ade80',
    fontSize: 14,
    fontWeight: '600',
  },
  saveButton: {
    backgroundColor: '#818cf8',
    padding: 16,
    borderRadius: 12,
    alignItems: 'center',
    marginTop: 20,
  },
  saveButtonText: {
    color: '#fff',
    fontSize: 16,
    fontWeight: '600',
  },
  about: {
    marginTop: 40,
    alignItems: 'center',
    paddingBottom: 40,
  },
  aboutText: {
    color: '#6b7280',
    fontSize: 12,
    marginBottom: 4,
  },
});
