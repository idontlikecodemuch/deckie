import Foundation

/// Hook candidates: research Q's item B7 (docs/research/q-vocal-uses.md). A DJ teases the next track's hook, cuts to
/// the chorus or lets the room sing it; "recognisable" is not in the audio, so this only proposes up to three
/// stretches of 4 to 8 bars, strongest first, for the DJ to confirm with one tap later. A hook here is a stretch that
/// repeats elsewhere in the track, is loud for the track and is sung.
///
/// Repetition comes from the features the structure novelty already uses (`FooteNovelty`): the frame-wise MFCC averaged
/// over each bar by the novelty's own frame edges, compared bar with bar as the novelty compares half-beats
/// (`FooteNovelty.mfccSimilarity`). Loudness is the per-bar `lufs` series; vocal density is the share of the stretch's
/// beats inside a vocal span (`VocalStructure.barCoverage`). A first cut, with its parameters kept beside the result.
public struct Hooks: Sendable, Equatable {
    /// The rule's parameters (a first cut, chosen on synthesised tracks; nothing is tuned on real music yet).
    public struct Parameters: Sendable, Equatable {
        /// Candidate lengths in bars, longest first: memo Q's 4 to 8 bars, a phrase or half of one.
        public var lengthsBars = [8, 4]
        /// Candidates start every this many bars from the lattice phase, so on a phrase boundary or halfway through
        /// one: a tease or a cut goes in on a phrase boundary (memo Q, use 4).
        public var stepBars = 4
        /// strength = (weightRepetition x repetition + weightLoudness x loudness + weightVocal x vocal density) / the
        /// weights' sum, each term 0 to 1. Repetition counts most: it is what makes a stretch a hook rather than
        /// merely the loudest part.
        public var weightRepetition = 0.5
        public var weightLoudness = 0.25
        public var weightVocal = 0.25
        /// A candidate must repeat: its best match elsewhere has a mean bar similarity of at least this.
        public var minRepetition = 0.5
        /// A shorter candidate is kept beside a longer one that holds it only when it is stronger by more than this,
        /// so an 8-bar chorus is not cut to the 4 bars that score a hair higher.
        public var shortMargin = 0.05
        /// A candidate is `sung` when at least this share of its beats is inside a vocal span.
        public var sungShare = 0.5
        /// At most this many candidates.
        public var maxHooks = 3

        public init() {}

        /// The engine's parameters.
        public static let standard = Parameters()
    }

    /// One candidate: bars `startBar ..< endBar` (1-based, the end a bar line).
    public struct Candidate: Sendable, Equatable {
        public var startBar: Int
        public var endBar: Int
        /// 0 to 1, from the three terms below.
        public var strength: Double
        public var sung: Bool
        /// The mean bar similarity to its best match elsewhere in the track, clipped to 0 to 1.
        public var repetition: Double
        /// The stretch's mean bar loudness between the track's 10th and 90th percentile bar loudness (at least 1 LU
        /// apart), clipped to 0 to 1.
        public var loudness: Double
        /// The share of its beats inside a vocal span.
        public var vocalDensity: Double
        /// Where its best match starts (1-based): the same hook again, which is why it is not a candidate of its own.
        public var repeatStartBar: Int

        public var bars: Int { endBar - startBar }

        public init(startBar: Int, endBar: Int, strength: Double, sung: Bool, repetition: Double, loudness: Double,
                    vocalDensity: Double, repeatStartBar: Int) {
            self.startBar = startBar; self.endBar = endBar; self.strength = strength; self.sung = sung
            self.repetition = repetition; self.loudness = loudness; self.vocalDensity = vocalDensity
            self.repeatStartBar = repeatStartBar
        }
    }

    public var parameters: Parameters
    /// The lattice the candidates start on (`Phrase.latticePhaseBar`).
    public var latticePhaseBar: Int
    /// Strongest first, none overlapping another or another's repeat.
    public var candidates: [Candidate]

