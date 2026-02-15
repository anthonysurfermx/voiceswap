/**
 * VoiceSwapWallet.swift
 * Local Ethereum wallet with Keychain storage and EIP-155 transaction signing.
 * Signs transactions on-device for zero-friction voice payments on Monad.
 */

import Foundation
import Security
import secp256k1

// MARK: - VoiceSwapWallet

@MainActor
class VoiceSwapWallet: ObservableObject {
    static let shared = VoiceSwapWallet()

    @Published private(set) var address: String = ""
    @Published private(set) var isCreated: Bool = false

    private var privateKeyData: Data?

    // Monad chain config
    private let chainId: UInt64 = 143
    private let rpcURL = URL(string: "https://rpc.monad.xyz")!

    // Nonce tracking for multi-step transactions
    private var lastUsedNonce: UInt64?
    private var lastNonceTime: Date?

    // Keychain identifiers
    private let keychainService = "com.voiceswap.wallet"
    private let keychainAccount = "private_key"

    // iCloud Keychain sync
    @Published var isBackedUpToiCloud: Bool = false

    private init() {
        isBackedUpToiCloud = UserDefaults.standard.bool(forKey: "wallet_icloud_backup")
    }

    // MARK: - Wallet Creation

    func create() throws {
        guard !isCreated else {
            NSLog("[VoiceSwapWallet] Wallet already exists, skipping create")
            return
        }

        // Generate 32 random bytes for private key
        var keyBytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, 32, &keyBytes)
        guard status == errSecSuccess else {
            throw WalletError.keyGenerationFailed
        }

        let keyData = Data(keyBytes)

        // Derive public key and address
        let derivedAddress = try deriveAddress(from: keyData)

        // Save to Keychain
        try saveToKeychain(keyData)

        // Set state
        privateKeyData = keyData
        address = derivedAddress
        isCreated = true

