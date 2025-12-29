/**
 * MetaGlassesManager.swift
 * VoiceSwap - Voice-activated crypto payments for Meta Ray-Ban glasses
 *
 * Integrates with Meta Wearables Device Access Toolkit (DAT) SDK
 * to stream video from glasses and detect QR codes for payments.
 */

import Foundation
import Combine
import AVFoundation
import Speech
import UIKit
import CoreImage
import SwiftUI
import Vision

// Import Meta Wearables DAT SDK
import MWDATCore
import MWDATCamera

// MARK: - Meta Glasses Connection State

public enum GlassesConnectionState: Equatable {
    case disconnected
    case searching
    case connecting
    case registered
    case connected
    case streaming
    case error(String)

    public static func == (lhs: GlassesConnectionState, rhs: GlassesConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.searching, .searching),
             (.connecting, .connecting),
             (.registered, .registered),
             (.connected, .connected),
             (.streaming, .streaming):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - Voice Command Result

public struct VoiceCommandResult {
    public let transcript: String
    public let confidence: Float
    public let language: String
    public let timestamp: Date
}

// MARK: - QR Scan Result

public struct QRScanResult {
    public let rawData: String
    public let merchantWallet: String?
    public let amount: String?
    public let merchantName: String?
    public let chainId: Int?
    public let token: String?

    public init(rawData: String, merchantWallet: String?, amount: String?, merchantName: String?, chainId: Int? = nil, token: String? = nil) {
        self.rawData = rawData
        self.merchantWallet = merchantWallet
        self.amount = amount
        self.merchantName = merchantName
        self.chainId = chainId
        self.token = token
    }

    /// Parse various payment QR code formats
    public static func parse(from urlString: String) -> QRScanResult? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Handle voiceswap:// deep links
        //    Format: voiceswap://pay?wallet=0x...&amount=10&name=CoffeeShop
        if trimmed.lowercased().hasPrefix("voiceswap://") {
            return parseVoiceSwapURL(trimmed)
        }

        // 2. Handle HTTPS voiceswap.cc links
        //    Format: https://voiceswap.cc/pay?wallet=0x...&amount=10
        if trimmed.lowercased().contains("voiceswap.cc") {
            return parseVoiceSwapURL(trimmed)
        }

        // 3. Handle EIP-681 ethereum: URLs (standard for crypto payments)
        //    Format: ethereum:0x1234...?value=1000000&chainId=130
        if trimmed.lowercased().hasPrefix("ethereum:") {
            return parseEIP681URL(trimmed)
        }

        // 4. Handle plain Ethereum addresses (0x...)
        if isValidEthereumAddress(trimmed) {
            return QRScanResult(
                rawData: trimmed,
                merchantWallet: trimmed,
                amount: nil,
                merchantName: nil
            )
        }

        // 5. Handle ENS names (name.eth)
        if trimmed.lowercased().hasSuffix(".eth") && trimmed.count > 4 {
            return QRScanResult(
                rawData: trimmed,
                merchantWallet: trimmed,  // Will be resolved by backend
                amount: nil,
                merchantName: trimmed
            )
        }

        // 6. Handle JSON payment requests
        if trimmed.hasPrefix("{") {
            return parseJSONPaymentRequest(trimmed)
        }

        return nil
    }

    /// Parse VoiceSwap URL format
    private static func parseVoiceSwapURL(_ urlString: String) -> QRScanResult? {
        guard let url = URL(string: urlString),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let queryItems = components.queryItems ?? []
        let wallet = queryItems.first(where: { $0.name == "wallet" || $0.name == "to" || $0.name == "address" })?.value
        let amount = queryItems.first(where: { $0.name == "amount" || $0.name == "value" })?.value
        let name = queryItems.first(where: { $0.name == "name" || $0.name == "merchant" || $0.name == "label" })?.value
        let chainIdStr = queryItems.first(where: { $0.name == "chainId" || $0.name == "chain" })?.value
        let token = queryItems.first(where: { $0.name == "token" || $0.name == "currency" })?.value

        guard wallet != nil || name != nil else { return nil }

        return QRScanResult(
            rawData: urlString,
            merchantWallet: wallet,
            amount: amount,
            merchantName: name,
            chainId: chainIdStr.flatMap { Int($0) },
            token: token
        )
    }

    /// Parse EIP-681 ethereum: URL format
    /// Example: ethereum:0x1234567890123456789012345678901234567890@130?value=1000000
    private static func parseEIP681URL(_ urlString: String) -> QRScanResult? {
        // Remove ethereum: prefix
        var remaining = urlString.dropFirst("ethereum:".count)

        // Check for pay- prefix (ethereum:pay-0x...)
        if remaining.hasPrefix("pay-") {
            remaining = remaining.dropFirst(4)
        }

        // Extract address (and optional chainId after @)
        var address: String
        var chainId: Int? = 130  // Default to Unichain

        if let atIndex = remaining.firstIndex(of: "@") {
            address = String(remaining[..<atIndex])
            let afterAt = remaining[remaining.index(after: atIndex)...]
            if let queryIndex = afterAt.firstIndex(of: "?") {
                chainId = Int(String(afterAt[..<queryIndex]))
            } else {
                chainId = Int(String(afterAt))
            }
        } else if let queryIndex = remaining.firstIndex(of: "?") {
            address = String(remaining[..<queryIndex])
        } else {
            address = String(remaining)
        }

        guard isValidEthereumAddress(address) else { return nil }

        // Parse query parameters
        var amount: String?
        if let queryIndex = remaining.firstIndex(of: "?") {
            let query = String(remaining[remaining.index(after: queryIndex)...])
            let params = query.split(separator: "&")
            for param in params {
                let parts = param.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    let key = String(parts[0]).lowercased()
                    let value = String(parts[1])
                    if key == "value" || key == "amount" {
                        // Convert wei to human readable if needed
                        amount = value
                    } else if key == "chainid" {
                        chainId = Int(value)
                    }
                }
            }
        }

