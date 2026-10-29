import Foundation
import Testing
import DeckieAudio
import DeckieCore
import DeckieTestSupport

/// Fixtures/key.json, written by Tools/make_key_fixtures.py: the lab's key decisions (mixer/key_light.py's functions,
/// copied and checked against the lab's source) on made-up chroma.
struct KeyFixture: Decodable {
    /// best_key's (pc, mode, r, margin)
    struct Best: Decodable {
        var pc: Int, mode: String, r: Double, margin: Double
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            pc = try c.decode(Int.self); mode = try c.decode(String.self)
            r = try c.decode(Double.self); margin = try c.decode(Double.self)
        }
    }
    /// segments' (start_s, camelot, mean_r)
    struct Segment: Decodable {
        var start: Double, key: String, meanR: Double
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            start = try c.decode(Double.self); key = try c.decode(String.self); meanR = try c.decode(Double.self)
        }
    }
    struct AltSegments: Decodable {
        var profile: String, winS: Double, hopS: Double, persist: Int, minMargin: Double
        var result: [Segment]
        enum CodingKeys: String, CodingKey {
            case profile, persist, result, winS = "win_s", hopS = "hop_s", minMargin = "min_margin"
        }
    }
    struct Window: Decodable {
        var startS: Double?, endS: Double?
        enum CodingKeys: String, CodingKey { case startS = "start_s", endS = "end_s" }
    }
    struct EndResult: Decodable {
        var empty: Bool
        var frames: [Int]?
        var key: String?, pc: Int?, mode: String?
        var r: Double?, margin: Double?, rSong: Double?, gain: Double?, gain2: Double?
        var flag: Bool?
        enum CodingKeys: String, CodingKey {
            case empty, frames, key, pc, mode, r, margin, gain, flag, rSong = "r_song", gain2 = "gain_2"
        }
    }
    struct End: Decodable { var window: Window?; var result: EndResult }
    struct Ends: Decodable {
        var ref: String
        var mixIn: End, mixOut: End
        enum CodingKeys: String, CodingKey { case ref, mixIn = "mix_in", mixOut = "mix_out" }
    }
    /// The lab's B.9 key decision on the three votes: their keys (edma, bgate, krumhansl), then the lab's key,
    /// confidence and rule.
    struct Vote: Decodable {
        var keys: [String]
        var camelot: String, confidence: Double, rule: String
    }
    /// One matrix's decisions; `seed` for the random ones, `name` and `blocks` for the hand-made ones.
    struct Case: Decodable {
        var seed: UInt64?
        var frames: Int?
        var name: String?
        var blocks: [Block]?
        var whole: [String: Best]
        var segments: [Segment]
        var segmentsAlt: AltSegments
        var ends: Ends
        var vote: Vote
        enum CodingKeys: String, CodingKey {
            case seed, frames, name, blocks, whole, segments, ends, vote, segmentsAlt = "segments_alt"
        }
    }
    /// [camelot, r, margin] of one vote on the lab's sheet.
    struct SheetVote: Decodable {
        var camelot: String, r: Double, margin: Double
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            camelot = try c.decode(String.self); r = try c.decode(Double.self); margin = try c.decode(Double.self)
        }
    }
    /// One track of mixer/key_light_stft.tsv: the three votes, the lab's key and confidence, and the lab's B.9 result.
    struct SheetRow: Decodable {
        var id: String
        var votes: [SheetVote]
        var lab: String, labConf: Double
        var camelot: String, confidence: Double, rule: String
        enum CodingKeys: String, CodingKey { case id, votes, lab, camelot, confidence, rule, labConf = "lab_conf" }
    }
    /// [key name, scale, strength] as the lab's B.9 block takes each slot.
    struct NamedVote: Decodable {
        var key: String, scale: String, r: Double
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            key = try c.decode(String.self); scale = try c.decode(String.self); r = try c.decode(Double.self)
        }
    }
    struct VoteCase: Decodable {
        var votes: [NamedVote]
        var camelot: String, confidence: Double, rule: String
    }
    /// [count, 12 values]: count identical frames.
    struct Block: Decodable {
        var count: Int, values: [Double]
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            count = try c.decode(Int.self); values = try c.decode([Double].self)
        }
    }
    var numpy: String
    var relation: [String: String]
    var wheelCost: [String: Int]
    var random: [Case]
    var hand: [Case]
    var sheet: [SheetRow]
    var voteCases: [VoteCase]
    enum CodingKeys: String, CodingKey {
        case numpy, relation, random, hand, sheet, wheelCost = "wheel_cost", voteCases = "vote_cases"
    }

    /// Every matrix with its chroma rebuilt (the random ones from their seeds, the hand-made ones from their blocks)
    /// and a label.
    var matrices: [(Case, Chromagram, String)] {
        random.map { ($0, randomChroma(seed: $0.seed!), "seed \($0.seed!)") }
            + hand.map { c in
                (c, Chromagram(frames: c.blocks!.reduce(0) { $0 + $1.count },
                               values: c.blocks!.flatMap { b in (0..<b.count).flatMap { _ in b.values } }), c.name!)
            }
    }
}

