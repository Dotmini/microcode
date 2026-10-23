// Copyright © 2025 Dotmini Software. All rights reserved.

import Foundation
import SwiftUI
import Combine

enum ErrorStatus: String, Codable, Equatable {
    case new
    case analyzing
    case explained
    case fixed
    case dismissed
}

public struct DAPStackFrame: Identifiable, Equatable {
    public let id: Int
    public let name: String
    public let sourcePath: String?
    public let line: Int
    public let column: Int
}

public struct DAPVariable: Identifiable, Equatable {
    public var id: String { "\(name)=\(value)" }
    public let name: String
    public let value: String
    public let type: String
}

public enum DebugSessionState: Equatable {
    case idle
    case compiling(target: String)
    case launching
    case running
    case paused(reason: String, file: String?, line: Int?, threadId: Int)
    case terminated(exitCode: Int?)
    
    public var isActive: Bool {
        switch self {
        case .idle, .terminated: return false
        case .compiling, .launching, .running, .paused: return true
        }
    }
    
    public var isPaused: Bool {
        if case .paused = self { return true }
        return false
    }
    
    public var statusText: String {
        switch self {
        case .idle: return "Idle"
        case .compiling(let t): return "Compiling \(t) (-g)…"
        case .launching: return "Starting lldb-dap…"
        case .running: return "Running"
        case .paused(let reason, _, let line, _):
            if let l = line { return "Paused (\(reason) @ L\(l))" }
            return "Paused (\(reason))"
        case .terminated(let code):
            if let c = code { return "Terminated (exit \(c))" }
            return "Terminated"
        }
    }
}

struct StackFrame: Identifiable, Equatable {
    let id = UUID()
    let functionName: String
    let filePath: String?
    let lineNumber: Int?
    let columnNumber: Int?
    let isUserCode: Bool
    
    static func == (lhs: StackFrame, rhs: StackFrame) -> Bool {
        lhs.id == rhs.id
    }
}

struct SuggestedFix: Equatable {
    let description: String
    let filePath: String
    let oldCode: String
    let newCode: String
    let confidence: Double
}

struct RuntimeError: Identifiable, Equatable {
    let id: UUID
    let language: String
    let errorType: String
    let message: String
    let stackTrace: [StackFrame]
    let rawOutput: String
    let timestamp: Date
    var aiExplanation: String?
    var suggestedFix: SuggestedFix?
    var status: ErrorStatus
    
    init(id: UUID = UUID(), language: String, errorType: String, message: String, stackTrace: [StackFrame], rawOutput: String, timestamp: Date = Date(), aiExplanation: String? = nil, suggestedFix: SuggestedFix? = nil, status: ErrorStatus = .new) {
        self.id = id
        self.language = language
        self.errorType = errorType
        self.message = message
        self.stackTrace = stackTrace
        self.rawOutput = rawOutput
        self.timestamp = timestamp
        self.aiExplanation = aiExplanation
        self.suggestedFix = suggestedFix
        self.status = status
    }
    
    static func == (lhs: RuntimeError, rhs: RuntimeError) -> Bool {
        lhs.id == rhs.id && lhs.status == rhs.status
    }
}

@MainActor
class DebugService: ObservableObject {
    static let shared = DebugService()
    static let breakpointsDidChangeNotification = Notification.Name("MicroCodeBreakpointsDidChange")
    
    @Published var errors: [RuntimeError] = []
    @Published var currentError: RuntimeError?
    @Published var isAnalyzing: Bool = false
    
    // MARK: - Interactive DAP / LLDB State
    @Published var breakpoints: [String: Set<Int>] = [:]
    @Published var sessionState: DebugSessionState = .idle
    @Published var callStack: [DAPStackFrame] = []
    @Published var localVariables: [DAPVariable] = []
    @Published var debugConsoleOutput: String = ""
    @Published var activeThreadId: Int = 1
    
    private var dapProcess: Process?
    private var dapStdin: FileHandle?
    private var dapSeq: Int = 1
    private var dapReadBuffer = Data()
    private var pendingDAPCallbacks: [Int: ([String: Any]) -> Void] = [:]
    private var compiledDebugBinaryURL: URL?
    
    private init() {
        loadPersistedBreakpoints()
    }
    
    // MARK: - Breakpoint Management
    
    private func normalizePath(_ filePath: String) -> String {
        URL(fileURLWithPath: (filePath as NSString).expandingTildeInPath).standardizedFileURL.path
    }
    
