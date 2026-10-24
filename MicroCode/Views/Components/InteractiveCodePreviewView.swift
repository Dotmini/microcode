//
//  InteractiveCodePreviewView.swift
//  MicroCode
//
//  High-performance code viewer and diff inspector for the Universal Preview Dock.
//  Provides AGY-style breadcrumb navigation, syntax-highlighted code view, line numbers,
//  scroll-to-line (#L10-L20) highlighting, git diff comparison, and unified diff rendering.
//

import SwiftUI
import AppKit

// MARK: - Interactive Code Preview View

struct InteractiveCodePreviewView: View {
    let url: URL
    var highlightRange: ClosedRange<Int>? = nil
    @EnvironmentObject var appState: AppState
    
    @State private var codeContent: String = ""
    @State private var highlightedLines: [AttributedString] = []
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var isCopied: Bool = false
    @State private var showLineNumbers: Bool = true
    @State private var showGitDiff: Bool = false
    @State private var gitDiffContent: (old: String, new: String)? = nil
    @State private var hasGitDiff: Bool = false
    @State private var activeHighlightRange: ClosedRange<Int>? = nil
    
    private var fileExtension: String {
        url.pathExtension.lowercased()
    }
    
    private var detectedLanguage: String {
        switch fileExtension {
        case "swift": return "swift"
        case "rs": return "rust"
        case "py", "pyi": return "python"
        case "js", "jsx", "mjs", "cjs": return "javascript"
        case "ts", "tsx": return "typescript"
        case "svelte": return "svelte"
        case "vue": return "vue"
        case "astro": return "astro"
        case "kt", "kts": return "kotlin"
        case "java": return "java"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp", "mm": return "cpp"
        case "m": return "objective-c"
        case "go": return "go"
        case "dart": return "dart"
        case "json", "jsonc", "jsonl": return "json"
        case "html", "htm": return "html"
        case "css", "scss", "sass", "less": return "css"
        case "yaml", "yml": return "yaml"
        case "xml", "plist", "svg": return "xml"
        case "sh", "bash", "zsh", "fish": return "bash"
        case "sql", "prisma": return "sql"
        case "toml": return "toml"
        case "md", "markdown", "mdx": return "markdown"
        case "rb": return "ruby"
        case "php": return "php"
        case "cs": return "csharp"
        case "ar": return "ardium"
        default: return "text"
        }
    }

    /// Breadcrumb segments relative to workspace root (matching AGY breadcrumb bar)
    private var breadcrumbSegments: [String] {
        let fullPath = url.standardizedFileURL.path
        if let wsPath = (AgentService.shared.currentWorkspace ?? appState.workspaceFolder?.path),
           !wsPath.isEmpty {
            let normWS = URL(fileURLWithPath: wsPath).standardizedFileURL.path
            let wsName = URL(fileURLWithPath: normWS).lastPathComponent
            if fullPath.hasPrefix(normWS + "/") {
                let rel = String(fullPath.dropFirst(normWS.count + 1))
                let parts = rel.split(separator: "/").map(String.init)
                return [wsName] + parts.dropLast()
            }
        }
        let comps = url.standardizedFileURL.pathComponents.filter { $0 != "/" }
        if comps.count > 1 {
            return Array(comps.dropLast().suffix(3))
        }
        return []
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // AGY-Style Breadcrumb & Action Bar
            headerBar
            
            Divider()
            
            // Content
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading file preview…")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                    Text("Cannot Preview File")
                        .font(.system(size: 13, weight: .semibold))
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if showGitDiff, let diff = gitDiffContent {
                // Inline Git Diff View
                InteractiveDiffPreviewView(
                    title: url.lastPathComponent,
                    oldContent: diff.old,
                    newContent: diff.new
                )
            } else {
                // Syntax-Highlighted Code View with Gutter & ScrollViewReader
                codeViewer
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onAppear {
            activeHighlightRange = highlightRange
            loadFileContent()
            checkGitDiff()
        }
        .onChange(of: url) { _ in
            activeHighlightRange = highlightRange
            loadFileContent()
            checkGitDiff()
        }
        .onChange(of: highlightRange) { newRange in
            activeHighlightRange = newRange
        }
    }
    
    // MARK: - AGY-Style Breadcrumb Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 6) {
            // Breadcrumb path + file icon & name
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(breadcrumbSegments.enumerated()), id: \.offset) { _, seg in
                        Text(seg)
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary.opacity(0.85))
                            .lineLimit(1)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8.5, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    
                    HStack(spacing: 5) {
                        ProgrammingLanguageIconView(fileName: url.lastPathComponent, size: 13)
                        Text(url.lastPathComponent)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }

