# 🏗️ VoiceSwap - Arquitectura Completa

**Fecha:** 2025-12-11
**Versión:** 1.0

---

## 📱 Diagrama de Flujo de Usuario (User Journey)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         ONBOARDING (Primera vez)                     │
└─────────────────────────────────────────────────────────────────────┘

Usuario abre app
    ↓
[Pantalla de Bienvenida]
    ↓
Elige método de autenticación:
    ├─ Email (OTP)
    ├─ Apple Sign-In
    ├─ Google Sign-In
    └─ Guest Mode (temporal)
    ↓
[Thirdweb In-App Wallet]
Wallet creada automáticamente
    ↓
[Smart Account Setup]
Backend crea Smart Account (ERC-4337)
Gas sponsorship activado ✅
    ↓
[Pantalla Principal - Home]


┌─────────────────────────────────────────────────────────────────────┐
│                      USO NORMAL (Sesión activa)                      │
└─────────────────────────────────────────────────────────────────────┘

[Pantalla Principal - Home]
    │
    ├─ Ver balance (WETH, USDC, ETH)
    ├─ Historial de swaps
    └─ Botón: "Start Voice Swap" 🎤
         ↓
    [Voice Command Screen]
         ↓
    Usuario se pone Meta Ray-Ban
         ↓
    Usuario dice:
    "Cambia 10 dólares de ETH a USDC"
         ↓
    ┌───────────────────────────────┐
    │   PROCESAMIENTO DE VOZ        │
    └───────────────────────────────┘
         ↓
    Meta Ray-Ban captura audio
         ↓
    Meta Wearables SDK (iOS)
    Envía audio stream a app
         ↓
    Speech-to-Text (Apple Voice Recognition)
    Convierte audio → texto
         ↓
    Texto: "Cambia 10 dólares de ETH a USDC"
         ↓
    ┌───────────────────────────────┐
    │   PROCESAMIENTO INTELIGENTE   │
    └───────────────────────────────┘
         ↓
    App envía a backend:
    POST /voice-command
    {
      "transcript": "Cambia 10 dólares de ETH a USDC",
      "userAddress": "0x..."
    }
         ↓
    Backend detecta idioma: Español
         ↓
    Traduce a inglés (OpenAI):
    "Swap $10 worth of ETH to USDC"
         ↓
    Envía a Thirdweb AI Chat API
         ↓
    Thirdweb AI responde:
    {
      "actions": [{
        "type": "sign_swap",
        "description": "Swap 0.0032 ETH for ~10 USDC",
        "data": "0x3593564c...",
        "value": "0x..."
      }]
    }
         ↓
    ┌───────────────────────────────┐
    │   CONFIRMACIÓN DE USUARIO     │
    └───────────────────────────────┘
         ↓
    [Pantalla de Confirmación]

    📊 Swap Details:
    ━━━━━━━━━━━━━━━━━━━━━━━━
    From:  0.0032 ETH
    To:    ~10.15 USDC

    Price Impact: 0.05%
    Gas: FREE ✅ (Sponsored)

    [Confirmar] [Cancelar]
         ↓
    Usuario toca "Confirmar"
    (O dice "Confirma" por voz)
         ↓
    ┌───────────────────────────────┐
    │   CREACIÓN DE SESSION KEY     │
    └───────────────────────────────┘
         ↓
    Primera vez: Crear session key
    POST /v1/wallets/create-session-key
    {
      "approvedTargets": ["0xef740bf..."], // Universal Router
      "nativeTokenLimitPerTransaction": "0.1 ETH",
      "durationInSeconds": 3600 // 1 hora
    }
         ↓
    Usuario firma UNA vez ✍️
         ↓
    Session key guardada en SecureStore
         ↓
    ┌───────────────────────────────┐
    │   EJECUCIÓN DE SWAP           │
    └───────────────────────────────┘
         ↓
    Backend ejecuta:
    POST /execute
    {
      "tokenIn": "0x4200...", // WETH
      "tokenOut": "0x078D...", // USDC
      "amountIn": "0.0032",
      "recipient": "0x...",
      "useEngine": true
    }
         ↓
    Thirdweb Engine API
    Crea UserOperation (ERC-4337)
    Gas sponsorship automático ✅
         ↓
    Transaction enviada a blockchain
         ↓
    Backend responde:
    {
      "queueId": "tx-1234567890",
      "status": "queued",
      "message": "Swap queued with gas sponsorship"
    }
         ↓
    ┌───────────────────────────────┐
    │   MONITOREO EN TIEMPO REAL    │
    └───────────────────────────────┘
         ↓
    [Pantalla de Progreso]

    ⏳ Swap en progreso...

    Status: Pending
    Tx Hash: 0xabc...def

    [Ver en Explorer]
         ↓
    Mobile App hace polling cada 2 segundos:
    GET /status/tx-1234567890
         ↓
    Backend responde:
    { "status": "pending" }
         ↓
    (Espera 10-30 segundos)
         ↓
    GET /status/tx-1234567890
         ↓
    Backend responde:
    {
      "status": "confirmed",
      "blockNumber": 12345678,
      "confirmations": 5,
      "gasUsed": "0"  // Gas sponsored!
    }
         ↓
    [Pantalla de Éxito]

    ✅ Swap Completado!

    Recibiste: 10.15 USDC
    Gas pagado: $0.00 (Sponsored)

    [Ver Detalles] [Nueva Swap]
         ↓
    Usuario puede:
    ├─ Ver historial
    ├─ Hacer otro swap (sin re-firmar, usa session key)
    └─ Cerrar sesión


