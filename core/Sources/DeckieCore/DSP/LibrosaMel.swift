import Foundation

/// librosa's mel filter bank, `librosa.filters.mel(sr=sampleRate, n_fft=fftSize, n_mels=bands)` with librosa's
/// defaults (librosa 1.0.0): fmin 0, fmax sr / 2, Slaney's mel scale (htk=False) and Slaney's area normalisation
/// (norm="slaney"). Named after librosa because other mel filter banks with other conventions may live in DeckieCore
/// (a neural model's front end, for one); this one is the lab's spectral features' (mixer/analyze.py).
///
/// Slaney's mel scale (the Auditory Toolbox's), linear below 1 kHz and logarithmic above it:
///
///   mel(f) = f / (200 / 3)                             for f < 1000 Hz
///   mel(f) = 15 + ln(f / 1000) / (ln(6.4) / 27)        for f >= 1000 Hz   (1000 Hz is mel 15)
///   hz(m)  = (200 / 3) m                               for m < 15
///   hz(m)  = 1000 exp((ln(6.4) / 27) (m - 15))         for m >= 15
///
/// (with htk: true, HTK's mel(f) = 2595 log10(1 + f / 700) and hz(m) = 700 (10^(m / 2595) - 1) instead).
///
/// The bank, following librosa's code:
///
///   f_k     = k sr / fftSize, k = 0 ... fftSize / 2            the FFT bins' frequencies (numpy.fft.rfftfreq)
///   c_i     = hz(mel(fmin) + i (mel(fmax) - mel(fmin)) / (bands + 1)), i = 0 ... bands + 1
///                                                              bands + 2 points evenly spaced in mel (numpy's
///                                                              linspace, the last set to mel(fmax) exactly)
///   w_(m,k) = max(0, min((f_k - c_m) / (c_(m+1) - c_m), (c_(m+2) - f_k) / (c_(m+2) - c_(m+1))))
///                                                              a triangle rising from c_m to 1 at c_(m+1), falling
///                                                              to 0 at c_(m+2); stored as float32 (librosa's dtype)
///   then w_(m,k) times 2 / (c_(m+2) - c_m), rounded to float32 again (Slaney: every triangle has the same area,
///   so a band's energy does not grow with its width).
///
/// The weights here are computed in double precision and go through the same two float32 roundings, then are kept as
/// doubles. numpy computes exp and log its own way, which differs from the C library's in the last bit for a few
/// percent of arguments; after the float32 rounding that leaves the weights identical (SpectralTests counts them).
/// A triangle covers only a few of the 1025 bins, so each band keeps the run of bins from its first non-zero weight
/// to its last.
public struct LibrosaMelFilterBank: Sendable {
    public let sampleRate: Double
    public let fftSize: Int
    public let bands: Int
    /// fftSize / 2 + 1.
    public let bins: Int
    public let fmin: Double
    public let fmax: Double
    public let htk: Bool
    /// c_0 ... c_(bands+1) in Hz, librosa's `mel_frequencies(bands + 2, fmin=fmin, fmax=fmax)`.
    public let melFrequencies: [Double]
    /// For each band, the first bin of its run of weights.
    public let firstBin: [Int]
    /// For each band, its weights for bins `firstBin[m]` on (empty for a band with no non-zero weight).
    public let weights: [[Double]]
    /// The runs end to end, for the projection loop.
    let flat: [Double]
    let flatStart: [Int]

