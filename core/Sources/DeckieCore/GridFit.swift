import Foundation

/// A constant 4/4 beat grid fitted to detected beat times: the lab's "grid" (mixer/analyze.py, fit_grid and the
/// functions under "grid fit"). Times are seconds.
public struct GridFit: Sendable, Equatable {
    /// Tempo in beats per minute (60 / period).
    public var bpm: Double
    /// Seconds between beats.
    public var period: Double
    /// Time of the grid's reference beat; every grid beat is `t0 + k * period`.
    public var t0: Double
    /// Time of the first grid downbeat (the beat phase, of four, that most detected downbeats fall on).
    public var firstDownbeat: Double
    /// Median distance between a detected beat and the nearest grid beat, in milliseconds.
    public var fitMadMs: Double
    /// Share of detected beats within 70 ms of the grid.
    public var inlierFrac: Double
    /// Share of detected downbeats that fall on the chosen downbeat phase.
    public var downbeatAgree: Double
    /// inlier_frac * (0.5 + 0.5 * downbeat_agree) * max(0, 1 - max(0, mad_ms - 5) / 50), clipped to 0...1.
    public var confidence: Double
    /// "irls" (whole-track robust line fit) or "windows" (median tempo of trusted 20 s windows).
    public var method: String
    /// From the windows estimator when it ran, whichever method won.
    public var trustedWindows: Int?
    public var periodSpreadPct: Double?
}

public enum BeatGrid {
    /// Period of one window of beats: cumulative integer indexing (robust to the 20 ms frame quantisation of the
    /// median interval) plus least squares with residual rejection. Port of `_win_fit`.
    /// Returns the period, the median absolute residual of the kept beats in ms, and how many beats were kept.
    public static func windowFit(_ beats: [Double]) -> (period: Double, madMs: Double, kept: Int)? {
        let b = beats.sorted()
        if b.count < 8 { return nil }
        var g = [Double](repeating: 0, count: b.count - 1)
        for i in 0..<g.count { g[i] = b[i + 1] - b[i] }
        let med = Py.median(g)
        if med <= 0 { return nil }
        var idx = [Double](repeating: 0, count: b.count)
        var acc = 0.0
        for i in 0..<g.count {
            acc += Py.roundEven(g[i] / med)
            idx[i + 1] = acc
        }
        var keep = [Bool](repeating: true, count: b.count)
        var P = med, off = b[0]
        var res = [Double](repeating: 0, count: b.count)
        for _ in 0..<3 {
            let nKeep = keep.lazy.filter { $0 }.count
            if nKeep < 8 { return nil }
            // Ordinary least squares of b on [idx, 1] over the kept beats (numpy.linalg.lstsq).
            var sxx = 0.0, sx = 0.0, sxy = 0.0, sy = 0.0, n = 0.0
            for i in 0..<b.count where keep[i] {
                sxx += idx[i] * idx[i]; sx += idx[i]; sxy += idx[i] * b[i]; sy += b[i]; n += 1
            }
            let det = sxx * n - sx * sx
            P = (sxy * n - sx * sy) / det
            off = (sxx * sy - sx * sxy) / det
            for i in 0..<b.count { res[i] = b[i] - (off + P * idx[i]) }
            for i in 0..<b.count { idx[i] += Py.roundEven(res[i] / P) }
            for i in 0..<b.count { res[i] = b[i] - (off + P * idx[i]) }
            for i in 0..<b.count { keep[i] = abs(res[i]) < 0.25 * P }
        }
        var keptRes: [Double] = []
        for i in 0..<b.count where keep[i] { keptRes.append(abs(res[i])) }
        return (P, Py.median(keptRes) * 1000, keptRes.count)
    }

    /// Period = median of the periods of trusted 20 s windows; phase = circular mean of the beat phases.
    /// Port of `_period_phase_windows`. Nil when fewer than three windows are trusted.
    public static func periodPhaseWindows(_ b: [Double], window: Double = 20.0)
        -> (period: Double, phase: Double, trustedWindows: Int, periodSpreadPct: Double)? {
        var per: [Double] = []
        var t = b[0]
        let tEnd = b[b.count - 1]
        while t < tEnd - window * 0.6 {
            let slice = b.filter { $0 >= t && $0 < t + window }
            if let r = windowFit(slice), r.madMs <= 15, r.kept >= 16 { per.append(r.period) }
            t += window
        }
        if per.count < 3 { return nil }
        let P = Py.median(per)
        var sumCos = 0.0, sumSin = 0.0
        for x in b {
            let ph = Py.fmod(x, P) / P * 2 * Double.pi
            sumCos += cos(ph); sumSin += sin(ph)
        }
        let phase = atan2(sumSin / Double(b.count), sumCos / Double(b.count)) / (2 * Double.pi) * P
        let spread = (per.max()! - per.min()!) / P * 100
        return (P, phase, per.count, Py.round(spread, 2))
    }

