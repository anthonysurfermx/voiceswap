/**
 * BetWhisperPulseMapView.swift
 * BetWhisper — Social Pulse Map (iOS)
 *
 * Live heatmap showing trading activity around the hackathon venue.
 * Fetches from betwhisper.ai/api/pulse/heatmap + SSE stream.
 * MapKit + SwiftUI overlays for trade animations.
 */

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Data Models

struct HeatmapPoint: Identifiable {
    let id = UUID()
    let lat: Double
    let lng: Double
    let intensity: Double
    let side: String
    let timestamp: TimeInterval
    let executionMode: String // "direct" or "unlink"

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var isZK: Bool { executionMode == "unlink" }
}

struct PulseStats {
    let marketName: String
    let teamA: (name: String, pct: Int, price: Double)
    let teamB: (name: String, pct: Int, price: Double)
    let activeTraders: Int
    let totalVolume: Int
    let spikeIndicator: Double
    let globalComparison: String
    let zkPrivateCount: Int
    let zkPrivatePct: Int
}

struct TradePopup: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let side: String
    let amount: String
    let isZK: Bool
    let createdAt: Date = Date()
}

// MARK: - Main Pulse Map View

struct BetWhisperPulseMapView: View {
    @StateObject private var viewModel = PulseMapViewModel()
    @State private var showStats = true

    // Hackathon venue: 50 W 23rd St, NYC
    private let initialRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 40.7450, longitude: -73.9920),
        span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
    )

    var body: some View {
        ZStack {
            // Map
            Map(initialPosition: .region(initialRegion)) {
                // Heatmap dots
                ForEach(viewModel.points) { point in
                    MapCircle(center: point.coordinate, radius: radiusForIntensity(point.intensity))
                        .foregroundStyle(colorForPoint(point).opacity(point.intensity * 0.6))
                }

                // Trade popups (animated)
                ForEach(viewModel.activePopups) { popup in
                    Annotation("", coordinate: popup.coordinate) {
                        TradePopupBubble(popup: popup)
                    }
                }

                // User location marker
                if let userLoc = viewModel.userLocation {
                    Annotation("YOU", coordinate: userLoc) {
                        RadarMarkerView()
                    }
                }
            }
            .mapStyle(.imagery(elevation: .flat))
            .mapControls {
                MapCompass()
            }
            .ignoresSafeArea()

            // Overlays
            VStack {
                // Top bar: title + connection status
                topBar

                Spacer()

                // Stats panel (bottom)
                if showStats, let stats = viewModel.stats {
                    statsPanel(stats)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            // Live trade feed (top-left)
            VStack {
                HStack {
                    tradeFeed
                    Spacer()
                }
                .padding(.top, 90)
                Spacer()
            }

            // Scan line animation
            if viewModel.showScanLine {
                scanLine
            }
        }
        .onAppear {
            viewModel.startPolling()
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            // Pulse dot
            Circle()
                .fill(viewModel.isConnected ? Color(hex: "10B981") : Color(hex: "EF4444"))
                .frame(width: 6, height: 6)
                .shadow(color: viewModel.isConnected ? Color(hex: "10B981") : .clear, radius: 4)

            Text("SOCIAL PULSE")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white)

            Spacer()

            // Trade count
            if viewModel.tradeCount > 0 {
                Text("\(viewModel.tradeCount) TRADES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .tracking(1)
            }

            // Toggle stats
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showStats.toggle()
                }
            } label: {
                Image(systemName: showStats ? "chart.bar.fill" : "chart.bar")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.9)
        )
        .padding(.top, 50)
    }

    // MARK: - Stats Panel

    private func statsPanel(_ stats: PulseStats) -> some View {
        VStack(spacing: 0) {
            // Market name + traders
            HStack {
                Text(stats.marketName)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10))
                    Text("\(stats.activeTraders)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundColor(Color(hex: "836EF9"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Flow bar
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color(hex: "836EF9"))
                    .frame(width: CGFloat(stats.teamA.pct) / 100.0 * (UIScreen.main.bounds.width - 32))

                Rectangle()
                    .fill(Color(hex: "EF4444"))
            }
            .frame(height: 4)
            .clipShape(RoundedRectangle(cornerRadius: 2))
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Labels under flow bar
            HStack {
                Text("\(stats.teamA.name) \(stats.teamA.pct)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "836EF9"))
                Spacer()
                Text("\(stats.teamB.name) \(stats.teamB.pct)%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "EF4444"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)

            // Volume + ZK stats
            HStack(spacing: 16) {
                // Volume
                HStack(spacing: 4) {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 10))
                    Text("$\(stats.totalVolume)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white.opacity(0.6))

                // Spike indicator
                if stats.spikeIndicator > 2.0 {
                    HStack(spacing: 2) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: 9))
                        Text("\(String(format: "%.1f", stats.spikeIndicator))x")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(Color(hex: "FFC107"))
                }

                Spacer()

                // ZK privacy
                HStack(spacing: 4) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 10))
                    Text("\(stats.zkPrivatePct)% ZK")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundColor(Color(hex: "10B981"))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // Global comparison
            Text(stats.globalComparison)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .lineLimit(2)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 12)
        }
        .background(
            Rectangle()
                .fill(Color.black.opacity(0.85))
        )
        .overlay(
            Rectangle()
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    // MARK: - Trade Feed

    private var tradeFeed: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(viewModel.recentTrades.prefix(5)) { trade in
                HStack(spacing: 6) {
                    Circle()
                        .fill(trade.isZK ? Color(hex: "10B981") : Color(hex: "836EF9"))
                        .frame(width: 5, height: 5)

                    Text("\(trade.side)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))

                    Text(trade.amount)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))

                    if trade.isZK {
                        Image(systemName: "lock.shield.fill")
                            .font(.system(size: 7))
                            .foregroundColor(Color(hex: "10B981").opacity(0.6))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                )
            }
        }
        .padding(.leading, 12)
    }

    // MARK: - Scan Line

    private var scanLine: some View {
        GeometryReader { geo in
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.clear, Color(hex: "836EF9").opacity(0.4), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 2)
                .offset(y: viewModel.scanLineY * geo.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Helpers

    private func radiusForIntensity(_ intensity: Double) -> CLLocationDistance {
        // 30m to 150m based on intensity
        return 30 + intensity * 120
    }

    private func colorForPoint(_ point: HeatmapPoint) -> Color {
        if point.isZK {
            return Color(hex: "10B981") // Emerald for ZK
        }
        // Purple gradient based on intensity
        if point.intensity > 0.7 {
            return Color(hex: "FFC107") // High intensity = amber/yellow
        }
        return Color(hex: "836EF9") // Normal = purple
    }
}

// MARK: - Trade Popup Bubble

struct TradePopupBubble: View {
    let popup: TradePopup
    @State private var opacity: Double = 0
    @State private var offset: CGFloat = 0
    @State private var scale: CGFloat = 0.5

    var body: some View {
        VStack(spacing: 2) {
            Text("+\(popup.amount)")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(popup.isZK ? Color(hex: "10B981") : Color(hex: "836EF9"))

            Text(popup.side)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.black.opacity(0.8))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(
                            popup.isZK ? Color(hex: "10B981").opacity(0.4) : Color(hex: "836EF9").opacity(0.4),
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(scale)
        .opacity(opacity)
        .offset(y: offset)
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                opacity = 1
                scale = 1
            }
            withAnimation(.easeOut(duration: 2.5)) {
                offset = -50
            }
            withAnimation(.easeOut(duration: 2.5).delay(1.5)) {
                opacity = 0
            }
        }
    }
}

