import Foundation

let str = "Hello, MicroCode!"
guard let data = str.data(using: .utf8) else { fatalError() }
do {
    let compressed = try (data as NSData).compressed(using: .lzfse)
    print("Compressed size: \(compressed.length)")
} catch {
    print("Error: \(error)")
}
