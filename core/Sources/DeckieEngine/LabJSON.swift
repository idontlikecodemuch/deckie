import Foundation
import DeckieCore

/// A JSON value with its object keys in order, written the way Python's `json.dump(obj, f, separators=(",", ":"))`
/// writes the lab's feature files: no spaces, keys in insertion order, non-ASCII escaped as `\uXXXX`, floats in their
/// shortest round-trip form with `.0` on whole numbers, integers without a decimal point. Python writes a non-finite
/// float as `NaN` or `Infinity`, which is not JSON; this writes `null` instead (the only case: the integrated loudness
/// of digital silence, minus infinity).
public indirect enum JSONValue: Sendable, Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([Member])

    public struct Member: Sendable, Equatable {
        public var key: String
        public var value: JSONValue
        public init(_ key: String, _ value: JSONValue) { self.key = key; self.value = value }
    }

    /// The value of `key` in an object (the first, if repeated); nil for a missing key or a non-object.
    public subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    /// The keys of an object, in order; empty for anything else.
    public var keys: [String] {
        guard case .object(let members) = self else { return [] }
        return members.map(\.key)
    }

    /// The compact text.
    public var text: String {
        var out = ""
        write(into: &out)
        return out
    }

    /// The compact text as UTF-8 bytes.
    public var data: Data { Data(text.utf8) }

    func write(into out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .number(let x): out += x.isFinite ? "\(x)" : "null"
        case .string(let s): JSONValue.writeString(s, into: &out)
        case .array(let a):
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                v.write(into: &out)
            }
            out += "]"
        case .object(let members):
            out += "{"
            for (i, m) in members.enumerated() {
                if i > 0 { out += "," }
                JSONValue.writeString(m.key, into: &out)
                out += ":"
                m.value.write(into: &out)
            }
            out += "}"
        }
    }

    /// Python's `json.dumps` string with `ensure_ascii=True`: `"` and `\` escaped, the five short escapes, and every
    /// other character outside space to tilde as `\uXXXX` (UTF-16, so a surrogate pair above U+FFFF).
    static func writeString(_ s: String, into out: inout String) {
        out += "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value >= 0x20 && u.value <= 0x7E {
                    out.unicodeScalars.append(u)
                } else {
                    for unit in String(u).utf16 { out += String(format: "\\u%04x", unit) }
                }
            }
        }
        out += "\""
    }
}

// Building values from Swift.
extension JSONValue {
    /// A number, or null for nil.
    static func num(_ x: Double?) -> JSONValue { x.map { .number($0) } ?? .null }
    /// Python's `round(x, places)` as a number, or null for nil.
    static func round(_ x: Double?, _ places: Int) -> JSONValue {
        guard let x else { return .null }
        return x.isFinite ? .number(Py.round(x, places)) : .number(x)
    }
    /// The lab's `rlist(a, nd)`.
    static func roundList(_ a: [Double], _ places: Int) -> JSONValue { .array(a.map { round($0, places) }) }
    static func integer(_ i: Int?) -> JSONValue { i.map { .int($0) } ?? .null }
    static func text(_ s: String?) -> JSONValue { s.map { .string($0) } ?? .null }
}
