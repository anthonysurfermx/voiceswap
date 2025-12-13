/**
 * MetaGlassesManager.swift
 * VoiceSwap - Voice-activated crypto payments for Meta Ray-Ban glasses
 *
 * This module manages the connection to Meta Ray-Ban smart glasses
 * using the Meta Wearables SDK (Device Access Toolkit - DAT)
 *
 * Features:
 * - Bluetooth connection management
 * - Voice command capture via glasses microphone
 * - Camera access for QR code scanning
 * - Text-to-Speech for voice responses
 * - Haptic feedback for confirmations
 */

import Foundation
import Combine
import AVFoundation
import Speech

// MARK: - Meta Glasses Connection State

public enum GlassesConnectionState: Equatable {
    case disconnected
    case searching
    case connecting
    case connected
    case error(String)
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
}

// MARK: - Meta Glasses Manager Protocol

public protocol MetaGlassesDelegate: AnyObject {
    func glassesDidConnect()
    func glassesDidDisconnect()
    func glassesDidReceiveVoiceCommand(_ result: VoiceCommandResult)
    func glassesDidScanQR(_ result: QRScanResult)
    func glassesDidEncounterError(_ error: Error)
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

    // MARK: - Delegate
    public weak var delegate: MetaGlassesDelegate?

    // MARK: - Private Properties
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()

    // VoiceSwap API client
    private let apiBaseURL: String
    private var userWalletAddress: String?
    private var currentMerchantWallet: String?

    // Wake word detection
    private let wakeWords = ["hey voiceswap", "oye voiceswap", "voice swap", "pagar", "pay"]
    private var isWakeWordDetected = false

    // MARK: - Initialization

    private override init() {
        #if DEBUG
        self.apiBaseURL = ProcessInfo.processInfo.environment["VOICESWAP_API_URL"] ?? "http://192.168.100.9:4021"
        #else
        self.apiBaseURL = "https://voiceswap.cc"
        #endif
        super.init()
        setupSpeechRecognition()
    }

    // MARK: - Public Methods

    /// Configure the manager with user's wallet address
    public func configure(walletAddress: String) {
        self.userWalletAddress = walletAddress
        print("[MetaGlasses] Configured with wallet: \(walletAddress.prefix(10))...")
    }

    /// Connect to Meta Ray-Ban glasses
    public func connectToGlasses() async throws {
        connectionState = .searching

        // TODO: Implement actual Meta Wearables SDK connection
        // For now, simulate connection for development
        try await simulateGlassesConnection()
    }

    /// Disconnect from glasses
    public func disconnect() {
        stopListening()
        connectionState = .disconnected
        delegate?.glassesDidDisconnect()
        print("[MetaGlasses] Disconnected")
    }

    /// Start listening for voice commands
    public func startListening() {
        // Allow listening even without glasses (use iPhone mic)
        if connectionState == .disconnected {
            // Auto-connect in iPhone mode
            connectionState = .connected
            batteryLevel = 100
            print("[MetaGlasses] Using iPhone microphone mode")
        }

        do {
            try startSpeechRecognition()
            isListening = true
            isWakeWordDetected = true // Skip wake word in direct mode
            print("[MetaGlasses] Started listening for voice commands")
        } catch {
            print("[MetaGlasses] Failed to start listening: \(error)")
            delegate?.glassesDidEncounterError(error)
        }
    }

