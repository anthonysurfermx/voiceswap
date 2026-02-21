/**
 * BetWhisperWalletView.swift
 * BetWhisper - Wallet management tab
 *
 * Face ID gated. Shows wallet address, MON balance, QR receive,
 * WalletConnect fund, export key.
 * Dark theme consistent with BetWhisper design language.
 */

import SwiftUI
import LocalAuthentication
import CoreImage.CIFilterBuiltins

struct BetWhisperWalletView: View {
    @ObservedObject private var wallet = VoiceSwapWallet.shared
    @ObservedObject private var walletConnect = WalletConnectManager.shared
    @ObservedObject private var security = SecuritySettings.shared

    @State private var isAuthenticated = false
    @State private var monBalance: Double = 0
    @State private var isLoadingBalance = false
    @State private var showReceiveSheet = false
    @State private var showFundSheet = false
    @State private var showExportSheet = false
    @State private var exportedKey: String? = nil
    @State private var copied = false
    @State private var balanceError: String? = nil

    var body: some View {
        ZStack {
            if wallet.isCreated && !isAuthenticated {
                faceIDGate
            } else if wallet.isCreated {
                walletScrollView
            } else {
                noWalletView
            }
        }
        .onAppear {
            if wallet.isCreated && !isAuthenticated {
                authenticateToView()
            }
        }
        .sheet(isPresented: $showReceiveSheet) {
            BetWhisperReceiveSheet(address: wallet.address)
        }
        .sheet(isPresented: $showFundSheet) {
            BetWhisperFundSheet(
                walletAddress: wallet.address,
                walletConnect: walletConnect,
                onFunded: { fetchBalance() }
            )
        }
        .sheet(isPresented: $showExportSheet) {
            if let key = exportedKey {
                BetWhisperExportKeySheet(privateKey: key)
            }
        }
    }

    // MARK: - Face ID Gate

    private var faceIDGate: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "faceid")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.2))

            Text("Wallet Locked")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white.opacity(0.6))

            Text("Authenticate to view your wallet")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.3))

            Button {
                authenticateToView()
            } label: {
                Text("UNLOCK")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Rectangle().fill(Color.white))
            }
            .padding(.horizontal, 48)

            Spacer()
        }
    }

    // MARK: - Wallet Scroll View

    private var walletScrollView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Wallet")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
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
                .padding(.bottom, 4)

                walletContent
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
        .onAppear {
            fetchBalance()
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
                // Fund from external wallet
                actionButton(
                    icon: "arrow.down.circle.fill",
                    label: "FUND WITH WALLET",
                    subtitle: walletConnect.isConnected
                        ? "Send MON from \(walletConnect.connectedWallet?.walletName ?? "wallet")"
                        : "Connect MetaMask or any wallet"
                ) {
                    if walletConnect.isConnected {
                        showFundSheet = true
                    } else {
                        // Open WalletConnect modal
                        walletConnect.connect()
                    }
                }

                // Receive QR
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
                                try? wallet.enableiCloudBackup()
                            }
                        }
                    ))
                    .tint(Color(hex: "836EF9"))
                }
                .padding(12)
                .background(Rectangle().fill(Color.white.opacity(0.04)))
                .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 1))
            }

            // WalletConnect status
            if walletConnect.isConnected {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color(hex: "10B981"))
                        .frame(width: 6, height: 6)
                    Text("External: \(truncateAddress(walletConnect.currentAddress ?? ""))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Button {
                        walletConnect.disconnect()
                    } label: {
                        Text("Disconnect")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "EF4444").opacity(0.7))
                    }
                }
                .padding(10)
                .background(Rectangle().fill(Color.white.opacity(0.02)))
                .overlay(Rectangle().stroke(Color.white.opacity(0.04), lineWidth: 1))
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

            Spacer()
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

    // MARK: - Helpers

    private func truncateAddress(_ addr: String) -> String {
        guard addr.count > 10 else { return addr }
        return String(addr.prefix(6)) + "..." + String(addr.suffix(4))
    }

    // MARK: - Create Wallet

    private func createWallet() {
        do {
            try VoiceSwapWallet.shared.create()
            isAuthenticated = true
            fetchBalance()
        } catch {
            print("[Wallet] Creation failed: \(error)")
        }
    }

    // MARK: - Authentication

    private func authenticateToView() {
        Task {
            let passed = await security.authenticateWithBiometrics()
            await MainActor.run {
                isAuthenticated = passed
                if passed { fetchBalance() }
            }
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

        let hex = hexResult.hasPrefix("0x") ? String(hexResult.dropFirst(2)) : hexResult
        guard let wei = UInt64(hex, radix: 16) else { return 0 }
        return Double(wei) / 1e18
    }

    // MARK: - Export Key

    private func authenticateAndExport() {
        Task {
            let passed = await security.authenticateWithBiometrics()
            await MainActor.run {
                if passed {
                    exportedKey = wallet.exportPrivateKey()
                    showExportSheet = true
                }
            }
        }
    }
}

// MARK: - Fund Sheet (WalletConnect)

