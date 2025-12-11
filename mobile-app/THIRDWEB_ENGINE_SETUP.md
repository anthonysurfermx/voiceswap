# Thirdweb Engine + Account Abstraction Setup

## 🎯 **Por qué usar Thirdweb Engine**

Thirdweb Engine es una **API backend lista para producción** que maneja:
- ✅ Smart Account deployment automático
- ✅ Gas sponsorship (paymaster)
- ✅ Transaction bundling
- ✅ Nonce management
- ✅ Retry logic
- ✅ Webhook notifications

**En lugar de implementar Account Abstraction desde cero, usamos Engine como backend.**

---

## 🏗️ **Arquitectura con Thirdweb Engine**

```
┌─────────────────────────────────────┐
│     iOS App (React Native/Expo)     │
│  ┌───────────────────────────────┐  │
│  │  Thirdweb SDK (wallet connect)│  │
│  └───────────────────────────────┘  │
│  ┌───────────────────────────────┐  │
│  │  Meta Ray-Ban (Voice I/O)     │  │
│  └───────────────────────────────┘  │
└─────────────────────────────────────┘
              ↓ HTTPS
┌─────────────────────────────────────┐
│   Thirdweb Engine (Self-hosted)     │
│   - Smart Account management        │
│   - Gas sponsorship                 │
│   - Transaction execution           │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│  Your Backend (Express + x402)      │
│  - Swap quotes (x402)               │
│  - Transaction routing              │
│  - Voice intent parsing             │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│  Uniswap V4 (Unichain)              │
└─────────────────────────────────────┘
```

---

## 📋 **Setup Paso a Paso**

### **Opción 1: Thirdweb Cloud Engine (Recomendado para hackathon)**

#### Paso 1: Crear Engine Instance