    /// Stop listening for voice commands
    public func stopListening() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        isListening = false
        print("[MetaGlasses] Stopped listening")
    }

    /// Speak text through glasses speakers
    public func speak(_ text: String, language: String = "en-US") {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.speak(utterance)
        print("[MetaGlasses] Speaking: \(text)")
    }

    /// Trigger haptic feedback on glasses
    public func triggerHaptic(_ pattern: HapticPattern) {
        // TODO: Implement actual haptic feedback via Meta SDK
        print("[MetaGlasses] Haptic feedback: \(pattern)")
    }

    /// Capture photo for QR scanning
    public func captureForQRScan() async throws -> QRScanResult? {
        // TODO: Implement actual camera capture via Meta SDK
        print("[MetaGlasses] Capturing for QR scan...")

        // Simulate QR detection for development
        return nil
    }

    // MARK: - Private Methods

    private func setupSpeechRecognition() {
        // Request authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    print("[MetaGlasses] Speech recognition authorized")
                    self?.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
                case .denied, .restricted, .notDetermined:
                    print("[MetaGlasses] Speech recognition not authorized: \(status)")
                @unknown default:
                    break
                }
            }
        }
    }

    private func startSpeechRecognition() throws {
        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            throw NSError(domain: "MetaGlasses", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to create recognition request"])
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false

        // Get input node
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let transcript = result.bestTranscription.formattedString
                self.lastTranscript = transcript

                // Check for wake word or process command
                Task { @MainActor in
                    await self.processTranscript(transcript, isFinal: result.isFinal)
                }
            }

            if error != nil || result?.isFinal == true {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil

                // Restart listening if still connected
                if self.connectionState == .connected && self.isListening {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        try? self.startSpeechRecognition()
                    }
                }
            }
        }

        // Start audio engine
        audioEngine.prepare()
        try audioEngine.start()
    }

    private func processTranscript(_ transcript: String, isFinal: Bool) async {
        let lowercased = transcript.lowercased()

        // Check for wake word
        if !isWakeWordDetected {
            for wakeWord in wakeWords {
                if lowercased.contains(wakeWord) {
                    isWakeWordDetected = true
                    speak("I'm listening", language: "en-US")
                    triggerHaptic(.short)
                    print("[MetaGlasses] Wake word detected!")
                    return
                }
            }
            return
        }

        // Process command if wake word was detected and this is final
        if isFinal && isWakeWordDetected {
            isWakeWordDetected = false

            let result = VoiceCommandResult(
                transcript: transcript,
                confidence: 0.9,
                language: detectLanguage(transcript),
                timestamp: Date()
            )

            // Send to VoiceSwap API for processing
            await processVoiceCommand(result)

            delegate?.glassesDidReceiveVoiceCommand(result)
        }
    }

    private func processVoiceCommand(_ command: VoiceCommandResult) async {
        guard let walletAddress = userWalletAddress else {
            speak("Please connect your wallet first", language: "en-US")
            return
        }

        do {
            // Call VoiceSwap AI endpoint
            let response = try await callVoiceSwapAPI(
                endpoint: "/voiceswap/ai/process",
                body: [
                    "transcript": command.transcript,
                    "userAddress": walletAddress,
                    "merchantWallet": currentMerchantWallet as Any
                ]
            )

            // Speak the response
            if let voiceResponse = response["data"] as? [String: Any],
               let speechText = voiceResponse["voiceResponse"] as? String {

                let language = command.language == "es" ? "es-ES" : "en-US"
                speak(speechText, language: language)

                // Handle next action
                if let nextAction = voiceResponse["nextAction"] as? String {
                    await handleNextAction(nextAction, response: voiceResponse)
                }
            }
        } catch {
            print("[MetaGlasses] API error: \(error)")
            speak("Sorry, there was an error processing your request", language: "en-US")
        }
    }

    private func handleNextAction(_ action: String, response: [String: Any]) async {
        switch action {
        case "scan_qr":
            speak("Please look at the QR code", language: "en-US")
            // Trigger QR scan

        case "await_confirmation":
            triggerHaptic(.double)
            // Wait for confirm/cancel voice command

        case "execute_transaction":
            triggerHaptic(.long)
            // Execute the payment
            await executePayment()

        case "cancel_transaction":
            triggerHaptic(.short)
            currentMerchantWallet = nil

        case "show_balance":
            triggerHaptic(.short)

        default:
            break
        }
    }

    private func executePayment() async {
        guard let walletAddress = userWalletAddress,
              let merchantWallet = currentMerchantWallet else {
            return
        }

        do {
            let response = try await callVoiceSwapAPI(
                endpoint: "/voiceswap/execute",
                body: [
                    "userAddress": walletAddress,
                    "merchantWallet": merchantWallet,
                    "amount": "10" // TODO: Get from context
                ]
            )

            if let data = response["data"] as? [String: Any],
               let message = data["message"] as? String {
                speak(message, language: "en-US")
                triggerHaptic(.success)
            }
        } catch {
            speak("Payment failed. Please try again.", language: "en-US")
            triggerHaptic(.error)
        }
    }

    private func callVoiceSwapAPI(endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: "\(apiBaseURL)\(endpoint)") else {
            throw NSError(domain: "MetaGlasses", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "MetaGlasses", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }

        return json
    }

    private func detectLanguage(_ text: String) -> String {
        let spanishIndicators = ["pagar", "enviar", "cuánto", "cuanto", "confirmar", "cancelar", "sí", "dale"]
        let lowercased = text.lowercased()

        for indicator in spanishIndicators {
            if lowercased.contains(indicator) {
                return "es"
            }
        }

        return "en"
    }

    private func simulateGlassesConnection() async throws {
        // Simulate connection delay
        try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

        connectionState = .connected
        batteryLevel = 85
        delegate?.glassesDidConnect()
        print("[MetaGlasses] Connected (simulated)")
    }
}

// MARK: - Haptic Patterns

public enum HapticPattern {
    case short      // Single short vibration
    case double     // Two short vibrations
    case long       // One long vibration
    case success    // Success pattern
    case error      // Error pattern
}

// MARK: - AVSpeechSynthesizerDelegate

extension MetaGlassesManager: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("[MetaGlasses] Finished speaking")
    }
}
