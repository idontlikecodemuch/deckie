import Foundation

/// Pitch-class energy over time: `frames` rows of 12 values, C first (0 = C, 1 = C#, ... 11 = B), in double precision.
/// Stored frame by frame (`values[t * 12 + pc]`); the lab's arrays are the transpose, 12 rows of frames.
public struct Chromagram: Sendable, Equatable {
    public let frames: Int
    public var values: [Double]

    public init(frames: Int, values: [Double]) {
        precondition(values.count == frames * 12, "\(values.count) values for \(frames) frames of 12")
        self.frames = frames
        self.values = values
    }

    /// The value of pitch class `pc` in frame `t`.
    public subscript(t: Int, pc: Int) -> Double { values[t * 12 + pc] }

    /// The 12 values of frame `t`.
    public func frame(_ t: Int) -> [Double] { Array(values[(t * 12)..<(t * 12 + 12)]) }
}

/// librosa's chroma filter bank (`librosa.filters.chroma`, librosa 1.0.0): for each FFT bin, a weight per pitch class
/// that projects a power spectrum onto the 12 pitch classes. Following librosa's code, with A440 = 440 Hz times
/// 2^(tuning / 12) and, for the FFT bins i = 1 ..< fftSize at f_i = i sampleRate / fftSize:
///
///   frqbins_i = 12 log2(f_i / (A440 / 16))         the bin's pitch in semitones above A0 (27.5 Hz at A440)
///   frqbins_0 = frqbins_1 - 18                      a made-up value for 0 Hz, an octave and a half below bin 1
///   width_i   = max(frqbins_(i+1) - frqbins_i, 1)   the bin's width in semitones, at least one; width of the last = 1
///   D_(c,i)   = ((frqbins_i - c + 6 + 120) mod 12) - 6     the distance from pitch class c (counted from A) to the
///                                                          bin, folded into [-6, 6) semitones
///   w_(c,i)   = exp(-0.5 (2 D_(c,i) / width_i)^2)  a Gaussian bump half a semitone wide (in width units) per class
///   each bin's 12 weights divided by their Euclidean length (norm=2),
///   then times exp(-0.5 ((frqbins_i / 12 - ctroct) / octwidth)^2), a Gaussian over octaves centred on ctroct
///   (5.0: five octaves above A0, 880 Hz) with half-width octwidth (2 octaves), which favours the middle register,
///   then rotated so that row 0 is C (base_c: the rows counted from A move down by 3),
///   and only bins 0 ... fftSize / 2 kept.
///
/// librosa returns the bank as float32 (its default dtype), so the lab's chroma used float32 weights. The weights here
/// are computed in double precision and then rounded to float32 the same way, and kept as doubles.
public struct ChromaFilterBank: Sendable {
    public let sampleRate: Double
    public let fftSize: Int
    /// fftSize / 2 + 1.
    public let bins: Int
    /// Bin by bin, 12 weights each: `weights[bin * 12 + pc]`, pc 0 = C.
    public let weights: [Double]

    public init(sampleRate: Double, fftSize: Int, tuning: Double = 0, ctroct: Double = 5.0, octwidth: Double? = 2.0,
                baseC: Bool = true) {
        precondition(fftSize >= 2 && sampleRate > 0)
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        bins = fftSize / 2 + 1
        let n = fftSize, nChroma = 12.0
        let a440 = 440.0 * pow(2.0, tuning / nChroma)
        // np.linspace(0, sr, n_fft, endpoint=False)[1:]: i * (sr / n_fft)
        let step = sampleRate / Double(n)
        var frq = [Double](repeating: 0, count: n)
        for i in 1..<n { frq[i] = nChroma * log2(Double(i) * step / (a440 / 16)) }
        frq[0] = frq[1] - 1.5 * nChroma
        var width = [Double](repeating: 1, count: n)
        for i in 0..<(n - 1) { width[i] = max(frq[i + 1] - frq[i], 1.0) }
        let half = (nChroma / 2).rounded(.toNearestOrEven)
        var w = [Double](repeating: 0, count: n * 12)  // w[i * 12 + c], c counted from A
        for i in 0..<n {
            for c in 0..<12 {
                let d = Py.fmod(frq[i] - Double(c) + half + 10 * nChroma, nChroma) - half
                let x = 2 * d / width[i]
                w[i * 12 + c] = exp(-0.5 * (x * x))
            }
            // util.normalize(norm=2, axis=0): numpy sums the squares row after row; length = sqrt of that.
            var sq = 0.0
            for c in 0..<12 { sq += w[i * 12 + c] * w[i * 12 + c] }
            let length = sq.squareRoot()
            if length >= Double.leastNormalMagnitude {
                for c in 0..<12 { w[i * 12 + c] = w[i * 12 + c] / length }
            }
            if let octwidth {
                let o = (frq[i] / nChroma - ctroct) / octwidth
                let g = exp(-0.5 * (o * o))
                for c in 0..<12 { w[i * 12 + c] *= g }
            }
        }
        let shift = baseC ? 3 : 0  // np.roll(wts, -3, axis=0): row c takes old row (c + 3) mod 12
        var out = [Double](repeating: 0, count: bins * 12)
        for i in 0..<bins {
            for c in 0..<12 { out[i * 12 + c] = Double(Float(w[i * 12 + (c + shift) % 12])) }
        }
        weights = out
    }

