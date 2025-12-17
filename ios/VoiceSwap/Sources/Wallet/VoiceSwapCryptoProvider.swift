import Foundation
import Web3
import CryptoSwift
import WalletConnectSigner

/// Minimal crypto provider required by Reown AppKit 2.x.
/// Uses Web3 + CryptoSwift to expose keccak hashing and ECDSA recovery.
struct VoiceSwapCryptoProvider: CryptoProvider {
    func recoverPubKey(signature: EthereumSignature, message: Data) throws -> Data {
        let messageBytes = [UInt8](message)
        let publicKey = try EthereumPublicKey(
            message: messageBytes,
            v: EthereumQuantity(quantity: BigUInt(signature.v)),
            r: EthereumQuantity(signature.r),
            s: EthereumQuantity(signature.s)
        )
        return Data(publicKey.rawPublicKey)
    }

    func keccak256(_ data: Data) -> Data {
        let digest = SHA3(variant: .keccak256)
        let hash = digest.calculate(for: [UInt8](data))
        return Data(hash)
    }
}