/// The script's `random_chroma`: the same draws in the same order, so the same matrix to the last bit.
func randomChroma(seed: UInt64) -> Chromagram {
    var g = SplitMix64(seed)
    let n = 1 + g.below(2600)
    let profile = KeyProfile.allCases[g.below(6)]
    let noise = 0.2 + 0.8 * g.uniform()
    let pChange = 0.004 * g.uniform()
    let pFlicker = 0.3 * g.uniform()
    var pc = g.below(12)
    var major = g.uniform() < 0.5
    var values: [Double] = []
    values.reserveCapacity(n * 12)
    for _ in 0..<n {
        if g.uniform() < pChange {
            pc = g.below(12)
            major = g.uniform() < 0.5
        }
        if g.uniform() < 0.02 {
            values += [Double](repeating: 0, count: 12)
            continue
        }
        var fpc = pc, fmaj = major
        if g.uniform() < pFlicker {
            fpc = (pc + [5, 7, 9, 2][g.below(4)]) % 12
            fmaj = g.uniform() < 0.5
        }
        let w = fmaj ? profile.major : profile.minor
        var col: [Double] = []
        for c in 0..<12 {
            let x = w[Py.mod(c - fpc, 12)] + noise * (g.uniform() - 0.5)
            col.append(x > 0.0 ? x : 0.0)
        }
        let mx = col.max()!
        values += mx > 0.0 ? col.map { $0 / mx } : col
    }
    return Chromagram(frames: n, values: values)
}

@Suite struct KeyDecisionTests {
    static let fx = try! RepoPaths.fixture("key.json", as: KeyFixture.self)

    @Test func relationAndWheelCostMatchTheLab() {
        let fx = Self.fx
        #expect(fx.relation.count == 576 && fx.wheelCost.count == 576)
        for (pair, want) in fx.relation {
            let ab = pair.split(separator: ">").map(String.init)
            #expect(Camelot.relation(ab[0], ab[1]).rawValue == want, "\(pair)")
            #expect(Camelot.wheelCost(ab[0], ab[1]) == fx.wheelCost[pair], "\(pair)")
        }
    }

