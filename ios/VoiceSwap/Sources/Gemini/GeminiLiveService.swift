import Foundation
import UIKit

// MARK: - Connection State

enum GeminiConnectionState: Equatable {
    case disconnected
    case connecting
    case settingUp
    case ready
    case error(String)
}

// MARK: - Tool Call Models

struct GeminiToolCall {
    let id: String
    let name: String
    let args: [String: Any]
}

struct GeminiToolCallCancellation {
    let ids: [String]
}

// MARK: - Delegate

protocol GeminiLiveServiceDelegate: AnyObject {
    func geminiDidChangeState(_ state: GeminiConnectionState)
    func geminiDidReceiveAudio(_ pcmData: Data)
    func geminiDidRequestToolCall(_ toolCall: GeminiToolCall)
    func geminiDidCancelToolCalls(_ cancellation: GeminiToolCallCancellation)
    func geminiDidCompleteTurn()
    func geminiDidInterrupt()
}

// MARK: - WebSocket Delegate

private class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
    var onOpen: ((String?) -> Void)?
    var onClose: ((URLSessionWebSocketTask.CloseCode, Data?) -> Void)?
    var onError: ((Error) -> Void)?

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol proto: String?) {
        onOpen?(proto)
    }

    func urlSession(_ session: URLSession,
                    webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
                    reason: Data?) {
        onClose?(closeCode, reason)
    }

    func urlSession(_ session: URLSession,
                    task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if let error = error {
            onError?(error)
        }
    }
}

// MARK: - GeminiLiveService

@MainActor
class GeminiLiveService: ObservableObject {

    // MARK: Published

    @Published private(set) var connectionState: GeminiConnectionState = .disconnected
    @Published private(set) var isModelSpeaking: Bool = false

    // MARK: Delegate

    weak var delegate: GeminiLiveServiceDelegate?

    // MARK: Configuration

    var systemPrompt: String = ""
    var toolDeclarations: [[String: Any]] = []

    // MARK: Private

    private var webSocketTask: URLSessionWebSocketTask?
    private let wsDelegate = WebSocketDelegate()
    private var urlSession: URLSession?
    private var connectContinuation: CheckedContinuation<Bool, Never>?

    private let sendQueue = DispatchQueue(label: "com.voiceswap.gemini.send", qos: .userInitiated)

    // Session resumption
    private var sessionResumptionHandle: String?
    private(set) var isReconnecting: Bool = false

    // Keepalive ping to prevent idle timeout during pre-connect
    private var keepaliveTask: Task<Void, Never>?

    // Latency tracking
    private var lastUserSpeechEnd: Date?
    private var responseLatencyLogged = false

    // MARK: - Connect

    func connect() async -> Bool {
        guard let url = GeminiConfig.websocketURL() else {
            connectionState = .error("Gemini API key not configured")
            return false
        }

        connectionState = .connecting

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            // Resolve any leaked continuation from a previous connect() call (e.g. auto-reconnect)
            self.resolveConnect(success: false)
            self.connectContinuation = continuation

            self.wsDelegate.onOpen = { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.connectionState = .settingUp
                    self.sendSetupMessage()
                    self.startReceiving()
                }
            }

            self.wsDelegate.onClose = { [weak self] code, _ in
                guard let self else { return }
                Task { @MainActor in
                    NSLog("[Gemini] WebSocket closed: %d (state: %@, reconnecting: %d)",
                          code.rawValue, String(describing: self.connectionState), self.isReconnecting ? 1 : 0)
                    self.isModelSpeaking = false

                    // Already reconnecting via GoAway handler — skip duplicate reconnect
                    if self.isReconnecting {
                        NSLog("[Gemini] Already reconnecting — ignoring close code %d", code.rawValue)
                        self.resolveConnect(success: false)
                        return
                    }

                    // Client-initiated close (our own disconnect()) — don't reconnect
                    if code == .normalClosure || (code == .goingAway && self.connectionState == .disconnected) {
                        self.connectionState = .disconnected
                        self.delegate?.geminiDidChangeState(.disconnected)
                        self.resolveConnect(success: false)
                        return
                    }

                    // Server-initiated close while session was active — auto-reconnect
                    // Covers 1001 (Going Away), 1011 (Server Error), etc.
                    if self.connectionState == .ready || self.connectionState == .settingUp {
                        NSLog("[Gemini] Server closed connection (%d) — auto-reconnecting...", code.rawValue)
                        self.isReconnecting = true
                        self.connectionState = .connecting
                        self.delegate?.geminiDidChangeState(.connecting)
                        self.resolveConnect(success: false)

                        self.webSocketTask = nil
                        self.urlSession?.invalidateAndCancel()
                        self.urlSession = nil

                        Task {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            let success = await self.connect()
                            self.isReconnecting = false
                            if !success {
                                NSLog("[Gemini] Auto-reconnect failed")
                                self.connectionState = .disconnected
                                self.delegate?.geminiDidChangeState(.disconnected)
                            } else {
                                NSLog("[Gemini] Auto-reconnect succeeded")
                            }
                        }
                        return
                    }

                    // Otherwise just disconnect
                    self.connectionState = .disconnected
                    self.delegate?.geminiDidChangeState(.disconnected)
                    self.resolveConnect(success: false)
                }
            }

