import Foundation
import Testing
import DeckieBooth
import DeckieCrate
@testable import DeckieRecognition

/// The shared switching rule, driven as the iPad app drives it (Recognizer.swift after the move): the same lines as the
/// present rule's record, step for step.
final class SharedDriver: RuleUnderTest {
    let lib: BoothLibrary
    var rule = BoothRule()
    var source: BoothRule.Source = .listening
    var level: Float = -20
    var startedAt = ruleEpoch
    var status = ""
    var notes: [String] = []
    var newSong = false
    var clock = ruleEpoch
    init(_ lib: BoothLibrary) { self.lib = lib }

    /// The app's one-line name of a song (Model.swift, `Track.oneLine`).
    func oneLine(_ id: String) -> String? {
        guard let s = lib.song(id) else { return nil }
        if s.named ?? true { return s.song }
        let placeText = s.disc.map { d in d + (s.folder.isEmpty ? "" : " / " + s.folder) + (s.num.map { String(format: " / %02d", $0) } ?? "") } ?? s.folder
        return placeText.isEmpty ? "No name yet" : placeText + " · " + "no name yet"
    }

    func take(_ r: BoothReading) {
        let o = rule.take(r, in: lib, now: clock, source: source, level: level, startedAt: startedAt)
        notes += rule.takeNotes()
        switch o {
        case .nothing: if rule.currentId == nil { status = "listening…" }
        case .kept: break
        case let .shown(n): newSong = n; status = source == .listening ? "listening · matched" : "test file · matched"
        }
    }

    func apply(_ step: RuleStep) {
        newSong = false
        switch step {
        case let .deckie(t, r):
            clock = at(t + r.milliseconds / 1000)
            guard let reading = BoothReading(deckie: r, heard: at(t)) else { return }
            if r.state == .named, let id = r.id {
                notes.append(String(format: "Deckie named %@ at %.1fs, speed %+.2f%%, key lock %@, confidence %.1f (%.0f ms), heard %.1fs", lib.song(id)?.title ?? id,
                                    r.positionSeconds ?? 0, r.speedPercent ?? 0, r.keyLock.map { $0 ? "on" : "off" } ?? "?", r.confidence, r.milliseconds, r.time))
            }
            take(reading)
        case let .reading(t, p):
            clock = at(t + (p.milliseconds ?? 0) / 1000)
            take(BoothReading(from: p.from == .deckie ? .deckie : .apple, date: p.date, audioTime: p.audioTime, id: p.id, position: p.position,
                              speedPercent: p.speedPercent, keyLock: p.keyLock, pitchRatio: p.pitchRatio, speedHint: p.speedHint,
                              speedFrom: p.speedFrom, confidence: p.confidence, vouched: p.vouched, fresh: p.fresh,
                              milliseconds: p.milliseconds, wait: p.wait,
                              incoming: p.incoming.map { .init(id: $0.id, position: $0.position, speedPercent: $0.speedPercent, keyLock: $0.keyLock, confidence: $0.confidence) }))
        case let .tick(t):
            clock = at(t)
            if rule.tick(now: clock, source: source, deckie: true, level: level) { status = "listening…" }
            notes += rule.takeNotes()
        case let .level(l): level = l
        case let .manual(t, id):
            clock = at(t); rule.setManual(id, in: lib, now: clock); source = .manual; status = "set by hand"
            notes += rule.takeNotes()
        case .forget: rule.forget(); source = .listening
        case let .listen(t):
            clock = at(t); source = .listening; startedAt = at(t); status = "listening…"
        }
    }

