import Foundation
import DeckieCore
import DeckieLab

/// The fields of a lab feature file (mixer/features/<id>.json) that the bench compares, read from either side: the
/// lab's committed file, or the engine's record in the same shape (`Analysis.labJSON()`).
public struct BenchRecord: Decodable, Sendable {
    public struct Grid: Decodable, Sendable {
        public var source: String?
        public var bpm: Double
        public var firstDownbeatS: Double
        public var barS: Double?
        public var nBars: Int
        enum CodingKeys: String, CodingKey {
            case source, bpm, firstDownbeatS = "first_downbeat_s", barS = "bar_s", nBars = "n_bars"
        }
    }
    public struct Key: Decodable, Sendable {
        public var camelot: String
        public var confidence: Double?
    }
    public struct Loudness: Decodable, Sendable {
        public var integratedLufs: Double?
        public var truePeakDb: Double?
        enum CodingKeys: String, CodingKey { case integratedLufs = "integrated_lufs", truePeakDb = "true_peak_db" }
    }
    public struct PerBar: Decodable, Sendable {
        public var vocalProb: [Double]?
        enum CodingKeys: String, CodingKey { case vocalProb = "vocal_prob" }
    }
    /// The engine's own block (absent in the lab's files).
    public struct Engine: Decodable, Sendable {
        public var engine: String?
        public var bytes: Int?
        public var madmomWouldRun: String?
        public var vocalModel: String?
        /// `deckie.key` (engine 0.4.0 on): the HPCP method's decision and its parity decision.
        public var key: EngineKey?
        enum CodingKeys: String, CodingKey {
            case engine, bytes, key, madmomWouldRun = "madmom_would_run", vocalModel = "vocal_model"
        }
    }
    /// The HPCP key method's decision as the engine's record writes it (`deckie.key`): the key, margin, agreement and
    /// sure flag with the literature's profile numbers, and `parity`, the same with key_light.py's (what
    /// mixer/key_parity.py decides). Older records have neither (their fields are nil).
    public struct EngineKey: Decodable, Sendable {
        public var camelot: String?
        public var margin: Double?
        public var agree: Int?
        public var sure: Bool?
        public var parity: KeyDecision?
    }
    /// One decision of the HPCP key method as `deckie.key.parity` writes it.
    public struct KeyDecision: Decodable, Sendable, Equatable {
        public var camelot: String
        public var margin: Double
        public var agree: Int
        public var sure: Bool
        public init(camelot: String, margin: Double, agree: Int, sure: Bool) {
            self.camelot = camelot; self.margin = margin; self.agree = agree; self.sure = sure
        }
    }

    public var id: String
    public var title: String?
    public var bpm: Double
    public var bpmTag: Double?
    public var grid: Grid
    public var beatsS: [Double]?
    public var downbeatsS: [Double]?
    public var detectedBeatsS: [Double]?
    public var detectedDownbeatsS: [Double]?
    public var boundariesBars: [Int]?
    public var key: Key
    public var loudness: Loudness?
    public var perBar: PerBar?
    public var deckie: Engine?

    enum CodingKeys: String, CodingKey {
        case id, title, bpm, grid, key, loudness, deckie
        case bpmTag = "bpm_tag", beatsS = "beats_s", downbeatsS = "downbeats_s", detectedBeatsS = "detected_beats_s"
        case detectedDownbeatsS = "detected_downbeats_s", boundariesBars = "boundaries_bars", perBar = "per_bar"
    }

    /// The bar length in seconds (`grid.bar_s`, or four beats at `grid.bpm`).
    public var barS: Double { grid.barS ?? 240.0 / grid.bpm }
}

/// One track's comparison, engine against lab, with the stage 1 metrics as mixer/bench_mu.py computes them
/// (docs/architecture/stage1-results.md, 1a). Nil where a side has nothing to compare.
public struct TrackScore: Sendable, Equatable {
    public var id: String
    public var title: String?
    /// The audio file's path below the folder.
    public var rel: String
    /// The engine's analysis time; nil when its record came from the records folder.
    public var seconds: Double?

