import Foundation

/// Reads the tables of an SQLite database file, read only, in plain Swift: no SQLite library, so it is the same on
/// macOS, Windows and Linux and adds no dependency. Written from the published file format
/// (https://www.sqlite.org/fileformat.html): the 100-byte header, table b-trees (interior and leaf pages), overflow
/// pages, the record format and its serial types, and the schema table on page 1, whose `CREATE TABLE` text gives the
/// column names.
///
/// What it does not do: indexes (a table is read whole, in rowid order), tables made `WITHOUT ROWID`, and the
/// write-ahead log: changes still in a `-wal` file beside the database, not yet copied into it, are not seen. It reads
/// bytes it was given; it never opens the database file itself, so a caller reads a copy and nothing is locked.
public struct SQLiteReader {
    public enum Value: Equatable, Sendable {
        case null
        case integer(Int64)
        case real(Double)
        case text(String)
        case blob([UInt8])

        public var text: String? { if case .text(let s) = self { return s }; return nil }
        public var integer: Int64? {
            switch self {
            case .integer(let i): return i
            case .real(let d) where d.isFinite && d.rounded() == d && abs(d) < 9e18: return Int64(d)
            case .text(let s): return Int64(s.trimmingCharacters(in: .whitespaces))
            default: return nil
            }
        }
        public var real: Double? {
            switch self {
            case .integer(let i): return Double(i)
            case .real(let d): return d
            case .text(let s): return Double(s.trimmingCharacters(in: .whitespaces))
            default: return nil
            }
        }
    }

    public struct Failure: Error, CustomStringConvertible {
        public let description: String
        init(_ d: String) { description = d }
    }

    /// One table: its column names, and its rows, each a column name to value (a column left out of an older row,
    /// added since by `ALTER TABLE`, is absent).
    public struct Table {
        public var columns: [String]
        public var rows: [[String: Value]]
    }

    let bytes: [UInt8]
    let pageSize: Int
    let usable: Int
    /// 1 UTF-8, 2 UTF-16 little-endian, 3 UTF-16 big-endian.
    let encoding: Int

    public init(data: Data) throws {
        bytes = [UInt8](data)
        guard bytes.count >= 100, Array(bytes[0..<16]) == Array("SQLite format 3\u{0}".utf8) else {
            throw Failure("not an SQLite database")
        }
        let raw = Int(bytes[16]) << 8 | Int(bytes[17])
        pageSize = raw == 1 ? 65536 : raw
        guard pageSize >= 512, pageSize & (pageSize - 1) == 0 else { throw Failure("page size \(raw) is not valid") }
        usable = pageSize - Int(bytes[20])
        let e = Int(bytes[56]) << 24 | Int(bytes[57]) << 16 | Int(bytes[58]) << 8 | Int(bytes[59])
        encoding = e == 0 ? 1 : e
        guard (1...3).contains(encoding) else { throw Failure("text encoding \(e) is not valid") }
    }

    /// The tables named in the schema: name to (root page, `CREATE TABLE` text).
    public func schema() throws -> [String: (root: Int, sql: String)] {
        var out: [String: (Int, String)] = [:]
        for (_, values) in try records(root: 1) {
            // sqlite_schema: type, name, tbl_name, rootpage, sql.
            guard values.count >= 5, values[0].text == "table", let name = values[1].text,
                  let root = values[3].integer, root > 0 else { continue }
            out[name] = (Int(root), values[4].text ?? "")
        }
        return out
    }

    /// The table named `name` (compared without regard to case), or nil when there is none.
    public func table(_ name: String) throws -> Table? {
        let s = try schema()
        guard let entry = s.first(where: { $0.key.lowercased() == name.lowercased() })?.value else { return nil }
        guard !entry.sql.uppercased().contains("WITHOUT ROWID") else { throw Failure("\(name) is a WITHOUT ROWID table") }
        let (columns, rowidColumn) = Self.columns(ofCreate: entry.sql)
        var rows: [[String: Value]] = []
        for (rowid, values) in try records(root: entry.root) {
            var row: [String: Value] = [:]
            for (i, c) in columns.enumerated() where i < values.count { row[c] = values[i] }
            if let r = rowidColumn, (row[r] ?? .null) == .null { row[r] = .integer(rowid) }
            rows.append(row)
        }
        return Table(columns: columns, rows: rows)
    }

