import Foundation

/// The lab's two-band split and its per-bar levels: `lr4` in mixer/analyze.py, a second-order Butterworth section
/// applied twice in series (a fourth-order Linkwitz-Riley response), low-pass at 150 Hz and high-pass at 4 kHz, run on
/// the mono signal; then for each bar `low_db` and `high_db`, the mean square of the filtered signal over the bar, in
/// dB:
///
///   low = lr4(mono.astype(np.float64), 150, "low");  high = lr4(mono.astype(np.float64), 4000, "high")
///   for a, b2 in zip(bi[:-1], bi[1:]):                    # bi = np.round(bar_t * SR).astype(int)
///       low_db.append(db(np.mean(low[a:b2] ** 2)))        # db(x) = max(-120, 10 log10(max(x, 1e-30)))
///       high_db.append(db(np.mean(high[a:b2] ** 2)))
///
/// The section is the one `scipy.signal.butter(2, fc, btype, fs=rate, output="sos")` designs (the analogue prototype's
/// poles -exp(+-i pi / 4), the cutoff pre-warped to 4 tan(pi (fc / (rate / 2)) / 2), the bilinear transform with
/// scipy's own operations, complex division as numpy does it), and it runs as `scipy.signal.sosfilt` runs it from
/// rest, in double precision in sosfilt's order of operations:
///
///   y = b0 x + z1;  z1 = (b1 x - a1 y) + z2;  z2 = b2 x - a2 y
///
/// At the lab's 44.1 kHz (and at 48 kHz) the coefficients are scipy's to the last bit, and so is the filtered signal;
/// the lab's rate is 44.1 kHz (it resamples everything to it first), other rates design the same filters for theirs.
/// The per-bar mean is a plain double-precision sum, within about 1e-15 of numpy's pairwise one. A bar past the end
/// of the signal holds no samples: numpy's mean of an empty slice is NaN, which the lab's `db` turns into -120.
public struct BandSplit: Sendable, Equatable {
    /// The lab's cutoffs in Hz.
    public static let lowCutoff = 150.0, highCutoff = 4000.0

    public let sampleRate: Int
    /// The low-pass section (applied twice).
    public let lowPass: Biquad
    /// The high-pass section (applied twice).
    public let highPass: Biquad

    public init(sampleRate: Int, lowCutoff: Double = BandSplit.lowCutoff, highCutoff: Double = BandSplit.highCutoff) {
        self.sampleRate = sampleRate
        lowPass = BandSplit.butterworth(cutoff: lowCutoff, sampleRate: Double(sampleRate), highPass: false)
        highPass = BandSplit.butterworth(cutoff: highCutoff, sampleRate: Double(sampleRate), highPass: true)
    }

    /// `scipy.signal.butter(2, cutoff, btype="low" or "high", fs=sampleRate, output="sos")`, its one section, computed
    /// with the operations scipy uses (buttap, lp2lp_zpk or lp2hp_zpk, bilinear_zpk, zpk2sos), so the coefficients are
    /// scipy's to the last bit (checked at 4,800 random cutoffs from 5 Hz to 0.49 of the rate, at eight rates from 8 to
    /// 96 kHz: all but 30 identical, those within 9e-16, all with cutoffs near the Nyquist frequency).
    public static func butterworth(cutoff: Double, sampleRate fs: Double, highPass: Bool) -> Biquad {
        // numpy's complex division (Smith's method) and multiplication.
        func div(_ ar: Double, _ ai: Double, _ br: Double, _ bi: Double) -> (Double, Double) {
            if abs(br) >= abs(bi) {
                let rat = bi / br, scl = 1.0 / (br + bi * rat)
                return ((ar + ai * rat) * scl, (ai - ar * rat) * scl)
            }
            let rat = br / bi, scl = 1.0 / (bi + br * rat)
            return ((ar * rat + ai) * scl, (ai * rat - ar) * scl)
        }
        func mul(_ ar: Double, _ ai: Double, _ br: Double, _ bi: Double) -> (Double, Double) {
            (ar * br - ai * bi, ar * bi + ai * br)
        }
        let wn = cutoff / (fs / 2)
        let warped = 2 * 2.0 * tan(Double.pi * wn / 2.0)
        // buttap(2): p = -exp(i pi m / 4) for m = -1, 1.
        let x = Double.pi * -1.0 / 4.0
        let p0 = (-cos(x), -sin(x)), p1 = (-cos(-x), -sin(-x))
        var poles: [(Double, Double)], k: Double, zeroProduct: Double
        if highPass {
            poles = [div(warped, 0, p0.0, p0.1), div(warped, 0, p1.0, p1.1)]
            let q = mul(-p0.0, -p0.1, -p1.0, -p1.1)
            k = 1.0 * div(1.0, 0, q.0, q.1).0
            zeroProduct = (4.0 - 0.0) * (4.0 - 0.0)  // two zeros at s = 0
        } else {
            poles = [(warped * p0.0, warped * p0.1), (warped * p1.0, warped * p1.1)]
            k = 1.0 * (warped * warped)
            zeroProduct = 1.0  // no finite zeros
        }
        // The bilinear transform with fs2 = 2 * 2.0.
        let pz = poles.map { div(4.0 + $0.0, $0.1, 4.0 - $0.0, -$0.1) }
        let den = mul(4.0 - poles[0].0, -poles[0].1, 4.0 - poles[1].0, -poles[1].1)
        let kz = k * div(zeroProduct, 0, den.0, den.1).0
        let (pr, pi) = pz[0].1 > 0 ? pz[0] : pz[1]
        let a1 = -pr - pr, a2 = pr * pr + pi * pi
        return Biquad(b0: kz, b1: kz * (highPass ? -2.0 : 2.0), b2: kz, a1: a1, a2: a2)
    }

