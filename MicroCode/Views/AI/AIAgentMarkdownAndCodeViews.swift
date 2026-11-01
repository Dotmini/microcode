//
//  AIAgentMarkdownAndCodeViews.swift
//  MicroCode
//
//  Created by Tirawat Nantamas
//  Copyright © 2024 Dotmini Company Limited. All rights reserved.
//

import SwiftUI
import Combine
import MicroCodeSupport
import AppKit
import WebKit
import UniformTypeIdentifiers
import PDFKit
import AVKit
import AVFoundation

// MARK: - Shape Extension
struct RoundedCornerShape: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        let w = rect.size.width
        let h = rect.size.height
        let r = min(min(self.radius, h/2), w/2)
        
        let tr = corners.contains(.topRight) ? r : 0
        let tl = corners.contains(.topLeft) ? r : 0
        let bl = corners.contains(.bottomLeft) ? r : 0
        let br = corners.contains(.bottomRight) ? r : 0
        
        path.move(to: CGPoint(x: w / 2.0, y: 0))
        path.addLine(to: CGPoint(x: w - tr, y: 0))
        path.addArc(center: CGPoint(x: w - tr, y: tr), radius: tr,
                    startAngle: Angle(degrees: -90), endAngle: Angle(degrees: 0), clockwise: false)
        
        path.addLine(to: CGPoint(x: w, y: h - br))
        path.addArc(center: CGPoint(x: w - br, y: h - br), radius: br,
                    startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        
        path.addLine(to: CGPoint(x: bl, y: h))
        path.addArc(center: CGPoint(x: bl, y: h - bl), radius: bl,
                    startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        
        path.addLine(to: CGPoint(x: 0, y: tl))
        path.addArc(center: CGPoint(x: tl, y: tl), radius: tl,
                    startAngle: Angle(degrees: 180), endAngle: Angle(degrees: 270), clockwise: false)
        
        path.closeSubpath()
        return path
    }
}

// Custom OptionSet for Corners (Cross-platform)
struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape( RoundedCornerShape(radius: radius, corners: corners) )
    }
}

// MARK: - Rich Text Components

final class MarkdownAttrCache {
    private static var cache: [String: AttributedString] = [:]
    private static let lock = NSLock()
    
    private static let inlineCodeFileRegex = try? NSRegularExpression(
        pattern: #"(?<!\[)`([^`\n]+?\.(?:swift|ts|tsx|js|jsx|svelte|vue|astro|py|rs|go|java|kt|kts|c|cpp|cc|h|hpp|m|mm|html|css|scss|json|yaml|yml|toml|sql|sh|md|ar|dart|rb|php|cs|proto|graphql)(?:#L\d+(?:-L?\d+)?)?)`(?!\])"#,
        options: [.caseInsensitive]
    )

    private static func sanitizeStreamingMarkdown(_ text: String) -> String {
        var working = text
        // During streaming, if the text ends with an unclosed markdown link `[label](url_fragment`,
        // strip the incomplete `(url_fragment` so AttributedString(markdown:) still parses earlier links.
        if let lastOpenBracket = working.lastIndex(of: "["),
           let midParen = working[lastOpenBracket...].range(of: "]("),
           !working[midParen.upperBound...].contains(")") {
            let label = working[working.index(after: lastOpenBracket)..<midParen.lowerBound]
            working.replaceSubrange(lastOpenBracket..<working.endIndex, with: "`\(label)`")
        }
        // Auto-convert standalone backticked code file names (e.g. `+page.svelte`, `AIUsageTracker.swift#L10-20`)
        // into clickable `microcode-file://` links so clicking them opens the AGY-style Right Code Preview Split Pane.
        if let regex = inlineCodeFileRegex {
            let ns = working as NSString
            let matches = regex.matches(in: working, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() where match.numberOfRanges >= 2 {
                let rawFile = ns.substring(with: match.range(at: 1))
                if let encoded = rawFile.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.union(.init(charactersIn: "#-:"))) {
                    let replacement = "[`\(rawFile)`](microcode-file://\(encoded))"
                    working = (working as NSString).replacingCharacters(in: match.range, with: replacement)
                }
            }
        }
        return working
    }
    
