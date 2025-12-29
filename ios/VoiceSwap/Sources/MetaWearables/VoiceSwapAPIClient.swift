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
    public let ethBalance: String?
    public let merchantName: String?
}

public struct WalletBalances: Decodable {
    public let address: String
    public let chainId: Int
    public let nativeETH: TokenBalance
    public let tokens: [TokenBalance]
    public let totalUSDC: String
    public let totalUSD: String
    public let ethPriceUSD: Double
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
    public let hasEnoughETH: Bool
    public let hasEnoughWETH: Bool
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

public struct PrepareTransactionResponse: Decodable {
    public let transaction: TransactionData
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

// MARK: - API Client

public actor VoiceSwapAPIClient {

    // MARK: - Singleton
    public static let shared = VoiceSwapAPIClient()

    // MARK: - Properties
    private let baseURL: String
    private let session: URLSession

    // MARK: - Initialization

    private init() {
        // Use production API by default, or override with environment variable for local development
        // To test locally: set VOICESWAP_API_URL environment variable (e.g., "http://192.168.1.X:4021")
        #if DEBUG
        self.baseURL = ProcessInfo.processInfo.environment["VOICESWAP_API_URL"] ?? "https://voiceswap.vercel.app"
        #else
        self.baseURL = "https://voiceswap.vercel.app"
        #endif

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)

        print("[VoiceSwapAPI] Initialized with base URL: \(baseURL)")
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
