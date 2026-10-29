import Foundation

// The engine's key method: research R's recommended estimator (docs/research/r-key-parity.md, row 3f), ported from
// its reference, mixer/key_parity.py's `recommended` (with `spectral_peaks`, `hpcp` and `decide`). Plain arithmetic on
// one FFT per frame, no model:
//
//   frames     mono audio at 44.1 kHz in frames of 4,096 samples, hop 4,096 (no overlap), full frames only, each
//              times a periodic Hann window; X = |FFT| * 2 / (window sum), bins 0 to 460 (0 to 4.95 kHz)
//   peaks      the local maxima of X between bins 3 and 324 (25 Hz to 3.5 kHz) above 1e-5, each refined by a
//              parabola through the dB values of it and its neighbours; the 60 largest per frame
//   whitening  each peak divided by the largest X within a third of an octave either side (bins clipped to 0..460):
//              the strongest peak of each neighbourhood reads 1, quieter regions count as much as loud ones
//   HPCP       a harmonic pitch-class profile (Gomez 2006): each whitened peak, squared, is credited to the pitch
//              classes near f / h for h = 1 to 4, weighted 0.6^(h-1) and by cos^2 over a window 4/3 semitone wide
//              (C = 0, A4 = 440 Hz); the frames' profiles averaged, with no per-frame normalisation
//   decision   Pearson correlation of the profile with the 24 keys by each of the edma, bgate and braw profiles
//              (`HPCPKeyProfiles.swift`), averaged over the three; the highest mean wins (ties to the first key in
//              the order major C..B, minor C..B); margin = best mean minus second; agree = how many of the three
//              profiles pick the winner alone; sure = all three agree and the margin is at least 0.08
//
// Library-blind: every parameter is the reference's, none changed in the port. The arithmetic follows numpy's types
// where they change numbers: the frame, the spectrum, the dB values, the parabola, the peak magnitudes, the envelope
// bounds and the semitone positions are float32 as numpy computes them; the frequencies, the weights and the profile
// sums are float64. One detail differs: the FFT. numpy (2.x) transforms float32 frames in single precision; the port
// transforms in double precision (`RealFFT`) and rounds the magnitudes to float32. Quiet bins, which whitening lifts
// to full weight, therefore differ by about 1e-7 of the frame's level; Fixtures/key_parity.json measures the effect
// stage by stage (KeyTests.swift).

/// Research R's whitened-HPCP key estimator (see above).
public enum HPCPKey {
    /// The rate it reads: 44,100 Hz (other rates are resampled first, as the reference's `load44` does).
    public static let sampleRate = 44100
    /// Frame and hop, in samples (93 ms, no overlap).
    public static let frameSize = 4096, hop = 4096
    /// The peak band: bins 3 to 324 (`ceil(25 N / SR)` to `int(3500 N / SR) - 1`), 26.9 Hz to 3.49 kHz.
    public static let minFrequency: Float = 25, maxFrequency: Float = 3500
    static let firstPeakBin = 3, endPeakBin = 325
    /// Bins the whitening envelope may reach: 0 to 460 (`int(3500 sqrt(2) N / SR) + 2` bins).
    public static let envelopeBins = 461
    /// Peaks kept per frame, and the smallest magnitude a peak may have (a full-scale sine reads 1).
    public static let peaksPerFrame = 60
    public static let peakFloor = Float(1e-5)
    /// Harmonics credited per peak, and the weight's decay per harmonic (Gomez 2006, eq. 3.35, s = 0.6).
    public static let harmonics = 4
    public static let harmonicDecay = 0.6
    /// The cos^2 weighting window's width in semitones (Gomez 2006, eq. 3.33, l = 4/3).
    public static let windowSemitones = 4.0 / 3.0
    /// The margin a sure key needs (set on research R's dev split).
    public static let marginSure = 0.08

    /// The periodic Hann window as the reference builds it, `np.hanning(N + 1)[:-1]` in float32:
    /// 0.5 + 0.5 cos(pi n / N) for n = -N, -N + 2, ..., N - 2.
    public static let window: [Float] = (0..<frameSize).map {
        Float(0.5 + 0.5 * cos(Double.pi * Double(2 * $0 - frameSize) / Double(frameSize)))
    }
    /// 2 / (the window's sum), so a full-scale sine's peak reads 1: the sum is 2048 exactly, so 2^-10.
    public static let spectrumScale: Float = 2 / Float(window.reduce(0.0) { $0 + Double($1) })

    /// Full frames in `samples` samples (none when there is less than one frame).
    public static func frameCount(samples n: Int) -> Int { n < frameSize ? 0 : 1 + (n - frameSize) / hop }

    // MARK: - One frame

