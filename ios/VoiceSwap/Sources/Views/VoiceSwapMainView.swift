/**
 * VoiceSwapMainView.swift
 * VoiceSwap - Voice-activated crypto payments
 *
 * Minimal brutalist design inspired by Interfacer.co
 * Clean, futuristic, high contrast
 */

import SwiftUI
import ReownAppKit
import AudioToolbox

// MARK: - Design System (Interfacer.co inspired)

struct Theme {
    // Core colors - Interfacer brutalist palette
    static let bg = Color.white                    // Pure white background
    static let card = Color.white
    static let dark = Color.black                  // Pure black for text/icons
    static let accent = Color(hex: "1BFFE3")       // Interfacer cyan
    static let accentHover = Color(hex: "66DEE0")  // Hover state
    static let success = Color(hex: "1BFFE3")
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

    public init() {}

    public var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {  // Interfacer: generous spacing
                headerView
                    .padding(.bottom, 12)

                walletCard
                glassesCard
                geminiCard

                // Manual QR scan button (phone camera fallback)
                if walletManager.isConnected {
                    phoneScanCard
                }

                if walletManager.isConnected {
                    balanceCard
                }

                // Show scanning card when glasses are streaming/scanning
                if glassesManager.isStreaming {
                    scanningCard
                }

                if viewModel.flowState != .idle {
                    paymentCard
                }

                Spacer(minLength: 56)
            }
            .padding(.horizontal, 24)  // Interfacer: 24px padding
            .padding(.top, 24)
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
        // Show phone camera scanner when glasses camera fails
        .onChange(of: glassesManager.connectionState) { state in
            if case .error(let msg) = state {
                // If camera/SDK error, offer phone camera as fallback
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

    // MARK: - Wallet Card

    private var walletCard: some View {
        MinimalCard {
            HStack(spacing: 12) {
                // Status dot
                Circle()
                    .fill(walletManager.isConnected ? Theme.accent : Theme.border)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text(walletManager.isConnected ? "WALLET" : "CONNECT")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark)

                    if let address = walletManager.currentAddress, walletManager.isConnected {
                        Text("\(address.prefix(6))...\(address.suffix(4))")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.muted)
                    } else {
                        Text("Tap to link wallet")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.muted)
                    }
                }

                Spacer()

                Button {
                    if walletManager.isConnected {
                        walletManager.disconnect()
                    } else {
                        walletManager.connect()
                    }
                } label: {
                    Circle()
                        .fill(walletManager.isConnected ? Theme.dark : Theme.accent)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: walletManager.isConnected ? "xmark" : "plus")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(walletManager.isConnected ? Theme.accent : Theme.dark)
                        )
                }
            }
        }
    }

    // MARK: - Glasses Card

    private var glassesCard: some View {
        let canConnect = walletManager.isConnected
        // Show green when SDK has devices OR glasses detected via audio route (A2DP)
        let isGlassesReady = !glassesManager.devices.isEmpty || glassesManager.isGlassesHFPConnected || glassesManager.isStreaming

        return MinimalCard {
            HStack(spacing: 12) {
                // Status dot - show accent only when SDK has real device connection
                Circle()
                    .fill(isGlassesReady ? Theme.accent : Theme.border)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("GLASSES")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark)

                    Text(glassesStatus(canConnect: canConnect))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.muted)
                }

                Spacer()

                Circle()
                    .fill(glassesButtonBackground(canConnect: canConnect))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Image(systemName: glassesButtonIcon)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(glassesButtonForeground(canConnect: canConnect))
                    )
                    .opacity(canConnect ? 1 : 0.4)
                    .onTapGesture {
                        guard canConnect else { return }
                        Task { await handleGlassesButtonTap() }
                    }
                    .onLongPressGesture(minimumDuration: 1.0) {
                        // Long press forces re-registration
                        guard canConnect else { return }
                        Task { await forceReconnectGlasses() }
                    }
            }
        }
    }

    private func glassesStatus(canConnect: Bool) -> String {
        guard canConnect else { return "Connect wallet first" }
        switch glassesManager.connectionState {
        case .disconnected: return "Tap to pair with Meta glasses"
        case .searching: return "Searching for glasses..."
        case .connecting: return "Opening Meta View app..."
        case .registered, .connected:
            // Check if SDK has devices OR glasses detected via audio route
            if !glassesManager.devices.isEmpty || glassesManager.isGlassesHFPConnected {
                return "Ready - tap to scan QR"
            }
            // No glasses detected - need to open Meta View
            return "Tap to open Meta View"
        case .streaming: return "Scanning for QR code..."
        case .error(let msg):
            if msg.contains("Meta View") || msg.contains("Device Access") {
                return "Enable in Meta View > Device Access"
            }
            return "Error - tap to retry"
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

    // MARK: - Glasses Button Helpers

    private var glassesButtonIcon: String {
        switch glassesManager.connectionState {
        case .streaming:
            return "xmark"  // Show X when streaming (to stop)
        case .connected, .registered:
            return "qrcode.viewfinder"  // Show QR scan icon when ready
        default:
            return "eyeglasses"  // Show glasses icon for disconnected/connecting
        }
    }

    private func glassesButtonBackground(canConnect: Bool) -> Color {
        switch glassesManager.connectionState {
        case .streaming:
            return Theme.dark  // Dark background when streaming (X to cancel)
        case .connected, .registered:
            return Theme.accent  // Teal background when ready to scan
        default:
            return canConnect ? Theme.accent : Theme.border
        }
    }

    private func glassesButtonForeground(canConnect: Bool) -> Color {
        switch glassesManager.connectionState {
        case .streaming:
            return Theme.accent  // Teal X on dark background
        default:
            return Theme.dark  // Dark icon on teal background
        }
    }

    // MARK: - Gemini Card

    private var geminiCard: some View {
        MinimalCard {
            HStack(spacing: 12) {
                // Status dot
                Circle()
                    .fill(geminiSession.isSessionActive ? Theme.accent : Theme.border)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("GEMINI")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark)

                    Text(geminiStatusText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.muted)
                }

                Spacer()

                if geminiSession.isAISpeaking {
                    // Speaking indicator
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Theme.accent)
                                .frame(width: 2, height: CGFloat([8, 14, 10][i]))
                        }
                    }
                    .padding(.trailing, 8)
                }

                Button {
                    handleGeminiButtonTap()
                } label: {
                    Circle()
                        .fill(geminiSession.isSessionActive ? Theme.dark : (GeminiConfig.isConfigured ? Theme.accent : Theme.border))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: geminiButtonIcon)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(geminiSession.isSessionActive ? Theme.accent : Theme.dark)
                        )
                }
            }
        }
    }

    private var geminiStatusText: String {
        if let error = geminiSession.sessionError {
            return error
        }
        if geminiSession.isAISpeaking {
            return "Speaking..."
        }
        if geminiSession.isListening {
            return "Listening..."
        }
        if geminiSession.isSessionActive {
            return "Active"
        }
        if !GeminiConfig.isConfigured {
            return "Tap to set API key"
        }
        return "Tap to start voice"
    }

    private var geminiButtonIcon: String {
        if geminiSession.isSessionActive {
            return "stop.fill"
        }
        if !GeminiConfig.isConfigured {
            return "key.fill"
        }
        return "mic.fill"
    }

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

    // MARK: - Phone Scan Card

    private var phoneScanCard: some View {
        MinimalCard {
            HStack(spacing: 12) {
                // Camera icon
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("SCAN QR")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(Theme.dark)

                    Text("Use phone camera")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.muted)
                }

                Spacer()

                Button {
                    showPhoneCameraScanner = true
                } label: {
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: "qrcode.viewfinder")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(Theme.dark)
                        )
                }
            }
        }
    }

    // MARK: - Scanning Card

    private var scanningCard: some View {
        MinimalCard(highlight: Theme.accent.opacity(0.1)) {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    // Animated scanning dot
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 8, height: 8)
                        .opacity(0.8)

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

                // Cancel button
                MinimalButton("Cancel", style: .secondary) {
                    glassesManager.stopQRScanning()
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
        default: return nil
        }
    }

    private var paymentDotColor: Color {
        switch viewModel.flowState {
        case .success: return Theme.accent
        case .failed: return Theme.error
        case .enteringAmount: return Theme.accent
        case .awaitingConfirmation: return Theme.accent
        default: return Theme.muted
        }
    }

    private var paymentTitle: String {
        switch viewModel.flowState {
        case .listening: return "LISTENING"
        case .processing: return "PROCESSING"
        case .scanningQR: return "SCANNING"
        case .enteringAmount: return "AMOUNT"
        case .awaitingConfirmation: return "CONFIRM"
        case .executing: return "SENDING"
        case .confirming: return "CONFIRMING"
        case .success: return "COMPLETE"
        case .failed: return "FAILED"
        case .cancelled: return "CANCELLED"
        default: return ""
        }
    }

    private var paymentSubtitle: String {
        switch viewModel.flowState {
        case .listening: return "Say command..."
        case .processing: return "Processing"
        case .scanningQR: return "Point at QR"
        case .enteringAmount: return "Enter amount"
        case .awaitingConfirmation: return "Review payment"
        case .executing: return "Sending..."
        case .confirming: return "On chain"
        case .success: return "Done"
        case .failed: return "Try again"
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
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)

        case .success(let txHash):
            VStack(spacing: 12) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "checkmark")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(Theme.dark)
                    )

                if txHash != "pending" {
                    Text("TX: \(txHash.prefix(8))...")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

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

        // Add corner brackets - Interfacer cyan (#1BFFE3)
        let bracketColor = UIColor(red: 27/255, green: 255/255, blue: 227/255, alpha: 1)
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

// MARK: - Preview

struct VoiceSwapMainView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceSwapMainView()
    }
}
