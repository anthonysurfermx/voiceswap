/**
 * VoiceSwapMainView.swift
 * VoiceSwap - Main SwiftUI View
 *
 * Brutalist design inspired by modern habit tracking apps.
 * Features bold typography, hard shadows, and vibrant colors.
 */

import SwiftUI
import ReownAppKit

// MARK: - Brutalist Design System

struct BrutalistColors {
    static let background = Color(hex: "F5F5DC") // Cream/Beige
    static let primary = Color(hex: "FFE135") // Bright Yellow
    static let accent = Color(hex: "FF6B6B") // Coral Red
    static let success = Color(hex: "4ECDC4") // Teal
    static let dark = Color.black
    static let cardBg = Color.white
}

struct BrutalistCard<Content: View>: View {
    let content: Content
    var backgroundColor: Color = BrutalistColors.cardBg

    init(backgroundColor: Color = BrutalistColors.cardBg, @ViewBuilder content: () -> Content) {
        self.backgroundColor = backgroundColor
        self.content = content()
    }

    var body: some View {
        content
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(BrutalistColors.dark, lineWidth: 3)
            )
            .shadow(color: BrutalistColors.dark, radius: 0, x: 4, y: 4)
    }
}

struct BrutalistButton: View {
    let title: String
    let icon: String?
    var backgroundColor: Color = BrutalistColors.primary
    var foregroundColor: Color = BrutalistColors.dark
    let action: () -> Void

    init(_ title: String, icon: String? = nil, backgroundColor: Color = BrutalistColors.primary, foregroundColor: Color = BrutalistColors.dark, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.backgroundColor = backgroundColor
        self.foregroundColor = foregroundColor
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .black))
                }
                Text(title.uppercased())
                    .font(.system(size: 16, weight: .black))
            }
            .foregroundColor(foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(BrutalistColors.dark, lineWidth: 3)
            )
            .shadow(color: BrutalistColors.dark, radius: 0, x: 3, y: 3)
        }
        .buttonStyle(BrutalistButtonStyle())
    }
}

struct BrutalistButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .offset(x: configuration.isPressed ? 3 : 0, y: configuration.isPressed ? 3 : 0)
            .shadow(color: BrutalistColors.dark, radius: 0, x: configuration.isPressed ? 0 : 3, y: configuration.isPressed ? 0 : 3)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Main View