    /// A spectral peak: its frequency and magnitude after the parabolic refinement, and its whitening envelope (the
    /// largest magnitude within a third of an octave). The whitened magnitude is `magnitude / envelope`.
    public struct Peak: Sendable, Equatable {
        public var frequency: Float
        public var magnitude: Float
        public var envelope: Float

        public init(frequency: Float, magnitude: Float, envelope: Float) {
            self.frequency = frequency
            self.magnitude = magnitude
            self.envelope = envelope
        }

        /// The whitened magnitude, as the reference divides it (`M / max(E, 1e-9)`, float32).
        public var whitened: Float { magnitude / max(envelope, Float(1e-9)) }
    }

    /// The magnitude spectrum of one frame, bins 0 to `envelopeBins - 1`: the `frameSize` samples at `samples` times
    /// the window (float32), transformed by `fft` in double precision, |X| rounded to float32 and scaled.
    static func spectrum(_ samples: UnsafePointer<Float>, fft: RealFFT, input: UnsafeMutablePointer<Double>,
                         real: UnsafeMutablePointer<Double>, imag: UnsafeMutablePointer<Double>,
                         into X: UnsafeMutablePointer<Float>) {
        window.withUnsafeBufferPointer { w in
            var i = 0
            while i < frameSize { input[i] = Double(samples[i] * w[i]); i += 1 }
        }
        fft.forward(UnsafePointer(input), real: real, imag: imag)
        let scale = spectrumScale
        var k = 0
        while k < envelopeBins {
            X[k] = Float((real[k] * real[k] + imag[k] * imag[k]).squareRoot()) * scale
            k += 1
        }
    }

    /// The magnitude spectrum of one frame of `frameSize` samples (bins 0 to `envelopeBins - 1`).
    public static func spectrum(frame: [Float]) -> [Float] {
        precondition(frame.count == frameSize, "a frame is \(frameSize) samples, not \(frame.count)")
        let fft = RealFFT(size: frameSize)
        var input = [Double](repeating: 0, count: frameSize)
        var re = [Double](repeating: 0, count: fft.bins), im = [Double](repeating: 0, count: fft.bins)
        var X = [Float](repeating: 0, count: envelopeBins)
        frame.withUnsafeBufferPointer { f in
            input.withUnsafeMutableBufferPointer { inp in
                re.withUnsafeMutableBufferPointer { r in
                    im.withUnsafeMutableBufferPointer { i in
                        X.withUnsafeMutableBufferPointer { x in
                            spectrum(f.baseAddress!, fft: fft, input: inp.baseAddress!, real: r.baseAddress!,
                                     imag: i.baseAddress!, into: x.baseAddress!)
                        }
                    }
                }
            }
        }
        return X
    }

    /// The peaks of one frame's magnitude spectrum (at least `envelopeBins` values), largest first, at most
    /// `peaksPerFrame` (ties in magnitude in bin order), each with its whitening envelope. As the reference: a bin k
    /// in 3...324 is a peak when X[k] > X[k-1] in dB, X[k] >= X[k+1] in dB and X[k] > 1e-5; with a, b, c its and its
    /// neighbours' dB (20 log10(X + 1e-10)), p = 0.5 (a - c) / (a - 2b + c) (0 when that is 0), frequency
    /// (k + p) 44100 / 4096 and magnitude 10^((b - 0.25 (a - c) p) / 20); the envelope is the largest X over bins
    /// floor(kf 2^(-1/3)) to ceil(kf 2^(1/3)) with kf = frequency 4096 / 44100, clipped to 0..460.
    public static func peaks(spectrum X: UnsafeBufferPointer<Float>) -> [Peak] {
        precondition(X.count >= envelopeBins, "the peaks need \(envelopeBins) bins, not \(X.count)")
        let tiny = Float(1e-10)
        @inline(__always) func dB(_ k: Int) -> Float { 20 * log10(X[k] + tiny) }
        var found: [(magnitude: Float, frequency: Float, bin: Int)] = []
        found.reserveCapacity(endPeakBin - firstPeakBin)
        var a = dB(firstPeakBin - 1), b = dB(firstPeakBin)
        var k = firstPeakBin
        while k < endPeakBin {
            let c = dB(k + 1)
            if b > a && b >= c && X[k] > peakFloor {
                let den = a - 2 * b + c
                let p: Float = den != 0 ? 0.5 * (a - c) / den : 0
                let frequency = Float((Double(k) + Double(p)) * Double(sampleRate) / Double(frameSize))
                let magnitude = pow(Float(10), (b - 0.25 * (a - c) * p) / 20)
                found.append((magnitude, frequency, k))
            }
            a = b
            b = c
            k += 1
        }
        found.sort { $0.magnitude != $1.magnitude ? $0.magnitude > $1.magnitude : $0.bin < $1.bin }
        let down = Float(pow(2.0, -1.0 / 3.0)), up = Float(pow(2.0, 1.0 / 3.0))
        let last = envelopeBins - 1
        return found.prefix(peaksPerFrame).map { peak in
            let kf = peak.frequency * Float(frameSize) / Float(sampleRate)
            let lo = min(max(Int((kf * down).rounded(.down)), 0), last)
            let hi = min(max(Int((kf * up).rounded(.up)), lo), last)
            var envelope = X[lo]
            var j = lo + 1
            while j <= hi { envelope = max(envelope, X[j]); j += 1 }
            return Peak(frequency: peak.frequency, magnitude: peak.magnitude, envelope: envelope)
        }
    }

