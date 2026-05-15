import Foundation
import Combine

class DataFrameService: ObservableObject {
    static let shared = DataFrameService()
    private let baseURL = "http://localhost:3000/api/dataframe"
    
    private init() {}
    
    func loadDataFrame(path: String) async throws -> String {
        let url = URL(string: "\(baseURL)/load")!
        let body = ["path": path]
        let requestData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = requestData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = response["id"] as? String else {
            throw NSError(domain: "DataFrameService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        return id
    }
    
    func getSchema(id: String) async throws -> [String: String] {
        let url = URL(string: "\(baseURL)/schema")!
        let body = ["id": id]
        let requestData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = requestData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let schema = response["schema"] as? [String: String] else {
            throw NSError(domain: "DataFrameService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        return schema
    }
    
    // Returns array of dictionaries (rows)
    func getSlice(id: String, offset: Int64, limit: Int) async throws -> [[String: Any]] {
        let url = URL(string: "\(baseURL)/slice")!
        let body: [String: Any] = ["id": id, "offset": offset, "limit": limit]
        let requestData = try JSONSerialization.data(withJSONObject: body)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = requestData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sliceData = response["data"] as? [[String: Any]] else {
            // It's possible sliceData is empty or different format depending on Polars output
             if let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let _ = response["data"] as? [Any] { // empty array case
                 return []
             }
            throw NSError(domain: "DataFrameService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        return sliceData
    }
}