    /// F-measure at 70 ms: the engine's detected beats against the lab's detected beats, its grid beats against the
    /// lab's grid beats, the better of the detected pair at the same octave or with either side halved; the same for
    /// downbeats.
    public var beatFDetected: Double?
    public var beatFGrid: Double?
    public var beatFBestOctave: Double?
    public var downbeatFDetected: Double?
    public var downbeatFGrid: Double?

    public var bpmEngine: Double
    public var bpmLab: Double
    /// Engine over lab.
    public var bpmRatio: Double
    /// Within 2 percent as stage 1 counts it (the ratio within 0.02 of 1), and after the octave normalisation (the
    /// ratio times 1/2, 1 or 2, whichever is nearest 1); an octave apart as stage 1 counts it.
    public var tempoWithin2: Bool
    public var tempoWithin2Octave: Bool
    public var octaveApart: Bool

    public var keyEngine: String
    public var keyLab: String
    public var keyConfidenceLab: Double?
    /// `exact`, `neighbour` (the relative key, or one step round the wheel) or `other`.
    public var keyRelation: String
    /// mixer/key_parity_keys.tsv's row for the track (research R's key method as key_parity.py decided it), nil when
    /// the sheet was not given or has no row for it.
    public var keyParityReference: KeyParityRow?
    /// The engine's parity decision (its HPCP method with key_light.py's profile numbers, `deckie.key.parity`), nil
    /// in a record made before engine 0.4.0.
    public var keyParityEngine: BenchRecord.KeyDecision?
    /// Parity of the engine's key with key_parity.py's (the main session's rule: the same key, the margin within
    /// 1e-3, the same sure flag): nil without both sides, `same`, or the differences in words.
    public var keyParity: String? {
        guard let r = keyParityReference, let e = keyParityEngine else { return nil }
        return r.differences(key: e.camelot, margin: e.margin, sure: e.sure) ?? "same"
    }

    /// Engine minus lab: integrated loudness (LU) and true peak (dB).
    public var lufsDelta: Double?
    public var truePeakDelta: Double?

    /// The lab's inner section boundaries (bar lines strictly inside the grid, in seconds) found by the engine's within
    /// one of the lab's bars (recall), and the engine's found by the lab's (precision).
    public var sectionRecall: Double?
    public var sectionPrecision: Double?

    /// Pearson correlation of the per-bar vocal probability, the engine's bar under the middle of each lab bar; nil
    /// with `vocalNote` saying which side has none.
    public var vocalR: Double?
    public var vocalNote: String

    /// Engine minus lab, the start of bar 1, in milliseconds; and the bar counts.
    public var bar1OffsetMs: Double
    public var nBarsEngine: Int
    public var nBarsLab: Int
    public var nBarsMatch: Bool { nBarsEngine == nBarsLab }

    /// Where the lab's grid came from (`beatthis` or `madmom`) and why the lab's rule would have run madmom on the
    /// engine's grid: where the grids may differ by design.
    public var labGridSource: String?
    public var madmomWouldRun: String?
}

/// The stage 1 measures, ported from mixer/bench_mu.py so the numbers mean what they meant there.
public enum BenchMetrics {
    /// The tolerance of a beat match: 70 ms.
    public static let tolerance = 0.07

