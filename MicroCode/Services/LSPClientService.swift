//
//  LSPClientService.swift
//  MicroCode - Language Server Protocol Client
//
//  Generic LSP client that can connect to any language server.
//  Supports: rust-analyzer, pyright, sourcekit-lsp, gopls, clangd
//
//  Copyright © 2025 Dotmini Company Limited. All rights reserved.
//

import Foundation

// MARK: - LSP Protocol Types

/// LSP Message header format
struct LSPMessage {
    static let contentLengthHeader = "Content-Length: "
    static let headerTerminator = "\r\n\r\n"
}

/// JSON-RPC Request
struct JSONRPCRequest<T: Encodable>: Encodable {
    let jsonrpc: String = "2.0"
    let id: Int
    let method: String
    let params: T?
}

/// JSON-RPC Response
struct JSONRPCResponse<T: Decodable>: Decodable {
    let jsonrpc: String
    let id: Int?
    let result: T?
    let error: JSONRPCError?
}

struct JSONRPCError: Decodable {
    let code: Int
    let message: String
}

/// JSON-RPC Notification (no id, no response expected)
struct JSONRPCNotification<T: Codable>: Codable {
    let jsonrpc: String = "2.0"
    let method: String
    let params: T?
}

// MARK: - LSP Initialize Types

struct InitializeParams: Codable {
    let processId: Int?
    let rootUri: String?
    let capabilities: ClientCapabilities
}

struct ClientCapabilities: Codable {
    let textDocument: TextDocumentClientCapabilities?
}

struct TextDocumentClientCapabilities: Codable {
    let completion: CompletionClientCapabilities?
    let hover: HoverClientCapabilities?
    let definition: DefinitionClientCapabilities?
}

struct CompletionClientCapabilities: Codable {
    let completionItem: CompletionItemCapabilities?
}

struct CompletionItemCapabilities: Codable {
    let snippetSupport: Bool?
    let documentationFormat: [String]?
}

struct HoverClientCapabilities: Codable {
    let contentFormat: [String]?
}

struct DefinitionClientCapabilities: Codable {
    let linkSupport: Bool?
}

struct InitializeResult: Codable {
    let capabilities: ServerCapabilities
}

struct ServerCapabilities: Codable {
    let completionProvider: CompletionOptions?
    let hoverProvider: Bool?
    let definitionProvider: Bool?
}

struct CompletionOptions: Codable {
    let triggerCharacters: [String]?
}

// MARK: - LSP TextDocument Types

struct TextDocumentIdentifier: Codable {
    let uri: String
}

struct VersionedTextDocumentIdentifier: Codable {
    let uri: String
    let version: Int
}

struct TextDocumentItem: Codable {
    let uri: String
    let languageId: String
    let version: Int
    let text: String
}

struct DidOpenTextDocumentParams: Codable {
    let textDocument: TextDocumentItem
}

struct DidChangeTextDocumentParams: Codable {
    let textDocument: VersionedTextDocumentIdentifier
    let contentChanges: [TextDocumentContentChangeEvent]
}

struct TextDocumentContentChangeEvent: Codable {
    let text: String
}

struct LSPPosition: Codable {
    let line: Int
    let character: Int
}

struct LSPRange: Codable {
    let start: LSPPosition
    let end: LSPPosition
}

struct LSPLocation: Codable {
    let uri: String
    let range: LSPRange
}

struct PublishDiagnosticsParams: Codable {
    let uri: String
    let diagnostics: [LSPDiagnostic]
}

struct LSPDiagnostic: Codable {
    let range: LSPRange
    let severity: Int?
    let code: DiagnosticCode?
    let source: String?
    let message: String
}

enum DiagnosticCode: Codable {
    case string(String)
    case int(Int)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Int.self) {
            self = .int(x)
            return
        }
        if let x = try? container.decode(String.self) {
            self = .string(x)
            return
        }
        throw DecodingError.typeMismatch(DiagnosticCode.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Wrong type for DiagnosticCode"))
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let x): try container.encode(x)
        case .string(let x): try container.encode(x)
        }
    }
}

// MARK: - Completion Types

struct CompletionContext: Codable {
    /// 1 = Invoked, 2 = TriggerCharacter, 3 = TriggerForIncompleteCompletions
    let triggerKind: Int
    let triggerCharacter: String?
}

struct CompletionParams: Codable {
    let textDocument: TextDocumentIdentifier
    let position: LSPPosition
    let context: CompletionContext?
    