    /// (a) The decisions on 50 random matrices and 18 made by hand: the whole-track key by all six profiles, the
    /// segments (lab settings and others), and both mix windows. Keys exactly, numbers within 1e-9.
    @Test func decisionsMatchTheLab() {
        var worst = 0.0, numbers = 0, identical = 0, keys = 0, segments = 0, windows = 0
        func check(_ got: Double, _ want: Double, _ what: @autoclosure () -> String) {
            numbers += 1
            if got == want { identical += 1 }
            worst = max(worst, abs(got - want))
            #expect(near(got, want, 1e-9), "\(what()): \(got), lab \(want)")
        }
        let cases = Self.fx.matrices
        for (c, chroma, label) in cases {
            if let n = c.frames { #expect(chroma.frames == n, "\(label): \(chroma.frames) frames, lab \(n)") }
            // whole-track key, every profile
            let mean = KeyEstimator.meanChroma(chroma, frames: 0..<chroma.frames)
            for (name, want) in c.whole {
                let got = KeyEstimator.bestKey(mean, profile: KeyProfile(rawValue: name)!)
                keys += 1
                #expect(got.pitchClass == want.pc && got.mode == want.mode, "\(label) \(name): \(got.camelot), lab \(want.pc) \(want.mode)")
                check(got.r, want.r, "\(label) \(name) r")
                check(got.margin, want.margin, "\(label) \(name) margin")
            }
            // segments
            func compare(_ got: [KeySegment], _ want: [KeyFixture.Segment], _ what: String) {
                segments += want.count
                #expect(got.count == want.count, "\(label) \(what): \(got.count) segments, lab \(want.count)")
                for (g, w) in zip(got, want) {
                    #expect(g.camelot == w.key, "\(label) \(what): \(g.camelot), lab \(w.key)")
                    check(g.start, w.start, "\(label) \(what) start")
                    check(g.meanR, w.meanR, "\(label) \(what) mean r")
                }
            }
            compare(KeyEstimator.segments(chroma), c.segments, "segments")
            let alt = c.segmentsAlt
            compare(KeyEstimator.segments(chroma, profile: KeyProfile(rawValue: alt.profile)!, windowSeconds: alt.winS,
                                          hopSeconds: alt.hopS, persist: alt.persist, minMargin: alt.minMargin),
                    alt.result, "segments \(alt.winS)/\(alt.hopS)/\(alt.persist)/\(alt.minMargin) \(alt.profile)")
            // mix windows, judged against the song key
            for (side, end) in [(MixEnd.mixIn, c.ends.mixIn), (.mixOut, c.ends.mixOut)] {
                windows += 1
                let got = KeyEstimator.windowKey(chroma, start: end.window?.startS ?? 0, end: end.window?.endS ?? 0,
                                                 side: side, songKey: c.ends.ref)
                let want = end.result
                guard let got, !want.empty else {
                    #expect(got == nil && want.empty, "\(label) \(side): empty window")
                    continue
                }
                #expect(got.frames == want.frames![0]..<want.frames![1], "\(label) \(side) frames")
                #expect(got.camelot == want.key! && got.estimate.pitchClass == want.pc! && got.estimate.mode == want.mode!,
                        "\(label) \(side): \(got.camelot), lab \(want.key!)")
                #expect(got.flag == want.flag!, "\(label) \(side) flag")
                check(got.estimate.r, want.r!, "\(label) \(side) r")
                check(got.estimate.margin, want.margin!, "\(label) \(side) margin")
                check(got.songKeyR, want.rSong!, "\(label) \(side) song key r")
                check(got.gain, want.gain!, "\(label) \(side) gain")
                #expect(Py.round(got.gain, 2) == want.gain2!, "\(label) \(side) gain rounded")
            }
        }
        print("key decisions against the lab's functions (numpy \(Self.fx.numpy)): \(cases.count) matrices, \(keys) "
              + "whole-track keys, \(segments) segments, \(windows) mix windows; \(identical) of \(numbers) numbers "
              + "identical, largest difference \(worst)")
    }
}

@Suite struct KeyVoteTests {
    static var fx: KeyFixture { KeyDecisionTests.fx }