    func breakpoints(for filePath: String) -> Set<Int> {
        let key = normalizePath(filePath)
        return breakpoints[key] ?? []
    }
    
    func hasBreakpoint(file: String, line: Int) -> Bool {
        breakpoints(for: file).contains(line)
    }
    
    func toggleBreakpoint(file: String, line: Int) {
        let key = normalizePath(file)
        var set = breakpoints[key] ?? []
        if set.contains(line) {
            set.remove(line)
        } else {
            set.insert(line)
        }
        if set.isEmpty {
            breakpoints.removeValue(forKey: key)
        } else {
            breakpoints[key] = set
        }
        persistBreakpoints()
        NotificationCenter.default.post(name: Self.breakpointsDidChangeNotification, object: nil, userInfo: ["file": key, "line": line])
        if sessionState.isActive {
            sendSetBreakpoints(for: key)
        }
    }
    
    func clearAllBreakpoints() {
        let keys = Array(breakpoints.keys)
        breakpoints.removeAll()
        persistBreakpoints()
        for k in keys {
            if sessionState.isActive {
                sendSetBreakpoints(for: k)
            }
        }
        NotificationCenter.default.post(name: Self.breakpointsDidChangeNotification, object: nil)
    }
    
    private func persistBreakpoints() {
        let serializable = breakpoints.mapValues { Array($0).sorted() }
        UserDefaults.standard.set(serializable, forKey: "MicroCode.Debugger.Breakpoints")
    }
    
    private func loadPersistedBreakpoints() {
        if let saved = UserDefaults.standard.dictionary(forKey: "MicroCode.Debugger.Breakpoints") as? [String: [Int]] {
            breakpoints = saved.mapValues { Set($0) }
        }
    }
    
    // MARK: - Native LLDB-DAP Interactive Debugger
    