    init(textDocument: TextDocumentIdentifier, position: LSPPosition, context: CompletionContext? = nil) {
        self.textDocument = textDocument
        self.position = position
        self.context = context
    }
}

struct CompletionList: Codable {
    let isIncomplete: Bool
    let items: [CompletionItem]
}

/// Official LSP 3.17 documentation payload (`string | MarkupContent`)
enum LSPDocumentation: Codable {
    case string(String)
    case markup(MarkupContent)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let markup = try? container.decode(MarkupContent.self) {
            self = .markup(markup)
        } else {
            self = .string("")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str): try container.encode(str)
        case .markup(let markup): try container.encode(markup)
        }
    }
    
    var displayText: String? {
        switch self {
        case .string(let s): return s.isEmpty ? nil : s
        case .markup(let m): return m.value.isEmpty ? nil : m.value
        }
    }
}

/// Official LSP 3.17 `TextEdit | InsertReplaceEdit`
struct LSPCompletionTextEdit: Codable {
    let newText: String
    let range: LSPRange?
    
    enum CodingKeys: String, CodingKey {
        case newText
        case range
        case replace
        case insert
    }
    
    init(newText: String, range: LSPRange? = nil) {
        self.newText = newText
        self.range = range
    }
    
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.newText = (try? c.decode(String.self, forKey: .newText)) ?? ""
        if let r = try? c.decode(LSPRange.self, forKey: .range) {
            self.range = r
        } else if let r = try? c.decode(LSPRange.self, forKey: .replace) {
            self.range = r
        } else {
            self.range = try? c.decode(LSPRange.self, forKey: .insert)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(newText, forKey: .newText)
        try c.encodeIfPresent(range, forKey: .range)
    }
}

struct CompletionItem: Codable, Identifiable {
    var id: String { "\(label)-\(kind ?? 0)-\(detail ?? "")" }
    let label: String
    let kind: Int?
    let detail: String?
    let documentationContent: LSPDocumentation?
    let insertText: String?
    let insertTextFormat: Int?
    let filterText: String?
    let sortText: String?
    let textEdit: LSPCompletionTextEdit?
    
    var documentation: String? {
        documentationContent?.displayText
    }
    
    enum CodingKeys: String, CodingKey {
        case label, kind, detail
        case documentationContent = "documentation"
        case insertText, insertTextFormat, filterText, sortText, textEdit
    }
    
    init(
        label: String,
        kind: Int? = nil,
        detail: String? = nil,
        documentation: String? = nil,
        insertText: String? = nil,
        insertTextFormat: Int? = nil,
        filterText: String? = nil,
        sortText: String? = nil,
        textEdit: LSPCompletionTextEdit? = nil
    ) {
        self.label = label
        self.kind = kind
        self.detail = detail
        self.documentationContent = documentation.map { .string($0) }
        self.insertText = insertText
        self.insertTextFormat = insertTextFormat
        self.filterText = filterText
        self.sortText = sortText
        self.textEdit = textEdit
    }
}

extension CompletionItem {
    /// Primary identifier part of the label (e.g. `frame` from `frame(minWidth:maxWidth:)`)
    var primarySymbolName: String {
        if let parenIdx = label.firstIndex(of: "(") {
            let prefix = String(label[..<parenIdx])
            if !prefix.isEmpty { return prefix }
        }
        return label
    }
    
    /// Parameter signature suffix if present (e.g. `(minWidth:maxWidth:)`)
    var parameterSignature: String? {
        if let parenIdx = label.firstIndex(of: "(") {
            let suffix = String(label[parenIdx...])
            return suffix.isEmpty ? nil : suffix
        }
        return nil
    }
    