    static func vote(_ slot: Int, _ camelot: String, r: Double, margin: Double = 0.1) -> KeyVote.Vote {
        let t = Camelot.tonic(camelot)!
        return KeyVote.Vote(name: KeyVote.slots[slot].name, profile: KeyVote.slots[slot].profile,
                            estimate: KeyEstimate(pitchClass: t.pitchClass, mode: t.major ? "major" : "minor", r: r,
                                                  margin: margin))
    }

    /// The vote on the 68 matrices: the three votes' keys, and the lab's decision, confidence and rule word for word,
    /// the rule run from mixer/analyze.py's own source by the fixture script.
    @Test func matricesMatchTheLab() {
        var split = 0
        for (c, chroma, label) in Self.fx.matrices {
            let v = KeyVote.whole(chroma)
            #expect(v.votes.map(\.camelot) == c.vote.keys, "\(label): votes \(v.votes.map(\.camelot)), lab \(c.vote.keys)")
            #expect(v.camelot == c.vote.camelot && v.confidence == c.vote.confidence && v.rule == c.vote.rule,
                    "\(label): \(v.camelot) \(v.confidence) \(v.rule); lab \(c.vote.camelot) \(c.vote.confidence) \(c.vote.rule)")
            // The edma vote is the whole-track key the estimator gives.
            #expect(v.votes[0].estimate == KeyEstimator.estimate(chroma).whole, "\(label)")
            if Set(v.votes.map(\.camelot)).count > 1 { split += 1 }
        }
        print("key vote on \(Self.fx.matrices.count) matrices: identical to the lab's B.9 rule; the votes split on \(split)")
    }

    /// Made-up votes through every branch of the rule: agreement, a neighbour or relative dissenting, an incompatible
    /// one, the strength either side of 0.6 (0.6 itself counts as strong), which slot's strength is read, no agreement.
    @Test func madeUpVotesMatchTheLab() {
        for (n, c) in Self.fx.voteCases.enumerated() {
            let votes = c.votes.enumerated().map { i, v in
                Self.vote(i, Camelot.code(key: v.key, scale: v.scale)!, r: v.r)
            }
            let got = KeyVote.decide(votes)
            #expect(got.camelot == c.camelot && got.confidence == c.confidence && got.rule == c.rule,
                    "case \(n): \(got.camelot) \(got.confidence) \(got.rule); lab \(c.camelot) \(c.confidence) \(c.rule)")
        }
    }

    /// The lab's own run of the three profiles over its 373 tracks (mixer/key_light_stft.tsv, the real audio): the
    /// vote equals the lab's rule on every track, and scores what core/Tools/key_vote_eval.py says it scores against
    /// the lab's confident keys: 237 of 311 exact, 280 exact or a Camelot neighbour, 7 tracks changed from the edma key.
    @Test func theLabSheet() {
        let rows = Self.fx.sheet
        #expect(rows.count == 373)
        var exact = 0, near = 0, confident = 0, changed = 0, engineExact = 0
        var levels: [Double: Int] = [:]
        for row in rows {
            let v = KeyVote.decide(row.votes.enumerated().map { i, x in Self.vote(i, x.camelot, r: x.r, margin: x.margin) })
            #expect(v.camelot == row.camelot && v.confidence == row.confidence && v.rule == row.rule,
                    "\(row.id): \(v.camelot) \(v.confidence) \(v.rule); lab \(row.camelot) \(row.confidence) \(row.rule)")
            levels[v.confidence, default: 0] += 1
            if v.camelot != row.votes[0].camelot { changed += 1 }
            guard row.labConf >= 0.65 else { continue }
            confident += 1
            if v.camelot == row.lab { exact += 1 }
            if row.votes[0].camelot == row.lab { engineExact += 1 }
            if [.exact, .relative, .neighbour].contains(Camelot.relation(v.camelot, row.lab)) { near += 1 }
        }
        print("key vote on the lab's sheet: exact \(exact) of \(confident) confident tracks (edma alone \(engineExact)), "
              + "exact or neighbour \(near), \(changed) of \(rows.count) keys changed; confidence levels "
              + levels.sorted { $0.key > $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: ", "))
        #expect(confident == 311 && exact == 237 && engineExact == 232 && near == 280 && changed == 7)
        #expect(levels == [1.0: 217, 0.65: 25, 0.6: 43, 0.45: 36, 0.3: 52])
    }

    /// The rule's parts on constructed votes: what is decided, from which vote it is spelled, how many agree, whose
    /// strength is read.
    @Test func constructedVotes() {
        // All three agree on A minor: 1.0, spelled from the edma vote.
        let all = KeyVote.decide([Self.vote(0, "8A", r: 0.7), Self.vote(1, "8A", r: 0.9), Self.vote(2, "8A", r: 0.4)])
        #expect(all.camelot == "8A" && all.agreeing == 3 && all.strength == 0.7 && all.confidence == 1.0)
        #expect(all.decided.key == "A" && all.decided.mode == "minor")
        // bgate and krumhansl outvote edma: their key, bgate's strength, spelled from bgate's vote; edma's 8B is the
        // relative, so a neighbour.
        let outvoted = KeyVote.decide([Self.vote(0, "8B", r: 0.9), Self.vote(1, "8A", r: 0.55), Self.vote(2, "8A", r: 0.8)])
        #expect(outvoted.camelot == "8A" && outvoted.agreeing == 2 && outvoted.strength == 0.55)
        #expect(outvoted.confidence == 0.3 && outvoted.rule == "2 of 3 agree, dissenter is a Camelot neighbour; strength < 0.6")
        #expect(outvoted.decided == outvoted.votes[1].estimate)
        // edma and krumhansl agree against a far bgate: edma's strength, 0.45.
        let far = KeyVote.decide([Self.vote(0, "3B", r: 0.65), Self.vote(1, "9B", r: 0.95), Self.vote(2, "3B", r: 0.2)])
        #expect(far.camelot == "3B" && far.strength == 0.65 && far.confidence == 0.45)
        // No two agree: edma's key whatever the others' correlations, 0.3; strength edma's.
        let none = KeyVote.decide([Self.vote(0, "1A", r: 0.3), Self.vote(1, "5B", r: 0.99), Self.vote(2, "7A", r: 0.99)])
        #expect(none.camelot == "1A" && none.agreeing == 1 && none.strength == 0.3 && none.confidence == 0.3)
        #expect(none.rule == "no two detectors agree")
        // A flat chroma: every profile gives (C, major, 0, 0), so all three agree with strength 0: 0.6.
        let flat = KeyVote.whole(Chromagram(frames: 4, values: [Double](repeating: 0.5, count: 48)))
        #expect(flat.camelot == "8B" && flat.agreeing == 3 && flat.confidence == 0.6)
    }

    /// On synthesised chord progressions the three votes agree on the key: C major, A minor, F sharp major.
    @Test func progressionsGiveOneKey() throws {
        for (chords, want) in [(Progression.cMajor, "8B"), (Progression.aMinor, "8A"), (Progression.fSharpMajor, "2B")] {
            let y = Progression.render(chords, seconds: 32).map { Float($0) }
            let v = KeyVote.whole(try KeyEstimator.chroma(y, sampleRate: 22050))
            print("progression in \(want): votes " + v.votes.map { "\($0.profile.rawValue) \($0.camelot)" }.joined(separator: ", ")
                  + "; \(v.camelot), \(v.confidence) (\(v.rule))")
            #expect(v.camelot == want && v.agreeing == 3, "\(want): \(v.votes.map(\.camelot))")
        }
    }
}

