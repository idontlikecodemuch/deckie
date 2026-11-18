import Foundation
import SwiftUI
import DeckieCrate

// MARK: - bundled data (Deck/Resources/deck_data.json, built by tools/prep_data.py)

struct Wave: Codable, Hashable {
    let t0: Double
    let n: Int
    let s: String
    let win: [Int]
    let beat0: Int
    var k0: Int? = nil       // grid index (in samples, from the first downbeat) of sample 0

    private static let b64: [Character: Int] = {
        var m: [Character: Int] = [:]
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".enumerated() { m[c] = i }
        return m
    }()
    /// 0...63 per quarter beat
    var values: [Int] { s.map { Wave.b64[$0] ?? 0 } }
}

/// whole-song waveform (Resources/overview.json, tools/overview_waves.py)
struct Overview: Codable {
    static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
    let n: Int
    let dur: Double
    let s: String
    var values: [Int] { Wave(t0: 0, n: n, s: s, win: [0, 0], beat0: 0).values }
    /// 0...1 heights with the quiet floor removed and a curve, so loud masters still show their shape
    var display: [Double] { Overview.shape(values.map { Double($0) / 63 }) }
    /// The whole-song wave's treatment of 0...1 values: the quiet floor (the 10th percentile of the values given)
    /// is removed and a curve applied, giving 0...1 heights. The crate join lanes use it too, with the song's floor.
    static func shape(_ v: [Double]) -> [Double] {
        guard !v.isEmpty else { return [] }
        let lo = v.sorted()[max(0, v.count / 10)]
        return v.map { x in 0.08 + 0.92 * pow(max(0, (x - lo) / max(0.05, 1 - lo)), 1.8) }
    }
}

