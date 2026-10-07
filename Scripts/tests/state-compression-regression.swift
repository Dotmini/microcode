import Foundation
import Compression

// Include StateCompressionEngine directly for standalone regression test execution
public final class StateCompressionEngine: Sendable {
    public static let shared = StateCompressionEngine()
    
    public static func compress(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
        defer { destinationBuffer.deallocate() }
        
        let compressedSize = data.withUnsafeBytes { rawBuffer -> Int in
            guard let sourceAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_encode_buffer(
                destinationBuffer,
                data.count,
                sourceAddress,
                data.count,
                nil,
                COMPRESSION_LZFSE
            )
        }
        guard compressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: compressedSize)
    }
    
    public static func decompress(_ data: Data, originalCapacity: Int = 0) -> Data? {
        guard !data.isEmpty else { return Data() }
        var bufferSize = max(originalCapacity, data.count * 4, 32768)
        
        while bufferSize <= 64 * 1024 * 1024 { // Up to 64MB
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            let decompressedSize = data.withUnsafeBytes { rawBuffer -> Int in
                guard let sourceAddress = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(
                    destinationBuffer,
                    bufferSize,
                    sourceAddress,
                    data.count,
                    nil,
                    COMPRESSION_LZFSE
                )
            }
            
            if decompressedSize > 0 && decompressedSize < bufferSize {
                let result = Data(bytes: destinationBuffer, count: decompressedSize)
                destinationBuffer.deallocate()
                return result
            }
            destinationBuffer.deallocate()
            bufferSize *= 4
        }
        return nil
    }
    
    public static func compressString(_ string: String) -> Data? {
        guard !string.isEmpty else { return Data() }
        guard let data = string.data(using: .utf8) else { return nil }
        return compress(data)
    }
    
    public static func decompressString(_ data: Data, originalLength: Int = 0) -> String? {
        guard let decompressedData = decompress(data, originalCapacity: originalLength) else { return nil }
        return String(data: decompressedData, encoding: .utf8)
    }
}

struct CodeFile: Identifiable, Equatable {
    let id: UUID
    var name: String
    var path: String
    private var _content: String
    private var _compressedData: Data?
    var language: String
    var isUnsaved: Bool
    var isReadOnly: Bool = false
    var usesPlainTextMode: Bool = false
    var originalByteSize: Int = 0
    var isTruncated: Bool = false

    var isCompressed: Bool {
        _compressedData != nil && _content.isEmpty
    }

    var compressedByteSize: Int {
        _compressedData?.count ?? _content.utf8.count
    }

    var content: String {
        get {
            if !_content.isEmpty {
                return _content
            }
            if let data = _compressedData, let decompressed = StateCompressionEngine.decompressString(data) {
                return decompressed
            }
            return _content
        }
        set {
            _content = newValue
            _compressedData = nil
        }
    }

    init(
        id: UUID = UUID(),
        name: String,
        path: String,
        content: String,
        language: String,
        isUnsaved: Bool,
        isReadOnly: Bool = false,
        usesPlainTextMode: Bool = false,
        originalByteSize: Int = 0,
        isTruncated: Bool = false
    ) {
        self.id = id
        self.name = name
        self.path = path
        self._content = content
        self._compressedData = nil
        self.language = language
        self.isUnsaved = isUnsaved
        self.isReadOnly = isReadOnly
        self.usesPlainTextMode = usesPlainTextMode
        self.originalByteSize = originalByteSize
        self.isTruncated = isTruncated
    }

    mutating func compress() {
        guard !_content.isEmpty, _content.utf8.count > 256 else { return }
        if let compressed = StateCompressionEngine.compressString(_content) {
            _compressedData = compressed
            _content = ""
        }
    }

    mutating func decompress() {
        guard let data = _compressedData else { return }
        if let decompressed = StateCompressionEngine.decompressString(data) {
            _content = decompressed
            _compressedData = nil
        }
    }

    static func == (lhs: CodeFile, rhs: CodeFile) -> Bool {
        lhs.id == rhs.id
    }
}

print("🧪 Testing StateCompressionEngine (LZFSE)...")

// 1. Generate realistic Swift code buffer (50KB)
var sampleCode = "// Swift Source Code Sample\n"
for i in 1...1000 {
    sampleCode += "func calculateValue_\(i)(input: Int) -> Double {\n"
    sampleCode += "    let factor = 3.14159 * Double(input)\n"
    sampleCode += "    return factor * \(i).0\n"
    sampleCode += "}\n\n"
}

let originalBytes = sampleCode.utf8.count
print("  Original Code Size: \(originalBytes) bytes (~50KB)")

// Benchmark Compression
let startTime = CFAbsoluteTimeGetCurrent()
guard let compressedData = StateCompressionEngine.compressString(sampleCode) else {
    fatalError("❌ Compression failed")
}
let compressDurationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
let compressedBytes = compressedData.count
let ratio = Double(compressedBytes) / Double(originalBytes) * 100

print("  Compressed Size: \(compressedBytes) bytes (\(String(format: "%.1f", ratio))% of original)")
print("  Compression Speed: \(String(format: "%.3f", compressDurationMs)) ms")
assert(ratio < 50.0, "Compression ratio should be under 50% for source code")
assert(compressDurationMs < 10.0, "Compression should take under 10ms")

// Benchmark Decompression
let decompressStart = CFAbsoluteTimeGetCurrent()
guard let decompressedCode = StateCompressionEngine.decompressString(compressedData) else {
    fatalError("❌ Decompression failed")
}
let decompressDurationMs = (CFAbsoluteTimeGetCurrent() - decompressStart) * 1000
print("  Decompression Speed: \(String(format: "%.3f", decompressDurationMs)) ms")
assert(decompressedCode == sampleCode, "Decompressed code must match original exactly")
assert(decompressDurationMs < 5.0, "Decompression must be sub-5ms (fast enough for 120fps)")
print("  ✅ StateCompressionEngine: PASS")

// 2. Test CodeFile Transparent Compression
print("\n🧪 Testing CodeFile Transparent State Compression...")
var file = CodeFile(
    name: "Calculator.swift",
    path: "/path/to/Calculator.swift",
    content: sampleCode,
    language: "swift",
    isUnsaved: false
)

assert(!file.isCompressed, "File should start uncompressed")
assert(file.content == sampleCode, "Content should match initial string")

// Compress inactive tab
file.compress()
assert(file.isCompressed, "File should be compressed after file.compress()")
assert(file.compressedByteSize == compressedBytes, "Compressed byte size should match LZFSE data size")

// Test Transparent Read
let readContent = file.content
assert(readContent == sampleCode, "Reading file.content should transparently decompress and return original string")

// Test Explicit Decompress
file.decompress()
assert(!file.isCompressed, "File should no longer be compressed after decompress()")
assert(file.content == sampleCode, "Content should still match exactly")

// Test Updating Content while Compressed
file.compress()
assert(file.isCompressed)
file.content = "func newQuickFunction() {}"
assert(!file.isCompressed, "Assigning content should clear compressed data")
assert(file.content == "func newQuickFunction() {}")
print("  ✅ CodeFile Transparent Compression: PASS")

print("\n🎉 ALL ADVANCED STATE COMPRESSION & IDLE MEMORY TESTS PASSED!")