    /// mixer/bench_mu.py's `fmeasure`: each estimate, in order, takes the first unused reference of the two around it
    /// (the one before, then the one at or after) within the tolerance; precision is hits over estimates, recall hits
    /// over references. Nil when either list is empty.
    public static func fMeasure(reference: [Double], estimate: [Double], tolerance tol: Double = tolerance) -> Double? {
        let ref = reference.sorted(), est = estimate.sorted()
        guard !ref.isEmpty, !est.isEmpty else { return nil }
        var used = Set<Int>()
        var hits = 0
        for x in est {
            var lo = 0, hi = ref.count  // bisect_left
            while lo < hi {
                let mid = (lo + hi) / 2
                if ref[mid] < x { lo = mid + 1 } else { hi = mid }
            }
            for j in [lo - 1, lo] where j >= 0 && j < ref.count && !used.contains(j) && abs(ref[j] - x) <= tol {
                hits += 1
                used.insert(j)
                break
            }
        }
        let p = Double(hits) / Double(est.count), r = Double(hits) / Double(ref.count)
        return p + r > 0 ? 2 * p * r / (p + r) : 0
    }

    /// mixer/bench_mu.py's `key_relation`.
    public static func keyRelation(_ a: String, _ b: String) -> String {
        if a == b { return "exact" }
        let (na, la) = Camelot.parse(a), (nb, lb) = Camelot.parse(b)
        guard na > 0, nb > 0 else { return "other" }
        if na == nb && la != lb { return "neighbour" }
        if la == lb && [1, 11].contains(Py.mod(na - nb, 12)) { return "neighbour" }
        return "other"
    }

    /// mixer/bench_mu.py's `boundary_pr`: (precision, recall) of `estimate` against `reference` within `tolerance`
    /// seconds; nil when either is empty.
    public static func boundaries(reference: [Double], estimate: [Double], tolerance: Double) -> (precision: Double, recall: Double)? {
        guard !reference.isEmpty, !estimate.isEmpty else { return nil }
        let hitE = estimate.filter { e in reference.contains { abs(e - $0) <= tolerance } }.count
        let hitR = reference.filter { r in estimate.contains { abs($0 - r) <= tolerance } }.count
        return (Double(hitE) / Double(estimate.count), Double(hitR) / Double(reference.count))
    }

    /// mixer/bench_mu.py's `pearson`: nil under three pairs or with no spread on a side.
    public static func pearson(_ x: [Double], _ y: [Double]) -> Double? {
        let n = x.count
        guard n >= 3, y.count == n else { return nil }
        let mx = pySum(x) / Double(n), my = pySum(y) / Double(n)
        let sx = pySum(x.map { ($0 - mx) * ($0 - mx) }).squareRoot()
        let sy = pySum(y.map { ($0 - my) * ($0 - my) }).squareRoot()
        guard sx != 0, sy != 0 else { return nil }
        return pySum(zip(x, y).map { ($0 - mx) * ($1 - my) }) / (sx * sy)
    }

    /// Python's built-in `sum` of floats as CPython 3.12 and later computes it: Neumaier's compensated summation, the
    /// running compensation added once at the end. (`x ** 2` in the lab is `x * x` here: both are one correctly rounded
    /// product.)
    static func pySum(_ values: [Double]) -> Double {
        var sum = 0.0, c = 0.0
        for x in values {
            let t = sum + x
            if abs(sum) >= abs(x) { c += (sum - t) + x } else { c += (x - t) + sum }
            sum = t
        }
        return c != 0 && c.isFinite ? sum + c : sum
    }

    /// The bar lines strictly inside the grid, in seconds (mixer/bench_mu.py's `lab_bd`).
    static func innerBoundaries(_ r: BenchRecord) -> [Double] {
        (r.boundariesBars ?? []).filter { $0 > 1 && $0 < r.grid.nBars }
            .map { r.grid.firstDownbeatS + Double($0 - 1) * r.barS }
    }

    /// Every other element, from the first (Python's `a[::2]`).
    static func everyOther(_ a: [Double]) -> [Double] { stride(from: 0, to: a.count, by: 2).map { a[$0] } }

