import Testing
import Foundation
import DeckieCore
import DeckieLab

/// One pair record as mixer/score.py writes it (Fixtures/pairs_sample.json).
struct SamplePair: Decodable {
    var a, b: String
    var scoreBase: Double
    var terms: [String: Double]
    var stretchPct: Double
    var multiplier: String
    var suggestedTransition: String
    var moves: [String]
    var reasons: [String]
    var vocalOverlap: Double
    var overlapBars: Int
    var keyShiftSt: Int
    var energyDeltaLu: Double
    enum CodingKeys: String, CodingKey {
        case a, b, terms, multiplier, moves, reasons
        case scoreBase = "score_base", stretchPct = "stretch_pct", suggestedTransition = "suggested_transition"
        case vocalOverlap = "vocal_overlap", overlapBars = "overlap_bars", keyShiftSt = "key_shift_st"
        case energyDeltaLu = "energy_delta_lu"
    }
}

struct PairsSummary: Decodable {
    var nTracks, nDirected, skippedSameCut, rejectedTempo, nScored, nAtLeastThreshold: Int
    var sumScoreBase: Double
    var termSums: [String: Double]
    var byTransition: [String: Int]
    var byMultiplier: [String: Int]
    enum CodingKeys: String, CodingKey {
        case nTracks = "n_tracks", nDirected = "n_directed", skippedSameCut = "skipped_same_cut"
        case rejectedTempo = "rejected_tempo", nScored = "n_scored", nAtLeastThreshold = "n_at_least_threshold"
        case sumScoreBase = "sum_score_base", termSums = "term_sums", byTransition = "by_transition"
        case byMultiplier = "by_multiplier"
    }
}

/// mixer/recs.json, the committed recommendations.
struct RecsFile: Decodable {
    struct Entry: Decodable {
        var id: String
        var title: String
        var score: Double
        var reasons: [String]
        var suggestedTransition: String
        var stretchPct: Double
        var multiplier: String
        var camelotA, camelotB: String
        enum CodingKeys: String, CodingKey {
            case id, title, score, reasons, multiplier
            case suggestedTransition = "suggested_transition", stretchPct = "stretch_pct"
            case camelotA = "camelot_a", camelotB = "camelot_b"
        }
    }
    struct Lists: Decodable { var out: [Entry]; var `in`: [Entry] }
    struct TrackRecs: Decodable {
        var title: String
        var bpm: Double
        var camelot: String
        var disc: Lists
        var pool: Lists
    }
}

/// The whole pool, loaded and scored once for every test in the suite (about 140,000 directed pairs).
final class ScoredPool: Sendable {
    let tracks: [Track]
    let pairs: [PairKey: PairScore]
    init() throws {
        tracks = try LabLoader.loadTracks(featuresDir: RepoPaths.features, candidatesFile: RepoPaths.candidates)
        pairs = PairScorer.scoreAll(tracks)
    }
    static let shared: ScoredPool = try! ScoredPool()
}

@Suite struct ScoringTests {
    // Tolerances: one unit in the lab's last rounded decimal, plus a little. The timbre term is a rank among
    // 69,378 cosine values (a step of 0.0000144), so a pair whose cosine the lab computed one bit differently can
    // move one step; that shows up as 0.001 in a term rounded to three places and 0.0001 in the score.
    static let termTol = 0.0011, scoreTol = 0.00011, twoPlaceTol = 0.011, threePlaceTol = 0.0011

    @Test func loadsThePoolLikeTheLab() throws {
        let pool = ScoredPool.shared
        let summary = try RepoPaths.fixture("pairs_summary.json", as: PairsSummary.self)
        #expect(pool.tracks.count == summary.nTracks)
        let byId = Dictionary(uniqueKeysWithValues: pool.tracks.map { ($0.id, $0) })
        let t = try #require(byId["0327cf1c94"])
        #expect(t.camelot == "12A" && t.inBars == 8 && t.outBars == 16 && t.nBars == 175)
        #expect(t.vocIn.count == 8 && t.vocOut.count == 16 && t.vocFirst16.count == 16)
        #expect(near(t.embedding.reduce(0) { $0 + $1 * $1 }, 1, 1e-9))
        #expect(t.kind == "dance original" && t.era == "pre-90s" && t.hal)
    }