┌─────────────────────────────────────────────────────────────────────┐
│                     SWAPS ADICIONALES (Misma sesión)                 │
└─────────────────────────────────────────────────────────────────────┘

Usuario dice otra vez:
"Swap 5 USDC to ETH"
    ↓
Procesamiento (igual que antes)
    ↓
[Pantalla de Confirmación]
    ↓
Usuario confirma
    ↓
¡NO necesita firmar! ✅
Session key válida
    ↓
Swap ejecutado automáticamente
    ↓
[Pantalla de Éxito]


┌─────────────────────────────────────────────────────────────────────┐
│                     OTRAS FUNCIONALIDADES                            │
└─────────────────────────────────────────────────────────────────────┘

[Pantalla de Wallet]
    ├─ Ver balance detallado
    ├─ Historial de transacciones
    ├─ Dirección de wallet (copiar/QR)
    └─ Enviar/Recibir tokens

[Pantalla de Configuración]
    ├─ Idioma (Español/English)
    ├─ Slippage tolerance (0.5% default)
    ├─ Gas sponsorship status
    ├─ Session keys activas
    ├─ Vincular más métodos de auth
    └─ Cerrar sesión
```

---

## 🔧 Estructura del Backend

```
voiceswap/
│
├── 📂 src/
│   │
│   ├── 📂 config/
│   │   ├── networks.ts          # Configuración de chains (Unichain Mainnet/Sepolia)
│   │   │                        # - Chain IDs, RPCs, explorers
│   │   │                        # - Contract addresses (Router, Quoter, StateView)
│   │   │                        # - Fee tiers (LOW, MEDIUM, HIGH)
│   │   └── index.ts             # Exports de config
│   │
│   ├── 📂 routes/
│   │   ├── swap.ts              # 🔹 ENDPOINTS PRINCIPALES
│   │   │                        # GET  /quote      - Cotización de swap
│   │   │                        # POST /route      - Ruta optimizada + calldata
│   │   │                        # POST /execute    - Ejecutar swap
│   │   │                        # GET  /status/:id - Status de transacción
│   │   │                        # GET  /tokens     - Lista de tokens soportados
│   │   │                        # [x402 middleware aplicado a todos]
│   │   │
│   │   └── voice.ts             # 🔹 VOICE COMMANDS (TODO)
│   │                            # POST /voice-command
│   │                            # - Recibe transcript del usuario
│   │                            # - Traduce español → inglés
│   │                            # - Envía a Thirdweb AI Chat
│   │                            # - Ejecuta swap automáticamente
│   │
│   ├── 📂 services/
│   │   │
│   │   ├── uniswap.ts           # 🔹 UNISWAP V4 INTEGRATION
│   │   │                        # class UniswapService {
│   │   │                        #   getQuote()         - Quoter V4
│   │   │                        #   getRoute()         - Routing + calldata
│   │   │                        #   executeSwap()      - Direct execution
│   │   │                        #   getTransactionStatus()
│   │   │                        #
│   │   │                        #   PRIVATE:
│   │   │                        #   buildPoolKey()     - Construir pool key
│   │   │                        #   findBestPool()     - Buscar pool con más liquidez
│   │   │                        #   calculatePriceImpact()
│   │   │                        #   encodeV4SwapCalldata() - Universal Router
│   │   │                        # }
│   │   │
│   │   ├── thirdwebEngine.ts    # 🔹 THIRDWEB ACCOUNT ABSTRACTION
│   │   │                        # class ThirdwebAPIClient {
│   │   │                        #   - API client con authentication
│   │   │                        #   - Secret key en headers
│   │   │                        # }
│   │   │                        #
│   │   │                        # executeSwapViaEngine() {
│   │   │                        #   - Crea smart account si no existe
│   │   │                        #   - Ejecuta tx con gas sponsorship
│   │   │                        #   - Retorna queueId para tracking
│   │   │                        # }
│   │   │                        #
│   │   │                        # getAccountsForUser() - List smart accounts
│   │   │                        # getTransactionStatus() - Track tx
│   │   │
│   │   ├── thirdwebAI.ts        # 🔹 THIRDWEB AI CHAT (TODO)
│   │   │                        # class ThirdwebAI {
│   │   │                        #   chat(transcript, context)
│   │   │                        #   - Envía comando a AI API
│   │   │                        #   - Retorna actions (sign_swap)
│   │   │                        # }
│   │   │
│   │   ├── translation.ts       # 🔹 TRADUCCIÓN ES→EN (TODO)
│   │   │                        # detectLanguage(text)
│   │   │                        # translateToEnglish(text)
│   │   │
│   │   └── uniswapx.ts          # 🔹 UNISWAP X (Futuro)
│   │                            # Para cross-chain swaps
│   │
│   ├── 📂 middleware/
│   │   │
│   │   ├── x402.ts              # 🔹 x402 MICROPAYMENTS
│   │   │                        # - Thirdweb facilitator
│   │   │                        # - Payment settlement
│   │   │                        # - Prices por endpoint
│   │   │                        # - Dev mode (X402_STRICT_MODE=false)
│   │   │                        #
│   │   │                        # requireX402Payment(price)
│   │   │                        # addPaymentInfo()
│   │   │
│   │   └── validation.ts        # 🔹 REQUEST VALIDATION
│   │                            # - Zod schemas
│   │                            # - validateRequest middleware
│   │
│   ├── 📂 types/
│   │   ├── api.ts               # TypeScript types
│   │   │                        # - QuoteRequest/Response
│   │   │                        # - RouteRequest/Response
│   │   │                        # - ExecuteRequest/Response
│   │   │                        # - StatusResponse
│   │   └── contracts.ts         # Contract types
│   │
│   ├── 📂 utils/
│   │   ├── logger.ts            # Winston logger
│   │   ├── errors.ts            # Error handlers
│   │   └── helpers.ts           # Helper functions
│   │
│   └── index.ts                 # 🔹 MAIN SERVER
│                                # - Express app setup
│                                # - CORS, helmet, rate limiting
│                                # - Health check endpoint
│                                # - Route mounting
│                                # - Error handling
│
├── 📂 tests/
│   ├── unit/
│   ├── integration/
│   └── e2e/
│
├── 📂 docs/
│   ├── BACKEND_COMPLETE.md          # Backend status
│   ├── THIRDWEB_COMPLETE_ANALYSIS.md # Roadmap completo
│   ├── SESSION_SUMMARY.md           # Progreso
│   ├── TEST_BACKEND.md              # Testing guide
│   └── X402_INTEGRATION.md          # x402 docs
│
├── 📄 .env                      # Environment variables
├── 📄 .env.example              # Example config
├── 📄 package.json              # Dependencies
├── 📄 tsconfig.json             # TypeScript config
└── 📄 test_endpoints.sh         # Testing script
```

---

## 🔄 Flujo de Datos Detallado

### 1. Quote Request Flow

```
Mobile App
    ↓
