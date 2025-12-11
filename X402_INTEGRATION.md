# x402 Payment Integration Guide

## Overview

VoiceSwap API integrates **x402 micropayments** using Thirdweb, enabling AI agents and apps to pay for API usage automatically.

---

## How It Works

### Payment Flow

1. **Client requests endpoint** without payment
2. **API returns `402 Payment Required`** with payment details
3. **Thirdweb x402 handles payment** automatically
4. **Client retries with payment header**
5. **API validates payment** and returns response

This is transparent to users when using Thirdweb's x402 tools.

---

## API Endpoints & Pricing

| Endpoint | Method | Price | Description |
|----------|--------|-------|-------------|
| `/quote` | GET/POST | $0.001 | Get swap quote |
| `/route` | POST | $0.005 | Get route with calldata |
| `/execute` | POST | $0.02 | Execute swap (gasless) |
| `/status/:id` | GET | $0.001 | Check transaction status |
| `/health` | GET | FREE | Health check |
| `/tokens` | GET | FREE | List supported tokens |

---

## Using the API

### Option 1: Thirdweb MCP Server (Recommended for AI Agents)

Configure your AI agent to use Thirdweb's x402 MCP server:

```typescript
import { createReactAgent } from "@langchain/langgraph";

const agent = createReactAgent({
  llm: model,
  tools: mcpTools, // From Thirdweb MCP
  prompt: `You can access VoiceSwap API using fetchWithPayment.

  Base URL: https://your-backend.railway.app

  Available endpoints:
  - GET /quote?tokenIn=0x...&tokenOut=0x...&amountIn=0.1
  - POST /route with JSON body
  - POST /execute with JSON body
  - GET /status/:identifier
  `
});
```

The agent will automatically handle payments.

### Option 2: Direct API Calls with Thirdweb SDK

```typescript
import { createThirdwebClient } from "thirdweb";
import { facilitator, settlePayment } from "thirdweb/x402";
import { arbitrumSepolia } from "thirdweb/chains";

const client = createThirdwebClient({
  secretKey: "your-secret-key"
});

const x402Facilitator = facilitator({
  client,
  serverWalletAddress: "0x...", // Your wallet
});

// Make a paid API call
const result = await settlePayment({
  resourceUrl: "https://your-backend.railway.app/quote?tokenIn=0x...&tokenOut=0x...&amountIn=0.1",
  method: "GET",
  network: arbitrumSepolia,
  price: "$0.001",
  facilitator: x402Facilitator,
});

if (result.status === 200) {
  console.log("Quote:", result.responseBody);
}
```

### Option 3: Using Thirdweb's fetchWithPayment Endpoint

```bash
curl -X POST "https://api.thirdweb.com/v1/x402/fetchWithPayment" \
  -H "x-secret-key: your-thirdweb-secret" \
  -H "Content-Type: application/json" \
  -d '{
    "url": "https://your-backend.railway.app/quote?tokenIn=0x4200000000000000000000000000000000000006&tokenOut=0x078D782b760474a361dDA0AF3839290b0EF57AD6&amountIn=0.1",
    "method": "GET",
    "chainId": "eip155:421614"
  }'
```

---

## Configuration

### Backend Configuration

Your backend `.env` needs:

```env
# Thirdweb (for x402 payments)
THIRDWEB_SECRET_KEY=your_secret_key
PAYMENT_RECEIVER_ADDRESS=0x2749A654FeE5CEc3a8644a27E7498693d0132759

# x402 Settings
X402_STRICT_MODE=false  # false = allow access in dev, true = require payment
NODE_ENV=development    # Set to 'production' for prod
```

### Payment Network

Payments are processed on:
- **Development**: Arbitrum Sepolia (testnet)
- **Production**: Arbitrum (mainnet)

To receive payments, ensure your `PAYMENT_RECEIVER_ADDRESS` wallet has gas on the payment network.

---

## Development vs Production

### Development Mode (`X402_STRICT_MODE=false`)

- Endpoints work **without payment**
- Payment errors are logged but don't block access
- Useful for testing

### Production Mode (`X402_STRICT_MODE=true`)

- **Payment required** for all paid endpoints
- Payment failures return `402` or `500`
- Recommended for production

---

## Testing x402 Payments

### 1. Test without payment (dev mode)

```bash
curl "http://localhost:4021/quote?tokenIn=0x4200000000000000000000000000000000000006&tokenOut=0x078D782b760474a361dDA0AF3839290b0EF57AD6&amountIn=0.1"
```

Should work in dev mode.

### 2. Test with payment required (strict mode)

Set in `.env`:
```env
X402_STRICT_MODE=true
```

Restart server. Same curl will return:
```json
{
  "error": "Payment required",
  "code": "X402_PAYMENT_REQUIRED",
  "price": "$0.001",
  "network": "arbitrum-sepolia",
  "receiver": "0x2749A654FeE5CEc3a8644a27E7498693d0132759"
}
```

