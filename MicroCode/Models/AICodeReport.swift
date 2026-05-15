//
//  AICodeReport.swift
//  MicroCode
//
//  AI-Powered Code Analysis with Paper-Style Reports
//

import SwiftUI

// MARK: - AI Code Report Model

struct AICodeReport: Identifiable {
    let id = UUID()
    
    // Basic Info
    var fileName: String
    var language: String
    var analyzedAt: Date
    
    // Metrics
    var linesOfCode: Int
    var functions: Int
    var classes: Int
    var complexity: Int
    
    // AI Analysis
    var qualityScore: Int  // 0-100
    var summary: String
    var strengths: [ReportItem]
    var weaknesses: [ReportItem]
    var recommendations: [ReportItem]
    var securityIssues: [SecurityIssue]
    
    // Paper Report
    var paperReport: String
    
    // Computed Properties
    var qualityGrade: String {
        switch qualityScore {
        case 90...100: return "A+"
        case 80..<90: return "A"
        case 70..<80: return "B"
        case 60..<70: return "C"
        case 50..<60: return "D"
        default: return "F"
        }
    }
    
    var qualityStars: Int {
        return min(5, max(1, qualityScore / 20))
    }
    
    var qualityColor: Color {
        switch qualityScore {
        case 80...100: return .green
        case 60..<80: return .yellow
        case 40..<60: return .orange
        default: return .red
        }
    }
}

struct ReportItem: Identifiable {
    let id = UUID()
    var title: String
    var description: String
    var severity: Severity
    var line: Int?
    
    enum Severity: String {
        case info = "info"
        case success = "success"
        case warning = "warning"
        case error = "error"
        
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }
    }
}

struct SecurityIssue: Identifiable {
    let id = UUID()
    var type: String
    var description: String
    var severity: String  // low, medium, high, critical
    var line: Int?
    var suggestion: String
    
    var severityColor: Color {
        switch severity {
        case "critical": return .red
        case "high": return .orange
        case "medium": return .yellow
        default: return .blue
        }
    }
}

// MARK: - Paper Report Generator

struct PaperReportGenerator {
    
    static func generate(
        fileName: String,
        language: String,
        metrics: CodeMetrics,
        aiAnalysis: AIAnalysisResult
    ) -> AICodeReport {
        
        let paperReport = generatePaperMarkdown(
            fileName: fileName,
            language: language,
            metrics: metrics,
            analysis: aiAnalysis
        )
        
        return AICodeReport(
            fileName: fileName,
            language: language,
            analyzedAt: Date(),
            linesOfCode: metrics.linesOfCode,
            functions: metrics.functions,
            classes: metrics.classes,
            complexity: metrics.complexity,
            qualityScore: aiAnalysis.qualityScore,
            summary: aiAnalysis.summary,
            strengths: aiAnalysis.strengths.map { ReportItem(title: $0.title, description: $0.description, severity: .success, line: nil) },
            weaknesses: aiAnalysis.weaknesses.map { ReportItem(title: $0.title, description: $0.description, severity: .warning, line: $0.line) },
            recommendations: aiAnalysis.recommendations.map { ReportItem(title: $0.title, description: $0.description, severity: .info, line: nil) },
            securityIssues: aiAnalysis.securityIssues,
            paperReport: paperReport
        )
    }
    
