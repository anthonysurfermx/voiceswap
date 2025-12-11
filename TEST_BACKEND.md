# Backend Testing Guide

## Prerequisites

Make sure you have Node.js installed:
```bash
node --version  # Should be v18+ or v20+
npm --version
```

## Step 1: Install Dependencies

```bash
cd /Users/mrrobot/Documents/GitHub/voiceswap
npm install
```

## Step 2: Verify Environment Configuration

Check your `.env` file has the following:

```bash
cat .env
```

Should contain:
```env
# Network Configuration
NETWORK=unichain
UNICHAIN_RPC_URL=https://mainnet.unichain.org

# Thirdweb Configuration
THIRDWEB_SECRET_KEY=***REMOVED_THIRDWEB_SECRET***
THIRDWEB_CLIENT_ID=***REMOVED_THIRDWEB_CLIENT_ID***
BACKEND_WALLET_ADDRESS=0x2749A654FeE5CEc3a8644a27E7498693d0132759

# Thirdweb API URL
THIRDWEB_API_URL=https://api.thirdweb.com/v1

# Universal Router
UNIVERSAL_ROUTER_ADDRESS=0xef740bf23acae26f6492b10de645d6b98dc8eaf3

# x402 Configuration
CDP_API_KEY_ID=your_cdp_api_key_id
CDP_API_KEY_SECRET=your_cdp_api_key_secret
PAYMENT_RECEIVER_ADDRESS=0x2749A654FeE5CEc3a8644a27E7498693d0132759

# Server
PORT=4021
```

## Step 3: Start the Backend Server

```bash
npm run dev
```

Expected output:
```
Server running on http://localhost:4021
Network: unichain
Chain ID: 130
Thirdweb API: Configured ✓
```

## Step 4: Test Health Endpoint

In a new terminal:

```bash
curl http://localhost:4021/health
```

Expected response:
```json
{
  "status": "ok",
  "service": "x402-swap-executor",
  "version": "2.2.0",
  "network": "unichain",
  "protocol": "Uniswap V4 + Uniswap X",
  "features": {
    "accountAbstraction": true,
    "gasSponsorship": true,
    "thirdwebEngine": true
  },
  "timestamp": "2025-12-11T..."
}
```

## Step 5: Test Quote Endpoint

```bash
curl "http://localhost:4021/quote?tokenIn=0x4200000000000000000000000000000000000006&tokenOut=0x078D782b760474a361dDA0AF3839290b0EF57AD6&amountIn=0.1"
```

**Token Addresses (Unichain Mainnet):**
- WETH: `0x4200000000000000000000000000000000000006`
- USDC: `0x078D782b760474a361dDA0AF3839290b0EF57AD6`

Expected response:
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
      "address": "0x078D782b760474a361dDA0AF3839290b0EF57AD6",
      "symbol": "USDC",
      "decimals": 6,
      "amount": "...",
      "amountRaw": "..."
    },
    "priceImpact": "0.05",
    "route": [...],
    "estimatedGas": "...",
    "timestamp": ...,
    "routingType": "v4"
  }
}
```

## Step 6: Test Route Endpoint (with Calldata)

```bash
curl -X POST http://localhost:4021/route \
  -H "Content-Type: application/json" \
  -d '{
    "tokenIn": "0x4200000000000000000000000000000000000006",
    "tokenOut": "0x078D782b760474a361dDA0AF3839290b0EF57AD6",
    "amountIn": "0.1",
    "recipient": "0x2749A654FeE5CEc3a8644a27E7498693d0132759",
    "slippageTolerance": 0.5
  }'
```

Expected response should include `calldata` field:
```json
{
  "success": true,
  "data": {
    ...,
    "calldata": "0x...",
    "value": "0",
    "to": "0xef740bf23acae26f6492b10de645d6b98dc8eaf3",
    "slippageTolerance": 0.5,
    "deadline": ...
  }
}
```

## Step 7: Test Thirdweb API Integration (DRY RUN)

**IMPORTANT:** This will attempt to submit a transaction to Thirdweb API. Make sure you have gas sponsorship configured first!

```bash
curl -X POST http://localhost:4021/execute \
  -H "Content-Type: application/json" \
  -d '{
    "tokenIn": "0x4200000000000000000000000000000000000006",
    "tokenOut": "0x078D782b760474a361dDA0AF3839290b0EF57AD6",
    "amountIn": "0.001",
    "recipient": "0x2749A654FeE5CEc3a8644a27E7498693d0132759",
    "slippageTolerance": 0.5,
    "useEngine": true
  }'
```

Expected response:
```json
{
  "success": true,
  "data": {
    "status": "queued",
    "queueId": "...",
    "smartAccountAddress": "0x2749A654FeE5CEc3a8644a27E7498693d0132759",
    "routingType": "v4_engine",
    "message": "Transaction queued with gas sponsorship"
  }
}
```

## Common Errors and Fixes

### Error: "Thirdweb API error: Unauthorized"
**Fix:** Check that `THIRDWEB_SECRET_KEY` in `.env` is correct

### Error: "Failed to get quote"
**Fix:**
- Verify `NETWORK=unichain` and `UNICHAIN_RPC_URL=https://mainnet.unichain.org`
- Check that token addresses are correct for Unichain mainnet

### Error: "Gas sponsorship failed"
**Fix:** You need to configure gas sponsorship in Thirdweb dashboard first (see Step 8)

### Error: "Backend wallet has insufficient balance"
**Fix:** Fund the backend wallet with ETH on Unichain mainnet

## Step 8: Configure Gas Sponsorship (Required for Execute)

1. Go to [Thirdweb Dashboard](https://thirdweb.com/dashboard)
2. Navigate to Settings → Sponsorship
3. Enable gas sponsorship for Chain ID **130** (Unichain Mainnet)
4. Add Universal Router to whitelist: `0xef740bf23acae26f6492b10de645d6b98dc8eaf3`
5. Fund the paymaster with at least 0.05 ETH

## Step 9: Fund Backend Wallet

Your backend wallet needs ETH on Unichain Mainnet:

**Wallet:** `0x2749A654FeE5CEc3a8644a27E7498693d0132759`

Options:
- Bridge from Ethereum mainnet via [Unichain Bridge](https://bridge.unichain.org)
- Transfer from another wallet on Unichain
- Buy ETH on an exchange that supports Unichain

Minimum recommended: **0.1 ETH**

## Next Steps

Once backend testing passes:

1. ✅ Configure gas sponsorship in Thirdweb dashboard
2. ✅ Fund backend wallet with ETH
3. ✅ Deploy backend to production (Railway/Render)
4. ✅ Update mobile app `.env` with production backend URL
5. ✅ Install mobile app dependencies and test

## Useful Commands

```bash
# Check backend logs
npm run dev

# Build for production
npm run build

# Start production server
npm start

# Check TypeScript errors
npx tsc --noEmit
```

## Production Deployment

See [QUICKSTART.md](./QUICKSTART.md) for Railway deployment instructions.
