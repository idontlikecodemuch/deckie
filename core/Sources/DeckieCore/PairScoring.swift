import Foundation

/// One analysed track as the pair scoring sees it: the fields mixer/score.py's `load()` extracts from a feature
/// file and its candidates.json row. Bars are counted from 1 in the lab's files; here `vocIn`, `vocOut` and
/// `vocFirst16` are already the per-bar vocal probabilities of the mix-in window, the mix-out window and the
/// first 16 bars from the mix-in start.
public struct Track: Sendable {
    public var id: String
    public var title: String
    public var ver: String
    public var secs: Double
    public var cutKey: String
    public var isLongest: Bool
    public var onDisc: Bool
    public var disc: String?
    public var folder: String
    public var hal: Bool
    public var bpm: Double
    public var bpmTag: Double?
    public var gridConf: Double
    public var bpmIn: Double
    public var bpmOut: Double
    public var tempoChange: Bool
    public var driftPct: Double
    public var inTrusted: Bool
    public var outTrusted: Bool
    public var steadyInBar: Int?
    public var steadyOutBar: Int?
    public var nBars: Int
    public var camelot: String
    public var keyConf: Double
    public var inBars: Int
    public var outBars: Int
    /// Mix-in window loudness (power mean of the bars) relative to the whole track, in LU.
    public var inRel: Double
    public var outRel: Double
    public var vocIn: [Double]
    public var vocOut: [Double]
    public var vocFirst16: [Double]
    /// Onset pattern: 2 bars x 8 eighth-note cells, max 1.
    public var pattern: [Double]
    /// Mean EffNet embedding, unit length.
    public var embedding: [Double]
    public var fadeOut: Bool
    public var flags: [String]
    public var kind: String
    public var era: String

    public init(id: String, title: String, ver: String, secs: Double, cutKey: String, isLongest: Bool, onDisc: Bool,
                disc: String?, folder: String, hal: Bool, bpm: Double, bpmTag: Double?, gridConf: Double,
                bpmIn: Double, bpmOut: Double, tempoChange: Bool, driftPct: Double, inTrusted: Bool,
                outTrusted: Bool, steadyInBar: Int?, steadyOutBar: Int?, nBars: Int, camelot: String,
                keyConf: Double, inBars: Int, outBars: Int, inRel: Double, outRel: Double, vocIn: [Double],
                vocOut: [Double], vocFirst16: [Double], pattern: [Double], embedding: [Double], fadeOut: Bool,
                flags: [String], kind: String, era: String) {
        self.id = id; self.title = title; self.ver = ver; self.secs = secs; self.cutKey = cutKey
        self.isLongest = isLongest; self.onDisc = onDisc; self.disc = disc; self.folder = folder; self.hal = hal
        self.bpm = bpm; self.bpmTag = bpmTag; self.gridConf = gridConf; self.bpmIn = bpmIn; self.bpmOut = bpmOut
        self.tempoChange = tempoChange; self.driftPct = driftPct; self.inTrusted = inTrusted
        self.outTrusted = outTrusted; self.steadyInBar = steadyInBar; self.steadyOutBar = steadyOutBar
        self.nBars = nBars; self.camelot = camelot; self.keyConf = keyConf; self.inBars = inBars
        self.outBars = outBars; self.inRel = inRel; self.outRel = outRel; self.vocIn = vocIn; self.vocOut = vocOut
        self.vocFirst16 = vocFirst16; self.pattern = pattern; self.embedding = embedding; self.fadeOut = fadeOut
        self.flags = flags; self.kind = kind; self.era = era
    }
}

/// The eight terms of the pair score, each 0...1.
public struct ScoreTerms: Sendable, Equatable {
    public var tempo, key, energy, vocal, phrase, timbre, rhythm, style: Double

    /// The terms in the lab's order (the order the weighted sum is taken in).
    public static let names = ["tempo", "key", "energy", "vocal", "phrase", "timbre", "rhythm", "style"]

