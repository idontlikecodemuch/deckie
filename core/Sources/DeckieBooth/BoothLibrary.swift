import Foundation
import DeckieCore
import DeckieCrate

/// One place of a song (D26, D27): the source by its own label (nil when it has none), the folder, and the number there
/// (nil in a folder with no source). The iPad app's `TrackPlace`.
public struct BoothPlace: Codable, Hashable, Sendable {
    public let disc: String?
    public let folder: String
    public let num: Int?
    public init(disc: String?, folder: String, num: Int?) { self.disc = disc; self.folder = folder; self.num = num }
}

/// A crate song as Booth sees it: what the switching rule and the picks read. The iPad app's `Track` is made from it and
/// adds what its screens draw (waves, colours, the cover).
public struct BoothSong: Sendable, Equatable {
    public let id: String
    /// "Artist - Song" (the song alone with no artist), the artist, the song's title, its version, the file's name.
    public let title: String
    public let artist: String
    public let song: String
    public let ver: String
    public let deck: String
    /// The place this copy is shown at: its own place, or one of its other places (`at`).
    public var on: Bool
    public var disc: String?
    public var folder: String
    public var num: Int?
    public let hal: Bool
    public let kind: String
    public let era: String
    public let bpmTag: Double?
    /// The recording (D24): copies of one recording share it.
    public let cut: String
    public let longest: Bool
    public let secs: Double?
    public let bpm: Double?
    public let bpmIn: Double?
    public let bpmOut: Double?
    /// The wheel code, when a key was read.
    public let key: String?
    public let keyConf: Double?
    /// The entry's other places (D27); nil when it has none.
    public let others: [BoothPlace]?
    /// False when the crate file gives the song no usable title; nil (named) otherwise.
    public let named: Bool?
    /// The home note (D36) of a song with no key; nil otherwise.
    public let keyHome: String?
    /// True when Deckie read the song and was not sure of its key (D33); nil otherwise.
    public let keyNotSure: Bool?

    public var place: BoothPlace { BoothPlace(disc: disc, folder: folder, num: num) }
    /// Every place of the entry: its own first, then its other places.
    public var places: [BoothPlace] { [BoothPlace(disc: disc, folder: folder, num: num)] + (others ?? []) }
    /// The same song shown at another of its places.
    public func at(_ p: BoothPlace) -> BoothSong {
        guard p != place else { return self }
        var c = self
        c.disc = p.disc; c.folder = p.folder; c.num = p.num; c.on = p.disc != nil
        return c
    }
    public var bpmShown: Double { bpm ?? bpmTag ?? 0 }
    /// The key where a song's key shows (D33, D36): its wheel code; "Home note A"; "not sure"; "?".
    public var keyShown: String {
        if let key { return key }
        if let n = keyHome { return BoothWords.t("song.homeNote", ["note": n]) }
        return keyNotSure == true ? BoothWords.t("song.keyNotSure") : BoothWords.t("song.keyUnknown")
    }
    /// Whether `keyShown` is words rather than a code or "?".
    public var keyShownIsWords: Bool { key == nil && (keyHome != nil || keyNotSure == true) }

    /// A song from a crate file's record, as the iPad's crate library has always read it.
    public init(_ t: CrateTrack) {
        let grid = t.grid
        let artist = t.ident.artist ?? ""
        let song = t.ident.title
        self.id = t.id
        self.title = artist.isEmpty ? song : "\(artist) - \(song)"
        self.artist = artist
        self.song = song
        self.ver = t.ident.version ?? ""
        self.deck = (t.file.name as NSString).deletingPathExtension
        self.on = t.ident.disc != nil
        self.disc = t.ident.disc
        // The folder as the DJ's software shows it: the crate's own label, else the file's parent folder.
        self.folder = t.ident.folder ?? ((t.file.rel ?? "") as NSString).deletingLastPathComponent.components(separatedBy: "/").last ?? ""
        self.num = t.ident.track
        self.hal = t.ident.tags.contains("halloween")
        self.kind = t.ident.kind ?? ""
        self.era = t.ident.era ?? ""
        self.bpmTag = t.file.tagBpm
        self.cut = t.recordingKey
        self.longest = t.ident.isLongest ?? true
        self.secs = t.file.durationS
        self.bpm = grid?.bpm ?? t.file.tagBpm
        self.bpmIn = grid?.bpmIn
        self.bpmOut = grid?.bpmOut
        self.key = t.key?.camelot
        self.keyConf = t.key?.confidence
        // Other places (D27): on a source, its folder there; with no source, the folder's own name, as above.
        self.others = t.ident.otherPlaces.isEmpty ? nil : t.ident.otherPlaces.map { p in
            BoothPlace(disc: p.disc, folder: p.disc != nil ? p.folder ?? "" : (p.folder ?? "").components(separatedBy: "/").last ?? "",
                       num: p.track)
        }
        // A song with no usable title (the crate file's own rule, `SongName`) leads with its place.
        self.named = t.hasUsableTitle ? nil : false
        self.keyHome = t.key == nil ? t.keyHome?.note : nil
        self.keyNotSure = t.keyState == .notSure ? true : nil
    }
}

