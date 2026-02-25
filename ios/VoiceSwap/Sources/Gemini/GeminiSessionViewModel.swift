import Foundation
import Combine
import UIKit
import AVFoundation

// MARK: - Tool Declarations

private enum VoiceSwapTools {

    static func allDeclarations() -> [[String: Any]] {
        // BetWhisper mode: prediction market tools only (no payment/QR tools)
        [searchMarkets, detectAgents, explainMarket, placeBet, confirmBet]
    }

    static let scanQR: [String: Any] = [
        "name": "scan_qr",
        "description": "Start scanning for a payment QR code using the glasses camera. The camera will automatically detect QR codes and parse payment information.",
        "parameters": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ] as [String: Any]
    ]

    static let preparePayment: [String: Any] = [
        "name": "prepare_payment",
        "description": "Prepare a USDC payment to a merchant. This checks balances and readies the transaction. Call this after you have the merchant wallet address and amount.",
        "parameters": [
            "type": "object",
            "properties": [
                "merchant_wallet": [
                    "type": "string",
                    "description": "The Ethereum wallet address (0x...) or ENS name of the recipient"
                ] as [String: Any],
                "amount": [
                    "type": "string",
                    "description": "The amount in USDC to pay (e.g., '10.50')"
                ] as [String: Any],
                "merchant_name": [
                    "type": "string",
                    "description": "Optional human-readable name of the merchant"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["merchant_wallet", "amount"]
        ] as [String: Any]
    ]

    static let confirmPayment: [String: Any] = [
        "name": "confirm_payment",
        "description": "Execute the previously prepared payment. Only call this after the user has explicitly confirmed they want to pay.",
        "parameters": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ] as [String: Any]
    ]

    static let cancelPayment: [String: Any] = [
        "name": "cancel_payment",
        "description": "Cancel the current payment flow and return to idle state.",
        "parameters": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ] as [String: Any]
    ]

    static let setPaymentAmount: [String: Any] = [
        "name": "set_payment_amount",
        "description": "Set the payment amount. The payment is auto-prepared after this. If result is ready_to_confirm, ask the user to confirm.",
        "parameters": [
            "type": "object",
            "properties": [
                "amount": [
                    "type": "string",
                    "description": "The amount in USDC (e.g., '25.00')"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["amount"]
        ] as [String: Any]
    ]

    // MARK: - BetWhisper Prediction Tools

    static let searchMarkets: [String: Any] = [
        "name": "search_markets",
        "description": "Search prediction markets by keyword. Returns top markets with current odds. Use when user asks about odds, bets, or prediction markets.",
        "parameters": [
            "type": "object",
            "properties": [
                "query": [
                    "type": "string",
                    "description": "Search query (e.g., 'Chiefs', 'Bitcoin', 'Lakers', 'trending')"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["query"]
        ] as [String: Any]
    ]

    static let detectAgents: [String: Any] = [
        "name": "detect_agents",
        "description": "Run Agent Radar on a prediction market. Scans top holders for bot behavior using 7 signals, classifies strategies (Market Maker, Sniper, Momentum), and detects smart money direction. Returns agent rate, capital flow, and recommendation.",
        "parameters": [
            "type": "object",
            "properties": [
                "condition_id": [
                    "type": "string",
                    "description": "The conditionId of the market to analyze (from search_markets result)"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["condition_id"]
        ] as [String: Any]
    ]

    static let explainMarket: [String: Any] = [
        "name": "explain_market",
        "description": "Get an AI explanation of the Agent Radar analysis in simple terms. Call after detect_agents. Returns a plain language summary of what the bots are doing and whether smart money agrees.",
        "parameters": [
            "type": "object",
            "properties": [
                "condition_id": [
                    "type": "string",
                    "description": "The conditionId of the market (same as detect_agents)"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["condition_id"]
        ] as [String: Any]
    ]

    static let placeBet: [String: Any] = [
        "name": "place_bet",
        "description": "Prepare a bet on a prediction market. Does NOT execute yet — returns details for user confirmation. You MUST ask the user to confirm before calling confirm_bet.",
        "parameters": [
            "type": "object",
            "properties": [
                "market_slug": [
                    "type": "string",
                    "description": "The slug of the market to bet on (from search_markets result)"
                ] as [String: Any],
                "side": [
                    "type": "string",
                    "description": "The side to bet on: 'Yes' or 'No'"
                ] as [String: Any],
                "amount": [
                    "type": "string",
                    "description": "Amount in USD to bet (e.g., '1')"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["market_slug", "side", "amount"]
        ] as [String: Any]
    ]

    static let confirmBet: [String: Any] = [
        "name": "confirm_bet",
        "description": "Execute the previously prepared bet AFTER the user has explicitly confirmed. Only call this when the user says 'yes', 'confirm', 'do it', 'dale', or similar explicit confirmation.",
        "parameters": [
            "type": "object",
            "properties": [:] as [String: Any],
            "required": [] as [String]
        ] as [String: Any]
    ]

}

// MARK: - Transcript Event

struct TranscriptEvent: Equatable {
    let id = UUID()
    let role: String   // "user" or "assistant"
    let text: String

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

// MARK: - Pending Bet (confirmation gate)

struct PendingBet {
    let marketSlug: String
    let side: String
    let amountUSD: Double
    let conditionId: String
    let monPriceUSD: Double
    let monAmount: Double
    let createdAt: Date = Date()

    var isExpired: Bool { Date().timeIntervalSince(createdAt) > 90 }
}

// MARK: - Bet Result Event (for chat display)

struct BetResultEvent: Equatable {
    let id = UUID()
    let market: String
    let side: String
    let amountUSD: String
    let txHash: String
    let monadTxHash: String
    let success: Bool

    var explorerURL: URL? {
        guard !monadTxHash.isEmpty else { return nil }
        return URL(string: "https://testnet.monadexplorer.com/tx/\(monadTxHash)")
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

// MARK: - GeminiSessionViewModel

@MainActor
class GeminiSessionViewModel: ObservableObject {

    // MARK: Published

    @Published private(set) var isSessionActive: Bool = false
    @Published private(set) var isListening: Bool = false
    @Published private(set) var isAISpeaking: Bool = false
    @Published private(set) var sessionError: String?

    /// Fires when a complete transcript is ready (debounced from incremental chunks)
    @Published private(set) var latestTranscript: TranscriptEvent?

    /// Fires when a bet is executed (for chat display)
    @Published private(set) var latestBetResult: BetResultEvent?

    /// True when user explicitly started voice session (vs just pre-connected)
    private var userStartedSession: Bool = false

    // MARK: Transcript Accumulation

    private var userTranscriptBuffer: String = ""
    private var assistantTranscriptBuffer: String = ""
    private var userTranscriptDebounce: Task<Void, Never>?
    private var assistantTranscriptDebounce: Task<Void, Never>?

    // MARK: Services

    let geminiService = GeminiLiveService()
    let audioManager = AudioManager()

    // MARK: References

    weak var paymentViewModel: VoiceSwapViewModel?

    // MARK: In-flight Tool Calls

    private var inFlightTasks: [String: Task<Void, Never>] = [:]

    // MARK: scan_qr dedup

    private var scanQRTask: Task<Void, Never>?

    // MARK: Voice payment context (survives UI cancel/reset)

    private var voiceMerchantWallet: String?
    private var voiceMerchantName: String?
    private var voiceAmount: String?

    // MARK: Prediction market context (for explain_market tool)

    private var lastDeepAnalysis: DeepAnalysisResult?
    private var lastAnalyzedConditionId: String?
    var lastSearchedMarkets: [MarketItem]?

    // MARK: Bet confirmation gate

    private var pendingBet: PendingBet?

    // MARK: MON price cache

    private var cachedMonPrice: Double?
    private var cachedMonPriceTime: Date = .distantPast

    // MARK: QR Response Fallback

    private var qrResponseFallbackTask: Task<Void, Never>?
    private var fallbackSynthesizer: AVSpeechSynthesizer?

    // MARK: Video Frame Throttle (glasses camera → Gemini)

    private var lastVideoFrameTime: Date = .distantPast
    private var videoFrameCount: Int = 0
    /// After initial context captured, pause video — only send when user speaks
    private var videoSlowMode: Bool = false
    /// When true, next camera frame will be sent (triggered by user speech)
    private var videoFrameRequested: Bool = false

    // MARK: Error Management

    private var errorDismissTask: Task<Void, Never>?

    // MARK: Cancellables

    private var cancellables = Set<AnyCancellable>()

    // MARK: Init

    init() {
        geminiService.delegate = self
        audioManager.onAudioCaptured = { [weak self] data in
            guard let self = self else { return }
            // Phone mode echo gate: mute mic while AI speaks
            if self.audioManager.audioMode == .phone && self.geminiService.isModelSpeaking {
                return
            }
            self.geminiService.sendAudio(data: data)
        }

        // Sync speaking state
        geminiService.$isModelSpeaking
            .receive(on: DispatchQueue.main)
            .assign(to: &$isAISpeaking)
    }

    // MARK: - Video Frames (glasses camera → Gemini vision)

    /// Called by MetaGlassesManager.onVideoFrame for every camera frame.
    /// Phase 1 (first 10 frames): 1fps for initial context capture.
    /// Phase 2 (slow mode): paused entirely, only sends 1 frame when user starts speaking.
    func handleVideoFrame(_ image: UIImage) {
        guard isSessionActive, geminiService.connectionState == .ready else { return }

        // Pause video while AI is speaking
        guard !geminiService.isModelSpeaking else { return }

        if videoSlowMode {
            // In slow mode: only send a fresh frame when user starts talking.
            // This avoids flooding WebSocket while user is silent/thinking.
            // The flag is set by geminiDidReceiveTranscript (user role).
            guard videoFrameRequested else { return }
            videoFrameRequested = false
        }

        // Throttle to max 1fps
        let now = Date()
        guard now.timeIntervalSince(lastVideoFrameTime) >= 1.0 else { return }
        lastVideoFrameTime = now

        guard let jpegData = image.jpegData(compressionQuality: 0.5) else { return }
        geminiService.sendVideoFrame(jpegData: jpegData)

        videoFrameCount += 1
        if videoFrameCount >= 10 && !videoSlowMode {
            videoSlowMode = true
            NSLog("[GeminiSession] Video slow mode: frames only on user speech (initial context captured)")
        }
    }

    /// Request one video frame when the user starts speaking (for visual context with their next query)
    func requestVideoFrame() {
        videoFrameRequested = true
    }

    // MARK: - Session Lifecycle

    /// Pre-establish WebSocket so voice activation is instant.
    /// Called when wallet connects or view appears. Does NOT start audio.
    func preconnect() {
        guard GeminiConfig.isConfigured else { return }
        guard !isSessionActive else { return }
        guard geminiService.connectionState == .disconnected else { return }

        NSLog("[GeminiSession] Pre-connecting to Gemini...")

        // BetWhisper: use VoiceSwapWallet directly (no paymentViewModel dependency)
        let walletAddr = VoiceSwapWallet.shared.isCreated ? VoiceSwapWallet.shared.address : paymentViewModel?.walletAddress
        let walletBal = paymentViewModel?.walletBalance
        geminiService.systemPrompt = VoiceSwapSystemPrompt.build(
            walletAddress: walletAddr,
            balance: walletBal
        )
        geminiService.toolDeclarations = VoiceSwapTools.allDeclarations()

        Task {
            let connected = await geminiService.connect()
            if connected {
                NSLog("[GeminiSession] Pre-connect succeeded — awaiting user tap for audio")
            } else {
                NSLog("[GeminiSession] Pre-connect failed (will retry on button tap)")
            }
        }
    }

    func startSession(audioMode: AudioMode) {
        guard GeminiConfig.isConfigured else {
            sessionError = "Gemini API key not configured"
            return
        }

        sessionError = nil
        audioManager.audioMode = audioMode
        userStartedSession = true
        videoFrameCount = 0
        videoSlowMode = false

        // If already pre-connected, just start audio capture instantly
        if geminiService.connectionState == .ready {
            NSLog("[GeminiSession] Already connected — starting audio immediately")
            isSessionActive = true
            do {
                try audioManager.startCapture()
                isListening = true
            } catch {
                sessionError = "Microphone error: \(error.localizedDescription)"
            }
            return
        }

        // Full connect flow — BetWhisper: use VoiceSwapWallet directly
        let walletAddr = VoiceSwapWallet.shared.isCreated ? VoiceSwapWallet.shared.address : paymentViewModel?.walletAddress
        let walletBal = paymentViewModel?.walletBalance
        geminiService.systemPrompt = VoiceSwapSystemPrompt.build(
            walletAddress: walletAddr,
            balance: walletBal
        )
        geminiService.toolDeclarations = VoiceSwapTools.allDeclarations()

        Task {
            let connected = await geminiService.connect()
            if !connected {
                sessionError = "Failed to connect to Gemini"
            }
        }
    }

    func stopSession() {
        NSLog("[GeminiSession] stopSession() called — active: %d, listening: %d",
              isSessionActive ? 1 : 0, isListening ? 1 : 0)

        // Cancel all in-flight tool calls
        for (_, task) in inFlightTasks {
            task.cancel()
        }
        inFlightTasks.removeAll()
        scanQRTask?.cancel()
        scanQRTask = nil
        errorDismissTask?.cancel()
        qrResponseFallbackTask?.cancel()
        qrResponseFallbackTask = nil
        fallbackSynthesizer?.stopSpeaking(at: .immediate)
        fallbackSynthesizer = nil

        // Clear voice payment context
        voiceMerchantWallet = nil
        voiceMerchantName = nil
        voiceAmount = nil

        // Clear transcript buffers
        userTranscriptDebounce?.cancel()
        assistantTranscriptDebounce?.cancel()
        userTranscriptBuffer = ""
        assistantTranscriptBuffer = ""

        // Clear pending bet
        pendingBet = nil

        audioManager.cleanup()
        geminiService.disconnect()
        isSessionActive = false
        isListening = false
        userStartedSession = false
    }

    /// Clear the error banner (called from UI auto-dismiss or recovery)
    func clearError() {
        sessionError = nil
    }

    /// Auto-dismiss transient errors after 5 seconds if session is still alive
    private func scheduleErrorDismiss() {
        errorDismissTask?.cancel()
        errorDismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            if self.sessionError != nil && self.isSessionActive {
                NSLog("[GeminiSession] Auto-dismissing transient error")
                self.sessionError = nil
            }
        }
    }

    // MARK: - QR Notification to Gemini

    func notifyQRDetected(merchantWallet: String, merchantName: String?, amount: String?) {
        guard isSessionActive else { return }

        // Cancel any pending scan_qr polling task
        scanQRTask?.cancel()
        scanQRTask = nil

        // Save voice payment context (survives UI cancel/reset)
        voiceMerchantWallet = merchantWallet
        voiceMerchantName = merchantName
        voiceAmount = amount

        // Mute audio input so Gemini processes this text immediately
        // (audio stream competes with clientContent — muting gives it priority)
        audioManager.isMutedForEcho = true

        // Ultra-short message for fast processing
        let context: String
        if let amount = amount {
            // QR has amount — auto-prepare payment and tell Gemini to confirm
            if let vm = paymentViewModel {
                vm.currentMerchantWallet = merchantWallet
                vm.currentMerchantName = merchantName
                vm.currentAmount = amount
                Task {
                    await vm.preparePayment()
                }
            }
            context = "QR scanned. Wallet: \(merchantWallet). Amount: \(amount) USDC. Say: Pay \(amount) dollars. Confirm?"
        } else {
            context = "QR scanned. Wallet: \(merchantWallet). Ask how much."
        }

        NSLog("[GeminiSession] Notifying Gemini of QR detection: %@", merchantWallet)
        geminiService.sendClientContent(context)

        // Unmute after brief delay to let Gemini process the text turn
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            self.audioManager.isMutedForEcho = false
        }

        // Fallback: if Gemini doesn't respond within 2s, speak "How much?" locally
        // This guarantees the user hears a prompt even if Gemini is slow
        if amount == nil {
            qrResponseFallbackTask?.cancel()
            qrResponseFallbackTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
                guard !Task.isCancelled else { return }
                // If Gemini hasn't started speaking yet, use local TTS
                if !self.isAISpeaking {
                    let lang = Locale.current.language.languageCode?.identifier ?? "en"
                    let prompt = lang == "es" ? "¿Cuánto?" : "How much?"
                    NSLog("[GeminiSession] Gemini slow — speaking '%@' locally", prompt)
                    let utterance = AVSpeechUtterance(string: prompt)
                    utterance.rate = 0.55 // slightly faster than default (0.5)
                    utterance.voice = AVSpeechSynthesisVoice(language: lang == "es" ? "es-MX" : "en-US")
                    let synthesizer = AVSpeechSynthesizer()
                    synthesizer.speak(utterance)
                    // Keep reference so ARC doesn't deallocate mid-speech
                    self.fallbackSynthesizer = synthesizer
                }
            }
        }
    }

    // MARK: - Private: Tool Call Dispatch

    private func handleToolCall(_ toolCall: GeminiToolCall) {
        // Payment tools require paymentViewModel; prediction tools do not
        let paymentTools = ["scan_qr", "prepare_payment", "confirm_payment", "cancel_payment", "set_payment_amount"]
        let vm = paymentViewModel
        if paymentTools.contains(toolCall.name) && vm == nil {
            geminiService.sendToolResponse(
                callId: toolCall.id,
                name: toolCall.name,
                result: ["error": "Payment system not available in BetWhisper mode"]
            )
            return
        }

        // scan_qr is handled separately — respond immediately, then start camera async
        // This prevents Gemini from cancelling the tool call while the camera is starting
        if toolCall.name == "scan_qr", let vm = vm {
            // GUARD: If we already have a merchant wallet from a previous scan, don't scan again.
            // This is the main fix for Gemini calling scan_qr 25+ times after QR was detected.
            if vm.currentMerchantWallet != nil {
                NSLog("[Gemini] scan_qr ignored — merchant already set: %@", vm.currentMerchantWallet ?? "")
                geminiService.sendToolResponse(callId: toolCall.id, name: toolCall.name, result: [
                    "status": "already_scanned",
                    "merchant_wallet": vm.currentMerchantWallet ?? ""
                ])
                return
            }

            // GUARD: Don't re-scan if flow is past idle/listening/scanningQR
            switch vm.flowState {
            case .idle, .listening, .cancelled, .failed:
                break // OK to scan
            case .scanningQR:
                // Already scanning — don't start another
                NSLog("[Gemini] scan_qr ignored — already scanning")
                geminiService.sendToolResponse(callId: toolCall.id, name: toolCall.name, result: ["status": "scanning", "message": "Already scanning for QR code."])
                return
            default:
                // Any other state (processing, enteringAmount, awaitingConfirmation, executing, etc.)
                NSLog("[Gemini] scan_qr ignored — flow in state: %@", "\(vm.flowState)")
                geminiService.sendToolResponse(callId: toolCall.id, name: toolCall.name, result: ["status": "already_scanned", "message": "Payment flow already in progress."])
                return
            }

            // GUARD: Don't start if camera already streaming
            if vm.glassesManager.isStreaming {
                NSLog("[Gemini] scan_qr ignored — camera already streaming")
                geminiService.sendToolResponse(callId: toolCall.id, name: toolCall.name, result: ["status": "scanning", "message": "Already scanning for QR"])
                return
            }

            // Cancel any previous scan_qr task (prevents multiple 10s polling loops)
            scanQRTask?.cancel()

            // Mute mic during scanning — no user input needed, reduces noise for Gemini
            audioManager.isMutedForEcho = true
            // Restart keepalive since no audio will flow during muted scanning
            geminiService.restartKeepalive()
            NSLog("[GeminiSession] Mic muted for QR scanning (keepalive active)")

            // Respond immediately so Gemini doesn't cancel
            vm.flowState = .scanningQR
            vm.glassesManager.triggerHaptic(.short)
            geminiService.sendToolResponse(callId: toolCall.id, name: toolCall.name, result: ["status": "scanning", "message": "Camera activated. WAIT for QR result — do NOT say Done yet. You will receive a separate message with the QR data."])

            // Start camera — glasses can take 5-8s to begin streaming
            scanQRTask = Task { @MainActor in
                NSLog("[Gemini] scan_qr: starting camera stream...")
                await vm.glassesManager.startCameraStream()

                // Poll for camera start with 10s total timeout
                var elapsed: UInt64 = 0
                let pollInterval: UInt64 = 500_000_000 // 0.5s
                let timeout: UInt64 = 10_000_000_000   // 10s

                while elapsed < timeout && !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: pollInterval)
                    elapsed += pollInterval

                    if vm.glassesManager.isStreaming {
                        NSLog("[Gemini] scan_qr: camera streaming after %.1fs", Double(elapsed) / 1_000_000_000)
                        return
                    }
                    // Flow moved past scanning — QR detected while waiting
                    if case .scanningQR = vm.flowState {} else {
                        NSLog("[Gemini] scan_qr: flow advanced — camera check done")
                        return
                    }
                    // Merchant set by QR callback while we were polling
                    if vm.currentMerchantWallet != nil {
                        NSLog("[Gemini] scan_qr: QR detected during poll — done")
                        return
                    }
                }

                guard !Task.isCancelled else { return }

                // Timeout — camera didn't start in 10s
                if case .scanningQR = vm.flowState, !vm.glassesManager.isStreaming {
                    NSLog("[Gemini] scan_qr: camera failed to start after 10s — notifying Gemini")
                    self.geminiService.sendToolResponse(
                        callId: "camera_error",
                        name: "system",
                        result: [
                            "event": "camera_error",
                            "message": "Camera failed to start. Tell the user to use the phone camera instead, or enter the wallet address manually."
                        ]
                    )
                }
            }
            return
        }

        let task = Task { @MainActor in
            let result: [String: Any]

            // Timeout wrapper — 30s max for any tool call
            let toolStart = Date()

            switch toolCall.name {
            case "prepare_payment":
                guard let vm = self.paymentViewModel else { result = ["error": "No payment VM"]; break }
                let wallet = toolCall.args["merchant_wallet"] as? String ?? ""
                let amount = toolCall.args["amount"] as? String ?? ""
                let merchantName = toolCall.args["merchant_name"] as? String

                // Save voice context (survives UI cancel)
                self.voiceMerchantWallet = wallet
                self.voiceMerchantName = merchantName
                self.voiceAmount = amount

                vm.currentMerchantWallet = wallet
                vm.currentMerchantName = merchantName
                vm.currentAmount = amount
                await vm.preparePayment()

                if case .awaitingConfirmation = vm.flowState {
                    var readyResult: [String: Any] = [
                        "status": "ready",
                        "amount": amount,
                        "merchant": merchantName ?? String(wallet.prefix(10))
                    ]
                    if !vm.securitySettings.isMerchantApproved(wallet) {
                        readyResult["merchant_warning"] = "New merchant"
                    }
                    result = readyResult
                } else if case .failed(let error) = vm.flowState {
                    result = ["status": "failed", "error": error]
                } else {
                    result = ["status": "processing"]
                }

            case "confirm_payment":
                guard let vm = self.paymentViewModel else { result = ["error": "No payment VM"]; break }
                // Mute mic during transaction execution — no user input needed
                self.audioManager.isMutedForEcho = true
                self.geminiService.restartKeepalive()
                NSLog("[GeminiSession] Mic muted for payment execution (keepalive active)")

                // In voice mode, flowState can get reset by UI interactions or timing.
                // We maintain a separate voice context that survives UI cancels.
                if case .awaitingConfirmation = vm.flowState {
                    // Good — proceed normally
                } else {
                    // Restore payment context from voice state if UI cleared it
                    let wallet = vm.currentMerchantWallet ?? self.voiceMerchantWallet
                    let amount = vm.currentAmount ?? self.voiceAmount
                    if let wallet = wallet, let amount = amount {
                        NSLog("[Gemini] confirm_payment: recovering — re-preparing (flowState was: %@)", "\(vm.flowState)")
                        vm.currentMerchantWallet = wallet
                        vm.currentMerchantName = vm.currentMerchantName ?? self.voiceMerchantName
                        vm.currentAmount = amount
                        await vm.preparePayment()
                        guard case .awaitingConfirmation = vm.flowState else {
                            NSLog("[Gemini] confirm_payment: re-prepare failed (flowState: %@)", "\(vm.flowState)")
                            result = ["status": "error", "error": "Payment preparation failed. Try again."]
                            break
                        }
                    } else {
                        NSLog("[Gemini] confirm_payment rejected — no payment context (current: %@)", "\(vm.flowState)")
                        result = [
                            "status": "error",
                            "error": "No payment prepared. Call prepare_payment first."
                        ]
                        break
                    }
                }

                await vm.confirmPayment()

                // Unmute after transaction completes — back to conversation
                self.audioManager.isMutedForEcho = false
                NSLog("[GeminiSession] Mic unmuted after payment execution")

                if case .success(let txHash) = vm.flowState {
                    // Clear voice context on success
                    self.voiceMerchantWallet = nil
                    self.voiceMerchantName = nil
                    self.voiceAmount = nil
                    result = ["status": "success", "tx_hash": txHash]
                } else if case .failed(let error) = vm.flowState {
                    result = ["status": "failed", "error": error]
                } else if case .cancelled = vm.flowState {
                    result = ["status": "cancelled", "message": "User rejected the transaction"]
                } else {
                    result = ["status": "pending"]
                }

            case "cancel_payment":
                guard let vm = self.paymentViewModel else { result = ["error": "No payment VM"]; break }
                vm.cancelPayment()
                // Clear voice context when Gemini explicitly cancels
                self.voiceMerchantWallet = nil
                self.voiceMerchantName = nil
                self.voiceAmount = nil
                self.audioManager.isMutedForEcho = false
                result = ["status": "cancelled"]

            case "set_payment_amount":
                guard let vm = self.paymentViewModel else { result = ["error": "No payment VM"]; break }
                let amount = toolCall.args["amount"] as? String ?? ""
                self.voiceAmount = amount

                // Mute mic during payment preparation — no user input needed
                self.audioManager.isMutedForEcho = true
                self.geminiService.restartKeepalive()
                NSLog("[GeminiSession] Mic muted for payment preparation (keepalive active)")

                // Ensure merchant wallet is set before calling setPaymentAmount
                // (setPaymentAmount already calls preparePayment internally — no need to call it again)
                if let wallet = vm.currentMerchantWallet ?? self.voiceMerchantWallet {
                    vm.currentMerchantWallet = wallet
                    vm.currentMerchantName = vm.currentMerchantName ?? self.voiceMerchantName
                }

                await vm.setPaymentAmount(amount)

                if case .awaitingConfirmation = vm.flowState {
                    // Unmute — Gemini needs to hear nothing, just call confirm_payment next
                    self.audioManager.isMutedForEcho = false
                    NSLog("[GeminiSession] Payment prepared — awaiting confirm_payment call")

                    let wallet = vm.currentMerchantWallet ?? self.voiceMerchantWallet ?? ""
                    result = [
                        "status": "ready_to_confirm",
                        "amount": amount,
                        "merchant": vm.currentMerchantName ?? String(wallet.prefix(10))
                    ]
                } else if case .failed(let error) = vm.flowState {
                    self.audioManager.isMutedForEcho = false
                    result = ["status": "failed", "error": error]
                } else {
                    self.audioManager.isMutedForEcho = false
                    result = ["status": "amount_set", "amount": amount]
                }

            // MARK: BetWhisper Prediction Tools

            case "search_markets":
                let query = toolCall.args["query"] as? String ?? ""
                do {
                    let response = try await VoiceSwapAPIClient.shared.searchMarkets(query: query)
                    var marketsResult: [[String: Any]] = []
                    var storedMarkets: [MarketItem] = []
                    for event in response.events.prefix(3) {
                        if let market = event.markets?.first {
                            marketsResult.append([
                                "question": market.question,
                                "conditionId": market.conditionId,
                                "slug": market.slug,
                                "yesPrice": market.yesPrice ?? 0,
                                "noPrice": market.noPrice ?? 0,
                                "volume": market.volume ?? 0,
                            ])
                            storedMarkets.append(market)
                        }
                    }
                    self.lastSearchedMarkets = storedMarkets
                    result = ["status": "ok", "markets": marketsResult, "count": marketsResult.count]
                } catch {
                    result = ["status": "error", "error": error.localizedDescription]
                }

            case "detect_agents":
                var conditionId = toolCall.args["condition_id"] as? String ?? ""

                // Fallback: if no conditionId, use first search result
                if conditionId.isEmpty, let firstMarket = self.lastSearchedMarkets?.first {
                    conditionId = firstMarket.conditionId
                    NSLog("[Gemini] detect_agents: using first search result conditionId=%@", conditionId)
                }

                if conditionId.isEmpty {
                    result = ["status": "error", "error": "No market selected. Say 'search' first to find markets."]
                    break
                }

                do {
                    let analysis = try await VoiceSwapAPIClient.shared.deepAnalyzeMarket(conditionId: conditionId)
                    // Store for explain_market to use
                    self.lastDeepAnalysis = analysis
                    self.lastAnalyzedConditionId = conditionId

                    var topSummary: [[String: Any]] = []
                    for h in analysis.topHolders.prefix(5) {
                        topSummary.append([
                            "pseudonym": h.pseudonym,
                            "side": h.side,
                            "size": h.positionSize,
                            "classification": h.classification,
                            "strategy": h.strategy.label,
                        ])
                    }
                    result = [
                        "status": "ok",
                        "agent_rate": analysis.agentRate,
                        "smart_money_direction": analysis.smartMoneyDirection,
                        "smart_money_pct": analysis.smartMoneyPct,
                        "total_holders": analysis.totalHolders,
                        "holders_scanned": analysis.holdersScanned,
                        "red_flags": analysis.redFlags,
                        "recommendation": analysis.recommendation,
                        "top_holders": topSummary,
                        "signal_hash": analysis.signalHash,
                    ]
                } catch {
                    result = ["status": "error", "error": error.localizedDescription]
                }

            case "explain_market":
                // Uses stored analysis from detect_agents
                guard let analysis = self.lastDeepAnalysis else {
                    result = ["status": "error", "error": "Run detect_agents first."]
                    break
                }
                // Find the market from the last search
                let conditionId = toolCall.args["condition_id"] as? String ?? self.lastAnalyzedConditionId ?? ""
                let market = self.lastSearchedMarkets?.first(where: { $0.conditionId == conditionId })
                    ?? MarketItem(conditionId: conditionId, question: "", slug: "", volume: nil, yesPrice: nil, noPrice: nil, image: nil, endDate: nil)
                let lang = Locale.current.language.languageCode?.identifier ?? "en"
                do {
                    let lines = try await VoiceSwapAPIClient.shared.explainMarket(analysis: analysis, market: market, language: lang)
                    result = [
                        "status": "ok",
                        "explanation": lines.joined(separator: " "),
                        "lines": lines,
                    ]
                } catch {
                    result = ["status": "error", "error": error.localizedDescription]
                }

            case "place_bet":
                // Phase 1: PREPARE the bet, do NOT execute. Store details and ask for confirmation.
                var marketSlug = toolCall.args["market_slug"] as? String ?? ""
                let side = toolCall.args["side"] as? String ?? "Yes"
                let amount = toolCall.args["amount"] as? String ?? "1"
                var conditionId = toolCall.args["condition_id"] as? String ?? self.lastAnalyzedConditionId ?? ""

                // Fallback: if no conditionId but we have search results, use the first one
                if conditionId.isEmpty, let firstMarket = self.lastSearchedMarkets?.first {
                    conditionId = firstMarket.conditionId
                    if marketSlug.isEmpty { marketSlug = firstMarket.slug }
                    NSLog("[Gemini] place_bet: using first search result conditionId=%@", conditionId)
                }

                if conditionId.isEmpty {
                    result = ["status": "error", "error": "No market selected. Say 'search' first to find markets."]
                    break
                }

                let amountUSD = Double(amount) ?? 1.0
                let monPriceUSD = await self.fetchMonPrice()

                let monAmount = (amountUSD / monPriceUSD) * 1.01

                // Store pending bet for confirm_bet
                self.pendingBet = PendingBet(
                    marketSlug: marketSlug,
                    side: side,
                    amountUSD: amountUSD,
                    conditionId: conditionId,
                    monPriceUSD: monPriceUSD,
                    monAmount: monAmount
                )

                NSLog("[Gemini] place_bet: prepared pending bet — $%.2f on %@ for %@, ~%.2f MON", amountUSD, side, marketSlug, monAmount)

                result = [
                    "status": "awaiting_confirmation",
                    "market": marketSlug,
                    "side": side,
                    "amount_usd": amountUSD,
                    "estimated_mon": String(format: "%.2f", monAmount),
                    "mon_price_usd": monPriceUSD,
                    "message": "Ask the user to confirm: $\(amount) on \(side) for \(marketSlug) (~\(String(format: "%.2f", monAmount)) MON). Call confirm_bet ONLY after they say yes."
                ]

            case "confirm_bet":
                // Phase 2: Execute the pending bet AFTER user confirmed
                guard let bet = self.pendingBet else {
                    result = ["status": "error", "error": "No pending bet. Call place_bet first to prepare a bet."]
                    break
                }
                if bet.isExpired {
                    self.pendingBet = nil
                    NSLog("[Gemini] confirm_bet: pending bet expired (>90s)")
                    result = ["status": "error", "error": "Bet expired. MON price may have changed. Call place_bet again to get fresh pricing."]
                    break
                }
                self.pendingBet = nil

                // Mute mic during execution
                self.audioManager.isMutedForEcho = true
                NSLog("[Gemini] confirm_bet: executing $%.2f on %@ for %@", bet.amountUSD, bet.side, bet.marketSlug)

                // Convert MON to wei hex
                let wholeMON = UInt64(bet.monAmount)
                let fracMON = bet.monAmount - Double(wholeMON)
                let wholeWei = wholeMON.multipliedReportingOverflow(by: 1_000_000_000_000_000_000)
                let fracWei = UInt64(fracMON * 1e18)
                let valueHex: String
                if wholeWei.overflow {
                    let weiDecimal = Decimal(bet.monAmount) * Decimal(sign: .plus, exponent: 18, significand: 1)
                    let weiString = NSDecimalNumber(decimal: weiDecimal).stringValue
                    valueHex = "0x" + Self.decimalStringToHex(weiString)
                } else {
                    let totalWei = wholeWei.partialValue &+ fracWei
                    valueHex = "0x" + String(totalWei, radix: 16)
                }

                // Step 1: On-chain transaction
                let depositAddress = "0x530aBd0674982BAf1D16fd7A52E2ea510E74C8c3"
                var monadTxHash: String? = nil
                if VoiceSwapWallet.shared.isCreated {
                    let metadata = "{\"protocol\":\"betwhisper\",\"market\":\"\(bet.marketSlug)\",\"side\":\"\(bet.side)\",\"amount_usd\":\(bet.amountUSD),\"mon_price\":\(bet.monPriceUSD),\"ts\":\(Int(Date().timeIntervalSince1970))}"
                    let dataHex = "0x" + (metadata.data(using: .utf8) ?? Data()).map { String(format: "%02x", $0) }.joined()
                    do {
                        monadTxHash = try await VoiceSwapWallet.shared.sendTransaction(to: depositAddress, value: valueHex, data: dataHex)
                    } catch {
                        let errMsg = error.localizedDescription
                        NSLog("[Gemini] confirm_bet: Monad tx failed — %@", errMsg)
                        let amountStr = String(format: "%.0f", bet.amountUSD)
                        if errMsg.lowercased().contains("insufficient") {
                            result = ["status": "error", "error": "Insufficient MON balance. You need ~\(String(format: "%.1f", bet.monAmount)) MON to place this bet. Top up your wallet first."]
                        } else {
                            result = ["status": "error", "error": "Transaction failed: \(errMsg)"]
                        }
                        self.latestBetResult = BetResultEvent(
                            market: bet.marketSlug, side: bet.side, amountUSD: amountStr,
                            txHash: "", monadTxHash: "", success: false
                        )
                        break
                    }
                }
                if monadTxHash == nil && !VoiceSwapWallet.shared.isCreated {
                    // Demo mode: no wallet, generate mock tx
                    monadTxHash = "0x" + (0..<64).map { _ in String(format: "%x", Int.random(in: 0...15)) }.joined()
                }

                // Step 2: Execute on Polymarket CLOB
                let outcomeIndex = bet.side.lowercased() == "yes" ? 0 : 1
                let amountStr = String(format: "%.0f", bet.amountUSD)
                do {
                    let clobResult = try await VoiceSwapAPIClient.shared.executeClobBet(
                        conditionId: bet.conditionId,
                        outcomeIndex: outcomeIndex,
                        amountUSD: bet.amountUSD,
                        signalHash: self.lastDeepAnalysis?.signalHash ?? "",
                        marketSlug: bet.marketSlug,
                        monadTxHash: monadTxHash,
                        monPriceUSD: bet.monPriceUSD
                    )
                    if clobResult.success == true {
                        _ = try? await VoiceSwapAPIClient.shared.recordBet(
                            marketSlug: bet.marketSlug, side: bet.side, amount: amountStr,
                            walletAddress: VoiceSwapWallet.shared.isCreated ? VoiceSwapWallet.shared.address : "demo",
                            txHash: clobResult.polygonTxHash ?? clobResult.txHash ?? ""
                        )
                        let txHash = clobResult.polygonTxHash ?? clobResult.txHash ?? monadTxHash ?? ""
                        result = [
                            "status": "bet_confirmed",
                            "market": bet.marketSlug,
                            "side": bet.side,
                            "amount": amountStr,
                            "source": clobResult.source ?? "polymarket",
                            "tx_hash": txHash,
                            "price": clobResult.price ?? 0,
                            "shares": clobResult.shares ?? 0,
                            "message": "Bet confirmed! $\(amountStr) on \(bet.side) via Polymarket."
                        ]
                        // Publish bet result for chat display
                        self.latestBetResult = BetResultEvent(
                            market: bet.marketSlug,
                            side: bet.side,
                            amountUSD: amountStr,
                            txHash: txHash,
                            monadTxHash: monadTxHash ?? "",
                            success: true
                        )
                    } else {
                        let errorMsg = clobResult.error ?? "CLOB execution failed"
                        result = ["status": "error", "error": errorMsg]
                        self.latestBetResult = BetResultEvent(
                            market: bet.marketSlug,
                            side: bet.side,
                            amountUSD: amountStr,
                            txHash: "",
                            monadTxHash: monadTxHash ?? "",
                            success: false
                        )
                    }
                } catch {
                    result = ["status": "error", "error": error.localizedDescription]
                    self.latestBetResult = BetResultEvent(
                        market: bet.marketSlug,
                        side: bet.side,
                        amountUSD: amountStr,
                        txHash: "",
                        monadTxHash: monadTxHash ?? "",
                        success: false
                    )
                }

            default:
                result = ["error": "Unknown tool: \(toolCall.name)"]
            }

            let elapsed = Date().timeIntervalSince(toolStart)
            NSLog("[Gemini] Tool %@ completed in %.1fs", toolCall.name, elapsed)

            guard !Task.isCancelled else {
                NSLog("[Gemini] Tool call %@ cancelled, skipping response", toolCall.id)
                return
            }

            self.geminiService.sendToolResponse(
                callId: toolCall.id,
                name: toolCall.name,
                result: result
            )
            self.inFlightTasks.removeValue(forKey: toolCall.id)

            // Unmute mic after confirm_bet completes (place_bet no longer sends transactions)
            if toolCall.name == "confirm_bet" {
                self.audioManager.isMutedForEcho = false
                NSLog("[Gemini] confirm_bet: unmuting mic")
            }
        }

        inFlightTasks[toolCall.id] = task
    }

    // MARK: - MON Price Helper

    /// Fetch MON price with 30s cache + retry. Falls back to cached or default.
    private func fetchMonPrice() async -> Double {
        // Return cached if fresh (<30s)
        if let cached = cachedMonPrice, Date().timeIntervalSince(cachedMonPriceTime) < 30 {
            return cached
        }

        // Try up to 2 times
        for attempt in 0..<2 {
            if attempt > 0 {
                try? await Task.sleep(nanoseconds: 300_000_000) // 300ms retry delay
            }
            if let priceURL = URL(string: "https://betwhisper.ai/api/mon-price"),
               let (priceData, _) = try? await URLSession.shared.data(from: priceURL),
               let json = try? JSONSerialization.jsonObject(with: priceData) as? [String: Any],
               let price = json["price"] as? Double, price > 0 {
                cachedMonPrice = price
                cachedMonPriceTime = Date()
                return price
            }
        }

        // Fall back to cached (even if stale) or default
        return cachedMonPrice ?? 0.021
    }

    // MARK: - Wei Conversion Helper

    /// Convert a decimal string (e.g. "48100000000000000000") to hex without UInt64 overflow
    private static func decimalStringToHex(_ decimalString: String) -> String {
        // Strip any decimal point and trailing digits (we only want integer part)
        let intString: String
        if let dotIndex = decimalString.firstIndex(of: ".") {
            intString = String(decimalString[decimalString.startIndex..<dotIndex])
        } else {
            intString = decimalString
        }
        guard !intString.isEmpty, intString != "0" else { return "0" }

        // Manual base-10 to base-16 conversion for arbitrary precision
        var digits = Array(intString).compactMap { $0.wholeNumberValue }
        var hex = ""
        while !digits.isEmpty && !(digits.count == 1 && digits[0] == 0) {
            var remainder = 0
            var newDigits: [Int] = []
            for d in digits {
                let current = remainder * 10 + d
                let quotient = current / 16
                remainder = current % 16
                if !newDigits.isEmpty || quotient > 0 {
                    newDigits.append(quotient)
                }
            }
            hex = String(remainder, radix: 16) + hex
            digits = newDigits.isEmpty ? [0] : newDigits
        }
        return hex.isEmpty ? "0" : hex
    }
}

// MARK: - GeminiLiveServiceDelegate

extension GeminiSessionViewModel: GeminiLiveServiceDelegate {

    func geminiDidChangeState(_ state: GeminiConnectionState) {
        switch state {
        case .ready:
            sessionError = nil

            if geminiService.isReconnecting {
                // Reconnection — audio already capturing
                isSessionActive = true
                NSLog("[GeminiSession] Session resumed — audio already active")

                // Re-inject payment context so Gemini knows where we left off
                if let wallet = voiceMerchantWallet {
                    let amount = voiceAmount ?? "unknown"
                    if let vm = paymentViewModel, case .awaitingConfirmation = vm.flowState {
                        let context = "Payment ready. \(amount) USDC to \(wallet). Ask user to confirm."
                        NSLog("[GeminiSession] Re-injecting payment context after reconnect")
                        geminiService.sendClientContent(context)
                    }
                }

                // Re-inject market search context so Gemini remembers what user was looking at
                if let markets = lastSearchedMarkets, !markets.isEmpty {
                    let summary = markets.prefix(3).map { m in
                        "\(m.question): Yes \(Int((m.yesPrice ?? 0) * 100))%, conditionId=\(m.conditionId)"
                    }.joined(separator: ". ")
                    let context = "Previous search results: \(summary). User was choosing which market."
                    NSLog("[GeminiSession] Re-injecting market context after reconnect")
                    geminiService.sendClientContent(context)
                }
            } else if !userStartedSession {
                // Pre-connect only — don't start audio until user taps button
                NSLog("[GeminiSession] Pre-connected — waiting for user to start voice")
            } else if isListening {
                // Already listening (e.g. after transient error recovery)
                isSessionActive = true
                NSLog("[GeminiSession] Ready — audio already active")
            } else {
                // User tapped button → start audio
                isSessionActive = true
                NSLog("[GeminiSession] Active — starting audio capture")
                do {
                    try audioManager.startCapture()
                    isListening = true
                } catch {
                    sessionError = "Microphone error: \(error.localizedDescription)"
                    NSLog("[GeminiSession] Audio capture error: %@", error.localizedDescription)
                }
            }

        case .error(let msg):
            sessionError = msg
            // Don't tear down session on transient errors — keep audio alive
            // Session teardown only happens on .disconnected
            NSLog("[GeminiSession] Error: %@ (keeping session alive for recovery)", msg)
            scheduleErrorDismiss()

        case .connecting:
            // During reconnection, keep audio alive
            if geminiService.isReconnecting {
                NSLog("[GeminiSession] Reconnecting — keeping audio active")
            }

        case .disconnected:
            // During reconnection, don't tear down
            if geminiService.isReconnecting {
                NSLog("[GeminiSession] Temporary disconnect for resumption")
                return
            }

            let wasActive = isSessionActive
            isSessionActive = false
            isListening = false
            audioManager.stopCapture()

            // If session was NOT user-started (preconnect only), silently re-preconnect
            if !wasActive && !userStartedSession {
                NSLog("[GeminiSession] Preconnect lost — will re-preconnect in 2s")
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self.preconnect()
                }
            }

        default:
            break
        }
    }

    func geminiDidReceiveAudio(_ pcmData: Data) {
        // Gemini responded — cancel local TTS fallback
        qrResponseFallbackTask?.cancel()
        qrResponseFallbackTask = nil
        fallbackSynthesizer?.stopSpeaking(at: .immediate)
        fallbackSynthesizer = nil

        // Echo gate for phone mode
        if audioManager.audioMode == .phone {
            audioManager.isMutedForEcho = true
        }
        audioManager.playAudio(data: pcmData)
    }

    func geminiDidRequestToolCall(_ toolCall: GeminiToolCall) {
        handleToolCall(toolCall)
    }

    func geminiDidCancelToolCalls(_ cancellation: GeminiToolCallCancellation) {
        for id in cancellation.ids {
            if let task = inFlightTasks[id] {
                task.cancel()
                inFlightTasks.removeValue(forKey: id)
                NSLog("[GeminiSession] Cancelled tool call: %@", id)
            }
        }
    }

    func geminiDidCompleteTurn() {
        // Model finished speaking — unmute mic
        audioManager.isMutedForEcho = false
    }

    func geminiDidInterrupt() {
        // User interrupted — stop playback immediately
        audioManager.stopPlayback()
    }

    func geminiDidReceiveTranscript(role: String, text: String) {
        if role == "user" {
            // User started speaking — request a fresh video frame for visual context
            requestVideoFrame()

            // Gemini sends cumulative text per utterance, not deltas
            userTranscriptBuffer = text
            userTranscriptDebounce?.cancel()
            userTranscriptDebounce = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000) // 600ms debounce
                guard !Task.isCancelled else { return }
                let finalText = self.userTranscriptBuffer
                guard !finalText.isEmpty else { return }
                self.userTranscriptBuffer = ""
                self.latestTranscript = TranscriptEvent(role: "user", text: finalText)
            }
        } else {
            assistantTranscriptBuffer = text
            assistantTranscriptDebounce?.cancel()
            assistantTranscriptDebounce = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard !Task.isCancelled else { return }
                let finalText = self.assistantTranscriptBuffer
                guard !finalText.isEmpty else { return }
                self.assistantTranscriptBuffer = ""
                self.latestTranscript = TranscriptEvent(role: "assistant", text: finalText)
            }
        }
    }
}