// MARK: - Radar Marker (User Location)

struct RadarMarkerView: View {
    @State private var sweepAngle: Double = 0
    @State private var pingScale: CGFloat = 0.3
    @State private var pingOpacity: Double = 0.6

    var body: some View {
        ZStack {
            // Ping ring
            Circle()
                .stroke(Color(hex: "836EF9").opacity(pingOpacity), lineWidth: 1.5)
                .frame(width: 40 * pingScale, height: 40 * pingScale)

            // Sweep
            Circle()
                .trim(from: 0, to: 0.25)
                .stroke(Color(hex: "836EF9").opacity(0.3), lineWidth: 1)
                .frame(width: 30, height: 30)
                .rotationEffect(.degrees(sweepAngle))

            // Center dot
            Circle()
                .fill(Color(hex: "836EF9"))
                .frame(width: 8, height: 8)
                .shadow(color: Color(hex: "836EF9"), radius: 6)
        }
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                sweepAngle = 360
            }
            withAnimation(.easeOut(duration: 2).repeatForever(autoreverses: false)) {
                pingScale = 2
                pingOpacity = 0
            }
        }
    }
}

// MARK: - ViewModel

@MainActor
class PulseMapViewModel: ObservableObject {
    @Published var points: [HeatmapPoint] = []
    @Published var stats: PulseStats?
    @Published var activePopups: [TradePopup] = []
    @Published var recentTrades: [TradePopup] = []
    @Published var isConnected = false
    @Published var tradeCount = 0
    @Published var showScanLine = false
    @Published var scanLineY: CGFloat = 0
    @Published var userLocation: CLLocationCoordinate2D?

    private let baseURL = "https://betwhisper.ai"
    private var pollTimer: Timer?
    private var sseTask: Task<Void, Never>?