struct BetWhisperFundSheet: View {
    let walletAddress: String
    @ObservedObject var walletConnect: WalletConnectManager
    var onFunded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedAmount: String = "5"
    @State private var customAmount: String = ""
    @State private var isCustom = false
    @State private var isFunding = false
    @State private var fundingSuccess = false
    @State private var lastTxHash: String?
    @State private var txCopied = false
    @State private var error: String?
    @FocusState private var isAmountFocused: Bool

    private let presets = ["1", "5", "10", "25"]

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
                    Text("FUND WALLET")
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

                if fundingSuccess {
                    successView
                } else {
                    fundFormView
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Success

    private var successView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(Color(hex: "10B981"))

            Text("SENT!")
                .font(.system(size: 18, weight: .black, design: .monospaced))
                .foregroundColor(.white)
                .tracking(2)

            Text("Funds will arrive in a few seconds")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))

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
                            .foregroundColor(.white.opacity(0.4))
                        Image(systemName: txCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(txCopied ? Color(hex: "10B981") : .white.opacity(0.3))
                    }
                }
            }

            Spacer()

            Button {
                onFunded()
                dismiss()
            } label: {
                Text("DONE")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Rectangle().fill(Color.white))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Fund Form

    private var fundFormView: some View {
        VStack(spacing: 20) {
            Text("Send MON from\n\(walletConnect.connectedWallet?.walletName ?? "external wallet")")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)

            // Amount presets
            VStack(spacing: 12) {
                Text("SELECT AMOUNT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .tracking(2)

                HStack(spacing: 8) {
                    ForEach(presets, id: \.self) { preset in
                        Button {
                            selectedAmount = preset
                            isCustom = false
                            customAmount = ""
                            isAmountFocused = false
                        } label: {
                            Text("\(preset) MON")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(!isCustom && selectedAmount == preset ? .black : .white.opacity(0.5))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 10)
                                .background(
                                    Rectangle().fill(!isCustom && selectedAmount == preset
                                        ? Color.white
                                        : Color.white.opacity(0.06))
                                )
                                .overlay(
                                    Rectangle().stroke(!isCustom && selectedAmount == preset
                                        ? Color.clear
                                        : Color.white.opacity(0.08), lineWidth: 1)
                                )
                        }
                    }
                }

                // Custom amount
                HStack(spacing: 8) {
                    TextField("Custom", text: $customAmount)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .keyboardType(.decimalPad)
                        .focused($isAmountFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Rectangle().fill(isCustom ? Color.white.opacity(0.1) : Color.white.opacity(0.04)))
                        .overlay(Rectangle().stroke(isCustom ? Color.white.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1))
                        .onChange(of: customAmount) { _, _ in
                            if !customAmount.isEmpty { isCustom = true }
                        }

                    Text("MON")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 24)

            // Destination
            VStack(spacing: 4) {
                Text("TO")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .tracking(2)
                Text(String(walletAddress.prefix(8)) + "..." + String(walletAddress.suffix(6)))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(Rectangle().fill(Color.white.opacity(0.04)))
            .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 1))
            .padding(.horizontal, 24)

            if let error = error {
                Text(error)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: "EF4444"))
                    .padding(.horizontal, 24)
            }

            Spacer()

            // Send button
            Button {
                sendFunds()
            } label: {
                HStack(spacing: 8) {
                    if isFunding {
                        ProgressView()
                            .tint(.black)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Text(isFunding ? "APPROVE IN WALLET..." : "SEND MON")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .tracking(2)
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Rectangle().fill(isFunding ? Color.white.opacity(0.5) : Color.white))
            }
            .disabled(isFunding)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Send Funds

    /// Convert decimal amount to hex wei (18 decimals)
    private func amountToHexWei(_ amount: String) -> String? {
        guard let value = Double(amount), value > 0 else { return nil }
        let parts = amount.split(separator: ".", maxSplits: 1)
        let wholePart = String(parts[0])
        let fracPart = parts.count > 1 ? String(parts[1]) : ""
        let paddedFrac = String((fracPart + String(repeating: "0", count: 18)).prefix(18))
        let raw = wholePart + paddedFrac
        let trimmed = String(raw.drop(while: { $0 == "0" }))
        if trimmed.isEmpty { return nil }
        // Decimal to hex
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

    private func sendFunds() {
        isAmountFocused = false
        let amountStr = isCustom ? customAmount : selectedAmount
        guard !amountStr.isEmpty, let val = Double(amountStr), val > 0 else {
            error = "Enter a valid amount"
            return
        }

        guard let hexWei = amountToHexWei(amountStr) else {
            error = "Invalid amount"
            return
        }

        isFunding = true
        error = nil

        Task {
            do {
                let txHash = try await walletConnect.sendTransaction(
                    to: walletAddress,
                    value: hexWei,
                    data: nil
                )
                print("[Fund] Sent \(amountStr) MON, tx: \(txHash)")
                await MainActor.run {
                    lastTxHash = txHash
                    isFunding = false
                    fundingSuccess = true
                }
            } catch {
                print("[Fund] Error: \(error)")
                await MainActor.run {
                    isFunding = false
                    self.error = error.localizedDescription
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
