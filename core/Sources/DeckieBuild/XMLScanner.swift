import Foundation

/// A small XML reader for files made of elements and attributes, such as rekordbox's collection export: it reports
/// each element's start (with its attributes, entities decoded) and end, and skips text, comments, CDATA, processing
/// instructions and the document type. Written here rather than taken from Foundation, whose XML parser on Linux and
/// Windows is a separate library on top of libxml2: this keeps the builder free of a runtime library for one file
/// format. It checks that tags nest and close, and names the line of the first problem.
enum XMLScanner {
    enum Event {
        case start(name: String, attributes: [String: String])
        case end(name: String)
    }

    struct Failure: Error, CustomStringConvertible {
        var line: Int
        var message: String
        var description: String { "line \(line): \(message)" }
    }

    static func scan(_ data: Data, _ handle: (Event) throws -> Void) throws {
        let b = [UInt8](data)
        var i = 0
        if b.count >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF { i = 3 }  // byte-order mark
        var stack: [String] = []
        var line = 1
        var lineCountedTo = 0
        func currentLine() -> Int {
            while lineCountedTo < min(i, b.count) {
                if b[lineCountedTo] == 0x0A { line += 1 }
                lineCountedTo += 1
            }
            return line
        }
        func fail(_ m: String) -> Failure { Failure(line: currentLine(), message: m) }
        func starts(_ s: String, at k: Int) -> Bool {
            let u = Array(s.utf8)
            return k + u.count <= b.count && Array(b[k..<(k + u.count)]) == u
        }
        /// Moves past the next `end` after `k`.
        func skip(past end: String, from k: Int) throws -> Int {
            let u = Array(end.utf8)
            var j = k
            while j + u.count <= b.count {
                if b[j] == u[0] && Array(b[j..<(j + u.count)]) == u { return j + u.count }
                j += 1
            }
            i = k
            throw fail("\"\(end)\" never comes")
        }
        func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }
        func isNameEnd(_ c: UInt8) -> Bool { isSpace(c) || c == 0x2F || c == 0x3E || c == 0x3D }

        while i < b.count {
            guard b[i] == 0x3C else { i += 1; continue }  // '<'
            if starts("<?", at: i) { i = try skip(past: "?>", from: i + 2); continue }
            if starts("<!--", at: i) { i = try skip(past: "-->", from: i + 4); continue }
            if starts("<![CDATA[", at: i) { i = try skip(past: "]]>", from: i + 9); continue }
            if starts("<!", at: i) {  // a document type, perhaps with an internal subset in brackets
                var depth = 0, j = i + 2
                while j < b.count {
                    if b[j] == 0x5B { depth += 1 } else if b[j] == 0x5D { depth -= 1 } else if b[j] == 0x3E && depth <= 0 { break }
                    j += 1
                }
                guard j < b.count else { throw fail("a <! declaration never ends") }
                i = j + 1
                continue
            }
            if starts("</", at: i) {
                var j = i + 2
                while j < b.count && !isNameEnd(b[j]) { j += 1 }
                let name = String(decoding: b[(i + 2)..<j], as: UTF8.self)
                while j < b.count && isSpace(b[j]) { j += 1 }
                guard j < b.count && b[j] == 0x3E else { throw fail("the end tag </\(name) is not closed") }
                guard let open = stack.popLast() else { throw fail("</\(name)> closes nothing") }
                guard open == name else { throw fail("</\(name)> closes <\(open)>") }
                try handle(.end(name: name))
                i = j + 1
                continue
            }
            // A start tag.
            var j = i + 1
            while j < b.count && !isNameEnd(b[j]) { j += 1 }
            guard j > i + 1 else { throw fail("a \"<\" that starts no tag") }
            let name = String(decoding: b[(i + 1)..<j], as: UTF8.self)
            var attributes: [String: String] = [:]
            var selfClosing = false
            while true {
                while j < b.count && isSpace(b[j]) { j += 1 }
                guard j < b.count else { throw fail("the tag <\(name) never ends") }
                if b[j] == 0x3E { j += 1; break }
                if b[j] == 0x2F {
                    guard j + 1 < b.count && b[j + 1] == 0x3E else { throw fail("a stray \"/\" in <\(name)>") }
                    selfClosing = true
                    j += 2
                    break
                }
                let a0 = j
                while j < b.count && !isNameEnd(b[j]) { j += 1 }
                let attr = String(decoding: b[a0..<j], as: UTF8.self)
                while j < b.count && isSpace(b[j]) { j += 1 }
                guard j < b.count && b[j] == 0x3D, !attr.isEmpty else { throw fail("attribute \(attr) of <\(name)> has no value") }
                j += 1
                while j < b.count && isSpace(b[j]) { j += 1 }
                guard j < b.count && (b[j] == 0x22 || b[j] == 0x27) else {
                    throw fail("attribute \(attr) of <\(name)> is not in quotes")
                }
                let quote = b[j]
                let v0 = j + 1
                j = v0
                while j < b.count && b[j] != quote { j += 1 }
                guard j < b.count else { throw fail("attribute \(attr) of <\(name)> never ends") }
                attributes[attr] = decodeEntities(b[v0..<j])
                j += 1
            }
            i = j
            try handle(.start(name: name, attributes: attributes))
            if selfClosing { try handle(.end(name: name)) } else { stack.append(name) }
        }
        if let open = stack.last { throw fail("<\(open)> is never closed") }
    }

    /// An attribute value with its entities (`&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&#nn;`, `&#xhh;`) decoded
    /// and literal tabs and line breaks turned into spaces, as XML reads attribute values. An entity it does not know
    /// is kept as written.
    static func decodeEntities(_ bytes: ArraySlice<UInt8>) -> String {
        let s = String(decoding: bytes, as: UTF8.self)
        guard s.contains("&") || s.contains("\t") || s.contains("\n") || s.contains("\r") else { return s }
        var out = ""
        var rest = Substring(s)
        while let amp = rest.firstIndex(where: { $0 == "&" || $0 == "\t" || $0 == "\n" || $0 == "\r" }) {
            out += rest[..<amp]
            if rest[amp] != "&" {
                out += " "
                rest = rest[rest.index(after: amp)...]
                continue
            }
            guard let semi = rest[amp...].firstIndex(of: ";"), rest.distance(from: amp, to: semi) <= 10 else {
                out += "&"
                rest = rest[rest.index(after: amp)...]
                continue
            }
            let entity = rest[rest.index(after: amp)..<semi]
            var decoded: String? = nil
            switch entity {
            case "amp": decoded = "&"
            case "lt": decoded = "<"
            case "gt": decoded = ">"
            case "quot": decoded = "\""
            case "apos": decoded = "'"
            default:
                if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                    decoded = UInt32(entity.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String($0) }
                } else if entity.hasPrefix("#") {
                    decoded = UInt32(entity.dropFirst()).flatMap(Unicode.Scalar.init).map { String($0) }
                }
            }
            if let decoded {
                out += decoded
                rest = rest[rest.index(after: semi)...]
            } else {
                out += "&"
                rest = rest[rest.index(after: amp)...]
            }
        }
        out += rest
        return out
    }
}