    func startPolling() {
        // Initial fetch
        fetchHeatmap()

        // Poll every 8 seconds
        pollTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fetchHeatmap()
            }
        }

        // Start SSE stream
        connectSSE()

        // Get user location
        if let loc = VoiceSwapAPIClient.lastKnownLocation {
            userLocation = CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        sseTask?.cancel()
        sseTask = nil
    }

    // MARK: - Heatmap Fetch

    private func fetchHeatmap() {
        guard let url = URL(string: "\(baseURL)/api/pulse/heatmap") else { return }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

                // Parse points
                if let rawPoints = json?["points"] as? [[String: Any]] {
                    points = rawPoints.compactMap { p in
                        guard let lat = p["lat"] as? Double,
                              let lng = p["lng"] as? Double else { return nil }
                        return HeatmapPoint(
                            lat: lat,
                            lng: lng,
                            intensity: p["intensity"] as? Double ?? 0.5,
                            side: p["side"] as? String ?? "Yes",
                            timestamp: p["timestamp"] as? TimeInterval ?? Date().timeIntervalSince1970 * 1000,
                            executionMode: p["executionMode"] as? String ?? "direct"
                        )
                    }
                }

                // Parse stats
                if let rawStats = json?["stats"] as? [String: Any] {
                    let teamA = rawStats["teamA"] as? [String: Any] ?? [:]
                    let teamB = rawStats["teamB"] as? [String: Any] ?? [:]

                    stats = PulseStats(
                        marketName: rawStats["marketName"] as? String ?? "Loading...",
                        teamA: (
                            name: teamA["name"] as? String ?? "YES",
                            pct: teamA["pct"] as? Int ?? 50,
                            price: teamA["price"] as? Double ?? 0.5
                        ),
                        teamB: (
                            name: teamB["name"] as? String ?? "NO",
                            pct: teamB["pct"] as? Int ?? 50,
                            price: teamB["price"] as? Double ?? 0.5
                        ),
                        activeTraders: rawStats["activeTraders"] as? Int ?? 0,
                        totalVolume: rawStats["totalVolume"] as? Int ?? 0,
                        spikeIndicator: rawStats["spikeIndicator"] as? Double ?? 1.0,
                        globalComparison: rawStats["globalComparison"] as? String ?? "",
                        zkPrivateCount: rawStats["zkPrivateCount"] as? Int ?? 0,
                        zkPrivatePct: rawStats["zkPrivatePct"] as? Int ?? 0
                    )
                }

                // Trigger scan line
                triggerScanLine()

            } catch {
                print("[Pulse] Heatmap fetch error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - SSE Stream

    private func connectSSE() {
        guard let url = URL(string: "\(baseURL)/api/pulse/stream") else { return }

        sseTask = Task {
            var request = URLRequest(url: url)
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 300

            do {
                let (bytes, response) = try await URLSession.shared.bytes(from: url)

                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    print("[Pulse] SSE connection failed")
                    return
                }

                isConnected = true

                for try await line in bytes.lines {
                    guard !Task.isCancelled else { break }

                    // SSE format: "data: {...}"
                    guard line.hasPrefix("data: ") else { continue }
                    let jsonStr = String(line.dropFirst(6))

                    guard let data = jsonStr.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let type = json["type"] as? String else { continue }

                    if type == "trade" {
                        let lat = json["lat"] as? Double ?? 40.745
                        let lng = json["lng"] as? Double ?? -73.992
                        let side = json["side"] as? String ?? "Yes"
                        let bucket = json["amountBucket"] as? String ?? "1-10"
                        let mode = json["executionMode"] as? String ?? "direct"

                        tradeCount += 1

                        // Add popup
                        let popup = TradePopup(
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                            side: side,
                            amount: amountFromBucket(bucket),
                            isZK: mode == "unlink"
                        )
                        activePopups.append(popup)
                        recentTrades.insert(popup, at: 0)

                        // Limit popups
                        if activePopups.count > 8 {
                            activePopups.removeFirst()
                        }
                        if recentTrades.count > 10 {
                            recentTrades.removeLast()
                        }

                        // Remove popup after 3s
                        let popupId = popup.id
                        Task {
                            try? await Task.sleep(nanoseconds: 3_000_000_000)
                            activePopups.removeAll { $0.id == popupId }
                        }

                        // Trigger scan line
                        triggerScanLine()

                        // Add to heatmap
                        let newPoint = HeatmapPoint(
                            lat: lat,
                            lng: lng,
                            intensity: intensityFromBucket(bucket),
                            side: side,
                            timestamp: Date().timeIntervalSince1970 * 1000,
                            executionMode: mode
                        )
                        points.append(newPoint)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    print("[Pulse] SSE error: \(error.localizedDescription)")
                    isConnected = false

                    // Retry after 5s
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                    if !Task.isCancelled {
                        connectSSE()
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func amountFromBucket(_ bucket: String) -> String {
        switch bucket {
        case "1-10": return "$\(Int.random(in: 1...10))"
        case "10-50": return "$\(Int.random(in: 10...50))"
        case "50-100": return "$\(Int.random(in: 50...100))"
        case "100+": return "$\(Int.random(in: 100...500))"
        default: return "$5"
        }
    }

    private func intensityFromBucket(_ bucket: String) -> Double {
        switch bucket {
        case "1-10": return 0.3
        case "10-50": return 0.55
        case "50-100": return 0.75
        case "100+": return 0.95
        default: return 0.4
        }
    }

    private func triggerScanLine() {
        showScanLine = true
        scanLineY = 0
        withAnimation(.easeInOut(duration: 2)) {
            scanLineY = 1
        }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            showScanLine = false
        }
    }
}