struct Track: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String
    let song: String
    let ver: String
    let deck: String
    // The place this copy is shown at: its own place, or one of its other places (`at`).
    var on: Bool
    var disc: String?
    var folder: String
    let hal: Bool
    let kind: String
    let era: String
    let bpmTag: Double?
    let cut: String
    let longest: Bool
    let secs: Double?
    var cd: Int?
    var num: Int?
    let bpm: Double?
    let bpmIn: Double?
    let bpmOut: Double?
    let key: String?
    let keyConf: Double?
    let dur: Double?
    let mixIn: [Double]?
    let mixOut: [Double]?
    let mixInBars: Int?
    let mixOutBars: Int?
    let fade: Bool?
    let firstBeat: Double?
    let wOut: Wave?
    let wIn: Wave?
    let wHead: Wave?          // track start .. 64 bars, for choosing where the next song starts
    let spb: Int?             // samples per beat of the snippets
    let steadyIn: Double?     // first steady-beat bar, seconds
    let bpmGrid: Double?
    /// The entry's other places (D27): the same file found somewhere else. Nil in the bundled data.
    var others: [TrackPlace]? = nil
    /// False when the crate file gives the song no usable title (`SongName`: empty, a number, "Track 07"); nil (named)
    /// in the bundled data.
    var named: Bool? = nil
    /// The song's facts from the crate file (D34): release, year, label, genre and whatever else its file, its disc,
    /// the DJ's programs or the DJ gave, by name, each with its values. Nil in the bundled data and in a crate file
    /// written before them.
    var facts: [String: [String]]? = nil
    /// The home note (D36: "A", "C#") of a song whose key reader found the home note and left major or minor open;
    /// nil when the song has a key, and in the bundled data.
    var keyHome: String? = nil
    /// True when Deckie's reader read the song and was not sure of its key (D33), as distinct from a key that was
    /// never read; nil otherwise and in the bundled data.
    var keyNotSure: Bool? = nil
    /// The song's cover (D36): the hash that names `covers/<hash>.jpg` in the crate file; nil when it has none.
    var cover: String? = nil

    /// The key where a song's key shows (D33, D36): its wheel code; "Home note A" in place of the code; "not sure"
    /// when Deckie read it and was not sure; "?" when no key was read.
    var keyShown: String {
        if let key { return key }
        if let n = keyHome { return Words.homeNote(n) }
        return keyNotSure == true ? Words.keyNotSureShort : Words.unknownKey
    }
    /// Whether `keyShown` is words rather than a code or "?", so a narrow key column lets it be as wide as it needs.
    var keyShownIsWords: Bool { key == nil && (keyHome != nil || keyNotSure == true) }

    /// Clean or dirty (D39), from the crate file's `lyrics` fact: "clean", "dirty", or nil when not said.
    var lyrics: String? { facts?["lyrics"]?.first }

    /// The short line of facts where a song's details are shown: "Friday Night · 1999 · Nervous · House, Garage",
    /// with only those present; nil when the crate file gives none. How facts are shown is to be refined (D34).
    var factsLine: String? {
        guard let f = facts else { return nil }
        return Words.factsLine(["release", "year", "label", "genre"].compactMap { f[$0] })
    }

    /// Where this track is shown: its source, folder and number.
    var place: TrackPlace { TrackPlace(disc: disc, folder: folder, num: num) }
    /// Every place of the entry: its own first, then its other places.
    var places: [TrackPlace] { [TrackPlace(disc: disc, folder: folder, num: num)] + (others ?? []) }
    /// The same track shown at another of its places: the source, folder and number (and the source's colour) of `p`.
    func at(_ p: TrackPlace) -> Track {
        guard p != place else { return self }
        var c = self
        c.disc = p.disc; c.folder = p.folder; c.num = p.num; c.on = p.disc != nil
        c.cd = p.disc.flatMap { d in Library.shared.data.discs.first { $0.disc == d }?.cd }
        return c
    }

    var samplesPerBeat: Int { spb ?? 4 }
    var gridBPM: Double { bpmGrid ?? bpm ?? bpmTag ?? 120 }
    var isRemix: Bool { !ver.isEmpty || kind == "pool edit" || kind == "official remix" }

    var bpmShown: Double { bpm ?? bpmTag ?? 0 }
    var duration: Double { dur ?? secs ?? 240 }
    // Places (D26): a source (the CD, stick or card the song was read from) is shown by its own name, never by a
    // word of ours; a song with no source is shown by its folder.
    /// The name of the source this song is on (its own name: "Stick 3", or the bundled data's "CD1 Singalongs").
    var sourceName: String? { disc.map { Library.shared.sourceName($0) } }
    /// "Stick 3 / House /": the source's name and the folder on it ("Stick 3 /" at its top). With no source: the
    /// file's own folder, which is how the DJ's software shows it.
    var folderPath: String {
        guard let s = sourceName else { return folder }
        return folder.isEmpty ? Words.sourceTop(s) : Words.sourceFolder(s, folder)
    }
    /// "Stick 3 / House / 04": where this copy is, as an "also on" line says it; with no source, the file's own folder.
    var placeText: String {
        guard let s = sourceName else { return folder }
        return s + (folder.isEmpty ? "" : Words.placeJoin + folder) + (num.map { Words.placeNumber($0) } ?? "")
    }
    /// "06 Lady (Hear Me Tonight)": track number as in the file name on the deck. A song with no name reads
    /// "06 · no name yet" (research AA, 3.13: the place leads, never a blank row or a placeholder title).
    var numberedSong: String { num.map { Words.numbered($0, songShown) } ?? songShown }

    // A song with no name (research AA, 3.13). The booth finds and shows it like any other; its place leads, and the
    // file name is shown only as a file name, never in the title's place. The words are in `Words`.
    /// Whether the crate file names this song.
    var hasName: Bool { named ?? true }
    /// The title, or "no name yet".
    var songShown: String { hasName ? song : Words.noNameYetInRow }
    /// The line under the title: the artist (nothing when there is none), or for a song with no name the file it was
    /// read from ("file: Track07").
    var secondLine: String { hasName ? artist : (deck.isEmpty ? "" : Words.fileLine(deck)) }
    /// The playing panel's big line: the title with its number, or for a song with no name its place ("Friday night
    /// / Peak / 07"; the folder when it is on no source; "No name yet" when it has neither).
    var playingTitle: String {
        if hasName { return numberedSong }
        // Broken by phrase: the source's name on one line, the folder and number on the next.
        if let s = sourceName {
            let rest = [folder.isEmpty ? nil : folder, num.map { Words.number($0) }].compactMap { $0 }.joined(separator: Words.placeJoin)
            return rest.isEmpty ? s : Words.twoLines(s, rest)
        }
        return placeText.isEmpty ? Words.noNameYet : placeText
    }
    /// The song in one line, for a log, a tracklist or a spoken label: "Song A", or "Friday night / Peak / 07 · no
    /// name yet".
    var oneLine: String {
        if hasName { return song }
        return placeText.isEmpty ? Words.noNameYet : placeText + Words.dotJoin + Words.noNameYetInRow
    }
    /// What the search in More looks through: title and artist, or for a song with no name its place and file name;
    /// and every fact the crate file gives it (D34: release, label, genre, ...).
    func matches(_ q: String) -> Bool {
        if facts?.values.contains(where: { $0.contains { $0.localizedStandardContains(q) } }) == true { return true }
        if hasName { return song.localizedStandardContains(q) || artist.localizedStandardContains(q) }
        return placeText.localizedStandardContains(q) || deck.localizedStandardContains(q)
            || Words.noNameYetInRow.localizedStandardContains(q)
    }
    /// the source's colour, the two colours alternating by the source's position (first lavender, second blue, third
    /// lavender, ...; no source: the accent)
    var discColor: Color { cd.map(Theme.disc) ?? Theme.acc }
    var functionColor: Color { hal ? Theme.hal : (cd.map(Theme.disc) ?? Theme.mut) }
}