    func line(at t: Double) -> String {
        let r = rule
        let n = notes; notes = []
        let place = r.currentPlace.map { "\($0.disc ?? "-")/\($0.folder)/\($0.num.map { "\($0)" } ?? "-")" } ?? "-"
        let inc = r.incoming.map { "\($0.id)@\($0.position.map { "\($0)" } ?? "-")" } ?? "-"
        let also = r.alsoHearingId.flatMap(oneLine)
        return "cur=\(r.currentId ?? "-") place=\(place) known=\(r.positionKnown) anchor=\(r.anchorOffset)@\(r.anchorDate.timeIntervalSince(ruleEpoch))"
            + " rate=\(r.rate) pitch=\(r.pitchPct) kind=\(r.pitchKind.rawValue) from=\(r.pitchFrom) notHeard=\(r.notHeard) paused=\(r.paused)"
            + " also=\(also ?? "-") incoming=\(inc) history=\(r.history.joined(separator: ","))"
            + " first=\(r.firstMatchSeconds.map { "\($0)" } ?? "-") conf=\(r.confidence(now: clock, source: source)) pos=\(r.position(at: DeckieBoothTests.at(t)))"
            + " matches=\(r.matchCount) none=\(r.noMatchCount) new=\(newSong) status=\(status)"
            + (n.isEmpty ? "" : " notes=[\(n.joined(separator: " ; "))]")
    }
}

/// The shared rule gives the present rule's record, line for line, and the present rule's output on further generated
/// sets that are not in the record.
@Suite struct SharedRuleTests {
    @Test func theSharedRuleGivesTheRecord() throws {
        let lib = BoothLibrary(FixtureCrate.crate)
        let made = RuleGoldenTests.text { SharedDriver(lib) }
        if Golden.recording { return }     // the record is the present rule's alone
        if let diff = try Golden.check("rule-golden", made) { Issue.record(Comment(rawValue: diff)) }
    }

    @Test func theSharedRuleAgreesWithThePresentOneOnMoreSets() {
        let shared = BoothLibrary(FixtureCrate.crate), present = PresentLibrary(FixtureCrate.crate)
        for seed in UInt64(100)..<UInt64(140) {
            let steps = RuleScripts.generated(seed, seconds: 400)
            let a = runScript(PresentDriver(present), "seed \(seed)", steps), b = runScript(SharedDriver(shared), "seed \(seed)", steps)
            if a != b {
                let x = a.split(separator: "\n"), y = b.split(separator: "\n")
                let i = (0..<min(x.count, y.count)).first { x[$0] != y[$0] } ?? min(x.count, y.count)
                Issue.record("seed \(seed) line \(i): present \(i < x.count ? String(x[i]) : "-") shared \(i < y.count ? String(y[i]) : "-")")
                return
            }
        }
    }
}

/// The shared picks give the iPad app's record (made in the simulator by deck-app/DeckTests/PicksGoldenTests.swift),
/// line for line, for the demo crate and the fixture crate.
@Suite struct SharedPicksTests {
    static func d(_ x: Double?) -> String { x.map { "\($0)" } ?? "-" }

    static func pairText(_ p: BoothPair?) -> String {
        guard let p else { return "pair=-" }
        return "pair=\(p.b) s=\(p.s) st=\(p.st) m=\(p.m) pitch=\(d(p.pitch)) tr=\(p.tr) trl=\(p.trl) ka=\(p.ka) kb=\(p.kb)"
            + " mv=\((p.mv ?? []).joined(separator: "/")) ks=\(p.ks.map { "\($0)" } ?? "-") kh=\(p.kh.map { "\($0)" } ?? "-")"
            + " reasons=\(p.reasons.joined(separator: " | "))"
    }

    static func joinText(_ cur: BoothSong, _ t: BoothSong, _ p: BoothPair?, _ deckA: Double) -> String {
        let ji = BoothJoin(cur, t, p, deckAPitch: deckA)
        return "join(\(deckA))=bm:\(ji.beatMatch) pitch:\(d(ji.pitch)) pt:\(ji.pitchText) keys:\(ji.keyText) v:\(ji.verdict)"
            + " vk:\(ji.verdictKind) sB:\(ji.scaleB) bpmLine:\(BoothJoin.bpmLine(t, p, ji)) moveLine:\(BoothJoin.moveLine(p, ji))"
    }

