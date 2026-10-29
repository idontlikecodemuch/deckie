import Foundation

/// A bank of triangular mel filters over the bins of a real FFT, as torchaudio's
/// `melscale_fbanks(n_freqs, f_min, f_max, n_mels, sample_rate, norm=None, mel_scale="slaney")` makes it
/// (torchaudio 2.11): the FFT bins sit at f_k = k (sample_rate // 2) / (n_freqs - 1); n_mels + 2 points are spaced
/// evenly in mels from mel(f_min) to mel(f_max) and turned back into Hz, p_0 ... p_(n_mels + 1), on Slaney's mel
/// scale (linear below 1 kHz, 3 mels per 200 Hz, logarithmic above, 27 mels per factor of 6.4); filter m rises
/// linearly from 0 at p_m to 1 at p_(m+1) and falls back to 0 at p_(m+2):
///
///   w_(m,k) = max(0, min((f_k - p_m) / (p_(m+1) - p_m), (p_(m+2) - f_k) / (p_(m+2) - p_(m+1))))
///
/// with no area normalisation (norm=None). torchaudio computes in float32 throughout, and so does this, step for
/// step, so the weights are torchaudio's own float32 values (kept as doubles): `torch.linspace` in float32 (its CPU
/// kernel computes start + step i, and end - step (steps - 1 - i) for the upper half, each with one rounding, a fused
/// multiply-add), the mel-to-Hz conversion in float32 with the C library's expf, and the slopes and divisions in
/// float32 (mel(f_min) and mel(f_max) themselves are double precision in torchaudio, and here
/// `LibrosaMelFilterBank.hzToMel`, the same arithmetic). Measured on Linux with Beat This!'s settings: 129 of the 130
/// mel points are torchaudio's to the bit; the one at 8,909.8 Hz is a float32 step away, because torch's vectorised
/// expf (Sleef) and glibc's round it differently, which moves the 42 weights of the three filters that use it by up
/// to 4e-6; the other 962 nonzero weights are identical (Tests: BeatThisTests). Another C library's expf may round
/// other points differently. Named after torchaudio, as `LibrosaMelFilterBank` is after librosa: the two libraries'
/// conventions differ (here no area normalisation, float32 throughout, the bins up to the integer half rate). Each
/// filter is stored as its first nonzero bin and the run of weights from there, so applying the bank costs about two
/// multiplications per bin.
public struct TorchaudioMelFilterBank: Sendable {
    public let sampleRate: Int
    public let fftSize: Int
    public let melCount: Int
    public let fMin: Double
    public let fMax: Double
    /// Filter m's first bin with a nonzero weight.
    public let firstBin: [Int]
    /// Filter m's weights for bins firstBin[m], firstBin[m] + 1, ..., all nonzero.
    public let weights: [[Double]]

    public init(sampleRate: Int, fftSize: Int, melCount: Int, fMin: Double, fMax: Double) {
        precondition(sampleRate > 0 && fftSize >= 2 && melCount >= 1 && fMin >= 0 && fMax > fMin)
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        self.melCount = melCount
        self.fMin = fMin
        self.fMax = fMax
        let bins = fftSize / 2 + 1
        // torch.linspace(0, sample_rate // 2, n_freqs): the integer half rate, as torchaudio passes it.
        let freqs = Self.linspace(0, Double(sampleRate / 2), bins)
        // The mel points: torch.linspace(mel(f_min), mel(f_max), n_mels + 2) in float32, then _mel_to_hz in float32.
        let mMin = LibrosaMelFilterBank.hzToMel(fMin), mMax = LibrosaMelFilterBank.hzToMel(fMax)
        let points = Self.linspace(mMin, mMax, melCount + 2).map(Self.hz32)
        let diff = zip(points.dropFirst(), points).map { $0 - $1 }  // f_pts[1:] - f_pts[:-1]
        var first: [Int] = [], all: [[Double]] = []
        for m in 0..<melCount {
            var start = -1
            var w: [Double] = []
            for k in 0..<bins {
                // slopes = f_pts - all_freqs; down = (-1 x slopes[m]) / diff[m]; up = slopes[m + 2] / diff[m + 1]
                let down = (-1 * (points[m] - freqs[k])) / diff[m], up = (points[m + 2] - freqs[k]) / diff[m + 1]
                let v = Double(max(0, min(down, up)))
                if v > 0 {
                    if start < 0 { start = k }
                    precondition(k == start + w.count, "mel filter \(m) is not one run of bins")
                    w.append(v)
                }
            }
            first.append(max(start, 0))
            all.append(w)
        }
        firstBin = first
        weights = all
    }

    /// `torch.linspace(start, end, steps)` in float32 as torch's CPU kernel computes it: the ends rounded to float32,
    /// step = (end - start) / (steps - 1) in float32, then start + step i for the lower half and end - step
    /// (steps - 1 - i) for the upper half, each a fused multiply-add (one rounding).
    static func linspace(_ start: Double, _ end: Double, _ steps: Int) -> [Float] {
        let a = Float(start), b = Float(end)
        if steps == 1 { return [a] }
        let step = (b - a) / Float(steps - 1)
        return (0..<steps).map { i in
            i < steps / 2 ? a.addingProduct(step, Float(i)) : b.addingProduct(-step, Float(steps - 1 - i))
        }
    }

    /// torchaudio's `_mel_to_hz(mels, "slaney")` on a float32 tensor: the Python constants (f_sp = 200 / 3 Hz per
    /// mel, the break at 1,000 Hz, which is 15 mels, and the log step ln(6.4) / 27) become float32.
    static func hz32(_ mel: Float) -> Float {
        let hzPerMel = 200.0 / 3, breakHz = 1000.0, breakMel = 1000.0 / (200.0 / 3), logStep = log(6.4) / 27.0
        if mel >= Float(breakMel) {
            return Float(breakHz) * exp(Float(logStep) * (mel - Float(breakMel)))
        }
        return Float(0.0) + Float(hzPerMel) * mel
    }

    /// Filter m's weight at FFT bin k (0 outside its run).
    public func weight(mel m: Int, bin k: Int) -> Double {
        let i = k - firstBin[m]
        return i >= 0 && i < weights[m].count ? weights[m][i] : 0
    }

    /// The bank applied to one frame of `fftSize / 2 + 1` bin values: `melCount` sums of weight times value,
    /// written to `out`.
    public func apply(_ spectrum: UnsafeBufferPointer<Double>, into out: UnsafeMutableBufferPointer<Double>) {
        precondition(spectrum.count == fftSize / 2 + 1 && out.count == melCount)
        for m in 0..<melCount {
            let start = firstBin[m]
            var sum = 0.0
            weights[m].withUnsafeBufferPointer { w in
                var j = 0
                while j < w.count { sum += w[j] * spectrum[start + j]; j += 1 }
            }
            out[m] = sum
        }
    }
}