@Suite struct ChromaParityTests {
    /// (b) librosa.feature.chroma_stft as key_light.py calls it, on seven synthesised signals: the float32 signal as
    /// the lab feeds it (librosa's arithmetic is then partly single precision) within 1e-6; the float64 signal (the same
    /// algorithm in double precision throughout) far closer.
    @Test func matchesLibrosa() {
        let fx = DSPFixture.shared
        var worst32 = 0.0, worst64 = 0.0, values = 0
        for s in fx.chroma {
            let y = ChordSynth.render(rate: 22050, samples: s.samples, chords: s.chords.map(\.chord),
                                      harmonics: s.harmonics, noise: s.noise, seed: s.seed)
            let c32 = Chroma.stft(y.map { Float($0) }), c64 = Chroma.stft(y)
            #expect(c32.frames == s.frames && c64.frames == s.frames, "\(s.name): \(c32.frames) frames, librosa \(s.frames)")
            var e32 = 0.0, e64 = 0.0
            for (t, want) in zip(s.float32.index, s.float32.values) {
                for pc in 0..<12 { e32 = max(e32, abs(c32[t, pc] - want[pc])) }
            }
            for (t, want) in zip(s.float64.index, s.float64.values) {
                for pc in 0..<12 { e64 = max(e64, abs(c64[t, pc] - want[pc])) }
            }
            values += s.float32.index.count * 12
            print("chroma \(s.name): \(s.frames) frames; largest difference from librosa \(e32) (float32 signal), "
                  + "\(e64) (float64 signal)")
            #expect(e32 <= 1e-6, "\(s.name): float32 path differs by \(e32)")
            #expect(e64 <= 1e-12, "\(s.name): float64 path differs by \(e64)")
            worst32 = max(worst32, e32)
            worst64 = max(worst64, e64)
        }
        print("chroma against librosa \(fx.versions["librosa"] ?? "?"), \(values) values per path: largest difference "
              + "\(worst32) for the lab's float32 input, \(worst64) for float64 input")
    }

