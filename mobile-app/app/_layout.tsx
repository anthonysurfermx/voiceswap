import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import { metaGlassesService } from '../src/services/MetaGlassesService';
import { thirdwebWalletService } from '../src/services/ThirdwebWalletService';
import { useAppStore } from '../src/store/appStore';
import 'react-native-get-random-values'; // Required for thirdweb

export default function RootLayout() {
  const setGlassesConnection = useAppStore((s) => s.setGlassesConnection);
  const setWalletAddress = useAppStore((s) => s.setWalletAddress);

  useEffect(() => {
    // Initialize Meta Glasses service
    metaGlassesService.initialize();

    // Listen for Meta Glasses connection changes
    const unsubscribeGlasses = metaGlassesService.onConnectionChange((state, device) => {
      setGlassesConnection(state, device);
    });

    // Auto-connect wallet if previously connected
    thirdwebWalletService.autoConnect().then((connected) => {
      if (connected) {
        const address = thirdwebWalletService.getAddress();
        if (address) {
          setWalletAddress(address);
          console.log('[App] Auto-connected wallet:', address);
        }
      }
    });

    // Listen for wallet state changes
    const unsubscribeWallet = thirdwebWalletService.onStateChange((state) => {
      if (state.isConnected && state.address) {
        setWalletAddress(state.address);
      } else {
        setWalletAddress(null);
      }
    });

    return () => {
      unsubscribeGlasses();
      unsubscribeWallet();
    };
  }, []);

  return (
    <>
      <StatusBar style="light" />
      <Stack
        screenOptions={{
          headerStyle: { backgroundColor: '#1a1a2e' },
          headerTintColor: '#fff',
          headerTitleStyle: { fontWeight: 'bold' },
          contentStyle: { backgroundColor: '#1a1a2e' },
        }}
      >
        <Stack.Screen
          name="index"
          options={{
            title: 'VoiceSwap',
            headerShown: false,
          }}
        />
        <Stack.Screen
          name="settings"
          options={{
            title: 'Settings',
            presentation: 'modal',
          }}
        />
        <Stack.Screen
          name="history"
          options={{
            title: 'Swap History',
          }}
        />
      </Stack>
    </>
  );
}
