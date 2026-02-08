/**
 * VoiceSwapViewModel.swift
 * VoiceSwap - Main ViewModel for the iOS app
 *
 * Coordinates between Meta Glasses, API client, and SwiftUI views.
 * Manages the complete payment flow from voice command to execution.
 */

import Foundation
import Combine
import SwiftUI

// MARK: - Token Display Info

public struct TokenDisplayInfo: Identifiable {
    public let id: String
    public let symbol: String
    public let balance: String
    public let icon: String  // SF Symbol name
    public let color: String // Hex color

    public init(symbol: String, balance: String, icon: String, color: String) {
        self.id = symbol
        self.symbol = symbol
        self.balance = balance
        self.icon = icon
        self.color = color
    }
}

// MARK: - Payment Flow State

public enum PaymentFlowState: Equatable {
    case idle
    case listening
    case processing
    case scanningQR
    case enteringAmount(merchant: String)  // QR scanned but no amount - prompt user
    case awaitingConfirmation(amount: String, merchant: String)
    case executing
    case confirming(txHash: String)  // Transaction sent, waiting for blockchain confirmation
    case success(txHash: String)
    case failed(error: String)
    case cancelled
}

// MARK: - VoiceSwap ViewModel

@MainActor
public class VoiceSwapViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published public var flowState: PaymentFlowState = .idle
    @Published public var isConnectedToGlasses: Bool = false
    @Published public var glassesBatteryLevel: Int = 0
    @Published public var walletAddress: String = ""
    @Published public var walletBalance: String = "0.00"
    @Published public var monBalance: String = "0.0000"
    @Published public var tokenBalances: [TokenDisplayInfo] = []
    @Published public var lastVoiceCommand: String = ""
    @Published public var lastResponse: String = ""
    @Published public var errorMessage: String?

    // Current payment context
    @Published public var currentMerchantWallet: String?
    @Published public var currentMerchantName: String?
    @Published public var currentAmount: String?
    @Published public var needsSwap: Bool = false
    @Published public var swapFromToken: String?

    // Session
    @Published public var currentSessionId: String?

    // MARK: - Private Properties

    let glassesManager = MetaGlassesManager.shared
    private let apiClient = VoiceSwapAPIClient.shared
    private var cancellables = Set<AnyCancellable>()

    // Gemini Live session reference
    private(set) var geminiSession: GeminiSessionViewModel?

    // MARK: - Initialization

    public init() {
        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Observe glasses connection state
        glassesManager.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .connected:
                    self?.isConnectedToGlasses = true
                default:
                    self?.isConnectedToGlasses = false
                }
            }
            .store(in: &cancellables)

        // Observe battery level
        glassesManager.$batteryLevel
            .receive(on: DispatchQueue.main)
            .assign(to: &$glassesBatteryLevel)

        // Observe voice transcripts
        glassesManager.$lastTranscript
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastVoiceCommand)
    }

    // MARK: - Gemini Session

    func setupGeminiSession(_ session: GeminiSessionViewModel) {
        self.geminiSession = session
        session.paymentViewModel = self
    }

    // MARK: - Wallet Management

    /// Set the user's wallet address
    public func setWalletAddress(_ address: String) {
        walletAddress = address
        glassesManager.configure(walletAddress: address)

        // Fetch initial balances
        Task {
            await refreshBalances()
        }
    }

    /// Refresh wallet balances
    public func refreshBalances() async {
        guard !walletAddress.isEmpty else { return }

        do {
            let response = try await apiClient.getWalletBalances(address: walletAddress)

            if let balances = response.data {
                walletBalance = balances.totalUSD  // Total in USD (USDC + MON)
                monBalance = balances.nativeMON.balance

                // Build token display list (Monad only)
                var tokens: [TokenDisplayInfo] = []

                // Always show MON first
                let monBal = Double(balances.nativeMON.balance) ?? 0
                if monBal > 0.0001 {
                    tokens.append(TokenDisplayInfo(
                        symbol: "MON",
                        balance: formatBalance(monBal, decimals: 4),
                        icon: "m.circle.fill",
                        color: "836EF9"  // Monad purple
                    ))
                }

                // USDC
                if let usdc = balances.tokens.first(where: { $0.symbol == "USDC" }) {
                    let bal = Double(usdc.balance) ?? 0
                    if bal > 0.01 {
                        tokens.append(TokenDisplayInfo(
                            symbol: "USDC",
                            balance: formatBalance(bal, decimals: 2),
                            icon: "dollarsign.circle.fill",
                            color: "2775CA"  // USDC blue
                        ))
                    }
                }

                // WMON
                if let wmon = balances.tokens.first(where: { $0.symbol == "WMON" }) {
                    let bal = Double(wmon.balance) ?? 0
                    if bal > 0.0001 {
                        tokens.append(TokenDisplayInfo(
                            symbol: "WMON",
                            balance: formatBalance(bal, decimals: 4),
                            icon: "w.circle.fill",
                            color: "836EF9"  // Monad purple
                        ))
                    }
                }

                tokenBalances = tokens
            }
        } catch {
            print("[ViewModel] Failed to refresh balances: \(error)")
        }
    }

    /// Format balance with appropriate decimals
    private func formatBalance(_ value: Double, decimals: Int) -> String {
        return String(format: "%.\(decimals)f", value)
    }

    // MARK: - Glasses Connection

    /// Connect to Meta Ray-Ban glasses
    public func connectToGlasses() async {
        do {
            try await glassesManager.connectToGlasses()
            glassesManager.delegate = self
        } catch {
            errorMessage = "Failed to connect to glasses: \(error.localizedDescription)"
        }
    }

    /// Disconnect from glasses
    public func disconnectGlasses() {
        glassesManager.disconnect()
    }

    // MARK: - Voice Commands (Gemini Live)

    /// Start Gemini Live voice session
    public func startListening() {
        glassesManager.delegate = self
        let audioMode: AudioMode = glassesManager.isConnected ? .glasses : .phone
        geminiSession?.startSession(audioMode: audioMode)
        flowState = .listening
    }

    /// Stop Gemini Live voice session
    public func stopListening() {
        geminiSession?.stopSession()
        if flowState == .listening {
            flowState = .idle
        }
    }

    /// Start QR scanning (callable from Gemini tool dispatch)
    public func startQRScanning() async {
        flowState = .scanningQR
        glassesManager.triggerHaptic(.short)
        await glassesManager.startQRScanning()
    }

    // MARK: - Payment Flow

    /// Handle QR code scan result
    /// Accepts either a full payment URL or a plain Ethereum wallet address (0x...)
    public func handleQRScan(_ qrData: String) async {
        print("[ViewModel] 📱 QR Scanned: \(qrData)")
        flowState = .processing

        let trimmedData = qrData.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if it's a plain Ethereum address (most common case for merchants)
        if trimmedData.hasPrefix("0x") && trimmedData.count == 42 {
            // It's just a wallet address - no amount, no merchant name
            print("[ViewModel] Detected plain wallet address: \(trimmedData)")

            currentMerchantWallet = trimmedData
            currentMerchantName = nil
            currentAmount = nil

            let merchantDisplay = "\(trimmedData.prefix(6))...\(trimmedData.suffix(4))"

            // Stop camera streaming since we got what we need
            glassesManager.stopQRScanning()

            // Prompt user to enter amount
            flowState = .enteringAmount(merchant: merchantDisplay)
            glassesManager.speak("Wallet detected. Enter the amount to pay.", language: "en-US")
            glassesManager.triggerHaptic(.success)

            print("[ViewModel] Ready for amount input, merchant: \(merchantDisplay)")
            return
        }

        // Otherwise try to parse as a payment URL (voiceswap://, ethereum:, etc.)
        do {
            let response = try await apiClient.parseQRCode(qrData: trimmedData)

            if let paymentRequest = response.data {
                currentMerchantWallet = paymentRequest.merchantWallet
                currentMerchantName = paymentRequest.merchantName
                currentAmount = paymentRequest.amount

                let merchantDisplay = paymentRequest.merchantName ?? "\(paymentRequest.merchantWallet.prefix(6))...\(paymentRequest.merchantWallet.suffix(4))"

                // Stop camera streaming
                glassesManager.stopQRScanning()

                // Check if amount is provided
                if let amount = paymentRequest.amount, !amount.isEmpty {
                    // We have an amount - proceed to payment preparation
                    await preparePayment()
                } else {
                    // No amount in QR - prompt user to enter amount
                    print("[ViewModel] QR code has no amount - prompting user to enter")
                    flowState = .enteringAmount(merchant: merchantDisplay)
                    glassesManager.speak("Merchant scanned. How much would you like to pay?", language: "en-US")
                    glassesManager.triggerHaptic(.double)
                }
            }
        } catch {
            print("[ViewModel] Failed to parse QR: \(error)")
            errorMessage = "Failed to parse QR code: \(error.localizedDescription)"
            flowState = .failed(error: error.localizedDescription)
            glassesManager.speak("Could not read QR code. Please try again.", language: "en-US")
            glassesManager.triggerHaptic(.error)
        }
    }

    /// Set the amount for a pending payment (after QR scan with no amount)
    public func setPaymentAmount(_ amount: String) async {
        guard currentMerchantWallet != nil else {
            errorMessage = "No merchant wallet set"
            return
        }

        currentAmount = amount
        print("[ViewModel] Amount set to: \(amount)")

        // Now proceed to prepare the payment
        await preparePayment()
    }

    /// Prepare payment (check balances, determine swap)
    public func preparePayment() async {
        guard let merchantWallet = currentMerchantWallet else { return }

        flowState = .processing

        do {
            let response = try await apiClient.preparePayment(
                userAddress: walletAddress,
                merchantWallet: merchantWallet,
                qrData: nil,
                amount: currentAmount
            )

            if let data = response.data {
                needsSwap = data.swapInfo.needsSwap
                swapFromToken = data.swapInfo.swapFromSymbol

                let merchantDisplay = currentMerchantName ?? "\(merchantWallet.prefix(6))...\(merchantWallet.suffix(4))"
                let amountDisplay = currentAmount ?? data.maxPayable.estimatedUSDC ?? "0"

                if data.ready {
                    flowState = .awaitingConfirmation(amount: amountDisplay, merchant: merchantDisplay)

                    // Speak prompt
                    glassesManager.speak(data.voicePrompt, language: "en-US")
                    glassesManager.triggerHaptic(.double)
                } else {
                    flowState = .failed(error: "Insufficient funds")
                    glassesManager.speak(data.voicePrompt, language: "en-US")
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            flowState = .failed(error: error.localizedDescription)
        }
    }

    /// Confirm and execute payment using WalletConnect
    /// The user's wallet will sign and broadcast the transaction
    public func confirmPayment() async {
        guard let merchantWallet = currentMerchantWallet,
              let amount = currentAmount else {
            errorMessage = "Missing payment details"
            return
        }

        flowState = .executing
        glassesManager.speak("Opening your wallet for approval", language: "en-US")

        do {
            // Step 1: Get transaction data from backend
            print("[ViewModel] Preparing transaction...")
            let prepareResponse = try await apiClient.prepareTransaction(
                userAddress: walletAddress,
                merchantWallet: merchantWallet,
                amount: amount
            )

            guard let txData = prepareResponse.data else {
                throw APIError.serverError(prepareResponse.error ?? "Failed to prepare transaction")
            }

            print("[ViewModel] Transaction prepared:")
            print("[ViewModel]   to: \(txData.transaction.to)")
            print("[ViewModel]   amount: \(txData.amount) \(txData.tokenSymbol)")

            // Step 2: Send transaction via WalletConnect
            // This will open the user's wallet for approval
            glassesManager.speak("Please approve the transaction in your wallet", language: "en-US")
            glassesManager.triggerHaptic(.double)

            let walletManager = WalletConnectManager.shared
            let txHash = try await walletManager.sendTransaction(
                to: txData.transaction.to,
                value: txData.transaction.value,
                data: txData.transaction.data
            )

            print("[ViewModel] Transaction sent: \(txHash)")

            // Step 3: Wait for blockchain confirmation
            flowState = .confirming(txHash: txHash)
            glassesManager.speak("Transaction sent. Waiting for confirmation.", language: "en-US")

            // Poll for transaction confirmation
            let confirmed = try await waitForTransactionConfirmation(txHash: txHash)

            if confirmed {
                print("[ViewModel] ✅ Transaction confirmed: \(txHash)")
                flowState = .success(txHash: txHash)
                let explorerUrl = "\(txData.explorerBaseUrl)\(txHash)"
                glassesManager.speak("Payment successful! \(txData.amount) USDC sent to \(txData.recipientShort)", language: "en-US")
                glassesManager.triggerHaptic(.success)
                print("[ViewModel] Explorer: \(explorerUrl)")
            } else {
                print("[ViewModel] ❌ Transaction failed: \(txHash)")
                flowState = .failed(error: "Transaction failed on-chain")
                glassesManager.speak("Transaction failed. Please try again.", language: "en-US")
                glassesManager.triggerHaptic(.error)
            }

            // Clear payment context
            clearPaymentContext()

            // Refresh balances after a short delay
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await refreshBalances()

        } catch WalletError.userRejected {
            print("[ViewModel] User rejected transaction")
            flowState = .cancelled
            glassesManager.speak("Transaction cancelled", language: "en-US")
            glassesManager.triggerHaptic(.short)
            clearPaymentContext()

        } catch WalletError.notConnected {
            print("[ViewModel] Wallet not connected")
            flowState = .failed(error: "Wallet not connected. Please connect your wallet first.")
            glassesManager.speak("Please connect your wallet first", language: "en-US")
            glassesManager.triggerHaptic(.error)

        } catch let error as APIError {
            print("[ViewModel] API error: \(error)")
            let userMessage: String
            switch error {
            case .serverError(let msg):
                userMessage = msg
            case .decodingError:
                userMessage = "Server response error. Please try again."
            case .httpError(let code):
                userMessage = "Server error (\(code)). Please try again."
            case .networkError:
                userMessage = "Network error. Check your connection."
            default:
                userMessage = error.localizedDescription
            }
            flowState = .failed(error: userMessage)
            glassesManager.speak("Payment failed. \(userMessage)", language: "en-US")
            glassesManager.triggerHaptic(.error)

        } catch {
            print("[ViewModel] Payment error: \(error)")
            flowState = .failed(error: error.localizedDescription)
            glassesManager.speak("Payment failed. Please try again.", language: "en-US")
            glassesManager.triggerHaptic(.error)
        }
    }

    /// Cancel current payment
    public func cancelPayment() {
        flowState = .cancelled
        glassesManager.speak("Payment cancelled", language: "en-US")
        glassesManager.triggerHaptic(.short)
        clearPaymentContext()

        // Return to listening after a delay
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            flowState = .listening
        }
    }

    /// Reset to idle state
    public func reset() {
        flowState = .idle
        clearPaymentContext()
        errorMessage = nil
    }

    /// Initiate payment from a deep link
    public func initiatePaymentFromDeepLink(recipient: String, amount: String?, merchantName: String?) {
        // Set up payment context from deep link
        currentMerchantWallet = recipient
        currentMerchantName = merchantName
        currentAmount = amount

        let merchantDisplay = merchantName ?? "\(recipient.prefix(6))...\(recipient.suffix(4))"
        let amountDisplay = amount ?? "?"

        print("[ViewModel] Payment initiated from deep link: \(amountDisplay) USDC to \(merchantDisplay)")

        // If we have an amount, go directly to confirmation
        if amount != nil {
            flowState = .awaitingConfirmation(amount: amountDisplay, merchant: merchantDisplay)
            glassesManager.speak("Ready to pay \(amountDisplay) dollars to \(merchantDisplay). Say confirm to proceed.", language: "en-US")
            glassesManager.triggerHaptic(.double)
        } else {
            // No amount specified, ask user
            flowState = .listening
            glassesManager.speak("How much would you like to pay to \(merchantDisplay)?", language: "en-US")
            glassesManager.triggerHaptic(.short)
        }
    }

    // MARK: - Private Helpers

    /// Poll backend for transaction confirmation
    /// Returns true if confirmed, false if failed
    /// Throws on timeout or network error
    private func waitForTransactionConfirmation(txHash: String) async throws -> Bool {
        let maxAttempts = 30  // 30 attempts * 2 seconds = 60 seconds max
        let pollInterval: UInt64 = 2_000_000_000  // 2 seconds in nanoseconds

        for attempt in 1...maxAttempts {
            print("[ViewModel] Checking tx status (attempt \(attempt)/\(maxAttempts)): \(txHash)")

            do {
                let response = try await apiClient.getTransactionStatus(txHash: txHash)

                guard let data = response.data else {
                    print("[ViewModel] No data in tx status response")
                    try await Task.sleep(nanoseconds: pollInterval)
                    continue
                }

                switch data.status {
                case "confirmed":
                    print("[ViewModel] Transaction confirmed with \(data.confirmations ?? 0) confirmations")
                    return true

                case "failed":
                    print("[ViewModel] Transaction failed on-chain")
                    return false

                case "pending":
                    print("[ViewModel] Transaction still pending...")
                    // Continue polling

                case "not_found":
                    // Transaction may have been dropped, but give it more time
                    print("[ViewModel] Transaction not found yet, waiting...")

                default:
                    print("[ViewModel] Unknown status: \(data.status)")
                }

            } catch {
                print("[ViewModel] Error checking tx status: \(error)")
                // Continue polling on transient errors
            }

            try await Task.sleep(nanoseconds: pollInterval)
        }

        // Timeout - we didn't get confirmation in time
        // The transaction might still be pending in the mempool
        print("[ViewModel] Transaction verification timed out")
        throw TransactionError.confirmationTimeout
    }

    private func clearPaymentContext() {
        currentMerchantWallet = nil
        currentMerchantName = nil
        currentAmount = nil
        needsSwap = false
        swapFromToken = nil
    }
}