    /// The column names of a `CREATE TABLE` statement, in order, and the one that is the rowid (`INTEGER PRIMARY
    /// KEY`), whose value the record leaves null.
    static func columns(ofCreate sql: String) -> (names: [String], rowid: String?) {
        guard let open = sql.firstIndex(of: "("), let close = sql.lastIndex(of: ")"), open < close else { return ([], nil) }
        let body = sql[sql.index(after: open)..<close]
        var parts: [String] = []
        var depth = 0, current = "", quote: Character? = nil
        for ch in body {
            if let q = quote {
                current.append(ch)
                if ch == q || (q == "[" && ch == "]") { quote = nil }
                continue
            }
            switch ch {
            case "\"", "'", "`", "[": quote = ch; current.append(ch)
            case "(": depth += 1; current.append(ch)
            case ")": depth -= 1; current.append(ch)
            case "," where depth == 0: parts.append(current); current = ""
            default: current.append(ch)
            }
        }
        parts.append(current)
        var names: [String] = []
        var rowid: String? = nil
        for p in parts {
            let def = p.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !def.isEmpty else { continue }
            let name = Self.firstName(def)
            if ["CONSTRAINT", "PRIMARY", "UNIQUE", "CHECK", "FOREIGN"].contains(name.uppercased()) { continue }
            names.append(name)
            let words = def.uppercased().split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
            if words.count >= 4, words[1] == "INTEGER", words[2] == "PRIMARY", words[3] == "KEY" { rowid = name }
        }
        return (names, rowid)
    }

    /// The first name of a column definition, its quotes taken off.
    static func firstName(_ def: String) -> String {
        guard let first = def.first else { return "" }
        let closing: Character? = first == "\"" ? "\"" : first == "`" ? "`" : first == "[" ? "]" : first == "'" ? "'" : nil
        if let closing {
            let rest = def.dropFirst()
            return String(rest.prefix { $0 != closing })
        }
        return String(def.prefix { !$0.isWhitespace && $0 != "(" })
    }

    // MARK: the b-tree

    func page(_ n: Int) throws -> ArraySlice<UInt8> {
        let start = (n - 1) * pageSize
        guard n >= 1, start + pageSize <= bytes.count else { throw Failure("page \(n) is past the end of the file") }
        return bytes[start..<(start + pageSize)]
    }

    /// Every record of the table b-tree rooted at `root`, in rowid order: (rowid, values).
    func records(root: Int) throws -> [(Int64, [Value])] {
        var out: [(Int64, [Value])] = []
        var visited = Set<Int>()
        try walk(root, &out, &visited)
        return out
    }

    private func walk(_ n: Int, _ out: inout [(Int64, [Value])], _ visited: inout Set<Int>) throws {
        guard visited.insert(n).inserted else { throw Failure("page \(n) is reached twice: the file is damaged") }
        let p = try page(n)
        let base = p.startIndex
        let h = base + (n == 1 ? 100 : 0)
        let type = bytes[h]
        let cells = Int(bytes[h + 3]) << 8 | Int(bytes[h + 4])
        switch type {
        case 0x05:  // interior table page
            let right = Int(u32(h + 8))
            for i in 0..<cells {
                let ptr = base + (Int(bytes[h + 12 + 2 * i]) << 8 | Int(bytes[h + 13 + 2 * i]))
                guard ptr + 4 <= p.endIndex else { throw Failure("page \(n): a cell is past the page") }
                try walk(Int(u32(ptr)), &out, &visited)
            }
            try walk(right, &out, &visited)
        case 0x0D:  // leaf table page
            for i in 0..<cells {
                let ptr = base + (Int(bytes[h + 8 + 2 * i]) << 8 | Int(bytes[h + 9 + 2 * i]))
                guard ptr < p.endIndex else { throw Failure("page \(n): a cell is past the page") }
                var at = ptr
                let size = Int(varint(&at))
                let rowid = Int64(bitPattern: varint(&at))
                let payload = try self.payload(at: at, size: size, pageEnd: p.endIndex)
                out.append((rowid, try record(payload)))
            }
        default:
            throw Failure("page \(n) is not a table page (type \(type))")
        }
    }

