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
    @State private var highlightedNSCode: NSAttributedString = NSAttributedString()
    @State private var lineUTF16Offsets: [Int] = [0]
    @State private var codeRevision: UInt64 = 0
    @State private var cachedMarkdownFrontmatter: [(key: String, value: String)] = []
    @State private var cachedMarkdownBody: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var isCopied: Bool = false
    @State private var showLineNumbers: Bool = true
    @State private var showGitDiff: Bool = false
    @State private var gitDiffContent: (old: String, new: String)? = nil
    @State private var hasGitDiff: Bool = false
    @State private var activeHighlightRange: ClosedRange<Int>? = nil

    // Playground-Style Live Render state (.swift SwiftUI, .html/.svg Web, .md Markdown)
    @State private var showLiveRender: Bool = false
    @State private var liveSwiftUIDylibPath: String? = nil
    @State private var liveSwiftUIDylibTrigger: UUID = UUID()
    @State private var isCompilingSwiftUI: Bool = false
    @State private var swiftUICompileError: String? = nil
    @State private var lastCompileMs: Int = 0
    @State private var liveWebRefreshTrigger: Bool = false
    @State private var liveWebIsLoading: Bool = false
    @State private var liveWebTitle: String = ""
    @State private var liveWebCanGoBack: Bool = false
    @State private var liveWebCanGoForward: Bool = false
    @State private var liveWebGoBack: Bool = false
    @State private var liveWebGoForward: Bool = false
    
    private var fileExtension: String {
        url.pathExtension.lowercased()
    }

    private var isMarkdownDocument: Bool {
        switch fileExtension {
        case "md", "markdown", "mdx":
            return true
        default:
            return false
        }
    }

    private var supportsLiveRender: Bool {
        switch fileExtension {
        case "swift", "html", "htm", "svg", "md", "markdown", "mdx":
            return true
        default:
            return false
        }
    }
    
    private static func detectLanguage(for fileURL: URL) -> String {
        switch fileURL.pathExtension.lowercased() {
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
        case "html", "htm", "razor", "cshtml": return "html"
        case "css", "scss", "sass", "less": return "css"
        case "yaml", "yml": return "yaml"
        case "xml", "plist", "svg", "axaml", "xaml", "csproj", "fsproj", "vbproj", "props", "targets", "resx", "config": return "xml"
        case "sh", "bash", "zsh", "fish": return "bash"
        case "sql", "prisma": return "sql"
        case "toml": return "toml"
        case "md", "markdown", "mdx": return "markdown"
        case "rb": return "ruby"
        case "php": return "php"
        case "cs": return "csharp"
        case "fs": return "fsharp"
        case "ar": return "ardium"
        default: return "text"
        }
    }

    private var detectedLanguage: String {
        Self.detectLanguage(for: url)
    }

    /// Only highlight a range when it points to a specific sub-section of the file,
    /// avoiding painting 100% of every line blue when `#L1-N` covers the entire file.
    private var effectiveHighlightRange: ClosedRange<Int>? {
        guard let range = activeHighlightRange else { return nil }
        let total = lineUTF16Offsets.count
        if total > 0 && range.lowerBound <= 1 && range.upperBound >= total {
            return nil
        }
        return range
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
        let theme = appState.appTheme
        let editorCanvas = theme.isGlass ? Color.clear : Color(nsColor: theme.editorBackground)
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
                // Inline Git Diff View (header bar above already provides Close button)
                InteractiveDiffPreviewView(
                    title: url.lastPathComponent,
                    oldContent: diff.old,
                    newContent: diff.new,
                    showsCloseButton: false
                )
            } else if showLiveRender && supportsLiveRender {
                // Playground-Style Live Render View (SwiftUI / HTML / SVG / Markdown)
                liveRenderView
            } else {
                // Syntax-Highlighted Code View with Gutter & ScrollViewReader
                codeViewer
            }
        }
        .background(editorCanvas)
        .onAppear {
            activeHighlightRange = highlightRange
            if isMarkdownDocument && highlightRange == nil {
                showLiveRender = true
            }
            loadFileContent(for: url)
            checkGitDiff(for: url)
        }
        .onChange(of: url) { newURL in
            activeHighlightRange = highlightRange
            showGitDiff = false
            gitDiffContent = nil
            hasGitDiff = false
            liveSwiftUIDylibPath = nil
            swiftUICompileError = nil
            let ext = newURL.pathExtension.lowercased()
            let isMD = (ext == "md" || ext == "markdown" || ext == "mdx")
            showLiveRender = isMD && (highlightRange == nil)
            loadFileContent(for: newURL)
            checkGitDiff(for: newURL)
        }
        .onChange(of: highlightRange) { newRange in
            activeHighlightRange = newRange
            if newRange != nil && isMarkdownDocument {
                showLiveRender = false
            }
        }
        .onChange(of: appState.appTheme) { newTheme in
            rehighlightCurrentCode(theme: newTheme)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeFileSaved"))) { note in
            guard PreviewHotReloadEngine.shared.isAutoHotReloadEnabled else { return }
            if let savedPath = note.userInfo?["path"] as? String,
               URL(fileURLWithPath: savedPath).standardizedFileURL.path == url.standardizedFileURL.path {
                loadFileContent(silent: true)
                checkGitDiff()
                if showLiveRender {
                    if fileExtension == "swift" {
                        compileSwiftUIIfNeeded(overrideCode: note.userInfo?["content"] as? String)
                    } else {
                        liveWebRefreshTrigger = true
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeWorkspaceFileDidChange"))) { note in
            guard PreviewHotReloadEngine.shared.isAutoHotReloadEnabled else { return }
            if let changedPath = note.userInfo?["path"] as? String,
               URL(fileURLWithPath: changedPath).standardizedFileURL.path == url.standardizedFileURL.path {
                loadFileContent(silent: true)
                checkGitDiff()
                if showLiveRender && fileExtension != "swift" {
                    liveWebRefreshTrigger = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("MicroCodeLiveBufferUpdated"))) { note in
            guard PreviewHotReloadEngine.shared.isAutoHotReloadEnabled,
                  PreviewHotReloadEngine.shared.isLiveTypingEnabled else { return }
            if let editedPath = note.userInfo?["path"] as? String,
               let content = note.userInfo?["content"] as? String,
               URL(fileURLWithPath: editedPath).standardizedFileURL.path == url.standardizedFileURL.path {
                applyLiveBufferContent(content)
                if showLiveRender && fileExtension == "swift" {
                    compileSwiftUIIfNeeded(overrideCode: content)
                }
            }
        }
    }
    
    // MARK: - AGY-Style Breadcrumb Header Bar
    
    private var headerBar: some View {
        let headerBg = appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.panelBackground)
        return HStack(spacing: 6) {
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

                    if let range = effectiveHighlightRange {
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

            // Playground-Style Live Render Toggle (.swift SwiftUI, .html/.svg Web, .md Markdown)
            if isMarkdownDocument {
                HStack(spacing: 1) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            showLiveRender = true
                            showGitDiff = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "doc.richtext")
                                .font(.system(size: 9, weight: .semibold))
                            Text("Preview")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(showLiveRender ? Color.accentColor.opacity(0.18) : Color.clear)
                        .foregroundColor(showLiveRender ? .accentColor : .secondary)
                        .cornerRadius(3.5)
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.easeInOut(duration: 0.14)) {
                            showLiveRender = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text("Raw")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(!showLiveRender ? Color.primary.opacity(0.10) : Color.clear)
                        .foregroundColor(!showLiveRender ? .primary : .secondary)
                        .cornerRadius(3.5)
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(5)
                .help("Switch between Rendered Markdown Preview and Raw Markdown Source")
            } else if supportsLiveRender {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        showLiveRender.toggle()
                        if showLiveRender {
                            showGitDiff = false
                            if fileExtension == "swift" {
                                compileSwiftUIIfNeeded()
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: showLiveRender ? "bolt.fill" : "play.tv")
                            .font(.system(size: 9, weight: .bold))
                        Text(showLiveRender ? (lastCompileMs > 0 ? "Live · \(lastCompileMs)ms" : "Live") : "Live Preview")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(showLiveRender ? Color.green.opacity(0.16) : Color.primary.opacity(0.06))
                    .foregroundColor(showLiveRender ? .green : .secondary)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Toggle Playground-Style Live Hot Reload Preview")
            }
            
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

            Divider()
                .frame(height: 14)
                .padding(.horizontal, 1)

            PreviewCloseTabButton()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(headerBg)
    }
    
    // MARK: - Syntax-Highlighted Code Viewer (120Hz Native AppKit TextKit2/TextKit1 ScrollView)
    
    private var codeViewer: some View {
        let theme = appState.appTheme
        return PreviewReadOnlyCodeNSView(
            attributedCode: highlightedNSCode,
            rawCode: codeContent,
            lineUTF16Offsets: lineUTF16Offsets,
            revision: codeRevision,
            showLineNumbers: showLineNumbers,
            highlightRange: effectiveHighlightRange,
            editorBackground: theme.editorBackground,
            gutterTextColor: theme.commentColor.withAlphaComponent(0.78),
            selectionHighlightColor: theme.selectionColor.withAlphaComponent(theme.isDark ? 0.52 : 0.40),
            isGlass: theme.isGlass
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Playground-Style Live Render View (SwiftUI / HTML / SVG / Markdown)

    @ViewBuilder
    private var liveRenderView: some View {
        switch fileExtension {
        case "swift":
            ZStack {
                if let dylibPath = liveSwiftUIDylibPath {
                    DynamicSwiftUIView(dylibPath: dylibPath, reloadTrigger: liveSwiftUIDylibTrigger)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isCompilingSwiftUI {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Compiling SwiftUI Live Preview…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = swiftUICompileError {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("SwiftUI Live Preview Compilation Error")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Text(err)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(14)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "swift")
                            .font(.system(size: 32))
                            .foregroundColor(.orange)
                        Text("Ready for Live SwiftUI Preview")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { compileSwiftUIIfNeeded() }
                }

                if isCompilingSwiftUI && liveSwiftUIDylibPath != nil {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 5) {
                                ProgressView().controlSize(.mini)
                                Text("Hot Reloading…")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                            .padding(10)
                        }
                        Spacer()
                    }
                }
            }

        case "html", "htm", "svg":
            WebBrowserView(
                url: url,
                htmlContent: nil,
                title: $liveWebTitle,
                isLoading: $liveWebIsLoading,
                canGoBack: $liveWebCanGoBack,
                canGoForward: $liveWebCanGoForward,
                refreshTrigger: $liveWebRefreshTrigger,
                goBackTrigger: $liveWebGoBack,
                goForwardTrigger: $liveWebGoForward
            )

        case "md", "markdown", "mdx":
            let mdBody = cachedMarkdownBody.isEmpty && !codeContent.isEmpty ? codeContent : cachedMarkdownBody
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if !cachedMarkdownFrontmatter.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(cachedMarkdownFrontmatter, id: \.key) { pair in
                                HStack(alignment: .top, spacing: 8) {
                                    Text(pair.key)
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .frame(minWidth: 76, alignment: .leading)
                                    Text(pair.value)
                                        .font(.system(size: 11.5))
                                        .foregroundColor(.primary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .cornerRadius(8)
                    }

                    RenderedMarkdownDocumentView(markdown: mdBody)
                        .equatable()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(appState.appTheme.isGlass ? Color.clear : Color(nsColor: appState.appTheme.editorBackground))

        default:
            codeViewer
        }
    }

    private static let relativeMarkdownImageRegex = try? NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\((?!https?://|file://|data:|/)([^)\s]+)\)"#,
        options: []
    )

    private static func extractYAMLFrontmatterAndResolveMedia(
        markdown: String,
        baseDir: URL
    ) -> (frontmatter: [(key: String, value: String)], body: String) {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var body = normalized
        var frontmatter: [(key: String, value: String)] = []

        if normalized.hasPrefix("---\n") {
            let lines = normalized.components(separatedBy: "\n")
            if let closingIdx = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }),
               closingIdx <= 30 {
                let fmLines = Array(lines[1..<closingIdx])
                var parsedPairs: [(key: String, value: String)] = []
                var validYAML = !fmLines.isEmpty
                for rawLine in fmLines {
                    let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                    guard let colon = trimmed.firstIndex(of: ":") else {
                        validYAML = false
                        break
                    }
                    let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                    let val = String(trimmed[trimmed.index(after: colon)...])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    if key.isEmpty || key.contains(" ") {
                        validYAML = false
                        break
                    }
                    parsedPairs.append((key: key, value: val))
                }
                if validYAML && !parsedPairs.isEmpty {
                    frontmatter = parsedPairs
                    body = lines[(closingIdx + 1)...].joined(separator: "\n")
                }
            }
        }

        if let regex = relativeMarkdownImageRegex, body.contains("![") {
            let ns = body as NSString
            let matches = regex.matches(in: body, options: [], range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() where match.numberOfRanges >= 3 {
                let alt = ns.substring(with: match.range(at: 1))
                let relPath = ns.substring(with: match.range(at: 2))
                let cleanRel = relPath.hasPrefix("./") ? String(relPath.dropFirst(2)) : relPath
                let resolvedURL = baseDir.appendingPathComponent(cleanRel).standardizedFileURL
                if FileManager.default.fileExists(atPath: resolvedURL.path) {
                    let replacement = "![\(alt)](file://\(resolvedURL.path))"
                    body = (body as NSString).replacingCharacters(in: match.range, with: replacement)
                }
            }
        }

        return (frontmatter, body)
    }

    private struct ThemeSyntaxPalette {
        let baseColor: Color
        let keywordColor: Color
        let typeColor: Color
        let functionColor: Color
        let stringColor: Color
        let commentColor: Color
        let numberColor: Color

        init(theme: AppTheme) {
            self.baseColor = Color(nsColor: theme.editorText)
            self.keywordColor = Color(nsColor: theme.keywordColor)
            self.typeColor = Color(nsColor: theme.typeColor)
            self.functionColor = Color(nsColor: theme.functionColor)
            self.stringColor = Color(nsColor: theme.stringColor)
            self.commentColor = Color(nsColor: theme.commentColor)
            self.numberColor = Color(nsColor: theme.numberColor)
        }
    }

    private static func normalizeDisplayLines(_ rawText: String) -> (lines: [String], maxChars: Int) {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var rawLines = normalized.components(separatedBy: "\n")
        // Drop single trailing empty line produced by standard POSIX trailing newline so line count matches editors
        if rawLines.count > 1 && rawLines.last == "" {
            rawLines.removeLast()
        }
        var maxChars = 0
        var expanded: [String] = []
        expanded.reserveCapacity(rawLines.count)
        for line in rawLines {
            let tabExpanded = line.contains("\t") ? line.replacingOccurrences(of: "\t", with: "    ") : line
            if tabExpanded.count > maxChars {
                maxChars = min(tabExpanded.count, 400)
            }
            expanded.append(tabExpanded)
        }
        return (expanded, maxChars)
    }

    private static func buildHighlightedNSCode(
        _ rawText: String,
        language: String,
        isDark: Bool,
        baseTextColor: NSColor
    ) -> (attributed: NSAttributedString, lineOffsets: [Int]) {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let offsets = SyntaxHighlightingEngine.computeUTF16LineStartsFast(normalized)
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = 19
        para.maximumLineHeight = 19
        para.lineBreakMode = .byClipping

        if normalized.utf8.count <= 180_000 && language != "text" {
            let highlighted = SyntaxHighlightingEngine.highlight(
                normalized,
                language: language,
                fontSize: 12,
                isDark: isDark
            )
            let mutable = NSMutableAttributedString(attributedString: highlighted)
            let fullRange = NSRange(location: 0, length: mutable.length)
            if fullRange.length > 0 {
                mutable.addAttributes([
                    .font: font,
                    .paragraphStyle: para
                ], range: fullRange)
            }
            return (mutable, offsets)
        } else {
            let plain = NSAttributedString(
                string: normalized,
                attributes: [
                    .font: font,
                    .foregroundColor: baseTextColor,
                    .paragraphStyle: para
                ]
            )
            return (plain, offsets)
        }
    }

    private func rehighlightCurrentCode(theme: AppTheme) {
        let currentCode = codeContent
        guard !currentCode.isEmpty else { return }
        let lang = detectedLanguage
        let isDark = theme.isDark
        let baseColor = theme.editorText
        DispatchQueue.global(qos: .userInitiated).async {
            let built = Self.buildHighlightedNSCode(
                currentCode,
                language: lang,
                isDark: isDark,
                baseTextColor: baseColor
            )
            DispatchQueue.main.async {
                self.highlightedNSCode = built.attributed
                self.lineUTF16Offsets = built.lineOffsets
                self.codeRevision &+= 1
            }
        }
    }

    private func applyLiveBufferContent(_ newContent: String) {
        let lang = detectedLanguage
        let isDark = appState.appTheme.isDark
        let baseColor = appState.appTheme.editorText
        let isMD = isMarkdownDocument
        let baseDir = url.deletingLastPathComponent()
        self.codeContent = newContent
        DispatchQueue.global(qos: .userInteractive).async {
            let mdExtracted: (frontmatter: [(key: String, value: String)], body: String)? = isMD
                ? Self.extractYAMLFrontmatterAndResolveMedia(markdown: newContent, baseDir: baseDir)
                : nil
            if let md = mdExtracted {
                _ = MessageContentParser.parse(md.body)
            }
            let built = Self.buildHighlightedNSCode(
                newContent,
                language: lang,
                isDark: isDark,
                baseTextColor: baseColor
            )
            DispatchQueue.main.async {
                if let md = mdExtracted {
                    self.cachedMarkdownFrontmatter = md.frontmatter
                    self.cachedMarkdownBody = md.body
                }
                self.highlightedNSCode = built.attributed
                self.lineUTF16Offsets = built.lineOffsets
                self.codeRevision &+= 1
            }
        }
    }

    private func compileSwiftUIIfNeeded(overrideCode: String? = nil) {
        let source = overrideCode ?? codeContent
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isCompilingSwiftUI = true
        swiftUICompileError = nil
        let start = CFAbsoluteTimeGetCurrent()
        Task {
            do {
                let dylib = try await SwiftUILivePreviewCompiler.compileDylib(
                    code: source,
                    width: 420,
                    height: 760,
                    isDark: appState.appTheme.isDark
                )
                await MainActor.run {
                    self.liveSwiftUIDylibPath = dylib
                    self.liveSwiftUIDylibTrigger = UUID()
                    self.lastCompileMs = max(1, Int((CFAbsoluteTimeGetCurrent() - start) * 1000))
                    self.isCompilingSwiftUI = false
                }
            } catch {
                await MainActor.run {
                    self.swiftUICompileError = error.localizedDescription
                    self.isCompilingSwiftUI = false
                }
            }
        }
    }

    // MARK: - Helpers & Theme-Synchronized Fast Syntax Highlighter
    
    private func loadFileContent(for overrideURL: URL? = nil, silent: Bool = false) {
        if !silent {
            isLoading = true
        }
        errorMessage = nil
        let targetURL = overrideURL ?? url
        let lang = Self.detectLanguage(for: targetURL)
        let ext = targetURL.pathExtension.lowercased()
        let isMD = (ext == "md" || ext == "markdown" || ext == "mdx")
        let baseDir = targetURL.deletingLastPathComponent()
        let isDark = appState.appTheme.isDark
        let baseColor = appState.appTheme.editorText
        
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
                
                let mdExtracted: (frontmatter: [(key: String, value: String)], body: String)? = isMD
                    ? Self.extractYAMLFrontmatterAndResolveMedia(markdown: string, baseDir: baseDir)
                    : nil
                if let md = mdExtracted {
                    _ = MessageContentParser.parse(md.body)
                }
                let built = Self.buildHighlightedNSCode(
                    string,
                    language: lang,
                    isDark: isDark,
                    baseTextColor: baseColor
                )
                
                DispatchQueue.main.async {
                    self.codeContent = string
                    if let md = mdExtracted {
                        self.cachedMarkdownFrontmatter = md.frontmatter
                        self.cachedMarkdownBody = md.body
                    } else {
                        self.cachedMarkdownFrontmatter = []
                        self.cachedMarkdownBody = ""
                    }
                    self.highlightedNSCode = built.attributed
                    self.lineUTF16Offsets = built.lineOffsets
                    self.codeRevision &+= 1
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
        "import", "from", "export", "default", "package", "module", "use", "mod", "crate", "namespace", "using",
        "struct", "class", "enum", "protocol", "interface", "trait", "impl", "type", "typealias", "extension", "record",
        "func", "fn", "def", "function", "sub", "proc", "init", "deinit", "subscript",
        "let", "var", "const", "mut", "static", "final", "lazy", "weak", "unowned", "readonly", "sealed", "partial",
        "public", "private", "internal", "fileprivate", "open", "protected", "pub", "override", "virtual", "abstract",
        "if", "else", "elif", "guard", "switch", "case", "match", "for", "foreach", "in", "while", "repeat", "loop", "do",
        "return", "yield", "break", "continue", "fallthrough", "defer",
        "try", "catch", "finally", "throw", "throws", "rethrows", "async", "await", "actor", "nonisolated", "some", "any",
        "where", "as", "is", "inout", "out", "ref", "Self", "self", "this", "base", "super", "new",
        "true", "false", "nil", "null", "None", "True", "False", "undefined",
        "bool", "int", "string", "double", "float", "decimal", "void", "object", "byte", "char", "long", "short",
        "get", "set", "value", "nameof", "typeof", "sizeof",
        "and", "or", "not", "with", "lambda", "pass", "del", "global", "nonlocal", "script", "style", "template"
    ]

    private static let markupLanguages: Set<String> = [
        "xml", "html", "svelte", "vue", "astro", "javascript", "typescript", "markdown"
    ]

    private static func highlightLines(_ lines: [String], language: String, palette: ThemeSyntaxPalette) -> [AttributedString] {
        var result: [AttributedString] = []
        result.reserveCapacity(lines.count)
        let isMarkup = markupLanguages.contains(language)
        let isPureXMLOrHTML = (language == "xml" || language == "html")

        let highlightCap = 3000 // Highlight up to 3000 lines for instant zero-lag rendering
        for (idx, line) in lines.enumerated() {
            if line.isEmpty {
                result.append(AttributedString(" "))
                continue
            }
            if idx >= highlightCap {
                var plain = AttributedString(line)
                plain.foregroundColor = palette.baseColor
                result.append(plain)
                continue
            }

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("<!--") ||
               (!isPureXMLOrHTML && (trimmed.hasPrefix("//") || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") ||
                (trimmed.hasPrefix("#") && !trimmed.hasPrefix("#include") && !trimmed.hasPrefix("#import") && !trimmed.hasPrefix("#if") && !trimmed.hasPrefix("#endif") && !trimmed.hasPrefix("#pragma") && !trimmed.hasPrefix("#region") && !trimmed.hasPrefix("#endregion")))) {
                var commentAttr = AttributedString(line)
                commentAttr.foregroundColor = palette.commentColor
                result.append(commentAttr)
                continue
            }

            // Check if there is a trailing `//` comment outside quotes (for non-XML languages)
            var codePart = line
            var trailingComment: String? = nil
            if !isPureXMLOrHTML, let commentRange = findTrailingLineComment(in: line) {
                codePart = String(line[..<commentRange.lowerBound])
                trailingComment = String(line[commentRange.lowerBound...])
            }

            var lineAttr = highlightCodeSegment(
                codePart,
                isMarkup: isMarkup,
                palette: palette
            )
            if let comment = trailingComment {
                var cAttr = AttributedString(comment)
                cAttr.foregroundColor = palette.commentColor
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

    private static func isXMLNameChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "-" || c == "_" || c == ":" || c == "."
    }

    private static func highlightCodeSegment(
        _ text: String,
        isMarkup: Bool,
        palette: ThemeSyntaxPalette
    ) -> AttributedString {
        var output = AttributedString()
        var i = text.startIndex

        while i < text.endIndex {
            let ch = text[i]

            // 0. XML / HTML / XAML / .csproj / JSX Tag (`<Tag attr="val">`, `</Tag>`, `<?xml ...?>`)
            if isMarkup && ch == "<" {
                let next1 = text.index(after: i)
                if next1 < text.endIndex {
                    let c1 = text[next1]
                    var bracketEnd = next1
                    var isClosingTag = false
                    if c1 == "/" || c1 == "?" || c1 == "!" {
                        isClosingTag = (c1 == "/")
                        bracketEnd = text.index(after: next1)
                    }
                    if bracketEnd < text.endIndex && (text[bracketEnd].isLetter || text[bracketEnd] == "_") {
                        // Append `<`, `</`, or `<?`
                        var openBracket = AttributedString(String(text[i..<bracketEnd]))
                        openBracket.foregroundColor = palette.commentColor
                        output.append(openBracket)

                        // Tag name
                        var tagEnd = bracketEnd
                        while tagEnd < text.endIndex && isXMLNameChar(text[tagEnd]) {
                            tagEnd = text.index(after: tagEnd)
                        }
                        var tagSeg = AttributedString(String(text[bracketEnd..<tagEnd]))
                        tagSeg.foregroundColor = palette.keywordColor
                        output.append(tagSeg)
                        i = tagEnd

                        // Parse attributes until closing `>`, `/>`, or `?>`
                        while i < text.endIndex {
                            let tc = text[i]
                            if tc == ">" {
                                let afterClose = text.index(after: i)
                                var closeSeg = AttributedString(">")
                                closeSeg.foregroundColor = palette.commentColor
                                output.append(closeSeg)
                                i = afterClose
                                break
                            }
                            if (tc == "/" || tc == "?") {
                                let n = text.index(after: i)
                                if n < text.endIndex && text[n] == ">" {
                                    let afterClose = text.index(after: n)
                                    var closeSeg = AttributedString(String(text[i..<afterClose]))
                                    closeSeg.foregroundColor = palette.commentColor
                                    output.append(closeSeg)
                                    i = afterClose
                                    break
                                }
                            }
                            if tc == "\"" || tc == "'" {
                                let quote = tc
                                var qEnd = text.index(after: i)
                                var escaped = false
                                while qEnd < text.endIndex {
                                    let qc = text[qEnd]
                                    if escaped {
                                        escaped = false
                                    } else if qc == "\\" {
                                        escaped = true
                                    } else if qc == quote {
                                        qEnd = text.index(after: qEnd)
                                        break
                                    }
                                    qEnd = text.index(after: qEnd)
                                }
                                var strSeg = AttributedString(String(text[i..<qEnd]))
                                strSeg.foregroundColor = palette.stringColor
                                output.append(strSeg)
                                i = qEnd
                                continue
                            }
                            if !isClosingTag && (tc.isLetter || tc == "_") {
                                var attrEnd = text.index(after: i)
                                while attrEnd < text.endIndex && isXMLNameChar(text[attrEnd]) {
                                    attrEnd = text.index(after: attrEnd)
                                }
                                var attrSeg = AttributedString(String(text[i..<attrEnd]))
                                attrSeg.foregroundColor = palette.typeColor
                                output.append(attrSeg)
                                i = attrEnd
                                continue
                            }
                            if tc == "=" {
                                var eqSeg = AttributedString("=")
                                eqSeg.foregroundColor = palette.commentColor
                                output.append(eqSeg)
                                i = text.index(after: i)
                                continue
                            }
                            let nextChar = text.index(after: i)
                            var wsSeg = AttributedString(String(text[i..<nextChar]))
                            wsSeg.foregroundColor = palette.baseColor
                            output.append(wsSeg)
                            i = nextChar
                        }
                        continue
                    }
                }
            }

            // 1. String literal ("...", '...', or `...`)
            if ch == "\"" || ch == "'" || ch == "`" {
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
                seg.foregroundColor = palette.stringColor
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
                    seg.foregroundColor = palette.keywordColor
                    output.append(seg)
                    i = end
                    continue
                }
            }

            // 3. Identifier / Keyword / Type / Function
            if ch.isLetter || ch == "_" {
                var end = text.index(after: i)
                while end < text.endIndex && (text[end].isLetter || text[end].isNumber || text[end] == "_") {
                    end = text.index(after: end)
                }
                let word = String(text[i..<end])
                var seg = AttributedString(word)
                if keywordsSet.contains(word) {
                    seg.foregroundColor = palette.keywordColor
                } else if let first = word.first, first.isUppercase {
                    seg.foregroundColor = palette.typeColor
                } else if end < text.endIndex && text[end] == "(" {
                    seg.foregroundColor = palette.functionColor
                } else {
                    seg.foregroundColor = palette.baseColor
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
                seg.foregroundColor = palette.numberColor
                output.append(seg)
                i = end
                continue
            }

            // 5. Punctuation / Whitespace
            var end = text.index(after: i)
            while end < text.endIndex {
                let c = text[end]
                if c == "\"" || c == "'" || c == "`" || c == "@" || (isMarkup && c == "<") || c.isLetter || c == "_" || c.isNumber {
                    break
                }
                end = text.index(after: end)
            }
            var seg = AttributedString(String(text[i..<end]))
            seg.foregroundColor = palette.baseColor
            output.append(seg)
            i = end
        }

        return output
    }
    
    private static func findGitRoot(startingAt fileURL: URL) -> URL? {
        var current = fileURL.hasDirectoryPath ? fileURL : fileURL.deletingLastPathComponent()
        while current.path != "/" && current.path.count > 1 {
            if FileManager.default.fileExists(atPath: current.appendingPathComponent(".git").path) {
                return current
            }
            current = current.deletingLastPathComponent()
        }
        return nil
    }

    private func checkGitDiff(for overrideURL: URL? = nil) {
        let targetURL = (overrideURL ?? url).standardizedFileURL
        let fallbackWS = appState.workspaceFolder
            ?? AgentService.shared.currentWorkspace.map { URL(fileURLWithPath: $0) }
        guard let gitRoot = Self.findGitRoot(startingAt: targetURL) ?? fallbackWS else { return }
        let rootPrefix = gitRoot.standardizedFileURL.path.hasSuffix("/")
            ? gitRoot.standardizedFileURL.path
            : gitRoot.standardizedFileURL.path + "/"
        guard targetURL.path.hasPrefix(rootPrefix) else { return }
        let relPath = String(targetURL.path.dropFirst(rootPrefix.count))
        
        DispatchQueue.global(qos: .utility).async {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["status", "--porcelain", "--", relPath]
            process.currentDirectoryURL = gitRoot
            process.standardOutput = pipe
            process.standardError = Pipe()
            try? process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                DispatchQueue.main.async {
                    self.hasGitDiff = false
                    self.gitDiffContent = nil
                }
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let status = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            if !status.isEmpty {
                let showProcess = Process()
                let showPipe = Pipe()
                showProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                showProcess.arguments = ["show", "HEAD:\(relPath)"]
                showProcess.currentDirectoryURL = gitRoot
                showProcess.standardOutput = showPipe
                showProcess.standardError = Pipe()
                try? showProcess.run()
                showProcess.waitUntilExit()
                let oldData = showPipe.fileHandleForReading.readDataToEndOfFile()
                let oldText = (showProcess.terminationStatus == 0) ? (String(data: oldData, encoding: .utf8) ?? "") : ""
                
                let attr = try? FileManager.default.attributesOfItem(atPath: targetURL.path)
                let fileSize = (attr?[.size] as? NSNumber)?.int64Value ?? 0
                if fileSize > 10 * 1024 * 1024 {
                    DispatchQueue.main.async {
                        self.hasGitDiff = false
                        self.gitDiffContent = nil
                    }
                    return
                }
                
                let currentText = (try? String(contentsOf: targetURL, encoding: .utf8)) ?? ""
                
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

// MARK: - Shared Header Close Tab Button [✕]

struct PreviewCloseTabButton: View {
    @State private var isHovered: Bool = false

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                PreviewDockService.shared.closeActiveTabOrHideDock()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(isHovered ? .white : .secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovered ? Color.red.opacity(0.85) : Color.primary.opacity(0.06))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help("Close Preview Tab")
    }
}

// MARK: - Interactive Diff Preview View (Theme-Synchronized & Edge-to-Edge Rows)

struct InteractiveDiffPreviewView: View {
    let title: String
    let oldContent: String
    let newContent: String
    var showsCloseButton: Bool = true

    @EnvironmentObject var appState: AppState
    @State private var isCopied: Bool = false
    
    private var diffEntry: CachedDiffEntry {
        DiffCacheManager.getOrComputeDiffEntry(
            id: "preview-diff:\(title)",
            old: oldContent,
            new: newContent
        )
    }

    private var diffLines: [UnifiedDiffLine] {
        diffEntry.lines
    }
    
    private var additionsCount: Int {
        diffLines.filter { $0.type == .addition }.count
    }
    
    private var deletionsCount: Int {
        diffLines.filter { $0.type == .deletion }.count
    }
    
    var body: some View {
        let theme = appState.appTheme
        let headerBg = theme.isGlass ? Color.clear : Color(nsColor: theme.panelBackground)
        let editorCanvas = theme.isGlass ? Color.clear : Color(nsColor: theme.editorBackground)
        let baseTextColor = Color(nsColor: theme.editorText)
        let lineNumColor = Color(nsColor: theme.commentColor).opacity(0.75)

        VStack(spacing: 0) {
            // Diff Stats Header
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    ProgrammingLanguageIconView(fileName: title, size: 14)
                    Text("Diff: \(title)")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
                // Badges: +N, -M
                HStack(spacing: 4) {
                    if additionsCount > 0 {
                        Text("+\(additionsCount)")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.green.opacity(0.16))
                            .foregroundColor(.green)
                            .cornerRadius(3.5)
                    }
                    if deletionsCount > 0 {
                        Text("-\(deletionsCount)")
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.red.opacity(0.16))
                            .foregroundColor(.red)
                            .cornerRadius(3.5)
                    }
                }
                
                Spacer()
                
                // Copy Diff Button
                Button {
                    let fullDiff = diffLines.map { line in
                        line.type == .hunkHeader ? line.text : "\(line.prefix)\(line.text)"
                    }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullDiff, forType: .string)
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        isCopied = false
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 9.5))
                        Text(isCopied ? "Copied" : "Copy Diff")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(isCopied ? .green : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help("Copy full unified diff to clipboard")

                if showsCloseButton {
                    Divider()
                        .frame(height: 14)
                        .padding(.horizontal, 1)

                    PreviewCloseTabButton()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(headerBg)
            
            Divider()
            
            // Diff Content Lines (Edge-to-Edge Full Width)
            GeometryReader { geo in
                let minRowWidth = max(geo.size.width, diffEntry.minContentWidth)
                ScrollView([.horizontal, .vertical], showsIndicators: true) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(diffLines) { (diffLine: UnifiedDiffLine) in
                            if diffLine.type == .hunkHeader {
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .fill(Color.cyan.opacity(0.85))
                                        .frame(width: 2.5, height: 22)

                                    Text("⋯")
                                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.cyan.opacity(0.8))
                                        .frame(width: 74, alignment: .center)

                                    Rectangle()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(width: 1, height: 22)

                                    Text(diffLine.text)
                                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                        .foregroundColor(.cyan.opacity(0.9))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .padding(.leading, 10)
                                        .padding(.trailing, 20)

                                    Spacer(minLength: 0)
                                }
                                .frame(minWidth: minRowWidth, minHeight: 22, maxHeight: 22, alignment: .leading)
                                .background(Color.cyan.opacity(theme.isDark ? 0.09 : 0.07))
                            } else {
                                let rowTextColor: Color = {
                                    switch diffLine.type {
                                    case .addition: return baseTextColor
                                    case .deletion: return baseTextColor.opacity(0.78)
                                    case .context: return baseTextColor.opacity(0.88)
                                    case .hunkHeader: return .cyan
                                    }
                                }()
                                let rowBg: Color = {
                                    switch diffLine.type {
                                    case .addition: return Color.green.opacity(theme.isDark ? 0.15 : 0.12)
                                    case .deletion: return Color.red.opacity(theme.isDark ? 0.14 : 0.10)
                                    case .context: return Color.clear
                                    case .hunkHeader: return Color.cyan.opacity(0.08)
                                    }
                                }()

                                HStack(spacing: 0) {
                                    // Status accent strip (2.5pt)
                                    Rectangle()
                                        .fill(diffLine.accentColor)
                                        .frame(width: 2.5, height: 19)
                                    
                                    // Old line number gutter
                                    Text(diffLine.oldNum)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(lineNumColor)
                                        .frame(width: 34, alignment: .trailing)
                                        .padding(.trailing, 4)
                                    
                                    // New line number gutter
                                    Text(diffLine.newNum)
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(lineNumColor)
                                        .frame(width: 34, alignment: .trailing)
                                        .padding(.trailing, 6)
                                    
                                    // Gutter divider line
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(width: 1, height: 19)
                                    
                                    // Prefix (+/-)
                                    Text(diffLine.prefix)
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .foregroundColor(diffLine.prefixColor)
                                        .frame(width: 18, alignment: .center)
                                    
                                    // Code text (tab-expanded for crisp alignment)
                                    Text(diffLine.displayText)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundColor(rowTextColor)
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .padding(.trailing, 24)
                                    
                                    Spacer(minLength: 0)
                                }
                                .frame(minWidth: minRowWidth, minHeight: 19, maxHeight: 19, alignment: .leading)
                                .background(rowBg)
                            }
                        }
                    }
                    .frame(minWidth: minRowWidth, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(editorCanvas)
        }
        .background(editorCanvas)
    }
}

// MARK: - Interactive Diff File Preview View (for .diff / .patch files)

struct InteractiveDiffFilePreviewView: View {
    let url: URL
    var showsCloseButton: Bool = true
    
    @EnvironmentObject var appState: AppState
    @State private var rawDiff: String = ""
    @State private var displayLines: [String] = []
    @State private var maxLineChars: Int = 0
    @State private var isLoading: Bool = true
    @State private var isCopied: Bool = false
    
    var body: some View {
        let theme = appState.appTheme
        let headerBg = theme.isGlass ? Color.clear : Color(nsColor: theme.panelBackground)
        let editorCanvas = theme.isGlass ? Color.clear : Color(nsColor: theme.editorBackground)
        let baseTextColor = Color(nsColor: theme.editorText)
        let lineNumColor = Color(nsColor: theme.commentColor).opacity(0.75)

        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.left.and.right.square")
                    .font(.system(size: 10.5))
                    .foregroundColor(.cyan)
                
                Text(url.lastPathComponent)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(.primary)
                
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
                        .font(.system(size: 11))
                        .foregroundColor(isCopied ? .green : .secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Copy patch content")

                if showsCloseButton {
                    Divider()
                        .frame(height: 14)
                        .padding(.horizontal, 1)

                    PreviewCloseTabButton()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(headerBg)
            
            Divider()
            
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geo in
                    let minRowWidth = max(geo.size.width, CGFloat(maxLineChars) * 7.2 + 72)
                    ScrollView([.horizontal, .vertical], showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(0..<displayLines.count, id: \.self) { idx in
                                let line = displayLines[idx]
                                let isAdd = line.hasPrefix("+") && !line.hasPrefix("+++")
                                let isDel = line.hasPrefix("-") && !line.hasPrefix("---")
                                let isHunk = line.hasPrefix("@@")
                                let isHeaderMeta = line.hasPrefix("+++") || line.hasPrefix("---") || line.hasPrefix("diff --git") || line.hasPrefix("index ")
                                
                                HStack(spacing: 0) {
                                    Rectangle()
                                        .fill(isAdd ? Color.green : (isDel ? Color.red : (isHunk ? Color.cyan : Color.clear)))
                                        .frame(width: 2.5, height: 19)
                                    
                                    Text("\(idx + 1)")
                                        .font(.system(size: 10.5, design: .monospaced))
                                        .foregroundColor(lineNumColor)
                                        .frame(width: 36, alignment: .trailing)
                                        .padding(.trailing, 6)
                                    
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(width: 1, height: 19)
                                    
                                    Text(line.isEmpty ? " " : line)
                                        .font(.system(size: 11.5, design: .monospaced))
                                        .foregroundColor(
                                            isAdd ? baseTextColor :
                                            (isDel ? baseTextColor.opacity(0.78) :
                                            (isHunk ? .cyan :
                                            (isHeaderMeta ? .secondary : baseTextColor.opacity(0.88))))
                                        )
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .padding(.leading, 8)
                                        .padding(.trailing, 24)
                                    
                                    Spacer(minLength: 0)
                                }
                                .frame(minWidth: minRowWidth, minHeight: 19, maxHeight: 19, alignment: .leading)
                                .background(
                                    isAdd ? Color.green.opacity(theme.isDark ? 0.15 : 0.12) :
                                    (isDel ? Color.red.opacity(theme.isDark ? 0.14 : 0.10) :
                                    (isHunk ? Color.cyan.opacity(theme.isDark ? 0.09 : 0.07) : Color.clear))
                                )
                            }
                        }
                        .frame(minWidth: minRowWidth, alignment: .leading)
                        .padding(.vertical, 4)
                    }
                }
                .background(editorCanvas)
            }
        }
        .background(editorCanvas)
        .onAppear {
            loadDiffFile(from: url)
        }
        .onChange(of: url) { newURL in
            loadDiffFile(from: newURL)
        }
    }

    private func loadDiffFile(from targetURL: URL) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let content = (try? String(contentsOf: targetURL, encoding: .utf8)) ?? ""
            let normalized = content
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            var lines = normalized.components(separatedBy: "\n")
            if lines.count > 1 && lines.last == "" {
                lines.removeLast()
            }
            var maxChars = 0
            let expanded = lines.map { line -> String in
                let s = line.contains("\t") ? line.replacingOccurrences(of: "\t", with: "    ") : line
                if s.count > maxChars { maxChars = min(s.count, 400) }
                return s
            }
            DispatchQueue.main.async {
                self.rawDiff = content
                self.displayLines = expanded
                self.maxLineChars = maxChars
                self.isLoading = false
            }
        }
    }
}

// MARK: - 120Hz Native AppKit Read-Only Code Viewer + Line Number Gutter

private final class PreviewCodeGutterRulerView: NSRulerView {
    weak var textView: NSTextView?
    var lineUTF16Offsets: [Int] = [0]
    var highlightRange: ClosedRange<Int>?
    var textColor: NSColor = .secondaryLabelColor
    var bgColor: NSColor = .textBackgroundColor
    var isGlass: Bool = false

    override var isFlipped: Bool { true }

    private let gutterFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    private let gutterBoldFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)

    init(scrollView: NSScrollView, textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        self.clientView = textView
        self.ruleThickness = 44
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateRuleThickness() {
        let total = max(1, lineUTF16Offsets.count)
        let desired: CGFloat = total > 9999 ? 54 : (total > 999 ? 46 : 38)
        if abs(ruleThickness - desired) > 0.5 {
            ruleThickness = desired
        }
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        if !isGlass {
            bgColor.setFill()
            rect.fill()
        }

        let visibleRect = scrollView?.contentView.bounds ?? textView.visibleRect
        let inset = textView.textContainerInset
        let containerRect = visibleRect.offsetBy(dx: -inset.width, dy: -inset.height)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: containerRect, in: textContainer)
        guard glyphRange.length > 0 || lineUTF16Offsets.count <= 1 else { return }
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // Binary search starting 0-based line index for charRange.location
        var lo = 0
        var hi = max(0, lineUTF16Offsets.count - 1)
        while lo < hi {
            let mid = (lo + hi + 1) >> 1
            if lineUTF16Offsets[mid] <= charRange.location {
                lo = mid
            } else {
                hi = mid - 1
            }
        }

        let endChar = NSMaxRange(charRange)
        let totalCount = lineUTF16Offsets.count
        var lineIdx = lo
        while lineIdx < totalCount {
            let charLoc = lineUTF16Offsets[lineIdx]
            if charLoc > endChar && lineIdx > lo { break }

            let glyphIdx = charLoc < layoutManager.numberOfGlyphs
                ? layoutManager.glyphIndexForCharacter(at: charLoc)
                : max(0, layoutManager.numberOfGlyphs - 1)
            let lineRect: NSRect
            if layoutManager.numberOfGlyphs > 0 && glyphIdx < layoutManager.numberOfGlyphs {
                lineRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIdx, effectiveRange: nil, withoutAdditionalLayout: true)
            } else {
                lineRect = NSRect(x: 0, y: 0, width: 100, height: 19)
            }

            let y = lineRect.minY + inset.height - visibleRect.minY
            if y > bounds.maxY + 24 { break }
            if y + lineRect.height >= -24 {
                let lineNum = lineIdx + 1
                let isHighlighted = highlightRange?.contains(lineNum) ?? false
                if isHighlighted {
                    NSColor.controlAccentColor.setFill()
                    NSRect(x: 0, y: y, width: 2.5, height: max(18, lineRect.height)).fill()
                }
                let numStr = "\(lineNum)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: isHighlighted ? gutterBoldFont : gutterFont,
                    .foregroundColor: isHighlighted ? NSColor.controlAccentColor : textColor
                ]
                let size = numStr.size(withAttributes: attrs)
                let drawPt = NSPoint(
                    x: max(4, ruleThickness - size.width - 8),
                    y: y + max(0, (lineRect.height - size.height) * 0.5)
                )
                numStr.draw(at: drawPt, withAttributes: attrs)
            }
            lineIdx += 1
        }
    }
}

private struct PreviewReadOnlyCodeNSView: NSViewRepresentable {
    let attributedCode: NSAttributedString
    let rawCode: String
    let lineUTF16Offsets: [Int]
    let revision: UInt64
    let showLineNumbers: Bool
    let highlightRange: ClosedRange<Int>?
    let editorBackground: NSColor
    let gutterTextColor: NSColor
    let selectionHighlightColor: NSColor
    let isGlass: Bool

    final class Coordinator: NSObject {
        var lastRevision: UInt64 = 0
        var lastHighlightRange: ClosedRange<Int>?
        var appliedTempRange: NSRange?
        weak var gutterView: PreviewCodeGutterRulerView?
        nonisolated(unsafe) var boundsObserver: NSObjectProtocol?

        deinit {
            if let obs = boundsObserver {
                NotificationCenter.default.removeObserver(obs)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = !isGlass
        scrollView.backgroundColor = editorBackground

        // Force TextKit 1 (`NSTextView(usingTextLayoutManager: false)`) so NSRulerView glyph layout & temporary attributes run at 120Hz
        let textView: NSTextView
        if #available(macOS 13.0, *) {
            textView = NSTextView(usingTextLayoutManager: false)
        } else {
            textView = NSTextView()
        }
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = false
        textView.usesFindBar = true
        textView.drawsBackground = !isGlass
        textView.backgroundColor = editorBackground
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = true
        textView.autoresizingMask = []
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = false

        scrollView.documentView = textView

        let gutter = PreviewCodeGutterRulerView(scrollView: scrollView, textView: textView)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = showLineNumbers
        scrollView.rulersVisible = showLineNumbers
        context.coordinator.gutterView = gutter

        scrollView.contentView.postsBoundsChangedNotifications = true
        context.coordinator.boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: scrollView.contentView,
            queue: .main
        ) { [weak gutter] _ in
            gutter?.needsDisplay = true
        }

        applyUpdates(to: scrollView, textView: textView, coordinator: context.coordinator, isInitial: true)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        applyUpdates(to: scrollView, textView: textView, coordinator: context.coordinator, isInitial: false)
    }

    private func applyUpdates(
        to scrollView: NSScrollView,
        textView: NSTextView,
        coordinator: Coordinator,
        isInitial: Bool
    ) {
        scrollView.drawsBackground = !isGlass
        scrollView.backgroundColor = editorBackground
        textView.drawsBackground = !isGlass
        textView.backgroundColor = editorBackground

        if scrollView.rulersVisible != showLineNumbers {
            scrollView.hasVerticalRuler = showLineNumbers
            scrollView.rulersVisible = showLineNumbers
        }

        let didChangeContent = isInitial || coordinator.lastRevision != revision
        if didChangeContent {
            coordinator.lastRevision = revision
            coordinator.appliedTempRange = nil
            textView.textStorage?.setAttributedString(attributedCode)
        }

        if let gutter = coordinator.gutterView {
            gutter.lineUTF16Offsets = lineUTF16Offsets
            gutter.highlightRange = highlightRange
            gutter.textColor = gutterTextColor
            gutter.bgColor = editorBackground
            gutter.isGlass = isGlass
            gutter.updateRuleThickness()
            gutter.needsDisplay = true
        }

        let didChangeHighlight = didChangeContent || coordinator.lastHighlightRange != highlightRange
        if didChangeHighlight, let lm = textView.layoutManager {
            coordinator.lastHighlightRange = highlightRange
            let docLen = (textView.string as NSString).length
            if let prev = coordinator.appliedTempRange, prev.location + prev.length <= docLen {
                lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: prev)
            }
            coordinator.appliedTempRange = nil

            if let range = highlightRange, !lineUTF16Offsets.isEmpty, docLen > 0 {
                let startIdx = max(0, min(lineUTF16Offsets.count - 1, range.lowerBound - 1))
                let endLineIdx = max(startIdx, min(lineUTF16Offsets.count - 1, range.upperBound - 1))
                let charStart = min(docLen, lineUTF16Offsets[startIdx])
                let charEnd: Int
                if endLineIdx + 1 < lineUTF16Offsets.count {
                    charEnd = min(docLen, lineUTF16Offsets[endLineIdx + 1])
                } else {
                    charEnd = docLen
                }
                if charEnd > charStart {
                    let nsRange = NSRange(location: charStart, length: charEnd - charStart)
                    lm.addTemporaryAttribute(.backgroundColor, value: selectionHighlightColor, forCharacterRange: nsRange)
                    coordinator.appliedTempRange = nsRange
                    DispatchQueue.main.async {
                        let contextStartIdx = max(0, startIdx - 3)
                        let contextCharStart = min(docLen, lineUTF16Offsets[contextStartIdx])
                        textView.scrollRangeToVisible(NSRange(location: contextCharStart, length: min(1, docLen - contextCharStart)))
                    }
                }
            } else if didChangeContent {
                textView.scroll(NSPoint.zero)
            }
        }
    }
}