        NSLog("[VoiceSwapWallet] Created wallet: %@", address)
    }

    // MARK: - Wallet Restore

    func restore() {
        guard let keyData = loadFromKeychain() else {
            NSLog("[VoiceSwapWallet] No wallet found in Keychain")
            return
        }

        do {
            let derivedAddress = try deriveAddress(from: keyData)
            privateKeyData = keyData
            address = derivedAddress
            isCreated = true
            NSLog("[VoiceSwapWallet] Restored wallet: %@", address)
        } catch {
            NSLog("[VoiceSwapWallet] Failed to restore wallet: %@", error.localizedDescription)
        }
    }

    // MARK: - Export Private Key (for backup)

    func exportPrivateKey() -> String? {
        guard let keyData = privateKeyData else { return nil }
        return "0x" + keyData.hexString
    }

    // MARK: - Import from Private Key

    func importFromPrivateKey(_ hexKey: String) throws {
        let cleaned = hexKey.hasPrefix("0x") ? String(hexKey.dropFirst(2)) : hexKey
        guard cleaned.count == 64 else {
            throw WalletError.rpcError("Invalid private key length")
        }
        let keyData = Data(hex: cleaned)
        guard keyData.count == 32 else {
            throw WalletError.rpcError("Invalid private key data")
        }

        let derivedAddress = try deriveAddress(from: keyData)
        try saveToKeychain(keyData)

        privateKeyData = keyData
        address = derivedAddress
        isCreated = true

        NSLog("[VoiceSwapWallet] Imported wallet: %@", address)
    }

    // MARK: - Wallet Deletion

    func deleteWallet() {
        // Use kSecAttrSynchronizableAny to delete BOTH local and iCloud entries
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        SecItemDelete(query as CFDictionary)

        // Clear iCloud backup state
        isBackedUpToiCloud = false
        UserDefaults.standard.removeObject(forKey: "wallet_icloud_backup")

        privateKeyData = nil
        address = ""
        isCreated = false
        resetNonceTracking()
        NSLog("[VoiceSwapWallet] Wallet deleted (local + iCloud)")
    }

    // MARK: - Send Transaction

    func sendTransaction(to: String, value: String, data: String?) async throws -> String {
        guard let keyData = privateKeyData else {
            throw WalletError.notCreated
        }

        // Get nonce
        let nonce = try await getNonce()

        // Get gas price (returned as Data for big integer support)
        let gasPrice = try await getGasPrice()

        // Parse value as big integer (hex string like "0x..." from backend)
        let valueBytes = parseHexToData(value)

        // Parse data
        let dataBytes: Data
        if let txData = data, txData.hasPrefix("0x") && txData.count > 2 {
            dataBytes = Data(hex: String(txData.dropFirst(2)))
        } else {
            dataBytes = Data()
        }

        // Parse to address
        let toAddress = to.hasPrefix("0x") ? String(to.dropFirst(2)) : to
        let toBytes = Data(hex: toAddress)

        // Estimate gas via RPC (with fallback)
        let gasLimit = try await estimateGas(
            from: address, to: to, value: value, data: data
        )

        NSLog("[VoiceSwapWallet] TX: to=%@, value=%@, gasLimit=%llu, nonce=%llu", to, value, gasLimit, nonce)

        // Build and sign transaction
        let signedTx = try signTransaction(
            nonce: nonce,
            gasPrice: gasPrice,
            gasLimit: gasLimit,
            to: toBytes,
            value: valueBytes,
            data: dataBytes,
            privateKey: keyData
        )

        // Broadcast
        let txHash = try await broadcastTransaction(signedTx)
        NSLog("[VoiceSwapWallet] Transaction sent: %@", txHash)
        return txHash
    }

    // MARK: - EIP-155 Transaction Signing

    private func signTransaction(
        nonce: UInt64,
        gasPrice: Data,
        gasLimit: UInt64,
        to: Data,
        value: Data,
        data: Data,
        privateKey: Data
    ) throws -> Data {
        // 1. RLP encode for signing: [nonce, gasPrice, gasLimit, to, value, data, chainId, 0, 0]
        let signingList: [RLPItem] = [
            .integer(nonce),
            .bigInt(gasPrice),
            .integer(gasLimit),
            .bytes(to),
            .bigInt(value),
            .bytes(data),
            .integer(chainId),
            .integer(0),
            .integer(0)
        ]
        let encodedForSigning = rlpEncodeList(signingList)

        // 2. Hash with Keccak-256
        let txHash = keccak256Hash(encodedForSigning)

        // 3. Sign with secp256k1 (recoverable ECDSA)
        let (r, s, recoveryId) = try signECDSARecoverable(hash: txHash, privateKey: privateKey)

        // 4. EIP-155: v = chainId * 2 + 35 + recoveryId
        let v = chainId * 2 + 35 + recoveryId

        // 5. Strip leading zeros from r and s (required by Ethereum RLP — non-canonical integers rejected)
        let rStripped = stripLeadingZeros(r)
        let sStripped = stripLeadingZeros(s)

        // 6. RLP encode final transaction: [nonce, gasPrice, gasLimit, to, value, data, v, r, s]
        let txList: [RLPItem] = [
            .integer(nonce),
            .bigInt(gasPrice),
            .integer(gasLimit),
            .bytes(to),
            .bigInt(value),
            .bytes(data),
            .integer(v),
            .bigInt(rStripped),
            .bigInt(sStripped)
        ]
        return rlpEncodeList(txList)
    }

    // MARK: - RPC Calls

    private func getNonce() async throws -> UInt64 {
        let result = try await rpcCall(method: "eth_getTransactionCount", params: [address, "pending"])
        guard let hexStr = result as? String else { throw WalletError.rpcError("Invalid nonce response") }
        let rpcNonce = parseHexUInt64(hexStr)

        // For multi-step transactions: if we recently used a nonce (within 30s),
        // use max(rpcNonce, lastUsedNonce + 1) to avoid nonce collision
        if let lastNonce = lastUsedNonce,
           let lastTime = lastNonceTime,
           Date().timeIntervalSince(lastTime) < 30 {
            let localNonce = lastNonce + 1
            let nonce = max(rpcNonce, localNonce)
            lastUsedNonce = nonce
            lastNonceTime = Date()
            return nonce
        }

        lastUsedNonce = rpcNonce
        lastNonceTime = Date()
        return rpcNonce
    }

    /// Reset local nonce tracking (call after multi-step completes or fails)
    func resetNonceTracking() {
        lastUsedNonce = nil
        lastNonceTime = nil
    }

    private func getGasPrice() async throws -> Data {
        let result = try await rpcCall(method: "eth_gasPrice", params: [])
        guard let hexStr = result as? String else { throw WalletError.rpcError("Invalid gas price response") }
        // Parse as big integer and add 20% buffer for faster inclusion
        let priceBytes = parseHexToData(hexStr)
        return addPercentage(priceBytes, percent: 20)
    }

    private func estimateGas(from: String, to: String, value: String, data: String?) async throws -> UInt64 {
        var txObj: [String: String] = [
            "from": from,
            "to": to,
            "value": value
        ]
        if let data = data, data.count > 2 {
            txObj["data"] = data
        }
        do {
            let result = try await rpcCall(method: "eth_estimateGas", params: [txObj])
            guard let hexStr = result as? String else {
                throw WalletError.rpcError("Invalid gas estimate response")
            }
            let estimate = parseHexUInt64(hexStr)
            // Add 30% buffer for safety
            return estimate + estimate * 3 / 10
        } catch {
            // Fallback to safe defaults if estimation fails
            NSLog("[VoiceSwapWallet] Gas estimation failed: %@, using defaults", error.localizedDescription)
            if let txData = data, txData != "0x" && txData.count > 2 {
                return 500_000
            } else {
                return 21_000
            }
        }
    }

    private func broadcastTransaction(_ signedTx: Data) async throws -> String {
        let hexTx = "0x" + signedTx.hexString
        let result = try await rpcCall(method: "eth_sendRawTransaction", params: [hexTx])
        guard let txHash = result as? String else {
            throw WalletError.rpcError("Invalid broadcast response")
        }
        return txHash
    }

    private func rpcCall(method: String, params: [Any]) async throws -> Any {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1
        ]

        var request = URLRequest(url: rpcURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            let code = error["code"] as? Int ?? 0
            NSLog("[VoiceSwapWallet] RPC error in %@: code=%d, message=%@", method, code, message)
            throw WalletError.rpcError(message)
        }

        guard let result = json["result"] else {
            throw WalletError.rpcError("No result in RPC response")
        }
        return result
    }

    // MARK: - Address Derivation

    private func deriveAddress(from privateKeyData: Data) throws -> String {
        // Use Signing key to get uncompressed public key (65 bytes: 04 || x || y)
        let signingKey = try secp256k1.Signing.PrivateKey(
            dataRepresentation: privateKeyData,
            format: .uncompressed
        )
        let uncompressedPubKey = signingKey.publicKey.dataRepresentation

        // Drop the 0x04 prefix, hash the remaining 64 bytes
        let pubKeyBody = Data(uncompressedPubKey.dropFirst())
        let hash = keccak256Hash(pubKeyBody)

        // Take last 20 bytes as address
        let addressBytes = hash.suffix(20)
        return "0x" + addressBytes.hexString
    }

    // MARK: - Keychain

    /// Enable iCloud Keychain backup — re-saves with kSecAttrSynchronizable
    func enableiCloudBackup() throws {
        guard let keyData = privateKeyData else {
            throw WalletError.notCreated
        }

        // Delete local-only entry
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Re-save with iCloud sync enabled
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: true
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WalletError.keychainError(status)
        }

        isBackedUpToiCloud = true
        UserDefaults.standard.set(true, forKey: "wallet_icloud_backup")
        NSLog("[VoiceSwapWallet] iCloud Keychain backup enabled")
    }

    private func saveToKeychain(_ data: Data) throws {
        // Delete existing entry first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw WalletError.keychainError(status)
        }
    }

    private func loadFromKeychain() -> Data? {
        // Try iCloud-synced first
        let icloudQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        var status = SecItemCopyMatching(icloudQuery as CFDictionary, &result)

        if status == errSecSuccess, let data = result as? Data {
            isBackedUpToiCloud = true
            return data
        }

        // Fallback to local-only
        let localQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        result = nil
        status = SecItemCopyMatching(localQuery as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return data
    }

    // MARK: - Errors

    enum WalletError: LocalizedError {
        case keyGenerationFailed
        case notCreated
        case rpcError(String)
        case keychainError(OSStatus)

        var errorDescription: String? {
            switch self {
            case .keyGenerationFailed: return "Failed to generate secure key"
            case .notCreated: return "VoiceSwap Wallet not created"
            case .rpcError(let msg): return "RPC error: \(msg)"
            case .keychainError(let status): return "Keychain error: \(status)"
            }
        }
    }
}

