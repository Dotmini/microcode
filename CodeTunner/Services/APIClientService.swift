//
//  APIClientService.swift
//  CodeTunner
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
        case .get: return .blue
        case .post: return .green
        case .put: return .orange
        case .delete: return .red
        case .patch: return .purple
        case .head: return .teal
        case .options: return .gray
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
        if isSuccess { return .green }
        if isRedirect { return .blue }
        if isClientError { return .orange }
        return .red
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
            
            let headerMap = Dictionary(uniqueKeysWithValues: httpResponse.allHeaderFields.compactMap { key, value in
                guard let k = key as? String, let v = value as? String else { return nil as (String, String)? }
                return (k, v)
            }.compactMap { $0 })
            
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
}
