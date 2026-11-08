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
    
    static func getOrParse(_ text: String, fontSize: CGFloat = 13.5) -> AttributedString {
        let key = "\(Int(fontSize * 10))|\(text)"
        lock.lock()
        if let found = cache[key] {
            lock.unlock()
            return found
        }
        lock.unlock()
        
        let sanitized = sanitizeStreamingMarkdown(text)
        let parsed = TeXMathEngine.parseMarkdownWithInlineTeX(sanitized, fontSize: fontSize)
        
        lock.lock()
        if cache.count > 1024 { cache.removeAll(keepingCapacity: true) }
        cache[key] = parsed
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
    
    static func resolvedFont(name: String, size: CGFloat) -> Font {
        if name.isEmpty || name == "SF Pro" || name == ".AppleSystemUIFont" {
            return .system(size: size)
        }
        return .custom(name, size: size)
    }
    
    var body: some View {
        let font = Self.resolvedFont(name: appState.agentFontName, size: fontSize)
        let attr = MarkdownAttrCache.getOrParse(text, fontSize: fontSize)
        Text(attr)
            .font(font)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundColor(.primary)
            .lineSpacing(5)
            .textSelection(.enabled)
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
        Text(MarkdownAttrCache.getOrParse(content, fontSize: fontSize))
            .font(.system(size: fontSize, weight: .bold))
            .foregroundColor(.primary)
            .tint(.accentColor)
            .textSelection(.enabled)
            .environment(\.openURL, OpenURLAction { url in
                if url.isFileURL || url.scheme == "file" || url.scheme == "microcode-file" {
                    if PreviewDockService.shared.openFileFromReference(url.absoluteString, workspacePath: appState.workspaceFolder?.path) {
                        return .handled
                    }
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
        Group {
            if blocks.count > 12 {
                LazyVStack(alignment: .leading, spacing: 10) {
                    renderedBlocks(blocks)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    renderedBlocks(blocks)
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func renderedBlocks(_ blocks: [MessageBlock]) -> some View {
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
}

/// Renders ordered/unordered list (with native checkbox support for [ ] and [x] and contiguous multi-bullet drag selection)
struct ListView: View {
    let items: [String]
    let isOrdered: Bool
    @EnvironmentObject var appState: AppState
    
    private var hasCheckboxItems: Bool {
        items.contains { raw in
            let t = raw.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("[x] ") || t.hasPrefix("[X] ") || t.hasPrefix("[ ] ")
        }
    }
    
    private var unifiedListAttributedString: AttributedString {
        var combined = AttributedString()
        for (index, rawItem) in items.enumerated() {
            if index > 0 {
                combined.append(AttributedString("\n"))
            }
            var marker = AttributedString(isOrdered ? "\(index + 1).  " : "•  ")
            marker.foregroundColor = .secondary
            combined.append(marker)
            combined.append(MarkdownAttrCache.getOrParse(rawItem, fontSize: appState.agentFontSize))
        }
        return combined
    }
    
    var body: some View {
        if !hasCheckboxItems {
            // Single contiguous Text so users can drag-select across multiple bullets and Cmd+C in one stroke
            let font = MarkdownTextView.resolvedFont(name: appState.agentFontName, size: appState.agentFontSize)
            Text(unifiedListAttributedString)
                .font(font)
                .foregroundColor(.primary)
                .lineSpacing(6)
                .textSelection(.enabled)
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
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
                .padding(.vertical, 2)
        } else {
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
            .textSelection(.enabled)
            .padding(.leading, 6)
            .padding(.vertical, 2)
        }
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
            
            Text(MarkdownAttrCache.getOrParse(content, fontSize: appState.agentFontSize))
                .font(.system(size: appState.agentFontSize))
                .foregroundColor(.secondary)
                .tint(.accentColor)
                .italic()
                .textSelection(.enabled)
                .environment(\.openURL, OpenURLAction { url in
                    if url.isFileURL || url.scheme == "file" || url.scheme == "microcode-file" {
                        if PreviewDockService.shared.openFileFromReference(url.absoluteString, workspacePath: appState.workspaceFolder?.path) {
                            return .handled
                        }
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

// MARK: - Native Mathematical TeX / LaTeX Engine (Inline + 2D Display Typography, Zero WebView RAM Overhead)

enum TeXFontStyle: Equatable {
    case mathItalic
    case uprightText
    case boldMath
    case boldText
    case italicText
    case blackboard
    case calligraphic
    case monospace
}

indirect enum TeXMathNode: Equatable {
    case text(String, style: TeXFontStyle)
    case symbol(String, isRelation: Bool = false, isBinOp: Bool = false, isBigOp: Bool = false)
    case space(CGFloat)
    case script(base: [TeXMathNode], sub: [TeXMathNode]?, sup: [TeXMathNode]?)
    case frac(num: [TeXMathNode], den: [TeXMathNode], hasBar: Bool = true)
    case sqrt(index: [TeXMathNode]?, radicand: [TeXMathNode])
    case overline([TeXMathNode])
    case underline([TeXMathNode])
    case delimited(left: String, body: [TeXMathNode], right: String)
    case matrix(kind: String, rows: [[[TeXMathNode]]])
}

struct TeXMathEngine {
    enum InlineSegment {
        case markdown(String)
        case inlineMath(String)
    }

    private static let astCacheLock = NSLock()
    private static var astCache: [String: [[TeXMathNode]]] = [:]

    static let commandSymbols: [String: (glyph: String, isRel: Bool, isBin: Bool, isBig: Bool)] = [
        // Lowercase Greek
        "alpha": ("α", false, false, false), "beta": ("β", false, false, false),
        "gamma": ("γ", false, false, false), "delta": ("δ", false, false, false),
        "epsilon": ("ϵ", false, false, false), "varepsilon": ("ε", false, false, false),
        "zeta": ("ζ", false, false, false), "eta": ("η", false, false, false),
        "theta": ("θ", false, false, false), "vartheta": ("ϑ", false, false, false),
        "iota": ("ι", false, false, false), "kappa": ("κ", false, false, false),
        "varkappa": ("ϰ", false, false, false), "lambda": ("λ", false, false, false),
        "mu": ("μ", false, false, false), "nu": ("ν", false, false, false),
        "xi": ("ξ", false, false, false), "pi": ("π", false, false, false),
        "varpi": ("ϖ", false, false, false), "rho": ("ρ", false, false, false),
        "varrho": ("ϱ", false, false, false), "sigma": ("σ", false, false, false),
        "varsigma": ("ς", false, false, false), "tau": ("τ", false, false, false),
        "upsilon": ("υ", false, false, false), "phi": ("ϕ", false, false, false),
        "varphi": ("φ", false, false, false), "chi": ("χ", false, false, false),
        "psi": ("ψ", false, false, false), "omega": ("ω", false, false, false),
        // Uppercase Greek
        "Gamma": ("Γ", false, false, false), "Delta": ("Δ", false, false, false),
        "Theta": ("Θ", false, false, false), "Lambda": ("Λ", false, false, false),
        "Xi": ("Ξ", false, false, false), "Pi": ("Π", false, false, false),
        "Sigma": ("Σ", false, false, false), "Upsilon": ("Υ", false, false, false),
        "Phi": ("Φ", false, false, false), "Psi": ("Ψ", false, false, false),
        "Omega": ("Ω", false, false, false),
        // Scientific & Physics Symbols
        "AA": ("Å", false, false, false), "angstrom": ("Å", false, false, false),
        "hbar": ("ℏ", false, false, false), "ell": ("ℓ", false, false, false),
        "Re": ("ℜ", false, false, false), "Im": ("ℑ", false, false, false),
        "wp": ("℘", false, false, false), "aleph": ("ℵ", false, false, false),
        "infty": ("∞", false, false, false), "partial": ("∂", false, false, false),
        "nabla": ("∇", false, false, false), "emptyset": ("∅", false, false, false),
        "varnothing": ("∅", false, false, false), "degree": ("°", false, false, false),
        "circ": ("∘", false, true, false), "prime": ("′", false, false, false),
        "triangle": ("△", false, false, false), "Box": ("□", false, false, false),
        "square": ("□", false, false, false), "angle": ("∠", false, false, false),
        "forall": ("∀", false, false, false), "exists": ("∃", false, false, false),
        "nexists": ("∄", false, false, false), "neg": ("¬", false, false, false),
        "lnot": ("¬", false, false, false), "top": ("⊤", false, false, false),
        "bot": ("⊥", false, false, false), "perp": ("⊥", true, false, false),
        "parallel": ("∥", true, false, false), "backslash": ("\\", false, false, false),
        "dots": ("…", false, false, false), "ldots": ("…", false, false, false),
        "cdots": ("⋯", false, false, false), "vdots": ("⋮", false, false, false),
        "ddots": ("⋱", false, false, false), "checkmark": ("✓", false, false, false),
        // Binary Operators
        "pm": ("±", false, true, false), "mp": ("∓", false, true, false),
        "times": ("×", false, true, false), "div": ("÷", false, true, false),
        "cdot": ("·", false, true, false), "ast": ("∗", false, true, false),
        "star": ("⋆", false, true, false), "oplus": ("⊕", false, true, false),
        "ominus": ("⊖", false, true, false), "otimes": ("⊗", false, true, false),
        "odot": ("⊙", false, true, false), "cup": ("∪", false, true, false),
        "cap": ("∩", false, true, false), "setminus": ("∖", false, true, false),
        "land": ("∧", false, true, false), "wedge": ("∧", false, true, false),
        "lor": ("∨", false, true, false), "vee": ("∨", false, true, false),
        "bullet": ("∙", false, true, false), "dagger": ("†", false, false, false),
        "ddagger": ("‡", false, false, false),
        // Relations & Arrows
        "le": ("≤", true, false, false), "leq": ("≤", true, false, false),
        "leqslant": ("⩽", true, false, false), "ge": ("≥", true, false, false),
        "geq": ("≥", true, false, false), "geqslant": ("⩾", true, false, false),
        "ll": ("≪", true, false, false), "gg": ("≫", true, false, false),
        "ne": ("≠", true, false, false), "neq": ("≠", true, false, false),
        "approx": ("≈", true, false, false), "sim": ("∼", true, false, false),
        "simeq": ("≃", true, false, false), "cong": ("≅", true, false, false),
        "equiv": ("≡", true, false, false), "propto": ("∝", true, false, false),
        "in": ("∈", true, false, false), "notin": ("∉", true, false, false),
        "ni": ("∋", true, false, false), "subset": ("⊂", true, false, false),
        "supset": ("⊃", true, false, false), "subseteq": ("⊆", true, false, false),
        "supseteq": ("⊇", true, false, false), "vdash": ("⊢", true, false, false),
        "models": ("⊨", true, false, false), "mid": ("∣", true, false, false),
        "to": ("→", true, false, false), "rightarrow": ("→", true, false, false),
        "longrightarrow": ("⟶", true, false, false), "leftarrow": ("←", true, false, false),
        "gets": ("←", true, false, false), "leftrightarrow": ("↔", true, false, false),
        "Rightarrow": ("⇒", true, false, false), "implies": ("⟹", true, false, false),
        "Leftarrow": ("⇐", true, false, false), "Leftrightarrow": ("⇔", true, false, false),
        "iff": ("⟺", true, false, false), "mapsto": ("↦", true, false, false),
        "uparrow": ("↑", true, false, false), "downarrow": ("↓", true, false, false),
        "nearrow": ("↗", true, false, false), "searrow": ("↘", true, false, false),
        "rightleftharpoons": ("⇌", true, false, false), "rightharpoonup": ("⇀", true, false, false),
        // Big Operators
        "sum": ("∑", false, false, true), "prod": ("∏", false, false, true),
        "coprod": ("∐", false, false, true), "int": ("∫", false, false, true),
        "iint": ("∬", false, false, true), "iiint": ("∭", false, false, true),
        "oint": ("∮", false, false, true), "bigcup": ("⋃", false, false, true),
        "bigcap": ("⋂", false, false, true), "bigoplus": ("⨁", false, false, true),
        "bigotimes": ("⨂", false, false, true),
        // Delimiters
        "langle": ("⟨", false, false, false), "rangle": ("⟩", false, false, false),
        "lfloor": ("⌊", false, false, false), "rfloor": ("⌋", false, false, false),
        "lceil": ("⌈", false, false, false), "rceil": ("⌉", false, false, false),
        "lvert": ("|", false, false, false), "rvert": ("|", false, false, false),
        "lVert": ("‖", false, false, false), "rVert": ("‖", false, false, false)
    ]

    static let namedFunctions: Set<String> = [
        "sin", "cos", "tan", "cot", "sec", "csc",
        "arcsin", "arccos", "arctan", "sinh", "cosh", "tanh", "coth",
        "ln", "log", "lg", "exp", "lim", "limsup", "liminf",
        "sup", "inf", "max", "min", "arg", "argmax", "argmin",
        "det", "dim", "ker", "hom", "deg", "gcd", "Pr", "cov", "var",
        "tr", "diag", "rank", "span", "sgn", "erf", "softmax", "sigmoid",
        "mod", "bmod", "pmod"
    ]

    static let limitBigOperators: Set<String> = ["lim", "limsup", "liminf", "max", "min", "sup", "inf", "argmax", "argmin"]

    // MARK: - Inline Markdown + TeX Splitter & Compiler

    static func parseMarkdownWithInlineTeX(_ text: String, fontSize: CGFloat = 13.5) -> AttributedString {
        guard text.contains("$") || text.contains("\\(") || text.contains("\\[") else {
            return (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        }
        let segments = splitInlineSegments(text)
        if segments.count == 1, case .markdown(let only) = segments[0] {
            return (try? AttributedString(markdown: only, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(only)
        }

        // Placeholder pass so outer Markdown formatting like `**Pauling-Corey $\alpha$-Helix**`
        // or `[Section $C_\alpha$](url)` stays intact across inline math boundaries!
        var templated = ""
        var mathExpressions: [String] = []
        for seg in segments {
            switch seg {
            case .markdown(let md):
                templated += md
            case .inlineMath(let math):
                let idx = mathExpressions.count
                mathExpressions.append(math)
                templated += "MCTEXPH\(idx)END"
            }
        }

        var attributed = (try? AttributedString(markdown: templated, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(templated)

        for (idx, math) in mathExpressions.enumerated() {
            let token = "MCTEXPH\(idx)END"
            guard let range = attributed.range(of: token) else { continue }
            let existingIntent = attributed[range].inlinePresentationIntent
            let existingLink = attributed[range].link
            let isBoldContext = existingIntent?.contains(.stronglyEmphasized) == true

            let lines = parseDisplayLines(math)
            var mathAttr = AttributedString()
            for (lIdx, lineNodes) in lines.enumerated() {
                if lIdx > 0 { mathAttr.append(AttributedString("  ")) }
                mathAttr.append(
                    compileNodesToAttributedString(
                        lineNodes,
                        fontSize: fontSize,
                        overrideStyle: isBoldContext ? .boldMath : nil
                    )
                )
            }
            if let link = existingLink {
                mathAttr.link = link
            }
            attributed.replaceSubrange(range, with: mathAttr)
        }
        return attributed
    }

    static func splitInlineSegments(_ text: String) -> [InlineSegment] {
        let chars = Array(text)
        let n = chars.count
        var segments: [InlineSegment] = []
        var mdStart = 0
        var i = 0

        func flushMarkdown(upTo end: Int) {
            if end > mdStart {
                segments.append(.markdown(String(chars[mdStart..<end])))
            }
        }

        while i < n {
            let c = chars[i]

            // 1. Respect Markdown code spans (`...` or ``...``)
            if c == "`" {
                var tickCount = 0
                while i + tickCount < n && chars[i + tickCount] == "`" { tickCount += 1 }
                var j = i + tickCount
                var foundClose = false
                while j < n {
                    if chars[j] == "`" {
                        var closeCount = 0
                        while j + closeCount < n && chars[j + closeCount] == "`" { closeCount += 1 }
                        if closeCount == tickCount {
                            i = j + closeCount
                            foundClose = true
                            break
                        }
                        j += closeCount
                    } else {
                        j += 1
                    }
                }
                if !foundClose { i += tickCount }
                continue
            }

            // 2. Skip Markdown link URL target `](...)` so `$` inside URLs is untouched
            if c == "]" && i + 1 < n && chars[i + 1] == "(" {
                var j = i + 2
                var parenDepth = 1
                while j < n && parenDepth > 0 && chars[j] != "\n" {
                    if chars[j] == "(" { parenDepth += 1 }
                    else if chars[j] == ")" { parenDepth -= 1 }
                    j += 1
                }
                i = j
                continue
            }

            // 3. Escaped character (`\$`, `\\`, etc.)
            if c == "\\" && i + 1 < n {
                let next = chars[i + 1]
                if next == "(" || next == "[" {
                    let closeChar: Character = (next == "(") ? ")" : "]"
                    var j = i + 2
                    var foundEnd: Int? = nil
                    while j + 1 < n {
                        if chars[j] == "\\" && chars[j + 1] == closeChar {
                            foundEnd = j
                            break
                        }
                        j += 1
                    }
                    if let end = foundEnd {
                        let inner = String(chars[(i + 2)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !inner.isEmpty {
                            flushMarkdown(upTo: i)
                            segments.append(.inlineMath(inner))
                            i = end + 2
                            mdStart = i
                            continue
                        }
                    }
                }
                // Skip escaped char (e.g. `\$`)
                i += 2
                continue
            }

            // 4. Inline `$$...$$` or `$...$`
            if c == "$" {
                // Check `$$...$$` on a single/inline span
                if i + 1 < n && chars[i + 1] == "$" {
                    var j = i + 2
                    var foundEnd: Int? = nil
                    while j + 1 < n {
                        if chars[j] == "$" && chars[j + 1] == "$" && chars[j - 1] != "\\" {
                            foundEnd = j
                            break
                        }
                        j += 1
                    }
                    if let end = foundEnd {
                        let inner = String(chars[(i + 2)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !inner.isEmpty {
                            flushMarkdown(upTo: i)
                            segments.append(.inlineMath(inner))
                            i = end + 2
                            mdStart = i
                            continue
                        }
                    }
                    i += 2
                    continue
                }

                // Single `$...$` on the same line
                var j = i + 1
                var braceDepth = 0
                var foundEnd: Int? = nil
                while j < n && chars[j] != "\n" {
                    if chars[j] == "\\" {
                        j += 2
                        continue
                    }
                    if chars[j] == "{" { braceDepth += 1 }
                    else if chars[j] == "}" && braceDepth > 0 { braceDepth -= 1 }
                    else if chars[j] == "$" && braceDepth == 0 {
                        // Do not match if immediately followed by another `$`
                        if j + 1 < n && chars[j + 1] == "$" { break }
                        foundEnd = j
                        break
                    }
                    j += 1
                }

                if let end = foundEnd {
                    let afterIsDigit: Bool = (end + 1 < n) && chars[end + 1].isASCII && chars[end + 1].isNumber
                    let rawInner = String(chars[(i + 1)..<end])
                    if !afterIsDigit && isValidSingleDollarMath(rawInner) {
                        flushMarkdown(upTo: i)
                        segments.append(.inlineMath(rawInner.trimmingCharacters(in: .whitespaces)))
                        i = end + 1
                        mdStart = i
                        continue
                    }
                }
            }

            i += 1
        }

        flushMarkdown(upTo: n)
        return segments
    }

    private static func isValidSingleDollarMath(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }

        let hasTeXSyntax = raw.contains("\\") || raw.contains("_") || raw.contains("^") || raw.contains("{") || raw.contains("}")
        if hasTeXSyntax {
            return true
        }

        // Standard KaTeX/Pandoc delimiter check when no explicit TeX backslash/sub/sup is present
        if raw.first?.isWhitespace == true || raw.last?.isWhitespace == true {
            return false
        }

        // Reject plain currency prose like `$100 per user and $`
        if let first = trimmed.first, first.isNumber && trimmed.contains(" ") {
            let mathIndicators: Set<Character> = ["=", "+", "-", "*", "/", "<", ">", "(", ")", "≈", "≤", "≥", "≠", "×", "·", "±"]
            if !trimmed.contains(where: { mathIndicators.contains($0) }) {
                return false
            }
        }
        return true
    }

    // MARK: - AST Parser (Cached)

    static func parseDisplayLines(_ rawExpression: String) -> [[TeXMathNode]] {
        let key = rawExpression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return [] }

        astCacheLock.lock()
        if let cached = astCache[key] {
            astCacheLock.unlock()
            return cached
        }
        astCacheLock.unlock()

        var parser = Parser(key)
        let parsed = parser.parseTopLevelLines()

        astCacheLock.lock()
        if astCache.count > 512 { astCache.removeAll(keepingCapacity: true) }
        astCache[key] = parsed
        astCacheLock.unlock()
        return parsed
    }

    static func contains2DStructure(_ lines: [[TeXMathNode]]) -> Bool {
        func check(_ nodes: [TeXMathNode]) -> Bool {
            for node in nodes {
                switch node {
                case .frac, .sqrt, .overline, .underline, .matrix:
                    return true
                case .script(let base, let sub, let sup):
                    if base.contains(where: { if case .symbol(_, _, _, let big) = $0 { return big }; return false }) && (sub != nil || sup != nil) {
                        return true
                    }
                    if check(base) || (sub.map(check) ?? false) || (sup.map(check) ?? false) {
                        return true
                    }
                case .delimited(_, let body, _):
                    if check(body) { return true }
                default:
                    break
                }
            }
            return false
        }
        return lines.contains(where: check)
    }

    // MARK: - Inline AttributedString Compiler (True Typographic Subscripts/Superscripts + Thai Text Support)

    static func compileNodesToAttributedString(
        _ nodes: [TeXMathNode],
        fontSize: CGFloat,
        baselineOffset: CGFloat = 0,
        overrideStyle: TeXFontStyle? = nil
    ) -> AttributedString {
        var result = AttributedString()
        var prevWasOperand = false

        for (idx, node) in nodes.enumerated() {
            switch node {
            case .text(let str, let nodeStyle):
                let style = overrideStyle ?? nodeStyle
                var run = AttributedString(applyStyleTransform(str, style: style))
                run.font = fontForStyle(style, size: fontSize)
                if baselineOffset != 0 { run.baselineOffset = baselineOffset }
                result.append(run)
                prevWasOperand = !str.trimmingCharacters(in: .whitespaces).isEmpty

            case .symbol(let sym, let isRel, let isBin, _):
                var textOut = sym
                if isRel {
                    let needLead = idx > 0
                    let needTrail = idx + 1 < nodes.count
                    textOut = (needLead ? " " : "") + sym + (needTrail ? " " : "")
                    prevWasOperand = false
                } else if isBin {
                    if sym == "-" || sym == "−" {
                        if prevWasOperand && idx + 1 < nodes.count {
                            textOut = " − "
                        } else {
                            textOut = "−"
                        }
                    } else if sym == "+" {
                        if prevWasOperand && idx + 1 < nodes.count {
                            textOut = " + "
                        } else {
                            textOut = "+"
                        }
                    } else if prevWasOperand && idx + 1 < nodes.count {
                        textOut = " \(sym) "
                    }
                    prevWasOperand = false
                } else if sym == "," {
                    let nextIsSpace: Bool = {
                        guard idx + 1 < nodes.count else { return true }
                        if case .space = nodes[idx + 1] { return true }
                        if case .text(let s, _) = nodes[idx + 1], s.first?.isWhitespace == true { return true }
                        // Keep comma inside numbers like 1,000 tight
                        if case .symbol(let nextSym, _, _, _) = nodes[idx + 1], nextSym.first?.isNumber == true,
                           idx > 0, case .symbol(let prevSym, _, _, _) = nodes[idx - 1], prevSym.last?.isNumber == true {
                            return true
                        }
                        return false
                    }()
                    textOut = nextIsSpace ? "," : ", "
                    prevWasOperand = false
                } else {
                    let closeSet: Set<String> = [")", "]", "}", "⟩", "⌋", "⌉", "|", "‖", "!", "%", "°", "′"]
                    let openSet: Set<String> = ["(", "[", "{", "⟨", "⌊", "⌈"]
                    if openSet.contains(sym) {
                        prevWasOperand = false
                    } else if closeSet.contains(sym) {
                        prevWasOperand = true
                    } else {
                        prevWasOperand = true
                    }
                }

                var run = AttributedString(textOut)
                let useSerif = !containsThaiOrCJK(textOut)
                run.font = useSerif
                    ? .system(size: fontSize, weight: overrideStyle == .boldMath ? .bold : .regular, design: .serif)
                    : .system(size: fontSize, weight: .regular)
                if baselineOffset != 0 { run.baselineOffset = baselineOffset }
                result.append(run)

            case .space(let em):
                if em > 0 {
                    let str = em >= 0.9 ? "  " : (em >= 0.25 ? " " : "\u{2009}")
                    var run = AttributedString(str)
                    run.font = .system(size: fontSize)
                    result.append(run)
                }

            case .script(let base, let sub, let sup):
                result.append(compileNodesToAttributedString(base, fontSize: fontSize, baselineOffset: baselineOffset, overrideStyle: overrideStyle))
                let scriptSize = max(8.5, fontSize * 0.73)
                if let supNodes = sup, !supNodes.isEmpty {
                    // Render `^\circ` cleanly as degree sign `°`
                    if supNodes == [.symbol("∘", isRelation: false, isBinOp: true, isBigOp: false)] {
                        var deg = AttributedString("°")
                        deg.font = .system(size: fontSize, design: .serif)
                        if baselineOffset != 0 { deg.baselineOffset = baselineOffset }
                        result.append(deg)
                    } else {
                        result.append(
                            compileNodesToAttributedString(
                                supNodes,
                                fontSize: scriptSize,
                                baselineOffset: baselineOffset + fontSize * 0.34,
                                overrideStyle: overrideStyle
                            )
                        )
                    }
                }
                if let subNodes = sub, !subNodes.isEmpty {
                    result.append(
                        compileNodesToAttributedString(
                            subNodes,
                            fontSize: scriptSize,
                            baselineOffset: baselineOffset - fontSize * 0.22,
                            overrideStyle: overrideStyle
                        )
                    )
                }
                prevWasOperand = true

            case .frac(let num, let den, let hasBar):
                let fracSize = max(9.0, fontSize * 0.80)
                let wrapNum = num.count > 1
                let wrapDen = den.count > 1
                if !hasBar {
                    var lp = AttributedString("(")
                    lp.font = .system(size: fontSize, design: .serif)
                    result.append(lp)
                    result.append(compileNodesToAttributedString(num, fontSize: fracSize, baselineOffset: baselineOffset + fontSize * 0.26))
                    result.append(compileNodesToAttributedString(den, fontSize: fracSize, baselineOffset: baselineOffset - fontSize * 0.18))
                    var rp = AttributedString(")")
                    rp.font = .system(size: fontSize, design: .serif)
                    result.append(rp)
                } else {
                    if wrapNum {
                        var p = AttributedString("("); p.font = .system(size: fracSize, design: .serif); p.baselineOffset = baselineOffset + fontSize * 0.22
                        result.append(p)
                    }
                    result.append(compileNodesToAttributedString(num, fontSize: fracSize, baselineOffset: baselineOffset + fontSize * 0.22))
                    if wrapNum {
                        var p = AttributedString(")"); p.font = .system(size: fracSize, design: .serif); p.baselineOffset = baselineOffset + fontSize * 0.22
                        result.append(p)
                    }
                    var slash = AttributedString("⁄")
                    slash.font = .system(size: fontSize, design: .serif)
                    if baselineOffset != 0 { slash.baselineOffset = baselineOffset }
                    result.append(slash)
                    if wrapDen {
                        var p = AttributedString("("); p.font = .system(size: fracSize, design: .serif); p.baselineOffset = baselineOffset - fontSize * 0.14
                        result.append(p)
                    }
                    result.append(compileNodesToAttributedString(den, fontSize: fracSize, baselineOffset: baselineOffset - fontSize * 0.14))
                    if wrapDen {
                        var p = AttributedString(")"); p.font = .system(size: fracSize, design: .serif); p.baselineOffset = baselineOffset - fontSize * 0.14
                        result.append(p)
                    }
                }
                prevWasOperand = true

            case .sqrt(let index, let radicand):
                if let idxNodes = index, !idxNodes.isEmpty {
                    result.append(compileNodesToAttributedString(idxNodes, fontSize: max(8.5, fontSize * 0.68), baselineOffset: baselineOffset + fontSize * 0.34))
                }
                var root = AttributedString("√")
                root.font = .system(size: fontSize, design: .serif)
                if baselineOffset != 0 { root.baselineOffset = baselineOffset }
                result.append(root)
                let needsParens = radicand.count > 1
                if needsParens {
                    var lp = AttributedString("("); lp.font = .system(size: fontSize, design: .serif)
                    if baselineOffset != 0 { lp.baselineOffset = baselineOffset }
                    result.append(lp)
                }
                result.append(compileNodesToAttributedString(radicand, fontSize: fontSize, baselineOffset: baselineOffset, overrideStyle: overrideStyle))
                if needsParens {
                    var rp = AttributedString(")"); rp.font = .system(size: fontSize, design: .serif)
                    if baselineOffset != 0 { rp.baselineOffset = baselineOffset }
                    result.append(rp)
                }
                prevWasOperand = true

            case .overline(let inner):
                var innerAttr = compileNodesToAttributedString(inner, fontSize: fontSize, baselineOffset: baselineOffset, overrideStyle: overrideStyle)
                if innerAttr.characters.count == 1 {
                    innerAttr.append(AttributedString("\u{0304}"))
                }
                result.append(innerAttr)
                prevWasOperand = true

            case .underline(let inner):
                var innerAttr = compileNodesToAttributedString(inner, fontSize: fontSize, baselineOffset: baselineOffset, overrideStyle: overrideStyle)
                innerAttr.underlineStyle = .single
                result.append(innerAttr)
                prevWasOperand = true

            case .delimited(let left, let body, let right):
                if !left.isEmpty {
                    var l = AttributedString(left)
                    l.font = .system(size: fontSize, design: .serif)
                    if baselineOffset != 0 { l.baselineOffset = baselineOffset }
                    result.append(l)
                }
                result.append(compileNodesToAttributedString(body, fontSize: fontSize, baselineOffset: baselineOffset, overrideStyle: overrideStyle))
                if !right.isEmpty {
                    var r = AttributedString(right)
                    r.font = .system(size: fontSize, design: .serif)
                    if baselineOffset != 0 { r.baselineOffset = baselineOffset }
                    result.append(r)
                }
                prevWasOperand = true

            case .matrix(let kind, let rows):
                let (lDel, rDel) = matrixDelimiters(for: kind)
                if !lDel.isEmpty {
                    var l = AttributedString(lDel); l.font = .system(size: fontSize, design: .serif)
                    result.append(l)
                }
                for (rIdx, row) in rows.enumerated() {
                    if rIdx > 0 { result.append(AttributedString("; ")) }
                    for (cIdx, cell) in row.enumerated() {
                        if cIdx > 0 { result.append(AttributedString(", ")) }
                        result.append(compileNodesToAttributedString(cell, fontSize: fontSize, baselineOffset: baselineOffset))
                    }
                }
                if !rDel.isEmpty {
                    var r = AttributedString(rDel); r.font = .system(size: fontSize, design: .serif)
                    result.append(r)
                }
                prevWasOperand = true
            }
        }
        return result
    }

    static func matrixDelimiters(for kind: String) -> (String, String) {
        switch kind {
        case "pmatrix": return ("(", ")")
        case "bmatrix": return ("[", "]")
        case "Bmatrix": return ("{", "}")
        case "vmatrix": return ("|", "|")
        case "Vmatrix": return ("‖", "‖")
        case "cases": return ("{", "")
        default: return ("", "")
        }
    }

    private static func containsThaiOrCJK(_ s: String) -> Bool {
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if (0x0E00...0x0E7F).contains(v) || (0x3000...0x9FFF).contains(v) {
                return true
            }
        }
        return false
    }

    private static func fontForStyle(_ style: TeXFontStyle, size: CGFloat) -> Font {
        switch style {
        case .mathItalic:
            return .system(size: size, weight: .regular, design: .serif).italic()
        case .uprightText:
            return .system(size: size, weight: .regular)
        case .boldMath:
            return .system(size: size, weight: .bold, design: .serif).italic()
        case .boldText:
            return .system(size: size, weight: .bold)
        case .italicText:
            return .system(size: size, weight: .regular).italic()
        case .blackboard:
            return .system(size: size, weight: .semibold, design: .serif)
        case .calligraphic:
            return .system(size: size, weight: .medium, design: .serif).italic()
        case .monospace:
            return .system(size: size, weight: .regular, design: .monospaced)
        }
    }

    private static func applyStyleTransform(_ str: String, style: TeXFontStyle) -> String {
        guard style == .blackboard else { return str }
        let map: [Character: String] = [
            "A": "𝔸", "B": "𝔹", "C": "ℂ", "D": "𝔻", "E": "𝔼", "F": "𝔽", "G": "𝔾",
            "H": "ℍ", "I": "𝕀", "J": "𝕁", "K": "𝕂", "L": "𝕃", "M": "𝕄", "N": "ℕ",
            "O": "𝕆", "P": "ℙ", "Q": "ℚ", "R": "ℝ", "S": "𝕊", "T": "𝕋", "U": "𝕌",
            "V": "𝕍", "W": "𝕎", "X": "𝕏", "Y": "𝕐", "Z": "ℤ", "1": "𝟙"
        ]
        return str.map { map[$0] ?? String($0) }.joined()
    }

    // MARK: - Recursive-Descent TeX Parser

    private struct Parser {
        let chars: [Character]
        var pos: Int = 0

        init(_ src: String) {
            self.chars = Array(src)
        }

        private var isAtEnd: Bool { pos >= chars.count }

        mutating func parseTopLevelLines() -> [[TeXMathNode]] {
            skipWhitespace()
            // Unwrap outer equation/displaymath wrapper while preserving matrix/align/cases
            if let env = peekBeginEnvironment() {
                let passthroughEnvs: Set<String> = ["equation", "equation*", "math", "displaymath"]
                if passthroughEnvs.contains(env) {
                    _ = consumeBeginEnvironment()
                    let inner = parseNodesUntil(stopAtEndEnv: env, stopAtRowBreak: false, stopAtCellSep: false, stopAtRight: false)
                    return [inner]
                }
            }

            var lines: [[TeXMathNode]] = []
            while !isAtEnd {
                let row = parseNodesUntil(stopAtEndEnv: nil, stopAtRowBreak: true, stopAtCellSep: false, stopAtRight: false)
                if !row.isEmpty {
                    lines.append(row)
                }
            }
            return lines.isEmpty ? [[]] : lines
        }

        mutating func skipWhitespace() {
            while pos < chars.count && chars[pos].isWhitespace {
                pos += 1
            }
        }

        private func peekBeginEnvironment() -> String? {
            let prefix = Array("\\begin{")
            guard pos + prefix.count < chars.count else { return nil }
            for k in 0..<prefix.count where chars[pos + k] != prefix[k] { return nil }
            var j = pos + prefix.count
            var name = ""
            while j < chars.count && chars[j] != "}" {
                name.append(chars[j])
                j += 1
            }
            return j < chars.count ? name : nil
        }

        private mutating func consumeBeginEnvironment() -> String? {
            guard let name = peekBeginEnvironment() else { return nil }
            pos += 7 + name.count + 1 // `\begin{` + name + `}`
            return name
        }

        private func peekEndEnvironment() -> String? {
            let prefix = Array("\\end{")
            guard pos + prefix.count < chars.count else { return nil }
            for k in 0..<prefix.count where chars[pos + k] != prefix[k] { return nil }
            var j = pos + prefix.count
            var name = ""
            while j < chars.count && chars[j] != "}" {
                name.append(chars[j])
                j += 1
            }
            return j < chars.count ? name : nil
        }

        private mutating func consumeEndEnvironment() {
            if let name = peekEndEnvironment() {
                pos += 5 + name.count + 1
            }
        }

        mutating func parseNodesUntil(
            stopAtEndEnv: String?,
            stopAtRowBreak: Bool,
            stopAtCellSep: Bool,
            stopAtRight: Bool,
            stopAtCloseBrace: Bool = false
        ) -> [TeXMathNode] {
            var nodes: [TeXMathNode] = []

            while !isAtEnd {
                skipWhitespace()
                if isAtEnd { break }

                let c = chars[pos]

                if stopAtCloseBrace && c == "}" {
                    pos += 1
                    break
                }

                if stopAtCellSep && c == "&" {
                    pos += 1
                    break
                }

                if c == "&" {
                    // Alignment tab outside explicit matrix -> render subtle space
                    pos += 1
                    nodes.append(.space(0.35))
                    continue
                }

                // Check `\end{...}` or `\\` or `\right`
                if c == "\\" {
                    if let endEnv = peekEndEnvironment() {
                        if stopAtEndEnv == nil || endEnv == stopAtEndEnv {
                            consumeEndEnvironment()
                            break
                        }
                    }
                    if pos + 1 < chars.count && chars[pos + 1] == "\\" {
                        pos += 2
                        // Optional `[4pt]` spacing after `\\`
                        skipWhitespace()
                        if pos < chars.count && chars[pos] == "[" {
                            while pos < chars.count && chars[pos] != "]" { pos += 1 }
                            if pos < chars.count && chars[pos] == "]" { pos += 1 }
                        }
                        if stopAtRowBreak {
                            break
                        } else {
                            nodes.append(.space(0.8))
                            continue
                        }
                    }
                    if stopAtRight && matchKeyword("\\right") {
                        break
                    }
                }

                if let atom = parseAtomWithScripts() {
                    nodes.append(contentsOf: atom)
                } else {
                    break
                }
            }
            return nodes
        }

        private func matchKeyword(_ kw: String) -> Bool {
            let kwChars = Array(kw)
            guard pos + kwChars.count <= chars.count else { return false }
            for k in 0..<kwChars.count where chars[pos + k] != kwChars[k] { return false }
            let nextIdx = pos + kwChars.count
            if nextIdx < chars.count && chars[nextIdx].isLetter { return false }
            return true
        }

        mutating func parseAtomWithScripts() -> [TeXMathNode]? {
            guard let base = parsePrimaryAtom() else { return nil }
            var sub: [TeXMathNode]? = nil
            var sup: [TeXMathNode]? = nil
            var extraPrimes = ""

            while !isAtEnd {
                skipWhitespace()
                if isAtEnd { break }
                if chars[pos] == "'" {
                    extraPrimes.append("′")
                    pos += 1
                    continue
                }
                if chars[pos] == "_" && sub == nil {
                    pos += 1
                    sub = parseScriptArgument()
                } else if chars[pos] == "^" && sup == nil {
                    pos += 1
                    sup = parseScriptArgument()
                } else {
                    break
                }
            }

            if !extraPrimes.isEmpty {
                let primeNode = TeXMathNode.symbol(extraPrimes)
                if sup != nil {
                    sup?.insert(primeNode, at: 0)
                } else if sub != nil {
                    sup = [primeNode]
                } else {
                    return base + [primeNode]
                }
            }

            if sub != nil || sup != nil {
                return [.script(base: base, sub: sub, sup: sup)]
            }
            return base
        }

        mutating func parseScriptArgument() -> [TeXMathNode] {
            skipWhitespace()
            guard !isAtEnd else { return [] }
            if chars[pos] == "{" {
                pos += 1
                return parseNodesUntil(stopAtEndEnv: nil, stopAtRowBreak: false, stopAtCellSep: false, stopAtRight: false, stopAtCloseBrace: true)
            }
            return parsePrimaryAtom() ?? []
        }

        mutating func parseBracedGroup() -> [TeXMathNode] {
            skipWhitespace()
            guard !isAtEnd else { return [] }
            if chars[pos] == "{" {
                pos += 1
                return parseNodesUntil(stopAtEndEnv: nil, stopAtRowBreak: false, stopAtCellSep: false, stopAtRight: false, stopAtCloseBrace: true)
            }
            return parsePrimaryAtom() ?? []
        }

        mutating func parseOptionalBracketGroup() -> [TeXMathNode]? {
            skipWhitespace()
            guard !isAtEnd, chars[pos] == "[" else { return nil }
            pos += 1
            var raw = ""
            var depth = 1
            while pos < chars.count && depth > 0 {
                if chars[pos] == "[" { depth += 1 }
                else if chars[pos] == "]" {
                    depth -= 1
                    if depth == 0 { pos += 1; break }
                }
                raw.append(chars[pos])
                pos += 1
            }
            var subParser = Parser(raw)
            return subParser.parseNodesUntil(stopAtEndEnv: nil, stopAtRowBreak: false, stopAtCellSep: false, stopAtRight: false)
        }

        mutating func readRawBracedText() -> String {
            skipWhitespace()
            guard !isAtEnd else { return "" }
            if chars[pos] != "{" {
                let ch = chars[pos]
                pos += 1
                return String(ch)
            }
            pos += 1
            var out = ""
            var depth = 1
            while pos < chars.count && depth > 0 {
                let ch = chars[pos]
                if ch == "\\" && pos + 1 < chars.count {
                    out.append(ch)
                    out.append(chars[pos + 1])
                    pos += 2
                    continue
                }
                if ch == "{" {
                    depth += 1
                    out.append(ch)
                } else if ch == "}" {
                    depth -= 1
                    if depth > 0 { out.append(ch) }
                } else {
                    out.append(ch)
                }
                pos += 1
            }
            return expandTextModeMacros(out)
        }

        private func expandTextModeMacros(_ raw: String) -> String {
            guard raw.contains("\\") || raw.contains("~") else { return raw }
            let cs = Array(raw)
            var out = ""
            var k = 0
            while k < cs.count {
                if cs[k] == "~" {
                    out.append("\u{00A0}")
                    k += 1
                    continue
                }
                if cs[k] == "\\" && k + 1 < cs.count {
                    let next = cs[k + 1]
                    if !next.isLetter {
                        switch next {
                        case " ", ",", ";", ":": out.append(" ")
                        case "!": break
                        case "%", "_", "&", "#", "$", "{", "}": out.append(next)
                        default: out.append(next)
                        }
                        k += 2
                        continue
                    }
                    var j = k + 1
                    var cmd = ""
                    while j < cs.count && cs[j].isLetter {
                        cmd.append(cs[j])
                        j += 1
                    }
                    if let sym = TeXMathEngine.commandSymbols[cmd] {
                        out.append(sym.glyph)
                        // In TeX text mode, `\AA ` absorbs a single trailing space unless followed by `\ `
                        if cmd == "AA" || cmd == "angstrom" {
                            // Preserve slash/text right after `\AA`, e.g. `\AA/residue` -> `Å/residue`
                        }
                        k = j
                        continue
                    }
                    out.append(cmd)
                    k = j
                    continue
                }
                out.append(cs[k])
                k += 1
            }
            return out
        }

        mutating func parsePrimaryAtom() -> [TeXMathNode]? {
            skipWhitespace()
            guard !isAtEnd else { return nil }

            let c = chars[pos]

            if c == "}" {
                return nil
            }

            if c == "{" {
                pos += 1
                return parseNodesUntil(stopAtEndEnv: nil, stopAtRowBreak: false, stopAtCellSep: false, stopAtRight: false, stopAtCloseBrace: true)
            }

            if c == "~" {
                pos += 1
                return [.space(0.35)]
            }

            // Numbers (coalesce contiguous digits & decimal point)
            if c.isASCII && c.isNumber {
                var num = ""
                while pos < chars.count && ((chars[pos].isASCII && chars[pos].isNumber) || (chars[pos] == "." && pos + 1 < chars.count && chars[pos + 1].isNumber)) {
                    num.append(chars[pos])
                    pos += 1
                }
                return [.symbol(num)]
            }

            // Single ASCII variable letter -> math italic
            if c.isASCII && c.isLetter {
                pos += 1
                return [.text(String(c), style: .mathItalic)]
            }

            // Non-ASCII letters / Thai characters directly inside math -> upright text
            if !c.isASCII && (c.isLetter || ("\u{0E00}"..."\u{0E7F}").contains(c)) {
                var word = ""
                while pos < chars.count && !chars[pos].isASCII && (chars[pos].isLetter || ("\u{0E00}"..."\u{0E7F}").contains(chars[pos])) {
                    word.append(chars[pos])
                    pos += 1
                }
                return [.text(word, style: .uprightText)]
            }

            // Backslash command or environment
            if c == "\\" {
                if let env = consumeBeginEnvironment() {
                    return [parseEnvironment(env)]
                }
                pos += 1
                guard !isAtEnd else { return [.symbol("\\")] }

                let next = chars[pos]
                if !next.isLetter {
                    pos += 1
                    switch next {
                    case " ": return [.space(0.35)]
                    case ",": return [.space(0.20)]
                    case ";", ":": return [.space(0.30)]
                    case "!": return [.space(0)]
                    case "{": return [.symbol("{")]
                    case "}": return [.symbol("}")]
                    case "|": return [.symbol("‖")]
                    case "%", "_", "&", "#", "$": return [.symbol(String(next))]
                    default: return [.symbol(String(next))]
                    }
                }

                var cmd = ""
                while pos < chars.count && chars[pos].isLetter {
                    cmd.append(chars[pos])
                    pos += 1
                }
                // Handle starred commands like `\operatorname*`
                if pos < chars.count && chars[pos] == "*" {
                    pos += 1
                }

                return handleCommand(cmd)
            }

            // Standard ASCII / Unicode math operators & punctuation
            pos += 1
            switch c {
            case "=", "<", ">", "≈", "≠", "≤", "≥", "≡", "∼", "∝", "→", "←", "↔", "⇒", "⇔", "∈", "∉", "⊂", "⊆":
                return [.symbol(String(c), isRelation: true)]
            case "+", "-", "−", "±", "∓", "×", "÷", "·":
                return [.symbol(c == "-" ? "-" : String(c), isBinOp: true)]
            case "*":
                return [.symbol("∗", isBinOp: true)]
            default:
                return [.symbol(String(c))]
            }
        }

        private mutating func parseEnvironment(_ env: String) -> TeXMathNode {
            var rows: [[[TeXMathNode]]] = []
            var rowCells: [[TeXMathNode]] = []
            var cellNodes: [TeXMathNode] = []
            while !isAtEnd {
                skipWhitespace()
                if isAtEnd { break }
                if let endName = peekEndEnvironment(), endName == env {
                    consumeEndEnvironment()
                    if !cellNodes.isEmpty || !rowCells.isEmpty {
                        rowCells.append(cellNodes)
                        rows.append(rowCells)
                    }
                    break
                }
                if chars[pos] == "&" {
                    pos += 1
                    rowCells.append(cellNodes)
                    cellNodes = []
                    continue
                }
                if chars[pos] == "\\" && pos + 1 < chars.count && chars[pos + 1] == "\\" {
                    pos += 2
                    skipWhitespace()
                    if pos < chars.count && chars[pos] == "[" {
                        while pos < chars.count && chars[pos] != "]" { pos += 1 }
                        if pos < chars.count && chars[pos] == "]" { pos += 1 }
                    }
                    rowCells.append(cellNodes)
                    rows.append(rowCells)
                    rowCells = []
                    cellNodes = []
                    continue
                }
                if let atom = parseAtomWithScripts() {
                    cellNodes.append(contentsOf: atom)
                } else {
                    pos += 1
                }
            }
            let normalizedKind = env.replacingOccurrences(of: "*", with: "")
            return .matrix(kind: normalizedKind, rows: rows)
        }

        private mutating func readDelimiterToken() -> String {
            skipWhitespace()
            guard !isAtEnd else { return "" }
            if chars[pos] == "." {
                pos += 1
                return ""
            }
            if chars[pos] == "\\" {
                pos += 1
                guard !isAtEnd else { return "" }
                if !chars[pos].isLetter {
                    let ch = chars[pos]
                    pos += 1
                    if ch == "|" { return "‖" }
                    return String(ch)
                }
                var cmd = ""
                while pos < chars.count && chars[pos].isLetter {
                    cmd.append(chars[pos])
                    pos += 1
                }
                if let sym = TeXMathEngine.commandSymbols[cmd] {
                    return sym.glyph
                }
                return ""
            }
            let ch = chars[pos]
            pos += 1
            return String(ch)
        }

        private mutating func handleCommand(_ cmd: String) -> [TeXMathNode] {
            switch cmd {
            case "frac", "dfrac", "tfrac", "cfrac":
                let num = parseBracedGroup()
                let den = parseBracedGroup()
                return [.frac(num: num, den: den, hasBar: true)]

            case "binom", "dbinom", "tbinom":
                let top = parseBracedGroup()
                let bot = parseBracedGroup()
                return [.delimited(left: "(", body: [.frac(num: top, den: bot, hasBar: false)], right: ")")]

            case "sqrt":
                let idx = parseOptionalBracketGroup()
                let rad = parseBracedGroup()
                return [.sqrt(index: idx, radicand: rad)]

            case "overline", "bar":
                return [.overline(parseBracedGroup())]

            case "underline":
                return [.underline(parseBracedGroup())]

            case "hat", "widehat", "tilde", "widetilde", "vec", "overrightarrow", "dot", "ddot":
                let combining: String = {
                    switch cmd {
                    case "hat", "widehat": return "\u{0302}"
                    case "tilde", "widetilde": return "\u{0303}"
                    case "vec", "overrightarrow": return "\u{20D7}"
                    case "dot": return "\u{0307}"
                    case "ddot": return "\u{0308}"
                    default: return "\u{0302}"
                    }
                }()
                var grp = parseBracedGroup()
                if grp.count == 1, case .text(let s, let st) = grp[0], s.count == 1 {
                    grp[0] = .text(s + combining, style: st)
                } else if grp.count == 1, case .symbol(let s, let r, let b, let big) = grp[0], s.count == 1 {
                    grp[0] = .symbol(s + combining, isRelation: r, isBinOp: b, isBigOp: big)
                }
                return grp

            case "text", "textrm", "textsf", "textnormal", "mathrm", "mbox", "hbox", "operatorname":
                let txt = readRawBracedText()
                return [.text(txt, style: .uprightText)]

            case "textbf":
                return [.text(readRawBracedText(), style: .boldText)]

            case "mathbf", "boldsymbol", "bm":
                let inner = parseBracedGroup()
                return inner.map { node in
                    if case .text(let s, _) = node { return .text(s, style: .boldMath) }
                    return node
                }

            case "textit", "mathit":
                return [.text(readRawBracedText(), style: .italicText)]

            case "mathbb":
                return [.text(readRawBracedText(), style: .blackboard)]

            case "mathcal", "mathscr":
                return [.text(readRawBracedText(), style: .calligraphic)]

            case "texttt", "mathtt":
                return [.text(readRawBracedText(), style: .monospace)]

            case "color", "textcolor":
                _ = readRawBracedText() // consume color name
                return parseBracedGroup()

            case "displaystyle", "textstyle", "scriptstyle", "scriptscriptstyle", "limits", "nolimits", "nonumber", "notag":
                return []

            case "quad":
                return [.space(1.0)]

            case "qquad":
                return [.space(1.8)]

            case "hspace", "vspace", "phantom", "hphantom":
                _ = readRawBracedText()
                return [.space(0.4)]

            case "tag":
                let tagStr = readRawBracedText()
                return [.space(1.2), .text("(\(tagStr))", style: .uprightText)]

            case "left":
                let leftDel = readDelimiterToken()
                let inner = parseNodesUntil(stopAtEndEnv: nil, stopAtRowBreak: false, stopAtCellSep: false, stopAtRight: true)
                var rightDel = ""
                if matchKeyword("\\right") {
                    pos += 6
                    rightDel = readDelimiterToken()
                }
                return [.delimited(left: leftDel, body: inner, right: rightDel)]

            case "bigl", "Bigl", "biggl", "Biggl", "bigr", "Bigr", "biggr", "Biggr", "big", "Big":
                let d = readDelimiterToken()
                return d.isEmpty ? [] : [.symbol(d)]

            default:
                if let sym = TeXMathEngine.commandSymbols[cmd] {
                    return [.symbol(sym.glyph, isRelation: sym.isRel, isBinOp: sym.isBin, isBigOp: sym.isBig)]
                }
                if TeXMathEngine.namedFunctions.contains(cmd) {
                    let isBig = TeXMathEngine.limitBigOperators.contains(cmd)
                    if isBig {
                        return [.symbol(cmd, isBigOp: true)]
                    }
                    return [.text(cmd, style: .uprightText), .space(0.15)]
                }
                // Fallback: render unknown command name upright without ugly leading backslash
                return [.text(cmd, style: .uprightText)]
            }
        }
    }
}

// MARK: - 2D Native SwiftUI Display Math Renderer (Stacked Fractions, Radicals, Matrices & Big Operators)

private struct TeXMathRowView: View {
    let nodes: [TeXMathNode]
    let fontSize: CGFloat

    private enum Segment {
        case inlineRun([TeXMathNode])
        case node2D(TeXMathNode)
    }

    private var segments: [Segment] {
        var out: [Segment] = []
        var buffer: [TeXMathNode] = []

        func flushBuffer() {
            if !buffer.isEmpty {
                out.append(.inlineRun(buffer))
                buffer.removeAll(keepingCapacity: true)
            }
        }

        for n in nodes {
            if TeXMathEngine.contains2DStructure([[n]]) {
                flushBuffer()
                out.append(.node2D(n))
            } else {
                buffer.append(n)
            }
        }
        flushBuffer()
        return out
    }

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .inlineRun(let runNodes):
                    Text(TeXMathEngine.compileNodesToAttributedString(runNodes, fontSize: fontSize))
                        .fixedSize()
                case .node2D(let node):
                    TeXMath2DNodeView(node: node, fontSize: fontSize)
                }
            }
        }
    }
}

private struct TeXMath2DNodeView: View {
    let node: TeXMathNode
    let fontSize: CGFloat

    var body: some View {
        switch node {
        case .frac(let num, let den, let hasBar):
            let subSize = max(10.5, fontSize * 0.86)
            VStack(alignment: .center, spacing: 2) {
                TeXMathRowView(nodes: num, fontSize: subSize)
                    .padding(.horizontal, 3)
                if hasBar {
                    Rectangle()
                        .fill(Color.primary.opacity(0.82))
                        .frame(height: 1.1)
                }
                TeXMathRowView(nodes: den, fontSize: subSize)
                    .padding(.horizontal, 3)
            }
            .fixedSize()
            .padding(.horizontal, 2)

        case .sqrt(let index, let radicand):
            HStack(alignment: .center, spacing: 0) {
                if let idx = index, !idx.isEmpty {
                    TeXMathRowView(nodes: idx, fontSize: max(9, fontSize * 0.65))
                        .offset(x: 2, y: -fontSize * 0.35)
                }
                Text("√")
                    .font(.system(size: fontSize * 1.18, weight: .regular, design: .serif))
                VStack(spacing: 1) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.82))
                        .frame(height: 1.0)
                    TeXMathRowView(nodes: radicand, fontSize: fontSize)
                        .padding(.horizontal, 2)
                }
                .fixedSize()
            }

        case .overline(let inner):
            VStack(spacing: 1) {
                Rectangle()
                    .fill(Color.primary.opacity(0.82))
                    .frame(height: 1.0)
                TeXMathRowView(nodes: inner, fontSize: fontSize)
            }
            .fixedSize()

        case .underline(let inner):
            VStack(spacing: 1) {
                TeXMathRowView(nodes: inner, fontSize: fontSize)
                Rectangle()
                    .fill(Color.primary.opacity(0.82))
                    .frame(height: 1.0)
            }
            .fixedSize()

        case .script(let base, let sub, let sup):
            let isBig = base.contains(where: { if case .symbol(_, _, _, let big) = $0 { return big }; return false })
            if isBig {
                let limSize = max(9.5, fontSize * 0.70)
                VStack(alignment: .center, spacing: 1) {
                    if let supNodes = sup, !supNodes.isEmpty {
                        TeXMathRowView(nodes: supNodes, fontSize: limSize)
                    }
                    TeXMathRowView(nodes: base, fontSize: fontSize * 1.24)
                    if let subNodes = sub, !subNodes.isEmpty {
                        TeXMathRowView(nodes: subNodes, fontSize: limSize)
                    }
                }
                .fixedSize()
                .padding(.horizontal, 2)
            } else {
                HStack(alignment: .center, spacing: 1) {
                    TeXMathRowView(nodes: base, fontSize: fontSize)
                    VStack(alignment: .leading, spacing: 1) {
                        if let supNodes = sup, !supNodes.isEmpty {
                            TeXMathRowView(nodes: supNodes, fontSize: max(9.5, fontSize * 0.72))
                        }
                        if let subNodes = sub, !subNodes.isEmpty {
                            TeXMathRowView(nodes: subNodes, fontSize: max(9.5, fontSize * 0.72))
                        }
                    }
                }
                .fixedSize()
            }

        case .delimited(let left, let body, let right):
            HStack(alignment: .center, spacing: 2) {
                if !left.isEmpty {
                    Text(left)
                        .font(.system(size: fontSize * 1.32, weight: .light, design: .serif))
                }
                TeXMathRowView(nodes: body, fontSize: fontSize)
                if !right.isEmpty {
                    Text(right)
                        .font(.system(size: fontSize * 1.32, weight: .light, design: .serif))
                }
            }
            .fixedSize()

        case .matrix(let kind, let rows):
            let (lDel, rDel) = TeXMathEngine.matrixDelimiters(for: kind)
            let isAligned = kind.hasPrefix("align") || kind == "cases"
            HStack(alignment: .center, spacing: 4) {
                if !lDel.isEmpty {
                    Text(lDel)
                        .font(.system(size: fontSize * CGFloat(max(1.25, Double(rows.count) * 0.72)), weight: .ultraLight, design: .serif))
                }
                Grid(alignment: isAligned ? .leading : .center, horizontalSpacing: 10, verticalSpacing: 5) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { colIdx, cell in
                                TeXMathRowView(nodes: cell, fontSize: fontSize * 0.94)
                                    .gridColumnAlignment(isAligned && colIdx == 0 && kind != "cases" ? .trailing : .leading)
                            }
                        }
                    }
                }
                if !rDel.isEmpty {
                    Text(rDel)
                        .font(.system(size: fontSize * CGFloat(max(1.25, Double(rows.count) * 0.72)), weight: .ultraLight, design: .serif))
                }
            }
            .fixedSize()

        default:
            Text(TeXMathEngine.compileNodesToAttributedString([node], fontSize: fontSize))
                .fixedSize()
        }
    }
}

/// Renders LaTeX equations natively in SwiftUI with full 2D fractions/radicals/matrices & Thai `\text{...}` support
struct LaTeXBlockView: View {
    let expression: String
    let isBlock: Bool
    @State private var copied = false
    @State private var isHovering = false
    @State private var showRawSource = false

    var body: some View {
        let baseFontSize: CGFloat = isBlock ? 15.0 : 13.5
        let lines = TeXMathEngine.parseDisplayLines(expression)
        let uses2D = TeXMathEngine.contains2DStructure(lines)

        Group {
            if showRawSource {
                Text(expression.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .padding(.trailing, 28)
            } else if uses2D {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .center, spacing: 8) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, lineNodes in
                            TeXMathRowView(nodes: lineNodes, fontSize: baseFontSize)
                        }
                    }
                    .frame(minWidth: isBlock ? 120 : nil)
                    .padding(.vertical, isBlock ? 12 : 6)
                    .padding(.horizontal, 16)
                    .padding(.trailing, 24)
                }
                .frame(maxWidth: .infinity, alignment: isBlock ? .center : .leading)
            } else {
                // Single/multi-line inline-height equation (e.g. pIC₅₀ = 4.306 + 0.173(Net Charge) + ...)
                // Wraps cleanly across narrow panels with ZERO `...` truncation!
                VStack(alignment: isBlock ? .center : .leading, spacing: 6) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, lineNodes in
                        Text(TeXMathEngine.compileNodesToAttributedString(lineNodes, fontSize: baseFontSize))
                            .multilineTextAlignment(isBlock ? .center : .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: isBlock ? .center : .leading)
                .padding(.vertical, isBlock ? 12 : 6)
                .padding(.horizontal, 14)
                .padding(.trailing, 24)
            }
        }
        .background(Color.primary.opacity(0.04))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 2) {
                if isHovering || showRawSource {
                    Button(action: { showRawSource.toggle() }) {
                        Text(showRawSource ? "TeX" : "</>")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(showRawSource ? .accentColor : .secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help(showRawSource ? "Show Rendered Equation" : "View LaTeX Source")
                }

                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(expression, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }) {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(copied ? .green : .secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .opacity(isHovering || copied ? 1.0 : 0.65)
                .help("Copy LaTeX")
            }
            .padding(3)
        }
        .cornerRadius(8)
        .onHover { isHovering = $0 }
    }

    static func prettyFormatLaTeX(_ raw: String) -> String {
        let lines = TeXMathEngine.parseDisplayLines(raw)
        return lines.map { String(TeXMathEngine.compileNodesToAttributedString($0, fontSize: 14).characters) }
            .joined(separator: "\n")
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

/// Renders Markdown Table with native text selection, unobstructed drag-highlight, and quick cell/table copy
struct TableBlockView: View {
    let headers: [String]
    let rows: [[String]]
    @State private var copiedCellKey: String? = nil
    @State private var hoveredCellKey: String? = nil
    @State private var copiedTable: Bool = false
    
    private var tsvRepresentation: String {
        var lines: [String] = [headers.joined(separator: "\t")]
        for row in rows {
            lines.append(row.joined(separator: "\t"))
        }
        return lines.joined(separator: "\n")
    }
    
    private static func plainCellValue(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "`", with: "")
    }
    
    @ViewBuilder
    private func tableGridContent(scrollable: Bool) -> some View {
        let minColW: CGFloat = scrollable ? 110 : 72
        let maxColW: CGFloat? = scrollable ? nil : .infinity
        VStack(alignment: .leading, spacing: 0) {
            // Header Row
            HStack(spacing: 0) {
                ForEach(headers.indices, id: \.self) { idx in
                    HStack(spacing: 4) {
                        Text(MarkdownAttrCache.getOrParse(headers[idx]))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(minWidth: minColW, maxWidth: maxColW, alignment: .leading)
                    
                    if idx < headers.count - 1 {
                        Divider()
                    }
                }
            }
            .background(Color.primary.opacity(0.06))
            .overlay(alignment: .trailing) {
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tsvRepresentation, forType: .string)
                    copiedTable = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedTable = false }
                }) {
                    HStack(spacing: 3) {
                        Image(systemName: copiedTable ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5, weight: .medium))
                        if copiedTable {
                            Text("Copied")
                                .font(.system(size: 9.5, weight: .medium))
                        }
                    }
                    .foregroundColor(copiedTable ? .green : .secondary.opacity(0.75))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
                .help("คัดลอกทั้งตาราง (Copy Table)")
            }
            
            Divider()
            
            // Data Rows
            ForEach(rows.indices, id: \.self) { rowIdx in
                let row = rows[rowIdx]
                HStack(spacing: 0) {
                    ForEach(headers.indices, id: \.self) { colIdx in
                        let cellText = colIdx < row.count ? row[colIdx] : ""
                        let cellKey = "\(rowIdx)-\(colIdx)"
                        let cleanValue = Self.plainCellValue(cellText)
                        HStack(spacing: 4) {
                            MarkdownTextView(text: cellText)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 10)
                        .padding(.trailing, !cleanValue.isEmpty ? 16 : 0)
                        .padding(.vertical, 7)
                        .frame(minWidth: minColW, maxWidth: maxColW, alignment: .leading)
                        .onHover { hovering in
                            if hovering {
                                hoveredCellKey = cellKey
                            } else if hoveredCellKey == cellKey {
                                hoveredCellKey = nil
                            }
                        }
                        .overlay(alignment: .trailing) {
                            if !cleanValue.isEmpty && (hoveredCellKey == cellKey || copiedCellKey == cellKey) {
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(cleanValue, forType: .string)
                                    copiedCellKey = cellKey
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                                        if copiedCellKey == cellKey { copiedCellKey = nil }
                                    }
                                }) {
                                    Image(systemName: copiedCellKey == cellKey ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 9.5, weight: .medium))
                                        .foregroundColor(copiedCellKey == cellKey ? .green : .secondary)
                                        .padding(4)
                                        .background(Color.primary.opacity(0.07))
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                                .padding(.trailing, 6)
                                .help("คัดลอก '\(cleanValue)'")
                            }
                        }
                        
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
        .textSelection(.enabled)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .cornerRadius(6)
    }
    
    var body: some View {
        Group {
            if headers.count >= 5 {
                ScrollView(.horizontal, showsIndicators: true) {
                    tableGridContent(scrollable: true)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    tableGridContent(scrollable: false)
                    ScrollView(.horizontal, showsIndicators: true) {
                        tableGridContent(scrollable: true)
                    }
                }
            }
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
    
    /// Maps a diff title (usually a file name) or fence language to a lexer language id.
    private func agentDiffLanguage(title: String) -> String? {
        let ext = (title.split(separator: " ").last.map(String.init) ?? title)
            .split(separator: ".").last.map { String($0).lowercased() } ?? ""
        let map: [String: String] = [
            "swift": "swift", "py": "python", "js": "javascript", "jsx": "javascript", "mjs": "javascript",
            "ts": "typescript", "tsx": "typescript", "rs": "rust", "go": "go", "c": "c", "h": "c",
            "cpp": "cpp", "cc": "cpp", "hpp": "cpp", "m": "objective-c", "mm": "objective-c",
            "java": "java", "kt": "kotlin", "rb": "ruby", "sh": "shell", "zsh": "shell", "bash": "shell",
            "json": "json", "yaml": "yaml", "yml": "yaml", "md": "markdown", "html": "html", "css": "css",
            "sql": "sql", "dart": "dart", "php": "php", "lua": "lua", "cs": "csharp", "zig": "zig", "ar": "ardium"
        ]
        if let lang = map[ext] { return lang }
        let fence = language.lowercased()
        if !fence.isEmpty, fence != "diff", fence != "patch" { return fence }
        return nil
    }
    
    /// Syntax-highlights a single diff row with the active editor theme (VS Code-style diff colors).
    private func diffHighlightedText(_ text: String, language: String?, theme: AppTheme) -> AttributedString {
        guard let language, text.utf8.count <= 600, !text.isEmpty else { return AttributedString(text) }
        return SyntaxHighlightingEngine.cachedSwiftUIAttributedString(
            text, language: language, fontSize: 11.5, isDark: theme.isDark, themeName: theme.rawValue
        )
    }
    
    private func agentDiffContentView(parsed: AgentParsedDiffBlock, theme: AppTheme) -> some View {
        let isTruncated = !isExpanded && parsed.lines.count > collapsedLineLimit
        let visibleLines = isTruncated ? Array(parsed.lines.prefix(collapsedLineLimit)) : parsed.lines
        let minRowWidth = max(blockViewportWidth, parsed.minContentWidth)
        let baseTextColor = Color(nsColor: theme.editorText)
        let lineNumColor = Color(nsColor: theme.commentColor).opacity(0.75)
        let diffLang = agentDiffLanguage(title: parsed.title)
        
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
                                
                                Text(diffHighlightedText(line.text, language: diffLang, theme: theme))
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
                .textSelection(.enabled)
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
                isDark: theme.isDark,
                themeName: theme.rawValue
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

