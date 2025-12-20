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

    /// Parse a VoiceSwap deep link URL
    public static func parse(from urlString: String) -> QRScanResult? {
        // Handle voiceswap:// deep links
        if urlString.hasPrefix("voiceswap://pay?") {
            guard let url = URL(string: urlString),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return nil
            }

            let queryItems = components.queryItems ?? []
            let wallet = queryItems.first(where: { $0.name == "wallet" })?.value
            let amount = queryItems.first(where: { $0.name == "amount" })?.value
            let name = queryItems.first(where: { $0.name == "name" })?.value

            return QRScanResult(
                rawData: urlString,
                merchantWallet: wallet,
                amount: amount,
                merchantName: name
            )
        }

        // Handle plain Ethereum addresses
        if urlString.hasPrefix("0x") && urlString.count == 42 {
            return QRScanResult(
                rawData: urlString,
                merchantWallet: urlString,
                amount: nil,
                merchantName: nil
            )
        }

        return nil
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

    // MARK: - Delegate
    public weak var delegate: MetaGlassesDelegate?

    // MARK: - Meta Wearables SDK Properties
    private var wearables: WearablesInterface?
    private var streamSession: StreamSession?
    private var deviceSelector: AutoDeviceSelector?
    private var registrationTask: Task<Void, Never>?
    private var deviceStreamTask: Task<Void, Never>?
    private var stateListenerToken: AnyListenerToken?
    private var videoFrameListenerToken: AnyListenerToken?
    private var errorListenerToken: AnyListenerToken?

    // MARK: - Speech Recognition Properties
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine!
    private let synthesizer = AVSpeechSynthesizer()

    // MARK: - QR Detection
    private var qrDetector: CIDetector?
    private var lastQRDetectionTime: Date = .distantPast
    private let qrDetectionCooldown: TimeInterval = 2.0

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

        // Initialize Meta Wearables SDK
        initializeWearablesSDK()

        // Setup speech recognition
        setupSpeechRecognition()

        print("[MetaGlasses] Initialized with Meta Wearables DAT SDK")
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

        registrationTask = Task {
            for await registrationState in wearables.registrationStateStream() {
                await MainActor.run {
                    switch registrationState {
                    case .unregistered:
                        self.connectionState = .disconnected
                    case .registering:
                        self.connectionState = .connecting
                    case .registered:
                        self.connectionState = .registered
                        self.setupDeviceStream()
                    }
                }
            }
        }
    }

    private func setupDeviceStream() {
        guard let wearables = wearables else { return }

        deviceStreamTask?.cancel()
        deviceStreamTask = Task {
            for await devices in wearables.devicesStream() {
                await MainActor.run {
                    self.devices = devices
                    if !devices.isEmpty {
                        self.connectionState = .connected
                        self.delegate?.glassesDidConnect()
                        print("[MetaGlasses] Device connected: \(devices.count) device(s)")
                    }
                }
            }
        }
    }

    // MARK: - Public Methods

    /// Configure the manager with user's wallet address
    public func configure(walletAddress: String) {
        self.userWalletAddress = walletAddress
        print("[MetaGlasses] Configured with wallet: \(walletAddress.prefix(10))...")
    }

    /// Connect to Meta Ray-Ban glasses
    public func connectToGlasses() async throws {
        guard let wearables = wearables else {
            throw NSError(domain: "MetaGlasses", code: 1, userInfo: [NSLocalizedDescriptionKey: "Wearables SDK not initialized"])
        }

        connectionState = .searching

        do {
            try wearables.startRegistration()
            print("[MetaGlasses] Started registration - redirecting to Meta AI app")
        } catch {
            connectionState = .error("Failed to start registration: \(error.localizedDescription)")
            throw error
        }
    }

    /// Disconnect from glasses
    public func disconnect() {
        stopListening()
        stopCameraStream()

        if let wearables = wearables {
            do {
                try wearables.startUnregistration()
            } catch {
                print("[MetaGlasses] Failed to unregister: \(error)")
            }
        }

        connectionState = .disconnected
        devices = []
        delegate?.glassesDidDisconnect()
        print("[MetaGlasses] Disconnected")
    }

    // MARK: - Camera Streaming

    /// Start streaming camera from glasses
    public func startCameraStream() async {
        guard let wearables = wearables else {
            print("[MetaGlasses] Cannot start stream - SDK not initialized")
            return
        }

        // Check camera permission
        do {
            let status = try await wearables.checkPermissionStatus(.camera)
            if status != .granted {
                let requestStatus = try await wearables.requestPermission(.camera)
                if requestStatus != .granted {
                    print("[MetaGlasses] Camera permission denied")
                    return
                }
            }
        } catch {
            print("[MetaGlasses] Permission error: \(error)")
            return
        }

        // Create device selector and stream session
        deviceSelector = AutoDeviceSelector(wearables: wearables)

        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .low,
            frameRate: 15
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
                print("[MetaGlasses] Stream error: \(error)")
                self?.delegate?.glassesDidEncounterError(NSError(
                    domain: "MetaGlasses",
                    code: 100,
                    userInfo: [NSLocalizedDescriptionKey: "Streaming error occurred"]
                ))
            }
        }

        // Subscribe to state changes
        stateListenerToken = streamSession?.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch state {
                case .streaming:
                    self.connectionState = .streaming
                    self.isStreamingCamera = true
                case .stopped:
                    self.isStreamingCamera = false
                    if self.connectionState == .streaming {
                        self.connectionState = .connected
                    }
                default:
                    break
                }
            }
        }

        await streamSession?.start()
        isStreamingCamera = true
        connectionState = .streaming
        print("[MetaGlasses] Camera streaming started")
    }

    /// Stop camera streaming
    public func stopCameraStream() {
        Task {
            await streamSession?.stop()
        }

        stateListenerToken = nil
        videoFrameListenerToken = nil
        errorListenerToken = nil
        streamSession = nil
        deviceSelector = nil

        isStreamingCamera = false
        currentVideoFrame = nil

        if connectionState == .streaming {
            connectionState = .connected
        }

        print("[MetaGlasses] Camera streaming stopped")
    }

    // MARK: - QR Code Detection

    private func scanForQRCode(in image: UIImage) {
        guard Date().timeIntervalSince(lastQRDetectionTime) > qrDetectionCooldown else { return }

        guard let ciImage = CIImage(image: image),
              let detector = qrDetector else { return }

        let features = detector.features(in: ciImage)

        for feature in features {
            if let qrFeature = feature as? CIQRCodeFeature,
               let messageString = qrFeature.messageString {

                if let result = QRScanResult.parse(from: messageString) {
                    lastQRDetectionTime = Date()
                    lastDetectedQR = result

                    print("[MetaGlasses] QR detected: \(messageString)")

                    delegate?.glassesDidScanQR(result)
                    triggerHaptic(.success)

                    if let name = result.merchantName {
                        speak("Payment request from \(name)")
                    } else if result.merchantWallet != nil {
                        speak("Payment request detected")
                    }

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
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        synthesizer.speak(utterance)
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
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension MetaGlassesManager: AVSpeechSynthesizerDelegate {
    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("[MetaGlasses] Finished speaking")
    }
}