/// A source of the crate (a CD, a stick, a card), by its label, its position in the crate's order (from 1) and its name.
public struct BoothDisc: Sendable, Equatable {
    public let disc: String
    public let cd: Int
    public let name: String
    /// The disc's name as a chip and a tag show it: the whole name up to 10 characters, else its first word when that
    /// fits ("CD1 Singalongs" reads "CD1"), else the name cut to 9 characters and an ellipsis.
    public var short: String { Self.short(name) }
    public static func short(_ name: String) -> String {
        if name.count <= 10 { return name }
        if let w = name.split(separator: " ").first, w.count <= 10 { return String(w) }
        return String(name.prefix(9)) + BoothWords.t("pick.cutShort")
    }
}

/// A crate as Booth sees it (the iPad app's `Library` and `CrateLibrary`, the parts that are not drawing): its songs and
/// sources, which entries are one song (D24) and where each is (D27), and the scoring that gives one song's picks.
public final class BoothLibrary: @unchecked Sendable {
    public let songs: [BoothSong]
    public let byId: [String: BoothSong]
    /// Every source a place names, own or other, in the crate's order (sorted by label).
    public let discs: [BoothDisc]
    /// The copies of each recording, in crate order.
    public let copiesByCut: [String: [String]]
    /// The scoring tracks and the sorted cosine list, for scoring one song's picks at a time.
    public let pool: PairPool
    public let coreById: [String: DeckieCore.Track]
    /// How long building the sorted cosine list took, in seconds.
    public let poolSecs: Double