    /// `peaks(spectrum:)` of an array.
    public static func peaks(spectrum X: [Float]) -> [Peak] { X.withUnsafeBufferPointer { peaks(spectrum: $0) } }

    /// Adds one frame's HPCP to `pcp` (12 values, C first): for h = 1 to 4 and each peak in turn (the reference's
    /// order), the semitone position s = 12 log2(f / (440 h)) + 9 (float32), and for each pitch class c from
    /// floor(s) - 1 to floor(s) + 2 within 2/3 semitone of s, cos^2(pi (s - c) / (4/3)) 0.6^(h-1) times the squared
    /// whitened magnitude, added to bin c mod 12. Peaks outside 25 Hz to 3.5 kHz, or of no magnitude, add nothing.
    public static func addHPCP(_ peaks: [Peak], to pcp: inout [Double]) {
        precondition(pcp.count == 12, "an HPCP has 12 bins")
        let width = windowSemitones, half = windowSemitones / 2
        let squared: [(frequency: Float, a2: Double)] = peaks.map { p in
            let valid = p.frequency >= minFrequency && p.frequency <= maxFrequency && p.magnitude > 0
            let a = p.whitened
            return (max(p.frequency, Float(1e-3)), valid ? Double(a * a) : 0)
        }
        for h in 1...harmonics {
            let ref = Float(Double(h) * 440.0)
            let decay = pow(harmonicDecay, Double(h - 1))
            for offset in -1...2 {
                for (f, a2) in squared {
                    let s: Float = 12 * log2(f / ref) + 9
                    let c = Int(s.rounded(.down)) + offset
                    let d = Double(s) - Double(c)
                    if abs(d) <= half {
                        let w = cos(Double.pi * d / width)
                        pcp[Py.mod(c, 12)] += w * w * decay * a2
                    }
                }
            }
        }
    }

    // MARK: - The whole track

    /// The track's HPCP: the mean of every full frame's (zeros, and 0 frames, for audio shorter than one frame).
    public static func hpcp(_ mono: [Float]) -> (pcp: [Double], frames: Int) {
        var sum = [Double](repeating: 0, count: 12)
        let n = frameCount(samples: mono.count)
        forEachFrame(mono) { _, peaks in
            var frame = [Double](repeating: 0, count: 12)
            addHPCP(peaks, to: &frame)
            for c in 0..<12 { sum[c] += frame[c] }
        }
        return (n == 0 ? sum : sum.map { $0 / Double(n) }, n)
    }

