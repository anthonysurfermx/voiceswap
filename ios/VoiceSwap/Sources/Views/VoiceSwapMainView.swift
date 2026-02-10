/**
 * VoiceSwapMainView.swift
 * VoiceSwap - Voice-activated crypto payments
 *
 * Minimal brutalist design with Monad purple branding
 * Clean, futuristic, high contrast
 */

import SwiftUI
import ReownAppKit
import AudioToolbox

// MARK: - Design System (Monad branded)

struct Theme {
    // Core colors - Monad purple palette
    static let bg = Color.white                    // Pure white background
    static let card = Color.white
    static let dark = Color.black                  // Pure black for text/icons
    static let accent = Color(hex: "836EF9")       // Monad purple
    static let accentHover = Color(hex: "A18FFF")  // Lighter purple hover
    static let success = Color(hex: "836EF9")
    static let error = Color(hex: "FF3B30")
    static let muted = Color(hex: "777777")        // Secondary text
    static let border = Color(hex: "DADADA")       // Subtle borders
    static let divider = Color(hex: "E5E5E5")      // 1px lines
}

// MARK: - Main View

public struct VoiceSwapMainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = VoiceSwapViewModel()
    @ObservedObject private var walletManager = WalletConnectManager.shared
    @StateObject private var glassesManager = MetaGlassesManager.shared
    @StateObject private var geminiSession = GeminiSessionViewModel()
    @State private var isBalanceHidden = false
    @State private var showPhoneCameraScanner = false
    @State private var showGeminiKeyInput = false
    @State private var geminiKeyInput: String = ""
    @State private var amountInput: String = ""
    @State private var showSecuritySettings = false
    @State private var showTransactionHistory = false
    @State private var showReceiveQR = false

    public init() {}

    @ObservedObject private var securitySettings = SecuritySettings.shared

    public var body: some View {
        ZStack {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                headerView
                    .padding(.bottom, 12)

                if walletManager.isConnected {
                    // --- Connected: compact status + balance + PAY ---
                    setupStatusRow

                    balanceCard

                    // History + Receive buttons
                    HStack(spacing: 8) {
                        Button {
                            showTransactionHistory = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 12, weight: .bold))
                                Text("HISTORY")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .tracking(1)
                            }
                            .foregroundColor(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                        }

                        Button {
                            showReceiveQR = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "qrcode")
                                    .font(.system(size: 12, weight: .bold))
                                Text("RECEIVE")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .tracking(1)
                            }
                            .foregroundColor(Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                        }
                    }

                    // Voice hint card — shows when Gemini is active but idle
                    if geminiSession.isSessionActive && viewModel.flowState == .idle {
                        voiceHintCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Gemini connecting indicator
                    if !geminiSession.isSessionActive && (geminiSession.geminiService.connectionState == .connecting || geminiSession.geminiService.connectionState == .settingUp) {
                        connectingCard
                            .transition(.opacity)
                    }

                    // Gemini error display
                    if let error = geminiSession.sessionError {
                        MinimalCard(highlight: Theme.error.opacity(0.08)) {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Theme.error)
                                Text(error)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(Theme.dark)
                                Spacer()
                                Button {
                                    handleGeminiButtonTap()
                                } label: {
                                    Text("RETRY")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(Theme.accent)
                                        .tracking(1)
                                }
                            }
                        }
                        .transition(.opacity)
                    }

                    payButton

                    // Show scanning card when glasses are streaming
                    if glassesManager.isStreaming {
                        scanningCard
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Show payment flow when active
                    if viewModel.flowState != .idle {
                        paymentCard
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                } else {
                    // --- Not connected: prominent connect prompt ---
                    connectWalletPrompt
                        .transition(.opacity)
                }

                Spacer(minLength: 56)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .animation(.easeInOut(duration: 0.25), value: walletManager.isConnected)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.flowState)
            .animation(.easeInOut(duration: 0.25), value: glassesManager.isStreaming)
            .animation(.easeInOut(duration: 0.25), value: geminiSession.isSessionActive)
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.light)
        .task {
            if let address = walletManager.currentAddress {
                viewModel.setWalletAddress(address)
            }

            // Wire Gemini session to ViewModel
            viewModel.setupGeminiSession(geminiSession)

            // Forward glasses video frames to Gemini for scene understanding
            glassesManager.onVideoFrame = { [weak geminiSession] image in
                geminiSession?.processVideoFrame(image)
            }
        }
        .onChange(of: walletManager.connectionState) { state in
            if case .connected(let address) = state {
                viewModel.setWalletAddress(address)
            }
        }
        .onChange(of: glassesManager.connectionState) { state in
            if case .error(let msg) = state {
                if msg.contains("Meta View") || msg.contains("camera") || msg.contains("Device Access") {
                    showPhoneCameraScanner = true
                }
            }
        }
        .sheet(isPresented: $showPhoneCameraScanner) {
            PhoneCameraScannerView(viewModel: viewModel) {
                showPhoneCameraScanner = false
            }
        }
        .alert("Gemini API Key", isPresented: $showGeminiKeyInput) {
            TextField("Paste your API key", text: $geminiKeyInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") {
                GeminiConfig.apiKey = geminiKeyInput
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Get a free key from Google AI Studio")
        }
        .sheet(isPresented: $showSecuritySettings) {
            SecuritySettingsSheet()
        }
        .sheet(isPresented: $showTransactionHistory) {
            TransactionHistorySheet(walletAddress: walletManager.currentAddress ?? "")
        }
        .sheet(isPresented: $showReceiveQR) {
            ReceiveQRSheet(walletAddress: walletManager.currentAddress ?? "")
        }
        .alert("New Merchant", isPresented: $viewModel.showNewMerchantAlert) {
            Button("Approve") {
                Task { await viewModel.approveNewMerchantAndRetryPayment() }
            }
            Button("Cancel", role: .cancel) {
                viewModel.pendingNewMerchantAddress = nil
            }
        } message: {
            if let address = viewModel.pendingNewMerchantAddress {
                Text("First payment to \(address.prefix(6))...\(address.suffix(4)). Approve this merchant?")
            } else {
                Text("Approve this new merchant?")
            }
        }

        // Lock screen overlay
        if securitySettings.faceIDOnLaunchEnabled && !securitySettings.isAppUnlocked {
            lockScreen
                .transition(.opacity)
        }
        } // ZStack
        .task {
            await securitySettings.unlockApp()
        }
    }

    // MARK: - Lock Screen

    private var lockScreen: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Theme.dark)
                        .frame(width: 80, height: 80)

                    Image(systemName: "faceid")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(Theme.accent)
                }

                Text("VOICESWAP")
                    .font(.system(size: 20, weight: .black, design: .monospaced))
                    .foregroundColor(Theme.dark)
                    .tracking(2)

                Text("Tap to unlock")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.muted)

                Spacer()

                Button {
                    Task { await securitySettings.unlockApp() }
                } label: {
                    Text("UNLOCK")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
            }
        }
    }

    // MARK: - Setup Status Row (compact indicators)

    private var isGlassesReady: Bool {
        !glassesManager.devices.isEmpty || glassesManager.isGlassesHFPConnected || glassesManager.isStreaming
    }

    private var glassesStatusCompact: String {
        switch glassesManager.connectionState {
        case .disconnected: return "Tap to pair"
        case .searching: return "Searching..."
        case .connecting: return "Connecting..."
        case .registered, .connected:
            return isGlassesReady ? "Ready" : "Tap to open Meta View"
        case .streaming: return "Scanning..."
        case .error: return "Tap to fix"
        }
    }

    private var voiceStatusCompact: String {
        if geminiSession.isAISpeaking { return "Speaking..." }
        if geminiSession.isListening { return "Listening..." }
        if geminiSession.isSessionActive { return "Active" }
        if geminiSession.geminiService.connectionState == .connecting || geminiSession.geminiService.connectionState == .settingUp { return "Connecting..." }
        if !GeminiConfig.isConfigured { return "Set API key" }
        return "Tap to start"
    }

    private var setupStatusRow: some View {
        HStack(spacing: 0) {
            // Wallet indicator
            setupIndicator(
                label: "WALLET",
                detail: walletManager.shortAddress,
                isActive: true,
                icon: "checkmark"
            ) {
                walletManager.disconnect()
            }

            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1, height: 28)

            // Glasses indicator
            setupIndicator(
                label: "GLASSES",
                detail: glassesStatusCompact,
                isActive: isGlassesReady,
                icon: isGlassesReady ? "checkmark" : "eyeglasses"
            ) {
                Task { await handleGlassesButtonTap() }
            }

            Rectangle()
                .fill(Theme.divider)
                .frame(width: 1, height: 28)

            // Voice indicator
            setupIndicator(
                label: "VOICE",
                detail: voiceStatusCompact,
                isActive: geminiSession.isSessionActive,
                icon: geminiSession.isSessionActive ? "waveform" : "mic.fill"
            ) {
                handleGeminiButtonTap()
            }
        }
        .padding(12)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(Theme.dark.opacity(0.1), lineWidth: 1)
        )
    }

    private func setupIndicator(
        label: String,
        detail: String?,
        isActive: Bool,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(isActive ? Theme.accent : Theme.border)
                        .frame(width: 6, height: 6)
                    Text(label)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark)
                }
                if let detail = detail {
                    Text(detail)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.muted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Voice Hint Card

    private var voiceHintCard: some View {
        MinimalCard(highlight: Theme.accent.opacity(0.06)) {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.accent)

                    Text("VOICE ACTIVE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark)
                        .tracking(1)

                    Spacer()

                    PulsingDot(color: Theme.accent)
                }

                Text("Say \"I want to pay\" or \"Quiero pagar\"")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.dark)

                HStack(spacing: 8) {
                    voiceExample("\"Pay 5 dollars\"")
                    voiceExample("\"Check balance\"")
                    voiceExample("\"Pagar\"")
                }
            }
        }
    }

    private func voiceExample(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(Theme.muted)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Theme.dark.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    // MARK: - Connecting Card

    private var connectingCard: some View {
        MinimalCard {
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                    .scaleEffect(0.9)

                VStack(alignment: .leading, spacing: 2) {
                    Text("CONNECTING TO AI")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark)
                        .tracking(1)
                    Text("Setting up voice session...")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.muted)
                }

                Spacer()
            }
        }
    }

    // MARK: - PAY Button

    @ViewBuilder
    private var payButton: some View {
        if viewModel.flowState == .idle {
            Button {
                startPaymentFlow()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 20, weight: .bold))
                    Text("PAY")
                        .font(.system(size: 18, weight: .black, design: .monospaced))
                        .tracking(4)
                }
                .foregroundColor(Theme.dark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
    }

    private func startPaymentFlow() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if isGlassesReady && geminiSession.isSessionActive {
            // Glasses + voice active: use glasses camera for QR scan
            Task {
                viewModel.flowState = .scanningQR
                glassesManager.delegate = viewModel
                await glassesManager.startQRScanning()
            }
        } else {
            // Default: open phone camera scanner
            showPhoneCameraScanner = true
        }
    }

    // MARK: - Connect Wallet Prompt

    private var connectWalletPrompt: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 40)

            Image(systemName: "wallet.pass.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(Theme.border)

            Text("Connect your wallet\nto start paying")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)

            Button {
                walletManager.connect()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                    Text("CONNECT WALLET")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .tracking(2)
                }
                .foregroundColor(Theme.dark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("VOICESWAP")
                    .font(.system(size: 24, weight: .black, design: .monospaced))
                    .foregroundColor(Theme.dark)
                    .tracking(2)

                Text("Voice payments")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.muted)
            }

            Spacer()

            // Settings gear
            Button { showSecuritySettings = true } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Theme.muted)
            }
            .padding(.trailing, 12)

            // Minimal logo
            ZStack {
                Circle()
                    .fill(Theme.dark)
                    .frame(width: 40, height: 40)

                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.accent)
            }
        }
    }

    // MARK: - Glasses Button Action

    private func handleGlassesButtonTap() async {
        switch glassesManager.connectionState {
        case .streaming:
            // Currently streaming - stop QR scan
            glassesManager.stopQRScanning()

        case .connected:
            // Start QR scan if SDK has devices OR glasses detected via audio route
            if !glassesManager.devices.isEmpty || glassesManager.isGlassesHFPConnected {
                glassesManager.delegate = viewModel
                await glassesManager.startQRScanning()
            } else {
                // Connected but no devices - try to start QR anyway
                glassesManager.delegate = viewModel
                await glassesManager.startQRScanning()
            }

        case .registered:
            // Already registered, waiting for Bluetooth device
            // Don't call connect() again - it would loop with RegistrationError
            if !glassesManager.devices.isEmpty || glassesManager.isGlassesHFPConnected {
                glassesManager.delegate = viewModel
                await glassesManager.startQRScanning()
            } else {
                print("[VoiceSwap] Registered but no glasses detected via Bluetooth")
                print("[VoiceSwap] Make sure glasses are connected in iOS Settings > Bluetooth")
                print("[VoiceSwap] Attempting automatic re-registration recovery...")
                await forceReconnectGlasses()
            }

        case .disconnected, .error:
            // Not registered or error - start registration flow
            await glassesManager.connect()

        case .searching, .connecting:
            // In progress - do nothing
            break
        }
    }

    /// Force disconnect and re-register glasses (long press action)
    /// Uses fullReset() to clear stale registration state (known Meta SDK issue)
    private func forceReconnectGlasses() async {
        print("[VoiceSwap] Force re-registration requested (full reset)")
        // Full reset clears all local state - fixes stale registration issue
        glassesManager.fullReset()
        // Small delay then reconnect
        try? await Task.sleep(nanoseconds: 500_000_000)
        await glassesManager.connect()
    }

    // MARK: - Gemini Helpers

    private func handleGeminiButtonTap() {
        if geminiSession.isSessionActive {
            viewModel.stopListening()
        } else if !GeminiConfig.isConfigured {
            geminiKeyInput = GeminiConfig.apiKey
            showGeminiKeyInput = true
        } else {
            viewModel.startListening()
        }
    }

    // MARK: - Scanning Card

    private var scanningCard: some View {
        MinimalCard(highlight: Theme.accent.opacity(0.1)) {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    // Animated scanning dot with pulse
                    PulsingDot(color: Theme.accent)

                    Text("SCANNING")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark)

                    Spacer()

                    Text("Look at QR code")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.muted)
                }

                // Scanning animation
                HStack(spacing: 20) {
                    Image(systemName: "qrcode.viewfinder")
                        .font(.system(size: 40, weight: .light))
                        .foregroundColor(Theme.accent)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Point glasses at")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.muted)
                        Text("merchant QR code")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.dark)
                    }

                    Spacer()
                }

                // Action buttons
                HStack(spacing: 8) {
                    MinimalButton("Cancel", style: .secondary) {
                        glassesManager.stopQRScanning()
                    }
                    MinimalButton("Use Phone", style: .primary) {
                        glassesManager.stopQRScanning()
                        showPhoneCameraScanner = true
                    }
                }
            }
        }
    }

    // MARK: - Balance Card

    private var balanceCard: some View {
        MinimalCard(accent: true) {
            VStack(spacing: 16) {
                HStack {
                    Text("BALANCE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark.opacity(0.5))

                    Spacer()

                    HStack(spacing: 12) {
                        Button { isBalanceHidden.toggle() } label: {
                            Image(systemName: isBalanceHidden ? "eye.slash" : "eye")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.dark.opacity(0.5))
                        }

                        Button { Task { await viewModel.refreshBalances() } } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Theme.dark.opacity(0.5))
                        }
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(isBalanceHidden ? "••••" : "$\(viewModel.walletBalance)")
                        .font(.system(size: 42, weight: .black, design: .monospaced))
                        .foregroundColor(Theme.dark)

                    if !isBalanceHidden {
                        Text("USD")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.dark.opacity(0.4))
                    }

                    Spacer()
                }

                // Token list with icons
                if !isBalanceHidden && !viewModel.tokenBalances.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(viewModel.tokenBalances) { token in
                            TokenRow(token: token)
                        }
                    }
                }

                HStack {
                    Spacer()

                    Text("MONAD")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark.opacity(0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.dark.opacity(0.05))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Payment Card

    private var paymentCard: some View {
        MinimalCard(highlight: paymentHighlight) {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(paymentDotColor)
                        .frame(width: 8, height: 8)

                    Text(paymentTitle)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark)

                    Spacer()

                    Text(paymentSubtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.muted)
                }

                paymentContent
                paymentButtons
            }
        }
    }

    private var paymentHighlight: Color? {
        switch viewModel.flowState {
        case .success: return Theme.accent.opacity(0.15)
        case .failed: return Theme.error.opacity(0.1)
        case .enteringAmount: return Theme.accent.opacity(0.08)
        case .awaitingConfirmation: return Theme.accent.opacity(0.1)
        case .swapping: return Theme.accent.opacity(0.08)
        default: return nil
        }
    }

    private var paymentDotColor: Color {
        switch viewModel.flowState {
        case .success: return Theme.accent
        case .failed: return Theme.error
        case .enteringAmount: return Theme.accent
        case .awaitingConfirmation: return Theme.accent
        case .swapping: return Theme.accent
        default: return Theme.muted
        }
    }

    private var paymentTitle: String {
        switch viewModel.flowState {
        case .listening: return "LISTENING"
        case .processing: return "PROCESSING"
        case .scanningQR: return "SCANNING"
        case .enteringAmount: return "ENTER AMOUNT"
        case .awaitingConfirmation: return "CONFIRM PAYMENT"
        case .executing: return "SENDING"
        case .swapping(let step, let total, _): return "STEP \(step)/\(total)"
        case .confirming: return "CONFIRMING"
        case .success: return "PAID"
        case .failed: return "FAILED"
        case .cancelled: return "CANCELLED"
        default: return ""
        }
    }

    private var paymentSubtitle: String {
        switch viewModel.flowState {
        case .listening: return "Say what to pay"
        case .processing: return "Preparing..."
        case .scanningQR: return "Point at QR"
        case .enteringAmount: return "How much?"
        case .awaitingConfirmation: return "Tap Confirm to send"
        case .executing: return "Approve in wallet app"
        case .swapping(_, _, let description): return description
        case .confirming: return "Waiting for Monad..."
        case .success: return "Payment sent"
        case .failed: return "Tap Done to retry"
        case .cancelled: return "Cancelled"
        default: return ""
        }
    }

    @ViewBuilder
    private var paymentContent: some View {
        switch viewModel.flowState {
        case .enteringAmount(let merchant):
            AmountInputView(
                amountInput: $amountInput,
                merchant: merchant
            )

        case .awaitingConfirmation(let amount, let merchant):
            VStack(spacing: 12) {
                Text(amount)
                    .font(.system(size: 48, weight: .black, design: .monospaced))
                    .foregroundColor(Theme.dark)

                HStack(spacing: 4) {
                    Text("USDC")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.muted)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.muted)
                    Text(merchant.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark)
                }

                // Gas estimate — Monad gas is ultra cheap
                HStack(spacing: 4) {
                    Image(systemName: "fuelpump")
                        .font(.system(size: 9, weight: .medium))
                    Text("GAS: ~$0.001")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                }
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Theme.accent.opacity(0.08))
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)

        case .success(let txHash):
            SuccessCheckmark(txHash: txHash)

        case .failed(let error):
            VStack(spacing: 12) {
                Circle()
                    .fill(Theme.error.opacity(0.15))
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "xmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Theme.error)
                    )

                Text(error)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

        case .swapping(let step, let total, let description):
            VStack(spacing: 12) {
                // Step progress dots
                HStack(spacing: 6) {
                    ForEach(1...total, id: \.self) { i in
                        Circle()
                            .fill(i < step ? Theme.accent : (i == step ? Theme.accent.opacity(0.6) : Theme.border))
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .stroke(i == step ? Theme.accent : Color.clear, lineWidth: 1.5)
                                    .frame(width: 14, height: 14)
                            )
                    }
                }
                .padding(.bottom, 4)

                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                    .scaleEffect(1.2)

                Text(description)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var paymentButtons: some View {
        switch viewModel.flowState {
        case .listening:
            MinimalButton("Cancel", style: .secondary) {
                viewModel.stopListening()
            }

        case .enteringAmount:
            HStack(spacing: 8) {
                MinimalButton("Cancel", style: .secondary) {
                    amountInput = ""
                    viewModel.cancelPayment()
                }
                MinimalButton("Continue", style: .primary) {
                    guard !amountInput.isEmpty else { return }
                    Task {
                        await viewModel.setPaymentAmount(amountInput)
                        amountInput = ""  // Reset for next time
                    }
                }
                .opacity(amountInput.isEmpty ? 0.5 : 1.0)
            }

        case .awaitingConfirmation:
            HStack(spacing: 8) {
                MinimalButton("Cancel", style: .secondary) {
                    viewModel.cancelPayment()
                }
                MinimalButton("Confirm", style: .primary) {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    Task { await viewModel.confirmPayment() }
                }
            }

        case .success, .failed, .cancelled:
            MinimalButton("Done", style: .primary) {
                viewModel.reset()
            }

        default:
            EmptyView()
        }
    }
}

