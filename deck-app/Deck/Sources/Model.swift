import Foundation
import SwiftUI

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
    let on: Bool
    let disc: String?
    let folder: String
    let hal: Bool
    let kind: String
    let era: String
    let bpmTag: Double?
    let cut: String
    let longest: Bool
    let secs: Double?
    let cd: Int?
    let num: Int?
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

    var samplesPerBeat: Int { spb ?? 4 }
    var gridBPM: Double { bpmGrid ?? bpm ?? bpmTag ?? 120 }
    var isRemix: Bool { !ver.isEmpty || kind == "pool edit" || kind == "official remix" }

    var bpmShown: Double { bpm ?? bpmTag ?? 0 }
    /// one entry per song in suggestions: the title without bracketed version info, letters and digits only
    var songKey: String {
        var t = song.lowercased()
        while let a = t.firstIndex(where: { $0 == "(" || $0 == "[" }), let b = t[a...].firstIndex(where: { $0 == ")" || $0 == "]" }) { t.removeSubrange(a...b) }
        return String(t.filter { $0.isLetter || $0.isNumber })
    }
    var duration: Double { dur ?? secs ?? 240 }
    /// "CD2 · 6-04": folder number and track number as the CDJ shows them
    var discLabel: String? {
        guard let cd, let num else { return nil }
        let f = folder.split(separator: " ").first.map(String.init) ?? "?"
        return "CD\(cd) · \(f)-\(String(format: "%02d", num))"
    }
    /// "CD1 · 8 - 135 plus · 02": disc, folder as named on the disc, track number (the CDJ browser's view)
    var discLocation: String {
        guard let cd, let num else { return folder }
        return "CD\(cd) · \(folder) · \(String(format: "%02d", num))"
    }
    /// "CD1 / 6 - 125-129 /": the folder path on the disc
    /// Off the discs (or in a crate without discs): the file's own folder, which is how the DJ's software shows it.
    var folderPath: String { cd.map { "CD\($0) / \(folder) /" } ?? folder }
    /// "06 Lady (Hear Me Tonight)": track number as in the file name on the deck
    var numberedSong: String { num.map { String(format: "%02d · ", $0) + song } ?? song }
    /// the disc's colour (CD1 lavender, CD2 teal; off the discs: the accent)
    var discColor: Color { disc == "S" ? Theme.sing : disc == "M" ? Theme.mix : Theme.acc }
    var functionColor: Color { hal ? Theme.hal : (disc == "S" ? Theme.sing : disc == "M" ? Theme.mix : Theme.mut) }
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
struct Disc: Codable, Hashable { let disc: String; let cd: Int; let name: String; let folders: [DiscFolder] }

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

    /// The picks for a song, the one place the views get them: the bundled data's trimmed list, or for a crate the
    /// list scored when the song is first asked for. The last few songs' lists are kept so going back and forth
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
