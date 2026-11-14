import Foundation
import DeckieCrate
import DeckieCore

/// The DJ programs whose own library a desk reads for keys and names (D30). The raw value is the name the crate file
/// uses for a key or a name from that program (`key.source`, a key in `key.votes`, `ident.source`).
public enum DJProgram: String, Codable, CaseIterable, Sendable {
    /// A rekordbox collection export (XML), chosen by the DJ: rekordbox's own database is encrypted and not read.
    case rekordbox = "rekordbox-xml"
    /// Traktor's `collection.nml`.
    case traktor
    /// Engine DJ's `Database2/m.db` (Engine DJ 2 and later).
    case engineDJ = "engine-dj"
    /// Serato's `_Serato_/database V2`.
    case serato
    /// VirtualDJ's `database.xml`.
    case virtualDJ = "virtualdj"

    /// The fixed order among programs whose libraries were written at the same moment (a tie, in practice never).
    var tieOrder: Int { Self.allCases.firstIndex(of: self)! }

    /// The program a library file is, by its name (and, for an XML file, its first element); nil for none.
    public static func of(file url: URL) -> DJProgram? {
        let name = url.lastPathComponent.lowercased()
        switch name {
        case "collection.nml": return .traktor
        case "m.db": return .engineDJ
        case "database v2": return .serato
        default: break
        }
        guard name.hasSuffix(".xml") || name.hasSuffix(".nml") else { return nil }
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let head = String(decoding: (try? h.read(upToCount: 4096)) ?? Data(), as: UTF8.self)
        if head.contains("<DJ_PLAYLISTS") { return .rekordbox }
        if head.contains("<VirtualDJ_Database") { return .virtualDJ }
        if head.contains("<NML") { return .traktor }
        return nil
    }
}

/// One song in a DJ program's library: where the program says its file is, the names it has for it, and its key.
public struct DJLibraryEntry: Sendable, Equatable {
    /// The file's path, as absolute paths it may be at, "/" between names (a program on Windows writes "\"). Most
    /// programs give one; Traktor on a Mac and Serato give two (the startup disk, or the named drive).
    public var paths: [String]
    public var title: String?
    public var artist: String?
    public var version: String?
    /// The key as the program wrote it, and its Camelot code (nil when the notation was not read).
    public var keyAsWritten: String?
    public var camelot: String?
    /// The file's size in bytes, when the program keeps it, and how far off it may be (Traktor keeps kilobytes).
    public var size: Int?
    public var sizeSlack: Int

    public init(paths: [String], title: String? = nil, artist: String? = nil, version: String? = nil,
                keyAsWritten: String? = nil, camelot: String? = nil, size: Int? = nil, sizeSlack: Int = 0) {
        self.paths = paths; self.title = title; self.artist = artist; self.version = version
        self.keyAsWritten = keyAsWritten; self.camelot = camelot ?? keyAsWritten.flatMap(KeyNotation.camelot)
        self.size = size; self.sizeSlack = sizeSlack
    }
}

/// A DJ program's library, read: which program, the file read, when that file was last written, and its songs.
public struct DJLibrary: Sendable {
    public var program: DJProgram
    public var file: String
    public var written: Date?
    public var entries: [DJLibraryEntry]

    public init(program: DJProgram, file: String, written: Date?, entries: [DJLibraryEntry]) {
        self.program = program; self.file = file; self.written = written; self.entries = entries
    }

    public struct ReadError: Error, CustomStringConvertible {
        public var file: String
        public var message: String
        public var description: String { "\(file): \(message)" }
    }