    @Test func totalsOverEveryPairMatchTheLab() throws {
        let pool = ScoredPool.shared
        let s = try RepoPaths.fixture("pairs_summary.json", as: PairsSummary.self)
        #expect(pool.pairs.count == s.nScored, "scored \(pool.pairs.count), lab \(s.nScored)")
        let byId = Dictionary(uniqueKeysWithValues: pool.tracks.map { ($0.id, $0) })
        var sum = 0.0, atLeast = 0
        var byTr: [String: Int] = [:], byMult: [String: Int] = [:], termSums: [String: Double] = [:]
        for (k, p) in pool.pairs {
            sum += p.scoreBase
            if p.scoreBase + PairScorer.bonus(byId[k.b]!) >= PairScoring.pairMin { atLeast += 1 }
            byTr[p.suggestedTransition, default: 0] += 1
            byMult[p.multiplier, default: 0] += 1
            for name in ScoreTerms.names { termSums[name, default: 0] += p.terms[name] }
        }
        #expect(near(sum, s.sumScoreBase, Double(s.nScored) * Self.scoreTol), "sum \(sum) vs \(s.sumScoreBase)")
        #expect(atLeast == s.nAtLeastThreshold, "pairs at or above 0.45: \(atLeast) vs \(s.nAtLeastThreshold)")
        #expect(byTr == s.byTransition, "by transition \(byTr) vs \(s.byTransition)")
        #expect(byMult == s.byMultiplier, "by multiplier \(byMult) vs \(s.byMultiplier)")
        for (name, want) in s.termSums {
            #expect(near(termSums[name]!, want, Double(s.nScored) * Self.termTol), "sum of \(name): \(termSums[name]!) vs \(want)")
        }
        print("scored \(pool.pairs.count) directed pairs; sum of score_base \(sum) (lab \(s.sumScoreBase))")
    }

    @Test func sampledPairsMatchTheLabFieldByField() throws {
        let pool = ScoredPool.shared
        let sample = try RepoPaths.fixture("pairs_sample.json", as: [SamplePair].self)
        #expect(sample.count > 2000)
        var reasonMismatches: [String] = []
        var maxScoreDiff = 0.0, maxTermDiff = 0.0, maxTermName = "", termsOff = 0
        for want in sample {
            let p = try #require(pool.pairs[PairKey(want.a, want.b)], "missing pair \(want.a) -> \(want.b)")
            let label = "\(want.a) -> \(want.b)"
            maxScoreDiff = max(maxScoreDiff, abs(p.scoreBase - want.scoreBase))
            #expect(near(p.scoreBase, want.scoreBase, Self.scoreTol), "\(label) score \(p.scoreBase) vs \(want.scoreBase)")
            for name in ScoreTerms.names {
                let diff = abs(p.terms[name] - want.terms[name]!)
                if diff > 0 { termsOff += 1 }
                if diff > maxTermDiff { maxTermDiff = diff; maxTermName = name }
                #expect(near(p.terms[name], want.terms[name]!, Self.termTol), "\(label) \(name) \(p.terms[name]) vs \(want.terms[name]!)")
            }
            #expect(near(p.stretchPct, want.stretchPct, Self.twoPlaceTol), "\(label) stretch")
            #expect(p.multiplier == want.multiplier, "\(label) multiplier")
            #expect(p.suggestedTransition == want.suggestedTransition, "\(label) transition \(p.suggestedTransition) vs \(want.suggestedTransition)")
            #expect(p.moves == want.moves, "\(label) moves")
            #expect(near(p.vocalOverlap, want.vocalOverlap, Self.threePlaceTol), "\(label) vocal overlap")
            #expect(p.overlapBars == want.overlapBars, "\(label) overlap bars")
            #expect(p.keyShiftSt == want.keyShiftSt, "\(label) key shift")
            #expect(near(p.energyDeltaLu, want.energyDeltaLu, Self.twoPlaceTol), "\(label) energy delta")
            if p.reasons != want.reasons { reasonMismatches.append("\(label): \(p.reasons) vs lab \(want.reasons)") }
        }
        print("sampled pairs: \(sample.count); largest score difference \(maxScoreDiff); terms differing at all: \(termsOff) of \(sample.count * 8), largest \(maxTermDiff) (\(maxTermName)); reason-text mismatches \(reasonMismatches.count)")
        for m in reasonMismatches.prefix(10) { print("  " + m) }
        // The reason texts quote the timbre rank as a whole percent, so the same one-step wobble can change
        // a digit in a few pairs; anything beyond that would be a real porting error.
        #expect(reasonMismatches.count <= sample.count / 200, "\(reasonMismatches.count) reason mismatches")
    }

