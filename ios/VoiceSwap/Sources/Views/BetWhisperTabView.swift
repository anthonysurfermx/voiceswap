/**
 * BetWhisperTabView.swift
 * BetWhisper - Main tab container
 *
 * Routes between Chat, Groups, Bets, Wallet, and Settings tabs.
 * Handles onboarding gate.
 * Profound style: black bg, white text, sharp corners.
 */

import SwiftUI

struct BetWhisperTabView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var glassesManager = MetaGlassesManager.shared
    @State private var isOnboarded: Bool = UserDefaults.standard.bool(forKey: "betwhisper_onboarded")
    @State private var selectedTab: Int = 0
    @State private var isConnectingGlasses = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if !isOnboarded {
                BetWhisperOnboardingView(isComplete: $isOnboarded)
            } else {
                VStack(spacing: 0) {
                    // Tab content
                    Group {
                        switch selectedTab {
                        case 0:
                            BetWhisperChatView()
                        case 1:
                            BetWhisperGroupsView()
                        case 2:
                            BetWhisperPortfolioView()
                        case 3:
                            BetWhisperWalletView()
                        case 4:
                            settingsView
                        default:
                            BetWhisperChatView()
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    // Custom tab bar
                    tabBar
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(index: 0, icon: "bubble.left.fill", label: "CHAT")
            tabButton(index: 1, icon: "person.3.fill", label: "GROUPS")
            tabButton(index: 2, icon: "chart.bar.fill", label: "BETS")
            tabButton(index: 3, icon: "wallet.bifold", label: "WALLET")
            tabButton(index: 4, icon: "gearshape.fill", label: "MORE")
        }
        .padding(.top, 8)
        .padding(.bottom, 24)
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(.white.opacity(0.06)),
            alignment: .top
        )
    }

    private func tabButton(index: Int, icon: String, label: String) -> some View {
        Button {
            selectedTab = index
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(selectedTab == index ? .white : .white.opacity(0.25))
                Text(label)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(selectedTab == index ? .white : .white.opacity(0.25))
                    .tracking(1)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Settings View

    private var settingsView: some View {
        let name = UserDefaults.standard.string(forKey: "betwhisper_assistant_name") ?? "BetWhisper"
        let cats = UserDefaults.standard.stringArray(forKey: "betwhisper_categories") ?? []

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.bottom, 8)

                // Assistant name
                settingsRow(label: "ASSISTANT NAME", value: name)

                // Categories
                VStack(alignment: .leading, spacing: 8) {
                    Text("CATEGORIES")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                        .tracking(1.5)

                    HStack(spacing: 6) {
                        ForEach(cats, id: \.self) { catId in
                            if let cat = ALL_CATEGORIES.first(where: { $0.id == catId }) {
                                HStack(spacing: 4) {
                                    Image(systemName: cat.icon)
                                        .font(.system(size: 10))
                                    Text(cat.name)
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.white.opacity(0.6))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    Rectangle()
                                        .fill(Color.white.opacity(0.06))
                                )
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                            }
                        }
                    }
                }

                // Smart Glasses
                glassesSection

                // Wallet
                settingsRow(
                    label: "WALLET",
                    value: WalletConnectManager.shared.isConnected
                        ? truncateAddress(WalletConnectManager.shared.currentAddress ?? "")
                        : VoiceSwapWallet.shared.isCreated
                            ? truncateAddress(VoiceSwapWallet.shared.address)
                            : "Not created"
                )

                // Network
                settingsRow(label: "NETWORK", value: "Monad (Chain 143)")

                Spacer().frame(height: 24)

                // Reset onboarding
                Button {
                    UserDefaults.standard.removeObject(forKey: "betwhisper_onboarded")
                    UserDefaults.standard.removeObject(forKey: "betwhisper_assistant_name")
                    UserDefaults.standard.removeObject(forKey: "betwhisper_categories")
                    isOnboarded = false
                } label: {
                    Text("RESET ONBOARDING")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundColor(Color(hex: "EF4444"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .overlay(
                            Rectangle()
                                .stroke(Color(hex: "EF4444").opacity(0.3), lineWidth: 1)
                        )
                }

                // Version
                Text("BetWhisper v1.0 / Monad Blitz CDMX")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.15))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Smart Glasses Section

    private var glassesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SMART GLASSES")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .tracking(1.5)

            VStack(spacing: 0) {
                // Status row
                HStack(spacing: 12) {
                    Image(systemName: glassesManager.isConnected ? "eyeglasses" : "eyeglasses")
                        .font(.system(size: 18))
                        .foregroundColor(glassesManager.isConnected ? Color(hex: "10B981") : .white.opacity(0.4))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Meta Ray-Ban")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))

                        Text(glassesStatusText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(glassesStatusColor)
                    }

                    Spacer()

                    if glassesManager.isConnected && glassesManager.batteryLevel > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: batteryIcon)
                                .font(.system(size: 14))
                            Text("\(glassesManager.batteryLevel)%")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(.white.opacity(0.4))
                    }
                }
                .padding(12)

                // Connect / Disconnect button
                Button {
                    if glassesManager.isConnected {
                        glassesManager.disconnect()
                    } else {
                        connectGlasses()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isConnectingGlasses {
                            ProgressView()
                                .tint(.white.opacity(0.6))
                                .scaleEffect(0.8)
                        }
                        Text(glassesManager.isConnected ? "DISCONNECT" : isConnectingGlasses ? "CONNECTING..." : "CONNECT GLASSES")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundColor(glassesManager.isConnected ? Color(hex: "EF4444") : .white.opacity(0.7))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Rectangle().fill(Color.white.opacity(0.04)))
                    .overlay(
                        Rectangle()
                            .stroke(
                                glassesManager.isConnected
                                    ? Color(hex: "EF4444").opacity(0.3)
                                    : Color.white.opacity(0.08),
                                lineWidth: 1
                            )
                    )
                }
                .disabled(isConnectingGlasses)
            }
            .background(Rectangle().fill(Color.white.opacity(0.04)))
            .overlay(Rectangle().stroke(Color.white.opacity(0.06), lineWidth: 1))
        }
    }

    private var glassesStatusText: String {
        switch glassesManager.connectionState {
        case .disconnected: return "Not connected"
        case .searching: return "Searching..."
        case .connecting: return "Connecting..."
        case .registered: return "Registered"
        case .connected: return "Connected"
        case .streaming: return "Streaming"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private var glassesStatusColor: Color {
        switch glassesManager.connectionState {
        case .connected, .registered, .streaming: return Color(hex: "10B981")
        case .searching, .connecting: return Color(hex: "F59E0B")
        case .error: return Color(hex: "EF4444")
        case .disconnected: return .white.opacity(0.3)
        }
    }

    private var batteryIcon: String {
        let level = glassesManager.batteryLevel
        if level > 75 { return "battery.100" }
        if level > 50 { return "battery.75" }
        if level > 25 { return "battery.50" }
        return "battery.25"
    }

    private func connectGlasses() {
        isConnectingGlasses = true
        Task {
            await glassesManager.connect()
            await MainActor.run {
                isConnectingGlasses = false
            }
        }
    }

    // MARK: - Helpers

    private func settingsRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .tracking(1.5)
            Text(value)
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            Rectangle()
                .fill(Color.white.opacity(0.04))
        )
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func truncateAddress(_ addr: String) -> String {
        guard addr.count > 10 else { return addr }
        return String(addr.prefix(6)) + "..." + String(addr.suffix(4))
    }
}