    /// Produces clean insertion text (resolving LSP snippet placeholders like `${1:value}` and `$0`)
    /// and returns how many UTF-16 characters from the end of the inserted string the cursor should be placed.
    func resolvedInsertion() -> (text: String, cursorOffsetFromEnd: Int) {
        var raw = textEdit?.newText ?? insertText ?? label
        
        // If `raw` is a Swift/LSP signature label like `frame(minWidth:idealWidth:)` without snippet placeholders
        // and no explicit insertText/textEdit was provided, convert `foo(bar:baz:)` -> `foo(bar: , baz: )`
        if textEdit == nil && insertText == nil,
           let parenStart = raw.firstIndex(of: "("),
           raw.hasSuffix(")"),
           raw.contains(":") {
            let funcName = String(raw[..<parenStart])
            let inner = String(raw[raw.index(after: parenStart)..<raw.index(before: raw.endIndex)])
            let parts = inner.split(separator: ":").map(String.init)
            if !parts.isEmpty {
                let formattedParams = parts.compactMap { part -> String? in
                    let p = part.trimmingCharacters(in: .whitespaces)
                    if p.isEmpty || p == "_" { return nil }
                    return "\(p): "
                }
                if formattedParams.isEmpty {
                    let result = "\(funcName)()"
                    return (result, 1) // place cursor inside ()
                } else {
                    let firstParam = formattedParams[0]
                    let restParams = formattedParams.dropFirst().joined(separator: ", ")
                    let fullInside = restParams.isEmpty ? firstParam : "\(firstParam), \(restParams)"
                    let result = "\(funcName)(\(fullInside))"
                    // Place cursor right after `firstParam`
                    let offsetFromEnd = (result.utf16.count) - (funcName.utf16.count + 1 + firstParam.utf16.count)
                    return (result, max(0, offsetFromEnd))
                }
            }
        }
        
        // Resolve LSP Snippet syntax: `${1:placeholder}` -> `placeholder`, `${1}` -> ``, `$0` -> cursor marker
        if raw.contains("$") {
            var output = ""
            var cursorUTF16Pos: Int? = nil
            var firstPlaceholderEndUTF16Pos: Int? = nil
            var i = raw.startIndex
            while i < raw.endIndex {
                if raw[i] == "$" {
                    let next = raw.index(after: i)
                    if next < raw.endIndex && raw[next] == "{" {
                        // Find matching `}`
                        if let closeBrace = raw[next...].firstIndex(of: "}") {
                            let inside = String(raw[raw.index(after: next)..<closeBrace])
                            if let colonIdx = inside.firstIndex(of: ":") {
                                let numStr = String(inside[..<colonIdx])
                                let placeholder = String(inside[inside.index(after: colonIdx)...])
                                // Clean Swift sourcekit-lsp type placeholders like `<#T##CGFloat?#>` if present
                                let cleanedPlaceholder = Self.cleanSourceKitPlaceholder(placeholder)
                                output.append(cleanedPlaceholder)
                                if numStr == "1" && firstPlaceholderEndUTF16Pos == nil {
                                    firstPlaceholderEndUTF16Pos = output.utf16.count
                                }
                            } else if inside == "0" {
                                cursorUTF16Pos = output.utf16.count
                            }
                            i = raw.index(after: closeBrace)
                            continue
                        }
                    } else if next < raw.endIndex && raw[next].isNumber {
                        var digitEnd = next
                        while digitEnd < raw.endIndex && raw[digitEnd].isNumber {
                            digitEnd = raw.index(after: digitEnd)
                        }
                        let numStr = String(raw[next..<digitEnd])
                        if numStr == "0" {
                            cursorUTF16Pos = output.utf16.count
                        } else if numStr == "1" && firstPlaceholderEndUTF16Pos == nil {
                            firstPlaceholderEndUTF16Pos = output.utf16.count
                        }
                        i = digitEnd
                        continue
                    }
                }
                output.append(raw[i])
                i = raw.index(after: i)
            }
            raw = Self.cleanSourceKitPlaceholder(output)
            let targetPos = cursorUTF16Pos ?? firstPlaceholderEndUTF16Pos ?? raw.utf16.count
            let offsetFromEnd = max(0, raw.utf16.count - targetPos)
            return (raw, offsetFromEnd)
        }
        
        raw = Self.cleanSourceKitPlaceholder(raw)
        if raw.hasSuffix("()") {
            return (raw, 0)
        }
        return (raw, 0)
    }
    
    private static func cleanSourceKitPlaceholder(_ text: String) -> String {
        guard text.contains("<#") else { return text }
        var result = ""
        var idx = text.startIndex
        while idx < text.endIndex {
            if text[idx...].hasPrefix("<#"),
               let endRange = text.range(of: "#>", range: idx..<text.endIndex) {
                let inner = String(text[text.index(idx, offsetBy: 2)..<endRange.lowerBound])
                // Format is often `T##Type##Display` or `T##Display`
                let parts = inner.components(separatedBy: "##")
                if let last = parts.last, !last.isEmpty, last != "T" {
                    result.append(last)
                }
                idx = endRange.upperBound
            } else {
                result.append(text[idx])
                idx = text.index(after: idx)
            }
        }
        return result
    }

