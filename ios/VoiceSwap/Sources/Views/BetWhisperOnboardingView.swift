/**
 * BetWhisperOnboardingView.swift
 * BetWhisper - Assistant naming + interest categories
 *
 * First-time flow:
 * 1. Name your assistant (suggestions + custom input)
 * 2. Pick 3 categories of bets you're interested in
 * 3. Continue to main app
 */

import SwiftUI

// MARK: - Bet Categories

struct BetCategory: Identifiable {
    let id: String
    let name: String
    let icon: String
    let query: String // Polymarket search query
}

let ALL_CATEGORIES: [BetCategory] = [
    BetCategory(id: "crypto",   name: "Crypto",      icon: "bitcoinsign.circle",  query: "bitcoin ethereum crypto"),
    BetCategory(id: "nba",      name: "NBA",         icon: "basketball",          query: "nba basketball"),
    BetCategory(id: "nfl",      name: "NFL",         icon: "football",            query: "nfl football"),
    BetCategory(id: "soccer",   name: "Soccer",      icon: "soccerball",          query: "soccer football premier league"),
    BetCategory(id: "politics", name: "Politics",    icon: "building.columns",    query: "president election politics"),
    BetCategory(id: "ai",       name: "AI",          icon: "brain.head.profile",  query: "artificial intelligence ai model"),
    BetCategory(id: "finance",  name: "Finance",     icon: "chart.line.uptrend.xyaxis", query: "fed rates stock market"),
    BetCategory(id: "mma",      name: "MMA / UFC",   icon: "figure.boxing",       query: "ufc mma fight"),
    BetCategory(id: "baseball", name: "MLB",         icon: "baseball",            query: "mlb baseball"),
    BetCategory(id: "esports",  name: "Esports",     icon: "gamecontroller",      query: "esports league of legends"),
    BetCategory(id: "world",    name: "World Events", icon: "globe",              query: "world event global"),
    BetCategory(id: "culture",  name: "Culture",     icon: "star",                query: "oscars grammys entertainment"),
]

// MARK: - Onboarding View

struct BetWhisperOnboardingView: View {
    @Binding var isComplete: Bool

    @State private var step: Int = 1 // 1 = name, 2 = categories
    @State private var assistantName: String = ""
    @State private var selectedCategories: Set<String> = []
    @FocusState private var nameFieldFocused: Bool

    private let nameSuggestions = [
        "Don Fede", "Buddy", "Seu Jorge", "\u{8001}\u{738B}",
        "Coach", "El Profe", "La G\u{FC}era", "Mate"
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 0)
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 18, height: 18)
                                .overlay(
                                    Text("BW")
                                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.6))
                                )
                            Text("BetWhisper")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.white)
                        }
                    }
                    Spacer()
                    Text("Step \(step) of 2")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)

                if step == 1 {
                    nameStep
                } else {
                    categoriesStep
                }

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Step 1: Name

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Name your assistant")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)

            Text("This is who you'll talk to. Pick a name that feels natural.")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 32)

            // Text field
            TextField("", text: $assistantName, prompt: Text("Type a name...").foregroundColor(.white.opacity(0.2)))
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    Rectangle()
                        .fill(Color.white.opacity(0.05))
                        .overlay(
                            Rectangle()
                                .stroke(Color.white.opacity(nameFieldFocused ? 0.3 : 0.1), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 24)
                .focused($nameFieldFocused)
                .onAppear { nameFieldFocused = true }

            // Suggestions
            Text("SUGGESTIONS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.25))
                .tracking(1.5)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 10)

            LazyVGrid(columns: [
                GridItem(.flexible()), GridItem(.flexible()),
                GridItem(.flexible()), GridItem(.flexible())
            ], spacing: 8) {
                ForEach(nameSuggestions, id: \.self) { name in
                    Button {
                        assistantName = name
                    } label: {
                        Text(name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(assistantName == name ? .black : .white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Rectangle()
                                    .fill(assistantName == name ? Color.white : Color.white.opacity(0.05))
                            )
                            .overlay(
                                Rectangle()
                                    .stroke(Color.white.opacity(assistantName == name ? 0 : 0.1), lineWidth: 1)
                            )
                    }
                }
            }
            .padding(.horizontal, 24)

            Spacer()

            // Continue button
            Button {
                guard !assistantName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                withAnimation(.easeInOut(duration: 0.3)) {
                    step = 2
                }
            } label: {
                Text("CONTINUE")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        Rectangle()
                            .fill(assistantName.trimmingCharacters(in: .whitespaces).isEmpty
                                  ? Color.white.opacity(0.2)
                                  : Color.white)
                    )
            }
            .disabled(assistantName.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Step 2: Categories

    private var categoriesStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("What do you bet on?")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 24)

            Text("Pick 3 categories. \(assistantName) will show you markets that match.")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 8)

            // Selection count
            HStack(spacing: 4) {
                Text("\(selectedCategories.count)")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(selectedCategories.count == 3 ? Color(hex: "10B981") : .white)
                Text("/ 3 selected")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)

            // Category grid
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
                ], spacing: 8) {
                    ForEach(ALL_CATEGORIES) { cat in
                        let isSelected = selectedCategories.contains(cat.id)
                        let canSelect = selectedCategories.count < 3 || isSelected

                        Button {
                            if isSelected {
                                selectedCategories.remove(cat.id)
                            } else if canSelect {
                                selectedCategories.insert(cat.id)
                            }
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: cat.icon)
                                    .font(.system(size: 20))
                                    .foregroundColor(isSelected ? .black : .white.opacity(canSelect ? 0.6 : 0.2))
                                Text(cat.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(isSelected ? .black : .white.opacity(canSelect ? 0.6 : 0.2))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                Rectangle()
                                    .fill(isSelected ? Color.white : Color.white.opacity(0.03))
                            )
                            .overlay(
                                Rectangle()
                                    .stroke(isSelected ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
                            )
                        }
                        .disabled(!canSelect && !isSelected)
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            // Start button
            Button {
                savePreferences()
                withAnimation(.easeInOut(duration: 0.3)) {
                    isComplete = true
                }
            } label: {
                HStack(spacing: 8) {
                    Text("START WHISPERING")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .tracking(2)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    Rectangle()
                        .fill(selectedCategories.count >= 3
                              ? Color.white
                              : Color.white.opacity(0.2))
                )
            }
            .disabled(selectedCategories.count < 3)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Save

    private func savePreferences() {
        let name = assistantName.trimmingCharacters(in: .whitespaces)
        UserDefaults.standard.set(name, forKey: "betwhisper_assistant_name")
        UserDefaults.standard.set(Array(selectedCategories), forKey: "betwhisper_categories")
        UserDefaults.standard.set(true, forKey: "betwhisper_onboarded")

        // Auto-create wallet if not already restored from Keychain
        if !VoiceSwapWallet.shared.isCreated {
            try? VoiceSwapWallet.shared.create()
            print("[BetWhisper] Wallet auto-created: \(VoiceSwapWallet.shared.address)")
        }
    }
}
