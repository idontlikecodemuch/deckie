import Foundation
import DeckieCrate

/// A DJ's fix to one entry's names and facts: each field fixed holds the DJ's value, and a field not fixed is nil, so
/// a re-read can take a new tag for the rest. Artist and version can be fixed to nothing (`Text(nil)`).
public struct NameCorrection: Codable, Equatable, Sendable {
    public struct Text: Codable, Equatable, Sendable {
        public var value: String?
        public init(_ value: String?) { self.value = value }
    }
    public var title: String?
    public var artist: Text?
    public var version: Text?
    public var tags: [String]?
    /// How the DJ gave each field fixed (letter AA): `user` (typed; also when this is missing), `pasted` (a list),
    /// `pattern` (the file names read by a pattern the DJ set), `playlist` (a playlist the DJ chose), `checked`
    /// (Desk's guess, which the DJ looked at and kept). By field name.
    public var from: [String: String]?
    /// The DJ's facts (D34), by `SongFacts` name: the values the DJ gave, or an empty list for a fact the DJ cleared
    /// (so the file's own value is not shown either). The same store as the names, so a re-read keeps both.
    public var facts: [String: [String]]?

    public init(title: String? = nil, artist: Text? = nil, version: Text? = nil, tags: [String]? = nil,
                from: [String: String]? = nil, facts: [String: [String]]? = nil) {
        self.title = title; self.artist = artist; self.version = version; self.tags = tags; self.from = from
        self.facts = facts
    }

    public var isEmpty: Bool { title == nil && artist == nil && version == nil && tags == nil && (facts ?? [:]).isEmpty }
}

/// The DJ's name fixes for one crate (`corrections.json`), by entry id. Reading a source or folder again writes the
/// names from the files' tags; the fixes are then put back (`apply`), so a fix is kept across reads and runs. Ids are
/// the file's content, so a fix follows the file wherever it is read from, and an edited file (other bytes) is a new
/// entry with its own names.
public struct NameCorrections: Codable, Equatable, Sendable {
    public var byId: [String: NameCorrection]

    public init(byId: [String: NameCorrection] = [:]) { self.byId = byId }

    enum CodingKeys: String, CodingKey { case byId = "by_id" }

    /// Notes what the DJ changed between `before` and `after` (one entry, the same id).
    public mutating func note(before: CrateTrack, after: CrateTrack) {
        guard before.id == after.id else { return }
        var c = byId[after.id] ?? NameCorrection()
        let b = before.ident, a = after.ident
        var how = c.from ?? [:]
        if a.title != b.title { c.title = a.title; how["title"] = "user" }
        if a.artist != b.artist { c.artist = .init(a.artist); how["artist"] = "user" }
        if a.version != b.version { c.version = .init(a.version); how["version"] = "user" }
        if a.tags != b.tags { c.tags = a.tags }
        // Facts (D34): one the DJ set (`from: user`) or took away.
        var facts = c.facts ?? [:]
        for name in Set(a.facts.keys).union(b.facts.keys) where a.facts[name] != b.facts[name] {
            if let f = a.facts[name] {
                guard f.from == SongFacts.Origin.user else { continue }
                facts[name] = f.values
            } else {
                facts[name] = []
            }
            how[name] = "user"
        }
        c.facts = facts.isEmpty ? nil : facts
        c.from = how.isEmpty ? nil : how
        byId[after.id] = c.isEmpty ? nil : c
    }

    /// Notes every name change from one crate to another (entries matched by id).
    public mutating func note(from old: Crate, to new: Crate) {
        let was = Dictionary(old.tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for t in new.tracks { if let b = was[t.id] { note(before: b, after: t) } }
    }

    /// Puts the fixes back on the crate's entries; the names fixed are marked as the DJ's (`ident.source` "user").
    /// Returns how many entries changed.
    @discardableResult
    public func apply(to crate: inout Crate) -> Int {
        var changed = 0
        for i in crate.tracks.indices {
            guard let c = byId[crate.tracks[i].id] else { continue }
            let before = crate.tracks[i]
            var id = before.ident
            if let t = c.title { id.title = t }
            if let a = c.artist { id.artist = a.value }
            if let v = c.version { id.version = v.value }
            if let t = c.tags { id.tags = t }
            if c.title != nil || c.artist != nil || c.version != nil { id.source = "user" }
            // The DJ's facts go back over whatever the reading found; a cleared one is taken out.
            for (name, values) in c.facts ?? [:] {
                id.facts[name] = values.isEmpty ? nil : CrateTrack.Fact(values, from: SongFacts.Origin.user)
            }
            crate.tracks[i].ident = id
            if crate.tracks[i] != before { changed += 1 }
        }
        return changed
    }

    public static func load(from url: URL) -> NameCorrections { JSONFile.read(Self.self, from: url) ?? NameCorrections() }
    public func save(to url: URL) throws { try JSONFile.write(self, to: url) }
}
