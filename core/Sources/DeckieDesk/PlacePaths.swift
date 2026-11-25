import Foundation
import DeckieCrate
import DeckieBuild

/// Where each place's file was when a desk read it (`places.json`), by entry id: the place's source (nil for the
/// ordinary music folder), its folder there as read, and the file's path below the source's top (or below the music
/// folder). The crate file carries one path, the own place's (`file.rel`); this keeps the path at every place, so a
/// desk always knows where a song's file is: when a source is read again without a song and an other place is
/// promoted to its own, `file.rel` is set from here instead of being left unknown, and anything that needs the file
/// tries each place in turn and takes the first whose source is present.
public struct PlacePaths: Codable, Equatable, Sendable {
    public struct Path: Codable, Hashable, Sendable {
        /// The source (`ident.disc`), or nil for the music folder.
        public var source: String?
        /// The folder on the source as read (it may since have been renamed in the crate).
        public var folder: String?
        /// The file's path below the source's top, or below the music folder.
        public var rel: String
        public init(source: String?, folder: String?, rel: String) { self.source = source; self.folder = folder; self.rel = rel }
    }

    public var byId: [String: [Path]]

    public init(byId: [String: [Path]] = [:]) { self.byId = byId }

    enum CodingKeys: String, CodingKey { case byId = "by_id" }

    /// After a read of `source` (or of the music folder when nil, keeping the sources `keep`): the paths that belong
    /// to that read are replaced by what was read now (`BuildResult.placesRead`); every other path stays. The rule is
    /// the builder's: a source's read owns that source's places; a folder's read owns the places with no source, or
    /// a source not kept.
    public mutating func record(_ read: [String: [ReadPlace]], source: String?, keep: Set<String> = []) {
        func belongs(_ s: String?) -> Bool {
            if let source { return s == source }
            return s.map { !keep.contains($0) } ?? true
        }
        for id in Array(byId.keys) {
            byId[id]!.removeAll { belongs($0.source) }
            if byId[id]!.isEmpty { byId[id] = nil }
        }
        for (id, list) in read {
            var paths = byId[id] ?? []
            for r in list {
                let p = Path(source: r.place.disc, folder: r.place.folder, rel: r.rel)
                if !paths.contains(p) { paths.append(p) }
            }
            byId[id] = paths
        }
    }

    /// The path of the file at `place` of entry `id`: the one on that source in that folder, else the first on that
    /// source, else nil.
    public func rel(for id: String, at place: CrateTrack.Place) -> String? {
        let on = (byId[id] ?? []).filter { $0.source == place.disc }
        return (on.first { ($0.folder ?? "") == (place.folder ?? "") } ?? on.first)?.rel
    }

    /// Sets `file.rel` of every entry that has none (its own place was promoted from an other place) from the path
    /// remembered for its own place. Returns how many were set.
    @discardableResult
    public func fillMissingPaths(_ crate: inout Crate) -> Int {
        var n = 0
        for i in crate.tracks.indices where crate.tracks[i].file.rel == nil {
            if let r = rel(for: crate.tracks[i].id, at: crate.tracks[i].ident.ownPlace) { crate.tracks[i].file.rel = r; n += 1 }
        }
        return n
    }

    /// A source renamed in the crate is renamed here too.
    public mutating func renameSource(_ old: String, to new: String) {
        for id in Array(byId.keys) {
            byId[id] = byId[id]!.map { var p = $0; if p.source == old { p.source = new }; return p }
        }
    }

    /// Forgets the paths on a source (or the music folder, nil).
    public mutating func forget(source: String?) {
        for id in Array(byId.keys) {
            byId[id]!.removeAll { $0.source == source }
            if byId[id]!.isEmpty { byId[id] = nil }
        }
    }

    /// Forgets entries no longer in the crate.
    public mutating func keepOnly(_ ids: Set<String>) { byId = byId.filter { ids.contains($0.key) } }

    /// Every file `t` may be at on this computer, in order: its own place's path (`file.rel`), then each remembered
    /// place in the order the places lead. A place on a source with no known root, or the music folder when none is
    /// known, gives nothing.
    public func candidates(for t: CrateTrack, roots: [String: URL], musicFolder: URL?) -> [URL] {
        func root(_ s: String?) -> URL? { s.map { roots[$0] } ?? musicFolder }
        var out: [URL] = []
        func add(_ u: URL?) { if let u, !out.contains(u) { out.append(u) } }
        if let rel = t.file.rel { add(root(t.ident.disc)?.appendingPathComponent(rel)) }
        for p in t.placesInOrder {
            if let rel = rel(for: t.id, at: p) { add(root(p.disc)?.appendingPathComponent(rel)) }
        }
        for p in byId[t.id] ?? [] { add(root(p.source)?.appendingPathComponent(p.rel)) }
        return out
    }

