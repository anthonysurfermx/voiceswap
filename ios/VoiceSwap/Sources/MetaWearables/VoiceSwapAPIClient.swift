/**
 * VoiceSwapAPIClient.swift
 * VoiceSwap - API client for backend communication
 *
 * Handles all HTTP communication with the VoiceSwap backend
 * including AI intent parsing, balance checks, and payment execution.
 */

import Foundation

// MARK: - API Response Models

public struct APIResponse<T: Decodable>: Decodable {
    public let success: Bool
    public let data: T?
    public let error: String?
}

public struct EmptyResponse: Decodable {}

public struct ParsedIntent: Decodable {
    public let type: String
    public let confidence: Double
    public let amount: String?
    public let currency: String?
    public let recipient: String?
    public let tokenIn: String?
    public let tokenOut: String?
    public let rawText: String
    public let language: String
}

public struct AIProcessResponse: Decodable {
    public let intent: ParsedIntent
    public let voiceResponse: String
    public let nextAction: String
    public let context: ContextInfo?
    public let timestamp: Int
}

public struct ContextInfo: Decodable {
    public let balance: String?
    public let monBalance: String?
    public let merchantName: String?
}

public struct WalletBalances: Decodable {
    public let address: String
    public let chainId: Int
    public let nativeMON: TokenBalance
    public let tokens: [TokenBalance]
    public let totalUSDC: String
    public let totalUSD: String
    public let monPriceUSD: Double

    enum CodingKeys: String, CodingKey {
        case address, chainId, nativeMON, tokens, totalUSDC, totalUSD, monPriceUSD
        // Legacy field names for backwards compatibility
        case nativeETH, ethPriceUSD
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        address = try c.decode(String.self, forKey: .address)
        chainId = try c.decode(Int.self, forKey: .chainId)
        tokens = try c.decode([TokenBalance].self, forKey: .tokens)
        totalUSDC = try c.decode(String.self, forKey: .totalUSDC)
        totalUSD = try c.decode(String.self, forKey: .totalUSD)
        // Accept nativeMON or fall back to nativeETH (old backend)
        if let mon = try? c.decode(TokenBalance.self, forKey: .nativeMON) {
            nativeMON = mon
        } else {
            nativeMON = try c.decode(TokenBalance.self, forKey: .nativeETH)
        }
        if let price = try? c.decode(Double.self, forKey: .monPriceUSD) {
            monPriceUSD = price
        } else {
            monPriceUSD = try c.decodeIfPresent(Double.self, forKey: .ethPriceUSD) ?? 0
        }
    }
}

public struct TokenBalance: Decodable {
    public let symbol: String
    public let address: String
    public let balance: String
    public let balanceRaw: String
    public let decimals: Int
}

public struct PaymentRequest: Decodable {
    public let merchantWallet: String
    public let amount: String?
    public let merchantName: String?
    public let orderId: String?
}

public struct PreparePaymentResponse: Decodable {
    public let paymentRequest: PaymentRequest
    public let userBalances: WalletBalances
    public let swapInfo: SwapInfo
    public let maxPayable: MaxPayable
    public let voicePrompt: String
    public let ready: Bool
}

public struct SwapInfo: Decodable {
    public let needsSwap: Bool
    public let swapFrom: String?
    public let swapFromSymbol: String?
    public let hasEnoughUSDC: Bool
    public let hasEnoughMON: Bool
    public let hasEnoughWMON: Bool
}

public struct MaxPayable: Decodable {
    public let tokenSymbol: String?
    public let tokenAddress: String?
    public let maxAmount: String?
    public let estimatedUSDC: String?
}

public struct ExecutePaymentResponse: Decodable {
    public let action: String
    public let status: String?
    public let token: String?
    public let tokenSymbol: String?
    public let amount: String?
    public let to: String?
    public let from: String?
    public let txHash: String?
    public let explorerUrl: String?
    public let message: String
    public let steps: [PaymentStep]?
}

public struct PaymentStep: Decodable {
    public let step: Int
    public let action: String
    public let tokenIn: String?
    public let tokenOut: String?
    public let amount: String?
    public let to: String?
}

public struct VoiceCommandResponse: Decodable {
    public let command: String
    public let transcript: String
    public let shouldProceed: Bool
    public let voiceResponse: String
    public let sessionId: String?
}