        return QRScanResult(
            rawData: urlString,
            merchantWallet: address,
            amount: amount,
            merchantName: nil,
            chainId: chainId,
            token: "USDC"  // Default to USDC for EIP-681
        )
    }

    /// Parse JSON payment request
    private static func parseJSONPaymentRequest(_ jsonString: String) -> QRScanResult? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let wallet = json["wallet"] as? String ?? json["to"] as? String ?? json["address"] as? String
        let amount = json["amount"] as? String ?? (json["value"] as? Double).map { String($0) }
        let name = json["name"] as? String ?? json["merchant"] as? String ?? json["label"] as? String
        let chainId = json["chainId"] as? Int ?? json["chain"] as? Int
        let token = json["token"] as? String ?? json["currency"] as? String

        guard wallet != nil else { return nil }

        return QRScanResult(
            rawData: jsonString,
            merchantWallet: wallet,
            amount: amount,
            merchantName: name,
            chainId: chainId,
            token: token
        )
    }

    /// Validate Ethereum address format
    private static func isValidEthereumAddress(_ address: String) -> Bool {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("0x") && trimmed.count == 42 else { return false }

        // Check that remaining characters are valid hex
        let hexPart = trimmed.dropFirst(2)
        let validHex = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return hexPart.unicodeScalars.allSatisfy { validHex.contains($0) }
    }
}

// MARK: - Meta Glasses Manager Protocol

public protocol MetaGlassesDelegate: AnyObject {
    func glassesDidConnect()
    func glassesDidDisconnect()
    func glassesDidReceiveVoiceCommand(_ result: VoiceCommandResult)
    func glassesDidScanQR(_ result: QRScanResult)
    func glassesDidEncounterError(_ error: Error)
    func glassesDidUpdateVideoFrame(_ image: UIImage)
}

// Default implementations for optional methods
public extension MetaGlassesDelegate {
    func glassesDidUpdateVideoFrame(_ image: UIImage) {}
}

// MARK: - Haptic Patterns

public enum HapticPattern {
    case short
    case double
    case long
    case success
    case error
}

// MARK: - Meta Glasses Manager

@MainActor
public class MetaGlassesManager: NSObject, ObservableObject {

    // MARK: - Singleton
    public static let shared = MetaGlassesManager()

    // MARK: - Published Properties
    @Published public private(set) var connectionState: GlassesConnectionState = .disconnected
    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var batteryLevel: Int = 0
    @Published public private(set) var lastTranscript: String = ""
    @Published public private(set) var isStreamingCamera: Bool = false
    @Published public private(set) var currentVideoFrame: UIImage?
    @Published public private(set) var devices: [DeviceIdentifier] = []
    @Published public private(set) var lastDetectedQR: QRScanResult?
    @Published public private(set) var isGlassesHFPConnected: Bool = false

    // MARK: - Computed Properties
    public var isConnected: Bool {
        switch connectionState {
        case .connected, .registered, .streaming:
            return true
        default:
            return false
        }
    }

    /// Check if glasses are connected via Bluetooth HFP (audio route)
    /// This is a fallback detection when devicesStream() returns empty
    public var hasGlassesViaHFP: Bool {
        return isGlassesHFPConnected
    }

    public var isStreaming: Bool {
        return connectionState == .streaming
    }

    // MARK: - Delegate
    public weak var delegate: MetaGlassesDelegate?

    // MARK: - Meta Wearables SDK Properties
    private var wearables: WearablesInterface?

    /// StreamSession is created once and reused with start()/stop()
    /// Per Meta SDK docs: "SDK requires ONE session instance, reused with start()/stop()"
    private var streamSession: StreamSession?
    private var deviceSelector: AutoDeviceSelector?
    private var isStreamSessionInitialized: Bool = false

    private var registrationTask: Task<Void, Never>?
    private var deviceStreamTask: Task<Void, Never>?
    private var deviceMonitorTask: Task<Void, Never>?
    private var stateListenerToken: AnyListenerToken?
    private var videoFrameListenerToken: AnyListenerToken?
    private var errorListenerToken: AnyListenerToken?
    private var compatibilityListenerToken: AnyListenerToken?

    // MARK: - Speech Recognition Properties
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine!
    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - QR Detection (Vision Framework)
    private var qrDetector: CIDetector?  // Fallback
    private var lastQRDetectionTime: Date = .distantPast
    private let qrDetectionCooldown: TimeInterval = 2.0
    private var isProcessingFrame: Bool = false
    private let visionQueue = DispatchQueue(label: "com.voiceswap.vision", qos: .userInitiated)

    // MARK: - Audio Route Observation
    private var audioRouteObserver: NSObjectProtocol?

    // MARK: - VoiceSwap Configuration
    private let apiBaseURL: String
    private var userWalletAddress: String?

    // Wake word detection
    private let wakeWords = ["hey voiceswap", "oye voiceswap", "voice swap", "pagar", "pay"]
    private var isWakeWordDetected = false
    private var isDirectMode = false
    private var pendingTranscript = ""

    // MARK: - Initialization

    private override init() {
        // Use production API by default, or override with environment variable for local development
        #if DEBUG
        self.apiBaseURL = ProcessInfo.processInfo.environment["VOICESWAP_API_URL"] ?? "https://voiceswap.vercel.app"
        #else
        self.apiBaseURL = "https://voiceswap.vercel.app"
        #endif
        self.audioEngine = AVAudioEngine()

        super.init()

        // Defer heavy initialization to not block app startup
        Task { @MainActor in
            // Initialize QR detector
            self.qrDetector = CIDetector(
                ofType: CIDetectorTypeQRCode,
                context: nil,
                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
            )

            // Setup audio route change observer for Bluetooth detection
            // (Re-enabled - confirmed audio was NOT blocking the Meta callback)
            self.setupAudioRouteObserver()

            // Initialize Meta Wearables SDK
            self.initializeWearablesSDK()

            // DISABLED FOR DEBUGGING - Testing if audio interferes with Meta callback
            // Setup speech recognition
            // self.setupSpeechRecognition()

            // Restore registration state if previously registered
            if UserDefaults.standard.bool(forKey: "metaGlassesRegistered") {
                self.connectionState = .registered
                self.setupDeviceStream()
            }

            print("[MetaGlasses] Initialized (AUDIO DISABLED FOR DEBUGGING)")
        }
    }

