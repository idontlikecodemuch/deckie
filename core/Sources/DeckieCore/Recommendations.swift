import Foundation

/// A directed pair's key, A into B.
public struct PairKey: Hashable, Sendable {
    public var a: String
    public var b: String
    public init(_ a: String, _ b: String) { self.a = a; self.b = b }
}

/// One line of a track's recommendation list (mixer/recs.json).
public struct RecEntry: Sendable, Equatable {
    public var id: String
    public var title: String
    public var score: Double
    public var reasons: [String]
    public var suggestedTransition: String
    public var stretchPct: Double
    public var multiplier: String
    public var camelotA: String
    public var camelotB: String
}

/// A track's top lists: `out` = what to play after it, `in` = what to play before it.
public struct RecLists: Sendable, Equatable {
    public var out: [RecEntry]
    public var `in`: [RecEntry]
}

/// Scoring a whole pool: the timbre ranking that needs every track, every directed pair, and the top lists.
/// Port of `main()` in mixer/score.py (without the files it writes).
public enum PairScorer {
    /// Rank-normalised timbre: for tracks i and j, the share of the pool's track-to-track cosine similarities
    /// (each unordered pair once) that are at most cosine(i, j).
    public static func timbrePercentiles(_ tracks: [Track]) -> [[Double]] {
        let n = tracks.count
        var C = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n {
            for j in i..<n {
                var dot = 0.0
                let ei = tracks[i].embedding, ej = tracks[j].embedding
                // A record without an embedding (an engine record) has an empty one, which scores 0 against any.
                for d in 0..<min(ei.count, ej.count) { dot += ei[d] * ej[d] }
                C[i][j] = dot; C[j][i] = dot
            }
        }
        var vals: [Double] = []
        vals.reserveCapacity(n * (n - 1) / 2)
        for i in 0..<n { for j in (i + 1)..<n { vals.append(C[i][j]) } }
        vals.sort()
        let denom = Double(max(1, vals.count))
        return C.map { row in row.map { Double(Py.countAtMost($0, in: vals)) / denom } }
    }

    /// Every directed pair that passes the gates (same-cut pairs are skipped).
    public static func scoreAll(_ tracks: [Track]) -> [PairKey: PairScore] {
        let pct = timbrePercentiles(tracks)
        var P: [PairKey: PairScore] = [:]
        for (i, A) in tracks.enumerated() {
            for (j, B) in tracks.enumerated() {
                if i == j || A.cutKey == B.cutKey { continue }
                if let r = PairScoring.scorePair(A, B, timbrePct: pct[i][j]) { P[PairKey(A.id, B.id)] = r }
            }
        }
        return P
    }

    /// +0.03 for a recommended track of 270 s or more ("longer cut").
    public static func bonus(_ t: Track) -> Double { t.secs >= PairScoring.longSecs ? PairScoring.longBonus : 0.0 }

    /// Keeps one track per cut key: the one marked longest, else the longest analysed. `ids` in pool order.
    public static func dedupe(_ ids: [String], _ by: [String: Track]) -> Set<String> {
        var best: [String: String] = [:]
        for i in ids {
            let t = by[i]!
            if let cur = best[t.cutKey] {
                let c = by[cur]!
                let better = t.isLongest != c.isLongest ? (t.isLongest && !c.isLongest) : t.secs > c.secs
                if better { best[t.cutKey] = i }
            } else {
                best[t.cutKey] = i
            }
        }
        return Set(best.values)
    }

    static func entry(_ p: PairScore, other: String, by: [String: Track], bonus bon: Double) -> RecEntry {
        let o = by[other]!
        var reasons = p.reasons
        if bon != 0 { reasons.append("longer cut") }
        return RecEntry(id: other, title: "\(o.title) \(o.ver)".trimmingCharacters(in: .whitespaces),
                        score: Py.round(p.scoreBase + bon, 4), reasons: reasons,
                        suggestedTransition: p.suggestedTransition, stretchPct: p.stretchPct,
                        multiplier: p.multiplier, camelotA: by[p.a]!.camelot, camelotB: by[p.b]!.camelot)
    }

    /// Per track, the top 8 out and in for the "disc" view (on-disc candidates) and the "pool" view (every
    /// analysed track), one track per cut key, never another cut of the same song. Candidates are visited in
    /// pool order and ties keep that order (the lab visits them in an order that changes from run to run).
    public static func recommendations(_ tracks: [Track], pairs P: [PairKey: PairScore])
        -> [String: [String: RecLists]] {
        let by = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        let ids = tracks.map { $0.id }
        let views: [(String, Set<String>)] = [
            ("disc", dedupe(ids.filter { by[$0]!.onDisc }, by)),
            ("pool", dedupe(ids, by)),
        ]
        var recs: [String: [String: RecLists]] = [:]
        for t in tracks {
            var r: [String: RecLists] = [:]
            for (vname, cand) in views {
                var outs: [RecEntry] = [], ins: [RecEntry] = []
                for o in ids where cand.contains(o) {
                    if o == t.id || by[o]!.cutKey == t.cutKey { continue }
                    if let p = P[PairKey(t.id, o)] { outs.append(entry(p, other: o, by: by, bonus: bonus(by[o]!))) }
                    if let q = P[PairKey(o, t.id)] { ins.append(entry(q, other: o, by: by, bonus: bonus(by[o]!))) }
                }
                outs = stableSortedByScore(outs)
                ins = stableSortedByScore(ins)
                r[vname] = RecLists(out: Array(outs.prefix(PairScoring.topN)), in: Array(ins.prefix(PairScoring.topN)))
            }
            recs[t.id] = r
        }
        return recs
    }

    static func stableSortedByScore(_ e: [RecEntry]) -> [RecEntry] {
        e.enumerated().sorted { l, r in
            l.element.score != r.element.score ? l.element.score > r.element.score : l.offset < r.offset
        }.map { $0.element }
    }
}
