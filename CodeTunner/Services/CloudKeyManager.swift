import Foundation

enum CloudKeyManager {
    // This uses a simple XOR cipher to hide the API key from plain text static analysis (e.g., `strings` command).
    // Note: Client-side keys can STILL be intercepted via proxy tools (Charles, Proxyman). 
    // To be 100% secure, you MUST use a backend proxy.
    
    // Developer: Replace these byte arrays with your XOR'd keys.
    // Use the python script or Swift script to generate the byte array:
    // "sk-12345...".utf8.map { $0 ^ 42 }
    
    // Example: [73, 65, 87, ...]
    private static let geminiEncrypted: [UInt8] = [] 
    private static let deepseekEncrypted: [UInt8] = []
    private static let openaiEncrypted: [UInt8] = []
    
    static func getKey(for provider: StreamableAIProvider) -> String {
        switch provider {
        case .gemini:
            return decrypt(geminiEncrypted)
        case .deepseek:
            return decrypt(deepseekEncrypted)
        case .openai:
            return decrypt(openaiEncrypted)
        default:
            return ""
        }
    }
    
    private static func decrypt(_ bytes: [UInt8]) -> String {
        guard !bytes.isEmpty else { return "" }
        let decrypted = bytes.map { $0 ^ 42 }
        return String(bytes: decrypted, encoding: .utf8) ?? ""
    }
}