    static func getOrParse(_ text: String) -> AttributedString {
        lock.lock()
        if let found = cache[text] {
            lock.unlock()
            return found
        }
        lock.unlock()
        
        let sanitized = sanitizeStreamingMarkdown(text)
        let parsed = (try? AttributedString(markdown: sanitized, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(sanitized)
        
        lock.lock()
        if cache.count > 1024 { cache.removeAll(keepingCapacity: true) }
        cache[text] = parsed
        lock.unlock()
        return parsed
    }
    
    static func clearAll() {
        lock.lock()
        cache.removeAll(keepingCapacity: false)
        lock.unlock()
    }
}

/// Renders inline markdown (bold, italic, code, links)
struct MarkdownTextView: View, Equatable {
    let text: String
    @EnvironmentObject var appState: AppState
    
    static func == (lhs: MarkdownTextView, rhs: MarkdownTextView) -> Bool {
        return lhs.text == rhs.text
    }
    
    private var fontSize: CGFloat {
        appState.agentFontSize
    }
    
    var body: some View {
        let font = Font.custom(appState.agentFontName, size: fontSize)
        let attr = MarkdownAttrCache.getOrParse(text)
        Text(attr)
            .font(font)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.primary)
            .lineSpacing(5)
            .environment(\.openURL, OpenURLAction { url in
                if url.isFileURL || url.scheme == "file" || url.scheme == "microcode-file" {
                    if PreviewDockService.shared.openFileFromReference(url.absoluteString, workspacePath: appState.workspaceFolder?.path) {
                        return .handled
                    }
                    let cleanPath = url.path.isEmpty
                        ? url.absoluteString.replacingOccurrences(of: "file://", with: "").replacingOccurrences(of: "microcode-file://", with: "").removingPercentEncoding ?? ""
                        : url.path
                    if !cleanPath.isEmpty {
                        NotificationCenter.default.post(
                            name: NSNotification.Name("MicroCodeOpenFileURL"),
                            object: URL(fileURLWithPath: cleanPath)
                        )
                        return .handled
                    }
                }
                return .systemAction
            })
    }
}

/// Renders heading with proper font size
struct HeadingView: View {
    let level: Int
    let content: String
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        Text(MarkdownAttrCache.getOrParse(content))
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(.primary)
            .tint(.accentColor)
            .environment(\.openURL, OpenURLAction { url in
                if url.scheme == "file" {
                    let path = url.path
                    if !path.isEmpty {
                        NotificationCenter.default.post(
                            name: Notification.Name("MicroCodeOpenFileURL"),
                            object: URL(fileURLWithPath: path)
                        )
                        return .handled
                    }
                }
                return .systemAction
            })
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topPadding)
            .padding(.bottom, 4)
    }
    
    private var fontSize: CGFloat {
        let base = appState.agentFontSize
        switch level {
        case 1: return base * 1.5
        case 2: return base * 1.3
        case 3: return base * 1.15
        case 4: return base * 1.05
        default: return base
        }
    }
    
    private var topPadding: CGFloat {
        level <= 2 ? 12 : 6
    }
}

/// Renders a full multi-block Markdown document (.md files like task.md, implement.md, walkthrough.md, README.md) as formatted rich text
struct RenderedMarkdownDocumentView: View, Equatable {
    let markdown: String
    @EnvironmentObject var appState: AppState
    
    static func == (lhs: RenderedMarkdownDocumentView, rhs: RenderedMarkdownDocumentView) -> Bool {
        lhs.markdown == rhs.markdown
    }
    
    var body: some View {
        let blocks = MessageContentParser.parse(markdown)
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .thought(let content, let duration):
                    AntigravityThoughtBlockView(content: content, durationSeconds: duration)
                case .text(let text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        MarkdownTextView(text: text)
                    }
                case .code(let lang, let code):
                    let lower = lang.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                    if lower == "markdown" || lower == "md" || lower.hasSuffix(".md") {
                        MarkdownTextView(text: code)
                    } else {
                        NativeCodeBlockView(language: lang, code: code)
                    }
                case .heading(let level, let content):
                    HeadingView(level: level, content: content)
                case .list(let items, let isOrdered):
                    ListView(items: items, isOrdered: isOrdered)
                case .table(let headers, let rows):
                    TableBlockView(headers: headers, rows: rows)
                case .blockquote(let content):
                    BlockquoteView(content: content)
                case .latex(let expression, let isBlock):
                    LaTeXBlockView(expression: expression, isBlock: isBlock)
                case .html(let content):
                    HTMLBlockView(content: content)
                case .media(let kind, let title, let target):
                    ChatMediaBlockView(kind: kind, title: title, target: target)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders ordered/unordered list (with native checkbox support for [ ] and [x])
struct ListView: View {
    let items: [String]
    let isOrdered: Bool
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items.indices, id: \.self) { index in
                let rawItem = items[index]
                let trimmedItem = rawItem.trimmingCharacters(in: .whitespaces)
                if trimmedItem.hasPrefix("[x] ") || trimmedItem.hasPrefix("[X] ") {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.square.fill")
                            .font(.system(size: appState.agentFontSize, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .padding(.top, 2)
                        MarkdownTextView(text: String(trimmedItem.dropFirst(4)))
                    }
                } else if trimmedItem.hasPrefix("[ ] ") {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "square")
                            .font(.system(size: appState.agentFontSize, weight: .regular))
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                        MarkdownTextView(text: String(trimmedItem.dropFirst(4)))
                    }
                } else {
                    HStack(alignment: .top, spacing: 8) {
                        Text(isOrdered ? "\(index + 1)." : "•")
                            .font(.system(size: appState.agentFontSize, weight: .semibold))
                            .foregroundColor(.secondary)
                            .frame(width: isOrdered ? 24 : 14, alignment: .trailing)
                        
                        MarkdownTextView(text: rawItem)
                    }
                }
            }
        }
        .padding(.leading, 6)
        .padding(.vertical, 2)
    }
}