    /// A leaf cell's payload: what is on the page, then the overflow pages.
    private func payload(at start: Int, size: Int, pageEnd: Int) throws -> [UInt8] {
        let x = usable - 35
        guard size >= 0 else { throw Failure("a negative payload size") }
        if size <= x {
            guard start + size <= pageEnd else { throw Failure("a payload is past its page") }
            return Array(bytes[start..<(start + size)])
        }
        let m = (usable - 12) * 32 / 255 - 23
        let k = m + (size - m) % (usable - 4)
        let local = k <= x ? k : m
        guard start + local + 4 <= pageEnd else { throw Failure("a payload is past its page") }
        var out = Array(bytes[start..<(start + local)])
        var next = Int(u32(start + local))
        var seen = Set<Int>()
        while out.count < size {
            guard next > 0, seen.insert(next).inserted else { throw Failure("an overflow chain is broken") }
            let p = try page(next)
            let take = min(usable - 4, size - out.count)
            out += bytes[(p.startIndex + 4)..<(p.startIndex + 4 + take)]
            next = Int(u32(p.startIndex))
        }
        return out
    }

    /// A record: a header of serial types, then the values.
    private func record(_ r: [UInt8]) throws -> [Value] {
        var at = 0
        let headerSize = Int(Self.varint(r, &at))
        guard headerSize <= r.count else { throw Failure("a record's header is past its end") }
        var types: [UInt64] = []
        while at < headerSize { types.append(Self.varint(r, &at)) }
        var body = headerSize
        var values: [Value] = []
        for t in types {
            func int(_ n: Int) throws -> Int64 {
                guard body + n <= r.count else { throw Failure("a record's value is past its end") }
                var v: Int64 = (r[body] & 0x80) != 0 ? -1 : 0
                for i in 0..<n { v = (v << 8) | Int64(r[body + i]) }
                body += n
                return v
            }
            switch t {
            case 0: values.append(.null)
            case 1: try values.append(.integer(int(1)))
            case 2: try values.append(.integer(int(2)))
            case 3: try values.append(.integer(int(3)))
            case 4: try values.append(.integer(int(4)))
            case 5: try values.append(.integer(int(6)))
            case 6: try values.append(.integer(int(8)))
            case 7: try values.append(.real(Double(bitPattern: UInt64(bitPattern: int(8)))))
            case 8: values.append(.integer(0))
            case 9: values.append(.integer(1))
            case 10, 11: throw Failure("a reserved serial type")
            default:
                let n = Int((t - 12) / 2)
                guard body + n <= r.count else { throw Failure("a record's value is past its end") }
                let b = Array(r[body..<(body + n)])
                body += n
                values.append(t % 2 == 0 ? .blob(b) : .text(decode(b)))
            }
        }
        return values
    }

    private func decode(_ b: [UInt8]) -> String {
        switch encoding {
        case 2, 3:
            var units: [UInt16] = []
            var i = 0
            while i + 1 < b.count {
                units.append(encoding == 3 ? UInt16(b[i]) << 8 | UInt16(b[i + 1]) : UInt16(b[i + 1]) << 8 | UInt16(b[i]))
                i += 2
            }
            return String(decoding: units, as: UTF16.self)
        default: return String(decoding: b, as: UTF8.self)
        }
    }

    private func u32(_ at: Int) -> UInt32 {
        UInt32(bytes[at]) << 24 | UInt32(bytes[at + 1]) << 16 | UInt32(bytes[at + 2]) << 8 | UInt32(bytes[at + 3])
    }

    private func varint(_ at: inout Int) -> UInt64 { Self.varint(bytes, &at) }

    /// SQLite's variable-length integer: up to eight bytes of seven bits each (the high bit says more follow), and a
    /// ninth of all eight bits. Stops at the end of `b`.
    static func varint<C: RandomAccessCollection>(_ b: C, _ at: inout Int) -> UInt64 where C.Element == UInt8, C.Index == Int {
        var v: UInt64 = 0
        for i in 0..<9 {
            guard at < b.endIndex else { break }
            let byte = b[at]
            at += 1
            if i == 8 { v = (v << 8) | UInt64(byte); break }
            v = (v << 7) | UInt64(byte & 0x7F)
            if byte & 0x80 == 0 { break }
        }
        return v
    }
}