    public init(sampleRate: Double, fftSize: Int, bands: Int = 128, fmin: Double = 0, fmax: Double? = nil,
                htk: Bool = false) {
        precondition(sampleRate > 0 && fftSize >= 2 && bands >= 1)
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        self.bands = bands
        bins = fftSize / 2 + 1
        self.fmin = fmin
        let top = fmax ?? sampleRate / 2
        self.fmax = top
        self.htk = htk
        let freqs = LibrosaMelFilterBank.fftFrequencies(sampleRate: sampleRate, fftSize: fftSize)
        let c = LibrosaMelFilterBank.melFrequencies(count: bands + 2, fmin: fmin, fmax: top, htk: htk)
        melFrequencies = c
        var first: [Int] = [], rows: [[Double]] = []
        for m in 0..<bands {
            let below = c[m + 1] - c[m], above = c[m + 2] - c[m + 1]  // numpy.diff(mel_f)
            let enorm = 2.0 / (c[m + 2] - c[m])
            var row: [Double] = []
            var start = -1
            for k in 0..<bins {
                // ramps = mel_f - fftfreqs; lower = -ramps[m] / fdiff[m]; upper = ramps[m + 2] / fdiff[m + 1]
                let lower = -(c[m] - freqs[k]) / below
                let upper = (c[m + 2] - freqs[k]) / above
                let w32 = Float(max(0, min(lower, upper)))
                let w = Double(Float(Double(w32) * enorm))
                if w != 0 {
                    if start < 0 { start = k }
                    while start + row.count < k { row.append(0) }
                    row.append(w)
                }
            }
            first.append(max(start, 0))
            rows.append(row)
        }
        firstBin = first
        weights = rows
        var f: [Double] = [], s: [Int] = []
        for r in rows { s.append(f.count); f.append(contentsOf: r) }
        flat = f
        flatStart = s
    }

    /// The bank the lab's spectral features use: 22,050 Hz, a 2048-point FFT, 64 bands (mixer/analyze.py).
    public static let lab = LibrosaMelFilterBank(sampleRate: 22050, fftSize: 2048, bands: 64)

    /// The weight of `bin` in `band` (0 outside the band's run).
    public func weight(band m: Int, bin k: Int) -> Double {
        let j = k - firstBin[m]
        return j >= 0 && j < weights[m].count ? weights[m][j] : 0
    }

    /// Projects one power spectrum (`bins` values) onto the bands: out[m] = sum over k of w_(m,k) p_k, added in bin
    /// order over the band's run.
    public func project(_ p: UnsafePointer<Double>, into out: UnsafeMutablePointer<Double>) {
        flat.withUnsafeBufferPointer { fb in
            let w = fb.baseAddress
            var m = 0
            while m < bands {
                let count = weights[m].count
                var s = 0.0
                if count > 0, let w {
                    let wm = w + flatStart[m], pm = p + firstBin[m]
                    var j = 0
                    while j < count { s += wm[j] * pm[j]; j += 1 }
                }
                out[m] = s
                m += 1
            }
        }
    }

    /// `librosa.hz_to_mel(f, htk=htk)` for one frequency (librosa's scalar branch).
    public static func hzToMel(_ f: Double, htk: Bool = false) -> Double {
        if htk { return 2595.0 * log10(1.0 + f / 700.0) }
        let fsp = 200.0 / 3
        let minLogHz = 1000.0, minLogMel = (minLogHz - 0.0) / fsp, logstep = log(6.4) / 27.0
        if f >= minLogHz { return minLogMel + log(f / minLogHz) / logstep }
        return (f - 0.0) / fsp
    }

    /// `librosa.mel_to_hz(m, htk=htk)` for one value (as its array branch computes each element).
    public static func melToHz(_ m: Double, htk: Bool = false) -> Double {
        if htk { return 700.0 * (pow(10.0, m / 2595.0) - 1.0) }
        let fsp = 200.0 / 3
        let minLogHz = 1000.0, minLogMel = (minLogHz - 0.0) / fsp, logstep = log(6.4) / 27.0
        if m >= minLogMel { return minLogHz * exp(logstep * (m - minLogMel)) }
        return 0.0 + fsp * m
    }

    /// `librosa.mel_frequencies(count, fmin=, fmax=, htk=)`: `count` frequencies evenly spaced in mel from fmin to
    /// fmax, with numpy's linspace (value i = i step + start, step = (stop - start) / (count - 1), the last = stop).
    public static func melFrequencies(count n: Int, fmin: Double, fmax: Double, htk: Bool = false) -> [Double] {
        precondition(n >= 1)
        let lo = hzToMel(fmin, htk: htk), hi = hzToMel(fmax, htk: htk)
        if n == 1 { return [melToHz(lo, htk: htk)] }
        let step = (hi - lo) / Double(n - 1)
        return (0..<n).map { i in melToHz(i == n - 1 ? hi : Double(i) * step + lo, htk: htk) }
    }

