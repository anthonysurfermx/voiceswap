/**
 * BetWhisperPortfolioView.swift
 * BetWhisper - Portfolio tab showing active bets with real positions
 *
 * Face ID gate -> Fetch positions from API -> Show balance + sell buttons
 * Profound style: black bg, white text, sharp corners.
 */

import SwiftUI

// MARK: - API Models

struct BalanceResponse: Decodable {
    let positions: [PositionItem]
    let totalValue: Double
    let totalPnl: Double
    let monPrice: Double
    let count: Int
}

struct PositionItem: Decodable, Identifiable {
    var id: Int
    let marketSlug: String
    let side: String
    let shares: Double
    let avgPrice: Double
    let currentPrice: Double
    let costBasis: Double
    let currentValue: Double
    let pnl: Double
    let pnlPct: Double
    let tokenId: String
    let tickSize: String
    let negRisk: Bool
}

struct SellResponse: Decodable {
    let success: Bool?
    let sharesSold: Double?
    let usdReceived: Double?
    let price: Double?
    let polygonTxHash: String?
    let explorerUrl: String?
    let remainingShares: Double?
    let error: String?
    let monCashout: MonCashout?
}

struct MonCashout: Decodable {
    let monAmount: Double
    let txHash: String
    let explorerUrl: String
    let status: String
}

// MARK: - Portfolio View

struct BetWhisperPortfolioView: View {
    @ObservedObject private var walletManager = WalletConnectManager.shared
    @ObservedObject private var localWallet = VoiceSwapWallet.shared
    @ObservedObject private var security = SecuritySettings.shared

    @State private var positions: [PositionItem] = []
    @State private var totalValue: Double = 0
    @State private var totalPnl: Double = 0
    @State private var isLoading = false
    @State private var isAuthenticated = false
    @State private var sellInProgress: Int? = nil
    @State private var sellResult: String? = nil
    @State private var errorMessage: String? = nil

    private var isConnected: Bool {
        walletManager.isConnected || localWallet.isCreated
    }

