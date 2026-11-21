import Foundation
import DeckieCrate

/// A made-up crate for Booth's golden tests: 24 songs with nothing taken from anyone's music. It has what the picks and
/// the switching rule care about: two sources and songs in plain folders, a recording kept twice (two copies), a file
/// found in two places, songs on no source, Halloween songs, eras, a half-time and a far-tempo song, a song whose tempo
/// changes, a song with only a home note, one Deckie was not sure of, one whose key was never read, a song with no
/// usable name, and one with no mix windows (so the scoring leaves it out).
///
/// Written once as a crate package beside these tests (`Fixtures/booth-fixture.deckie`), so the iPad app's own tests
/// can open the very same crate.
enum FixtureCrate {
    struct Spec {
        var id: String
        var title: String
        var artist: String = "Test Band"
        var disc: String? = nil
        var folder: String? = nil
        var track: Int? = nil
        var rel: String? = nil
        var others: [CrateTrack.Place] = []
        var cut: String? = nil
        var bpm: Double = 126
        var bpmIn: Double? = nil
        var bpmOut: Double? = nil
        var camelot: String? = "8A"
        var homeNote: Bool = false
        var engineVersion: String = "0.7.0"
        var family: String = CrateFormat.EngineFamily.deckie
        var tags: [String] = []
        var era: String? = nil
        var kind: String? = nil
        var version: String? = nil
        var segments: Int = 1
        var mixWindows = true
        var seconds: Double = 300
    }

    static let specs: [Spec] = [
        Spec(id: "s01", title: "Morning Light", disc: "Stick 3", folder: "House", track: 1, bpm: 124, camelot: "8A", era: "90s"),
        Spec(id: "s02", title: "Second Wind", disc: "Stick 3", folder: "House", track: 2, bpm: 125, camelot: "9A", era: "90s"),
        Spec(id: "s03", title: "Glass Floor", disc: "Stick 3", folder: "House", track: 3, bpm: 126, camelot: "8B", era: "00s"),
        Spec(id: "s04", title: "Paper Moon", disc: "Stick 3", folder: "House", track: 4, bpm: 127, camelot: "7A", era: "90s"),
        Spec(id: "s05", title: "Copy Cat", disc: "Stick 3", folder: "Peak", track: 1, cut: "copy-cat", bpm: 128, camelot: "10A", era: "00s"),
        Spec(id: "s06", title: "Copy Cat", disc: "CD Party", folder: "Warm up", track: 1, cut: "copy-cat", bpm: 128, camelot: "10A", era: "00s"),
        Spec(id: "s07", title: "Two Homes", disc: "Stick 3", folder: "Peak", track: 2,
             others: [CrateTrack.Place(disc: "CD Party", folder: "Warm up", track: 2)], bpm: 126, camelot: "8A", era: "80s"),
        Spec(id: "s08", title: "Far Away", disc: "CD Party", folder: "Warm up", track: 3, bpm: 123, camelot: "3B", era: "80s"),
        Spec(id: "s09", title: "Clash Point", disc: "CD Party", folder: "Warm up", track: 4, bpm: 126, camelot: "2A", era: "90s"),
        Spec(id: "s10", title: "Home Note", disc: "CD Party", folder: "Peak", track: 1, bpm: 126, camelot: nil, homeNote: true, era: "90s"),
        Spec(id: "s11", title: "Not Sure", disc: "CD Party", folder: "Peak", track: 2, bpm: 125, camelot: nil, era: "00s"),
        Spec(id: "s12", title: "Never Read", rel: "Downloads/Disco/never-read.mp3", bpm: 124, camelot: nil, family: "lab",
             era: "80s"),
        Spec(id: "s13", title: "Half Step", disc: "Stick 3", folder: "Peak", track: 3, bpm: 63, camelot: "8A", era: "00s"),
        Spec(id: "s14", title: "Fast Lane", disc: "Stick 3", folder: "Peak", track: 4, bpm: 140, camelot: "9A", era: "00s"),
        Spec(id: "s15", title: "Gear Change", disc: "Stick 3", folder: "House", track: 5, bpm: 126, bpmIn: 120,
             camelot: "9B", era: "90s", segments: 2),
        Spec(id: "s16", title: "Night Walk", disc: "CD Party", folder: "Peak", track: 3, bpm: 126, camelot: "8A",
             tags: ["halloween"], era: "80s"),
        Spec(id: "s17", title: "Night Walk", disc: "CD Party", folder: "Peak", track: 4, bpm: 128, camelot: "7A",
             tags: ["halloween"], era: "80s", kind: "official remix", version: "Club Mix"),
        Spec(id: "s18", title: "Track 07", artist: "", rel: "Downloads/Disco/Track 07.mp3", bpm: 125, camelot: "8A"),
        Spec(id: "s19", title: "No Windows", rel: "Downloads/Disco/no-windows.mp3", bpm: 126, camelot: "8A", mixWindows: false),
        Spec(id: "s20", title: "Loose Ends", rel: "Downloads/Edits/loose-ends.mp3", bpm: 126, camelot: "8B", era: "90s"),
        Spec(id: "s21", title: "Bright Side", rel: "Downloads/Edits/bright-side.mp3", bpm: 127, camelot: "9B", era: "00s"),
        Spec(id: "s22", title: "Low Tide", disc: "Stick 3", folder: "House", track: 6, bpm: 122, camelot: "6A", era: "90s"),
        Spec(id: "s23", title: "High Tide", disc: "Stick 3", folder: "House", track: 7, bpm: 130, camelot: "11A", era: "00s"),
        Spec(id: "s24", title: "Even Keel", disc: "CD Party", folder: "Peak", track: 5, bpm: 126, camelot: "8A", era: "90s",
             seconds: 210),
    ]

