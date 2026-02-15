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
    @State private var amountInput: String = ""
    @State private var showSecuritySettings = false
    @State private var showTransactionHistory = false
    @State private var showReceiveQR = false
    @State private var showWalletSetup = false
    @State private var showFundWallet = false
    @State private var showSendSheet = false
    @State private var addressCopied = false
    @State private var pendingFundAfterConnect = false
    @ObservedObject private var localWallet = VoiceSwapWallet.shared

    public init() {}

    @ObservedObject private var securitySettings = SecuritySettings.shared

    public var body: some View {
        ZStack {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                headerView
                    .padding(.bottom, 12)

                if walletManager.isConnected || localWallet.isCreated {
                    // --- Connected (WalletConnect or VoiceSwap Wallet): status + balance + PAY ---
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

                    // Fund + Send buttons (always visible when instant wallet exists)
                    if localWallet.isCreated {
                        HStack(spacing: 8) {
                            Button {
                                showWalletSetup = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("FUND")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .tracking(1)
                                }
                                .foregroundColor(Theme.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Theme.accent.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                                )
                            }

                            Button {
                                showSendSheet = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 12, weight: .bold))
                                    Text("SEND")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .tracking(1)
                                }
                                .foregroundColor(Color(hex: "836EF9"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color(hex: "836EF9").opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(Color(hex: "836EF9").opacity(0.3), lineWidth: 1)
                                )
                            }
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
            .animation(.easeInOut(duration: 0.25), value: walletManager.isConnected || localWallet.isCreated)
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.flowState)
            .animation(.easeInOut(duration: 0.25), value: glassesManager.isStreaming)
            .animation(.easeInOut(duration: 0.25), value: geminiSession.isSessionActive)
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.light)
        .task {
            // Priority: VoiceSwap Wallet > WalletConnect
            if localWallet.isCreated {
                viewModel.setWalletAddress(localWallet.address)
            } else if let address = walletManager.currentAddress {
                viewModel.setWalletAddress(address)
            }

            // Wire Gemini session to ViewModel
            viewModel.setupGeminiSession(geminiSession)

            // Pre-connect to Gemini so voice activation is instant
            if localWallet.isCreated || walletManager.isConnected {
                geminiSession.preconnect()
            }
        }
        .onChange(of: walletManager.connectionState) { state in
            if case .connected(let address) = state {
                // Only use MetaMask address if Instant Wallet is NOT created
                // Instant Wallet is the primary wallet for balance + payments
                if !localWallet.isCreated {
                    viewModel.setWalletAddress(address)
                }
                // Pre-connect to Gemini when wallet connects
                geminiSession.preconnect()
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
        .sheet(isPresented: $showSecuritySettings) {
            SecuritySettingsSheet()
        }
        .sheet(isPresented: $showTransactionHistory) {
            TransactionHistorySheet(walletAddress: localWallet.isCreated ? localWallet.address : (walletManager.currentAddress ?? ""))
        }
        .sheet(isPresented: $showReceiveQR) {
            ReceiveQRSheet(walletAddress: localWallet.isCreated ? localWallet.address : (walletManager.currentAddress ?? ""))
        }
        .sheet(isPresented: $showWalletSetup) {
            WalletSetupView(
                onComplete: {
                    showWalletSetup = false
                    if localWallet.isCreated {
                        viewModel.setWalletAddress(localWallet.address)
                    }
                },
                onConnectAndFund: {
                    // Dismiss deposit sheet first, then open AppKit wallet picker
                    showWalletSetup = false
                    pendingFundAfterConnect = true
                    // Longer delay to ensure sheet is fully dismissed before presenting AppKit
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        walletManager.connect()
                    }
                }
            )
        }
        .sheet(isPresented: $showFundWallet) {
            FundWalletSheet(
                walletAddress: localWallet.address,
                walletConnect: walletManager
            )
        }
        .sheet(isPresented: $showSendSheet) {
            SendSheet(viewModel: viewModel)
        }
        .onChange(of: walletManager.isConnected) { connected in
            if connected && pendingFundAfterConnect {
                pendingFundAfterConnect = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showFundWallet = true
                }
            }
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
        if geminiSession.geminiService.connectionState == .ready { return "Ready" }
        return "Tap to start"
    }

    private var setupStatusRow: some View {
        HStack(spacing: 0) {
            // Wallet indicator — tap to copy address
            setupIndicator(
                label: localWallet.isCreated
                    ? (addressCopied ? "COPIED" : "INSTANT")
                    : "WALLET",
                detail: localWallet.isCreated
                    ? String(localWallet.address.prefix(6)) + "..." + String(localWallet.address.suffix(4))
                    : walletManager.shortAddress,
                isActive: true,
                icon: localWallet.isCreated
                    ? (addressCopied ? "checkmark" : "bolt.fill")
                    : "checkmark"
            ) {
                if localWallet.isCreated {
                    UIPasteboard.general.string = localWallet.address
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    addressCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { addressCopied = false }
                } else {
                    walletManager.disconnect()
                }
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
                isActive: geminiSession.isSessionActive || geminiSession.geminiService.connectionState == .ready,
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

    @State private var showWalletCreation = false
    @State private var showImportWallet = false
    @State private var importKeyText = ""
    @State private var importError: String?

    private var connectWalletPrompt: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 60)

            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: 96, height: 96)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 42, weight: .medium))
                    .foregroundColor(Theme.accent)
            }

            VStack(spacing: 8) {
                Text("Start paying\nwith your voice")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.dark)
                    .multilineTextAlignment(.center)

                Text("Zero friction. Say it, done.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.muted)
            }

            Spacer().frame(height: 8)

            Button {
                showWalletCreation = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("GET STARTED")
                        .font(.system(size: 15, weight: .black, design: .monospaced))
                        .tracking(2)
                }
                .foregroundColor(Theme.dark)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
                .background(Theme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 2))
            }

            Text("Creates an instant wallet on your device")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Theme.muted)

            Button {
                showImportWallet = true
            } label: {
                Text("IMPORT EXISTING WALLET")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.muted)
                    .tracking(1)
            }
        }
        .fullScreenCover(isPresented: $showWalletCreation) {
            WalletCreationFlowView {
                showWalletCreation = false
                if localWallet.isCreated {
                    viewModel.setWalletAddress(localWallet.address)
                    // Show deposit options after creation flow
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showWalletSetup = true
                    }
                }
            }
        }
        .sheet(isPresented: $showImportWallet) {
            ImportWalletSheet(
                importKeyText: $importKeyText,
                importError: $importError
            ) {
                // On success
                showImportWallet = false
                if localWallet.isCreated {
                    viewModel.setWalletAddress(localWallet.address)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showWalletSetup = true
                    }
                }
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
            if geminiSession.isSessionActive {
                // Voice mode — Gemini handles confirmation, show tap-to-confirm as fallback
                HStack(spacing: 8) {
                    MinimalButton("CANCEL", style: .secondary) {
                        viewModel.cancelPayment()
                    }
                    MinimalButton("CONFIRM", style: .primary) {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        Task { await viewModel.confirmPayment() }
                    }
                }
                Text("Tap Confirm to send")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.muted)
            } else {
                HStack(spacing: 8) {
                    MinimalButton("CANCEL", style: .secondary) {
                        viewModel.cancelPayment()
                    }
                    MinimalButton("CONFIRM", style: .primary) {
                        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                        Task { await viewModel.confirmPayment() }
                    }
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

// MARK: - Wallet Creation Flow (Animated)

struct WalletCreationFlowView: View {
    @ObservedObject private var wallet = VoiceSwapWallet.shared
    @State private var phase: CreationPhase = .creating
    @State private var spinnerRotation: Double = 0
    @State private var checkScale: CGFloat = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 0
    @State private var showParticles = false
    @State private var textOpacity: Double = 0
    @State private var backupButtonOpacity: Double = 0
    @State private var isBackingUp = false
    @State private var backupDone = false
    @State private var showPrivateKey = false
    @State private var keyCopied = false
    @State private var creationError: String?

    let onComplete: () -> Void

    enum CreationPhase {
        case creating
        case success
        case backup
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip / close button
                HStack {
                    Spacer()
                    if phase == .backup {
                        Button {
                            onComplete()
                        } label: {
                            Text("SKIP")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.muted)
                                .tracking(1)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .frame(height: 44)

                Spacer()

                // Main content
                switch phase {
                case .creating:
                    creatingView
                case .success:
                    successView
                case .backup:
                    backupView
                }

                Spacer()
                Spacer()
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            startCreation()
        }
    }

    // MARK: - Creating Phase

    private var creatingView: some View {
        VStack(spacing: 32) {
            // Animated spinner
            ZStack {
                // Outer ring
                Circle()
                    .stroke(Theme.border, lineWidth: 3)
                    .frame(width: 100, height: 100)

                // Spinning arc
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .frame(width: 100, height: 100)
                    .rotationEffect(.degrees(spinnerRotation))

                Image(systemName: "bolt.fill")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundColor(Theme.accent)
            }

            VStack(spacing: 8) {
                Text("Creating your wallet")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(Theme.dark)

                Text("Generating secure keys...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Theme.muted)
            }

            if let error = creationError {
                Text(error)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.error)
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                spinnerRotation = 360
            }
        }
    }

    // MARK: - Success Phase

    private var successView: some View {
        VStack(spacing: 24) {
            ZStack {
                // Expanding ring
                Circle()
                    .stroke(Theme.accent.opacity(ringOpacity), lineWidth: 2)
                    .frame(width: 100, height: 100)
                    .scaleEffect(ringScale)

                // Particles
                if showParticles {
                    ForEach(0..<12, id: \.self) { i in
                        CreationParticle(index: i)
                    }
                }

                // Checkmark circle
                ZStack {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 100, height: 100)
                    Image(systemName: "checkmark")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(Theme.dark)
                }
                .scaleEffect(checkScale)
                .shadow(color: Theme.accent.opacity(0.3), radius: 20, x: 0, y: 8)
            }
            .frame(width: 140, height: 140)

            VStack(spacing: 8) {
                Text("Wallet Created!")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(Theme.dark)

                if wallet.isCreated {
                    Text(shortAddress)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.muted)
                }
            }
            .opacity(textOpacity)
        }
    }

    // MARK: - Backup Phase

    private var backupView: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                // Warning icon
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.1))
                        .frame(width: 100, height: 100)
                    Image(systemName: "exclamationmark.shield.fill")
                        .font(.system(size: 40, weight: .medium))
                        .foregroundColor(.red)
                }

                // Warning text
                VStack(spacing: 8) {
                    Text("Save your private key")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(Theme.dark)

                    Text("This is the ONLY way to recover\nyour wallet. Save it now.")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                }

                // Warning box
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.red)
                    Text("If you lose this key and don't have iCloud backup, your funds will be lost forever.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.dark)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 24)

                // Private key reveal
                VStack(spacing: 12) {
                    if showPrivateKey, let key = wallet.exportPrivateKey() {
                        VStack(spacing: 8) {
                            Text("YOUR PRIVATE KEY")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.muted)
                                .tracking(2)

                            Text(key)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(Theme.dark)
                                .multilineTextAlignment(.center)
                                .padding(14)
                                .frame(maxWidth: .infinity)
                                .background(Color(hex: "F5F5F5"))
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            Button {
                                UIPasteboard.general.string = key
                                keyCopied = true
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { keyCopied = false }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: keyCopied ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 12, weight: .bold))
                                    Text(keyCopied ? "COPIED" : "COPY KEY")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .tracking(1)
                                }
                                .foregroundColor(keyCopied ? Theme.accent : Theme.dark)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(keyCopied ? Theme.accent.opacity(0.1) : Color(hex: "F5F5F5"))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }

                            Text("Store this in a password manager\nor write it down somewhere safe")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Theme.muted)
                                .multilineTextAlignment(.center)
                        }
                    } else {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                showPrivateKey = true
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "key.fill")
                                    .font(.system(size: 14, weight: .bold))
                                Text("REVEAL PRIVATE KEY")
                                    .font(.system(size: 13, weight: .black, design: .monospaced))
                                    .tracking(1)
                            }
                            .foregroundColor(Theme.dark)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Color(hex: "F5F5F5"))
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)

                // Divider with "or"
                HStack(spacing: 12) {
                    Rectangle().fill(Theme.border).frame(height: 1)
                    Text("or")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Theme.muted)
                    Rectangle().fill(Theme.border).frame(height: 1)
                }
                .padding(.horizontal, 24)

                VStack(spacing: 12) {
                    if backupDone {
                        // Success state
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(Theme.accent)
                            Text("Backed up to iCloud")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.accent)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(Theme.accent.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                        Button {
                            onComplete()
                        } label: {
                            Text("CONTINUE")
                                .font(.system(size: 15, weight: .black, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(Theme.dark)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                                .background(Theme.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                    } else {
                        // iCloud backup button
                        Button {
                            backupToiCloud()
                        } label: {
                            HStack(spacing: 10) {
                                if isBackingUp {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.dark))
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "icloud.and.arrow.up")
                                        .font(.system(size: 16, weight: .bold))
                                }
                                Text("BACK UP TO ICLOUD")
                                    .font(.system(size: 14, weight: .black, design: .monospaced))
                                    .tracking(1)
                            }
                            .foregroundColor(Theme.dark)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                            .background(Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                        }
                        .disabled(isBackingUp)

                        // Skip option (less prominent)
                        Button {
                            onComplete()
                        } label: {
                            Text("I'LL DO IT LATER")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(Theme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .opacity(backupButtonOpacity)

                Spacer(minLength: 40)
            }
            .padding(.top, 16)
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.4)) {
                backupButtonOpacity = 1
            }
        }
    }

    // MARK: - Actions

    private func startCreation() {
        // Simulate slight delay for the animation to register
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            do {
                try wallet.create()
                transitionToSuccess()
            } catch {
                creationError = error.localizedDescription
            }
        }
    }

    private func transitionToSuccess() {
        withAnimation(.easeInOut(duration: 0.3)) {
            phase = .success
        }

        // Haptic
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Checkmark bounce
        withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) {
            checkScale = 1.0
        }

        // Ring burst
        withAnimation(.easeOut(duration: 0.6)) {
            ringScale = 2.5
            ringOpacity = 0.6
        }
        withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
            ringOpacity = 0
        }

        // Particles
        withAnimation(.easeOut(duration: 0.1)) {
            showParticles = true
        }

        // Text fade in
        withAnimation(.easeIn(duration: 0.3).delay(0.3)) {
            textOpacity = 1.0
        }

        // Second haptic
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }

        // Transition to backup after a moment
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.4)) {
                phase = .backup
            }
        }
    }

    private func backupToiCloud() {
        isBackingUp = true
        do {
            try wallet.enableiCloudBackup()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isBackingUp = false
                backupDone = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            isBackingUp = false
            NSLog("[WalletCreation] iCloud backup failed: %@", error.localizedDescription)
        }
    }

    private var shortAddress: String {
        let addr = wallet.address
        guard addr.count > 10 else { return addr }
        return String(addr.prefix(6)) + "..." + String(addr.suffix(4))
    }
}