    public subscript(name: String) -> Double {
        switch name {
        case "tempo": return tempo
        case "key": return key
        case "energy": return energy
        case "vocal": return vocal
        case "phrase": return phrase
        case "timbre": return timbre
        case "rhythm": return rhythm
        case "style": return style
        default: preconditionFailure("unknown term \(name)")
        }
    }

    public func rounded(_ places: Int) -> ScoreTerms {
        ScoreTerms(tempo: Py.round(tempo, places), key: Py.round(key, places), energy: Py.round(energy, places),
                   vocal: Py.round(vocal, places), phrase: Py.round(phrase, places),
                   timbre: Py.round(timbre, places), rhythm: Py.round(rhythm, places), style: Py.round(style, places))
    }
}

/// The score of one directed pair, A mixing into B: the record mixer/score.py writes into pairs.json.
public struct PairScore: Sendable, Equatable {
    public var a: String
    public var b: String
    /// Weighted sum of the terms, before the "longer cut" bonus; rounded to 4 places like the lab.
    public var scoreBase: Double
    /// Rounded to 3 places like the lab.
    public var terms: ScoreTerms
    public var stretchPct: Double
    public var multiplier: String
    public var suggestedTransition: String
    public var moves: [String]
    public var vocalOverlap: Double
    public var overlapBars: Int
    public var keyShiftSt: Int
    public var energyDeltaLu: Double
    public var reasons: [String]
}

/// Directed pair scoring, "A mixes into B" (research B.9, B.10, E.3, E.4). Port of mixer/score.py.
public enum PairScoring {
    /// The weights of the eight terms, in the order the sum is taken.
    public static let weights: [(String, Double)] = [
        ("tempo", 0.26), ("key", 0.14), ("energy", 0.11), ("vocal", 0.11),
        ("phrase", 0.08), ("timbre", 0.12), ("rhythm", 0.05), ("style", 0.13),
    ]
    public static let pairMin = 0.45
    public static let longSecs = 270.0
    public static let longBonus = 0.03
    public static let topN = 8
    static let voc = 0.5
    static let danceKinds: Set<String> = ["pool edit", "official remix", "dance original"]

    /// How alike the two records are as DJ material: remix, house and dance versus pop original, era, Halloween.
    public static func styleTerm(_ A: Track, _ B: Track) -> Double {
        let fa = danceKinds.contains(A.kind) ? "dance" : "pop"
        let fb = danceKinds.contains(B.kind) ? "dance" : "pop"
        var st = fa == fb ? 1.0 : 0.45
        if !A.era.isEmpty && !B.era.isEmpty { st -= A.era == B.era ? 0.0 : 0.15 }
        if A.hal && B.hal { st = min(1.0, st + 0.1) }
        return max(0.0, st)
    }

    /// Key term: the B.9 table, or a pitch shift of B by up to two semitones when that lands on a neighbour,
    /// scaled by the lower of the two key confidences.
    public static func keyTerm(_ A: Track, _ B: Track)
        -> (value: Double, raw: Double, shift: Int, why: String, confidence: Double) {
        let (raw, why) = Camelot.rawCompatibility(A.camelot, B.camelot)
        var best = raw, shift = 0
        for s in [1, -1, 2, -2] {
            let (r2, _) = Camelot.rawCompatibility(A.camelot, Camelot.shifted(B.camelot, semitones: s))
            if r2 >= 0.85 {
                let v = 0.85 - 0.12 * Double(abs(s))
                if v > best { best = v; shift = s }
            }
        }
        let c = min(A.keyConf, B.keyConf)
        return (best * (0.5 + 0.5 * c), raw, shift, why, c)
    }

