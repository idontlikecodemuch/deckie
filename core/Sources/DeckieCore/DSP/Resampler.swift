import Foundation
import DeckieAudio

/// Sample-rate conversion by a rational factor, built to stand in for soxr at quality "HQ", the lab's resampler:
/// `soxr.resample(y, sr, 44100)` for files not at 44.1 kHz and `soxr.resample(mono, 44100, 22050)` and
/// `soxr.resample(mono, 44100, 16000)` for the spectral features and the vocal model (mixer/analyze.py), and
/// `librosa.resample(y, orig_sr=sr, target_sr=22050, res_type="soxr_hq")` for the key estimator (mixer/key_light.py).
///
/// The filter. soxr's HQ filter was measured from its impulse response (an impulse at every input phase; at 2:1 the
/// fit is in core/Tools/make_resample_fixtures.py, `--fit`). Between 44.1 and 22.05 kHz, both ways, it is a single
/// linear-phase Kaiser-windowed sinc:
///
///   h(t) = sinc(2 fc t) I0(beta sqrt(1 - (t / T)^2)) / I0(beta)  for |t| < T, else 0,   sinc(x) = sin(pi x) / (pi x)
///
/// with the cutoff fc = 0.956872 of the lower rate's Nyquist frequency (the -6 dB point: 10,549.5 Hz between 44.1 and
/// 22.05 kHz), beta = 13.04, and the half-length T = 97.25 periods of the lower rate (194.5 input samples from 44.1 to
/// 22.05 kHz, so 389 taps). Those three numbers reproduce soxr's impulse response within 6e-8 at every point (its
/// peak is 0.48), which is soxr's own single-precision noise; `Design.soxrHQ` holds them, and this type uses them at
/// every ratio, scaled to the lower rate. The response: flat within 1e-5 dB to 0.9 of the lower Nyquist frequency,
/// -3 dB at 0.951, -6 dB at 0.957, and at least 126 dB down from the lower Nyquist frequency on, so nothing above it
/// folds back (or is imaged) above -126 dB. At other ratios (48 to 44.1 kHz, 44.1 to 16 kHz and back) soxr adds a
/// second, interpolating stage: its passband droops 0.007 to 0.008 dB by 0.9 of the lower Nyquist frequency, its
/// transition band differs by up to 0.05 dB above -3 dB, and its first few output samples start up differently; there
/// the two outputs agree to about -60 dB on noise rather than -120 (ResampleTests measures all of it).
///
/// The algorithm is the textbook polyphase filter (the same design method as soxr's; no soxr code is used). For a ratio
/// up / down (the two rates divided by their greatest common divisor), output sample k sits at input position
/// k down / up: its whole part i and its phase (k down) mod up pick one of `up` sets of taps, which are the filter
/// sampled at that fractional offset; the output is the dot product of those taps with the input around sample i.
/// Each set is scaled to sum to 1 (so a constant comes out unchanged) and kept as Float, and the dot product runs in
/// Float with eight running sums, as soxr's HQ setting runs in single precision. The input counts as zero beyond its
/// ends. Output k is centred on input time k / outputRate exactly: no delay, as soxr compensates its own.
///
/// Length: `outputCount(for:)` is soxr's, the input length times the ratio rounded half up; librosa.resample, which the
/// lab's key estimator goes through, then pads or cuts to the ratio rounded up (`process(_:count:)`).
///
/// Cost: each output sample is a dot product of 2 T periods of the lower rate's worth of input (392 taps from 44.1 to
/// 22.05 kHz, 544 from 44.1 to 16 kHz, 216 from 48 to 44.1 kHz, 200 when upsampling), so four minutes of stereo take
/// 0.5 to 0.75 s in a release build at each of those ratios (a SIMD loop) and six to eight seconds in a debug build,
/// which runs the same arithmetic one Float at a time. The taps take `up` times that many floats: 350 KB from 16 to
/// 44.1 kHz.
public struct Resampler: Sendable {
    /// The filter's shape, in units of the lower of the two rates.
    public struct Design: Sendable, Equatable {
        /// The cutoff, as a fraction of the lower rate's Nyquist frequency (where the response is -6 dB).
        public var cutoff: Double
        /// The Kaiser window's beta.
        public var beta: Double
        /// Half the filter's length, in periods of the lower rate.
        public var halfLength: Double

        public init(cutoff: Double, beta: Double, halfLength: Double) {
            self.cutoff = cutoff
            self.beta = beta
            self.halfLength = halfLength
        }

        /// soxr's "HQ" (its default, and librosa's "soxr_hq"), as measured: see `Resampler`.
        public static let soxrHQ = Design(cutoff: 0.956872, beta: 13.04, halfLength: 97.25)
    }