    /// The bank for the key estimator: 22,050 Hz, 8192-point FFT, tuning 0 (mixer/key_light.py).
    public static let keyEstimator = ChromaFilterBank(sampleRate: 22050, fftSize: 8192)
}

/// Chroma from the short-time Fourier transform, as `librosa.feature.chroma_stft` computes it (librosa 1.0.0).
public enum Chroma {
    /// `librosa.feature.chroma_stft(y=y, sr=22050, n_fft=8192, hop_length=2048, tuning=0.0)`, the call in
    /// mixer/key_light.py: the power spectrogram (`STFT`: Hann window, centred frames, zero padding, magnitude
    /// squared), projected through `ChromaFilterBank` with tuning 0 (so librosa's tuning estimate is skipped), and
    /// each frame divided by its largest value (librosa's norm=inf). A frame whose largest value is below the
    /// smallest normal float32 (the lab's chroma is float32), such as one of digital silence, is left as it is.
    ///
    /// `y` is a mono signal at `sampleRate`; the defaults are the lab's. The lab feeds float32 audio, so librosa's
    /// arithmetic is partly single precision (the spectrogram and the projection); everything here is double
    /// precision, which puts it within 1e-6 of the lab's values (8.4e-7 at most on the synthesised signals of
    /// ChromaParityTests; 8.5e-15 when librosa is given the signal in double precision).
    public static func stft(_ y: [Float], sampleRate: Int = 22050, fftSize: Int = 8192, hop: Int = 2048) -> Chromagram {
        let bank = filterBank(sampleRate: sampleRate, fftSize: fftSize)
        var out: [Double] = []
        let stft = STFT(fftSize: fftSize, hop: hop)
        out.reserveCapacity(stft.frameCount(samples: y.count) * 12)
        stft.forEachPowerFrame(y) { _, p in project(p, bank, into: &out) }
        return Chromagram(frames: out.count / 12, values: out)
    }

    /// `stft` for a signal held in double precision.
    public static func stft(_ y: [Double], sampleRate: Int = 22050, fftSize: Int = 8192, hop: Int = 2048) -> Chromagram {
        let bank = filterBank(sampleRate: sampleRate, fftSize: fftSize)
        var out: [Double] = []
        let stft = STFT(fftSize: fftSize, hop: hop)
        out.reserveCapacity(stft.frameCount(samples: y.count) * 12)
        stft.forEachPowerFrame(y) { _, p in project(p, bank, into: &out) }
        return Chromagram(frames: out.count / 12, values: out)
    }

    static func filterBank(sampleRate: Int, fftSize: Int) -> ChromaFilterBank {
        sampleRate == 22050 && fftSize == 8192
            ? .keyEstimator : ChromaFilterBank(sampleRate: Double(sampleRate), fftSize: fftSize)
    }

    /// One frame: the 12 sums of weight times power over the bins, then divided by the largest of them. Twelve running
    /// sums in local variables, written out so a debug build stays quick.
    static func project(_ p: UnsafeBufferPointer<Double>, _ bank: ChromaFilterBank, into out: inout [Double]) {
        var s0 = 0.0, s1 = 0.0, s2 = 0.0, s3 = 0.0, s4 = 0.0, s5 = 0.0
        var s6 = 0.0, s7 = 0.0, s8 = 0.0, s9 = 0.0, s10 = 0.0, s11 = 0.0
        bank.weights.withUnsafeBufferPointer { wb in
            var w = wb.baseAddress!
            var q = p.baseAddress!
            let end = q + bank.bins
            while q < end {
                let v = q.pointee
                s0 += w[0] * v; s1 += w[1] * v; s2 += w[2] * v; s3 += w[3] * v
                s4 += w[4] * v; s5 += w[5] * v; s6 += w[6] * v; s7 += w[7] * v
                s8 += w[8] * v; s9 += w[9] * v; s10 += w[10] * v; s11 += w[11] * v
                w += 12
                q += 1
            }
        }
        let raw = [s0, s1, s2, s3, s4, s5, s6, s7, s8, s9, s10, s11]
        var length = 0.0
        for v in raw where abs(v) > length { length = abs(v) }
        if length < Double(Float.leastNormalMagnitude) { length = 1 }
        for v in raw { out.append(v / length) }
    }
}
