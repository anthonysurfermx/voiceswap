import Foundation
import LocalAuthentication

// MARK: - Security Check Result

enum SecurityCheckResult {
    case allowed
    case dailyLimitExceeded(spent: Double, limit: Double)
    case newMerchantNeedsApproval(address: String)
    case faceIDRequired
}

// MARK: - Security Settings

@MainActor
class SecuritySettings: ObservableObject {

    static let shared = SecuritySettings()

    // MARK: - Face ID on App Launch

    @Published var faceIDOnLaunchEnabled: Bool {
        didSet { UserDefaults.standard.set(faceIDOnLaunchEnabled, forKey: "security_faceID_launch") }
    }

    @Published var isAppUnlocked: Bool = false

    func unlockApp() async {
        if !faceIDOnLaunchEnabled {
            isAppUnlocked = true
            return
        }
        let passed = await authenticateWithBiometrics()
        isAppUnlocked = passed
    }

    // MARK: - Face ID (every 3 transactions)

    @Published var faceIDEnabled: Bool {
        didSet { UserDefaults.standard.set(faceIDEnabled, forKey: "security_faceID_enabled") }
    }

    @Published var transactionCount: Int {
        didSet { UserDefaults.standard.set(transactionCount, forKey: "security_faceID_txCount") }
    }

    static let faceIDThreshold = 3

    // MARK: - Daily Limit

    @Published var dailyLimitEnabled: Bool {
        didSet { UserDefaults.standard.set(dailyLimitEnabled, forKey: "security_dailyLimit_enabled") }
    }

    @Published var dailyLimitAmount: Double {
        didSet { UserDefaults.standard.set(dailyLimitAmount, forKey: "security_dailyLimit_amount") }
    }

    @Published var dailySpentAmount: Double {
        didSet { UserDefaults.standard.set(dailySpentAmount, forKey: "security_dailySpent_amount") }
    }

    private var dailySpentDate: String {
        didSet { UserDefaults.standard.set(dailySpentDate, forKey: "security_dailySpent_date") }
    }

    // MARK: - Merchant Whitelist

    @Published var whitelistEnabled: Bool {
        didSet { UserDefaults.standard.set(whitelistEnabled, forKey: "security_whitelist_enabled") }
    }

    @Published var approvedMerchants: [String] {
        didSet {
            if let data = try? JSONEncoder().encode(approvedMerchants) {
                UserDefaults.standard.set(data, forKey: "security_approvedMerchants")
            }
        }
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults.standard

        // Face ID on launch — default enabled
        if defaults.object(forKey: "security_faceID_launch") == nil {
            defaults.set(true, forKey: "security_faceID_launch")
        }
        self.faceIDOnLaunchEnabled = defaults.bool(forKey: "security_faceID_launch")

        // Face ID every 3 tx — default enabled
        if defaults.object(forKey: "security_faceID_enabled") == nil {
            defaults.set(true, forKey: "security_faceID_enabled")
        }
        self.faceIDEnabled = defaults.bool(forKey: "security_faceID_enabled")
        self.transactionCount = defaults.integer(forKey: "security_faceID_txCount")

        // Daily limit — default enabled, $250
        if defaults.object(forKey: "security_dailyLimit_enabled") == nil {
            defaults.set(true, forKey: "security_dailyLimit_enabled")
        }
        self.dailyLimitEnabled = defaults.bool(forKey: "security_dailyLimit_enabled")

        let savedLimit = defaults.double(forKey: "security_dailyLimit_amount")
        self.dailyLimitAmount = savedLimit > 0 ? savedLimit : 250.0

        self.dailySpentAmount = defaults.double(forKey: "security_dailySpent_amount")
        self.dailySpentDate = defaults.string(forKey: "security_dailySpent_date") ?? ""

        // Whitelist — default enabled
        if defaults.object(forKey: "security_whitelist_enabled") == nil {
            defaults.set(true, forKey: "security_whitelist_enabled")
        }
        self.whitelistEnabled = defaults.bool(forKey: "security_whitelist_enabled")

        if let data = defaults.data(forKey: "security_approvedMerchants"),
           let merchants = try? JSONDecoder().decode([String].self, from: data) {
            self.approvedMerchants = merchants
        } else {
            self.approvedMerchants = []
        }

        // Reset daily spend if it's a new day
        resetDailySpendIfNeeded()
    }

    // MARK: - Security Checks

    func performSecurityChecks(amount: Double, merchantWallet: String) async -> SecurityCheckResult {
        // Check 1: Daily limit
        if dailyLimitEnabled {
            resetDailySpendIfNeeded()
            if dailySpentAmount + amount > dailyLimitAmount {
                return .dailyLimitExceeded(spent: dailySpentAmount, limit: dailyLimitAmount)
            }
        }

        // Check 2: Merchant whitelist
        if whitelistEnabled && !isMerchantApproved(merchantWallet) {
            return .newMerchantNeedsApproval(address: merchantWallet)
        }

        // Check 3: Face ID every N transactions
        if faceIDEnabled && transactionCount >= Self.faceIDThreshold {
            return .faceIDRequired
        }

        return .allowed
    }

    // MARK: - Biometrics

    func authenticateWithBiometrics() async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            print("[Security] Biometrics unavailable: \(error?.localizedDescription ?? "unknown")")
            // If biometrics not available, allow (don't block payments on devices without Face ID)
            return true
        }

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Confirm payment with Face ID"
            )
        } catch {
            print("[Security] Biometric auth failed: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Payment Recording

    func recordSuccessfulPayment(amount: Double) {
        transactionCount += 1
        resetDailySpendIfNeeded()
        dailySpentAmount += amount
        print("[Security] Payment recorded: $\(String(format: "%.2f", amount)) | Tx count: \(transactionCount)/\(Self.faceIDThreshold) | Daily: $\(String(format: "%.2f", dailySpentAmount))/$\(String(format: "%.0f", dailyLimitAmount))")
    }

    func resetTransactionCounter() {
        transactionCount = 0
    }

    // MARK: - Merchant Whitelist

    func approveMerchant(_ address: String) {
        let normalized = address.lowercased()
        guard !approvedMerchants.contains(normalized) else { return }
        approvedMerchants.append(normalized)
        print("[Security] Merchant approved: \(normalized)")
    }

    func removeMerchant(_ address: String) {
        approvedMerchants.removeAll { $0 == address.lowercased() }
    }

    func isMerchantApproved(_ address: String) -> Bool {
        approvedMerchants.contains(address.lowercased())
    }

    // MARK: - Daily Reset

    private func resetDailySpendIfNeeded() {
        let today = Self.todayString()
        if dailySpentDate != today {
            dailySpentAmount = 0
            dailySpentDate = today
        }
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
