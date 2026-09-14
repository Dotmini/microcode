//
//  AgentLSPBridge.swift
//  MicroCode
//
//  Feature 8: LSP Integration for AI Agent
//  Provides agent tools to query LSP servers for hover info,
//  go-to-definition, completions, and active diagnostics.
//  Tirawat Nantamas Founder and CEO of Dotmini Software.
//  Copyright © 2025 Dotmini Software. All rights reserved.
//

import Foundation

// MARK: - Helper: Language Detection from File Path

private func languageForFile(_ path: String) -> String {
    let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
    switch ext {
    case "py":                     return "python"
    case "js":                     return "javascript"
    case "ts":                     return "typescript"
    case "tsx":                    return "typescript"
    case "jsx":                    return "javascript"
    case "rs":                     return "rust"
    case "swift":                  return "swift"
    case "go":                     return "go"
    case "rb":                     return "ruby"
    case "java":                   return "java"
    case "kt", "kts":             return "kotlin"
    case "cpp", "cc", "cxx", "c++": return "cpp"
    case "c":                      return "c"
    case "h", "hpp":              return "cpp"
    case "m":                      return "objective-c"
    case "mm":                     return "objective-cpp"
    case "dart":                   return "dart"
    case "php":                    return "php"
    case "cs":                     return "csharp"
    case "html":                   return "html"
    case "css":                    return "css"
    case "json":                   return "json"
    default:                       return ext
    }
}

// MARK: - LSP Hover Tool

struct LSPHoverTool: AgentTool {
    let name = "lsp_hover"
    let description = "Get type information and documentation for a symbol at a specific position in a file via LSP. Returns hover information including type signatures, documentation, and module info."
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute path to the source file", required: true),
        ToolParameter(name: "line", type: "integer", description: "0-based line number of the symbol", required: true),
        ToolParameter(name: "character", type: "integer", description: "0-based character/column offset within the line", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String else {
            throw ToolBoxError.invalidParams("Missing 'path'")
        }
        guard let line = params["line"] as? Int else {
            throw ToolBoxError.invalidParams("Missing 'line' (integer)")
        }
        guard let character = params["character"] as? Int else {
            throw ToolBoxError.invalidParams("Missing 'character' (integer)")
        }
        
        let url = URL(fileURLWithPath: path)
        let uri = url.absoluteString
        let language = languageForFile(path)
        
        // Ensure document is opened in LSP
        await ensureDocumentOpen(path: path, language: language)
        
        let result = await LSPManager.shared.getHover(
            uri: uri,
            language: language,
            line: line,
            character: character
        )
        
        if let hoverText = result, !hoverText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Hover info for \(url.lastPathComponent) at line \(line + 1):\(character + 1):\n\n\(hoverText)"
        } else {
            return "No hover information available at \(url.lastPathComponent) line \(line + 1):\(character + 1). The symbol may not be recognized by the language server, or the LSP server for '\(language)' may not be installed."
        }
    }
}

// MARK: - LSP Definition Tool

struct LSPDefinitionTool: AgentTool {
    let name = "lsp_definition"
    let description = "Go to definition: find where a symbol is defined. Returns file path and line number of the definition. Useful for navigating code and understanding symbol origins."
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute path to the source file", required: true),
        ToolParameter(name: "line", type: "integer", description: "0-based line number of the symbol", required: true),
        ToolParameter(name: "character", type: "integer", description: "0-based character/column offset within the line", required: true)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String else {
            throw ToolBoxError.invalidParams("Missing 'path'")
        }
        guard let line = params["line"] as? Int else {
            throw ToolBoxError.invalidParams("Missing 'line' (integer)")
        }
        guard let character = params["character"] as? Int else {
            throw ToolBoxError.invalidParams("Missing 'character' (integer)")
        }
        
        let url = URL(fileURLWithPath: path)
        let uri = url.absoluteString
        let language = languageForFile(path)
        
        await ensureDocumentOpen(path: path, language: language)
        
        let locations = await LSPManager.shared.getDefinition(
            uri: uri,
            language: language,
            line: line,
            character: character
        )
        
        if locations.isEmpty {
            return "No definition found for symbol at \(url.lastPathComponent) line \(line + 1):\(character + 1). The symbol may be a built-in, or the LSP server for '\(language)' may not be running."
        }
        