    /// Compares the engine's record with the lab's for one track, and its key with key_parity.py's (`parity`, the
    /// track's row of mixer/key_parity_keys.tsv) when given.
    public static func compare(engine e: BenchRecord, lab l: BenchRecord, rel: String, seconds: Double?,
                               parity: KeyParityRow? = nil) -> TrackScore {
        let eb = e.detectedBeatsS ?? [], lb = l.detectedBeatsS ?? []
        let beatF = fMeasure(reference: lb, estimate: eb)
        let best = [beatF ?? 0, fMeasure(reference: lb, estimate: everyOther(eb)) ?? 0,
                    fMeasure(reference: everyOther(lb), estimate: eb) ?? 0].max()!
        let ratio = e.bpm / l.bpm
        let octave = [ratio, ratio * 2, ratio / 2].min { abs($0 - 1) < abs($1 - 1) }!
        var lufsDelta: Double? = nil
        if let a = e.loudness?.integratedLufs, let b = l.loudness?.integratedLufs, a.isFinite, b.isFinite { lufsDelta = a - b }
        var peakDelta: Double? = nil
        if let a = e.loudness?.truePeakDb, let b = l.loudness?.truePeakDb, a.isFinite, b.isFinite { peakDelta = a - b }
        let sections = boundaries(reference: innerBoundaries(l), estimate: innerBoundaries(e), tolerance: l.barS)

        // Vocal: the engine's bar under the middle of each of the lab's bars.
        var vocalR: Double? = nil
        let vocalNote: String
        switch (e.perBar?.vocalProb, l.perBar?.vocalProb) {
        case (nil, nil): vocalNote = "absent on both sides"
        case (nil, _): vocalNote = "absent: the engine ran without its vocal tagger"
        case (_, nil): vocalNote = "absent: the lab has none"
        case (let ev?, let lv?):
            var xs: [Double] = [], ys: [Double] = []
            for (i, v) in lv.enumerated() {
                let mid = l.grid.firstDownbeatS + (Double(i) + 0.5) * l.barS
                let j = Int(((mid - e.grid.firstDownbeatS) / e.barS).rounded(.down))
                if j >= 0 && j < ev.count { xs.append(ev[j]); ys.append(v) }
            }
            vocalR = pearson(xs, ys)
            vocalNote = vocalR == nil ? "not enough bars or no spread to correlate" : "compared over \(xs.count) bars"
        }

        return TrackScore(
            id: l.id, title: l.title, rel: rel, seconds: seconds,
            beatFDetected: beatF, beatFGrid: fMeasure(reference: l.beatsS ?? [], estimate: e.beatsS ?? []),
            beatFBestOctave: best,
            downbeatFDetected: fMeasure(reference: l.detectedDownbeatsS ?? [], estimate: e.detectedDownbeatsS ?? []),
            downbeatFGrid: fMeasure(reference: l.downbeatsS ?? [], estimate: e.downbeatsS ?? []),
            bpmEngine: e.bpm, bpmLab: l.bpm, bpmRatio: ratio, tempoWithin2: abs(ratio - 1) < 0.02,
            tempoWithin2Octave: abs(octave - 1) < 0.02, octaveApart: abs(ratio - 2) < 0.04 || abs(ratio - 0.5) < 0.01,
            keyEngine: e.key.camelot, keyLab: l.key.camelot, keyConfidenceLab: l.key.confidence,
            keyRelation: keyRelation(e.key.camelot, l.key.camelot),
            keyParityReference: parity, keyParityEngine: e.deckie?.key?.parity,
            lufsDelta: lufsDelta, truePeakDelta: peakDelta,
            sectionRecall: sections?.recall, sectionPrecision: sections?.precision,
            vocalR: vocalR, vocalNote: vocalNote,
            bar1OffsetMs: (e.grid.firstDownbeatS - l.grid.firstDownbeatS) * 1000,
            nBarsEngine: e.grid.nBars, nBarsLab: l.grid.nBars,
            labGridSource: l.grid.source, madmomWouldRun: e.deckie?.madmomWouldRun)
    }
}
