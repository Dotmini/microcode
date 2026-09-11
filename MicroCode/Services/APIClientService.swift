//
//  APIClientService.swift
//  MicroCode
//
//  Professional HTTP Client — Postman-level API Testing
//  Direct execution, Collections, Environments, Auth, cURL
//
//  Copyright © 2025 SPU AI CLUB. All rights reserved.
//

import Foundation
import Combine
import SwiftUI

// MARK: - HTTP Method

enum HTTPMethod: String, CaseIterable, Identifiable, Codable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
    case options = "OPTIONS"
    
    var id: String { rawValue }
    
    var color: Color {
        switch self {
        case .get: return Color(red: 0.28, green: 0.52, blue: 0.85) // Subtle Steel Blue
        case .post: return Color(red: 0.22, green: 0.58, blue: 0.44) // Muted Sage Teal
        case .put: return Color(red: 0.82, green: 0.55, blue: 0.18) // Warm Amber
        case .delete: return Color(red: 0.82, green: 0.32, blue: 0.32) // Muted Crimson
        case .patch: return Color(red: 0.55, green: 0.42, blue: 0.78) // Slate Purple
        case .head: return Color(red: 0.35, green: 0.55, blue: 0.65) // Slate Blue
        case .options: return Color(red: 0.55, green: 0.58, blue: 0.62) // Neutral Slate
        }
    }
}

// MARK: - Auth Types

enum APIAuthType: String, CaseIterable, Codable {
    case none = "None"
    case bearer = "Bearer Token"
    case basic = "Basic Auth"
    case apiKey = "API Key"
}

struct APIAuth: Codable {
    var type: APIAuthType = .none
    var bearerToken: String = ""
    var basicUser: String = ""
    var basicPassword: String = ""
    var apiKeyName: String = "X-API-Key"
    var apiKeyValue: String = ""
    var apiKeyIn: String = "header" // header or query
}

// MARK: - Request Model

struct APIRequest: Codable, Identifiable {
    var id = UUID()
    var name: String = "New Request"
    var method: String = "GET"
    var url: String = ""
    var headers: [String: String] = [:]
    var body: String?
    var auth: APIAuth = APIAuth()
    var queryParams: [KeyValueItem] = []
    var contentType: String = "application/json"
    var timeout: Int = 30
    var followRedirects: Bool = true
    var timestamp: Date = Date()
}

// MARK: - Response Model

struct APIResponse: Codable {
    let status: Int
    let statusText: String
    let header_map: [String: String]
    let body: String
    let duration_ms: Int
    let bodySize: Int
    let responseDate: Date
    
    var isSuccess: Bool { status >= 200 && status < 300 }
    var isRedirect: Bool { status >= 300 && status < 400 }
    var isClientError: Bool { status >= 400 && status < 500 }
    var isServerError: Bool { status >= 500 }
    
    var statusColor: Color {
        if isSuccess { return Color(red: 0.22, green: 0.60, blue: 0.44) } // Muted Emerald
        if isRedirect { return Color(red: 0.28, green: 0.52, blue: 0.85) } // Steel Blue
        if isClientError { return Color(red: 0.85, green: 0.55, blue: 0.20) } // Warm Amber
        return Color(red: 0.82, green: 0.32, blue: 0.32) // Muted Crimson
    }
    
    var formattedBody: String {
        // Pretty-print JSON
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyStr = String(data: prettyData, encoding: .utf8) {
            return prettyStr
        }
        return body
    }
}

// MARK: - Collection & Environment

struct APICollection: Identifiable, Codable {
    var id = UUID()
    var name: String
    var requests: [APIRequest] = []
    var timestamp: Date = Date()
}

struct APIEnvironment: Identifiable, Codable {
    var id = UUID()
    var name: String
    var variables: [KeyValueItem] = []
    var isActive: Bool = false
}

struct KeyValueItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var key: String = ""
    var value: String = ""
    var isEnabled: Bool = true
}

// MARK: - History Entry

struct APIHistoryEntry: Identifiable, Codable {
    var id = UUID()
    var request: APIRequest
    var status: Int
    var duration: Int
    var timestamp: Date = Date()
}

// MARK: - AI Test Assertion

