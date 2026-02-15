/**
 * WalletSetupView.swift
 * "Deposit with" screen — Fomo-style card layout.
 * Shows after instant wallet creation OR from FUND button.
 * Three options:
 *   1. Crypto Wallet — connect MetaMask and send (active refill)
 *   2. Receive — QR code + address (passive receive)
 *   3. Apple Pay — Coinbase Onramp (USDC on Base)
 */

import SwiftUI
import SafariServices
import CoreImage.CIFilterBuiltins

// MARK: - Safari sheet helper

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredControlTintColor = UIColor(Theme.accent)
        return vc
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - Deposit View

struct WalletSetupView: View {
    @ObservedObject var wallet = VoiceSwapWallet.shared
    @ObservedObject var walletConnect = WalletConnectManager.shared
    @State private var showCryptoWalletFund = false
    @State private var showReceiveQR = false
    @State private var showApplePayOnRamp = false
    @State private var onrampURL: URL?
    @State private var isLoadingOnramp = false
    @State private var copied = false
    var onComplete: () -> Void
    /// Called when user wants to connect a new wallet — parent should dismiss this sheet, open AppKit, then fund
    var onConnectAndFund: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                Button {
                    onComplete()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Theme.muted)
                }

                Spacer()

                Text("DEPOSIT")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(Theme.muted)
                    .tracking(2)

                Spacer()

                // Spacer for centering
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.clear)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            .padding(.bottom, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    // Wallet address pill
                    if wallet.isCreated {
                        walletAddressPill
                    }

                    // Header
                    VStack(spacing: 4) {
                        Text("Deposit with")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(Theme.dark)

                        Text("Fund your wallet to start paying")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                    // Deposit option cards
                    VStack(spacing: 12) {
                        // 1. Crypto Wallet — active refill via WalletConnect (any wallet)
                        depositCard(
                            title: "Crypto Wallet",
                            subtitle: walletConnect.isConnected
                                ? "Send from \(walletConnect.connectedWallet?.walletName ?? "wallet")"
                                : "Connect any wallet\nto send crypto",
                            icon: "arrow.down.circle.fill",
                            badge: nil
                        ) {
                            if walletConnect.isConnected {
                                // Already connected — go straight to fund sheet
                                showCryptoWalletFund = true
                            } else {
                                // Dismiss this sheet, let parent open AppKit picker
                                onConnectAndFund?()
                            }
                        }

                        // 2. Receive — passive QR code / address sharing
                        depositCard(
                            title: "Receive",
                            subtitle: "Show QR code to receive\ncrypto from anyone",
                            icon: "qrcode",
                            badge: nil
                        ) {
                            showReceiveQR = true
                        }

                        // 3. Apple Pay — Coinbase Onramp (USDC on Base)
                        depositCard(
                            title: "Apple Pay",
                            subtitle: isLoadingOnramp
                                ? "Loading..."
                                : "Buy USDC instantly\nwith Apple Pay",
                            icon: "apple.logo",
                            badge: "New"
                        ) {
                            guard !isLoadingOnramp else { return }
                            fetchOnrampSession()
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.light)
        .sheet(isPresented: $showCryptoWalletFund) {
            FundWalletSheet(
                walletAddress: wallet.address,
                walletConnect: walletConnect
            )
        }
        .sheet(isPresented: $showReceiveQR) {
            ReceiveDepositSheet(wallet: wallet)
        }
        .sheet(isPresented: $showApplePayOnRamp) {
            if let url = onrampURL {
                SafariView(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    // MARK: - Wallet Address Pill

    private var walletAddressPill: some View {
        Button {
            UIPasteboard.general.string = wallet.address
            copied = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(Theme.accent)
                    .frame(width: 8, height: 8)

                Text(shortAddress)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(Theme.dark)

                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(copied ? Theme.accent : Theme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(hex: "F5F5F5"))
            .clipShape(Capsule())
        }
    }

    private var shortAddress: String {
        let addr = wallet.address
        guard addr.count > 10 else { return addr }
        return String(addr.prefix(6)) + "..." + String(addr.suffix(4))
    }

    // MARK: - Deposit Card

    private func depositCard(
        title: String,
        subtitle: String,
        icon: String,
        badge: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(Theme.dark)

                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.accent)
                                .clipShape(Capsule())
                        }
                    }

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.muted)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                }

                Spacer()

                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(hex: "F5F5F5"))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(Theme.dark)
                }
            }
            .padding(20)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Theme.border, lineWidth: 1)
            )
        }
    }

    // MARK: - Coinbase Onramp (Session Token)

    private static let apiBaseURL = "https://voiceswap.vercel.app"

    private func fetchOnrampSession() {
        isLoadingOnramp = true
        Task {
            do {
                let url = URL(string: "\(Self.apiBaseURL)/voiceswap/onramp/session-token")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")

                let body: [String: Any] = [
                    "address": wallet.address,
                    "blockchains": ["base"],
                    "assets": ["USDC"]
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, response) = try await URLSession.shared.data(for: request)
                let httpResponse = response as? HTTPURLResponse

                guard httpResponse?.statusCode == 200 else {
                    let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
                    print("[Onramp] Backend error (\(httpResponse?.statusCode ?? 0)): \(errorText)")
                    await MainActor.run { isLoadingOnramp = false }
                    return
                }

                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataDict = json["data"] as? [String: Any],
                      let onrampUrlString = dataDict["onrampUrl"] as? String,
                      let parsedURL = URL(string: onrampUrlString) else {
                    print("[Onramp] Failed to parse session token response")
                    await MainActor.run { isLoadingOnramp = false }
                    return
                }

                await MainActor.run {
                    onrampURL = parsedURL
                    isLoadingOnramp = false
                    showApplePayOnRamp = true
                }
            } catch {
                print("[Onramp] Error fetching session token: \(error)")
                await MainActor.run { isLoadingOnramp = false }
            }
        }
    }
}

// MARK: - Receive Deposit Sheet (QR code + address for passive receive)

struct ReceiveDepositSheet: View {
    @ObservedObject var wallet: VoiceSwapWallet
    @State private var copied = false
    @Environment(\.dismiss) var dismiss

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
                Text("RECEIVE")
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

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    Text("Share this QR code or address\nto receive crypto")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Theme.muted)
                        .multilineTextAlignment(.center)

                    // QR Code
                    if let qrImage = generateQRCode(from: wallet.address) {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 200, height: 200)
                            .padding(20)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(Theme.border, lineWidth: 1)
                            )
                    }

                    // Address
                    VStack(spacing: 8) {
                        Text("YOUR ADDRESS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.muted)
                            .tracking(2)

                        Button {
                            UIPasteboard.general.string = wallet.address
                            copied = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                        } label: {
                            HStack(spacing: 8) {
                                Text(wallet.address)
                                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                                    .foregroundColor(Theme.dark)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(copied ? Theme.accent : Theme.muted)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(Color(hex: "F5F5F5"))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    // Network info
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 6, height: 6)
                        Text("Monad Network")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Theme.muted)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.accent.opacity(0.08))
                    .clipShape(Capsule())

                    // Instructions
                    VStack(alignment: .leading, spacing: 12) {
                        Text("ACCEPTS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Theme.muted)
                            .tracking(2)

                        HStack(spacing: 8) {
                            tokenPill("MON", color: "836EF9")
                            tokenPill("USDC", color: "2775CA")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(Color(hex: "FAFAFA"))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .preferredColorScheme(.light)
    }

    private func tokenPill(_ name: String, color: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(hex: color))
                .frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.dark)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(hex: color).opacity(0.1))
        .clipShape(Capsule())
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
