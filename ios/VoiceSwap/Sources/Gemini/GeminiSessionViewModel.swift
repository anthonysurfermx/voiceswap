import Foundation
import Combine
import UIKit

// MARK: - Tool Declarations

private enum VoiceSwapTools {

    static func allDeclarations() -> [[String: Any]] {
        [scanQR, getBalance, preparePayment, confirmPayment, cancelPayment, setPaymentAmount, setPurchaseConcept]
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

    static let getBalance: [String: Any] = [
        "name": "get_balance",
        "description": "Get the user's current wallet balance including USDC, MON, and other tokens on Monad.",
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
        "description": "Execute the previously prepared payment. This opens the user's wallet for transaction signing. Only call this after the user has explicitly confirmed they want to pay.",
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
        "description": "Set the amount for a pending payment when the QR code did not include an amount. You MUST call this tool when the user tells you the amount. After this returns, you MUST call prepare_payment next.",
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

    static let setPurchaseConcept: [String: Any] = [
        "name": "set_purchase_concept",
        "description": "Record what the user is buying (e.g. 'coffee', 'lunch', 'groceries'). Call this when the user tells you what they are purchasing, before scanning the QR code.",
        "parameters": [
            "type": "object",
            "properties": [
                "concept": [
                    "type": "string",
                    "description": "Short description of what the user is buying (e.g., 'coffee', 'lunch', 'tacos')"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["concept"]
        ] as [String: Any]
    ]
}

// MARK: - GeminiSessionViewModel

@MainActor
class GeminiSessionViewModel: ObservableObject {

    // MARK: Published

    @Published private(set) var isSessionActive: Bool = false
    @Published private(set) var isListening: Bool = false
    @Published private(set) var isAISpeaking: Bool = false
    @Published private(set) var sessionError: String?

    // MARK: Services

    let geminiService = GeminiLiveService()
    let audioManager = AudioManager()

    // MARK: References

    weak var paymentViewModel: VoiceSwapViewModel?

    // MARK: Video Throttle

    private var lastVideoSendTime: Date = .distantPast

    // MARK: In-flight Tool Calls

    private var inFlightTasks: [String: Task<Void, Never>] = [:]

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

    // MARK: - Session Lifecycle

    func startSession(audioMode: AudioMode) {
        guard GeminiConfig.isConfigured else {
            sessionError = "Enter your Gemini API key in Settings"
            return
        }

        sessionError = nil
        audioManager.audioMode = audioMode

        // Configure Gemini
        geminiService.systemPrompt = VoiceSwapSystemPrompt.build(
            walletAddress: paymentViewModel?.walletAddress,
            balance: paymentViewModel?.walletBalance
        )
        geminiService.toolDeclarations = VoiceSwapTools.allDeclarations()

        // Connect
        Task {
            let connected = await geminiService.connect()
            if !connected {
                sessionError = "Failed to connect to Gemini"
            }
        }
    }

    func stopSession() {
        // Cancel all in-flight tool calls
        for (_, task) in inFlightTasks {
            task.cancel()
        }
        inFlightTasks.removeAll()

        audioManager.cleanup()
        geminiService.disconnect()
        isSessionActive = false
        isListening = false
    }

    // MARK: - Video Frame Forwarding

    func processVideoFrame(_ image: UIImage) {
        guard isSessionActive, geminiService.connectionState == .ready else { return }

        let now = Date()
        guard now.timeIntervalSince(lastVideoSendTime) >= GeminiConfig.videoFrameInterval else { return }
        lastVideoSendTime = now

        guard let jpegData = image.jpegData(compressionQuality: GeminiConfig.videoJPEGQuality) else { return }
        geminiService.sendVideoFrame(jpegData: jpegData)
    }

    // MARK: - QR Notification to Gemini

    func notifyQRDetected(merchantWallet: String, merchantName: String?, amount: String?) {
        guard isSessionActive else { return }

        // Send context as a text message so Gemini knows about the QR detection
        var context = "A QR code was detected. Merchant wallet: \(merchantWallet)."
        if let name = merchantName {
            context += " Merchant: \(name)."
        }
        if let amount = amount {
            context += " Amount: \(amount) USDC."
        } else {
            context += " No amount specified — ask the user how much to pay."
        }

        // Send as a realtime input text (context injection)
        let json: [String: Any] = [
            "clientContent": [
                "turns": [
                    [
                        "role": "user",
                        "parts": [["text": context]]
                    ]
                ],
                "turnComplete": true
            ]
        ]

        // Use the send queue via the service
        if let data = try? JSONSerialization.data(withJSONObject: json),
           let text = String(data: data, encoding: .utf8) {
            // Access websocket through the service
            geminiService.sendToolResponse(callId: "qr_context", name: "system", result: ["context": context])
        }
    }

    // MARK: - Private: Tool Call Dispatch

    private func handleToolCall(_ toolCall: GeminiToolCall) {
        guard let vm = paymentViewModel else {
            geminiService.sendToolResponse(
                callId: toolCall.id,
                name: toolCall.name,
                result: ["error": "Payment system not ready"]
            )
            return
        }

        // scan_qr is handled separately — respond immediately, then start camera async
        // This prevents Gemini from cancelling the tool call while the camera is starting
        if toolCall.name == "scan_qr" {
            // Don't re-scan if we already have a QR or are past scanning
            if case .enteringAmount = vm.flowState {
                NSLog("[Gemini] scan_qr ignored — already entering amount")
                geminiService.sendToolResponse(callId: toolCall.id, name: toolCall.name, result: ["status": "already_scanned", "message": "QR already detected, waiting for amount"])
                return
            }
            if case .awaitingConfirmation = vm.flowState {
                NSLog("[Gemini] scan_qr ignored — already awaiting confirmation")
                geminiService.sendToolResponse(callId: toolCall.id, name: toolCall.name, result: ["status": "already_scanned", "message": "Payment ready for confirmation"])
                return
            }
            if vm.glassesManager.isStreaming {
                NSLog("[Gemini] scan_qr ignored — camera already streaming")
                geminiService.sendToolResponse(callId: toolCall.id, name: toolCall.name, result: ["status": "scanning", "message": "Already scanning for QR"])
                return
            }

            // Respond immediately so Gemini doesn't cancel
            vm.flowState = .scanningQR
            vm.glassesManager.triggerHaptic(.short)
            geminiService.sendToolResponse(callId: toolCall.id, name: toolCall.name, result: ["status": "scanning", "message": "QR scanning started. Tell the user to point at the QR code."])

            // Start camera with timeout — if camera fails or takes too long, notify Gemini
            Task { @MainActor in
                NSLog("[Gemini] scan_qr: starting camera stream...")
                await vm.glassesManager.startCameraStream()

                // Check if camera actually started after a brief delay
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds

                // If still in scanningQR state but camera isn't streaming, something went wrong
                if case .scanningQR = vm.flowState, !vm.glassesManager.isStreaming {
                    NSLog("[Gemini] scan_qr: camera failed to start after 3s — notifying Gemini")
                    // Inject context so Gemini knows the camera failed
                    self.geminiService.sendToolResponse(
                        callId: "camera_error",
                        name: "system",
                        result: [
                            "event": "camera_error",
                            "message": "Camera failed to start. The user can still use the phone camera — tell them to point their phone at the QR code instead. Or they can enter the merchant wallet address manually."
                        ]
                    )
                } else {
                    NSLog("[Gemini] scan_qr: camera streaming OK or QR already detected")
                }
            }
            return
        }

        let task = Task { @MainActor in
            let result: [String: Any]

            // Timeout wrapper — 30s max for any tool call
            let toolStart = Date()

            switch toolCall.name {
            case "get_balance":
                await vm.refreshBalances()
                let tokens = vm.tokenBalances.map { ["symbol": $0.symbol, "balance": $0.balance] }
                result = [
                    "balance_usd": vm.walletBalance,
                    "mon_balance": vm.monBalance,
                    "tokens": tokens
                ] as [String: Any]

            case "prepare_payment":
                let wallet = toolCall.args["merchant_wallet"] as? String ?? ""
                let amount = toolCall.args["amount"] as? String ?? ""
                let merchantName = toolCall.args["merchant_name"] as? String

                vm.currentMerchantWallet = wallet
                vm.currentMerchantName = merchantName
                vm.currentAmount = amount
                await vm.preparePayment()

                if case .awaitingConfirmation = vm.flowState {
                    var readyResult: [String: Any] = [
                        "status": "ready",
                        "amount": amount,
                        "merchant": merchantName ?? wallet,
                        "needs_swap": vm.needsSwap,
                    ]
                    if vm.needsSwap, let swapFrom = vm.swapFromToken {
                        readyResult["swap_from"] = swapFrom
                        readyResult["message"] = "Will swap \(swapFrom) to USDC before paying. User will need to approve multiple transactions."
                    }
                    result = readyResult
                } else if case .failed(let error) = vm.flowState {
                    result = ["status": "failed", "error": error]
                } else {
                    result = ["status": "processing"]
                }

            case "confirm_payment":
                // Guard: confirm_payment requires prepare_payment to have been called first
                guard case .awaitingConfirmation = vm.flowState else {
                    NSLog("[Gemini] confirm_payment rejected — not in awaitingConfirmation state (current: \(vm.flowState))")
                    result = [
                        "status": "error",
                        "error": "Cannot confirm — you must call prepare_payment first. Current state: \(vm.flowState)"
                    ]
                    break
                }

                await vm.confirmPayment()
                if case .success(let txHash) = vm.flowState {
                    result = ["status": "success", "tx_hash": txHash]
                } else if case .failed(let error) = vm.flowState {
                    result = ["status": "failed", "error": error]
                } else if case .cancelled = vm.flowState {
                    result = ["status": "cancelled", "message": "User rejected the transaction"]
                } else {
                    result = ["status": "pending"]
                }

            case "cancel_payment":
                vm.cancelPayment()
                result = ["status": "cancelled"]

            case "set_payment_amount":
                let amount = toolCall.args["amount"] as? String ?? ""
                await vm.setPaymentAmount(amount)
                if case .awaitingConfirmation = vm.flowState {
                    result = ["status": "ready", "amount": amount]
                } else {
                    result = ["status": "amount_set", "amount": amount, "next_step": "Now call prepare_payment with the merchant_wallet and this amount"]
                }

            case "set_purchase_concept":
                let concept = toolCall.args["concept"] as? String ?? ""
                vm.currentPurchaseConcept = concept
                NSLog("[Gemini] Purchase concept set: %@", concept)
                result = ["status": "recorded", "concept": concept]

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
        }

        inFlightTasks[toolCall.id] = task
    }
}

// MARK: - GeminiLiveServiceDelegate

extension GeminiSessionViewModel: GeminiLiveServiceDelegate {

    func geminiDidChangeState(_ state: GeminiConnectionState) {
        switch state {
        case .ready:
            isSessionActive = true
            sessionError = nil
            NSLog("[GeminiSession] Active — starting audio capture")
            do {
                try audioManager.startCapture()
                isListening = true
            } catch {
                sessionError = "Microphone error: \(error.localizedDescription)"
                NSLog("[GeminiSession] Audio capture error: %@", error.localizedDescription)
            }

        case .error(let msg):
            sessionError = msg
            isSessionActive = false
            isListening = false
            audioManager.stopCapture()

        case .disconnected:
            isSessionActive = false
            isListening = false
            audioManager.stopCapture()

        default:
            break
        }
    }

    func geminiDidReceiveAudio(_ pcmData: Data) {
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
}