        var output = "Definition locations for symbol at \(url.lastPathComponent) line \(line + 1):\(character + 1):\n\n"
        for (i, loc) in locations.enumerated() {
            let defPath: String
            if let defURL = URL(string: loc.uri) {
                defPath = defURL.path
            } else {
                defPath = loc.uri
            }
            let defLine = loc.range.start.line + 1
            let defChar = loc.range.start.character + 1
            let endLine = loc.range.end.line + 1
            output += "\(i + 1). \(defPath):\(defLine):\(defChar)"
            if endLine != defLine {
                output += " → line \(endLine)"
            }
            output += "\n"
        }
        return output
    }
}

// MARK: - LSP Completions Tool

struct LSPCompletionsTool: AgentTool {
    let name = "lsp_completions"
    let description = "Get code completion suggestions at a specific position. Returns a list of completion items with their labels, kinds, and documentation. Useful for understanding what methods/properties are available on an object."
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute path to the source file", required: true),
        ToolParameter(name: "line", type: "integer", description: "0-based line number", required: true),
        ToolParameter(name: "character", type: "integer", description: "0-based character/column offset", required: true),
        ToolParameter(name: "limit", type: "integer", description: "Maximum number of completions to return (default: 20)", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String else {
            throw ToolBoxError.invalidParams("Missing 'path'")
        }
        guard let line = params["line"] as? Int else {
            throw ToolBoxError.invalidParams("Missing 'line' (integer)")
        }
        guard let character = params["character"] as? Int else {
            throw ToolBoxError.invalidParams("Missing 'character' (integer)")
        }
        let limit = (params["limit"] as? Int) ?? 20
        
        let url = URL(fileURLWithPath: path)
        let uri = url.absoluteString
        let language = languageForFile(path)
        
        await ensureDocumentOpen(path: path, language: language)
        
        let items = await LSPManager.shared.getCompletions(
            uri: uri,
            language: language,
            line: line,
            character: character
        )
        
        if items.isEmpty {
            return "No completions available at \(url.lastPathComponent) line \(line + 1):\(character + 1). The position may be in a comment, string, or the LSP server for '\(language)' may not be running."
        }
        
        let capped = Array(items.prefix(limit))
        var output = "Completions at \(url.lastPathComponent) line \(line + 1):\(character + 1) (\(items.count) total, showing \(capped.count)):\n\n"
        
        for item in capped {
            let kindStr = completionKindName(item.kind ?? 0)
            output += "• \(item.label)"
            if !kindStr.isEmpty {
                output += " [\(kindStr)]"
            }
            if let detail = item.detail, !detail.isEmpty {
                output += " — \(detail)"
            }
            output += "\n"
        }
        return output
    }
    
    private func completionKindName(_ kind: Int) -> String {
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
        default: return ""
        }
    }
}

// MARK: - LSP Active Diagnostics Tool (Enhanced)

struct LSPActiveDiagnosticsTool: AgentTool {
    let name = "lsp_diagnostics"
    let description = "Get real-time diagnostics (errors, warnings, hints) from the LSP server for a file. Unlike get_diagnostics which reads cached data, this actively syncs the document with the LSP server first to get the latest diagnostics."
    let parameters = [
        ToolParameter(name: "path", type: "string", description: "Absolute path to the source file", required: true),
        ToolParameter(name: "severity", type: "string", description: "Filter by severity: 'error', 'warning', 'info', 'hint', or 'all' (default: 'all')", required: false)
    ]
    