POST /quote?tokenIn=WETH&tokenOut=USDC&amountIn=0.1
    ↓
[x402 Middleware]
├─ Check X-Payment header
├─ Settle payment ($0.001)
└─ Allow request ✅
    ↓
[Route Handler: swap.ts]
    ↓
UniswapService.getQuote()
    ↓
├─ getTokenInfo() - Fetch decimals, symbols
├─ findBestPool() - Check liquidity across fee tiers
│   ├─ StateView.getLiquidity(poolId)
│   ├─ Compare LOW (0.05%), MEDIUM (0.3%), HIGH (1%)
│   └─ Return pool con más liquidez
├─ sortTokens() - Ensure currency0 < currency1
├─ buildPoolKey() - Construct pool key struct
│   └─ { currency0, currency1, fee, tickSpacing, hooks }
├─ Quoter V4 Contract
│   ├─ quoteExactInputSingle(quoteParams)
│   └─ Returns: amountOut, gasEstimate
└─ calculatePriceImpact() - From sqrtPriceX96
    ↓
Response:
{
  "success": true,
  "data": {
    "tokenIn": { symbol: "WETH", amount: "0.1", ... },
    "tokenOut": { symbol: "USDC", amount: "305.23", ... },
    "priceImpact": "0.05%",
    "estimatedGas": "133573",
    "route": ["0x4200...", "0x078D..."]
  }
}
```

### 2. Execute Request Flow

```
Mobile App
    ↓
