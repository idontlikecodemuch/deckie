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

/// A name for a source being read, so two different folders that happen to share a name do not become one source.
public enum SourceNaming {
    /// `name` itself when no source has it, or when the source of that name was read from `root` (the same source
    /// read again), or when the place it was read from is not there now (a stick mounted under another path). Else
    /// "name 2", "name 3", ..., the first free or already read from `root`.
    public static func unique(_ name: String, root: URL, roots: [String: URL],
                              exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> String {
        func free(_ n: String) -> Bool {
            guard let r = roots[n] else { return true }
            return r.standardizedFileURL.path == root.standardizedFileURL.path || !exists(r)
        }
        if free(name) { return name }
        var k = 2
        while !free("\(name) \(k)") { k += 1 }
        return "\(name) \(k)"
    }
}
