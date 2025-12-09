# VoiceSwap - Voice-Activated DeFi Swaps

> Connect Meta Ray-Ban glasses to execute Uniswap V4 swaps on Unichain using voice commands

Built for the x402 Hackathon (December 2025 - January 2026)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Usuario con Meta Glasses                    │
│                                                                  │
│   🗣️ "Hey, swap 100 USDC to ETH"                                │
│                                                                  │
└──────────────────────────┬──────────────────────────────────────┘
                           │ Audio (Bluetooth)
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    VoiceSwap App (iOS/Android)                   │
│                                                                  │
│   ┌─────────────┐    ┌─────────────┐    ┌─────────────┐        │
│   │ Meta SDK    │───▶│ Speech-to-  │───▶│ Intent      │        │
│   │ (audio in)  │    │ Text        │    │ Parser      │        │
│   └─────────────┘    └─────────────┘    └──────┬──────┘        │
│                                                 │                │
│                                                 ▼                │
│                                          ┌─────────────┐        │
│                                          │ x402 Client │        │
│                                          │ (paga USDC) │        │
│                                          └──────┬──────┘        │
└─────────────────────────────────────────────────┼───────────────┘
                                                  │ HTTPS + x402
                                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                    x402 Swap Executor Backend                    │
│                                                                  │
│   /quote ──▶ /route ──▶ /execute ──▶ Uniswap V4 on Unichain    │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

## Features

- 🎙️ Voice-activated token swaps
- 👓 Meta Ray-Ban glasses integration
- ⚡ Uniswap V4 on Unichain (fastest L2)
- 💳 x402 micropayments (~$0.027 per swap)
- 🔊 Audio confirmation through glasses

## Voice Commands

| Say | Action |
|-----|--------|
| "Swap 100 USDC to ETH" | Execute swap |
| "Exchange 50 dollars for ether" | Execute swap |
| "Get quote for 0.1 ETH to USDC" | Get price quote |
| "Check status" | Check last transaction |
| "Yes" / "Confirm" | Confirm pending swap |
| "No" / "Cancel" | Cancel pending swap |
| "Help" | List available commands |

## Quick Start

### Prerequisites

- Node.js 18+
- Expo CLI (`npm install -g expo-cli`)
- iOS Simulator / Android Emulator or physical device
- Meta Ray-Ban glasses (optional - app works without them)

### Installation

```bash
cd mobile-app
npm install
```

### Development

```bash
# Start Expo development server
npm start

# Run on iOS
npm run ios

# Run on Android
npm run android
```

### Configuration

1. Open app Settings
2. Enter your Ethereum wallet address
3. Set backend URL (default: `http://localhost:4021`)

## Project Structure

```
mobile-app/
├── app/                      # Expo Router pages
│   ├── _layout.tsx          # Root layout
│   ├── index.tsx            # Home screen
│   ├── settings.tsx         # Settings page
│   └── history.tsx          # Swap history
├── src/
│   ├── services/
│   │   ├── IntentParser.ts  # Voice command parser
│   │   ├── SwapService.ts   # x402 backend client
│   │   ├── SpeechService.ts # TTS/STT wrapper
│   │   └── MetaGlassesService.ts # Meta SDK wrapper
│   ├── hooks/
│   │   └── useVoiceSwap.ts  # Main orchestrator hook
│   ├── store/
│   │   └── appStore.ts      # Zustand state store
│   └── utils/
│       └── tokens.ts        # Token addresses/aliases
├── app.json                  # Expo config
├── package.json
└── README.md
```

## Meta Wearables SDK

### App ID
```
865317392634736
```

### iOS Configuration (Info.plist)
```xml
<key>MWDAT</key>
<dict>
    <key>MetaAppID</key>
    <string>865317392634736</string>
</dict>
```

### Android Configuration (AndroidManifest.xml)
```xml
<meta-data
  android:name="com.meta.wearable.mwdat.APPLICATION_ID"
  android:value="865317392634736"
/>
```

## x402 Pricing

| Endpoint | Cost |
|----------|------|
| /quote | $0.001 |
| /route | $0.005 |
| /execute | $0.02 |
| /status | $0.001 |
| **Total per swap** | **~$0.027** |

## Testing Without Hardware

The app includes mock mode for development:

1. Use the "Test Voice Command" input on the home screen
2. Click quick-action buttons to simulate commands
3. MetaGlassesService auto-connects a mock device after 2 seconds

## Token Support

### Unichain Mainnet
| Token | Address |
|-------|---------|
| WETH | `0x4200000000000000000000000000000000000006` |
| USDC | `0x078D782b760474a361dDA0AF3839290b0EF57AD6` |

### Unichain Sepolia (Testnet)
| Token | Address |
|-------|---------|
| WETH | `0x4200000000000000000000000000000000000006` |
| USDC | `0x31d0220469e10c4E71834a79b1f276d740d3768F` |

## User Flow

1. **Connect** - Open app, glasses auto-connect via Bluetooth
2. **Speak** - "Swap 100 USDC to ETH"
3. **Confirm** - App says quote, user says "Yes"
4. **Execute** - x402 payment + on-chain swap
5. **Done** - "Swap complete! You received 0.028 ETH"

## Tech Stack

- **Framework**: Expo / React Native
- **Navigation**: Expo Router
- **State**: Zustand
- **Speech**: expo-speech + @react-native-voice/voice
- **Blockchain**: ethers.js
- **Backend**: x402 Swap Executor (Uniswap V4)

## Building for Production

```bash
# Install EAS CLI
npm install -g eas-cli

# Build for iOS
eas build --platform ios

# Build for Android
eas build --platform android
```

## Resources

- [Meta Wearables SDK](https://wearables.developer.meta.com/docs/develop)
- [x402 Protocol](https://x402.org)
- [Uniswap V4 Docs](https://docs.uniswap.org)
- [Unichain Docs](https://docs.unichain.org)
- [Expo Documentation](https://docs.expo.dev)

## License

MIT

---

Built with ❤️ for the x402 Hackathon
