//
//  CodeAnalysisWindow.swift
//  MicroCode
//
//  AI-Powered Code Analysis with Paper-Style Reports
//

import SwiftUI

struct CodeAnalysisWindow: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    @State private var metrics: CodeMetrics?
    @State private var aiReport: AICodeReport?
    @State private var isAnalyzing: Bool = false
    @State private var isAIAnalyzing: Bool = false
    @State private var selectedTab: AnalysisTab = .overview
    @State private var showExportMenu: Bool = false
    
    enum AnalysisTab: String, CaseIterable {
        case overview = "Overview"
        case details = "Details"
        case paper = "Paper Report"
        
        var icon: String {
            switch self {
            case .overview: return "chart.bar"
            case .details: return "list.bullet"
            case .paper: return "doc.text"
            }
        }
    }
    
    var body: some View {
        ToolWindowWrapper(
            title: "AI Code Analysis",
            subtitle: "Detailed code quality and security report",
            icon: "chart.bar.doc.horizontal",
            iconColor: .blue
        ) {
            // Content
            VStack(spacing: 0) {
                // Tab Bar
                tabBar
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .overview:
                            overviewTab
                        case .details:
                            detailsTab
                        case .paper:
                            paperTab
                        }
                    }
                    .padding()
                }
            }
        } footer: {
            footerView
        }
        .onAppear {
            if appState.currentFile != nil {
                analyzeCode()
            }
        }
    }
    
    // MARK: - Header (Removed - Handled by Wrapper)
    
    // MARK: - Tab Bar
    
    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(AnalysisTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                        Text(tab.rawValue)
                    }
                    .font(.system(size: 12))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.2) : Color.clear)
                    .foregroundColor(selectedTab == tab ? .accentColor : .primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Overview Tab
    
    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            if isAnalyzing || isAIAnalyzing {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(isAIAnalyzing ? "🤖 AI is analyzing your code..." : "Analyzing code structure...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
            } else if let report = aiReport {
                // Quality Score Card
                qualityScoreCard(report)
                
                // Summary
                VStack(alignment: .leading, spacing: 8) {
                    Text("📝 Summary")
                        .font(.headline)
                    Text(report.summary)
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // Metrics Grid
                if let metrics = metrics {
                    metricsGrid(metrics)
                }
                
                // Quick Stats
                HStack(spacing: 16) {
                    statCard("✅ Strengths", count: report.strengths.count, color: .green)
                    statCard("⚠️ Weaknesses", count: report.weaknesses.count, color: .orange)
                    statCard("💡 Recommendations", count: report.recommendations.count, color: .blue)
                    statCard("🔒 Security", count: report.securityIssues.count, color: report.securityIssues.isEmpty ? .green : .red)
                }
            } else {
                emptyState
            }
        }
    }
    
    private func qualityScoreCard(_ report: AICodeReport) -> some View {
        HStack(spacing: 20) {
            // Score Circle
            ZStack {
                Circle()
                    .stroke(report.qualityColor.opacity(0.2), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(report.qualityScore) / 100)
                    .stroke(report.qualityColor, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 4) {
                    Text("\(report.qualityScore)")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(report.qualityColor)
                    Text(report.qualityGrade)
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 120, height: 120)
            
            // Details
            VStack(alignment: .leading, spacing: 8) {
                Text("Quality Score")
                    .font(.title2.bold())
                
                Text(String(repeating: "⭐", count: report.qualityStars))
                    .font(.title3)
                
                Text(qualityDescription(report.qualityScore))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(report.qualityColor.opacity(0.1))
        .cornerRadius(16)
    }
    
    private func qualityDescription(_ score: Int) -> String {
        switch score {
        case 90...100: return "Excellent! Code follows best practices"
        case 80..<90: return "Great code with minor improvements"
        case 70..<80: return "Good code, some areas need attention"
        case 60..<70: return "Acceptable, but refactoring recommended"
        case 50..<60: return "Below average, needs significant work"
        default: return "Poor quality, major refactoring needed"
        }
    }
    
    private func metricsGrid(_ metrics: CodeMetrics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "Lines of Code", value: "\(metrics.linesOfCode)", color: .blue)
            MetricCard(title: "Functions", value: "\(metrics.functions)", color: .green)
            MetricCard(title: "Classes", value: "\(metrics.classes)", color: .purple)
            MetricCard(title: "Complexity", value: "\(metrics.complexity)", color: complexityColor(metrics.complexity))
        }
    }
    
    private func complexityColor(_ complexity: Int) -> Color {
        switch complexity {
        case 0..<10: return .green
        case 10..<20: return .yellow
        case 20..<30: return .orange
        default: return .red
        }
    }
    
    private func statCard(_ title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.bold())
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Details Tab
    
    private var detailsTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let report = aiReport {
                // Strengths
                detailSection("✅ Strengths", items: report.strengths, emptyMessage: "No specific strengths identified")
                
                // Weaknesses
                detailSection("⚠️ Areas for Improvement", items: report.weaknesses, emptyMessage: "No weaknesses found - great job!")
                
                // Recommendations
                detailSection("💡 Recommendations", items: report.recommendations, emptyMessage: "No recommendations at this time")
                
                // Security Issues
                if !report.securityIssues.isEmpty {
                    securitySection(report.securityIssues)
                }
            } else {
                emptyState
            }
        }
    }
    
    private func detailSection(_ title: String, items: [ReportItem], emptyMessage: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            
            if items.isEmpty {
                Text(emptyMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(items) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.severity.icon)
                            .foregroundColor(item.severity.color)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.title)
                                    .font(.system(size: 13, weight: .medium))
                                if let line = item.line {
                                    Text("Line \(line)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Text(item.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
        .padding()
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .cornerRadius(12)
    }
    
    private func securitySection(_ issues: [SecurityIssue]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("🔒 Security Issues")
                .font(.headline)
            
            ForEach(issues) { issue in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundColor(issue.severityColor)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(issue.type)
                                .font(.system(size: 13, weight: .medium))
                            Text("[\(issue.severity.uppercased())]")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(issue.severityColor.opacity(0.2))
                                .cornerRadius(4)
                        }
                        Text(issue.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        if !issue.suggestion.isEmpty {
                            Text("💡 \(issue.suggestion)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    Spacer()
                }
                .padding(12)
                .background(issue.severityColor.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color.red.opacity(0.05))
        .cornerRadius(12)
    }
    
    // MARK: - Paper Tab
    
    private var paperTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let report = aiReport {
                // Paper Header
                HStack {
                    Text("📄 Paper-Style Report")
                        .font(.headline)
                    Spacer()
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report.paperReport, forType: .string)
                    }
                    .buttonStyle(.bordered)
                }
                
                // Paper Content (Markdown rendered)
                ScrollView {
                    Text(report.paperReport)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .background(Color(nsColor: .textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            } else {
                emptyState
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Click 'Analyze' to start AI-powered code analysis")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack {
            Text(appState.currentFile?.name ?? "No file selected")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            
            Spacer()
            
            if isAnalyzing || isAIAnalyzing {
                ProgressView()
                    .scaleEffect(0.7)
                Text(isAIAnalyzing ? "AI analyzing..." : "Processing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Button("Analyze") {
                analyzeCode()
            }
            .buttonStyle(.bordered)
            .disabled(appState.currentFile == nil || isAnalyzing || isAIAnalyzing)
            
            Button("AI Deep Analysis") {
                runAIAnalysis()
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.currentFile == nil || isAnalyzing || isAIAnalyzing)
            
            // Export Button (Moved from Header)
            Menu {
                Button("Export as Markdown") {
                    exportAsMarkdown()
                }
                Button("Copy to Clipboard") {
                    copyToClipboard()
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .frame(width: 20)
            }
            .menuStyle(.borderlessButton)
            .buttonStyle(.bordered)
            .disabled(aiReport == nil)
        }
    }
    
    // MARK: - Actions
    
    private func analyzeCode() {
        guard let file = appState.currentFile else { return }
        
        isAnalyzing = true
        
        DispatchQueue.global().async {
            let analyzer = CodeAnalyzer.shared
            let result = analyzer.analyzeComplexity(code: file.content, language: file.language)
            
            DispatchQueue.main.async {
                self.metrics = result
                self.isAnalyzing = false
            }
        }
    }
    
    private func runAIAnalysis() {
        guard let file = appState.currentFile else { return }
        
        isAIAnalyzing = true
        
        Task {
            do {
                // First get basic metrics
                let analyzer = CodeAnalyzer.shared
                let basicMetrics = analyzer.analyzeComplexity(code: file.content, language: file.language)
                
                await MainActor.run {
                    self.metrics = basicMetrics
                }
                
                // Then run AI analysis
                let analysisResult = try await performAIAnalysis(code: file.content, language: file.language)
                
                await MainActor.run {
                    // Generate full report
                    self.aiReport = PaperReportGenerator.generate(
                        fileName: file.name,
                        language: file.language,
                        metrics: basicMetrics,
                        aiAnalysis: analysisResult
                    )
                    self.isAIAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    self.isAIAnalyzing = false
                }
            }
        }
    }
    
    private func performAIAnalysis(code: String, language: String) async throws -> AIAnalysisResult {
        let prompt = """
        Analyze this \(language) code and provide a comprehensive review. Return a JSON response with:
        
        {
            "quality_score": <0-100>,
            "summary": "<brief summary>",
            "strengths": [{"title": "", "description": ""}],
            "weaknesses": [{"title": "", "description": "", "line": <optional>}],
            "recommendations": [{"title": "", "description": ""}],
            "security_issues": [{"type": "", "description": "", "severity": "low|medium|high|critical", "suggestion": ""}]
        }
        
        Code to analyze:
        ```\(language)
        \(code)
        ```
        """
        
        let response = try await BackendService.shared.explainCode(
            code: "Analyze this code and return JSON:\n\(prompt)\n\nCode:\n\(code)",
            provider: appState.aiProvider,
            model: appState.aiModel,
            apiKey: appState.apiKeys[appState.aiProvider] ?? ""
        )
        
        // Parse JSON from response
        if let jsonStart = response.firstIndex(of: "{"),
           let jsonEnd = response.lastIndex(of: "}") {
            let jsonString = String(response[jsonStart...jsonEnd])
            if let jsonData = jsonString.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                return AIAnalysisResult.parse(from: json)
            }
        }
        
        // Default fallback
        return AIAnalysisResult(
            qualityScore: 70,
            summary: response,
            strengths: [],
            weaknesses: [],
            recommendations: [],
            securityIssues: []
        )
    }
    
    private func exportAsMarkdown() {
        guard let report = aiReport else { return }
        
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.text]
        savePanel.nameFieldStringValue = "\(report.fileName)_analysis.md"
        
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? report.paperReport.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    private func copyToClipboard() {
        guard let report = aiReport else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.paperReport, forType: .string)
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(color)
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}
