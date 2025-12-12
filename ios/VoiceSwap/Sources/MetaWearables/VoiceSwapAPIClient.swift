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
    public let merchantName: String?
}

public struct WalletBalances: Decodable {
    public let address: String
    public let chainId: Int
    public let nativeETH: TokenBalance
    public let tokens: [TokenBalance]
    public let totalUSDC: String
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
    public let tokenSymbol: String
    public let tokenAddress: String
    public let maxAmount: String
    public let estimatedUSDC: String
}

public struct ExecutePaymentResponse: Decodable {
    public let action: String
    public let token: String?
    public let amount: String?
    public let to: String?
    public let from: String?
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

public struct PaymentSession: Decodable {
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

// MARK: - API Client

public actor VoiceSwapAPIClient {

    // MARK: - Singleton
    public static let shared = VoiceSwapAPIClient()

    // MARK: - Properties
    private let baseURL: String
    private let session: URLSession

    // MARK: - Initialization

    private init() {
        self.baseURL = ProcessInfo.processInfo.environment["VOICESWAP_API_URL"] ?? "http://localhost:4021"

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
    public func extractPaymentDetails(transcript: String) async throws -> APIResponse<[String: Any]> {
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

    /// Execute payment
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
        session: PaymentSession,
        newState: String,
        updates: [String: Any]?
    ) async throws -> APIResponse<[String: Any]> {
        var body: [String: Any] = [
            "session": session,
            "newState": newState
        ]

        if let updates = updates {
            body["updates"] = updates
        }

        return try await put("/voiceswap/session/\(sessionId)", body: body)
    }

    // MARK: - Health Check

    /// Check AI health
    public func checkAIHealth() async throws -> APIResponse<[String: Any]> {
        return try await get("/voiceswap/ai/health")
    }

    /// Check overall service health
    public func checkHealth() async throws -> APIResponse<[String: Any]> {
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

            if httpResponse.statusCode >= 400 {
                // Try to decode error response
                if let errorResponse = try? JSONDecoder().decode(APIResponse<T>.self, from: data) {
                    throw APIError.serverError(errorResponse.error ?? "Unknown error")
                }
                throw APIError.httpError(httpResponse.statusCode)
            }

            let decoder = JSONDecoder()
            return try decoder.decode(APIResponse<T>.self, from: data)

        } catch let error as APIError {
            throw error
        } catch {
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