    /// Reads the library at `url` as `program`. Read only: the file is first copied to a folder of its own (the
    /// program may have it open, and reading a copy takes no lock and can change nothing), read from the copy, and
    /// the copy deleted.
    public static func read(_ program: DJProgram, at url: URL) throws -> DJLibrary {
        let fm = FileManager.default
        let written = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        let folder = fm.temporaryDirectory.appendingPathComponent("deckie-library-" + UUID().uuidString, isDirectory: true)
        defer { try? DeckieFiles.remove(folder) }
        let data: Data
        do {
            try DeckieFiles.createDirectory(folder)
            let copy = folder.appendingPathComponent("library")
            try DeckieFiles.copy(url, to: copy)
            data = try Data(contentsOf: copy)
        } catch {
            throw ReadError(file: url.path, message: "could not be copied to read (\(error.localizedDescription))")
        }
        do {
            return DJLibrary(program: program, file: url.path, written: written, entries: try parse(program, data, at: url))
        } catch let e as ReadError {
            throw e
        } catch {
            throw ReadError(file: url.path, message: "\(error)")
        }
    }

    /// The songs of a library file's bytes; `url` is where the file is, for paths written relative to it.
    public static func parse(_ program: DJProgram, _ data: Data, at url: URL) throws -> [DJLibraryEntry] {
        switch program {
        case .rekordbox: return try rekordbox(data)
        case .traktor: return try traktor(data)
        case .virtualDJ: return try virtualDJ(data, at: url)
        case .engineDJ: return try engineDJ(data, at: url)
        case .serato: return try serato(data, at: url)
        }
    }

    // MARK: rekordbox: the collection export

    static func rekordbox(_ data: Data) throws -> [DJLibraryEntry] {
        try RekordboxCollection.parse(data).tracks.compactMap { t in
            guard let p = t.path else { return nil }
            return DJLibraryEntry(paths: [PathKey.slashes(p)], title: t.name, artist: t.artist, version: t.mix,
                                  keyAsWritten: t.tonality, size: t.size)
        }
    }

    // MARK: Traktor: collection.nml

    /// Traktor's collection (`NML` > `COLLECTION` > `ENTRY`): `TITLE` and `ARTIST` on the entry; its `LOCATION`'s
    /// `VOLUME`, `DIR` (names each after "/:") and `FILE`; its `INFO`'s `KEY` (the key as Traktor shows it, in the
    /// DJ's chosen notation) and `FILESIZE` (kilobytes). `MUSICAL_KEY`'s number is not read: its numbering is not
    /// published. A volume that is a drive letter ("C:") starts the path on Windows; on a Mac the volume is a disk's
    /// name, so the path is tried on the startup disk and under /Volumes/<name>.
    static func traktor(_ data: Data) throws -> [DJLibraryEntry] {
        var out: [DJLibraryEntry] = []
        var inCollection = false, sawRoot = false
        var current: DJLibraryEntry? = nil
        try XMLScanner.scan(data) { event in
            switch event {
            case .start(let name, let a):
                switch name {
                case "NML": sawRoot = true
                case "COLLECTION": inCollection = true
                case "ENTRY" where inCollection:
                    current = DJLibraryEntry(paths: [], title: nonEmpty(a["TITLE"]), artist: nonEmpty(a["ARTIST"]))
                case "LOCATION" where current != nil:
                    let dir = (a["DIR"] ?? "").replacingOccurrences(of: "/:", with: "/")
                    let file = a["FILE"] ?? ""
                    let volume = a["VOLUME"] ?? ""
                    guard !file.isEmpty else { break }
                    let rest = (dir.hasSuffix("/") ? dir : dir + "/") + file
                    if volume.count == 2, volume.last == ":" {
                        current?.paths = [volume + rest]
                    } else {
                        current?.paths = [rest] + (volume.isEmpty ? [] : ["/Volumes/" + volume + rest])
                    }
                case "INFO" where current != nil:
                    if let k = nonEmpty(a["KEY"]) { current?.keyAsWritten = k; current?.camelot = KeyNotation.camelot(k) }
                    if let kb = a["FILESIZE"].flatMap({ Int($0) }) { current?.size = kb * 1024; current?.sizeSlack = 1024 }
                default: break
                }
            case .end(let name):
                if name == "COLLECTION" { inCollection = false }
                if name == "ENTRY", inCollection, let c = current {
                    if !c.paths.isEmpty { out.append(c) }
                    current = nil
                }
            }
        }
        guard sawRoot else { throw ReadError(file: "", message: "has no NML element: not a Traktor collection") }
        return out
    }