    /// The candidates from the bar-by-bar similarity (`barSimilarity`, n x n row-major), the per-bar loudness `lufs`
    /// (LUFS), each bar's vocal coverage (0 to 1) and the phrase lattice.
    public init(barSimilarity sim: [Double], lufs: [Double], vocalCoverage: [Double], latticePhaseBar: Int,
                parameters: Parameters = .standard) {
        let n = lufs.count
        precondition(sim.count == n * n && vocalCoverage.count == n,
                     "\(sim.count) similarities and \(vocalCoverage.count) coverages for \(n) bars")
        self.parameters = parameters
        self.latticePhaseBar = latticePhaseBar
        guard n > 0 else { candidates = []; return }
        let p10 = Py.percentile(lufs, 10), p90 = Py.percentile(lufs, 90)
        let range = max(p90 - p10, 1.0)
        let weights = parameters.weightRepetition + parameters.weightLoudness + parameters.weightVocal

        var all: [Candidate] = []
        for length in parameters.lengthsBars where length >= 1 && length <= n {
            for s in 0...(n - length) where Py.mod(s + 1 - latticePhaseBar, max(parameters.stepBars, 1)) == 0 {
                // The best match: the window elsewhere, not overlapping this one, whose bars are most like this one's,
                // bar for bar.
                var best = -Double.infinity, bestAt = -1
                for t in 0...(n - length) where abs(t - s) >= length {
                    var m = 0.0
                    for i in 0..<length { m += sim[(s + i) * n + t + i] }
                    m /= Double(length)
                    if m > best { best = m; bestAt = t }
                }
                guard bestAt >= 0, best >= parameters.minRepetition else { continue }
                let repetition = min(max(best, 0), 1)
                let loudness = min(max((Py.mean(Array(lufs[s..<(s + length)])) - p10) / range, 0), 1)
                let vocal = Py.mean(Array(vocalCoverage[s..<(s + length)]))
                let strength = (parameters.weightRepetition * repetition + parameters.weightLoudness * loudness
                                + parameters.weightVocal * vocal) / weights
                all.append(Candidate(startBar: s + 1, endBar: s + length + 1, strength: strength,
                                     sung: vocal >= parameters.sungShare, repetition: repetition, loudness: loudness,
                                     vocalDensity: vocal, repeatStartBar: bestAt + 1))
            }
        }
        // A shorter candidate yields to a longer one holding it unless clearly stronger.
        let pool = all.filter { c in
            !all.contains { o in
                o.bars > c.bars && o.startBar <= c.startBar && o.endBar >= c.endBar
                    && o.strength >= c.strength - parameters.shortMargin
            }
        }
        let ordered = pool.sorted {
            ($0.strength, $0.bars, -$0.startBar) > ($1.strength, $1.bars, -$1.startBar)
        }
        // Strongest first; a candidate overlapping one already taken, or that one's repeat, is the same hook.
        var taken: [Candidate] = []
        func overlaps(_ a: Int, _ b: Int, _ c: Int, _ d: Int) -> Bool { a < d && c < b }
        for c in ordered where taken.count < parameters.maxHooks {
            let clash = taken.contains { t in
                overlaps(c.startBar, c.endBar, t.startBar, t.endBar)
                    || overlaps(c.startBar, c.endBar, t.repeatStartBar, t.repeatStartBar + t.bars)
            }
            if !clash { taken.append(c) }
        }
        candidates = taken
    }

    /// Per-bar features for the repetition: the frame-wise MFCC (`SpectralFeatures.mfcc`) averaged over each bar
    /// (`FooteNovelty.segmentMeans` on every eighth of the novelty's half-beat frame edges, `FooteNovelty.frameEdges`),
    /// with the first coefficient left out (the overall level, which the loudness term weighs on its own) and each
    /// other coefficient centred on its mean over the track, so the comparison sees how bars differ rather than the
    /// timbre they all share. One frame per bar, 12 rows.
    public static func barFeatures(mfcc: FrameMatrix, halfBeatEdges edges: [Int]) -> FrameMatrix {
        let perBar = FooteNovelty.framesPerBar
        precondition(edges.count >= perBar + 1 && (edges.count - 1) % perBar == 0, "\(edges.count) half-beat edges")
        let barEdges = stride(from: 0, to: edges.count, by: perBar).map { edges[$0] }
        let means = FooteNovelty.segmentMeans(mfcc, edges: barEdges)
        let n = means.frames, rows = max(means.rows - 1, 0)
        var out = [Double](repeating: 0, count: n * rows)
        for r in 0..<rows {
            let column = means.row(r + 1)
            let centre = Py.mean(column)
            for b in 0..<n { out[b * rows + r] = column[b] - centre }
        }
        return FrameMatrix(frames: n, rows: rows, values: out)
    }

    /// Bar-by-bar similarity of `barFeatures`: the cosine of each pair's feature vectors (`FooteNovelty.mfccSimilarity`),
    /// -1 to 1, n x n row-major.
    public static func barSimilarity(_ features: FrameMatrix) -> [Double] {
        FooteNovelty.mfccSimilarity(features)
    }
}
