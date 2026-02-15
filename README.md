# x402 Swap Executor

> Swap-as-a-Service: x402-powered Uniswap V3 swap execution for AI agents on Monad

Built for the [x402 Hackathon](https://www.x402hackathon.com) (December 8, 2025 - January 5, 2026)

## What is this?

x402 Swap Executor is a microservice that allows AI agents to execute token swaps on **Uniswap V3** on **Monad** by paying micropayments via the [x402 protocol](https://x402.org). No API keys, no accounts, no subscriptions—just pay per request.

### The Problem

AI agents that want to execute DeFi operations face massive friction:
- Managing private keys and wallets
- Understanding complex DEX protocols
- Calculating optimal routes
- Handling gas estimation
- Dealing with transaction failures

### The Solution

This service abstracts all that complexity behind simple HTTP endpoints. Agents pay a small x402 micropayment and get:
- Instant swap quotes
- Optimal route calculation
- On-chain execution
- Transaction status tracking

### Why Monad + Uniswap V3?

- **Monad**: Uniswap's native L2 with 200ms block times, lowest fees, and MEV protection
- **Uniswap V3**: Latest protocol with hooks, flash accounting, native ETH support, and improved gas efficiency

## Pricing

| Endpoint | Price | Description |
|----------|-------|-------------|
| `GET /quote` | $0.001 | Get a swap quote |
| `POST /route` | $0.005 | Calculate optimal route with calldata |
| `POST /execute` | $0.02 | Execute swap on-chain |
| `GET /status/:txHash` | $0.001 | Check transaction status |
| `GET /tokens` | FREE | List supported tokens |
| `GET /health` | FREE | Health check |

## Quick Start

### 1. Clone and Install

```bash
git clone https://github.com/your-repo/x402-swap-executor
cd x402-swap-executor
npm install
```

### 2. Configure Environment

```bash
cp .env.example .env
```

Edit `.env`:

```env
# Your wallet address to receive x402 payments
PAYMENT_RECEIVER_ADDRESS=0xYourEthereumAddress

# Network: monad-sepolia (testnet) or monad (mainnet)
NETWORK=monad-sepolia

# RPC URL
MONAD_SEPOLIA_RPC_URL=https://sepolia.monad.org

# Optional: For executing swaps
RELAYER_PRIVATE_KEY=your_private_key
```

### 3. Run the Server

```bash
# Development
npm run dev

# Production
npm run build
npm start
```

## API Usage

### Get a Quote

```bash
curl "http://localhost:4021/quote?tokenIn=0x4200000000000000000000000000000000000006&tokenOut=0x31d0220469e10c4E71834a79b1f276d740d3768F&amountIn=0.1"
```

Without x402 payment, you'll receive:

```
HTTP/1.1 402 Payment Required
X-Payment-Address: 0x...
X-Payment-Amount: 0.001 USDC
```

With proper x402 payment header, you get:

```json
{
  "success": true,
  "data": {
    "tokenIn": {
      "address": "0x4200000000000000000000000000000000000006",
      "symbol": "WETH",
      "decimals": 18,
      "amount": "0.1",
      "amountRaw": "100000000000000000"
    },
    "tokenOut": {
      "address": "0x31d0220469e10c4E71834a79b1f276d740d3768F",
      "symbol": "USDC",
      "decimals": 6,
      "amount": "350.25",
      "amountRaw": "350250000"
    },
    "priceImpact": "0.1000",
    "route": ["0x4200...", "0x31d0..."],
    "estimatedGas": "150000",
    "timestamp": 1733673600000
  }
}
```

### Calculate Route

```bash
curl -X POST "http://localhost:4021/route" \
  -H "Content-Type: application/json" \
  -d '{
    "tokenIn": "0x4200000000000000000000000000000000000006",
    "tokenOut": "0x31d0220469e10c4E71834a79b1f276d740d3768F",
    "amountIn": "0.1",
    "recipient": "0xYourAddress",
    "slippageTolerance": 0.5
  }'
```

### Execute Swap

```bash
curl -X POST "http://localhost:4021/execute" \
  -H "Content-Type: application/json" \
  -d '{
    "tokenIn": "0x4200000000000000000000000000000000000006",
    "tokenOut": "0x31d0220469e10c4E71834a79b1f276d740d3768F",
    "amountIn": "0.1",
    "recipient": "0xRecipientAddress",
    "slippageTolerance": 0.5
  }'
```

### Check Status

```bash
curl "http://localhost:4021/status/0xTransactionHash"
```

## For AI Agent Developers

If you're building an AI agent that needs to swap tokens, here's how to integrate:

### Using x402 Client

```typescript
import { wrapFetch } from '@x402/client';

const x402Fetch = wrapFetch(fetch, {
  privateKey: process.env.AGENT_PRIVATE_KEY,
});

// Get a quote
const quote = await x402Fetch('https://swap-executor.example.com/quote?tokenIn=0x...&tokenOut=0x...&amountIn=100');
const quoteData = await quote.json();

// Execute swap
const result = await x402Fetch('https://swap-executor.example.com/execute', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    tokenIn: '0x...',
    tokenOut: '0x...',
    amountIn: '100',
    recipient: '0xAgentWallet',
  }),
});
```

## Architecture

```
┌─────────────────┐
│   AI Agents     │ (pay x402 micropayments)
└────────┬────────┘
         │ HTTP + x402
         ▼
┌─────────────────────────────────────────────┐
│           x402 Swap Executor                 │
├─────────────────────────────────────────────┤
│  x402 Middleware (verifies payments)        │
│  ├── /quote    → V3 Quoter                  │
│  ├── /route    → Universal Router           │
│  ├── /execute  → Transaction Builder        │
│  └── /status   → Chain Indexer              │
├─────────────────────────────────────────────┤
│  Relayer Wallet (executes txs for clients)  │
└─────────────────────────────────────────────┘
         │
         ▼
┌─────────────────┐
│   Uniswap V3    │
│   (Monad)    │
└─────────────────┘
```

## Supported Tokens

### Monad Mainnet (Chain ID: 130)

| Token | Address |
|-------|---------|
| WETH | `0x4200000000000000000000000000000000000006` |
| USDC | `0x078D782b760474a361dDA0AF3839290b0EF57AD6` |

### Monad Sepolia (Chain ID: 1301)

| Token | Address |
|-------|---------|
| WETH | `0x4200000000000000000000000000000000000006` |
| USDC | `0x31d0220469e10c4E71834a79b1f276d740d3768F` |

## Uniswap V3 Contracts on Monad

| Contract | Mainnet Address |
|----------|-----------------|
| PoolManager | `0x1f98400000000000000000000000000000000004` |
| Universal Router | `0xef740bf23acae26f6492b10de645d6b98dc8eaf3` |
| Quoter | `0x333e3c607b141b18ff6de9f258db6e77fe7491e0` |
| PositionManager | `0x4529a01c7a0410167c5740c487a8de60232617bf` |
| StateView | `0x86e8631a016f9068c3f085faf484ee3f5fdee8f2` |

## Tech Stack

- **Runtime**: Node.js 20+
- **Framework**: Express.js
- **x402**: `x402-express`, `@coinbase/x402`
- **DEX**: Uniswap V3 SDK + Universal Router
- **Blockchain**: ethers.js v5
- **Network**: Monad (L2)
- **Validation**: Zod
- **Language**: TypeScript

## Roadmap

- [x] Basic quote endpoint
- [x] Route calculation with calldata
- [x] x402 payment integration
- [x] Uniswap V3 migration
- [x] Monad deployment
- [ ] Multi-hop routing
- [ ] Multiple DEX aggregation
- [ ] Account abstraction for gasless execution
- [ ] MCP (Model Context Protocol) server

## Contributing

This project was built for the x402 Hackathon. Contributions welcome!

## License

MIT

---

Built with love for the x402 Hackathon by [Anthony Chavez](https://twitter.com/anthonychavez)