    /// Plain checks that need no librosa: a 440 Hz sine puts nearly everything in A (its neighbours get the filter
    /// bank's Gaussian skirt, exp(-2) of A's weight at one semitone); a C major triad lights C, E and G above every
    /// other class; digital silence stays zero.
    @Test func pitchClassesOfToneAndChord() {
        let rate = 22050, n = 5 * rate
        let tone = (0..<n).map { Float(0.5 * sin(2 * Double.pi * 440 * Double($0) / Double(rate))) }
        let a = KeyEstimator.meanChroma(Chroma.stft(tone), frames: 10..<50)
        print("440 Hz: chroma " + a.map { Py.fixed($0, 3) }.joined(separator: " "))
        #expect(a[9] == 1 && a[8] < 0.2 && a[10] < 0.2)
        #expect((0..<12).filter { ![8, 9, 10].contains($0) }.allSatisfy { a[$0] < 0.01 })
        let y = ChordSynth.render(rate: rate, samples: n, chords: [(n / 2, n, ChordSynth.C)], harmonics: 6, noise: 0,
                                  seed: 1, exact: false)
        let c = Chroma.stft(y.map { Float($0) })
        #expect(c.frame(0) == [Double](repeating: 0, count: 12))
        let mean = KeyEstimator.meanChroma(c, frames: 40..<50)
        let top3 = (0..<12).sorted { mean[$0] > mean[$1] }.prefix(3).sorted()
        print("C major triad with bass: chroma " + mean.map { Py.fixed($0, 2) }.joined(separator: " "))
        #expect(top3 == [0, 4, 7])
    }
}

/// Synthesised music, rendered in the test: I-IV-V-I progressions, two seconds a chord, triads with the root an
/// octave and a half below, six harmonics, light noise.
enum Progression {
    static func render(_ chords: [[Double]], seconds: Double, rate: Int = 22050, from start: Double = 0,
                       harmonics: Int = 6) -> [Double] {
        let n = Int(seconds * Double(rate))
        return ChordSynth.render(rate: rate, samples: n,
                                 chords: ChordSynth.progression(rate: rate, samples: n, chordSeconds: 2.0, chords),
                                 harmonics: harmonics, noise: 0.01, seed: 9, exact: false)
    }