    static func text(_ lib: BoothLibrary) -> String {
        let picks = BoothPicks(lib)
        var out: [String] = ["songs \(lib.songCount) discs \(lib.discs.map(\.disc).joined(separator: ","))"]
        let discs = lib.discs.map(\.disc)
        var filters: [(String, BoothFilter)] = [("all discs", BoothFilter())]
        if let first = discs.first {
            var f = BoothFilter(); f.set(first, on: false); filters.append(("\(first) off", f))
            var g = f; g.other = true; filters.append(("\(first) off, all on", g))
        }
        var o = BoothFilter(); o.other = true; filters.append(("all on", o))
        let ids = lib.songs.map(\.id)
        var seed: UInt64 = 1
        for id in ids {
            guard let t = lib.song(id) else { continue }
            for place in t.places {
                let cur = t.at(place)
                let others = ids.filter { $0 != id }
                let history = Array(others.prefix(3))
                let pins: [String?] = [nil, others.last, others.first { o in !lib.picks(from: id).contains { $0.b == o } }]
                var runs: [(String, BoothFilter, [String], String?, Double)] = []
                for (fname, filter) in filters { for shuffle in [0.0, 0.5, 1.0] { runs.append((fname, filter, [], nil, shuffle)) } }
                for pinned in pins { runs.append((filters[0].0, filters[0].1, history, pinned, 0.5)) }
                for (fname, filter, exclude, pinned, shuffle) in runs {
                    var rng = SeededRNG(seed: seed); seed += 1
                    let (list, short) = picks.ranked(cur: cur, target: filter, exclude: Set(exclude), pinned: pinned, shuffle: shuffle, rng: &rng)
                    out.append("cur=\(id)@\(place.disc ?? "-")/\(place.folder)/\(place.num.map { "\($0)" } ?? "-") filter=\(fname)"
                               + " label=\(filter.label(lib.discs)) exclude=\(exclude.joined(separator: ",")) pinned=\(pinned ?? "-")"
                               + " shuffle=\(shuffle) seed=\(seed - 1) shortlist=\(short) rows=\(list.count)")
                    let full = shuffle == 0 && exclude.isEmpty
                    for (i, op) in list.enumerated() {
                        guard let target = lib.placed(op.id, playingDisc: cur.disc, among: picks.allowsPlace(filter)) else {
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

    /// The Listen page's path: each song set by hand in turn, the songs played before from the rule's history, Simple
    /// and Full with the dial at 0.
    static func screenText(_ lib: BoothLibrary) -> String {
        var out: [String] = []
        var rule = BoothRule()
        let picks = BoothPicks(lib)
        for t in lib.songs {
            rule.setManual(t.id, in: lib, now: ruleEpoch)
            guard let cur = rule.current(in: lib) else { continue }
            var rng = SeededRNG(seed: 0)
            let (list, short) = picks.ranked(cur: cur, target: BoothFilter(), exclude: Set(rule.history.suffix(12)), pinned: nil, shuffle: 0, rng: &rng)
            for (mode, full) in [("SIMPLE", false), ("FULL", true)] {
                let s = BoothPicks.split(list, shortlist: short, full: full)
                out.append("screen cur=\(t.id) mode=\(mode) history=\(rule.history.joined(separator: ",")) shortlist=\(short)"
                           + " options=\(s.shown.map(\.id).joined(separator: ",")) rest=\(s.more.count) restShortlist=\(s.restShortlist)")
            }
        }
        return out.joined(separator: "\n") + "\n"
    }

    func check(_ url: URL, _ name: String) throws {
        let lib = BoothLibrary(try CrateReader.read(from: url))
        let made = Self.text(lib) + Self.screenText(lib)
        if Golden.recording { return }     // the record is the iPad app's alone
        if let diff = try Golden.check("picks-golden-\(name)", made) { Issue.record(Comment(rawValue: diff)) }
    }

    @Test func theSharedPicksGiveTheDemoCratesRecord() throws { try check(FixtureCrate.demoURL, "demo") }
    @Test func theSharedPicksGiveTheFixtureCratesRecord() throws { try check(FixtureCrate.packageURL, "fixture") }

    /// The words table holds every word the shared code says, and none says "AI" or "track".
    @Test func theWordsAreInTheTable() {
        for (k, v) in BoothWords.table {
            #expect(v.range(of: #"\bAI\b"#, options: .regularExpression) == nil, "\(k)")
            #expect(!v.lowercased().contains("track"), "\(k)")
        }
        #expect(BoothWords.moveLabels["bass_swap_16"] == "blend")
        #expect(BoothWords.signed1(3.21) == "+3.2" && BoothWords.signed1(-1) == "−1.0" && BoothWords.signed1(0.01) == "±0.0")
    }
}