// MARK: - Creation Particle

struct CreationParticle: View {
    let index: Int
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1

    private var angle: Double {
        Double(index) * (360.0 / 12.0)
    }

    var body: some View {
        Circle()
            .fill(index % 3 == 0 ? Theme.accent : (index % 3 == 1 ? Theme.accent.opacity(0.6) : Color(hex: "836EF9").opacity(0.4)))
            .frame(width: index % 2 == 0 ? 8 : 5, height: index % 2 == 0 ? 8 : 5)
            .offset(
                x: offset * CGFloat(cos(angle * .pi / 180)),
                y: offset * CGFloat(sin(angle * .pi / 180))
            )
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.6)) {
                    offset = CGFloat.random(in: 40...65)
                }
                withAnimation(.easeOut(duration: 0.6).delay(0.25)) {
                    opacity = 0
                }
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

// MARK: - Success Checkmark Animation (Enhanced with particles)

struct SuccessCheckmark: View {
    let txHash: String
    @State private var scale: CGFloat = 0.3
    @State private var opacity: Double = 0
    @State private var ringScale: CGFloat = 0.5
    @State private var ringOpacity: Double = 0
    @State private var showParticles = false

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Expanding ring burst
                Circle()
                    .stroke(Theme.accent.opacity(ringOpacity), lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .scaleEffect(ringScale)

                // Particle burst
                if showParticles {
                    ForEach(0..<8, id: \.self) { i in
                        PaymentParticle(index: i)
                    }
                }

                // Main checkmark circle
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Theme.dark)
                    )
                    .scaleEffect(scale)
                    .shadow(color: Theme.accent.opacity(0.4), radius: 12, x: 0, y: 4)
            }
            .frame(width: 100, height: 100)

            if txHash != "pending" {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 6, height: 6)
                    Text("TX: \(txHash.prefix(10))...")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.muted)
                }
                .opacity(opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .onAppear {
            // Haptic burst
            UINotificationFeedbackGenerator().notificationOccurred(.success)

            // Play system success sound
            AudioServicesPlaySystemSound(1025) // subtle "tweet" sound

            // Main checkmark spring
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                scale = 1.0
            }

            // Ring burst
            withAnimation(.easeOut(duration: 0.6)) {
                ringScale = 2.0
                ringOpacity = 0.6
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                ringOpacity = 0
            }

            // Particles
            withAnimation(.easeOut(duration: 0.1)) {
                showParticles = true
            }

            // TX hash fade in
            withAnimation(.easeIn(duration: 0.3).delay(0.4)) {
                opacity = 1.0
            }

            // Second haptic for emphasis
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
}

