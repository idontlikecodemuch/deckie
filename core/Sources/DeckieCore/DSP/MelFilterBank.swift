import Foundation

/// The mel scale as Slaney's Auditory Toolbox defines it (and librosa's and torchaudio's `mel_scale="slaney"`):
/// linear below 1 kHz, 3 mels per 200 Hz, and logarithmic above, 27 mels per factor of 6.4.
public enum SlaneyMel {
    static let hzPerMel = 200.0 / 3
    static let breakHz = 1000.0
    static let breakMel = breakHz / hzPerMel  // 15
    static let logStep = log(6.4) / 27.0

    /// Mels for `hz`, as torchaudio's `_hz_to_mel(freq, "slaney")` computes it in double precision.
    public static func mel(hz: Double) -> Double {
        if hz >= breakHz { return breakMel + log(hz / breakHz) / logStep }
        return (hz - 0) / hzPerMel
    }

    /// Hz for `mel` (torchaudio's `_mel_to_hz`).
    public static func hz(mel: Double) -> Double {
        if mel >= breakMel { return breakHz * exp(logStep * (mel - breakMel)) }
        return 0 + hzPerMel * mel
    }
}

/// A bank of triangular mel filters over the bins of a real FFT, as torchaudio's
/// `melscale_fbanks(n_freqs, f_min, f_max, n_mels, sample_rate, norm=None, mel_scale="slaney")` makes it
/// (torchaudio 2.11): the FFT bins sit at f_k = k (sample_rate // 2) / (n_freqs - 1); n_mels + 2 points are spaced
/// evenly in mels from mel(f_min) to mel(f_max) and turned back into Hz, p_0 ... p_(n_mels + 1); filter m rises
/// linearly from 0 at p_m to 1 at p_(m+1) and falls back to 0 at p_(m+2):
///
///   w_(m,k) = max(0, min((f_k - p_m) / (p_(m+1) - p_m), (p_(m+2) - f_k) / (p_(m+2) - p_(m+1))))
///
/// with no area normalisation (norm=None). torchaudio computes in float32 throughout, and so does this, step for
/// step, so the weights are torchaudio's own float32 values (kept as doubles): `torch.linspace` in float32 (its CPU
/// kernel computes start + step i, and end - step (steps - 1 - i) for the upper half, each with one rounding, a fused
/// multiply-add), the mel-to-Hz conversion in float32 with the C library's expf, and the slopes and divisions in
/// float32. Measured on Linux: all 1,004 nonzero weights identical to torchaudio 2.11's (one mel point in 130
/// differs from torch's in its last bit through expf, which rounds no weight differently); where another C library's
/// expf differs, weights may move by a float32 rounding step (Tests: BeatThisTests). Each filter is stored as its
/// first nonzero bin and the run of weights from there, so applying the bank costs about two multiplications per bin.
public struct MelFilterBank: Sendable {
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
        let points = Self.linspace(SlaneyMel.mel(hz: fMin), SlaneyMel.mel(hz: fMax), melCount + 2).map(Self.hz32)
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

    /// torchaudio's `_mel_to_hz(mels, "slaney")` on a float32 tensor: the Python constants become float32.
    static func hz32(_ mel: Float) -> Float {
        if mel >= Float(SlaneyMel.breakMel) {
            return Float(SlaneyMel.breakHz) * exp(Float(SlaneyMel.logStep) * (mel - Float(SlaneyMel.breakMel)))
        }
        return Float(0.0) + Float(SlaneyMel.hzPerMel) * mel
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
