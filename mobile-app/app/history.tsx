import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  SafeAreaView,
  FlatList,
  TouchableOpacity,
  Linking,
} from 'react-native';
import { useAppStore, type SwapHistoryItem } from '../src/store/appStore';
import { getTokenSymbol } from '../src/utils/tokens';

export default function HistoryScreen() {
  const swapHistory = useAppStore((s) => s.swapHistory);

  const openExplorer = (txHash: string) => {
    // Unichain explorer URL
    const url = `https://uniscan.xyz/tx/${txHash}`;
    Linking.openURL(url);
  };

  const renderItem = ({ item }: { item: SwapHistoryItem }) => {
    const tokenIn = item.intent.tokenIn ? getTokenSymbol(item.intent.tokenIn) : '?';
    const tokenOut = item.intent.tokenOut ? getTokenSymbol(item.intent.tokenOut) : '?';
    const amount = item.intent.amountIn || '?';
    const date = new Date(item.timestamp);

    return (
      <TouchableOpacity
        style={styles.item}
        onPress={() => item.txHash && openExplorer(item.txHash)}
        disabled={!item.txHash}
      >
        <View style={styles.itemHeader}>
          <View style={styles.statusBadge}>
            <View
              style={[
                styles.statusDot,
                {
                  backgroundColor:
                    item.status === 'confirmed'
                      ? '#4ade80'
                      : item.status === 'pending'
                      ? '#fbbf24'
                      : '#f87171',
                },
              ]}
            />
            <Text style={styles.statusText}>{item.status}</Text>
          </View>
          <Text style={styles.date}>
            {date.toLocaleDateString()} {date.toLocaleTimeString()}
          </Text>
        </View>

        <View style={styles.swapInfo}>
          <Text style={styles.swapAmount}>{amount}</Text>
          <Text style={styles.swapTokens}>
            {tokenIn} → {tokenOut}
          </Text>
        </View>

        {item.quote && (
          <View style={styles.quoteInfo}>
            <Text style={styles.quoteText}>
              Received: {item.quote.tokenOut.amount} {item.quote.tokenOut.symbol}
            </Text>
          </View>
        )}

        {item.txHash && (
          <Text style={styles.txHash}>
            TX: {item.txHash.slice(0, 10)}...{item.txHash.slice(-8)} ↗
          </Text>
        )}
      </TouchableOpacity>
    );
  };

  const EmptyList = () => (
    <View style={styles.empty}>
      <Text style={styles.emptyIcon}>📜</Text>
      <Text style={styles.emptyText}>No swaps yet</Text>
      <Text style={styles.emptyHint}>
        Say "Swap 100 USDC to ETH" to get started
      </Text>
    </View>
  );

  return (
    <SafeAreaView style={styles.container}>
      <FlatList
        data={swapHistory}
        renderItem={renderItem}
        keyExtractor={(item) => item.id}
        contentContainerStyle={styles.list}
        ListEmptyComponent={EmptyList}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#1a1a2e',
  },
  list: {
    padding: 16,
    flexGrow: 1,
  },
  item: {
    backgroundColor: '#2d2d44',
    borderRadius: 12,
    padding: 16,
    marginBottom: 12,
  },
  itemHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 12,
  },
  statusBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#1a1a2e',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 12,
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginRight: 6,
  },
  statusText: {
    color: '#fff',
    fontSize: 12,
    textTransform: 'capitalize',
  },
  date: {
    color: '#6b7280',
    fontSize: 12,
  },
  swapInfo: {
    marginBottom: 8,
  },
  swapAmount: {
    color: '#fff',
    fontSize: 24,
    fontWeight: 'bold',
  },
  swapTokens: {
    color: '#818cf8',
    fontSize: 16,
    marginTop: 4,
  },
  quoteInfo: {
    backgroundColor: '#1a1a2e',
    padding: 10,
    borderRadius: 8,
    marginTop: 8,
  },
  quoteText: {
    color: '#4ade80',
    fontSize: 14,
  },
  txHash: {
    color: '#6b7280',
    fontSize: 12,
    marginTop: 12,
  },
  empty: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    paddingVertical: 60,
  },
  emptyIcon: {
    fontSize: 48,
    marginBottom: 16,
  },
  emptyText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
    marginBottom: 8,
  },
  emptyHint: {
    color: '#6b7280',
    fontSize: 14,
    textAlign: 'center',
  },
});
