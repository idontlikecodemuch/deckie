import Foundation

/// YAMNet's mel filter bank, as TensorFlow's `tf.signal.linear_to_mel_weight_matrix` builds it (TensorFlow 2.21,
/// tensorflow/python/ops/signal/mel_ops.py; rewritten here, no TensorFlow code is used): HTK's mel scale,
/// mel(f) = 1127 ln(1 + f / 700); the FFT bins at f_k = k (sampleRate / 2) / (bins - 1) (TensorFlow's linspace from 0
/// to the Nyquist frequency); `bands + 2` edges evenly spaced in mels from mel(lowHz) to mel(highHz); band m a triangle
/// in the mel domain (not in Hz) rising from edge m to 1 at edge m + 1 and falling to 0 at edge m + 2:
///
///   w_(m,k) = max(0, min((mel(f_k) - e_m) / (e_(m+1) - e_m), (e_(m+2) - mel(f_k)) / (e_(m+2) - e_(m+1))))
///
/// with no area normalisation, and the DC bin (k = 0) left out of every band, as HTK does. TensorFlow computes in
/// float32; here the weights are double precision, within 8.2e-6 of TensorFlow's, which is TensorFlow's own float32
/// rounding of the mels (Tests: YAMNetFrontEndTests, against the matrix TensorFlow itself gives,
/// core/Tools/make_yamnet_fixtures.py). Each band is stored as its first nonzero bin and the run of weights from there.
public struct YAMNetMelFilterBank: Sendable {
    public let sampleRate: Double
    public let bins: Int
    public let bands: Int
    public let lowHz: Double
    public let highHz: Double
    /// Band m's first bin with a nonzero weight.
    public let firstBin: [Int]
    /// Band m's weights for bins firstBin[m], firstBin[m] + 1, ...
    public let weights: [[Double]]

    /// HTK's mel scale, as TensorFlow's `_hertz_to_mel`.
    public static func hzToMel(_ f: Double) -> Double { 1127.0 * log(1.0 + f / 700.0) }

    public init(sampleRate: Double, bins: Int, bands: Int, lowHz: Double, highHz: Double) {
        precondition(sampleRate > 0 && bins >= 2 && bands >= 1 && lowHz >= 0 && highHz > lowHz)
        self.sampleRate = sampleRate
        self.bins = bins
        self.bands = bands
        self.lowHz = lowHz
        self.highHz = highHz
        let nyquist = sampleRate / 2
        let lo = Self.hzToMel(lowHz), hi = Self.hzToMel(highHz)
        let edges = (0..<(bands + 2)).map { lo + (hi - lo) * Double($0) / Double(bands + 1) }
        var first: [Int] = [], all: [[Double]] = []
        for m in 0..<bands {
            let e0 = edges[m], e1 = edges[m + 1], e2 = edges[m + 2]
            var start = -1
            var w: [Double] = []
            for k in 1..<bins {  // the DC bin is in no band
                let mel = Self.hzToMel(nyquist * Double(k) / Double(bins - 1))
                let v = max(0, min((mel - e0) / (e1 - e0), (e2 - mel) / (e2 - e1)))
                if v > 0 {
                    if start < 0 { start = k }
                    precondition(k == start + w.count, "mel band \(m) is not one run of bins")
                    w.append(v)
                }
            }
            first.append(max(start, 0))
            all.append(w)
        }
        firstBin = first
        weights = all
    }

    /// The weight of bin k in band m (0 outside the band's run).
    public func weight(band m: Int, bin k: Int) -> Double {
        let i = k - firstBin[m]
        return i >= 0 && i < weights[m].count ? weights[m][i] : 0
    }
}

/// YAMNet's front end (Google's audio event tagger; tensorflow/models, research/audioset/yamnet, features.py and
/// params.py, Apache 2.0; rewritten here, no TensorFlow code is used): mono audio at 16 kHz in, the log-mel patches the
/// network reads out.
///
///   1. Padding (`pad_waveform`): zeros at the end so the audio holds a whole number of patches: at least 15,600
///      samples (one patch of 0.96 s plus the last STFT window's overhang, 0.96 + 0.025 - 0.010 s), then up to the next
///      whole number of 7,680-sample (0.48 s) hops beyond that. n samples give 1 + ceil(max(0, n - 15600) / 7680)
///      patches.
///   2. The STFT as `tf.signal.stft` computes it: frames of 400 samples (25 ms) every 160 (10 ms), not centred (frame
///      j reads samples 160 j ..< 160 j + 400), each times the periodic Hann window of 400 points and zero-padded at
///      its end to 512 for the FFT; the magnitude of its 257 bins.
///   3. 64 mel bands from 125 to 7,500 Hz (`YAMNetMelFilterBank`), then log(mel + 0.001).
///   4. Patches of 96 frames (0.96 s) every 48 frames (0.48 s) (`tf.signal.frame`): patch k is frames 48 k ..< 48 k + 96
///      and reads samples 7,680 k ..< 7,680 k + 15,600, so its middle is at 0.48 k + 0.4875 s. (YAMNet's own plots
///      put it at 0.48 k + 0.48, half the patch's 96 frames; this counts the last window's 15 ms overhang too.)
///
/// TensorFlow computes in float32; here everything up to the final rounding to float32 is double precision, which puts
/// the values within 1.8e-4 of YAMNet's own feature code, 5e-6 on average (Tests: YAMNetFrontEndTests measure it on
/// synthesised music). Frames are computed one at a time.
public struct YAMNetFrontEnd: Sendable {
    public static let sampleRate = 16000
    public static let windowLength = 400
    public static let hop = 160
    public static let fftLength = 512
    public static let bands = 64
    public static let lowHz = 125.0
    public static let highHz = 7500.0
    public static let logOffset = 0.001
    public static let patchFrames = 96
    public static let patchHopFrames = 48
    /// Samples a single patch needs (`pad_waveform`'s minimum) and samples between patches.
    public static let minimumSamples = 15600
    public static let patchHopSamples = 7680
    /// Seconds between patches, and from the start of the audio to the middle of patch 0's samples.
    public static let patchHopSeconds = 0.48
    public static let patchCentreSeconds = 0.4875

