/**
 * VoiceSwapMainView.swift
 * VoiceSwap - Main SwiftUI View
 *
 * Primary interface for the VoiceSwap iOS app.
 * Shows connection status, balance, and payment flow.
 */

import SwiftUI

public struct VoiceSwapMainView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = VoiceSwapViewModel()
    @State private var showingSettings = false
    @State private var testCommand = ""

    public init() {}

    public var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: "1a1a2e"),
                        Color(hex: "16213e")
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Header
                    headerSection

                    // Connection Status
                    connectionStatusCard

                    // Balance Card
                    balanceCard

                    // Payment Flow State
                    paymentFlowCard

                    // Voice Command Testing (Development)
                    #if DEBUG
                    testingSection
                    #endif

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarHidden(true)
        }
        .preferredColorScheme(.dark)
        .task {
            // Set demo wallet address for testing
            viewModel.setWalletAddress("0x2749A654FeE5CEc3a8644a27E7498693d0132759")
        }
        .onChange(of: appState.pendingAction) { _, newAction in
            handlePendingAction(newAction)
        }
    }

    // MARK: - Deep Link Action Handler

    private func handlePendingAction(_ action: PendingAction) {
        switch action {
        case .none:
            break

        case .initiatePayment:
            if let payment = appState.pendingPayment {
                // Set up payment from deep link
                viewModel.initiatePaymentFromDeepLink(
                    recipient: payment.recipientAddress,
                    amount: payment.amount,
                    merchantName: payment.merchantName
                )
            }
            appState.clearPendingAction()

        case .checkBalance:
            Task {
                await viewModel.refreshBalances()
            }
            appState.clearPendingAction()

        case .connectGlasses:
            Task {
                await viewModel.connectToGlasses()
            }
            appState.clearPendingAction()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("VoiceSwap")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)

                Text("Voice-activated crypto payments")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }

            Spacer()

            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
        }
    }

    // MARK: - Connection Status

    private var connectionStatusCard: some View {
        HStack {
            // Glasses icon
            Image(systemName: viewModel.isConnectedToGlasses ? "glasses" : "glasses")
                .font(.title)
                .foregroundColor(viewModel.isConnectedToGlasses ? .green : .gray)

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.isConnectedToGlasses ? "Meta Ray-Ban Connected" : "Not Connected")
                    .font(.headline)
                    .foregroundColor(.white)

                if viewModel.isConnectedToGlasses {
                    Text("Battery: \(viewModel.glassesBatteryLevel)%")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            Button(action: {
                Task {
                    if viewModel.isConnectedToGlasses {
                        viewModel.disconnectGlasses()
                    } else {
                        await viewModel.connectToGlasses()
                    }
                }
            }) {
                Text(viewModel.isConnectedToGlasses ? "Disconnect" : "Connect")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(viewModel.isConnectedToGlasses ? Color.red.opacity(0.3) : Color.blue.opacity(0.3))
                    )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Balance Card

    private var balanceCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Your Balance")
                    .font(.headline)
                    .foregroundColor(.gray)

                Spacer()

                Button(action: {
                    Task { await viewModel.refreshBalances() }
                }) {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(.blue)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$\(viewModel.walletBalance)")
                    .font(.system(size: 48, weight: .bold))
                    .foregroundColor(.white)

                Text("USDC")
                    .font(.title3)
                    .foregroundColor(.gray)
            }

            HStack {
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                    .foregroundColor(.blue)

                Text("\(viewModel.ethBalance) ETH")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                Spacer()

                Text("Unichain")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }

    // MARK: - Payment Flow Card

    private var paymentFlowCard: some View {
        VStack(spacing: 16) {
            // State indicator
            HStack {
                Circle()
                    .fill(stateColor)
                    .frame(width: 12, height: 12)

                Text(stateText)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()
            }

            // State-specific content
            stateContent

            // Action buttons based on state
            actionButtons
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }

    private var stateColor: Color {
        switch viewModel.flowState {
        case .idle: return .gray
        case .listening: return .green
        case .processing: return .yellow
        case .scanningQR: return .blue
        case .awaitingConfirmation: return .orange
        case .executing: return .purple
        case .success: return .green
        case .failed: return .red
        case .cancelled: return .gray
        }
    }

    private var stateText: String {
        switch viewModel.flowState {
        case .idle: return "Ready"
        case .listening: return "Listening..."
        case .processing: return "Processing..."
        case .scanningQR: return "Scan QR Code"
        case .awaitingConfirmation: return "Confirm Payment"
        case .executing: return "Executing..."
        case .success: return "Success!"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    @ViewBuilder
    private var stateContent: some View {
        switch viewModel.flowState {
        case .idle:
            Text("Say \"Hey VoiceSwap\" or tap the button to start")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)

        case .listening:
            VStack(spacing: 8) {
                // Animated listening indicator
                HStack(spacing: 4) {
                    ForEach(0..<5) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.green)
                            .frame(width: 4, height: CGFloat.random(in: 10...30))
                            .animation(
                                Animation.easeInOut(duration: 0.5)
                                    .repeatForever()
                                    .delay(Double(i) * 0.1),
                                value: UUID()
                            )
                    }
                }
                .frame(height: 30)

                if !viewModel.lastVoiceCommand.isEmpty {
                    Text("\"\(viewModel.lastVoiceCommand)\"")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .italic()
                }
            }

        case .awaitingConfirmation(let amount, let merchant):
            VStack(spacing: 12) {
                Text("Pay \(amount) USDC")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text("to \(merchant)")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                if viewModel.needsSwap, let token = viewModel.swapFromToken {
                    Text("(Swapping from \(token))")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

        case .success(let txHash):
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)

                Text("Payment Successful")
                    .font(.headline)
                    .foregroundColor(.white)

                if txHash != "pending" {
                    Text("TX: \(txHash.prefix(10))...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

        case .failed(let error):
            VStack(spacing: 8) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.red)

                Text(error)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch viewModel.flowState {
        case .idle:
            Button(action: { viewModel.startListening() }) {
                HStack {
                    Image(systemName: "mic.fill")
                    Text("Start Listening")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

        case .listening:
            Button(action: { viewModel.stopListening() }) {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.red.opacity(0.8))
                .foregroundColor(.white)
                .cornerRadius(12)
            }

        case .awaitingConfirmation:
            HStack(spacing: 12) {
                Button(action: { viewModel.cancelPayment() }) {
                    HStack {
                        Image(systemName: "xmark")
                        Text("Cancel")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red.opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }

                Button(action: {
                    Task { await viewModel.confirmPayment() }
                }) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Confirm")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            }

        case .success, .failed, .cancelled:
            Button(action: { viewModel.reset() }) {
                Text("Done")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }

        default:
            EmptyView()
        }
    }

    // MARK: - Testing Section (Debug only)

    #if DEBUG
    private var testingSection: some View {
        VStack(spacing: 12) {
            Text("Test Voice Commands")
                .font(.caption)
                .foregroundColor(.gray)

            HStack {
                TextField("Enter command...", text: $testCommand)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .foregroundColor(.black)

                Button("Send") {
                    Task {
                        await viewModel.processVoiceCommand(testCommand)
                        testCommand = ""
                    }
                }
                .buttonStyle(.bordered)
            }

            // Quick test buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(["Cuanto tengo", "Paga 10 dolares", "Confirmar", "Cancelar"], id: \.self) { cmd in
                        Button(cmd) {
                            Task { await viewModel.processVoiceCommand(cmd) }
                        }
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.2))
                        .cornerRadius(16)
                    }
                }
            }

            if !viewModel.lastResponse.isEmpty {
                Text("Response: \(viewModel.lastResponse)")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.05))
        )
    }
    #endif
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
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