    // MARK: - Meta Wearables SDK Setup

    private func initializeWearablesSDK() {
        do {
            try Wearables.configure()
            self.wearables = Wearables.shared
            print("[MetaGlasses] Wearables SDK configured successfully")

            setupRegistrationListener()
        } catch {
            print("[MetaGlasses] Failed to configure Wearables SDK: \(error)")
            connectionState = .error("Failed to initialize Meta SDK: \(error.localizedDescription)")
        }
    }

    private func setupRegistrationListener() {
        guard let wearables = wearables else { return }

        print("[MetaGlasses] Setting up registration listener...")

        registrationTask = Task {
            print("[MetaGlasses] Registration stream Task started. Entering for-await loop...")
            do {
                for await registrationState in wearables.registrationStateStream() {
                    print("[MetaGlasses] Registration state changed: \(registrationState)")
                    await MainActor.run {
                        switch registrationState {
                            case .registering:
                                print("[MetaGlasses] → State: registering")
                                self.connectionState = .connecting
                            case .registered:
                                print("[MetaGlasses] → State: registered ✅")
                                UserDefaults.standard.set(true, forKey: "metaGlassesRegistered")
                                self.connectionState = .registered

                                // Only setup stream if not already running to avoid churn
                                if self.deviceStreamTask == nil {
                                    self.setupDeviceStream()
                                }
                            @unknown default:
                                // Unknown states - log but don't change connection state aggressively
                                // This prevents losing registered state on transient/unknown states
                                print("[MetaGlasses] → State: unknown (rawValue: \(registrationState)) - ignoring")
                                // Only disconnect if we're not already registered or connected
                                if case .disconnected = self.connectionState {
                                    // Already disconnected, nothing to do
                                } else if case .connecting = self.connectionState {
                                    // Still connecting, reset to disconnected
                                    self.connectionState = .disconnected
                                }
                                // If registered/connected, keep that state - don't downgrade on unknown
                        }
                    }
                }
                print("[MetaGlasses] Registration stream ended gracefully.")
            } catch {
                print("[MetaGlasses] ERROR: Registration stream encountered an error: \(error.localizedDescription)")
                await MainActor.run {
                    self.delegate?.glassesDidEncounterError(error)
                    self.connectionState = .error("Registration stream error: \(error.localizedDescription)")
                }
            }
            print("[MetaGlasses] Registration stream Task finished.")
        }
    }

    private func setupDeviceStream() {
        guard let wearables = wearables else {
            print("[MetaGlasses] Cannot setup device stream - SDK not initialized")
            return
        }

        print("[MetaGlasses] Setting up device stream to listen for Bluetooth-connected glasses...")

        deviceStreamTask?.cancel()
        deviceStreamTask = Task {
            print("[MetaGlasses] Device stream task started, waiting for Bluetooth devices...")
            var hasReceivedUpdate = false

            for await devices in wearables.devicesStream() {
                hasReceivedUpdate = true
                await MainActor.run {
                    self.devices = devices

                    print("[MetaGlasses] Device stream update: \(devices.count) device(s) found")

                    if devices.isEmpty {
                        print("[MetaGlasses] No glasses connected via Bluetooth")
                        print("[MetaGlasses] Make sure glasses are:")
                        print("[MetaGlasses]   1. Powered on (tap temple to wake)")
                        print("[MetaGlasses]   2. Connected in iOS Settings > Bluetooth")
                        print("[MetaGlasses]   3. Not connected to another device")

                        // Keep registered state but inform user
                        if self.connectionState == .registered {
                            // Stay in registered state - glasses are registered but not BT connected
                            print("[MetaGlasses] Registered with Meta View, awaiting Bluetooth connection")
                        }
                    } else {
                        self.connectionState = .connected
                        self.delegate?.glassesDidConnect()
                        print("[MetaGlasses] Device connected via Bluetooth: \(devices.count) device(s)")
                        for (index, device) in devices.enumerated() {
                            print("[MetaGlasses]   Device \(index + 1): \(device)")
                            // Check device compatibility (v0.2.0+ API)
                            self.checkDeviceCompatibility(device)
                        }
                    }
                }
            }

            if !hasReceivedUpdate {
                print("[MetaGlasses] Device stream ended without any updates")
            }
        }
    }

    /// Check device compatibility for camera streaming (v0.2.0+ API)
    private func checkDeviceCompatibility(_ device: DeviceIdentifier) {
        guard let wearables = wearables else { return }

        // The SDK in v0.2.0+ provides compatibility() method on Device objects
        // DeviceIdentifier is just an identifier - we need to get the actual Device
        // For now, log what we have
        print("[MetaGlasses] Device identifier: \(device)")
        print("[MetaGlasses] Note: Use Meta View > Settings > Device Access to grant camera permissions")
    }

    // MARK: - Public Methods

    /// Configure the manager with user's wallet address
    public func configure(walletAddress: String) {
        self.userWalletAddress = walletAddress
        print("[MetaGlasses] Configured with wallet: \(walletAddress.prefix(10))...")
    }

    /// Connect to Meta Ray-Ban glasses (convenience method)
    public func connect() async {
        do {
            try await connectToGlasses()
        } catch {
            print("[MetaGlasses] Connect error: \(error)")
        }
    }