// MARK: - Transaction Errors

public enum TransactionError: Error, LocalizedError {
    case confirmationTimeout

    public var errorDescription: String? {
        switch self {
        case .confirmationTimeout:
            return "Transaction confirmation timed out. Please check the explorer for status."
        }
    }
}

// MARK: - MetaGlassesDelegate

extension VoiceSwapViewModel: MetaGlassesDelegate {

    nonisolated public func glassesDidConnect() {
        Task { @MainActor in
            isConnectedToGlasses = true
            print("[ViewModel] Glasses connected")
        }
    }

    nonisolated public func glassesDidDisconnect() {
        Task { @MainActor in
            isConnectedToGlasses = false
            geminiSession?.stopSession()
            flowState = .idle
        }
    }

    nonisolated public func glassesDidReceiveVoiceCommand(_ result: VoiceCommandResult) {
        // Voice commands now handled by Gemini Live — this delegate is no longer used
        print("[ViewModel] Voice command via delegate (ignored, using Gemini): '\(result.transcript)'")
    }

    nonisolated public func glassesDidScanQR(_ result: QRScanResult) {
        Task { @MainActor in
            await handleQRScan(result.rawData)

            // Notify Gemini about the QR detection so it can speak about it
            geminiSession?.notifyQRDetected(
                merchantWallet: result.merchantWallet ?? result.rawData,
                merchantName: result.merchantName,
                amount: result.amount
            )
        }
    }

    nonisolated public func glassesDidEncounterError(_ error: Error) {
        Task { @MainActor in
            errorMessage = error.localizedDescription
            flowState = .failed(error: error.localizedDescription)
        }
    }
}