POST /execute
{
  "tokenIn": "0x4200...",
  "tokenOut": "0x078D...",
  "amountIn": "0.1",
  "recipient": "0x2749...",
  "useEngine": true
}
    ↓
[x402 Middleware]
Payment: $0.02
    ↓
[Route Handler: swap.ts]
    ↓
Check useEngine flag
    ↓
IF useEngine === true:
    ↓
    UniswapService.getRoute()
    ├─ getQuote() - Get amounts
    ├─ Calculate slippage (amountOutMin)
    └─ encodeV4SwapCalldata()
        ├─ Actions: [SWAP_EXACT_IN_SINGLE, SETTLE_ALL, TAKE_ALL]
        ├─ Encode params for each action
        ├─ Build Universal Router execute() call
        └─ Return calldata: "0x3593564c..."
    ↓
    ThirdwebEngine.executeSwapViaEngine()
        ↓
        GET /backend-wallet/{chainId}/{userAddress}/get-all-accounts
        ├─ Check if smart account exists
        └─ If not, auto-create
        ↓
        POST /transactions
        {
          "chainId": "130",
          "from": "0x2749...",  // Backend wallet
          "transactions": [{
            "type": "raw",
            "to": "0xef740bf...",  // Universal Router
            "data": "0x3593564c...",
            "value": "0x..."
          }],
          "sponsorGas": true  // ✅ Gas sponsorship
        }
        ↓
        Thirdweb Engine API
        ├─ Create UserOperation (ERC-4337)
        ├─ Calculate gas with Paymaster
        ├─ Submit to bundler
        └─ Return queueId
    ↓
    Response:
    {
      "success": true,
      "data": {
        "status": "queued",
        "queueId": "tx-1234567890",
        "smartAccountAddress": "0x...",
        "routingType": "v4_engine",
        "message": "Transaction queued with gas sponsorship"
      }
    }

IF useEngine === false:
    ↓
    UniswapService.executeSwap()
    ├─ Check relayer wallet balance
    ├─ getRoute() - Generate calldata
    ├─ estimateGas()
    ├─ sendTransaction() - Direct execution
    └─ Return txHash
    ↓
    Response:
    {
      "status": "submitted",
      "txHash": "0xabc..."
    }
```

### 3. Voice Command Flow (TODO)

```
Mobile App (Meta Ray-Ban audio)
    ↓
Speech-to-Text (Apple Voice Recognition)
    ↓
"Cambia 0.1 ETH a USDC"
    ↓
POST /voice-command
{
  "transcript": "Cambia 0.1 ETH a USDC",
  "userAddress": "0x..."
}
    ↓
[Route Handler: voice.ts]
    ↓
detectLanguage(transcript)
├─ "es" detected
└─ translateToEnglish()
    ↓
    OpenAI API (GPT-4)
    Prompt: "Translate to English: Cambia 0.1 ETH a USDC"
    Response: "Swap 0.1 ETH to USDC"
    ↓
ThirdwebAI.chat()
    ↓
    POST https://ai.thirdweb.com/v1/chat
    {
      "messages": [{ role: "user", content: "Swap 0.1 ETH to USDC" }],
      "context": {
        "wallet_address": "0x...",
        "chain_ids": [130]
      }
    }
    ↓
    Thirdweb AI Response:
    {
      "actions": [{
        "type": "sign_swap",
        "description": "Swap 0.1 ETH for ~305.23 USDC",
        "data": "0x3593564c...",
        "value": "0x016345785d8a0000"
      }]
    }
    ↓
executeSwapViaEngine()
├─ Use calldata from AI
└─ Execute with gas sponsorship
    ↓
Response:
{
  "success": true,
  "description": "Swap 0.1 ETH for ~305.23 USDC",
  "queueId": "tx-..."
}
```

---

## 🗄️ Base de Datos (No SQL - Todo en memoria/blockchain)

**Actualmente NO usamos base de datos tradicional:**

- ✅ User wallets → Thirdweb gestiona
- ✅ Transactions → Blockchain (verificamos con RPC)
- ✅ Session keys → SecureStore en mobile
- ✅ x402 payments → Thirdweb gestiona

**Si necesitamos DB en el futuro (opcional):**
```
PostgreSQL/MongoDB:
├─ Users table
│   ├─ id, email, wallet_address
│   └─ created_at, last_login
├─ Transactions table
│   ├─ id, user_id, tx_hash, status
│   ├─ token_in, token_out, amount
│   └─ created_at, confirmed_at
└─ Analytics table
    └─ Track usage, swaps, revenue
