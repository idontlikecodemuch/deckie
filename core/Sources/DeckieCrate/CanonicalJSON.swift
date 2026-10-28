import Foundation

/// A JSON value as the crate writes it: objects unordered here (the printer sorts the keys), numbers carrying the
/// decimals they are written with.
indirect enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case number(Double, decimals: Int)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

/// Turns `Encodable` values into `JSONValue`s and prints them in the crate's canonical form
/// (docs/architecture/crate-format.md, "How it is written"): keys sorted by byte, no spaces, `null` for every nil,
/// fractional numbers with the decimals `decimals` gives for their field name.
enum CanonicalJSON {
    /// Encodes `value` into a tree. `decimals` maps a field name to the decimals of the fractional numbers under it;
    /// a fractional number under an unlisted name, or a NaN or infinite one, is an error naming its path.
    static func tree<T: Encodable>(_ value: T, decimals: [String: Int]) throws -> JSONValue {
        let root = Node()
        try value.encode(to: TreeEncoder(node: root, codingPath: [], decimals: decimals))
        return root.value
    }

    /// The canonical text of `value`. With `linePerTopLevelItem`, each item of an array directly under the top-level
    /// object starts on its own line (crate.json's tracks).
    static func text(_ value: JSONValue, linePerTopLevelItem: Bool = false) -> String {
        var out = ""
        write(value, into: &out, depth: 0, breakItems: linePerTopLevelItem)
        out += "\n"
        return out
    }

    private static func write(_ v: JSONValue, into out: inout String, depth: Int, breakItems: Bool) {
        switch v {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .int(let i): out += String(i)
        case .number(let x, let d): out += number(x, decimals: d)
        case .string(let s): string(s, into: &out)
        case .array(let items):
            let split = breakItems && depth == 1 && !items.isEmpty
            out += "["
            for (i, item) in items.enumerated() {
                if i > 0 { out += "," }
                if split { out += "\n" }
                write(item, into: &out, depth: depth + 1, breakItems: breakItems)
            }
            if split { out += "\n" }
            out += "]"
        case .object(let members):
            out += "{"
            for (i, key) in members.keys.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }).enumerated() {
                if i > 0 { out += "," }
                string(key, into: &out)
                out += ":"
                write(members[key]!, into: &out, depth: depth + 1, breakItems: breakItems)
            }
            out += "}"
        }
    }

    /// `x` rounded to `decimals` places (correctly rounded from its exact binary value, as Python's `round` does),
    /// trailing zeros dropped, one digit kept after the point; negative zero is written as 0.0.
    static func number(_ x: Double, decimals: Int) -> String {
        var s = String(format: "%.\(decimals)f", x)
        if let dot = s.firstIndex(of: ".") {
            while s.last == "0" && s.index(before: s.endIndex) > s.index(after: dot) { s.removeLast() }
        } else {
            s += ".0"
        }
        if s.first == "-" && s.dropFirst().allSatisfy({ $0 == "0" || $0 == "." }) { s.removeFirst() }
        return s
    }

    /// A JSON string: `"` and `\` escaped, control characters as `\n`, `\t` and the like or `\u00XX`; everything else,
    /// `/` and non-ASCII letters included, as it is (UTF-8).
    private static func string(_ s: String, into out: inout String) {
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
                if u.value < 0x20 {
                    let hex = String(u.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(u)
                }
            }
        }
        out += "\""
    }
}

/// The path of a coding position as the crate's messages write it: `tracks[2].grid.bpm`.
func fieldPath(_ path: [CodingKey]) -> String {
    var s = ""
    for k in path {
        if let i = k.intValue, k.stringValue.hasPrefix("Index") {
            s += "[\(i)]"
        } else {
            s += s.isEmpty ? k.stringValue : "." + k.stringValue
        }
    }
    return s
}

// MARK: - The encoder

/// A place in the tree being built; containers write into it.
private final class Node {
    enum Content { case unset, leaf(JSONValue), array([Node]), object([String: Node]) }
    var content: Content = .unset

    var value: JSONValue {
        switch content {
        case .unset: return .null
        case .leaf(let v): return v
        case .array(let items): return .array(items.map(\.value))
        case .object(let members): return .object(members.mapValues(\.value))
        }
    }

    func child(_ key: String) -> Node {
        let n = Node()
        if case .object(var members) = content {
            members[key] = n
            content = .object(members)
        }
        return n
    }

    func append() -> Node {
        let n = Node()
        if case .array(var items) = content {
            items.append(n)
            content = .array(items)
        }
        return n
    }
}

private struct IndexKey: CodingKey {
    var intValue: Int?
    var stringValue: String
    init(_ i: Int) { intValue = i; stringValue = "Index \(i)" }
    init?(intValue: Int) { self.init(intValue) }
    init?(stringValue: String) { return nil }
}