    /// Tempo term from A's end tempo and B's start tempo over the seven multipliers.
    /// `reject` is true beyond an 18 percent stretch.
    public static func tempoTerm(_ A: Track, _ B: Track)
        -> (value: Double, k: Double, label: String, stretchPct: Double, reject: Bool) {
        var best: (d: Double, k: Double, lab: String, r: Double)? = nil
        for (k, lab) in Tempo.labels {
            let r = B.bpmIn * k / A.bpmOut
            let d = abs(log(r))
            if best == nil || d < best!.d - 1e-12 { best = (d, k, lab, r) }
        }
        let (_, k, lab, r) = best!
        let s = abs(r - 1) * 100
        if s > 18 { return (0.0, k, lab, s, true) }
        // Mike's CDJ-1000MK3 pitch range goes to +/-16 percent: free to 3, gentle to 10, usable to 16.
        var t = s <= 3 ? 1.0 : (s <= 10 ? 1 - (s - 3) / 7 * 0.6 : 0.4 - (s - 10) / 6 * 0.3)
        t = max(t, 0.05)
        if k == 0.5 || k == 2.0 {
            t = max(0.01, t - 0.10)
        } else if k != 1.0 {  // 2/3, 3/4, 4/3, 3/2: needs a tempo-change transition track or a brake, never a blend
            t = min(t, 0.35)
        }
        return (t, k, lab, s, false)
    }

    static func fold8(_ p: [Double]) -> [Double] { (0..<8).map { (p[$0] + p[$0 + 8]) / 2 } }

    /// numpy.interp(arange(16) / 2, arange(8), p8): the one-bar pattern stretched to 16 cells.
    static func up16(_ p8: [Double]) -> [Double] {
        (0..<16).map { i -> Double in
            let x = Double(i) / 2.0
            if x >= 7 { return p8[7] }
            let j = Int(x)
            if Double(j) == x { return p8[j] }
            let slope = (p8[j + 1] - p8[j]) / 1.0
            return slope * (x - Double(j)) + p8[j]
        }
    }

    /// Pearson correlation; 0 when either side is flat.
    static func corr(_ x: [Double], _ y: [Double]) -> Double {
        let mx = Py.mean(x), my = Py.mean(y)
        var dot = 0.0, nx = 0.0, ny = 0.0
        for i in 0..<x.count {
            let a = x[i] - mx, b = y[i] - my
            dot += a * b; nx += a * a; ny += b * b
        }
        let den = nx.squareRoot() * ny.squareRoot()
        return den > 0 ? dot / den : 0.0
    }

    /// Rhythm term: correlation of the two onset patterns, folding the half-tempo side for a 2 or 1/2 relation;
    /// a neutral 0.25 for the relations that cannot be compared cell by cell.
    public static func rhythmTerm(_ A: Track, _ B: Track, k: Double) -> Double {
        if k == 1.0 { return max(0.0, corr(A.pattern, B.pattern)) }
        if k == 2.0 { return max(0.0, corr(A.pattern, up16(fold8(B.pattern)))) }
        if k == 0.5 { return max(0.0, corr(up16(fold8(A.pattern)), B.pattern)) }
        return 0.25
    }

    /// The suggested transition (research E.4).
    public static func transition(_ A: Track, _ B: Track, s: Double, k: Double, v: Double, rhythm: Double,
                                  L: Int, steady: Bool) -> String {
        if !steady {  // no steady beat at A's end or B's start: echo A out and cut B in on its downbeat
            return s <= 8 ? "quick_blend_echo" : "brake_cut"
        }
        if s > 16 || (!(k == 1.0 || k == 0.5 || k == 2.0) && rhythm < 0.5) { return "brake_cut" }
        // Mike mixes progressively: a blend is the default answer whenever the beats can be matched.
        // The vocal detector over-reports singing, so only heavy overlap pushes a pair to an effect exit.
        if v >= 0.6 { return s <= 16 ? "quick_blend_echo" : "brake_cut" }
        if s > 6 { return "ramped_blend" }
        if v < 0.35 && A.outBars >= 16 && B.inBars >= 16 {
            return (A.outBars >= 32 && B.inBars >= 32 && v < 0.2) ? "bass_swap_32" : "bass_swap_16"
        }
        if A.outBars >= 8 && B.inBars >= 8 { return "bass_swap_8" }
        return Py.mean(Array(A.vocOut.suffix(L))) >= Py.mean(Array(B.vocIn.prefix(L))) ? "quick_blend_echo" : "filter_sweep"
    }