    // MARK: VirtualDJ: database.xml

    /// VirtualDJ's database (`VirtualDJ_Database` > `Song`, VirtualDJ's wiki page "VDJ database"): `FilePath` and
    /// `FileSize` on the song; its `Tags`' `Author`, `Title`, `Remix` and `Key` (the file's tag or the DJ's edit), and
    /// its `Scan`'s `Key` (VirtualDJ's own reading), the first of the two keys taken, as VirtualDJ shows. A path with
    /// no drive or top folder (a database kept on an external drive) is taken below that drive: the folder holding
    /// the `VirtualDJ` folder.
    static func virtualDJ(_ data: Data, at url: URL) throws -> [DJLibraryEntry] {
        var out: [DJLibraryEntry] = []
        var current: DJLibraryEntry? = nil
        var tagKey: String? = nil, scanKey: String? = nil
        var sawRoot = false
        let driveTop = PathKey.slashes(url.deletingLastPathComponent().deletingLastPathComponent().path)
        try XMLScanner.scan(data) { event in
            switch event {
            case .start(let name, let a):
                switch name {
                case "VirtualDJ_Database": sawRoot = true
                case "Song":
                    guard let p = nonEmpty(a["FilePath"]) else { current = nil; break }
                    var path = PathKey.slashes(p)
                    if !PathKey.isAbsolute(path) { path = driveTop + (path.hasPrefix("/") ? "" : "/") + path }
                    current = DJLibraryEntry(paths: [path], size: a["FileSize"].flatMap { Int($0) })
                    tagKey = nil; scanKey = nil
                case "Tags" where current != nil:
                    current?.title = nonEmpty(a["Title"]); current?.artist = nonEmpty(a["Author"])
                    current?.version = nonEmpty(a["Remix"]); tagKey = nonEmpty(a["Key"])
                case "Scan" where current != nil:
                    scanKey = nonEmpty(a["Key"])
                default: break
                }
            case .end(let name):
                if name == "Song", var c = current {
                    c.keyAsWritten = tagKey ?? scanKey
                    c.camelot = c.keyAsWritten.flatMap(KeyNotation.camelot)
                    out.append(c)
                    current = nil
                }
            }
        }
        guard sawRoot else { throw ReadError(file: "", message: "has no VirtualDJ_Database element: not a VirtualDJ database") }
        return out
    }

    // MARK: Engine DJ: Database2/m.db

    /// Engine DJ's library (Engine DJ 2 and later: the `Track` table of `Engine Library/Database2/m.db`, an SQLite
    /// database read by `SQLiteReader`): `path` (relative to the `Engine Library` folder, or absolute), `filename`,
    /// `title`, `artist`, `fileBytes` and `key`, a number 0 to 23 round the circle of fifths, a major key and its
    /// relative minor in turn from C major (0) and A minor (1), as the open-source libdjinterop lists it. The older
    /// Engine Prime 1 library keeps keys in another table and is not read.
    static func engineDJ(_ data: Data, at url: URL) throws -> [DJLibraryEntry] {
        let db = try SQLiteReader(data: data)
        guard let track = try db.table("Track") else { throw ReadError(file: "", message: "has no Track table: not an Engine DJ library") }
        guard track.columns.contains("key") else {
            throw ReadError(file: "", message: "has no key column: an Engine Prime 1 library, which is not read")
        }
        let top = PathKey.slashes(url.deletingLastPathComponent().deletingLastPathComponent().path)
        return track.rows.compactMap { row in
            guard let p = row["path"]?.text, !p.isEmpty else { return nil }
            var path = PathKey.slashes(p)
            if !PathKey.isAbsolute(path) { path = PathKey.resolved(top + "/" + path) }
            let key = row["key"]?.integer.map(Int.init)
            return DJLibraryEntry(paths: [path], title: nonEmpty(row["title"]?.text), artist: nonEmpty(row["artist"]?.text),
                                  keyAsWritten: key.map(String.init), camelot: key.flatMap(engineKey),
                                  size: row["fileBytes"]?.integer.map(Int.init))
        }
    }