private struct TreeEncoder: Encoder {
    let node: Node
    let codingPath: [CodingKey]
    let decimals: [String: Int]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        if case .unset = node.content { node.content = .object([:]) }
        return KeyedEncodingContainer(KeyedTree<Key>(node: node, codingPath: codingPath, decimals: decimals))
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        if case .unset = node.content { node.content = .array([]) }
        return UnkeyedTree(node: node, codingPath: codingPath, decimals: decimals)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        SingleTree(node: node, codingPath: codingPath, decimals: decimals)
    }
}

/// The JSON value of a leaf: whole numbers as integers, fractional ones with the decimals of their field (the
/// nearest enclosing key that is not an array index).
private func leaf(_ x: Double, _ path: [CodingKey], _ decimals: [String: Int]) throws -> JSONValue {
    guard x.isFinite else {
        throw EncodingError.invalidValue(x, .init(codingPath: path, debugDescription: "\(x) is not a finite number"))
    }
    guard let name = path.last(where: { $0.intValue == nil })?.stringValue, let d = decimals[name] else {
        throw EncodingError.invalidValue(x, .init(codingPath: path,
            debugDescription: "no decimals are documented for this field (CrateFormat.decimals)"))
    }
    return .number(x, decimals: d)
}

private func encodeAny<T: Encodable>(_ value: T, into node: Node, _ path: [CodingKey], _ decimals: [String: Int]) throws {
    switch value {
    case let x as Bool: node.content = .leaf(.bool(x))
    case let x as String: node.content = .leaf(.string(x))
    case let x as Int: node.content = .leaf(.int(x))
    case let x as Double: node.content = .leaf(try leaf(x, path, decimals))
    case let x as Float: node.content = .leaf(try leaf(Double(x), path, decimals))
    default: try value.encode(to: TreeEncoder(node: node, codingPath: path, decimals: decimals))
    }
}

private struct KeyedTree<Key: CodingKey>: KeyedEncodingContainerProtocol {
    let node: Node
    let codingPath: [CodingKey]
    let decimals: [String: Int]

    private func put<T: Encodable>(_ value: T, _ key: Key) throws {
        try encodeAny(value, into: node.child(key.stringValue), codingPath + [key], decimals)
    }
    private func putOptional<T: Encodable>(_ value: T?, _ key: Key) throws {
        if let value { try put(value, key) } else { node.child(key.stringValue).content = .leaf(.null) }
    }

    mutating func encodeNil(forKey key: Key) throws { node.child(key.stringValue).content = .leaf(.null) }
    mutating func encode(_ value: Bool, forKey key: Key) throws { try put(value, key) }
    mutating func encode(_ value: String, forKey key: Key) throws { try put(value, key) }
    mutating func encode(_ value: Double, forKey key: Key) throws { try put(value, key) }
    mutating func encode(_ value: Float, forKey key: Key) throws { try put(value, key) }
    mutating func encode(_ value: Int, forKey key: Key) throws { try put(value, key) }
    mutating func encode(_ value: Int8, forKey key: Key) throws { try put(Int(value), key) }
    mutating func encode(_ value: Int16, forKey key: Key) throws { try put(Int(value), key) }
    mutating func encode(_ value: Int32, forKey key: Key) throws { try put(Int(value), key) }
    mutating func encode(_ value: Int64, forKey key: Key) throws { try put(Int(value), key) }
    mutating func encode(_ value: UInt, forKey key: Key) throws { try put(Int(value), key) }
    mutating func encode(_ value: UInt8, forKey key: Key) throws { try put(Int(value), key) }
    mutating func encode(_ value: UInt16, forKey key: Key) throws { try put(Int(value), key) }
    mutating func encode(_ value: UInt32, forKey key: Key) throws { try put(Int(value), key) }
    mutating func encode(_ value: UInt64, forKey key: Key) throws { try put(Int(value), key) }
    mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws { try put(value, key) }

