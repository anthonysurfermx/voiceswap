/**
 * BetWhisperPINView.swift
 * BetWhisper - PIN entry/setup screen
 *
 * Uses web APIs:
 *   GET  /api/user/pin/check?wallet=  → { hasPin }
 *   POST /api/user/pin/setup          → { success }
 *   POST /api/user/pin/verify         → { verified, token }
 *
 * Flow:
 *   - App launch → check if wallet has PIN
 *   - No PIN → create 4-digit PIN (enter + confirm)
 *   - Has PIN → enter PIN to unlock
 */

import SwiftUI

struct BetWhisperPINView: View {
    @Binding var isUnlocked: Bool
    let walletAddress: String

    @State private var mode: PINMode = .checking
    @State private var pin: String = ""
    @State private var confirmPin: String = ""
    @State private var isConfirmStep = false
    @State private var error: String? = nil
    @State private var isLoading = false
    @State private var attemptsRemaining: Int = 5
    @State private var shake = false

    private let pinLength = 4

    enum PINMode {
        case checking   // Loading: checking if PIN exists
        case create     // First time: create a new PIN
        case verify     // Returning: enter existing PIN
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // Logo / Title
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 40))
                        .foregroundColor(.white.opacity(0.6))

                    Text(titleText)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    Text(subtitleText)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }

                Spacer().frame(height: 48)

                // PIN dots
                HStack(spacing: 20) {
                    ForEach(0..<pinLength, id: \.self) { index in
                        Circle()
                            .fill(index < currentPin.count ? Color.white : Color.white.opacity(0.15))
                            .frame(width: 16, height: 16)
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                }
                .offset(x: shake ? -10 : 0)
                .animation(shake ? .default.repeatCount(3, autoreverses: true).speed(6) : .default, value: shake)

                // Error message
                if let error = error {
                    Text(error)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color(hex: "EF4444"))
                        .padding(.top, 16)
                }

                Spacer().frame(height: 48)

                // Number pad
                if mode != .checking {
                    numberPad
                }

                if isLoading {
                    ProgressView()
                        .tint(.white.opacity(0.6))
                        .padding(.top, 24)
                }

                Spacer()

                // Version
                Text("BetWhisper")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.1))
                    .padding(.bottom, 32)
            }
            .padding(.horizontal, 24)
        }
        .task {
            await checkPINStatus()
        }
    }

    // MARK: - Computed

    private var currentPin: String {
        isConfirmStep ? confirmPin : pin
    }

    private var titleText: String {
        switch mode {
        case .checking: return "Loading..."
        case .create:
            return isConfirmStep ? "Confirm PIN" : "Create PIN"
        case .verify: return "Enter PIN"
        }
    }

    private var subtitleText: String {
        switch mode {
        case .checking: return ""
        case .create:
            return isConfirmStep ? "Enter the same 4-digit PIN again" : "Choose a 4-digit PIN to secure your wallet"
        case .verify: return "Enter your 4-digit PIN to continue"
        }
    }

    // MARK: - Number Pad

    private var numberPad: some View {
        VStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 24) {
                    ForEach(1...3, id: \.self) { col in
                        let number = row * 3 + col
                        numberButton(String(number))
                    }
                }
            }
            // Bottom row: empty, 0, delete
            HStack(spacing: 24) {
                Color.clear.frame(width: 72, height: 72)
                numberButton("0")
                deleteButton
            }
        }
    }

    private func numberButton(_ digit: String) -> some View {
        Button {
            addDigit(digit)
        } label: {
            Text(digit)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.white)
                .frame(width: 72, height: 72)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .disabled(isLoading)
    }

    private var deleteButton: some View {
        Button {
            removeDigit()
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 20))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 72, height: 72)
        }
        .disabled(isLoading)
    }

    // MARK: - Input Logic

    private func addDigit(_ digit: String) {
        error = nil
        if isConfirmStep {
            guard confirmPin.count < pinLength else { return }
            confirmPin += digit
            if confirmPin.count == pinLength {
                Task { await handleConfirmComplete() }
            }
        } else {
            guard pin.count < pinLength else { return }
            pin += digit
            if pin.count == pinLength {
                Task { await handlePinComplete() }
            }
        }
    }

    private func removeDigit() {
        if isConfirmStep {
            guard !confirmPin.isEmpty else { return }
            confirmPin.removeLast()
        } else {
            guard !pin.isEmpty else { return }
            pin.removeLast()
        }
    }

    // MARK: - API Calls

    private func checkPINStatus() async {
        guard let url = URL(string: "https://betwhisper.ai/api/user/pin/check?wallet=\(walletAddress)") else {
            mode = .create
            return
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hasPin = json["hasPin"] as? Bool {
                mode = hasPin ? .verify : .create
            } else {
                mode = .create
            }
        } catch {
            mode = .create
        }
    }

    private func handlePinComplete() async {
        switch mode {
        case .create:
            // Move to confirm step
            isConfirmStep = true
        case .verify:
            await verifyPIN()
        case .checking:
            break
        }
    }

    private func handleConfirmComplete() async {
        if pin == confirmPin {
            await setupPIN()
        } else {
            shakeAndReset()
            error = "PINs don't match. Try again."
            confirmPin = ""
            isConfirmStep = false
            pin = ""
        }
    }

    private func setupPIN() async {
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "https://betwhisper.ai/api/user/pin/setup") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "wallet": walletAddress,
            "pin": pin,
        ])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let success = json["success"] as? Bool, success {
                // PIN created — now verify to get token
                await verifyPIN()
            } else {
                error = "Failed to create PIN"
                shakeAndReset()
            }
        } catch {
            self.error = "Network error"
            shakeAndReset()
        }
    }

    private func verifyPIN() async {
        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "https://betwhisper.ai/api/user/pin/verify") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "wallet": walletAddress,
            "pin": pin,
        ])

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let verified = json["verified"] as? Bool, verified {
                    // Store JWT token for authenticated API calls
                    if let token = json["token"] as? String {
                        UserDefaults.standard.set(token, forKey: "betwhisper_auth_token")
                    }
                    isUnlocked = true
                } else {
                    if let remaining = json["attemptsRemaining"] as? Int {
                        attemptsRemaining = remaining
                        error = "Wrong PIN. \(remaining) attempts left."
                    } else if let locked = json["locked"] as? Bool, locked {
                        error = "Too many attempts. Try later."
                    } else {
                        error = "Wrong PIN"
                    }
                    shakeAndReset()
                }
            }
        } catch {
            self.error = "Network error"
            shakeAndReset()
        }
    }

    private func shakeAndReset() {
        shake = true
        pin = ""
        confirmPin = ""
        isConfirmStep = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            shake = false
        }
    }
}
