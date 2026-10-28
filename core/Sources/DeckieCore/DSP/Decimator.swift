import Foundation

/// Halving the sample rate, for the key estimator's 44.1 kHz input (it reads 22,050 Hz).
///
/// A STOPGAP. The lab resamples with soxr at quality "hq" (`librosa.resample(..., res_type="soxr_hq")` in
/// mixer/key_light.py's `load`), a long linear-phase filter with a flat passband to about 91 percent of the new Nyquist
/// frequency and its stopband from the new Nyquist on. A proper resampler, for every rate, is a later mechanic. Until
/// then this is a plain windowed-sinc low-pass of 65 taps, then every second sample:
///
///   h[m] = 0.5 sinc(0.5 m) w[m],  m = -32 ... 32,  sinc(x) = sin(pi x) / (pi x),
///   w[m] = I0(beta sqrt(1 - (m / 32)^2)) / I0(beta)  (a Kaiser window, beta = 5, scipy's resample_poly default),
///
/// scaled so the taps sum to 1. The cutoff is 0.5 of the input's Nyquist frequency, that is the new Nyquist
/// frequency (11,025 Hz), where the response is -6 dB; it is flat within 0.02 dB to 9.9 kHz, 48.5 dB down at
/// 12.1 kHz and at least 57 dB down from 12.5 kHz. So, unlike soxr, it rolls off 9.9 to 11 kHz and folds some of
/// 11 to 12.5 kHz down into that band. A half-band filter: every second tap (even m other than 0) is exactly zero, so each output sample
/// costs 17 multiplications. It has no delay: output k is centred on input sample 2k, as soxr's output is.
///
/// Parity with soxr is measured here on a synthesised signal only (DSPTests: samples and chroma); on real tracks it
/// is to be measured on the Mac against the lab's chroma (mixer/key_light_stft.tsv holds the lab's keys).
public enum Decimator {
    /// The 65 taps, h[0] for m = -32 ... h[64] for m = 32.
    public static let taps: [Double] = {
        let half = 32, beta = 5.0
        let i0beta = TruePeak.besselI0(beta)
        var h = (0...(2 * half)).map { k -> Double in
            let m = k - half
            if m == 0 { return 0.5 }
            if m % 2 == 0 { return 0 }  // sin(pi m / 2) = 0: exactly zero, not floating-point's 1e-17
            let x = Double.pi * 0.5 * Double(m)
            let r = Double(m) / Double(half)
            return 0.5 * (sin(x) / x) * (TruePeak.besselI0(beta * (1 - r * r).squareRoot()) / i0beta)
        }
        let sum = h.reduce(0, +)
        for k in h.indices { h[k] /= sum }
        return h
    }()

    /// `x` (at 44.1 kHz, say) low-pass filtered and every second sample kept: (count + 1) / 2 samples, sample k
    /// centred on input sample 2k, with the input taken as zero outside its ends. The arithmetic is double precision.
    public static func halve(_ x: [Float]) -> [Float] {
        let n = x.count, outCount = (n + 1) / 2, half = 32
        if n == 0 { return [] }
        // The nonzero side taps, at odd m = 1, 3, ... 31, each used for x[2k - m] + x[2k + m].
        let side = stride(from: 1, through: 31, by: 2).map { taps[half + $0] }
        let centre = taps[half]
        var out = [Float](repeating: 0, count: outCount)
        x.withUnsafeBufferPointer { xb in
            side.withUnsafeBufferPointer { sb in
                out.withUnsafeMutableBufferPointer { ob in
                    let p = xb.baseAddress!, s = sb.baseAddress!
                    var k = 0
                    while k < outCount {
                        let i = 2 * k
                        var acc = centre * Double(p[i])
                        var j = 0, m = 1
                        if i >= 31 && i + 31 < n {
                            while j < 16 {
                                acc += s[j] * (Double(p[i - m]) + Double(p[i + m]))
                                j += 1
                                m += 2
                            }
                        } else {  // near the ends: samples outside the input count as zero
                            while j < 16 {
                                let before = i - m >= 0 ? Double(p[i - m]) : 0, after = i + m < n ? Double(p[i + m]) : 0
                                acc += s[j] * (before + after)
                                j += 1
                                m += 2
                            }
                        }
                        ob[k] = Float(acc)
                        k += 1
                    }
                }
            }
        }
        return out
    }
}
