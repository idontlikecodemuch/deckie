import Foundation
import DeckieCrate

/// One crate a desk keeps (`crate.json` in its folder): its name, when it was made and last opened, and where its
/// music was read from on this computer. The crate file holds no absolute path; this does, and it never leaves the
/// computer.
public struct CrateInfo: Codable, Equatable, Hashable, Sendable {
    /// The crate's folder name: a lowercase UUID made with it. Not the crate file's own `crate_id`.
    public var id: String
    public var name: String
    /// Seconds since 1970.
    public var createdAt: Double
    public var openedAt: Double
    /// Where each source was last read from, by the source's name (a mounted volume's path, or the folder chosen).
    public var sourceRoots: [String: String]
    /// The ordinary folder read with no source (the rekordbox route, or a crate made before sources), if any.
    public var musicFolder: String?

    public init(id: String, name: String, createdAt: Double, openedAt: Double, sourceRoots: [String: String] = [:],
                musicFolder: String? = nil) {
        self.id = id; self.name = name; self.createdAt = createdAt; self.openedAt = openedAt
        self.sourceRoots = sourceRoots; self.musicFolder = musicFolder
    }

    enum CodingKeys: String, CodingKey {
        case id, name, createdAt = "created_at", openedAt = "opened_at", sourceRoots = "source_roots"
        case musicFolder = "music_folder"
    }

    public var roots: [String: URL] { sourceRoots.mapValues { URL(fileURLWithPath: $0) } }
    public var musicFolderURL: URL? { musicFolder.map { URL(fileURLWithPath: $0) } }
}

/// A desk's crates (D28): made, listed most recent first, renamed, deleted, brought in from a crate file and sent
/// out as one. Each crate is a folder below `Crates/`; see `DeskHome` for what is in it.
public struct CrateShelf: Sendable {
    public let home: DeskHome
    public init(home: DeskHome) { self.home = home }

    public static let infoFile = "crate.json"
    public static let packageName = "crate.deckiecrate"

    public func folder(_ id: String) -> URL { home.cratesFolder.appendingPathComponent(id, isDirectory: true) }
    /// The crate file, kept in the crate's folder; it exists once music has been added.
    public func package(_ id: String) -> URL { folder(id).appendingPathComponent(Self.packageName, isDirectory: true) }
    public func file(_ name: String, of id: String) -> URL { folder(id).appendingPathComponent(name) }