    /// Engine DJ's key number as a Camelot code: 0 C major (8B), 1 A minor (8A), 2 G major (9B), ... 23 D minor (7A).
    public static func engineKey(_ n: Int) -> String? {
        guard (0...23).contains(n) else { return nil }
        return "\((8 + n / 2 - 1) % 12 + 1)\(n % 2 == 0 ? "B" : "A")"
    }

    // MARK: Serato: _Serato_/database V2

    /// Serato's library (`_Serato_/database V2`), as people who have taken it apart describe it (Serato publishes no
    /// description): fields one after another, each four letters, a 32-bit big-endian length and the value; each song
    /// an `otrk` field holding fields of its own: `pfil` the path (below the top of the drive, with no leading "/"),
    /// `tsng` the title, `tart` the artist, `tkey` the key; text in UTF-16 big-endian. The path is tried below the
    /// drive that holds the `_Serato_` folder and below the computer's own top ("/", or the home folder's drive).
    static func serato(_ data: Data, at url: URL) throws -> [DJLibraryEntry] {
        let bytes = [UInt8](data)
        let seratoFolder = url.deletingLastPathComponent()
        let driveTop = PathKey.slashes(seratoFolder.deletingLastPathComponent().path)
        // The computer's own top: "" on a Mac or Linux ("/" follows), the home folder's drive ("C:") on Windows, whose
        // URL paths may start "/C:".
        var home = PathKey.slashes(FileManager.default.homeDirectoryForCurrentUser.path)
        if home.count >= 3, home.hasPrefix("/"), Array(home)[2] == ":" { home.removeFirst() }
        let systemTop = home.count >= 2 && Array(home)[1] == ":" ? String(home.prefix(2)) : ""
        var out: [DJLibraryEntry] = []
        var sawVersion = false
        for (tag, value) in seratoFields(bytes[...]) {
            if tag == "vrsn" { sawVersion = true; continue }
            guard tag == "otrk" else { continue }
            var e = DJLibraryEntry(paths: [])
            for (t, v) in seratoFields(value) {
                switch t {
                case "pfil":
                    let p = PathKey.slashes(utf16BE(v)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                    guard !p.isEmpty else { continue }
                    var paths = [driveTop + "/" + p]
                    let own = systemTop + "/" + p
                    if own != paths[0] { paths.append(own) }
                    e.paths = paths
                case "tsng": e.title = nonEmpty(utf16BE(v))
                case "tart": e.artist = nonEmpty(utf16BE(v))
                case "tkey": e.keyAsWritten = nonEmpty(utf16BE(v)); e.camelot = e.keyAsWritten.flatMap(KeyNotation.camelot)
                default: break
                }
            }
            if !e.paths.isEmpty { out.append(e) }
        }
        guard sawVersion || !out.isEmpty else { throw ReadError(file: "", message: "is not a Serato database") }
        return out
    }

    static func seratoFields(_ b: ArraySlice<UInt8>) -> [(String, ArraySlice<UInt8>)] {
        var out: [(String, ArraySlice<UInt8>)] = []
        var at = b.startIndex
        while at + 8 <= b.endIndex {
            let tag = String(decoding: b[at..<(at + 4)], as: UTF8.self)
            let n = Int(b[at + 4]) << 24 | Int(b[at + 5]) << 16 | Int(b[at + 6]) << 8 | Int(b[at + 7])
            guard n >= 0, at + 8 + n <= b.endIndex, tag.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { break }
            out.append((tag, b[(at + 8)..<(at + 8 + n)]))
            at += 8 + n
        }
        return out
    }

    static func utf16BE(_ b: ArraySlice<UInt8>) -> String {
        var units: [UInt16] = []
        var i = b.startIndex
        while i + 1 < b.endIndex { units.append(UInt16(b[i]) << 8 | UInt16(b[i + 1])); i += 2 }
        if let nul = units.firstIndex(of: 0) { units = Array(units[..<nul]) }
        return String(decoding: units, as: UTF16.self)
    }
}

/// Paths compared across programs and platforms: "/" between names, accents in one form, case ignored (the Mac's and
/// Windows' disks ignore it), a drive letter written "c:" with no "/" before it.
public enum PathKey {
    public static func slashes(_ p: String) -> String { p.replacingOccurrences(of: "\\", with: "/") }