struct APITestAssertion: Identifiable, Codable {
    var id = UUID()
    var name: String
    var passed: Bool
    var details: String
}

// MARK: - Code Snippet Language

enum CodeSnippetLanguage: String, CaseIterable, Identifiable {
    case curl = "cURL"
    case swift = "Swift (URLSession)"
    case typescript = "TypeScript (fetch)"
    case python = "Python (httpx)"
    case rust = "Rust (reqwest)"
    
    var id: String { rawValue }
}

// MARK: - API Client Service

@MainActor
class APIClientService: ObservableObject {
    static let shared = APIClientService()
    
    @Published var lastResponse: APIResponse?
    @Published var isLoading = false
    @Published var error: String?
    @Published var history: [APIHistoryEntry] = []
    @Published var collections: [APICollection] = []
    @Published var environments: [APIEnvironment] = []
    @Published var activeEnvironment: APIEnvironment?
    @Published var requestProgress: Double = 0
    @Published var activeTestAssertions: [APITestAssertion] = []
    @Published var isScanningRoutes: Bool = false
    @Published var routeScanMessage: String? = nil
    
    private var storageDir: String {
        let workspace = AgentToolBox.shared.workspaceRoot ?? NSHomeDirectory()
        return (workspace as NSString).appendingPathComponent(".microcode/api-client")
    }
    
    private init() {
        loadData()
        if collections.isEmpty {
            collections.append(APICollection(name: "Default Collection"))
        }
        if environments.isEmpty {
            environments.append(APIEnvironment(name: "Development", variables: [
                KeyValueItem(key: "base_url", value: "http://localhost:3000"),
                KeyValueItem(key: "api_key", value: "")
            ]))
        }
    }
    
    // MARK: - Direct HTTP Execution
    
    func execute(_ request: APIRequest) async throws -> APIResponse {
        isLoading = true
        error = nil
        lastResponse = nil
        requestProgress = 0
        
        defer { isLoading = false }
        
        // Resolve environment variables
        let resolvedURL = resolveVariables(request.url)
        guard let url = buildURL(resolvedURL, queryParams: request.queryParams) else {
            error = "Invalid URL: \(resolvedURL)"
            throw NSError(domain: "APIClient", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.timeoutInterval = TimeInterval(request.timeout)
        
        // Set headers
        for (key, value) in request.headers {
            urlRequest.setValue(resolveVariables(value), forHTTPHeaderField: key)
        }
        
        // Apply auth
        applyAuth(request.auth, to: &urlRequest)
        
        // Set body
        if request.method != "GET" && request.method != "HEAD" {
            if let body = request.body, !body.isEmpty {
                urlRequest.httpBody = resolveVariables(body).data(using: .utf8)
                if urlRequest.value(forHTTPHeaderField: "Content-Type") == nil {
                    urlRequest.setValue(request.contentType, forHTTPHeaderField: "Content-Type")
                }
            }
        }
        
        requestProgress = 0.3
        
        // Execute
        let startTime = Date()
        
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            let duration = Int(Date().timeIntervalSince(startTime) * 1000)
            requestProgress = 0.9
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NSError(domain: "APIClient", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
            }
            
            var headerMap: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let k = key as? String, let v = value as? String {
                    headerMap[k] = v
                }
            }
            
            let bodyStr = String(data: data, encoding: .utf8) ?? "(binary data: \(data.count) bytes)"
            
            let statusText = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            
            let apiResponse = APIResponse(
                status: httpResponse.statusCode,
                statusText: statusText.capitalized,
                header_map: headerMap,
                body: bodyStr,
                duration_ms: duration,
                bodySize: data.count,
                responseDate: Date()
            )
            
            lastResponse = apiResponse
            requestProgress = 1.0
            _ = generateAITestSuite(for: request, response: apiResponse)
            
            // Save to history
            let entry = APIHistoryEntry(
                request: request,
                status: httpResponse.statusCode,
                duration: duration
            )
            history.insert(entry, at: 0)
            if history.count > 200 { history = Array(history.prefix(200)) }
            saveData()
            
            return apiResponse
            
        } catch {
            self.error = error.localizedDescription
            requestProgress = 0
            throw error
        }
    }
    
    // MARK: - Auth
    
