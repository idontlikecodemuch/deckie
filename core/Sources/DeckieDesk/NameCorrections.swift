import Foundation
import DeckieCrate

/// A DJ's fix to one entry's names: each field fixed holds the DJ's value, and a field not fixed is nil, so a re-read
/// can take a new tag for the rest. Artist and version can be fixed to nothing (`Text(nil)`).
public struct NameCorrection: Codable, Equatable, Sendable {
    public struct Text: Codable, Equatable, Sendable {
        public var value: String?
        public init(_ value: String?) { self.value = value }
    }
    public var title: String?
    public var artist: Text?
    public var version: Text?
    public var tags: [String]?

    public init(title: String? = nil, artist: Text? = nil, version: Text? = nil, tags: [String]? = nil) {
        self.title = title; self.artist = artist; self.version = version; self.tags = tags
    }

    public var isEmpty: Bool { title == nil && artist == nil && version == nil && tags == nil }
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
        if a.title != b.title { c.title = a.title }
        if a.artist != b.artist { c.artist = .init(a.artist) }
        if a.version != b.version { c.version = .init(a.version) }
        if a.tags != b.tags { c.tags = a.tags }
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
            crate.tracks[i].ident = id
            if crate.tracks[i] != before { changed += 1 }
        }
        return changed
    }

    public static func load(from url: URL) -> NameCorrections { JSONFile.read(Self.self, from: url) ?? NameCorrections() }
    public func save(to url: URL) throws { try JSONFile.write(self, to: url) }
}