    /// Calls `body(t, peaks)` for each full frame in turn with its peaks.
    public static func forEachFrame(_ mono: [Float], _ body: (_ frame: Int, _ peaks: [Peak]) -> Void) {
        let n = frameCount(samples: mono.count)
        guard n > 0 else { return }
        let fft = RealFFT(size: frameSize)
        var input = [Double](repeating: 0, count: frameSize)
        var re = [Double](repeating: 0, count: fft.bins), im = [Double](repeating: 0, count: fft.bins)
        var X = [Float](repeating: 0, count: envelopeBins)
        mono.withUnsafeBufferPointer { y in
            input.withUnsafeMutableBufferPointer { inp in
                re.withUnsafeMutableBufferPointer { r in
                    im.withUnsafeMutableBufferPointer { i in
                        X.withUnsafeMutableBufferPointer { x in
                            for t in 0..<n {
                                spectrum(y.baseAddress! + t * hop, fft: fft, input: inp.baseAddress!, real: r.baseAddress!,
                                         imag: i.baseAddress!, into: x.baseAddress!)
                                body(t, peaks(spectrum: UnsafeBufferPointer(x)))
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - The decision

    /// The decision on one HPCP with one table of profiles.
    public struct Decision: Sendable, Equatable {
        /// The winner: its Camelot code, tonic (0 = C) and mode ("major" or "minor").
        public var camelot: String
        public var pitchClass: Int
        public var mode: String
        /// The winner's mean correlation, and its lead over the second key's.
        public var meanR: Double
        public var margin: Double
        /// How many of the three profiles pick the winner on their own (0 to 3).
        public var agree: Int
        /// All three agree and the margin is at least 0.08.
        public var sure: Bool
        /// Each profile's own winner: its name, Camelot code and correlation, in the table's order.
        public var profileKeys: [(name: String, camelot: String, r: Double)]
        /// The 24 mean correlations (major C..B, then minor C..B), and each profile's 24, in the table's order.
        public var meanCorrelations: [Double]
        public var correlations: [[Double]]

        /// The tonic's name as the lab spells it ("C#", not "Db").
        public var key: String { KeyEstimator.pitchNames[pitchClass] }

        public static func == (a: Decision, b: Decision) -> Bool {
            a.camelot == b.camelot && a.meanR == b.meanR && a.margin == b.margin && a.agree == b.agree
                && a.sure == b.sure && a.meanCorrelations == b.meanCorrelations && a.correlations == b.correlations
        }
    }

    /// The Camelot code of key index i (major C..B, then minor C..B), key_parity.py's `cam24`.
    public static func camelot(index i: Int) -> String { Camelot.code(pitchClass: i % 12, major: i < 12) }

    /// The 24 correlations of `pcp` with one profile pair, key_parity.py's `corr24(c, km(p))`: the HPCP less its mean,
    /// over its norm, against each key's profile (the pair rolled to each tonic, less its mean, over its norm), major
    /// C..B then minor C..B; all zero for a flat HPCP. numpy's summation order and dot product (`Py`).
    public static func correlations(_ pcp: [Double], _ profile: HPCPProfile) -> [Double] {
        precondition(pcp.count == 12, "an HPCP has 12 bins")
        let mean = Py.pairwiseSum(pcp) / 12
        let c = pcp.map { $0 - mean }
        let n = Py.norm(c)
        guard n > 0 else { return [Double](repeating: 0, count: 24) }
        var out: [Double] = []
        out.reserveCapacity(24)
        for weights in [profile.major, profile.minor] {
            for s in 0..<12 {
                var q = KeyEstimator.roll(weights, s)
                let qm = Py.pairwiseSum(q) / 12
                q = q.map { $0 - qm }
                let qn = Py.norm(q)
                q = q.map { $0 / qn }
                out.append(Py.dot(q, c) / n)
            }
        }
        return out
    }

    /// The decision on an HPCP (key_parity.py's `decide`) with the given table (by default the literature's).
    public static func decide(_ pcp: [Double], table: Table = .literature) -> Decision {
        let profiles = table.profiles
        let rs = profiles.map { correlations(pcp, $0) }
        var mean = [Double](repeating: 0, count: 24)
        for r in rs { for i in 0..<24 { mean[i] += r[i] } }
        mean = mean.map { $0 / Double(profiles.count) }
        func firstMax(_ v: [Double], skipping skip: Int? = nil) -> Int {
            var best = -1
            for i in v.indices where i != skip && (best < 0 || v[i] > v[best]) { best = i }
            return best
        }
        let top = firstMax(mean), second = firstMax(mean, skipping: top)
        let margin = mean[top] - mean[second]
        let own = rs.map { firstMax($0) }
        let agree = own.filter { $0 == top }.count
        return Decision(camelot: camelot(index: top), pitchClass: top % 12, mode: top < 12 ? "major" : "minor",
                        meanR: mean[top], margin: margin, agree: agree,
                        sure: agree == profiles.count && margin >= marginSure,
                        profileKeys: zip(profiles, zip(own, rs)).map { ($0.name, camelot(index: $1.0), $1.1[$1.0]) },
                        meanCorrelations: mean, correlations: rs)
    }

    /// The method's result for a track: its HPCP and frame count, the decision with the literature's profiles (the
    /// engine's key) and the same with key_light.py's (the parity reference: what mixer/key_parity.py decides).
    public struct Result: Sendable, Equatable {
        public var pcp: [Double]
        public var frames: Int
        public var decision: Decision
        public var parity: Decision
        /// Whitening is part of the method (always on); written into the record as research R asked.
        public var whitening: Bool { true }
    }

    public enum EstimateError: Error, Equatable, CustomStringConvertible {
        case resampleFirst(sampleRate: Int)
        public var description: String {
            switch self {
            case .resampleFirst(let rate): return "the HPCP key method reads 44100 Hz audio; resample \(rate) Hz audio first"
            }
        }
    }

    /// The key of mono audio at 44.1 kHz (any other rate throws `resampleFirst`).
    public static func estimate(_ mono: [Float], sampleRate rate: Int) throws -> Result {
        guard rate == sampleRate else { throw EstimateError.resampleFirst(sampleRate: rate) }
        let (pcp, frames) = hpcp(mono)
        return Result(pcp: pcp, frames: frames, decision: decide(pcp, table: .literature),
                      parity: decide(pcp, table: .keyLight))
    }
}