    /// Handle registration callback from Meta View app
    public func handleRegistrationCallback(authorityKey: String?, constellationGroupId: String?) async {
        guard wearables != nil else {
            connectionState = .error("SDK not initialized")
            return
        }

        // The deep link with valid authorityKey and constellationGroupId indicates successful registration
        if authorityKey != nil && constellationGroupId != nil {
            print("[MetaGlasses] Registration successful")

            // Save registration state
            UserDefaults.standard.set(true, forKey: "metaGlassesRegistered")

            // Set to registered
            connectionState = .registered

            // Setup device stream to listen for connected devices
            setupDeviceStream()

            // Brief wait for device to connect
            for _ in 1...4 {
                try? await Task.sleep(nanoseconds: 500_000_000)
                if !devices.isEmpty || connectionState == .connected {
                    print("[MetaGlasses] Device connected via SDK")
                    return
                }
            }

            // If SDK devicesStream didn't find devices, check audio route as fallback
            if devices.isEmpty {
                print("[MetaGlasses] SDK devicesStream empty, checking Bluetooth audio route...")
                checkAndUpdateHFPConnection()

                if isGlassesHFPConnected {
                    print("[MetaGlasses] ✓ Glasses detected via audio route - ready for camera")
                    connectionState = .connected
                    delegate?.glassesDidConnect()
                } else {
                    // List available Bluetooth devices for debugging
                    listAvailableBluetoothDevices()
                }
            }
        } else {
            connectionState = .error("Registration failed - please try again")
        }
    }

    /// Connect to Meta Ray-Ban glasses
    public func connectToGlasses() async throws {
        guard let wearables = wearables else {
            throw NSError(domain: "MetaGlasses", code: 1, userInfo: [NSLocalizedDescriptionKey: "Wearables SDK not initialized"])
        }

        // Only skip registration if actually streaming or have real device connection
        // Don't skip if just "registered" - we need to start registration flow to open Meta View
        if connectionState == .streaming || (!devices.isEmpty && connectionState == .connected) {
            print("[MetaGlasses] Already streaming/connected with devices, skipping registration")
            return
        }

        connectionState = .connecting

        do {
            try wearables.startRegistration()
            print("[MetaGlasses] Started registration - redirecting to Meta AI app")
            print("[MetaGlasses] Expected callback: voiceswap://?metaWearablesAction=register&...")
            print("[MetaGlasses] Verify Meta Developer Portal has URL scheme: voiceswap://")
        } catch {
            connectionState = .error("Failed to start registration: \(error.localizedDescription)")
            throw error
        }
    }

    /// Disconnect from glasses
    public func disconnect() {
        stopListening()
        cleanupStreamSession()

        if let wearables = wearables {
            do {
                try wearables.startUnregistration()
            } catch {
                print("[MetaGlasses] Failed to unregister: \(error)")
            }
        }

        // Clear saved registration
        UserDefaults.standard.removeObject(forKey: "metaGlassesRegistered")

        connectionState = .disconnected
        devices = []
        delegate?.glassesDidDisconnect()
    }

    // MARK: - QR Scanning

    /// Start scanning for QR codes using the glasses camera
    /// This starts the camera stream and processes frames for QR detection
    public func startQRScanning() async {
        print("[MetaGlasses] Starting QR scanning mode...")

        // Reset detection state
        lastDetectedQR = nil
        lastQRDetectionTime = .distantPast
        isProcessingFrame = false

        // Check audio route first to detect glasses via A2DP
        checkAndUpdateHFPConnection()

        // Check if we can start camera stream
        if devices.isEmpty && !isGlassesHFPConnected {
            print("[MetaGlasses] Cannot start QR scan - no glasses connected")
            print("[MetaGlasses] Glasses audio connected: \(isGlassesHFPConnected)")
            speak("Please connect your Meta glasses first", language: "en-US")
            triggerHaptic(.error)
            connectionState = .error("Connect glasses via Bluetooth first")
            return
        }

        print("[MetaGlasses] ✓ Glasses detected (SDK: \(devices.count), Audio: \(isGlassesHFPConnected))")

        speak("Scanning for payment QR code. Look at the merchant's QR.", language: "en-US")
        triggerHaptic(.short)

        // Start camera stream - QR detection happens automatically via scanForQRCode()
        await startCameraStream()

        // If camera didn't start (error state), inform user about Meta View setup
        if connectionState == .error("Enable VoiceSwap in Meta View > Settings > Device Access") ||
           connectionState == .error("Grant camera access in Meta View app") {
            // Already handled in startCameraStream with voice feedback
            print("[MetaGlasses] Camera stream failed - user needs to configure Meta View")
        }
    }

    /// Stop QR scanning
    public func stopQRScanning() {
        print("[MetaGlasses] Stopping QR scanning mode...")
        stopCameraStream()
    }

    // MARK: - Audio Route Observation

    /// Setup observer for audio route changes (Bluetooth connect/disconnect)
    private func setupAudioRouteObserver() {
        audioRouteObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }

