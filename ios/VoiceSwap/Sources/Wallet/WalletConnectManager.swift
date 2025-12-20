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
import UIKit
import ReownAppKit
import WalletConnectNetworking
import WalletConnectRelay

// MARK: - Socket Factory (Required by WalletConnect SDK)

struct VoiceSwapSocketFactory: WebSocketFactory {
    func create(with url: URL) -> WebSocketConnecting {
        return NativeWebSocket(url: url)
    }
}

// Native WebSocket implementation using URLSessionWebSocketTask
class NativeWebSocket: WebSocketConnecting {
    private var task: URLSessionWebSocketTask?
    private let url: URL
    var isConnected: Bool = false
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onText: ((String) -> Void)?
    var request: URLRequest

    init(url: URL) {
        self.url = url
        self.request = URLRequest(url: url)
    }

    func connect() {
        let session = URLSession(configuration: .default)
        task = session.webSocketTask(with: request)
        task?.resume()
        isConnected = true
        onConnect?()
        receiveMessage()
    }

    func disconnect() {
        task?.cancel(with: .normalClosure, reason: nil)
        isConnected = false
        onDisconnect?(nil)
    }

    func write(string: String, completion: (() -> Void)?) {
        task?.send(.string(string)) { _ in
            completion?()
        }
    }