    @Test func topListsMatchTheCommittedRecommendations() throws {
        let pool = ScoredPool.shared
        let recs = PairScorer.recommendations(pool.tracks, pairs: pool.pairs)
        let committed = try JSONDecoder().decode([String: RecsFile.TrackRecs].self, from: Data(contentsOf: RepoPaths.recs))
        #expect(recs.count == committed.count)
        var lists = 0, idMatches = 0, idChecks = 0, tieLists = 0
        for (id, want) in committed {
            let got = try #require(recs[id], "no recommendations for \(id)")
            #expect(got["pool"]!.out.count <= 8 && got["pool"]!.in.count <= 8)
            for (view, lw) in [("disc", want.disc), ("pool", want.pool)] {
                for (dir, wantList) in [("out", lw.out), ("in", lw.in)] {
                    let gotList = dir == "out" ? got[view]!.out : got[view]!.in
                    lists += 1
                    let label = "\(id) \(view) \(dir)"
                    #expect(gotList.count == wantList.count, "\(label) count \(gotList.count) vs \(wantList.count)")
                    guard gotList.count == wantList.count else { continue }
                    // Scores must agree position by position; ids too, except where the lab's list has a
                    // tie (its tie order changes from run to run).
                    let scores = wantList.map { $0.score }
                    let hasTie = Set(scores).count != scores.count || (wantList.count == 8 && gotList.count == 8)
                    if hasTie { tieLists += 1 }
                    for (g, w) in zip(gotList, wantList) {
                        #expect(near(g.score, w.score, Self.scoreTol), "\(label) score \(g.score) vs \(w.score)")
                        let tied = scores.filter { near($0, w.score, Self.scoreTol) }.count > 1
                        if !tied && !(w.score == scores.last && wantList.count == 8) {
                            idChecks += 1
                            if g.id == w.id {
                                idMatches += 1
                                #expect(g.title == w.title && g.suggestedTransition == w.suggestedTransition
                                        && g.multiplier == w.multiplier && g.camelotA == w.camelotA
                                        && g.camelotB == w.camelotB, "\(label)")
                                #expect(near(g.stretchPct, w.stretchPct, Self.twoPlaceTol), "\(label)")
                            } else {
                                #expect(g.id == w.id, "\(label): \(g.id) (\(g.score)) vs \(w.id) (\(w.score))")
                            }
                        }
                    }
                }
            }
        }
        print("recommendation lists compared: \(lists); ids checked where the lab's score is unique: \(idChecks), matching \(idMatches)")
    }

    /// The booth scores one song at a time (`PairPool`); for every source that must give exactly the pairs the
    /// whole-pool table holds for it, field by field.
    @Test func oneSourceAtATimeMatchesTheWholeTable() throws {
        let pool = ScoredPool.shared
        let one = PairPool(pool.tracks)
        var bySource: [String: [PairKey: PairScore]] = [:]
        for (k, p) in pool.pairs { bySource[k.a, default: [:]][k] = p }
        var compared = 0
        for A in pool.tracks {
            let got = one.scores(from: A)
            let want = bySource[A.id] ?? [:]
            #expect(got.count == want.count, "\(A.id): \(got.count) pairs, table has \(want.count)")
            for p in got {
                #expect(want[PairKey(p.a, p.b)] == p, "\(p.a) -> \(p.b) differs")
                compared += 1
            }
        }
        #expect(compared == pool.pairs.count)
    }

    @Test func tempoAndKeyTermsOnHandMadeTracks() throws {
        var a = ScoredPool.shared.tracks[0], b = a
        a.bpmOut = 126; b.bpmIn = 128
        let t = PairScoring.tempoTerm(a, b)
        #expect(t.label == "1" && near(t.stretchPct, 100 * (128.0 / 126.0 - 1), 1e-9) && t.value == 1)
        b.bpmIn = 63  // B at half A's tempo: the multiplier that lines them up is 2
        #expect(PairScoring.tempoTerm(a, b).label == "2")
        b.bpmIn = 126 * 1.17
        #expect(PairScoring.tempoTerm(a, b).value < 0.4 && !PairScoring.tempoTerm(a, b).reject)
        b.bpmIn = 126 * 1.19  // 19 percent at x1, but x3/4 brings it within 11 percent (capped at 0.35)
        #expect(PairScoring.tempoTerm(a, b).label == "3/4" && PairScoring.tempoTerm(a, b).value == 0.35)
        b.bpmIn = 126 * 2.5  // no multiplier within 18 percent
        #expect(PairScoring.tempoTerm(a, b).reject)
        a.camelot = "8A"; b.camelot = "9A"; a.keyConf = 1; b.keyConf = 1
        #expect(PairScoring.keyTerm(a, b).value == 0.9)
        b.camelot = "3A"  // 8A +7 steps = one semitone up; shifting B down a semitone lands on 8A
        let k = PairScoring.keyTerm(a, b)
        #expect(k.raw == 0.5 && k.shift == -1 && near(k.value, 0.85 - 0.12, 1e-12))
    }
}
