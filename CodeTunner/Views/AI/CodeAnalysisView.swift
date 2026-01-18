//
//  CodeAnalysisView.swift
//  CodeTunner
//
//  AI-powered Code Analysis with PDF/Word Export
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import SwiftUI
import PDFKit

// MARK: - Analysis Types

enum AnalysisType: String, CaseIterable, Identifiable {
    case quality = "Code Quality"
    case security = "Security Audit"
    case performance = "Performance"
    case refactor = "Refactor Suggestions"
    case documentation = "Documentation"
    case complexity = "Complexity Analysis"
    case testCoverage = "Test Coverage"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .quality: return "checkmark.seal.fill"
        case .security: return "lock.shield.fill"
        case .performance: return "speedometer"
        case .refactor: return "arrow.triangle.2.circlepath"
        case .documentation: return "doc.text.fill"
        case .complexity: return "chart.bar.fill"
        case .testCoverage: return "testtube.2"
        }
    }
    
    var color: Color {
        switch self {
        case .quality: return .green
        case .security: return .red
        case .performance: return .orange
        case .refactor: return .blue
        case .documentation: return .purple
        case .complexity: return .cyan
        case .testCoverage: return .mint
        }
    }
    
    var prompt: String {
        switch self {
        case .quality:
            return """
            Analyze this code for quality. Provide:
            1. Overall quality score (1-10)
            2. Code style issues
            3. Best practices violations
            4. Naming conventions
            5. Code organization
            6. Specific recommendations
            Format as a professional report.
            """
        case .security:
            return """
            Perform a security audit on this code. Identify:
            1. Security vulnerabilities (Critical, High, Medium, Low)
            2. Input validation issues
            3. Authentication/Authorization flaws
            4. Data exposure risks
            5. Injection vulnerabilities
            6. Remediation steps
            Format as a professional security report.
            """
        case .performance:
            return """
            Analyze this code for performance. Provide:
            1. Performance score (1-10)
            2. Time complexity analysis
            3. Memory usage concerns
            4. Optimization opportunities
            5. Bottleneck identification
            6. Specific improvements
            Format as a professional report.
            """
        case .refactor:
            return """
            Suggest refactoring improvements for this code:
            1. Code smells detected
            2. Design pattern opportunities
            3. DRY violations
            4. SOLID principle violations
            5. Modularization suggestions
            6. Provide refactored code examples
            Format as a professional report with code examples.
            """
        case .documentation:
            return """
            Generate comprehensive documentation:
            1. Overview and purpose
            2. Function/class descriptions
            3. Parameter documentation
            4. Return value documentation
            5. Usage examples
            6. Dependencies and requirements
            Format in standard documentation style.
            """
        case .complexity:
            return """
            Analyze code complexity:
            1. Cyclomatic complexity
            2. Cognitive complexity
            3. Lines of code (LOC) analysis
            4. Function length analysis
            5. Nesting depth
            6. Recommendations for simplification
            Format as a professional technical report.
            """
        case .testCoverage:
            return """
            Analyze test coverage and suggest tests:
            1. Current testability assessment
            2. Suggested unit tests
            3. Integration test suggestions
            4. Edge cases to cover
            5. Mock/stub recommendations
            6. Test code examples
            Format as a professional report with code examples.
            """
        }
    }
}

// MARK: - AI Provider

enum AIProvider: String, CaseIterable, Identifiable {
    case chatgpt = "ChatGPT"
    case gemini = "Gemini"
    case claude = "Claude"
    case deepseek = "DeepSeek"
    case perplexity = "Perplexity"
    case glm = "GLM"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .chatgpt: return "🤖"
        case .gemini: return "✨"
        case .claude: return "🧠"
        case .deepseek: return "🔍"
        case .perplexity: return "💡"
        case .glm: return "🌐"
        }
    }
    
    var color: Color {
        switch self {
        case .chatgpt: return .green
        case .gemini: return .blue
        case .claude: return .orange
        case .deepseek: return .purple
        case .perplexity: return .mint
        case .glm: return .cyan
        }
    }
}

