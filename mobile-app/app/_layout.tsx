import { Stack } from 'expo-router';
import { StatusBar } from 'expo-status-bar';
import { useEffect } from 'react';
import { metaGlassesService } from '../src/services/MetaGlassesService';
import { useAppStore } from '../src/store/appStore';

export default function RootLayout() {
  const setGlassesConnection = useAppStore((s) => s.setGlassesConnection);

  useEffect(() => {
    // Initialize Meta Glasses service
    metaGlassesService.initialize();

    // Listen for connection changes
    const unsubscribe = metaGlassesService.onConnectionChange((state, device) => {
      setGlassesConnection(state, device);
    });

    return () => {
      unsubscribe();
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
