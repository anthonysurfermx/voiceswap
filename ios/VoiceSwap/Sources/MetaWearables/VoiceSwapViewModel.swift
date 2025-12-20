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

// MARK: - Payment Flow State

public enum PaymentFlowState: Equatable {
    case idle
    case listening
    case processing
    case scanningQR
    case awaitingConfirmation(amount: String, merchant: String)
    case executing
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
    @Published public var ethBalance: String = "0.0000"
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

    private let glassesManager = MetaGlassesManager.shared
    private let apiClient = VoiceSwapAPIClient.shared
    private var cancellables = Set<AnyCancellable>()

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
                walletBalance = balances.totalUSD  // Total in USD (USDC + ETH)
                ethBalance = balances.nativeETH.balance
            }
        } catch {
            print("[ViewModel] Failed to refresh balances: \(error)")
        }
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

    // MARK: - Voice Commands

    /// Start listening for voice commands
    public func startListening() {
        // IMPORTANT: Set delegate before starting to listen
        // This ensures voice commands are routed back to the ViewModel
        glassesManager.delegate = self
        glassesManager.startListening()
        flowState = .listening
    }

    /// Stop listening
    public func stopListening() {
        glassesManager.stopListening()
        if flowState == .listening {
            flowState = .idle
        }
    }

    /// Process a voice command manually (for testing without glasses)
    public func processVoiceCommand(_ transcript: String) async {
        print("[ViewModel] Processing voice command: '\(transcript)' with wallet: \(walletAddress)")
        lastVoiceCommand = transcript
        flowState = .processing

        do {
            let response = try await apiClient.processVoiceCommand(
                transcript: transcript,
                userAddress: walletAddress.isEmpty ? nil : walletAddress,
                merchantWallet: currentMerchantWallet
            )

            print("[ViewModel] API response success: \(response.success)")

            guard let data = response.data else {
                print("[ViewModel] No data in response!")
                throw APIError.serverError("No data in response")
            }

            print("[ViewModel] Voice response: '\(data.voiceResponse)'")
            print("[ViewModel] Next action: \(data.nextAction)")
            lastResponse = data.voiceResponse

            // Speak the response
            let language = data.intent.language == "es" ? "es-ES" : "en-US"
            print("[ViewModel] Speaking in language: \(language)")
            glassesManager.speak(data.voiceResponse, language: language)

            // Handle the next action
            await handleNextAction(data.nextAction, intent: data.intent)

        } catch {
            print("[ViewModel] ERROR: \(error)")
            errorMessage = error.localizedDescription
            flowState = .failed(error: error.localizedDescription)
            glassesManager.speak("Sorry, there was an error", language: "en-US")
        }
    }

    // MARK: - Payment Flow

    /// Handle QR code scan result
    public func handleQRScan(_ qrData: String) async {
        flowState = .processing

        do {
            let response = try await apiClient.parseQRCode(qrData: qrData)

            if let paymentRequest = response.data {
                currentMerchantWallet = paymentRequest.merchantWallet
                currentMerchantName = paymentRequest.merchantName
                currentAmount = paymentRequest.amount

                // Prepare the payment
                await preparePayment()
            }
        } catch {
            errorMessage = "Failed to parse QR code: \(error.localizedDescription)"
            flowState = .failed(error: error.localizedDescription)
        }
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
                let amountDisplay = currentAmount ?? data.maxPayable.estimatedUSDC

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

            print("[ViewModel] ✅ Transaction confirmed: \(txHash)")

            // Step 3: Success!
            flowState = .success(txHash: txHash)
            let explorerUrl = "\(txData.explorerBaseUrl)\(txHash)"
            glassesManager.speak("Payment successful! \(txData.amount) USDC sent to \(txData.recipientShort)", language: "en-US")
            glassesManager.triggerHaptic(.success)

            print("[ViewModel] Explorer: \(explorerUrl)")

            // Clear payment context
            clearPaymentContext()

            // Refresh balances after a short delay
            try? await Task.sleep(nanoseconds: 3_000_000_000)
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

    private func handleNextAction(_ action: String, intent: ParsedIntent) async {
        switch action {
        case "scan_qr":
            flowState = .scanningQR
            glassesManager.triggerHaptic(.short)

        case "await_confirmation":
            let amount = intent.amount ?? currentAmount ?? "?"
            let merchant = intent.recipient ?? currentMerchantName ?? "merchant"
            flowState = .awaitingConfirmation(amount: amount, merchant: merchant)

            // Store context
            if let amount = intent.amount {
                currentAmount = amount
            }
            if let recipient = intent.recipient {
                currentMerchantName = recipient
            }

        case "execute_transaction":
            await confirmPayment()

        case "cancel_transaction":
            cancelPayment()

        case "show_balance":
            await refreshBalances()
            flowState = .idle

        case "show_help":
            flowState = .idle

        default:
            flowState = .listening
        }
    }

    private func clearPaymentContext() {
        currentMerchantWallet = nil
        currentMerchantName = nil
        currentAmount = nil
        needsSwap = false
        swapFromToken = nil
    }
}

// MARK: - MetaGlassesDelegate

extension VoiceSwapViewModel: MetaGlassesDelegate {

    nonisolated public func glassesDidConnect() {
        Task { @MainActor in
            isConnectedToGlasses = true
            glassesManager.speak("VoiceSwap connected. Say 'Hey VoiceSwap' to start.", language: "en-US")
        }
    }

    nonisolated public func glassesDidDisconnect() {
        Task { @MainActor in
            isConnectedToGlasses = false
            flowState = .idle
        }
    }

    nonisolated public func glassesDidReceiveVoiceCommand(_ result: VoiceCommandResult) {
        print("[ViewModel] Delegate received voice command: '\(result.transcript)'")
        Task { @MainActor in
            await processVoiceCommand(result.transcript)
        }
    }

    nonisolated public func glassesDidScanQR(_ result: QRScanResult) {
        Task { @MainActor in
            await handleQRScan(result.rawData)
        }
    }

    nonisolated public func glassesDidEncounterError(_ error: Error) {
        Task { @MainActor in
            errorMessage = error.localizedDescription
            flowState = .failed(error: error.localizedDescription)
        }
    }
}
