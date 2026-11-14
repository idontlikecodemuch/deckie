import Foundation

/// A crate file as one file (docs/architecture/crate-format.md, "The single-file form").
///
/// On a Mac a `.deckiecrate` is a package: a folder that Finder, Files and AirDrop show and move as one document. On
/// Windows it is just a folder, awkward to send to an iPad. The single-file form is the same files, with the same
/// names and the same bytes, in one archive: a plain zip in which nothing is compressed ("stored"), so it changes
/// nothing inside, any zip tool can open it, and it is written and read by the few lines below with no library, the
/// same on macOS, Linux and Windows.
///
/// - Written canonically, like everything else in a crate file: `manifest.json` first, `crate.json` second, the rest
///   sorted by the bytes of their paths, every time stamp the zip format's zero (Jan 1, 1980), no comments and no
///   extra fields, so the same contents always give the same bytes.
/// - Damage is detected: every file carries the zip format's CRC-32 checksum (a 4-byte fingerprint of its bytes),
///   checked on reading, and the archive's own tables are checked against each other. A file cut short, a changed
///   byte or a missing table is reported, naming the file inside where it can.
/// - Read strictly but not only our own writing: a zip made by another tool reads when its entries are stored. An
///   entry that is compressed or encrypted is refused in plain words, never guessed at.
/// - Sizes: the zip64 extension is written and read for the count of files (past 65,535, about 20,000 songs with
///   signatures); an archive of 4 GB or more is refused (a crate file is about 4 KB a song).
public enum CrateArchive {
    /// Whether `url` is a file (not a folder) that starts like a zip: what `CrateReader.read(from:)` takes as the
    /// single-file form.
    public static func isArchive(_ url: URL) -> Bool {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue,
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        let head = [UInt8]((try? handle.read(upToCount: 4)) ?? Data())
        return head == [0x50, 0x4B, 0x03, 0x04] || head == [0x50, 0x4B, 0x05, 0x06]
    }

    // MARK: Writing

    /// The archive holding `files` (by their path inside the package, "/" between names).
    public static func encode(_ files: [String: Data]) throws -> Data {
        var problems: [CrateProblem] = []
        for path in files.keys.sorted(by: byteOrder) {
            if let why = unsafePath(path) { problems.append(CrateProblem(file: path, path: "", message: why)) }
            if path.utf8.count > 0xFFFF { problems.append(CrateProblem(file: path, path: "", message: "its path is too long for an archive")) }
            if files[path]!.count >= 0xFFFF_FFFF { problems.append(CrateProblem(file: path, path: "", message: "is 4 GB or more, too large for a crate file")) }
        }
        if !problems.isEmpty { throw CrateError(problems) }

        let first = [CrateFormat.manifestFile, CrateFormat.tracksFile].filter { files[$0] != nil }
        let order = first + files.keys.filter { !first.contains($0) }.sorted(by: byteOrder)
        var out = [UInt8]()
        out.reserveCapacity(files.values.reduce(0) { $0 + $1.count } + order.count * 128 + 128)
        var central = [UInt8]()
        for path in order {
            let data = files[path]!
            let name = Array(path.utf8)
            let crc = CRC32.checksum(data)
            let offset = out.count
            guard offset < 0xFFFF_FFFF else { throw tooLarge }
            // Local header: signature, version needed 1.0, flags (bit 11: the name is UTF-8), method 0 (stored),
            // time and date (zero: Jan 1, 1980), CRC-32, the size twice, the name's length, no extra field.
            put32(&out, 0x0403_4B50); put16(&out, 10); put16(&out, 0x0800); put16(&out, 0)
            put16(&out, 0); put16(&out, 0x0021)
            put32(&out, crc); put32(&out, UInt32(data.count)); put32(&out, UInt32(data.count))
            put16(&out, UInt16(name.count)); put16(&out, 0)
            out += name
            out += data
            // The same in the central directory (the table at the end), with where the local header is.
            put32(&central, 0x0201_4B50); put16(&central, 20); put16(&central, 10); put16(&central, 0x0800)
            put16(&central, 0); put16(&central, 0); put16(&central, 0x0021)
            put32(&central, crc); put32(&central, UInt32(data.count)); put32(&central, UInt32(data.count))
            put16(&central, UInt16(name.count)); put16(&central, 0); put16(&central, 0)
            put16(&central, 0); put16(&central, 0); put32(&central, 0)
            put32(&central, UInt32(offset))
            central += name
        }
        let centralOffset = out.count
        guard centralOffset + central.count < 0xFFFF_FFFF else { throw tooLarge }
        out += central
        if order.count > 0xFFFF {
            // zip64, for the count of files only: its end record, then the locator that points at it.
            let zip64Offset = out.count
            put32(&out, 0x0606_4B50); put64(&out, 44); put16(&out, 45); put16(&out, 45); put32(&out, 0); put32(&out, 0)
            put64(&out, UInt64(order.count)); put64(&out, UInt64(order.count))
            put64(&out, UInt64(central.count)); put64(&out, UInt64(centralOffset))
            put32(&out, 0x0706_4B50); put32(&out, 0); put64(&out, UInt64(zip64Offset)); put32(&out, 1)
        }
        let count16 = UInt16(min(order.count, 0xFFFF))
        put32(&out, 0x0605_4B50); put16(&out, 0); put16(&out, 0); put16(&out, count16); put16(&out, count16)
        put32(&out, UInt32(central.count)); put32(&out, UInt32(centralOffset)); put16(&out, 0)
        return Data(out)
    }

