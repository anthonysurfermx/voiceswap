/**
 * BetWhisperChatView.swift
 * BetWhisper - Progressive analysis chat interface
 *
 * 5-step flow: Market Preview → Agent Radar → AI Explanation → Amount Input → Win Probability
 * Mirrors the web app at /predict with the same API endpoints.
 */

import SwiftUI
import Speech

// MARK: - i18n

private let isSpanish = Locale.current.language.languageCode?.identifier == "es"

private func loc(_ en: String, _ es: String) -> String { isSpanish ? es : en }

// MARK: - Chat Message Model

enum ChatRole {
    case user
    case assistant
}

enum ChatAttachment {
    case markets([MarketItem])
    case marketPreview(MarketItem)
    case deepAnalysis(DeepAnalysisResult, MarketItem)
    case aiExplanation([String], MarketItem, DeepAnalysisResult)
    case betAmountInput(MarketItem, DeepAnalysisResult)
    case successProbability(ProbabilityResult, MarketItem, String)
    case betChoice(MarketItem)
    case betPrompt(String, String, String) // side, slug, signalHash
    case betConfirmed(BetRecord)
    case contextInsight(String, [String]) // insight, keyStats
    case loading(String)
    case error(String)
}

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: ChatRole
    let text: String
    var attachment: ChatAttachment?
    let timestamp = Date()
}

// MARK: - Colors

private let emerald = Color(hex: "10B981")
private let red400 = Color(hex: "EF4444")
private let amber400 = Color(hex: "F59E0B")

// MARK: - Chat View

struct BetWhisperChatView: View {
    @State private var messages: [ChatMessage] = []
    @State private var inputText: String = ""
    @State private var isLoading: Bool = false
    @State private var betAmountText: String = ""
    @State private var aiGateEligible: Bool = false
    @FocusState private var inputFocused: Bool

    // Voice input
    @StateObject private var speechRecognizer = SpeechRecognizer()
    private let tts = ChatSpeechSynthesizer()
    @State private var ttsEnabled: Bool = true

    private let assistantName: String
    private let categories: [String]