    // A nil optional is written as null, never left out (the crate's records list every field).
    mutating func encodeIfPresent(_ value: Bool?, forKey key: Key) throws { try putOptional(value, key) }
    mutating func encodeIfPresent(_ value: String?, forKey key: Key) throws { try putOptional(value, key) }
    mutating func encodeIfPresent(_ value: Double?, forKey key: Key) throws { try putOptional(value, key) }
    mutating func encodeIfPresent(_ value: Float?, forKey key: Key) throws { try putOptional(value, key) }
    mutating func encodeIfPresent(_ value: Int?, forKey key: Key) throws { try putOptional(value, key) }
    mutating func encodeIfPresent(_ value: Int8?, forKey key: Key) throws { try putOptional(value.map { Int($0) }, key) }
    mutating func encodeIfPresent(_ value: Int16?, forKey key: Key) throws { try putOptional(value.map { Int($0) }, key) }
    mutating func encodeIfPresent(_ value: Int32?, forKey key: Key) throws { try putOptional(value.map { Int($0) }, key) }
    mutating func encodeIfPresent(_ value: Int64?, forKey key: Key) throws { try putOptional(value.map { Int($0) }, key) }
    mutating func encodeIfPresent(_ value: UInt?, forKey key: Key) throws { try putOptional(value.map { Int($0) }, key) }
    mutating func encodeIfPresent(_ value: UInt8?, forKey key: Key) throws { try putOptional(value.map { Int($0) }, key) }
    mutating func encodeIfPresent(_ value: UInt16?, forKey key: Key) throws { try putOptional(value.map { Int($0) }, key) }
    mutating func encodeIfPresent(_ value: UInt32?, forKey key: Key) throws { try putOptional(value.map { Int($0) }, key) }
    mutating func encodeIfPresent(_ value: UInt64?, forKey key: Key) throws { try putOptional(value.map { Int($0) }, key) }
    mutating func encodeIfPresent<T: Encodable>(_ value: T?, forKey key: Key) throws { try putOptional(value, key) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type,
                                                        forKey key: Key) -> KeyedEncodingContainer<NestedKey> {
        let child = node.child(key.stringValue)
        child.content = .object([:])
        return KeyedEncodingContainer(KeyedTree<NestedKey>(node: child, codingPath: codingPath + [key], decimals: decimals))
    }
    mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
        let child = node.child(key.stringValue)
        child.content = .array([])
        return UnkeyedTree(node: child, codingPath: codingPath + [key], decimals: decimals)
    }
    mutating func superEncoder() -> Encoder {
        TreeEncoder(node: node.child("super"), codingPath: codingPath, decimals: decimals)
    }
    mutating func superEncoder(forKey key: Key) -> Encoder {
        TreeEncoder(node: node.child(key.stringValue), codingPath: codingPath + [key], decimals: decimals)
    }
}

private struct UnkeyedTree: UnkeyedEncodingContainer {
    let node: Node
    let codingPath: [CodingKey]
    let decimals: [String: Int]
    var count: Int {
        if case .array(let items) = node.content { return items.count }
        return 0
    }

    private func put<T: Encodable>(_ value: T) throws {
        let path = codingPath + [IndexKey(count)]
        try encodeAny(value, into: node.append(), path, decimals)
    }

    mutating func encodeNil() throws { node.append().content = .leaf(.null) }
    mutating func encode(_ value: Bool) throws { try put(value) }
    mutating func encode(_ value: String) throws { try put(value) }
    mutating func encode(_ value: Double) throws { try put(value) }
    mutating func encode(_ value: Float) throws { try put(value) }
    mutating func encode(_ value: Int) throws { try put(value) }
    mutating func encode(_ value: Int8) throws { try put(Int(value)) }
    mutating func encode(_ value: Int16) throws { try put(Int(value)) }
    mutating func encode(_ value: Int32) throws { try put(Int(value)) }
    mutating func encode(_ value: Int64) throws { try put(Int(value)) }
    mutating func encode(_ value: UInt) throws { try put(Int(value)) }
    mutating func encode(_ value: UInt8) throws { try put(Int(value)) }
    mutating func encode(_ value: UInt16) throws { try put(Int(value)) }
    mutating func encode(_ value: UInt32) throws { try put(Int(value)) }
    mutating func encode(_ value: UInt64) throws { try put(Int(value)) }
    mutating func encode<T: Encodable>(_ value: T) throws { try put(value) }

    mutating func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
        let path = codingPath + [IndexKey(count)]
        let child = node.append()
        child.content = .object([:])
        return KeyedEncodingContainer(KeyedTree<NestedKey>(node: child, codingPath: path, decimals: decimals))
    }
    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let path = codingPath + [IndexKey(count)]
        let child = node.append()
        child.content = .array([])
        return UnkeyedTree(node: child, codingPath: path, decimals: decimals)
    }
    mutating func superEncoder() -> Encoder {
        let path = codingPath + [IndexKey(count)]
        return TreeEncoder(node: node.append(), codingPath: path, decimals: decimals)
    }
}

private struct SingleTree: SingleValueEncodingContainer {
    let node: Node
    let codingPath: [CodingKey]
    let decimals: [String: Int]

    private func put<T: Encodable>(_ value: T) throws { try encodeAny(value, into: node, codingPath, decimals) }

    mutating func encodeNil() throws { node.content = .leaf(.null) }
    mutating func encode(_ value: Bool) throws { try put(value) }
    mutating func encode(_ value: String) throws { try put(value) }
    mutating func encode(_ value: Double) throws { try put(value) }
    mutating func encode(_ value: Float) throws { try put(value) }
    mutating func encode(_ value: Int) throws { try put(value) }
    mutating func encode(_ value: Int8) throws { try put(Int(value)) }
    mutating func encode(_ value: Int16) throws { try put(Int(value)) }
    mutating func encode(_ value: Int32) throws { try put(Int(value)) }
    mutating func encode(_ value: Int64) throws { try put(Int(value)) }
    mutating func encode(_ value: UInt) throws { try put(Int(value)) }
    mutating func encode(_ value: UInt8) throws { try put(Int(value)) }
    mutating func encode(_ value: UInt16) throws { try put(Int(value)) }
    mutating func encode(_ value: UInt32) throws { try put(Int(value)) }
    mutating func encode(_ value: UInt64) throws { try put(Int(value)) }
    mutating func encode<T: Encodable>(_ value: T) throws { try put(value) }
}