1. Ve a [thirdweb.com/dashboard/engine](https://thirdweb.com/dashboard/engine)
2. Click **Create Engine**
3. Configura:
   - **Name**: `voiceswap-engine`
   - **Plan**: Growth (gratis con código `x402-GROWTH-2M`)
   - **Region**: US East (más cercano)

4. Guarda tu **Engine URL** y **Access Token**:
```env
THIRDWEB_ENGINE_URL=https://engine-xxx.thirdweb.com
THIRDWEB_ENGINE_ACCESS_TOKEN=thirdweb_xxxxxxxx
```

#### Paso 2: Configurar Backend Wallet

Tu Engine necesita un wallet para firmar transacciones:

1. En el dashboard de Engine, ve a **Backend Wallets**
2. Click **Import Wallet**
3. Opciones:
   - **Local Wallet**: Importa con private key (para testing)
   - **AWS KMS**: Para producción (más seguro)
   - **Google KMS**: Alternativa

4. Usa tu wallet de desarrollo:
```bash
# Genera nueva o usa existente
BACKEND_WALLET_ADDRESS=0xTuBackendWallet
```

#### Paso 3: Habilitar Account Abstraction

1. En Engine dashboard, ve a **Features → Account Abstraction**
2. Activa **Smart Backend Wallets**
3. Configura Paymaster:
   - **Chain**: Unichain Sepolia (1301)
   - **Paymaster Address**: (Thirdweb te da uno por defecto)
4. Deposita fondos al paymaster (0.05 ETH para testing)

#### Paso 4: Configurar tu Backend

Actualiza tu backend Express para usar Engine:

```bash
cd ..  # Volver a raíz
npm install @thirdweb-dev/engine
```

Crea `src/services/thirdwebEngine.ts`:

```typescript
import { Engine } from '@thirdweb-dev/engine';

const engine = new Engine({
  url: process.env.THIRDWEB_ENGINE_URL!,
  accessToken: process.env.THIRDWEB_ENGINE_ACCESS_TOKEN!,
});

/**
 * Create or get smart account for user
 */
export async function getOrCreateSmartAccount(userAddress: string) {
  try {
    // Check if user already has a smart account
    const accounts = await engine.account.getAll({
      chain: 'unichain-sepolia',
      admin: userAddress,
    });

    if (accounts.length > 0) {
      return accounts[0].address;
    }

    // Create new smart account
    const result = await engine.account.create({
      chain: 'unichain-sepolia',
      admin: userAddress,
      // Engine automatically uses Smart Backend Wallet
    });

    return result.accountAddress;
  } catch (error) {
    console.error('[Engine] Failed to get/create smart account:', error);
    throw error;
  }
}

/**
 * Execute swap transaction via smart account
 */
export async function executeSwapViaEngine(params: {
  userAddress: string;
  tokenIn: string;
  tokenOut: string;
  amountIn: string;
  calldata: string;
}) {
  // Get or create smart account for user
  const smartAccountAddress = await getOrCreateSmartAccount(params.userAddress);

  // Execute transaction with gas sponsorship
  const result = await engine.transaction.write({
    chain: 'unichain-sepolia',
    contractAddress: params.tokenOut, // Universal Router address
    functionName: 'execute', // Your swap function
    args: [/* calldata args */],
    // Engine automatically sponsors gas if paymaster is configured
    txOverrides: {
      // Optional: customize gas, etc
    },
    // Smart account handles the UserOp
    account: smartAccountAddress,
  });

  return {
    queueId: result.queueId,
    smartAccountAddress,
  };
}

/**
 * Check transaction status
 */
export async function checkTransactionStatus(queueId: string) {
  const status = await engine.transaction.status(queueId);

  return {
    status: status.status, // 'queued' | 'sent' | 'mined' | 'errored'
    transactionHash: status.transactionHash,
    blockNumber: status.blockNumber,
    errorMessage: status.errorMessage,
  };
}

export { engine };
```

---

### **Opción 2: Self-Hosted Engine (Producción)**

Si quieres control completo:

#### Paso 1: Deploy Engine

```bash
# Clonar Engine
git clone https://github.com/thirdweb-dev/engine.git
cd engine

# Configurar .env
cp .env.example .env
```

Edita `.env`:
```env
# Thirdweb
THIRDWEB_API_SECRET_KEY=***REMOVED_THIRDWEB_SECRET***

# Database (PostgreSQL required)
DATABASE_URL=postgresql://user:password@localhost:5432/engine

# Backend wallet
BACKEND_WALLET_PRIVATE_KEY=0x...

# Admin API key (genera uno seguro)
ADMIN_API_KEY=your_secure_admin_key_here
```

#### Paso 2: Deploy con Docker

```bash
# Build
docker-compose build

# Run
docker-compose up -d

# Check logs
docker-compose logs -f
```

Engine estará en: `http://localhost:3005`

#### Paso 3: Configurar Paymaster

```bash
# Via API
curl -X POST http://localhost:3005/configuration/chains \
  -H "Authorization: Bearer ${ADMIN_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "chainId": 1301,
    "paymasterAddress": "0x...",
    "paymasterSponsorshipPolicy": "always"
  }'
```

---

## 🔗 **Integrar Engine en tu App**

### Actualizar Backend Express

En `src/routes/swap.ts`:

```typescript
import { getOrCreateSmartAccount, executeSwapViaEngine } from '../services/thirdwebEngine';

// Endpoint para ejecutar swap
router.post('/execute', async (req, res) => {
  try {
    const { tokenIn, tokenOut, amountIn, recipient } = req.body;

    // 1. Obtener calldata de Uniswap
    const route = await uniswapService.getRoute({
      tokenIn,
      tokenOut,
      amountIn,
      recipient,
    });

    // 2. Ejecutar via Engine (gas sponsorship automático)
    const result = await executeSwapViaEngine({
      userAddress: recipient,
      tokenIn,
      tokenOut,
      amountIn,
      calldata: route.calldata,
    });

    res.json({
      success: true,
      data: {
        queueId: result.queueId,
        smartAccountAddress: result.smartAccountAddress,
        status: 'queued',
      },
    });
  } catch (error) {
    console.error('[Swap] Execute failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Endpoint para check status
router.get('/status/:queueId', async (req, res) => {
  try {
    const { queueId } = req.params;
    const status = await checkTransactionStatus(queueId);

    res.json({
      success: true,
      data: status,
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});
```

### Actualizar Mobile App

En `src/services/SwapService.ts`, no necesitas cambiar mucho:

```typescript
async executeSwap(params: SwapParams): Promise<ExecuteResponse> {
  // El backend ahora usa Engine internamente
  const response = await fetch(`${this.baseUrl}/execute`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(params),
  });

  const data = await response.json();

  if (!data.success) {
    throw new Error(data.error);
  }

  // Engine devuelve queueId en lugar de txHash inmediatamente
  return {
    status: 'pending',
    queueId: data.data.queueId,
    smartAccountAddress: data.data.smartAccountAddress,
  };
}

async getStatus(queueId: string): Promise<StatusResponse> {
  const response = await fetch(`${this.baseUrl}/status/${queueId}`);
  const data = await response.json();

  return {
    status: data.data.status === 'mined' ? 'confirmed' : 'pending',
    txHash: data.data.transactionHash,
    blockNumber: data.data.blockNumber,
  };
}
```

---

## 🎯 **Ventajas de usar Engine**

### **vs. SDK directo:**
- ✅ Backend maneja complejidad de ERC-4337
- ✅ Retry automático si falla
- ✅ Queue management
- ✅ Webhooks para notificaciones
- ✅ No expones private keys en app

### **vs. Implementación custom:**
- ✅ 90% menos código
- ✅ Ya probado en producción
- ✅ Actualizaciones automáticas
- ✅ Soporte de Thirdweb

---

## 🧪 **Testing**

### Test local con Engine Cloud:

```bash
# 1. Backend
cd ..
npm run dev

# 2. Mobile app
cd mobile-app
npm run ios

# 3. Hacer un swap
# Voice: "swap 10 USDC to WETH"
# Voice: "yes"

# 4. Verificar en Engine dashboard:
# - Transaction queue
# - Gas sponsored
# - UserOp ejecutado
```

---

## 📊 **Monitoreo**

### Engine Dashboard

1. **Transactions**: Ver todas las transacciones en queue/sent/mined
2. **Backend Wallets**: Balance del wallet backend
3. **Webhooks**: Configurar notificaciones
4. **Logs**: Debugging en tiempo real

### Webhooks (Opcional)

Recibe notificaciones cuando transacciones se minan:

```typescript
// En tu backend
router.post('/webhooks/engine', (req, res) => {
  const event = req.body;

  if (event.type === 'transaction_mined') {
    // Notificar al usuario via push notification
    console.log(`Transaction mined: ${event.data.transactionHash}`);

    // Actualizar estado en tu DB
    // Enviar push notification
  }

  res.json({ received: true });
});
```

Configurar en Engine dashboard:
- **Webhook URL**: `https://tu-backend.com/webhooks/engine`
- **Events**: transaction_mined, transaction_errored

---

## ⚡ **Comparación: Con vs Sin Engine**

### **Sin Engine (implementación custom)**
- 500+ líneas de código para Account Abstraction
- Manejar UserOp, bundler, paymaster manualmente
- Gestión de nonces
- Retry logic custom
- 2-3 semanas de desarrollo

### **Con Engine**
- 50 líneas de código
- API REST simple
- Todo manejado automáticamente
- 1-2 días de integración

---

## 🚀 **Próximos Pasos**

1. **Ahora (30 min):**
   - Crear Engine instance en Thirdweb dashboard
   - Obtener Engine URL + Access Token
   - Configurar backend wallet

2. **Hoy (2 horas):**
   - Instalar `@thirdweb-dev/engine` en backend
   - Crear `thirdwebEngine.ts` service
   - Actualizar endpoint `/execute`

3. **Mañana:**
   - Testing end-to-end
   - Deploy backend con Engine integrado
   - Probar con Meta Ray-Ban

---

## 🔗 **Recursos**

- [Thirdweb Engine Docs](https://portal.thirdweb.com/engine)
- [Account Abstraction Features](https://portal.thirdweb.com/engine/v2/features/account-abstraction)
- [Engine GitHub](https://github.com/thirdweb-dev/engine)
- [Smart Backend Wallets](https://portal.thirdweb.com/engine/features/smart-wallets)

---

## ❓ **FAQ**

### ¿Engine reemplaza mi backend?
No. Engine complementa tu backend:
- **Tu backend**: Lógica de negocio, x402, quotes
- **Engine**: Account Abstraction, gas sponsorship, transactions

### ¿Necesito self-hosted o cloud?
- **Hackathon/MVP**: Cloud (más rápido)
- **Producción**: Considera self-hosted (más control)

### ¿Cuánto cuesta Engine?
- **Development**: Gratis
- **Growth**: Gratis con código `x402-GROWTH-2M`
- **Production**: Ver pricing en dashboard

### ¿Funciona con x402?
Sí! Tu backend sigue usando x402 para quotes/routes.
Engine solo maneja la ejecución de la transacción final.

---

¿Quieres que te ayude a configurar Engine step-by-step?