    /// Whether a path (with "/" between names) is absolute: it starts with "/" and is not a Windows path below the
    /// current drive's top ("\Music\x.mp3" read as "/Music/x.mp3" is taken as absolute too, on a Mac), or with a drive.
    public static func isAbsolute(_ p: String) -> Bool {
        let c = Array(p)
        return p.hasPrefix("/") || (c.count >= 2 && c[0].isLetter && c[1] == ":")
    }

    /// `..` and `.` taken out.
    public static func resolved(_ p: String) -> String {
        var out: [String] = []
        for n in p.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            if n == "." { continue }
            if n == "..", let last = out.last, !last.isEmpty, !(last.count == 2 && last.last == ":") { out.removeLast(); continue }
            out.append(n)
        }
        return out.joined(separator: "/")
    }

    /// The form two paths are compared in.
    public static func key(_ p: String) -> String {
        var s = resolved(slashes(p)).precomposedStringWithCanonicalMapping.lowercased()
        while s.contains("//") { s = s.replacingOccurrences(of: "//", with: "/") }
        let c = Array(s)
        if c.count >= 3, c[0] == "/", c[1].isLetter, c[2] == ":" { s.removeFirst() }
        if s.count > 1, s.hasSuffix("/") { s.removeLast() }
        return s
    }

    /// The last name of a path.
    public static func lastName(_ p: String) -> String { String(slashes(p).split(separator: "/").last ?? Substring(p)) }
}

/// Finds a file's entry in each DJ library: by its path first (any path the file is at, compared by `PathKey`);
/// else, where the library was made on another computer or the music has moved, the one entry whose path ends with
/// the file's path below its source or music folder (two names or more); else the one entry with the file's name and
/// size. Never by title, and never when two entries fit equally.
public struct DJLibraryMatcher: Sendable {
    public let libraries: [DJLibrary]
    private var byPath: [[String: Int]] = []
    private var byName: [[String: [Int]]] = []

    public init(_ libraries: [DJLibrary]) {
        self.libraries = libraries
        for lib in libraries {
            var paths: [String: Int] = [:], names: [String: [Int]] = [:]
            for (i, e) in lib.entries.enumerated() {
                for p in e.paths {
                    let k = PathKey.key(p)
                    if paths[k] == nil { paths[k] = i }
                }
                if let first = e.paths.first { names[PathKey.key(PathKey.lastName(first)), default: []].append(i) }
            }
            byPath.append(paths); byName.append(names)
        }
    }

    /// The file at `paths` (absolute), `rels` below their source or music folder, `size` bytes: its entry in each
    /// library that has one, as (library index, entry).
    public func match(paths: [String], rels: [String], size: Int?) -> [(library: Int, entry: DJLibraryEntry)] {
        var out: [(Int, DJLibraryEntry)] = []
        for (li, lib) in libraries.enumerated() {
            if let i = paths.lazy.compactMap({ self.byPath[li][PathKey.key($0)] }).first {
                out.append((li, lib.entries[i])); continue
            }
            var found: Int? = nil
            for rel in rels {
                let r = PathKey.key(rel)
                guard r.split(separator: "/").count >= 2,
                      let candidates = byName[li][PathKey.key(PathKey.lastName(rel))] else { continue }
                let suffix = candidates.filter { i in lib.entries[i].paths.contains { PathKey.key($0).hasSuffix("/" + r) } }
                if suffix.count == 1 { found = suffix[0]; break }
            }
            if found == nil, let size {
                let names = Set(rels.map { PathKey.key(PathKey.lastName($0)) } + paths.map { PathKey.key(PathKey.lastName($0)) })
                var sized = Set<Int>()
                for n in names {
                    for i in byName[li][n] ?? [] {
                        if let s = lib.entries[i].size, abs(s - size) <= lib.entries[i].sizeSlack { sized.insert(i) }
                    }
                }
                if sized.count == 1 { found = sized.first }
            }
            if let found { out.append((li, lib.entries[found])) }
        }
        return out
    }
}