// MARK: - Components (Interfacer brutalist style)

struct MinimalCard<Content: View>: View {
    let content: Content
    var accent: Bool = false
    var highlight: Color? = nil

    init(accent: Bool = false, highlight: Color? = nil, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.highlight = highlight
        self.content = content()
    }

    var body: some View {
        content
            .padding(20)
            .background(highlight ?? (accent ? Theme.accent : Theme.card))
            .clipShape(RoundedRectangle(cornerRadius: 2))  // Brutalist: minimal radius
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.dark.opacity(0.1), lineWidth: 1)
            )
    }
}

enum ButtonStyleType {
    case primary, secondary
}

// MARK: - Amount Input View (Optimized for keyboard performance)

struct AmountInputView: View {
    @Binding var amountInput: String
    let merchant: String
    @FocusState private var isInputFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            // Amount input field
            HStack(alignment: .center, spacing: 4) {
                Text("$")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.muted)

                TextField("0.00", text: $amountInput)
                    .font(.system(size: 48, weight: .black, design: .monospaced))
                    .foregroundColor(Theme.dark)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.leading)
                    .focused($isInputFocused)
                    .frame(maxWidth: .infinity)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            .padding(.horizontal, 8)

            HStack(spacing: 4) {
                Text("USDC")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.muted)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Theme.muted)
                Text(merchant.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.dark)
            }

            // Quick amount buttons
            HStack(spacing: 8) {
                ForEach(["5", "10", "25", "50"], id: \.self) { amount in
                    Button {
                        amountInput = amount
                        isInputFocused = false
                    } label: {
                        Text("$\(amount)")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(amountInput == amount ? Theme.dark : Theme.muted)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(amountInput == amount ? Theme.accent : Theme.border.opacity(0.5))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .onAppear {
            // Auto-focus the input field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isInputFocused = true
            }
        }
    }
}

