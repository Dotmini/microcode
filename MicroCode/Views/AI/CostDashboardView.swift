import SwiftUI

// MARK: - Cost Dashboard View
// Apple HIG Monochrome Design — Real-time AI token usage & cost tracking

struct CostDashboardView: View {
    @ObservedObject private var tracker = AIUsageTracker.shared
    @ObservedObject private var router = AIModelRouter.shared
    @State private var selectedTimeRange: TimeRange = .session
    @State private var showExportSheet = false
    @State private var copiedToast = false
    
    enum TimeRange: String, CaseIterable {
        case session = "This Session"
        case today = "Today"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            dashboardHeader
            
            Divider().background(Color.white.opacity(0.1))
            
            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 16) {
                    // Key Metrics Cards
                    metricsRow
                    
                    // Routing Strategy Selector
                    routingStrategySection
                    
                    Divider().background(Color.white.opacity(0.08))
                    
                    // Usage by Provider
                    if !tracker.records.isEmpty {
                        providerBreakdown
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        // Usage by Model
                        modelBreakdown
                        
                        Divider().background(Color.white.opacity(0.08))
                        
                        // Recent Activity
                        recentActivity
                    } else {
                        emptyState
                    }
                }
                .padding(16)
            }
        }
        .background(Color.black)
        .overlay(alignment: .top) {
            if copiedToast {
                toastBanner("Copied to clipboard")
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: copiedToast)
    }
    
    // MARK: - Header
    
    private var dashboardHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            
            Text("Cost Dashboard")
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
            
            Spacer()
            
            // Budget Alert Toggle
            if tracker.budgetAlertThreshold > 0 {
                HStack(spacing: 4) {
                    Image(systemName: tracker.budgetAlertTriggered ? "exclamationmark.triangle.fill" : "bell.fill")
                        .font(.system(size: 10))
                        .foregroundColor(tracker.budgetAlertTriggered ? .orange : .white.opacity(0.4))
                    Text(String(format: "$%.2f limit", tracker.budgetAlertThreshold))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            // Export Button
            Button(action: {
                let csv = tracker.exportCSV()
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(csv, forType: .string)
                copiedToast = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedToast = false }
            }) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Export usage as CSV")
            
            // Reset Button
            Button(action: {
                tracker.resetSession()
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .help("Reset session stats")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(white: 0.06))
    }
    
    // MARK: - Key Metrics Row
    
    private var metricsRow: some View {
        HStack(spacing: 10) {
            metricCard(
                icon: "dollarsign.circle.fill",
                label: "Est. Cost",
                value: tracker.formattedSessionCost(),
                accent: tracker.sessionCostUSD > 1.0 ? Color.orange : Color.white
            )
            
            metricCard(
                icon: "number.circle.fill",
                label: "Tokens",
                value: tracker.formattedSessionTokens(),
                accent: .white
            )
            
            metricCard(
                icon: "arrow.up.arrow.down.circle.fill",
                label: "Requests",
                value: "\(tracker.sessionRequests)",
                accent: .white
            )
            
            metricCard(
                icon: "gauge.open.with.lines.needle.33percent",
                label: "Avg/Req",
                value: tracker.sessionRequests > 0
                    ? "\(tracker.sessionTokens / max(tracker.sessionRequests, 1))"
                    : "—",
                accent: .white
            )
        }
    }
    
    private func metricCard(icon: String, label: String, value: String, accent: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(accent.opacity(0.7))
            
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }
    
    // MARK: - Routing Strategy
    
    private var routingStrategySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Text("Model Routing Strategy")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            HStack(spacing: 0) {
                ForEach(AIModelRouter.RoutingStrategy.allCases, id: \.rawValue) { strategy in
                    Button(action: { router.activeStrategy = strategy }) {
                        Text(strategyShortName(strategy))
                            .font(.system(size: 10, weight: router.activeStrategy == strategy ? .bold : .medium, design: .monospaced))
                            .foregroundColor(router.activeStrategy == strategy ? .white : .white.opacity(0.4))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                router.activeStrategy == strategy
                                    ? Color(white: 0.2)
                                    : Color.clear
                            )
                    }
                    .buttonStyle(.plain)
                    
                    if strategy != AIModelRouter.RoutingStrategy.allCases.last {
                        Divider()
                            .frame(height: 16)
                            .background(Color.white.opacity(0.1))
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(white: 0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    )
            )
            
            Text(strategyDescription(router.activeStrategy))
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.35))
        }
    }
    
    private func strategyShortName(_ s: AIModelRouter.RoutingStrategy) -> String {
        switch s {
        case .smart: return "Smart"
        case .costOptimized: return "Cheap"
        case .speedOptimized: return "Fast"
        case .qualityOptimized: return "Best"
        case .manual: return "Manual"
        }
    }
    
    private func strategyDescription(_ s: AIModelRouter.RoutingStrategy) -> String {
        switch s {
        case .smart: return "Auto-analyzes prompt complexity and picks the optimal model for each task"
        case .costOptimized: return "Always uses the cheapest model that can handle the task"
        case .speedOptimized: return "Prioritizes fastest response time (Flash/Mini models)"
        case .qualityOptimized: return "Uses the most capable model available (Opus/Pro/GPT-6)"
        case .manual: return "Uses your manually selected model — no automatic switching"
        }
    }
    
    // MARK: - Provider Breakdown
    
    private var providerBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "building.2.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Text("By Provider")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            let summary = tracker.sessionSummary()
            let sortedProviders = summary.byProvider.values.sorted { $0.estimatedCostUSD > $1.estimatedCostUSD }
            
            ForEach(sortedProviders, id: \.provider) { prov in
                HStack(spacing: 10) {
                    Circle()
                        .fill(providerColor(prov.provider))
                        .frame(width: 8, height: 8)
                    
                    Text(prov.provider.capitalized)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .frame(width: 80, alignment: .leading)
                    
                    // Usage bar
                    GeometryReader { geo in
                        let maxTokens = sortedProviders.first?.totalTokens ?? 1
                        let ratio = CGFloat(prov.totalTokens) / CGFloat(max(maxTokens, 1))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(providerColor(prov.provider).opacity(0.5))
                            .frame(width: geo.size.width * min(ratio, 1.0))
                    }
                    .frame(height: 6)
                    
                    Text("\(prov.requests) req")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .frame(width: 45, alignment: .trailing)
                    
                    Text(formatCost(prov.estimatedCostUSD))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 55, alignment: .trailing)
                }
                .frame(height: 20)
            }
        }
    }
    
    // MARK: - Model Breakdown
    
    private var modelBreakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "cpu.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Text("By Model")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
            }
            
            let summary = tracker.sessionSummary()
            let sortedModels = summary.byModel.values.sorted { $0.totalTokens > $1.totalTokens }
            
            ForEach(sortedModels.prefix(8), id: \.model) { mdl in
                HStack(spacing: 8) {
                    Text(truncateModelName(mdl.model))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 120, alignment: .leading)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("\(formatTokens(mdl.promptTokens))↑")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                    
                    Text("\(formatTokens(mdl.completionTokens))↓")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                    
                    Text(formatCost(mdl.estimatedCostUSD))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 55, alignment: .trailing)
                }
            }
        }
    }
    
    // MARK: - Recent Activity
    
    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.5))
                Text("Recent")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("\(tracker.records.count) total")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            
            ForEach(tracker.records.suffix(15).reversed()) { record in
                HStack(spacing: 6) {
                    Text(timeAgo(record.timestamp))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.25))
                        .frame(width: 40, alignment: .leading)
                    
                    Text(record.taskLabel)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.06)))
                    
                    Text(truncateModelName(record.model))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.35))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text("\(record.totalTokens) tok")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text(formatCost(record.estimatedCostUSD))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(record.estimatedCostUSD > 0.01 ? .white.opacity(0.5) : .white.opacity(0.3))
                        .frame(width: 50, alignment: .trailing)
                }
            }
        }
    }
    
    // MARK: - Empty State
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 40)
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32))
                .foregroundColor(.white.opacity(0.15))
            Text("No usage data yet")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
            Text("Token usage and costs will appear here\nas you use AI features")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.2))
                .multilineTextAlignment(.center)
            Spacer().frame(height: 40)
        }
    }
    
    // MARK: - Toast
    
    private func toastBanner(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color(white: 0.2)))
            .padding(.top, 8)
    }
    
    // MARK: - Helpers
    
    private func providerColor(_ provider: String) -> Color {
        switch provider.lowercased() {
        case "openai", "copilot": return .white
        case "anthropic": return .white.opacity(0.8)
        case "gemini", "google": return .white.opacity(0.9)
        case "deepseek": return .white.opacity(0.7)
        case "local", "ollama": return .white.opacity(0.5)
        default: return .white.opacity(0.6)
        }
    }
    
    private func formatCost(_ usd: Double) -> String {
        if usd == 0 { return "FREE" }
        if usd < 0.001 { return String(format: "$%.4f", usd) }
        if usd < 0.01 { return String(format: "$%.3f", usd) }
        if usd < 1.0 { return String(format: "$%.3f", usd) }
        return String(format: "$%.2f", usd)
    }
    
    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM", Double(count) / 1_000_000.0) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000.0) }
        return "\(count)"
    }
    
    private func truncateModelName(_ name: String) -> String {
        if name.count > 22 {
            return String(name.prefix(22)) + "…"
        }
        return name
    }
    
    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        if seconds < 86400 { return "\(seconds / 3600)h" }
        return "\(seconds / 86400)d"
    }
}

// MARK: - Cost Status Bar Widget (for inline display in header/status bar)

struct CostStatusWidget: View {
    @ObservedObject private var tracker = AIUsageTracker.shared
    
    var body: some View {
        if tracker.sessionRequests > 0 {
            HStack(spacing: 4) {
                Image(systemName: "dollarsign.circle")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.35))
                
                Text(tracker.formattedSessionCost())
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(tracker.sessionCostUSD > 1.0 ? .orange.opacity(0.8) : .white.opacity(0.45))
                    .lineLimit(1)
                
                Text("·")
                    .foregroundColor(.white.opacity(0.2))
                
                Text(tracker.formattedSessionTokens())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white.opacity(0.35))
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .frame(height: 20)
            .background(
                Capsule()
                    .fill(Color(white: 0.08))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5))
            )
            .fixedSize()
            .help("Session: \(tracker.sessionRequests) requests · \(tracker.formattedSessionTokens()) tokens · \(tracker.formattedSessionCost())")
        }
    }
}