/// Renders blockquote
struct BlockquoteView: View {
    let content: String
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.6))
                .frame(width: 3)
            
            Text(MarkdownAttrCache.getOrParse(content))
                .font(.system(size: appState.agentFontSize))
                .foregroundColor(.secondary)
                .tint(.accentColor)
                .italic()
                .environment(\.openURL, OpenURLAction { url in
                    if url.scheme == "file" {
                        let path = url.path
                        if !path.isEmpty {
                            NotificationCenter.default.post(
                                name: Notification.Name("MicroCodeOpenFileURL"),
                                object: URL(fileURLWithPath: path)
                            )
                            return .handled
                        }
                    }
                    return .systemAction
                })
                .padding(.leading, 12)
                .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renders LaTeX equation natively in SwiftUI without spawning heavy WKWebView child processes (~50MB RAM each)
struct LaTeXBlockView: View {
    let expression: String
    let isBlock: Bool
    @State private var copied = false
    
    private var formattedMath: String {
        Self.prettyFormatLaTeX(expression)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if isBlock { Spacer(minLength: 8) }
            Text(formattedMath)
                .font(.system(size: isBlock ? 15 : 13.5, weight: .regular, design: .serif))
                .foregroundColor(.primary.opacity(0.92))
                .multilineTextAlignment(isBlock ? .center : .leading)
                .padding(.vertical, isBlock ? 12 : 6)
                .padding(.horizontal, 14)
            if isBlock { Spacer(minLength: 8) }
        }
        .frame(maxWidth: .infinity)
        .background(Color.primary.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(expression, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .help("Copy LaTeX")
        }
        .cornerRadius(8)
    }
    
    static func prettyFormatLaTeX(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacements: [(String, String)] = [
            ("\\alpha", "α"), ("\\beta", "β"), ("\\gamma", "γ"), ("\\delta", "δ"),
            ("\\epsilon", "ε"), ("\\varepsilon", "ε"), ("\\zeta", "ζ"), ("\\eta", "η"),
            ("\\theta", "θ"), ("\\iota", "ι"), ("\\kappa", "κ"), ("\\lambda", "λ"),
            ("\\mu", "μ"), ("\\nu", "ν"), ("\\xi", "ξ"), ("\\pi", "π"),
            ("\\rho", "ρ"), ("\\sigma", "σ"), ("\\tau", "τ"), ("\\phi", "φ"),
            ("\\varphi", "φ"), ("\\chi", "χ"), ("\\psi", "ψ"), ("\\omega", "ω"),
            ("\\Gamma", "Γ"), ("\\Delta", "Δ"), ("\\Theta", "Θ"), ("\\Lambda", "Λ"),
            ("\\Xi", "Ξ"), ("\\Pi", "Π"), ("\\Sigma", "Σ"), ("\\Phi", "Φ"),
            ("\\Psi", "Ψ"), ("\\Omega", "Ω"),
            ("\\sum", "∑"), ("\\prod", "∏"), ("\\int", "∫"), ("\\partial", "∂"),
            ("\\nabla", "∇"), ("\\infty", "∞"), ("\\approx", "≈"), ("\\neq", "≠"),
            ("\\ne", "≠"), ("\\leq", "≤"), ("\\le", "≤"), ("\\geq", "≥"), ("\\ge", "≥"),
            ("\\times", "×"), ("\\cdot", "·"), ("\\pm", "±"), ("\\mp", "∓"),
            ("\\rightarrow", "→"), ("\\to", "→"), ("\\leftarrow", "←"),
            ("\\Rightarrow", "⇒"), ("\\Leftarrow", "⇐"), ("\\leftrightarrow", "↔"),
            ("\\Leftrightarrow", "⇔"), ("\\forall", "∀"), ("\\exists", "∃"),
            ("\\in", "∈"), ("\\notin", "∉"), ("\\subset", "⊂"), ("\\subseteq", "⊆"),
            ("\\cup", "∪"), ("\\cap", "∩"), ("\\emptyset", "∅"), ("\\sqrt", "√"),
            ("\\left", ""), ("\\right", ""), ("\\,", " "), ("\\;", " "), ("\\quad", "  ")
        ]
        for (k, v) in replacements {
            s = s.replacingOccurrences(of: k, with: v)
        }
        return s
    }
}

/// Renders HTML content or divider
struct HTMLBlockView: View {
    let content: String
    
    var body: some View {
        if content == "<hr/>" || content == "<hr>" || content == "<hr />" {
            Divider()
                .padding(.vertical, 8)
        } else {
            HTMLWebView(content: content)
                .frame(minHeight: 100)
                .frame(maxWidth: .infinity)
                .cornerRadius(6)
        }
    }
}