    /// `numpy.fft.rfftfreq(fftSize, 1 / sampleRate)`: k times 1 / (fftSize (1 / sampleRate)), k = 0 ... fftSize / 2.
    public static func fftFrequencies(sampleRate: Double, fftSize: Int) -> [Double] {
        let val = 1.0 / (Double(fftSize) * (1.0 / sampleRate))
        return (0...(fftSize / 2)).map { Double($0) * val }
    }
}

/// librosa's mel spectrogram and decibel conversion as the lab calls them.
public enum LibrosaMel {
    /// `librosa.feature.melspectrogram(y=y, sr=, n_fft=, hop_length=hop, n_mels=)` with its defaults (librosa 1.0.0):
    /// the power spectrogram (`STFT`: periodic Hann window, centred frames, zero padding, magnitude squared) projected
    /// through `bank`. Frame by frame, so the whole STFT is never held.
    ///
    /// The lab gives float32 audio, so librosa's spectrogram (complex64), its magnitude and square, and the projection
    /// (float32 matrix product) are single precision; here everything is double precision (on the test signals the
    /// lab's values are within 1e-6 relative of these; SpectralTests prints the figures).
    public static func spectrogram(_ y: [Float], bank: LibrosaMelFilterBank = .lab, hop: Int = 512) -> FrameMatrix {
        let stft = STFT(fftSize: bank.fftSize, hop: hop)
        let frames = stft.frameCount(samples: y.count)
        var out = [Double](repeating: 0, count: frames * bank.bands)
        out.withUnsafeMutableBufferPointer { ob in
            stft.forEachPowerFrame(y) { t, p in bank.project(p.baseAddress!, into: ob.baseAddress! + t * bank.bands) }
        }
        return FrameMatrix(frames: frames, rows: bank.bands, values: out)
    }

    /// `spectrogram` for a signal held in double precision.
    public static func spectrogram(_ y: [Double], bank: LibrosaMelFilterBank = .lab, hop: Int = 512) -> FrameMatrix {
        let stft = STFT(fftSize: bank.fftSize, hop: hop)
        let frames = stft.frameCount(samples: y.count)
        var out = [Double](repeating: 0, count: frames * bank.bands)
        out.withUnsafeMutableBufferPointer { ob in
            stft.forEachPowerFrame(y) { t, p in bank.project(p.baseAddress!, into: ob.baseAddress! + t * bank.bands) }
        }
        return FrameMatrix(frames: frames, rows: bank.bands, values: out)
    }

    /// `librosa.power_to_db(S, ref=ref, amin=amin, top_db=topDb)` (defaults: ref 1.0, amin 1e-10, top_db 80):
    ///
    ///   v = 10 log10(max(amin, s)) - 10 log10(max(amin, |ref|))
    ///   then, with top_db, v = max(v, (the largest v of the whole matrix) - top_db)
    ///
    /// so nothing lies more than top_db below the loudest value anywhere in the matrix, and digital silence reads
    /// 10 log10(amin) = -100 dB before that clamp. (librosa's "auto" axes for a 2-D input take the maximum over both
    /// axes, all frames and all bands.) numpy's log10 can differ from the C library's in the last bit.
    public static func powerToDb(_ s: FrameMatrix, ref: Double = 1.0, amin: Double = 1e-10, topDb: Double? = 80)
        -> FrameMatrix {
        precondition(amin > 0, "amin must be strictly positive")
        let refDb = 10.0 * log10(max(amin, abs(ref)))
        var v = s.values
        var top = -Double.infinity
        v.withUnsafeMutableBufferPointer { b in
            var i = 0
            while i < b.count {
                let x = 10.0 * log10(max(amin, b[i])) - refDb
                b[i] = x
                if x > top { top = x }
                i += 1
            }
            if let topDb, !b.isEmpty {
                precondition(topDb >= 0, "top_db must be non-negative")
                let floor = top - topDb
                i = 0
                while i < b.count { if b[i] < floor { b[i] = floor }; i += 1 }
            }
        }
        return FrameMatrix(frames: s.frames, rows: s.rows, values: v)
    }
}
