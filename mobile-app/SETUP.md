# VoiceSwap iOS Setup Guide

## 🚀 Quick Start (3 Semanas a Producción)

### Semana 1: Setup Core Infrastructure

#### 1. Instalar Dependencias

```bash
cd mobile-app
npm install
```

#### 2. Configurar Variables de Entorno

Copia `.env.example` a `.env` y configura:

```env
# Thirdweb (YA CONFIGURADO)
EXPO_PUBLIC_THIRDWEB_CLIENT_ID=***REMOVED_THIRDWEB_CLIENT_ID***
THIRDWEB_SECRET_KEY=***REMOVED_THIRDWEB_SECRET***

# OpenAI API (NECESITAS OBTENER)
EXPO_PUBLIC_OPENAI_API_KEY=sk-proj-...

# Backend URL (actualizar después de deploy)
EXPO_PUBLIC_BACKEND_URL=http://localhost:4021

# Network
EXPO_PUBLIC_CHAIN_ID=1301
EXPO_PUBLIC_NETWORK=monad-sepolia
```

#### 3. Configurar Thirdweb Gas Sponsorship

1. Ve a [thirdweb.com/dashboard](https://thirdweb.com/dashboard)
2. Navega a **Account Abstraction → Paymasters**
3. Activa Gas Sponsorship para Monad Sepolia (Chain ID: 1301)
4. Configura reglas de sponsorship:
   - **Global spend limit**: $100/mes (ajusta según necesidad)
   - **Contract whitelist**: Añade dirección del Universal Router de Uniswap V3
   - **Chain**: Monad Sepolia (1301)

**Dirección del Universal Router:**
```
0xef740bf23acae26f6492b10de645d6b98dc8eaf3
```

#### 4. Meta Ray-Ban SDK Setup

##### Opción A: Development con Bluetooth Estándar (Recomendado para empezar)
No requiere configuración adicional. La app usará Bluetooth estándar del sistema.

##### Opción B: Meta Wearables DAT SDK (Producción)

1. **Crear App en Meta Developer Console**
   - Ve a [developers.facebook.com](https://developers.facebook.com)
   - Crea una nueva app
   - Habilita "Meta Wearables" en productos
   - Obtén tu App ID

2. **Actualizar app.json**
   ```json
   {
     "ios": {
       "infoPlist": {
         "MWDAT": {
           "MetaAppID": "TU_META_APP_ID_AQUI"
         }
       }
     }
   }
   ```

3. **Crear Native Module** (Ver `IOS_NATIVE_MODULE.md`)

---

### Semana 2: Deploy & Integration

#### 5. Deploy Backend

##### Opción A: Railway (Recomendado)

```bash
cd ..  # Volver a raíz del proyecto
railway login
railway init
railway up
```

Configura variables de entorno en Railway:
```
PAYMENT_RECEIVER_ADDRESS=0xTuDireccionAqui
NETWORK=monad-sepolia
MONAD_SEPOLIA_RPC_URL=https://sepolia.monad.org
RELAYER_PRIVATE_KEY=tu_private_key_para_ejecutar_swaps
```

##### Opción B: Render.com

1. Conecta tu repo de GitHub
2. Selecciona "Web Service"
3. Build command: `npm install && npm run build`
4. Start command: `npm start`
5. Añade variables de entorno

Actualiza `.env` con la URL de producción:
```env
EXPO_PUBLIC_BACKEND_URL=https://tu-app.railway.app
```

#### 6. Configurar Monad Wallet

1. Crea wallet en MetaMask
2. Añade red Monad Sepolia:
   - **RPC URL**: https://sepolia.monad.org
   - **Chain ID**: 1301
   - **Symbol**: ETH
   - **Explorer**: https://sepolia.uniscan.xyz

3. Obtén fondos de testnet:
   - ETH: [Monad Sepolia Faucet](https://faucet.monad.org)
   - USDC de prueba: Usar bridge o mint contract

4. Configura relayer wallet para backend con ETH para gas

#### 7. Testing

```bash
# Terminal 1: Backend local
cd ../
npm run dev

# Terminal 2: Mobile app
cd mobile-app
npm run ios
```

**Test checklist:**
- [ ] Wallet connection (MetaMask/Coinbase)
- [ ] Get quote (voice: "swap 10 USDC to WETH")
- [ ] Execute swap (voice: "yes" o "confirm")
- [ ] Check transaction status
- [ ] Meta Glasses connection (Bluetooth)
- [ ] Voice recognition en español

---

### Semana 3: Polish & Launch

#### 8. Implementar Biometría

Ya está configurado en `app.json` (FaceID/TouchID permissions).
Verifica que funciona al conectar wallet.

#### 9. App Store Preparation

1. **Apple Developer Account**
   - Costo: $99/año
   - Registra en [developer.apple.com](https://developer.apple.com)

2. **Signing & Certificates**
   ```bash
   cd mobile-app
   npx expo build:ios --type archive
   ```

3. **App Store Assets**
   - Screenshots (6.5", 5.5")
   - App icon (1024x1024)
   - Privacy policy
   - Description

4. **Submit via EAS Build**
   ```bash
   eas build --platform ios
   eas submit --platform ios
   ```

---

## 🔧 Development Commands

```bash
# Iniciar en modo desarrollo
npm run ios

# Limpiar cache
expo start -c

# Build para testing
eas build --platform ios --profile preview

# Build para producción
eas build --platform ios --profile production
```

---

## 🐛 Troubleshooting

### Error: "Expo Go not supported"
**Solución**: Usa development build, no Expo Go.
```bash
npx expo run:ios
```

### Error: "Thirdweb client not found"
**Solución**: Verifica `.env` y reinicia metro bundler.

### Error: "MetaWearablesDAT module not found"
**Solución**: Esto es normal si no has creado el native module. La app usará modo Bluetooth estándar.

### Error: "402 Payment Required"
**Solución**:
1. Verifica que el backend esté corriendo
2. Verifica que Gas Tank tenga fondos (o configura x402 en backend)

---

## 📚 Documentación Adicional

- [Thirdweb React Native Docs](https://portal.thirdweb.com/react-native)
- [Meta Wearables DAT SDK](https://github.com/facebook/meta-wearables-dat-ios)
- [Uniswap V3 Docs](https://docs.uniswap.org/contracts/v3/overview)
- [x402 Protocol](https://x402.org)

---

## ✅ Checklist de Producción

### Backend
- [ ] Desplegado en producción
- [ ] Variables de entorno configuradas
- [ ] Wallet relayer con fondos
- [ ] x402 payment configurado
- [ ] SSL/HTTPS habilitado

### Frontend
- [ ] Thirdweb configurado con Gas Sponsorship
- [ ] OpenAI API key configurada
- [ ] Backend URL actualizada a producción
- [ ] Meta SDK integrado (o Bluetooth fallback)
- [ ] Permisos iOS configurados
- [ ] Testing en dispositivo físico

### Meta Ray-Ban
- [ ] App creada en Meta Developer Console
- [ ] App ID configurado en app.json
- [ ] Native module creado (o Bluetooth fallback activo)
- [ ] Permisos Bluetooth configurados

### App Store
- [ ] Apple Developer account activo
- [ ] Signing certificates configurados
- [ ] Screenshots y assets listos
- [ ] Privacy policy creada
- [ ] App submitted for review

---

## 🚨 Prioridades Críticas (Para cumplir 3 semanas)

### Día 1-3
1. ✅ Thirdweb setup
2. Deploy backend
3. OpenAI API integration

### Día 4-7
4. Meta SDK (o confirmar Bluetooth fallback)
5. End-to-end testing con wallet real
6. Fix bugs críticos

### Día 8-14
7. UI polish
8. Testing en dispositivo real con Meta Ray-Ban
9. Performance optimization

### Día 15-21
10. Apple Developer setup
11. App Store assets
12. Submit for review
13. Buffer para revisiones/fixes

---

## 💡 Tips

1. **Usa Bluetooth fallback** si Meta SDK toma mucho tiempo
2. **Gas Sponsorship** de Thirdweb elimina fricción de UX
3. **Testing temprano** en dispositivo físico (no simulador)
4. **OpenAI API** es crítico para parsing de voz en español
5. **Backend en Railway** es el deploy más rápido

¿Dudas? Pregunta en Discord de x402 Hackathon o Thirdweb.
