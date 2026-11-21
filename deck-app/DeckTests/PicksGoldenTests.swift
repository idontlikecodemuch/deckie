import Foundation
import Testing
@testable import Deck

/// The picks' golden record (the move of Nov 21, 2026: the picks into the core must not change what the iPad shows).
/// Two crates, the demo crate and the core's made-up fixture crate (core/Tests/DeckieBoothTests/Fixtures), go through
/// the app's own picks: for every song, with discs switched off and on, songs played before, a pinned song and the
/// Shuffle dial at three settings (a seeded dice), every pick's place, kind, tags, pair, join words, BPM line and move
/// line; and the Listen page's split into the picks shown and More. The text is kept in
/// core/Tests/DeckieBoothTests/Fixtures/picks-golden-<crate>.txt, which the core's tests check the shared picks
/// against. Missing, it is written; there, it must match.
///   nice -n 19 xcodebuild test -project Deck.xcodeproj -scheme Deck -destination 'platform=iOS Simulator,name=<an iPad>'
@Suite(.serialized) struct PicksGoldenTests {
    static let repo: URL = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { u.deleteLastPathComponent() }
        return u
    }()
    static let fixtures = repo.appendingPathComponent("core/Tests/DeckieBoothTests/Fixtures")

    /// SplitMix64, as the core's tests have it.
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

    static func d(_ x: Double?) -> String { x.map { "\($0)" } ?? "-" }

    static func pairText(_ p: Pair?) -> String {
        guard let p else { return "pair=-" }
        return "pair=\(p.b) s=\(p.s) st=\(p.st) m=\(p.m) pitch=\(d(p.pitch)) tr=\(p.tr) trl=\(p.trl) ka=\(p.ka) kb=\(p.kb)"
            + " mv=\((p.mv ?? []).joined(separator: "/")) ks=\(p.ks.map { "\($0)" } ?? "-") kh=\(p.kh.map { "\($0)" } ?? "-")"
            + " reasons=\(p.reasons.joined(separator: " | "))"
    }

    static func joinText(_ cur: Track, _ t: Track, _ p: Pair?, _ deckA: Double) -> String {
        let ji = joinInfo(cur, t, p, deckAPitch: deckA)
        return "join(\(deckA))=bm:\(ji.beatMatch) pitch:\(d(ji.pitch)) pt:\(ji.pitchText) keys:\(ji.keyText) v:\(ji.verdict)"
            + " vk:\(ji.verdictKind) sB:\(ji.scaleB) bpmLine:\(pickBPMLine(t, p, ji)) moveLine:\(pickMoveLine(p, ji))"
    }

    @MainActor static func text() -> String {
        let lib = Library.shared
        var out: [String] = ["songs \(lib.songCount) discs \(lib.data.discs.map(\.disc).joined(separator: ","))"]
        let discs = lib.data.discs.map(\.disc)
        var filters: [(String, LibraryFilter)] = [("all discs", LibraryFilter())]
        if let first = discs.first {
            var f = LibraryFilter(); f.set(first, on: false); filters.append(("\(first) off", f))
            var g = f; g.other = true; filters.append(("\(first) off, all on", g))
        }
        var o = LibraryFilter(); o.other = true; filters.append(("all on", o))
        let ids = lib.data.tracks.map(\.id)
        var seed: UInt64 = 1
        for id in ids {
            guard let t = lib.track(id) else { continue }
            // The song at each of its places (D27), as the playing panel shows it.
            for place in t.places {
                let cur = t.at(place)
                let others = ids.filter { $0 != id }
                let history = Array(others.prefix(3))
                let pins: [String?] = [nil, others.last, others.first { o in !lib.pairs(from: id).contains { $0.b == o } }]
                // Every filter at every dial setting; songs played before with each pinned song at one setting.
                var runs: [(String, LibraryFilter, [String], String?, Double)] = []
                for (fname, filter) in filters { for shuffle in [0.0, 0.5, 1.0] { runs.append((fname, filter, [], nil, shuffle)) } }
                for pinned in pins { runs.append((filters[0].0, filters[0].1, history, pinned, 0.5)) }
                for (fname, filter, exclude, pinned, shuffle) in runs {
                    var rng = SeededRNG(seed: seed); seed += 1
                    let (list, short) = Suggester().ranked(cur: cur, target: filter, exclude: Set(exclude), pinned: pinned,
                                                           shuffle: shuffle, rng: &rng)
                    out.append("cur=\(id)@\(place.disc ?? "-")/\(place.folder)/\(place.num.map { "\($0)" } ?? "-") filter=\(fname)"
                               + " label=\(filter.label) exclude=\(exclude.joined(separator: ",")) pinned=\(pinned ?? "-")"
                               + " shuffle=\(shuffle) seed=\(seed - 1) shortlist=\(short) rows=\(list.count)")
                    // Every row's words for the first roll of each filter; the first rows and the pinned one after.
                    let full = shuffle == 0 && exclude.isEmpty
                    for (i, op) in list.enumerated() {
                        guard let target = lib.placed(op.id, playingDisc: cur.disc, among: filter.allows) else {
                            out.append("  \(i) \(op.id) (no track)"); continue
                        }
                        var line = "  \(i) \(op.kind == .pinned ? "pinned" : "pick") \(op.id) at=\(target.disc ?? "-")/\(target.folder)"
                            + " tags=\(op.tags.joined(separator: ","))"
                        if full || i < 4 || op.kind == .pinned {
                            line += " " + pairText(op.pair) + " " + joinText(cur, target, op.pair, 0) + " " + joinText(cur, target, op.pair, 1.7)
                        } else {
                            line += " s=\(op.pair.map { "\($0.s)" } ?? "-")"
                        }
                        out.append(line)
                    }
                }
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    /// The Listen page's own path (SuggestState.reroll): Simple and Full, the dial at 0 (no dice), with the songs
    /// played before taken from the recogniser's history.
    @MainActor static func screenText() -> String {
        let lib = Library.shared
        var out: [String] = []
        let rec = Recognizer()
        let sug = SuggestState()
        let before = sug.shuffle
        defer { sug.shuffle = before }
        sug.shuffle = 0
        for t in lib.data.tracks {
            rec.setManual(t.id)
            for mode in [SuggestMode.simple, .full] {
                sug.mode = mode
                sug.reroll(rec)
                out.append("screen cur=\(t.id) mode=\(mode.rawValue) history=\(rec.history.joined(separator: ",")) shortlist=\(sug.shortlistSize)"
                           + " options=\(sug.options.map(\.id).joined(separator: ",")) rest=\(sug.rest.count) restShortlist=\(sug.restShortlist)")
            }
        }
        rec.forgetSongs()
        return out.joined(separator: "\n") + "\n"
    }

    @MainActor func check(_ crate: URL, _ name: String) throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("booth-picks-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work); Library.shared.close() }
        _ = try Library.shared.open(crateFile: crate, into: work)
        let made = Self.text() + Self.screenText()
        let file = Self.fixtures.appendingPathComponent("picks-golden-\(name).txt")
        if let kept = try? String(contentsOf: file, encoding: .utf8) {
            let a = kept.split(separator: "\n", omittingEmptySubsequences: false), b = made.split(separator: "\n", omittingEmptySubsequences: false)
            let first = (0..<max(a.count, b.count)).first { i in (i < a.count ? a[i] : "") != (i < b.count ? b[i] : "") }
            #expect(first == nil, "picks-golden-\(name).txt line \((first ?? 0) + 1): kept \(first.map { $0 < a.count ? String(a[$0]) : "<none>" } ?? "") made \(first.map { $0 < b.count ? String(b[$0]) : "<none>" } ?? "")")
        } else {
            try made.write(to: file, atomically: true, encoding: .utf8)
        }
    }

    @MainActor @Test func theDemoCratesPicksAreAsRecorded() throws {
        try check(Self.repo.appendingPathComponent("deck-app/Deck/Demo/Demo.deckie"), "demo")
    }

    @MainActor @Test func theFixtureCratesPicksAreAsRecorded() throws {
        try check(Self.fixtures.appendingPathComponent("booth-fixture.deckie"), "fixture")
    }
}