    static func track(_ s: Spec, _ i: Int) -> CrateTrack {
        let engine = CrateTrack.Engine(family: s.family, version: s.engineVersion, platform: "test", fidelity: 1,
                                       models: [.init(name: "beat-this-small", version: "1")],
                                       decoder: .init(name: "dr_mp3", version: "0.7.4"))
        let barSeconds = 240 / s.bpm
        let n = max(16, Int((s.seconds - 0.5) / barSeconds))
        let bpmIn = s.bpmIn ?? s.bpm, bpmOut = s.bpmOut ?? s.bpm
        let segments: [CrateTrack.TempoSegment] = s.segments < 2
            ? [.init(startBar: 1, startS: 0.5, bpm: s.bpm, beatsPerBar: 4, beatInBar: 1, confidence: 0.9)]
            : [.init(startBar: 1, startS: 0.5, bpm: bpmIn, beatsPerBar: 4, beatInBar: 1, confidence: 0.9),
               .init(startBar: n / 2, startS: 0.5 + Double(n / 2 - 1) * barSeconds, bpm: s.bpm, beatsPerBar: 4, beatInBar: 1,
                     confidence: 0.9)]
        let key: CrateTrack.Key? = s.camelot.map {
            .init(source: "votes", confidence: 0.7, camelot: $0, key: nil, scale: nil, votes: [:], changes: nil)
        }
        let rel = s.rel ?? "\(s.disc ?? "Music")/\(s.folder ?? "")/\(s.title).mp3"
        let name = (rel as NSString).lastPathComponent
        return CrateTrack(
            id: s.id,
            file: .init(name: name, rel: rel, bytes: 5_000_000 + i, sha1Head: String(format: "%04x", i), durationS: s.seconds),
            ident: .init(title: s.title, artist: s.artist.isEmpty ? nil : s.artist, version: s.version, source: "tag",
                         disc: s.disc, folder: s.folder, track: s.track, cutKey: s.cut, isLongest: true, era: s.era,
                         kind: s.kind, tags: s.tags, otherPlaces: s.others),
            analysis: .init(engine: "deckie-\(s.engineVersion)", analysedAt: "2026-11-21T00:00:00Z", device: "test",
                            secs: 10, level: 1),
            engine: engine,
            grid: .init(source: "beat-this-small", confidence: 0.9, bpm: s.bpm, firstDownbeatS: 0.5, nBars: n, fitMadMs: 5,
                        bpmIn: bpmIn, bpmOut: bpmOut, inTrusted: true, outTrusted: true),
            tempoSegments: segments,
            key: key,
            mixIn: s.mixWindows ? .init(startBar: 1, endBar: 17, vocalFreeBars: 16) : nil,
            mixOut: s.mixWindows ? .init(startBar: n - 15, endBar: n + 1, vocalFreeBars: 16) : nil,
            ends: .init(firstSoundS: 0, lastSoundS: s.seconds - 0.5, fadeOut: i % 5 == 0, fadeStartBar: nil, steadyInBar: 1 + i % 3,
                        steadyOutBar: n),
            loudness: .init(source: "deckie-core", confidence: nil, integratedLufs: -9 - Double(i % 4), lra: 5, truePeakDb: -0.3),
            vocal: .init(source: "test", confidence: 0.7, mean: Double(i % 7) / 7, heavy: i % 6 == 0),
            onsetPattern16: (0..<16).map { Double(($0 * (i + 3)) % 16) / 16 },
            style: .init(model: "style-v1", values: (0..<32).map { sin(Double($0 * (i % 5 + 1)) + Double(i) * 0.37) }),
            bars: BarSeries([BarSeries.lufs: (0..<n).map { -14 + 4 * sin(Double($0) / 9 + Double(i)) },
                             BarSeries.vocal: (0..<n).map { Double(($0 + i) % 10) / 10 }]),
            keyHome: s.homeNote ? .init(source: "three-answer", note: "A", pitchClass: 9, camelot: ["8A", "11B"]) : nil)
    }