    var kindDescription: String {
        switch kind {
        case 1: return "Text"
        case 2: return "Method"
        case 3: return "Function"
        case 4: return "Constructor"
        case 5: return "Field"
        case 6: return "Variable"
        case 7: return "Class"
        case 8: return "Interface"
        case 9: return "Module"
        case 10: return "Property"
        case 11: return "Unit"
        case 12: return "Value"
        case 13: return "Enum"
        case 14: return "Keyword"
        case 15: return "Snippet"
        case 16: return "Color"
        case 17: return "File"
        case 18: return "Reference"
        case 19: return "Folder"
        case 20: return "EnumMember"
        case 21: return "Constant"
        case 22: return "Struct"
        case 23: return "Event"
        case 24: return "Operator"
        case 25: return "TypeParameter"
        default: return "Symbol"
        }
    }
}

// MARK: - Hover Types

struct HoverParams: Codable {
    let textDocument: TextDocumentIdentifier
    let position: LSPPosition
}

struct HoverResult: Codable {
    let contents: HoverContents
    let range: LSPRange?
}

enum HoverContents: Codable {
    case string(String)
    case markedString(MarkedString)
    case markupContent(MarkupContent)
    case array([MarkedString])
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let markup = try? container.decode(MarkupContent.self) {
            self = .markupContent(markup)
        } else if let marked = try? container.decode(MarkedString.self) {
            self = .markedString(marked)
        } else if let array = try? container.decode([MarkedString].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid hover contents")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let str): try container.encode(str)
        case .markedString(let marked): try container.encode(marked)
        case .markupContent(let markup): try container.encode(markup)
        case .array(let array): try container.encode(array)
        }
    }
    
    var displayText: String {
        switch self {
        case .string(let str): return str
        case .markedString(let marked): return marked.value
        case .markupContent(let markup): return markup.value
        case .array(let array): return array.map { $0.value }.joined(separator: "\n")
        }
    }
}

struct MarkedString: Codable {
    let language: String?
    let value: String
}

struct MarkupContent: Codable {
    let kind: String
    let value: String
}

// MARK: - Definition Types

struct DefinitionParams: Codable {
    let textDocument: TextDocumentIdentifier
    let position: LSPPosition
}

// MARK: - Language Server Configuration

enum LanguageServer: String, CaseIterable {
    case rustAnalyzer = "rust-analyzer"
    case pyright = "pyright-langserver"
    case sourcekitLSP = "sourcekit-lsp"
    case gopls = "gopls"
    case clangd = "clangd"
    case typescriptServer = "typescript-language-server"
    case kotlin = "kotlin-language-server"
    case dart = "dart" // dart language-server
    case jdtls = "jdtls" // Java
    case csharp = "csharp-ls" // C# / .NET
    case solargraph = "solargraph" // Ruby
    case intelephense = "intelephense" // PHP
    
    var languageIds: [String] {
        switch self {
        case .rustAnalyzer: return ["rust", "rs"]
        case .pyright: return ["python", "py"]
        case .sourcekitLSP: return ["swift", "objective-c", "objc"]
        case .gopls: return ["go", "golang"]
        case .clangd: return ["c", "cpp", "c++", "h", "hpp", "m", "mm", "objective-c", "objective-cpp"]
        case .typescriptServer: return ["typescript", "javascript", "ts", "js", "tsx", "jsx", "html", "css", "json"]
        case .kotlin: return ["kotlin", "kt"]
        case .dart: return ["dart"]
        case .jdtls: return ["java"]
        case .csharp: return ["csharp", "cs", "dotnet"]
        case .solargraph: return ["ruby", "rb"]
        case .intelephense: return ["php"]
        }
    }
    
    var searchPaths: [String] {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let commonPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "\(homeDir)/.cargo/bin",
            "\(homeDir)/.local/bin",
            // Add flutter/dart path estimation
            "\(homeDir)/development/flutter/bin",
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin",
            "/Library/Developer/CommandLineTools/usr/bin"
        ]
        return commonPaths.map { "\($0)/\(rawValue)" }
    }
    
    static func serverFor(language: String) -> LanguageServer? {
        let lang = language.lowercased()
        return allCases.first { $0.languageIds.contains(lang) }
    }
}

enum CustomLanguageServer: String, CaseIterable {
   // Placeholder for extending via settings
   case none
}

// MARK: - LSP Client Service

/// Generic LSP client that can connect to any language server
@MainActor
class LSPClientService: ObservableObject {
    
    // MARK: - Properties
    