            self.wsDelegate.onError = { [weak self] error in
                guard let self else { return }
                Task { @MainActor in
                    NSLog("[Gemini] WebSocket error: %@", error.localizedDescription)
                    self.connectionState = .error(error.localizedDescription)
                    self.delegate?.geminiDidChangeState(self.connectionState)
                    self.resolveConnect(success: false)
                }
            }

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 300
            self.urlSession = URLSession(configuration: config, delegate: self.wsDelegate, delegateQueue: nil)

            self.webSocketTask = self.urlSession?.webSocketTask(with: url)
            self.webSocketTask?.resume()

            // Timeout after 15 seconds
            Task {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                await MainActor.run {
                    if self.connectContinuation != nil {
                        NSLog("[Gemini] Connection timeout")
                        self.connectionState = .error("Connection timeout")
                        self.delegate?.geminiDidChangeState(self.connectionState)
                        self.resolveConnect(success: false)
                        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                    }
                }
            }
        }

        return result
    }

    func disconnect() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        connectionState = .disconnected
        isModelSpeaking = false
        sessionResumptionHandle = nil
        isReconnecting = false
        sendErrorCount = 0
        resolveConnect(success: false)
    }

    // MARK: - Session Resumption

    private func reconnectWithResumption() async {
        guard sessionResumptionHandle != nil else { return }
        isReconnecting = true
        connectionState = .connecting
        NSLog("[Gemini] Reconnecting with session resumption...")

        // Close old connection
        keepaliveTask?.cancel()
        keepaliveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        // Brief delay before reconnecting
        try? await Task.sleep(nanoseconds: 500_000_000)

        let success = await connect()
        isReconnecting = false

        if !success {
            NSLog("[Gemini] Session resumption failed — token may have expired")
            sessionResumptionHandle = nil
            connectionState = .disconnected
            delegate?.geminiDidChangeState(.disconnected)
        } else {
            NSLog("[Gemini] Session resumed successfully")
        }
    }

    // MARK: - Send Audio

    func sendAudio(data: Data) {
        guard connectionState == .ready else { return }
        sendQueue.async { [weak self] in
            let base64 = data.base64EncodedString()
            let json: [String: Any] = [
                "realtimeInput": [
                    "audio": [
                        "mimeType": "audio/pcm;rate=16000",
                        "data": base64
                    ]
                ]
            ]
            self?.sendJSON(json)
        }
    }

    // MARK: - Send Video Frame

    func sendVideoFrame(jpegData: Data) {
        guard connectionState == .ready else { return }
        sendQueue.async { [weak self] in
            let base64 = jpegData.base64EncodedString()
            let json: [String: Any] = [
                "realtimeInput": [
                    "video": [
                        "mimeType": "image/jpeg",
                        "data": base64
                    ]
                ]
            ]
            self?.sendJSON(json)
        }
    }

    // MARK: - Send Tool Response

    func sendToolResponse(callId: String, name: String, result: [String: Any]) {
        let json: [String: Any] = [
            "toolResponse": [
                "functionResponses": [
                    [
                        "id": callId,
                        "name": name,
                        "response": result
                    ]
                ]
            ]
        ]
        sendJSON(json)
    }

    // MARK: - Send Client Content (text context injection)

    /// Inject a text message into the session as if the user said it.
    /// Used to notify Gemini of events (e.g. QR detection) during an active session.
    func sendClientContent(_ text: String) {
        let json: [String: Any] = [
            "clientContent": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [["text": text]]
                    ]
                ],
                "turnComplete": true
            ]
        ]
        sendJSON(json)
    }

    // MARK: - Private: Setup

    private func sendSetupMessage() {
        // Exactly matches the last known-working setup (commit 44c585e)
        // with improved VAD sensitivity for glasses
        var setup: [String: Any] = [
            "model": GeminiConfig.model,
            "generationConfig": [
                "responseModalities": ["AUDIO"]
            ],
            "systemInstruction": [
                "parts": [
                    ["text": systemPrompt]
                ]
            ],
            "realtimeInputConfig": [
                "automaticActivityDetection": [
                    "disabled": false,
                    "startOfSpeechSensitivity": "START_SENSITIVITY_HIGH",
                    "endOfSpeechSensitivity": "END_SENSITIVITY_HIGH",
                    "prefixPaddingMs": 20
                ] as [String: Any],
                "activityHandling": "START_OF_ACTIVITY_INTERRUPTS",
                "turnCoverage": "TURN_INCLUDES_ALL_INPUT"
            ],
            "inputAudioTranscription": [:] as [String: Any],
            "outputAudioTranscription": [:] as [String: Any]
        ]

        if !toolDeclarations.isEmpty {
            setup["tools"] = [
                ["functionDeclarations": toolDeclarations]
            ]
        }

        NSLog("[Gemini] Sending setup for model: %@", GeminiConfig.model)
        sendJSON(["setup": setup])
    }

    // MARK: - Private: Receive

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    Task { @MainActor in
                        self.handleMessage(text)
                    }
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        Task { @MainActor in
                            self.handleMessage(text)
                        }
                    }
                @unknown default:
                    break
                }
                self.startReceiving()

            case .failure(let error):
                Task { @MainActor in
                    NSLog("[Gemini] Receive error: %@", error.localizedDescription)

                    // Already disconnected — don't restart
                    guard self.connectionState != .disconnected else { return }

                    // Check if terminal (socket dead) vs transient
                    let nsError = error as NSError
                    let isTerminal = nsError.code == 57   // Socket is not connected
                        || nsError.code == 54             // Connection reset by peer
                        || nsError.code == 60             // Operation timed out

                    if isTerminal {
                        // If already reconnecting, ignore duplicate errors from dying socket
                        guard !self.isReconnecting else {
                            NSLog("[Gemini] Ignoring terminal error (code %d) — already reconnecting", nsError.code)
                            return
                        }

                        NSLog("[Gemini] Terminal error (code %d) — session lost", nsError.code)
                        if self.sessionResumptionHandle != nil {
                            Task { await self.reconnectWithResumption() }
                        } else if self.connectionState == .ready {
                            // No resumption token but session was active — fresh reconnect
                            NSLog("[Gemini] Auto-reconnecting with fresh session...")
                            self.isReconnecting = true
                            self.connectionState = .connecting
                            self.delegate?.geminiDidChangeState(.connecting)
                            self.keepaliveTask?.cancel()
                            self.keepaliveTask = nil
                            self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                            self.webSocketTask = nil
                            self.urlSession?.invalidateAndCancel()
                            self.urlSession = nil
                            Task {
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                let success = await self.connect()
                                self.isReconnecting = false
                                if success {
                                    NSLog("[Gemini] Auto-reconnect succeeded")
                                } else {
                                    NSLog("[Gemini] Auto-reconnect failed")
                                    self.connectionState = .disconnected
                                    self.delegate?.geminiDidChangeState(.disconnected)
                                }
                            }
                        } else {
                            self.connectionState = .error(error.localizedDescription)
                            self.delegate?.geminiDidChangeState(self.connectionState)
                        }
                    } else {
                        // Transient error — keep the receive loop alive
                        NSLog("[Gemini] Transient error — restarting receive loop")
                        self.startReceiving()
                    }
                }
            }
        }
    }

    // MARK: - Private: Message Parsing

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            NSLog("[Gemini] ⚠️ Message not UTF-8 decodable (length: %d)", text.count)
            return
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let preview = String(text.prefix(200))
            NSLog("[Gemini] ⚠️ Failed to parse JSON message: %@", preview)
            return
        }

        // 1. Setup complete
        if json["setupComplete"] != nil {
            connectionState = .ready
            delegate?.geminiDidChangeState(.ready)
            resolveConnect(success: true)
            startKeepalive()
            NSLog("[Gemini] Setup complete — session active")
            return
        }

        // 2. Session resumption update — save token for reconnection
        if let update = json["sessionResumptionUpdate"] as? [String: Any],
           let handle = update["handle"] as? String {
            sessionResumptionHandle = handle
            NSLog("[Gemini] Session resumption token updated")
            return
        }

        // 3. GoAway — server ending session, auto-reconnect
        if json["goAway"] != nil {
            NSLog("[Gemini] GoAway received (state: %@)", String(describing: connectionState))
            if sessionResumptionHandle != nil {
                NSLog("[Gemini] Auto-reconnecting with session resumption...")
                Task { await self.reconnectWithResumption() }
            } else if connectionState == .ready {
                // No resumption token but session was active — fresh reconnect
                NSLog("[Gemini] No resumption token — reconnecting with fresh session...")
                isReconnecting = true
                connectionState = .connecting
                delegate?.geminiDidChangeState(.connecting)

                webSocketTask?.cancel(with: .goingAway, reason: nil)
                webSocketTask = nil
                urlSession?.invalidateAndCancel()
                urlSession = nil

                Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    let success = await self.connect()
                    self.isReconnecting = false
                    if !success {
                        NSLog("[Gemini] Fresh reconnect after GoAway failed")
                        self.connectionState = .disconnected
                        self.delegate?.geminiDidChangeState(.disconnected)
                    } else {
                        NSLog("[Gemini] Fresh reconnect after GoAway succeeded")
                    }
                }
            } else {
                NSLog("[Gemini] GoAway while not active — disconnecting")
                connectionState = .disconnected
                delegate?.geminiDidChangeState(.disconnected)
            }
            return
        }

        // 4. Tool call
        if let toolCall = json["toolCall"] as? [String: Any],
           let functionCalls = toolCall["functionCalls"] as? [[String: Any]] {
            for call in functionCalls {
                guard let id = call["id"] as? String,
                      let name = call["name"] as? String else { continue }
                let args = call["args"] as? [String: Any] ?? [:]
                NSLog("[Gemini] Tool call: %@ (%@)", name, id)
                delegate?.geminiDidRequestToolCall(GeminiToolCall(id: id, name: name, args: args))
            }
            return
        }

        // 5. Tool call cancellation
        if let cancellation = json["toolCallCancellation"] as? [String: Any],
           let ids = cancellation["ids"] as? [String] {
            NSLog("[Gemini] Tool call cancelled: %@", ids.joined(separator: ", "))
            delegate?.geminiDidCancelToolCalls(GeminiToolCallCancellation(ids: ids))
            return
        }

        // 6. Server content
        if let serverContent = json["serverContent"] as? [String: Any] {

            // 5a. Interruption
            if let interrupted = serverContent["interrupted"] as? Bool, interrupted {
                isModelSpeaking = false
                delegate?.geminiDidInterrupt()
                return
            }

            // 5b. Model audio response
            if let modelTurn = serverContent["modelTurn"] as? [String: Any],
               let parts = modelTurn["parts"] as? [[String: Any]] {
                for part in parts {
                    if let inlineData = part["inlineData"] as? [String: Any],
                       let mimeType = inlineData["mimeType"] as? String,
                       mimeType.hasPrefix("audio/pcm"),
                       let base64Data = inlineData["data"] as? String,
                       let audioData = Data(base64Encoded: base64Data) {

                        // Latency tracking
                        if let speechEnd = lastUserSpeechEnd, !responseLatencyLogged {
                            let latency = Date().timeIntervalSince(speechEnd)
                            NSLog("[Gemini] Latency: %.0fms (speech end -> first audio)", latency * 1000)
                            responseLatencyLogged = true
                        }

                        if !isModelSpeaking {
                            isModelSpeaking = true
                        }
                        delegate?.geminiDidReceiveAudio(audioData)
                    }
                }
            }

            // 5c. Turn complete
            if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
                isModelSpeaking = false
                delegate?.geminiDidCompleteTurn()
            }

            // 5d. Input transcription (for latency tracking)
            if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
               let text = inputTranscription["text"] as? String, !text.isEmpty {
                lastUserSpeechEnd = Date()
                responseLatencyLogged = false
                NSLog("[Gemini] User said: %@", text)
            }

            // 5e. Output transcription
            if let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
               let text = outputTranscription["text"] as? String, !text.isEmpty {
                NSLog("[Gemini] AI said: %@", text)
            }

            return
        }

        // Log unrecognized message types
        let keys = Array(json.keys).joined(separator: ", ")
        NSLog("[Gemini] ⚠️ Unrecognized message keys: %@", keys)
    }

    // MARK: - Keepalive

    /// Restart keepalive pings (e.g. when mic is muted and no audio traffic flows).
    /// Prevents the WebSocket from timing out during idle periods like QR scanning.
    func restartKeepalive() {
        guard connectionState == .ready else { return }
        startKeepalive()
    }

    /// Stop keepalive pings (e.g. when audio streaming resumes).
    func stopKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = nil
    }

    private func startKeepalive() {
        keepaliveTask?.cancel()
        keepaliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                guard !Task.isCancelled, let self else { return }
                await MainActor.run {
                    guard self.connectionState == .ready else { return }
                    self.webSocketTask?.sendPing { [weak self] error in
                        if let error {
                            NSLog("[Gemini] Keepalive ping failed: %@", error.localizedDescription)
                            // Ping failure means connection is dead — trigger reconnect
                            Task { @MainActor in
                                guard let self, self.connectionState == .ready, !self.isReconnecting else { return }
                                NSLog("[Gemini] Keepalive detected dead connection — reconnecting...")
                                self.isReconnecting = true
                                self.connectionState = .connecting
                                self.delegate?.geminiDidChangeState(.connecting)
                                self.keepaliveTask?.cancel()
                                self.keepaliveTask = nil
                                self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                                self.webSocketTask = nil
                                self.urlSession?.invalidateAndCancel()
                                self.urlSession = nil
                                Task {
                                    try? await Task.sleep(nanoseconds: 500_000_000)
                                    let success = await self.connect()
                                    self.isReconnecting = false
                                    if success {
                                        NSLog("[Gemini] Keepalive reconnect succeeded")
                                    } else {
                                        NSLog("[Gemini] Keepalive reconnect failed")
                                        self.connectionState = .disconnected
                                        self.delegate?.geminiDidChangeState(.disconnected)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        NSLog("[Gemini] Keepalive started (15s interval)")
    }

    // MARK: - Private: Helpers

    private func resolveConnect(success: Bool) {
        if let cont = connectContinuation {
            connectContinuation = nil
            cont.resume(returning: success)
        }
    }

    private var sendErrorCount = 0

    private func sendJSON(_ json: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: json),
              let text = String(data: data, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { [weak self] error in
            if let error = error {
                NSLog("[Gemini] Send error: %@", error.localizedDescription)
                Task { @MainActor in
                    guard let self else { return }
                    self.sendErrorCount += 1
                    // 3 consecutive send errors = connection is dead
                    if self.sendErrorCount >= 3 && self.connectionState == .ready && !self.isReconnecting {
                        NSLog("[Gemini] Multiple send failures — connection dead, reconnecting...")
                        self.isReconnecting = true
                        self.connectionState = .connecting
                        self.delegate?.geminiDidChangeState(.connecting)
                        self.keepaliveTask?.cancel()
                        self.keepaliveTask = nil
                        self.webSocketTask?.cancel(with: .goingAway, reason: nil)
                        self.webSocketTask = nil
                        self.urlSession?.invalidateAndCancel()
                        self.urlSession = nil
                        self.sendErrorCount = 0
                        Task {
                            try? await Task.sleep(nanoseconds: 500_000_000)
                            let success = await self.connect()
                            self.isReconnecting = false
                            if success {
                                NSLog("[Gemini] Send-error reconnect succeeded")
                            } else {
                                NSLog("[Gemini] Send-error reconnect failed")
                                self.connectionState = .disconnected
                                self.delegate?.geminiDidChangeState(.disconnected)
                            }
                        }
                    }
                }
            } else {
                Task { @MainActor in
                    self?.sendErrorCount = 0
                }
            }
        }
    }
}