    /// The original whole-track L1 fit with incremental integer indexing: IRLS, iteratively reweighted least
    /// squares, which keeps pulling the line towards the majority of beats and away from stray ones.
    /// Port of `_period_phase_irls`. Returns the period and the reference time `t0`.
    public static func periodPhaseIRLS(_ b: [Double]) -> (period: Double, t0: Double) {
        var ibi = [Double](repeating: 0, count: b.count - 1)
        for i in 0..<ibi.count { ibi[i] = b[i + 1] - b[i] }
        var P = Py.median(ibi)
        var k: [Double] = [0]
        var keep: [Int] = [0]
        for i in 1..<b.count {
            let step = Int(Py.roundEven((b[i] - b[keep[keep.count - 1]]) / P))
            if step <= 0 { continue }
            k.append(k[k.count - 1] + Double(step))
            keep.append(i)
        }
        let bb = keep.map { b[$0] }
        var kk = k
        var t0 = bb[0]
        for it in 0..<12 {
            // Weighted least squares of bb on [1, kk] with weights 1 / max(|residual|, 1 ms), capped at 1000:
            // numpy solves the 2x2 normal equations (Wa.T @ A) sol = Wa.T @ bb; so does this, by Cramer's rule.
            var sw = 0.0, swk = 0.0, swkk = 0.0, swb = 0.0, swkb = 0.0
            for i in 0..<bb.count {
                let res = bb[i] - (t0 + kk[i] * P)
                let w = min(1.0 / max(abs(res), 1e-3), 1e3)
                sw += w; swk += w * kk[i]; swkk += w * kk[i] * kk[i]; swb += w * bb[i]; swkb += w * kk[i] * bb[i]
            }
            let det = sw * swkk - swk * swk
            t0 = (swb * swkk - swk * swkb) / det
            P = (sw * swkb - swk * swb) / det
            if it == 3 || it == 7 {
                for i in 0..<bb.count { kk[i] = Py.roundEven((bb[i] - t0) / P) }
            }
        }
        return (P, t0)
    }

    /// Scores a candidate grid (period, t0) against the detected beats and downbeats. Port of `_grid_eval`.
    public static func evaluate(beats b: [Double], downbeats: [Double], period P: Double, t0: Double,
                                method: String = "") -> GridFit {
        var absr = [Double](repeating: 0, count: b.count)
        var inliers = 0
        for i in 0..<b.count {
            absr[i] = abs(b[i] - (t0 + Py.roundEven((b[i] - t0) / P) * P))
            if absr[i] < 0.07 { inliers += 1 }
        }
        let madMs = Py.median(absr) * 1000
        let inlier = Double(inliers) / Double(b.count)
        var j = 0
        var dbAgree = 0.0
        if downbeats.count >= 2 {
            var counts = [0, 0, 0, 0]
            for d in downbeats {
                let idx = Int(Py.roundEven((d - t0) / P))
                if abs(d - (t0 + Double(idx) * P)) < 0.25 * P { counts[Py.mod(idx, 4)] += 1 }
            }
            for c in 1..<4 where counts[c] > counts[j] { j = c }
            dbAgree = Double(counts[j]) / Double(max(1, downbeats.count))
        }
        let conf = inlier * (0.5 + 0.5 * dbAgree) * max(0.0, 1 - max(0.0, madMs - 5) / 50)
        return GridFit(bpm: 60.0 / P, period: P, t0: t0, firstDownbeat: t0 + Double(j) * P,
                       fitMadMs: madMs, inlierFrac: inlier, downbeatAgree: dbAgree,
                       confidence: min(max(conf, 0), 1), method: method, trustedWindows: nil, periodSpreadPct: nil)
    }

    /// Constant 4/4 grid from detected beats. Two estimators are tried (the whole-track IRLS fit, and the median
    /// of trusted 20 s window periods, which survives doubled beats and coarse medians); the one that puts more
    /// detected beats within 70 ms of the grid wins, then the lower median error. Port of `fit_grid`.
    /// Nil with fewer than 16 beats.
    public static func fit(beats: [Double], downbeats: [Double]) -> GridFit? {
        let b = beats.sorted()
        if b.count < 16 { return nil }
        let (P, t0) = periodPhaseIRLS(b)
        var best = evaluate(beats: b, downbeats: downbeats, period: P, t0: t0, method: "irls")
        if let w = periodPhaseWindows(b) {
            let alt = evaluate(beats: b, downbeats: downbeats, period: w.period, t0: w.phase, method: "windows")
            let keyBest = (-Py.round(best.inlierFrac, 3), best.fitMadMs)
            let keyAlt = (-Py.round(alt.inlierFrac, 3), alt.fitMadMs)
            if keyAlt < keyBest { best = alt }
            best.trustedWindows = w.trustedWindows
            best.periodSpreadPct = w.periodSpreadPct
        }
        return best
    }
}