                    if let range = activeHighlightRange {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                activeHighlightRange = nil
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Text(range.lowerBound == range.upperBound ? "#L\(range.lowerBound)" : "#L\(range.lowerBound)-\(range.upperBound)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                Image(systemName: "xmark")
                                    .font(.system(size: 7.5, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.14))
                            .foregroundColor(.accentColor)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .help("Clear line highlight")
                    }
                }
            }
            
            Spacer(minLength: 6)
            
            // Toggle Git Diff (if modified)
            if hasGitDiff {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showGitDiff.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.swap")
                            .font(.system(size: 9))
                        Text(showGitDiff ? "Code" : "Diff")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(showGitDiff ? Color.orange.opacity(0.15) : Color.primary.opacity(0.06))
                    .foregroundColor(showGitDiff ? .orange : .secondary)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Toggle Git Diff with HEAD")
            }
            
            // Copy Code Button
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(codeContent, forType: .string)
                isCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isCopied = false
                }
            } label: {
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(isCopied ? .green : .secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy file content")
            
            // Open in Main Code Editor
            Button {
                Task { @MainActor in
                    await appState.loadFile(url: url)
                    appState.editorMode = .code
                    NotificationCenter.default.post(name: NSNotification.Name("MicroCodeEditorModeChanged"), object: EditorMode.code)
                }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in full Code Editor")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.55))
    }
    
    // MARK: - Syntax-Highlighted Code Viewer
    
    private var codeViewer: some View {
        let totalLines = max(1, highlightedLines.count)
        let gutterWidth: CGFloat = totalLines > 9999 ? 48 : (totalLines > 999 ? 40 : (totalLines > 99 ? 32 : 26))
        
        return ScrollViewReader { scrollProxy in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<highlightedLines.count, id: \.self) { index in
                        let lineNumber = index + 1
                        let isHighlighted = activeHighlightRange?.contains(lineNumber) ?? false
                        
                        HStack(alignment: .firstTextBaseline, spacing: 0) {
                            if showLineNumbers {
                                Rectangle()
                                    .fill(isHighlighted ? Color.accentColor : Color.clear)
                                    .frame(width: 2.5, height: 19)
                                
                                Text("\(lineNumber)")
                                    .font(.system(size: 11.5, design: .monospaced))
                                    .foregroundColor(isHighlighted ? .accentColor : .secondary.opacity(0.45))
                                    .frame(width: gutterWidth, alignment: .trailing)
                                    .padding(.trailing, 10)
                                    .padding(.leading, 4)
                            }
                            
                            Text(highlightedLines[index])
                                .font(.system(size: 12, design: .monospaced))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.leading, 6)
                                .padding(.trailing, 24)
                            
                            Spacer(minLength: 0)
                        }
                        .frame(height: 19, alignment: .leading)
                        .background(isHighlighted ? Color.accentColor.opacity(0.11) : Color.clear)
                        .id(lineNumber)
                    }
                }
                .padding(.vertical, 8)
                .textSelection(.enabled)
            }
            .onAppear {
                scrollToHighlightedLine(using: scrollProxy)
            }
            .onChange(of: activeHighlightRange) { _ in
                scrollToHighlightedLine(using: scrollProxy)
            }
            .onChange(of: highlightedLines.count) { _ in
                scrollToHighlightedLine(using: scrollProxy)
            }
        }
    }

    private func scrollToHighlightedLine(using proxy: ScrollViewProxy) {
        guard let targetLine = activeHighlightRange?.lowerBound,
              targetLine > 0,
              targetLine <= highlightedLines.count else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo(max(1, targetLine - 3), anchor: .top)
            }
        }
    }
    
    // MARK: - Helpers & Fast Syntax Highlighter
    
    private func loadFileContent() {
        isLoading = true
        errorMessage = nil
        let targetURL = url
        let lang = detectedLanguage
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let attr = try? FileManager.default.attributesOfItem(atPath: targetURL.path)
                let fileSize = (attr?[.size] as? NSNumber)?.int64Value ?? 0
                let isGiant = fileSize > 10 * 1024 * 1024 // > 10MB
                
                let data: Data
                if isGiant {
                    let handle = try FileHandle(forReadingFrom: targetURL)
                    defer { try? handle.close() }
                    data = handle.readData(ofLength: 1024 * 1024)
                } else {
                    data = try Data(contentsOf: targetURL)
                }
                
                var string = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? String(decoding: data, as: UTF8.self)
                
                if isGiant {
                    let formatted = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
                    string = "⚠️ [LARGE FILE WARNING: File size is \(formatted). Previewing the first 1 MB in read-only mode.]\n\n" + string
                }
                
                let rawLines = string.components(separatedBy: "\n")
                let styled = Self.highlightLines(rawLines, language: lang)
                
                DispatchQueue.main.async {
                    self.codeContent = string
                    self.highlightedLines = styled
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private static let keywordsSet: Set<String> = [
        "import", "from", "export", "default", "package", "module", "use", "mod", "crate",
        "struct", "class", "enum", "protocol", "interface", "trait", "impl", "type", "typealias", "extension",
        "func", "fn", "def", "function", "sub", "proc", "init", "deinit", "subscript",
        "let", "var", "const", "mut", "static", "final", "lazy", "weak", "unowned",
        "public", "private", "internal", "fileprivate", "open", "protected", "pub",
        "if", "else", "elif", "guard", "switch", "case", "match", "for", "in", "while", "repeat", "loop", "do",
        "return", "yield", "break", "continue", "fallthrough", "defer",
        "try", "catch", "throw", "throws", "rethrows", "async", "await", "actor", "nonisolated", "some", "any",
        "where", "as", "is", "in", "inout", "Self", "self", "super", "true", "false", "nil", "null", "None", "True", "False",
        "and", "or", "not", "with", "lambda", "pass", "del", "global", "nonlocal", " script", "style", "template"
    ]

    private static func highlightLines(_ lines: [String], language: String) -> [AttributedString] {
        let keywordColor = Color(red: 0.72, green: 0.20, blue: 0.66)     // Xcode/AGY Magenta-Purple
        let typeColor = Color(red: 0.16, green: 0.52, blue: 0.68)        // Teal-Blue for Types & Attributes
        let stringColor = Color(red: 0.78, green: 0.22, blue: 0.18)      // Warm Red-Orange for Strings
        let commentColor = Color.secondary.opacity(0.68)                 // Muted Gray-Green for Comments
        let numberColor = Color(red: 0.15, green: 0.44, blue: 0.82)      // Royal Blue for Numbers
        let baseColor = Color.primary.opacity(0.90)

        var result: [AttributedString] = []
        result.reserveCapacity(lines.count)

        let highlightCap = 3000 // Highlight up to 3000 lines for instant zero-lag rendering
        for (idx, line) in lines.enumerated() {
            if line.isEmpty {
                result.append(AttributedString(" "))
                continue
            }
            if idx >= highlightCap {
                var plain = AttributedString(line)
                plain.foregroundColor = baseColor
                result.append(plain)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || (trimmed.hasPrefix("#") && !trimmed.hasPrefix("#include") && !trimmed.hasPrefix("#import") && !trimmed.hasPrefix("#if") && !trimmed.hasPrefix("#endif") && !trimmed.hasPrefix("#pragma")) || trimmed.hasPrefix("<!--") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") {
                var commentAttr = AttributedString(line)
                commentAttr.foregroundColor = commentColor
                result.append(commentAttr)
                continue
            }

            // Check if there is a trailing `//` comment outside quotes
            var codePart = line
            var trailingComment: String? = nil
            if let commentRange = findTrailingLineComment(in: line) {
                codePart = String(line[..<commentRange.lowerBound])
                trailingComment = String(line[commentRange.lowerBound...])
            }

            var lineAttr = highlightCodeSegment(
                codePart,
                baseColor: baseColor,
                keywordColor: keywordColor,
                typeColor: typeColor,
                stringColor: stringColor,
                numberColor: numberColor
            )
            if let comment = trailingComment {
                var cAttr = AttributedString(comment)
                cAttr.foregroundColor = commentColor
                lineAttr.append(cAttr)
            }
            result.append(lineAttr)
        }
        return result
    }

    private static func findTrailingLineComment(in line: String) -> Range<String.Index>? {
        var inDoubleQuote = false
        var inSingleQuote = false
        var prevChar: Character = "\0"
        var idx = line.startIndex
        while idx < line.endIndex {
            let ch = line[idx]
            if ch == "\"" && !inSingleQuote && prevChar != "\\" {
                inDoubleQuote.toggle()
            } else if ch == "'" && !inDoubleQuote && prevChar != "\\" {
                inSingleQuote.toggle()
            } else if !inDoubleQuote && !inSingleQuote && ch == "/" {
                let nextIdx = line.index(after: idx)
                if nextIdx < line.endIndex && line[nextIdx] == "/" {
                    // Ignore `://` in URLs
                    if prevChar != ":" {
                        return idx..<line.endIndex
                    }
                }
            }
            prevChar = ch
            idx = line.index(after: idx)
        }
        return nil
    }

    private static func highlightCodeSegment(
        _ text: String,
        baseColor: Color,
        keywordColor: Color,
        typeColor: Color,
        stringColor: Color,
        numberColor: Color
    ) -> AttributedString {
        var output = AttributedString()
        var i = text.startIndex

        while i < text.endIndex {
            let ch = text[i]

            // 1. String literal ("..." or '...')
            if ch == "\"" || ch == "'" {
                let quote = ch
                var end = text.index(after: i)
                var escaped = false
                while end < text.endIndex {
                    let c = text[end]
                    if escaped {
                        escaped = false
                    } else if c == "\\" {
                        escaped = true
                    } else if c == quote {
                        end = text.index(after: end)
                        break
                    }
                    end = text.index(after: end)
                }
                var seg = AttributedString(String(text[i..<end]))
                seg.foregroundColor = stringColor
                output.append(seg)
                i = end
                continue
            }

            // 2. Decorator / Attribute (@MainActor, @Published, etc.)
            if ch == "@" {
                var end = text.index(after: i)
                while end < text.endIndex && (text[end].isLetter || text[end].isNumber || text[end] == "_") {
                    end = text.index(after: end)
                }
                if end > text.index(after: i) {
                    var seg = AttributedString(String(text[i..<end]))
                    seg.foregroundColor = keywordColor
                    output.append(seg)
                    i = end
                    continue
                }
            }

            // 3. Identifier / Keyword / Type
            if ch.isLetter || ch == "_" {
                var end = text.index(after: i)
                while end < text.endIndex && (text[end].isLetter || text[end].isNumber || text[end] == "_") {
                    end = text.index(after: end)
                }
                let word = String(text[i..<end])
                var seg = AttributedString(word)
                if keywordsSet.contains(word) {
                    seg.foregroundColor = keywordColor
                } else if let first = word.first, first.isUppercase {
                    seg.foregroundColor = typeColor
                } else {
                    seg.foregroundColor = baseColor
                }
                output.append(seg)
                i = end
                continue
            }

            // 4. Numbers
            if ch.isNumber {
                var end = text.index(after: i)
                while end < text.endIndex && (text[end].isNumber || text[end] == "." || text[end] == "_" || text[end] == "x" || text[end] == "X") {
                    end = text.index(after: end)
                }
                var seg = AttributedString(String(text[i..<end]))
                seg.foregroundColor = numberColor
                output.append(seg)
                i = end
                continue
            }

            // 5. Punctuation / Whitespace
            var end = text.index(after: i)
            while end < text.endIndex {
                let c = text[end]
                if c == "\"" || c == "'" || c == "@" || c.isLetter || c == "_" || c.isNumber {
                    break
                }
                end = text.index(after: end)
            }
            var seg = AttributedString(String(text[i..<end]))
            seg.foregroundColor = baseColor
            output.append(seg)
            i = end
        }

        return output
    }
    
    private func checkGitDiff() {
        guard let workspace = appState.workspaceFolder else { return }
        let relPath = url.path.replacingOccurrences(of: workspace.path + "/", with: "")
        
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["status", "--porcelain", "--", relPath]
            process.currentDirectoryURL = workspace
            process.standardOutput = pipe
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let status = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            if !status.isEmpty {
                let showProcess = Process()
                let showPipe = Pipe()
                showProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                showProcess.arguments = ["show", "HEAD:\(relPath)"]
                showProcess.currentDirectoryURL = workspace
                showProcess.standardOutput = showPipe
                showProcess.standardError = Pipe()
                try? showProcess.run()
                showProcess.waitUntilExit()
                let oldData = showPipe.fileHandleForReading.readDataToEndOfFile()
                let oldText = String(data: oldData, encoding: .utf8) ?? ""
                
                let attr = try? FileManager.default.attributesOfItem(atPath: self.url.path)
                let fileSize = (attr?[.size] as? NSNumber)?.int64Value ?? 0
                if fileSize > 10 * 1024 * 1024 {
                    DispatchQueue.main.async {
                        self.hasGitDiff = false
                        self.gitDiffContent = nil
                    }
                    return
                }
                
                let currentText = (try? String(contentsOf: self.url, encoding: .utf8)) ?? ""
                
                DispatchQueue.main.async {
                    self.hasGitDiff = true
                    self.gitDiffContent = (old: oldText, new: currentText)
                }
            } else {
                DispatchQueue.main.async {
                    self.hasGitDiff = false
                    self.gitDiffContent = nil
                }
            }
        }
    }
}