    static let cMajor = [ChordSynth.C, ChordSynth.F, ChordSynth.G, ChordSynth.C]
    static let aMinor = [ChordSynth.Am, ChordSynth.Dm, ChordSynth.E, ChordSynth.Am]  // i-iv-V-i, the V major
    static let fSharpMajor = [ChordSynth.Fs, ChordSynth.B, ChordSynth.Cs, ChordSynth.Fs]
    static let dMajor = [ChordSynth.D, ChordSynth.G, ChordSynth.A, ChordSynth.D]
}

@Suite struct KeyEndToEndTests {
    /// (c) Whole-track keys of I-IV-V-I in C major, A minor (i-iv-V-i) and F# major.
    @Test func progressionsGiveTheirKeys() throws {
        for (name, chords, want) in [("C major", Progression.cMajor, "8B"), ("A minor", Progression.aMinor, "8A"),
                                     ("F# major", Progression.fSharpMajor, "2B")] {
            let y = Progression.render(chords, seconds: 32).map { Float($0) }
            let result = KeyEstimator.estimate(try KeyEstimator.chroma(y, sampleRate: 22050))
            print("\(name): whole \(result.whole.camelot) (\(result.whole.key) \(result.whole.mode)) r "
                  + "\(Py.fixed(result.whole.r, 3)) margin \(Py.fixed(result.whole.margin, 3)); segments "
                  + result.segments.map { "\($0.start) s \($0.camelot)" }.joined(separator: ", "))
            #expect(result.whole.camelot == want, "\(name): \(result.whole.camelot)")
            #expect(result.segments.map(\.camelot) == [want])
        }
    }

    /// (c) 60 s that modulate from C major to D major at 30 s: two segments, 8B then 10B. The lab's segment start is
    /// the start of the first 20 s window of the run that opened it, so it lands about half a window before the
    /// change: the window that opened it, centred 10 s later, sits on the change.
    @Test func modulationGivesTwoSegments() throws {
        let rate = 22050, n = 60 * rate, half = n / 2
        let chords = ChordSynth.progression(rate: rate, samples: half, chordSeconds: 2.0, Progression.cMajor)
            + ChordSynth.progression(rate: rate, samples: n - half, chordSeconds: 2.0, Progression.dMajor, offset: half)
        let y = ChordSynth.render(rate: rate, samples: n, chords: chords, harmonics: 6, noise: 0.01, seed: 9, exact: false)
        let result = KeyEstimator.estimate(try KeyEstimator.chroma(y.map { Float($0) }, sampleRate: rate))
        let segs = result.segments
        print("C to D at 30 s: segments " + segs.map { "\($0.start) s \($0.camelot) (r \($0.meanR))" }.joined(separator: ", ")
              + "; whole \(result.whole.camelot) margin \(Py.fixed(result.whole.margin, 3))")
        try #require(segs.count == 2)
        #expect(segs[0].camelot == "8B" && segs[0].start == 0 && segs[1].camelot == "10B")
        let start = segs[1].start, centre = start + 20.0 / 2
        print("boundary: segment start \(start) s (\(Py.fixed(30 - start, 1)) s before the change); its first window "
              + "is centred at \(Py.fixed(centre, 1)) s (\(Py.fixed(abs(centre - 30), 1)) s from the change)")
        #expect(start < 30 && 30 - start <= 10 + 5)  // half a window plus one hop at most
        #expect(abs(centre - 30) <= 10)
    }