    private var walletAddress: String? {
        if walletManager.isConnected {
            return walletManager.currentAddress
        } else if localWallet.isCreated {
            return localWallet.address
        }
        return nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                portfolioHeader

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        if isConnected {
                            if isAuthenticated {
                                balanceCard
                                positionsSection
                            } else {
                                authPrompt
                            }
                        } else {
                            connectPrompt
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 40)
                }
            }

            if isLoading {
                Color.black.opacity(0.6).ignoresSafeArea()
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear { authenticateIfNeeded() }
    }

    // MARK: - Authentication

    private func authenticateIfNeeded() {
        guard isConnected, !isAuthenticated else { return }
        Task {
            let passed = await security.authenticateWithBiometrics()
            await MainActor.run {
                isAuthenticated = passed
                if passed { fetchPositions() }
            }
        }
    }

    private func fetchPositions() {
        guard let addr = walletAddress else { return }
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let url = URL(string: "https://betwhisper.ai/api/bet?wallet=\(addr.lowercased())")!
                let (data, _) = try await URLSession.shared.data(from: url)

                struct BetResponse: Decodable {
                    let positions: [RawPosition]
                    let count: Int
                }
                struct RawPosition: Decodable {
                    let id: Int
                    let market_slug: String
                    let side: String
                    let shares: String
                    let avg_price: String
                    let total_usd: String
                    let token_id: String
                    let tick_size: String
                    let neg_risk: Bool
                }

                let response = try JSONDecoder().decode(BetResponse.self, from: data)

                await MainActor.run {
                    self.positions = response.positions.map { raw in
                        let shares = Double(raw.shares) ?? 0
                        let avgPrice = Double(raw.avg_price) ?? 0
                        let totalUsd = Double(raw.total_usd) ?? 0
                        return PositionItem(
                            id: raw.id,
                            marketSlug: raw.market_slug,
                            side: raw.side,
                            shares: shares,
                            avgPrice: avgPrice,
                            currentPrice: avgPrice, // We don't have live price from this endpoint
                            costBasis: totalUsd,
                            currentValue: shares * avgPrice,
                            pnl: 0,
                            pnlPct: 0,
                            tokenId: raw.token_id,
                            tickSize: raw.tick_size,
                            negRisk: raw.neg_risk
                        )
                    }
                    self.totalValue = self.positions.reduce(0) { $0 + $1.currentValue }
                    self.totalPnl = 0
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to load positions"
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Sell

    private func sellPosition(_ pos: PositionItem) {
        guard let addr = walletAddress else { return }
        sellInProgress = pos.id
        sellResult = nil

        Task {
            // Face ID before sell
            let passed = await security.authenticateWithBiometrics()
            guard passed else {
                await MainActor.run {
                    sellInProgress = nil
                    sellResult = "Face ID required"
                }
                return
            }

            do {
                let url = URL(string: "https://betwhisper.ai/api/bet/sell")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("ios", forHTTPHeaderField: "X-Platform")

                let body: [String: Any] = [
                    "wallet": addr.lowercased(),
                    "tokenId": pos.tokenId,
                    "shares": pos.shares,
                    "tickSize": pos.tickSize,
                    "negRisk": pos.negRisk,
                    "marketSlug": pos.marketSlug
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, _) = try await URLSession.shared.data(for: request)
                let response = try JSONDecoder().decode(SellResponse.self, from: data)

                await MainActor.run {
                    sellInProgress = nil
                    if response.success == true {
                        let usd = response.usdReceived ?? 0
                        if let mc = response.monCashout, mc.status == "sent" {
                            sellResult = "Sold for $\(String(format: "%.2f", usd)). \(String(format: "%.1f", mc.monAmount)) MON sent to your wallet."
                        } else {
                            sellResult = "Sold for $\(String(format: "%.2f", usd)). Cashout pending."
                        }
                        fetchPositions() // Refresh
                    } else {
                        sellResult = response.error ?? "Sell failed"
                    }
                }
            } catch {
                await MainActor.run {
                    sellInProgress = nil
                    sellResult = "Network error"
                }
            }
        }
    }

    // MARK: - Header

    private var portfolioHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Portfolio")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
                Text("YOUR POSITIONS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .tracking(1.5)
            }
            Spacer()
            if isConnected && isAuthenticated {
                Button {
                    fetchPositions()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Rectangle().fill(Color.white.opacity(0.03)))
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)),
            alignment: .bottom
        )
    }

    // MARK: - Balance Card

    private var balanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BALANCE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .tracking(1.5)

            if let addr = walletAddress {
                HStack {
                    Text(truncateAddress(addr))
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    Text("MONAD")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .tracking(1)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("$\(String(format: "%.2f", totalValue))")
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Text(totalPnl >= 0 ? "+$\(String(format: "%.2f", totalPnl))" : "-$\(String(format: "%.2f", abs(totalPnl)))")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(totalPnl >= 0 ? Color(hex: "10B981") : Color(hex: "EF4444"))
            }
        }
        .padding(16)
        .background(Rectangle().fill(Color.white.opacity(0.04)))
        .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Positions Section

    private var positionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("POSITIONS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .tracking(1.5)
                .padding(.top, 8)

            if let result = sellResult {
                Text(result)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(result.contains("Sold") ? Color(hex: "10B981") : Color(hex: "EF4444"))
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Rectangle().fill(Color.white.opacity(0.02)))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 1))
            }

            if let error = errorMessage {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "EF4444"))
            }

            if positions.isEmpty && !isLoading {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.15))
                    Text("No open positions")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(Rectangle().fill(Color.white.opacity(0.02)))
                .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 1))
            } else {
                ForEach(positions) { pos in
                    positionRow(pos)
                }
            }
        }
    }

    private func positionRow(_ pos: PositionItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(pos.marketSlug)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(2)

            HStack {
                Text(pos.side.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(pos.side == "Yes" ? Color(hex: "10B981") : Color(hex: "EF4444"))

                Text("\(String(format: "%.1f", pos.shares)) shares @ $\(String(format: "%.2f", pos.avgPrice))")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                if sellInProgress == pos.id {
                    ProgressView().tint(.white).scaleEffect(0.7)
                } else {
                    Button {
                        sellPosition(pos)
                    } label: {
                        Text("SELL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(Color(hex: "F59E0B"))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(
                                Rectangle().stroke(Color(hex: "F59E0B").opacity(0.3), lineWidth: 1)
                            )
                    }
                }
            }
        }
        .padding(12)
        .background(Rectangle().fill(Color.white.opacity(0.04)))
        .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    // MARK: - Auth Prompt

    private var authPrompt: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 40)

            Image(systemName: "faceid")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.15))

            Text("Verify Identity")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Text("Use Face ID to view your positions and sell shares.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                authenticateIfNeeded()
            } label: {
                Text("VERIFY WITH FACE ID")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Rectangle().fill(Color.white))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    // MARK: - Connect Prompt

    private var connectPrompt: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 60)

            Image(systemName: "wallet.pass")
                .font(.system(size: 36))
                .foregroundColor(.white.opacity(0.15))

            Text("Connect your wallet")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)

            Text("Connect a wallet on Monad to place bets and track your positions.")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button {
                // Trigger wallet connect flow
            } label: {
                Text("CONNECT WALLET")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Rectangle().fill(Color.white))
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
    }

    // MARK: - Helpers

    private func truncateAddress(_ addr: String) -> String {
        guard addr.count > 10 else { return addr }
        return String(addr.prefix(6)) + "..." + String(addr.suffix(4))
    }
}
