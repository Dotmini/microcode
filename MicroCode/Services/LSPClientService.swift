//
//  LSPClientService.swift
//  MicroCode - Language Server Protocol Client
//
//  Generic LSP client that can connect to any language server.
//  Supports: rust-analyzer, pyright, sourcekit-lsp, gopls, clangd
//
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
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

struct CompletionParams: Codable {
    let textDocument: TextDocumentIdentifier
    let position: LSPPosition
}

struct CompletionList: Codable {
    let isIncomplete: Bool
    let items: [CompletionItem]
}

struct CompletionItem: Codable, Identifiable {
    var id: String { label }
    let label: String
    let kind: Int?
    let detail: String?
    let documentation: String?
    let insertText: String?
    let insertTextFormat: Int?
}

extension CompletionItem {
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
        default: return "Unknown"
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
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin"
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
        guard let serverPath = findServerBinary() else {
            throw LSPError.serverNotFound(serverType.rawValue)
        }
        
        print("🚀 [LSP] Starting \(serverType.rawValue) at \(serverPath)")
        
        // Setup process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: serverPath)
        
        // Server-specific arguments
        switch serverType {
        case .pyright:
            process.arguments = ["--stdio"]
        case .typescriptServer:
            process.arguments = ["--stdio"]
        case .sourcekitLSP:
            // sourcekit-lsp uses stdio by default, but we can be explicit or add logging if needed
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
                self?.isRunning = false
                print("⚠️ [LSP] \(self?.serverType.rawValue ?? "Unknown") terminated")
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
        pendingRequests.removeAll()
    }
    
    // MARK: - Server Binary Detection
    
    private func findServerBinary() -> String? {
        for path in serverType.searchPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        
        // Try `which` command
        let whichProcess = Process()
        whichProcess.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        whichProcess.arguments = [serverType.rawValue]
        let pipe = Pipe()
        whichProcess.standardOutput = pipe
        
        do {
            try whichProcess.run()
            whichProcess.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                return path
            }
        } catch {}
        
        return nil
    }
    
    // MARK: - Response Reading
    
    private func startReadingResponses() {
        readTask = Task { [weak self] in
            guard let self = self, let stdout = self.stdout else { return }
            
            let handle = stdout.fileHandleForReading
            var buffer = Data()
            
            while !Task.isCancelled {
                do {
                    // Read available data
                    let newData = handle.availableData
                    if newData.isEmpty {
                        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                        continue
                    }
                    buffer.append(newData)
                    
                    // Parse messages from buffer
                    while let message = await self.extractMessage(from: &buffer) {
                        await self.handleMessage(message)
                    }
                } catch {
                    break
                }
            }
        }
    }
    
    private func extractMessage(from buffer: inout Data) async -> Data? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }
        
        let headerData = buffer.subdata(in: 0..<headerEnd.lowerBound)
        guard let headerString = String(data: headerData, encoding: .utf8),
              headerString.hasPrefix(LSPMessage.contentLengthHeader),
              let contentLength = Int(headerString.dropFirst(LSPMessage.contentLengthHeader.count).trimmingCharacters(in: .whitespaces)) else {
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
                    print("✅ [LSP] Diagnostics for \(params.uri): \(params.diagnostics.count) items")
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
    
    private func sendRequest<P: Encodable, R: Decodable>(method: String, params: P) async throws -> R {
        let id = nextRequestId()
        let request = JSONRPCRequest(id: id, method: method, params: params)
        
        let requestData = try encoder.encode(request)
        try sendMessage(requestData)
        
        // Wait for response
        let responseData = try await withCheckedThrowingContinuation { continuation in
            pendingRequests[id] = continuation
        }
        
        let response = try decoder.decode(JSONRPCResponse<R>.self, from: responseData)
        
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
        let data = try encoder.encode(notification)
        try sendMessage(data)
    }
    
    private func sendMessage(_ data: Data) throws {
        guard let stdin = stdin else {
            throw LSPError.notConnected
        }
        
        let header = "\(LSPMessage.contentLengthHeader)\(data.count)\(LSPMessage.headerTerminator)"
        guard let headerData = header.data(using: .utf8) else {
            throw LSPError.encodingError
        }
        
        let fileHandle = stdin.fileHandleForWriting
        try fileHandle.write(contentsOf: headerData)
        try fileHandle.write(contentsOf: data)
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
    
    /// Request completions at a position
    func completion(uri: String, line: Int, character: Int) async throws -> [CompletionItem] {
        let params = CompletionParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: LSPPosition(line: line, character: character)
        )
        
        // Response can be either CompletionList or [CompletionItem]
        do {
            let result: CompletionList = try await sendRequest(method: "textDocument/completion", params: params)
            return result.items
        } catch {
            // Try as array
            let items: [CompletionItem] = try await sendRequest(method: "textDocument/completion", params: params)
            return items
        }
    }
    
    /// Request hover information
    func hover(uri: String, line: Int, character: Int) async throws -> HoverResult? {
        let params = HoverParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: LSPPosition(line: line, character: character)
        )
        
        return try await sendRequest(method: "textDocument/hover", params: params)
    }
    
    /// Request go-to-definition
    func definition(uri: String, line: Int, character: Int) async throws -> [LSPLocation] {
        let params = DefinitionParams(
            textDocument: TextDocumentIdentifier(uri: uri),
            position: LSPPosition(line: line, character: character)
        )
        
        // Response can be Location, [Location], or null
        do {
            let locations: [LSPLocation] = try await sendRequest(method: "textDocument/definition", params: params)
            return locations
        } catch {
            // Try as single location
            let location: LSPLocation = try await sendRequest(method: "textDocument/definition", params: params)
            return [location]
        }
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
