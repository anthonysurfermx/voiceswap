# 🤖 Thirdweb AI Chat - Análisis para VoiceSwap

**Fecha:** 2025-12-11
**Documentación:** https://portal.thirdweb.com/ai/chat

---

## 🎯 Descubrimiento Importante

Thirdweb tiene una **AI Chat API** que podría **reemplazar nuestra necesidad de OpenAI** para el parsing de comandos de voz.

### Lo que hace Thirdweb AI Chat:

1. **Natural Language → Blockchain Transactions**
   - Input: `"Send 0.01 ETH to vitalik.eth"`
   - Output: Transaction preparada con calldata

2. **Swap Intent Recognition**
   - Input: `"Swap 0.1 ETH to USDC"`
   - Output: Swap transaction lista para ejecutar

3. **OpenAI-Compatible API**
   - Mismo formato que OpenAI Chat Completions
   - Podemos usar sin cambiar mucho código

4. **Wallet Context Aware**
   - Acepta `from` address y `chain_ids`
   - Prepara transacciones para la wallet correcta

---

## 🔄 Comparación: Thirdweb AI vs OpenAI

### Opción 1: OpenAI (Plan Original)
```
Usuario dice: "Cambia 10 dólares de ETH a USDC"
         ↓
    OpenAI GPT-4
         ↓
Parse intent: {
  action: "swap",
  tokenIn: "ETH",
  tokenOut: "USDC",
  amountUSD: 10
}
         ↓
Nuestro código convierte a transaction
         ↓
Ejecuta swap
```

**Pros:**
- ✅ Flexible - podemos agregar features custom
- ✅ Multilenguaje (español perfecto)
- ✅ Ya sabemos cómo usarlo

**Contras:**
- ❌ Costo adicional (API de OpenAI)
- ❌ Tenemos que hacer el parsing manual
- ❌ Tenemos que construir transaction nosotros

---

### Opción 2: Thirdweb AI Chat (Nuevo)
```
Usuario dice: "Swap 0.1 ETH to USDC"
         ↓
  Thirdweb AI Chat
         ↓
Transaction preparada: {
  type: "sign_transaction",
  chain_id: 143,
  to: "0xef740bf...",
  data: "0x3593564c...",
  value: "0x..."
}
         ↓
Ejecutamos directamente
```

**Pros:**
- ✅ Todo integrado - no necesitamos OpenAI
- ✅ Transaction prep automática
- ✅ Ya incluido en Thirdweb (sin costo extra?)
- ✅ Optimizado para blockchain

**Contras:**
- ⚠️ Probablemente solo inglés (necesitamos verificar)
- ⚠️ Menos flexible que OpenAI custom
- ⚠️ No sabemos si soporta comandos en español

---

## 🎤 Arquitectura: Voice → AI → Swap

### Flow Completo con Thirdweb AI

```
Meta Ray-Ban Glasses
         ↓ (audio)
Meta Wearables SDK
         ↓ (audio stream)
Speech-to-Text (Apple o Meta)
         ↓ (text)
"Swap 0.1 ETH to USDC"
         ↓
Thirdweb AI Chat API
         ↓
{
  actions: [{
    type: "sign_transaction",
    chain_id: 143,
    to: "0xef740bf23acae26f6492b10de645d6b98dc8eaf3",
    data: "0x3593564c000...",
    value: "0x0",
    description: "Swap 0.1 ETH for USDC on Monad"
  }]
}
         ↓
Backend /execute endpoint
         ↓
Thirdweb Engine (gas sponsored)
         ↓
Swap ejecutado ✅
```

---

## 📋 API Format de Thirdweb AI Chat

### Request
```typescript
POST https://ai.thirdweb.com/v1/chat/completions

Headers:
  Authorization: Bearer {THIRDWEB_SECRET_KEY}
  Content-Type: application/json

Body:
{
  "model": "thirdweb-ai",
  "messages": [
    {
      "role": "user",
      "content": "Swap 0.1 ETH to USDC"
    }
  ],
  "from": "0x2749A654FeE5CEc3a8644a27E7498693d0132759",
  "chain_ids": [143], // Monad
  "tools": ["contract_call", "swap"]
}
```

### Response
```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": "I've prepared a swap of 0.1 ETH to USDC on Monad. Would you like to proceed?",
      "actions": [{
        "type": "sign_transaction",
        "chain_id": 143,
        "to": "0xef740bf23acae26f6492b10de645d6b98dc8eaf3",
        "data": "0x3593564c...",
        "value": "0x016345785d8a0000",
        "description": "Swap 0.1 ETH for ~305.23 USDC"
      }]
    }
  }]
}
```

---

## 🚀 Plan de Implementación

### Opción A: Usar Thirdweb AI (Recomendado)

**Ventajas:**
- Todo integrado en una sola plataforma
- No necesitamos OpenAI separado
- Transaction prep automática
- Menos código que mantener

**Desventajas:**
- Probablemente solo inglés
- Menos control sobre parsing

**Implementación:**

1. **Backend - Crear `/voice-command` endpoint**
```typescript
// src/routes/voice.ts
import { createThirdwebClient } from 'thirdweb';

const client = createThirdwebClient({
  secretKey: process.env.THIRDWEB_SECRET_KEY!,
});

router.post('/voice-command', async (req, res) => {
  const { transcript, userAddress } = req.body;

  // Llamar Thirdweb AI Chat
  const response = await fetch('https://ai.thirdweb.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${process.env.THIRDWEB_SECRET_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'thirdweb-ai',
      messages: [{ role: 'user', content: transcript }],
      from: userAddress,
      chain_ids: [143], // Monad
      tools: ['swap'],
    }),
  });

  const aiResponse = await response.json();
  const action = aiResponse.choices[0].message.actions[0];

  // Ejecutar con Thirdweb Engine
  const result = await executeSwapViaEngine({
    userAddress,
    calldata: action.data,
    value: action.value,
  });

  res.json({
    success: true,
    description: action.description,
    queueId: result.queueId,
  });
});
```