public struct VoiceSwapMainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = VoiceSwapViewModel()
    @ObservedObject private var walletManager = WalletConnectManager.shared
    @State private var showingSettings = false
    @State private var testCommand = ""
    @State private var showWalletSheet = false

    public init() {}

    public var body: some View {
        ZStack {
            // Background
            BrutalistColors.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection

                    // Wallet Connection Card
                    walletConnectionCard

                    // Balance Card (only show if wallet connected)
                    if walletManager.isConnected {
                        balanceCard
                    }

                    // Payment Flow State
                    paymentFlowCard

                    // Voice Command Testing (Development)
                    #if DEBUG
                    testingSection
                    #endif
                }
                .padding(20)
            }
        }
        .preferredColorScheme(.light)
        .task {
            if let address = walletManager.currentAddress {
                viewModel.setWalletAddress(address)
            }
        }
        .onChange(of: appState.pendingAction) { newAction in
            handlePendingAction(newAction)
        }
        .onChange(of: walletManager.connectionState) { state in
            if case .connected(let address) = state {
                viewModel.setWalletAddress(address)
            }
        }
        .sheet(isPresented: $showWalletSheet) {
            BrutalistWalletConnectView(walletManager: walletManager, isPresented: $showWalletSheet)
        }
    }

    // MARK: - Deep Link Action Handler

    private func handlePendingAction(_ action: PendingAction) {
        switch action {
        case .none:
            break
        case .initiatePayment:
            if let payment = appState.pendingPayment {
                viewModel.initiatePaymentFromDeepLink(
                    recipient: payment.recipientAddress,
                    amount: payment.amount,
                    merchantName: payment.merchantName
                )
            }
            appState.clearPendingAction()
        case .checkBalance:
            Task { await viewModel.refreshBalances() }
            appState.clearPendingAction()
        case .connectGlasses:
            Task { await viewModel.connectToGlasses() }
            appState.clearPendingAction()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("VOICESWAP")
                    .font(.system(size: 36, weight: .black))
                    .foregroundColor(BrutalistColors.dark)

                Text("Voice-activated crypto payments")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(BrutalistColors.dark.opacity(0.6))
            }

            Spacer()

            // Logo/Icon
            ZStack {
                Circle()
                    .fill(BrutalistColors.primary)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Circle()
                            .stroke(BrutalistColors.dark, lineWidth: 3)
                    )
                    .shadow(color: BrutalistColors.dark, radius: 0, x: 2, y: 2)

                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(BrutalistColors.dark)
            }
        }
        .padding(.bottom, 10)
    }

    // MARK: - Wallet Connection Card

    private var walletIconColor: Color {
        if walletManager.isConnected {
            return BrutalistColors.success
        } else if case .connecting = walletManager.connectionState {
            return BrutalistColors.accent
        } else {
            return BrutalistColors.primary
        }
    }

    private var walletIconName: String {
        if walletManager.isConnected {
            return "checkmark.circle.fill"
        } else if case .connecting = walletManager.connectionState {
            return "arrow.triangle.2.circlepath"
        } else {
            return "wallet.pass"
        }
    }

    private var walletConnectionCard: some View {
        BrutalistCard(backgroundColor: walletManager.isConnected ? BrutalistColors.success.opacity(0.2) : BrutalistColors.cardBg) {
            VStack(spacing: 12) {
                HStack(spacing: 16) {
                    // Wallet icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(walletIconColor)
                            .frame(width: 50, height: 50)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(BrutalistColors.dark, lineWidth: 2)
                            )

                        Image(systemName: walletIconName)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(BrutalistColors.dark)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        if walletManager.isConnected, let address = walletManager.currentAddress {
                            Text("CONNECTED")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(BrutalistColors.dark)

                            HStack(spacing: 6) {
                                Text("\(address.prefix(6))...\(address.suffix(4))")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(BrutalistColors.dark.opacity(0.6))

                                if let walletName = walletManager.connectedWallet?.walletName {
                                    Text("(\(walletName))")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(BrutalistColors.dark.opacity(0.4))
                                }
                            }
                        } else if case .connecting = walletManager.connectionState {
                            Text("CONNECTING...")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(BrutalistColors.dark)

                            Text("Return here after signing")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(BrutalistColors.accent)
                        } else {
                            Text("NO WALLET")
                                .font(.system(size: 14, weight: .black))
                                .foregroundColor(BrutalistColors.dark)

                            Text("Connect to start")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(BrutalistColors.dark.opacity(0.6))
                        }
                    }

                    Spacer()

                    // Single action button - either disconnect or connect
                    Button {
                        print("[VoiceSwap] Wallet button tapped, isConnected: \(walletManager.isConnected)")
                        if walletManager.isConnected {
                            walletManager.disconnect()
                        } else {
                            print("[VoiceSwap] Calling walletManager.connect()")
                            walletManager.connect()
                        }
                    } label: {
                        Text(walletManager.isConnected ? "X" : "+")
                            .font(.system(size: 24, weight: .black))
                            .foregroundColor(BrutalistColors.dark)
                            .frame(width: 44, height: 44)
                            .background(walletManager.isConnected ? BrutalistColors.accent : BrutalistColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(BrutalistColors.dark, lineWidth: 2)
                            )
                    }
                }

                // Network switch button (only show if connected but not on Unichain)
                if walletManager.isConnected {
                    if let wallet = walletManager.connectedWallet, wallet.chainId != 130 {
                        Button {
                            Task {
                                await walletManager.switchToUnichain()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("SWITCH TO UNICHAIN")
                                    .font(.system(size: 11, weight: .black))
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundColor(BrutalistColors.dark)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(BrutalistColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(BrutalistColors.dark, lineWidth: 2)
                            )
                        }
                    } else {
                        // On Unichain - show confirmation
                        HStack(spacing: 6) {
                            Circle()
                                .fill(BrutalistColors.success)
                                .frame(width: 8, height: 8)
                            Text("UNICHAIN")
                                .font(.system(size: 10, weight: .black))
                                .foregroundColor(BrutalistColors.dark.opacity(0.6))
                        }
                    }
                }
            }
            .padding(16)
        }
        // Force UI refresh when connection state changes
        .id("wallet-card-\(walletManager.isConnected)-\(walletManager.currentAddress ?? "none")")
    }

    // MARK: - Balance Card

    private var balanceCard: some View {
        BrutalistCard(backgroundColor: BrutalistColors.primary) {
            VStack(spacing: 16) {
                HStack {
                    Text("BALANCE")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(BrutalistColors.dark.opacity(0.6))

                    Spacer()

                    Button(action: {
                        Task { await viewModel.refreshBalances() }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(BrutalistColors.dark)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("$\(viewModel.walletBalance)")
                        .font(.system(size: 56, weight: .black))
                        .foregroundColor(BrutalistColors.dark)

                    Text("USD")
                        .font(.system(size: 18, weight: .black))
                        .foregroundColor(BrutalistColors.dark.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(BrutalistColors.dark)
                            .frame(width: 8, height: 8)

                        Text("\(viewModel.ethBalance) ETH")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(BrutalistColors.dark)
                    }

                    Spacer()

                    Text("UNICHAIN")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(BrutalistColors.dark)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(BrutalistColors.cardBg)
                        .clipShape(RoundedRectangle(cornerRadius: 2))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(BrutalistColors.dark, lineWidth: 2)
                        )
                }
            }
            .padding(20)
        }
    }

    // MARK: - Payment Flow Card

    private var paymentFlowCard: some View {
        BrutalistCard {
            VStack(spacing: 20) {
                // State indicator
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(stateColor)
                            .frame(width: 40, height: 40)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(BrutalistColors.dark, lineWidth: 2)
                            )

                        Image(systemName: stateIcon)
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(BrutalistColors.dark)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stateText.uppercased())
                            .font(.system(size: 16, weight: .black))
                            .foregroundColor(BrutalistColors.dark)

                        Text(stateSubtext)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(BrutalistColors.dark.opacity(0.6))
                    }

                    Spacer()
                }

                // State-specific content
                stateContent

                // Action buttons based on state
                actionButtons
            }
            .padding(20)
        }
    }

    private var stateColor: Color {
        switch viewModel.flowState {
        case .idle: return BrutalistColors.cardBg
        case .listening: return BrutalistColors.success
        case .processing: return BrutalistColors.primary
        case .scanningQR: return BrutalistColors.primary
        case .awaitingConfirmation: return BrutalistColors.accent
        case .executing: return BrutalistColors.primary
        case .success: return BrutalistColors.success
        case .failed: return BrutalistColors.accent
        case .cancelled: return BrutalistColors.cardBg
        }
    }

    private var stateIcon: String {
        switch viewModel.flowState {
        case .idle: return "mic"
        case .listening: return "waveform"
        case .processing: return "brain"
        case .scanningQR: return "qrcode"
        case .awaitingConfirmation: return "exclamationmark"
        case .executing: return "arrow.right"
        case .success: return "checkmark"
        case .failed: return "xmark"
        case .cancelled: return "arrow.uturn.backward"
        }
    }

    private var stateText: String {
        switch viewModel.flowState {
        case .idle: return "Ready"
        case .listening: return "Listening"
        case .processing: return "Processing"
        case .scanningQR: return "Scan QR"
        case .awaitingConfirmation: return "Confirm"
        case .executing: return "Sending"
        case .success: return "Done!"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    private var stateSubtext: String {
        switch viewModel.flowState {
        case .idle: return "Tap to start voice command"
        case .listening: return "Say your command..."
        case .processing: return "Understanding your request"
        case .scanningQR: return "Point at merchant QR"
        case .awaitingConfirmation: return "Review and confirm"
        case .executing: return "Processing payment"
        case .success: return "Payment complete"
        case .failed: return "Something went wrong"
        case .cancelled: return "Transaction cancelled"
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.flowState {
        case .listening:
            VStack(spacing: 12) {
                // Animated bars
                HStack(spacing: 6) {
                    ForEach(0..<7, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(BrutalistColors.success)
                            .frame(width: 8, height: CGFloat.random(in: 20...50))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(BrutalistColors.dark, lineWidth: 1)
                            )
                    }
                }
                .frame(height: 50)

                if !viewModel.lastVoiceCommand.isEmpty {
                    Text("\"\(viewModel.lastVoiceCommand)\"")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(BrutalistColors.dark.opacity(0.6))
                        .italic()
                }
            }

        case .awaitingConfirmation(let amount, let merchant):
            VStack(spacing: 16) {
                // Amount display
                HStack {
                    Text(amount)
                        .font(.system(size: 48, weight: .black))
                        .foregroundColor(BrutalistColors.dark)

                    Text("USDC")
                        .font(.system(size: 20, weight: .black))
                        .foregroundColor(BrutalistColors.dark.opacity(0.6))
                }

                // Arrow
                Image(systemName: "arrow.down")
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(BrutalistColors.dark)

                // Recipient
                Text(merchant.uppercased())
                    .font(.system(size: 16, weight: .black))
                    .foregroundColor(BrutalistColors.dark)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(BrutalistColors.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(BrutalistColors.dark, lineWidth: 2)
                    )

                if viewModel.needsSwap, let token = viewModel.swapFromToken {
                    Text("SWAPPING FROM \(token)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(BrutalistColors.accent)
                }
            }
            .padding(.vertical, 10)

        case .success(let txHash):
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(BrutalistColors.success)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Circle()
                                .stroke(BrutalistColors.dark, lineWidth: 3)
                        )

                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .black))
                        .foregroundColor(BrutalistColors.dark)
                }

                Text("PAYMENT SENT!")
                    .font(.system(size: 20, weight: .black))
                    .foregroundColor(BrutalistColors.dark)

                if txHash != "pending" {
                    Text("TX: \(txHash.prefix(12))...")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalistColors.dark.opacity(0.6))
                }
            }
            .padding(.vertical, 10)

        case .failed(let error):
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(BrutalistColors.accent)
                        .frame(width: 80, height: 80)
                        .overlay(
                            Circle()
                                .stroke(BrutalistColors.dark, lineWidth: 3)
                        )

                    Image(systemName: "xmark")
                        .font(.system(size: 40, weight: .black))
                        .foregroundColor(BrutalistColors.dark)
                }

                Text(error.uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(BrutalistColors.dark.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 10)

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch viewModel.flowState {
        case .idle:
            BrutalistButton("Start Listening", icon: "mic.fill", backgroundColor: BrutalistColors.success) {
                viewModel.startListening()
            }

        case .listening:
            BrutalistButton("Stop", icon: "stop.fill", backgroundColor: BrutalistColors.accent) {
                viewModel.stopListening()
            }

        case .awaitingConfirmation:
            HStack(spacing: 12) {
                BrutalistButton("Cancel", icon: "xmark", backgroundColor: BrutalistColors.cardBg) {
                    viewModel.cancelPayment()
                }

                BrutalistButton("Confirm", icon: "checkmark", backgroundColor: BrutalistColors.success) {
                    Task { await viewModel.confirmPayment() }
                }
            }

        case .success, .failed, .cancelled:
            BrutalistButton("Done", icon: "arrow.right") {
                viewModel.reset()
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Testing Section (Debug only)

    #if DEBUG
    @State private var testMerchantWallet = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb7"
    @State private var testPaymentAmount = "5"

    private var testingSection: some View {
        BrutalistCard {
            VStack(spacing: 16) {
                Text("DEV TOOLS")
                    .font(.system(size: 12, weight: .black))
                    .foregroundColor(BrutalistColors.dark.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Voice command input
                HStack(spacing: 8) {
                    TextField("Voice command...", text: $testCommand)
                        .font(.system(size: 14, weight: .medium))
                        .padding(12)
                        .background(BrutalistColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(BrutalistColors.dark, lineWidth: 2)
                        )

                    Button(action: {
                        Task {
                            await viewModel.processVoiceCommand(testCommand)
                            testCommand = ""
                        }
                    }) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(BrutalistColors.dark)
                            .frame(width: 44, height: 44)
                            .background(BrutalistColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(BrutalistColors.dark, lineWidth: 2)
                            )
                    }
                }

                // Quick commands
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(["Balance", "Pay $10", "Confirm", "Cancel"], id: \.self) { cmd in
                            Button(action: {
                                Task { await viewModel.processVoiceCommand(cmd) }
                            }) {
                                Text(cmd.uppercased())
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(BrutalistColors.dark)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(BrutalistColors.background)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(BrutalistColors.dark, lineWidth: 2)
                                    )
                            }
                        }
                    }
                }

                // Direct payment test
                HStack(spacing: 8) {
                    TextField("$", text: $testPaymentAmount)
                        .font(.system(size: 14, weight: .bold))
                        .keyboardType(.decimalPad)
                        .frame(width: 60)
                        .padding(10)
                        .background(BrutalistColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(BrutalistColors.dark, lineWidth: 2)
                        )

                    Text("USDC")
                        .font(.system(size: 12, weight: .black))
                        .foregroundColor(BrutalistColors.dark.opacity(0.6))

                    Spacer()

                    Button(action: {
                        viewModel.initiatePaymentFromDeepLink(
                            recipient: testMerchantWallet,
                            amount: testPaymentAmount,
                            merchantName: "Test Merchant"
                        )
                    }) {
                        Text("PAY NOW")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(BrutalistColors.dark)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(BrutalistColors.success)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(BrutalistColors.dark, lineWidth: 2)
                            )
                    }
                }

                if !viewModel.lastResponse.isEmpty {
                    Text(viewModel.lastResponse)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BrutalistColors.success)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(16)
        }
    }
    #endif
}

