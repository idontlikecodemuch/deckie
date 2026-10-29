import Foundation

/// A tagger's patch-by-patch values averaged into bars, exactly as the lab averages its Discogs-EffNet voice
/// probabilities (mixer/analyze.py, "vocal probability + embedding"): patch k is centred at
/// `centreOffset + k hop` seconds; a bar's value is the mean of the patches whose centres fall in it
/// (`bar start <= centre < bar end`), or, when none does, the patches' values linearly interpolated at the bar's middle
/// (numpy's `interp`: the first value before the first centre, the last after the last). The lab's EffNet patches
/// have hop 0.992 s and offset 1.024 s; YAMNet's have 0.48 and 0.4875 (`YAMNetFrontEnd`).
public enum PatchBars {
    /// One value per bar of `barTimes` (bar lines in seconds, one more than there are bars). With no patches every bar
    /// is 0 (the lab never has none: its audio is always longer than a patch).
    public static func average(_ values: [Double], hop: Double, centreOffset: Double, barTimes: [Double]) -> [Double] {
        let bars = max(barTimes.count - 1, 0)
        guard !values.isEmpty else { return [Double](repeating: 0, count: bars) }
        let n = values.count
        let centres = (0..<n).map { Double($0) * hop + centreOffset }
        var out = [Double](repeating: 0, count: bars)
        var first = 0  // the first patch whose centre is not before the bar (the bars are in order)
        for b in 0..<bars {
            let a = barTimes[b], e = barTimes[b + 1]
            while first < n && centres[first] < a { first += 1 }
            var k = first, sum = 0.0, count = 0
            while k < n && centres[k] < e { sum += values[k]; count += 1; k += 1 }
            out[b] = count > 0 ? sum / Double(count) : interpolate((a + e) / 2, centres, values)
        }
        return out
    }

    /// numpy's `interp(x, xp, fp)` for increasing `xp`: fp[0] at or before xp[0], fp[last] at or after xp[last],
    /// linear in between.
    public static func interpolate(_ x: Double, _ xp: [Double], _ fp: [Double]) -> Double {
        precondition(!xp.isEmpty && xp.count == fp.count)
        if x <= xp[0] { return fp[0] }
        if x >= xp[xp.count - 1] { return fp[fp.count - 1] }
        // The first xp[i] > x, then the segment xp[i - 1] ..< xp[i].
        var lo = 0, hi = xp.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if xp[mid] <= x { lo = mid } else { hi = mid }
        }
        let t = (x - xp[lo]) / (xp[hi] - xp[lo])
        return fp[lo] + t * (fp[hi] - fp[lo])
    }
}