    static let crate = Crate(
        manifest: CrateManifest(crateId: "b0074e57-0000-4000-8000-000000000024", name: "Booth fixture",
                                createdAt: "2026-11-21T00:00:00Z", devicesSeen: ["test"]),
        tracks: specs.enumerated().map { track($1, $0) })

    static let folder: URL = {
        var u = URL(fileURLWithPath: #filePath)
        u.deleteLastPathComponent()
        return u.appendingPathComponent("Fixtures", isDirectory: true)
    }()
    static let packageURL = folder.appendingPathComponent("booth-fixture.deckie", isDirectory: true)
    /// The demo crate the iPad app carries (deck-app/Deck/Demo).
    static let demoURL: URL = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<4 { u.deleteLastPathComponent() }   // Tests/DeckieBoothTests/<file> -> core -> repo
        return u.appendingPathComponent("deck-app/Deck/Demo/Demo.deckie", isDirectory: true)
    }()
}

/// A golden record: the text a test makes, kept in Fixtures/<name>.txt. `DECKIE_RECORD_GOLDEN=1` writes it; otherwise the
/// text must be the same, line for line.
enum Golden {
    static var recording: Bool { ProcessInfo.processInfo.environment["DECKIE_RECORD_GOLDEN"] == "1" }
    static func url(_ name: String) -> URL { FixtureCrate.folder.appendingPathComponent("\(name).txt") }
    /// The first differing line, or nil when the record matches (or was just written).
    static func check(_ name: String, _ text: String) throws -> String? {
        let u = url(name)
        if recording {
            try FileManager.default.createDirectory(at: FixtureCrate.folder, withIntermediateDirectories: true)
            try text.write(to: u, atomically: true, encoding: .utf8)
            return nil
        }
        guard let read = try? String(contentsOf: u, encoding: .utf8) else { return "\(name).txt is missing" }
        // A Windows checkout may hand the record back with its lines ending the Windows way; the record is its lines.
        let kept = read.replacingOccurrences(of: "\r\n", with: "\n")
        if kept == text { return nil }
        let a = kept.split(separator: "\n", omittingEmptySubsequences: false)
        let b = text.split(separator: "\n", omittingEmptySubsequences: false)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? String(a[i]) : "<none>", y = i < b.count ? String(b[i]) : "<none>"
            if x != y { return "\(name).txt line \(i + 1):\n  kept: \(x)\n  made: \(y)" }
        }
        return "\(name).txt differs"
    }
}

/// A seeded generator (SplitMix64, Steele et al. 2014), so a shuffled shortlist and a generated sequence are the same on
/// every run and every computer. The iPad app's tests carry the same few lines.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
