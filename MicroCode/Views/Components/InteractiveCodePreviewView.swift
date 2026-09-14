//
//  InteractiveCodePreviewView.swift
//  MicroCode
//
//  High-performance code viewer and diff inspector for the Universal Preview Dock.
//  Provides syntax-styled code view, line numbers, git diff comparison,
//  and unified diff rendering for code files and patches.
//

import SwiftUI
import AppKit

// MARK: - Interactive Code Preview View

struct InteractiveCodePreviewView: View {
    let url: URL
    @EnvironmentObject var appState: AppState
    
    @State private var codeContent: String = ""
    @State private var isLoading: Bool = true
    @State private var errorMessage: String? = nil
    @State private var isCopied: Bool = false
    @State private var showLineNumbers: Bool = true
    @State private var showGitDiff: Bool = false
    @State private var gitDiffContent: (old: String, new: String)? = nil
    @State private var hasGitDiff: Bool = false
    
    private var fileExtension: String {
        url.pathExtension.lowercased()
    }
    
    private var detectedLanguage: String {
        switch fileExtension {
        case "swift": return "swift"
        case "rs": return "rust"
        case "py": return "python"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "kt", "kts": return "kotlin"
        case "java": return "java"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "go": return "go"
        case "dart": return "dart"
        case "json": return "json"
        case "html", "htm": return "html"
        case "css", "scss", "sass": return "css"
        case "yaml", "yml": return "yaml"
        case "xml", "plist": return "xml"
        case "sh", "bash", "zsh": return "bash"
        case "sql": return "sql"
        case "toml": return "toml"
        case "md", "markdown": return "markdown"
        default: return "text"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
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
                // Code View with Gutter
                codeViewer
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.85))
        .onAppear {
            loadFileContent()
            checkGitDiff()
        }
        .onChange(of: url) { _ in
            loadFileContent()
            checkGitDiff()
        }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 8) {
            // File icon & language badge
            HStack(spacing: 5) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.accentColor)
                
                Text(url.lastPathComponent)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                
                Text(detectedLanguage.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundColor(.accentColor)
                    .cornerRadius(3)
            }
            
            Spacer()
            
            // Stats (lines & size)
            if !isLoading && errorMessage == nil {
                let lineCount = codeContent.components(separatedBy: "\n").count
                let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? codeContent.utf8.count
                let formattedSize = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
                
                Text("\(lineCount) lines · \(formattedSize)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            // Toggle Line Numbers
            Button {
                showLineNumbers.toggle()
            } label: {
                Image(systemName: showLineNumbers ? "list.number" : "text.alignleft")
                    .font(.system(size: 10))
                    .foregroundColor(showLineNumbers ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            .help(showLineNumbers ? "Hide Line Numbers" : "Show Line Numbers")
            
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
                        Text(showGitDiff ? "Show Code" : "Diff")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
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
                    .font(.system(size: 10))
                    .foregroundColor(isCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Copy code to clipboard")
            
            // Open in Main Editor
            Button {
                Task { @MainActor in
                    await appState.loadFile(url: url)
                }
            } label: {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open in main editor tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }
    
    // MARK: - Code Viewer
    
    private var codeViewer: some View {
        let lines = codeContent.components(separatedBy: "\n")
        let totalLines = lines.count
        let gutterWidth: CGFloat = totalLines > 999 ? 42 : (totalLines > 99 ? 34 : 26)
        
        return ScrollView([.horizontal, .vertical], showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                // Line Numbers Gutter
                if showLineNumbers {
                    VStack(alignment: .trailing, spacing: 0) {
                        ForEach(0..<lines.count, id: \.self) { index in
                            Text("\(index + 1)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary.opacity(0.45))
                                .frame(width: gutterWidth, height: 18, alignment: .trailing)
                                .padding(.trailing, 6)
                        }
                    }
                    .padding(.vertical, 6)
                    .background(Color.primary.opacity(0.025))
                    
                    // Gutter Separator
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 1)
                }
                
                // Code Lines
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<lines.count, id: \.self) { index in
                        Text(lines[index].isEmpty ? " " : lines[index])
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.primary.opacity(0.92))
                            .frame(height: 18, alignment: .leading)
                            .padding(.leading, 8)
                    }
                }
                .padding(.vertical, 6)
                .textSelection(.enabled)
                
                Spacer(minLength: 20)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    // MARK: - Helpers
    
    private func loadFileContent() {
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                // Try UTF-8 first, fallback to ASCII/Latin-1
                let string = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? String(decoding: data, as: UTF8.self)
                
                DispatchQueue.main.async {
                    self.codeContent = string
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
                // Fetch HEAD version
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
                HStack(spacing: 4) {
                    Image(systemName: "arrow.left.and.right.square")
                        .font(.system(size: 10))
                        .foregroundColor(.cyan)
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
