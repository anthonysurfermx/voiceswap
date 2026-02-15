# VoiceSwap

> Voice-activated crypto payments through Meta Ray-Ban smart glasses on Monad

**Website:** [voiceswap.cc](https://voiceswap.cc) | **Track:** Agent | **Hackathon:** [Moltiverse](https://moltiverse.dev/)

## What is VoiceSwap?

VoiceSwap lets you pay anyone with crypto using just your voice. Put on Meta Ray-Ban glasses, say "send money", look at a QR code, confirm the amount — payment executes on Monad. No phone, no screens, no MetaMask popups.

### Demo Flow (under 20 seconds)

```
"Hey Gemini, send money"  →  Scanning.
     ↓ (looks at QR)
"Five dollars?"           →  "Yes"
     ↓
"Sending."                →  "Done."
     ↓
USDC transferred on Monad ✅
```

## Architecture (V2 — Current)

```
┌──────────────────────┐     ┌──────────────────────┐
│  Meta Ray-Ban Glasses │     │   Gemini Live API    │
│  • Camera (QR scan)  │     │  • Bidirectional     │
│  • Bluetooth audio   │     │    WebSocket audio   │
│  • Haptic feedback   │     │  • Function calling  │
└──────────┬───────────┘     │  • Native audio I/O  │
           │ BT audio        └──────────┬───────────┘
           ▼                            │ WSS
┌──────────────────────────────────────────────────────┐
│                  iOS App (Swift)                      │
├──────────────────────────────────────────────────────┤
│  AudioManager        │ PCM 16kHz → Gemini            │
│                      │ PCM 24kHz ← Gemini            │
│  GeminiLiveService   │ WebSocket + keepalive (15s)   │
│  GeminiSessionVM     │ Tool call dispatch             │
│  VoiceSwapWallet     │ Local secp256k1 signing        │
│  MetaGlassesManager  │ Wearables SDK 0.4.0            │
│  Apple Vision        │ Local QR detection (per frame) │
├──────────────────────────────────────────────────────┤
│  Payment Tools (Gemini function calls):              │
│  scan_qr → set_payment_amount → confirm_payment     │
└──────────────────────┬───────────────────────────────┘
                       │ RPC
                       ▼
              ┌─────────────────┐
              │  Monad Mainnet  │
              │  Chain ID: 143  │
              │  USDC + Uniswap │
              └─────────────────┘
```

### Key Technical Decisions

- **Gemini Live API** for real-time bidirectional voice (PCM 16kHz in, 24kHz out) with function calling — Gemini orchestrates the entire payment flow through tool calls
- **Local wallet signing** with secp256k1 on-device — no MetaMask popups, instant transaction execution
- **Apple Vision** for QR detection — runs locally every frame, no round-trip to server
- **Meta Wearables SDK 0.4.0** — camera streaming + Bluetooth audio from Ray-Ban glasses
- **Uniswap on Monad** for MON→USDC swaps before payment execution
- **Proactive Audio** — Gemini only responds when addressed directly, ignores ambient conversation

## Tech Stack

| Component | Technology |
|-----------|-----------|
| App | Swift, iOS 17+, SwiftUI |
| Voice AI | Gemini Live API (gemini-2.5-flash-native-audio) |
| Glasses | Meta Wearables SDK 0.4.0 |
| QR Detection | Apple Vision framework |
| Wallet | secp256k1.swift 0.18.0 (on-device signing) |
| Blockchain | Monad Mainnet (Chain ID 143) |
| DEX | Uniswap V3 (MON→USDC swaps) |
| Payments | USDC (EIP-155 transactions) |
| Backend | Node.js + Express (balance API, onramp) |

## Project Structure

```
ios/VoiceSwap/Sources/
├── Gemini/
│   ├── AudioManager.swift          # AVAudioEngine, PCM capture/playback
│   ├── GeminiConfig.swift          # API keys, model config, VAD settings
│   ├── GeminiLiveService.swift     # WebSocket connection, keepalive, reconnect
│   ├── GeminiSessionViewModel.swift # Tool call dispatch, payment flow orchestration
│   └── VoiceSwapSystemPrompt.swift  # Voice assistant personality + flow
├── MetaWearables/
│   ├── VoiceSwapViewModel.swift    # Main app state, payment execution
│   └── VoiceSwapAPIClient.swift    # Backend API calls
├── Views/
│   ├── VoiceSwapMainView.swift     # Main UI
│   └── WalletSetupView.swift       # Deposit/fund wallet screen
├── Wallet/
│   ├── VoiceSwapWallet.swift       # Local wallet (Keychain, secp256k1)
│   ├── VoiceSwapCryptoProvider.swift # EIP-155 signing, RLP, keccak256
│   └── WalletConnectManager.swift  # MetaMask integration for funding
└── VoiceSwapApp.swift              # App entry point, deep links
```

## How It Works

1. **User speaks** → Bluetooth mic on Ray-Ban glasses captures audio
2. **AudioManager** → Converts to PCM 16kHz, streams to Gemini via WebSocket
3. **Gemini processes** → Understands intent, calls `scan_qr` function
4. **Camera activates** → Meta SDK streams glasses camera, Apple Vision detects QR
5. **QR parsed** → Merchant wallet extracted, sent to Gemini as context
6. **Amount confirmed** → Gemini calls `set_payment_amount` → `confirm_payment`
7. **Transaction signed** → VoiceSwapWallet signs EIP-155 tx locally with secp256k1
8. **On-chain execution** → Raw tx sent to Monad RPC, USDC transferred
9. **Gemini confirms** → "Done." spoken back through glasses speakers

## Setup

### Prerequisites
- Xcode 15+, iOS 17+ device
- Meta Ray-Ban smart glasses with Developer Mode enabled
- Gemini API key
- Monad RPC access

### Build & Run
```bash
git clone https://github.com/anthonysurfermx/voiceswap
cd voiceswap/ios/VoiceSwap
open VoiceSwap.xcodeproj
```

Configure `GeminiConfig.swift` with your Gemini API key, build and run on device.

---

# V1 — Evolution & Lessons Learned

VoiceSwap went through a significant architectural evolution. The V1 approach below was our starting point — understanding why we moved away from it explains the design decisions in V2.

## V1 Architecture (x402 + Thirdweb + Apple STT)

The original VoiceSwap was called **x402 Swap Executor** — a microservice for AI agents to execute Uniswap V3 swaps via x402 micropayments.

### What We Built (V1)

```
User Voice → Apple STT → Backend (OpenAI) → Thirdweb Engine → Monad
```

- **Apple Speech-to-Text** for voice recognition
- **OpenAI API** for intent parsing (cloud round-trip)
- **Thirdweb Engine** for wallet management + smart accounts (ERC-4337)
- **x402 protocol** for micropayment-gated API endpoints
- **Gas sponsorship** via Thirdweb's account abstraction

### Why We Moved Away From V1

#### 1. Thirdweb — Too Many Layers, Not Enough Control

Thirdweb provided wallet infrastructure (in-app wallets, smart accounts, gas sponsorship), but the abstraction came at a cost:

- **Latency**: Every transaction went through Thirdweb Engine → bundler → on-chain. For a voice-first UX where users expect sub-second feedback, this pipeline was too slow
- **Dependency risk**: Our entire payment flow depended on Thirdweb's uptime and API reliability
- **Debugging difficulty**: When transactions failed, the error was buried 3 layers deep (our code → Thirdweb SDK → bundler → chain)
- **Unnecessary for our use case**: ERC-4337 account abstraction is powerful for gasless UX, but we realized a pre-funded local wallet with direct signing is simpler and faster for a glasses-first flow where the user already set up once

**What replaced it:** `VoiceSwapWallet.swift` — a local wallet that stores a private key in iOS Keychain and signs transactions directly with secp256k1. One hop: sign → send raw tx to Monad RPC. No bundlers, no relay, no smart accounts.

#### 2. Apple STT + OpenAI — Two Hops Too Many

The V1 voice pipeline had three serialized network calls:

```
Voice → Apple STT (on-device) → Text → OpenAI API (cloud) → Intent → Execute
```

- Apple's on-device STT was decent but not great with crypto terminology ("send USDC" often became "send USD see")
- The OpenAI round-trip added 1-2 seconds of latency
- No way to have a natural back-and-forth conversation — it was command-response

**What replaced it:** Gemini Live API — a single bidirectional WebSocket that handles speech recognition, intent understanding, conversation flow, AND function calling all in one connection. Voice goes in, actions come out. No intermediate text representation.

#### 3. x402 — Clever But Wrong Fit

x402 micropayments were elegant for an API service model (agents pay per request), but VoiceSwap evolved into a consumer product where:

- Users don't want to pay micropayments to use their own wallet
- The service isn't an API — it's an app running on their phone
- The payment flow IS the product, not a paid endpoint

**What replaced it:** Direct on-chain execution. The user's local wallet pays gas directly on Monad.

### What We Kept From V1

- **Monad as the target chain** — fast finality, low fees, perfect for real-time voice payments
- **Uniswap V3 integration** — MON→USDC swaps for payment flexibility
- **The core vision** — voice-first crypto payments through smart glasses

## V1 Original README

<details>
<summary>Click to expand the original x402 Swap Executor documentation</summary>

### x402 Swap Executor

> Swap-as-a-Service: x402-powered Uniswap V3 swap execution for AI agents on Monad

Built for the [x402 Hackathon](https://www.x402hackathon.com) (December 8, 2025 - January 5, 2026)

#### What was this?

x402 Swap Executor was a microservice that allowed AI agents to execute token swaps on Uniswap V3 on Monad by paying micropayments via the x402 protocol. No API keys, no accounts, no subscriptions — just pay per request.

#### Pricing

| Endpoint | Price | Description |
|----------|-------|-------------|
| `GET /quote` | $0.001 | Get a swap quote |
| `POST /route` | $0.005 | Calculate optimal route with calldata |
| `POST /execute` | $0.02 | Execute swap on-chain |
| `GET /status/:txHash` | $0.001 | Check transaction status |
| `GET /tokens` | FREE | List supported tokens |

#### Tech Stack (V1)

- **Runtime**: Node.js 20+
- **Framework**: Express.js
- **x402**: `x402-express`, `@coinbase/x402`
- **DEX**: Uniswap V3 SDK + Universal Router
- **Blockchain**: ethers.js v5
- **Wallets**: Thirdweb Engine + Smart Accounts (ERC-4337)
- **Voice**: Apple Speech-to-Text + OpenAI
- **Network**: Monad

</details>

---

Built by [Anthony Chavez](https://twitter.com/anthonychavez) for the [Moltiverse Hackathon](https://moltiverse.dev/)