    func startDebugSession(filePath: String, workspacePath: String? = nil) async {
        stopDebugSession()
        debugConsoleOutput = ""
        callStack.removeAll()
        localVariables.removeAll()
        
        let normalizedSource = normalizePath(filePath)
        let ext = (normalizedSource as NSString).pathExtension.lowercased()
        let targetName = (normalizedSource as NSString).lastPathComponent
        sessionState = .compiling(target: targetName)
        appendDebugLog("⚙️ Preparing debug target for \(targetName)…\n")
        
        guard let binaryURL = await buildDebugBinaryIfNeeded(sourcePath: normalizedSource, ext: ext, workspacePath: workspacePath) else {
            sessionState = .idle
            return
        }
        compiledDebugBinaryURL = binaryURL
        
        sessionState = .launching
        appendDebugLog("🚀 Launching xcrun lldb-dap for \(binaryURL.path)…\n")
        
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        proc.arguments = ["lldb-dap"]
        if let ws = workspacePath, !ws.isEmpty {
            proc.currentDirectoryURL = URL(fileURLWithPath: ws)
        } else {
            proc.currentDirectoryURL = binaryURL.deletingLastPathComponent()
        }
        
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        
        dapReadBuffer.removeAll(keepingCapacity: false)
        dapSeq = 1
        pendingDAPCallbacks.removeAll()
        
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consumeDAPStdout(data)
            }
        }
        
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor [weak self] in
                self?.appendDebugLog(text)
            }
        }
        
        proc.terminationHandler = { [weak self] p in
            Task { @MainActor [weak self] in
                guard let self else { return }
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                if self.sessionState.isActive {
                    self.sessionState = .terminated(exitCode: Int(p.terminationStatus))
                }
                NotificationCenter.default.post(name: Self.breakpointsDidChangeNotification, object: nil)
            }
        }
        
        do {
            try proc.run()
            self.dapProcess = proc
            self.dapStdin = inPipe.fileHandleForWriting
        } catch {
            appendDebugLog("❌ Failed to launch lldb-dap: \(error.localizedDescription)\n")
            sessionState = .idle
            return
        }
        
        // 1. Send DAP `initialize`
        sendDAPRequest(command: "initialize", arguments: [
            "clientID": "microcode",
            "clientName": "MicroCode Native IDE",
            "adapterID": "lldb-dap",
            "pathFormat": "path",
            "linesStartAt1": true,
            "columnsStartAt1": true,
            "supportsVariableType": true
        ]) { [weak self] _ in
            guard let self else { return }
            // 2. Send `launch`
            let cwd = workspacePath ?? binaryURL.deletingLastPathComponent().path
            self.sendDAPRequest(command: "launch", arguments: [
                "program": binaryURL.path,
                "cwd": cwd,
                "stopOnEntry": self.breakpoints.isEmpty
            ]) { [weak self] _ in
                guard let self else { return }
                // 3. Register all breakpoints
                for fileKey in self.breakpoints.keys {
                    self.sendSetBreakpoints(for: fileKey)
                }
                // 4. Send `configurationDone`
                self.sendDAPRequest(command: "configurationDone", arguments: nil) { [weak self] _ in
                    guard let self else { return }
                    if case .launching = self.sessionState {
                        self.sessionState = .running
                    }
                }
            }
        }
    }
    
    private func buildDebugBinaryIfNeeded(sourcePath: String, ext: String, workspacePath: String?) async -> URL? {
        let tempBin = FileManager.default.temporaryDirectory.appendingPathComponent("microcode_debug_\(UUID().uuidString.prefix(8))")
        
        let (compiler, args): (String, [String])
        switch ext {
        case "swift":
            compiler = "/usr/bin/xcrun"
            args = ["swiftc", "-g", "-Onone", sourcePath, "-o", tempBin.path]
        case "c":
            compiler = "/usr/bin/clang"
            args = ["-g", "-O0", sourcePath, "-o", tempBin.path]
        case "cpp", "cc", "cxx", "mm":
            compiler = "/usr/bin/clang++"
            args = ["-std=c++20", "-g", "-O0", sourcePath, "-o", tempBin.path]
        case "rs":
            compiler = "/usr/bin/env"
            args = ["rustc", "-g", sourcePath, "-o", tempBin.path]
        default:
            // Check if sourcePath itself is already an executable binary
            if FileManager.default.isExecutableFile(atPath: sourcePath) {
                return URL(fileURLWithPath: sourcePath)
            }
            appendDebugLog("⚠️ Native LLDB debugging supports Swift, C, C++, Objective-C++, Rust, or compiled Mach-O binaries. Current file: \(ext)\n")
            return nil
        }
        
        let result: (exitCode: Int32, output: String) = await Task.detached(priority: .userInitiated) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: compiler)
            p.arguments = args
            if let ws = workspacePath {
                p.currentDirectoryURL = URL(fileURLWithPath: ws)
            }
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = pipe
            do {
                try p.run()
                p.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let out = String(data: data, encoding: .utf8) ?? ""
                return (p.terminationStatus, out)
            } catch {
                return (-1, error.localizedDescription)
            }
        }.value
        
        if !result.output.isEmpty {
            appendDebugLog(result.output + "\n")
        }
        guard result.exitCode == 0, FileManager.default.fileExists(atPath: tempBin.path) else {
            appendDebugLog("❌ Debug build failed (exit \(result.exitCode)).\n")
            return nil
        }
        return tempBin
    }
    
    func sendSetBreakpoints(for filePath: String) {
        let lines = Array(breakpoints[filePath] ?? []).sorted()
        let bpObjects = lines.map { ["line": $0] }
        sendDAPRequest(command: "setBreakpoints", arguments: [
            "source": ["path": filePath],
            "breakpoints": bpObjects
        ])
    }
    
    func continueExecution() {
        guard sessionState.isPaused else { return }
        sessionState = .running
        NotificationCenter.default.post(name: Self.breakpointsDidChangeNotification, object: nil)
        sendDAPRequest(command: "continue", arguments: ["threadId": activeThreadId])
    }
    
    func stepOver() {
        guard sessionState.isPaused else { return }
        sendDAPRequest(command: "next", arguments: ["threadId": activeThreadId])
    }
    
    func stepInto() {
        guard sessionState.isPaused else { return }
        sendDAPRequest(command: "stepIn", arguments: ["threadId": activeThreadId])
    }
    
    func stepOut() {
        guard sessionState.isPaused else { return }
        sendDAPRequest(command: "stepOut", arguments: ["threadId": activeThreadId])
    }
    
    func stopDebugSession() {
        if let proc = dapProcess, proc.isRunning {
            sendDAPRequest(command: "disconnect", arguments: ["terminateDebuggee": true])
            proc.terminate()
        }
        dapProcess = nil
        dapStdin = nil
        pendingDAPCallbacks.removeAll()
        if let temp = compiledDebugBinaryURL, temp.path.contains("microcode_debug_") {
            try? FileManager.default.removeItem(at: temp)
        }
        compiledDebugBinaryURL = nil
        if sessionState.isActive {
            sessionState = .idle
        }
        callStack.removeAll()
        localVariables.removeAll()
        NotificationCenter.default.post(name: Self.breakpointsDidChangeNotification, object: nil)
    }
    
    private func sendDAPRequest(command: String, arguments: [String: Any]?, completion: (([String: Any]) -> Void)? = nil) {
        guard let stdin = dapStdin else { return }
        let seq = dapSeq
        dapSeq += 1
        var payload: [String: Any] = [
            "seq": seq,
            "type": "request",
            "command": command
        ]
        if let arguments {
            payload["arguments"] = arguments
        }
        if let completion {
            pendingDAPCallbacks[seq] = completion
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload),
              let headerData = "Content-Length: \(jsonData.count)\r\n\r\n".data(using: .utf8) else { return }
        try? stdin.write(contentsOf: headerData)
        try? stdin.write(contentsOf: jsonData)
    }
    
    private func consumeDAPStdout(_ chunk: Data) {
        dapReadBuffer.append(chunk)
        let separator = Data("\r\n\r\n".utf8)
        while let headerRange = dapReadBuffer.range(of: separator) {
            let headerData = dapReadBuffer.subdata(in: 0..<headerRange.lowerBound)
            guard let headerStr = String(data: headerData, encoding: .utf8) else {
                dapReadBuffer.removeAll()
                break
            }
            var contentLength = 0
            for line in headerStr.components(separatedBy: "\r\n") {
                if line.lowercased().hasPrefix("content-length:") {
                    let val = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                    contentLength = Int(val) ?? 0
                }
            }
            let bodyStart = headerRange.upperBound
            guard contentLength > 0, dapReadBuffer.count >= bodyStart + contentLength else {
                break
            }
            let bodyData = dapReadBuffer.subdata(in: bodyStart..<(bodyStart + contentLength))
            dapReadBuffer.removeSubrange(0..<(bodyStart + contentLength))
            if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                handleDAPMessage(json)
            }
        }
    }
    
    private func handleDAPMessage(_ msg: [String: Any]) {
        let type = msg["type"] as? String ?? ""
        if type == "response" {
            if let reqSeq = msg["request_seq"] as? Int,
               let cb = pendingDAPCallbacks.removeValue(forKey: reqSeq) {
                cb(msg)
            }
        } else if type == "event" {
            let event = msg["event"] as? String ?? ""
            let body = msg["body"] as? [String: Any] ?? [:]
            switch event {
            case "output":
                if let output = body["output"] as? String {
                    appendDebugLog(output)
                }
            case "stopped":
                let reason = body["reason"] as? String ?? "breakpoint"
                let threadId = body["threadId"] as? Int ?? 1
                self.activeThreadId = threadId
                fetchStackTraceAndVariables(threadId: threadId, reason: reason)
            case "continued":
                self.sessionState = .running
                NotificationCenter.default.post(name: Self.breakpointsDidChangeNotification, object: nil)
            case "terminated", "exited":
                let code = body["exitCode"] as? Int
                self.sessionState = .terminated(exitCode: code)
                NotificationCenter.default.post(name: Self.breakpointsDidChangeNotification, object: nil)
            default:
                break
            }
        }
    }
    
    private func fetchStackTraceAndVariables(threadId: Int, reason: String) {
        sendDAPRequest(command: "stackTrace", arguments: [
            "threadId": threadId,
            "startFrame": 0,
            "levels": 20
        ]) { [weak self] resp in
            guard let self else { return }
            let body = resp["body"] as? [String: Any] ?? [:]
            let rawFrames = body["stackFrames"] as? [[String: Any]] ?? []
            var parsedFrames: [DAPStackFrame] = []
            for f in rawFrames {
                let id = f["id"] as? Int ?? 0
                let name = f["name"] as? String ?? "<frame>"
                let line = f["line"] as? Int ?? 0
                let col = f["column"] as? Int ?? 0
                let source = f["source"] as? [String: Any]
                let path = source?["path"] as? String
                parsedFrames.append(DAPStackFrame(id: id, name: name, sourcePath: path, line: line, column: col))
            }
            self.callStack = parsedFrames
            let topUserFrame = parsedFrames.first(where: { $0.sourcePath != nil && $0.line > 0 }) ?? parsedFrames.first
            self.sessionState = .paused(
                reason: reason,
                file: topUserFrame?.sourcePath.map { self.normalizePath($0) },
                line: topUserFrame?.line,
                threadId: threadId
            )
            NotificationCenter.default.post(name: Self.breakpointsDidChangeNotification, object: nil)
            
            if let top = topUserFrame, let line = top.line as Int?, line > 0 {
                NotificationCenter.default.post(
                    name: Notification.Name("JumpToLineNotification"),
                    object: nil,
                    userInfo: ["line": line, "column": max(1, top.column)]
                )
            }
            
            if let frameId = topUserFrame?.id {
                self.fetchVariables(forFrameId: frameId)
            }
        }
    }
    
    func fetchVariables(forFrameId frameId: Int) {
        sendDAPRequest(command: "scopes", arguments: ["frameId": frameId]) { [weak self] resp in
            guard let self else { return }
            let body = resp["body"] as? [String: Any] ?? [:]
            let scopes = body["scopes"] as? [[String: Any]] ?? []
            guard let localScope = scopes.first(where: { ($0["name"] as? String)?.lowercased().contains("local") == true }) ?? scopes.first,
                  let varRef = localScope["variablesReference"] as? Int, varRef > 0 else {
                self.localVariables = []
                return
            }
            self.sendDAPRequest(command: "variables", arguments: ["variablesReference": varRef]) { [weak self] varResp in
                guard let self else { return }
                let vBody = varResp["body"] as? [String: Any] ?? [:]
                let rawVars = vBody["variables"] as? [[String: Any]] ?? []
                self.localVariables = rawVars.compactMap { v in
                    guard let name = v["name"] as? String else { return nil }
                    let val = v["value"] as? String ?? ""
                    let type = v["type"] as? String ?? ""
                    return DAPVariable(name: name, value: val, type: type)
                }
            }
        }
    }
    
    private func appendDebugLog(_ text: String) {
        debugConsoleOutput += text
        if debugConsoleOutput.count > 64_000 {
            debugConsoleOutput = String(debugConsoleOutput.suffix(48_000))
        }
    }
    
    func parseErrorOutput(_ output: String, language: String) -> RuntimeError? {
        let lines = output.components(separatedBy: .newlines)
        
        switch language.lowercased() {
        case "python":
            return parsePythonError(output, lines: lines)
        case "javascript", "typescript", "node":
            return parseNodeError(output, lines: lines)
        case "rust":
            return parseRustError(output, lines: lines)
        case "swift":
            return parseSwiftError(output, lines: lines)
        case "go":
            return parseGoError(output, lines: lines)
        case "java":
            return parseJavaError(output, lines: lines)
        default:
            return parseGenericError(output, lines: lines, language: language)
        }
    }
    
    func analyzeError(_ error: RuntimeError) async {
        guard let index = errors.firstIndex(where: { $0.id == error.id }) else { return }
        
        isAnalyzing = true
        errors[index].status = .analyzing
        if currentError?.id == error.id {
            currentError?.status = .analyzing
        }
        
        let prompt = """
        Analyze this \(error.language) runtime error.
        
        Error Type: \(error.errorType)
        Message: \(error.message)
        
        Stack Trace:
        \(error.stackTrace.map { "\($0.functionName) at \($0.filePath ?? "unknown"):\($0.lineNumber ?? 0)" }.joined(separator: "\n"))
        
        Raw Output:
        \(error.rawOutput)
        
        Provide a plain-English explanation, identify the root cause, and at the end return a ```json fenced block with a 'fix' object containing 'description', 'oldCode', 'newCode', 'filePath', and 'confidence' (0.0 to 1.0).
        """
        
        do {
            let response = try await AIClient.shared.generateText(prompt: prompt)
            let (explanation, parsedFix) = Self.extractExplanationAndFix(from: response, fallbackFilePath: error.stackTrace.first(where: { $0.filePath != nil })?.filePath)
            
            errors[index].aiExplanation = explanation
            errors[index].suggestedFix = parsedFix
            errors[index].status = .explained
            if currentError?.id == error.id {
                currentError?.aiExplanation = explanation
                currentError?.suggestedFix = parsedFix
                currentError?.status = .explained
            }
        } catch let catchError {
            print("Error analyzing: \(catchError)")
            errors[index].status = .new
            if currentError?.id == error.id {
                currentError?.status = .new
            }
        }
        
        isAnalyzing = false
    }
    
    private static func extractExplanationAndFix(from response: String, fallbackFilePath: String?) -> (String, SuggestedFix?) {
        var jsonCandidate: String?
        var cleanExplanation = response
        
        if let fenceStart = response.range(of: "```json"),
           let fenceEnd = response.range(of: "```", range: fenceStart.upperBound..<response.endIndex) {
            jsonCandidate = String(response[fenceStart.upperBound..<fenceEnd.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            cleanExplanation.removeSubrange(fenceStart.lowerBound..<fenceEnd.upperBound)
            cleanExplanation = cleanExplanation.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let firstBrace = response.firstIndex(of: "{"),
                  let lastBrace = response.lastIndex(of: "}"),
                  firstBrace < lastBrace {
            jsonCandidate = String(response[firstBrace...lastBrace])
        }
        
        guard let jsonStr = jsonCandidate,
              let data = jsonStr.data(using: .utf8),
              let rootObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (response, nil)
        }
        
        let fixDict = (rootObj["fix"] as? [String: Any]) ?? rootObj
        guard let oldCode = fixDict["oldCode"] as? String,
              let newCode = fixDict["newCode"] as? String,
              !oldCode.isEmpty else {
            return (cleanExplanation.isEmpty ? response : cleanExplanation, nil)
        }
        
        let description = (fixDict["description"] as? String) ?? "AI suggested fix"
        let filePath = (fixDict["filePath"] as? String).flatMap({ $0.isEmpty ? nil : $0 }) ?? fallbackFilePath ?? ""
        let confidence = (fixDict["confidence"] as? Double) ?? 0.85
        
        guard !filePath.isEmpty else {
            return (cleanExplanation.isEmpty ? response : cleanExplanation, nil)
        }
        
        let suggested = SuggestedFix(
            description: description,
            filePath: filePath,
            oldCode: oldCode,
            newCode: newCode,
            confidence: confidence
        )
        return (cleanExplanation.isEmpty ? response : cleanExplanation, suggested)
    }
    
    func applyFix(_ fix: SuggestedFix) async {
        let fileURL = URL(fileURLWithPath: (fix.filePath as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            print("[DebugService] Cannot read file for fix: \(fix.filePath)")
            return
        }
        
        guard content.contains(fix.oldCode) else {
            print("[DebugService] oldCode not found in \(fix.filePath)")
            return
        }
        
        let updatedContent = content.replacingOccurrences(of: fix.oldCode, with: fix.newCode)
        do {
            try updatedContent.write(to: fileURL, atomically: true, encoding: .utf8)
            for idx in errors.indices {
                if errors[idx].suggestedFix == fix {
                    errors[idx].status = .fixed
                }
            }
            if currentError?.suggestedFix == fix {
                currentError?.status = .fixed
            }
            NotificationCenter.default.post(name: NSNotification.Name("FileUpdatedExternally"), object: nil, userInfo: ["path": fileURL.path])
        } catch {
            print("[DebugService] Failed to write fix to \(fix.filePath): \(error)")
        }
    }
    
    func dismissError(_ error: RuntimeError) {
        if let index = errors.firstIndex(where: { $0.id == error.id }) {
            errors[index].status = .dismissed
            if currentError?.id == error.id {
                currentError = nil
            }
        }
    }
    
    func clearAll() {
        errors.removeAll()
        currentError = nil
        isAnalyzing = false
    }
    
    // MARK: - Language Parsers
    
    private func parsePythonError(_ output: String, lines: [String]) -> RuntimeError? {
        guard output.contains("Traceback (most recent call last):") else { return nil }
        
        var stackTrace: [StackFrame] = []
        var errorType = "PythonError"
        var message = ""
        
        let fileRegex = try? NSRegularExpression(pattern: #"File "(.+)", line (\d+), in (.+)"#)
        
        for (i, line) in lines.enumerated() {
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = fileRegex?.firstMatch(in: line, range: nsRange) {
                if let fileRange = Range(match.range(at: 1), in: line),
                   let lineRange = Range(match.range(at: 2), in: line),
                   let funcRange = Range(match.range(at: 3), in: line) {
                    let file = String(line[fileRange])
                    let lineNum = Int(line[lineRange])
                    let funcName = String(line[funcRange])
                    
                    let isUserCode = !file.contains("/lib/python") && !file.contains("/site-packages/")
                    
                    stackTrace.append(StackFrame(functionName: funcName, filePath: file, lineNumber: lineNum, columnNumber: nil, isUserCode: isUserCode))
                }
            } else if !line.hasPrefix(" ") && i > 0 && line.contains(":") {
                let parts = line.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    errorType = parts[0].trimmingCharacters(in: .whitespaces)
                    message = parts[1].trimmingCharacters(in: .whitespaces)
                } else {
                    message = line
                }
            }
        }
        
        return RuntimeError(language: "Python", errorType: errorType, message: message.isEmpty ? "Unknown python error" : message, stackTrace: stackTrace.reversed(), rawOutput: output)
    }
    
    private func parseNodeError(_ output: String, lines: [String]) -> RuntimeError? {
        guard output.contains("Error:") || output.contains("Exception:") || output.contains("TypeError:") || output.contains("ReferenceError:") else { return nil }
        
        var stackTrace: [StackFrame] = []
        var errorType = "NodeError"
        var message = ""
        
        let stackRegex = try? NSRegularExpression(pattern: #"at (.+) \((.+):(\d+):(\d+)\)"#)
        let stackRegexAlt = try? NSRegularExpression(pattern: #"at (.+):(\d+):(\d+)"#)
        
        var firstErrorFound = false
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !firstErrorFound && (trimmed.contains("Error:") || trimmed.hasSuffix("Error")) {
                let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    errorType = parts[0].trimmingCharacters(in: .whitespaces)
                    message = parts[1].trimmingCharacters(in: .whitespaces)
                } else {
                    message = trimmed
                }
                firstErrorFound = true
                continue
            }
            
            if trimmed.hasPrefix("at ") {
                let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
                if let match = stackRegex?.firstMatch(in: line, range: nsRange) {
                    if let funcRange = Range(match.range(at: 1), in: line),
                       let fileRange = Range(match.range(at: 2), in: line),
                       let lineRange = Range(match.range(at: 3), in: line),
                       let colRange = Range(match.range(at: 4), in: line) {
                        
                        let funcName = String(line[funcRange])
                        let file = String(line[fileRange])
                        let lineNum = Int(line[lineRange])
                        let colNum = Int(line[colRange])
                        let isUserCode = !file.contains("node_modules") && !file.contains("internal/")
                        
                        stackTrace.append(StackFrame(functionName: funcName, filePath: file, lineNumber: lineNum, columnNumber: colNum, isUserCode: isUserCode))
                    }
                } else if let match = stackRegexAlt?.firstMatch(in: line, range: nsRange) {
                    if let fileRange = Range(match.range(at: 1), in: line),
                       let lineRange = Range(match.range(at: 2), in: line),
                       let colRange = Range(match.range(at: 3), in: line) {
                        
                        let file = String(line[fileRange])
                        let lineNum = Int(line[lineRange])
                        let colNum = Int(line[colRange])
                        let isUserCode = !file.contains("node_modules") && !file.contains("internal/")
                        
                        stackTrace.append(StackFrame(functionName: "<anonymous>", filePath: file, lineNumber: lineNum, columnNumber: colNum, isUserCode: isUserCode))
                    }
                }
            }
        }
        
        return RuntimeError(language: "JavaScript/TypeScript", errorType: errorType, message: message, stackTrace: stackTrace, rawOutput: output)
    }
    
    private func parseRustError(_ output: String, lines: [String]) -> RuntimeError? {
        guard output.contains("error[E") || output.contains("error:") || output.contains("panicked at") else { return nil }
        
        var stackTrace: [StackFrame] = []
        var errorType = "RustError"
        var message = ""
        
        if output.contains("panicked at") {
            errorType = "Panic"
            if let panicRange = output.range(of: "panicked at") {
                let afterPanic = output[panicRange.upperBound...]
                let msgLine = afterPanic.split(separator: "\n").first ?? ""
                message = String(msgLine).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        let fileRegex = try? NSRegularExpression(pattern: #"--> (.+):(\d+):(\d+)"#)
        
        for line in lines {
            if line.starts(with: "error[") {
                let parts = line.split(separator: "]", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    errorType = parts[0].replacingOccurrences(of: "error[", with: "").trimmingCharacters(in: .whitespaces)
                    message = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                }
            } else if line.starts(with: "error:") {
                message = line.replacingOccurrences(of: "error:", with: "").trimmingCharacters(in: .whitespaces)
            }
            
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            if let match = fileRegex?.firstMatch(in: line, range: nsRange) {
                if let fileRange = Range(match.range(at: 1), in: line),
                   let lineRange = Range(match.range(at: 2), in: line),
                   let colRange = Range(match.range(at: 3), in: line) {
                    
                    let file = String(line[fileRange])
                    let lineNum = Int(line[lineRange])
                    let colNum = Int(line[colRange])
                    
                    stackTrace.append(StackFrame(functionName: "unknown", filePath: file, lineNumber: lineNum, columnNumber: colNum, isUserCode: true))
                }
            }
        }
        
        if errorType == "RustError" && message.isEmpty {
            return nil
        }
        
        return RuntimeError(language: "Rust", errorType: errorType, message: message, stackTrace: stackTrace, rawOutput: output)
    }
    
    private func parseSwiftError(_ output: String, lines: [String]) -> RuntimeError? {
        guard output.contains("Fatal error:") || output.contains("Precondition failed:") else { return nil }
        
        var errorType = "Swift Fatal Error"
        var message = ""
        
        for line in lines {
            if line.contains("Fatal error:") {
                message = line.components(separatedBy: "Fatal error:").last?.trimmingCharacters(in: .whitespaces) ?? ""
            } else if line.contains("Precondition failed:") {
                errorType = "Precondition Failed"
                message = line.components(separatedBy: "Precondition failed:").last?.trimmingCharacters(in: .whitespaces) ?? ""
            }
        }
        
        return RuntimeError(language: "Swift", errorType: errorType, message: message, stackTrace: [], rawOutput: output)
    }
    
    private func parseGoError(_ output: String, lines: [String]) -> RuntimeError? {
        guard output.contains("panic:") else { return nil }
        
        var stackTrace: [StackFrame] = []
        var errorType = "Go Panic"
        var message = ""
        
        var inStack = false
        var currentFunc = ""
        
        for line in lines {
            if line.hasPrefix("panic:") {
                message = line.replacingOccurrences(of: "panic:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("goroutine") {
                inStack = true
            } else if inStack {
                if line.hasPrefix("\t") {
                    // file and line
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    let parts = trimmed.split(separator: " ")
                    if let fileLine = parts.first {
                        let fileParts = fileLine.split(separator: ":")
                        if fileParts.count == 2 {
                            let file = String(fileParts[0])
                            let lineNum = Int(fileParts[1])
                            let isUserCode = !file.contains("/go/src/") && !file.contains("pkg/mod")
                            stackTrace.append(StackFrame(functionName: currentFunc, filePath: file, lineNumber: lineNum, columnNumber: nil, isUserCode: isUserCode))
                        }
                    }
                } else {
                    currentFunc = line.components(separatedBy: "(").first ?? line
                }
            }
        }
        
        return RuntimeError(language: "Go", errorType: errorType, message: message, stackTrace: stackTrace, rawOutput: output)
    }
    
    private func parseJavaError(_ output: String, lines: [String]) -> RuntimeError? {
        guard output.contains("Exception in thread") else { return nil }
        
        var stackTrace: [StackFrame] = []
        var errorType = "JavaException"
        var message = ""
        
        let stackRegex = try? NSRegularExpression(pattern: #"at (.+)\((.+):(\d+)\)"#)
        
        for line in lines {
            if line.starts(with: "Exception in thread") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 2 {
                    errorType = parts[1].trimmingCharacters(in: .whitespaces)
                    if parts.count >= 3 {
                        message = parts[2...].joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    }
                }
            } else if line.trimmingCharacters(in: .whitespaces).hasPrefix("at ") {
                let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
                if let match = stackRegex?.firstMatch(in: line, range: nsRange) {
                    if let funcRange = Range(match.range(at: 1), in: line),
                       let fileRange = Range(match.range(at: 2), in: line),
                       let lineRange = Range(match.range(at: 3), in: line) {
                        
                        let funcName = String(line[funcRange])
                        let file = String(line[fileRange])
                        let lineNum = Int(line[lineRange])
                        
                        let isUserCode = !funcName.starts(with: "java.") && !funcName.starts(with: "sun.")
                        
                        stackTrace.append(StackFrame(functionName: funcName, filePath: file, lineNumber: lineNum, columnNumber: nil, isUserCode: isUserCode))
                    }
                }
            }
        }
        
        return RuntimeError(language: "Java", errorType: errorType, message: message, stackTrace: stackTrace, rawOutput: output)
    }
    
    private func parseGenericError(_ output: String, lines: [String], language: String) -> RuntimeError? {
        let lower = output.lowercased()
        if lower.contains("error:") || lower.contains("fatal:") || lower.contains("exception") {
            let firstErrorLine = lines.first(where: { $0.lowercased().contains("error:") || $0.lowercased().contains("exception") }) ?? "Unknown error"
            return RuntimeError(language: language, errorType: "GenericError", message: firstErrorLine, stackTrace: [], rawOutput: output)
        }
        return nil
    }
}