// MARK: - Payment Particle (burst effect)

struct PaymentParticle: View {
    let index: Int
    @State private var offset: CGFloat = 0
    @State private var opacity: Double = 1

    private var angle: Double {
        Double(index) * (360.0 / 8.0)
    }

    var body: some View {
        Circle()
            .fill(index % 2 == 0 ? Theme.accent : Theme.accent.opacity(0.6))
            .frame(width: index % 2 == 0 ? 6 : 4, height: index % 2 == 0 ? 6 : 4)
            .offset(
                x: offset * CGFloat(cos(angle * .pi / 180)),
                y: offset * CGFloat(sin(angle * .pi / 180))
            )
            .opacity(opacity)
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    offset = CGFloat.random(in: 30...50)
                }
                withAnimation(.easeOut(duration: 0.5).delay(0.2)) {
                    opacity = 0
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

// MARK: - Send QR Scanner Sheet

struct SendQRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onAddressScanned: (String) -> Void

    var body: some View {
        NavigationView {
            ZStack {
                QRCodeScannerView { code in
                    // Extract wallet address from scanned code
                    if let address = extractAddress(from: code) {
                        onAddressScanned(address)
                    }
                }
                .ignoresSafeArea()

                // Overlay with scan frame
                VStack {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white)
                        Text("SCAN WALLET ADDRESS")
                            .font(.system(size: 11, weight: .black, design: .monospaced))
                            .foregroundColor(.white)
                            .tracking(2)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 60)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
        }
    }

    /// Extract an Ethereum address from a scanned QR code.
    /// Supports: plain address, ethereum: URI, voiceswap URLs, or any string containing 0x + 40 hex chars.
    private func extractAddress(from code: String) -> String? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)

        // Plain 0x address
        if trimmed.hasPrefix("0x") && trimmed.count == 42 {
            return trimmed
        }

        // ethereum:0x... URI
        if trimmed.lowercased().hasPrefix("ethereum:") {
            let after = String(trimmed.dropFirst("ethereum:".count))
            let addr = after.components(separatedBy: CharacterSet(charactersIn: "?@/")).first ?? ""
            if addr.hasPrefix("0x") && addr.count == 42 { return addr }
        }

        // URL with wallet param (voiceswap://pay?wallet=0x...)
        if let url = URL(string: trimmed),
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            // Check query params for wallet/address
            if let wallet = components.queryItems?.first(where: { $0.name == "wallet" || $0.name == "address" })?.value,
               wallet.hasPrefix("0x") && wallet.count == 42 {
                return wallet
            }
            // Check path for /pay/0x...
            let path = components.path
            if path.hasPrefix("/pay/") {
                let addr = String(path.dropFirst("/pay/".count))
                if addr.hasPrefix("0x") && addr.count == 42 { return addr }
            }
        }

        // Fallback: find 0x + 40 hex chars anywhere in the string
        if let range = trimmed.range(of: "0x[0-9a-fA-F]{40}", options: .regularExpression) {
            return String(trimmed[range])
        }

        return nil
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

// MARK: - Import Wallet Sheet