// MARK: - Low-Level ECDSA Signing

/// Signs a 32-byte hash using secp256k1 recoverable ECDSA.
/// Uses C bindings directly to avoid SHA256 double-hashing from the high-level API.
private func signECDSARecoverable(hash: Data, privateKey: Data) throws -> (r: Data, s: Data, recoveryId: UInt64) {
    let context = secp256k1.Context.rawRepresentation

    var rsig = secp256k1_ecdsa_recoverable_signature()
    let hashBytes = Array(hash)
    let keyBytes = Array(privateKey)

    guard secp256k1_ecdsa_sign_recoverable(context, &rsig, hashBytes, keyBytes, nil, nil) == 1 else {
        throw VoiceSwapWallet.WalletError.rpcError("secp256k1 signing failed")
    }

    var compact = [UInt8](repeating: 0, count: 64)
    var recid: Int32 = 0
    secp256k1_ecdsa_recoverable_signature_serialize_compact(context, &compact, &recid, &rsig)

    let r = Data(compact[0..<32])
    let s = Data(compact[32..<64])
    return (r, s, UInt64(recid))
}

// MARK: - RLP Encoding

private enum RLPItem {
    case bytes(Data)
    case integer(UInt64)
    case bigInt(Data) // Big-endian unsigned integer bytes (no leading zeros)
}

