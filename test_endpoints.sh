#!/bin/bash

# Configuration
API_URL="http://localhost:4021"
TOKEN_IN="0x4200000000000000000000000000000000000006" # WETH
TOKEN_OUT="0x078D782b760474a361dDA0AF3839290b0EF57AD6" # USDC (Mainnet)
RECIPIENT="0x2749A654FeE5CEc3a8644a27E7498693d0132759" # Backend wallet
AMOUNT_IN="0.001"

echo "🧪 Starting x402 Swap Executor Tests..."
echo "Target: $API_URL"
echo "----------------------------------------"

# 1. Health Check
echo "1️⃣  Testing /health..."
curl -s "$API_URL/health" | python3 -m json.tool || echo "❌ Failed"
echo "----------------------------------------"

# 2. Get Quote (Hybrid V4 + Uniswap X)
echo "2️⃣  Testing /quote (Hybrid)..."
RESPONSE=$(curl -s "$API_URL/quote?tokenIn=$TOKEN_IN&tokenOut=$TOKEN_OUT&amountIn=$AMOUNT_IN")
echo "$RESPONSE" | python3 -m json.tool
echo "----------------------------------------"

# 3. Calculate Route
echo "3️⃣  Testing /route..."
curl -s -X POST "$API_URL/route" \
  -H "Content-Type: application/json" \
  -d "{
    \"tokenIn\": \"$TOKEN_IN\",
    \"tokenOut\": \"$TOKEN_OUT\",
    \"amountIn\": \"$AMOUNT_IN\",
    \"recipient\": \"$RECIPIENT\",
    \"slippageTolerance\": 0.5
  }" | python3 -m json.tool
echo "----------------------------------------"

# 4. Test /execute with Thirdweb Engine (simulated)
echo "4️⃣  Testing /execute (Thirdweb Engine)..."
curl -s -X POST "$API_URL/execute" \
  -H "Content-Type: application/json" \
  -d "{
    \"tokenIn\": \"$TOKEN_IN\",
    \"tokenOut\": \"$TOKEN_OUT\",
    \"amountIn\": \"$AMOUNT_IN\",
    \"recipient\": \"$RECIPIENT\",
    \"slippageTolerance\": 0.5,
    \"useEngine\": true
  }" | python3 -m json.tool
echo "----------------------------------------"

# 5. Test /tokens endpoint
echo "5️⃣  Testing /tokens..."
curl -s "$API_URL/tokens" | python3 -m json.tool
echo "----------------------------------------"

echo "✅ Tests Completed. Check output for errors."