struct ImportWalletSheet: View {
    @ObservedObject private var wallet = VoiceSwapWallet.shared
    @Binding var importKeyText: String
    @Binding var importError: String?
    @Environment(\.dismiss) var dismiss
    var onSuccess: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.muted)
                }
                Spacer()
                Text("IMPORT")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.muted)
                    .tracking(2)
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.clear)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 24)

            VStack(spacing: 20) {
                VStack(spacing: 4) {
                    Text("Import Wallet")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(Theme.dark)

                    Text("Paste your private key to restore")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("PRIVATE KEY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.muted)
                        .tracking(2)

                    HStack(spacing: 8) {
                        TextField("0x...", text: $importKeyText)
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.dark)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)

                        Button {
                            if let pasted = UIPasteboard.general.string {
                                importKeyText = pasted
                            }
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Theme.muted)
                        }
                    }
                    .padding(14)
                    .background(Color(hex: "F5F5F5"))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if let error = importError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text(error)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Theme.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    importError = nil
                    do {
                        try wallet.importFromPrivateKey(importKeyText)
                        importKeyText = ""
                        onSuccess()
                    } catch {
                        importError = error.localizedDescription
                    }
                } label: {
                    Text("IMPORT WALLET")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Theme.dark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .disabled(importKeyText.isEmpty)
                .opacity(importKeyText.isEmpty ? 0.5 : 1)

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}

// MARK: - Security Settings Sheet

struct SecuritySettingsSheet: View {
    @ObservedObject private var settings = SecuritySettings.shared
    @ObservedObject private var wallet = VoiceSwapWallet.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showPrivateKey = false
    @State private var privateKeyCopied = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationView {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    if wallet.isCreated {
                        backupSection
                    }
                    faceIDSection
                    dailyLimitSection
                    whitelistSection
                    if wallet.isCreated {
                        deleteWalletSection
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
        .alert("Delete Wallet?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Forever", role: .destructive) {
                wallet.deleteWallet()
                dismiss()
            }
        } message: {
            Text("You will lose all funds in this wallet unless you have backed up your private key. This action cannot be undone.")
        }
    }

    // MARK: - Backup Section

    private var backupSection: some View {
        MinimalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "key.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Theme.accent)

                    Text("BACKUP")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark.opacity(0.5))
                        .tracking(1)

                    Spacer()
                }

                Text("Save your private key to restore your wallet on another device")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Theme.muted)

                if showPrivateKey, let key = wallet.exportPrivateKey() {
                    // Show private key
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Theme.error)
                            Text("Never share this with anyone")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.error)
                            Spacer()
                        }

                        Text(key)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.dark)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: "F5F5F5"))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Button {
                            // Auto-expire from clipboard after 60 seconds
                            UIPasteboard.general.setItems(
                                [[UIPasteboard.typeAutomatic: key]],
                                options: [.expirationDate: Date().addingTimeInterval(60)]
                            )
                            privateKeyCopied = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { privateKeyCopied = false }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: privateKeyCopied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 12, weight: .bold))
                                Text(privateKeyCopied ? "COPIED! (60s)" : "COPY PRIVATE KEY")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .tracking(1)
                            }
                            .foregroundColor(privateKeyCopied ? Theme.accent : Theme.dark)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(privateKeyCopied ? Theme.accent.opacity(0.1) : Theme.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                        }

                        Button {
                            showPrivateKey = false
                        } label: {
                            Text("HIDE")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(Theme.muted)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(Theme.border, lineWidth: 1)
                                )
                        }
                    }
                } else {
                    Button {
                        Task {
                            let authenticated = await SecuritySettings.shared.authenticateWithBiometrics()
                            if authenticated {
                                showPrivateKey = true
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "faceid")
                                .font(.system(size: 12, weight: .bold))
                            Text("SHOW PRIVATE KEY")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundColor(Theme.dark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Theme.dark, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Delete Wallet Section

    private var deleteWalletSection: some View {
        MinimalCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "trash.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Theme.error)

                    Text("DANGER ZONE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.error.opacity(0.7))
                        .tracking(1)

                    Spacer()
                }

                Button {
                    showDeleteConfirmation = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 12, weight: .bold))
                        Text("DELETE WALLET")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundColor(Theme.error)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 2)
                            .stroke(Theme.error.opacity(0.5), lineWidth: 1)
                    )
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

    private var explorerURL: URL? {
        URL(string: "https://monadscan.com/tx/\(payment.tx_hash)")
    }

    var body: some View {
        VStack(spacing: 0) {
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

            // Receipt row — tx hash + Monadscan link
            if let url = explorerURL {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.accent)

                        Text("RECEIPT")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(Theme.accent)

                        Text(payment.txHashShort)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.muted)

                        Spacer()

                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.muted)
                    }
                    .padding(.top, 8)
                    .padding(.leading, 52) // align with text (40px icon + 12px spacing)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
    }
}

// MARK: - Send Sheet (Withdraw MON or USDC)

struct SendSheet: View {
    @ObservedObject var viewModel: VoiceSwapViewModel
    @ObservedObject private var wallet = VoiceSwapWallet.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedToken: String = "MON"
    @State private var amount: String = ""
    @State private var recipientAddress: String = ""
    @State private var showConfirmation = false
    @State private var isSending = false
    @State private var sendSuccess = false
    @State private var txHash: String?
    @State private var error: String?
    @State private var txCopied = false
    @State private var selectedPercentage: Int? = nil
    @State private var showQRScanner = false

