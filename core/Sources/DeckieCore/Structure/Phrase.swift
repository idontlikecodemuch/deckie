import Foundation

/// A novelty peak snapped to a bar line: `bar` is the 1-based bar that starts at the peak (the lab writes
/// `novelty_peaks` as `[bar, value]` pairs this way), `value` the Foote novelty there.
public struct NoveltyPeak: Sendable, Equatable {
    public var bar: Int
    public var value: Double
    public init(bar: Int, value: Double) {
        self.bar = bar
        self.value = value
    }
}

/// The 8-bar phrase lattice: the phase (bar position within 8) carrying the most novelty, how much it stands out, and
/// the phase used for snapping mix windows. The lab's `phrase` (mixer/analyze.py, structure). Bars are 1-based.
public struct Phrase: Sendable, Equatable {
    /// Phrases are taken to be 8 bars long.
    public static let length = 8
    /// Below this confidence the snapping lattice falls back to phrases starting on bar 1.
    public static let snapConfidence = 0.35

    /// The first bar of the lattice with the largest summed novelty (1 to 8).
    public var latticePhaseBar: Int
    /// Always 8.
    public var phraseLenBars: Int
    /// 0.6 x the lattice's share of all peak novelty + 0.4 x its margin over the runner-up phase, relative to its own
    /// sum, clipped to 0...1 (the lab writes it to 3 decimals).
    public var confidence: Double
    /// Summed peak novelty for each of the 8 phases, phase 1 first (3 decimals in the file).
    public var phaseNovelty: [Double]
    /// `latticePhaseBar` when `confidence >= 0.35`, otherwise 1.
    public var snapPhaseBar: Int

    public init(latticePhaseBar: Int, phraseLenBars: Int = Phrase.length, confidence: Double, phaseNovelty: [Double],
                snapPhaseBar: Int) {
        self.latticePhaseBar = latticePhaseBar
        self.phraseLenBars = phraseLenBars
        self.confidence = confidence
        self.phaseNovelty = phaseNovelty
        self.snapPhaseBar = snapPhaseBar
    }

    /// The phrase lattice from novelty peaks: their values summed by phase, then `init(phaseNovelty:)`. The peaks are
    /// the ones the lab keeps: at most one per bar, on bars 2 to `nBars` (none on bar 1 or the end line).
    public init(peaks: [NoveltyPeak]) {
        self.init(phaseNovelty: Phrase.phaseNovelty(peaks: peaks))
    }

    /// The phrase lattice from the 8 summed phase novelties. The phase is the first largest sum (numpy's argmax);
    /// with no novelty at all it is bar 1 and the confidence 0.
    public init(phaseNovelty sums: [Double]) {
        precondition(sums.count == Phrase.length, "phase novelty needs 8 sums, got \(sums.count)")
        let total = Py.pairwiseSum(sums)
        var phase = 0
        var conf = 0.0
        if total > 0 {
            for i in 1..<sums.count where sums[i] > sums[phase] { phase = i }
            let srt = sums.sorted(by: >)
            let share = srt[0] / total
            // The lab's expression, evaluated in its order: 0.6 * share + (0.4 * (top - second)) / (top + 1e-9).
            conf = min(max(0.6 * share + 0.4 * (srt[0] - srt[1]) / (srt[0] + 1e-9), 0), 1)
        }
        self.init(latticePhaseBar: phase + 1, confidence: conf, phaseNovelty: sums,
                  snapPhaseBar: conf >= Phrase.snapConfidence ? phase + 1 : 1)
    }

    /// Summed novelty per phase: peak at 1-based bar b adds its value to phase `(b - 1) % 8`. Values are added in the
    /// order given (the lab adds them strongest first; any order differs only in the last bits).
    public static func phaseNovelty(peaks: [NoveltyPeak]) -> [Double] {
        var sums = [Double](repeating: 0, count: length)
        for p in peaks { sums[Py.mod(p.bar - 1, length)] += p.value }
        return sums
    }

    /// The peaks on the lattice that starts at `latticePhaseBar`, as sorted, distinct 1-based bars (the lab's `bset`;
    /// the mix windows extend to these when the vocal-free stretch is short).
    public static func onLatticeBars(peaks: [NoveltyPeak], latticePhaseBar: Int) -> [Int] {
        let phase = latticePhaseBar - 1
        return Array(Set(peaks.map { $0.bar - 1 }.filter { Py.mod($0, length) == phase })).sorted().map { $0 + 1 }
    }

    /// Section boundaries, the lab's `boundaries_bars`: bar 1, the on-lattice peaks and the end line (`nBars + 1`),
    /// sorted and distinct, 1-based.
    public static func boundaries(peaks: [NoveltyPeak], latticePhaseBar: Int, nBars: Int) -> [Int] {
        let inner = onLatticeBars(peaks: peaks, latticePhaseBar: latticePhaseBar).map { $0 - 1 }
        return Array(Set([0] + inner + [nBars])).sorted().map { $0 + 1 }
    }
}
