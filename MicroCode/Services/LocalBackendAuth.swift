import Foundation

/// A per-launch capability shared only with the child backend. Never persist it.
enum LocalBackendAuth {
    static let token: String = {
        if let value = ProcessInfo.processInfo.environment["MICROCODE_LOCAL_API_TOKEN"], value.count >= 32 { return value }
        return UUID().uuidString + UUID().uuidString
    }()

    static func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        if ["127.0.0.1", "localhost", "::1"].contains(url.host ?? ""), url.port == 3000,
           ["http", "ws"].contains(url.scheme ?? "") {
            request.setValue(token, forHTTPHeaderField: "X-MicroCode-Token")
        }
        return request
    }
}