// MARK: - Token Row Component

struct TokenRow: View {
    let token: TokenDisplayInfo

    var body: some View {
        HStack(spacing: 12) {
            // Token icon with colored background
            ZStack {
                Circle()
                    .fill(Color(hex: token.color).opacity(0.15))
                    .frame(width: 32, height: 32)

                Image(systemName: token.icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: token.color))
            }

            // Token symbol
            Text(token.symbol)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.dark)

            Spacer()

            // Balance
            Text(token.balance)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(Theme.dark.opacity(0.7))
        }
        .padding(.vertical, 4)
    }
}

struct MinimalButton: View {
    let title: String
    let style: ButtonStyleType
    let action: () -> Void

    init(_ title: String, style: ButtonStyleType = .primary, action: @escaping () -> Void) {
        self.title = title
        self.style = style
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundColor(style == .primary ? Theme.dark : Theme.dark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(style == .primary ? Theme.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 2))  // Brutalist: sharp edges
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Theme.dark, lineWidth: style == .primary ? 0 : 1)
                )
        }
    }
}

// MARK: - Pulsing Dot Animation

struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.3))
                .frame(width: 16, height: 16)
                .scaleEffect(isPulsing ? 1.0 : 0.5)
                .opacity(isPulsing ? 0 : 0.8)

            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Success Checkmark Animation