2. **Mobile App - Integrar con Meta SDK**
```typescript
// mobile-app/src/services/VoiceCommandService.ts
class VoiceCommandService {
  async processVoiceCommand(audioData: ArrayBuffer): Promise<SwapResult> {
    // 1. Speech to text (Apple o Meta)
    const transcript = await this.speechToText(audioData);

    // 2. Send to backend
    const response = await fetch(`${BACKEND_URL}/voice-command`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        transcript,
        userAddress: thirdwebWalletService.getAddress(),
      }),
    });

    const result = await response.json();

    // 3. Monitor transaction
    return txMonitor.waitForConfirmation(result.queueId);
  }
}
```

**Tiempo estimado:** 2-3 horas

---

### Opción B: Usar OpenAI Custom

**Ventajas:**
- Soporte para español perfecto
- Control total sobre parsing
- Podemos agregar features custom

**Desventajas:**
- Costo adicional de OpenAI
- Más código que mantener
- Tenemos que hacer transaction prep manual

**Implementación:**

```typescript
// src/services/openai.ts
import OpenAI from 'openai';

const openai = new OpenAI({
  apiKey: process.env.OPENAI_API_KEY,
});

export async function parseVoiceCommand(transcript: string) {
  const completion = await openai.chat.completions.create({
    model: 'gpt-4',
    messages: [
      {
        role: 'system',
        content: `Eres un asistente que parsea comandos de voz para swaps de crypto.
        Extrae: action, tokenIn, tokenOut, amount.
        Responde en JSON.`
      },
      {
        role: 'user',
        content: transcript
      }
    ],
  });

  return JSON.parse(completion.choices[0].message.content);
}
```

**Tiempo estimado:** 3-4 horas (más parsing manual)

---

## 🤔 Decisión: ¿Cuál usar?

### Test Crítico: ¿Thirdweb AI soporta español?

**Necesitamos verificar:**
```bash
curl https://ai.thirdweb.com/v1/chat/completions \
  -H "Authorization: Bearer $THIRDWEB_SECRET_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "thirdweb-ai",
    "messages": [{
      "role": "user",
      "content": "Cambia 0.1 ETH a USDC"
    }],
    "from": "0x2749A654FeE5CEc3a8644a27E7498693d0132759",
    "chain_ids": [143],
    "tools": ["swap"]
  }'
```

### Si soporta español → Usar Thirdweb AI ✅
**Razón:** Todo integrado, menos costo, menos código

### Si NO soporta español → Usar OpenAI 🤷
**Razón:** Tu app es en español, necesitamos soporte perfecto

---

## 📊 Comparación de Costos

### Opción 1: Thirdweb AI
```
- Thirdweb x402 Growth Plan: FREE (2 meses)
- Thirdweb AI Chat: ??? (probablemente incluido)
- Total: ~$0/mes
```

### Opción 2: OpenAI
```
- OpenAI API (GPT-4):
  - $0.03 por 1K tokens input
  - $0.06 por 1K tokens output
  - ~100 tokens por comando = $0.009 por comando
  - 1000 comandos/mes = $9/mes
- Total: ~$9-15/mes
```

**Ganador en costo:** Thirdweb AI (si está incluido)

---

## 🎯 Recomendación Final

### Plan Híbrido (MEJOR)

1. **Fase 1 (MVP):** Usar Thirdweb AI en inglés
   - Comandos simples: "Swap 0.1 ETH to USDC"
   - Rápido de implementar
   - Sin costo extra

2. **Fase 2 (Post-MVP):** Agregar OpenAI para español
   - Traducir comando español → inglés
   - Enviar a Thirdweb AI
   - Best of both worlds

**Ejemplo:**
```typescript
async function processVoiceCommand(transcript: string) {
  let command = transcript;

  // Si está en español, traducir a inglés
  if (detectLanguage(transcript) === 'es') {
    command = await translateToEnglish(transcript); // GPT-4
  }

  // Usar Thirdweb AI para execution
  const action = await thirdwebAI.chat(command);

  return action;
}
```

**Ventajas:**
- ✅ Soporta español
- ✅ Transaction prep automática
- ✅ Costo bajo (solo traducción, no parsing completo)

---

## 📁 Archivos a Crear

### Backend
```
src/routes/voice.ts           - Voice command endpoint
src/services/thirdwebAI.ts    - Thirdweb AI client
src/services/translation.ts   - Español → Inglés (si necesario)
```

### Mobile App
```
mobile-app/src/services/VoiceCommandService.ts
mobile-app/src/services/SpeechToText.ts
mobile-app/src/screens/VoiceCommandScreen.tsx
```

---

## ✅ Next Steps

1. **Test Thirdweb AI con comando en español** (5 min)
2. **Verificar si está incluido en x402 Growth Plan** (revisar pricing)
3. **Implementar endpoint `/voice-command`** (2 horas)
4. **Integrar con Meta SDK cuando esté listo** (más adelante)

---

**Decisión pendiente:** ¿Thirdweb AI soporta español? Necesitamos testear.