// MARK: - Interactive Diff Preview View

struct InteractiveDiffPreviewView: View {
    let title: String
    let oldContent: String
    let newContent: String
    
    @State private var isCopied: Bool = false
    @State private var cardWidth: CGFloat = 0
    
    private var diffLines: [UnifiedDiffLine] {
        DiffCacheManager.getOrComputeDiff(
            id: "preview-diff:\(title)",
            old: oldContent,
            new: newContent
        )
    }
    
    private var additionsCount: Int {
        diffLines.filter { $0.type == .addition }.count
    }
    
    private var deletionsCount: Int {
        diffLines.filter { $0.type == .deletion }.count
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Diff Stats Header
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    ProgrammingLanguageIconView(fileName: title, size: 14)
                    Text("Diff: \(title)")
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }
                
                // Badges: +N, -M
                HStack(spacing: 4) {
                    if additionsCount > 0 {
                        Text("+\(additionsCount)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(3)
                    }
                    if deletionsCount > 0 {
                        Text("-\(deletionsCount)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(3)
                    }
                }
                
                Spacer()
                
                // Copy Diff Button
                Button {
                    let fullDiff = diffLines.map { "\($0.prefix)\($0.text)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullDiff, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isCopied = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9))
                        Text(isCopied ? "Copied" : "Copy Diff")
                            .font(.system(size: 10))
                    }
                    .foregroundColor(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy full unified diff to clipboard")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
            
            Divider()
            
            let maxTextWidth = diffLines.reduce(CGFloat(0)) { currentMax, line in
                let textWidth = (line.text as NSString).size(
                    withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)]
                ).width
                return max(currentMax, textWidth)
            }
            let gutterWidth: CGFloat = 95.5
            let minContentWidth = gutterWidth + maxTextWidth + 32
            let effectiveWidth = max(cardWidth, minContentWidth)
            
            // Diff Content Lines
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(diffLines) { (diffLine: UnifiedDiffLine) in
                        HStack(spacing: 0) {
                            // Status accent strip (2.5pt)
                            Rectangle()
                                .fill(diffLine.accentColor)
                                .frame(width: 2.5)
                            
                            // Old line number gutter
                            Text(diffLine.oldNum)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.4))
                                .frame(width: 32, alignment: .trailing)
                                .padding(.trailing, 4)
                            
                            // New line number gutter
                            Text(diffLine.newNum)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.4))
                                .frame(width: 32, alignment: .trailing)
                                .padding(.trailing, 6)
                            