    private static func generatePaperMarkdown(
        fileName: String,
        language: String,
        metrics: CodeMetrics,
        analysis: AIAnalysisResult
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .short
        
        let stars = String(repeating: "⭐", count: min(5, max(1, analysis.qualityScore / 20)))
        
        return """
        # 📄 Code Analysis Report
        
        **File:** \(fileName)  
        **Language:** \(language)  
        **Date:** \(dateFormatter.string(from: Date()))  
        **Quality Score:** \(analysis.qualityScore)/100 \(stars)
        
        ---
        
        ## 📝 Abstract
        
        \(analysis.summary)
        
        ---
        
        ## 📖 Introduction
        
        This report presents a comprehensive analysis of `\(fileName)`, examining code quality, complexity, potential issues, and recommendations for improvement. The analysis covers structural metrics, code patterns, and security considerations.
        
        ---
        
        ## 🔬 Methodology
        
        The code was analyzed using:
        - **Static Analysis** - Examining code structure without execution
        - **Complexity Metrics** - Cyclomatic complexity, nesting depth
        - **Pattern Detection** - Common code smells and anti-patterns
        - **AI-Powered Review** - Deep semantic understanding
        
        ---
        
        ## 📊 Results
        
        ### Key Metrics
        
        | Metric | Value |
        |--------|-------|
        | Lines of Code | \(metrics.linesOfCode) |
        | Functions | \(metrics.functions) |
        | Classes | \(metrics.classes) |
        | Complexity | \(metrics.complexity) |
        | Quality Score | \(analysis.qualityScore)/100 |
        
        ### ✅ Strengths
        
        \(analysis.strengths.map { "- **\($0.title)**: \($0.description)" }.joined(separator: "\n"))
        
        ### ⚠️ Areas for Improvement
        
        \(analysis.weaknesses.map { "- **\($0.title)**: \($0.description)" }.joined(separator: "\n"))
        
        ### 🔒 Security Considerations
        
        \(analysis.securityIssues.isEmpty ? "No security issues detected. ✅" : analysis.securityIssues.map { "- **[\($0.severity.uppercased())]** \($0.type): \($0.description)" }.joined(separator: "\n"))
        
        ---
        
        ## 💡 Discussion
        
        ### Recommendations
        
        \(analysis.recommendations.enumerated().map { "**\($0.offset + 1).** \($0.element.title)\n   \($0.element.description)" }.joined(separator: "\n\n"))
        
        ---
        
        ## ✅ Conclusion
        
        This analysis identified \(analysis.strengths.count) strengths and \(analysis.weaknesses.count) areas for improvement. The overall quality score of **\(analysis.qualityScore)/100** indicates \(analysis.qualityScore >= 80 ? "well-structured code with minor improvements possible" : analysis.qualityScore >= 60 ? "good code with some areas needing attention" : "code requiring significant refactoring").
        
        ### Action Items
        
        1. Address high-priority weaknesses first
        2. Consider implementing recommended improvements
        3. Re-analyze after changes to track progress
        
        ---
        
        *Generated by Project IDX AI Analysis Engine*
        """
    }
}

// MARK: - AI Analysis Result (from AI response)

struct AIAnalysisResult {
    var qualityScore: Int
    var summary: String
    var strengths: [AnalysisItem]
    var weaknesses: [AnalysisItem]
    var recommendations: [AnalysisItem]
    var securityIssues: [SecurityIssue]
    
    struct AnalysisItem {
        var title: String
        var description: String
        var line: Int?
    }
    
    // Parse from AI JSON response
    static func parse(from json: [String: Any]) -> AIAnalysisResult {
        let qualityScore = json["quality_score"] as? Int ?? 70
        let summary = json["summary"] as? String ?? "Code analysis completed."
        
        var strengths: [AnalysisItem] = []
        if let items = json["strengths"] as? [[String: Any]] {
            strengths = items.map { item in
                AnalysisItem(
                    title: item["title"] as? String ?? "",
                    description: item["description"] as? String ?? "",
                    line: item["line"] as? Int
                )
            }
        }
        
        var weaknesses: [AnalysisItem] = []
        if let items = json["weaknesses"] as? [[String: Any]] {
            weaknesses = items.map { item in
                AnalysisItem(
                    title: item["title"] as? String ?? "",
                    description: item["description"] as? String ?? "",
                    line: item["line"] as? Int
                )
            }
        }
        
        var recommendations: [AnalysisItem] = []
        if let items = json["recommendations"] as? [[String: Any]] {
            recommendations = items.map { item in
                AnalysisItem(
                    title: item["title"] as? String ?? "",
                    description: item["description"] as? String ?? "",
                    line: nil
                )
            }
        }
        
        var securityIssues: [SecurityIssue] = []
        if let items = json["security_issues"] as? [[String: Any]] {
            securityIssues = items.map { item in
                SecurityIssue(
                    type: item["type"] as? String ?? "",
                    description: item["description"] as? String ?? "",
                    severity: item["severity"] as? String ?? "low",
                    line: item["line"] as? Int,
                    suggestion: item["suggestion"] as? String ?? ""
                )
            }
        }
        
        return AIAnalysisResult(
            qualityScore: qualityScore,
            summary: summary,
            strengths: strengths,
            weaknesses: weaknesses,
            recommendations: recommendations,
            securityIssues: securityIssues
        )
    }
}
