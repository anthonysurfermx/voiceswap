/**
 * WalletConnectManager.swift
 * VoiceSwap - Reown AppKit integration for wallet connections
 *
 * Uses Reown (WalletConnect) AppKit to connect real wallets
 * like MetaMask, Rainbow, Coinbase Wallet, etc.
 */

import Foundation
import Combine
import SwiftUI

// MARK: - Wallet Connection State

public enum WalletConnectionState: Equatable {
    case disconnected
    case connecting
    case connected(address: String)
    case error(String)
}

// MARK: - Connected Wallet Info

public struct ConnectedWallet: Codable {
    public let address: String
    public let chainId: Int
    public let walletName: String?
    public let connectedAt: Date

    public init(address: String, chainId: Int, walletName: String? = nil) {
        self.address = address
        self.chainId = chainId
        self.walletName = walletName
        self.connectedAt = Date()
    }
}

// MARK: - Unichain Configuration

public struct UnichainConfig {
    public static let mainnet = ChainInfo(
        chainId: 130,
        name: "Unichain",
        rpcUrl: "https://mainnet.unichain.org",
        symbol: "ETH",
        explorer: "https://uniscan.xyz"
    )

    public static let sepolia = ChainInfo(
        chainId: 1301,
        name: "Unichain Sepolia",
        rpcUrl: "https://sepolia.unichain.org",
        symbol: "ETH",
        explorer: "https://sepolia.uniscan.xyz"
    )
}

public struct ChainInfo {
    public let chainId: Int
    public let name: String
    public let rpcUrl: String
    public let symbol: String
    public let explorer: String
}

// MARK: - WalletConnect Manager

@MainActor
public class WalletConnectManager: ObservableObject {

    // MARK: - Singleton
    public static let shared = WalletConnectManager()

    // MARK: - Published Properties
    @Published public private(set) var connectionState: WalletConnectionState = .disconnected
    @Published public private(set) var connectedWallet: ConnectedWallet?
    @Published public var showWalletModal: Bool = false

    // MARK: - Properties
    public let projectId = "0c9c91473cd01a94bd2417f6fb1d5c9d"
    private let userDefaults = UserDefaults.standard
    private let walletKey = "voiceswap_connected_wallet"

    // Current chain config
    public var currentChain: ChainInfo {
        #if DEBUG
        return UnichainConfig.mainnet // Use mainnet for testing with real USDC
        #else
        return UnichainConfig.mainnet
        #endif
    }

    // MARK: - Initialization

    private init() {
        // Restore previous session if exists
        restorePreviousSession()
    }

    // MARK: - Public Methods

    /// Open wallet connection modal
    public func connect() {
        connectionState = .connecting
        showWalletModal = true
    }

    /// Connect with a specific wallet address (manual input)
    public func connectWithAddress(_ address: String) {
        guard isValidEthereumAddress(address) else {
            connectionState = .error("Invalid Ethereum address")
            return
        }

        let wallet = ConnectedWallet(
            address: address,
            chainId: currentChain.chainId,
            walletName: "Manual"
        )

        connectedWallet = wallet
        connectionState = .connected(address: address)
        saveWalletSession(wallet)
        showWalletModal = false

        print("[WalletConnect] Connected to wallet: \(address)")
    }

    /// Handle successful connection from AppKit
    public func handleConnection(address: String, chainId: Int, walletName: String?) {
        let wallet = ConnectedWallet(
            address: address,
            chainId: chainId,
            walletName: walletName
        )

        connectedWallet = wallet
        connectionState = .connected(address: address)
        saveWalletSession(wallet)
        showWalletModal = false

        print("[WalletConnect] Connected via AppKit: \(address) on chain \(chainId)")
    }

    /// Disconnect current wallet
    public func disconnect() {
        connectedWallet = nil
        connectionState = .disconnected
        clearWalletSession()
        print("[WalletConnect] Disconnected")
    }

    /// Get current connected address
    public var currentAddress: String? {
        connectedWallet?.address
    }

    /// Check if wallet is connected
    public var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    /// Get short address display
    public var shortAddress: String? {
        guard let address = currentAddress else { return nil }
        return "\(address.prefix(6))...\(address.suffix(4))"
    }

    // MARK: - Transaction Methods

    /// Sign and send a transaction (requires AppKit integration)
    public func sendTransaction(
        to: String,
        value: String,
        data: String? = nil
    ) async throws -> String {
        guard let _ = connectedWallet else {
            throw WalletError.notConnected
        }

        // This will be handled by AppKit when fully integrated
        // For now, we prepare the transaction and the backend executes it
        print("[WalletConnect] Transaction request - to: \(to), value: \(value)")

        throw WalletError.requiresWalletApproval
    }

    /// Sign a message
    public func signMessage(_ message: String) async throws -> String {
        guard let _ = connectedWallet else {
            throw WalletError.notConnected
        }

        // This will be handled by AppKit when fully integrated
        throw WalletError.requiresWalletApproval
    }

    // MARK: - Private Methods

    private func isValidEthereumAddress(_ address: String) -> Bool {
        let pattern = "^0x[a-fA-F0-9]{40}$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(location: 0, length: address.utf16.count)
        return regex?.firstMatch(in: address, range: range) != nil
    }