            if let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
               let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) {

                switch reason {
                case .newDeviceAvailable:
                    print("[MetaGlasses] 🔊 New audio device available")
                    self.checkAndUpdateHFPConnection()
                case .oldDeviceUnavailable:
                    print("[MetaGlasses] 🔇 Audio device disconnected")
                    self.checkAndUpdateHFPConnection()
                case .categoryChange:
                    print("[MetaGlasses] Audio category changed")
                case .override:
                    print("[MetaGlasses] Audio route override")
                case .routeConfigurationChange:
                    print("[MetaGlasses] Route configuration changed")
                    self.checkAndUpdateHFPConnection()
                default:
                    break
                }
            }
        }
    }

    /// Try to force audio route to Bluetooth HFP
    /// This helps establish the HFP connection needed for glasses detection
    private func tryForceBluetoothAudioRoute() async {
        // DISABLED FOR DEBUGGING - Testing if audio interferes with Meta callback
        print("[MetaGlasses] tryForceBluetoothAudioRoute() DISABLED FOR DEBUGGING")
        /*
        print("[MetaGlasses] Attempting to force Bluetooth audio route...")

        let audioSession = AVAudioSession.sharedInstance()

        do {
            // Configure audio session for Bluetooth HFP
            try audioSession.setCategory(
                .playAndRecord,
                mode: .voiceChat,  // voiceChat mode prefers Bluetooth HFP
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )

            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

            // Give the system time to switch routes
            try? await Task.sleep(nanoseconds: 500_000_000)

            // Check available inputs and try to select Bluetooth
            let availableInputs = audioSession.availableInputs ?? []
            print("[MetaGlasses] Available audio inputs:")
            for input in availableInputs {
                print("[MetaGlasses]   - \(input.portName) (\(input.portType.rawValue))")
            }

            // Try to find and select a Bluetooth input
            if let bluetoothInput = availableInputs.first(where: {
                $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP
            }) {
                print("[MetaGlasses] Found Bluetooth input: \(bluetoothInput.portName)")
                try audioSession.setPreferredInput(bluetoothInput)
                print("[MetaGlasses] ✓ Set preferred input to Bluetooth")

                // Wait a bit for the route to switch
                try? await Task.sleep(nanoseconds: 300_000_000)
            } else {
                print("[MetaGlasses] No Bluetooth audio input available")
                print("[MetaGlasses] Make sure glasses are:")
                print("[MetaGlasses]   1. Connected in iOS Settings > Bluetooth")
                print("[MetaGlasses]   2. Set as audio output (play music to verify)")
            }
        } catch {
            print("[MetaGlasses] Failed to configure Bluetooth audio: \(error)")
        }
        */
    }

    /// List all available Bluetooth devices for debugging
    private func listAvailableBluetoothDevices() {
        let audioSession = AVAudioSession.sharedInstance()

        print("[MetaGlasses] ═══════════════════════════════════════")
        print("[MetaGlasses] BLUETOOTH DIAGNOSTICS")
        print("[MetaGlasses] ═══════════════════════════════════════")

        // Available inputs
        if let inputs = audioSession.availableInputs {
            print("[MetaGlasses] Available Inputs (\(inputs.count)):")
            for input in inputs {
                let isBluetooth = input.portType == .bluetoothHFP || input.portType == .bluetoothA2DP
                let marker = isBluetooth ? "🔵" : "⚪"
                print("[MetaGlasses]   \(marker) \(input.portName) [\(input.portType.rawValue)]")
            }
        }

        // Current route
        let currentRoute = audioSession.currentRoute
        print("[MetaGlasses] Current Route:")
        print("[MetaGlasses]   Inputs: \(currentRoute.inputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", "))")
        print("[MetaGlasses]   Outputs: \(currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", "))")

        print("[MetaGlasses] ═══════════════════════════════════════")
        print("[MetaGlasses] If glasses not listed above:")
        print("[MetaGlasses]   1. Open iOS Settings > Bluetooth")
        print("[MetaGlasses]   2. Find 'Ray-Ban | Meta' and tap (i)")
        print("[MetaGlasses]   3. Ensure 'Connect' is enabled")
        print("[MetaGlasses]   4. Try playing music to establish audio route")
        print("[MetaGlasses] ═══════════════════════════════════════")
    }

    /// Check if Meta glasses are connected via HFP/A2DP and update state accordingly
    private func checkAndUpdateHFPConnection() {
        let audioSession = AVAudioSession.sharedInstance()
        let currentRoute = audioSession.currentRoute

        let inputs = currentRoute.inputs.map { "\($0.portName) (\($0.portType.rawValue))" }
        let outputs = currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" }

        print("[MetaGlasses] Current audio route:")
        print("  Inputs: \(inputs.joined(separator: ", "))")
        print("  Outputs: \(outputs.joined(separator: ", "))")

        // Check for Bluetooth audio (HFP or A2DP)
        let hasBluetoothAudio = currentRoute.inputs.contains {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP
        } || currentRoute.outputs.contains {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP
        }

        // Check if device name contains "Meta" or "Ray-Ban" or "Glasses"
        let glassesKeywords = ["meta", "ray-ban", "rayban", "glasses", "oakley", "mr robot"]
        let hasGlassesDevice = currentRoute.inputs.contains { port in
            glassesKeywords.contains { port.portName.lowercased().contains($0) }
        } || currentRoute.outputs.contains { port in
            glassesKeywords.contains { port.portName.lowercased().contains($0) }
        }

        let wasConnected = isGlassesHFPConnected
        isGlassesHFPConnected = hasBluetoothAudio && hasGlassesDevice

        if isGlassesHFPConnected {
            print("[MetaGlasses] ✓ Glasses detected via Bluetooth audio (A2DP/HFP)")

            // If SDK devicesStream is empty but we detect glasses via audio route,
            // update connection state as a fallback
            if devices.isEmpty && connectionState == .registered {
                print("[MetaGlasses] 📱 Using audio route as fallback - glasses detected!")
                connectionState = .connected
                delegate?.glassesDidConnect()
            }
        } else if wasConnected && !isGlassesHFPConnected {
            print("[MetaGlasses] ✗ Glasses disconnected from Bluetooth audio")
            // Only downgrade if we were relying on audio detection
            if devices.isEmpty && connectionState == .connected {
                connectionState = .registered
                delegate?.glassesDidDisconnect()
            }
        }
    }


    // MARK: - Audio Configuration for HFP

    /// Configure HFP (Hands-Free Profile) audio BEFORE starting streaming
    /// Per Meta docs: "It is essential to ensure that HFP is fully configured before initiating any streaming session"
    private func configureHFPAudio() throws {
        // DISABLED FOR DEBUGGING - Testing if audio interferes with Meta callback
        print("[MetaGlasses] configureHFPAudio() DISABLED FOR DEBUGGING")
        /*
        print("[MetaGlasses] Configuring HFP audio session...")

        let audioSession = AVAudioSession.sharedInstance()

        // Configure for play and record with Bluetooth HFP support
        // Using .allowBluetooth enables HFP for both input and output
        // Note: .allowBluetooth is being deprecated - use .allowBluetoothHFP in future iOS versions
        try audioSession.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.allowBluetooth, .defaultToSpeaker, .mixWithOthers]
        )

        // Activate the session - this establishes HFP connection
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Log current audio route for debugging
        let currentRoute = audioSession.currentRoute
        print("[MetaGlasses] Audio inputs: \(currentRoute.inputs.map { $0.portName })")
        print("[MetaGlasses] Audio outputs: \(currentRoute.outputs.map { $0.portName })")

        // Check if Bluetooth is in the route
        let hasBluetoothInput = currentRoute.inputs.contains {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP
        }
        let hasBluetoothOutput = currentRoute.outputs.contains {
            $0.portType == .bluetoothHFP || $0.portType == .bluetoothA2DP
        }

        if hasBluetoothInput || hasBluetoothOutput {
            print("[MetaGlasses] ✓ Bluetooth HFP audio configured successfully")
        } else {
            print("[MetaGlasses] ⚠ No Bluetooth device in audio route - glasses mic may not work")
        }
        */
    }

    // MARK: - Camera Streaming

    /// Initialize StreamSession once - this follows Meta SDK best practice
    /// "SDK requires ONE session instance, reused with start()/stop()"
    private func initializeStreamSession() {
        guard let wearables = wearables else {
            print("[MetaGlasses] Cannot initialize stream session - SDK not initialized")
            return
        }

        guard !isStreamSessionInitialized else {
            print("[MetaGlasses] StreamSession already initialized")
            return
        }

        print("[MetaGlasses] Initializing StreamSession (one-time setup)...")

        // Create AutoDeviceSelector - this automatically selects connected devices
        deviceSelector = AutoDeviceSelector(wearables: wearables)

        // Monitor active device changes
        deviceMonitorTask = Task { @MainActor in
            guard let deviceSelector = self.deviceSelector else { return }
            for await device in deviceSelector.activeDeviceStream() {
                print("[MetaGlasses] 📱 Active device changed: \(device != nil ? "connected" : "disconnected")")
                if device != nil && self.connectionState == .registered {
                    self.connectionState = .connected
                    self.delegate?.glassesDidConnect()
                }
            }
        }

        // Configure StreamSession with optimal settings for QR detection
        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .low,    // Low res is faster for QR detection
            frameRate: 24        // 24 fps matches TurboMeta's approach
        )

        streamSession = StreamSession(streamSessionConfig: config, deviceSelector: deviceSelector!)

        // Subscribe to video frames
        videoFrameListenerToken = streamSession?.videoFramePublisher.listen { [weak self] videoFrame in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let image = videoFrame.makeUIImage() {
                    self.currentVideoFrame = image
                    self.delegate?.glassesDidUpdateVideoFrame(image)
                    self.scanForQRCode(in: image)
                }
            }
        }

        // Subscribe to errors
        errorListenerToken = streamSession?.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                print("[MetaGlasses] ❌ Stream error: \(error)")

                let errorDescription = "\(error)"
                var userMessage = "Camera streaming error"
                var speakMessage = "Camera error occurred"

                if errorDescription.contains("deviceNotFound") || errorDescription.contains("DeviceNotFound") {
                    userMessage = "Glasses not found. Ensure firmware is v20+ and developer mode is enabled."
                    speakMessage = "Glasses not found. Check firmware version."
                    print("[MetaGlasses] Error: Device not found - check firmware v20+ and Meta AI developer mode")
                } else if errorDescription.contains("deviceNotConnected") || errorDescription.contains("DeviceNotConnected") {
                    userMessage = "Glasses disconnected. Please reconnect via Bluetooth."
                    speakMessage = "Glasses disconnected"
                } else if errorDescription.contains("permissionDenied") || errorDescription.contains("PermissionDenied") {
                    userMessage = "Camera permission denied. Enable in Meta View > Settings > Device Access."
                    speakMessage = "Camera permission denied. Enable in Meta View app."
                } else if errorDescription.contains("timeout") || errorDescription.contains("Timeout") {
                    userMessage = "Connection timeout. Try restarting glasses and the app."
                    speakMessage = "Connection timed out"
                }

                self.speak(speakMessage, language: "en-US")
                self.connectionState = .error(userMessage)

                self.delegate?.glassesDidEncounterError(NSError(
                    domain: "MetaGlasses",
                    code: 100,
                    userInfo: [NSLocalizedDescriptionKey: userMessage]
                ))
            }
        }

        // Subscribe to state changes
        stateListenerToken = streamSession?.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                print("[MetaGlasses] StreamSession state: \(state)")

                switch state {
                case .streaming:
                    print("[MetaGlasses] ✅ Camera streaming active!")
                    self.connectionState = .streaming
                    self.isStreamingCamera = true
                case .waitingForDevice:
                    print("[MetaGlasses] ⏳ Waiting for device...")
                    print("[MetaGlasses] Ensure: 1) Firmware v20+ 2) Developer mode enabled in Meta AI app")
                    // Don't speak every time - only on first wait
                    if !self.isStreamingCamera {
                        self.speak("Waiting for glasses. Make sure developer mode is enabled.", language: "en-US")
                    }
                case .starting:
                    print("[MetaGlasses] 🔄 StreamSession starting...")
                case .paused:
                    print("[MetaGlasses] ⏸️ StreamSession paused")
                    self.isStreamingCamera = false
                case .stopped:
                    print("[MetaGlasses] ⏹️ StreamSession stopped")
                    self.isStreamingCamera = false
                    if self.connectionState == .streaming {
                        self.connectionState = .connected
                    }
                @unknown default:
                    print("[MetaGlasses] Unknown StreamSession state: \(state)")
                }
            }
        }

        isStreamSessionInitialized = true
        print("[MetaGlasses] ✅ StreamSession initialized (will be reused)")
    }

    /// Start streaming camera from glasses
    public func startCameraStream() async {
        guard let wearables = wearables else {
            print("[MetaGlasses] Cannot start stream - SDK not initialized")
            connectionState = .error("SDK not initialized")
            return
        }

        // Must be registered first
        guard isConnected else {
            print("[MetaGlasses] Cannot start stream - not connected")
            connectionState = .error("Connect to glasses first")
            return
        }

        print("[MetaGlasses] Starting camera stream...")
        print("[MetaGlasses] Connected devices: \(devices.count), HFP: \(isGlassesHFPConnected)")

        // KEY INSIGHT: If devices.isEmpty, the SDK cannot communicate with glasses yet.
        // Instead of blocking with a permission check that will fail (PermissionError 0),
        // we skip the permission check and let StreamSession enter "waitingForDevice" state.
        // The AutoDeviceSelector will automatically connect when the SDK recognizes the glasses.

        if devices.isEmpty {
            print("[MetaGlasses] ⚠️ No devices detected yet - skipping permission check")
            print("[MetaGlasses] StreamSession will wait for device connection...")
            speak("Waiting for glasses connection.", language: "en-US")
        } else {
            // Only check permissions if we have devices - otherwise it will fail with error 0
            do {
                let status = try await wearables.checkPermissionStatus(.camera)
                print("[MetaGlasses] Camera permission status: \(status)")

                if status != .granted {
                    print("[MetaGlasses] Requesting camera permission - this will open Meta View...")
                    speak("Opening Meta View for camera permission.", language: "en-US")

                    let requestStatus = try await wearables.requestPermission(.camera)
                    print("[MetaGlasses] Permission request result: \(requestStatus)")

                    if requestStatus != .granted {
                        print("[MetaGlasses] Camera permission denied by user")
                        speak("Camera access denied. Please approve in Meta View app settings.", language: "en-US")
                        connectionState = .error("Camera denied - approve in Meta View > VoiceSwap")
                        return
                    }

                    print("[MetaGlasses] ✅ Camera permission granted!")
                    speak("Camera access granted.", language: "en-US")
                } else {
                    print("[MetaGlasses] ✅ Camera permission already granted")
                }
            } catch {
                print("[MetaGlasses] Permission error: \(error)")
                let errorDesc = "\(error)"

                // PermissionError(rawValue: 0) - don't block, let StreamSession try anyway
                if errorDesc.contains("PermissionError(rawValue: 0)") {
                    print("[MetaGlasses] PermissionError 0 - SDK may not see device yet, continuing anyway...")
                    print("[MetaGlasses] StreamSession will enter waitingForDevice state")
                    // Don't return - let StreamSession handle the device discovery
                } else {
                    speak("Camera permission error. Check Meta View settings.", language: "en-US")
                    connectionState = .error("Camera error: \(error.localizedDescription)")
                    return
                }
            }
        }

        // Configure HFP audio BEFORE starting streaming
        do {
            try configureHFPAudio()
        } catch {
            print("[MetaGlasses] Warning: Could not configure HFP audio: \(error)")
        }

        // Initialize StreamSession once (reused across start/stop cycles)
        if !isStreamSessionInitialized {
            initializeStreamSession()
        }

        // Start the session (reusing existing instance)
        print("[MetaGlasses] Calling streamSession.start()...")
        await streamSession?.start()
        print("[MetaGlasses] streamSession.start() returned")
    }

    /// Stop camera streaming
    /// Note: We only stop the stream, not destroy the session (reused per Meta SDK pattern)
    public func stopCameraStream() {
        Task {
            await streamSession?.stop()
        }

        isStreamingCamera = false
        currentVideoFrame = nil

        if connectionState == .streaming {
            connectionState = .connected
        }

        print("[MetaGlasses] Camera streaming stopped (session preserved for reuse)")
    }

    /// Cleanup StreamSession completely (call on disconnect or app termination)
    private func cleanupStreamSession() {
        stateListenerToken = nil
        videoFrameListenerToken = nil
        errorListenerToken = nil
        deviceMonitorTask?.cancel()
        deviceMonitorTask = nil
        streamSession = nil
        deviceSelector = nil
        isStreamSessionInitialized = false
        isStreamingCamera = false
        currentVideoFrame = nil
        print("[MetaGlasses] StreamSession cleaned up")
    }

    // MARK: - QR Code Detection (Vision Framework)

    /// Scan for QR codes in camera frame using Apple Vision framework
    /// Vision is significantly faster and more accurate than CIDetector for real-time detection
    private func scanForQRCode(in image: UIImage) {
        // Check cooldown to avoid duplicate detections
        guard Date().timeIntervalSince(lastQRDetectionTime) > qrDetectionCooldown else { return }

        // Avoid processing multiple frames simultaneously
        guard !isProcessingFrame else { return }
        isProcessingFrame = true

        guard let cgImage = image.cgImage else {
            isProcessingFrame = false
            return
        }

        // Process on dedicated Vision queue to keep main thread responsive
        visionQueue.async { [weak self] in
            guard let self = self else { return }

            // Create Vision barcode detection request
            let request = VNDetectBarcodesRequest { [weak self] request, error in
                guard let self = self else { return }

                defer {
                    Task { @MainActor in
                        self.isProcessingFrame = false
                    }
                }

                if let error = error {
                    print("[MetaGlasses] Vision QR detection error: \(error.localizedDescription)")
                    return
                }

                guard let results = request.results as? [VNBarcodeObservation] else { return }

                // Process detected barcodes
                for barcode in results {
                    // We're specifically looking for QR codes
                    guard barcode.symbology == .qr else { continue }
                    guard let payloadString = barcode.payloadStringValue else { continue }

                    // Try to parse as VoiceSwap payment QR
                    if let result = QRScanResult.parse(from: payloadString) {
                        Task { @MainActor in
                            self.handleDetectedQR(result, rawData: payloadString, confidence: barcode.confidence)
                        }
                        return
                    }
                }
            }

            // Configure for QR code detection specifically
            request.symbologies = [.qr]

            // Perform the request
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("[MetaGlasses] Vision request failed: \(error.localizedDescription)")
                Task { @MainActor in
                    self.isProcessingFrame = false
                }
            }
        }
    }

    /// Handle a successfully detected QR code
    private func handleDetectedQR(_ result: QRScanResult, rawData: String, confidence: Float) {
        // Update detection time to trigger cooldown
        lastQRDetectionTime = Date()
        lastDetectedQR = result

        print("[MetaGlasses] ✅ QR detected via Vision (confidence: \(String(format: "%.1f%%", confidence * 100)))")
        print("[MetaGlasses]    Raw data: \(rawData)")
        if let wallet = result.merchantWallet {
            print("[MetaGlasses]    Wallet: \(wallet.prefix(10))...")
        }
        if let amount = result.amount {
            print("[MetaGlasses]    Amount: \(amount)")
        }
        if let name = result.merchantName {
            print("[MetaGlasses]    Merchant: \(name)")
        }

        // Notify delegate
        delegate?.glassesDidScanQR(result)

        // Provide haptic and voice feedback
        triggerHaptic(.success)

        if let name = result.merchantName, let amount = result.amount {
            speak("Found payment: \(amount) dollars to \(name)")
        } else if let name = result.merchantName {
            speak("Payment request from \(name)")
        } else if result.merchantWallet != nil {
            speak("Payment QR detected")
        }
    }

    /// Fallback QR detection using CIDetector (slower but works on older iOS)
    private func scanForQRCodeFallback(in image: UIImage) {
        guard Date().timeIntervalSince(lastQRDetectionTime) > qrDetectionCooldown else { return }

        guard let ciImage = CIImage(image: image),
              let detector = qrDetector else { return }

        let features = detector.features(in: ciImage)

        for feature in features {
            if let qrFeature = feature as? CIQRCodeFeature,
               let messageString = qrFeature.messageString {

                if let result = QRScanResult.parse(from: messageString) {
                    handleDetectedQR(result, rawData: messageString, confidence: 0.8)
                    return
                }
            }
        }
    }

    // MARK: - Voice Commands

    public func startListening() {
        if connectionState == .disconnected {
            connectionState = .connected
            batteryLevel = 100
            isDirectMode = true
        }

        do {
            try startSpeechRecognition()
            isListening = true
            isWakeWordDetected = isDirectMode
        } catch {
            delegate?.glassesDidEncounterError(error)
        }
    }

    public func stopListening() {
        let transcriptToProcess = pendingTranscript
        let shouldProcess = !transcriptToProcess.isEmpty && isWakeWordDetected

        cleanupAudioEngine()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        if shouldProcess {
            pendingTranscript = ""
            let result = VoiceCommandResult(
                transcript: transcriptToProcess,
                confidence: 0.9,
                language: detectLanguage(transcriptToProcess),
                timestamp: Date()
            )
            delegate?.glassesDidReceiveVoiceCommand(result)
        }
    }

    public func speak(_ text: String, language: String = "en-US") {
        // DISABLED FOR DEBUGGING - Testing if audio interferes with Meta callback
        print("[MetaGlasses] SPEAK (disabled): \(text)")
        // let utterance = AVSpeechUtterance(string: text)
        // utterance.voice = AVSpeechSynthesisVoice(language: language)
        // utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        // utterance.pitchMultiplier = 1.0
        // utterance.volume = 1.0
        // synthesizer.speak(utterance)
    }

    public func triggerHaptic(_ pattern: HapticPattern) {
        let generator = UINotificationFeedbackGenerator()
        switch pattern {
        case .short:
            generator.notificationOccurred(.warning)
        case .double, .long, .success:
            generator.notificationOccurred(.success)
        case .error:
            generator.notificationOccurred(.error)
        }
    }

    // MARK: - Speech Recognition Private Methods

    private func setupSpeechRecognition() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                if status == .authorized {
                    self?.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
                }
            }
        }
    }

    private func startSpeechRecognition() throws {
        // DISABLED FOR DEBUGGING - Testing if audio interferes with Meta callback
        print("[MetaGlasses] startSpeechRecognition() DISABLED FOR DEBUGGING")
        return
        /*
        recognitionTask?.cancel()
        recognitionTask = nil

        if audioEngine != nil {
            if audioEngine.isRunning { audioEngine.stop() }
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        audioEngine = AVAudioEngine()
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "MetaGlasses", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }

        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let transcript = result.bestTranscription.formattedString
                self.lastTranscript = transcript
                if !transcript.isEmpty { self.pendingTranscript = transcript }

                Task { @MainActor in
                    await self.processTranscript(transcript, isFinal: result.isFinal)
                }
            }

            if error != nil || result?.isFinal == true {
                self.cleanupAudioEngine()
                self.recognitionRequest = nil
                self.recognitionTask = nil

                if self.connectionState == .connected && self.isListening {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        if !self.synthesizer.isSpeaking {
                            try? self.startSpeechRecognition()
                        }
                    }
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        */
    }

    private func cleanupAudioEngine() {
        guard audioEngine != nil else { return }
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func processTranscript(_ transcript: String, isFinal: Bool) async {
        guard !transcript.isEmpty else { return }

        let lowercased = transcript.lowercased()

        if !isWakeWordDetected {
            for wakeWord in wakeWords {
                if lowercased.contains(wakeWord) {
                    isWakeWordDetected = true
                    speak("I'm listening")
                    triggerHaptic(.short)
                    return
                }
            }
            return
        }

        if isFinal && isWakeWordDetected {
            if !isDirectMode { isWakeWordDetected = false }
            pendingTranscript = ""

            let result = VoiceCommandResult(
                transcript: transcript,
                confidence: 0.9,
                language: detectLanguage(transcript),
                timestamp: Date()
            )
            delegate?.glassesDidReceiveVoiceCommand(result)
        }
    }

    private func detectLanguage(_ text: String) -> String {
        let spanishIndicators = ["pagar", "enviar", "cuánto", "cuanto", "confirmar", "cancelar", "sí", "dale"]
        for indicator in spanishIndicators {
            if text.lowercased().contains(indicator) { return "es" }
        }
        return "en"
    }

    deinit {
        registrationTask?.cancel()
        deviceStreamTask?.cancel()
        deviceMonitorTask?.cancel()
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension MetaGlassesManager: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("[MetaGlasses] Finished speaking")
    }
}
