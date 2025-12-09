/**
 * Example: AI Agent consuming the x402 Swap Executor
 *
 * This demonstrates how an AI agent can use the swap service
 * by paying micropayments via the x402 protocol.
 *
 * Network: Unichain (Uniswap V4)
 */

// In production, you'd use the x402 client library
// import { wrapFetch } from '@x402/fetch';

const SWAP_EXECUTOR_URL = 'http://localhost:4021';

// Example tokens on Unichain Sepolia
const TOKENS = {
  WETH: '0x4200000000000000000000000000000000000006',
  USDC: '0x31d0220469e10c4E71834a79b1f276d740d3768F',
};

/**
 * Simulates an AI agent that wants to swap tokens
 */
async function aiAgentSwapExample() {
  console.log('🤖 AI Agent: I need to swap 0.01 WETH for USDC on Unichain\n');

  // Step 1: Check service health (free)
  console.log('📡 Checking swap service health...');
  const healthResponse = await fetch(`${SWAP_EXECUTOR_URL}/health`);
  const health = await healthResponse.json();
  console.log('   Status:', health.status);
  console.log('   Network:', health.network);
  console.log('   Protocol:', health.protocol);
  console.log('');

  // Step 2: Get available tokens (free)
  console.log('📋 Fetching available tokens...');
  const tokensResponse = await fetch(`${SWAP_EXECUTOR_URL}/tokens`);
  const tokens = await tokensResponse.json();
  console.log('   Available tokens:', Object.keys(tokens.data).join(', '));
  console.log('');

  // Step 3: Get a quote (requires x402 payment of $0.001)
  console.log('💰 Getting swap quote...');
  console.log('   (This would trigger a 402 Payment Required without x402 payment)');

  const quoteUrl = new URL(`${SWAP_EXECUTOR_URL}/quote`);
  quoteUrl.searchParams.set('tokenIn', TOKENS.WETH);
  quoteUrl.searchParams.set('tokenOut', TOKENS.USDC);
  quoteUrl.searchParams.set('amountIn', '0.01');

  try {
    const quoteResponse = await fetch(quoteUrl.toString());

    if (quoteResponse.status === 402) {
      // This is what happens without x402 payment
      console.log('\n   ⚠️  Received 402 Payment Required');
      console.log('   The agent would now pay via x402 and retry...');

      // In reality, the x402 client library handles this automatically:
      // const x402Fetch = wrapFetch(fetch, { privateKey: AGENT_WALLET_KEY });
      // const quote = await x402Fetch(quoteUrl);

      // Simulate what the response would look like after payment
      console.log('\n   ✅ After x402 payment, quote received:');
      console.log('   {');
      console.log('     tokenIn: { symbol: "WETH", amount: "0.01" },');
      console.log('     tokenOut: { symbol: "USDC", amount: "~35.02" },');
      console.log('     priceImpact: "0.1%",');
      console.log('     estimatedGas: "150000"');
      console.log('   }');
    } else {
      const quote = await quoteResponse.json();
      console.log('   Quote received:', JSON.stringify(quote, null, 2));
    }
  } catch (error) {
    console.log('   Error getting quote:', error);
  }

  console.log('');
  console.log('🎯 Next steps for the AI agent:');
  console.log('   1. Call POST /route to get the calldata ($0.005)');
  console.log('   2. Call POST /execute to swap on-chain ($0.02)');
  console.log('   3. Call GET /status/:txHash to confirm ($0.001)');
  console.log('');
  console.log('💡 Total cost for a complete swap: ~$0.027 in x402 micropayments');
}

/**
 * Example of the full swap flow with mock data
 */
async function fullSwapFlowExample() {
  console.log('\n' + '='.repeat(60));
  console.log('Full Swap Flow Example (with mock responses)\n');

  // Simulated responses after x402 payments

  const mockQuote = {
    success: true,
    data: {
      tokenIn: {
        address: TOKENS.WETH,
        symbol: 'WETH',
        decimals: 18,
        amount: '0.01',
        amountRaw: '10000000000000000',
      },
      tokenOut: {
        address: TOKENS.USDC,
        symbol: 'USDC',
        decimals: 6,
        amount: '35.02',
        amountRaw: '35020000',
      },
      priceImpact: '0.1000',
      route: [TOKENS.WETH, TOKENS.USDC],
      estimatedGas: '150000',
      timestamp: Date.now(),
    },
  };

  const mockRoute = {
    success: true,
    data: {
      ...mockQuote.data,
      calldata: '0x3593564c...',
      to: '0xef740bf23acae26f6492b10de645d6b98dc8eaf3', // Universal Router on Unichain
      value: '0',
      slippageTolerance: 0.5,
      deadline: Math.floor(Date.now() / 1000) + 1800,
    },
  };

  const mockExecute = {
    success: true,
    data: {
      status: 'submitted',
      txHash: '0x' + 'a'.repeat(64),
    },
  };

  const mockStatus = {
    success: true,
    data: {
      status: 'confirmed',
      txHash: '0x' + 'a'.repeat(64),
      blockNumber: 12345678,
      confirmations: 3,
      gasUsed: '145000',
    },
  };

  console.log('Step 1: GET /quote ($0.001)');
  console.log(JSON.stringify(mockQuote, null, 2));
  console.log('');

  console.log('Step 2: POST /route ($0.005)');
  console.log(JSON.stringify(mockRoute, null, 2));
  console.log('');

  console.log('Step 3: POST /execute ($0.02)');
  console.log(JSON.stringify(mockExecute, null, 2));
  console.log('');

  console.log('Step 4: GET /status/:txHash ($0.001)');
  console.log(JSON.stringify(mockStatus, null, 2));
  console.log('');

  console.log('✅ Swap completed successfully on Unichain!');
  console.log('   Total x402 cost: $0.027');
  console.log('   Tokens received: 35.02 USDC');
}

// Run examples
console.log('╔═══════════════════════════════════════════════════════════════╗');
console.log('║     x402 Swap Executor - Client Example (Unichain V4)        ║');
console.log('╚═══════════════════════════════════════════════════════════════╝\n');

aiAgentSwapExample()
  .then(() => fullSwapFlowExample())
  .catch(console.error);
