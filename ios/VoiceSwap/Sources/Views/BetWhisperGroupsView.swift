/**
 * BetWhisperGroupsView.swift
 * BetWhisper - Groups management (create, join, detail, leaderboard)
 *
 * Mobile-first group betting UI with AI Gate status.
 * Mirrors the web drawer at betwhisper.ai/predict.
 */

import SwiftUI

private let purple = Color(hex: "836EF9")
private let emerald = Color(hex: "10B981")
private let red400 = Color(hex: "EF4444")
private let amber400 = Color(hex: "F59E0B")
private let isSpanish = Locale.current.language.languageCode?.identifier == "es"
private func loc(_ en: String, _ es: String) -> String { isSpanish ? es : en }

// MARK: - View State

private enum GroupsViewState {
    case list
    case create
    case join
    case detail(String) // invite code
}

// MARK: - Groups View

struct BetWhisperGroupsView: View {
    @State private var viewState: GroupsViewState = .list
    @State private var groups: [GroupInfo] = []
    @State private var loading = false
    @State private var aiGateEligible = false

    // Create
    @State private var createName = ""
    @State private var createMode = "leaderboard"

    // Join
    @State private var joinCode = ""
    @State private var joinError = ""
    @State private var joinSuccess: JoinGroupResult?

    // New group code
    @State private var newGroupCode = ""
    @State private var copied = false

    // Detail
    @State private var groupDetail: GroupDetail?
    @State private var leaderboard: [LeaderboardEntry] = []