public struct PaymentSession: Codable {
    public let id: String
    public let state: String
    public let userAddress: String
    public let merchantWallet: String?
    public let merchantName: String?
    public let amount: String?
    public let needsSwap: Bool
    public let swapFromToken: String?
    public let createdAt: Int
    public let updatedAt: Int
    public let txHash: String?
    public let error: String?
}

public struct PaymentDetailsResponse: Decodable {
    public let amount: String?
    public let currency: String?
    public let recipient: String?
    public let confidence: Double?
}

public struct SessionUpdateResponse: Decodable {
    public let success: Bool
    public let sessionId: String?
}

// MARK: - Transaction Preparation (for WalletConnect signing)

public struct TransactionStep: Decodable {
    public let type: String        // "wrap", "approve", "swap", "transfer"
    public let tx: TransactionData
    public let description: String
}

public struct SwapDetails: Decodable {
    public let fromToken: String?
    public let toToken: String?
    public let amountIn: String?
    public let estimatedOut: String?
    public let priceImpact: String?
    public let slippage: String?
}

public struct PrepareTransactionResponse: Decodable {
    public let transaction: TransactionData
    public let steps: [TransactionStep]?
    public let needsSwap: Bool?
    public let swapInfo: SwapDetails?
    public let tokenAddress: String
    public let tokenSymbol: String
    public let amount: String
    public let recipient: String
    public let recipientShort: String
    public let message: String
    public let explorerBaseUrl: String
}

public struct TransactionData: Decodable {
    public let to: String
    public let value: String
    public let data: String
    public let from: String
    public let chainId: Int
}

public struct HealthResponse: Decodable {
    public let status: String
    public let timestamp: Int?
    public let openai: String?
}

// Extended error response for prepare-tx (when insufficient balance)
public struct InsufficientBalanceError: Decodable {
    public let success: Bool
    public let error: String
    public let currentBalance: String?
    public let requiredAmount: String?
}

// MARK: - Payment Receipt

public struct PaymentReceiptResponse: Decodable {
    public let receiptHash: String
    public let txHash: String
    public let timestamp: Int
    public let signature: String
    public let verifyUrl: String
}

// MARK: - Gas Sponsorship

public struct GasRequestResponse: Decodable {
    public let status: String    // "funded" or "sufficient"
    public let txHash: String?
    public let amount: String?
    public let balance: String?
    public let message: String
}

// MARK: - User Payment History

public struct UserPayment: Decodable, Identifiable {
    public var id: Int? { _id }
    private let _id: Int?
    public let merchant_wallet: String
    public let tx_hash: String
    public let from_address: String
    public let amount: String
    public let concept: String?
    public let merchant_name: String?
    public let block_number: Int
    public let created_at: Int

    enum CodingKeys: String, CodingKey {
        case _id = "id"
        case merchant_wallet, tx_hash, from_address, amount, concept, merchant_name, block_number, created_at
    }

    public var merchantShort: String {
        guard merchant_wallet.count > 10 else { return merchant_wallet }
        return "\(merchant_wallet.prefix(6))...\(merchant_wallet.suffix(4))"
    }

    public var txHashShort: String {
        guard tx_hash.count > 12 else { return tx_hash }
        return "\(tx_hash.prefix(8))...\(tx_hash.suffix(4))"
    }

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(created_at / 1000))
    }
}

public struct UserPaymentsResponse: Decodable {
    public let payments: [UserPayment]
    public let pagination: PaginationInfo
}

public struct PaginationInfo: Decodable {
    public let limit: Int
    public let offset: Int
    public let count: Int
}

// MARK: - Transaction Status

public struct TransactionStatusResponse: Decodable {
    public let txHash: String
    public let status: String  // "pending", "confirmed", "failed", "not_found"
    public let confirmations: Int?
    public let blockNumber: Int?
    public let gasUsed: String?
    public let from: String?
    public let to: String?
    public let explorerUrl: String?
    public let message: String
}

// MARK: - BetWhisper Prediction Market Models

public struct MarketEvent: Decodable {
    public let title: String
    public let slug: String
    public let image: String?
    public let volume: Double?
    public let endDate: String?
    public let markets: [MarketItem]?
}