    /// Every crate, the one opened most recently first.
    public func list() -> [CrateInfo] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home.cratesFolder.path)) ?? []
        return names.compactMap { info($0) }.sorted {
            $0.openedAt != $1.openedAt ? $0.openedAt > $1.openedAt : $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    public func info(_ id: String) -> CrateInfo? { JSONFile.read(CrateInfo.self, from: file(Self.infoFile, of: id)) }

    public func save(_ info: CrateInfo) throws { try JSONFile.write(info, to: file(Self.infoFile, of: info.id)) }

    /// The crate most recently opened, if there is one.
    public var mostRecent: CrateInfo? { list().first }

    /// A crate by its name (the first, most recent, when two share it).
    public func named(_ name: String) -> CrateInfo? { list().first { $0.name == name } }

    /// A name no crate has yet: `name`, else "name 2", "name 3", ...
    public func unusedName(_ name: String, except id: String? = nil) -> String {
        let taken = Set(list().filter { $0.id != id }.map { $0.name.lowercased() })
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = base.isEmpty ? "Crate" : base
        if !taken.contains(start.lowercased()) { return start }
        var n = 2
        while taken.contains("\(start) \(n)".lowercased()) { n += 1 }
        return "\(start) \(n)"
    }

    /// Makes an empty crate (no crate file until music is added), named `name` or a free variant of it.
    @discardableResult
    public func make(name: String, now: Double = Date().timeIntervalSince1970) throws -> CrateInfo {
        try home.prepare()
        let info = CrateInfo(id: UUID().uuidString.lowercased(), name: unusedName(name), createdAt: now, openedAt: now)
        try FileManager.default.createDirectory(at: folder(info.id), withIntermediateDirectories: true)
        try save(info)
        return info
    }

    /// Notes that the crate was opened now, so it is the one Desk opens next time.
    @discardableResult
    public func touch(_ id: String, now: Double = Date().timeIntervalSince1970) throws -> CrateInfo? {
        guard var i = info(id) else { return nil }
        i.openedAt = max(now, (list().first?.openedAt ?? 0) + 0.001)
        try save(i)
        return i
    }

    /// Renames a crate: its name here and the name its crate file carries (the one the booth shows). Returns the
    /// name given, made unique among the crates.
    @discardableResult
    public func rename(_ id: String, to new: String) throws -> CrateInfo {
        guard var i = info(id) else { throw DeskError("no crate \(id)") }
        let n = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, n != i.name else { return i }
        i.name = unusedName(n, except: id)
        try save(i)
        let pkg = package(id)
        if FileManager.default.fileExists(atPath: pkg.appendingPathComponent(CrateFormat.manifestFile).path) {
            var c = try CrateReader.read(from: pkg)
            c.manifest.name = i.name
            try CrateWriter.write(c, to: pkg)
        }
        return i
    }

    /// Deletes a crate's folder for good: its crate file, its work folder, its corrections. What was worked out for
    /// each file stays in `Files/`, so adding the same music again is quick.
    public func delete(_ id: String) throws {
        let f = folder(id)
        guard f.deletingLastPathComponent().standardizedFileURL == home.cratesFolder.standardizedFileURL else { return }
        if FileManager.default.fileExists(atPath: f.path) { try FileManager.default.removeItem(at: f) }
    }

    /// Brings in a crate file made elsewhere as a new crate: the file is checked, then copied; the original is only
    /// read, never changed. The crate takes the name the file carries (made unique).
    @discardableResult
    public func importCopy(of url: URL, now: Double = Date().timeIntervalSince1970) throws -> CrateInfo {
        let c = try CrateReader.read(from: url)
        try home.prepare()
        let info = CrateInfo(id: UUID().uuidString.lowercased(), name: unusedName(c.manifest.name), createdAt: now,
                             openedAt: now)
        let fm = FileManager.default
        try fm.createDirectory(at: folder(info.id), withIntermediateDirectories: true)
        do {
            try fm.copyItem(at: url, to: package(info.id))
            if info.name != c.manifest.name {
                var copy = try CrateReader.read(from: package(info.id))
                copy.manifest.name = info.name
                try CrateWriter.write(copy, to: package(info.id))
            }
            try save(info)
        } catch {
            try? fm.removeItem(at: folder(info.id))
            throw error
        }
        return info
    }

    /// Writes a copy of the crate's crate file to `destination` (replacing what is there), for the DJ to keep or
    /// send. Throws when the crate has no music yet.
    public func exportCopy(_ id: String, to destination: URL) throws {
        let pkg = package(id)
        let fm = FileManager.default
        guard fm.fileExists(atPath: pkg.appendingPathComponent(CrateFormat.manifestFile).path) else {
            throw DeskError("the crate has no songs yet, so there is no crate file to write")
        }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.copyItem(at: pkg, to: destination)
        // Signatures of songs taken out of the crate stay in Desk's own copy (an undo puts the songs back); the copy
        // that leaves carries only the crate's own.
        let c = try CrateReader.read(from: destination)
        let listed = Set(c.tracks.flatMap { t in t.signatures.keys.map { "\(t.id)_\($0).shazamsignature" } })
        let sigs = destination.appendingPathComponent(CrateFormat.signaturesFolder)
        for name in (try? fm.contentsOfDirectory(atPath: sigs.path)) ?? [] where name.hasSuffix(".shazamsignature") && !listed.contains(name) {
            try fm.removeItem(at: sigs.appendingPathComponent(name))
        }
    }

    /// The crate file copied to the outbox under the crate's name (`Friday night.deckiecrate`), ready for the share
    /// sheet; the outbox holds only the last one.
    public func outboxCopy(_ id: String) throws -> URL {
        guard let i = info(id) else { throw DeskError("no crate \(id)") }
        let fm = FileManager.default
        if fm.fileExists(atPath: home.outbox.path) { try fm.removeItem(at: home.outbox) }
        let safe = i.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let dest = home.outbox.appendingPathComponent(safe + "." + CrateFormat.packageExtension, isDirectory: true)
        try exportCopy(id, to: dest)
        return dest
    }
}