/// One place of a track (D26, D27): the source by its own label (nil when it has none), the folder, and the number
/// there (nil in a folder with no source).
struct TrackPlace: Codable, Hashable {
    let disc: String?
    let folder: String
    let num: Int?
}

struct Pair: Codable, Hashable {
    let b: String
    let s: Double
    let st: Double
    let m: String
    let pitch: Double?
    let tr: String
    let trl: String
    let ka: String
    let kb: String
    let reasons: [String]
    let mv: [String]?        // up to three moves, primary first (labels)
    let ks: Int?
    /// D36: true when either song has only a home note, so `ka` and `kb` are the codes the scoring compared it as
    /// (the better fit of the two keys on the note), not keys that were read. Nil in the bundled data.
    var kh: Bool? = nil
}

struct DiscFolder: Codable, Hashable { let name: String; let ids: [String] }
struct Disc: Codable, Hashable {
    let disc: String; let cd: Int; let name: String; let folders: [DiscFolder]
    /// The disc's name as a chip and a tag show it: the whole name up to 10 characters, else its first word when that
    /// fits ("CD1 Singalongs" reads "CD1"), else the name cut to 9 characters and an ellipsis.
    var short: String {
        if name.count <= 10 { return name }
        if let w = name.split(separator: " ").first, w.count <= 10 { return String(w) }
        return String(name.prefix(9)) + Words.cutShort
    }
    var color: Color { Theme.disc(cd) }
}

struct DeckData: Codable {
    let generated: String
    let tracks: [Track]
    let discs: [Disc]
    let pairs: [String: [Pair]]
    let catalogVariants: [String]?
}

final class Library {
    static let shared = Library()
    private(set) var data: DeckData
    private(set) var byId: [String: Track]
    private(set) var overview: [String: Overview]
    /// The crate in use, if the data came from one rather than the bundled deck_data.json.
    private(set) var crate: CrateLibrary?

    private init() {
        data = DeckData(generated: "", tracks: [], discs: [], pairs: [:], catalogVariants: nil)
        byId = [:]; overview = [:]
        // A crate first: the one remembered (opened before, kept in the app's own storage), else one placed in the
        // app's Documents folder (Files app, Finder), taken into the app's storage in either form; the bundled data
        // otherwise.
        if let url = Library.rememberedCrate, let c = try? CrateLibrary.load(url) {
            apply(c)
        } else if let doc = Library.crateInDocuments, let r = try? CrateImport.copy(doc, into: Library.storeFolder),
                  let c = try? CrateLibrary.load(r.package) {
            apply(c)
            UserDefaults.standard.set(r.package.path, forKey: "cratePath")
        } else if let url = Bundle.main.url(forResource: "deck_data", withExtension: "json"),
                  let d = try? Data(contentsOf: url), let dd = try? JSONDecoder().decode(DeckData.self, from: d) {
            data = dd
            byId = Dictionary(uniqueKeysWithValues: dd.tracks.map { ($0.id, $0) })
            indexCopies()
            if let u = Bundle.main.url(forResource: "overview", withExtension: "json"), let d2 = try? Data(contentsOf: u),
               let ov = try? JSONDecoder().decode([String: Overview].self, from: d2) { overview = ov }
        }
    }

    func load(crate url: URL) throws {
        apply(try CrateLibrary.load(url))
        UserDefaults.standard.set(url.path, forKey: "cratePath")
    }