    public let inputRate: Int
    public let outputRate: Int
    /// The ratio in lowest terms: `outputRate / inputRate = up / down`.
    public let up: Int
    public let down: Int
    public let design: Design
    /// Taps in each of the `up` phases (a multiple of 8; the last few may be zero).
    public let tapsPerPhase: Int
    /// The first tap of every phase reads input sample `i - leading`, where i is the whole part of the position.
    public let leading: Int
    /// The `up` phases, `tapsPerPhase` Float values each: phase p, tap j at `coefficients[p * tapsPerPhase + j]`.
    public let coefficients: [Float]

    /// A resampler from `inputRate` to `outputRate` (both in Hz, both positive). Equal rates copy the samples through.
    /// Designing the filter takes a few milliseconds; keep the resampler to reuse it.
    public init(from inputRate: Int, to outputRate: Int, design: Design = .soxrHQ) {
        precondition(inputRate > 0 && outputRate > 0, "sample rates must be positive")
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        let g = gcd(inputRate, outputRate)
        let L = outputRate / g, M = inputRate / g
        self.inputRate = inputRate
        self.outputRate = outputRate
        self.up = L
        self.down = M
        self.design = design
        if L == M {
            tapsPerPhase = 0
            leading = 0
            coefficients = []
            return
        }
        // Work on the fine grid of rate L * inputRate (= M * outputRate), where both rates' samples fall on whole
        // positions u. One period of the lower rate is max(L, M) positions there.
        let unit = Double(max(L, M))
        let halfWidth = design.halfLength * unit             // taps where |u| < halfWidth
        let fc = design.cutoff / (2 * unit)                  // cycles per fine-grid position
        let reach = Int(halfWidth.rounded(.down))            // the largest |u| that can carry a tap
        // The filter at u = 0 ... reach; it is symmetric, h(-u) = h(u).
        let i0beta = TruePeak.besselI0(design.beta)
        let table = (0...reach).map { u -> Double in
            let x = Double(u)
            if x >= halfWidth { return 0 }
            let r = x / halfWidth
            let window = TruePeak.besselI0(design.beta * (1 - r * r).squareRoot()) / i0beta
            if u == 0 { return window }
            let a = Double.pi * 2 * fc * x
            return sin(a) / a * window
        }
        // Phase p, tap j reads input i - D + j and takes h at u = p + (D - j) L. The largest D with a tap in it is
        // floor(reach / L) (phase 0); the last tap of any phase is at j = D + floor((reach + L - 1) / L).
        let D = reach / L
        let last = D + (reach + L - 1) / L
        let K = (last + 1 + 7) / 8 * 8
        var c = [Float](repeating: 0, count: L * K)
        for p in 0..<L {
            var taps = [Double](repeating: 0, count: K)
            var sum = 0.0
            for j in 0..<K {
                let u = abs(p + (D - j) * L)
                if u <= reach {
                    taps[j] = table[u]
                    sum += table[u]
                }
            }
            for j in 0..<K { c[p * K + j] = Float(taps[j] / sum) }
        }
        tapsPerPhase = K
        leading = D
        coefficients = c
    }

    /// soxr's output length for `inputCount` samples: inputCount * up / down rounded half up.
    public func outputCount(for inputCount: Int) -> Int {
        (2 * inputCount * up + down) / (2 * down)
    }

    /// librosa.resample's output length: inputCount * up / down rounded up (its `fix_length`).
    public func librosaCount(for inputCount: Int) -> Int {
        (inputCount * up + down - 1) / down
    }

    /// `x` resampled: `outputCount(for: x.count)` samples, output k at input time k / outputRate.
    public func process(_ x: [Float]) -> [Float] {
        process(x, count: outputCount(for: x.count))
    }

    /// `x` resampled to exactly `count` samples. Samples past soxr's own length (`outputCount(for:)`) are zeros, as
    /// librosa.resample pads them (pass `librosaCount(for: x.count)` for its length); a smaller count cuts the end.
    public func process(_ x: [Float], count: Int) -> [Float] {
        if up == down { return Array(x.prefix(count)) + [Float](repeating: 0, count: max(0, count - x.count)) }
        let computed = min(count, outputCount(for: x.count))
        var out = [Float](repeating: 0, count: max(count, 0))
        if computed <= 0 { return out }
        x.withUnsafeBufferPointer { xb in
            out.withUnsafeMutableBufferPointer { ob in
                run(input: xb.baseAddress, count: x.count, stride: 1, into: ob.baseAddress!, outputs: computed,
                    outputStride: 1)
            }
        }
        return out
    }

