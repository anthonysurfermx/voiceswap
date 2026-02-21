/**
 * BetWhisperWalletView.swift
 * BetWhisper - Wallet management tab
 *
 * Shows wallet address, MON balance, QR receive, export key.
 * Dark theme consistent with BetWhisper design language.
 */

import SwiftUI
import LocalAuthentication
import CoreImage.CIFilterBuiltins

struct BetWhisperWalletView: View {
    @ObservedObject private var wallet = VoiceSwapWallet.shared
    @State private var monBalance: Double = 0
    @State private var isLoadingBalance = false
    @State private var showReceiveSheet = false
    @State private var showExportSheet = false
    @State private var exportedKey: String? = nil
    @State private var copied = false
    @State private var balanceError: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Wallet")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                    if wallet.isCreated {
                        Button {
                            fetchBalance()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.white.opacity(0.4))
                                .rotationEffect(.degrees(isLoadingBalance ? 360 : 0))
                                .animation(isLoadingBalance ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoadingBalance)
                        }
                    }
                }
                .padding(.bottom, 4)

                if wallet.isCreated {
                    walletContent
                } else {
                    noWalletView
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .onAppear {
            if wallet.isCreated {
                fetchBalance()
            }
        }
        .sheet(isPresented: $showReceiveSheet) {
            BetWhisperReceiveSheet(address: wallet.address)
        }
        .sheet(isPresented: $showExportSheet) {
            if let key = exportedKey {
                BetWhisperExportKeySheet(privateKey: key)
            }
        }
    }

    // MARK: - Wallet Content

    private var walletContent: some View {
        VStack(spacing: 16) {
            // Balance card
            VStack(spacing: 12) {
                Text("BALANCE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .tracking(1.5)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if isLoadingBalance {
                        ProgressView()
                            .tint(.white.opacity(0.5))
                    } else {
                        Text(String(format: "%.4f", monBalance))
                            .font(.system(size: 36, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("MON")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                }

                if let error = balanceError {
                    Text(error)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Color(hex: "EF4444").opacity(0.8))
                }
            }
            .padding(16)
            .background(Rectangle().fill(Color.white.opacity(0.04)))
            .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 1))

            // Address
            Button {
                UIPasteboard.general.string = wallet.address
                copied = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ADDRESS")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                        .tracking(1.5)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: "836EF9"))
                            .frame(width: 8, height: 8)

                        Text(wallet.address)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(copied ? Color(hex: "10B981") : .white.opacity(0.3))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Rectangle().fill(Color.white.opacity(0.04)))
                .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 1))
            }

            // Network
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "10B981"))
                    .frame(width: 6, height: 6)
                Text("Monad Mainnet")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text("Chain 143")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
            }
            .padding(12)
            .background(Rectangle().fill(Color.white.opacity(0.02)))
            .overlay(Rectangle().stroke(Color.white.opacity(0.04), lineWidth: 1))

            // Action buttons
            VStack(spacing: 10) {
                // Receive
                actionButton(icon: "qrcode", label: "RECEIVE MON", subtitle: "Show QR code") {
                    showReceiveSheet = true
                }

                // Export key
                actionButton(icon: "key.fill", label: "EXPORT PRIVATE KEY", subtitle: "Face ID required") {
                    authenticateAndExport()
                }

                // iCloud backup
                HStack(spacing: 12) {
                    Image(systemName: "icloud.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.5))
                        .frame(width: 36, height: 36)
                        .background(Rectangle().fill(Color.white.opacity(0.06)))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("iCLOUD BACKUP")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.7))
                            .tracking(1)
                        Text("Sync wallet to iCloud Keychain")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { wallet.isBackedUpToiCloud },
                        set: { newValue in
                            if newValue {
                                wallet.enableiCloudBackup()
                            }
                        }
                    ))
                    .tint(Color(hex: "836EF9"))
                }
                .padding(12)
                .background(Rectangle().fill(Color.white.opacity(0.04)))
                .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 1))
            }
        }
    }

    // MARK: - No Wallet View

    private var noWalletView: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 60)

            Image(systemName: "wallet.bifold")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.15))

            Text("No Wallet")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white.opacity(0.6))

            Text("Create a wallet to start placing bets\nwith MON on Monad.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)

            Button {
                createWallet()
            } label: {
                Text("CREATE WALLET")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Rectangle().fill(Color.white))
            }
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action Button

    private func actionButton(icon: String, label: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.5))
                    .frame(width: 36, height: 36)
                    .background(Rectangle().fill(Color.white.opacity(0.06)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .tracking(1)
                    Text(subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white.opacity(0.15))
            }
            .padding(12)
            .background(Rectangle().fill(Color.white.opacity(0.04)))
            .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
    }

    // MARK: - Create Wallet

    private func createWallet() {
        do {
            try VoiceSwapWallet.shared.create()
            fetchBalance()
        } catch {
            print("[Wallet] Creation failed: \(error)")
        }
    }

    // MARK: - Fetch Balance

    private func fetchBalance() {
        guard wallet.isCreated else { return }
        isLoadingBalance = true
        balanceError = nil

        Task {
            do {
                let balance = try await fetchMONBalance(address: wallet.address)
                await MainActor.run {
                    monBalance = balance
                    isLoadingBalance = false
                }
            } catch {
                await MainActor.run {
                    balanceError = "Failed to fetch balance"
                    isLoadingBalance = false
                }
            }
        }
    }

    private func fetchMONBalance(address: String) async throws -> Double {
        let url = URL(string: "https://rpc.monad.xyz")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "method": "eth_getBalance",
            "params": [address, "latest"],
            "id": 1
        ])

        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hexResult = json["result"] as? String else {
            throw URLError(.badServerResponse)
        }

        // Parse hex wei to MON (18 decimals)
        let hex = hexResult.hasPrefix("0x") ? String(hexResult.dropFirst(2)) : hexResult
        guard let wei = UInt64(hex, radix: 16) else { return 0 }
        return Double(wei) / 1e18
    }

    // MARK: - Export Key

    private func authenticateAndExport() {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Fallback: show key without biometrics (simulator)
            exportedKey = wallet.exportPrivateKey()
            showExportSheet = true
            return
        }

        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Export your private key") { success, _ in
            DispatchQueue.main.async {
                if success {
                    exportedKey = wallet.exportPrivateKey()
                    showExportSheet = true
                }
            }
        }
    }
}

