//
//  AgentPrivacyGuard.swift
//  MicroCode
//
//  Zero-Privacy-Leakage and Secret Sanitization Guard for Autonomous Agents.
//  Strictly enforces that no API keys, auth tokens, passwords, private keys,
//  or sensitive credentials are persisted in `.microcode/` files or workspace rules.
//
//  Copyright © 2025 Dotmini Company Limited
//

import Foundation

public struct AgentPrivacyFinding: Equatable, Identifiable {
    public var id: String { "\(ruleName):\(range.lowerBound)-\(range.upperBound)" }
    public let ruleName: String
    public let range: Range<String.Index>
    public let maskedSnippet: String
}

public enum AgentPrivacyGuard {
    
    public static let redactionPlaceholder = "[REDACTED_SECRET_FOR_PRIVACY]"
    
    // MARK: - Secret Detection Regex Patterns
    
    private struct SecretPattern {
        let name: String
        let regex: NSRegularExpression
        
        init(name: String, pattern: String, options: NSRegularExpression.Options = []) {
            self.name = name
            // Regexes are compiled statically once
            self.regex = try! NSRegularExpression(pattern: pattern, options: options)
        }
    }
    
    private static let patterns: [SecretPattern] = [
        SecretPattern(name: "JWT", pattern: #"\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#),
        SecretPattern(name: "Dotmini Platform Key", pattern: #"\bmci-live-[A-Za-z0-9_-]{12,}\b"#),
        // OpenAI / Codex API Keys
        SecretPattern(name: "OpenAI / Codex API Key", pattern: #"\bsk-[A-Za-z0-9_-]{20,}\b"#),
        
        // Anthropic Claude API Keys
        SecretPattern(name: "Anthropic Claude API Key", pattern: #"\bsk-ant-[A-Za-z0-9_-]{20,}\b"#),
        
        // Google Gemini / API Keys
        SecretPattern(name: "Google AI / Gemini API Key", pattern: #"\bAIza[0-9A-Za-z_-]{30,}\b"#),
        
        // GitHub Personal Access Tokens
        SecretPattern(name: "GitHub Token", pattern: #"\b(?:ghp|gho|ghu|ghs|ghr)_[0-9A-Za-z]{30,}\b|\bgithub_pat_[0-9A-Za-z_]{70,}\b"#),
        
        // AWS Access Key ID
        SecretPattern(name: "AWS Access Key", pattern: #"\b(?:AKIA|ABIA|ACCA|ASIA)[0-9A-Z]{16}\b"#),
        
        // Generic HTTP Bearer Tokens
        SecretPattern(name: "HTTP Bearer Token", pattern: #"(?i)\bBearer\s+[A-Za-z0-9\-_\.=]{20,}\b"#),
        
        // Private Keys (RSA, EC, PGP, OPENSSH)
        SecretPattern(
            name: "Cryptographic Private Key",
            pattern: #"-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----"#,
            options: []
        ),
        
        // Database connection strings containing passwords
        SecretPattern(
            name: "Database Credential URI",
            pattern: #"\b((?:postgres|postgresql|mysql|mongodb(?:\+srv)?|redis|amqp)://[^:\s@]+):([^@\s]+)@([^\s]+)"#,
            options: [.caseInsensitive]
        ),
        
        // Hardcoded assignments: api_key = "..." / password = "..."
        SecretPattern(
            name: "Hardcoded Credential Assignment",
            pattern: #"(?i)\b(api[_-]?key|apikey|secret[_-]?key|client[_-]?secret|auth[_-]?token|access[_-]?token|password|passwd|pwd)\s*[:=]\s*["']([^"'\r\n]{8,})["']"#
        )
    ]
    
    // MARK: - Sanitization API
    
    /// Replaces all identified secrets and credentials with `[REDACTED_SECRET_FOR_PRIVACY]`.
    public static func sanitize(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        
        for p in patterns {
            let fullRange = NSRange(result.startIndex..<result.endIndex, in: result)
            if p.name == "Database Credential URI" {
                // Redact only the password part in the URI
                result = p.regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: fullRange,
                    withTemplate: "$1:[REDACTED_PASSWORD]@$3"
                )
            } else if p.name == "Hardcoded Credential Assignment" {
                result = p.regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: fullRange,
                    withTemplate: "$1 = \"\(redactionPlaceholder)\""
                )
            } else {
                result = p.regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: fullRange,
                    withTemplate: redactionPlaceholder
                )
            }
        }
        
        return result
    }
    
    /// Audits a string and reports any secrets found without modifying the string.
    public static func audit(_ text: String) -> (isClean: Bool, findings: [AgentPrivacyFinding]) {
        guard !text.isEmpty else { return (true, []) }
        var findings: [AgentPrivacyFinding] = []
        
        for p in patterns {
            let fullRange = NSRange(text.startIndex..<text.endIndex, in: text)
            let matches = p.regex.matches(in: text, options: [], range: fullRange)
            for match in matches {
                if let swiftRange = Range(match.range, in: text) {
                    let snippet = String(text[swiftRange])
                    let maskedSnippet: String
                    if snippet.count > 8 {
                        maskedSnippet = "\(snippet.prefix(4))...\(snippet.suffix(3))"
                    } else {
                        maskedSnippet = "***"
                    }
                    findings.append(AgentPrivacyFinding(
                        ruleName: p.name,
                        range: swiftRange,
                        maskedSnippet: maskedSnippet
                    ))
                }
            }
        }
        
        return (findings.isEmpty, findings)
    }
    
    /// Sanitize JSON values without corrupting JSON escaping or schema keys.
    public static func sanitizeJSON(_ data: Data) throws -> Data {
        func clean(_ value: Any) -> Any {
            if let text = value as? String { return sanitize(text) }
            if let values = value as? [Any] { return values.map(clean) }
            if let values = value as? [String: Any] { return values.mapValues(clean) }
            return value
        }
        return try JSONSerialization.data(withJSONObject: clean(JSONSerialization.jsonObject(with: data)), options: [.sortedKeys])
    }

    /// Safely writes content to a file URL after guaranteeing that all sensitive secrets have been redacted.
    @discardableResult
    public static func safeWrite(content: String, to url: URL) throws -> (sanitized: Bool, writtenLength: Int) {
        let (isClean, _) = audit(content)
        let finalContent = isClean ? content : sanitize(content)
        
        let directory = url.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        
        try finalContent.write(to: url, atomically: true, encoding: .utf8)
        return (!isClean, finalContent.utf8.count)
    }
}

// MARK: - Feature #7: 1-Click Secret & API Key Leak Shield

public struct SecretLeakAlert: Identifiable, Equatable {
    public let id = UUID()
    public let filePath: String
    public let fileName: String
    public let findings: [AgentPrivacyFinding]
    public let timestamp: Date
}

@MainActor
public final class SecretShieldMonitor: ObservableObject {
    public static let shared = SecretShieldMonitor()

    @Published public var activeAlerts: [SecretLeakAlert] = []

    private init() {}

    /// Inspects a source file write for accidentally hardcoded API keys or credentials.
    /// Returns a warning string if secrets are detected, or `nil` if clean.
    @discardableResult
    public func inspectFileWrite(content: String, filePath: String) -> String? {
        let fileName = URL(fileURLWithPath: filePath).lastPathComponent
        // Skip .env files, .microcode files, and lockfiles
        if fileName == ".env" || fileName.hasPrefix(".env.") || filePath.contains("/.microcode/") || fileName.hasSuffix(".lock") {
            return nil
        }
        let (isClean, findings) = AgentPrivacyGuard.audit(content)
        guard !isClean, !findings.isEmpty else {
            activeAlerts.removeAll { $0.filePath == filePath }
            return nil
        }

        let alert = SecretLeakAlert(
            filePath: filePath,
            fileName: fileName,
            findings: findings,
            timestamp: Date()
        )
        activeAlerts.removeAll { $0.filePath == filePath }
        activeAlerts.insert(alert, at: 0)
        if activeAlerts.count > 10 {
            activeAlerts = Array(activeAlerts.prefix(10))
        }

        let ruleSummary = Array(Set(findings.map(\.ruleName))).sorted().joined(separator: ", ")
        return "\n\n⚠️ [Secret Leak Shield Warning]: Detected \(findings.count) potential hardcoded credential(s) (\(ruleSummary)) in `\(fileName)`. Consider moving secrets to `.env` and referencing environment variables instead."
    }

    /// 1-Click Action: Extracts detected secrets from the source file, writes them to `<workspace>/.env`,
    /// ensures `.env` is in `.gitignore`, and replaces hardcoded strings with environment variable lookups.
    public func moveSecretsToEnv(alert: SecretLeakAlert, workspaceRoot: String?) -> String {
        guard let rawContent = try? String(contentsOfFile: alert.filePath, encoding: .utf8) else {
            activeAlerts.removeAll { $0.id == alert.id }
            return "Could not read \(alert.fileName)"
        }

        let rootDir = workspaceRoot ?? URL(fileURLWithPath: alert.filePath).deletingLastPathComponent().path
        let envPath = (rootDir as NSString).appendingPathComponent(".env")
        let gitignorePath = (rootDir as NSString).appendingPathComponent(".gitignore")
        let ext = URL(fileURLWithPath: alert.filePath).pathExtension.lowercased()

        // Audit fresh content so ranges are exact
        let (_, findings) = AgentPrivacyGuard.audit(rawContent)
        guard !findings.isEmpty else {
            activeAlerts.removeAll { $0.id == alert.id }
            return "No active secrets found in \(alert.fileName)"
        }

        var updatedContent = rawContent
        var envEntries: [(key: String, value: String)] = []
        var counter = 1

        // Process findings in reverse range order so string indices remain valid
        let sortedFindings = findings.sorted { $0.range.lowerBound > $1.range.lowerBound }
        for finding in sortedFindings {
            let matchedText = String(updatedContent[finding.range])
            let envKey: String = {
                switch finding.ruleName {
                case "OpenAI / Codex API Key": return counter == 1 ? "OPENAI_API_KEY" : "OPENAI_API_KEY_\(counter)"
                case "Anthropic Claude API Key": return counter == 1 ? "ANTHROPIC_API_KEY" : "ANTHROPIC_API_KEY_\(counter)"
                case "Google AI / Gemini API Key": return counter == 1 ? "GEMINI_API_KEY" : "GEMINI_API_KEY_\(counter)"
                case "GitHub Token": return counter == 1 ? "GITHUB_TOKEN" : "GITHUB_TOKEN_\(counter)"
                case "AWS Access Key": return counter == 1 ? "AWS_ACCESS_KEY_ID" : "AWS_ACCESS_KEY_ID_\(counter)"
                case "Dotmini Platform Key": return counter == 1 ? "DOTMINI_API_KEY" : "DOTMINI_API_KEY_\(counter)"
                default: return "APP_SECRET_\(counter)"
                }
            }()
            counter += 1

            // If it's a hardcoded assignment like `apiKey = "sk-..."`, extract just the quoted value if possible
            if finding.ruleName == "Hardcoded Credential Assignment" {
                let sanitizedAssignment = AgentPrivacyGuard.sanitize(matchedText)
                updatedContent.replaceSubrange(finding.range, with: sanitizedAssignment)
                envEntries.append((key: envKey, value: matchedText))
            } else {
                envEntries.append((key: envKey, value: matchedText))
                let envRef: String = {
                    switch ext {
                    case "js", "jsx", "ts", "tsx", "mjs", "cjs":
                        return "process.env.\(envKey)"
                    case "py":
                        return "os.environ.get(\"\(envKey)\", \"\")"
                    case "swift":
                        return "(ProcessInfo.processInfo.environment[\"\(envKey)\"] ?? \"\")"
                    case "rs":
                        return "std::env::var(\"\(envKey)\").unwrap_or_default()"
                    case "go":
                        return "os.Getenv(\"\(envKey)\")"
                    default:
                        return "${\(envKey)}"
                    }
                }()
                updatedContent.replaceSubrange(finding.range, with: envRef)
            }
        }

        // Write updated source file
        try? updatedContent.write(toFile: alert.filePath, atomically: true, encoding: .utf8)

        // Append extracted secrets to .env
        var existingEnv = (try? String(contentsOfFile: envPath, encoding: .utf8)) ?? ""
        if !existingEnv.isEmpty && !existingEnv.hasSuffix("\n") {
            existingEnv += "\n"
        }
        for entry in envEntries.reversed() {
            if !existingEnv.contains("\(entry.key)=") {
                existingEnv += "\(entry.key)=\"\(entry.value.replacingOccurrences(of: "\"", with: "\\\""))\"\n"
            }
        }
        try? existingEnv.write(toFile: envPath, atomically: true, encoding: .utf8)

        // Ensure .env is in .gitignore
        var gitignore = (try? String(contentsOfFile: gitignorePath, encoding: .utf8)) ?? ""
        if !gitignore.components(separatedBy: .newlines).contains(where: { $0.trimmingCharacters(in: .whitespaces) == ".env" }) {
            if !gitignore.isEmpty && !gitignore.hasSuffix("\n") { gitignore += "\n" }
            gitignore += ".env\n"
            try? gitignore.write(toFile: gitignorePath, atomically: true, encoding: .utf8)
        }

        activeAlerts.removeAll { $0.id == alert.id }
        return "Moved \(envEntries.count) secret(s) from \(alert.fileName) to .env & updated .gitignore"
    }

    public func dismissAlert(_ alert: SecretLeakAlert) {
        activeAlerts.removeAll { $0.id == alert.id }
    }
}

