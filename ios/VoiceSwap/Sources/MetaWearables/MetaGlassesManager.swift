/**
 * MetaGlassesManager.swift
 * VoiceSwap - Voice-activated crypto payments for Meta Ray-Ban glasses
 *
 * This module manages voice commands and audio for VoiceSwap.
 * Currently uses iPhone microphone with future Meta Glasses SDK integration.
 */

import Foundation
import Combine
import AVFoundation
import Speech
import UIKit
import CoreImage

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

// MARK: - Haptic Patterns

public enum HapticPattern {
    case short      // Single short vibration
    case double     // Two short vibrations
    case long       // One long vibration
    case success    // Success pattern
    case error      // Error pattern
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

    // MARK: - Delegate
    public weak var delegate: MetaGlassesDelegate?

    // MARK: - Private Properties
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine!
    private let synthesizer = AVSpeechSynthesizer()

    // VoiceSwap API client
    private let apiBaseURL: String
    private var userWalletAddress: String?
    private var currentMerchantWallet: String?

    // Wake word detection
    private let wakeWords = ["hey voiceswap", "oye voiceswap", "voice swap", "pagar", "pay"]
    private var isWakeWordDetected = false
    private var isDirectMode = false
    private var pendingTranscript = ""

    // QR Detection
    private var qrDetector: CIDetector?

    // MARK: - Initialization

    private override init() {
        #if DEBUG
        self.apiBaseURL = ProcessInfo.processInfo.environment["VOICESWAP_API_URL"] ?? "http://192.168.100.9:4021"
        #else
        self.apiBaseURL = "https://voiceswap.vercel.app"
        #endif
        self.audioEngine = AVAudioEngine()
        super.init()

        // Initialize QR detector
        self.qrDetector = CIDetector(                     
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        )

        setupSpeechRecognition()
        print("[MetaGlasses] Initialized - using iPhone microphone mode")
    }

    // MARK: - Public Methods

    /// Configure the manager with user's wallet address
    public func configure(walletAddress: String) {
        self.userWalletAddress = walletAddress
        print("[MetaGlasses] Configured with wallet: \(walletAddress.prefix(10))...")
    }

    /// Connect to Meta Ray-Ban glasses (currently simulated)
    public func connectToGlasses() async throws {
        connectionState = .searching

        // Simulate connection delay
        try await Task.sleep(nanoseconds: 1_500_000_000)

        connectionState = .connected
        batteryLevel = 100
        isDirectMode = true
        delegate?.glassesDidConnect()
        print("[MetaGlasses] Connected (iPhone mode)")
    }

    /// Disconnect from glasses
    public func disconnect() {
        stopListening()
        stopCameraStream()
        connectionState = .disconnected
        isDirectMode = false
        isWakeWordDetected = false
        delegate?.glassesDidDisconnect()
        print("[MetaGlasses] Disconnected")
    }

    /// Start listening for voice commands
    public func startListening() {
        if connectionState == .disconnected {
            connectionState = .connected
            batteryLevel = 100
            isDirectMode = true
            print("[MetaGlasses] Using iPhone microphone mode")
        }

        do {
            try startSpeechRecognition()
            isListening = true
            isWakeWordDetected = isDirectMode
            print("[MetaGlasses] Started listening (directMode: \(isDirectMode))")
        } catch {
            print("[MetaGlasses] Failed to start listening: \(error)")
            delegate?.glassesDidEncounterError(error)
        }
    }

    /// Stop listening for voice commands
    public func stopListening() {
        let transcriptToProcess = pendingTranscript
        let shouldProcess = !transcriptToProcess.isEmpty && isWakeWordDetected

        cleanupAudioEngine()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        print("[MetaGlasses] Stopped listening (pending: '\(transcriptToProcess)')")

        if shouldProcess {
            pendingTranscript = ""
            let result = VoiceCommandResult(
                transcript: transcriptToProcess,
                confidence: 0.9,
                language: detectLanguage(transcriptToProcess),
                timestamp: Date()
            )
            print("[MetaGlasses] Processing pending command: \(transcriptToProcess)")
            delegate?.glassesDidReceiveVoiceCommand(result)
        }
    }

    /// Speak text through speakers
    public func speak(_ text: String, language: String = "en-US") {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.speak(utterance)
        print("[MetaGlasses] Speaking: \(text)")
    }

    /// Trigger haptic feedback
    public func triggerHaptic(_ pattern: HapticPattern) {
        print("[MetaGlasses] Haptic feedback: \(pattern)")

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

    // MARK: - Camera Streaming (Placeholder)

    public func startCameraStream() {
        print("[MetaGlasses] Camera streaming not available in iPhone mode")
        isStreamingCamera = false
    }

    public func stopCameraStream() {
        isStreamingCamera = false
        print("[MetaGlasses] Stopped camera stream")
    }

    public func captureForQRScan() async throws -> QRScanResult? {
        return nil
    }

    // MARK: - Private Methods

    private func setupSpeechRecognition() {
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
        recognitionTask?.cancel()
        recognitionTask = nil

        if audioEngine != nil {
            if audioEngine.isRunning {
                audioEngine.stop()
            }
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
        recognitionRequest.requiresOnDeviceRecognition = false

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            throw NSError(domain: "MetaGlasses", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid audio format"])
        }

        print("[MetaGlasses] Audio format: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount) ch")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                print("[MetaGlasses] Recognition error: \(error.localizedDescription)")
            }

            if let result = result {
                let transcript = result.bestTranscription.formattedString
                self.lastTranscript = transcript

                if !transcript.isEmpty {
                    self.pendingTranscript = transcript
                }

                Task { @MainActor in
                    let transcriptToProcess = transcript.isEmpty ? self.pendingTranscript : transcript
                    await self.processTranscript(transcriptToProcess, isFinal: result.isFinal)
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
                        } else {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                try? self.startSpeechRecognition()
                            }
                        }
                    }
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    private func cleanupAudioEngine() {
        guard audioEngine != nil else { return }
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
    }

    private func processTranscript(_ transcript: String, isFinal: Bool) async {
        guard !transcript.isEmpty else { return }

        let lowercased = transcript.lowercased()

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

        if isFinal && isWakeWordDetected {
            if !isDirectMode {
                isWakeWordDetected = false
            }

            self.pendingTranscript = ""

            let result = VoiceCommandResult(
                transcript: transcript,
                confidence: 0.9,
                language: detectLanguage(transcript),
                timestamp: Date()
            )

            print("[MetaGlasses] Processing voice command: \(transcript)")

            if let delegate = delegate {
                delegate.glassesDidReceiveVoiceCommand(result)
            } else {
                print("[MetaGlasses] WARNING: delegate is nil!")
            }
        }
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
}

// MARK: - AVSpeechSynthesizerDelegate

extension MetaGlassesManager: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("[MetaGlasses] Finished speaking")
    }
}
