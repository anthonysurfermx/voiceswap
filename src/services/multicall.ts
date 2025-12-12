/**
 * Multicall3 Service
 *
 * Batch multiple RPC calls into a single request for performance
 */

import { ethers } from 'ethers';

// Multicall3 is deployed at the same address on all chains
const MULTICALL3_ADDRESS = '0xcA11bde05977b3631167028862bE2a173976CA11';

const MULTICALL3_ABI = [
  'function aggregate3(tuple(address target, bool allowFailure, bytes callData)[] calls) returns (tuple(bool success, bytes returnData)[] returnData)',
];

export interface Call {
  target: string;
  allowFailure: boolean;
  callData: string;
}

export interface Result {
  success: boolean;
  returnData: string;
}

/**
 * Execute multiple calls in a single transaction
 */
export async function multicall(
  provider: ethers.providers.Provider,
  calls: Call[]
): Promise<Result[]> {
  const multicall = new ethers.Contract(
    MULTICALL3_ADDRESS,
    MULTICALL3_ABI,
    provider
  );

  const results = await multicall.callStatic.aggregate3(calls);

  return results.map((result: any) => ({
    success: result.success,
    returnData: result.returnData,
  }));
}

/**
 * Helper: Encode a contract call
 */
export function encodeCall(
  contractInterface: ethers.utils.Interface,
  functionName: string,
  params: any[]
): string {
  return contractInterface.encodeFunctionData(functionName, params);
}

/**
 * Helper: Decode a result
 */
export function decodeResult(
  contractInterface: ethers.utils.Interface,
  functionName: string,
  data: string
): any {
  return contractInterface.decodeFunctionResult(functionName, data);
}