public struct MarketItem: Decodable {
    public let conditionId: String
    public let question: String
    public let slug: String
    public let volume: Double?
    public let yesPrice: Double?
    public let noPrice: Double?
    public let image: String?
    public let endDate: String?
}

public struct MarketsResponse: Decodable {
    public let events: [MarketEvent]
    public let cached: Bool?
}

public struct SmartWalletPosition: Decodable {
    public let pseudonym: String
    public let score: Double
    public let side: String
    public let positionSize: Double
    public let conviction: Double
    public let weight: Double
    public let isAgent: Bool
}

public struct MarketConsensus: Decodable {
    public let direction: String
    public let pct: Int
    public let yesWeight: Int
    public let noWeight: Int
    public let count: Int
}

public struct AgentShieldInfo: Decodable {
    public let agentCount: Int
    public let humanCount: Int
    public let warning: String?
    public let riskLevel: String
}

public struct MarketAnalysis: Decodable {
    public let smartWallets: [SmartWalletPosition]
    public let consensus: MarketConsensus
    public let agentShield: AgentShieldInfo
    public let totalHolders: Int
    public let trackedWalletCount: Int
    public let signalHash: String
}

// MARK: - Deep Analysis Models (Agent Radar)

public struct DeepAnalysisClassifications: Decodable {
    public let bot: Int
    public let likelyBot: Int
    public let mixed: Int
    public let human: Int
}

public struct OutcomeCapital: Decodable {
    public let total: Double
    public let agent: Double
    public let human: Double
}

public struct CapitalByOutcome: Decodable {
    public let Yes: OutcomeCapital
    public let No: OutcomeCapital
}

public struct HolderStrategy: Decodable {
    public let type: String
    public let label: String
    public let confidence: Double
}

public struct DominantStrategy: Decodable {
    public let type: String
    public let label: String
    public let count: Int
}

public struct TopHolder: Decodable {
    public let address: String
    public let pseudonym: String
    public let side: String
    public let positionSize: Double
    public let botScore: Int
    public let classification: String
    public let strategy: HolderStrategy
}

public struct DeepAnalysisResult: Decodable {
    public let totalHolders: Int
    public let holdersScanned: Int
    public let agentRate: Int
    public let classifications: DeepAnalysisClassifications
    public let strategies: [String: Int]
    public let dominantStrategy: DominantStrategy?
    public let capitalByOutcome: CapitalByOutcome
    public let topHolders: [TopHolder]
    public let smartMoneyDirection: String
    public let smartMoneyPct: Int
    public let redFlags: [String]
    public let recommendation: String
    public let tags: [String]
    public let signalHash: String
}

public struct ExplainFallbackResponse: Decodable {
    public let fallback: [String]?
}

public struct BetConfirmation: Decodable {
    public let success: Bool
    public let bet: BetRecord?
}

public struct BetRecord: Decodable {
    public let id: String?
    public let marketSlug: String
    public let side: String
    public let amount: String
    public let txHash: String
    public let timestamp: Int?
    public let source: String?
    public let explorerUrl: String?
    public let shares: Double?
    public let price: Double?
    public let monadTxHash: String?
}

public struct ClobExecuteResult: Decodable {
    public let success: Bool?
    public let source: String?
    public let orderID: String?
    public let txHash: String?
    public let polygonTxHash: String?
    public let price: Double?
    public let shares: Double?
    public let amountUSD: Double?
    public let explorerUrl: String?
    public let monadTxHash: String?
    public let marketSlug: String?
    public let side: String?
    public let error: String?
}

// MARK: - Order History (Transaction History)

public struct OrderHistoryItem: Decodable, Identifiable {
    public var id: Int
    public let marketSlug: String
    public let side: String
    public let amountUSD: Double
    public let shares: Double
    public let fillPrice: Double
    public let status: String
    public let monadTxHash: String?
    public let polygonTxHash: String?
    public let monPaid: String?
    public let monPriceUSD: Double?
    public let errorMsg: String?
    public let createdAt: String

    public var monadTxShort: String? {
        guard let hash = monadTxHash, hash.count > 12 else { return monadTxHash }
        return "\(hash.prefix(8))...\(hash.suffix(4))"
    }

    public var polygonTxShort: String? {
        guard let hash = polygonTxHash, hash.count > 12 else { return polygonTxHash }
        return "\(hash.prefix(8))...\(hash.suffix(4))"
    }

