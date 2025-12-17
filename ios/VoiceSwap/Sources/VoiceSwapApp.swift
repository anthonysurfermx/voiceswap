 /**
 * VoiceSwapApp.swift
 * VoiceSwap - Main App Entry Point
 *
 * Voice-activated crypto payments for Meta Ray-Ban smart glasses.
 * Built on Unichain with USDC payments.
 */

import SwiftUI
import UserNotifications
import ReownAppKit

@main
struct VoiceSwapApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            VoiceSwapMainView()
                .environmentObject(appState)
                .onAppear {
                    setupApp()
                }
                .onOpenURL { url in
                    handleDeepLink(url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // App became active - check for wallet sessions
                // This handles the case where user connected in wallet app and returned
                // Check immediately and again after delays for wallets that don't redirect
                print("[VoiceSwap] App became active - checking wallet sessions")
                WalletConnectManager.shared.checkForNewSessions()

                // Additional checks for wallets like Uniswap that don't auto-redirect
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    WalletConnectManager.shared.checkForNewSessions()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    WalletConnectManager.shared.checkForNewSessions()
                }
            }
        }
    }

    private func setupApp() {
        // Request necessary permissions
        requestPermissions()

        // Initialize WalletConnect
        WalletConnectManager.shared.initialize()

        // Configure app
        print("[VoiceSwap] App started")
        print("[VoiceSwap] Network: Unichain Mainnet (Chain ID: 130)")
    }

    private func requestPermissions() {
        // Microphone permission is requested when starting speech recognition
        // Camera permission would be requested when using QR scanning

        // Request notification permission for payment alerts
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("[VoiceSwap] Notification permission error: \(error)")
            } else if granted {
                print("[VoiceSwap] Notifications authorized")
            }
        }
    }

    // MARK: - Deep Link Handling

    private func handleDeepLink(_ url: URL) {
        print("[VoiceSwap] Received deep link: \(url)")
        print("[VoiceSwap] Deep link scheme: \(url.scheme ?? "nil"), host: \(url.host ?? "nil")")

        // Handle WalletConnect deep links first
        if url.scheme == "wc" || url.absoluteString.contains("wc:") {
            print("[VoiceSwap] Handling WalletConnect deep link")
            AppKit.instance.handleDeeplink(url)
            // Also trigger a session check after handling the deep link
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                WalletConnectManager.shared.checkForNewSessions()
            }
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            print("[VoiceSwap] Invalid URL components")
            return
        }

        // Handle voiceswap:// scheme
        if url.scheme == "voiceswap" {
            // Check if it's a WalletConnect callback
            if url.host == "wc" || url.absoluteString.contains("wc") {
                print("[VoiceSwap] Handling voiceswap WC callback")
                AppKit.instance.handleDeeplink(url)
                // Also trigger a session check
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    WalletConnectManager.shared.checkForNewSessions()
                }
                return
            }
            handleVoiceSwapURL(components)
        }
        // Handle Universal Links (https://voiceswap.cc/...)
        else if url.host == "voiceswap.cc" {
            handleUniversalLink(components)
        }

        // Always check for sessions when app receives any deep link (wallet might be returning)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            WalletConnectManager.shared.checkForNewSessions()
        }
    }

    private func handleVoiceSwapURL(_ components: URLComponents) {
        guard let host = components.host else { return }

        switch host {
        case "pay":
            // voiceswap://pay?wallet=0x...&amount=25&name=CoffeeShop
            handlePaymentDeepLink(components)

        case "balance":
            // voiceswap://balance
            appState.pendingAction = .checkBalance

        case "connect":
            // voiceswap://connect (connect to glasses)
            appState.pendingAction = .connectGlasses

        default:
            print("[VoiceSwap] Unknown deep link host: \(host)")
        }
    }

    private func handleUniversalLink(_ components: URLComponents) {
        let path = components.path

        if path.hasPrefix("/pay/") {
            // https://voiceswap.cc/pay/0x1234...?amount=25&name=CoffeeShop
            let wallet = String(path.dropFirst("/pay/".count))
            let queryItems = components.queryItems ?? []
            let amount = queryItems.first(where: { $0.name == "amount" })?.value
            let name = queryItems.first(where: { $0.name == "name" })?.value

            appState.pendingPayment = PendingPayment(
                recipientAddress: wallet,
                amount: amount,
                merchantName: name
            )
            appState.pendingAction = .initiatePayment
        }
        else if path.hasPrefix("/app/") {
            // https://voiceswap.cc/app/... - generic app actions
            let action = String(path.dropFirst("/app/".count))
            print("[VoiceSwap] Universal link action: \(action)")
        }
    }

    private func handlePaymentDeepLink(_ components: URLComponents) {
        let queryItems = components.queryItems ?? []

        let wallet = queryItems.first(where: { $0.name == "wallet" })?.value
        let amount = queryItems.first(where: { $0.name == "amount" })?.value
        let name = queryItems.first(where: { $0.name == "name" })?.value

        guard let recipientWallet = wallet else {
            print("[VoiceSwap] Payment deep link missing wallet address")
            return
        }

        print("[VoiceSwap] Payment deep link - Wallet: \(recipientWallet), Amount: \(amount ?? "unspecified"), Name: \(name ?? "Unknown")")

        appState.pendingPayment = PendingPayment(
            recipientAddress: recipientWallet,
            amount: amount,
            merchantName: name
        )
        appState.pendingAction = .initiatePayment
    }
}

// MARK: - App State

enum PendingAction {
    case none
    case initiatePayment
    case checkBalance
    case connectGlasses
}

struct PendingPayment {
    let recipientAddress: String
    let amount: String?
    let merchantName: String?
}

class AppState: ObservableObject {
    @Published var isOnboarded: Bool = false
    @Published var walletConnected: Bool = false
    @Published var pendingAction: PendingAction = .none
    @Published var pendingPayment: PendingPayment?

    init() {
        // Check if user has completed onboarding
        isOnboarded = UserDefaults.standard.bool(forKey: "isOnboarded")
    }

    func completeOnboarding() {
        isOnboarded = true
        UserDefaults.standard.set(true, forKey: "isOnboarded")
    }

    func clearPendingAction() {
        pendingAction = .none
        pendingPayment = nil
    }
}