```

---

## 🌐 APIs Externas

```
┌─────────────────────────────────────────┐
│     VoiceSwap Backend                    │
└─────────────────────────────────────────┘
         │
         ├─────────────────────────────────┐
         │                                 │
         ↓                                 ↓
┌──────────────────┐            ┌──────────────────┐
│  Thirdweb APIs   │            │  Blockchain RPCs │
└──────────────────┘            └──────────────────┘
         │                                 │
         ├─ Account Abstraction            ├─ Unichain Mainnet RPC
         ├─ Gas Sponsorship                ├─ Unichain Sepolia RPC
         ├─ AI Chat                        ├─ eth_call (quotes)
         ├─ x402 Settlement                ├─ eth_sendTransaction
         └─ Smart Wallet Management        └─ eth_getTransactionReceipt
         │
         ↓
┌──────────────────┐
│   OpenAI API     │
│   (Opcional)     │
└──────────────────┘
         │
         └─ Traducción ES→EN
            (si Thirdweb AI no soporta español)
```

---

## 📦 Dependencias Principales

```json
{
  "dependencies": {
    "express": "^4.18.2",           // Web server
    "ethers": "^5.7.2",             // Ethereum interactions
    "thirdweb": "^5.74.0",          // Thirdweb SDK
    "zod": "^3.22.4",               // Validation
    "cors": "^2.8.5",               // CORS
    "helmet": "^7.1.0",             // Security headers
    "express-rate-limit": "^7.1.5", // Rate limiting
    "dotenv": "^16.3.1",            // Environment vars
    "winston": "^3.11.0"            // Logging
  },
  "devDependencies": {
    "typescript": "^5.3.3",
    "tsx": "^4.7.0",                // TS execution
    "@types/express": "^4.17.21",
    "@types/node": "^20.10.6"
  }
}
```

---

## 🔐 Variables de Entorno

```bash
# Network
NETWORK=unichain                    # o unichain-sepolia
PORT=4021

# Thirdweb
THIRDWEB_CLIENT_ID=d180849f99bd996b77591d55b65373d0
THIRDWEB_SECRET_KEY=lR5bfHCESjbO5...
THIRDWEB_API_URL=https://api.thirdweb.com/v1

# Wallets
BACKEND_WALLET_ADDRESS=0x2749A654FeE5CEc3a8644a27E7498693d0132759
RELAYER_PRIVATE_KEY=0x...           # Para executeSwap directo (opcional)

# Contracts (Unichain)
UNIVERSAL_ROUTER_ADDRESS=0xef740bf23acae26f6492b10de645d6b98dc8eaf3
QUOTER_ADDRESS=0x...
STATE_VIEW_ADDRESS=0x...

# x402
X402_STRICT_MODE=false              # true en producción
PAYMENT_RECEIVER_ADDRESS=0x2749A654FeE5CEc3a8644a27E7498693d0132759

# Node
NODE_ENV=development                # production en deploy
```

---

## 🚀 Performance Metrics

### Latencia Esperada:

```
GET  /quote      → ~500-800ms    (RPC calls)
POST /route      → ~800-1200ms   (quote + encoding)
POST /execute    → ~1500-2500ms  (Thirdweb Engine queue)
GET  /status     → ~200-400ms    (RPC call)

POST /voice-command → ~2000-3500ms
    ├─ Translation: ~500ms
    ├─ Thirdweb AI: ~1000ms
    └─ Execute: ~1500ms
```

### Throughput:

```
Rate Limiting: 100 requests/15min por IP
Concurrent swaps: ~50-100 (limitado por Thirdweb Engine)
```

---

## 📊 Monitoreo y Logging

```typescript
// Winston Logger levels
{
  error: 0,   // Errores críticos
  warn: 1,    // Advertencias
  info: 2,    // Info general (requests, swaps)
  debug: 3    // Debugging (solo dev)
}

// Logs importantes:
- Swap execution (tokenIn, tokenOut, amount)
- Thirdweb Engine calls (queueId, status)
- x402 payments (price, status)
- Errors (stack traces)
```

---

## 🔒 Seguridad

### Backend:
- ✅ Helmet (security headers)
- ✅ CORS configurado
- ✅ Rate limiting
- ✅ Input validation (Zod)
- ✅ x402 payment verification
- ✅ Secret key en env vars

### Mobile App:
- ✅ SecureStore para keys
- ✅ Session keys con límites
- ✅ HTTPS only
- ✅ User confirmation antes de swaps

---

**Siguiente paso:** Implementar features faltantes (In-App Wallets, AI Chat, Transaction Monitoring)