    private func receiveMessage() {
        task?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.onText?(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.onText?(text)
                    }
                @unknown default:
                    break
                }
                self?.receiveMessage()
            case .failure(let error):
                self?.isConnected = false
                self?.onDisconnect?(error)
            }
        }
    }
}

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
    public static let mainnetChainId = 130
    public static let sepoliaChainId = 1301

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
    private var isAppKitConfigured = false
    private var cancellables = Set<AnyCancellable>()
    private var currentSessionTopic: String?
    private let cryptoProvider = VoiceSwapCryptoProvider()

    // Current chain config
    public var currentChain: ChainInfo {
        return UnichainConfig.mainnet
    }

    // MARK: - Initialization

    private init() {
        // Delay AppKit configuration to avoid slowing down app startup
        // Will configure lazily when needed
    }

    /// Call this to initialize WalletConnect (call from app startup or when needed)
    public func initialize() {
        guard !isAppKitConfigured else { return }

        // Defer initialization to avoid blocking app startup
        // AppKit.configure makes network calls that can take 30+ seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.configureAppKit()
            self?.restorePreviousSession()
            self?.setupSessionObserver()
        }
    }

    // MARK: - AppKit Configuration

    private func configureAppKit() {
        do {
            let redirect = try AppMetadata.Redirect(
                native: "voiceswap://wc",
                universal: "https://voiceswap.cc/wc",
                linkMode: true
            )

            let metadata = AppMetadata(
                name: "VoiceSwap",
                description: "Voice-activated crypto payments",
                url: "https://voiceswap.cc",
                icons: ["https://voiceswap.cc/icon.png"],
                redirect: redirect
            )

            Networking.configure(
                groupIdentifier: "group.com.voiceswap.app",
                projectId: projectId,
                socketFactory: VoiceSwapSocketFactory()
            )

            AppKit.configure(
                projectId: projectId,
                metadata: metadata,
                crypto: cryptoProvider,
                sessionParams: makeSessionParams(),
                authRequestParams: nil,
                recommendedWalletIds: [
                    "c03dfee351b6fcc421b4494ea33b9d4b92a984f87aa76d1663bb28705e95f4be", // Uniswap
                    "c57ca95b47569778a828d19178114f4db188b89b763c899ba0be274e97267d96", // MetaMask
                    "1ae92b26df02f0abca6304df07debccd18262fdf5fe82daa81593582dac9a369"  // Rainbow
                ]
            )

            addUnichainPreset()
            isAppKitConfigured = true
            print("[WalletConnect] Configured")
        } catch {
            print("[WalletConnect] Config error: \(error)")
            isAppKitConfigured = false
        }
    }

    /// Add Unichain as a custom chain preset to AppKit
    private func addUnichainPreset() {
        let chain = Chain(
            chainName: "Unichain",
            chainNamespace: "eip155",
            chainReference: String(UnichainConfig.mainnetChainId),
            requiredMethods: [
                "personal_sign",
                "eth_signTypedData",
                "eth_sendTransaction"
            ],
            optionalMethods: [
                "wallet_switchEthereumChain",
                "wallet_addEthereumChain"
            ],
            events: [
                "chainChanged",
                "accountsChanged"
            ],
            token: .init(name: "Ether", symbol: "ETH", decimal: 18),
            rpcUrl: UnichainConfig.mainnet.rpcUrl,
            blockExplorerUrl: UnichainConfig.mainnet.explorer,
            imageId: "unichain"
        )

        AppKit.instance.addChainPreset(chain)
        AppKit.instance.selectChain(chain)
    }

    private func makeSessionParams() -> SessionParams {
        let methods: Set<String> = [
            "personal_sign",
            "eth_signTypedData",
            "eth_sendTransaction",
            "wallet_switchEthereumChain",
            "wallet_addEthereumChain"
        ]
        let events: Set<String> = [
            "chainChanged",
            "accountsChanged"
        ]
        let chains: [Blockchain] = [
            Blockchain("eip155:\(UnichainConfig.mainnetChainId)")!
        ]
        let namespaces: [String: ProposalNamespace] = [
            "eip155": ProposalNamespace(
                chains: chains,
                methods: methods,
                events: events
            )
        ]

        return SessionParams(namespaces: namespaces)
    }

    private func setupSessionObserver() {
        AppKit.instance.sessionSettlePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                self?.handleSessionsUpdate([session])
            }
            .store(in: &cancellables)

        AppKit.instance.sessionDeletePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_, _) in
                self?.handleSessionsUpdate([])
            }
            .store(in: &cancellables)

        AppKit.instance.sessionRejectionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] (_, reason) in
                print("[WalletConnect] ⚠️ Session rejected: \(reason.message)")
                self?.connectionState = .error(reason.message)
            }
            .store(in: &cancellables)

        // Poll only when in connecting state (not continuously)
        // The sessionSettlePublisher should handle most updates automatically
    }

    private func handleSessionsUpdate(_ sessions: [Session]) {
        if let session = sessions.first {
            // We have an active session
            print("[WalletConnect] Processing session: \(session.peer.name)")
            print("[WalletConnect]   Available accounts: \(session.accounts.count)")

            // Try to find an account on Unichain first, otherwise use the first account
            var bestAccount = session.accounts.first
            for account in session.accounts {
                let chainIdStr = account.blockchain.reference
                print("[WalletConnect]   - Account \(account.address.prefix(10))... on chain \(chainIdStr)")
                if chainIdStr == "130" || chainIdStr == String(UnichainConfig.mainnetChainId) {
                    bestAccount = account
                    print("[WalletConnect]   → Selected (Unichain account)")
                    break
                }
            }

            guard let account = bestAccount else {
                print("[WalletConnect] ⚠️ No accounts found in session")
                return
            }

            let address = account.address
            let chainIdString = account.blockchain.reference
            let chainId = Int(chainIdString) ?? UnichainConfig.mainnetChainId

            currentSessionTopic = session.topic

            let wallet = ConnectedWallet(
                address: address,
                chainId: chainId,
                walletName: session.peer.name
            )

            // Check if we need to switch to Unichain
            let wasDisconnected = connectedWallet == nil

            connectedWallet = wallet
            connectionState = .connected(address: address)
            saveWalletSession(wallet)
            showWalletModal = false

            print("[WalletConnect] ✅ Connected: \(address.prefix(10))... on chain \(chainId) via \(session.peer.name)")

            // Dismiss the AppKit modal after successful connection
            self.dismissPresentedModal()

            // If just connected and not on Unichain, request network switch
            // Skip for Uniswap Wallet since it already defaults to Unichain
            let isUnichainWallet = session.peer.name.lowercased().contains("uniswap")
            if wasDisconnected && chainId != UnichainConfig.mainnetChainId && !isUnichainWallet {
                print("[WalletConnect] Not on Unichain (chain \(chainId)), requesting switch...")
                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5s for connection to stabilize
                    await switchToUnichain()
                }
            }
        } else {
            // No sessions - disconnected
            if case .connected = connectionState {
                connectedWallet = nil
                connectionState = .disconnected
                currentSessionTopic = nil
                clearWalletSession()
                print("[WalletConnect] ❌ Disconnected")
            }
        }
    }

    // MARK: - Public Methods

    /// Open wallet connection modal using AppKit
    public func connect() {
        print("[WalletConnect] connect() called, isAppKitConfigured: \(isAppKitConfigured)")

        // Initialize lazily if not already done
        if !isAppKitConfigured {
            print("[WalletConnect] Initializing AppKit...")
            initialize()
        }

        connectionState = .connecting

        if isAppKitConfigured {
            print("[WalletConnect] Calling AppKit.present()...")

            // Get the root view controller to present from
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                // Find the topmost presented controller
                var topVC = rootVC
                while let presented = topVC.presentedViewController {
                    topVC = presented
                }
                print("[WalletConnect] Presenting from: \(type(of: topVC))")
                AppKit.present(from: topVC)
            } else {
                // Fallback to default present
                print("[WalletConnect] No root VC found, using default present")
                AppKit.present()
            }
            print("[WalletConnect] AppKit.present() called")
        } else {
            print("[WalletConnect] AppKit not configured, showing fallback modal")
            // Fallback to manual input
            showWalletModal = true
        }
    }

    /// Check for new sessions (called after deep link handling or when app becomes active)
    public func checkForNewSessions() {
        // Skip if already connected - no need to check
        if case .connected = connectionState { return }

        // Only check if not configured yet or in connecting state
        guard isAppKitConfigured else { return }

        let sessions = AppKit.instance.getSessions()
        if !sessions.isEmpty {
            handleSessionsUpdate(sessions)
            return
        }

        // If still connecting and no sessions found, retry a few times
        if case .connecting = connectionState {
            for delay in [0.5, 1.5, 2.5] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self else { return }
                    if case .connecting = self.connectionState {
                        let newSessions = AppKit.instance.getSessions()
                        if !newSessions.isEmpty {
                            self.handleSessionsUpdate(newSessions)
                        }
                    }
                }
            }
        }
    }

    /// Dismiss any presented modal (AppKit sheet)
    private func dismissPresentedModal() {
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let rootVC = windowScene.windows.first?.rootViewController {
                // Find the topmost presented controller and dismiss it
                var topVC = rootVC
                while let presented = topVC.presentedViewController {
                    topVC = presented
                }
                // Only dismiss if it's not the root
                if topVC !== rootVC {
                    print("[WalletConnect] Dismissing modal: \(type(of: topVC))")
                    topVC.dismiss(animated: true)
                }
            }
        }
    }

    /// Connect with a specific wallet address (manual input / fallback)
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

        print("[WalletConnect] Connected manually: \(address)")
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
        // Disconnect from AppKit session
        if let topic = currentSessionTopic {
            Task {
                try? await AppKit.instance.disconnect(topic: topic)
            }
        }

        connectedWallet = nil
        connectionState = .disconnected
        currentSessionTopic = nil
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

    /// Continuation for waiting on transaction response
    private var transactionContinuation: CheckedContinuation<String, Error>?

    /// Sign a personal message
    public func signMessage(_ message: String) async throws -> String {
        guard let address = currentAddress else {
            throw WalletError.notConnected
        }

        guard let topic = currentSessionTopic else {
            throw WalletError.notConnected
        }

        do {
            // Create the request params for personal_sign
            let params = AnyCodable([message, address])
            let blockchain = Blockchain("eip155:\(currentChain.chainId)")!
            let request = try Request(
                topic: topic,
                method: "personal_sign",
                params: params,
                chainId: blockchain
            )

            try await AppKit.instance.request(params: request)

            // The response will come through sessionResponsePublisher
            // For now, return a placeholder - in production you'd wait for the response
            return "signature_pending"
        } catch {
            print("[WalletConnect] Sign message error: \(error)")
            throw WalletError.transactionFailed(error.localizedDescription)
        }
    }

    /// Send a transaction and wait for the transaction hash
    /// This method opens the wallet app and waits for the user to approve
    public func sendTransaction(
        to: String,
        value: String,
        data: String? = nil
    ) async throws -> String {
        guard let address = currentAddress else {
            throw WalletError.notConnected
        }

        guard let topic = currentSessionTopic else {
            throw WalletError.notConnected
        }

        // Create transaction parameters as Codable struct
        struct TxParams: Codable {
            let from: String
            let to: String
            let value: String
            let data: String
        }

        let txParams = TxParams(
            from: address,
            to: to,
            value: value,
            data: data ?? "0x"
        )

        let params = AnyCodable([txParams])
        let blockchain = Blockchain("eip155:\(currentChain.chainId)")!

        do {
            let request = try Request(
                topic: topic,
                method: "eth_sendTransaction",
                params: params,
                chainId: blockchain
            )

            print("[WalletConnect] Sending transaction request...")
            print("[WalletConnect]   to: \(to)")
            print("[WalletConnect]   value: \(value)")
            print("[WalletConnect]   data: \(data?.prefix(20) ?? "0x")...")

            // Use withCheckedThrowingContinuation to wait for response
            return try await withCheckedThrowingContinuation { continuation in
                self.transactionContinuation = continuation

                Task {
                    do {
                        try await AppKit.instance.request(params: request)

                        // Open the wallet app to approve the transaction
                        print("[WalletConnect] Opening wallet for approval...")
                        try? await AppKit.instance.launchCurrentWallet()

                        // Set up response listener
                        self.setupTransactionResponseListener()

                    } catch {
                        print("[WalletConnect] Request failed: \(error)")
                        self.transactionContinuation?.resume(throwing: WalletError.transactionFailed(error.localizedDescription))
                        self.transactionContinuation = nil
                    }
                }

                // Timeout after 2 minutes
                Task {
                    try? await Task.sleep(nanoseconds: 120_000_000_000)
                    if self.transactionContinuation != nil {
                        print("[WalletConnect] Transaction timeout")
                        self.transactionContinuation?.resume(throwing: WalletError.transactionFailed("Transaction timed out. Please try again."))
                        self.transactionContinuation = nil
                    }
                }
            }
        } catch {
            print("[WalletConnect] Send transaction error: \(error)")
            throw WalletError.transactionFailed(error.localizedDescription)
        }
    }

    /// Set up listener for transaction response
    private func setupTransactionResponseListener() {
        AppKit.instance.sessionResponsePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] response in
                guard let self = self, let continuation = self.transactionContinuation else { return }

                print("[WalletConnect] Received session response")

                // RPCResult is an enum with .response(AnyCodable) or .error(JSONRPCError)
                switch response.result {
                case .response(let anyCodable):
                    // Try to extract the transaction hash string
                    if let txHash = anyCodable.value as? String {
                        print("[WalletConnect] ✅ Transaction hash: \(txHash)")
                        continuation.resume(returning: txHash)
                    } else {
                        print("[WalletConnect] ⚠️ Unexpected response type: \(type(of: anyCodable.value))")
                        // Try to convert to string anyway
                        let txHash = String(describing: anyCodable.value)
                        continuation.resume(returning: txHash)
                    }
                case .error(let rpcError):
                    print("[WalletConnect] ❌ Transaction rejected: \(rpcError.message)")
                    continuation.resume(throwing: WalletError.userRejected)
                }

                self.transactionContinuation = nil
            }
            .store(in: &cancellables)
    }

    // MARK: - Network Switching

    /// Switch the connected wallet to Unichain network
    public func switchToUnichain() async {
        guard let topic = currentSessionTopic else {
            print("[WalletConnect] Cannot switch network: no active session")
            return
        }

        guard let wallet = connectedWallet else {
            print("[WalletConnect] Cannot switch network: no wallet info")
            return
        }

        let unichainHex = String(format: "0x%x", UnichainConfig.mainnetChainId) // 0x82

        // Use the current chain the wallet is on for the request
        let currentChainId = wallet.chainId > 0 ? wallet.chainId : 1
        print("[WalletConnect] Current chain: \(currentChainId), switching to Unichain (130)")

        do {
            // First try to switch to Unichain (if already added)
            print("[WalletConnect] Requesting wallet_switchEthereumChain to \(unichainHex)...")

            struct SwitchChainParams: Codable {
                let chainId: String
            }

            let switchParams = SwitchChainParams(chainId: unichainHex)
            let params = AnyCodable([switchParams])

            // Use the current chain the wallet is on
            let blockchain = Blockchain("eip155:\(currentChainId)")!
            let request = try Request(
                topic: topic,
                method: "wallet_switchEthereumChain",
                params: params,
                chainId: blockchain
            )

            try await AppKit.instance.request(params: request)

            // Launch wallet app for user to approve
            print("[WalletConnect] Launching wallet for approval...")
            try? await AppKit.instance.launchCurrentWallet()

            print("[WalletConnect] Switch chain request sent")

        } catch {
            print("[WalletConnect] Switch failed: \(error), trying to add Unichain...")

            // If switch fails (chain not added), try to add Unichain
            await addUnichainNetwork()
        }
    }

    /// Add Unichain network to the wallet
    private func addUnichainNetwork() async {
        guard let topic = currentSessionTopic else { return }
        guard let wallet = connectedWallet else { return }

        let unichainHex = String(format: "0x%x", UnichainConfig.mainnetChainId)
        let currentChainId = wallet.chainId > 0 ? wallet.chainId : 1

        do {
            struct AddChainParams: Codable {
                let chainId: String
                let chainName: String
                let nativeCurrency: NativeCurrency
                let rpcUrls: [String]
                let blockExplorerUrls: [String]

                struct NativeCurrency: Codable {
                    let name: String
                    let symbol: String
                    let decimals: Int
                }
            }

            let addParams = AddChainParams(
                chainId: unichainHex,
                chainName: "Unichain",
                nativeCurrency: AddChainParams.NativeCurrency(
                    name: "Ethereum",
                    symbol: "ETH",
                    decimals: 18
                ),
                rpcUrls: ["https://mainnet.unichain.org"],
                blockExplorerUrls: ["https://uniscan.xyz"]
            )

            let params = AnyCodable([addParams])
            let blockchain = Blockchain("eip155:\(currentChainId)")!
            let request = try Request(
                topic: topic,
                method: "wallet_addEthereumChain",
                params: params,
                chainId: blockchain
            )

            print("[WalletConnect] Requesting wallet_addEthereumChain for Unichain...")
            try await AppKit.instance.request(params: request)

            print("[WalletConnect] Launching wallet for approval...")
            try? await AppKit.instance.launchCurrentWallet()

            print("[WalletConnect] Add chain request sent")

        } catch {
            print("[WalletConnect] Failed to add Unichain: \(error)")
        }
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
        // First check if AppKit has active sessions
        let sessions = AppKit.instance.getSessions()
        if !sessions.isEmpty {
            handleSessionsUpdate(sessions)
            return
        }

        // Otherwise try to restore from UserDefaults (for manual connections)
        guard let data = userDefaults.data(forKey: walletKey),
              let wallet = try? JSONDecoder().decode(ConnectedWallet.self, from: data) else {
            return
        }

        // Only restore manual connections from UserDefaults
        if wallet.walletName == "Manual" {
            connectedWallet = wallet
            connectionState = .connected(address: wallet.address)
            print("[WalletConnect] Restored manual session: \(wallet.address)")
        }
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

// MARK: - Wallet Connect View (Fallback Modal)

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

                        // AppKit Connect Button
                        Button(action: {
                            AppKit.present()
                        }) {
                            HStack {
                                Image(systemName: "link.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)

                                Text("Connect with WalletConnect")
                                    .font(.headline)
                                    .foregroundColor(.white)

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.blue.opacity(0.2))
                            )
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
}