    /// (c) A steady key: both mix windows, given or left to the lab's fallback, read the song key, unflagged; a song
    /// key given from outside (Apple's, in the product) is the one they are judged against.
    @Test func mixWindowsOfASteadyKeyReturnTheSongKey() throws {
        let y = Progression.render(Progression.cMajor, seconds: 90).map { Float($0) }
        let chroma = try KeyEstimator.chroma(y, sampleRate: 22050)
        let given = KeyEstimator.estimate(chroma, mixIn: (0, 30), mixOut: (60, 90))
        let fallback = KeyEstimator.estimate(chroma)
        let apple = KeyEstimator.estimate(chroma, mixIn: (0, 30), mixOut: (60, 90), songKey: "8B")
        for (label, r) in [("windows given", given), ("fallback windows", fallback), ("song key given", apple)] {
            print("steady C major, \(label): song key \(r.songKey); mix-in \(r.mixIn?.camelot ?? "-") gain "
                  + "\(Py.fixed(r.mixIn?.gain ?? .nan, 3)); mix-out \(r.mixOut?.camelot ?? "-") gain "
                  + "\(Py.fixed(r.mixOut?.gain ?? .nan, 3))")
            #expect(r.songKey == "8B" && r.mixIn?.camelot == "8B" && r.mixOut?.camelot == "8B", "\(label)")
            #expect(r.mixIn?.flag == false && r.mixOut?.flag == false, "\(label)")
        }
        #expect(given.mixIn?.frames == 0..<322 && given.mixOut?.frames == 645..<968)  // int(90 * 10.7666...) = 968
        #expect(fallback.mixOut?.frames == (chroma.frames - 322)..<chroma.frames)
        // A song key far from the music: the windows keep their own key and are flagged.
        let far = KeyEstimator.estimate(chroma, mixIn: (0, 30), mixOut: (60, 90), songKey: "2B")
        #expect(far.mixIn?.camelot == "8B" && far.mixIn?.flag == true && far.mixOut?.flag == true)
    }

    /// The input contract: 44.1 kHz is halved first (the decimator), 22.05 kHz is read as it is, any other rate
    /// asks for resampling first. Stereo is averaged to mono.
    @Test func sampleRates() throws {
        let y44 = Progression.render(Progression.cMajor, seconds: 24, rate: 44100).map { Float($0) }
        let stereo = AudioBuffer(sampleRate: 44100, channelCount: 2, samples: y44.flatMap { [$0, $0] })
        let result = try KeyEstimator.estimate(stereo)
        #expect(result.whole.camelot == "8B")
        let direct = try KeyEstimator.chroma(y44, sampleRate: 44100)
        #expect(direct.frames == 1 + ((y44.count + 1) / 2) / 2048)
        #expect(throws: KeyEstimatorError.resampleFirst(sampleRate: 48000)) {
            try KeyEstimator.chroma([Float](repeating: 0, count: 48000), sampleRate: 48000)
        }
    }
}

@Suite struct KeySpeedTests {
    /// (d) Four minutes of mono at 22,050 Hz through chroma and key (whole track, both mix windows, segments) in under
    /// 3 s in a debug build.
    @Test func fourMinutesInUnderThreeSeconds() throws {
        let y = Progression.render(Progression.cMajor, seconds: 240, harmonics: 4).map { Float($0) }
        let clock = ContinuousClock()
        var chroma: Chromagram? = nil, result: KeyResult? = nil
        let chromaTime = seconds(clock.measure { chroma = try? KeyEstimator.chroma(y, sampleRate: 22050) })
        let keyTime = seconds(clock.measure { result = KeyEstimator.estimate(chroma!, mixIn: (0, 30), mixOut: (200, 230)) })
        print("4 min mono at 22.05 kHz: chroma \(Py.fixed(chromaTime, 3)) s (\(chroma!.frames) frames), key "
              + "\(Py.fixed(keyTime, 3)) s (\(result!.segments.count) segment(s), whole \(result!.whole.camelot)); "
              + "\(Py.fixed(chromaTime + keyTime, 3)) s in all")
        #expect(result!.whole.camelot == "8B")
        // A loose ceiling: the times are printed above (under 1 s here); a tight limit flakes under load.
        #expect(chromaTime + keyTime < 30.0)
    }
}