// MARK: - Brutalist Wallet Connect View

struct BrutalistWalletConnectView: View {
    @ObservedObject var walletManager: WalletConnectManager
    @Binding var isPresented: Bool
    @State private var manualAddress: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            BrutalistColors.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        Text("CONNECT")
                            .font(.system(size: 28, weight: .black))
                            .foregroundColor(BrutalistColors.dark)

                        Spacer()

                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(BrutalistColors.dark)
                                .frame(width: 44, height: 44)
                                .background(BrutalistColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(BrutalistColors.dark, lineWidth: 2)
                                )
                        }
                    }
                    .padding(.top, 20)

                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(BrutalistColors.primary)
                            .frame(width: 80, height: 80)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(BrutalistColors.dark, lineWidth: 4)
                            )
                            .shadow(color: BrutalistColors.dark, radius: 0, x: 4, y: 4)

                        Image(systemName: "wallet.pass.fill")
                            .font(.system(size: 40, weight: .bold))
                            .foregroundColor(BrutalistColors.dark)
                    }
                    .padding(.vertical, 10)

                    // Unichain compatibility notice
                    VStack(spacing: 8) {
                        Text("UNICHAIN COMPATIBLE WALLETS")
                            .font(.system(size: 10, weight: .black))
                            .foregroundColor(BrutalistColors.dark.opacity(0.6))

                        Text("Use MetaMask or Rainbow for best experience")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(BrutalistColors.dark.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }

                    // Wallet buttons
                    VStack(spacing: 12) {
                        // WalletConnect (opens AppKit modal with all wallets)
                        brutalistWalletButton(
                            name: "WalletConnect",
                            subtitle: "MetaMask, Rainbow, etc.",
                            icon: "link.circle.fill",
                            color: Color(hex: "3396FF")
                        ) {
                            isPresented = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                walletManager.connect()
                            }
                        }
                    }

                    // Divider
                    HStack(spacing: 16) {
                        Rectangle()
                            .fill(BrutalistColors.dark.opacity(0.2))
                            .frame(height: 2)
                        Text("OR")
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(BrutalistColors.dark.opacity(0.4))
                        Rectangle()
                            .fill(BrutalistColors.dark.opacity(0.2))
                            .frame(height: 2)
                    }
                    .padding(.vertical, 8)

                    // Manual Input Section (always visible for reliability)
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            Image(systemName: "keyboard")
                                .font(.system(size: 14, weight: .bold))
                            Text("PASTE YOUR ADDRESS")
                                .font(.system(size: 12, weight: .black))
                        }
                        .foregroundColor(BrutalistColors.dark)

                        Text("Copy your wallet address and paste it below")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(BrutalistColors.dark.opacity(0.6))

                        TextField("0x...", text: $manualAddress)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding(14)
                            .background(BrutalistColors.cardBg)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(BrutalistColors.dark, lineWidth: 2)
                            )

                        // Validation feedback
                        if !manualAddress.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: isValidAddress ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .foregroundColor(isValidAddress ? BrutalistColors.success : BrutalistColors.accent)
                                Text(isValidAddress ? "Valid address" : "Invalid address (needs 42 characters starting with 0x)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(isValidAddress ? BrutalistColors.success : BrutalistColors.accent)
                            }
                        }

                        BrutalistButton("Link Wallet", icon: "link", backgroundColor: isValidAddress ? BrutalistColors.success : BrutalistColors.cardBg) {
                            walletManager.connectWithAddress(manualAddress)
                            isPresented = false
                        }
                        .disabled(!isValidAddress)
                        .opacity(isValidAddress ? 1 : 0.6)
                    }
                    .padding(16)
                    .background(BrutalistColors.cardBg)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(BrutalistColors.dark, lineWidth: 2)
                    )

                    Spacer(minLength: 20)

                    // Network info
                    VStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(BrutalistColors.accent)
                                .frame(width: 10, height: 10)
                                .overlay(
                                    Circle()
                                        .stroke(BrutalistColors.dark, lineWidth: 1)
                                )

                            Text("UNICHAIN MAINNET (CHAIN ID: 130)")
                                .font(.system(size: 11, weight: .black))
                                .foregroundColor(BrutalistColors.dark)
                        }

                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "server.rack")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(BrutalistColors.success)
                                Text("Payments executed via secure backend")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(BrutalistColors.dark.opacity(0.5))
                            }

                            HStack(spacing: 6) {
                                Image(systemName: "lock.shield.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(BrutalistColors.success)
                                Text("Your keys stay in your wallet")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(BrutalistColors.dark.opacity(0.5))
                            }
                        }
                    }
                    .padding(.bottom, 30)
                }
                .padding(.horizontal, 20)
            }
        }
    }

    // MARK: - Validation

    private var isValidAddress: Bool {
        manualAddress.count == 42 && manualAddress.hasPrefix("0x")
    }

    // MARK: - Wallet Button Component

    private func brutalistWalletButton(name: String, subtitle: String? = nil, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                // Icon box
                ZStack {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(0.2))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(BrutalistColors.dark, lineWidth: 2)
                        )

                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(name.uppercased())
                        .font(.system(size: 14, weight: .black))
                        .foregroundColor(BrutalistColors.dark)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(BrutalistColors.dark.opacity(0.6))
                    }
                }

                Spacer()

                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(BrutalistColors.dark)
            }
            .padding(12)
            .background(BrutalistColors.cardBg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(BrutalistColors.dark, lineWidth: 3)
            )
            .shadow(color: BrutalistColors.dark, radius: 0, x: 3, y: 3)
        }
        .buttonStyle(BrutalistButtonStyle())
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
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

struct VoiceSwapMainView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceSwapMainView()
    }
}
