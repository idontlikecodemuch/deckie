import Foundation

/// The lab's rhythm fingerprint, `onset_pattern_16` (mixer/analyze.py, "onset pattern"; mixer/README.md): the onset
/// strength's largest value in each eighth-note cell (8 cells a bar, the same half-beat edges as the novelty), laid out
/// as two bars of 8 cells, averaged over the bar pairs that sound (bars 1-2, 3-4, ... whose quieter bar is within
/// 10 LU of the median bar loudness), and scaled to a maximum of 1. The pair scoring compares these 16 values between
/// tracks (`rhythm`).
public enum OnsetPattern {
    /// Cells per bar: eighth notes.
    public static let cellsPerBar = 8
    /// A bar pair counts when its quieter bar is louder than the median bar less this (LU).
    public static let quietPairLU = 10.0

    /// The lab's `cellv`: for each of the nBars * 8 cells, the largest onset strength over frames
    /// a ..< max(a + 1, b), a and b the cell's edges as STFT frames (`FooteNovelty.frameEdges`, clipped to the
    /// envelope's length).
    public static func cellValues(onsetEnvelope env: [Double], grid: BarGrid,
                                  framesPerSecond: Double = SpectralFeatures.framesPerSecond) -> [Double] {
        let edges = FooteNovelty.frameEdges(grid: grid, framesPerSecond: framesPerSecond, frameCount: env.count)
        return (0..<(edges.count - 1)).map { s in
            let a = edges[s], b = max(a + 1, edges[s + 1])
            return env[a..<b].max()!
        }
    }

    /// The 16 values from the cell values (8 per bar) and the per-bar loudness (`lufs_st`, one value per bar): the
    /// cells of bars 2i and 2i + 1 (0-based) form row i, for i < nBars / 2 (an odd last bar is left out); the rows
    /// whose two bars are both louder than median - 10 LU are averaged cell by cell (all rows when none is), added row
    /// after row as numpy's mean down the first axis does; then the 16 values are divided by their maximum plus 1e-9.
    public static func pattern(cellValues cells: [Double], barLoudness lufs: [Double]) -> [Double] {
        let nBars = lufs.count
        precondition(cells.count == nBars * cellsPerBar, "\(cells.count) cells for \(nBars) bars")
        let pairs = nBars / 2
        precondition(pairs >= 1, "the onset pattern needs at least two bars")
        let body = Py.median(lufs)
        let keep = (0..<pairs).filter { min(lufs[2 * $0], lufs[2 * $0 + 1]) > body - quietPairLU }
        let rows = keep.isEmpty ? Array(0..<pairs) : keep
        var pat = [Double](repeating: 0, count: 16)
        for c in 0..<16 {
            var s = 0.0
            for r in rows { s += cells[r * 16 + c] }
            pat[c] = s / Double(rows.count)
        }
        let d = pat.max()! + 1e-9
        return pat.map { $0 / d }
    }

    /// `pattern` from the onset envelope (`SpectralFeatures.onsetEnvelope`), the bar grid and the per-bar loudness.
    public static func pattern(onsetEnvelope env: [Double], grid: BarGrid, barLoudness lufs: [Double],
                               framesPerSecond: Double = SpectralFeatures.framesPerSecond) -> [Double] {
        pattern(cellValues: cellValues(onsetEnvelope: env, grid: grid, framesPerSecond: framesPerSecond),
                barLoudness: lufs)
    }
}

/// The lab's per-bar `onset_density` (mixer/analyze.py, per-bar loop; mixer/README.md, "Loudness"): librosa's onsets
/// (`OnsetDetect.times`) counted in each bar and divided by 4, so onsets per beat.
public enum OnsetDensity {
    /// `numpy.histogram(onsetTimes, bins=barTimes)[0] / 4`: bar k counts the onsets at or after bar line k and before
    /// line k + 1, except the last bar, which also counts an onset exactly on the end line; onsets before bar 1 or
    /// after the end are not counted.
    public static func perBar(onsetTimes: [Double], barTimes: [Double]) -> [Double] {
        precondition(barTimes.count >= 2, "at least one bar")
        let t = onsetTimes.sorted()
        let last = barTimes.count - 1
        var cum = barTimes.prefix(last).map { Py.countBelow($0, in: t) }
        cum.append(Py.countAtMost(barTimes[last], in: t))
        return (0..<last).map { Double(cum[$0 + 1] - cum[$0]) / 4.0 }
    }

    /// The onsets of `envelope` (`OnsetDetect.times`) per bar of `grid`.
    public static func perBar(onsetEnvelope env: [Double], grid: BarGrid, sampleRate: Int = SpectralFeatures.sampleRate,
                              hop: Int = SpectralFeatures.hop) -> [Double] {
        perBar(onsetTimes: OnsetDetect.times(envelope: env, sampleRate: sampleRate, hop: hop), barTimes: grid.barTimes)
    }
}
