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
    case swapping(step: Int, total: Int, description: String)  // Multi-step swap progress
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
    @Published public var currentPurchaseConcept: String?

    // Security
    @Published public var showNewMerchantAlert: Bool = false
    @Published public var pendingNewMerchantAddress: String?

    // Session
    @Published public var currentSessionId: String?

    // MARK: - Private Properties

    let glassesManager = MetaGlassesManager.shared
    private let apiClient = VoiceSwapAPIClient.shared
    let securitySettings = SecuritySettings.shared
    private var cancellables = Set<AnyCancellable>()

    // Gemini Live session reference
    private(set) var geminiSession: GeminiSessionViewModel?

    // Auto-refresh balance timer
    private var balanceTimer: Timer?

    // Gas request tracking — only request once per session
    private var gasRequested = false

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
        gasRequested = false  // Reset gas flag for new address
        glassesManager.configure(walletAddress: address)

        // Fetch initial balances and start auto-refresh
        Task {
            await refreshBalances()
        }
        startBalanceAutoRefresh()
    }

    /// Start auto-refreshing balance every 60 seconds
    private var isRefreshingBalance = false
    private func startBalanceAutoRefresh() {
        balanceTimer?.invalidate()
        balanceTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, !self.isRefreshingBalance else { return }
                await self.refreshBalances()
            }
        }
    }

    /// Stop auto-refresh (e.g., when wallet is deleted)
    public func stopBalanceAutoRefresh() {
        balanceTimer?.invalidate()
        balanceTimer = nil
    }

    /// Refresh wallet balances
    public func refreshBalances() async {
        guard !walletAddress.isEmpty else { return }
        guard !isRefreshingBalance else { return }
        isRefreshingBalance = true
        defer { isRefreshingBalance = false }

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

                // Auto-request gas if MON balance is zero
                if monBal < 0.001 {
                    Task {
                        await requestGasIfNeeded()
                    }
                }
            }
        } catch {
            print("[ViewModel] Failed to refresh balances: \(error)")
        }
    }

    /// Request gas sponsorship for users with no MON (once per session)
    private func requestGasIfNeeded() async {
        guard !walletAddress.isEmpty, !gasRequested else { return }
        gasRequested = true
        do {
            let response = try await apiClient.requestGas(userAddress: walletAddress)
            if let data = response.data {
                print("[ViewModel] Gas request: \(data.status) - \(data.message)")
                if data.status == "funded" {
                    // Refresh balances after gas is received
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    await refreshBalances()
                }
            }
        } catch {
            print("[ViewModel] Gas request failed (non-critical): \(error.localizedDescription)")
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
        NSLog("[ViewModel] stopListening() called — flowState: %@", String(describing: flowState))
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

                    // Only speak locally when Gemini is NOT handling voice
                    if geminiSession?.isSessionActive != true {
                        glassesManager.speak(data.voicePrompt, language: "en-US")
                    }
                    glassesManager.triggerHaptic(.double)
                } else {
                    flowState = .failed(error: "Insufficient funds")
                    if geminiSession?.isSessionActive != true {
                        glassesManager.speak(data.voicePrompt, language: "en-US")
                    }
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

        // --- Security checks ---
        let amountValue = Double(amount) ?? 0
        let securityResult = await securitySettings.performSecurityChecks(
            amount: amountValue,
            merchantWallet: merchantWallet
        )

        switch securityResult {
        case .allowed:
            break

        case .dailyLimitExceeded(let spent, let limit):
            let remaining = max(0, limit - spent)
            flowState = .failed(error: "Daily limit ($\(String(format: "%.0f", limit))) reached. Remaining: $\(String(format: "%.2f", remaining))")
            glassesManager.speak("Daily spending limit reached", language: "en-US")
            glassesManager.triggerHaptic(.error)
            return

        case .newMerchantNeedsApproval(let address):
            // Voice mode: Gemini already warned "New merchant" and user said "yes" by voice.
            // Auto-approve without UI alert — user can't see/touch screen with glasses.
            if geminiSession?.isSessionActive == true {
                NSLog("[Security] Voice-confirmed new merchant — auto-approving: %@", address)
                securitySettings.approveMerchant(address)
            } else {
                pendingNewMerchantAddress = address
                showNewMerchantAlert = true
                return
            }

        case .faceIDRequired:
            let passed = await securitySettings.authenticateWithBiometrics()
            if passed {
                securitySettings.resetTransactionCounter()
            } else {
                flowState = .failed(error: "Face ID verification required")
                glassesManager.speak("Face ID verification failed", language: "en-US")
                glassesManager.triggerHaptic(.error)
                return
            }
        }

        flowState = .executing

        // Determine signing method: local VoiceSwap Wallet (instant) vs WalletConnect (MetaMask)
        let useLocalWallet = VoiceSwapWallet.shared.isCreated
            && walletAddress == VoiceSwapWallet.shared.address

        if geminiSession?.isSessionActive != true {
            if useLocalWallet {
                glassesManager.speak("Processing payment", language: "en-US")
            } else {
                glassesManager.speak("Opening your wallet for approval", language: "en-US")
            }
        }

        do {
            // Step 1: Get transaction data from backend
            print("[ViewModel] Preparing transaction... (local wallet: \(useLocalWallet))")
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
            print("[ViewModel]   needsSwap: \(txData.needsSwap ?? false)")
            print("[ViewModel]   steps: \(txData.steps?.count ?? 0)")

            let walletManager = WalletConnectManager.shared
            var finalTxHash: String = ""

            /// Signs and sends a single transaction using the appropriate wallet
            func sendTx(to: String, value: String, data: String?) async throws -> String {
                if useLocalWallet {
                    return try await VoiceSwapWallet.shared.sendTransaction(to: to, value: value, data: data)
                } else {
                    return try await walletManager.sendTransaction(to: to, value: value, data: data)
                }
            }

            // Check if we have multi-step transaction (swap flow)
            if let steps = txData.steps, steps.count > 1 {
                // Multi-step: wrap? → approve? → swap → transfer
                let totalSteps = steps.count
                print("[ViewModel] Multi-step payment: \(totalSteps) steps")

                if txData.needsSwap == true {
                    if useLocalWallet {
                        glassesManager.speak("Swapping tokens. This will take a moment.", language: "en-US")
                    } else {
                        glassesManager.speak("Swapping tokens first. Please approve \(totalSteps) transactions in your wallet.", language: "en-US")
                    }
                }

                for (index, step) in steps.enumerated() {
                    let stepNum = index + 1
                    flowState = .swapping(step: stepNum, total: totalSteps, description: step.description)
                    print("[ViewModel] Step \(stepNum)/\(totalSteps): \(step.type) — \(step.description)")

                    glassesManager.triggerHaptic(.double)

                    let stepTxHash = try await sendTx(
                        to: step.tx.to,
                        value: step.tx.value,
                        data: step.tx.data
                    )

                    print("[ViewModel] Step \(stepNum) tx: \(stepTxHash)")

                    // Wait for on-chain confirmation before next step
                    flowState = .confirming(txHash: stepTxHash)
                    let confirmed = try await waitForTransactionConfirmation(txHash: stepTxHash)

                    if !confirmed {
                        flowState = .failed(error: "Step \(stepNum) failed: \(step.description)")
                        glassesManager.speak("Transaction failed at step \(stepNum). Please try again.", language: "en-US")
                        glassesManager.triggerHaptic(.error)
                        clearPaymentContext()
                        VoiceSwapWallet.shared.resetNonceTracking()
                        return
                    }

                    print("[ViewModel] ✅ Step \(stepNum) confirmed")
                    finalTxHash = stepTxHash

                    // Small delay between steps to let state settle
                    if index < steps.count - 1 {
                        try? await Task.sleep(nanoseconds: 1_000_000_000)
                    }
                }

            } else {
                // Single-step: direct USDC transfer
                if !useLocalWallet {
                    glassesManager.speak("Please approve the transaction in your wallet", language: "en-US")
                }
                glassesManager.triggerHaptic(.double)

                finalTxHash = try await sendTx(
                    to: txData.transaction.to,
                    value: txData.transaction.value,
                    data: txData.transaction.data
                )

                print("[ViewModel] Transaction sent: \(finalTxHash)")

                // During Gemini voice session: skip confirmation polling for speed
                // The tx is already broadcast — Monad confirms in <1s anyway
                if geminiSession?.isSessionActive == true {
                    NSLog("[ViewModel] Voice mode — skipping confirmation poll for speed")
                } else {
                    // Non-voice mode: wait for blockchain confirmation
                    flowState = .confirming(txHash: finalTxHash)
                    if useLocalWallet {
                        glassesManager.speak("Confirming on Monad.", language: "en-US")
                    } else {
                        glassesManager.speak("Transaction sent. Waiting for confirmation.", language: "en-US")
                    }

                    let confirmed = try await waitForTransactionConfirmation(txHash: finalTxHash)

                    if !confirmed {
                        print("[ViewModel] Transaction failed: \(finalTxHash)")
                        flowState = .failed(error: "Transaction failed on-chain")
                        glassesManager.speak("Transaction failed. Please try again.", language: "en-US")
                        glassesManager.triggerHaptic(.error)
                        clearPaymentContext()
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        await refreshBalances()
                        return
                    }
                }
            }

            // Payment successful
            print("[ViewModel] Payment confirmed: \(finalTxHash)")
            flowState = .success(txHash: finalTxHash)
            let explorerUrl = "\(txData.explorerBaseUrl)\(finalTxHash)"
            if geminiSession?.isSessionActive != true {
                glassesManager.speak("Payment successful! \(txData.amount) USDC sent to \(txData.recipientShort)", language: "en-US")
            }
            glassesManager.triggerHaptic(.success)
            print("[ViewModel] Explorer: \(explorerUrl)")

            // Record for security tracking (daily spend + Face ID counter)
            securitySettings.recordSuccessfulPayment(amount: amountValue)

            // Save payment with purchase concept for merchant history
            Task {
                try? await apiClient.saveMerchantPayment(
                    merchantWallet: merchantWallet,
                    txHash: finalTxHash,
                    fromAddress: walletAddress,
                    amount: amount,
                    concept: currentPurchaseConcept
                )
                if let concept = currentPurchaseConcept {
                    print("[ViewModel] Payment saved with concept: \(concept)")
                }
            }

            // Generate signed receipt (proof of purchase)
            Task {
                do {
                    let receiptResponse = try await apiClient.requestReceipt(
                        txHash: finalTxHash,
                        payerAddress: walletAddress,
                        merchantWallet: merchantWallet,
                        amount: amount,
                        concept: currentPurchaseConcept
                    )
                    if let receipt = receiptResponse.data {
                        print("[ViewModel] Receipt generated: \(receipt.receiptHash.prefix(16))...")
                        print("[ViewModel] Verify: \(receipt.verifyUrl)")
                    }
                } catch {
                    print("[ViewModel] Receipt generation failed (non-critical): \(error)")
                }
            }

            // Clear payment context and nonce tracking
            clearPaymentContext()
            VoiceSwapWallet.shared.resetNonceTracking()

            // Refresh balances in background (don't block success flow)
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self.refreshBalances()
            }

        } catch WalletError.userRejected {
            print("[ViewModel] User rejected transaction")
            flowState = .cancelled
            glassesManager.speak("Transaction cancelled", language: "en-US")
            glassesManager.triggerHaptic(.short)
            clearPaymentContext()
            VoiceSwapWallet.shared.resetNonceTracking()

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
            VoiceSwapWallet.shared.resetNonceTracking()
        }
    }

    /// Approve a new merchant and retry the payment
    public func approveNewMerchantAndRetryPayment() async {
        guard let address = pendingNewMerchantAddress else { return }
        securitySettings.approveMerchant(address)
        pendingNewMerchantAddress = nil
        showNewMerchantAlert = false
        await confirmPayment()
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
        currentPurchaseConcept = nil
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
            // Don't kill Gemini session on Bluetooth audio route changes —
            // AVAudioSession reconfiguration temporarily drops A2DP/HFP.
            // Only reset flow if not in an active Gemini session.
            if geminiSession?.isSessionActive != true {
                flowState = .idle
            } else {
                NSLog("[ViewModel] Glasses HFP dropped but Gemini session active — keeping session alive")
            }
        }
    }

    nonisolated public func glassesDidReceiveVoiceCommand(_ result: VoiceCommandResult) {
        // Voice commands now handled by Gemini Live — this delegate is no longer used
        print("[ViewModel] Voice command via delegate (ignored, using Gemini): '\(result.transcript)'")
    }

    nonisolated public func glassesDidScanQR(_ result: QRScanResult) {
        Task { @MainActor in
            // When Gemini session is active, route QR through voice flow (not keyboard UI)
            if geminiSession?.isSessionActive == true {
                let trimmedData = result.rawData.trimmingCharacters(in: .whitespacesAndNewlines)
                let wallet = result.merchantWallet ?? trimmedData
                NSLog("[ViewModel] QR detected (Gemini active) — routing to voice flow: %@", wallet)

                // Store merchant info for Gemini tool calls
                currentMerchantWallet = wallet
                currentMerchantName = result.merchantName
                currentAmount = result.amount

                // Update flowState so camera poll in scan_qr exits early
                flowState = .processing

                // Stop camera since we got the QR
                glassesManager.stopQRScanning()
                glassesManager.triggerHaptic(.success)

                // Notify Gemini — it will ask for amount by voice
                geminiSession?.notifyQRDetected(
                    merchantWallet: wallet,
                    merchantName: result.merchantName,
                    amount: result.amount
                )
                return
            }

            // Fallback: old keyboard-based flow when Gemini is not active
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