    /// Every channel of `buffer` resampled (soxr's length), as an `AudioBuffer` at `outputRate`.
    public func process(_ buffer: AudioBuffer) -> AudioBuffer {
        precondition(buffer.sampleRate == inputRate,
                     "a \(buffer.sampleRate) Hz buffer through a \(inputRate) Hz resampler")
        if up == down { return buffer }
        let ch = buffer.channelCount, n = buffer.frames
        let frames = outputCount(for: n)
        var out = [Float](repeating: 0, count: frames * ch)
        if frames > 0 {
            buffer.samples.withUnsafeBufferPointer { xb in
                out.withUnsafeMutableBufferPointer { ob in
                    for c in 0..<ch {
                        run(input: xb.baseAddress.map { $0 + c }, count: n, stride: ch, into: ob.baseAddress! + c,
                            outputs: frames, outputStride: ch)
                    }
                }
            }
        }
        return AudioBuffer(sampleRate: outputRate, channelCount: ch, samples: out)
    }

    /// `x` from `inputRate` to `outputRate` with soxr's HQ design (builds a resampler each call).
    public static func resample(_ x: [Float], from inputRate: Int, to outputRate: Int) -> [Float] {
        Resampler(from: inputRate, to: outputRate).process(x)
    }

    /// `buffer` at `outputRate` with soxr's HQ design (builds a resampler each call).
    public static func resample(_ buffer: AudioBuffer, to outputRate: Int) -> AudioBuffer {
        Resampler(from: buffer.sampleRate, to: outputRate).process(buffer)
    }

    /// The conversion of one channel: `count` input samples `stride` apart from `input` (nil when there are none),
    /// `outputs` samples written `outputStride` apart from `output`. The input is copied with `leading` zeros in front
    /// and zeros after, so the dot products need no bounds checks; loops use raw pointers so that a debug build stays
    /// usable.
    private func run(input: UnsafePointer<Float>?, count n: Int, stride: Int, into output: UnsafeMutablePointer<Float>,
                     outputs: Int, outputStride: Int) {
        let L = up, M = down, K = tapsPerPhase, D = leading
        let lastWhole = ((outputs - 1) * M) / L
        let padded = max(D + n, lastWhole + K)
        let work = UnsafeMutablePointer<Float>.allocate(capacity: padded)
        defer { work.deallocate() }
        work.initialize(repeating: 0, count: padded)
        if let input {
            var src = input, dst = work + D
            let end = work + D + n
            while dst < end {
                dst.pointee = src.pointee
                dst += 1
                src += stride
            }
        }
        coefficients.withUnsafeBufferPointer { cb in
            let taps = cb.baseAddress!
            var whole = 0, phase = 0
            var o = output
            let oEnd = output + outputs * outputStride
            while o < oEnd {
                #if DEBUG
                // The same arithmetic as below, lane by lane: SIMD types are about twenty times slower than plain
                // Floats in a debug build, where nothing is inlined.
                var h = taps + phase * K
                var s = work + whole
                let hEnd = h + K
                var a0: Float = 0, a1: Float = 0, a2: Float = 0, a3: Float = 0
                var a4: Float = 0, a5: Float = 0, a6: Float = 0, a7: Float = 0
                while h < hEnd {
                    a0 += h.pointee * s.pointee
                    a1 += (h + 1).pointee * (s + 1).pointee
                    a2 += (h + 2).pointee * (s + 2).pointee
                    a3 += (h + 3).pointee * (s + 3).pointee
                    a4 += (h + 4).pointee * (s + 4).pointee
                    a5 += (h + 5).pointee * (s + 5).pointee
                    a6 += (h + 6).pointee * (s + 6).pointee
                    a7 += (h + 7).pointee * (s + 7).pointee
                    h += 8
                    s += 8
                }
                o.pointee = ((a0 + a1) + (a2 + a3)) + ((a4 + a5) + (a6 + a7))
                #else
                // Eight running sums in one vector: tap j goes to sum j mod 8 (no fused multiply-add, as above).
                var h = UnsafeRawPointer(taps + phase * K)
                var s = UnsafeRawPointer(work + whole)
                let hEnd = h + 4 * K
                var acc = SIMD8<Float>()
                while h < hEnd {
                    acc += h.loadUnaligned(as: SIMD8<Float>.self) * s.loadUnaligned(as: SIMD8<Float>.self)
                    h += 32
                    s += 32
                }
                o.pointee = ((acc[0] + acc[1]) + (acc[2] + acc[3])) + ((acc[4] + acc[5]) + (acc[6] + acc[7]))
                #endif
                o += outputStride
                phase += M
                if phase >= L {
                    whole += phase / L
                    phase %= L
                }
            }
        }
    }
}