private func rlpEncodeList(_ items: [RLPItem]) -> Data {
    var payload = Data()
    for item in items {
        switch item {
        case .bytes(let data):
            payload.append(rlpEncodeBytes(data))
        case .integer(let value):
            payload.append(rlpEncodeBytes(encodeUInt64(value)))
        case .bigInt(let data):
            // Big integers are RLP-encoded as their minimal big-endian representation
            let stripped = stripLeadingZeros(data)
            payload.append(rlpEncodeBytes(stripped))
        }
    }
    return rlpEncodeLength(payload.count, offset: 0xc0) + payload
}

private func rlpEncodeBytes(_ data: Data) -> Data {
    if data.count == 1 && data[0] < 0x80 {
        return data
    }
    return rlpEncodeLength(data.count, offset: 0x80) + data
}

private func rlpEncodeLength(_ length: Int, offset: Int) -> Data {
    if length < 56 {
        return Data([UInt8(offset + length)])
    }
    let lengthBytes = encodeUInt64(UInt64(length))
    return Data([UInt8(offset + 55 + lengthBytes.count)]) + lengthBytes
}

private func encodeUInt64(_ value: UInt64) -> Data {
    if value == 0 { return Data() }
    var bytes = [UInt8]()
    var v = value
    while v > 0 {
        bytes.insert(UInt8(v & 0xFF), at: 0)
        v >>= 8
    }
    return Data(bytes)
}

// MARK: - Big Integer Helpers

/// Strip leading zero bytes from Data (for RLP integer encoding)
private func stripLeadingZeros(_ data: Data) -> Data {
    guard let firstNonZero = data.firstIndex(where: { $0 != 0 }) else {
        return Data() // All zeros → empty (represents 0)
    }
    return Data(data[firstNonZero...])
}

/// Parse a hex string ("0x..." or decimal) into big-endian Data bytes
private func parseHexToData(_ str: String) -> Data {
    if str.hasPrefix("0x") {
        let hex = String(str.dropFirst(2))
        if hex.isEmpty || hex == "0" { return Data() }
        return stripLeadingZeros(Data(hex: hex))
    }
    // Decimal string → convert to hex via UInt64 if small enough
    if let val = UInt64(str) {
        return encodeUInt64(val)
    }
    return Data()
}

/// Add a percentage to a big-endian integer (e.g., add 20% gas price buffer)
private func addPercentage(_ data: Data, percent: UInt) -> Data {
    // Convert Data to UInt64 if it fits (gas prices fit in UInt64)
    if data.count <= 8 {
        var value: UInt64 = 0
        for byte in data {
            value = value << 8 | UInt64(byte)
        }
        let added = value + value * UInt64(percent) / 100
        return encodeUInt64(added)
    }
    // For values > UInt64, just return as-is (unlikely for gas price)
    return data
}

// MARK: - Hex Helpers

private func parseHexUInt64(_ hex: String) -> UInt64 {
    let cleaned = hex.hasPrefix("0x") ? String(hex.dropFirst(2)) : hex
    return UInt64(cleaned, radix: 16) ?? 0
}

extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }

    init(hex: String) {
        var data = Data()
        var hex = hex
        // Remove 0x prefix if present
        if hex.hasPrefix("0x") {
            hex = String(hex.dropFirst(2))
        }
        // Pad odd-length strings
        if hex.count % 2 != 0 {
            hex = "0" + hex
        }
        var index = hex.startIndex
        while index < hex.endIndex {
            let nextIndex = hex.index(index, offsetBy: 2)
            if let byte = UInt8(hex[index..<nextIndex], radix: 16) {
                data.append(byte)
            }
            index = nextIndex
        }
        self = data
    }
}