    private func saveWalletSession(_ wallet: ConnectedWallet) {
        if let encoded = try? JSONEncoder().encode(wallet) {
            userDefaults.set(encoded, forKey: walletKey)
        }
    }

    private func restorePreviousSession() {
        guard let data = userDefaults.data(forKey: walletKey),
              let wallet = try? JSONDecoder().decode(ConnectedWallet.self, from: data) else {
            return
        }

        connectedWallet = wallet
        connectionState = .connected(address: wallet.address)
        print("[WalletConnect] Restored previous session: \(wallet.address)")
    }

    private func clearWalletSession() {
        userDefaults.removeObject(forKey: walletKey)
    }
}

// MARK: - Wallet Errors

public enum WalletError: Error, LocalizedError {
    case notConnected
    case invalidAddress
    case requiresWalletApproval
    case transactionFailed(String)
    case networkError(Error)
    case userRejected

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "No wallet connected"
        case .invalidAddress:
            return "Invalid Ethereum address"
        case .requiresWalletApproval:
            return "Transaction requires approval in your wallet app"
        case .transactionFailed(let message):
            return "Transaction failed: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .userRejected:
            return "Transaction rejected by user"
        }
    }
}

// MARK: - Wallet Connect View (Modal)

public struct WalletConnectView: View {
    @ObservedObject var walletManager: WalletConnectManager
    @State private var manualAddress: String = ""
    @State private var showManualInput: Bool = false
    @Environment(\.dismiss) private var dismiss

    public init(walletManager: WalletConnectManager) {
        self.walletManager = walletManager
    }

    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.1, green: 0.1, blue: 0.18).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        VStack(spacing: 12) {
                            Image(systemName: "wallet.pass.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)

                            Text("Connect Wallet")
                                .font(.title)
                                .fontWeight(.bold)
                                .foregroundColor(.white)

                            Text("Connect your wallet to make voice payments on Unichain")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        .padding(.top, 30)

                        // Wallet Options
                        VStack(spacing: 12) {
                            // MetaMask
                            walletButton(
                                name: "MetaMask",
                                icon: "m.circle.fill",
                                color: .orange
                            ) {
                                openWalletApp("metamask")
                            }

                            // Rainbow
                            walletButton(
                                name: "Rainbow",
                                icon: "rainbow",
                                color: .purple
                            ) {
                                openWalletApp("rainbow")
                            }

                            // Coinbase Wallet
                            walletButton(
                                name: "Coinbase Wallet",
                                icon: "c.circle.fill",
                                color: .blue
                            ) {
                                openWalletApp("cbwallet")
                            }

                            // Trust Wallet
                            walletButton(
                                name: "Trust Wallet",
                                icon: "shield.fill",
                                color: .cyan
                            ) {
                                openWalletApp("trust")
                            }
                        }
                        .padding(.horizontal)

                        // Divider
                        HStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                            Text("or")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(height: 1)
                        }
                        .padding(.horizontal, 40)

                        // Manual Input
                        VStack(spacing: 12) {
                            Button(action: { showManualInput.toggle() }) {
                                HStack {
                                    Image(systemName: "keyboard")
                                    Text("Enter address manually")
                                }
                                .font(.subheadline)
                                .foregroundColor(.blue)
                            }

                            if showManualInput {
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("0x...", text: $manualAddress)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .autocapitalization(.none)
                                        .disableAutocorrection(true)

                                    Button(action: {
                                        walletManager.connectWithAddress(manualAddress)
                                    }) {
                                        Text("Connect")
                                            .frame(maxWidth: .infinity)
                                            .padding()
                                            .background(manualAddress.count == 42 ? Color.blue : Color.gray)
                                            .foregroundColor(.white)
                                            .cornerRadius(12)
                                    }
                                    .disabled(manualAddress.count != 42)
                                }
                                .padding(.horizontal)
                                .transition(.opacity)
                            }
                        }

                        Spacer(minLength: 40)

                        // Network info
                        VStack(spacing: 8) {
                            HStack {
                                Circle()
                                    .fill(Color.pink)
                                    .frame(width: 8, height: 8)
                                Text("Unichain Mainnet")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }

                            HStack {
                                Image(systemName: "lock.shield.fill")
                                    .foregroundColor(.green)
                                Text("Your keys never leave your device")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        walletManager.showWalletModal = false
                    }
                    .foregroundColor(.blue)
                }
            }
        }
    }

    private func walletButton(name: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                    .frame(width: 40)

                Text(name)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
            )
        }
    }

    private func openWalletApp(_ wallet: String) {
        // Generate WalletConnect URI and open wallet app
        let wcUri = generateWCUri()

        var urlString: String?
        switch wallet {
        case "metamask":
            urlString = "metamask://wc?uri=\(wcUri)"
        case "rainbow":
            urlString = "rainbow://wc?uri=\(wcUri)"
        case "cbwallet":
            urlString = "cbwallet://wc?uri=\(wcUri)"
        case "trust":
            urlString = "trust://wc?uri=\(wcUri)"
        default:
            break
        }

        if let urlString = urlString,
           let url = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "") {
            UIApplication.shared.open(url)
        }
    }

    private func generateWCUri() -> String {
        // Generate a basic WalletConnect v2 URI
        // In production, this would come from the actual WalletConnect session
        let topic = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        return "wc:\(topic)@2?relay-protocol=irn&symKey=\(randomHex(32))"
    }

    private func randomHex(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