### 3. Test with Thirdweb x402

Use Thirdweb's `fetchWithPayment` as shown above.

---

## Response Headers

All responses include x402 payment info headers:

```
X-Payment-Required: true
X-Payment-Price: $0.001
X-Payment-Network: arbitrum-sepolia
X-Payment-Receiver: 0x2749A654FeE5CEc3a8644a27E7498693d0132759
X-Payment-Endpoint: /quote
Access-Control-Expose-Headers: X-Payment-Required, X-Payment-Price, X-Payment-Network, X-Payment-Receiver
```

Clients can read these to understand payment requirements.

---

## Example: Mobile App Integration

In your React Native mobile app:

```typescript
import { createThirdwebClient } from "thirdweb";
import { settlePayment, facilitator } from "thirdweb/x402";
import { arbitrumSepolia } from "thirdweb/chains";

const client = createThirdwebClient({
  clientId: process.env.EXPO_PUBLIC_THIRDWEB_CLIENT_ID!,
});

// User's wallet will pay
const userFacilitator = facilitator({
  client,
  serverWalletAddress: userWalletAddress, // Connected wallet
});

async function getQuote(tokenIn: string, tokenOut: string, amountIn: string) {
  const backendUrl = process.env.EXPO_PUBLIC_BACKEND_URL;

  const result = await settlePayment({
    resourceUrl: `${backendUrl}/quote?tokenIn=${tokenIn}&tokenOut=${tokenOut}&amountIn=${amountIn}`,
    method: "GET",
    network: arbitrumSepolia,
    price: "$0.001",
    facilitator: userFacilitator,
  });

  if (result.status === 200) {
    return result.responseBody.data;
  } else {
    throw new Error(`API error: ${result.status}`);
  }
}
```

---

## Gas Tank (Optional)

Thirdweb x402 supports **gas tanks** for pre-funding multiple API calls:

```typescript
// Create gas tank
const gasTank = await createGasTank({
  client,
  amount: "0.01", // Pre-fund with 0.01 ETH worth of credits
  network: arbitrumSepolia,
});

// Use gas tank for requests
await settlePayment({
  resourceUrl: "...",
  method: "GET",
  price: "$0.001",
  facilitator: userFacilitator,
  gasTankId: gasTank.id, // Deduct from tank
});
```

This reduces per-request transaction overhead.

---

## Monitoring Payments

### View Received Payments

Check your `PAYMENT_RECEIVER_ADDRESS` on:
- **Testnet**: https://sepolia.arbiscan.io/address/0x2749A654FeE5CEc3a8644a27E7498693d0132759
- **Mainnet**: https://arbiscan.io/address/0x2749A654FeE5CEc3a8644a27E7498693d0132759

### Backend Logs

The backend logs all payment attempts:

```
[x402] Processing payment for https://api.example.com/quote ($0.001)
[x402] Payment successful for https://api.example.com/quote
```

Or:

```
[x402] Payment required for https://api.example.com/quote: 402
```

---

## Troubleshooting

### Error: "Thirdweb client not initialized"

**Fix**: Ensure `THIRDWEB_SECRET_KEY` is set in `.env`

### Error: "Payment processing failed"

**Causes**:
- Insufficient balance in payer wallet
- Wrong network (check Arbitrum Sepolia for testnet)
- Invalid payment receiver address

**Fix**:
- Fund wallet on correct network
- Verify `PAYMENT_RECEIVER_ADDRESS` is correct

### Payments work but API still returns 402

**Cause**: `X402_STRICT_MODE=true` but payment not properly validated

**Fix**: Check backend logs for x402 errors

### Free endpoints returning 402

**Cause**: Middleware applied to wrong routes

**Fix**: Free endpoints (`/health`, `/tokens`) should NOT have `requireX402Payment()` middleware

---

## Production Checklist

Before deploying:

- [ ] Set `X402_STRICT_MODE=true`
- [ ] Set `NODE_ENV=production`
- [ ] Verify `PAYMENT_RECEIVER_ADDRESS` is correct
- [ ] Fund payment receiver with gas on Arbitrum
- [ ] Test all paid endpoints with x402
- [ ] Monitor payment logs

---

## Additional Resources

- [Thirdweb x402 Docs](https://portal.thirdweb.com/x402)
- [x402 for AI Agents](https://portal.thirdweb.com/x402/agents)
- [Thirdweb MCP Server](https://portal.thirdweb.com/x402/mcp)
- [x402 Protocol](https://x402.org)

---

## Support

For x402 integration help:
- Thirdweb Discord: https://discord.gg/thirdweb
- x402 Protocol: https://x402.org

---

**Last Updated:** 2025-12-11
