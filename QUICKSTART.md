# 🚀 VoiceSwap Quick Start

## Setup en 15 minutos

### 1. Crear Thirdweb Engine (5 min)

```bash
# 1. Ve a: https://thirdweb.com/dashboard/engine
# 2. Click "Create Engine"
# 3. Nombre: voiceswap-engine
# 4. Plan: Growth
# 5. Ingresa código: x402-GROWTH-2M
# 6. Click "Create"
# 7. Copia: Engine URL y Access Token
```

### 2. Configurar Backend Wallet (3 min)

```bash
# En Engine dashboard:
# 1. Go to "Backend Wallets"
# 2. Click "Import Wallet"
# 3. Pega tu private key de desarrollo
# 4. Guarda la address
```

### 3. Activar Gas Sponsorship (5 min)

```bash
# En Engine dashboard:
# 1. Features → Account Abstraction
# 2. Toggle "Smart Backend Wallets" ON
# 3. Depositar fondos:
#    - Chain: Unichain Sepolia (1301)
#    - Amount: 0.05 ETH
# 4. Configurar whitelist:
#    - Add contract: 0xef740bf23acae26f6492b10de645d6b98dc8eaf3
```

### 4. Configurar Variables de Entorno (2 min)

```bash
# Backend .env
cd /Users/mrrobot/Documents/GitHub/voiceswap
cp .env.example .env

# Edita y añade:
THIRDWEB_ENGINE_URL=https://engine-xxx.thirdweb.com
THIRDWEB_ENGINE_ACCESS_TOKEN=thirdweb_xxxxxxxx
BACKEND_WALLET_ADDRESS=0xYourBackendWallet
```

```bash
# Mobile .env (ya está configurado con tus credenciales)
cd mobile-app

# Solo añade OpenAI key si tienes:
# EXPO_PUBLIC_OPENAI_API_KEY=sk-proj-xxx
```

---

## Testing Local (5 min)

### Terminal 1: Backend

```bash
cd /Users/mrrobot/Documents/GitHub/voiceswap
npm install
npm run dev

# Deberías ver:
# Server running on http://localhost:4021
# Thirdweb Engine: ✓ Connected
```

### Terminal 2: Mobile App

```bash
cd /Users/mrrobot/Documents/GitHub/voiceswap/mobile-app
npm install
npm run ios

# Espera a que Expo abra el simulador
```

---

## Probar el Flujo (10 min)

### 1. En el Simulador iOS

1. Click "Connect Wallet"
2. Selecciona MetaMask/Coinbase
3. Autoriza conexión
4. Verifica que muestra tu address

### 2. Voice Command (Simulado)

En la app, usa el botón para probar comando:

```typescript
// Test command
"swap 10 USDC to WETH"
```

Deberías ver:
- ✅ Quote obtenida
- ✅ Confirmation prompt
- ✅ "Say yes to confirm"

### 3. Ejecutar Swap

Simula: "yes"

Deberías ver:
- ✅ "Transaction queued"
- ✅ queueId en logs
- ✅ Smart account address
- ✅ "Gas sponsored by VoiceSwap"

### 4. Verificar en Engine Dashboard

```bash
# Ve a: https://thirdweb.com/dashboard/engine
# Transactions → Recent
# Deberías ver tu transaction con status: mined
```

---

## Deploy Backend (15 min)

### Railway (Recomendado)

```bash
# 1. Instalar CLI
npm install -g @railway/cli

# 2. Login
railway login

# 3. Inicializar proyecto
cd /Users/mrrobot/Documents/GitHub/voiceswap
railway init

# Nombre: voiceswap-backend

# 4. Añadir variables de entorno en Railway dashboard
railway variables set THIRDWEB_ENGINE_URL=https://...
railway variables set THIRDWEB_ENGINE_ACCESS_TOKEN=thirdweb_xxx
railway variables set BACKEND_WALLET_ADDRESS=0x...
railway variables set NETWORK=unichain-sepolia

# 5. Deploy
railway up

# 6. Obtener URL
railway domain

# Output: voiceswap-backend.railway.app
```

### Actualizar Mobile App

```bash
cd mobile-app

# Edita .env:
EXPO_PUBLIC_BACKEND_URL=https://voiceswap-backend.railway.app
```

---

## Troubleshooting

### Error: "Engine not responding"

```bash
# Check Engine health
curl https://your-engine-url.thirdweb.com/health

# Verifica access token en .env
```

### Error: "Gas sponsorship failed"

```bash
# 1. Verifica fondos en paymaster:
#    Engine dashboard → Paymasters → Balance

# 2. Verifica whitelist:
#    Engine dashboard → Rules → Contract Whitelist
#    Debe incluir: 0xef740bf23acae26f6492b10de645d6b98dc8eaf3
```

### Error: "Smart account creation failed"

```bash
# 1. Verifica backend wallet tiene ETH:
#    Engine dashboard → Backend Wallets → Balance

# 2. Get testnet ETH:
#    https://faucet.unichain.org
```

---

## Comandos Útiles

```bash
# Backend
npm run dev              # Desarrollo
npm run build           # Build para producción
npm start               # Producción

# Mobile
npm run ios             # iOS simulator
npm run android         # Android emulator
npx expo start -c       # Clear cache
eas build --platform ios # Build para device

# Railway
railway logs            # Ver logs
railway status          # Status del deploy
railway variables       # Ver variables de entorno
```

---

## Next Steps

Ahora que tienes el setup básico funcionando:

1. **OpenAI API** - Mejora parsing de voz en español
2. **Meta Ray-Ban** - Conecta glasses reales
3. **TestFlight** - Deploy a dispositivos físicos
4. **App Store** - Submit para revisión

---

## Links Rápidos

- [Engine Dashboard](https://thirdweb.com/dashboard/engine)
- [Railway Dashboard](https://railway.app/dashboard)
- [Unichain Faucet](https://faucet.unichain.org)
- [Unichain Explorer](https://sepolia.uniscan.xyz)

---

## Checklist de Setup

- [ ] Engine instance creada
- [ ] Backend wallet configurado
- [ ] Gas sponsorship activo (0.05 ETH depositado)
- [ ] Contract whitelist configurado
- [ ] Variables de entorno del backend configuradas
- [ ] Backend corriendo localmente
- [ ] Mobile app corriendo en simulador
- [ ] Test swap exitoso
- [ ] Backend desplegado a Railway
- [ ] Mobile app apuntando a backend en producción

---

**¿Necesitas ayuda?** Pregúntame cualquier cosa!
