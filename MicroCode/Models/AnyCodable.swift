
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
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                try container.encode(n.boolValue)
            } else {
                try container.encode(n.doubleValue)
            }
        case let x as String: try container.encode(x)
        case let x as [Any]: try container.encode(x.map { AnyCodable($0) })
        case let x as [String: Any]: try container.encode(x.mapValues { AnyCodable($0) })
        case is NSNull: try container.encodeNil()
        default: try container.encodeNil()
        }
    }

    static func unwrapJSONObject(_ dict: [String: AnyCodable]) -> [String: Any] {
        var out: [String: Any] = [:]
        out.reserveCapacity(dict.count)
        for (k, v) in dict {
            if let unwrapped = unwrapValue(v.value) {
                out[k] = unwrapped
            }
        }
        return out
    }

    private static func unwrapValue(_ raw: Any) -> Any? {
        switch raw {
        case let sub as AnyCodable:
            return unwrapValue(sub.value)
        case is NSNull:
            return nil
        case let b as Bool:
            return b
        case let i as Int:
            return i
        case let d as Double:
            return d.isFinite ? d : nil
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() {
                return n.boolValue
            }
            let d = n.doubleValue
            return d.isFinite ? n : nil
        case let s as String:
            return s
        case let arr as [Any]:
            return arr.compactMap { unwrapValue($0) }
        case let dict as [String: Any]:
            var clean: [String: Any] = [:]
            for (k, v) in dict {
                if let uv = unwrapValue(v) {
                    clean[k] = uv
                }
            }
            return clean
        default:
            return "\(raw)"
        }
    }
}