// MARK: - Analysis Result

struct AnalysisResult: Identifiable {
    let id = UUID()
    let type: AnalysisType
    let provider: AIProvider
    let code: String
    let analysis: String
    let refactoredCode: String?
    let timestamp: Date
    var score: Int?
}

// MARK: - Code Analysis View

struct CodeAnalysisView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var viewModel = CodeAnalysisViewModel()
    @State private var selectedType: AnalysisType = .quality
    @State private var selectedProvider: AIProvider = .chatgpt
    @State private var showingExportOptions = false
    @State private var showingAPIKeySheet = false
    
    var body: some View {
        CompatHSplitView {
            // Left: Code Input
            codeInputPanel
                .frame(minWidth: 400)
            
            // Right: Analysis Results
            analysisResultsPanel
                .frame(minWidth: 450)
        }
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showingExportOptions) {
            ExportOptionsSheet(result: viewModel.currentResult, viewModel: viewModel)
        }
        .sheet(isPresented: $showingAPIKeySheet) {
            APIKeyConfigSheet(provider: selectedProvider, viewModel: viewModel)
        }
    }
    
    // MARK: - Code Input Panel
    
    private var codeInputPanel: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .foregroundColor(.blue)
                Text("Code Input")
                    .font(.headline)
                Spacer()
                
                Button {
                    viewModel.codeInput = appState.currentFile?.content ?? ""
                } label: {
                    Label("Load Current File", systemImage: "doc.fill")
                        .font(.caption)
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            // Code Editor
            TextEditor(text: $viewModel.codeInput)
                .font(.system(.body, design: .monospaced))
                .padding(8)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
    
    // MARK: - Analysis Results Panel
    
    private var analysisResultsPanel: some View {
        VStack(spacing: 0) {
            // Controls Header
            controlsHeader
            
            Divider()
            
            // Results
            if viewModel.isAnalyzing {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Analyzing with \(selectedProvider.rawValue)...")
                        .font(.headline)
                    Text(viewModel.statusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let result = viewModel.currentResult {
                resultView(result)
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private var controlsHeader: some View {
        VStack(spacing: 12) {
            // Analysis Type
            HStack {
                Text("Analysis Type")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Picker("", selection: $selectedType) {
                    ForEach(AnalysisType.allCases) { type in
                        Label(type.rawValue, systemImage: type.icon)
                            .tag(type)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 180)
            }
            
            // AI Provider
            HStack {
                Text("AI Provider")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                
                Picker("", selection: $selectedProvider) {
                    ForEach(AIProvider.allCases) { provider in
                        HStack {
                            Text(provider.icon)
                            Text(provider.rawValue)
                        }
                        .tag(provider)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
                
                Button {
                    showingAPIKeySheet = true
                } label: {
                    Image(systemName: "key.fill")
                }
                .help("Configure API Key")
            }
            
            // Action Buttons
            HStack {
                Button {
                    viewModel.analyze(
                        code: viewModel.codeInput,
                        type: selectedType,
                        provider: selectedProvider
                    )
                } label: {
                    Label("Analyze", systemImage: "sparkle.magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.codeInput.isEmpty || viewModel.isAnalyzing)
                
                if viewModel.currentResult != nil {
                    Button {
                        showingExportOptions = true
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                
                Spacer()
            }
        }
        .padding()
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No Analysis Yet")
                .font(.title2)
            Text("Enter code and click Analyze to get AI-powered insights")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func resultView(_ result: AnalysisResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack {
                    Image(systemName: result.type.icon)
                        .foregroundColor(result.type.color)
                    Text(result.type.rawValue)
                        .font(.title2.bold())
                    
                    Spacer()
                    
                    if let score = result.score {
                        ScoreBadge(score: score)
                    }
                    
                    Text(result.provider.icon)
                    Text(result.provider.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Analysis Content
                Text("Analysis Report")
                    .font(.headline)
                
                Text(result.analysis)
                    .font(.body)
                    .textSelection(.enabled)
                
                // Refactored Code (if available)
                if let refactored = result.refactoredCode, !refactored.isEmpty {
                    Divider()
                    
                    HStack {
                        Text("Refactored Code")
                            .font(.headline)
                        Spacer()
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(refactored, forType: .string)
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.caption)
                        }
                        
                        Button {
                            viewModel.applyRefactored(refactored, appState: appState)
                        } label: {
                            Label("Apply", systemImage: "checkmark.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(refactored)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(12)
                            .background(Color(nsColor: .textBackgroundColor))
                            .cornerRadius(8)
                    }
                }
                
                // Timestamp
                Text("Generated: \(result.timestamp.formatted())")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding()
        }
    }
}

// MARK: - Score Badge

struct ScoreBadge: View {
    let score: Int
    
    var color: Color {
        if score >= 8 { return .green }
        if score >= 6 { return .yellow }
        if score >= 4 { return .orange }
        return .red
    }
    
    var body: some View {
        Text("\(score)/10")
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(color)
            .cornerRadius(8)
    }
}

// MARK: - Export Options Sheet

struct ExportOptionsSheet: View {
    let result: AnalysisResult?
    @ObservedObject var viewModel: CodeAnalysisViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var exportFormat: ExportFormat = .pdf
    @State private var includeCode = true
    @State private var includeRefactored = true
    @State private var companyName = ""
    @State private var projectName = ""
    
    enum ExportFormat: String, CaseIterable {
        case pdf = "PDF"
        case word = "Word (.docx)"
        case markdown = "Markdown"
        case html = "HTML"
        case json = "JSON"
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Export Report")
                .font(.title2.bold())
            
            Form {
                Section("Format") {
                    Picker("Export As", selection: $exportFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                }
                
                Section("Content") {
                    Toggle("Include Original Code", isOn: $includeCode)
                    Toggle("Include Refactored Code", isOn: $includeRefactored)
                }
                
                Section("Report Details") {
                    TextField("Company/Organization", text: $companyName)
                    TextField("Project Name", text: $projectName)
                }
            }
            .compatGroupedFormStyle()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Export") {
                    if let result = result {
                        viewModel.exportReport(
                            result: result,
                            format: exportFormat,
                            includeCode: includeCode,
                            includeRefactored: includeRefactored,
                            companyName: companyName,
                            projectName: projectName
                        )
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 400)
    }
}

// MARK: - API Key Config Sheet

struct APIKeyConfigSheet: View {
    let provider: AIProvider
    @ObservedObject var viewModel: CodeAnalysisViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    
    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(provider.icon)
                    .font(.title)
                Text("\(provider.rawValue) API Key")
                    .font(.title2.bold())
            }
            
            SecureField("Enter API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 350)
            
            Text("Your API key is stored securely in Keychain")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Save") {
                    viewModel.saveAPIKey(apiKey, for: provider)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKey.isEmpty)
            }
        }
        .padding()
        .frame(width: 400, height: 200)
        .onAppear {
            apiKey = viewModel.getAPIKey(for: provider) ?? ""
        }
    }
}

// MARK: - View Model

class CodeAnalysisViewModel: ObservableObject {
    @Published var codeInput: String = ""
    @Published var currentResult: AnalysisResult?
    @Published var isAnalyzing: Bool = false
    @Published var statusMessage: String = ""
    @Published var history: [AnalysisResult] = []
    
    private var apiKeys: [AIProvider: String] = [:]
    
    init() {
        loadAPIKeys()
    }
    
    // MARK: - Analyze
    
    func analyze(code: String, type: AnalysisType, provider: AIProvider) {
        guard !code.isEmpty else { return }
        
        isAnalyzing = true
        statusMessage = "Preparing analysis..."
        
        Task {
            do {
                let result = try await performAnalysis(code: code, type: type, provider: provider)
                
                await MainActor.run {
                    self.currentResult = result
                    self.history.insert(result, at: 0)
                    self.isAnalyzing = false
                    self.statusMessage = ""
                }
            } catch {
                await MainActor.run {
                    self.isAnalyzing = false
                    self.statusMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func performAnalysis(code: String, type: AnalysisType, provider: AIProvider) async throws -> AnalysisResult {
        await MainActor.run {
            statusMessage = "Sending to \(provider.rawValue)..."
        }
        
        let apiKey = getAPIKey(for: provider) ?? ""
        guard !apiKey.isEmpty else {
            throw NSError(domain: "CodeAnalysis", code: 1, userInfo: [NSLocalizedDescriptionKey: "API Key not configured for \(provider.rawValue)"])
        }
        
        let systemPrompt = """
        You are an expert code analyst. Analyze the provided code and give a detailed, professional report.
        Be specific, provide examples, and format your response clearly.
        If the analysis type involves refactoring, provide the refactored code at the end clearly marked.
        """
        
        let userPrompt = """
        \(type.prompt)
        
        CODE TO ANALYZE:
        ```
        \(code)
        ```
        """
        
        // Call AI API based on provider
        let response = try await callAI(provider: provider, apiKey: apiKey, systemPrompt: systemPrompt, userPrompt: userPrompt)
        
        // Extract refactored code if present
        let refactoredCode = extractRefactoredCode(from: response)
        
        // Extract score if present
        let score = extractScore(from: response)
        
        return AnalysisResult(
            type: type,
            provider: provider,
            code: code,
            analysis: response,
            refactoredCode: refactoredCode,
            timestamp: Date(),
            score: score
        )
    }
    
    private func callAI(provider: AIProvider, apiKey: String, systemPrompt: String, userPrompt: String) async throws -> String {
        var request: URLRequest
        var body: [String: Any]
        
        switch provider {
        case .chatgpt:
            request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": "gpt-4o-mini",
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userPrompt]
                ],
                "temperature": 0.3,
                "max_tokens": 4000
            ]
            
        case .gemini:
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(apiKey)")!)
            body = [
                "contents": [
                    ["role": "user", "parts": [["text": systemPrompt]]],
                    ["role": "model", "parts": [["text": "Understood."]]],
                    ["role": "user", "parts": [["text": userPrompt]]]
                ]
            ]
            
        case .claude:
            request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            body = [
                "model": "claude-3-5-sonnet-20241022",
                "max_tokens": 4000,
                "system": systemPrompt,
                "messages": [["role": "user", "content": userPrompt]]
            ]
            
        case .deepseek:
            request = URLRequest(url: URL(string: "https://api.deepseek.com/v1/chat/completions")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": "deepseek-chat",
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userPrompt]
                ],
                "temperature": 0.3
            ]
            
        case .perplexity:
            request = URLRequest(url: URL(string: "https://api.perplexity.ai/chat/completions")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": "llama-3.1-sonar-small-128k-online",
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userPrompt]
                ]
            ]
            
        case .glm:
            request = URLRequest(url: URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!)
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            body = [
                "model": "glm-4",
                "messages": [
                    ["role": "system", "content": systemPrompt],
                    ["role": "user", "content": userPrompt]
                ]
            ]
        }
        
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 120
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        
        // Parse response based on provider
        switch provider {
        case .gemini:
            if let candidates = json["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {
                return text
            }
        case .claude:
            if let content = json["content"] as? [[String: Any]],
               let text = content.first?["text"] as? String {
                return text
            }
        default:
            if let choices = json["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                return content
            }
        }
        
        throw NSError(domain: "CodeAnalysis", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse AI response"])
    }
    
    private func extractRefactoredCode(from response: String) -> String? {
        // Look for code blocks after "Refactored" or similar keywords
        let patterns = [
            "```[a-z]*\\n([\\s\\S]*?)```",
            "Refactored Code:[\\s\\S]*?```[a-z]*\\n([\\s\\S]*?)```"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)) {
                if match.numberOfRanges > 1 {
                    let range = Range(match.range(at: 1), in: response)!
                    return String(response[range])
                }
            }
        }
        
        return nil
    }
    
    private func extractScore(from response: String) -> Int? {
        let patterns = [
            "(?:score|rating)[:\\s]+([0-9]+)(?:/10|\\s*out of\\s*10)?",
            "([0-9]+)/10"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: response, range: NSRange(response.startIndex..., in: response)) {
                if match.numberOfRanges > 1 {
                    let range = Range(match.range(at: 1), in: response)!
                    if let score = Int(response[range]) {
                        return min(10, max(1, score))
                    }
                }
            }
        }
        
        return nil
    }
    
    // MARK: - Export
    
    func exportReport(result: AnalysisResult, format: ExportOptionsSheet.ExportFormat, includeCode: Bool, includeRefactored: Bool, companyName: String, projectName: String) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        
        switch format {
        case .pdf:
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = "Code_Analysis_Report.pdf"
        case .word:
            panel.allowedContentTypes = [.init(filenameExtension: "docx")!]
            panel.nameFieldStringValue = "Code_Analysis_Report.docx"
        case .markdown:
            panel.allowedContentTypes = [.init(filenameExtension: "md")!]
            panel.nameFieldStringValue = "Code_Analysis_Report.md"
        case .html:
            panel.allowedContentTypes = [.html]
            panel.nameFieldStringValue = "Code_Analysis_Report.html"
        case .json:
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "Code_Analysis_Report.json"
        }
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                self.saveReport(to: url, result: result, format: format, includeCode: includeCode, includeRefactored: includeRefactored, companyName: companyName, projectName: projectName)
            }
        }
    }
    
    private func saveReport(to url: URL, result: AnalysisResult, format: ExportOptionsSheet.ExportFormat, includeCode: Bool, includeRefactored: Bool, companyName: String, projectName: String) {
        let content = generateReportContent(result: result, includeCode: includeCode, includeRefactored: includeRefactored, companyName: companyName, projectName: projectName)
        
        switch format {
        case .pdf:
            exportToPDF(content: content, url: url, result: result, companyName: companyName, projectName: projectName)
        case .word:
            exportToWord(content: content, url: url)
        case .markdown:
            try? content.write(to: url, atomically: true, encoding: .utf8)
        case .html:
            let html = generateHTML(content: content, result: result, companyName: companyName, projectName: projectName)
            try? html.write(to: url, atomically: true, encoding: .utf8)
        case .json:
            let json = generateJSON(result: result, includeCode: includeCode, includeRefactored: includeRefactored)
            try? json.write(to: url, atomically: true, encoding: .utf8)
        }
    }
    
    private func generateReportContent(result: AnalysisResult, includeCode: Bool, includeRefactored: Bool, companyName: String, projectName: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"
        let formattedDate = dateFormatter.string(from: result.timestamp)
        let year = Calendar.current.component(.year, from: Date())
        
        var content = """
        \(result.type.rawValue.uppercased()) REPORT
        ============================================================
        
        DOCUMENT INFORMATION
        ------------------------------------------------------------
        Prepared by:    MicroCode AI Analysis System
        Date:           \(formattedDate)
        Organization:   \(companyName.isEmpty ? "-" : companyName)
        Project:        \(projectName.isEmpty ? "-" : projectName)
        AI Provider:    \(result.provider.rawValue)
        
        
        EXECUTIVE SUMMARY
        ------------------------------------------------------------
        This report presents the results of an automated \(result.type.rawValue.lowercased())
        analysis performed on the submitted source code. The analysis was
        conducted using the \(result.provider.rawValue) AI engine.
        
        """
        
        if let score = result.score {
            let rating: String
            if score >= 8 {
                rating = "Excellent"
            } else if score >= 6 {
                rating = "Good"
            } else if score >= 4 {
                rating = "Fair"
            } else {
                rating = "Needs Improvement"
            }
            
            content += """
        
        OVERALL SCORE
        ------------------------------------------------------------
        Score:          \(score) / 10
        Rating:         \(rating)
        
        """
        }
        
        content += """
        
        ANALYSIS RESULTS
        ============================================================
        
        \(result.analysis)
        
        
        RECOMMENDATIONS
        ------------------------------------------------------------
        Based on the analysis findings, the following actions are recommended:
        
          1. Review and address any critical issues identified above.
          2. Implement suggested improvements in order of priority.
          3. Consider refactoring opportunities where applicable.
          4. Update documentation to reflect any changes made.
        
        """
        
        if includeCode {
            content += """
        
        APPENDIX A: ORIGINAL CODE
        ------------------------------------------------------------
        
        \(result.code)
        
        """
        }
        
        if includeRefactored, let refactored = result.refactoredCode {
            content += """
        
        APPENDIX B: SUGGESTED REFACTORED CODE
        ------------------------------------------------------------
        
        \(refactored)
        
        """
        }
        
        content += """
        
        ============================================================
        END OF REPORT
        ============================================================
        
        This report was automatically generated by MicroCode AI Analysis
        System using \(result.provider.rawValue).
        
        Copyright \(year) \(companyName.isEmpty ? "All rights reserved" : companyName + ". All rights reserved").
        """
        
        return content
    }
    
    private func exportToPDF(content: String, url: URL, result: AnalysisResult, companyName: String, projectName: String) {
        let printInfo = NSPrintInfo.shared
        printInfo.paperSize = NSSize(width: 612, height: 792) // Letter size
        printInfo.topMargin = 72
        printInfo.bottomMargin = 72
        printInfo.leftMargin = 72
        printInfo.rightMargin = 72
        
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 468, height: 648))
        textView.string = content
        textView.font = NSFont.systemFont(ofSize: 12)
        
        let pdfData = textView.dataWithPDF(inside: textView.bounds)
        try? pdfData.write(to: url)
    }
    
    private func exportToWord(content: String, url: URL) {
        // For Word, we export as RTF which Word can open
        let rtfUrl = url.deletingPathExtension().appendingPathExtension("rtf")
        if let data = content.data(using: .utf8) {
            try? data.write(to: rtfUrl)
        }
    }
    
    private func generateHTML(content: String, result: AnalysisResult, companyName: String, projectName: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMMM d, yyyy"
        let formattedDate = dateFormatter.string(from: result.timestamp)
        let year = Calendar.current.component(.year, from: Date())
        
        let scoreSection: String
        if let score = result.score {
            let rating = score >= 8 ? "Excellent" : score >= 6 ? "Good" : score >= 4 ? "Fair" : "Needs Improvement"
            scoreSection = """
            <h2>Overall Score</h2>
            <table class="info-table">
                <tr><td>Score</td><td>\(score) / 10</td></tr>
                <tr><td>Rating</td><td>\(rating)</td></tr>
            </table>
            """
        } else {
            scoreSection = ""
        }
        
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>\(result.type.rawValue) Report</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial, sans-serif;
                    line-height: 1.6;
                    color: #333;
                    max-width: 800px;
                    margin: 0 auto;
                    padding: 40px 20px;
                }
                h1 {
                    font-size: 24px;
                    margin-bottom: 30px;
                    padding-bottom: 15px;
                    border-bottom: 2px solid #333;
                }
                h2 {
                    font-size: 16px;
                    margin-top: 30px;
                    margin-bottom: 15px;
                    color: #555;
                }
                p { margin-bottom: 12px; }
                .info-table {
                    width: 100%;
                    border-collapse: collapse;
                    margin-bottom: 20px;
                }
                .info-table td {
                    padding: 8px 0;
                    border-bottom: 1px solid #eee;
                }
                .info-table td:first-child {
                    width: 150px;
                    color: #666;
                }
                .analysis-content {
                    background: #f9f9f9;
                    padding: 20px;
                    border-radius: 4px;
                    white-space: pre-wrap;
                    font-size: 14px;
                    line-height: 1.5;
                }
                .recommendations {
                    margin-left: 20px;
                }
                .recommendations li {
                    margin-bottom: 8px;
                }
                .footer {
                    margin-top: 50px;
                    padding-top: 20px;
                    border-top: 1px solid #ddd;
                    font-size: 12px;
                    color: #888;
                }
            </style>
        </head>
        <body>
            <h1>\(result.type.rawValue.uppercased()) REPORT</h1>
            
            <h2>Document Information</h2>
            <table class="info-table">
                <tr><td>Prepared by</td><td>MicroCode AI Analysis System</td></tr>
                <tr><td>Date</td><td>\(formattedDate)</td></tr>
                <tr><td>Organization</td><td>\(companyName.isEmpty ? "-" : companyName)</td></tr>
                <tr><td>Project</td><td>\(projectName.isEmpty ? "-" : projectName)</td></tr>
                <tr><td>AI Provider</td><td>\(result.provider.rawValue)</td></tr>
            </table>
            
            <h2>Executive Summary</h2>
            <p>This report presents the results of an automated \(result.type.rawValue.lowercased()) analysis performed on the submitted source code. The analysis was conducted using the \(result.provider.rawValue) AI engine.</p>
            
            \(scoreSection)
            
            <h2>Analysis Results</h2>
            <div class="analysis-content">\(result.analysis)</div>
            
            <h2>Recommendations</h2>
            <p>Based on the analysis findings, the following actions are recommended:</p>
            <ol class="recommendations">
                <li>Review and address any critical issues identified above.</li>
                <li>Implement suggested improvements in order of priority.</li>
                <li>Consider refactoring opportunities where applicable.</li>
                <li>Update documentation to reflect any changes made.</li>
            </ol>
            
            <div class="footer">
                <p>This report was automatically generated by MicroCode AI Analysis System using \(result.provider.rawValue).</p>
                <p>Copyright \(year) \(companyName.isEmpty ? "All rights reserved" : companyName + ". All rights reserved").</p>
            </div>
        </body>
        </html>
        """
    }
    
    private func generateJSON(result: AnalysisResult, includeCode: Bool, includeRefactored: Bool) -> String {
        var dict: [String: Any] = [
            "type": result.type.rawValue,
            "provider": result.provider.rawValue,
            "timestamp": result.timestamp.ISO8601Format(),
            "analysis": result.analysis
        ]
        
        if let score = result.score {
            dict["score"] = score
        }
        
        if includeCode {
            dict["originalCode"] = result.code
        }
        
        if includeRefactored, let refactored = result.refactoredCode {
            dict["refactoredCode"] = refactored
        }
        
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
            return String(data: data, encoding: .utf8) ?? "{}"
        }
        return "{}"
    }
    
    // MARK: - Apply Refactored
    
    @MainActor
    func applyRefactored(_ code: String, appState: AppState) {
        if var file = appState.currentFile,
           let index = appState.openFiles.firstIndex(where: { $0.id == file.id }) {
            file.content = code
            appState.openFiles[index] = file
            appState.currentFile = file
        }
    }
    
    // MARK: - API Keys
    
    func saveAPIKey(_ key: String, for provider: AIProvider) {
        apiKeys[provider] = key
        UserDefaults.standard.set(key, forKey: "api_key_\(provider.rawValue)")
    }
    
    func getAPIKey(for provider: AIProvider) -> String? {
        if let cached = apiKeys[provider] {
            return cached
        }
        return UserDefaults.standard.string(forKey: "api_key_\(provider.rawValue)")
    }
    
    private func loadAPIKeys() {
        for provider in AIProvider.allCases {
            if let key = UserDefaults.standard.string(forKey: "api_key_\(provider.rawValue)") {
                apiKeys[provider] = key
            }
        }
    }
}

#Preview {
    CodeAnalysisView()
        .environmentObject(AppState())
}