/// Renders Markdown Table with sleek macOS typography
struct TableBlockView: View {
    let headers: [String]
    let rows: [[String]]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 0) {
                // Header Row
                HStack(spacing: 0) {
                    ForEach(headers.indices, id: \.self) { idx in
                        HStack {
                            Text(MarkdownAttrCache.getOrParse(headers[idx]))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.primary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .frame(minWidth: 110, alignment: .leading)
                        
                        if idx < headers.count - 1 {
                            Divider()
                        }
                    }
                }
                .background(Color.primary.opacity(0.06))
                
                Divider()
                
                // Data Rows
                ForEach(rows.indices, id: \.self) { rowIdx in
                    let row = rows[rowIdx]
                    HStack(spacing: 0) {
                        ForEach(headers.indices, id: \.self) { colIdx in
                            let cellText = colIdx < row.count ? row[colIdx] : ""
                            HStack {
                                MarkdownTextView(text: cellText)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(minWidth: 110, alignment: .leading)
                            
                            if colIdx < headers.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(rowIdx % 2 == 1 ? Color.primary.opacity(0.02) : Color.clear)
                    
                    if rowIdx < rows.count - 1 {
                        Divider().opacity(0.5)
                    }
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(6)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - HTML WebView

struct HTMLWebView: NSViewRepresentable {
    let content: String
    
    final class Coordinator {
        var lastContent: String?
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let config = WebEngine.shared.createConfiguration(enableJavaScript: false)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.lastContent != content else { return }
        context.coordinator.lastContent = content
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                    font-size: 13px;
                    color: #e0e0e0;
                    background: #1e1e1e;
                    padding: 12px;
                    margin: 0;
                }
                table { border-collapse: collapse; width: 100%; }
                th, td { border: 1px solid #444; padding: 8px; text-align: left; }
                th { background: #2d2d2d; }
                a { color: #58a6ff; }
            </style>
        </head>
        <body>
            \(content)
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }
}

// MARK: - Dynamic Code Tag Generator

/// Generates meaningful tags from code content in real-time
struct CodeTagGenerator {
    private static let cacheLock = NSLock()
    private static var tagCache: [Int: String] = [:]
    private static var compiledRegexCache: [String: NSRegularExpression] = [:]
    
    static func cachedRegex(_ pattern: String) -> NSRegularExpression? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let existing = compiledRegexCache[pattern] {
            return existing
        }
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        compiledRegexCache[pattern] = regex
        return regex
    }
    
    /// Generate a smart tag from code analysis (memoized)
    static func generateTag(from code: String, language: String) -> String {
        var hasher = Hasher()
        hasher.combine(code.count)
        hasher.combine(code.prefix(512))
        hasher.combine(language.lowercased())
        let key = hasher.finalize()
        
        cacheLock.lock()
        if let cached = tagCache[key] {
            cacheLock.unlock()
            return cached
        }
        cacheLock.unlock()
        
        let sample = code.count > 2_000 ? String(code.prefix(2_000)) : code
        let result: String
        // 1. Try to extract function/method name
        if let funcName = extractFunctionName(from: sample, language: language) {
            result = "#\(funcName)"
        } else if let className = extractClassName(from: sample, language: language) {
            // 2. Try to extract class/struct name
            result = "#\(className)"
        } else if let purpose = detectPurpose(from: sample) {
            // 3. Try to detect purpose from comments
            result = "#\(purpose)"
        } else {
            // 4. Fallback to language + line count
            let lineCount = code.reduce(into: 1) { if $1 == "\n" { $0 += 1 } }
            let lang = language.isEmpty ? "Code" : language.capitalized
            result = "#\(lang)\(lineCount)L"
        }
        
        cacheLock.lock()
        if tagCache.count > 512 {
            tagCache.removeAll(keepingCapacity: true)
        }
        tagCache[key] = result
        cacheLock.unlock()
        return result
    }
    
    /// Extract function/method name
    private static func extractFunctionName(from code: String, language: String) -> String? {
        let patterns: [String]
        
        switch language.lowercased() {
        case "swift":
            patterns = [
                #"func\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"private\s+func\s+([a-zA-Z_][a-zA-Z0-9_]*)"#
            ]
        case "python":
            patterns = [#"def\s+([a-zA-Z_][a-zA-Z0-9_]*)"#]
        case "javascript", "typescript", "js", "ts":
            patterns = [
                #"function\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"const\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*\("#,
                #"([a-zA-Z_][a-zA-Z0-9_]*)\s*=\s*async"#
            ]
        case "rust":
            patterns = [#"fn\s+([a-zA-Z_][a-zA-Z0-9_]*)"#]
        case "go", "golang":
            patterns = [#"func\s+([a-zA-Z_][a-zA-Z0-9_]*)"#]
        case "java", "kotlin":
            patterns = [
                #"public\s+\w+\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\("#,
                #"private\s+\w+\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\("#,
                #"fun\s+([a-zA-Z_][a-zA-Z0-9_]*)"#
            ]
        default:
            patterns = [#"func\s+([a-zA-Z_][a-zA-Z0-9_]*)"#, #"function\s+([a-zA-Z_][a-zA-Z0-9_]*)"#]
        }
        
        for pattern in patterns {
            if let match = code.firstMatch(pattern: pattern) {
                return match
            }
        }
        return nil
    }
    
    /// Extract class/struct/type name
    private static func extractClassName(from code: String, language: String) -> String? {
        let patterns: [String]
        
        switch language.lowercased() {
        case "swift":
            patterns = [
                #"class\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"struct\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"enum\s+([a-zA-Z_][a-zA-Z0-9_]*)"#
            ]
        case "python":
            patterns = [#"class\s+([a-zA-Z_][a-zA-Z0-9_]*)"#]
        case "javascript", "typescript", "js", "ts":
            patterns = [
                #"class\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"interface\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"type\s+([a-zA-Z_][a-zA-Z0-9_]*)"#
            ]
        case "rust":
            patterns = [
                #"struct\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"enum\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"impl\s+([a-zA-Z_][a-zA-Z0-9_]*)"#
            ]
        case "java", "kotlin":
            patterns = [
                #"class\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"interface\s+([a-zA-Z_][a-zA-Z0-9_]*)"#,
                #"data\s+class\s+([a-zA-Z_][a-zA-Z0-9_]*)"#
            ]
        default:
            patterns = [#"class\s+([a-zA-Z_][a-zA-Z0-9_]*)"#]
        }
        
        for pattern in patterns {
            if let match = code.firstMatch(pattern: pattern) {
                return match
            }
        }
        return nil
    }
    
    /// Detect purpose from comments
    private static func detectPurpose(from code: String) -> String? {
        let lower = code.lowercased()
        
        if lower.contains("fix:") || lower.contains("// fix") || lower.contains("bugfix") {
            return "Fix"
        }
        if lower.contains("todo:") || lower.contains("// todo") {
            return "TODO"
        }
        if lower.contains("feature:") || lower.contains("new feature") {
            return "Feature"
        }
        if lower.contains("refactor") {
            return "Refactor"
        }
        if lower.contains("test") || lower.contains("spec") {
            return "Test"
        }
        if lower.contains("example") || lower.contains("demo") || lower.contains("sample") {
            return "Example"
        }
        if lower.contains("api") || lower.contains("endpoint") {
            return "API"
        }
        if lower.contains("model") || lower.contains("entity") {
            return "Model"
        }
        if lower.contains("view") || lower.contains("component") || lower.contains("ui") {
            return "View"
        }
        if lower.contains("service") || lower.contains("manager") {
            return "Service"
        }
        
        return nil
    }
}

// String extension for regex matching
extension String {
    func firstMatch(pattern: String) -> String? {
        guard let regex = CodeTagGenerator.cachedRegex(pattern) else {
            return nil
        }
        let range = NSRange(self.startIndex..., in: self)
        if let match = regex.firstMatch(in: self, options: [], range: range),
           match.numberOfRanges > 1,
           let captureRange = Range(match.range(at: 1), in: self) {
            return String(self[captureRange])
        }
        return nil
    }
}

/// Dynamic tag with auto-generated name
struct DynamicTag: Equatable {
    let name: String
    let color: Color
    
    static let none = DynamicTag(name: "", color: .gray)
    
    var isEmpty: Bool { name.isEmpty }
    
    init(name: String, color: Color = .accentColor) {
        self.name = name
        self.color = DynamicTag.colorFor(name: name)
    }
    
    private static func colorFor(name: String) -> Color {
        let lower = name.lowercased()
        if lower.contains("fix") || lower.contains("bug") { return .orange }
        if lower.contains("feature") || lower.contains("new") { return .green }
        if lower.contains("refactor") { return .purple }
        if lower.contains("test") { return .yellow }
        if lower.contains("api") || lower.contains("service") { return .cyan }
        if lower.contains("view") || lower.contains("ui") { return .pink }
        if lower.contains("model") { return .teal }
        // Hash-based color for unique names
        let hash = abs(name.hashValue)
        let colors: [Color] = [.blue, .indigo, .mint, .orange, .pink, .purple, .teal, .cyan]
        return colors[hash % colors.count]
    }
}

// MARK: - Purpose-Built Agent Mode Diff & Code Block (120fps Metal Rasterized, Zero Nested ScrollView)

fileprivate struct AgentParsedDiffBlock {
    struct Line: Identifiable {
        enum Kind {
            case addition
            case deletion
            case hunk
            case fileComment
            case context
        }
        let id: Int
        let lineNum: String
        let symbol: String
        let text: String
        let kind: Kind
    }
    
    let isDiff: Bool
    let title: String
    let additions: Int
    let deletions: Int
    let totalLines: Int
    let minContentWidth: CGFloat
    let lines: [Line]
}

fileprivate final class AgentCodeAndDiffCache {
    private static var diffCache: [Int: AgentParsedDiffBlock] = [:]
    private static let lock = NSLock()
    
    static func parse(language: String, code: String) -> AgentParsedDiffBlock {
        var hasher = Hasher()
        hasher.combine(language.lowercased())
        hasher.combine(code)
        let key = hasher.finalize()
        
        lock.lock()
        if let cached = diffCache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        
        let normalizedCode = code
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var rawLines = normalizedCode.components(separatedBy: "\n")
        if rawLines.count > 1 && rawLines.last == "" {
            rawLines.removeLast()
        }
        let trimmedFenceHeader = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let fenceTokens = trimmedFenceHeader
            .replacingOccurrences(of: "//", with: " ")
            .replacingOccurrences(of: ":", with: " ")
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let lowerLang = (fenceTokens.first ?? trimmedFenceHeader).lowercased()
        
        var extractedFile: String? = fenceTokens.dropFirst().first(where: { $0.contains(".") && $0.count <= 80 })
            ?? (trimmedFenceHeader.contains(".") && trimmedFenceHeader.contains("/") ? trimmedFenceHeader : nil)

        // Pre-scan to verify if this block is truly a unified diff so context lines drop their 1-space unified prefix cleanly
        var col0Add = 0
        var col0Del = 0
        var hasUnifiedMarkers = (lowerLang == "diff" || lowerLang == "patch")
        for rawLine in rawLines {
            if rawLine.hasPrefix("@@") || rawLine.hasPrefix("+++ ") || rawLine.hasPrefix("--- ") || rawLine.hasPrefix("diff --git") {
                hasUnifiedMarkers = true
            } else if rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                col0Add += 1
            } else if rawLine.hasPrefix("-") && !rawLine.hasPrefix("---") {
                col0Del += 1
            }
        }
        let isDiffBlock = hasUnifiedMarkers || (col0Add + col0Del >= 2 && col0Add > 0 && col0Del > 0 && lowerLang != "markdown" && lowerLang != "md" && lowerLang != "yaml" && lowerLang != "yml")

        func expandTabs(_ s: String) -> String {
            let expanded = s.contains("\t") ? s.replacingOccurrences(of: "\t", with: "    ") : s
            return expanded.isEmpty ? " " : expanded
        }

        var addCount = 0
        var delCount = 0
        var maxChars = 0
        var parsedLines: [AgentParsedDiffBlock.Line] = []
        parsedLines.reserveCapacity(min(rawLines.count, 500))
        
        var displayLineNum = 1
        for (idx, rawLine) in rawLines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            
            // Detect leading file comment on line 0/1: e.g. "// index.html", "# app.py", "--- a/index.html", "+++ b/index.html"
            if idx <= 2 && extractedFile == nil {
                if trimmed.hasPrefix("// ") || trimmed.hasPrefix("# ") || trimmed.hasPrefix("/* ") {
                    let candidate = trimmed
                        .replacingOccurrences(of: "//", with: "")
                        .replacingOccurrences(of: "/*", with: "")
                        .replacingOccurrences(of: "*/", with: "")
                        .replacingOccurrences(of: "#", with: "")
                        .trimmingCharacters(in: .whitespaces)
                    if candidate.contains(".") && !candidate.contains(" ") && candidate.count <= 80 {
                        extractedFile = candidate
                    }
                } else if trimmed.hasPrefix("+++ b/") || trimmed.hasPrefix("--- a/") {
                    let candidate = String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                    if !candidate.isEmpty && candidate != "/dev/null" {
                        extractedFile = URL(fileURLWithPath: candidate).lastPathComponent
                    }
                }
            }
            
            if isDiffBlock && (trimmed.hasPrefix("+++ ") || trimmed.hasPrefix("--- ") || trimmed.hasPrefix("diff --git ") || trimmed.hasPrefix("index ")) && (trimmed.contains("a/") || trimmed.contains("b/") || trimmed.contains("/dev/null") || trimmed.hasPrefix("index ")) {
                continue
            }
            
            if isDiffBlock && trimmed.hasPrefix("@@") {
                maxChars = max(maxChars, min(trimmed.count, 320))
                parsedLines.append(.init(id: idx, lineNum: "⋯", symbol: "", text: trimmed, kind: .hunk))
            } else if isDiffBlock && (trimmed == "..." || trimmed == "…") {
                parsedLines.append(.init(id: idx, lineNum: "⋯", symbol: "", text: "⋯", kind: .hunk))
            } else if isDiffBlock && rawLine.hasPrefix("+") && !rawLine.hasPrefix("+++") {
                addCount += 1
                let body = expandTabs(String(rawLine.dropFirst()))
                maxChars = max(maxChars, min(body.count, 320))
                parsedLines.append(.init(id: idx, lineNum: "\(displayLineNum)", symbol: "+", text: body, kind: .addition))
                displayLineNum += 1
            } else if isDiffBlock && rawLine.hasPrefix("-") && !rawLine.hasPrefix("---") {
                delCount += 1
                let body = expandTabs(String(rawLine.dropFirst()))
                maxChars = max(maxChars, min(body.count, 320))
                parsedLines.append(.init(id: idx, lineNum: "\(displayLineNum)", symbol: "−", text: body, kind: .deletion))
            } else if idx == 0 && extractedFile != nil && (trimmed.hasPrefix("//") || trimmed.hasPrefix("#") || trimmed.hasPrefix("/*")) {
                let body = expandTabs(isDiffBlock && rawLine.hasPrefix(" ") ? String(rawLine.dropFirst()) : rawLine)
                maxChars = max(maxChars, min(body.count, 320))
                parsedLines.append(.init(id: idx, lineNum: "\(displayLineNum)", symbol: " ", text: body, kind: .fileComment))
                displayLineNum += 1
            } else {
                // Drop the 1-space unified diff context prefix (" ") so context lines align identically with +/- lines
                let rawBody = (isDiffBlock && rawLine.hasPrefix(" ")) ? String(rawLine.dropFirst()) : rawLine
                let body = expandTabs(rawBody)
                maxChars = max(maxChars, min(body.count, 320))
                parsedLines.append(.init(id: idx, lineNum: "\(displayLineNum)", symbol: " ", text: body, kind: .context))
                displayLineNum += 1
            }
        }
        
        let resolvedTitle: String = {
            if let file = extractedFile, !file.isEmpty {
                return file
            }
            if isDiffBlock {
                return "Diff Patch"
            }
            return lowerLang.isEmpty ? "Code" : language.uppercased()
        }()
        let minContentWidth = CGFloat(maxChars) * 7.2 + 96.0
        
        let parsed = AgentParsedDiffBlock(
            isDiff: isDiffBlock,
            title: resolvedTitle,
            additions: addCount,
            deletions: delCount,
            totalLines: rawLines.count,
            minContentWidth: minContentWidth,
            lines: parsedLines
        )
        
        lock.lock()
        if diffCache.count > 256 {
            diffCache.removeAll(keepingCapacity: true)
        }
        diffCache[key] = parsed
        lock.unlock()
        return parsed
    }
    
    static func clearAll() {
        lock.lock()
        diffCache.removeAll(keepingCapacity: false)
        lock.unlock()
    }
}

struct NativeCodeBlockView: View, Equatable {
    let language: String
    let code: String
    
    static func == (lhs: NativeCodeBlockView, rhs: NativeCodeBlockView) -> Bool {
        return lhs.language == rhs.language && lhs.code == rhs.code
    }
    
    @State private var isCopied = false
    @State private var isExpanded = false
    @State private var blockViewportWidth: CGFloat = 0
    
    private let collapsedLineLimit = 22

    private var activeTheme: AppTheme {
        AppState.shared?.appTheme ?? .dark
    }
    
    var body: some View {
        let theme = activeTheme
        let editorCanvas = theme.isGlass ? Color.primary.opacity(0.03) : Color(nsColor: theme.editorBackground)
        let parsed = AgentCodeAndDiffCache.parse(language: language, code: code)
        VStack(alignment: .leading, spacing: 0) {
            agentHeaderView(parsed: parsed, theme: theme)
            Divider().opacity(0.32)
            if parsed.isDiff {
                agentDiffContentView(parsed: parsed, theme: theme)
            } else {
                agentCodeContentView(parsed: parsed, theme: theme)
            }
        }
        .background(editorCanvas)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.13), lineWidth: 1)
        )
        .padding(.vertical, 6)
    }
    
    // MARK: - Agent Mode Header (Theme-Synchronized)
    
    private func agentHeaderView(parsed: AgentParsedDiffBlock, theme: AppTheme) -> some View {
        let isLong = parsed.totalLines > collapsedLineLimit || code.count > 1_600
        let headerBg = theme.isGlass ? Color.primary.opacity(0.04) : Color(nsColor: theme.panelBackground)
        return HStack(spacing: 8) {
            ProgrammingLanguageIconView(
                fileName: parsed.title,
                languageHint: language,
                size: 15
            )
            
            Text(parsed.title)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
            
            if parsed.isDiff {
                HStack(spacing: 4) {
                    if parsed.additions > 0 {
                        Text("+\(parsed.additions)")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.green.opacity(0.15))
                            .cornerRadius(3.5)
                    }
                    if parsed.deletions > 0 {
                        Text("-\(parsed.deletions)")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundColor(.red)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(3.5)
                    }
                }
            } else if !language.isEmpty && parsed.title.lowercased() != language.lowercased() {
                Text(language.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(3.5)
            }
            
            Text("\(parsed.totalLines) lines")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.75))
            
            Spacer(minLength: 8)
            
            HStack(spacing: 6) {
                if !parsed.isDiff {
                    Button(action: openInEditor) {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.right.square")
                                .font(.system(size: 9.5))
                            Text("Editor")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("Open snippet in Code Editor")
                }
                
                if isLong {
                    Button(action: {
                        isExpanded.toggle()
                    }) {
                        HStack(spacing: 3) {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                            Text(isExpanded ? "Collapse" : "Expand")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                
                Button(action: copyCode) {
                    HStack(spacing: 3.5) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5, weight: .medium))
                        Text(isCopied ? "Copied" : "Copy")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundColor(isCopied ? .green : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(headerBg)
    }
    
    // MARK: - Agent Mode Diff Body (Theme-Synchronized & Full-Width Horizontal Scroll)
    
    private func agentDiffContentView(parsed: AgentParsedDiffBlock, theme: AppTheme) -> some View {
        let isTruncated = !isExpanded && parsed.lines.count > collapsedLineLimit
        let visibleLines = isTruncated ? Array(parsed.lines.prefix(collapsedLineLimit)) : parsed.lines
        let minRowWidth = max(blockViewportWidth, parsed.minContentWidth)
        let baseTextColor = Color(nsColor: theme.editorText)
        let lineNumColor = Color(nsColor: theme.commentColor).opacity(0.75)
        
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleLines) { line in
                        if line.kind == .hunk {
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(Color.cyan.opacity(0.85))
                                    .frame(width: 2.5, height: 21)

                                Text("⋯")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.cyan.opacity(0.8))
                                    .frame(width: 38, alignment: .center)

                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(width: 1, height: 21)

                                Text(line.text)
                                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(.cyan.opacity(0.9))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.leading, 10)
                                    .padding(.trailing, 18)

                                Spacer(minLength: 0)
                            }
                            .frame(minWidth: minRowWidth, minHeight: 21, maxHeight: 21, alignment: .leading)
                            .background(Color.cyan.opacity(theme.isDark ? 0.09 : 0.07))
                        } else {
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(diffBarColor(line.kind))
                                    .frame(width: 2.5, height: 19)
                                
                                Text(line.lineNum)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(lineNumColor)
                                    .frame(width: 34, alignment: .trailing)
                                    .padding(.trailing, 4)

                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(width: 1, height: 19)
                                
                                Text(line.symbol)
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundColor(diffSymbolColor(line.kind))
                                    .frame(width: 18, alignment: .center)
                                
                                Text(line.text)
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(diffTextColor(line.kind, baseTextColor: baseTextColor))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.trailing, 18)
                                
                                Spacer(minLength: 0)
                            }
                            .frame(minWidth: minRowWidth, minHeight: 19, maxHeight: 19, alignment: .leading)
                            .background(diffRowBackground(line.kind, isDark: theme.isDark))
                        }
                    }
                }
                .frame(minWidth: minRowWidth, alignment: .leading)
                .padding(.vertical, 4)
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { blockViewportWidth = geo.size.width }
                        .onChange(of: geo.size.width) { newW in blockViewportWidth = newW }
                }
            )
            
            if isTruncated {
                Divider().opacity(0.25)
                Button(action: {
                    isExpanded = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Show \(parsed.lines.count - collapsedLineLimit) more diff lines")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.025))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func diffBarColor(_ kind: AgentParsedDiffBlock.Line.Kind) -> Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .hunk: return .cyan.opacity(0.85)
        case .fileComment, .context: return .clear
        }
    }
    
    private func diffSymbolColor(_ kind: AgentParsedDiffBlock.Line.Kind) -> Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .hunk: return .cyan
        case .fileComment, .context: return .secondary.opacity(0.3)
        }
    }
    
    private func diffTextColor(_ kind: AgentParsedDiffBlock.Line.Kind, baseTextColor: Color) -> Color {
        switch kind {
        case .addition: return baseTextColor
        case .deletion: return baseTextColor.opacity(0.76)
        case .hunk: return .cyan.opacity(0.9)
        case .fileComment: return .secondary
        case .context: return baseTextColor.opacity(0.88)
        }
    }
    
    private func diffRowBackground(_ kind: AgentParsedDiffBlock.Line.Kind, isDark: Bool) -> Color {
        switch kind {
        case .addition: return Color.green.opacity(isDark ? 0.15 : 0.12)
        case .deletion: return Color.red.opacity(isDark ? 0.14 : 0.10)
        case .hunk: return Color.cyan.opacity(isDark ? 0.09 : 0.07)
        case .fileComment, .context: return Color.clear
        }
    }
    
    // MARK: - Agent Mode Standard Code Body (Theme-Synchronized)
    
    private func agentCodeContentView(parsed: AgentParsedDiffBlock, theme: AppTheme) -> some View {
        let isLong = parsed.totalLines > collapsedLineLimit || code.count > 1_600
        let isWideSingleLinePayload = code.count > 1_200 && parsed.totalLines <= 2
        
        let displayCode: String = {
            if isExpanded || !isLong {
                return code
            } else if isWideSingleLinePayload {
                return String(code.prefix(1_200)) + "\n…"
            } else {
                return code.components(separatedBy: "\n").prefix(collapsedLineLimit).joined(separator: "\n")
            }
        }()
        
        let highlightedCode: AttributedString = displayCode.count <= 8_000
            ? SyntaxHighlightingEngine.cachedSwiftUIAttributedString(
                displayCode,
                language: language.isEmpty ? "swift" : language,
                fontSize: 11.5,
                isDark: theme.isDark
            )
            : AttributedString(displayCode)
        
        return VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: true) {
                Text(highlightedCode)
                    .font(.custom("Menlo", size: 11.5))
                    .lineSpacing(3.5)
                    .foregroundColor(Color(nsColor: theme.editorText))
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minWidth: max(0, blockViewportWidth - 28), alignment: .leading)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .textSelection(.enabled)
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { blockViewportWidth = geo.size.width }
                        .onChange(of: geo.size.width) { newW in blockViewportWidth = newW }
                }
            )
            
            if isLong && !isExpanded {
                Divider().opacity(0.25)
                Button(action: {
                    isExpanded = true
                }) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                        Text(isWideSingleLinePayload
                             ? "Show \(max(0, code.count - 1_200)) more characters"
                             : "Show \(max(0, parsed.totalLines - collapsedLineLimit)) more lines")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.025))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private func openInEditor() {
        let ext = languageExtension(for: language)
        let fileName = "ai_code_\(Int(Date().timeIntervalSince1970)).\(ext)"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        do {
            try code.write(to: tempURL, atomically: true, encoding: .utf8)
            NotificationCenter.default.post(
                name: Notification.Name("OpenFileInEditor"),
                object: nil,
                userInfo: ["url": tempURL]
            )
        } catch {
            print("Failed to create temp file: \(error)")
        }
    }
    
    private func languageExtension(for lang: String) -> String {
        switch lang.lowercased() {
        case "swift": return "swift"
        case "python": return "py"
        case "javascript", "js": return "js"
        case "typescript", "ts": return "ts"
        case "rust": return "rs"
        case "go", "golang": return "go"
        case "java": return "java"
        case "kotlin": return "kt"
        case "ruby": return "rb"
        case "c": return "c"
        case "cpp", "c++": return "cpp"
        case "html": return "html"
        case "css": return "css"
        case "sql": return "sql"
        case "shell", "bash": return "sh"
        default: return "txt"
        }
    }
    
    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            isCopied = false
        }
    }
}

