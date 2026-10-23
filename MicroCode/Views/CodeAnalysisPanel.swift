//
//  CodeAnalysisPanel.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2024 Dotmini Company Limited. All rights reserved.
//

import SwiftUI

struct CodeAnalysisPanel: View {
    @EnvironmentObject var appState: AppState
    
    @State private var metrics: CodeMetrics?
    @State private var aiReport: AICodeReport?
    @State private var isAnalyzing: Bool = false
    @State private var selectedTab: AnalysisTab = .overview
    
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
        VStack(spacing: 0) {
            // Tab Bar
            HStack(spacing: 0) {
                ForEach(AnalysisTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                            Text(tab.rawValue)
                        }
                        .font(.system(size: 11))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                        .foregroundColor(selectedTab == tab ? .accentColor : .primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                
                // Analyze Button
                HStack(spacing: 8) {
                    if isAnalyzing {
                        ProgressView().scaleEffect(0.6)
                        Text("Analyzing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button("Analyze") {
                        analyzeCode()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(appState.currentFile == nil || isAnalyzing)
                }
                .padding(.horizontal, 8)
            }
            .frame(height: 28)
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
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
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    // MARK: - Overview Tab
    
    private var overviewTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let report = aiReport {
                // Quality Score
                HStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(report.qualityColor.opacity(0.2), lineWidth: 8)
                        Circle()
                            .trim(from: 0, to: CGFloat(report.qualityScore) / 100)
                            .stroke(report.qualityColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 60, height: 60)
                        
                        Text("\(report.qualityScore)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(report.qualityColor)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(report.qualityGrade)
                            .font(.headline)
                        Text(report.summary)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(12)
                
                // Quick Stats
                HStack(spacing: 12) {
                    statCard("Strengths", count: report.strengths.count, color: .green)
                    statCard("Weaknesses", count: report.weaknesses.count, color: .orange)
                    statCard("Security", count: report.securityIssues.count, color: report.securityIssues.isEmpty ? .green : .red)
                }
                
                if let metrics = metrics {
                    metricsGrid(metrics)
                }
            } else {
                emptyState
            }
        }
    }
    
    private func metricsGrid(_ metrics: CodeMetrics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            MetricCard(title: "LOC", value: "\(metrics.linesOfCode)", color: .blue)
            MetricCard(title: "Complexity", value: "\(metrics.complexity)", color: .orange)
        }
    }
    
    private func statCard(_ title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.headline)
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
    
    // MARK: - Details Tab
    
    private var detailsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let report = aiReport {
                detailSection("Strengths", items: report.strengths)
                detailSection("Weaknesses", items: report.weaknesses)
                detailSection("Recommendations", items: report.recommendations)
                
                if !report.securityIssues.isEmpty {
                    Text("Security Issues")
                        .font(.headline)
                    ForEach(report.securityIssues) { issue in
                        HStack {
                            Image(systemName: "exclamationmark.shield.fill")
                                .foregroundColor(.red)
                            VStack(alignment: .leading) {
                                Text(issue.type).font(.caption.bold())
                                Text(issue.description).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            } else {
                emptyState
            }
        }
    }
    
    private func detailSection(_ title: String, items: [ReportItem]) -> some View {
        Group {
            if !items.isEmpty {
                Text(title).font(.headline)
                ForEach(items) { item in
                    HStack(alignment: .top) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .padding(.top, 6)
                        VStack(alignment: .leading) {
                            Text(item.title).font(.caption.bold())
                            Text(item.description).font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Paper Tab
    
    private var paperTab: some View {
        VStack(alignment: .leading) {
            if let report = aiReport {
                HStack {
                    Spacer()
                    Button("Copy Report") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(report.paperReport, forType: .string)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Text(report.paperReport)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
            } else {
                emptyState
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "wand.and.stars")
                .font(.system(size: 32))
                .foregroundColor(.purple.opacity(0.5))
            Text("Ready to analyze code")
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(height: 200)
    }
    
    // MARK: - Logic (Ported from CodeAnalysisWindow)
    
    private func analyzeCode() {
        guard let file = appState.currentFile else { return }
        isAnalyzing = true
        
        let code = file.content
        let language = file.language
        let fileName = file.name
        
        DispatchQueue.global(qos: .userInitiated).async {
            let analyzer = CodeAnalyzer.shared
            let result = analyzer.analyzeComplexity(code: code, language: language)
            
            let smellPenalty = min(45, result.codeSmells.count * 5)
            let complexityPenalty = max(0, (result.complexity - 15) * 2)
            let score = max(20, min(100, 100 - smellPenalty - complexityPenalty))
            
            var strengths: [AIAnalysisResult.AnalysisItem] = []
            if result.complexity <= 15 {
                strengths.append(.init(title: "Low Cyclomatic Complexity", description: "Control flow complexity (\(result.complexity)) is clean and maintainable.", line: nil))
            }
            if result.codeSmells.isEmpty {
                strengths.append(.init(title: "Clean Code Structure", description: "No code smells or structural warnings detected across \(result.linesOfCode) LOC.", line: nil))
            }
            if result.functions > 0 {
                strengths.append(.init(title: "Modular Decomposition", description: "Organized into \(result.functions) function(s) and \(result.classes) type(s).", line: nil))
            }
            
            let weaknesses: [AIAnalysisResult.AnalysisItem] = result.codeSmells.map { smell in
                .init(title: "\(smell.type) (Line \(smell.line))", description: smell.message, line: smell.line)
            }
            
            var recommendations: [AIAnalysisResult.AnalysisItem] = []
            if result.complexity > 20 {
                recommendations.append(.init(title: "Reduce Cyclomatic Complexity", description: "Extract deeply nested branches or switch statements into helper functions.", line: nil))
            }
            if !result.codeSmells.isEmpty {
                recommendations.append(.init(title: "Resolve Static Code Smells", description: "Address \(result.codeSmells.count) flagged line(s) to improve readability and maintainability.", line: nil))
            }
            
            let analysisResult = AIAnalysisResult(
                qualityScore: score,
                summary: "Static analysis of \(fileName) (\(result.linesOfCode) LOC, complexity \(result.complexity), \(result.functions) functions, \(result.codeSmells.count) findings).",
                strengths: strengths,
                weaknesses: weaknesses,
                recommendations: recommendations,
                securityIssues: []
            )
            
            let generatedReport = PaperReportGenerator.generate(
                fileName: fileName,
                language: language,
                metrics: result,
                aiAnalysis: analysisResult
            )
            
            DispatchQueue.main.async {
                self.metrics = result
                self.aiReport = generatedReport
                self.isAnalyzing = false
            }
        }
    }
}
