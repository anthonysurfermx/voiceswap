 /**
 * VoiceSwapApp.swift
 * VoiceSwap - Main App Entry Point
 *
 * Voice-activated crypto payments for Meta Ray-Ban smart glasses.
 * Built on Monad with USDC payments.
 */

import SwiftUI
import UserNotifications
import ReownAppKit
import AVFoundation

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
                // Check for wallet sessions only once when app becomes active
                // The checkForNewSessions function handles retries internally
                WalletConnectManager.shared.checkForNewSessions()

                // WORKAROUND: Meta AI callback deep link never arrives after registration.
                // When returning to app after Meta AI completes registration,
                // retry startRegistration() - if it throws .alreadyRegistered,
                // our catch handler sets state to .registered and starts device stream.
                let glassesManager = MetaGlassesManager.shared
                if glassesManager.connectionState == .connecting {
                    print("[VoiceSwap] App resumed while connecting - retrying registration to detect completion...")
                    Task { @MainActor in
                        // Small delay to let the app fully activate
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        await glassesManager.retryRegistrationAfterResume()
                    }
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
        print("[VoiceSwap] Network: Monad Mainnet (Chain ID: 143)")
    }

    private func requestPermissions() {
        // Request microphone permission for Gemini Live audio streaming
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            print("[VoiceSwap] Microphone permission: \(granted)")
        }

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
        print("[VoiceSwap] ═══════════════════════════════════════")
        print("[VoiceSwap] Received deep link: \(url.absoluteString)")
        print("[VoiceSwap] Scheme: \(url.scheme ?? "nil")")
        print("[VoiceSwap] Host: \(url.host ?? "nil")")
        print("[VoiceSwap] Path: \(url.path)")
        print("[VoiceSwap] Query: \(url.query ?? "nil")")
        print("[VoiceSwap] ═══════════════════════════════════════")

        // PRIORITY 1: Meta Wearables SDK callback (VisionClaw pattern)
        // Check for metaWearablesAction query param FIRST, before any other processing.
        // This is the pattern that works in VisionClaw — direct handleUrl() call.
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true {
            print("[VoiceSwap] 🎯 Meta Wearables callback detected!")
            Task { @MainActor in
                do {
                    let handled = try await MetaGlassesManager.shared.handleURL(url)
                    print("[VoiceSwap] Meta SDK handleUrl result: \(handled)")
                    if !handled {
                        // Fallback: manually process the callback
                        let queryItems = components.queryItems ?? []
                        let action = queryItems.first(where: { $0.name == "metaWearablesAction" })?.value ?? ""
                        self.handleMetaWearablesCallback(queryItems: queryItems, action: action)
                    }
                } catch {
                    print("[VoiceSwap] Meta SDK handleURL error: \(error)")
                    // Still try manual callback processing
                    let queryItems = components.queryItems ?? []
                    let action = queryItems.first(where: { $0.name == "metaWearablesAction" })?.value ?? ""
                    self.handleMetaWearablesCallback(queryItems: queryItems, action: action)
                }
            }
            return
        }

        // PRIORITY 2: WalletConnect deep links
        if url.scheme == "wc" || url.absoluteString.contains("wc:") {
            print("[VoiceSwap] Handling WalletConnect deep link")
            AppKit.instance.handleDeeplink(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                WalletConnectManager.shared.checkForNewSessions()
            }
            return
        }

        // PRIORITY 3: Other voiceswap:// URLs
        if url.scheme == "voiceswap" {
            processVoiceSwapURL(url)
            return
        }

        // Handle Universal Links (https://voiceswap.cc/...)
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            print("[VoiceSwap] Invalid URL components")
            return
        }

        if url.host == "voiceswap.cc" || url.host == "www.voiceswap.cc" {
            handleUniversalLink(components)
        }

        // Always check for sessions when app receives any deep link (wallet might be returning)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            WalletConnectManager.shared.checkForNewSessions()
        }
    }

    /// Process voiceswap:// URLs that were NOT handled by Meta SDK
    private func processVoiceSwapURL(_ url: URL) {
        // Check for WalletConnect callback
        if url.host == "wc" || url.absoluteString.contains("wc") {
            print("[VoiceSwap] Handling voiceswap WC callback")
            AppKit.instance.handleDeeplink(url)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                WalletConnectManager.shared.checkForNewSessions()
            }
            return
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
        handleVoiceSwapURL(components)
    }

    private func handleVoiceSwapURL(_ components: URLComponents) {
        let queryItems = components.queryItems ?? []

        print("[VoiceSwap] Processing voiceswap URL, queryItems count: \(queryItems.count)")
        for item in queryItems {
            print("[VoiceSwap]   - \(item.name): \(item.value?.prefix(20) ?? "nil")...")
        }

        // Check for Meta Wearables callback (no host or empty host, has metaWearablesAction parameter)
        if let metaAction = queryItems.first(where: { $0.name == "metaWearablesAction" })?.value {
            print("[VoiceSwap] Meta Wearables callback: \(metaAction)")
            handleMetaWearablesCallback(queryItems: queryItems, action: metaAction)
            return
        }

        // Get host, treating empty string same as nil
        let host = components.host
        guard let host = host, !host.isEmpty else {
            print("[VoiceSwap] Unknown deep link format (no host or empty host)")
            return
        }

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

    private func handleMetaWearablesCallback(queryItems: [URLQueryItem], action: String) {
        switch action {
        case "register":
            // User authorized the connection in Meta View app
            let authorityKey = queryItems.first(where: { $0.name == "authorityKey" })?.value
            let constellationGroupId = queryItems.first(where: { $0.name == "constellationGroupId" })?.value
            let attestationValidated = queryItems.first(where: { $0.name == "attestationValidated" })?.value

            print("[VoiceSwap] Meta Wearables registration callback:")
            print("  - authorityKey: \(authorityKey?.prefix(20) ?? "nil")...")
            print("  - constellationGroupId: \(constellationGroupId ?? "nil")")
            print("  - attestationValidated: \(attestationValidated ?? "nil")")

            // Notify MetaGlassesManager to complete the connection
            Task { @MainActor in
                await MetaGlassesManager.shared.handleRegistrationCallback(
                    authorityKey: authorityKey,
                    constellationGroupId: constellationGroupId
                )
            }

        case "unregister":
            print("[VoiceSwap] Meta Wearables unregistration callback")
            MetaGlassesManager.shared.disconnect()

        default:
            print("[VoiceSwap] Unknown Meta Wearables action: \(action)")
        }
    }

    private func handleUniversalLink(_ components: URLComponents) {
        let path = components.path
        let queryItems = components.queryItems ?? []

        // Check for Meta Wearables callback FIRST (highest priority)
        // Callback URL: https://voiceswap.cc/?metaWearablesAction=register&authorityKey=...
        if let metaAction = queryItems.first(where: { $0.name == "metaWearablesAction" })?.value {
            print("[VoiceSwap] Meta Wearables callback via Universal Link: \(metaAction)")
            handleMetaWearablesCallback(queryItems: queryItems, action: metaAction)
            return
        }

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
