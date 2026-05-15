//
//  DatabaseService.swift
//  MicroCode
//
//  Created by SPU AI CLUB
//  Copyright © 2024 AIPRENEUR. All rights reserved.
//

import Foundation
import Combine

enum DatabaseType: String, CaseIterable, Identifiable {
    case sqlite
    case postgres
    case mysql
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .sqlite: return "SQLite"
        case .postgres: return "PostgreSQL"
        case .mysql: return "MySQL"
        }
    }
    
    var placeholder: String {
        switch self {
        case .sqlite: return "sqlite:/path/to/db.sqlite"
        case .postgres: return "postgres://user:password@localhost/dbname"
        case .mysql: return "mysql://user:password@localhost/dbname"
        }
    }
}

struct QueryResult: Codable {
    let columns: [String]
    let rows: [[AnyCodable]]
    let affectedRows: Int
    
    enum CodingKeys: String, CodingKey {
        case columns, rows, affectedRows = "affected_rows"
    }
}

// Helper for heterogeneous JSON arrays (Imported from Models)

class DatabaseService: ObservableObject {
    static let shared = DatabaseService()
    
    @Published var activeConnectionId: String?
    @Published var isConnecting = false
    @Published var connectionError: String?
    
    private let baseURL = "http://127.0.0.1:3000/api/db"
    
    func connect(type: DatabaseType, connectionString: String) async -> Bool {
        await MainActor.run {
            self.isConnecting = true
            self.connectionError = nil
        }
        
        defer {
            Task { await MainActor.run { self.isConnecting = false } }
        }
        
        guard let url = URL(string: "\(baseURL)/connect") else { return false }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["db_type": type.rawValue, "connection_string": connectionString]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errorMsg = String(data: data, encoding: .utf8) ?? "Unknown Error"
                await MainActor.run { self.connectionError = errorMsg }
                return false
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               let id = json["connection_id"] {
                await MainActor.run { self.activeConnectionId = id }
                return true
            }
        } catch {
            await MainActor.run { self.connectionError = error.localizedDescription }
        }
        
        return false
    }
    
    func executeQuery(_ query: String) async throws -> QueryResult {
        guard let connectionId = activeConnectionId else {
            throw NSError(domain: "DatabaseService", code: 400, userInfo: [NSLocalizedDescriptionKey: "No active connection"])
        }
        
        guard let url = URL(string: "\(baseURL)/query") else {
            throw NSError(domain: "DatabaseService", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: String] = ["connection_id": connectionId, "query": query]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let errorMsg = String(data: data, encoding: .utf8) ?? "Query Execution Failed"
            throw NSError(domain: "DatabaseService", code: 500, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }
        
        return try JSONDecoder().decode(QueryResult.self, from: data)
    }
}