    /// Writes the package folder at `package` as one file at `file`: every file in the folder, at any depth, but
    /// names that start with a dot (`.DS_Store`). Nothing inside is changed. Written whole or not at all.
    public static func pack(package: URL, to file: URL) throws {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: package.path, isDirectory: &isFolder), isFolder.boolValue else {
            throw CrateError([CrateProblem(file: package.lastPathComponent, path: "", message: "is not a crate package folder")])
        }
        var files: [String: Data] = [:]
        var unread: [CrateProblem] = []
        func walk(_ folder: URL, _ rel: String) {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return }
            for name in names.sorted() where !name.hasPrefix(".") {
                let url = folder.appendingPathComponent(name)
                let path = rel.isEmpty ? name : rel + "/" + name
                var sub: ObjCBool = false
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &sub) else { continue }
                if sub.boolValue { walk(url, path); continue }
                if let data = try? Data(contentsOf: url) { files[path] = data }
                else { unread.append(CrateProblem(file: path, path: "", message: "could not be read")) }
            }
        }
        walk(package, "")
        if !unread.isEmpty { throw CrateError(unread) }
        guard files[CrateFormat.manifestFile] != nil else {
            throw CrateError([CrateProblem(file: CrateFormat.manifestFile, path: "", message: "is missing")])
        }
        try encode(files).write(to: file, options: .atomic)
    }

    // MARK: Reading

    /// The files in the archive, by their path inside the package. Throws a `CrateError` saying what is wrong when
    /// the archive is cut short, damaged, compressed, encrypted or not a zip at all.
    public static func decode(_ data: Data, name: String = "the crate file") throws -> [String: Data] {
        let b = [UInt8](data)
        func fail(_ message: String, in entry: String? = nil) -> CrateError {
            CrateError([CrateProblem(file: entry.map { "\(name): \($0)" } ?? name, path: "", message: message)])
        }
        func u16(_ at: Int) -> Int { Int(b[at]) | Int(b[at + 1]) << 8 }
        func u32(_ at: Int) -> Int { u16(at) | u16(at + 2) << 16 }
        func u64(_ at: Int) -> UInt64 { UInt64(u32(at)) | UInt64(u32(at + 4)) << 32 }

        // The end record: 22 bytes at the very end, or a little before when a tool added a comment.
        guard b.count >= 22 else {
            throw fail(b.count >= 4 && Array(b[0..<4]) == [0x50, 0x4B, 0x03, 0x04]
                       ? "is cut short (its end is missing)" : "is not a crate file")
        }
        var end = -1
        var at = b.count - 22
        while at >= max(0, b.count - 22 - 0xFFFF) {
            if u32(at) == 0x0605_4B50, at + 22 + u16(at + 20) == b.count { end = at; break }
            at -= 1
        }
        guard end >= 0 else {
            throw fail(Array(b[0..<4]) == [0x50, 0x4B, 0x03, 0x04]
                       ? "is cut short or damaged (its end is missing)" : "is not a crate file")
        }
        guard u16(end + 4) == 0, u16(end + 6) == 0 else { throw fail("is one part of an archive split over several files") }
        var count = u16(end + 10), centralSize = u32(end + 12), centralOffset = u32(end + 16)
        if count == 0xFFFF || centralSize == 0xFFFF_FFFF || centralOffset == 0xFFFF_FFFF {
            // zip64: the locator sits just before the end record and points at the zip64 end record.
            let locator = end - 20
            guard locator >= 0, u32(locator) == 0x0706_4B50, let z = Int(exactly: u64(locator + 8)), z >= 0, z + 56 <= locator,
                  u32(z) == 0x0606_4B50, let n = Int(exactly: u64(z + 32)), let size = Int(exactly: u64(z + 40)),
                  let offset = Int(exactly: u64(z + 48)) else {
                throw fail("is damaged (its table of contents cannot be found)")
            }
            (count, centralSize, centralOffset) = (n, size, offset)
            end = z
        }
        guard centralOffset >= 0, centralSize >= 0, centralOffset + centralSize <= end, count <= centralSize / 46 + 1 else {
            throw fail("is damaged (its table of contents does not fit the file)")
        }

        var files: [String: Data] = [:]
        var p = centralOffset
        for _ in 0..<count {
            guard p + 46 <= centralOffset + centralSize, u32(p) == 0x0201_4B50 else {
                throw fail("is damaged (its table of contents is broken)")
            }
            let flags = u16(p + 8), method = u16(p + 10), crc = UInt32(u32(p + 16))
            let packed = u32(p + 20), size = u32(p + 24)
            let nameLength = u16(p + 28), extra = u16(p + 30), comment = u16(p + 32), local = u32(p + 42)
            guard p + 46 + nameLength + extra + comment <= centralOffset + centralSize else {
                throw fail("is damaged (its table of contents is broken)")
            }
            guard let path = String(bytes: b[(p + 46)..<(p + 46 + nameLength)], encoding: .utf8) else {
                throw fail("is damaged (a file name in it cannot be read)")
            }
            p += 46 + nameLength + extra + comment
            if path.hasSuffix("/") && size == 0 { continue }  // a folder's own entry, as some tools write
            if let why = unsafePath(path) { throw fail(why, in: path) }
            guard flags & 0x0041 == 0 else { throw fail("is encrypted; a crate file never is", in: path) }
            guard method == 0 else {
                throw fail("is compressed, so another program has rewritten this crate file; make it again with Deckie", in: path)
            }
            guard packed == size, size != 0xFFFF_FFFF, local != 0xFFFF_FFFF else { throw fail("is damaged (its sizes disagree)", in: path) }
            guard local + 30 <= centralOffset, u32(local) == 0x0403_4B50 else { throw fail("is damaged (its header is missing)", in: path) }
            let start = local + 30 + u16(local + 26) + u16(local + 28)
            guard u16(local + 26) == nameLength, Array(b[(local + 30)..<min(b.count, local + 30 + nameLength)]) == Array(path.utf8) else {
                throw fail("is damaged (its header names another file)", in: path)
            }
            guard start + size <= centralOffset else { throw fail("is cut short", in: path) }
            let body = Data(b[start..<(start + size)])
            guard CRC32.checksum(body) == crc else {
                throw fail("is damaged (its bytes do not match their checksum)", in: path)
            }
            guard files.updateValue(body, forKey: path) == nil else { throw fail("is in the archive twice", in: path) }
        }
        return files
    }

    /// Unpacks the single-file crate at `file` into a package folder at `package` (made if missing; files already
    /// there with the same paths are replaced, others are left alone). The archive is checked whole before anything is
    /// written.
    public static func unpack(_ file: URL, to package: URL) throws {
        let files = try read(file)
        let fm = FileManager.default
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        for path in files.keys.sorted(by: byteOrder) {
            var url = package
            for part in path.split(separator: "/") { url = url.appendingPathComponent(String(part)) }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files[path]!.write(to: url, options: .atomic)
        }
    }

    /// The files of the single-file crate at `file`.
    public static func read(_ file: URL) throws -> [String: Data] {
        guard let data = try? Data(contentsOf: file) else {
            throw CrateError([CrateProblem(file: file.lastPathComponent, path: "", message: "could not be read")])
        }
        return try decode(data, name: file.lastPathComponent)
    }

    // MARK: Pieces

    private static var tooLarge: CrateError {
        CrateError([CrateProblem(file: "the crate file", path: "", message: "would be 4 GB or more, too large for one archive")])
    }

    /// Why `path` may not name a file in a crate file, or nil: it must be names joined by "/" that stay inside the
    /// package (no empty name, no "." or "..", no backslash, no drive letter or leading "/").
    static func unsafePath(_ path: String) -> String? {
        if path.isEmpty { return "has no name" }
        if path.contains("\\") { return "has a backslash in its path; a crate file's paths use \"/\"" }
        if path.contains(":") || path.hasPrefix("/") { return "has an absolute path; a crate file's paths stay inside it" }
        for part in path.split(separator: "/", omittingEmptySubsequences: false) where part.isEmpty || part == "." || part == ".." {
            return "has a path that does not stay inside the crate file"
        }
        return nil
    }

    private static func put16(_ a: inout [UInt8], _ v: UInt16) { a.append(UInt8(v & 0xFF)); a.append(UInt8(v >> 8)) }
    private static func put32(_ a: inout [UInt8], _ v: UInt32) { for s in stride(from: 0, to: 32, by: 8) { a.append(UInt8(v >> UInt32(s) & 0xFF)) } }
    private static func put64(_ a: inout [UInt8], _ v: UInt64) { for s in stride(from: 0, to: 64, by: 8) { a.append(UInt8(v >> UInt64(s) & 0xFF)) } }
}

/// CRC-32 as zip, gzip and PNG use it (the polynomial 0xEDB88320, reflected), written out here so the crate needs no
/// library on any system.
enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        data.withUnsafeBytes { bytes in
            for byte in bytes { c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8) }
        }
        return c ^ 0xFFFF_FFFF
    }
}
