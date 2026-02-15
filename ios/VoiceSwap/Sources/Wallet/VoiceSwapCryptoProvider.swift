/**
 * VoiceSwapCryptoProvider.swift
 * Minimal CryptoProvider implementation for Reown AppKit
 * Uses native iOS crypto - no external dependencies required
 */

import Foundation
import CryptoKit
import WalletConnectSigner

/// Minimal CryptoProvider for Reown AppKit
/// Note: recoverPubKey is not implemented as it's not needed for basic wallet connections
struct VoiceSwapCryptoProvider: CryptoProvider {

    public func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        // This method is used for signature verification which we don't need for basic connections
        // The wallet app handles all signing operations
        // Return empty data - AppKit will work without this for wallet connections
        throw CryptoProviderError.notImplemented
    }

    public func keccak256(_ data: Data) -> Data {
        // Keccak-256 implementation using SHA3
        return keccak256Hash(data)
    }
}

enum CryptoProviderError: Error {
    case notImplemented
}

// MARK: - Keccak-256 Implementation

/// Pure Swift Keccak-256 implementation
/// Based on the Keccak specification (FIPS 202)
func keccak256Hash(_ data: Data) -> Data {
    var state = [UInt64](repeating: 0, count: 25)
    let rateInBytes = 136 // (1600 - 256 * 2) / 8
    var inputData = [UInt8](data)

    // Padding
    inputData.append(0x01)
    while inputData.count % rateInBytes != rateInBytes - 1 {
        inputData.append(0x00)
    }
    inputData.append(0x80)

    // Absorb
    for chunkStart in stride(from: 0, to: inputData.count, by: rateInBytes) {
        for i in 0..<(rateInBytes / 8) {
            let offset = chunkStart + i * 8
            if offset + 8 <= inputData.count {
                var value: UInt64 = 0
                for j in 0..<8 {
                    value |= UInt64(inputData[offset + j]) << (j * 8)
                }
                state[i] ^= value
            }
        }
        keccakF1600(&state)
    }

    // Squeeze (we only need 32 bytes for Keccak-256)
    var output = [UInt8]()
    for i in 0..<4 {
        var value = state[i]
        for _ in 0..<8 {
            output.append(UInt8(value & 0xFF))
            value >>= 8
        }
    }

    return Data(output)
}

/// Keccak-f[1600] permutation
private func keccakF1600(_ state: inout [UInt64]) {
    let roundConstants: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
    ]

    let rotationOffsets: [[Int]] = [
        [0, 36, 3, 41, 18],
        [1, 44, 10, 45, 2],
        [62, 6, 43, 15, 61],
        [28, 55, 25, 21, 56],
        [27, 20, 39, 8, 14]
    ]

    for round in 0..<24 {
        // θ (theta)
        var c = [UInt64](repeating: 0, count: 5)
        for x in 0..<5 {
            c[x] = state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20]
        }
        var d = [UInt64](repeating: 0, count: 5)
        for x in 0..<5 {
            d[x] = c[(x + 4) % 5] ^ rotateLeft(c[(x + 1) % 5], by: 1)
        }
        for x in 0..<5 {
            for y in 0..<5 {
                state[x + y * 5] ^= d[x]
            }
        }

        // ρ (rho) and π (pi)
        var b = [UInt64](repeating: 0, count: 25)
        for x in 0..<5 {
            for y in 0..<5 {
                let index = x + y * 5
                b[y + ((2 * x + 3 * y) % 5) * 5] = rotateLeft(state[index], by: rotationOffsets[x][y])
            }
        }

        // χ (chi)
        for x in 0..<5 {
            for y in 0..<5 {
                let index = x + y * 5
                state[index] = b[index] ^ ((~b[(x + 1) % 5 + y * 5]) & b[(x + 2) % 5 + y * 5])
            }
        }

        // ι (iota)
        state[0] ^= roundConstants[round]
    }
}

private func rotateLeft(_ value: UInt64, by amount: Int) -> UInt64 {
    return (value << amount) | (value >> (64 - amount))
}