/// Where each DJ program keeps its library on a Mac and on Windows, found automatically (D30), and the files a DJ may
/// also choose by hand. Only whether a file is there is checked here; nothing is opened.
public enum DJLibraryLocations {
    public struct Found: Equatable, Sendable {
        public var program: DJProgram
        public var url: URL
        public init(program: DJProgram, url: URL) { self.program = program; self.url = url }
    }

    /// The libraries below a user's home folder: Traktor's `Documents/Native Instruments/Traktor <version>/
    /// collection.nml` (every version found), Serato's `Music/_Serato_/database V2`, Engine DJ's `Music/Engine
    /// Library/Database2/m.db`, VirtualDJ's `Documents/VirtualDJ/database.xml` (and on a Mac `Library/Application
    /// Support/VirtualDJ/database.xml`). The same names on both systems: Windows keeps Documents and Music in the home
    /// folder too (a Documents folder moved elsewhere, to OneDrive for one, is not looked for).
    public static func inHome(_ home: URL, exists: (URL) -> Bool = fileExists,
                              list: (URL) -> [String] = listFolder) -> [Found] {
        var out: [Found] = []
        let ni = home.appendingPathComponent("Documents/Native Instruments", isDirectory: true)
        for name in list(ni).filter({ $0.hasPrefix("Traktor") }).sorted() {
            let u = ni.appendingPathComponent(name).appendingPathComponent("collection.nml")
            if exists(u) { out.append(.init(program: .traktor, url: u)) }
        }
        for (program, rel) in [(DJProgram.serato, "Music/_Serato_/database V2"),
                               (.engineDJ, "Music/Engine Library/Database2/m.db"),
                               (.virtualDJ, "Documents/VirtualDJ/database.xml"),
                               (.virtualDJ, "Library/Application Support/VirtualDJ/database.xml")] {
            let u = home.appendingPathComponent(rel)
            if exists(u) { out.append(.init(program: program, url: u)) }
        }
        return out
    }

    /// The libraries a program keeps at the top of a drive, a stick or a folder being read: Serato's
    /// `_Serato_/database V2`, Engine DJ's `Engine Library/Database2/m.db`, VirtualDJ's `VirtualDJ/database.xml`.
    public static func onDrive(_ top: URL, exists: (URL) -> Bool = fileExists) -> [Found] {
        [(DJProgram.serato, "_Serato_/database V2"), (.engineDJ, "Engine Library/Database2/m.db"),
         (.virtualDJ, "VirtualDJ/database.xml")].compactMap { program, rel in
            let u = top.appendingPathComponent(rel)
            return exists(u) ? Found(program: program, url: u) : nil
        }
    }

    /// Whether rekordbox's own library is in the home folder (`Library/Pioneer/rekordbox/master.db` on a Mac,
    /// `AppData/Roaming/Pioneer/rekordbox/master.db` on Windows). It is encrypted and never opened; a DJ who has it
    /// is told to export the collection as XML instead.
    public static func rekordboxDatabase(inHome home: URL, exists: (URL) -> Bool = fileExists) -> Bool {
        ["Library/Pioneer/rekordbox/master.db", "AppData/Roaming/Pioneer/rekordbox/master.db"]
            .contains { exists(home.appendingPathComponent($0)) }
    }

    /// Whether a drive holds a rekordbox USB export (`PIONEER/rekordbox/export.pdb`), which is not read in this
    /// version.
    public static func rekordboxExport(onDrive top: URL, exists: (URL) -> Bool = fileExists) -> Bool {
        exists(top.appendingPathComponent("PIONEER/rekordbox/export.pdb"))
    }

    public static func fileExists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }
    public static func listFolder(_ u: URL) -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: u.path)) ?? [] }
}
