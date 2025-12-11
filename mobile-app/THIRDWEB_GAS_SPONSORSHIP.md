# Thirdweb Gas Sponsorship Setup

## Configuración completa de Gas Sponsorship para VoiceSwap

### ¿Qué es Gas Sponsorship?

Gas Sponsorship permite que tu app pague los gas fees de los usuarios, eliminando la necesidad de que tengan ETH en su wallet. Esto es crítico para VoiceSwap porque:

1. **UX sin fricción**: Usuarios pueden swapear sin ETH
2. **Voice-first**: No interrupciones para obtener gas
3. **Onboarding fácil**: Solo necesitan tokens para swapear, no ETH para gas

---

## Paso 1: Activar Gas Sponsorship en Thirdweb

### 1.1 Ir al Dashboard

1. Ve a [thirdweb.com/dashboard](https://thirdweb.com/dashboard)
2. Inicia sesión con tu cuenta
3. Navega a **Account Abstraction** en el menú izquierdo

### 1.2 Crear Paymaster

1. Click en **Create Paymaster**
2. Selecciona **Unichain Sepolia** (Chain ID: 1301)
3. Nombra tu paymaster: `voiceswap-sepolia-paymaster`
4. Click **Create**

### 1.3 Depositar Fondos

El paymaster necesita fondos para patrocinar gas:

1. En la página del paymaster, click **Deposit**
2. Mínimo recomendado: **0.05 ETH** (~ 50-100 transacciones en Sepolia)
3. Para mainnet: Calcular basado en volumen esperado

**Estimación de costos:**
- Unichain Sepolia: ~0.0005 ETH por swap
- Unichain Mainnet: ~0.001-0.002 ETH por swap
- 100 usuarios × 5 swaps = 500 swaps
- Costo estimado en mainnet: ~0.5-1 ETH

---

## Paso 2: Configurar Sponsorship Rules

### 2.1 Global Spend Limit

1. En tu paymaster, ve a **Settings → Spend Limits**
2. Configura **Monthly Spend Limit**:
   - Development: **$50/mes**
   - Production: **$500-1000/mes** (ajustar según demanda)
3. Configura **Per-Transaction Limit**:
   - Máximo: **$5** por transacción

Esto previene abuse y controla costos.

### 2.2 Contract Whitelist

Solo patrocina transacciones hacia contratos específicos:

1. Ve a **Rules → Contract Whitelist**
2. Click **Add Contract**
3. Añade estos contratos de Uniswap V4:

```
# Universal Router (Uniswap V4)
0xef740bf23acae26f6492b10de645d6b98dc8eaf3

# Pool Manager (opcional, para swaps directos)
0x1f98400000000000000000000000000000000004
```

4. **Importante**: NO patrocines contratos arbitrarios (riesgo de abuse)

### 2.3 Chain Restriction

1. Ve a **Rules → Allowed Chains**
2. Selecciona solo:
   - ✅ Unichain Sepolia (1301) - testnet
   - ✅ Unichain (130) - mainnet cuando lances

### 2.4 Rate Limiting (Opcional pero recomendado)

Previene abuse de un mismo usuario:

1. Ve a **Rules → Rate Limits**
2. Configura:
   - **Max transactions per address**: 10 por hora
   - **Max transactions per IP**: 20 por hora (si detectas IPs)
   - **Cooldown period**: 60 segundos entre transacciones

---

## Paso 3: Integrar en tu App

### 3.1 Verificar Configuración

El archivo `src/config/thirdweb.ts` ya está configurado:

```typescript
export const accountAbstractionConfig = {
  chain: currentChain, // Unichain Sepolia
  sponsorGas: true,    // ✅ Habilitado
};
```

### 3.2 Testear Gas Sponsorship

```typescript
import { thirdwebWalletService } from './services/ThirdwebWalletService';

// Conectar wallet
await thirdwebWalletService.connect('metamask');

// Verificar que gas sponsorship está habilitado
const gasInfo = thirdwebWalletService.getGasSponsorship();
console.log(gasInfo);
// Output: { enabled: true, message: "Gas fees are sponsored..." }

// Hacer un swap - el gas será sponsoreado automáticamente
await swapService.executeSwap({
  tokenIn: 'USDC',
  tokenOut: 'WETH',
  amountIn: '10',
  recipient: walletAddress,
});
// ✅ Usuario no necesita ETH para gas!
```

---

## Paso 4: Monitorear Uso

### 4.1 Dashboard de Thirdweb

1. Ve a tu paymaster en el dashboard
2. Revisa **Analytics**:
   - Total transactions sponsored
   - Total gas spent
   - Average cost per transaction
   - Top users by gas consumption

### 4.2 Set Alerts

1. Ve a **Settings → Notifications**
2. Configura alertas:
   - ⚠️ **80% of monthly limit reached**
   - 🚨 **90% of monthly limit reached**
   - 📧 **Weekly usage report**

Esto te permite anticipar cuando necesitas recargar fondos o ajustar límites.

---

## Paso 5: Optimizar Costos

### 5.1 Progressive Onboarding

Sponsorea más gas para nuevos usuarios, menos para usuarios establecidos:

```typescript
// En tu app logic:
const userSwapCount = getUserSwapCount(userAddress);

if (userSwapCount < 5) {
  // Primeros 5 swaps: 100% sponsoreados
  return accountAbstractionConfig;
} else if (userSwapCount < 20) {
  // Swaps 6-20: sponsorear solo hasta $1 de gas
  return {
    ...accountAbstractionConfig,
    maxGasSponsorship: parseUnits('1', 'ether')
  };
} else {
  // Usuarios power: pagan su propio gas
  return { chain: currentChain, sponsorGas: false };
}
```

### 5.2 Incentivizar Acciones Específicas

Sponsorea más gas para acciones que quieres promover:

```typescript
// Ejemplo: Sponsorear swaps grandes
if (swapAmountUSD > 100) {
  // Swaps >$100: Gas 100% sponsoreado
  return { chain: currentChain, sponsorGas: true };
} else {
  // Swaps pequeños: Usuario paga gas
  return { chain: currentChain, sponsorGas: false };
}
```

---

## Checklist de Producción

### Pre-Launch
- [ ] Paymaster creado en Unichain Sepolia (testnet)
- [ ] Fondos depositados (0.05 ETH mínimo)
- [ ] Contract whitelist configurado
- [ ] Rate limits configurados
- [ ] Monthly spend limit configurado ($50 para empezar)
- [ ] Alerts configuradas
- [ ] Testing end-to-end con wallet real

### Launch (Mainnet)
- [ ] Crear nuevo paymaster en Unichain Mainnet (Chain ID: 130)
- [ ] Depositar fondos en mainnet (1-2 ETH para empezar)
- [ ] Actualizar contract whitelist con direcciones de mainnet
- [ ] Ajustar spend limits según proyección de usuarios
- [ ] Monitorear uso primeros días

### Post-Launch
- [ ] Revisar analytics semanalmente
- [ ] Ajustar spend limits según uso real
- [ ] Implementar progressive onboarding
- [ ] Refinar rate limits basado en abuse patterns
- [ ] Considerar incentivos para acciones específicas

---

## Troubleshooting

### Error: "Gas sponsorship failed"

**Causas posibles:**
1. Paymaster sin fondos
2. Transacción excede spend limit
3. Contrato no está en whitelist
4. Rate limit excedido

**Solución:**
```typescript
try {
  await executeSwap(params);
} catch (error) {
  if (error.message.includes('sponsor')) {
    // Fallback: pedir al usuario que pague gas
    await executeSwap({ ...params, sponsorGas: false });
  }
}
```

### Error: "Monthly limit reached"

**Solución:**
1. Ve al dashboard de Thirdweb
2. Aumenta el monthly limit
3. O espera al próximo ciclo de billing
4. O implementa progressive onboarding

### Costos más altos de lo esperado

**Diagnóstico:**
1. Revisa **Top Users** en analytics
2. Busca patrones de abuse
3. Ajusta rate limits

**Solución:**
- Implementar rate limiting más estricto
- Blacklist de direcciones que abusan
- Progressive onboarding

---

## Recursos

- [Thirdweb Gas Sponsorship Docs](https://portal.thirdweb.com/connect/account-abstraction/guides/react)
- [Sponsorship Rules](https://portal.thirdweb.com/connect/account-abstraction/sponsorship-rules)
- [Unichain Block Explorer](https://sepolia.uniscan.xyz)

---

## Código Promocional x402 Hackathon

Recuerda usar tu código para 2 meses gratis:

```
x402-GROWTH-2M
```

Aplicar en: [thirdweb.com/dashboard/settings/billing](https://thirdweb.com/dashboard/settings/billing)

¡Esto te da gas sponsorship gratis durante el hackathon! 🎉