    public init(_ crate: Crate) {
        let discNames = Array(Set(crate.tracks.flatMap { $0.ident.allPlaces.compactMap(\.disc) })).sorted()
        discs = discNames.enumerated().map { BoothDisc(disc: $1, cd: $0 + 1, name: $1) }
        songs = crate.tracks.map(BoothSong.init)
        byId = Dictionary(uniqueKeysWithValues: songs.map { ($0.id, $0) })
        var c: [String: [String]] = [:]
        for s in songs { c[s.cut, default: []].append(s.id) }
        copiesByCut = c
        // Picks are scored per song when it plays (`picks(from:)`), not here: the pool keeps the sorted list of
        // track-to-track cosines the timbre rank needs, built once.
        let core = crate.tracks.compactMap { $0.scoringTrack() }
        coreById = Dictionary(core.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let t0 = Date()
        pool = PairPool(core)
        poolSecs = Date().timeIntervalSince(t0)
    }

    /// No crate open.
    public static let empty = BoothLibrary(Crate(manifest: CrateManifest(crateId: "", name: "", createdAt: "", devicesSeen: []), tracks: []))

    /// How many songs the library holds, counting copies of one recording once.
    public var songCount: Int { copiesByCut.count }
    public func song(_ id: String?) -> BoothSong? { id.flatMap { byId[$0] } }
    /// A source's own name, from its label.
    public func sourceName(_ disc: String) -> String { discs.first { $0.disc == disc }?.name ?? disc }

    /// Whether two entries are the same song (the same recording).
    public func sameSong(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b, let x = byId[a], let y = byId[b] else { return false }
        return x.cut == y.cut
    }
    /// Every place the song `id` is at, as songs shown at each place: each copy's own place and its other places (D27;
    /// a copy of the same recording, D24, and the same file found twice are treated alike), the one that leads first (on
    /// `playingDisc`, else on the first disc in the crate's disc order; `SameSong.ordered`), then the rest. `among`
    /// keeps only those places (for a filter); empty when none is left.
    public func places(of id: String, playingDisc: String?, among: ((BoothSong) -> Bool)? = nil) -> [BoothSong] {
        guard let t = byId[id] else { return [] }
        let all = (copiesByCut[t.cut] ?? [id]).compactMap { byId[$0] }.flatMap { c in c.places.map { c.at($0) } }
            .filter { among?($0) ?? true }
        let places = all.enumerated().map { SameSong.Place(id: String($0.offset), disc: $0.element.disc, folder: $0.element.folder, track: $0.element.num) }
        return SameSong.ordered(places, playingDisc: playingDisc, discOrder: discs.map(\.disc)).map { all[Int($0.id)!] }
    }
    /// The copy of the song `id` whose place leads.
    public func leadingCopy(of id: String, playingDisc: String?) -> String {
        places(of: id, playingDisc: playingDisc).first?.id ?? id
    }
    /// The entry `id` shown at the place of its own that leads: among the places `among` allows when there is one, else
    /// among all of them.
    public func placed(_ id: String, playingDisc: String?, among: ((BoothSong) -> Bool)? = nil) -> BoothSong? {
        let mine = { (ts: [BoothSong]) in ts.first { $0.id == id } }
        return mine(places(of: id, playingDisc: playingDisc, among: among)) ?? mine(places(of: id, playingDisc: playingDisc)) ?? byId[id]
    }
    /// Whether the filter allows the entry: when it allows any of its places (D27).
    public func allows(_ t: BoothSong, _ filter: BoothFilter) -> Bool {
        t.places.contains { p in let s = t.at(p); return filter.allows(on: s.on, disc: s.disc, crateHasDiscs: !discs.isEmpty) }
    }

    /// The picks for one song: every other track that passes the scoring's gates, scored from it, best first. Nothing is
    /// cut here; `BoothPicks` keeps the shortlist from this list after its filters.
    public func picks(from a: String) -> [BoothPair] {
        guard let A = coreById[a] else { return [] }
        let sorted = pool.scores(from: A).sorted { $0.scoreBase > $1.scoreBase }
        return sorted.map { p in
            let B = coreById[p.b]
            let km = BoothJoin.multiples[p.multiplier] ?? 1
            let pitch = B.map { ((A.bpmOut / ($0.bpmIn * km)) - 1) * 100 }.map { ($0 * 10).rounded() / 10 }
            let moves = p.moves.isEmpty ? [p.suggestedTransition] : p.moves
            // A song with only a home note (D36) is scored as the better fit of the two keys on its note; the pair
            // carries the two codes the scoring compared, and says so, so the key words do not claim a key was read.
            let homeOnly = B.map { (!PairScoring.keyRead(A) && A.homePitchClass != nil) || (!PairScoring.keyRead($0) && $0.homePitchClass != nil) } ?? false
            let compared = homeOnly ? B.flatMap { PairScoring.keyTermDetail(A, $0).codes } : nil
            let labels = BoothWords.moveLabels
            return BoothPair(b: p.b, s: (p.scoreBase * 1000).rounded() / 1000, st: (p.stretchPct * 10).rounded() / 10,
                             m: p.multiplier, pitch: pitch, tr: p.suggestedTransition,
                             trl: labels[p.suggestedTransition] ?? p.suggestedTransition,
                             ka: compared?.a ?? (A.camelot.isEmpty ? "?" : A.camelot),
                             kb: compared?.b ?? (B?.camelot).flatMap { $0.isEmpty ? nil : $0 } ?? "?",
                             reasons: Array(p.reasons.prefix(5)), mv: Array(moves.map { labels[$0] ?? $0 }.prefix(3)),
                             ks: p.keyShiftSt, kh: compared != nil ? true : nil)
        }
    }
}