    /// The first of `candidates` that is there now (its source plugged in), or nil.
    public func locate(_ t: CrateTrack, roots: [String: URL], musicFolder: URL?,
                       exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> URL? {
        candidates(for: t, roots: roots, musicFolder: musicFolder).first(where: exists)
    }

    public static func load(from url: URL) -> PlacePaths { JSONFile.read(Self.self, from: url) ?? PlacePaths() }
    public func save(to url: URL) throws { try JSONFile.write(self, to: url) }
}

extension CrateInfo {
    /// The source a folder or a drive at `root` is read into (`SourceNaming.choose`): the source it already is, else
    /// a new one named `name`, numbered when that name is in use. Never one of the crate's music CDs.
    /// `crate` and `paths` are the crate's own (what its sources are known to hold); `identify` and `size` are the
    /// system's, replaced in tests.
    public func sourceName(_ name: String, root: URL, crate: Crate?, paths: PlacePaths,
                           identify: SourceIdentity.Reader = SourceIdentity.read,
                           size: (URL) -> Int? = SourceNaming.fileSize) -> String {
        SourceNaming.choose(name, root: root, found: identify(root), recorded: recordedSources(crate: crate, paths: paths),
                            taken: Set(discs.keys), size: size)
    }

    /// What Add music reads for a folder or a drive at `root`: its source (`sourceName`) and the identity of the drive
    /// it is on now, so a run carried on later reads the same drive and no other.
    public func sourceRequest(_ name: String, root: URL, crate: Crate?, paths: PlacePaths, rekordbox: URL? = nil,
                              identify: SourceIdentity.Reader = SourceIdentity.read,
                              size: (URL) -> Int? = SourceNaming.fileSize) -> RunRequest {
        let found = identify(root)
        let source = SourceNaming.choose(name, root: root, found: found, recorded: recordedSources(crate: crate, paths: paths),
                                         taken: Set(discs.keys), size: size)
        var r = RunRequest(folder: root, source: source, rekordbox: rekordbox)
        r.volume = found.identity
        return r
    }

    /// Every source of this crate that is a folder or a drive, as `SourceNaming` weighs it: where it was read from,
    /// its drive's identity, and the files it is known to hold (each place on it Desk remembers, `places.json`, and
    /// each song's own path, `file.rel`), each with its size. A source the crate names but this desk never read (a
    /// crate brought in from elsewhere) is one too, with no place and no identity. Music CDs are left out.
    public func recordedSources(crate: Crate?, paths: PlacePaths) -> [SourceNaming.Recorded] {
        typealias File = SourceNaming.Recorded.File
        // Every place of one song holds the same bytes (its id is their hash), so the song's size is each file's.
        var bytes: [String: Int] = [:]
        for t in crate?.tracks ?? [] { if let b = t.file.bytes { bytes[t.id] = b } }
        var files: [String: [String: File]] = [:]
        for (id, list) in paths.byId {
            for p in list { if let s = p.source { files[s, default: [:]][p.rel] = File(rel: p.rel, bytes: bytes[id]) } }
        }
        for t in crate?.tracks ?? [] {
            if let s = t.ident.disc, let rel = t.file.rel, files[s]?[rel] == nil {
                files[s, default: [:]][rel] = File(rel: rel, bytes: t.file.bytes)
            }
        }
        var names = Set(roots.keys)
        for t in crate?.tracks ?? [] { for p in t.ident.allPlaces { if let s = p.disc { names.insert(s) } } }
        names.subtract(discs.keys)
        return names.sorted().map { n in
            SourceNaming.Recorded(name: n, root: roots[n], identity: sourceIds[n],
                                  files: (files[n] ?? [:]).values.sorted { $0.rel < $1.rel })
        }
    }
}

/// Which source a folder or a drive being read is (Nov 25, 2026): two sticks that share a name, or are mounted one
/// after the other at the same path, are two sources, and the same stick is one source wherever it is mounted. Adding
/// a source never takes another source's songs: what a read finds replaces only the songs of the source it is read
/// into, so choosing the wrong source would lose songs, and when in doubt a new source is made.
public enum SourceNaming {
    /// A source of the crate as it is weighed: its name, where it was last read from, its drive's identity (nil when
    /// none was known), and the files it is known to hold.
    public struct Recorded: Equatable, Sendable {
        public var name: String
        public var root: URL?
        public var identity: SourceIdentity?
        public var files: [File]
        public struct File: Equatable, Sendable {
            /// The path below the source's top.
            public var rel: String
            /// The file's size in bytes, when known.
            public var bytes: Int?
            public init(rel: String, bytes: Int?) { self.rel = rel; self.bytes = bytes }
        }
        public init(name: String, root: URL?, identity: SourceIdentity?, files: [File]) {
            self.name = name; self.root = root; self.identity = identity; self.files = files
        }
    }