    private func applyAuth(_ auth: APIAuth, to request: inout URLRequest) {
        switch auth.type {
        case .bearer:
            let token = resolveVariables(auth.bearerToken)
            if !token.isEmpty {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        case .basic:
            let credentials = "\(auth.basicUser):\(auth.basicPassword)"
            if let data = credentials.data(using: .utf8) {
                request.setValue("Basic \(data.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }
        case .apiKey:
            let key = resolveVariables(auth.apiKeyName)
            let value = resolveVariables(auth.apiKeyValue)
            if auth.apiKeyIn == "header" {
                request.setValue(value, forHTTPHeaderField: key)
            }
            // Query param handled in buildURL
        case .none:
            break
        }
    }
    
    // MARK: - URL Builder
    
    private func buildURL(_ urlString: String, queryParams: [KeyValueItem]) -> URL? {
        guard var components = URLComponents(string: urlString) else { return nil }
        
        let activeParams = queryParams.filter { $0.isEnabled && !$0.key.isEmpty }
        if !activeParams.isEmpty {
            var items = components.queryItems ?? []
            for param in activeParams {
                items.append(URLQueryItem(name: param.key, value: resolveVariables(param.value)))
            }
            components.queryItems = items
        }
        
        return components.url
    }
    
    // MARK: - Environment Variables
    
    private func resolveVariables(_ input: String) -> String {
        guard let env = activeEnvironment ?? environments.first else { return input }
        var result = input
        for variable in env.variables where variable.isEnabled {
            result = result.replacingOccurrences(of: "{{\(variable.key)}}", with: variable.value)
        }
        return result
    }
    
    // MARK: - cURL Export
    
    func exportCURL(_ request: APIRequest) -> String {
        var parts = ["curl"]
        parts.append("-X \(request.method)")
        
        let resolvedURL = resolveVariables(request.url)
        parts.append("'\(resolvedURL)'")
        
        for (key, value) in request.headers {
            parts.append("-H '\(key): \(resolveVariables(value))'")
        }
        
        // Auth headers
        switch request.auth.type {
        case .bearer:
            parts.append("-H 'Authorization: Bearer \(resolveVariables(request.auth.bearerToken))'")
        case .basic:
            parts.append("-u '\(request.auth.basicUser):\(request.auth.basicPassword)'")
        case .apiKey:
            if request.auth.apiKeyIn == "header" {
                parts.append("-H '\(request.auth.apiKeyName): \(resolveVariables(request.auth.apiKeyValue))'")
            }
        case .none: break
        }
        
        if let body = request.body, !body.isEmpty, request.method != "GET" {
            let escaped = body.replacingOccurrences(of: "'", with: "'\\''")
            parts.append("-d '\(escaped)'")
        }
        
        return parts.joined(separator: " \\\n  ")
    }
    
    // MARK: - cURL Import
    
    func importCURL(_ curl: String) -> APIRequest? {
        var request = APIRequest()
        let parts = curl.replacingOccurrences(of: "\\\n", with: " ").components(separatedBy: " ").filter { !$0.isEmpty }
        
        var i = 0
        while i < parts.count {
            let part = parts[i]
            switch part {
            case "-X", "--request":
                i += 1
                if i < parts.count { request.method = parts[i].uppercased() }
            case "-H", "--header":
                i += 1
                if i < parts.count {
                    let header = parts[i].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    if let colonIdx = header.firstIndex(of: ":") {
                        let key = String(header[header.startIndex..<colonIdx]).trimmingCharacters(in: .whitespaces)
                        let value = String(header[header.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)
                        request.headers[key] = value
                    }
                }
            case "-d", "--data", "--data-raw":
                i += 1
                if i < parts.count {
                    request.body = parts[i].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                }
            case "-u", "--user":
                i += 1
                if i < parts.count {
                    let creds = parts[i].trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    let split = creds.components(separatedBy: ":")
                    request.auth.type = .basic
                    request.auth.basicUser = split.first ?? ""
                    request.auth.basicPassword = split.count > 1 ? split[1] : ""
                }
            default:
                if part != "curl" && !part.hasPrefix("-") {
                    let cleaned = part.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    if cleaned.hasPrefix("http") {
                        request.url = cleaned
                    }
                }
            }
            i += 1
        }
        
        if request.method.isEmpty { request.method = request.body != nil ? "POST" : "GET" }
        return request.url.isEmpty ? nil : request
    }
    
    // MARK: - Collections
    
    func saveToCollection(_ request: APIRequest, collectionId: UUID? = nil) {
        let targetId = collectionId ?? collections.first?.id
        guard let id = targetId,
              let idx = collections.firstIndex(where: { $0.id == id }) else { return }
        collections[idx].requests.append(request)
        saveData()
    }
    
    // MARK: - Persistence
    
    func saveData() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: storageDir, withIntermediateDirectories: true)
        
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: URL(fileURLWithPath: "\(storageDir)/history.json"))
        }
        if let data = try? JSONEncoder().encode(collections) {
            try? data.write(to: URL(fileURLWithPath: "\(storageDir)/collections.json"))
        }
        if let data = try? JSONEncoder().encode(environments) {
            try? data.write(to: URL(fileURLWithPath: "\(storageDir)/environments.json"))
        }
    }
    