    private var process: Process?
    private var stdin: Pipe?
    private var stdout: Pipe?
    private var stderr: Pipe?
    
    private var requestId: Int = 0
    private var pendingRequests: [Int: CheckedContinuation<Data, Error>] = [:]
    
    @Published var isRunning = false
    @Published var serverCapabilities: ServerCapabilities?
    @Published var lastError: String?
    
    private let serverType: LanguageServer
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private var readTask: Task<Void, Never>?
    
    // Thread-safe cache for resolved binaries (stores Optional<String> so missing binaries are also cached)
    nonisolated(unsafe) private static var resolvedBinariesCache: [String: String?] = [:]
    nonisolated private static let cacheLock = NSLock()
    
    nonisolated static func getCachedBinaryLookup(for name: String) -> (foundInCache: Bool, path: String?) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let entry = resolvedBinariesCache[name] {
            return (true, entry)
        }
        return (false, nil)
    }
    
    nonisolated static func setCachedBinary(_ path: String?, for name: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        resolvedBinariesCache[name] = path
    }
    
    static func clearBinaryCache() {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        resolvedBinariesCache.removeAll()
    }
    
    static func resolveBinaryAsync(_ name: String, searchPaths: [String]) async -> String? {
        let lookup = getCachedBinaryLookup(for: name)
        if lookup.foundInCache {
            return lookup.path
        }
        
        let resolved = await Task.detached(priority: .utility) {
            LSPClientService.resolveBinary(name, searchPaths: searchPaths)
        }.value
        
        setCachedBinary(resolved, for: name)
        return resolved
    }
    
    // MARK: - Initialization
    
    init(serverType: LanguageServer) {
        self.serverType = serverType
    }
    
    deinit {
        // Cancel the read task synchronously
        readTask?.cancel()
        // Terminate process (Process.terminate() is safe to call)
        process?.terminate()
    }
    
    // MARK: - Server Lifecycle
    
    /// Start the language server process
    func start(rootUri: String) async throws {
        guard !isRunning else { return }
        
        // Find the server binary
        guard let serverPath = await findServerBinary() else {
            throw LSPError.serverNotFound(serverType.rawValue)
        }
        
        print("🚀 [LSP] Starting \(serverType.rawValue) at \(serverPath)")
        
        // Setup process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverPath)
        
        // Server-specific arguments
        switch serverType {
        case .pyright, .typescriptServer, .intelephense:
            process.arguments = ["--stdio"]
        case .dart:
            process.arguments = ["language-server", "--protocol=lsp"]
        case .solargraph:
            process.arguments = ["stdio"]
        case .sourcekitLSP:
            process.arguments = []
        default:
            process.arguments = []
        }
        
        // Setup pipes
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.isRunning = false
                let pending = self.pendingRequests
                self.pendingRequests.removeAll()
                for (_, continuation) in pending {
                    continuation.resume(throwing: LSPError.notConnected)
                }
                print("⚠️ [LSP] \(self.serverType.rawValue) terminated")
            }
        }
        
        // Start process
        try process.run()
        
        self.process = process
        self.stdin = stdinPipe
        self.stdout = stdoutPipe
        self.stderr = stderrPipe
        self.isRunning = true
        
        // Start reading responses
        startReadingResponses()
        
        // Monitor stderr (capture the pipe before entering detached task)
        let stderrHandle = stderrPipe.fileHandleForReading
        Task.detached {
            for try await line in stderrHandle.bytes.lines {
                print("[LSP stderr] \(line)")
            }
        }
        
        // Send initialize request
        let initResult = try await initialize(rootUri: rootUri)
        self.serverCapabilities = initResult.capabilities
        
        // Send initialized notification
        try await sendNotification(method: "initialized", params: EmptyParams())
        
        print("✅ [LSP] \(serverType.rawValue) initialized successfully")
    }
    
    /// Stop the language server
    func stop() {
        readTask?.cancel()
        readTask = nil
        
        process?.terminate()
        process = nil
        stdin = nil
        stdout = nil
        stderr = nil
        isRunning = false
        let pending = pendingRequests
        pendingRequests.removeAll()
        for (_, continuation) in pending {
            continuation.resume(throwing: LSPError.notConnected)
        }
    }
    
    // MARK: - Server Binary Detection
    
    private func findServerBinary() async -> String? {
        return await LSPClientService.resolveBinaryAsync(serverType.rawValue, searchPaths: serverType.searchPaths)
    }

    /// Resolve a language-server binary the user installed by ANY means.
    /// Uses `resolvedBinariesCache` so negative lookups never respawn shells.
    nonisolated static func resolveBinary(_ name: String, searchPaths: [String]) -> String? {
        let lookup = getCachedBinaryLookup(for: name)
        if lookup.foundInCache {
            return lookup.path
        }

        let fm = FileManager.default
        
        // For Apple toolchain servers (sourcekit-lsp, clangd), prefer `xcrun --find` first
        // so the server has full access to Xcode's macOS/iOS SDKs (SwiftUI, AppKit, Foundation)
        // even when Xcode resides on an external volume like /Volumes/MAC/Xcode.app.
        if (name == "sourcekit-lsp" || name == "clangd"), fm.isExecutableFile(atPath: "/usr/bin/xcrun") {
            let xc = Process()
            xc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            xc.arguments = ["--find", name]
            let pipe = Pipe(); xc.standardOutput = pipe; xc.standardError = Pipe()
            if (try? xc.run()) != nil {
                xc.waitUntilExit()
                if xc.terminationStatus == 0,
                   let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .split(separator: "\n").first.map(String.init)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !out.isEmpty,
                   fm.isExecutableFile(atPath: out) {
                    setCachedBinary(out, for: name)
                    return out
                }
            }
        }

        for path in searchPaths where fm.isExecutableFile(atPath: path) {
            setCachedBinary(path, for: name)
            return path
        }

        // Common version-manager / global bin locations (fast filesystem check before spawning shell).
        let home = fm.homeDirectoryForCurrentUser.path
        var dirs = [
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin",
            "\(home)/.cargo/bin", "\(home)/.local/bin", "\(home)/.deno/bin",
            "\(home)/.bun/bin", "\(home)/.volta/bin", "\(home)/.pyenv/shims",
            "\(home)/.asdf/shims", "\(home)/go/bin",
            "/opt/homebrew/opt/node/bin", "/usr/local/share/dotnet"
        ]
        if let v = try? fm.contentsOfDirectory(atPath: "\(home)/.nvm/versions/node") {
            for ver in v { dirs.append("\(home)/.nvm/versions/node/\(ver)/bin") }
        }
        for d in dirs {
            let cand = (d as NSString).appendingPathComponent(name)
            if fm.isExecutableFile(atPath: cand) {
                setCachedBinary(cand, for: name)
                return cand
            }
        }

        // Login shell fallback — picks up custom PATH / version managers
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        if fm.isExecutableFile(atPath: shell) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: shell)
            p.arguments = ["-l", "-c", "command -v \(name) 2>/dev/null"]
            let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
            if (try? p.run()) != nil {
                p.waitUntilExit()
                if let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .split(separator: "\n").first.map(String.init)?
                    .trimmingCharacters(in: .whitespaces), !out.isEmpty,
                   fm.isExecutableFile(atPath: out) {
                    setCachedBinary(out, for: name)
                    return out
                }
            }
        }

        setCachedBinary(nil, for: name)
        return nil
    }
    
    // MARK: - Response Reading
    
    private func startReadingResponses() {
        guard let stdout = self.stdout else { return }
        let handle = stdout.fileHandleForReading
        
        readTask = Task.detached(priority: .userInitiated) { [weak self] in
            var buffer = Data()
            
            while !Task.isCancelled {
                // Read available data (blocks on Unix pipe until bytes arrive or EOF)
                let newData = handle.availableData
                if newData.isEmpty {
                    // EOF reached (child process closed stdout) — exit loop instead of spinning
                    break
                }
                buffer.append(newData)
                
                // Parse messages from buffer
                while let message = LSPClientService.extractMessage(from: &buffer) {
                    guard let self = self else { break }
                    await self.handleIncomingMessage(message)
                }
            }
        }
    }
    
    private func handleIncomingMessage(_ message: Data) async {
        await handleMessage(message)
    }
    
    // Non-isolated helper so it can be called from background thread
    nonisolated static func extractMessage(from buffer: inout Data) -> Data? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }
        
        let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8) else {
            buffer.removeSubrange(0..<headerEnd.upperBound)
            return nil
        }
        
        var parsedLength: Int?
        for line in headerString.components(separatedBy: "\r\n") {
            let lower = line.lowercased()
            if lower.hasPrefix("content-length:") {
                let valStr = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                parsedLength = Int(valStr)
                break
            }
        }
        guard let contentLength = parsedLength, contentLength >= 0 else {
            buffer.removeSubrange(0..<headerEnd.upperBound)
            return nil
        }
        
        let contentStart = headerEnd.upperBound
        let contentEnd = contentStart + contentLength
        
        guard buffer.count >= contentEnd else {
            return nil
        }
        
        let content = buffer.subdata(in: contentStart..<contentEnd)
        buffer.removeSubrange(0..<contentEnd)
        
        return content
    }
    
    private func handleMessage(_ data: Data) async {
        // Try to decode as response with ID
        if let responseWrapper = try? decoder.decode(JSONRPCResponse<LSPAnyCodable>.self, from: data),
           let id = responseWrapper.id,
           let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(returning: data)
            return
        }
        
        // Handle notifications (diagnostics, etc.)
        if let method = try? getMethod(from: data) {
            if method == "textDocument/publishDiagnostics" {
                if let notification = try? decoder.decode(JSONRPCNotification<PublishDiagnosticsParams>.self, from: data),
                   let params = notification.params {
                    // Propagate to LSPManager -> UI
                    Task { @MainActor in
                        LSPManager.shared.fileDiagnostics[params.uri] = params.diagnostics
                    }
                }
            }
        }
    }
    
    private func getMethod(from data: Data) throws -> String? {
        struct MethodOnly: Decodable { let method: String }
        return try? decoder.decode(MethodOnly.self, from: data).method
    }
    
    // MARK: - Request/Response
    
    private struct CancelParams: Codable {
        let id: Int
    }
    
    private func cancelPendingRequest(id: Int) {
        if let continuation = pendingRequests.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
            Task { [weak self] in
                try? await self?.sendNotification(method: "$/cancelRequest", params: CancelParams(id: id))
            }
        }
    }
    
    private func sendRawRequest<P: Encodable>(method: String, params: P) async throws -> Data {
        let id = nextRequestId()
        let request = JSONRPCRequest(id: id, method: method, params: params)
        
        let requestData = try await Task.detached(priority: .userInitiated) {
            let encoder = JSONEncoder()
            return try encoder.encode(request)
        }.value
        
        try await sendMessage(requestData)
        
        let timeoutNanoseconds: UInt64 = (method == "initialize") ? 15_000_000_000 : 5_000_000_000
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard !Task.isCancelled else { return }
            if let continuation = self?.pendingRequests.removeValue(forKey: id) {
                continuation.resume(throwing: LSPError.noResult)
            }
        }
        defer { timeoutTask.cancel() }
        
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    pendingRequests[id] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelPendingRequest(id: id)
            }
        }
    }

    private func sendRequest<P: Encodable, R: Decodable>(method: String, params: P) async throws -> R {
        let responseData = try await sendRawRequest(method: method, params: params)
        
        let response = try await Task.detached(priority: .userInitiated) {
            let decoder = JSONDecoder()
            return try decoder.decode(JSONRPCResponse<R>.self, from: responseData)
        }.value
        
        if let error = response.error {
            throw LSPError.serverError(error.code, error.message)
        }
        
        guard let result = response.result else {
            throw LSPError.noResult
        }
        
        return result
    }
    
    private func sendNotification<P: Codable>(method: String, params: P) async throws {
        let notification = JSONRPCNotification(method: method, params: params)
        
        let data = try await Task.detached(priority: .userInitiated) {
            let encoder = JSONEncoder()
            return try encoder.encode(notification)
        }.value
        
        try await sendMessage(data)
    }
    
    private func sendMessage(_ data: Data) async throws {
        guard let stdin = stdin else {
            throw LSPError.notConnected
        }
        
        let header = "\(LSPMessage.contentLengthHeader)\(data.count)\(LSPMessage.headerTerminator)"
        guard let headerData = header.data(using: .utf8) else {
            throw LSPError.encodingError
        }
        
        let fileHandle = stdin.fileHandleForWriting
        
        // Perform I/O on a background thread to avoid blocking the Main Actor
        try await Task.detached(priority: .userInitiated) {
            try fileHandle.write(contentsOf: headerData)
            try fileHandle.write(contentsOf: data)
        }.value
    }
    
    private func nextRequestId() -> Int {
        requestId += 1
        return requestId
    }
    
    // MARK: - LSP Protocol Methods
    
    /// Initialize the server
    private func initialize(rootUri: String) async throws -> InitializeResult {
        let params = InitializeParams(
            processId: Int(ProcessInfo.processInfo.processIdentifier),
            rootUri: rootUri,
            capabilities: ClientCapabilities(
                textDocument: TextDocumentClientCapabilities(
                    completion: CompletionClientCapabilities(
                        completionItem: CompletionItemCapabilities(
                            snippetSupport: true,
                            documentationFormat: ["markdown", "plaintext"]
                        )
                    ),
                    hover: HoverClientCapabilities(
                        contentFormat: ["markdown", "plaintext"]
                    ),
                    definition: DefinitionClientCapabilities(
                        linkSupport: true
                    )
                )
            )
        )
        
        return try await sendRequest(method: "initialize", params: params)
    }
    
    /// Notify server that a document was opened
    func didOpen(uri: String, languageId: String, version: Int, text: String) async throws {
        let params = DidOpenTextDocumentParams(
            textDocument: TextDocumentItem(
                uri: uri,
                languageId: languageId,
                version: version,
                text: text
            )
        )
        try await sendNotification(method: "textDocument/didOpen", params: params)
    }
    
    /// Notify server that a document changed
    func didChange(uri: String, version: Int, text: String) async throws {
        let params = DidChangeTextDocumentParams(
            textDocument: VersionedTextDocumentIdentifier(uri: uri, version: version),
            contentChanges: [TextDocumentContentChangeEvent(text: text)]
        )
        try await sendNotification(method: "textDocument/didChange", params: params)
    }
    
    /// Request completions at a position (single RPC call, supports both CompletionList and [CompletionItem])
    func completion(uri: String, line: Int, character: Int, triggerCharacter: String? = nil) async throws -> [CompletionItem] {
        let context: CompletionContext?
        if let trig = triggerCharacter, !trig.isEmpty {
            context = CompletionContext(triggerKind: 2, triggerCharacter: trig)
        } else {
            context = CompletionContext(triggerKind: 1, triggerCharacter: nil)
        }
        let params = CompletionParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: LSPPosition(line: line, character: character),
            context: context
        )
        
        let responseData = try await sendRawRequest(method: "textDocument/completion", params: params)
        return try await Task.detached(priority: .userInitiated) {
            let decoder = JSONDecoder()
            if let listResp = try? decoder.decode(JSONRPCResponse<CompletionList>.self, from: responseData) {
                if let error = listResp.error { throw LSPError.serverError(error.code, error.message) }
                if let result = listResp.result { return result.items }
            }
            let arrResp = try decoder.decode(JSONRPCResponse<[CompletionItem]>.self, from: responseData)
            if let error = arrResp.error { throw LSPError.serverError(error.code, error.message) }
            return arrResp.result ?? []
        }.value
    }
    
    /// Request hover information
    func hover(uri: String, line: Int, character: Int) async throws -> HoverResult? {
        let params = HoverParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: LSPPosition(line: line, character: character)
        )
        
        return try await sendRequest(method: "textDocument/hover", params: params)
    }
    
    /// Request go-to-definition (single RPC call, supports both [LSPLocation] and LSPLocation)
    func definition(uri: String, line: Int, character: Int) async throws -> [LSPLocation] {
        let params = DefinitionParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: LSPPosition(line: line, character: character)
        )
        
        let responseData = try await sendRawRequest(method: "textDocument/definition", params: params)
        return try await Task.detached(priority: .userInitiated) {
            let decoder = JSONDecoder()
            if let arrResp = try? decoder.decode(JSONRPCResponse<[LSPLocation]>.self, from: responseData) {
                if let error = arrResp.error { throw LSPError.serverError(error.code, error.message) }
                if let result = arrResp.result { return result }
            }
            if let singleResp = try? decoder.decode(JSONRPCResponse<LSPLocation>.self, from: responseData) {
                if let error = singleResp.error { throw LSPError.serverError(error.code, error.message) }
                if let result = singleResp.result { return [result] }
            }
            return []
        }.value
    }
}

// MARK: - Helper Types

struct EmptyParams: Codable {}

struct LSPAnyCodable: Codable {
    init(from decoder: Decoder) throws {
        // Just consume the data
    }
    
    func encode(to encoder: Encoder) throws {
        // Empty
    }
}

// MARK: - Errors

enum LSPError: LocalizedError {
    case serverNotFound(String)
    case notConnected
    case encodingError
    case serverError(Int, String)
    case noResult
    
    var errorDescription: String? {
        switch self {
        case .serverNotFound(let name):
            return "Language server '\(name)' not found. Please install it."
        case .notConnected:
            return "Not connected to language server"
        case .encodingError:
            return "Failed to encode message"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .noResult:
            return "No result from server"
        }
    }
}
