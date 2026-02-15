import Foundation
import AVFoundation

// MARK: - Audio Mode

enum AudioMode {
    case glasses   // .videoChat — hardware AEC via Bluetooth HFP
    case phone     // .voiceChat — software AEC + echo gate
}

// MARK: - AudioManager

@MainActor
class AudioManager: ObservableObject {

    // MARK: Published

    @Published private(set) var isCapturing: Bool = false
    @Published private(set) var isPlaying: Bool = false
    @Published var audioMode: AudioMode = .phone

    // MARK: Callbacks

    var onAudioCaptured: ((Data) -> Void)?

    // MARK: Private — Capture

    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?

    // MARK: Private — Playback

    private var playerNode: AVAudioPlayerNode?
    private var playbackEngine: AVAudioEngine?
    private var pendingBufferCount: Int = 0

    // MARK: Private — Echo Gate

    var isMutedForEcho: Bool = false

    // MARK: Private — Route Change Recovery

    private var routeChangeObserver: NSObjectProtocol?

    // MARK: Private — Chunk Accumulation

    private var accumulatedData = Data()
    private let sendQueue = DispatchQueue(label: "com.voiceswap.audio.send", qos: .userInitiated)
    // 100ms at 16kHz mono Int16 = 1600 samples * 2 bytes = 3200 bytes
    private let minSendBytes = 3200

    // MARK: - Audio Session

    func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()

        let mode: AVAudioSession.Mode
        let options: AVAudioSession.CategoryOptions

        switch audioMode {
        case .glasses:
            mode = .videoChat
            options = [.allowBluetooth, .allowBluetoothA2DP]
        case .phone:
            mode = .voiceChat
            options = [.defaultToSpeaker, .allowBluetooth]
        }

        try session.setCategory(.playAndRecord, mode: mode, options: options)
        try session.setPreferredSampleRate(GeminiConfig.inputAudioSampleRate)
        try session.setPreferredIOBufferDuration(0.064)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // In glasses mode, prefer Bluetooth HFP input
        if audioMode == .glasses {
            if let btInput = session.availableInputs?.first(where: { $0.portType == .bluetoothHFP }) {
                try session.setPreferredInput(btInput)
            }
        }

