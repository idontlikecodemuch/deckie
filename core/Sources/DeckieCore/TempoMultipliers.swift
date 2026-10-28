import Foundation

/// Tempo relations between two tracks: 1 (same), 2 and 1/2 (double or half time), and the 2/3, 3/4, 4/3, 3/2
/// relations that need a transition track or a brake. Port of MULTIPLIERS, mult_dev and mult_label in
/// mixer/analyze.py and MULTS in mixer/score.py.
public enum Tempo {
    public static let multipliers: [Double] = [0.5, 2.0 / 3.0, 0.75, 1.0, 4.0 / 3.0, 1.5, 2.0]
    public static let octaveMultipliers: [Double] = [0.5, 1.0, 2.0]
    public static let labels: [(Double, String)] = [
        (0.5, "1/2"), (2.0 / 3.0, "2/3"), (0.75, "3/4"), (1.0, "1"), (4.0 / 3.0, "4/3"), (1.5, "3/2"), (2.0, "2"),
    ]

    /// The multiplier `m` among `among` with `bpm` closest to `reference * m` (smallest |log ratio|),
    /// and the remaining deviation in percent.
    public static func closest(bpm: Double, reference: Double, among: [Double] = multipliers)
        -> (multiplier: Double, deviationPct: Double) {
        var best: (Double, Double)? = nil
        for m in among {
            let d = abs(log(bpm / (reference * m)))
            if best == nil || d < best!.1 { best = (m, d) }
        }
        let (m, d) = best!
        return (m, (exp(d) - 1) * 100)
    }

    /// "1/2", "2/3", "3/4", "1", "4/3", "3/2", "2", or the number to three decimals.
    public static func label(_ m: Double) -> String {
        for (v, s) in labels where abs(m - v) < 1e-6 { return s }
        return Py.fixed(m, 3)
    }
}