    private static let usdcContract = "0x754704Bc059F8C67012fEd69BC8A327a5aafb603"

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color(hex: "836EF9").opacity(0.1))
                        .frame(width: 72, height: 72)
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(Color(hex: "836EF9"))
                }
                .padding(.top, 20)

                if sendSuccess {
                    successView
                } else if showConfirmation {
                    confirmationView
                } else {
                    inputView
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("SEND")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Theme.dark)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Color(hex: "836EF9"))
                }
            }
            .sheet(isPresented: $showQRScanner) {
                SendQRScannerSheet { address in
                    recipientAddress = address
                    showQRScanner = false
                }
            }
        }
    }

    // MARK: - Success View

    private var successView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundColor(Theme.accent)

            Text("SENT!")
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .foregroundColor(Theme.dark)
                .tracking(2)

            if let hash = txHash {
                Button {
                    UIPasteboard.general.string = hash
                    txCopied = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { txCopied = false }
                } label: {
                    HStack(spacing: 6) {
                        Text(String(hash.prefix(10)) + "..." + String(hash.suffix(6)))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.muted)
                        Image(systemName: txCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(txCopied ? Theme.accent : Theme.muted)
                    }
                }
            }

            Spacer().frame(height: 8)

            Button {
                dismiss()
            } label: {
                Text("DONE")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(Theme.dark)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
        }
        .padding(.vertical, 20)
    }

    // MARK: - Input View

    private var inputView: some View {
        VStack(spacing: 16) {
            // Token picker
            VStack(spacing: 6) {
                Text("TOKEN")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.muted)
                    .tracking(2)

                HStack(spacing: 8) {
                    tokenPill("MON", color: "836EF9", balance: viewModel.monBalance)
                    tokenPill("USDC", color: "2775CA", balance: usdcBalance)
                }
            }

            // Amount input
            VStack(spacing: 6) {
                Text("AMOUNT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.muted)
                    .tracking(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    TextField("0.00", text: $amount)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark)
                        .keyboardType(.decimalPad)

                    Text(selectedToken)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.muted)
                }
                .padding(14)
                .background(Color(hex: "F5F5F5"))
                .clipShape(RoundedRectangle(cornerRadius: 2))

                // Percentage bar (25% / 50% / 75% / MAX)
                percentageBar

                // Available balance hint
                HStack {
                    Text("Available: \(selectedToken == "MON" ? viewModel.monBalance : usdcBalance) \(selectedToken)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.muted)
                    if selectedToken == "MON" {
                        Text("(\(String(format: "%.3f", Self.gasReserve)) reserved for gas)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.muted.opacity(0.6))
                    }
                    Spacer()
                }
            }

            // Recipient address
            VStack(spacing: 6) {
                HStack {
                    Text("TO ADDRESS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.muted)
                        .tracking(2)
                    Spacer()
                    Button {
                        showQRScanner = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 10, weight: .bold))
                            Text("SCAN")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundColor(Color(hex: "836EF9"))
                    }
                    Button {
                        if let clip = UIPasteboard.general.string {
                            recipientAddress = clip
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 10, weight: .bold))
                            Text("PASTE")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .tracking(1)
                        }
                        .foregroundColor(Color(hex: "836EF9"))
                    }
                }

                TextField("0x...", text: $recipientAddress)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.dark)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .padding(14)
                    .background(Color(hex: "F5F5F5"))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }

            // Error
            if let error = error {
                Text(error)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.error)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Review button → goes to confirmation
            Button {
                error = nil
                // Validate address
                guard isValidAddress(recipientAddress) else {
                    error = "Enter a valid 0x address (42 characters)"
                    return
                }
                if recipientAddress.lowercased() == wallet.address.lowercased() {
                    error = "Cannot send to your own address"
                    return
                }
                // Validate amount
                guard let amountVal = Double(amount), amountVal > 0 else {
                    error = "Enter an amount greater than zero"
                    return
                }
                let balance = selectedToken == "MON"
                    ? (Double(viewModel.monBalance) ?? 0)
                    : (Double(usdcBalance) ?? 0)
                if amountVal > balance {
                    error = "Insufficient \(selectedToken) balance"
                    return
                }
                let monBal = Double(viewModel.monBalance) ?? 0
                if selectedToken == "MON" {
                    if monBal - amountVal < Self.gasReserve {
                        // Auto-adjust: reduce amount to leave gas reserve
                        let adjusted = max(monBal - Self.gasReserve, 0)
                        if adjusted <= 0 {
                            error = "Balance too low. You need >\(Self.gasReserve) MON to cover gas."
                            return
                        }
                        amount = String(format: "%.6f", adjusted)
                        error = "Adjusted to \(amount) MON (\(Self.gasReserve) reserved for gas)"
                        // Let user review the adjusted amount — don't auto-proceed
                        return
                    }
                } else {
                    // USDC send — user still needs MON for gas
                    if monBal < Self.gasReserve {
                        error = "You need MON to pay gas fees. Deposit MON first."
                        return
                    }
                }
                withAnimation(.easeInOut(duration: 0.2)) {
                    showConfirmation = true
                }
            } label: {
                Text("REVIEW")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(canSend ? Color(hex: "836EF9") : Color(hex: "836EF9").opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .disabled(!canSend)
        }
    }

    // MARK: - Confirmation View

    private var shortRecipient: String {
        guard recipientAddress.count > 10 else { return recipientAddress }
        return String(recipientAddress.prefix(8)) + "..." + String(recipientAddress.suffix(6))
    }

    private var confirmationView: some View {
        VStack(spacing: 20) {
            Text("Confirm transaction")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(Theme.dark)

            // Summary card
            VStack(spacing: 16) {
                HStack {
                    Text("AMOUNT")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.muted)
                        .tracking(2)
                    Spacer()
                    Text("\(amount) \(selectedToken)")
                        .font(.system(size: 16, weight: .black, design: .monospaced))
                        .foregroundColor(Theme.dark)
                }

                Rectangle().fill(Theme.border).frame(height: 1)

                HStack {
                    Text("TO")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.muted)
                        .tracking(2)
                    Spacer()
                    Text(shortRecipient)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.dark)
                }

                Rectangle().fill(Theme.border).frame(height: 1)

                HStack {
                    Text("NETWORK")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.muted)
                        .tracking(2)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(Color(hex: "836EF9")).frame(width: 6, height: 6)
                        Text("Monad")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.dark)
                    }
                }

                Rectangle().fill(Theme.border).frame(height: 1)

                HStack {
                    Text("GAS FEE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.muted)
                        .tracking(2)
                    Spacer()
                    Text("< 0.001 MON")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.accent)
                }
            }
            .padding(16)
            .background(Color(hex: "F5F5F5"))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Warning
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.orange)
                Text("This action is irreversible")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.muted)
            }

            if let error = error {
                Text(error)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.error)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            // Confirm + Back buttons
            VStack(spacing: 10) {
                Button {
                    sendFunds()
                } label: {
                    HStack(spacing: 8) {
                        if isSending {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text(isSending ? "SENDING..." : "CONFIRM SEND")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(isSending ? Color(hex: "836EF9").opacity(0.6) : Color(hex: "836EF9"))
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                }
                .disabled(isSending)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showConfirmation = false
                    }
                } label: {
                    Text("GO BACK")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
            }
        }
    }

    // MARK: - Percentage Bar

    private var percentageBar: some View {
        GeometryReader { geo in
            let steps = [25, 50, 75, 100]
            let dotSize: CGFloat = 20
            let lineHeight: CGFloat = 3
            let totalWidth = geo.size.width

            ZStack(alignment: .leading) {
                // Track line
                RoundedRectangle(cornerRadius: 2)
                    .fill(Theme.border)
                    .frame(height: lineHeight)
                    .padding(.horizontal, dotSize / 2)

                // Filled line up to selected percentage
                if let pct = selectedPercentage, let idx = steps.firstIndex(of: pct) {
                    let progress = CGFloat(idx) / CGFloat(steps.count - 1)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color(hex: "836EF9"))
                        .frame(width: (totalWidth - dotSize) * progress + dotSize / 2, height: lineHeight)
                        .padding(.leading, dotSize / 2)
                }

                // Dots + labels
                HStack(spacing: 0) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { idx, pct in
                        if idx > 0 { Spacer() }

                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            selectedPercentage = pct
                            setAmountByPercentage(pct)
                        } label: {
                            VStack(spacing: 4) {
                                ZStack {
                                    Circle()
                                        .fill(isPercentageActive(pct) ? Color(hex: "836EF9") : Color(hex: "F5F5F5"))
                                        .frame(width: dotSize, height: dotSize)
                                    Circle()
                                        .stroke(isPercentageActive(pct) ? Color(hex: "836EF9") : Theme.border, lineWidth: 1.5)
                                        .frame(width: dotSize, height: dotSize)
                                    if isPercentageActive(pct) {
                                        Circle()
                                            .fill(Color.white)
                                            .frame(width: 6, height: 6)
                                    }
                                }

                                Text(pct == 100 ? "MAX" : "\(pct)%")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(isPercentageActive(pct) ? Color(hex: "836EF9") : Theme.muted)
                            }
                        }
                    }
                }
            }
        }
        .frame(height: 44)
    }

    private func isPercentageActive(_ pct: Int) -> Bool {
        guard let selected = selectedPercentage else { return false }
        return pct <= selected
    }

    private func setAmountByPercentage(_ pct: Int) {
        let balance: Double
        if selectedToken == "MON" {
            balance = Double(viewModel.monBalance) ?? 0
        } else {
            balance = Double(usdcBalance) ?? 0
        }

        if pct == 100 {
            amount = maxAmount
        } else {
            let fraction = Double(pct) / 100.0
            var computed = balance * fraction
            // For MON, never exceed maxAmount
            if selectedToken == "MON" {
                let maxVal = Double(maxAmount) ?? 0
                computed = min(computed, maxVal)
            }
            let decimals = selectedToken == "MON" ? 6 : 2
            amount = String(format: "%.\(decimals)f", computed)
        }
    }

    // MARK: - Token Pill

    private func tokenPill(_ symbol: String, color: String, balance: String) -> some View {
        Button {
            selectedToken = symbol
            selectedPercentage = nil
            amount = ""
        } label: {
            VStack(spacing: 4) {
                Text(symbol)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(selectedToken == symbol ? Theme.dark : Theme.muted)
                Text(balance)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(selectedToken == symbol ? Color(hex: color).opacity(0.12) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(selectedToken == symbol ? Color(hex: color) : Theme.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Computed Properties

    private var usdcBalance: String {
        viewModel.tokenBalances.first(where: { $0.symbol == "USDC" })?.balance ?? "0.00"
    }

    /// Gas reserve for native MON sends — covers gasPrice*gasLimit with large buffer
    /// Monad gas is extremely cheap (~0.003 MON per transfer), so 0.05 is very safe
    private static let gasReserve: Double = 0.05

    private var maxAmount: String {
        if selectedToken == "MON" {
            let bal = Double(viewModel.monBalance) ?? 0
            let maxVal = max(bal - Self.gasReserve, 0)
            return String(format: "%.6f", maxVal)
        } else {
            return usdcBalance
        }
    }

    private var canSend: Bool {
        guard !amount.isEmpty,
              let amountVal = Double(amount),
              amountVal > 0,
              isValidAddress(recipientAddress) else { return false }
        // Check sufficient balance
        if selectedToken == "MON" {
            return amountVal <= (Double(viewModel.monBalance) ?? 0)
        } else {
            return amountVal <= (Double(usdcBalance) ?? 0)
        }
    }

    private func isValidAddress(_ addr: String) -> Bool {
        let pattern = "^0x[a-fA-F0-9]{40}$"
        return addr.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Send Logic

    private func sendFunds() {
        guard canSend else { return }

        // Validate not sending to self
        if recipientAddress.lowercased() == wallet.address.lowercased() {
            error = "Cannot send to your own address"
            return
        }

        isSending = true
        error = nil

        Task {
            do {
                let hash: String
                if selectedToken == "MON" {
                    let weiHex = convertMONToWeiHex(amount)
                    NSLog("[Send] Sending %@ MON (wei hex: %@) to %@", amount, weiHex, recipientAddress)
                    hash = try await wallet.sendTransaction(
                        to: recipientAddress,
                        value: weiHex,
                        data: nil
                    )
                } else {
                    let calldata = encodeERC20Transfer(to: recipientAddress, amount: amount)
                    hash = try await wallet.sendTransaction(
                        to: Self.usdcContract,
                        value: "0x0",
                        data: calldata
                    )
                }

                NSLog("[Send] Sent %@ %@, tx: %@", amount, selectedToken, hash)
                await MainActor.run {
                    isSending = false
                    txHash = hash
                    sendSuccess = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }

                // Refresh balances after a short delay
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await viewModel.refreshBalances()
            } catch {
                NSLog("[Send] Error: %@", error.localizedDescription)
                await MainActor.run {
                    isSending = false
                    self.error = friendlyError(error)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Map raw wallet errors to user-friendly messages
    private func friendlyError(_ error: Error) -> String {
        let msg = error.localizedDescription.lowercased()

        // Insufficient funds for gas (from our pre-check or RPC)
        if msg.contains("insufficient balance") || msg.contains("insufficient funds") {
            // Try to extract the detailed message from our pre-check
            if let range = error.localizedDescription.range(of: "Insufficient balance: ") {
                return String(error.localizedDescription[range.upperBound...])
            }
            return "Not enough MON to cover transfer + gas. Try a smaller amount."
        }
        // Nonce issues (stuck or already used)
        if msg.contains("nonce") {
            return "Transaction conflict. Please wait a moment and try again."
        }
        // Gas estimation / execution revert
        if msg.contains("execution reverted") || msg.contains("revert") {
            if selectedToken == "USDC" {
                return "Transfer failed. Check you have enough USDC and the address is correct."
            }
            return "Transaction reverted by the network. Double-check the amount and address."
        }
        // Network / connectivity
        if msg.contains("timed out") || msg.contains("timeout") {
            return "Network request timed out. Check your connection and try again."
        }
        if msg.contains("could not connect") || msg.contains("network") || msg.contains("url") {
            return "Unable to reach Monad network. Check your internet connection."
        }
        // Wallet not set up
        if msg.contains("not created") {
            return "Wallet not set up. Create or import a wallet first."
        }
        // RPC generic
        if msg.contains("rpc error") {
            let cleaned = error.localizedDescription
                .replacingOccurrences(of: "RPC error: ", with: "")
            return "Network error: \(cleaned)"
        }
        // Fallback
        return "Something went wrong. Please try again."
    }

    /// Convert a decimal MON amount to hex wei string (e.g., "1.5" → "0x14d1120d7b160000")
    /// Uses string-based arithmetic to avoid UInt64 overflow for amounts > 18.44 MON.
    private func convertMONToWeiHex(_ amount: String) -> String {
        guard Double(amount) != nil else { return "0x0" }

        // Split into integer and fractional parts to avoid floating-point precision issues
        let parts = amount.split(separator: ".", maxSplits: 1)
        let integerPart = String(parts[0])
        let fractionalPart = parts.count > 1 ? String(parts[1]) : ""

        // Pad or truncate fractional part to 18 digits (wei = 10^18)
        let paddedFrac = (fractionalPart + String(repeating: "0", count: 18)).prefix(18)
        let rawWeiString = integerPart + paddedFrac
        // Strip leading zeros
        let weiString = String(rawWeiString.drop(while: { $0 == "0" }))

        guard !weiString.isEmpty else { return "0x0" }

        // Try UInt64 first (works for amounts up to ~18.44 MON)
        if let weiValue = UInt64(weiString) {
            return "0x" + String(weiValue, radix: 16)
        }

        // Big integer path: convert decimal string to hex via repeated division
        return "0x" + decimalStringToHex(weiString)
    }

    /// Convert a decimal digit string to hex string (no UInt64 overflow).
    /// Uses schoolbook division by 16 on an array of decimal digits.
    private func decimalStringToHex(_ decimal: String) -> String {
        var digits = Array(decimal).map { Int(String($0))! }
        var hex = ""

        while !digits.isEmpty && !(digits.count == 1 && digits[0] == 0) {
            var remainder = 0
            var quotient: [Int] = []
            for digit in digits {
                let current = remainder * 10 + digit
                quotient.append(current / 16)
                remainder = current % 16
            }
            hex = String(remainder, radix: 16) + hex
            // Strip leading zeros from quotient
            digits = Array(quotient.drop(while: { $0 == 0 }))
        }

        return hex.isEmpty ? "0" : hex
    }

    /// Encode ERC20 transfer(address,uint256) calldata
    /// selector: 0xa9059cbb
    /// address: zero-padded to 32 bytes
    /// amount: in 6 decimals (USDC), zero-padded to 32 bytes
    private func encodeERC20Transfer(to address: String, amount: String) -> String {
        let selector = "a9059cbb"

        // Address: strip 0x prefix, left-pad to 64 hex chars (32 bytes)
        let cleanAddr = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
        let paddedAddr = String(repeating: "0", count: 64 - cleanAddr.count) + cleanAddr.lowercased()

        // Amount: convert to USDC units (6 decimals)
        let parts = amount.split(separator: ".", maxSplits: 1)
        let integerPart = String(parts[0])
        let fractionalPart = parts.count > 1 ? String(parts[1]) : ""
        let paddedFrac = (fractionalPart + String(repeating: "0", count: 6)).prefix(6)
        let unitsString = integerPart + paddedFrac

        // Convert to UInt64 and then to hex
        let units = UInt64(unitsString) ?? 0
        let hexAmount = String(units, radix: 16)
        let paddedAmount = String(repeating: "0", count: 64 - hexAmount.count) + hexAmount

        return "0x" + selector + paddedAddr + paddedAmount
    }
}

// MARK: - Fund Wallet Sheet

struct FundWalletSheet: View {
    let walletAddress: String
    @ObservedObject var walletConnect: WalletConnectManager
    @Environment(\.dismiss) private var dismiss
    @State private var selectedToken: String = "MON"
    @State private var selectedAmount: String = "5"
    @State private var customAmount: String = ""
    @State private var isCustom: Bool = false
    @State private var isFunding = false
    @State private var fundingSuccess = false
    @State private var lastTxHash: String?
    @State private var txCopied = false
    @State private var showHistory = false
    @State private var error: String?
    @FocusState private var isAmountFocused: Bool

    private static let usdcContract = "0x754704Bc059F8C67012fEd69BC8A327a5aafb603"

    private let monAmounts = ["1", "5", "10", "25"]
    private let usdcAmounts = ["5", "10", "25", "50"]

    private var currentPresets: [String] {
        selectedToken == "MON" ? monAmounts : usdcAmounts
    }

    /// Convert a decimal amount to hex smallest-unit value
    /// decimals: 18 for MON, 6 for USDC
    private func amountToHex(_ amount: String, decimals: Int) -> String? {
        guard let value = Double(amount), value > 0 else { return nil }
        let parts = amount.split(separator: ".", maxSplits: 1)
        let wholePart = String(parts[0])
        let fracPart = parts.count > 1 ? String(parts[1]) : ""
        let paddedFrac = String((fracPart + String(repeating: "0", count: decimals)).prefix(decimals))
        let raw = wholePart + paddedFrac
        let trimmed = String(raw.drop(while: { $0 == "0" }))
        if trimmed.isEmpty { return nil }
        // Big-number decimal → hex conversion
        var digits = trimmed.map { Int(String($0))! }
        var hex = ""
        while !digits.isEmpty {
            var remainder = 0
            var quotient: [Int] = []
            for d in digits {
                let cur = remainder * 10 + d
                quotient.append(cur / 16)
                remainder = cur % 16
            }
            hex = String(remainder, radix: 16) + hex
            digits = Array(quotient.drop(while: { $0 == 0 }))
        }
        return "0x" + hex
    }

    /// Encode ERC20 transfer(address,uint256) calldata
    private func encodeERC20Transfer(to address: String, amountHex: String) -> String {
        let selector = "a9059cbb"
        let cleanAddr = address.hasPrefix("0x") ? String(address.dropFirst(2)) : address
        let paddedAddr = String(repeating: "0", count: 64 - cleanAddr.count) + cleanAddr.lowercased()
        let cleanHex = amountHex.hasPrefix("0x") ? String(amountHex.dropFirst(2)) : amountHex
        let paddedAmount = String(repeating: "0", count: 64 - cleanHex.count) + cleanHex
        return "0x" + selector + paddedAddr + paddedAmount
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.1))
                        .frame(width: 72, height: 72)
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 32, weight: .medium))
                        .foregroundColor(Theme.accent)
                }
                .padding(.top, 20)

                Text("Fund your VoiceSwap Wallet\nfrom \(walletConnect.connectedWallet?.walletName ?? "your wallet")")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center)

                // Token selector
                HStack(spacing: 8) {
                    ForEach(["MON", "USDC"], id: \.self) { token in
                        Button {
                            selectedToken = token
                            selectedAmount = token == "MON" ? "5" : "10"
                            isCustom = false
                            customAmount = ""
                            error = nil
                            isAmountFocused = false
                        } label: {
                            Text(token)
                                .font(.system(size: 12, weight: .black, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(selectedToken == token ? Theme.dark : Theme.muted)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedToken == token ? Theme.accent : Color.clear)
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(selectedToken == token ? Theme.accent : Theme.border, lineWidth: 1)
                                )
                        }
                    }
                }

                if fundingSuccess {
                    // Success state
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(Theme.accent)

                        Text("SENT!")
                            .font(.system(size: 16, weight: .black, design: .monospaced))
                            .foregroundColor(Theme.dark)
                            .tracking(2)

                        Text("Funds will arrive in a few seconds")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.muted)

                        if let hash = lastTxHash {
                            Button {
                                UIPasteboard.general.string = hash
                                txCopied = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { txCopied = false }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(String(hash.prefix(10)) + "..." + String(hash.suffix(6)))
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(Theme.muted)
                                    Image(systemName: txCopied ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(txCopied ? Theme.accent : Theme.muted)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 20)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Text("DONE")
                            .font(.system(size: 14, weight: .black, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Theme.dark)
                            .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                } else {
                    // Amount selector
                    VStack(spacing: 12) {
                        Text("SELECT AMOUNT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.muted)
                            .tracking(2)

                        HStack(spacing: 8) {
                            ForEach(currentPresets, id: \.self) { preset in
                                Button {
                                    selectedAmount = preset
                                    isCustom = false
                                    customAmount = ""
                                    isAmountFocused = false
                                } label: {
                                    Text("\(preset) \(selectedToken)")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(!isCustom && selectedAmount == preset ? Theme.dark : Theme.muted)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 10)
                                        .background(!isCustom && selectedAmount == preset ? Theme.accent : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 2)
                                                .stroke(!isCustom && selectedAmount == preset ? Theme.accent : Theme.border, lineWidth: 1)
                                        )
                                }
                            }
                        }

                        // Custom amount input
                        HStack(spacing: 8) {
                            TextField("Custom amount", text: $customAmount)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .keyboardType(.decimalPad)
                                .focused($isAmountFocused)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(isCustom ? Theme.accent.opacity(0.1) : Color(hex: "F5F5F5"))
                                .clipShape(RoundedRectangle(cornerRadius: 2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(isCustom ? Theme.accent : Theme.border, lineWidth: 1)
                                )
                                .onChange(of: customAmount) { _ in
                                    if !customAmount.isEmpty {
                                        isCustom = true
                                    }
                                }

                            Text(selectedToken)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(Theme.muted)
                        }
                    }

                    // Destination
                    VStack(spacing: 4) {
                        Text("TO")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.muted)
                            .tracking(2)

                        Text(String(walletAddress.prefix(8)) + "..." + String(walletAddress.suffix(6)))
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.dark)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(hex: "F5F5F5"))
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                    if let error = error {
                        Text(error)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.error)
                    }

                    Spacer()

                    // Fund button
                    Button {
                        sendFunds()
                    } label: {
                        HStack(spacing: 8) {
                            if isFunding {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.dark))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "paperplane.fill")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            Text(isFunding ? "APPROVE IN WALLET..." : "SEND FUNDS")
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                .tracking(2)
                        }
                        .foregroundColor(Theme.dark)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                        .background(Theme.accent)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                    }
                    .disabled(isFunding)
                    .opacity(isFunding ? 0.7 : 1.0)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .background(Theme.bg.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showHistory.toggle()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Theme.muted)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("FUND WALLET")
                        .font(.system(size: 14, weight: .black, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(Theme.dark)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.accent)
                }
            }
            .sheet(isPresented: $showHistory) {
                FundingHistoryView()
            }
        }
    }

    private func sendFunds() {
        isAmountFocused = false
        let amountStr = isCustom ? customAmount : selectedAmount
        guard !amountStr.isEmpty, let val = Double(amountStr), val > 0 else {
            error = "Enter a valid amount"
            return
        }

        isFunding = true
        error = nil

        Task {
            do {
                let txHash: String
                if selectedToken == "USDC" {
                    // ERC-20 transfer: call USDC contract with transfer(to, amount)
                    let decimals = 6
                    guard let hexAmount = amountToHex(amountStr, decimals: decimals) else {
                        await MainActor.run { isFunding = false; self.error = "Invalid amount" }
                        return
                    }
                    let calldata = encodeERC20Transfer(to: walletAddress, amountHex: hexAmount)
                    NSLog("[FundWallet] Sending %@ USDC to %@", amountStr, walletAddress)
                    txHash = try await walletConnect.sendTransaction(
                        to: Self.usdcContract,
                        value: "0x0",
                        data: calldata
                    )
                } else {
                    // Native MON transfer
                    guard let hexWei = amountToHex(amountStr, decimals: 18) else {
                        await MainActor.run { isFunding = false; self.error = "Invalid amount" }
                        return
                    }
                    NSLog("[FundWallet] Sending %@ MON (hex: %@) to %@", amountStr, hexWei, walletAddress)
                    txHash = try await walletConnect.sendTransaction(
                        to: walletAddress,
                        value: hexWei,
                        data: nil
                    )
                }

                NSLog("[FundWallet] Sent %@ %@, tx: %@", amountStr, selectedToken, txHash)
                FundingHistory.save(FundingRecord(
                    txHash: txHash,
                    amount: amountStr,
                    token: selectedToken,
                    date: Date()
                ))
                await MainActor.run {
                    lastTxHash = txHash
                    isFunding = false
                    fundingSuccess = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    AudioServicesPlaySystemSound(1025)
                }
            } catch {
                await MainActor.run {
                    isFunding = false
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Funding History

struct FundingRecord: Codable, Identifiable {
    var id: String { txHash }
    let txHash: String
    let amount: String
    let token: String
    let date: Date
}

enum FundingHistory {
    private static let key = "voiceswap_funding_history"

    static func load() -> [FundingRecord] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let records = try? JSONDecoder().decode([FundingRecord].self, from: data) else {
            return []
        }
        return records.sorted { $0.date > $1.date }
    }

    static func save(_ record: FundingRecord) {
        var records = load()
        // Avoid duplicates
        if records.contains(where: { $0.txHash == record.txHash }) { return }
        records.insert(record, at: 0)
        // Keep last 50
        if records.count > 50 { records = Array(records.prefix(50)) }
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

struct FundingHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [FundingRecord] = []
    @State private var copiedHash: String?

    var body: some View {
        NavigationView {
            Group {
                if records.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "tray")
                            .font(.system(size: 32, weight: .light))
                            .foregroundColor(Theme.muted)
                        Text("No deposits yet")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.muted)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(records) { record in
                                HStack(spacing: 12) {
                                    // Token icon
                                    Text(record.token)
                                        .font(.system(size: 10, weight: .black, design: .monospaced))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 4)
                                        .background(record.token == "USDC" ? Color.blue : Theme.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 2))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(record.amount) \(record.token)")
                                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                                            .foregroundColor(Theme.dark)

                                        Text(record.date, style: .relative)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(Theme.muted)
                                            + Text(" ago")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(Theme.muted)
                                    }

                                    Spacer()

                                    // Copy tx hash
                                    Button {
                                        UIPasteboard.general.string = record.txHash
                                        copiedHash = record.txHash
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                            if copiedHash == record.txHash { copiedHash = nil }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(String(record.txHash.prefix(6)) + "...")
                                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                                .foregroundColor(Theme.muted)
                                            Image(systemName: copiedHash == record.txHash ? "checkmark" : "doc.on.doc")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundColor(copiedHash == record.txHash ? Theme.accent : Theme.muted)
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .background(Theme.bg)
                            }
                        }
                    }
                }
            }
            .background(Color(hex: "F5F5F5").ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("DEPOSIT HISTORY")
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
            .onAppear {
                records = FundingHistory.load()
            }
        }
    }
}

// MARK: - Preview

struct VoiceSwapMainView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceSwapMainView()
    }
}