    func execute(params: [String: Any]) async throws -> String {
        guard let path = params["path"] as? String else {
            throw ToolBoxError.invalidParams("Missing 'path'")
        }
        let severityFilter = (params["severity"] as? String)?.lowercased() ?? "all"
        
        let url = URL(fileURLWithPath: path)
        let uri = url.absoluteString
        let language = languageForFile(path)
        
        // Actively sync document with LSP server
        await ensureDocumentOpen(path: path, language: language)
        
        // Read current file content and push to LSP
        if let content = try? String(contentsOfFile: path, encoding: .utf8) {
            await LSPManager.shared.documentChanged(uri: uri, language: language, content: content)
        }
        
        // Brief delay to allow diagnostics to propagate
        try? await Task.sleep(nanoseconds: 300_000_000) // 300ms
        
        return await MainActor.run {
            guard let diagnostics = LSPManager.shared.fileDiagnostics[uri], !diagnostics.isEmpty else {
                return "✅ No diagnostics for \(url.lastPathComponent). The file appears clean."
            }
            
            let filtered: [LSPDiagnostic]
            switch severityFilter {
            case "error":   filtered = diagnostics.filter { $0.severity == 1 }
            case "warning": filtered = diagnostics.filter { $0.severity == 2 }
            case "info":    filtered = diagnostics.filter { $0.severity == 3 }
            case "hint":    filtered = diagnostics.filter { $0.severity == 4 }
            default:        filtered = diagnostics
            }
            
            if filtered.isEmpty {
                return "No '\(severityFilter)' diagnostics for \(url.lastPathComponent). Found \(diagnostics.count) diagnostics at other severity levels."
            }
            
            var output = "Diagnostics for \(url.lastPathComponent)"
            if severityFilter != "all" {
                output += " (filtered: \(severityFilter))"
            }
            output += " — \(filtered.count) issue(s):\n\n"
            
            let errorCount = filtered.filter { $0.severity == 1 }.count
            let warnCount = filtered.filter { $0.severity == 2 }.count
            let infoCount = filtered.filter { $0.severity == 3 }.count
            let hintCount = filtered.filter { $0.severity == 4 }.count
            
            output += "Summary: "
            var parts: [String] = []
            if errorCount > 0 { parts.append("\(errorCount) error(s)") }
            if warnCount > 0 { parts.append("\(warnCount) warning(s)") }
            if infoCount > 0 { parts.append("\(infoCount) info") }
            if hintCount > 0 { parts.append("\(hintCount) hint(s)") }
            output += parts.joined(separator: ", ") + "\n\n"
            
            for diag in filtered {
                let severityStr: String
                switch diag.severity {
                case 1: severityStr = "❌ ERROR"
                case 2: severityStr = "⚠️ WARNING"
                case 3: severityStr = "ℹ️ INFO"
                case 4: severityStr = "💡 HINT"
                default: severityStr = "❓ ISSUE"
                }
                let line = diag.range.start.line + 1
                let char = diag.range.start.character + 1
                output += "\(severityStr) Line \(line):\(char) — \(diag.message)\n"
            }
            return output
        }
    }
}

// MARK: - LSP Server Status Tool

struct LSPStatusTool: AgentTool {
    let name = "lsp_status"
    let description = "Check the status of LSP language servers. Shows which servers are installed, running, and which languages are supported. Useful for understanding IDE capabilities."
    let parameters: [ToolParameter] = []
    
    func execute(params: [String: Any]) async throws -> String {
        return await MainActor.run {
            let manager = LSPManager.shared
            let installed = manager.detectInstalledServers()
            let languages = manager.detectedLanguages()
            
            var output = "LSP Server Status:\n\n"
            
            output += "📦 Installed Servers (\(installed.count)/\(LanguageServer.allCases.count)):\n"
            for server in LanguageServer.allCases {
                let isInstalled = installed.contains(server)
                let isActive = manager.activeClients[server]?.isRunning == true
                let status: String
                if isActive {
                    status = "🟢 Running"
                } else if isInstalled {
                    status = "🟡 Installed (idle)"
                } else {
                    status = "⚫ Not installed"
                }
                let langs = server.languageIds.joined(separator: ", ")
                output += "  \(status) \(server.rawValue) → [\(langs)]\n"
            }
            
            output += "\n🌐 Supported Languages: \(languages.joined(separator: ", "))\n"
            
            // Show active diagnostics counts
            let totalDiags = manager.fileDiagnostics.values.reduce(0) { $0 + $1.count }
            let errorCount = manager.fileDiagnostics.values.flatMap { $0 }.filter { $0.severity == 1 }.count
            output += "\n📊 Active Diagnostics: \(totalDiags) total (\(errorCount) errors) across \(manager.fileDiagnostics.count) file(s)\n"
            
            return output
        }
    }
}

// MARK: - Helper: Ensure Document Is Open

private func ensureDocumentOpen(path: String, language: String) async {
    let url = URL(fileURLWithPath: path)
    let uri = url.absoluteString
    
    // Read file content
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }
    
    // Open in LSP (idempotent — LSPManager handles duplicates gracefully)
    await LSPManager.shared.documentOpened(uri: uri, language: language, content: content)
}
