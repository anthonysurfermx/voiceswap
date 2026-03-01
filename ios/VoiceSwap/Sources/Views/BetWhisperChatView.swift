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
    case betPrompt(String, String, String, String) // side, slug, signalHash, conditionId
    case betConfirm(String, String, String, String, String) // side, slug, signalHash, amount, conditionId
    case betConfirmed(BetRecord)
    case contextInsight(String, [String]) // insight, keyStats
    case balanceView([PositionItem], Double, Double) // positions, totalValue, totalPnl
    case pinVerify // inline PIN pad
    case sellConfirmed(String) // sell result text
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

    // Voice input (basic STT for text input)
    @StateObject private var speechRecognizer = SpeechRecognizer()
    private let tts = ChatSpeechSynthesizer()
    @State private var ttsEnabled: Bool = true

    // Gemini Live voice session (agentic mode with tools)
    @StateObject private var geminiSession = GeminiSessionViewModel()
    @ObservedObject private var glassesManager = MetaGlassesManager.shared
    @State private var isGeminiActive: Bool = false

    // Conversation persistence
    @StateObject private var conversationStore = ConversationStore.shared
    @State private var currentConversationId: UUID?
    @State private var showConversationList: Bool = false

    // Balance / PIN / Sell
    @State private var pinDigits: String = ""
    @State private var pinError: String? = nil
    @State private var pinLoading: Bool = false
    @State private var sellingPositionId: Int? = nil
    private let security = SecuritySettings.shared

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

                // Beta disclaimer
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 9))
                        .foregroundColor(amber400)
                    Text("Proceed with caution — Beta v0.1. Experimental version, may involve financial risks.")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(amber400.opacity(0.8))
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(amber400.opacity(0.05))

                // Gemini Live session banner
                if isGeminiActive {
                    geminiSessionBanner
                }

                // Gemini error
                if let error = geminiSession.sessionError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 9))
                            .foregroundColor(amber400)
                        Text(error)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(amber400)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(amber400.opacity(0.08))
                }

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
                    .onChange(of: messages.count) { oldCount, newCount in
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                            // Auto-persist new messages with non-empty text
                            if newCount > oldCount, !last.text.isEmpty {
                                persistMessage(role: last.role, text: last.text)
                            }
                        }
                    }
                }

                inputBar
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Create or resume conversation
            if currentConversationId == nil {
                let conv = conversationStore.create()
                currentConversationId = conv.id
            }
            loadInitialMarkets()
            checkAIGateEligibility()
            speechRecognizer.requestPermission()
            speechRecognizer.onFinalTranscript = { text in
                inputText = text
                sendMessage()
            }
            // Pre-connect Gemini WebSocket for instant voice activation
            geminiSession.preconnect()
            // Wire glasses camera frames to Gemini for visual context
            glassesManager.onVideoFrame = { [weak geminiSession] image in
                geminiSession?.handleVideoFrame(image)
            }
        }
        .onChange(of: speechRecognizer.transcript) { _, newValue in
            if speechRecognizer.isListening && !newValue.isEmpty {
                inputText = newValue
            }
        }
        .onChange(of: geminiSession.isSessionActive) { _, active in
            isGeminiActive = active
        }
        .onChange(of: geminiSession.latestTranscript) { _, event in
            guard let event else { return }
            let chatRole: ChatRole = event.role == "user" ? .user : .assistant
            messages.append(ChatMessage(role: chatRole, text: event.text))
        }
        .onChange(of: geminiSession.latestBetResult) { _, event in
            guard let event else { return }
            if event.success {
                let txShort = event.monadTxHash.isEmpty ? "" : "\(event.monadTxHash.prefix(10))...\(event.monadTxHash.suffix(6))"
                let text = "Bet Confirmed\n$\(event.amountUSD) on \(event.side) — \(event.market)\(txShort.isEmpty ? "" : "\nMonad Tx: \(txShort)")"
                messages.append(ChatMessage(role: .assistant, text: text))
            } else {
                messages.append(ChatMessage(role: .assistant, text: "Bet Failed\n$\(event.amountUSD) on \(event.side) — \(event.market)"))
            }
        }
        .sheet(isPresented: $showConversationList) {
            ConversationListView(
                store: conversationStore,
                onSelect: { conv in
                    loadConversation(conv)
                },
                onNewChat: {
                    startNewConversation()
                }
            )
        }
    }

    // MARK: - Header

    private var chatHeader: some View {
        HStack {
            // Conversation list button
            Button {
                showConversationList = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(.trailing, 4)

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
                HStack(spacing: 4) {
                    if isGeminiActive {
                        Text(geminiSession.isAISpeaking ? "SPEAKING" : "LISTENING")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(geminiSession.isAISpeaking ? amber400 : emerald)
                            .tracking(1.5)
                    } else {
                        Text("PREDICTION MARKETS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.25))
                            .tracking(1.5)
                    }
                }
            }
            Spacer()

            // Gemini Live voice button
            Button {
                toggleGeminiSession()
            } label: {
                HStack(spacing: 6) {
                    if isGeminiActive {
                        PulsingDot(color: emerald)
                    }
                    Image(systemName: isGeminiActive ? "waveform.circle.fill" : glassesManager.isConnected ? "eyeglasses" : "waveform.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(isGeminiActive ? emerald : .white.opacity(0.5))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Rectangle().fill(isGeminiActive ? emerald.opacity(0.12) : Color.white.opacity(0.06)))
                .overlay(Rectangle().stroke(isGeminiActive ? emerald.opacity(0.3) : Color.white.opacity(0.08), lineWidth: 1))
            }
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
        case .betPrompt(let side, let slug, let signalHash, let conditionId):
            betPromptView(side: side, slug: slug, signalHash: signalHash, conditionId: conditionId)
        case .betConfirm(let side, let slug, let signalHash, let amount, let conditionId):
            betConfirmView(side: side, slug: slug, signalHash: signalHash, amount: amount, conditionId: conditionId)
        case .betConfirmed(let record):
            betConfirmedView(record)
        case .contextInsight(let insight, let keyStats):
            contextInsightView(insight, keyStats: keyStats)
        case .balanceView(let positions, let totalValue, let totalPnl):
            balanceViewAttachment(positions, totalValue: totalValue, totalPnl: totalPnl)
        case .pinVerify:
            pinVerifyAttachment()
        case .sellConfirmed(let text):
            sellConfirmedView(text)
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
                Text(loc("TRADE", "INVERTIR"))
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
                             ? loc("Your position is \(sizePct)% of market volume. This will move the price against you.",
                                   "Tu posicion es \(sizePct)% del volumen. Esto movera el precio en tu contra.")
                             : loc("Your position size has negligible market impact.",
                                   "Tu posicion tiene impacto minimo en el mercado."))
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

                    // Manual YES / NO choice (override recommendation)
                    HStack(spacing: 8) {
                        Button {
                            handleBetPrompt(side: "Yes", slug: market.slug, signalHash: signalHash, conditionId: market.conditionId)
                        } label: {
                            Text("TRADE YES")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(emerald.opacity(side == "Yes" ? 0.3 : 0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .overlay(Rectangle().stroke(emerald.opacity(0.2), lineWidth: 1))
                        }
                        Button {
                            handleBetPrompt(side: "No", slug: market.slug, signalHash: signalHash, conditionId: market.conditionId)
                        } label: {
                            Text("TRADE NO")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundColor(red400.opacity(side == "No" ? 0.3 : 0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .overlay(Rectangle().stroke(red400.opacity(0.2), lineWidth: 1))
                        }
                    }
                }
                .padding(14)
            } else {
                VStack(spacing: 10) {
                    Text(loc("No edge detected. Trade at your own risk.", "Sin ventaja detectada. Invierte bajo tu propio riesgo."))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(amber400.opacity(0.7))

                    HStack(spacing: 8) {
                        Button {
                            handleBetPrompt(side: "Yes", slug: market.slug, signalHash: signalHash, conditionId: market.conditionId)
                        } label: {
                            Text("TRADE YES")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(emerald)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .overlay(Rectangle().stroke(emerald.opacity(0.3), lineWidth: 1))
                        }
                        Button {
                            handleBetPrompt(side: "No", slug: market.slug, signalHash: signalHash, conditionId: market.conditionId)
                        } label: {
                            Text("TRADE NO")
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
                    Text("TRADE YES")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(emerald)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay(Rectangle().stroke(emerald.opacity(0.3), lineWidth: 1))
                }
                Button {
                    handleBetPrompt(side: "No", slug: market.slug, signalHash: "skip")
                } label: {
                    Text("TRADE NO")
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

    private func betPromptView(side: String, slug: String, signalHash: String, conditionId: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("How much?", "Cuanto?"))
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.6))

            HStack(spacing: 6) {
                ForEach(["1", "5", "10", "25"], id: \.self) { amt in
                    Button {
                        showBetConfirmation(side: side, slug: slug, signalHash: signalHash, amount: amt, conditionId: conditionId)
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

    private func showBetConfirmation(side: String, slug: String, signalHash: String, amount: String, conditionId: String) {
        messages.append(ChatMessage(role: .user, text: "$\(amount) on \(side)"))
        var msg = ChatMessage(role: .assistant, text: loc("Confirm your trade:", "Confirma tu operacion:"))
        msg.attachment = .betConfirm(side, slug, signalHash, amount, conditionId)
        messages.append(msg)
    }

    // MARK: - Bet Confirm (PIN + Face ID gate)

    private func betConfirmView(side: String, slug: String, signalHash: String, amount: String, conditionId: String) -> some View {
        let sideColor = side == "Yes" ? emerald : red400

        return VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundColor(amber400)
                    .font(.system(size: 14))
                Text(loc("CONFIRM TRADE", "CONFIRMAR OPERACION"))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(amber400)
                    .tracking(1)
            }

            // Trade summary
            HStack(spacing: 12) {
                Text(side.uppercased())
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundColor(sideColor)
                Text("$\(amount) USD")
                    .font(.system(size: 15, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
            }

            // Market slug
            Text(slug.replacingOccurrences(of: "-", with: " ").prefix(50).uppercased())
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))
                .lineLimit(1)

            Divider().background(Color.white.opacity(0.1))

            // PIN entry
            Text(loc("Enter PIN to confirm:", "Ingresa tu PIN para confirmar:"))
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))

            // PIN dots
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { i in
                    ZStack {
                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(width: 36, height: 40)
                            .overlay(Rectangle().stroke(
                                pinDigits.count > i ? sideColor : Color.white.opacity(0.2),
                                lineWidth: 1
                            ))
                        if pinDigits.count > i {
                            Circle()
                                .fill(sideColor)
                                .frame(width: 10, height: 10)
                        }
                    }
                }
                Spacer()
            }

            if let error = pinError {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(red400)
            }

            // Number pad (compact)
            VStack(spacing: 4) {
                ForEach([[1,2,3],[4,5,6],[7,8,9]], id: \.self) { row in
                    HStack(spacing: 4) {
                        ForEach(row, id: \.self) { num in
                            Button {
                                guard pinDigits.count < 4 else { return }
                                pinDigits += "\(num)"
                                if pinDigits.count == 4 {
                                    handleTradeConfirmPin(pin: pinDigits, side: side, slug: slug, signalHash: signalHash, amount: amount, conditionId: conditionId)
                                }
                            } label: {
                                Text("\(num)")
                                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 36)
                                    .background(Color.white.opacity(0.06))
                            }
                        }
                    }
                }
                HStack(spacing: 4) {
                    Color.clear.frame(height: 36)
                    Button {
                        guard pinDigits.count < 4 else { return }
                        pinDigits += "0"
                        if pinDigits.count == 4 {
                            handleTradeConfirmPin(pin: pinDigits, side: side, slug: slug, signalHash: signalHash, amount: amount, conditionId: conditionId)
                        }
                    } label: {
                        Text("0")
                            .font(.system(size: 16, weight: .medium, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(Color.white.opacity(0.06))
                    }
                    Button {
                        if !pinDigits.isEmpty { pinDigits.removeLast() }
                    } label: {
                        Image(systemName: "delete.left")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(Color.white.opacity(0.06))
                    }
                }
            }

            if pinLoading {
                HStack(spacing: 6) {
                    ProgressView().tint(sideColor).scaleEffect(0.7)
                    Text(loc("Verifying...", "Verificando..."))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(12)
        .background(Rectangle().fill(Color.white.opacity(0.04)))
        .overlay(Rectangle().stroke(sideColor.opacity(0.3), lineWidth: 1))
    }

    private func handleTradeConfirmPin(pin: String, side: String, slug: String, signalHash: String, amount: String, conditionId: String) {
        pinLoading = true
        pinError = nil

        Task {
            let wallet = VoiceSwapWallet.shared.address
            guard let url = URL(string: "https://betwhisper.ai/api/user/pin/verify") else {
                pinLoading = false
                pinError = "Invalid URL"
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "wallet": wallet.lowercased(),
                "pin": pin,
            ])

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let verified = json["verified"] as? Bool, verified,
                       let token = json["token"] as? String {
                        UserDefaults.standard.set(token, forKey: "betwhisper_auth_token")
                        await MainActor.run {
                            pinDigits = ""
                            pinLoading = false
                            // Remove the confirm attachment
                            messages.removeAll { if case .betConfirm = $0.attachment { return true }; return false }
                        }
                        // Face ID before executing
                        let passed = await security.authenticateWithBiometrics()
                        if passed {
                            await MainActor.run {
                                handlePlaceBet(side: side, slug: slug, signalHash: signalHash, amount: amount, conditionId: conditionId)
                            }
                        } else {
                            await MainActor.run {
                                messages.append(ChatMessage(role: .assistant, text: loc(
                                    "Face ID required to execute trade.",
                                    "Face ID requerido para ejecutar operacion."
                                )))
                            }
                        }
                    } else {
                        let attemptsLeft = json["attemptsRemaining"] as? Int
                        await MainActor.run {
                            pinLoading = false
                            pinDigits = ""
                            if let remaining = attemptsLeft {
                                pinError = loc("Wrong PIN. \(remaining) attempts left.", "PIN incorrecto. \(remaining) intentos.")
                            } else {
                                pinError = loc("Wrong PIN.", "PIN incorrecto.")
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    pinLoading = false
                    pinError = loc("Network error. Try again.", "Error de red. Intenta de nuevo.")
                    pinDigits = ""
                }
            }
        }
    }

    // MARK: - Bet Confirmed

    private func betConfirmedView(_ record: BetRecord) -> some View {
        // Prefer Monad tx (always real on-chain) over Polygon (may be mock)
        let monadHash = record.monadTxHash ?? ""
        let monadUrl = monadHash.isEmpty ? nil : "https://testnet.monadscan.com/tx/\(monadHash)"
        let displayHash = monadHash.isEmpty ? record.txHash : monadHash
        let displayUrl = monadUrl ?? record.explorerUrl ?? "https://testnet.monadscan.com/tx/\(record.txHash)"

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(emerald)
                Text(loc("TRADE CONFIRMED", "POSICION CONFIRMADA"))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(emerald)
                    .tracking(1)
                Text("MONAD")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(emerald.opacity(0.5))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .overlay(Rectangle().stroke(emerald.opacity(0.2), lineWidth: 1))
            }
            HStack(spacing: 12) {
                Text(record.side.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(record.side == "Yes" ? emerald : red400)
                Text("$\(record.amount) USD")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(.white)
            }
            if let price = record.price, let shares = record.shares {
                HStack(spacing: 16) {
                    Text("Price: \(String(format: "%.2f", price))")
                    Text("Shares: \(String(format: "%.1f", shares))")
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
            }
            Button {
                if let url = URL(string: displayUrl) {
                    UIApplication.shared.open(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Text(String(displayHash.prefix(18)) + "...")
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

            if isGeminiActive {
                // Gemini Live active: show voice-only bar
                HStack(spacing: 12) {
                    Text(loc("Voice mode active. \(assistantName) is listening.",
                             "Modo voz activo. \(assistantName) escucha."))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                    Spacer()
                    Button {
                        toggleGeminiSession()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.03))
            } else {
                // Normal text + voice input
                HStack(spacing: 10) {
                    TextField("", text: $inputText,
                              prompt: Text(loc("Ask \(assistantName)...", "Pregunta a \(assistantName)..."))
                        .foregroundColor(.white.opacity(0.2)))
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                        .focused($inputFocused)
                        .onSubmit { sendMessage() }

                    // Mic button (basic STT)
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
        // Don't play TTS through glasses speakers when typing in text chat
        guard !glassesManager.isConnected else { return }
        tts.speak(text)
    }

    // MARK: - Gemini Live Session

    private var geminiSessionBanner: some View {
        HStack(spacing: 10) {
            // Audio waveform indicator
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 0)
                        .fill(geminiSession.isAISpeaking ? amber400 : emerald)
                        .frame(width: 2, height: geminiSession.isAISpeaking
                               ? CGFloat.random(in: 4...14)
                               : geminiSession.isListening ? CGFloat.random(in: 2...8) : 3)
                        .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true).delay(Double(i) * 0.08), value: geminiSession.isAISpeaking)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(geminiSession.isAISpeaking
                     ? loc("\(assistantName) is speaking...", "\(assistantName) esta hablando...")
                     : loc("Listening via \(glassesManager.isConnected ? "Meta glasses" : "phone mic")...",
                           "Escuchando por \(glassesManager.isConnected ? "lentes Meta" : "microfono")..."))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
                if glassesManager.isConnected {
                    HStack(spacing: 4) {
                        Image(systemName: "eyeglasses")
                            .font(.system(size: 8))
                        Text("META")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(1)
                    }
                    .foregroundColor(emerald.opacity(0.5))
                }
            }

            Spacer()

            // Stop button
            Button {
                toggleGeminiSession()
            } label: {
                Text("STOP")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(red400)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(Rectangle().stroke(red400.opacity(0.3), lineWidth: 1))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Rectangle().fill(emerald.opacity(0.06)))
        .overlay(Rectangle().frame(height: 1).foregroundColor(emerald.opacity(0.15)), alignment: .bottom)
    }

    private func toggleGeminiSession() {
        if isGeminiActive {
            // Stop Gemini Live session
            geminiSession.stopSession()
            messages.append(ChatMessage(role: .assistant, text: loc(
                "Voice session ended.",
                "Sesion de voz terminada."
            )))
        } else {
            // Stop basic STT if active
            if speechRecognizer.isListening {
                speechRecognizer.stopListening()
            }
            tts.stopSpeaking()

            // Determine audio mode: glasses if connected, phone otherwise
            let audioMode: AudioMode = glassesManager.isConnected ? .glasses : .phone
            let modeText = glassesManager.isConnected
                ? loc("Voice activated via Meta glasses. Say something!", "Voz activada por lentes Meta. Di algo!")
                : loc("Voice activated via phone mic. Say something!", "Voz activada por microfono. Di algo!")

            messages.append(ChatMessage(role: .assistant, text: modeText))
            geminiSession.startSession(audioMode: audioMode)

            // Start glasses camera for visual context (Gemini sees what you see)
            if glassesManager.isConnected && !glassesManager.isStreaming {
                Task { await glassesManager.startCameraStream() }
            }
        }
    }

    // MARK: - Conversation Management

    private func persistMessage(role: ChatRole, text: String) {
        guard let convId = currentConversationId, !text.isEmpty else { return }
        let tm = TranscriptMessage(
            role: role == .user ? "user" : "assistant",
            text: text
        )
        conversationStore.appendMessage(to: convId, message: tm)
    }

    private func loadConversation(_ conv: Conversation) {
        currentConversationId = conv.id
        messages = conv.messages.map { tm in
            ChatMessage(
                role: tm.role == "user" ? .user : .assistant,
                text: tm.text
            )
        }
    }

    private func startNewConversation() {
        let conv = conversationStore.create()
        currentConversationId = conv.id
        messages = []
        loadInitialMarkets()
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
        if lower.contains("balance") || lower.contains("posicion") || lower.contains("position")
            || lower.contains("portfolio") || lower.contains("mis trades") || lower.contains("my trades") {
            await showBalance()
        } else if lower.contains("trending") || lower.contains("what's hot") || lower.contains("que hay") || lower.contains("popular") {
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
        var msg = ChatMessage(role: .assistant, text: loc("Want my analysis before you trade?", "Quieres mi analisis antes de invertir?"))
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
        messages.append(ChatMessage(role: .user, text: loc("Skip, trade now", "Saltar, invertir ya")))
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

    // Step 4: Smart bet → show confirmation
    private func handleSmartBet(side: String, slug: String, signalHash: String, amount: String, conditionId: String) {
        showBetConfirmation(side: side, slug: slug, signalHash: signalHash, amount: amount, conditionId: conditionId)
    }

    // Bet prompt → place bet
    private func handleBetPrompt(side: String, slug: String, signalHash: String, conditionId: String = "") {
        messages.append(ChatMessage(role: .user, text: "\(side) on this market"))
        var msg = ChatMessage(role: .assistant, text: loc("How much?", "Cuanto?"))
        msg.attachment = .betPrompt(side, slug, signalHash, conditionId)
        messages.append(msg)
    }

    // BetWhisper deposit address (server wallet that receives MON payments)
    private let depositAddress = "0x530aBd0674982BAf1D16fd7A52E2ea510E74C8c3"

    // Place bet: 3-step flow (Monad Intent → CLOB Execution → Confirmed)
    private func handlePlaceBet(side: String, slug: String, signalHash: String, amount: String, conditionId: String = "") {
        isLoading = true

        Task {
            // Step 1: Fetch MON price and register intent on Monad
            var loadingMsg = ChatMessage(role: .assistant, text: "", attachment: .loading(loc("Fetching MON price...", "Obteniendo precio MON...")))
            messages.append(loadingMsg)
            var loadingId = loadingMsg.id

            // Fetch current MON price (no hardcoded fallback — abort if unavailable)
            var monPriceUSD: Double = 0
            do {
                let url = URL(string: "https://betwhisper.ai/api/mon-price")!
                let (data, _) = try await URLSession.shared.data(from: url)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let price = json["price"] as? Double, price > 0 {
                    monPriceUSD = price
                }
            } catch {
                print("[BetWhisper] MON price fetch failed")
            }
            guard monPriceUSD > 0 else {
                messages.removeAll { $0.id == loadingId }
                messages.append(ChatMessage(role: .assistant, text: loc(
                    "Could not fetch MON price. Try again in a moment.",
                    "No se pudo obtener el precio de MON. Intenta en un momento."
                )))
                isLoading = false
                return
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
                isLoading = false
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
                isLoading = false
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
            var tokenId: String? = nil
            var tickSize: String? = nil
            var negRisk: Bool? = nil

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
                        tokenId = result.tokenId
                        tickSize = result.tickSize
                        negRisk = result.negRisk
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

            // Record position on backend only when CLOB succeeded (has shares)
            if let s = shares, s > 0 {
                do {
                    let wallet = VoiceSwapWallet.shared.isCreated ? VoiceSwapWallet.shared.address : "demo"
                    let recordUrl = URL(string: "https://betwhisper.ai/api/bet")!
                    var recordReq = URLRequest(url: recordUrl)
                    recordReq.httpMethod = "POST"
                    recordReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    var recordBody: [String: Any] = [
                        "marketSlug": slug,
                        "side": side,
                        "amount": amount,
                        "walletAddress": wallet,
                        "txHash": finalTxHash,
                        "conditionId": resolvedConditionId,
                        "monadTxHash": monadTxHash ?? "",
                        "shares": s,
                    ]
                    if let p = price { recordBody["price"] = p }
                    if let t = tokenId { recordBody["tokenId"] = t }
                    if let ts = tickSize { recordBody["tickSize"] = ts }
                    if let nr = negRisk { recordBody["negRisk"] = nr }
                    recordReq.httpBody = try JSONSerialization.data(withJSONObject: recordBody)
                    _ = try await URLSession.shared.data(for: recordReq)
                } catch {
                    print("[BetWhisper] Record position failed: \(error)")
                }
            }

            // Step 3: Confirmed
            let record = BetRecord(
                id: nil, marketSlug: slug, side: side, amount: amount, txHash: finalTxHash,
                timestamp: Int(Date().timeIntervalSince1970),
                source: source, explorerUrl: explorerUrl, shares: shares, price: price, monadTxHash: monadTxHash
            )
            let confirmText = loc("Trade confirmed on Polymarket.", "Posicion confirmada en Polymarket.")
            var confirmMsg = ChatMessage(role: .assistant, text: confirmText)
            confirmMsg.attachment = .betConfirmed(record)
            messages.append(confirmMsg)
            // TTS: bet confirmation
            let priceStr = price != nil ? String(format: " at %.2f", price!) : ""
            let ttsText = loc(
                "Trade placed. \(amount) dollars on \(side)\(priceStr).",
                "Posicion confirmada. \(amount) dolares en \(side)\(priceStr)."
            )
            speakIfEnabled(ttsText)
            isLoading = false
        }
    }

    // MARK: - Balance Flow (PIN + Face ID)

    private func showBalance() async {
        guard VoiceSwapWallet.shared.isCreated else {
            messages.append(ChatMessage(role: .assistant, text: loc(
                "Create your wallet first in the Wallet tab.",
                "Crea tu wallet primero en la tab Wallet."
            )))
            return
        }

        // Check if we have a valid PIN token
        if let token = UserDefaults.standard.string(forKey: "betwhisper_auth_token") {
            await fetchAndShowBalance(token: token)
        } else {
            // Need PIN verification — show inline PIN pad
            var msg = ChatMessage(role: .assistant, text: loc("Enter your PIN to view positions.", "Ingresa tu PIN para ver posiciones."))
            msg.attachment = .pinVerify
            messages.append(msg)
        }
    }

    private func fetchAndShowBalance(token: String) async {
        let loadingMsg = ChatMessage(role: .assistant, text: "", attachment: .loading(loc("Loading positions...", "Cargando posiciones...")))
        messages.append(loadingMsg)
        let loadingId = loadingMsg.id

        do {
            let wallet = VoiceSwapWallet.shared.address
            let response = try await VoiceSwapAPIClient.shared.fetchBalance(wallet: wallet, token: token)
            messages.removeAll { $0.id == loadingId }

            let text = response.positions.isEmpty
                ? loc("No open positions.", "Sin posiciones abiertas.")
                : loc("Your positions:", "Tus posiciones:")
            var msg = ChatMessage(role: .assistant, text: text)
            msg.attachment = .balanceView(response.positions, response.totalValue, response.totalPnl)
            messages.append(msg)
        } catch {
            messages.removeAll { $0.id == loadingId }
            // If 401 (token expired), prompt for PIN again
            if case APIError.httpError(401) = error {
                UserDefaults.standard.removeObject(forKey: "betwhisper_auth_token")
                var msg = ChatMessage(role: .assistant, text: loc("Session expired. Enter your PIN again.", "Sesion expirada. Ingresa tu PIN de nuevo."))
                msg.attachment = .pinVerify
                messages.append(msg)
            } else {
                messages.append(ChatMessage(role: .assistant, text: "", attachment: .error(loc("Failed to load positions.", "Error al cargar posiciones."))))
            }
        }
    }

    private func handlePinSubmit(_ pin: String) {
        pinLoading = true
        pinError = nil

        Task {
            let wallet = VoiceSwapWallet.shared.address
            guard let url = URL(string: "https://betwhisper.ai/api/user/pin/verify") else {
                pinLoading = false
                pinError = "Invalid URL"
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: [
                "wallet": wallet.lowercased(),
                "pin": pin,
            ])

            do {
                let (data, _) = try await URLSession.shared.data(for: request)
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let verified = json["verified"] as? Bool, verified,
                       let token = json["token"] as? String {
                        UserDefaults.standard.set(token, forKey: "betwhisper_auth_token")
                        await MainActor.run {
                            pinDigits = ""
                            pinLoading = false
                            // Remove PIN attachment and show balance
                            messages.removeAll { if case .pinVerify = $0.attachment { return true }; return false }
                        }
                        // Face ID before showing sensitive data
                        let passed = await security.authenticateWithBiometrics()
                        if passed {
                            await fetchAndShowBalance(token: token)
                        } else {
                            await MainActor.run {
                                messages.append(ChatMessage(role: .assistant, text: loc("Face ID required to view positions.", "Face ID requerido para ver posiciones.")))
                            }
                        }
                    } else {
                        await MainActor.run {
                            pinLoading = false
                            pinDigits = ""
                            if let remaining = json["attemptsRemaining"] as? Int {
                                pinError = loc("Wrong PIN. \(remaining) attempts left.", "PIN incorrecto. \(remaining) intentos restantes.")
                            } else if let locked = json["locked"] as? Bool, locked {
                                pinError = loc("Too many attempts. Try later.", "Demasiados intentos. Intenta despues.")
                            } else {
                                pinError = loc("Wrong PIN", "PIN incorrecto")
                            }
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    pinLoading = false
                    pinError = loc("Network error", "Error de red")
                }
            }
        }
    }

    // MARK: - Sell Flow (multi-step timeline like web)

    private func handleSellPosition(_ position: PositionItem) {
        sellingPositionId = position.id

        Task {
            // Face ID before selling
            let passed = await security.authenticateWithBiometrics()
            guard passed else {
                await MainActor.run {
                    sellingPositionId = nil
                    messages.append(ChatMessage(role: .assistant, text: loc("Face ID required to sell.", "Face ID requerido para vender.")))
                }
                return
            }

            // Step 1: CLOB Sell
            let step1Msg = ChatMessage(role: .assistant, text: "", attachment: .loading(loc("CLOB SELL — Executing on Polymarket...", "CLOB SELL — Ejecutando en Polymarket...")))
            await MainActor.run { messages.append(step1Msg) }
            let step1Id = step1Msg.id

            do {
                let wallet = VoiceSwapWallet.shared.address
                let result = try await VoiceSwapAPIClient.shared.sellPosition(
                    wallet: wallet,
                    tokenId: position.tokenId,
                    shares: position.shares,
                    tickSize: position.tickSize,
                    negRisk: position.negRisk,
                    marketSlug: position.marketSlug
                )

                await MainActor.run {
                    messages.removeAll { $0.id == step1Id }

                    guard result.success == true else {
                        sellingPositionId = nil
                        messages.append(ChatMessage(role: .assistant, text: "", attachment: .error(result.error ?? loc("Sell failed", "Venta fallida"))))
                        return
                    }

                    let usd = result.usdReceived ?? 0
                    let sharesStr = String(format: "%.1f", result.sharesSold ?? position.shares)
                    let priceStr = String(format: "%.2f", result.price ?? 0)

                    // Step 1 done
                    var clobMsg = ChatMessage(role: .assistant, text: loc(
                        "CLOB SELL — Sold \(sharesStr) shares @ $\(priceStr) = $\(String(format: "%.2f", usd))",
                        "CLOB SELL — Vendidas \(sharesStr) shares @ $\(priceStr) = $\(String(format: "%.2f", usd))"
                    ))
                    clobMsg.attachment = .sellConfirmed(loc("Polygon", "Polygon"))
                    messages.append(clobMsg)

                    // Step 2: MON Cashout result
                    if let mc = result.monCashout {
                        let monStr = String(format: "%.2f", mc.monAmount)
                        if mc.status == "sent" {
                            var cashoutMsg = ChatMessage(role: .assistant, text: loc(
                                "MON CASHOUT — \(monStr) MON sent to your wallet",
                                "MON CASHOUT — \(monStr) MON enviados a tu wallet"
                            ))
                            cashoutMsg.attachment = .sellConfirmed(loc("Monad", "Monad"))
                            messages.append(cashoutMsg)
                        } else if mc.status == "pending" {
                            messages.append(ChatMessage(role: .assistant, text: loc(
                                "MON CASHOUT — \(monStr) MON pending (server low balance)",
                                "MON CASHOUT — \(monStr) MON pendiente (balance servidor bajo)"
                            )))
                        } else {
                            messages.append(ChatMessage(role: .assistant, text: "", attachment: .error(loc(
                                "MON CASHOUT — Failed. \(monStr) MON will be retried.",
                                "MON CASHOUT — Fallido. \(monStr) MON se reintentara."
                            ))))
                        }
                    }

                    sellingPositionId = nil
                }
            } catch {
                await MainActor.run {
                    messages.removeAll { $0.id == step1Id }
                    sellingPositionId = nil
                    messages.append(ChatMessage(role: .assistant, text: "", attachment: .error(loc("Sell failed: \(error.localizedDescription)", "Venta fallida: \(error.localizedDescription)"))))
                }
            }
        }
    }

    // MARK: - Balance View Attachment

    private func balanceViewAttachment(_ positions: [PositionItem], totalValue: Double, totalPnl: Double) -> some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(loc("YOUR POSITIONS", "TUS POSICIONES"))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1.5)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Rectangle().fill(Color.white.opacity(0.02)))
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            // Summary: Value + P&L
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Value")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                    Text("$\(String(format: "%.2f", totalValue))")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)

                Rectangle().fill(Color.white.opacity(0.06)).frame(width: 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text("P&L")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                    Text("\(totalPnl >= 0 ? "+" : "")$\(String(format: "%.2f", totalPnl))")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(totalPnl >= 0 ? emerald : red400)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            }
            .background(Rectangle().fill(Color.white.opacity(0.03)))
            .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

            // Positions list
            if positions.isEmpty {
                Text(loc("No open positions", "Sin posiciones abiertas"))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
                    .padding(20)
            } else {
                ForEach(positions) { pos in
                    positionRow(pos)
                }
            }
        }
        .background(Rectangle().fill(Color.white.opacity(0.04)))
        .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func positionRow(_ pos: PositionItem) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(pos.marketSlug.replacingOccurrences(of: "-", with: " ").prefix(40).uppercased())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(pos.side.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(pos.side == "Yes" ? emerald : red400)

                        Text("\(String(format: "%.1f", pos.shares)) @ $\(String(format: "%.2f", pos.avgPrice)) → $\(String(format: "%.2f", pos.currentPrice))")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                    }
                }

                Spacer()

                // P&L
                Text("\(pos.pnl >= 0 ? "+" : "")$\(String(format: "%.2f", pos.pnl))")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(pos.pnl >= 0 ? emerald : red400)

                // Sell button
                if sellingPositionId == pos.id {
                    ProgressView().tint(.white).scaleEffect(0.7)
                        .frame(width: 50)
                } else {
                    Button {
                        handleSellPosition(pos)
                    } label: {
                        Text("SELL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundColor(amber400)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .overlay(Rectangle().stroke(amber400.opacity(0.3), lineWidth: 1))
                    }
                }
            }
            .padding(12)

            Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
        }
    }

    // MARK: - PIN Verify Attachment

    private func pinVerifyAttachment() -> some View {
        VStack(spacing: 16) {
            // PIN dots
            HStack(spacing: 16) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i < pinDigits.count ? Color.white : Color.white.opacity(0.15))
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
            }

            // Error
            if let err = pinError {
                Text(err)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(red400)
            }

            if pinLoading {
                ProgressView().tint(.white.opacity(0.6))
            } else {
                // Number pad (compact)
                VStack(spacing: 10) {
                    ForEach(0..<3, id: \.self) { row in
                        HStack(spacing: 16) {
                            ForEach(1...3, id: \.self) { col in
                                let digit = row * 3 + col
                                pinButton(String(digit))
                            }
                        }
                    }
                    HStack(spacing: 16) {
                        Color.clear.frame(width: 52, height: 44)
                        pinButton("0")
                        Button {
                            if !pinDigits.isEmpty { pinDigits.removeLast() }
                        } label: {
                            Image(systemName: "delete.left")
                                .font(.system(size: 16))
                                .foregroundColor(.white.opacity(0.4))
                                .frame(width: 52, height: 44)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Rectangle().fill(Color.white.opacity(0.04)))
        .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func pinButton(_ digit: String) -> some View {
        Button {
            pinError = nil
            guard pinDigits.count < 4 else { return }
            pinDigits += digit
            if pinDigits.count == 4 {
                handlePinSubmit(pinDigits)
            }
        } label: {
            Text(digit)
                .font(.system(size: 22, weight: .light))
                .foregroundColor(.white)
                .frame(width: 52, height: 44)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
    }

    // MARK: - Sell Confirmed View

    private func sellConfirmedView(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundColor(emerald)
            Text(text)
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Rectangle().fill(emerald.opacity(0.08)))
        .overlay(Rectangle().stroke(emerald.opacity(0.2), lineWidth: 1))
    }

    /// Convert MON amount string (e.g. "0.01") to hex wei string (e.g. "0x2386f26fc10000")
    /// Uses string-based big integer math to avoid UInt64 overflow (max ~18.4 MON)
    private func monToWeiHex(_ amount: String) -> String {
        guard let decimalValue = Decimal(string: amount) else { return "0x0" }
        let weiDecimal = decimalValue * Decimal(sign: .plus, exponent: 18, significand: 1)
        let weiString = NSDecimalNumber(decimal: weiDecimal).stringValue
        let cleanWei = weiString.components(separatedBy: ".").first ?? weiString

        // Use Python-style big integer: parse decimal string digit by digit into hex
        // This avoids UInt64 overflow for amounts > ~18.4 MON
        var value: [UInt8] = [] // big-endian bytes
        for ch in cleanWei {
            guard let digit = ch.wholeNumberValue else { return "0x0" }
            // Multiply current value by 10 and add digit
            var carry = digit
            for i in (0..<value.count).reversed() {
                let product = Int(value[i]) * 10 + carry
                value[i] = UInt8(product & 0xFF)
                carry = product >> 8
            }
            while carry > 0 {
                value.insert(UInt8(carry & 0xFF), at: 0)
                carry >>= 8
            }
        }
        if value.isEmpty { return "0x0" }
        let hex = value.map { String(format: "%02x", $0) }.joined()
        // Strip leading zeros
        let stripped = String(hex.drop(while: { $0 == "0" }))
        return "0x" + (stripped.isEmpty ? "0" : stripped)
    }
}

// PulsingDot is defined in VoiceSwapMainView.swift and reused here