// MARK: - Receive Sheet

struct BetWhisperReceiveSheet: View {
    let address: String
    @State private var copied = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    Text("RECEIVE")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(2)
                    Spacer()
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.clear)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        Text("Share this QR code or address\nto receive MON")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.4))
                            .multilineTextAlignment(.center)

                        // QR Code
                        if let qrImage = generateQRCode(from: address) {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 200, height: 200)
                                .padding(20)
                                .background(Color.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        // Address
                        VStack(spacing: 8) {
                            Text("YOUR ADDRESS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.25))
                                .tracking(2)

                            Button {
                                UIPasteboard.general.string = address
                                copied = true
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(address)
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.7))
                                        .lineLimit(1)
                                        .truncationMode(.middle)

                                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(copied ? Color(hex: "10B981") : .white.opacity(0.3))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Rectangle().fill(Color.white.opacity(0.06)))
                                .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                            }
                        }

                        // Network
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(hex: "836EF9"))
                                .frame(width: 6, height: 6)
                            Text("Monad Network")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color(hex: "836EF9").opacity(0.1))

                        // Accepts
                        HStack(spacing: 8) {
                            tokenPill("MON", color: "836EF9")
                            tokenPill("USDC", color: "2775CA")
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func tokenPill(_ name: String, color: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: color))
                .frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: color).opacity(0.15))
    }

    private func generateQRCode(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Export Key Sheet

struct BetWhisperExportKeySheet: View {
    let privateKey: String
    @State private var copied = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white.opacity(0.4))
                    }
                    Spacer()
                    Text("PRIVATE KEY")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .tracking(2)
                    Spacer()
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.clear)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 32)

                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 32))
                        .foregroundColor(Color(hex: "F59E0B"))

                    Text("Never share your private key.\nAnyone with this key can access your funds.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "F59E0B").opacity(0.8))
                        .multilineTextAlignment(.center)

                    // Key display
                    Button {
                        UIPasteboard.general.string = privateKey
                        copied = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    } label: {
                        VStack(spacing: 8) {
                            Text(privateKey)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                                .multilineTextAlignment(.center)
                                .lineLimit(3)

                            HStack(spacing: 4) {
                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 10, weight: .bold))
                                Text(copied ? "Copied" : "Tap to copy")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                            }
                            .foregroundColor(copied ? Color(hex: "10B981") : .white.opacity(0.3))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(Rectangle().fill(Color.white.opacity(0.04)))
                        .overlay(Rectangle().stroke(Color(hex: "F59E0B").opacity(0.3), lineWidth: 1))
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}