    /// Opens a crate file the DJ handed the app (Files, AirDrop, iCloud Drive, a cable, "Open in", or a test hook), in
    /// either form: a package folder made on a Mac or the single file made on a PC. It is copied (a package) or
    /// unpacked (a single file) into the app's own storage, read whole there, and only then used; the file the DJ
    /// gave is only read. A file from a file provider (iCloud Drive) is read through a file coordinator, so it is
    /// downloaded first when it is not on the iPad yet.
    func open(crateFile url: URL) throws -> CrateImport.Result {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var result: Result<CrateImport.Result, Error> = .failure(CocoaError(.fileReadUnknown))
        var coordinationError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { readable in
            result = Result { try CrateImport.copy(readable, into: Library.storeFolder) }
        }
        if let coordinationError { throw coordinationError }
        let r = try result.get()
        try load(crate: r.package)
        return r
    }

    /// Where the app keeps the crate files it has opened, as packages: Application Support/Crates, out of the DJ's
    /// way (not in the Files app).
    static var storeFolder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("Crates", isDirectory: true)
    }

    /// Whether the booth can name what is playing: the bundled data's catalogue, or a crate file with fingerprints
    /// (recognition signatures). A crate file made on a PC has none yet (D29); its songs are set by hand.
    var canRecognise: Bool { crate.map { !$0.signatures.isEmpty || $0.deckieSongs > 0 } ?? true }

    /// The open crate file's fingerprints, handed once to Deckie's index and then let go (they are not needed again
    /// until another crate file opens, and a large crate's are many megabytes).
    func takeFingerprints() -> Crate.Fingerprints? {
        defer { pendingFingerprints = nil }
        return pendingFingerprints
    }
    private var pendingFingerprints: Crate.Fingerprints?

    private func apply(_ c: CrateLibrary) {
        var c = c
        pendingFingerprints = c.fingerprints
        c.fingerprints = nil
        crate = c
        recentPicks = [:]; recentOrder = []
        data = c.data
        byId = Dictionary(uniqueKeysWithValues: c.data.tracks.map { ($0.id, $0) })
        overview = c.overview
        indexCopies()
    }

    // MARK: the same song (D24)

    /// The copies of each recording (`Track.cut`, the crate's cut_key, else the entry's id), in crate order. Two
    /// entries are the same song only when they are the same recording; nothing is folded by title.
    private(set) var copiesByCut: [String: [String]] = [:]
    private func indexCopies() {
        copiesByCut = [:]
        for t in data.tracks { copiesByCut[t.cut, default: []].append(t.id) }
    }
    /// How many songs the library holds, counting copies of one recording once.
    var songCount: Int { copiesByCut.count }
    /// Whether two entries are the same song (the same recording).
    func sameSong(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b, let x = byId[a], let y = byId[b] else { return false }
        return x.cut == y.cut
    }
    /// Every place of the song `id` is, as tracks shown at each place: each copy's own place and its other places
    /// (D27; a copy of the same recording, D24, and the same file found twice are treated alike), in the order the
    /// booth shows them: the one that leads first (on `playingDisc`, else on the first disc in the crate's disc order;
    /// `SameSong.ordered`), then the rest. `among` keeps only those places (for a filter); empty when none is left.
    func places(of id: String, playingDisc: String?, among: ((Track) -> Bool)? = nil) -> [Track] {
        guard let t = byId[id] else { return [] }
        let all = (copiesByCut[t.cut] ?? [id]).compactMap { byId[$0] }.flatMap { c in c.places.map { c.at($0) } }
            .filter { among?($0) ?? true }
        let places = all.enumerated().map { SameSong.Place(id: String($0.offset), disc: $0.element.disc, folder: $0.element.folder, track: $0.element.num) }
        return SameSong.ordered(places, playingDisc: playingDisc, discOrder: data.discs.map(\.disc)).map { all[Int($0.id)!] }
    }
    /// The copy of the song `id` is whose place leads (see `places(of:playingDisc:among:)`).
    func leadingCopy(of id: String, playingDisc: String?) -> String {
        places(of: id, playingDisc: playingDisc).first?.id ?? id
    }
    /// The entry `id` shown at the place of its own that leads: among the places `among` allows when there is one,
    /// else among all of them. This is the place a row shows; the rest are its "also on".
    func placed(_ id: String, playingDisc: String?, among: ((Track) -> Bool)? = nil) -> Track? {
        let mine = { (ts: [Track]) in ts.first { $0.id == id } }
        return mine(places(of: id, playingDisc: playingDisc, among: among)) ?? mine(places(of: id, playingDisc: playingDisc)) ?? byId[id]
    }
    /// Whether the filter allows the entry: when it allows any of its places (D27).
    func allows(_ t: Track, _ filter: LibraryFilter) -> Bool { t.places.contains { filter.allows(t.at($0)) } }
    /// "also on Stick 3 / Peak / 04 · also in Album": every other place of the song `t` is shown at (its copies'
    /// and its own other places), in order; nil when it has none.
    func alsoOn(_ t: Track, playingDisc: String?) -> String? {
        let others = places(of: t.id, playingDisc: playingDisc).filter { !($0.id == t.id && $0.place == t.place) }
        guard !others.isEmpty else { return nil }
        let onDiscs = others.filter { $0.cd != nil }.map(\.placeText)
        let inFolders = others.filter { $0.cd == nil }.map(\.placeText)
        return ((onDiscs.isEmpty ? [] : [Words.alsoOn(onDiscs)])
                + (inFolders.isEmpty ? [] : [Words.alsoIn(inFolders)])).joined(separator: Words.dotJoin)
    }

    static var rememberedCrate: URL? {
        guard let p = UserDefaults.standard.string(forKey: "cratePath"), FileManager.default.fileExists(atPath: p) else { return nil }
        return URL(fileURLWithPath: p)
    }
    /// The first .deckiecrate in the app's Documents folder (Files app > On My iPad > Deck).
    static var crateInDocuments: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
              let names = try? FileManager.default.contentsOfDirectory(atPath: docs.path) else { return nil }
        return names.filter { $0.hasSuffix(".deckiecrate") }.sorted().first.map { docs.appendingPathComponent($0) }
    }

    func track(_ id: String?) -> Track? { id.flatMap { byId[$0] } }

    /// A source's own name, from its label (the crate file's `disc`; the bundled data's labels are "S" and "M").
    func sourceName(_ disc: String) -> String { data.discs.first { $0.disc == disc }?.name ?? disc }

    /// The songs with no source, by folder: the folders in the order a player walks them, each folder's songs by file
    /// name in the same order (`SourceReading`). The Crate tab shows them after the sources. A song in a folder on the
    /// Mac as well as on a source (D27) is listed here too.
    var folders: [DiscFolder] {
        var by: [String: [Track]] = [:]
        for t in data.tracks { for p in Set(t.places) where p.disc == nil { by[p.folder, default: []].append(t) } }
        return by.keys.sorted(by: SourceReading.groupComesBefore).map { f in
            DiscFolder(name: f, ids: by[f]!.sorted { SourceReading.comesBefore($0.deck, $1.deck, isFile: false) }.map(\.id))
        }
    }

    /// The picks for a song, the one place the views get them: the bundled data's list (its 80 best, made by
    /// tools/prep_data.py), or for a crate every scored song, scored when the song is first asked for. The last few songs' lists are kept so going back and forth
    /// between songs does not score them again.
    func pairs(from id: String) -> [Pair] {
        guard let crate else { return data.pairs[id] ?? [] }
        if let hit = recentPicks[id] { return hit }
        let t0 = Date()
        let list = crate.picks(from: id)
        lastPickSecs = Date().timeIntervalSince(t0)
        recentPicks[id] = list
        recentOrder.removeAll { $0 == id }
        recentOrder.append(id)
        while recentOrder.count > Library.recentLimit { recentPicks[recentOrder.removeFirst()] = nil }
        return list
    }
    private static let recentLimit = 8
    private var recentPicks: [String: [Pair]] = [:]
    private var recentOrder: [String] = []
    /// How long the last song's picks took to score, in seconds; read once, for the booth's log.
    private var lastPickSecs: Double?
    func takePickSecs() -> Double? { defer { lastPickSecs = nil }; return lastPickSecs }
}

// The theme's colours (the web player's tokens) are Theme, in Look.swift.

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

func fmtTime(_ s: Double) -> String {
    let t = max(0, Int(s.rounded()))
    return String(format: "%d:%02d", t / 60, t % 60)
}
func signed1(_ p: Double) -> String { Words.signed(p > 0.05 ? Words.signPlus : p < -0.05 ? Words.signMinus : Words.signNone, abs(p)) }