    private var walletAddress: String {
        VoiceSwapWallet.shared.isCreated ? VoiceSwapWallet.shared.address : ""
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    switch viewState {
                    case .list:
                        listView
                    case .create:
                        createView
                    case .join:
                        joinView
                    case .detail(let code):
                        detailView(code: code)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 40)
            }
        }
        .onAppear { fetchGroups(); checkEligibility() }
    }

    // MARK: - List View

    private var listView: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text(loc("Groups", "Grupos"))
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.white)
                .padding(.bottom, 4)

            // AI Gate status
            HStack(spacing: 8) {
                Image(systemName: aiGateEligible ? "lock.open.fill" : "lock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(aiGateEligible ? emerald : purple)
                Text(aiGateEligible
                     ? loc("AI UNLOCKED", "IA DESBLOQUEADA")
                     : loc("INVITE 1 FRIEND TO UNLOCK AI", "INVITA 1 AMIGO PARA DESBLOQUEAR IA"))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(aiGateEligible ? emerald : purple)
                Spacer()
            }
            .padding(12)
            .background(Rectangle().fill((aiGateEligible ? emerald : purple).opacity(0.06)))
            .overlay(Rectangle().stroke((aiGateEligible ? emerald : purple).opacity(0.2), lineWidth: 1))

            // New group code
            if !newGroupCode.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("INVITE CODE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(purple)
                        .tracking(1.5)
                    HStack {
                        Text(newGroupCode)
                            .font(.system(size: 24, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .tracking(4)
                        Spacer()
                        Button {
                            UIPasteboard.general.string = newGroupCode
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                        } label: {
                            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 14))
                                .foregroundColor(copied ? emerald : .white.opacity(0.4))
                                .frame(width: 36, height: 36)
                                .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                        }
                    }
                    Text(loc("Share this code with friends to start competing", "Comparte este codigo con amigos para competir"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(16)
                .background(Rectangle().fill(purple.opacity(0.05)))
                .overlay(Rectangle().stroke(purple.opacity(0.3), lineWidth: 1))
            }

            // Groups list
            if loading {
                HStack {
                    Spacer()
                    ProgressView().tint(.white.opacity(0.3))
                    Text(loc("Loading...", "Cargando..."))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                    Spacer()
                }
                .padding(.vertical, 32)
            } else if groups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.3")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.15))
                    Text(loc("No groups yet", "Sin grupos aun"))
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                    Text(loc("Create a group or join with an invite code", "Crea un grupo o unete con un codigo de invitacion"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.2))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 6) {
                    ForEach(groups) { g in
                        Button {
                            viewState = .detail(g.invite_code)
                            fetchDetail(g.invite_code)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(g.name)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white)
                                    HStack(spacing: 8) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "person.2")
                                                .font(.system(size: 9))
                                            Text("\(g.member_count ?? 0)")
                                                .font(.system(size: 10, design: .monospaced))
                                        }
                                        .foregroundColor(.white.opacity(0.3))

                                        Text(g.mode == "draft_pool" ? "DRAFT POOL" : "LEADERBOARD")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(purple.opacity(0.6))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .overlay(Rectangle().stroke(purple.opacity(0.2), lineWidth: 1))
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundColor(.white.opacity(0.2))
                            }
                            .padding(12)
                            .background(Rectangle().fill(Color.white.opacity(0.04)))
                            .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                        }
                    }
                }
            }

            // CTAs
            HStack(spacing: 8) {
                Button {
                    viewState = .create
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("CREATE")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Rectangle().fill(purple))
                }

                Button {
                    viewState = .join
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 12, weight: .bold))
                        Text("JOIN")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Create View

    private var createView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Back + header
            HStack(spacing: 8) {
                Button { viewState = .list } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 28, height: 28)
                }
                Text(loc("CREATE GROUP", "CREAR GRUPO"))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1.5)
                Spacer()
            }

            // Name
            VStack(alignment: .leading, spacing: 6) {
                Text("NAME")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1)
                TextField(loc("e.g. Crypto Degens", "ej. Crypto Degens"), text: $createName)
                    .font(.system(size: 14))
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Rectangle().fill(Color.clear))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .tint(.white)
            }

            // Mode
            VStack(alignment: .leading, spacing: 6) {
                Text("MODE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1)
                HStack(spacing: 8) {
                    modeButton("leaderboard", label: "LEADERBOARD")
                    modeButton("draft_pool", label: "DRAFT POOL")
                }
                Text(createMode == "leaderboard"
                     ? loc("Free competition. Each member picks their own markets. Ranked by P&L.",
                           "Competencia libre. Cada miembro elige sus mercados. Ranking por P&L.")
                     : loc("Same market for everyone. Pure conviction test.",
                           "Mismo mercado para todos. Prueba de conviccion pura."))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.2))
            }

            // Create button
            Button {
                createGroup()
            } label: {
                if loading {
                    ProgressView().tint(.white).frame(maxWidth: .infinity).padding(.vertical, 12)
                } else {
                    Text(loc("CREATE GROUP", "CREAR GRUPO"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(createName.trimmingCharacters(in: .whitespaces).isEmpty ? .white.opacity(0.2) : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .background(Rectangle().fill(createName.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.1) : purple))
            .disabled(createName.trimmingCharacters(in: .whitespaces).isEmpty || loading)

            Spacer()
        }
    }

    private func modeButton(_ mode: String, label: String) -> some View {
        Button { createMode = mode } label: {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(createMode == mode ? purple : .white.opacity(0.3))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Rectangle().fill(createMode == mode ? purple.opacity(0.1) : Color.clear))
                .overlay(Rectangle().stroke(createMode == mode ? purple.opacity(0.4) : Color.white.opacity(0.1), lineWidth: 1))
        }
    }

    // MARK: - Join View

    private var joinView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Button {
                    viewState = .list
                    joinError = ""
                    joinSuccess = nil
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 28, height: 28)
                }
                Text(loc("JOIN GROUP", "UNIRSE A GRUPO"))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1.5)
                Spacer()
            }

            if let success = joinSuccess {
                // Success state
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(emerald)
                    Text(loc("Joined \(success.group_name)", "Te uniste a \(success.group_name)"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                    Text("\(success.member_count) \(loc("members", "miembros"))")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                    Button {
                        viewState = .list
                        joinSuccess = nil
                        fetchGroups()
                    } label: {
                        Text(loc("VIEW GROUPS", "VER GRUPOS"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .overlay(Rectangle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .background(Rectangle().fill(emerald.opacity(0.05)))
                .overlay(Rectangle().stroke(emerald.opacity(0.2), lineWidth: 1))
            } else {
                // Code input
                VStack(alignment: .leading, spacing: 6) {
                    Text("INVITE CODE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .tracking(1)
                    TextField("e.g. BW-ABC123", text: $joinCode)
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white)
                        .tracking(2)
                        .textInputAutocapitalization(.characters)
                        .padding(12)
                        .background(Rectangle().fill(Color.clear))
                        .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                        .tint(.white)
                }

                if !joinError.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(red400)
                        Text(joinError)
                            .font(.system(size: 11))
                            .foregroundColor(red400.opacity(0.8))
                    }
                }

                Button {
                    handleJoin()
                } label: {
                    if loading {
                        ProgressView().tint(.black).frame(maxWidth: .infinity).padding(.vertical, 12)
                    } else {
                        Text("JOIN")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(joinCode.trimmingCharacters(in: .whitespaces).isEmpty ? .white.opacity(0.2) : .black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                }
                .background(Rectangle().fill(joinCode.trimmingCharacters(in: .whitespaces).isEmpty ? Color.white.opacity(0.1) : Color.white))
                .disabled(joinCode.trimmingCharacters(in: .whitespaces).isEmpty || loading)
            }

            Spacer()
        }
    }

    // MARK: - Detail View

    private func detailView(code: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    viewState = .list
                    groupDetail = nil
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 28, height: 28)
                }
                Text(groupDetail?.name.uppercased() ?? "GROUP")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
                    .tracking(1.5)
                Spacer()
            }

            if loading || groupDetail == nil {
                HStack {
                    Spacer()
                    ProgressView().tint(.white.opacity(0.3))
                    Spacer()
                }
                .padding(.vertical, 32)
            } else if let detail = groupDetail {
                // Invite code
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("INVITE CODE")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                            .tracking(1)
                        Text(detail.invite_code)
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .tracking(3)
                    }
                    Spacer()
                    Button {
                        UIPasteboard.general.string = detail.invite_code
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 14))
                            .foregroundColor(copied ? emerald : .white.opacity(0.4))
                            .frame(width: 36, height: 36)
                            .overlay(Rectangle().stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                }
                .padding(12)
                .background(Rectangle().fill(Color.white.opacity(0.04)))
                .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))

                // AI Gate status
                let memberCount = detail.member_count ?? detail.members.count
                HStack(spacing: 8) {
                    Image(systemName: memberCount >= 2 ? "lock.open.fill" : "lock.fill")
                        .font(.system(size: 11))
                        .foregroundColor(memberCount >= 2 ? emerald : amber400)
                    Text(memberCount >= 2
                         ? loc("AI UNLOCKED", "IA DESBLOQUEADA")
                         : loc("\(2 - memberCount) more friend\(2 - memberCount != 1 ? "s" : "") needed",
                               "\(2 - memberCount) amigo\(2 - memberCount != 1 ? "s" : "") mas"))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(memberCount >= 2 ? emerald : amber400)
                    Spacer()
                }
                .padding(10)
                .background(Rectangle().fill((memberCount >= 2 ? emerald : amber400).opacity(0.04)))
                .overlay(Rectangle().stroke((memberCount >= 2 ? emerald : amber400).opacity(0.2), lineWidth: 1))

                // Members
                VStack(spacing: 0) {
                    HStack {
                        Text("MEMBERS (\(memberCount))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.3))
                            .tracking(1.5)
                        Spacer()
                    }
                    .padding(10)
                    .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

                    ForEach(Array(detail.members.enumerated()), id: \.element.wallet_address) { i, member in
                        HStack(spacing: 8) {
                            if i == 0 {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 10))
                                    .foregroundColor(amber400)
                            }
                            Text(truncate(member.wallet_address))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                            if member.wallet_address.lowercased() == walletAddress.lowercased() {
                                Text("YOU")
                                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                                    .foregroundColor(purple)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .overlay(Rectangle().stroke(purple.opacity(0.2), lineWidth: 1))
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .overlay(
                            i < detail.members.count - 1
                                ? Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.04))
                                : nil,
                            alignment: .bottom
                        )
                    }
                }
                .background(Rectangle().fill(Color.white.opacity(0.04)))
                .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))

                // Leaderboard
                if !leaderboard.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            Text("LEADERBOARD")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.3))
                                .tracking(1.5)
                            Spacer()
                        }
                        .padding(10)
                        .overlay(Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.06)), alignment: .bottom)

                        ForEach(Array(leaderboard.enumerated()), id: \.element.wallet_address) { i, entry in
                            let pnl = Double(entry.total_pnl) ?? 0
                            HStack {
                                Text("\(i + 1)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.3))
                                    .frame(width: 16)
                                Text(truncate(entry.wallet_address))
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.6))
                                Spacer()
                                Text("\(entry.bet_count) bets")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.3))
                                Text("\(pnl >= 0 ? "+" : "")$\(String(format: "%.2f", abs(pnl)))")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(pnl >= 0 ? emerald : red400)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .overlay(
                                i < leaderboard.count - 1
                                    ? Rectangle().frame(height: 1).foregroundColor(.white.opacity(0.04))
                                    : nil,
                                alignment: .bottom
                            )
                        }
                    }
                    .background(Rectangle().fill(Color.white.opacity(0.04)))
                    .overlay(Rectangle().stroke(Color.white.opacity(0.08), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - Actions

    private func fetchGroups() {
        guard !walletAddress.isEmpty else { return }
        loading = true
        Task {
            do {
                let result = try await VoiceSwapAPIClient.shared.listGroups(wallet: walletAddress)
                await MainActor.run { groups = result; loading = false }
            } catch {
                print("[Groups] Fetch error: \(error)")
                await MainActor.run { loading = false }
            }
        }
    }

    private func checkEligibility() {
        guard !walletAddress.isEmpty else { return }
        Task {
            do {
                let result = try await VoiceSwapAPIClient.shared.checkGroupEligibility(wallet: walletAddress)
                await MainActor.run { aiGateEligible = result.eligible }
            } catch {
                print("[Groups] Eligibility check error: \(error)")
            }
        }
    }

    private func createGroup() {
        let name = createName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !walletAddress.isEmpty else { return }
        loading = true
        Task {
            do {
                let group = try await VoiceSwapAPIClient.shared.createGroup(
                    name: name, mode: createMode, creatorWallet: walletAddress
                )
                await MainActor.run {
                    newGroupCode = group.invite_code
                    createName = ""
                    viewState = .list
                    loading = false
                    fetchGroups()
                }
            } catch {
                print("[Groups] Create error: \(error)")
                await MainActor.run { loading = false }
            }
        }
    }

    private func handleJoin() {
        let code = joinCode.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty, !walletAddress.isEmpty else { return }
        loading = true
        joinError = ""
        Task {
            do {
                let result = try await VoiceSwapAPIClient.shared.joinGroup(code: code, wallet: walletAddress)
                await MainActor.run {
                    joinSuccess = result
                    joinCode = ""
                    loading = false
                    checkEligibility()
                    fetchGroups()
                }
            } catch {
                let msg = (error as? APIError)?.errorDescription ?? "Failed to join"
                await MainActor.run { joinError = msg; loading = false }
            }
        }
    }

    private func fetchDetail(_ code: String) {
        loading = true
        Task {
            do {
                async let detailReq = VoiceSwapAPIClient.shared.getGroupDetail(code: code)
                async let lbReq = VoiceSwapAPIClient.shared.getGroupLeaderboard(code: code)
                let (detail, lb) = try await (detailReq, lbReq)
                await MainActor.run {
                    groupDetail = detail
                    leaderboard = lb.leaderboard
                    loading = false
                }
            } catch {
                print("[Groups] Detail error: \(error)")
                await MainActor.run { loading = false }
            }
        }
    }

    private func truncate(_ addr: String) -> String {
        guard addr.count > 10 else { return addr }
        return String(addr.prefix(6)) + "..." + String(addr.suffix(4))
    }
}