    func loadData() {
        let fm = FileManager.default
        if let data = fm.contents(atPath: "\(storageDir)/history.json"),
           let h = try? JSONDecoder().decode([APIHistoryEntry].self, from: data) {
            history = h
        }
        if let data = fm.contents(atPath: "\(storageDir)/collections.json"),
           let c = try? JSONDecoder().decode([APICollection].self, from: data) {
            collections = c
        }
        if let data = fm.contents(atPath: "\(storageDir)/environments.json"),
           let e = try? JSONDecoder().decode([APIEnvironment].self, from: data) {
            environments = e
        }
    }
    
    func clearHistory() {
        history.removeAll()
        saveData()
    }
    
    // MARK: - Killer Feature 1: AI Test Suite Generator
    
    @discardableResult
    func generateAITestSuite(for request: APIRequest, response: APIResponse) -> [APITestAssertion] {
        var tests: [APITestAssertion] = []
        
        // 1. Status Code Check
        let statusPassed = response.isSuccess
        tests.append(APITestAssertion(
            name: "Status Code 2xx OK",
            passed: statusPassed,
            details: "Received HTTP \(response.status) (\(response.statusText))"
        ))
        
        // 2. Latency SLA (< 1500ms)
        let latencyPassed = response.duration_ms < 1500
        tests.append(APITestAssertion(
            name: "Latency SLA (< 1500ms)",
            passed: latencyPassed,
            details: "Response finished in \(response.duration_ms)ms"
        ))
        
        // 3. Response Body Presence
        let hasBody = response.bodySize > 0
        tests.append(APITestAssertion(
            name: "Response Body Not Empty",
            passed: hasBody,
            details: "Payload size: \(response.bodySize) bytes"
        ))
        
        // 4. JSON Structure & Key Schema
        if let data = response.body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            if let dict = json as? [String: Any] {
                let keys = Array(dict.keys).sorted().prefix(6).joined(separator: ", ")
                tests.append(APITestAssertion(
                    name: "Valid JSON Object",
                    passed: true,
                    details: "Root keys: [\(keys)]"
                ))
            } else if let arr = json as? [Any] {
                tests.append(APITestAssertion(
                    name: "Valid JSON Array",
                    passed: true,
                    details: "Array with \(arr.count) items"
                ))
            }
        } else {
            let isJsonExpected = response.header_map.contains { $0.key.lowercased() == "content-type" && $0.value.contains("json") }
            if isJsonExpected {
                tests.append(APITestAssertion(
                    name: "Valid JSON Format",
                    passed: false,
                    details: "Content-Type is JSON but body failed parsing"
                ))
            }
        }
        
        // 5. Header Declaration
        let hasContentType = response.header_map.keys.contains { $0.lowercased() == "content-type" }
        tests.append(APITestAssertion(
            name: "Content-Type Declared",
            passed: hasContentType,
            details: response.header_map.first { $0.key.lowercased() == "content-type" }?.value ?? "Header missing"
        ))
        