    public var date: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = formatter.date(from: createdAt) { return d }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: createdAt)
    }

    public var relativeTime: String {
        guard let d = date else { return createdAt }
        let interval = Date().timeIntervalSince(d)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

public struct OrderHistoryResponse: Decodable {
    public let orders: [OrderHistoryItem]
}

// MARK: - Groups Models

public struct GroupEligibility: Decodable {
    public let eligible: Bool
    public let group: GroupInfo?
}

public struct GroupInfo: Decodable, Identifiable {
    public let id: String
    public let name: String
    public let mode: String
    public let invite_code: String
    public let creator_wallet: String
    public let member_count: Int?
    public let market_slug: String?
    public let created_at: String?

    enum CodingKeys: String, CodingKey {
        case id, name, mode, invite_code, creator_wallet, member_count, market_slug, created_at
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mode = try c.decode(String.self, forKey: .mode)
        invite_code = try c.decode(String.self, forKey: .invite_code)
        creator_wallet = try c.decode(String.self, forKey: .creator_wallet)
        market_slug = try c.decodeIfPresent(String.self, forKey: .market_slug)
        created_at = try c.decodeIfPresent(String.self, forKey: .created_at)
        // member_count can come as Int or String from Postgres
        if let intVal = try? c.decode(Int.self, forKey: .member_count) {
            member_count = intVal
        } else if let strVal = try? c.decode(String.self, forKey: .member_count), let parsed = Int(strVal) {
            member_count = parsed
        } else {
            member_count = nil
        }
    }
}

public struct GroupMember: Decodable {
    public let wallet_address: String
    public let joined_at: String?
}

public struct GroupDetail: Decodable {
    public let id: String
    public let name: String
    public let mode: String
    public let invite_code: String
    public let creator_wallet: String
    public let member_count: Int?
    public let members: [GroupMember]

    enum CodingKeys: String, CodingKey {
        case id, name, mode, invite_code, creator_wallet, member_count, members
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        mode = try c.decode(String.self, forKey: .mode)
        invite_code = try c.decode(String.self, forKey: .invite_code)
        creator_wallet = try c.decode(String.self, forKey: .creator_wallet)
        members = try c.decode([GroupMember].self, forKey: .members)
        if let intVal = try? c.decode(Int.self, forKey: .member_count) {
            member_count = intVal
        } else if let strVal = try? c.decode(String.self, forKey: .member_count), let parsed = Int(strVal) {
            member_count = parsed
        } else {
            member_count = nil
        }
    }
}

public struct JoinGroupResult: Decodable {
    public let joined: Bool
    public let group_id: String
    public let group_name: String
    public let member_count: Int
}

public struct LeaderboardEntry: Decodable {
    public let wallet_address: String
    public let total_pnl: String
    public let bet_count: String
}

public struct GroupLeaderboard: Decodable {
    public let group_name: String
    public let mode: String
    public let leaderboard: [LeaderboardEntry]
}

// MARK: - API Client

public actor VoiceSwapAPIClient {

    // MARK: - Singleton
    public static let shared = VoiceSwapAPIClient()

    // MARK: - Properties
    private let baseURL: String        // Payment/wallet API (Express server)
    private let betwhisperURL: String  // Prediction market API (Next.js app)
    private let session: URLSession

    // MARK: - Initialization

    private init() {
        // Payment API: Express server at voiceswap.vercel.app
        #if DEBUG
        self.baseURL = ProcessInfo.processInfo.environment["VOICESWAP_API_URL"] ?? "https://voiceswap.vercel.app"
        #else
        self.baseURL = "https://voiceswap.vercel.app"
        #endif

        // Prediction market API: Next.js app at betwhisper.ai
        self.betwhisperURL = "https://betwhisper.ai"

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        print("[VoiceSwapAPI] Initialized with base URL: \(baseURL)")
        print("[VoiceSwapAPI] BetWhisper API: \(betwhisperURL)")
    }

    // MARK: - AI Endpoints

    /// Parse voice transcript using AI
    public func parseVoiceCommand(transcript: String) async throws -> APIResponse<AIProcessResponse> {
        let body: [String: Any] = ["transcript": transcript]
        return try await post("/voiceswap/ai/parse", body: body)
    }

    /// Full AI processing with context
    public func processVoiceCommand(
        transcript: String,
        userAddress: String?,
        merchantWallet: String?
    ) async throws -> APIResponse<AIProcessResponse> {
        var body: [String: Any] = ["transcript": transcript]

        if let address = userAddress {
            body["userAddress"] = address
        }
        if let merchant = merchantWallet {
            body["merchantWallet"] = merchant
        }

        return try await post("/voiceswap/ai/process", body: body)
    }

    /// Extract payment details from natural language
    public func extractPaymentDetails(transcript: String) async throws -> APIResponse<PaymentDetailsResponse> {
        let body: [String: Any] = ["transcript": transcript]
        return try await post("/voiceswap/ai/payment-details", body: body)
    }

    // MARK: - Payment Endpoints

    /// Parse QR code data
    public func parseQRCode(qrData: String) async throws -> APIResponse<PaymentRequest> {
        let body: [String: Any] = ["qrData": qrData]
        return try await post("/voiceswap/parse-qr", body: body)
    }

    /// Get wallet balances
    public func getWalletBalances(address: String) async throws -> APIResponse<WalletBalances> {
        return try await get("/voiceswap/balance/\(address)")
    }

    /// Prepare payment (check balances, determine swap needs)
    public func preparePayment(
        userAddress: String,
        merchantWallet: String?,
        qrData: String?,
        amount: String?
    ) async throws -> APIResponse<PreparePaymentResponse> {
        var body: [String: Any] = ["userAddress": userAddress]

        if let merchant = merchantWallet {
            body["merchantWallet"] = merchant
        }
        if let qr = qrData {
            body["qrData"] = qr
        }
        if let amt = amount {
            body["amount"] = amt
        }

        return try await post("/voiceswap/prepare", body: body)
    }

    /// Execute payment (DEPRECATED - use prepareTransaction + WalletConnect instead)
    public func executePayment(
        userAddress: String,
        merchantWallet: String,
        amount: String
    ) async throws -> APIResponse<ExecutePaymentResponse> {
        let body: [String: Any] = [
            "userAddress": userAddress,
            "merchantWallet": merchantWallet,
            "amount": amount
        ]
        return try await post("/voiceswap/execute", body: body)
    }

    /// Prepare transaction for client-side signing via WalletConnect
    /// Returns transaction data (to, value, data) ready to be sent to the user's wallet
    public func prepareTransaction(
        userAddress: String,
        merchantWallet: String,
        amount: String
    ) async throws -> APIResponse<PrepareTransactionResponse> {
        let body: [String: Any] = [
            "userAddress": userAddress,
            "merchantWallet": merchantWallet,
            "amount": amount
        ]

        // Use custom handling for this endpoint to provide better error messages
        guard let url = URL(string: "\(baseURL)/voiceswap/prepare-tx") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        print("[VoiceSwapAPI] prepare-tx response: HTTP \(httpResponse.statusCode)")

        // Handle 400 errors specially (insufficient balance, etc.)
        if httpResponse.statusCode == 400 {
            if let balanceError = try? JSONDecoder().decode(InsufficientBalanceError.self, from: data) {
                var errorMsg = balanceError.error
                if let current = balanceError.currentBalance, let required = balanceError.requiredAmount {
                    errorMsg = "Insufficient USDC. Balance: \(current), Required: \(required)"
                }
                throw APIError.serverError(errorMsg)
            }
            throw APIError.httpError(400)
        }

        if httpResponse.statusCode >= 400 {
            if let bodyString = String(data: data, encoding: .utf8) {
                print("[VoiceSwapAPI] Error body: \(bodyString)")
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        return try JSONDecoder().decode(APIResponse<PrepareTransactionResponse>.self, from: data)
    }

    /// Process voice confirmation
    public func confirmVoiceCommand(
        transcript: String,
        sessionId: String?
    ) async throws -> APIResponse<VoiceCommandResponse> {
        var body: [String: Any] = ["transcript": transcript]

        if let session = sessionId {
            body["sessionId"] = session
        }

        return try await post("/voiceswap/confirm", body: body)
    }

    // MARK: - Session Management

    /// Create new payment session
    public func createSession(userAddress: String) async throws -> APIResponse<PaymentSession> {
        let body: [String: Any] = ["userAddress": userAddress]
        return try await post("/voiceswap/session", body: body)
    }

    /// Update session state
    public func updateSession(
        sessionId: String,
        newState: String
    ) async throws -> APIResponse<SessionUpdateResponse> {
        let body: [String: Any] = [
            "newState": newState
        ]

        return try await put("/voiceswap/session/\(sessionId)", body: body)
    }

    // MARK: - Transaction Status

    /// Get transaction status from blockchain
    /// Returns status: "pending", "confirmed", "failed", or "not_found"
    public func getTransactionStatus(txHash: String) async throws -> APIResponse<TransactionStatusResponse> {
        return try await get("/voiceswap/tx/\(txHash)")
    }

    // MARK: - Merchant Payment Tracking

    /// Record a payment with purchase concept for merchant history
    public func saveMerchantPayment(
        merchantWallet: String,
        txHash: String,
        fromAddress: String,
        amount: String,
        concept: String?,
        blockNumber: Int? = nil
    ) async throws {
        var body: [String: Any] = [
            "merchantWallet": merchantWallet,
            "txHash": txHash,
            "fromAddress": fromAddress,
            "amount": amount
        ]
        if let concept = concept {
            body["concept"] = concept
        }
        if let blockNumber = blockNumber {
            body["blockNumber"] = blockNumber
        }

        // Fire and forget — don't fail the payment if tracking fails
        let _: APIResponse<EmptyResponse> = try await post("/voiceswap/merchant/payment", body: body)
    }

    // MARK: - Payment Receipts

    /// Request a signed payment receipt (proof of purchase)
    public func requestReceipt(
        txHash: String,
        payerAddress: String,
        merchantWallet: String,
        amount: String,
        concept: String?
    ) async throws -> APIResponse<PaymentReceiptResponse> {
        var body: [String: Any] = [
            "txHash": txHash,
            "payerAddress": payerAddress,
            "merchantWallet": merchantWallet,
            "amount": amount,
        ]
        if let concept = concept {
            body["concept"] = concept
        }
        return try await post("/voiceswap/receipt", body: body)
    }

    // MARK: - Gas Sponsorship

    /// Request gas airdrop for new users
    public func requestGas(userAddress: String) async throws -> APIResponse<GasRequestResponse> {
        let body: [String: Any] = ["userAddress": userAddress]
        return try await post("/voiceswap/gas/request", body: body)
    }

    // MARK: - User Payment History

    /// Get user's payment history
    public func getUserPayments(address: String, limit: Int = 50, offset: Int = 0) async throws -> APIResponse<UserPaymentsResponse> {
        return try await get("/voiceswap/user/payments/\(address)?limit=\(limit)&offset=\(offset)")
    }

    // MARK: - BetWhisper Prediction Markets

    /// Search prediction markets by query
    public func searchMarkets(query: String, limit: Int = 5) async throws -> MarketsResponse {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let url = URL(string: "\(betwhisperURL)/api/markets?q=\(encodedQuery)&limit=\(limit)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(MarketsResponse.self, from: data)
    }

    /// Analyze a market for whale positions
    public func analyzeMarket(conditionId: String) async throws -> MarketAnalysis {
        let url = URL(string: "\(betwhisperURL)/api/market/analyze")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["conditionId": conditionId])
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(MarketAnalysis.self, from: data)
    }

    /// Deep analyze a market with Agent Radar (bot detection, strategy classification)
    public func deepAnalyzeMarket(conditionId: String) async throws -> DeepAnalysisResult {
        let url = URL(string: "\(betwhisperURL)/api/market/deep-analyze")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 120 // deep analysis scans 15 holders, can take a while
        request.httpBody = try JSONSerialization.data(withJSONObject: ["conditionId": conditionId])
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(DeepAnalysisResult.self, from: data)
    }

    /// Get AI explanation of market analysis (Claude Haiku)
    /// Handles both SSE stream and JSON fallback responses
    public func explainMarket(
        analysis: DeepAnalysisResult,
        market: MarketItem,
        language: String
    ) async throws -> [String] {
        let url = URL(string: "\(betwhisperURL)/api/market/explain")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        // Build the request body matching the web's ExplainRequest interface
        let analysisDict: [String: Any] = [
            "totalHolders": analysis.totalHolders,
            "holdersScanned": analysis.holdersScanned,
            "agentRate": analysis.agentRate,
            "classifications": [
                "bot": analysis.classifications.bot,
                "likelyBot": analysis.classifications.likelyBot,
                "mixed": analysis.classifications.mixed,
                "human": analysis.classifications.human,
            ],
            "strategies": analysis.strategies,
            "capitalByOutcome": [
                "Yes": ["total": analysis.capitalByOutcome.Yes.total, "agent": analysis.capitalByOutcome.Yes.agent, "human": analysis.capitalByOutcome.Yes.human],
                "No": ["total": analysis.capitalByOutcome.No.total, "agent": analysis.capitalByOutcome.No.agent, "human": analysis.capitalByOutcome.No.human],
            ],
            "topHolders": analysis.topHolders.map { h in
                [
                    "address": h.address,
                    "pseudonym": h.pseudonym,
                    "side": h.side,
                    "positionSize": h.positionSize,
                    "classification": h.classification,
                    "strategy": ["label": h.strategy.label, "confidence": h.strategy.confidence],
                ] as [String: Any]
            },
            "smartMoneyDirection": analysis.smartMoneyDirection,
            "smartMoneyPct": analysis.smartMoneyPct,
            "redFlags": analysis.redFlags,
            "signalHash": analysis.signalHash,
        ]

        let marketDict: [String: Any] = [
            "question": market.question,
            "yesPrice": market.yesPrice ?? 0,
            "noPrice": market.noPrice ?? 0,
            "volume": market.volume ?? 0,
            "endDate": market.endDate ?? "",
        ]

        let body: [String: Any] = [
            "analysis": analysisDict,
            "market": marketDict,
            "language": language,
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)

        let contentType = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""

        if contentType.contains("text/event-stream") {
            // Parse SSE: extract text from data: {"text": "..."} lines
            guard let raw = String(data: data, encoding: .utf8) else { return ["> Analysis unavailable."] }
            var fullText = ""
            for line in raw.components(separatedBy: "\n") where line.hasPrefix("data: ") {
                let payload = String(line.dropFirst(6))
                if payload == "[DONE]" { break }
                if let jsonData = payload.data(using: .utf8),
                   let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let text = parsed["text"] as? String {
                    fullText += text
                }
            }
            return fullText.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        } else {
            // JSON fallback
            let decoded = try JSONDecoder().decode(ExplainFallbackResponse.self, from: data)
            return decoded.fallback ?? ["> Analysis unavailable."]
        }
    }

    /// Record a bet placement
    public func recordBet(
        marketSlug: String,
        side: String,
        amount: String,
        walletAddress: String,
        txHash: String
    ) async throws -> BetConfirmation {
        let url = URL(string: "\(betwhisperURL)/api/bet")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "marketSlug": marketSlug,
            "side": side,
            "amount": amount,
            "walletAddress": walletAddress,
            "txHash": txHash
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(BetConfirmation.self, from: data)
    }

    /// Execute a real Polymarket CLOB bet via backend
    public func executeClobBet(
        conditionId: String,
        outcomeIndex: Int,
        amountUSD: Double,
        signalHash: String,
        marketSlug: String,
        monadTxHash: String?,
        monPriceUSD: Double? = nil
    ) async throws -> ClobExecuteResult {
        let url = URL(string: "\(betwhisperURL)/api/bet/execute")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var body: [String: Any] = [
            "conditionId": conditionId,
            "outcomeIndex": outcomeIndex,
            "amountUSD": amountUSD,
            "signalHash": signalHash,
            "marketSlug": marketSlug
        ]
        if let monadTx = monadTxHash {
            body["monadTxHash"] = monadTx
        }
        if let price = monPriceUSD {
            body["monPriceUSD"] = price
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(ClobExecuteResult.self, from: data)
    }

    // MARK: - Groups API

    /// Check AI Gate eligibility
    public func checkGroupEligibility(wallet: String) async throws -> GroupEligibility {
        let url = URL(string: "\(betwhisperURL)/api/groups/check?wallet=\(wallet.lowercased())")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(GroupEligibility.self, from: data)
    }

    /// List groups for a wallet
    public func listGroups(wallet: String) async throws -> [GroupInfo] {
        let url = URL(string: "\(betwhisperURL)/api/groups?wallet=\(wallet.lowercased())")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode([GroupInfo].self, from: data)
    }

    /// Create a group
    public func createGroup(name: String, mode: String, creatorWallet: String) async throws -> GroupInfo {
        let url = URL(string: "\(betwhisperURL)/api/groups")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["name": name, "mode": mode, "creator_wallet": creatorWallet.lowercased()]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(GroupInfo.self, from: data)
    }

    /// Join a group by invite code
    public func joinGroup(code: String, wallet: String) async throws -> JoinGroupResult {
        let url = URL(string: "\(betwhisperURL)/api/groups/\(code)/join")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = ["wallet_address": wallet.lowercased()]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 409 {
            throw APIError.serverError("Already a member")
        }
        if http.statusCode >= 400 {
            if let err = try? JSONDecoder().decode([String: String].self, from: data), let msg = err["error"] {
                throw APIError.serverError(msg)
            }
            throw APIError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(JoinGroupResult.self, from: data)
    }

    /// Get group detail by invite code
    public func getGroupDetail(code: String) async throws -> GroupDetail {
        let url = URL(string: "\(betwhisperURL)/api/groups/\(code)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(GroupDetail.self, from: data)
    }

    /// Get group leaderboard
    public func getGroupLeaderboard(code: String) async throws -> GroupLeaderboard {
        let url = URL(string: "\(betwhisperURL)/api/groups/\(code)/leaderboard")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, _) = try await session.data(for: request)
        return try JSONDecoder().decode(GroupLeaderboard.self, from: data)
    }

    // MARK: - Order History

    /// Get user's order history (transaction history)
    /// Uses X-Platform: ios header instead of JWT (Face ID gated on device)
    public func getOrderHistory(wallet: String) async throws -> OrderHistoryResponse {
        let url = URL(string: "\(betwhisperURL)/api/user/history?wallet=\(wallet.lowercased())")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios", forHTTPHeaderField: "X-Platform")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode >= 400 {
            throw APIError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(OrderHistoryResponse.self, from: data)
    }

    // MARK: - Health Check

    /// Check AI health
    public func checkAIHealth() async throws -> APIResponse<HealthResponse> {
        return try await get("/voiceswap/ai/health")
    }

    /// Check overall service health
    public func checkHealth() async throws -> APIResponse<HealthResponse> {
        return try await get("/health")
    }

    // MARK: - Private HTTP Methods

    private func get<T: Decodable>(_ path: String) async throws -> APIResponse<T> {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        return try await execute(request)
    }

    private func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> APIResponse<T> {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await execute(request)
    }

    private func put<T: Decodable>(_ path: String, body: [String: Any]) async throws -> APIResponse<T> {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await execute(request)
    }

    private func execute<T: Decodable>(_ request: URLRequest) async throws -> APIResponse<T> {
        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            // Log response for debugging
            let url = request.url?.absoluteString ?? "unknown"
            print("[VoiceSwapAPI] Response from \(url): HTTP \(httpResponse.statusCode)")

            if httpResponse.statusCode >= 400 {
                // Log error response body
                if let bodyString = String(data: data, encoding: .utf8) {
                    print("[VoiceSwapAPI] Error body: \(bodyString.prefix(500))")
                }

                // Try to decode error response
                if let errorResponse = try? JSONDecoder().decode(APIResponse<T>.self, from: data) {
                    throw APIError.serverError(errorResponse.error ?? "Unknown error")
                }
                throw APIError.httpError(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            do {
                return try decoder.decode(APIResponse<T>.self, from: data)
            } catch let decodingError {
                // Log decoding error with response body for debugging
                if let bodyString = String(data: data, encoding: .utf8) {
                    print("[VoiceSwapAPI] Decoding failed for: \(bodyString.prefix(1000))")
                }
                print("[VoiceSwapAPI] Decoding error: \(decodingError)")
                throw APIError.decodingError(decodingError)
            }

        } catch let error as APIError {
            throw error
        } catch {
            print("[VoiceSwapAPI] Network error: \(error)")
            throw APIError.networkError(error)
        }
    }
}

// MARK: - API Errors

public enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case serverError(String)
    case networkError(Error)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let message):
            return "Server error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        }
    }
}