struct SuccessCheckmark: View {
    let txHash: String
    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0

    var body: some View {
        VStack(spacing: 12) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Theme.dark)
                )
                .scaleEffect(scale)

            if txHash != "pending" {
                Text("TX: \(txHash.prefix(8))...")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.muted)
                    .opacity(opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
                scale = 1.0
            }
            withAnimation(.easeIn(duration: 0.3).delay(0.2)) {
                opacity = 1.0
            }
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}

// MARK: - Phone Camera Scanner View (Fallback)

struct PhoneCameraScannerView: View {
    @ObservedObject var viewModel: VoiceSwapViewModel
    let onDismiss: () -> Void
    @State private var scannedCode: String?
    @State private var isScanning = true

    var body: some View {
        NavigationView {
            ZStack {
                // Camera view
                if isScanning {
                    QRCodeScannerView { code in
                        scannedCode = code
                        isScanning = false
                        handleScannedCode(code)
                    }
                    .ignoresSafeArea()
                }

                // Overlay
                VStack {
                    Spacer()

                    VStack(spacing: 16) {
                        if let code = scannedCode {
                            // Success state
                            VStack(spacing: 12) {
                                Circle()
                                    .fill(Theme.accent)
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 24, weight: .bold))
                                            .foregroundColor(Theme.dark)
                                    )

                                Text("QR Code Scanned!")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)

                                Text(code.prefix(40) + (code.count > 40 ? "..." : ""))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.7))
                                    .multilineTextAlignment(.center)
                            }
                            .padding(24)
                            .background(Color.black.opacity(0.8))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            // Scanning instructions
                            VStack(spacing: 8) {
                                Text("SCAN QR CODE")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white)

