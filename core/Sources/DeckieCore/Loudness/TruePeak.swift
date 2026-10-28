import Foundation
import DeckieAudio

/// True peak as the lab measures it (mixer/analyze.py, `true_peak_db`): each channel oversampled four times with
/// `scipy.signal.resample_poly(x, 4, 1)` and its default filter, in 10 s blocks each widened by 64 samples on both
/// sides and oversampled on its own, and the largest absolute value found. The oversampled signal shows peaks that
/// fall between samples (ITU-R BS.1770-4, annex 2, asks for at least four times oversampling).
public enum TruePeak {
    /// The interpolation filter `resample_poly` designs for 4x upsampling by default: `firwin(81, 1/4,
    /// window=("kaiser", 5.0))` times 4. That is 81 taps (half length 10 * 4 = 40 each side of the centre), each
    /// h[k] = 1/4 sinc((k - 40) / 4) w[k] with sinc(x) = sin(pi x) / (pi x) and the Kaiser window
    /// w[k] = I0(5 sqrt(1 - ((k - 40) / 40)^2)) / I0(5), then scaled so the taps sum to 1, then by 4 (the upsampling
    /// factor, so the filtered signal keeps its level).
    public static let interpolationFilter: [Double] = {
        let half = 40, beta = 5.0, cutoff = 0.25
        let i0beta = besselI0(beta)
        var h = (0...(2 * half)).map { k -> Double in
            let m = Double(k - half)
            let y = Double.pi * (m == 0 ? 1e-20 : cutoff * m)  // numpy's sinc nudges 0 to 1e-20
            let r = m / Double(half)
            return cutoff * (sin(y) / y) * (besselI0(beta * (1 - r * r).squareRoot()) / i0beta)
        }
        let sum = h.reduce(0, +)
        for k in h.indices { h[k] = h[k] / sum * 4 }
        return h
    }()