    public let filterBank: YAMNetMelFilterBank
    /// The periodic Hann window of 400 points (`tf.signal.hann_window(400, periodic=True)`).
    public let window: [Double]
    let fft: RealFFT

    public init() {
        filterBank = YAMNetMelFilterBank(sampleRate: Double(Self.sampleRate), bins: Self.fftLength / 2 + 1,
                                         bands: Self.bands, lowHz: Self.lowHz, highHz: Self.highHz)
        window = (0..<Self.windowLength).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(Self.windowLength)) }
        fft = RealFFT(size: Self.fftLength)
    }

    /// Patches for `samples` samples at 16 kHz: 1 + ceil(max(0, samples - 15600) / 7680).
    public static func patchCount(samples: Int) -> Int {
        1 + (max(0, samples - minimumSamples) + patchHopSamples - 1) / patchHopSamples
    }

    /// The padded length: 15,600 samples plus a whole number of 7,680-sample hops.
    public static func paddedCount(samples: Int) -> Int { minimumSamples + (patchCount(samples: samples) - 1) * patchHopSamples }

    /// STFT frames of the padded audio: 96 + 48 (patches - 1).
    public static func frameCount(samples: Int) -> Int { patchFrames + (patchCount(samples: samples) - 1) * patchHopFrames }

    /// The middle of patch k, in seconds from the start of the audio.
    public static func patchCentre(_ k: Int) -> Double { patchCentreSeconds + patchHopSeconds * Double(k) }

    /// The log-mel spectrogram of mono audio at 16 kHz after YAMNet's padding: `frameCount(samples:)` frames of 64
    /// bands, frame by frame (`values[t * 64 + band]`), band 0 the lowest, rounded to float32.
    public func logMel(_ y: [Float]) -> (frames: Int, values: [Float]) {
        let frames = Self.frameCount(samples: y.count), bands = Self.bands, bins = Self.fftLength / 2 + 1
        let win = Self.windowLength, size = Self.fftLength, hop = Self.hop
        var out = [Float](repeating: 0, count: frames * bands)
        let x = UnsafeMutablePointer<Double>.allocate(capacity: size)
        let re = UnsafeMutablePointer<Double>.allocate(capacity: bins)
        let im = UnsafeMutablePointer<Double>.allocate(capacity: bins)
        defer { x.deallocate(); re.deallocate(); im.deallocate() }
        x.initialize(repeating: 0, count: size)
        let n = y.count
        y.withUnsafeBufferPointer { yb in
            window.withUnsafeBufferPointer { wb in
                out.withUnsafeMutableBufferPointer { ob in
                    for t in 0..<frames {
                        let start = t * hop
                        var j = 0
                        if start + win <= n {
                            while j < win { x[j] = Double(yb[start + j]) * wb[j]; j += 1 }
                        } else {
                            while j < win { x[j] = start + j < n ? Double(yb[start + j]) * wb[j] : 0; j += 1 }
                        }
                        // x[400..<512] stays zero.
                        fft.forward(x, real: re, imag: im)
                        var k = 0
                        while k < bins { re[k] = (re[k] * re[k] + im[k] * im[k]).squareRoot(); k += 1 }
                        for m in 0..<bands {
                            let first = filterBank.firstBin[m]
                            var s = 0.0
                            filterBank.weights[m].withUnsafeBufferPointer { w in
                                var i = 0
                                while i < w.count { s += w[i] * re[first + i]; i += 1 }
                            }
                            ob[t * bands + m] = Float(log(s + Self.logOffset))
                        }
                    }
                }
            }
        }
        return (frames, out)
    }

    /// The patches of mono audio at 16 kHz, as the network's input: `count` patches of 96 frames of 64 bands
    /// (`values[(k * 96 + frame) * 64 + band]`), the layout of the model's input (count x 96 x 64).
    public func patches(_ y: [Float]) -> (count: Int, values: [Float]) {
        let spec = logMel(y)
        return Self.patches(spec.values, frames: spec.frames)
    }

    /// Cuts a log-mel spectrogram (`frames` x 64) into patches of 96 frames every 48.
    public static func patches(_ spec: [Float], frames: Int) -> (count: Int, values: [Float]) {
        guard frames >= patchFrames else { return (0, []) }
        let count = 1 + (frames - patchFrames) / patchHopFrames
        let size = patchFrames * bands
        var out = [Float](repeating: 0, count: count * size)
        for k in 0..<count {
            let from = k * patchHopFrames * bands
            out.replaceSubrange((k * size)..<((k + 1) * size), with: spec[from..<(from + size)])
        }
        return (count, out)
    }
}