                                Text("Point camera at merchant's payment QR")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white.opacity(0.7))
                            }
                            .padding(16)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundColor(.white)
                }

                ToolbarItem(placement: .principal) {
                    Text("Phone Camera")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
    }

    private func handleScannedCode(_ code: String) {
        // Parse and handle the QR code
        Task {
            await viewModel.handleQRScan(code)
            // Small delay to show success state
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            onDismiss()
        }
    }
}

// MARK: - QR Code Scanner View (AVFoundation)

import AVFoundation

struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.onCodeScanned = onCodeScanned
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var onCodeScanned: ((String) -> Void)?
    private var hasScanned = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else {
            showCameraError()
            return
        }

        // Optimize camera for QR scanning
        do {
            try videoCaptureDevice.lockForConfiguration()
            // Enable auto-focus for faster QR detection
            if videoCaptureDevice.isFocusModeSupported(.continuousAutoFocus) {
                videoCaptureDevice.focusMode = .continuousAutoFocus
            }
            // Enable auto-exposure
            if videoCaptureDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoCaptureDevice.exposureMode = .continuousAutoExposure
            }
            videoCaptureDevice.unlockForConfiguration()
        } catch {
            print("[QRScanner] Failed to configure camera: \(error)")
        }

        let videoInput: AVCaptureDeviceInput
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            showCameraError()
            return
        }

        captureSession = AVCaptureSession()
        captureSession?.sessionPreset = .high  // Better quality for QR detection

        guard let captureSession = captureSession else { return }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            showCameraError()
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            showCameraError()
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer!.frame = view.layer.bounds
        previewLayer!.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer!)

        // Add scanning frame overlay
        addScanningOverlay()

        // Set scanning region to center of screen for faster detection
        DispatchQueue.main.async {
            let frameSize = min(self.view.bounds.width, self.view.bounds.height) * 0.7
            let scanRect = CGRect(
                x: (self.view.bounds.width - frameSize) / 2,
                y: (self.view.bounds.height - frameSize) / 2,
                width: frameSize,
                height: frameSize
            )
            // Convert to metadata output coordinates (normalized, rotated)
            if let previewLayer = self.previewLayer {
                metadataOutput.rectOfInterest = previewLayer.metadataOutputRectConverted(fromLayerRect: scanRect)
            }
        }

        DispatchQueue.global(qos: .userInteractive).async {
            captureSession.startRunning()
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        previewLayer?.frame = view.layer.bounds
    }

    private func addScanningOverlay() {
        let overlayView = UIView(frame: view.bounds)
        overlayView.backgroundColor = .clear

        // Create scanning frame
        let frameSize: CGFloat = min(view.bounds.width, view.bounds.height) * 0.7
        let frameRect = CGRect(
            x: (view.bounds.width - frameSize) / 2,
            y: (view.bounds.height - frameSize) / 2,
            width: frameSize,
            height: frameSize
        )

        // Create mask with hole
        let path = UIBezierPath(rect: view.bounds)
        let scanPath = UIBezierPath(roundedRect: frameRect, cornerRadius: 16)
        path.append(scanPath)
        path.usesEvenOddFillRule = true

        let maskLayer = CAShapeLayer()
        maskLayer.path = path.cgPath
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.5).cgColor

        overlayView.layer.addSublayer(maskLayer)

        // Add corner brackets - Monad purple (#836EF9)
        let bracketColor = UIColor(red: 131/255, green: 110/255, blue: 249/255, alpha: 1)
        let bracketLength: CGFloat = 30
        let bracketWidth: CGFloat = 4

        // Top-left
        let topLeft = UIView()
        topLeft.backgroundColor = bracketColor
        topLeft.frame = CGRect(x: frameRect.minX, y: frameRect.minY, width: bracketLength, height: bracketWidth)
        overlayView.addSubview(topLeft)

        let topLeftV = UIView()
        topLeftV.backgroundColor = bracketColor
        topLeftV.frame = CGRect(x: frameRect.minX, y: frameRect.minY, width: bracketWidth, height: bracketLength)
        overlayView.addSubview(topLeftV)

        // Top-right
        let topRight = UIView()
        topRight.backgroundColor = bracketColor
        topRight.frame = CGRect(x: frameRect.maxX - bracketLength, y: frameRect.minY, width: bracketLength, height: bracketWidth)
        overlayView.addSubview(topRight)

        let topRightV = UIView()
        topRightV.backgroundColor = bracketColor
        topRightV.frame = CGRect(x: frameRect.maxX - bracketWidth, y: frameRect.minY, width: bracketWidth, height: bracketLength)
        overlayView.addSubview(topRightV)

        // Bottom-left
        let bottomLeft = UIView()
        bottomLeft.backgroundColor = bracketColor
        bottomLeft.frame = CGRect(x: frameRect.minX, y: frameRect.maxY - bracketWidth, width: bracketLength, height: bracketWidth)
        overlayView.addSubview(bottomLeft)

        let bottomLeftV = UIView()
        bottomLeftV.backgroundColor = bracketColor
        bottomLeftV.frame = CGRect(x: frameRect.minX, y: frameRect.maxY - bracketLength, width: bracketWidth, height: bracketLength)
        overlayView.addSubview(bottomLeftV)

        // Bottom-right
        let bottomRight = UIView()
        bottomRight.backgroundColor = bracketColor
        bottomRight.frame = CGRect(x: frameRect.maxX - bracketLength, y: frameRect.maxY - bracketWidth, width: bracketLength, height: bracketWidth)
        overlayView.addSubview(bottomRight)

        let bottomRightV = UIView()
        bottomRightV.backgroundColor = bracketColor
        bottomRightV.frame = CGRect(x: frameRect.maxX - bracketWidth, y: frameRect.maxY - bracketLength, width: bracketWidth, height: bracketLength)
        overlayView.addSubview(bottomRightV)

        view.addSubview(overlayView)
    }

    private func showCameraError() {
        let label = UILabel()
        label.text = "Camera not available"
        label.textColor = .white
        label.textAlignment = .center
        label.frame = view.bounds
        view.addSubview(label)
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !hasScanned else { return }

        if let metadataObject = metadataObjects.first,
           let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject,
           let stringValue = readableObject.stringValue {

            hasScanned = true
            // Vibrate on successful scan
            let vibrate: SystemSoundID = kSystemSoundID_Vibrate
            AudioServicesPlaySystemSound(vibrate)
            captureSession?.stopRunning()
            onCodeScanned?(stringValue)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
}

// MARK: - Security Settings Sheet

struct SecuritySettingsSheet: View {
    @ObservedObject private var settings = SecuritySettings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    faceIDSection
                    dailyLimitSection
                    whitelistSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SECURITY")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Theme.dark)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }

    // MARK: - Face ID Section

    private var faceIDSection: some View {
        MinimalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "faceid")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Theme.accent)

                    Text("FACE ID")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark.opacity(0.5))
                        .tracking(1)

                    Spacer()
                }

                // Face ID on app launch
                HStack {
                    Text("Require on app launch")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.dark)

                    Spacer()

                    Toggle("", isOn: $settings.faceIDOnLaunchEnabled)
                        .tint(Theme.accent)
                        .labelsHidden()
                }

                Divider().background(Theme.divider)

                // Face ID every 3 payments
                HStack {
                    Text("Require every \(SecuritySettings.faceIDThreshold) payments")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.dark)

                    Spacer()

                    Toggle("", isOn: $settings.faceIDEnabled)
                        .tint(Theme.accent)
                        .labelsHidden()
                }

                if settings.faceIDEnabled {
                    HStack(spacing: 4) {
                        ForEach(0..<SecuritySettings.faceIDThreshold, id: \.self) { i in
                            Circle()
                                .fill(i < settings.transactionCount ? Theme.accent : Theme.border)
                                .frame(width: 8, height: 8)
                        }
                        Text("\(settings.transactionCount)/\(SecuritySettings.faceIDThreshold)")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.muted)
                            .padding(.leading, 4)
                    }
                }
            }
        }
    }

    // MARK: - Daily Limit Section

    private var dailyLimitSection: some View {
        MinimalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "banknote")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Theme.accent)

                    Text("DAILY LIMIT")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark.opacity(0.5))
                        .tracking(1)

                    Spacer()

                    Toggle("", isOn: $settings.dailyLimitEnabled)
                        .tint(Theme.accent)
                        .labelsHidden()
                }

                Text("Max $\(String(format: "%.0f", settings.dailyLimitAmount)) USDC per day")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.dark)

                if settings.dailyLimitEnabled {
                    // Preset buttons
                    HStack(spacing: 8) {
                        ForEach([100.0, 250.0, 500.0, 1000.0], id: \.self) { amount in
                            Button {
                                settings.dailyLimitAmount = amount
                            } label: {
                                Text("$\(String(format: "%.0f", amount))")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(settings.dailyLimitAmount == amount ? .white : Theme.dark)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(settings.dailyLimitAmount == amount ? Theme.accent : Theme.bg)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(Theme.border, lineWidth: 1)
                                    )
                            }
                        }
                    }

                    // Spent today progress
                    VStack(alignment: .leading, spacing: 4) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Theme.border)
                                    .frame(height: 4)

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(spentRatio > 0.8 ? Theme.error : Theme.accent)
                                    .frame(width: geo.size.width * min(spentRatio, 1.0), height: 4)
                            }
                        }
                        .frame(height: 4)

                        Text("Spent today: $\(String(format: "%.2f", settings.dailySpentAmount)) / $\(String(format: "%.0f", settings.dailyLimitAmount))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.muted)
                    }
                }
            }
        }
    }

    private var spentRatio: Double {
        guard settings.dailyLimitAmount > 0 else { return 0 }
        return settings.dailySpentAmount / settings.dailyLimitAmount
    }

    // MARK: - Whitelist Section

    private var whitelistSection: some View {
        MinimalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "person.badge.shield.checkmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Theme.accent)

                    Text("MERCHANT WHITELIST")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark.opacity(0.5))
                        .tracking(1)

                    Spacer()

                    Toggle("", isOn: $settings.whitelistEnabled)
                        .tint(Theme.accent)
                        .labelsHidden()
                }

                Text("Approve new merchants before paying")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.dark)

                if settings.whitelistEnabled {
                    if settings.approvedMerchants.isEmpty {
                        Text("No approved merchants yet. You'll be asked to approve each new merchant on first payment.")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Theme.muted)
                            .padding(.top, 4)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(settings.approvedMerchants, id: \.self) { address in
                                HStack {
                                    Circle()
                                        .fill(Theme.accent.opacity(0.2))
                                        .frame(width: 24, height: 24)
                                        .overlay(
                                            Text(String(address.dropFirst(2).prefix(2)).uppercased())
                                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                                .foregroundColor(Theme.accent)
                                        )

                                    Text("\(address.prefix(6))...\(address.suffix(4))")
                                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                                        .foregroundColor(Theme.dark)

                                    Spacer()

                                    Button {
                                        settings.removeMerchant(address)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(Theme.error.opacity(0.7))
                                    }
                                }
                                .padding(.vertical, 8)

                                if address != settings.approvedMerchants.last {
                                    Divider()
                                        .background(Theme.divider)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Receive QR Sheet

struct ReceiveQRSheet: View {
    let walletAddress: String
    @Environment(\.dismiss) private var dismiss
    @State private var amount: String = ""
    @State private var merchantName: String = ""

    private var qrString: String {
        var params = "wallet=\(walletAddress)"
        if !amount.isEmpty { params += "&amount=\(amount)" }
        if !merchantName.isEmpty {
            params += "&name=\(merchantName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? merchantName)"
        }
        return "voiceswap://pay?\(params)"
    }

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    // QR Code
                    if let qrImage = generateQRCode(from: qrString) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 220, height: 220)
                            .padding(20)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Theme.dark.opacity(0.1), lineWidth: 1)
                            )
                    }

                    // Address
                    VStack(spacing: 4) {
                        Text("YOUR ADDRESS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.muted)
                            .tracking(1)

                        Text(walletAddress)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.dark)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }

                    // Optional fields
                    MinimalCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("OPTIONAL")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.muted)
                                .tracking(1)

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Amount (USDC)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(Theme.dark)

                                TextField("0.00", text: $amount)
                                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                                    .keyboardType(.decimalPad)
                                    .padding(12)
                                    .background(Theme.bg)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(Theme.border, lineWidth: 1)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Your Name / Store")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(Theme.dark)

                                TextField("e.g. Coffee Shop", text: $merchantName)
                                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                                    .padding(12)
                                    .background(Theme.bg)
                                    .clipShape(RoundedRectangle(cornerRadius: 2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 2)
                                            .stroke(Theme.border, lineWidth: 1)
                                    )
                            }
                        }
                    }

                    // Share button
                    Button {
                        UIPasteboard.general.string = qrString
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12, weight: .bold))
                            Text("COPY LINK")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundColor(Theme.dark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("RECEIVE")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Theme.dark)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.accent)
                }
            }
        }
    }

    private func generateQRCode(from string: String) -> UIImage? {
        guard let data = string.data(using: .ascii),
              let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")

        guard let ciImage = filter.outputImage else { return nil }
        let scale = 10.0
        let transformed = ciImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return UIImage(ciImage: transformed)
    }
}