    /// The largest absolute value of any channel oversampled four times, as a linear amplitude (1.0 is full scale).
    public static func peak(_ buffer: AudioBuffer) -> Double {
        let n = buffer.frames, ch = buffer.channelCount
        let hop = buffer.sampleRate * 10, pad = 64
        if n == 0 { return 0 }
        let h = interpolationFilter
        // Output 4q + p of a block x is sum over m of x[m] h[40 + 4q + p - 4m], with x zero outside the block (what
        // resample_poly's default zero padding amounts to). Phase p = 0 is the centre tap times x[q]: its other taps
        // fall on the zeros of the sinc, where floating-point sin(pi k) leaves about 1e-17 instead of 0, worth less
        // than the rounding of the sum, so they are left out. Phases 1 to 3 read the same 20 samples
        // w[i] = x[q - 9 + i], i = 0..<20, with taps h[40 + p - 4(i - 9)]. The filter is symmetric, so phase 3's
        // taps are phase 1's reversed and phase 2's are their own reverse. With u_j = w[j] + w[19 - j] and
        // v_j = w[j] - w[19 - j], j = 0..<10, and phase 1's taps p_i = h[77 - 4i]:
        //   phase 1 + phase 3 = sum (p_j + p_(19-j)) u_j,  phase 1 - phase 3 = sum (p_j - p_(19-j)) v_j,
        //   phase 2 = sum h[78 - 4j] u_j,
        // and max(|phase 1|, |phase 3|) = (|sum| + |difference|) / 2: 30 multiplications for three outputs
        // instead of 60. The loop is written out in full, with the taps in local constants, because it must also be
        // quick in a debug build, where Swift does not unroll or inline.
        func p(_ i: Int) -> Double { h[77 - 4 * i] }
        let s0 = p(0) + p(19), s1 = p(1) + p(18), s2 = p(2) + p(17), s3 = p(3) + p(16), s4 = p(4) + p(15)
        let s5 = p(5) + p(14), s6 = p(6) + p(13), s7 = p(7) + p(12), s8 = p(8) + p(11), s9 = p(9) + p(10)
        let d0 = p(0) - p(19), d1 = p(1) - p(18), d2 = p(2) - p(17), d3 = p(3) - p(16), d4 = p(4) - p(15)
        let d5 = p(5) - p(14), d6 = p(6) - p(13), d7 = p(7) - p(12), d8 = p(8) - p(11), d9 = p(9) - p(10)
        let e0 = h[78], e1 = h[74], e2 = h[70], e3 = h[66], e4 = h[62]
        let e5 = h[58], e6 = h[54], e7 = h[50], e8 = h[46], e9 = h[42]
        let centre = h[40]

        var peak = 0.0
        // One block's channel at a time, as doubles, with 10 zeros before and after so the edges need no checks.
        var scratch = [Double](repeating: 0, count: 10 + hop + 2 * pad + 10)
        buffer.samples.withUnsafeBufferPointer { sb in
            scratch.withUnsafeMutableBufferPointer { xb in
                let samples = sb.baseAddress!, x = xb.baseAddress!
                var start = 0
                while start < n {
                    let a = max(0, start - pad), b = min(start + hop + pad, n), len = b - a
                    for c in 0..<ch {
                        var src = samples + a * ch + c
                        var dst = x + 10
                        let stop = dst + len
                        while dst < stop {
                            dst.pointee = Double(src.pointee)
                            dst += 1
                            src += ch
                        }
                        (x + 10 + len).update(repeating: 0, count: 10)
                        var w = x + 1  // w[i] = x[q - 9 + i] for q = 0
                        let end = w + len
                        while w < end {
                            let u0 = w[0] + w[19], v0 = w[0] - w[19]
                            let u1 = w[1] + w[18], v1 = w[1] - w[18]
                            let u2 = w[2] + w[17], v2 = w[2] - w[17]
                            let u3 = w[3] + w[16], v3 = w[3] - w[16]
                            let u4 = w[4] + w[15], v4 = w[4] - w[15]
                            let u5 = w[5] + w[14], v5 = w[5] - w[14]
                            let u6 = w[6] + w[13], v6 = w[6] - w[13]
                            let u7 = w[7] + w[12], v7 = w[7] - w[12]
                            let u8 = w[8] + w[11], v8 = w[8] - w[11]
                            let u9 = w[9] + w[10], v9 = w[9] - w[10]
                            var sum = s0 * u0
                            sum += s1 * u1; sum += s2 * u2; sum += s3 * u3; sum += s4 * u4
                            sum += s5 * u5; sum += s6 * u6; sum += s7 * u7; sum += s8 * u8; sum += s9 * u9
                            var dif = d0 * v0
                            dif += d1 * v1; dif += d2 * v2; dif += d3 * v3; dif += d4 * v4
                            dif += d5 * v5; dif += d6 * v6; dif += d7 * v7; dif += d8 * v8; dif += d9 * v9
                            var mid = e0 * u0
                            mid += e1 * u1; mid += e2 * u2; mid += e3 * u3; mid += e4 * u4
                            mid += e5 * u5; mid += e6 * u6; mid += e7 * u7; mid += e8 * u8; mid += e9 * u9
                            var on = centre * w[9]
                            if on < 0 { on = -on }
                            if sum < 0 { sum = -sum }
                            if dif < 0 { dif = -dif }
                            if mid < 0 { mid = -mid }
                            let side = (sum + dif) * 0.5
                            if on > peak { peak = on }
                            if side > peak { peak = side }
                            if mid > peak { peak = mid }
                            w += 1
                        }
                    }
                    start += hop
                }
            }
        }
        return peak
    }

    /// True peak in dBTP (decibels relative to full scale, true peak): 20 log10 of `peak(_:)`, with the peak floored
    /// at 1e-9 (-180 dBTP) like the lab's, so silence gives -180.
    public static func decibels(_ buffer: AudioBuffer) -> Double {
        20 * log10(max(peak(buffer), 1e-9))
    }

    /// The modified Bessel function of the first kind, order 0, by its power series sum ((x/2)^k / k!)^2, whose terms
    /// are all positive; for the arguments here (up to 5) it converges to double precision in about 25 terms.
    static func besselI0(_ x: Double) -> Double {
        let q = x * x / 4
        var term = 1.0, sum = 1.0, k = 1.0
        while term > sum * 1e-17 {
            term *= q / (k * k)
            sum += term
            k += 1
        }
        return sum
    }
}