    /// Ordered menu of plausible moves for the pair, primary first; Mike picks, the app only suggests.
    public static func moveOptions(_ A: Track, _ B: Track, s: Double, k: Double, v: Double, tr: String) -> [String] {
        var opts = [tr]
        let matchable = s <= 16 && (k == 1.0 || k == 0.5 || k == 2.0)
        func add(_ x: String) { if !opts.contains(x) { opts.append(x) } }
        if matchable {
            if A.outBars >= 16 && B.inBars >= 16 { add("bass_swap_16") }
            else if A.outBars >= 8 && B.inBars >= 8 { add("bass_swap_8") }
            add("quick_blend_echo")
            if A.outTrusted && v < 0.6 { add("filter_sweep") }
        } else {
            add("quick_blend_echo")
        }
        add("brake_cut")
        return Array(opts.prefix(3))
    }

    /// Scores A mixing into B. `timbrePct` is the rank-normalised timbre similarity (see `PairScorer`).
    /// Nil when the tempo gap is beyond 18 percent, or heavy vocal overlap meets a blend (never, by construction).
    public static func scorePair(_ A: Track, _ B: Track, timbrePct: Double) -> PairScore? {
        let (tempo, k, klab, s, reject) = tempoTerm(A, B)
        if reject { return nil }
        let (key, _, shift, kwhy, kc) = keyTerm(A, B)
        let dE = B.inRel - A.outRel
        let energy = 1 - min(max(abs(dE) - 2, 0), 8) / 8
        var L = min(A.outBars, B.inBars)
        var pa = Array(A.vocOut.suffix(L))
        var pb = Array(B.vocIn.prefix(L))
        L = min(pa.count, pb.count)
        pa = Array(pa.suffix(L)); pb = Array(pb.prefix(L))
        let v = L > 0 ? Py.mean((0..<L).map { pa[$0] * pb[$0] }) : 0.0
        var clash = 0
        for i in 0..<L where pa[i] >= voc && pb[i] >= voc { clash += 1 }
        let clean16 = B.vocFirst16.count >= 16 && B.vocFirst16.allSatisfy { $0 < voc }
        let vocal = min(1.0, 1 - v + (clean16 ? 0.1 : 0.0))
        let longOk = A.outBars >= 16 && B.inBars >= 16
        let steady = A.outTrusted && B.inTrusted
        let gconf = (0.7 + 0.3 * A.gridConf) * (0.7 + 0.3 * B.gridConf)
        let win = min(A.outBars, B.inBars)
        var phrase = gconf * min(1.0, max(0.0, Double(win - 8) / 8.0))  // graded: 0 at 8 bars, full at 16
        let dropIn = !B.inTrusted && (B.steadyInBar ?? 0) != 0
            && Double(B.steadyInBar!) <= max(9.0, 0.3 * Double(B.nBars))
        if !steady { phrase *= dropIn ? 0.6 : 0.4 }
        let timbre = timbrePct
        let rhythm = rhythmTerm(A, B, k: k)
        let style = styleTerm(A, B)
        let terms = ScoreTerms(tempo: tempo, key: key, energy: energy, vocal: vocal, phrase: phrase,
                               timbre: timbre, rhythm: rhythm, style: style)
        var base = 0.0
        for (name, w) in weights { base += w * terms[name] }
        let tr = transition(A, B, s: s, k: k, v: v, rhythm: rhythm, L: max(L, 1), steady: steady)
        // hard gate: heavy vocal overlap only with a cut-style transition (always true by construction)
        if v >= 0.6 && tr != "quick_blend_echo" && tr != "brake_cut" { return nil }

        var txt: [String: String] = [:]
        if k == 0.5 || k == 2.0 {
            txt["tempo"] = "half-time/double-time blend (x\(klab)), \(Py.fixed(s, 1))% stretch"
        } else if k != 1.0 {
            txt["tempo"] = "tempo change x\(klab) (\(Py.fixed(A.bpmOut, 0)) -> \(Py.fixed(B.bpmIn, 0))): "
                + "transition track or brake, no blend"
        } else if s <= 0.5 {
            txt["tempo"] = "same tempo (\(Py.fixed(A.bpmOut, 1)) BPM at A's end)"
        } else {
            txt["tempo"] = "\(B.bpmIn * k < A.bpmOut ? "+" : "-")\(Py.fixed(s, 1))% stretch on B "
                + "(\(Py.fixed(A.bpmOut, 1)) end -> \(Py.fixed(B.bpmIn, 1)) start)"
        }
        var ktxt = "\(A.camelot) -> \(B.camelot)"
        if shift != 0 {
            ktxt += " (pitch-shift B by \(shift >= 0 ? "+" : "")\(shift) st)"
        } else if kwhy != "same key" {
            ktxt += " (\(kwhy))"
        }
        if kc < 0.5 { ktxt += ", key unsure" }
        txt["key"] = ktxt
        txt["energy"] = abs(dE) <= 2
            ? "energy steady (\(Py.signedFixed(dE, 1)) LU)"
            : "B enters \(Py.signedFixed(dE, 1)) LU \(dE > 0 ? "louder" : "quieter")"
        if clean16 {
            txt["vocal"] = "B has a clean 16-bar intro"
        } else if clash != 0 {
            txt["vocal"] = "vocals overlap \(clash) of \(L) bars"
        } else {
            txt["vocal"] = "no vocal clash"
        }
        if !steady {
            if !A.outTrusted {
                txt["phrase"] = "no steady beat at A's end (echo out, cut B in on its downbeat)"
            } else if dropIn {
                txt["phrase"] = "B's beat starts at bar \(B.steadyInBar!) (cut in there, skip the intro)"
            } else {
                txt["phrase"] = "no steady beat at B's start (cut in on the downbeat)"
            }
        } else if !longOk {
            txt["phrase"] = "\(win)-bar window (short of a 16-bar phrase)"
        } else if phrase < 0.4 {
            txt["phrase"] = "shaky beat grid"
        } else {
            txt["phrase"] = "\(L)-bar phrases both sides"
        }
        txt["style"] = style >= 0.9 ? "same style" : (style >= 0.6 ? "related style" : "different style")
        txt["timbre"] = timbre >= 0.5
            ? "similar sound (closer than \(Py.fixed(timbre * 100, 0))% of pairs)"
            : "different sound (closer than only \(Py.fixed(timbre * 100, 0))% of pairs)"
        if k == 1.0 || k == 2.0 || k == 0.5 {
            txt["rhythm"] = "\(rhythm >= 0.6 ? "matching" : "different") groove (r=\(Py.fixed(rhythm, 2)))"
        } else {
            txt["rhythm"] = "groove not comparable at x\(klab)"
        }
        // The three largest positive terms (a stable sort, so ties keep the lab's term order), then every
        // term below 0.4 that is not already listed.
        let positive = ScoreTerms.names.enumerated().filter { terms[$0.element] > 0 }
        let order = positive.sorted { l, r in
            let a = terms[l.element], b = terms[r.element]
            return a != b ? a > b : l.offset < r.offset
        }.prefix(3).map { $0.element }
        var reasons = order.map { txt[$0]! }
        for name in ScoreTerms.names where terms[name] < 0.4 && !order.contains(name) { reasons.append(txt[name]!) }
        return PairScore(a: A.id, b: B.id, scoreBase: Py.round(base, 4), terms: terms.rounded(3),
                         stretchPct: Py.round(s, 2), multiplier: klab, suggestedTransition: tr,
                         moves: moveOptions(A, B, s: s, k: k, v: v, tr: tr), vocalOverlap: Py.round(v, 3),
                         overlapBars: L, keyShiftSt: shift, energyDeltaLu: Py.round(dE, 2), reasons: reasons)
    }
}
