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
        return folder.isEmpty ? "\(s) /" : "\(s) / \(folder) /"
    }
    /// "Stick 3 / House / 04": where this copy is, as an "also on" line says it; with no source, the file's own folder.
    var placeText: String {
        guard let s = sourceName else { return folder }
        return s + (folder.isEmpty ? "" : " / \(folder)") + (num.map { String(format: " / %02d", $0) } ?? "")
    }
    /// "06 Lady (Hear Me Tonight)": track number as in the file name on the deck
    var numberedSong: String { num.map { String(format: "%02d · ", $0) + song } ?? song }
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
}

struct DiscFolder: Codable, Hashable { let name: String; let ids: [String] }
struct Disc: Codable, Hashable {
    let disc: String; let cd: Int; let name: String; let folders: [DiscFolder]
    /// The disc's name as a chip and a tag show it: the whole name up to 10 characters, else its first word when that
    /// fits ("CD1 Singalongs" reads "CD1"), else the name cut to 9 characters and an ellipsis.
    var short: String {
        if name.count <= 10 { return name }
        if let w = name.split(separator: " ").first, w.count <= 10 { return String(w) }
        return String(name.prefix(9)) + "…"
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
        // A crate first: the one remembered, else one placed in the app's Documents folder (Files app, Finder);
        // the bundled data otherwise.
        if let url = Library.rememberedCrate ?? Library.crateInDocuments, let c = try? CrateLibrary.load(url) {
            apply(c)
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

    private func apply(_ c: CrateLibrary) {
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
        return ((onDiscs.isEmpty ? [] : ["also on " + onDiscs.joined(separator: ", ")])
                + (inFolders.isEmpty ? [] : ["also in " + inFolders.joined(separator: ", ")])).joined(separator: " · ")
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

// MARK: - theme (the web player's tokens)

enum Theme {
    static let bg = Color(hex: 0x0f0a17)
    static let bg2 = Color(hex: 0x160f22)
    static let card = Color(hex: 0x1d1530)
    static let card2 = Color(hex: 0x251b3b)
    static let line = Color(hex: 0x30254a)
    static let tx = Color(hex: 0xf2edf9)
    static let mut = Color(hex: 0xab9fc2)
    static let dim = Color(hex: 0x76698f)
    static let acc = Color(hex: 0xb490ff)
    static let acc2 = Color(hex: 0x8a5cff)
    static let accDim = Color(hex: 0x4a3b6e)
    static let orange = Color(hex: 0xff8a1f)
    static let amber = Color(hex: 0xffc040)
    static let bad = Color(hex: 0xff5d6c)
    static let ok = Color(hex: 0x72dca0)
    static let sing = Color(hex: 0x8f7bc8)     // CD1: muted lavender
    static let mix = Color(hex: 0x5a6cc0)      // CD2: dark, spooky blue
    /// A disc's colour by its number: the two disc colours alternating (odd discs lavender, even discs blue).
    static func disc(_ cd: Int) -> Color { cd % 2 == 1 ? sing : mix }
    static let hal = Color(hex: 0xff8a1f)
    static let rsn = Color(hex: 0xa99bd0)
    static let chipTx = Color(hex: 0xe3d6ff)
    static let backdrop = LinearGradient(colors: [Color(hex: 0x1c1036), Color(hex: 0x0f0a17)], startPoint: .topTrailing, endPoint: .bottomLeading)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: alpha)
    }
}

func fmtTime(_ s: Double) -> String {
    let t = max(0, Int(s.rounded()))
    return String(format: "%d:%02d", t / 60, t % 60)
}
func signed1(_ p: Double) -> String { (p > 0.05 ? "+" : p < -0.05 ? "−" : "±") + String(format: "%.1f", abs(p)) }