// MARK: - Transaction History Sheet

struct TransactionHistorySheet: View {
    let walletAddress: String
    @Environment(\.dismiss) private var dismiss
    @State private var payments: [UserPayment] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    VStack(spacing: 16) {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.accent))
                        Text("Loading...")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.muted)
                        Spacer()
                    }
                } else if let error = error {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(Theme.muted)
                        Text(error)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.muted)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .padding(.horizontal, 24)
                } else if payments.isEmpty {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "tray")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(Theme.border)
                        Text("No payments yet")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.muted)
                        Text("Your payment history will appear here")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.border)
                        Spacer()
                    }
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 0) {
                            ForEach(payments) { payment in
                                PaymentHistoryRow(payment: payment)

                                if payment.id != payments.last?.id {
                                    Divider()
                                        .background(Theme.divider)
                                        .padding(.horizontal, 24)
                                }
                            }
                        }
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                }
            }
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("HISTORY")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Theme.dark)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.accent)
                }
            }
        }
        .task {
            await loadPayments()
        }
    }

    private func loadPayments() async {
        guard !walletAddress.isEmpty else {
            isLoading = false
            error = "Wallet not connected"
            return
        }

        do {
            let response = try await VoiceSwapAPIClient.shared.getUserPayments(address: walletAddress)
            if let data = response.data {
                payments = data.payments
            } else {
                error = response.error ?? "No data"
            }
        } catch {
            self.error = "Failed to load: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

struct PaymentHistoryRow: View {
    let payment: UserPayment

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: payment.date)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.12))
                    .frame(width: 40, height: 40)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(Theme.accent)
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(payment.concept?.uppercased() ?? "PAYMENT")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.dark)
                    .lineLimit(1)

                Text("To \(payment.merchant_name ?? payment.merchantShort)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.muted)
            }

            Spacer()

            // Amount + date
            VStack(alignment: .trailing, spacing: 4) {
                Text("-$\(payment.amount)")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .foregroundColor(Theme.dark)

                Text(formattedDate)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.muted)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

// MARK: - Preview

struct VoiceSwapMainView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceSwapMainView()
    }
}
