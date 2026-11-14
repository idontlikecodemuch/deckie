import Foundation
import DeckieCrate
import DeckieBuild

/// The crate as a window shows it, as plain data with codes instead of words (docs/architecture/desk-protocol.md,
/// "songs"): one row per song for the table, the sources panel's outline, and the list of what did not go in. The
/// Windows and Linux pages draw these; which words a code takes is `DeskWords`'.
public struct DeskSongRow: Codable, Equatable, Sendable {
    public struct Place: Codable, Equatable, Sendable {
        /// The source's name, or nil for the music folder (a crate made before sources, or the rekordbox route).
        public var source: String?
        /// The folder on the source ("" at its top), or the folder below the music folder.
        public var folder: String
        public var number: Int?
        /// "Stick 3 / House 4", as the booth shows a place; nil for the music folder.
        public var line: String?
    }
    public struct Key: Codable, Equatable, Sendable {
        public var camelot: String
        public var key: String?
        public var scale: String?
        /// Where it came from, as a code (`rekordbox-xml`, `tag`, `deckie`, ...): words `keyFrom.<code>`.
        public var from: String
        public var uncertain: Bool
        /// What the DJ's other programs, and Deckie's own reading, say: code and Camelot key.
        public var others: [Other]
        public struct Other: Codable, Equatable, Sendable { public var from: String; public var camelot: String }
    }

    public var id: String
    public var title: String
    public var artist: String?
    public var version: String?
    public var tags: [String]
    /// Where the name came from, as codes joined by "+" (`tag`, `filename`, `user`, ...).
    public var nameFrom: String?
    /// In the "Needs a name" list: no usable title, no artist, or a guess of Desk's not yet checked (letter AA, 3.3).
    public var needsName: Bool
    /// Why, as a code: `noTitle`, `noArtist`, `guess` (words `nameReason.<code>`); nil when it has a name.
    public var nameReason: String?
    /// Each name, where it came from and whether it is a guess (the panel's small lines, letter AA 3.4).
    public var names: DeskNaming.Facts?
    /// Tempo in beats per minute, and bars; nil when the song has no beat grid.
    public var bpm: Double?
    public var bars: Int?
    public var seconds: Double
    public var vocals: Double?
    public var vocalHeavy: Bool
    public var key: Key?
    /// What the record says about the key, as a code: `key`, `home_note`, `not_sure`, `not_read`
    /// (`CrateTrack.KeyState`). Words: a key as before; `homeNote` for the home note; `keyDeckieNotSure`; `keyNotRead`.
    public var keyState: String
    /// The home note alone (D36), when there is no key: its name and the two keys on it.
    public var homeNote: HomeNote?
    public struct HomeNote: Codable, Equatable, Sendable { public var note: String; public var camelot: [String] }
    /// Every place the song is (D27), the one that leads first.
    public var places: [Place]
    public var file: String
    public var signed: Bool
    /// Notes as codes: `needsName`, `damagedFrames`, `gridUnsure`, `vocalsNotRead`, `signed`.
    public var notes: [String]
    public var damagedFrames: Int

    public init(_ t: CrateTrack, facts: DeskNaming.Facts? = nil) {
        id = t.id
        title = t.ident.title
        artist = t.ident.artist
        version = t.ident.version
        tags = t.ident.tags
        nameFrom = t.ident.source
        names = facts
        nameReason = facts.flatMap { DeskNaming.reason(t, $0) } ?? (LocalFacts.needsName(t) ? "noTitle" : nil)
        if facts == nil && nameReason != nil && LocalNames.isUsableTitle(t.ident.title) { nameReason = "noArtist" }
        needsName = nameReason != nil
        bpm = t.grid?.bpm
        bars = t.grid?.nBars
        seconds = t.file.durationS
        vocals = t.vocal?.mean
        vocalHeavy = t.vocal?.heavy ?? false
        if let k = t.key {
            let others = k.votes
                .filter { (LocalFacts.djOrigins.contains($0.key) || $0.key == LocalFacts.ownVote) && $0.key != k.source }
                .sorted { $0.key < $1.key }
                .map { Key.Other(from: $0.key, camelot: $0.value) }
            key = Key(camelot: k.camelot, key: k.key, scale: k.scale, from: k.source,
                      uncertain: t.flags.contains("key_uncertain"), others: others)
        } else { key = nil }
        keyState = t.keyState.rawValue
        homeNote = t.key == nil ? t.keyHome.map { HomeNote(note: $0.note, camelot: $0.camelot) } : nil
        places = t.placesInOrder.map { p in
            Place(source: p.disc, folder: p.folder ?? "", number: p.track, line: Crate.placeLine(p))
        }
        file = t.file.name
        signed = !t.signatures.isEmpty
        damagedFrames = t.file.damagedFrames?.count ?? 0
        var n: [String] = []
        if needsName { n.append("needsName") }
        if damagedFrames > 0 { n.append("damagedFrames") }
        if t.flags.contains("low_grid_confidence") { n.append("gridUnsure") }
        if t.flags.contains("vocal_unknown") { n.append("vocalsNotRead") }
        if signed { n.append("signed") }
        notes = n
    }
}

/// The sources panel's outline: each source by its own name, its folders in the order a player walks them, each
/// folder's songs by their number there.
public struct DeskSourceRow: Codable, Equatable, Sendable {
    public struct Folder: Codable, Equatable, Sendable {
        public var name: String
        public var songs: [Song]
    }
    public struct Song: Codable, Equatable, Sendable {
        public var id: String
        public var number: Int?
    }
    public var name: String
    public var songs: Int
    public var folders: [Folder]

    public static func outline(_ crate: Crate) -> [DeskSourceRow] {
        crate.discPlan.map { d in
            let folders = d.folders.map { f in
                Folder(name: f.name, songs: crate.folderPlaces(disc: d.name, folder: f.name).map { Song(id: $0.id, number: $0.number) })
            }
            return DeskSourceRow(name: d.name, songs: d.folders.reduce(0) { $0 + $1.trackIds.count }, folders: folders)
        }
    }
}

/// What did not go in (the crate's import log), grouped by reason code.
public struct DeskImportLog: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var rel: String
        public var reason: String
        public var message: String
    }
    public var builtBy: String
    public var builtAt: String
    public var filesSeen: Int
    public var songs: Int
    public var entries: [Entry]

    public init?(_ crate: Crate) {
        guard let log = crate.manifest.importLog else { return nil }
        builtBy = log.builtBy; builtAt = log.builtAt; filesSeen = log.filesSeen; songs = log.tracks
        entries = log.entries.map { Entry(rel: $0.rel, reason: $0.reason, message: $0.message) }
    }

    /// Files that are not in the crate (a damaged frame is a note on a song that did go in).
    public var notInCount: Int { entries.filter { $0.reason != CrateManifest.ImportLog.Reason.damagedFrames }.count }
}