        NSLog("[Audio] Session configured: mode=%@, sampleRate=%.0f",
              audioMode == .glasses ? "glasses" : "phone",
              session.sampleRate)
    }

    // MARK: - Capture

    func startCapture() throws {
        guard !isCapturing else { return }

        try configureAudioSession()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        NSLog("[Audio] Input format: %.0fHz, %d ch", inputFormat.sampleRate, inputFormat.channelCount)

        // Target format: 16kHz, mono, Float32 (we convert to Int16 manually)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: GeminiConfig.inputAudioSampleRate,
            channels: GeminiConfig.audioChannels,
            interleaved: false
        )!

        // Create converter if sample rates differ
        let needsConversion = inputFormat.sampleRate != GeminiConfig.inputAudioSampleRate
            || inputFormat.channelCount != GeminiConfig.audioChannels
        if needsConversion {
            audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }

        // Install tap on input node
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            guard !self.isMutedForEcho else { return }

            let pcmData: Data
            if let converter = self.audioConverter {
                guard let converted = self.resample(buffer: buffer, converter: converter, targetFormat: targetFormat) else { return }
                pcmData = self.floatBufferToInt16Data(converted)
            } else {
                pcmData = self.floatBufferToInt16Data(buffer)
            }

            self.sendQueue.async {
                self.accumulatedData.append(pcmData)
                if self.accumulatedData.count >= self.minSendBytes {
                    let chunk = Data(self.accumulatedData.prefix(self.minSendBytes))
                    self.accumulatedData = Data(self.accumulatedData.dropFirst(self.minSendBytes))
                    self.onAudioCaptured?(chunk)
                }
            }
        }

        // Setup playback engine
        setupPlaybackEngine()

        engine.prepare()
        try engine.start()
        self.audioEngine = engine
        isCapturing = true

        // Monitor audio route changes — Bluetooth can temporarily disconnect
        // (e.g., when Meta StreamSession stops), killing the AVAudioEngine.
        // We need to restart capture when the route comes back.
        setupRouteChangeObserver()

        NSLog("[Audio] Capture started (mode: %@)", audioMode == .glasses ? "glasses" : "phone")
    }

    func stopCapture() {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioConverter = nil
        isCapturing = false
        sendQueue.async { self.accumulatedData = Data() }
        NSLog("[Audio] Capture stopped")
    }

    // MARK: - Playback

    func playAudio(data: Data) {
        guard let playerNode = playerNode,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: GeminiConfig.outputAudioSampleRate,
                  channels: GeminiConfig.audioChannels,
                  interleaved: false
              ) else { return }

        let frameCount = UInt32(data.count) / (GeminiConfig.audioBitsPerSample / 8 * GeminiConfig.audioChannels)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount

        // Convert Int16 → Float32
        data.withUnsafeBytes { rawBuffer in
            guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress,
                  let floatData = buffer.floatChannelData else { return }
            for i in 0..<Int(frameCount) {
                floatData[0][i] = Float(int16Ptr[i]) / Float(Int16.max)
            }
        }

        pendingBufferCount += 1
        playerNode.scheduleBuffer(buffer) { [weak self] in
            Task { @MainActor in
                guard let self = self else { return }
                self.pendingBufferCount -= 1
                if self.pendingBufferCount <= 0 {
                    self.pendingBufferCount = 0
                    self.isPlaying = false
                }
            }
        }

        if !playerNode.isPlaying {
            playerNode.play()
        }
        isPlaying = true
    }

    func stopPlayback() {
        playerNode?.stop()
        pendingBufferCount = 0
        isPlaying = false
        isMutedForEcho = false

        // Restart player node so it's ready for next audio
        playerNode?.play()
    }

    // MARK: - Audio Route Recovery

    private func setupRouteChangeObserver() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification)
            }
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard isCapturing else { return }
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }

        // When a Bluetooth device disconnects and reconnects (e.g., Meta StreamSession stop/start),
        // AVAudioEngine's input tap can die silently. Check if engine is still running.
        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .routeConfigurationChange:
            guard let engine = audioEngine else { return }
            if !engine.isRunning {
                NSLog("[Audio] Engine stopped after route change (reason: %lu) — restarting capture", reasonValue)
                restartCapture()
            } else {
                NSLog("[Audio] Route changed (reason: %lu) — engine still running", reasonValue)
            }
        default:
            break
        }
    }

    /// Restart audio capture after a route change killed the engine
    private func restartCapture() {
        guard isCapturing else { return }

        // Tear down old engine
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioConverter = nil

        // Retry with increasing delays — Bluetooth route changes can take time to settle
        Task { @MainActor in
            let delays: [UInt64] = [500_000_000, 1_000_000_000, 2_000_000_000] // 0.5s, 1s, 2s

            for (attempt, delay) in delays.enumerated() {
                try? await Task.sleep(nanoseconds: delay)
                guard self.isCapturing else { return }

                do {
                    // Reset audio session to pick up new route
                    try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    try self.configureAudioSession()

                    let engine = AVAudioEngine()
                    let inputNode = engine.inputNode
                    let inputFormat = inputNode.outputFormat(forBus: 0)

                    NSLog("[Audio] Restart attempt %d: %.0fHz, %d ch", attempt + 1, inputFormat.sampleRate, inputFormat.channelCount)

                    let targetFormat = AVAudioFormat(
                        commonFormat: .pcmFormatFloat32,
                        sampleRate: GeminiConfig.inputAudioSampleRate,
                        channels: GeminiConfig.audioChannels,
                        interleaved: false
                    )!

                    let needsConversion = inputFormat.sampleRate != GeminiConfig.inputAudioSampleRate
                        || inputFormat.channelCount != GeminiConfig.audioChannels
                    if needsConversion {
                        self.audioConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
                    }

                    inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
                        guard let self = self else { return }
                        guard !self.isMutedForEcho else { return }

                        let pcmData: Data
                        if let converter = self.audioConverter {
                            guard let converted = self.resample(buffer: buffer, converter: converter, targetFormat: targetFormat) else { return }
                            pcmData = self.floatBufferToInt16Data(converted)
                        } else {
                            pcmData = self.floatBufferToInt16Data(buffer)
                        }

                        self.sendQueue.async {
                            self.accumulatedData.append(pcmData)
                            if self.accumulatedData.count >= self.minSendBytes {
                                let chunk = Data(self.accumulatedData.prefix(self.minSendBytes))
                                self.accumulatedData = Data(self.accumulatedData.dropFirst(self.minSendBytes))
                                self.onAudioCaptured?(chunk)
                            }
                        }
                    }

                    engine.prepare()
                    try engine.start()
                    self.audioEngine = engine

                    // Also restart playback engine
                    self.playbackEngine?.stop()
                    self.playbackEngine = nil
                    self.playerNode = nil
                    self.setupPlaybackEngine()

                    NSLog("[Audio] Capture restarted successfully (attempt %d)", attempt + 1)
                    return // Success — exit retry loop
                } catch {
                    NSLog("[Audio] Restart attempt %d failed: %@", attempt + 1, error.localizedDescription)
                    // Clean up failed engine before retry
                    self.audioEngine?.inputNode.removeTap(onBus: 0)
                    self.audioEngine?.stop()
                    self.audioEngine = nil
                    self.audioConverter = nil
                }
            }

            NSLog("[Audio] All restart attempts failed — audio capture stopped")
        }
    }

    // MARK: - Cleanup

    func cleanup() {
        stopCapture()
        stopPlayback()
        playbackEngine?.stop()
        playbackEngine = nil
        playerNode = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        NSLog("[Audio] Cleanup complete")
    }

    // MARK: - Private: Playback Engine Setup

    private func setupPlaybackEngine() {
        let engine = AVAudioEngine()
        let node = AVAudioPlayerNode()

        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: GeminiConfig.outputAudioSampleRate,
            channels: GeminiConfig.audioChannels,
            interleaved: false
        )!

        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)

        do {
            engine.prepare()
            try engine.start()
            self.playbackEngine = engine
            self.playerNode = node
        } catch {
            NSLog("[Audio] Playback engine error: %@", error.localizedDescription)
        }
    }

    // MARK: - Private: Conversion Helpers

    private func resample(buffer: AVAudioPCMBuffer,
                          converter: AVAudioConverter,
                          targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let outputFrameCount = UInt32(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
            return nil
        }

        var error: NSError?
        var isDone = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if isDone {
                outStatus.pointee = .noDataNow
                return nil
            }
            isDone = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error = error {
            NSLog("[Audio] Resample error: %@", error.localizedDescription)
            return nil
        }

        return outputBuffer
    }

    private func floatBufferToInt16Data(_ buffer: AVAudioPCMBuffer) -> Data {
        guard let floatData = buffer.floatChannelData else { return Data() }
        let frameCount = Int(buffer.frameLength)
        var int16Data = Data(count: frameCount * 2) // 2 bytes per Int16

        int16Data.withUnsafeMutableBytes { rawPtr in
            guard let int16Ptr = rawPtr.bindMemory(to: Int16.self).baseAddress else { return }
            for i in 0..<frameCount {
                let sample = max(-1.0, min(1.0, floatData[0][i]))
                int16Ptr[i] = Int16(sample * 32767.0)
            }
        }

        return int16Data
    }
}