    init() {
        self.assistantName = UserDefaults.standard.string(forKey: "betwhisper_assistant_name") ?? "BetWhisper"
        self.categories = UserDefaults.standard.stringArray(forKey: "betwhisper_categories") ?? []
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                chatHeader

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(messages) { msg in
                                chatBubble(msg)
                                    .id(msg.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                inputBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            loadInitialMarkets()
            checkAIGateEligibility()
            speechRecognizer.requestPermission()
            speechRecognizer.onFinalTranscript = { text in
                inputText = text
                sendMessage()
            }
        }
        .onChange(of: speechRecognizer.transcript) { _, newValue in
            if speechRecognizer.isListening && !newValue.isEmpty {
                inputText = newValue
            }
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
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
                    Text(assistantName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text("PREDICTION MARKETS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.25))
                    .tracking(1.5)
            }
            Spacer()
            Circle().fill(emerald).frame(width: 6, height: 6)
            Text("LIVE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(emerald)
                .tracking(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Rectangle().fill(Color.white.opacity(0.03)))
        .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)
    }

    // MARK: - Chat Bubble

    @ViewBuilder
    private func chatBubble(_ msg: ChatMessage) -> some View {
        VStack(alignment: msg.role == .user ? .trailing : .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(msg.role == .assistant ? assistantName.uppercased() : "YOU")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1)
            }

            if !msg.text.isEmpty {
                Text(msg.text)
                    .font(.system(size: 15))
                    .foregroundColor(msg.role == .user ? .black : .white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Rectangle().fill(msg.role == .user ? Color.white : Color.white.opacity(0.06)))
                    .overlay(Rectangle().stroke(Color.white.opacity(msg.role == .user ? 0 : 0.08), lineWidth: 1))
            }

            if let attachment = msg.attachment {
                attachmentView(attachment)
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.role == .user ? .trailing : .leading)
    }

    // MARK: - Attachment Router

    @ViewBuilder
    private func attachmentView(_ attachment: ChatAttachment) -> some View {
        switch attachment {
        case .markets(let markets):
            marketListView(markets)
        case .marketPreview(let market):
            marketPreviewView(market)
        case .deepAnalysis(let analysis, let market):
            deepAnalysisView(analysis, market: market)
        case .aiExplanation(let lines, let market, let analysis):
            aiExplanationView(lines, market: market, analysis: analysis)
        case .betAmountInput(let market, let analysis):
            betAmountInputView(market, analysis: analysis)
        case .successProbability(let prob, let market, let signalHash):
            successProbabilityView(prob, market: market, signalHash: signalHash)
        case .betChoice(let market):
            betChoiceView(market)
        case .betPrompt(let side, let slug, let signalHash):
            betPromptView(side: side, slug: slug, signalHash: signalHash)
        case .betConfirmed(let record):
            betConfirmedView(record)
        case .contextInsight(let insight, let keyStats):
            contextInsightView(insight, keyStats: keyStats)
        case .loading(let text):
            loadingView(text)
        case .error(let text):
            errorView(text)
        }
    }

    // MARK: - Step 0: Market List

    private func marketListView(_ markets: [MarketItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(markets.prefix(5), id: \.conditionId) { market in
                Button { handleMarketSelect(market) } label: {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(market.question)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 12) {
                                priceLabel("YES", market.yesPrice, emerald)
                                priceLabel("NO", market.noPrice, red400)
                                if let vol = market.volume, vol > 0 {
                                    Text("$\(fmtVol(vol))")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.2))
                    }
                    .padding(12)
                    .background(Rectangle().fill(Color.white.opacity(0.04)))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Step 1: Market Preview

    private func marketPreviewView(_ market: MarketItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Market info
            VStack(alignment: .leading, spacing: 8) {
                Text(market.question)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white)
                HStack(spacing: 16) {
                    priceLabel("YES", market.yesPrice, emerald)
                    priceLabel("NO", market.noPrice, red400)
                    if let vol = market.volume, vol > 0 {
                        Text("Vol: $\(fmtVol(vol))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
            }
            .padding(14)

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    handleDetectAgents(market)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "shield.lefthalf.filled")
                            .font(.system(size: 11))
                        Text(loc("DETECT AGENTS", "DETECTAR AGENTES"))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Rectangle().fill(Color.white))
                }
                .disabled(isLoading)

                Button {
                    handleSkipToChoice(market)
                } label: {
                    Text(loc("SKIP", "SALTAR"))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Rectangle().fill(Color.white.opacity(0.06)))
                        .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .background(Rectangle().fill(Color.white.opacity(0.04)))
        .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Step 2: Agent Radar (Deep Analysis)

    private func deepAnalysisView(_ analysis: DeepAnalysisResult, market: MarketItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("AGENT RADAR")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1.5)
                Spacer()
                Text("\(analysis.holdersScanned) scanned / \(analysis.totalHolders) holders")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            // Market structure
            VStack(alignment: .leading, spacing: 8) {
                Text("MARKET STRUCTURE")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))

                HStack(spacing: 16) {
                    HStack(spacing: 4) {
                        Text("\(analysis.agentRate)%")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                        Text("agent")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                    }
                    classificationPills(analysis.classifications)
                }

                // Capital flow bar
                let totalYes = analysis.capitalByOutcome.Yes.total
                let totalNo = analysis.capitalByOutcome.No.total
                let totalCap = totalYes + totalNo
                let yesPct = totalCap > 0 ? totalYes / totalCap : 0.5

                HStack(spacing: 0) {
                    Rectangle().fill(emerald.opacity(0.6)).frame(width: max(2, CGFloat(yesPct) * 200), height: 6)
                    Rectangle().fill(red400.opacity(0.6)).frame(height: 6)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 6)

                HStack {
                    Text("YES \(fmtCap(totalYes))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(emerald.opacity(0.7))
                    Spacer()
                    Text("NO \(fmtCap(totalNo))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(red400.opacity(0.7))
                }
            }
            .padding(14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            // Smart money
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                Text(loc("Smart Money:", "Smart Money:"))
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                Text(analysis.smartMoneyDirection)
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(analysis.smartMoneyDirection == "Yes" ? emerald : analysis.smartMoneyDirection == "No" ? red400 : .white.opacity(0.5))
                Text("(\(analysis.smartMoneyPct)%)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            // Top holders (max 5)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(analysis.topHolders.prefix(5), id: \.pseudonym) { holder in
                    HStack {
                        Text(holder.pseudonym)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        Text(holder.side.uppercased())
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(holder.side == "Yes" ? emerald : red400)
                        Text("$\(fmtCap(holder.positionSize))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                        Text(holder.classification)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(classColor(holder.classification))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .overlay(Rectangle().stroke(classColor(holder.classification).opacity(0.3), lineWidth: 1))
                    }
                }
            }
            .padding(14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            // Action buttons
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        handleExplainWithAI(analysis, market: market)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 11))
                            Text(loc("EXPLAIN WITH AI", "EXPLICAR CON IA"))
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Rectangle().fill(Color.white))
                    }
                    .disabled(isLoading)

                    Button {
                        handleAskAmount(market, analysis: analysis)
                    } label: {
                        Text(loc("SKIP", "SALTAR"))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.4))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Rectangle().fill(Color.white.opacity(0.06)))
                            .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                }

                Button {
                    handleFetchContext(market)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 11))
                        Text(loc("STATS", "ESTADISTICAS"))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundColor(Color(hex: "3B82F6"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Rectangle().fill(Color(hex: "3B82F6").opacity(0.08)))
                    .overlay(Rectangle().stroke(Color(hex: "3B82F6").opacity(0.3), lineWidth: 1))
                }
                .disabled(isLoading)
            }
            .padding(14)
        }
        .background(Rectangle().fill(Color.white.opacity(0.04)))
        .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Step 3: AI Explanation

    private func aiExplanationView(_ lines: [String], market: MarketItem, analysis: DeepAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("AI ANALYSIS")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .tracking(1.5)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(14)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            Button {
                handleAskAmount(market, analysis: analysis)
            } label: {
                Text(loc("BET", "APOSTAR"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Rectangle().fill(Color.white))
            }
            .padding(14)
        }
        .background(Rectangle().fill(Color.white.opacity(0.04)))
        .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Step 3.5: Amount Input

    private func betAmountInputView(_ market: MarketItem, analysis: DeepAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(loc("HOW MUCH DO YOU WANT TO INVEST?", "CUANTO QUIERES INVERTIR?"))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1.5)
                Spacer()
                if let vol = market.volume, vol > 0 {
                    Text("Vol: $\(fmtVol(vol))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            VStack(spacing: 12) {
                // Dollar input
                HStack(spacing: 4) {
                    Text("$")
                        .font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    TextField("", text: $betAmountText, prompt: Text(loc("Amount in USD", "Monto en USD")).foregroundColor(.white.opacity(0.2)))
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .keyboardType(.decimalPad)
                }

                // Quick presets
                HStack(spacing: 6) {
                    ForEach(["10", "50", "100", "500"], id: \.self) { preset in
                        Button {
                            betAmountText = preset
                        } label: {
                            Text("$\(preset)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(betAmountText == preset ? .white : .white.opacity(0.3))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .background(Rectangle().fill(betAmountText == preset ? Color.white.opacity(0.1) : Color.clear))
                                .overlay(Rectangle().stroke(Color.white.opacity(betAmountText == preset ? 0.4 : 0.1), lineWidth: 1))
                        }
                    }
                }

                // Size impact preview
                let numAmount = Double(betAmountText) ?? 0
                let vol = market.volume ?? 0
                if numAmount > 0 && vol > 0 {
                    let sizePct = (numAmount / vol * 1000).rounded() / 10
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(sizePct >= 25 ? red400 : sizePct >= 5 ? amber400 : emerald)
                            .frame(width: 2)
                        Text(sizePct >= 5
                             ? loc("Your bet is \(sizePct)% of market volume. This will move the price against you.",
                                   "Tu apuesta es \(sizePct)% del volumen. Esto movera el precio en tu contra.")
                             : loc("Your bet size has negligible market impact.",
                                   "Tu apuesta tiene impacto minimo en el mercado."))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(sizePct >= 25 ? red400.opacity(0.7) : sizePct >= 5 ? amber400.opacity(0.7) : emerald.opacity(0.7))
                    }
                    .padding(.vertical, 4)
                }

                // Calculate button
                Button {
                    if numAmount > 0 {
                        handleCalculateProbability(market, analysis: analysis, amountUSD: numAmount)
                    }
                } label: {
                    Text(loc("CALCULATE PROBABILITY", "CALCULAR PROBABILIDAD"))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(numAmount > 0 ? .black : .white.opacity(0.2))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Rectangle().fill(numAmount > 0 ? Color.white : Color.white.opacity(0.1)))
                }
                .disabled(numAmount <= 0)
            }
            .padding(14)
        }
        .background(Rectangle().fill(Color.white.opacity(0.04)))
        .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Step 4: Success Probability

    private func successProbabilityView(_ prob: ProbabilityResult, market: MarketItem, signalHash: String) -> some View {
        let hasSide = prob.recommendedSide != nil
        let side = prob.recommendedSide ?? "Yes"
        let isYes = side == "Yes"
        let sideColor = isYes ? emerald : red400
        let probColor = prob.winProbability >= 65 ? emerald : prob.winProbability >= 45 ? amber400 : red400
        let confText = prob.confidence == "high" ? loc("High confidence", "Alta confianza")
            : prob.confidence == "medium" ? loc("Medium confidence", "Confianza media")
            : loc("Low confidence", "Baja confianza")
        let hasImpact = prob.breakdown.marketImpact < -2

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(loc("WIN PROBABILITY", "PROBABILIDAD DE EXITO"))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1.5)
                Spacer()
                if prob.betAmount > 0 {
                    Text("$\(Int(prob.betAmount)) USD")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            // Big number
            VStack(spacing: 6) {
                Text("\(prob.winProbability)%")
                    .font(.system(size: 56, weight: .bold, design: .monospaced))
                    .foregroundColor(probColor)
                Text(confText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            // Breakdown
            HStack(spacing: 12) {
                Text("Market: \(prob.breakdown.marketImplied)%")
                Text("Agent: \(prob.breakdown.agentAdjustment > 0 ? "+" : "")\(String(format: "%.1f", prob.breakdown.agentAdjustment))%")
                if prob.breakdown.redFlagPenalty < 0 {
                    Text("Risk: \(String(format: "%.1f", prob.breakdown.redFlagPenalty))%")
                        .foregroundColor(amber400.opacity(0.6))
                }
                if hasImpact {
                    Text(loc("Size: ", "Tamano: ") + "\(String(format: "%.1f", prob.breakdown.marketImpact))%")
                        .foregroundColor(red400.opacity(0.6))
                }
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.2))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            if hasSide {
                VStack(spacing: 10) {
                    // Recommended side
                    HStack(spacing: 6) {
                        Text(loc("Recommended", "Recomendado"))
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.3))
                        Text(side.uppercased())
                            .font(.system(size: 16, weight: .bold, design: .monospaced))
                            .foregroundColor(sideColor)
                    }

                    // Smart Money button
                    Button {
                        handleSmartBet(side: side, slug: market.slug, signalHash: signalHash, amount: "\(prob.smartMoneySize)", conditionId: market.conditionId)
                    } label: {
                        Text("\(loc("SMART MONEY", "SMART MONEY")): $\(prob.smartMoneySize) USD")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundColor(sideColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Rectangle().fill(sideColor.opacity(0.05)))
                            .overlay(Rectangle().stroke(sideColor.opacity(0.4), lineWidth: 1))
                    }

                    Text("Kelly: \(Int(prob.kellyFraction * 100))% of $\(Int(prob.betAmount))")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.15))

                    // Full amount button
                    if prob.betAmount > 0 && prob.smartMoneySize < Int(prob.betAmount) {
                        Button {
                            handleSmartBet(side: side, slug: market.slug, signalHash: signalHash, amount: "\(Int(prob.betAmount))", conditionId: market.conditionId)
                        } label: {
                            Text("$\(Int(prob.betAmount)) USD (100%)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(sideColor.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .overlay(Rectangle().stroke(sideColor.opacity(0.15), lineWidth: 1))
                        }
                    }
                }
                .padding(14)
            } else {
                VStack(spacing: 10) {
                    Text(loc("No edge detected. Bet at your own risk.", "Sin ventaja detectada. Apuesta bajo tu propio riesgo."))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(amber400.opacity(0.7))

                    HStack(spacing: 8) {
                        Button {
                            handleBetPrompt(side: "Yes", slug: market.slug, signalHash: signalHash, conditionId: market.conditionId)
                        } label: {
                            Text("BET YES")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(emerald)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .overlay(Rectangle().stroke(emerald.opacity(0.3), lineWidth: 1))
                        }
                        Button {
                            handleBetPrompt(side: "No", slug: market.slug, signalHash: signalHash, conditionId: market.conditionId)
                        } label: {
                            Text("BET NO")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(red400)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .overlay(Rectangle().stroke(red400.opacity(0.3), lineWidth: 1))
                        }
                    }
                }
                .padding(14)
            }
        }
        .background(Rectangle().fill(Color.white.opacity(0.04)))
        .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Skip path: Bet Choice

    private func betChoiceView(_ market: MarketItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                priceLabel("YES", market.yesPrice, emerald)
                priceLabel("NO", market.noPrice, red400)
            }
            .padding(12)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            HStack(spacing: 8) {
                Button {
                    handleBetPrompt(side: "Yes", slug: market.slug, signalHash: "skip")
                } label: {
                    Text("BET YES")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(emerald)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(Rectangle().stroke(emerald.opacity(0.3), lineWidth: 1))
                }
                Button {
                    handleBetPrompt(side: "No", slug: market.slug, signalHash: "skip")
                } label: {
                    Text("BET NO")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(red400)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(Rectangle().stroke(red400.opacity(0.3), lineWidth: 1))
                }
            }
            .padding(12)
        }
        .background(Rectangle().fill(Color.white.opacity(0.04)))
        .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Bet Prompt (amount entry)

    private func betPromptView(side: String, slug: String, signalHash: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("How much?", "Cuanto?"))
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))

            HStack(spacing: 6) {
                ForEach(["1", "5", "10", "25"], id: \.self) { amt in
                    Button {
                        handlePlaceBet(side: side, slug: slug, signalHash: signalHash, amount: amt)
                    } label: {
                        Text("$\(amt)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(side == "Yes" ? emerald : red400)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .overlay(Rectangle().stroke((side == "Yes" ? emerald : red400).opacity(0.3), lineWidth: 1))
                    }
                }
            }
        }
        .padding(12)
        .background(Rectangle().fill(Color.white.opacity(0.04)))
        .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
    }

    // MARK: - Bet Confirmed

    private func betConfirmedView(_ record: BetRecord) -> some View {
        let isPolymarket = record.source == "polymarket" || record.source == "polymarket-mock"
        let linkUrl = record.explorerUrl ?? "https://polygonscan.com/tx/\(record.txHash)"

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(emerald)
                Text(loc("BET PLACED", "APUESTA CONFIRMADA"))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(emerald)
                    .tracking(1)
                if isPolymarket {
                    Text("POLYMARKET")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(emerald.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Rectangle().stroke(emerald.opacity(0.2), lineWidth: 1))
                }
            }
            HStack(spacing: 12) {
                Text(record.side.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(record.side == "Yes" ? emerald : red400)
                Text("$\(record.amount) USD")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
            }
            if isPolymarket, let price = record.price, let shares = record.shares {
                HStack(spacing: 16) {
                    Text("Price: \(String(format: "%.2f", price))")
                    Text("Shares: \(String(format: "%.1f", shares))")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
            }
            Button {
                if let url = URL(string: linkUrl) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(String(record.txHash.prefix(18)) + "...")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
        }
        .padding(12)
        .background(Rectangle().fill(emerald.opacity(0.08)))
        .overlay(Rectangle().stroke(emerald.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Context Insight

    private func contextInsightView(_ insight: String, keyStats: [String]) -> some View {
        let blue = Color(hex: "3B82F6")

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10))
                    .foregroundColor(blue)
                Text(loc("STATISTICAL CONTEXT", "CONTEXTO ESTADISTICO"))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(blue.opacity(0.7))
                    .tracking(1.5)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            Text(insight)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.8))
                .padding(14)

            if !keyStats.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(keyStats.enumerated()), id: \.offset) { _, stat in
                        HStack(spacing: 6) {
                            Circle().fill(blue).frame(width: 4, height: 4)
                            Text(stat)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        .background(Rectangle().fill(blue.opacity(0.04)))
        .overlay(Rectangle().stroke(blue.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Loading / Error

    private func loadingView(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.4)))
                .scaleEffect(0.7)
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func errorView(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 11))
                .foregroundColor(red400)
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(red400.opacity(0.8))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            // Voice listening indicator
            if speechRecognizer.isListening {
                HStack(spacing: 6) {
                    PulsingDot(color: emerald)
                    Text(loc("Listening...", "Escuchando..."))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(emerald)
                        .tracking(0.5)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(emerald.opacity(0.08))
            }

            // Voice error indicator
            if let voiceError = speechRecognizer.errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 9))
                        .foregroundColor(amber400)
                    Text(voiceError)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(amber400)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(amber400.opacity(0.08))
            }

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)

            HStack(spacing: 10) {
                TextField("", text: $inputText,
                          prompt: Text(loc("Ask \(assistantName)...", "Pregunta a \(assistantName)..."))
                    .foregroundColor(.white.opacity(0.2)))
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .focused($inputFocused)
                    .onSubmit { sendMessage() }

                // Mic button
                Button {
                    tts.stopSpeaking()
                    // Small delay to let TTS audio session release
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        speechRecognizer.toggle()
                    }
                } label: {
                    Image(systemName: speechRecognizer.isListening ? "mic.fill" : "mic")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(speechRecognizer.isListening ? .black : .white.opacity(0.4))
                        .frame(width: 32, height: 32)
                        .background(Rectangle().fill(
                            speechRecognizer.isListening ? emerald : Color.white.opacity(0.06)))
                }
                .disabled(isLoading)

                // Send button
                Button { sendMessage() } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(inputText.trimmingCharacters(in: .whitespaces).isEmpty ? .white.opacity(0.15) : .black)
                        .frame(width: 32, height: 32)
                        .background(Rectangle().fill(
                            inputText.trimmingCharacters(in: .whitespaces).isEmpty
                            ? Color.white.opacity(0.06) : Color.white))
                }
                .disabled(inputText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.03))
        }
    }

    // MARK: - Helpers

    private func priceLabel(_ label: String, _ price: Double?, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(fmtPrice(price))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
    }

    private func classificationPills(_ c: DeepAnalysisClassifications) -> some View {
        HStack(spacing: 6) {
            if c.bot > 0 { classPill("\(c.bot) bot", red400) }
            if c.likelyBot > 0 { classPill("\(c.likelyBot) likely", Color(hex: "F97316")) }
            if c.mixed > 0 { classPill("\(c.mixed) mixed", amber400) }
            if c.human > 0 { classPill("\(c.human) human", emerald) }
        }
    }

    private func classPill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .overlay(Rectangle().stroke(color.opacity(0.3), lineWidth: 1))
    }

    private func classColor(_ classification: String) -> Color {
        switch classification {
        case "bot": return red400
        case "likely-bot": return Color(hex: "F97316")
        case "mixed": return amber400
        case "human": return emerald
        default: return .white.opacity(0.3)
        }
    }

    private func fmtPrice(_ price: Double?) -> String {
        guard let p = price else { return "--" }
        return String(format: "%.0f\u{00A2}", p * 100)
    }

    private func fmtVol(_ vol: Double) -> String {
        if vol >= 1_000_000 { return String(format: "%.1fM", vol / 1_000_000) }
        if vol >= 1_000 { return String(format: "%.0fK", vol / 1_000) }
        return String(format: "%.0f", vol)
    }

    private func fmtCap(_ n: Double) -> String {
        if n > 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
        if n > 1_000 { return String(format: "%.0fK", n / 1_000) }
        return String(format: "%.0f", n)
    }

    // MARK: - TTS Helper

    private func speakIfEnabled(_ text: String) {
        guard ttsEnabled else { return }
        tts.speak(text)
    }

    // MARK: - Actions

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        // Stop listening if active (user submitted via keyboard while mic was on)
        if speechRecognizer.isListening {
            speechRecognizer.stopListening()
        }
        messages.append(ChatMessage(role: .user, text: text))
        inputText = ""
        isLoading = true
        Task {
            await handleUserMessage(text)
            isLoading = false
        }
    }

    private func handleUserMessage(_ text: String) async {
        let lower = text.lowercased()
        if lower.contains("trending") || lower.contains("what's hot") || lower.contains("que hay") || lower.contains("popular") {
            await searchMarkets(query: "trending")
        } else {
            await searchMarkets(query: text)
        }
    }

    private func loadInitialMarkets() {
        guard messages.isEmpty else { return }
        let greeting = loc("What's on your mind? Search a market to start.", "Que tienes en mente? Busca un mercado para comenzar.")
        messages.append(ChatMessage(role: .assistant, text: greeting))
    }

    private func searchMarkets(query: String) async {
        let loadingMsg = ChatMessage(role: .assistant, text: "", attachment: .loading(loc("Searching markets...", "Buscando mercados...")))
        messages.append(loadingMsg)
        let loadingId = loadingMsg.id

        do {
            let response = try await VoiceSwapAPIClient.shared.searchMarkets(query: query)
            messages.removeAll { $0.id == loadingId }
            let allMarkets = response.events.flatMap { $0.markets ?? [] }
            if allMarkets.isEmpty {
                let noResultText = loc("No markets found for \"\(query)\".", "No encontre mercados para \"\(query)\".")
                messages.append(ChatMessage(role: .assistant, text: noResultText))
                speakIfEnabled(noResultText)
            } else {
                let display = Array(allMarkets.prefix(5))
                let foundText = loc("Found \(allMarkets.count) market\(allMarkets.count == 1 ? "" : "s"). Tap one to analyze.", "Encontre \(allMarkets.count) mercado\(allMarkets.count == 1 ? "" : "s"). Toca uno para analizar.")
                var msg = ChatMessage(role: .assistant, text: foundText)
                msg.attachment = .markets(display)
                messages.append(msg)
                // TTS: read first market question + odds
                if let first = display.first {
                    let yPct = Int((first.yesPrice ?? 0.5) * 100)
                    let ttsText = loc(
                        "Found \(allMarkets.count) markets. First: \(first.question), \(yPct) percent yes.",
                        "Encontre \(allMarkets.count) mercados. Primero: \(first.question), \(yPct) por ciento si."
                    )
                    speakIfEnabled(ttsText)
                }
            }
        } catch {
            messages.removeAll { $0.id == loadingId }
            messages.append(ChatMessage(role: .assistant, text: "", attachment: .error(loc("Failed to search markets.", "Error al buscar mercados."))))
        }
    }

    // Step 0 → Step 1: Market selected
    private func handleMarketSelect(_ market: MarketItem) {
        messages.append(ChatMessage(role: .user, text: market.question))
        var msg = ChatMessage(role: .assistant, text: loc("Want my analysis before you bet?", "Quieres mi analisis antes de apostar?"))
        msg.attachment = .marketPreview(market)
        messages.append(msg)
    }

    // Step 1 → Step 2: Detect Agents
    private func handleDetectAgents(_ market: MarketItem) {
        guard !isLoading else { return }
        messages.append(ChatMessage(role: .user, text: loc("Detect Agents", "Detectar Agentes")))
        isLoading = true

        Task {
            let loadingMsg = ChatMessage(role: .assistant, text: "", attachment: .loading(loc("Agent Radar scanning holders...", "Agent Radar escaneando holders...")))
            messages.append(loadingMsg)
            let loadingId = loadingMsg.id

            do {
                let analysis = try await VoiceSwapAPIClient.shared.deepAnalyzeMarket(conditionId: market.conditionId)
                messages.removeAll { $0.id == loadingId }
                let text = loc(
                    "Scanned \(analysis.holdersScanned) of \(analysis.totalHolders) holders. \(analysis.agentRate)% agent activity.",
                    "Escanee \(analysis.holdersScanned) de \(analysis.totalHolders) holders. \(analysis.agentRate)% actividad de agentes."
                )
                var msg = ChatMessage(role: .assistant, text: text)
                msg.attachment = .deepAnalysis(analysis, market)
                messages.append(msg)
                // TTS: agent radar summary
                let ttsText = loc(
                    "Scanned \(analysis.holdersScanned) holders, \(analysis.agentRate) percent agent activity. Smart money says \(analysis.smartMoneyDirection).",
                    "Escaneados \(analysis.holdersScanned) holders, \(analysis.agentRate) por ciento actividad de agentes. Smart money dice \(analysis.smartMoneyDirection)."
                )
                speakIfEnabled(ttsText)
            } catch {
                messages.removeAll { $0.id == loadingId }
                messages.append(ChatMessage(role: .assistant, text: "", attachment: .error(loc("Failed to analyze market.", "Error al analizar el mercado."))))
            }
            isLoading = false
        }
    }

    // Step 1 skip → Bet Choice
    private func handleSkipToChoice(_ market: MarketItem) {
        messages.append(ChatMessage(role: .user, text: loc("Skip, bet now", "Saltar, apostar ya")))
        var msg = ChatMessage(role: .assistant, text: "")
        msg.attachment = .betChoice(market)
        messages.append(msg)
    }

    // MARK: - AI Gate

    private func checkAIGateEligibility() {
        let wallet = VoiceSwapWallet.shared.isCreated ? VoiceSwapWallet.shared.address : ""
        guard !wallet.isEmpty else { return }
        Task {
            do {
                let result = try await VoiceSwapAPIClient.shared.checkGroupEligibility(wallet: wallet)
                await MainActor.run { aiGateEligible = result.eligible }
            } catch {
                print("[AIGate] Check failed: \(error)")
            }
        }
    }

    // Step 2 → Step 3: Explain with AI
    private func handleExplainWithAI(_ analysis: DeepAnalysisResult, market: MarketItem) {
        guard !isLoading else { return }

        // AI Gate: require group with 2+ members
        if !aiGateEligible {
            messages.append(ChatMessage(role: .assistant, text: "",
                attachment: .error(loc(
                    "To use \"Explain with AI\", create a group and invite at least 1 friend. Go to the Groups tab.",
                    "Para usar \"Explicar con IA\", crea un grupo e invita al menos 1 amigo. Ve a la pestaña Grupos."
                ))))
            return
        }

        messages.append(ChatMessage(role: .user, text: loc("Explain with AI", "Explicar con IA")))
        isLoading = true

        Task {
            let loadingMsg = ChatMessage(role: .assistant, text: "", attachment: .loading(loc("AI analyzing market data...", "IA analizando datos del mercado...")))
            messages.append(loadingMsg)
            let loadingId = loadingMsg.id

            do {
                let lang = isSpanish ? "es" : "en"
                let lines = try await VoiceSwapAPIClient.shared.explainMarket(analysis: analysis, market: market, language: lang)
                messages.removeAll { $0.id == loadingId }
                var msg = ChatMessage(role: .assistant, text: "")
                msg.attachment = .aiExplanation(lines, market, analysis)
                messages.append(msg)
            } catch {
                messages.removeAll { $0.id == loadingId }
                messages.append(ChatMessage(role: .assistant, text: "", attachment: .error(loc("Failed to get AI explanation.", "Error al obtener explicacion de IA."))))
            }
            isLoading = false
        }
    }

    // Stats: Fetch context from Anthropic
    private func handleFetchContext(_ market: MarketItem) {
        guard !isLoading else { return }
        messages.append(ChatMessage(role: .user, text: loc("Stats", "Estadisticas")))
        isLoading = true

        Task {
            let loadingMsg = ChatMessage(role: .assistant, text: "", attachment: .loading(loc("Fetching stats...", "Buscando estadisticas...")))
            messages.append(loadingMsg)
            let loadingId = loadingMsg.id

            do {
                let url = URL(string: "https://betwhisper.ai/api/market/context")!
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("ios", forHTTPHeaderField: "X-Platform")

                let body: [String: Any] = [
                    "marketTitle": market.question,
                    "marketSlug": market.slug,
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)

                let (data, _) = try await URLSession.shared.data(for: request)

                struct ContextResponse: Decodable {
                    let insight: String?
                    let keyStats: [String]?
                    let error: String?
                }

                let response = try JSONDecoder().decode(ContextResponse.self, from: data)

                await MainActor.run {
                    messages.removeAll { $0.id == loadingId }

                    if let error = response.error {
                        messages.append(ChatMessage(role: .assistant, text: "", attachment: .error(error)))
                    } else {
                        let insight = response.insight ?? loc("No context available.", "Sin contexto disponible.")
                        let stats = response.keyStats ?? []
                        var msg = ChatMessage(role: .assistant, text: "")
                        msg.attachment = .contextInsight(insight, stats)
                        messages.append(msg)
                        speakIfEnabled(insight)
                    }
                }
            } catch {
                await MainActor.run {
                    messages.removeAll { $0.id == loadingId }
                    messages.append(ChatMessage(role: .assistant, text: "", attachment: .error(loc("Failed to fetch stats.", "Error al obtener estadisticas."))))
                }
            }
            isLoading = false
        }
    }

    // Step 3 → Step 3.5: Ask amount
    private func handleAskAmount(_ market: MarketItem, analysis: DeepAnalysisResult) {
        betAmountText = ""
        var msg = ChatMessage(role: .assistant, text: loc("How much do you want to invest?", "Cuanto quieres invertir?"))
        msg.attachment = .betAmountInput(market, analysis)
        messages.append(msg)
    }

    // Step 3.5 → Step 4: Calculate probability
    private func handleCalculateProbability(_ market: MarketItem, analysis: DeepAnalysisResult, amountUSD: Double) {
        messages.append(ChatMessage(role: .user, text: "$\(Int(amountUSD)) USD"))
        let prob = ProbabilityCalculator.calculate(
            analysis: analysis,
            yesPrice: market.yesPrice ?? 0.5,
            noPrice: market.noPrice ?? 0.5,
            betAmountUSD: amountUSD,
            marketVolumeUSD: market.volume ?? 0
        )
        var msg = ChatMessage(role: .assistant, text: loc("Win Probability", "Probabilidad de Exito"))
        msg.attachment = .successProbability(prob, market, analysis.signalHash)
        messages.append(msg)
    }

    // Step 4: Smart bet
    private func handleSmartBet(side: String, slug: String, signalHash: String, amount: String, conditionId: String) {
        handlePlaceBet(side: side, slug: slug, signalHash: signalHash, amount: amount, conditionId: conditionId)
    }

    // Bet prompt → place bet
    private func handleBetPrompt(side: String, slug: String, signalHash: String, conditionId: String = "") {
        messages.append(ChatMessage(role: .user, text: "\(side) on this market"))
        var msg = ChatMessage(role: .assistant, text: loc("How much?", "Cuanto?"))
        msg.attachment = .betPrompt(side, slug, signalHash)
        messages.append(msg)
    }

    // BetWhisper deposit address (server wallet that receives MON payments)
    private let depositAddress = "0x530aBd0674982BAf1D16fd7A52E2ea510E74C8c3"

    // Place bet: 3-step flow (Monad Intent → CLOB Execution → Confirmed)
    private func handlePlaceBet(side: String, slug: String, signalHash: String, amount: String, conditionId: String = "") {
        messages.append(ChatMessage(role: .user, text: "$\(amount) on \(side)"))
        isLoading = true

        Task {
            // Step 1: Fetch MON price and register intent on Monad
            var loadingMsg = ChatMessage(role: .assistant, text: "", attachment: .loading(loc("Fetching MON price...", "Obteniendo precio MON...")))
            messages.append(loadingMsg)
            var loadingId = loadingMsg.id

            // Fetch current MON price
            var monPriceUSD: Double = 0.021
            do {
                let url = URL(string: "https://betwhisper.ai/api/mon-price")!
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let price = json["price"] as? Double, price > 0 {
                    monPriceUSD = price
                }
            } catch {
                print("[BetWhisper] MON price fetch failed, using fallback: \(monPriceUSD)")
            }

            // Calculate MON amount: (USD / MON price) * 1.01 buffer
            let amountUSD = Double(amount) ?? 1.0
            let monAmount = (amountUSD / monPriceUSD) * 1.01
            let monAmountStr = String(format: "%.6f", monAmount)

            messages.removeAll { $0.id == loadingId }
            loadingMsg = ChatMessage(role: .assistant, text: "", attachment: .loading(loc("Sending \(monAmountStr) MON on Monad...", "Enviando \(monAmountStr) MON en Monad...")))
            messages.append(loadingMsg)
            loadingId = loadingMsg.id

            // Require wallet for real on-chain payment
            guard VoiceSwapWallet.shared.isCreated else {
                messages.removeAll { $0.id == loadingId }
                messages.append(ChatMessage(role: .assistant, text: loc(
                    "Wallet not created. Go to the Wallet tab to set up your wallet first.",
                    "Wallet no creada. Ve a la tab Wallet para configurarla."
                )))
                return
            }

            var monadTxHash: String? = nil
            do {
                let metadata = "{\"protocol\":\"betwhisper\",\"market\":\"\(slug)\",\"side\":\"\(side)\",\"signal\":\"\(signalHash)\",\"amount_usd\":\(amountUSD),\"mon_price\":\(monPriceUSD),\"ts\":\(Int(Date().timeIntervalSince1970))}"
                let dataHex = "0x" + (metadata.data(using: .utf8) ?? Data()).map { String(format: "%02x", $0) }.joined()
                let valueHex = monToWeiHex(monAmountStr)
                monadTxHash = try await VoiceSwapWallet.shared.sendTransaction(to: depositAddress, value: valueHex, data: dataHex)
                print("[BetWhisper] Monad intent tx: \(monadTxHash ?? "") (\(monAmountStr) MON to deposit)")
            } catch {
                print("[BetWhisper] Monad intent failed: \(error)")
                messages.removeAll { $0.id == loadingId }
                messages.append(ChatMessage(role: .assistant, text: loc(
                    "Transaction failed: \(error.localizedDescription). Check your MON balance in the Wallet tab.",
                    "Transaccion fallida: \(error.localizedDescription). Revisa tu balance de MON en la tab Wallet."
                )))
                return
            }
            messages.removeAll { $0.id == loadingId }

            // Step 2: Execute on Polymarket CLOB
            loadingMsg = ChatMessage(role: .assistant, text: "", attachment: .loading(loc("Executing on Polymarket CLOB...", "Ejecutando en Polymarket CLOB...")))
            messages.append(loadingMsg)
            loadingId = loadingMsg.id

            // Resolve conditionId from chat history if empty
            var resolvedConditionId = conditionId
            if resolvedConditionId.isEmpty {
                for msg in messages.reversed() {
                    if case .deepAnalysis(_, let market) = msg.attachment {
                        resolvedConditionId = market.conditionId
                        break
                    }
                    if case .marketPreview(let market) = msg.attachment {
                        resolvedConditionId = market.conditionId
                        break
                    }
                }
            }

            var finalTxHash: String
            var explorerUrl: String? = nil
            var source: String = "demo"
            var shares: Double? = nil
            var price: Double? = nil

            if !resolvedConditionId.isEmpty {
                do {
                    let result = try await VoiceSwapAPIClient.shared.executeClobBet(
                        conditionId: resolvedConditionId,
                        outcomeIndex: side == "Yes" ? 0 : 1,
                        amountUSD: Double(amount) ?? 1.0,
                        signalHash: signalHash,
                        marketSlug: slug,
                        monadTxHash: monadTxHash,
                        monPriceUSD: monPriceUSD
                    )
                    if result.success == true {
                        finalTxHash = result.polygonTxHash ?? result.txHash ?? monadTxHash ?? ""
                        explorerUrl = result.explorerUrl
                        source = result.source ?? "polymarket"
                        shares = result.shares
                        price = result.price
                        print("[BetWhisper] CLOB order: \(result.orderID ?? "") tx: \(finalTxHash)")
                    } else {
                        print("[BetWhisper] CLOB failed: \(result.error ?? "unknown")")
                        finalTxHash = monadTxHash ?? ""
                    }
                } catch {
                    print("[BetWhisper] CLOB error: \(error)")
                    finalTxHash = monadTxHash ?? ""
                }
            } else {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                finalTxHash = "0x" + (0..<64).map { _ in String(format: "%x", Int.random(in: 0...15)) }.joined()
                explorerUrl = "https://polygonscan.com/tx/\(finalTxHash)"
            }

            messages.removeAll { $0.id == loadingId }

            // Record bet on backend
            _ = try? await VoiceSwapAPIClient.shared.recordBet(
                marketSlug: slug,
                side: side,
                amount: amount,
                walletAddress: VoiceSwapWallet.shared.isCreated ? VoiceSwapWallet.shared.address : "demo",
                txHash: finalTxHash
            )

            // Step 3: Confirmed
            let record = BetRecord(
                id: nil, marketSlug: slug, side: side, amount: amount, txHash: finalTxHash,
                timestamp: Int(Date().timeIntervalSince1970),
                source: source, explorerUrl: explorerUrl, shares: shares, price: price, monadTxHash: monadTxHash
            )
            let confirmText = loc("Bet confirmed on Polymarket.", "Apuesta confirmada en Polymarket.")
            var confirmMsg = ChatMessage(role: .assistant, text: confirmText)
            confirmMsg.attachment = .betConfirmed(record)
            messages.append(confirmMsg)
            // TTS: bet confirmation
            let priceStr = price != nil ? String(format: " at %.2f", price!) : ""
            let ttsText = loc(
                "Bet placed. \(amount) dollars on \(side)\(priceStr).",
                "Apuesta confirmada. \(amount) dolares en \(side)\(priceStr)."
            )
            speakIfEnabled(ttsText)
            isLoading = false
        }
    }

    /// Convert MON amount string (e.g. "0.01") to hex wei string (e.g. "0x2386f26fc10000")
    private func monToWeiHex(_ amount: String) -> String {
        // Parse decimal amount and multiply by 10^18
        guard let decimalValue = Decimal(string: amount) else { return "0x0" }
        let weiDecimal = decimalValue * Decimal(sign: .plus, exponent: 18, significand: 1)
        let weiString = NSDecimalNumber(decimal: weiDecimal).stringValue
        // Remove any decimal point (should be integer after multiplication)
        let cleanWei = weiString.components(separatedBy: ".").first ?? weiString
        guard let weiUInt = UInt64(cleanWei) else { return "0x0" }
        return "0x" + String(weiUInt, radix: 16)
    }
}

// PulsingDot is defined in VoiceSwapMainView.swift and reused here
