/**
 * SpeechRecognizer.swift
 * VoiceSwap - On-device speech-to-text for BetWhisper chat
 *
 * Uses SFSpeechRecognizer with auto locale detection (EN/ES),
 * Bluetooth audio routing for Meta Ray-Ban glasses,
 * and timer-based silence detection (2s timeout).
 */

import Foundation
import Speech
import AVFoundation

@MainActor
class SpeechRecognizer: ObservableObject {

    // MARK: - Published State

    @Published var transcript: String = ""
    @Published var isListening: Bool = false
    @Published var permissionGranted: Bool = false
    @Published var errorMessage: String? = nil

    // MARK: - Callback

    var onFinalTranscript: ((String) -> Void)?

    // MARK: - Private

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.autoupdatingCurrent)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine = AVAudioEngine()
    private var silenceTimer: Timer?
    private let silenceTimeout: TimeInterval = 2.0

    // MARK: - Permission

    func requestPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                switch status {
                case .authorized:
                    self.permissionGranted = true
                case .denied:
                    self.permissionGranted = false
                    self.errorMessage = "Speech recognition denied. Enable in Settings > Privacy."
                    print("[SpeechRecognizer] Permission denied")
                case .restricted:
                    self.permissionGranted = false
                    self.errorMessage = "Speech recognition restricted on this device."
                    print("[SpeechRecognizer] Permission restricted")
                case .notDetermined:
                    self.permissionGranted = false
                    print("[SpeechRecognizer] Permission not determined")
                @unknown default:
                    self.permissionGranted = false
                }
            }
        }

        AVAudioApplication.requestRecordPermission { granted in
            if !granted {
                Task { @MainActor [weak self] in
                    self?.errorMessage = "Microphone access denied. Enable in Settings > Privacy."
                }
                print("[SpeechRecognizer] Microphone permission denied")
            }
        }
    }

    // MARK: - Start / Stop

    func startListening() {
        guard !isListening else { return }
        errorMessage = nil

        guard permissionGranted else {
            errorMessage = "Speech permission required"
            print("[SpeechRecognizer] Not authorized, requesting permission")
            requestPermission()
            return
        }

        guard speechRecognizer?.isAvailable == true else {
            errorMessage = "Speech recognition unavailable"
            print("[SpeechRecognizer] Speech recognizer not available")
            return
        }

        // Cancel any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        do {
            try configureAudioSession()
        } catch {
            errorMessage = "Audio error: \(error.localizedDescription)"
            print("[SpeechRecognizer] Audio session error: \(error)")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Could not create recognition request"
            return
        }
        recognitionRequest.shouldReportPartialResults = true

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Check for valid format
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            errorMessage = "Invalid audio format"
            print("[SpeechRecognizer] Invalid recording format: rate=\(recordingFormat.sampleRate) ch=\(recordingFormat.channelCount)")
            return
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Could not start audio engine"
            print("[SpeechRecognizer] Audio engine start error: \(error)")
            cleanUp()
            return
        }

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                if let result = result {
                    self.transcript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                }

                if let error = error {
                    // Ignore cancellation errors (expected when stopping manually)
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 216 {
                        // "kAFAssistantErrorDomain error 216" = recognition was cancelled, expected
                    } else if nsError.code == 1110 { // No speech detected
                        print("[SpeechRecognizer] No speech detected")
                    } else {
                        print("[SpeechRecognizer] Recognition error: \(error)")
                    }

                    if !self.transcript.isEmpty {
                        self.finalize()
                    } else {
                        self.stopListening()
                    }
                } else if result?.isFinal == true {
                    if !self.transcript.isEmpty {
                        self.finalize()
                    } else {
                        self.stopListening()
                    }
                }
            }
        }

        transcript = ""
        isListening = true
        resetSilenceTimer()
        print("[SpeechRecognizer] Listening started (locale: \(Locale.autoupdatingCurrent.identifier))")
    }

    func stopListening() {
        guard isListening else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false

        // Deactivate audio session to release mic for other uses
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[SpeechRecognizer] Could not deactivate audio session: \(error)")
        }

        print("[SpeechRecognizer] Listening stopped")
    }

    func toggle() {
        if isListening {
            // Manual stop: finalize whatever we have
            if !transcript.isEmpty {
                finalize()
            } else {
                stopListening()
            }
        } else {
            startListening()
        }
    }

    // MARK: - Private

    private func finalize() {
        let final = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        stopListening()
        if !final.isEmpty {
            print("[SpeechRecognizer] Final transcript: \(final)")
            onFinalTranscript?(final)
        }
        transcript = ""
    }

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.isListening else { return }
                if !self.transcript.isEmpty {
                    self.finalize()
                } else {
                    self.stopListening()
                }
            }
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        // Deactivate first to reset any previous state (e.g., from TTS)
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        try session.setCategory(.playAndRecord, mode: .voiceChat,
                                options: [.allowBluetoothHFP, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Prefer Bluetooth HFP input when glasses are connected
        if let btInput = session.availableInputs?.first(where: { $0.portType == .bluetoothHFP }) {
            try session.setPreferredInput(btInput)
            print("[SpeechRecognizer] Using Bluetooth HFP input")
        }
    }

    private func cleanUp() {
        recognitionRequest = nil
        recognitionTask = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
        isListening = false
    }
}