    /// The source to read `root` into. First, a source whose drive has the very identity `found` gives, at the same
    /// place on it, is that source, whatever its name now and wherever the drive is mounted. Otherwise `name` itself
    /// when no source has it, or when the source of that name is this one (`same`); else "name 2", "name 3", ...,
    /// the first that is free or is this one. `taken`: names never free (the crate's music CDs).
    public static func choose(_ name: String, root: URL, found: SourceIdentity.Found, recorded: [Recorded],
                              taken: Set<String> = [], size: (URL) -> Int? = fileSize) -> String {
        if let id = found.identity, let s = recorded.first(where: { $0.identity == id }) { return s.name }
        let byName = Dictionary(recorded.map { ($0.name, $0) }, uniquingKeysWith: { a, _ in a })
        func free(_ n: String) -> Bool {
            if taken.contains(n) { return false }
            guard let s = byName[n] else { return true }
            return same(s, root: root, found: found, size: size)
        }
        if free(name) { return name }
        var k = 2
        while !free("\(name) \(k)") { k += 1 }
        return "\(name) \(k)"
    }

    /// Whether the folder or drive at `root` is the recorded source `s`:
    /// 1. Both identities known: a different drive is a different source; the same drive at the same place on it is
    ///    the same source; the same drive at another place on it is decided by evidence (a folder moved on it).
    /// 2. An identity missing on either side (a system or file system that gives none, or a source recorded before
    ///    identities were kept): the very same folder on the computer's own disk is the same source (a path there
    ///    is not reused by another drive, as a mount point is); anything else is decided by evidence.
    /// Evidence (`holdsMostOf`): more than half of the files the source is known to hold are at `root` under the
    /// same path with the same size. A source with no known files is never the same by evidence.
    public static func same(_ s: Recorded, root: URL, found: SourceIdentity.Found, size: (URL) -> Int? = fileSize) -> Bool {
        if let a = found.identity, let b = s.identity {
            if a.volume != b.volume { return false }
            if a.inside == b.inside { return true }
            return holdsMostOf(s.files, at: root, size: size)
        }
        if found.ownDisk, let r = s.root, comparablePath(r) == comparablePath(root) { return true }
        return holdsMostOf(s.files, at: root, size: size)
    }

    /// A place's path in a form two places can be compared by: `Folders.standardized` (a Windows drive's top is kept
    /// as `E:\`, never standardised into a path below the working folder), and on Windows in lower case, because
    /// Windows' names do not tell case apart (`C:\Music` and `c:\music` are one folder), which `Folders.same` does
    /// only for the drive's letter.
    static func comparablePath(_ url: URL) -> String {
        let p = Folders.standardized(url).path
        #if os(Windows)
        return p.lowercased()
        #else
        return p
        #endif
    }

    /// More than half of `files` are below `root`, each with its size when the size is known. Stops as soon as the
    /// answer is certain.
    public static func holdsMostOf(_ files: [Recorded.File], at root: URL, size: (URL) -> Int? = fileSize) -> Bool {
        guard !files.isEmpty else { return false }
        var found = 0, missing = 0
        for f in files {
            let there = size(root.appendingPathComponent(f.rel)).map { got in f.bytes.map { $0 == got } ?? true } ?? false
            if there { found += 1 } else { missing += 1 }
            if found * 2 > files.count { return true }
            if missing * 2 >= files.count { return false }
        }
        return false
    }

    /// The size of an ordinary file, or nil when there is none at `url`.
    public static func fileSize(_ url: URL) -> Int? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              (a[.type] as? FileAttributeType) == .typeRegular else { return nil }
        return (a[.size] as? NSNumber)?.intValue
    }

    /// The first of `name`, "name 2", "name 3", ... not in `taken` (a music CD's name, which is not found by a path).
    public static func unique(_ name: String, taken: Set<String>) -> String {
        if !taken.contains(name) { return name }
        var k = 2
        while taken.contains("\(name) \(k)") { k += 1 }
        return "\(name) \(k)"
    }
}
