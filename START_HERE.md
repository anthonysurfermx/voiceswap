# 🚀 START HERE - Siguiente Paso

## ¡El backend está listo! Aquí está lo que debes hacer ahora:

---

## Paso 1: Probar el Backend Localmente (5 minutos)

Abre tu terminal y ejecuta:

```bash
cd /Users/mrrobot/Documents/GitHub/voiceswap
npm install
npm run dev
```

Deberías ver:
```
Server running on http://localhost:4021
Network: unichain
Chain ID: 130
```

### Verificar que funciona:

Abre **otra terminal** y ejecuta:

```bash
curl http://localhost:4021/health
```

Si ves esto, ¡todo funciona! ✅:
```json
{
  "status": "ok",
  "features": {
    "accountAbstraction": true,
    "gasSponsorship": true,
    "thirdwebEngine": true
  }
}
```

---

## Paso 2: Configurar Gas Sponsorship (15 minutos)

**IMPORTANTE:** Sin esto, los swaps no funcionarán.

### En Thirdweb Dashboard:

1. Ve a: https://thirdweb.com/dashboard
2. Inicia sesión con tus credenciales
3. Settings → Sponsorship (o "Gas Sponsorship")
4. Enable para **Chain ID: 130** (Unichain Mainnet)
5. En "Sponsored Contracts", añade:
   ```
   0xef740bf23acae26f6492b10de645d6b98dc8eaf3
   ```
6. Deposita **0.05 ETH** al paymaster

---

## Paso 3: Fondear Wallets (15 minutos)

Necesitas fondear 2 wallets diferentes para 2 propósitos:

### 3A. Backend Wallet - Unichain (para swaps)

**Address:** `0x2749A654FeE5CEc3a8644a27E7498693d0132759`
**Network:** Unichain Mainnet
**Propósito:** Ejecutar swaps en Uniswap V4

**Cómo obtener ETH:**
1. Ve a: https://bridge.unichain.org
2. Conecta tu wallet
3. Bridge al menos **0.1 ETH** a Unichain Mainnet

**Verificar:**
```bash
https://unichain.org/explorer/address/0x2749A654FeE5CEc3a8644a27E7498693d0132759
```

### 3B. Payment Receiver - Arbitrum (para x402 pagos)

**Address:** `0x2749A654FeE5CEc3a8644a27E7498693d0132759`
**Network:** Arbitrum Sepolia (testnet) / Arbitrum (mainnet)
**Propósito:** Recibir pagos x402 por uso de API

**Cómo obtener ETH (testnet):**
1. Usa faucet: https://faucet.quicknode.com/arbitrum/sepolia
2. O bridge desde Sepolia: https://bridge.arbitrum.io/?destinationChain=arbitrum-sepolia

**Mínimo:** 0.01 ETH para gas

**Verificar:**
```bash
https://sepolia.arbiscan.io/address/0x2749A654FeE5CEc3a8644a27E7498693d0132759
```

---

## Paso 4: Probar un Swap (Opcional, 5 minutos)

Con el backend corriendo (`npm run dev`), prueba un swap real:

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

Si funciona, verás:
```json
{
  "success": true,
  "data": {
    "status": "queued",
    "queueId": "...",
    "message": "Transaction queued with gas sponsorship"
  }
}
```

---

## Paso 5: Deploy a Producción (30 minutos)

### Railway (Recomendado)

```bash
# Instalar CLI
npm install -g @railway/cli

# Login
railway login

# Inicializar proyecto
railway init
# Nombre: voiceswap-backend

# Configurar variables de entorno
railway variables set NETWORK=unichain
railway variables set THIRDWEB_SECRET_KEY=lR5bfHCESjbO5-SWqGZXpCRAgCbY9SabnjVtuJbZRWHwVWOGTKrXY0VgE_AJvKbNPUimAZF8jmTvcBrfkjNwHg
railway variables set THIRDWEB_CLIENT_ID=d180849f99bd996b77591d55b65373d0
railway variables set BACKEND_WALLET_ADDRESS=0x2749A654FeE5CEc3a8644a27E7498693d0132759
railway variables set THIRDWEB_API_URL=https://api.thirdweb.com/v1
railway variables set UNIVERSAL_ROUTER_ADDRESS=0xef740bf23acae26f6492b10de645d6b98dc8eaf3
railway variables set PORT=4021

# Deploy
railway up

# Obtener URL
railway domain
```

Guarda la URL (ej: `voiceswap-backend.railway.app`)

---

## Paso 6: Configurar Mobile App (10 minutos)

```bash
cd /Users/mrrobot/Documents/GitHub/voiceswap/mobile-app

# Instalar dependencias
npm install

# Editar .env
nano .env
```

Actualiza esta línea con tu URL de Railway:
```env
EXPO_PUBLIC_BACKEND_URL=https://voiceswap-backend.railway.app
```

### Probar en iOS Simulator:

```bash
npm run ios
```

Deberías ver la app arrancar en el simulador de iOS.

---

## 📋 Checklist Completo

Marca cada paso cuando lo completes:

### Backend Local
- [ ] `npm install` completado sin errores
- [ ] `npm run dev` arranca el servidor
- [ ] `curl /health` responde OK
- [ ] No hay errores en la consola

### Thirdweb Configuration
- [ ] Gas sponsorship habilitado para Chain ID 130
- [ ] Contract whitelist incluye `0xef740bf...`
- [ ] Paymaster tiene al menos 0.05 ETH

### Backend Wallet
- [ ] Wallet tiene al menos 0.1 ETH en Unichain Mainnet
- [ ] Balance verificado en explorer

### Production Deployment
- [ ] Railway CLI instalado
- [ ] Proyecto creado en Railway
- [ ] Variables de entorno configuradas
- [ ] Deploy exitoso
- [ ] URL del backend guardada

### Mobile App
- [ ] Dependencias instaladas
- [ ] `.env` actualizado con backend URL
- [ ] App arranca en simulador iOS

---

## 🆘 ¿Problemas?

### El servidor no arranca
**Verifica:**
- Node.js instalado: `node --version` (necesitas v18+)
- Todas las dependencias: `rm -rf node_modules && npm install`

### Health check falla
**Verifica:**
- `.env` tiene todas las variables
- `THIRDWEB_SECRET_KEY` es correcto

### Gas sponsorship no funciona
**Verifica:**
- Thirdweb dashboard → Sponsorship → Chain ID 130 enabled
- Contract `0xef740bf...` en whitelist
- Paymaster tiene fondos

### Wallet sin ETH
**Opciones:**
- Bridge desde Ethereum: https://bridge.unichain.org
- Pedir a un amigo con ETH en Unichain
- Comprar en exchange con soporte Unichain

---

## 📚 Más Documentación

Si necesitas más info, revisa estos archivos:

- **[BACKEND_READY.md](BACKEND_READY.md)** - Status completo del backend
- **[TEST_BACKEND.md](TEST_BACKEND.md)** - Guía de testing detallada
- **[QUICKSTART.md](QUICKSTART.md)** - Quick start en 15 min
- **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - Resumen técnico

---

## ✨ ¡Siguiente Milestone!

Después de completar estos pasos, tu backend estará en producción y listo para recibir requests de la mobile app.

El siguiente gran paso será integrar **OpenAI** para voice parsing en español y **Meta Ray-Ban SDK** para los lentes.

¡Pero primero, completa estos pasos! 🚀

---

**Tiempo estimado total:** 1-2 horas
**Dificultad:** Fácil
**¿Bloqueado?** Pregúntame lo que necesites 😊