                            // Gutter divider line
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(width: 1)
                            
                            // Prefix (+/-)
                            Text(diffLine.prefix)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(diffLine.prefixColor)
                                .frame(width: 18, alignment: .center)
                            
                            // Code text
                            Text(diffLine.text)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(diffLine.textColor)
                                .lineLimit(1)
                            
                            Spacer(minLength: 0)
                        }
                        .frame(height: 18)
                        .frame(width: effectiveWidth > 0 ? effectiveWidth : nil, alignment: .leading)
                        .background(diffLine.bgColor)
                    }
                }
                .frame(width: effectiveWidth > 0 ? effectiveWidth : nil, alignment: .leading)
                .padding(.vertical, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.85))
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear { cardWidth = geo.size.width }
                    .onChange(of: geo.size.width) { newW in cardWidth = newW }
            }
        )
    }
}

// MARK: - Interactive Diff File Preview View (for .diff / .patch files)

struct InteractiveDiffFilePreviewView: View {
    let url: URL
    
    @State private var rawDiff: String = ""
    @State private var isLoading: Bool = true
    @State private var isCopied: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.and.right.square")
                    .font(.system(size: 10))
                    .foregroundColor(.cyan)
                
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                
                Text("PATCH")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Color.cyan.opacity(0.15))
                    .foregroundColor(.cyan)
                    .cornerRadius(3)
                
                Spacer()
                
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(rawDiff, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { isCopied = false }
                } label: {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("Copy patch content")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
            
            Divider()
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 0) {
                        let lines = rawDiff.components(separatedBy: "\n")
                        ForEach(0..<lines.count, id: \.self) { idx in
                            let line = lines[idx]
                            let isAdd = line.hasPrefix("+") && !line.hasPrefix("+++")
                            let isDel = line.hasPrefix("-") && !line.hasPrefix("---")
                            let isHunk = line.hasPrefix("@@")
                            
                            HStack(spacing: 0) {
                                Rectangle()
                                    .fill(isAdd ? Color.green : (isDel ? Color.red : (isHunk ? Color.cyan : Color.clear)))
                                    .frame(width: 2.5)
                                
                                Text("\(idx + 1)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary.opacity(0.4))
                                    .frame(width: 32, alignment: .trailing)
                                    .padding(.trailing, 6)
                                
                                Rectangle()
                                    .fill(Color.primary.opacity(0.08))
                                    .frame(width: 1)
                                
                                Text(line.isEmpty ? " " : line)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(isAdd ? .green : (isDel ? .red : (isHunk ? .cyan : .primary.opacity(0.85))))
                                    .padding(.leading, 6)
                                
                                Spacer(minLength: 16)
                            }
                            .frame(height: 18)
                            .background(isAdd ? Color.green.opacity(0.1) : (isDel ? Color.red.opacity(0.08) : (isHunk ? Color.cyan.opacity(0.06) : Color.clear)))
                        }
                    }
                    .padding(.vertical, 4)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.85))
            }
        }
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async {
                let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
                DispatchQueue.main.async {
                    self.rawDiff = content
                    self.isLoading = false
                }
            }
        }
    }
}