    /// `x` through `section` twice, from rest, as `sosfilt(sos, sosfilt(sos, x))`: the lab's `lr4`.
    public static func lr4(_ x: [Double], section: Biquad) -> [Double] {
        var out = [Double](repeating: 0, count: x.count)
        x.withUnsafeBufferPointer { xb in
            out.withUnsafeMutableBufferPointer { ob in
                var f = Cascade(section)
                for i in 0..<xb.count { ob[i] = f.step(xb[i]) }
            }
        }
        return out
    }

    /// The low band of a mono signal: `lr4(mono.astype(np.float64), 150, "low")`.
    public func low(_ mono: [Float]) -> [Double] { BandSplit.lr4(mono.map(Double.init), section: lowPass) }

    /// The high band of a mono signal: `lr4(mono.astype(np.float64), 4000, "high")`.
    public func high(_ mono: [Float]) -> [Double] { BandSplit.lr4(mono.map(Double.init), section: highPass) }

    /// The per-bar levels in dB.
    public struct Levels: Sendable, Equatable {
        /// The lab's `low_db`: the mean square of the low band over each bar, in dB (never below -120).
        public var lowDB: [Double]
        /// The lab's `high_db`.
        public var highDB: [Double]

        public init(lowDB: [Double], highDB: [Double]) {
            self.lowDB = lowDB
            self.highDB = highDB
        }
    }

    /// The per-bar levels of a mono signal (the lab's `mono`, the channels' float32 mean, `AudioBuffer.mono()`), for
    /// bars whose first frames are `barFrames` (bar k spans `barFrames[k]..<barFrames[k + 1]`, so one more frame than
    /// bars; non-decreasing, never negative). A span is cut at the end of the signal like a numpy slice; an empty one
    /// gives -120. One pass: each sample goes through the four sections once and its squares are added to its bar.
    public func levels(_ mono: [Float], barFrames: [Int]) -> Levels {
        let bars = max(0, barFrames.count - 1)
        precondition(barFrames.first.map { $0 >= 0 } ?? true, "a bar starts before the first frame")
        precondition(zip(barFrames, barFrames.dropFirst()).allSatisfy { $0 <= $1 }, "bar frames must not decrease")
        var lowSum = [Double](repeating: 0, count: bars), highSum = [Double](repeating: 0, count: bars)
        let n = mono.count
        let end = min(n, barFrames.last ?? 0)  // nothing after the last bar is needed
        mono.withUnsafeBufferPointer { xb in
            var lo = Cascade(lowPass), hi = Cascade(highPass)
            var i = 0, bar = -1
            var next = barFrames.first ?? end  // where the next bar starts
            var ls = 0.0, hs = 0.0
            while i < end {
                // Move to the bar holding sample i (empty bars are skipped and keep 0).
                if i >= next {
                    if bar >= 0 { lowSum[bar] = ls; highSum[bar] = hs }
                    ls = 0; hs = 0
                    bar += 1
                    while bar + 1 < barFrames.count && barFrames[bar + 1] <= i { bar += 1 }
                    next = bar + 1 < barFrames.count ? barFrames[bar + 1] : end
                }
                let v = Double(xb[i])
                let l = lo.step(v), h = hi.step(v)
                ls += l * l
                hs += h * h
                i += 1
            }
            if bar >= 0 && bar < bars { lowSum[bar] = ls; highSum[bar] = hs }
        }
        var levels = Levels(lowDB: [], highDB: [])
        for k in 0..<bars {
            let a = min(barFrames[k], n), b = min(barFrames[k + 1], n)
            if b > a {
                levels.lowDB.append(LoudnessMath.db(lowSum[k] / Double(b - a)))
                levels.highDB.append(LoudnessMath.db(highSum[k] / Double(b - a)))
            } else {
                levels.lowDB.append(-120)
                levels.highDB.append(-120)
            }
        }
        return levels
    }

    /// The per-bar levels for bar lines in seconds (`BarGrid.barTimes`), each turned into a frame as the lab does,
    /// `np.round(bar_t * SR).astype(int)` (half to even).
    public func levels(_ mono: [Float], barTimes: [Double]) -> Levels {
        levels(mono, barFrames: barTimes.map { Int(Py.roundEven($0 * Double(sampleRate))) })
    }

    /// A section applied twice, in sosfilt's order of operations, from rest.
    struct Cascade {
        let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
        var s0 = 0.0, s1 = 0.0, t0 = 0.0, t1 = 0.0

        init(_ q: Biquad) { b0 = q.b0; b1 = q.b1; b2 = q.b2; a1 = q.a1; a2 = q.a2 }

        @inline(__always) mutating func step(_ x: Double) -> Double {
            let y = b0 * x + s0
            s0 = b1 * x - a1 * y + s1
            s1 = b2 * x - a2 * y
            let z = b0 * y + t0
            t0 = b1 * y - a1 * z + t1
            t1 = b2 * y - a2 * z
            return z
        }
    }
}