        activeTestAssertions = tests
        return tests
    }
    
    // MARK: - Killer Feature 2: Workspace Route Scanner
    
    @discardableResult
    func scanWorkspaceRoutes(workspacePath: String? = nil) async -> [APIRequest] {
        let root = workspacePath ?? AgentToolBox.shared.workspaceRoot ?? NSHomeDirectory()
        isScanningRoutes = true
        routeScanMessage = "Scanning project files for API endpoints..."
        defer { isScanningRoutes = false }
        
        var foundRequests: [APIRequest] = []
        let fm = FileManager.default
        let ignoredDirs: Set<String> = [
            ".git", "node_modules", "target", ".build", "dist", ".next", ".cache",
            "venv", ".venv", "__pycache__", "Pods", "DerivedData"
        ]
        let allowedExtensions: Set<String> = ["py", "js", "ts", "tsx", "rs", "go", "php"]
        
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: root),
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else {
            routeScanMessage = "Could not read workspace directory"
            return []
        }
        
        let pyPattern = #"@(?:app|router|api)\.(get|post|put|delete|patch)\s*\(\s*["']([^"']+)["']"#
        let jsPattern = #"(?:app|router)\.(get|post|put|delete|patch)\s*\(\s*["']([^"']+)["']"#
        let rustPattern = #"\.route\s*\(\s*["']([^"']+)["']\s*,\s*(get|post|put|delete|patch)\b"#
        let goPattern = #"\.(GET|POST|PUT|DELETE|PATCH)\s*\(\s*["']([^"']+)["']"#
        
        let pyRegex = try? NSRegularExpression(pattern: pyPattern, options: [.caseInsensitive])
        let jsRegex = try? NSRegularExpression(pattern: jsPattern, options: [.caseInsensitive])
        let rustRegex = try? NSRegularExpression(pattern: rustPattern, options: [.caseInsensitive])
        let goRegex = try? NSRegularExpression(pattern: goPattern, options: [])
        
        for case let fileURL as URL in enumerator {
            let pathComponents = fileURL.pathComponents
            if pathComponents.contains(where: { ignoredDirs.contains($0) }) {
                enumerator.skipDescendants()
                continue
            }
            
            let ext = fileURL.pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }
            
            // Next.js App Router route.ts / route.js
            let filename = fileURL.lastPathComponent
            if (filename == "route.ts" || filename == "route.js") && fileURL.path.contains("/app/") {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    let nextHttpMethods = ["GET", "POST", "PUT", "DELETE", "PATCH"]
                    let relPath = fileURL.path.replacingOccurrences(of: root, with: "")
                    if let range = relPath.range(of: "/app/") {
                        var routePath = String(relPath[range.upperBound...])
                        routePath = routePath.replacingOccurrences(of: "/route.ts", with: "").replacingOccurrences(of: "/route.js", with: "")
                        if !routePath.hasPrefix("/") { routePath = "/" + routePath }
                        
                        for m in nextHttpMethods {
                            if content.contains("export async function \(m)") || content.contains("export function \(m)") {
                                let req = APIRequest(
                                    name: "\(m) \(routePath)",
                                    method: m,
                                    url: "{{base_url}}\(routePath)",
                                    headers: ["Content-Type": "application/json"],
                                    body: (m == "POST" || m == "PUT" || m == "PATCH") ? "{\n  \n}" : nil
                                )
                                foundRequests.append(req)
                            }
                        }
                    }
                }
                continue
            }
            
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8), content.count < 500_000 else { continue }
            let nsRange = NSRange(content.startIndex..<content.endIndex, in: content)
            
            if ext == "py", let regex = pyRegex {
                let matches = regex.matches(in: content, range: nsRange)
                for match in matches {
                    if match.numberOfRanges >= 3,
                       let mRange = Range(match.range(at: 1), in: content),
                       let pRange = Range(match.range(at: 2), in: content) {
                        let m = String(content[mRange]).uppercased()
                        let path = String(content[pRange])
                        foundRequests.append(APIRequest(
                            name: "\(m) \(path)",
                            method: m,
                            url: "{{base_url}}\(path)",
                            headers: ["Content-Type": "application/json"],
                            body: (m == "POST" || m == "PUT" || m == "PATCH") ? "{\n  \n}" : nil
                        ))
                    }
                }
            } else if (ext == "js" || ext == "ts" || ext == "tsx"), let regex = jsRegex {
                let matches = regex.matches(in: content, range: nsRange)
                for match in matches {
                    if match.numberOfRanges >= 3,
                       let mRange = Range(match.range(at: 1), in: content),
                       let pRange = Range(match.range(at: 2), in: content) {
                        let m = String(content[mRange]).uppercased()
                        let path = String(content[pRange])
                        foundRequests.append(APIRequest(
                            name: "\(m) \(path)",
                            method: m,
                            url: "{{base_url}}\(path)",
                            headers: ["Content-Type": "application/json"],
                            body: (m == "POST" || m == "PUT" || m == "PATCH") ? "{\n  \n}" : nil
                        ))
                    }
                }
            } else if ext == "rs", let regex = rustRegex {
                let matches = regex.matches(in: content, range: nsRange)
                for match in matches {
                    if match.numberOfRanges >= 3,
                       let pRange = Range(match.range(at: 1), in: content),
                       let mRange = Range(match.range(at: 2), in: content) {
                        let path = String(content[pRange])
                        let m = String(content[mRange]).uppercased()
                        foundRequests.append(APIRequest(
                            name: "\(m) \(path)",
                            method: m,
                            url: "{{base_url}}\(path)",
                            headers: ["Content-Type": "application/json"],
                            body: (m == "POST" || m == "PUT" || m == "PATCH") ? "{\n  \n}" : nil
                        ))
                    }
                }
            } else if ext == "go", let regex = goRegex {
                let matches = regex.matches(in: content, range: nsRange)
                for match in matches {
                    if match.numberOfRanges >= 3,
                       let mRange = Range(match.range(at: 1), in: content),
                       let pRange = Range(match.range(at: 2), in: content) {
                        let m = String(content[mRange]).uppercased()
                        let path = String(content[pRange])
                        foundRequests.append(APIRequest(
                            name: "\(m) \(path)",
                            method: m,
                            url: "{{base_url}}\(path)",
                            headers: ["Content-Type": "application/json"],
                            body: (m == "POST" || m == "PUT" || m == "PATCH") ? "{\n  \n}" : nil
                        ))
                    }
                }
            }
        }
        
        // Deduplicate
        var unique: [APIRequest] = []
        var seen: Set<String> = []
        for req in foundRequests {
            let key = "\(req.method):\(req.url)"
            if !seen.contains(key) {
                seen.insert(key)
                unique.append(req)
            }
        }
        
        if !unique.isEmpty {
            let colName = "Scanned Project Routes (\(unique.count))"
            if let existingIdx = collections.firstIndex(where: { $0.name.hasPrefix("Scanned Project Routes") }) {
                collections[existingIdx].requests = unique
                collections[existingIdx].name = colName
            } else {
                collections.insert(APICollection(name: colName, requests: unique), at: 0)
            }
            saveData()
            routeScanMessage = "Discovered \(unique.count) endpoints from codebase!"
        } else {
            routeScanMessage = "No API routes detected in project files."
        }
        
        return unique
    }
    
    // MARK: - Killer Feature 3: Project .env Vault Importer
    
    @discardableResult
    func loadProjectDotEnv(workspacePath: String? = nil) -> Int {
        let root = workspacePath ?? AgentToolBox.shared.workspaceRoot ?? NSHomeDirectory()
        let fm = FileManager.default
        let envCandidates = [
            (root as NSString).appendingPathComponent(".env"),
            (root as NSString).appendingPathComponent(".env.local"),
            (root as NSString).appendingPathComponent("backend/.env"),
            (root as NSString).appendingPathComponent("server/.env")
        ]
        
        var loadedItems: [KeyValueItem] = []
        for candidate in envCandidates {
            guard fm.fileExists(atPath: candidate),
                  let content = try? String(contentsOfFile: candidate, encoding: .utf8) else { continue }
            
            let lines = content.components(separatedBy: .newlines)
            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
                if let eqIndex = trimmed.firstIndex(of: "=") {
                    let key = String(trimmed[..<eqIndex]).trimmingCharacters(in: .whitespaces)
                    var val = String(trimmed[trimmed.index(after: eqIndex)...]).trimmingCharacters(in: .whitespaces)
                    if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                        val = String(val.dropFirst().dropLast())
                    }
                    if !key.isEmpty && !loadedItems.contains(where: { $0.key == key }) {
                        loadedItems.append(KeyValueItem(key: key, value: val, isEnabled: true))
                    }
                }
            }
        }
        
        if !loadedItems.contains(where: { $0.key == "base_url" }) {
            loadedItems.insert(KeyValueItem(key: "base_url", value: "http://localhost:3000", isEnabled: true), at: 0)
        }
        
        if !loadedItems.isEmpty {
            if let existingIdx = environments.firstIndex(where: { $0.name == "Project (.env)" }) {
                environments[existingIdx].variables = loadedItems
                activeEnvironment = environments[existingIdx]
            } else {
                let newEnv = APIEnvironment(name: "Project (.env)", variables: loadedItems, isActive: true)
                environments.insert(newEnv, at: 0)
                activeEnvironment = newEnv
            }
            saveData()
        }
        
        return loadedItems.count
    }
    
    // MARK: - Killer Feature 4: Modern Multi-Language Code & SDK Generator
    
    func generateCodeSnippet(for request: APIRequest, language: CodeSnippetLanguage) -> String {
        let resolvedURL = resolveVariables(request.url)
        let method = request.method
        
        switch language {
        case .curl:
            return exportCURL(request)
            
        case .swift:
            var code = "import Foundation\n\n"
            code += "guard let url = URL(string: \"\(resolvedURL)\") else { return }\n"
            code += "var request = URLRequest(url: url)\n"
            code += "request.httpMethod = \"\(method)\"\n"
            for (k, v) in request.headers {
                code += "request.setValue(\"\(resolveVariables(v))\", forHTTPHeaderField: \"\(k)\")\n"
            }
            if let body = request.body, !body.isEmpty && method != "GET" {
                let escaped = body.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                code += "request.httpBody = \"\(escaped)\".data(using: .utf8)\n"
            }
            code += "\nlet (data, response) = try await URLSession.shared.data(for: request)\n"
            code += "if let str = String(data: data, encoding: .utf8) {\n"
            code += "    print(\"Response: \\(str)\")\n"
            code += "}\n"
            return code
            
        case .typescript:
            var headersObj = "{\n"
            for (k, v) in request.headers {
                headersObj += "    \"\(k)\": \"\(resolveVariables(v))\",\n"
            }
            headersObj += "  }"
            
            var code = "const response = await fetch(\"\(resolvedURL)\", {\n"
            code += "  method: \"\(method)\",\n"
            code += "  headers: \(headersObj),\n"
            if let body = request.body, !body.isEmpty && method != "GET" {
                code += "  body: JSON.stringify(\(body.trimmingCharacters(in: .whitespacesAndNewlines))),\n"
            }
            code += "});\n\n"
            code += "const data = await response.json();\n"
            code += "console.log(data);\n"
            return code
            
        case .python:
            var headersDict = "{\n"
            for (k, v) in request.headers {
                headersDict += "    \"\(k)\": \"\(resolveVariables(v))\",\n"
            }
            headersDict += "}"
            
            var code = "import httpx\n\n"
            code += "url = \"\(resolvedURL)\"\n"
            code += "headers = \(headersDict)\n"
            if let body = request.body, !body.isEmpty && method != "GET" {
                code += "data = \(body.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
                code += "with httpx.Client() as client:\n"
                code += "    response = client.request(\"\(method)\", url, headers=headers, json=data)\n"
            } else {
                code += "\nwith httpx.Client() as client:\n"
                code += "    response = client.request(\"\(method)\", url, headers=headers)\n"
            }
            code += "    print(response.status_code, response.text)\n"
            return code
            
        case .rust:
            var code = "use reqwest::Client;\n\n"
            code += "let client = Client::new();\n"
            code += "let response = client\n"
            code += "    .\(method.lowercased())(\"\(resolvedURL)\")\n"
            for (k, v) in request.headers {
                code += "    .header(\"\(k)\", \"\(resolveVariables(v))\")\n"
            }
            if let body = request.body, !body.isEmpty && method != "GET" {
                let escaped = body.replacingOccurrences(of: "\"", with: "\\\"")
                code += "    .body(\"\(escaped)\")\n"
            }
            code += "    .send()\n"
            code += "    .await?;\n\n"
            code += "let body = response.text().await?;\n"
            code += "println!(\"{}\", body);\n"
            return code
        }
    }
}
