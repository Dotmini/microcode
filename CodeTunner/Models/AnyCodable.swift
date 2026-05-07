
import Foundation

struct AnyCodable: Codable, CustomStringConvertible {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(value: Any) {
        self.value = value
    }
    
    var description: String {
        return "\(value)"
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let x = try? container.decode(Bool.self) { value = x }
        else if let x = try? container.decode(Int.self) { value = x }
        else if let x = try? container.decode(Double.self) { value = x }
        else if let x = try? container.decode(String.self) { value = x }
        else if let x = try? container.decode([AnyCodable].self) { value = x.map { $0.value } }
        else if let x = try? container.decode(Dictionary<String, AnyCodable>.self) { value = x.mapValues { $0.value } }
        else if container.decodeNil() { value = NSNull() }
        else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let x as Bool: try container.encode(x)
        case let x as Int: try container.encode(x)
        case let x as Double: try container.encode(x)
        case let x as String: try container.encode(x)
        case let x as [Any]: try container.encode(x.map { AnyCodable($0) })
        case let x as [String: Any]: try container.encode(x.mapValues { AnyCodable($0) })
        case is NSNull: try container.encodeNil()
        default: throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyCodable value cannot be encoded"))
        }
    }
}
