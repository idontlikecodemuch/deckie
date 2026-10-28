import Foundation
import Testing
import DeckieAudio
import DeckieCore

/// Fixtures/resample.json, written by Tools/make_resample_fixtures.py (soxr at quality "HQ", the lab's resampler).
struct ResampleFixture: Decodable {
    struct Level: Decodable {
        var f: Double
        var gainDB: Double?
        /// [frequency, level in dB relative to the tone] of each alias or image below the output's Nyquist frequency.
        var spurs: [[Double]]
        enum CodingKeys: String, CodingKey { case f, spurs, gainDB = "gain_db" }
    }
    struct Signal: Decodable {
        var kind: String
        var outSamples: Int, midStart: Int
        /// The RMS of soxr's whole output.
        var rms: Double
        var head: [Double], mid: [Double], tail: [Double]
        var levels: [Level]?
        var delay: Double?, delayMax: Double?
        enum CodingKeys: String, CodingKey {
            case kind, rms, head, mid, tail, levels, delay
            case outSamples = "out_samples", midStart = "mid_start", delayMax = "delay_max"
        }
    }
    struct Response: Decodable {
        var ripple045DB: Double, ripple090DB: Double, minus3DBAt: Double, minus6DBAt: Double, stopbandDB: Double
        enum CodingKeys: String, CodingKey {
            case ripple045DB = "ripple_045_db", ripple090DB = "ripple_090_db", minus3DBAt = "minus3_db_at"
            case minus6DBAt = "minus6_db_at", stopbandDB = "stopband_db"
        }
    }
    struct Ratio: Decodable {
        var inRate: Int, outRate: Int, samples: Int, noiseSeed: UInt64
        var tones: [Double]
        var signals: [Signal]
        var response: Response
        var lengths: [[Int]]
        enum CodingKeys: String, CodingKey {
            case samples, tones, signals, response, lengths
            case inRate = "in_rate", outRate = "out_rate", noiseSeed = "noise_seed"
        }
        var label: String { "\(Py.fixed(Double(inRate) / 1000, 2)) -> \(Py.fixed(Double(outRate) / 1000, 2)) kHz" }
    }
    var versions: [String: String]
    var toneAmp: Double
    var analysisBeta: Double
    var ratios: [Ratio]
    enum CodingKeys: String, CodingKey {
        case versions, ratios
        case toneAmp = "tone_amp", analysisBeta = "analysis_beta"
    }

    static let shared = try! RepoPaths.fixture("resample.json", as: ResampleFixture.self)
}

/// The script's test signals, operation for operation, rounded to float32.
enum ResampleSignals {
    static func make(_ kind: String, rate: Int, samples n: Int, seed: UInt64, tones: [Double], amp: Double) -> [Float] {
        let fin = Double(rate)
        var y = [Double](repeating: 0, count: n)
        switch kind {
        case "sweep":
            let f0 = 20.0, f1 = fin / 2.0
            for i in 0..<n {
                let t = Double(i)
                y[i] = 0.5 * sin(2.0 * Double.pi * (f0 * t / fin + (f1 - f0) * t * t / (2.0 * fin * Double(n))))
            }
        case "multitone":
            for f in tones {
                let w = 2.0 * Double.pi * f / fin
                for i in 0..<n { y[i] += amp * sin(w * Double(i)) }
            }
        case "noise":
            var g = SplitMix64(seed)
            for i in 0..<n { y[i] = 0.5 * (2.0 * g.uniform() - 1.0) }
        default:  // clicks
            y[0] = 0.8; y[n / 3] = -0.6; y[n / 2] = 0.7; y[n - 1] = 0.8
        }
        return y.map { Float($0) }
    }
}

/// The script's tone measurement: a Kaiser-windowed DFT (beta 20) over the output clear of the filter's transients.
struct ToneMeter {
    let a: Int, b: Int
    let window: [Double]
    let windowSum: Double
    let outRate: Double

    init(inRate: Int, outRate: Int, count: Int, beta: Double) {
        let lower = Double(min(inRate, outRate))
        let edge = Int((1.25 * Resampler.Design.soxrHQ.halfLength * Double(outRate) / lower).rounded(.up))
        a = edge
        b = count - edge
        let m = b - a
        func i0(_ x: Double) -> Double {
            let q = x * x / 4
            var term = 1.0, sum = 1.0, k = 1.0
            while term > sum * 1e-17 { term *= q / (k * k); sum += term; k += 1 }
            return sum
        }
        let alpha = Double(m - 1) / 2, i0b = i0(beta)
        window = (0..<m).map { i0(beta * max(0, 1 - pow((Double($0) - alpha) / alpha, 2)).squareRoot()) / i0b }
        windowSum = window.reduce(0, +)
        self.outRate = Double(outRate)
    }

    /// The windowed DFT of y at `frequency` Hz (k the absolute output index); nil for y takes sin(omega k), the output
    /// a zero-delay conversion of the tone would give.
    func dft(_ y: [Float]?, _ frequency: Double) -> (re: Double, im: Double) {
        let om = 2 * Double.pi * frequency / outRate
        var re = 0.0, im = 0.0
        for k in a..<b {
            let v = window[k - a] * (y.map { Double($0[k]) } ?? sin(om * Double(k)))
            re += v * cos(om * Double(k))
            im -= v * sin(om * Double(k))
        }
        return (re, im)
    }

    /// The level in dB of a tone at `frequency`, relative to the input amplitude `amp`.
    func levelDB(_ y: [Float], _ frequency: Double, amp: Double) -> Double {
        let (re, im) = dft(y, frequency)
        return 20 * log10(max(2 * hypot(re, im) / windowSum, 1e-30) / amp)
    }

    /// The delay in output samples of a passband tone: the phase of the output against a zero-delay sine.
    func delay(_ y: [Float], _ frequency: Double) -> Double {
        let (yr, yi) = dft(y, frequency), (rr, ri) = dft(nil, frequency)
        let phase = atan2(yi * rr - yr * ri, yr * rr + yi * ri)
        return -phase / (2 * Double.pi * frequency / outRate)
    }
}

@Suite struct ResamplerTests {
    let fx = ResampleFixture.shared

    /// The output length is soxr's (the input length times the ratio, rounded half up), checked against soxr's own
    /// lengths for eleven input lengths per ratio; librosa's length is the ratio rounded up.
    @Test func lengthsMatchSoxr() {
        for ratio in fx.ratios {
            let r = Resampler(from: ratio.inRate, to: ratio.outRate)
            for pair in ratio.lengths {
                #expect(r.outputCount(for: pair[0]) == pair[1], "\(ratio.label): \(pair[0]) samples")
            }
            #expect(r.process([Float](repeating: 0.25, count: 3)).count == r.outputCount(for: 3))
            #expect(r.process([]).isEmpty)
        }
        let r = Resampler(from: 44100, to: 16000)
        #expect(r.outputCount(for: 1001) == 363 && r.librosaCount(for: 1001) == 364)
        let y = r.process([Float](repeating: 0.5, count: 1001), count: 364)
        #expect(y.count == 364 && y[363] == 0 && y[362] != 0)
    }

    /// Against soxr on the four signals at the six ratios: the RMS difference over a middle stretch of 256 samples
    /// (the interior) and over the first and last 48 (the edges), each relative to the RMS of soxr's whole output.
    /// At 2:1 the filter is soxr's own and the two agree to soxr's single-precision noise. At the other ratios soxr
    /// adds a second stage (its passband droops 0.007 to 0.008 dB by 0.9 of the lower Nyquist frequency and its
    /// transition band is shaped a little differently) and starts up differently: its first few output samples miss
    /// part of the filter's response to the first input samples (by 3 to 5 percent of a click on sample 0, by about
    /// 1e-4 over the first 128 outputs), so the clicks' edges differ by more than the rest.
    @Test func samplesAgainstSoxr() {
        var lines: [String] = []
        for ratio in fx.ratios {
            let r = Resampler(from: ratio.inRate, to: ratio.outRate)
            let twoToOne = ratio.inRate == 2 * ratio.outRate || ratio.outRate == 2 * ratio.inRate
            var row: [String] = []
            for s in ratio.signals {
                let x = ResampleSignals.make(s.kind, rate: ratio.inRate, samples: ratio.samples, seed: ratio.noiseSeed,
                                             tones: ratio.tones, amp: fx.toneAmp)
                let y = r.process(x)
                #expect(y.count == s.outSamples, "\(ratio.label) \(s.kind)")
                guard y.count == s.outSamples else { continue }
                func rmsDB(_ ours: [Float], _ theirs: [Double]) -> Double {
                    let d = zip(ours, theirs).map { (Double($0) - $1) * (Double($0) - $1) }.reduce(0, +)
                    return 10 * log10(max(d / Double(theirs.count), 1e-40) / (s.rms * s.rms))
                }
                let interior = rmsDB(Array(y[s.midStart..<(s.midStart + s.mid.count)]), s.mid)
                let edges = rmsDB(Array(y[0..<s.head.count]) + Array(y[(y.count - s.tail.count)...]), s.head + s.tail)
                row.append("\(s.kind) \(Py.fixed(interior, 1)) / \(Py.fixed(edges, 1))")
                #expect(interior < (twoToOne ? -100 : -40), "\(ratio.label) \(s.kind): interior \(interior) dB")
                let edgeBound = twoToOne ? -100.0 : s.kind == "click" ? 0 : -30
                #expect(edges < edgeBound, "\(ratio.label) \(s.kind): edges \(edges) dB")
            }
            lines.append("  \(ratio.label): " + row.joined(separator: ", "))
        }
        print("resampler against soxr \(fx.versions["soxr"] ?? "?") HQ, RMS difference in dB relative to soxr's output, "
              + "interior / edges:\n" + lines.joined(separator: "\n"))
    }

    /// The multitone measured as the script measures soxr's: each tone's gain, every alias (downsampling) or image
    /// (upsampling) below the output's Nyquist frequency, and the delay on the passband tones.
    @Test func tonesAgainstSoxr() {
        var lines: [String] = []
        for ratio in fx.ratios {
            guard let s = ratio.signals.first(where: { $0.kind == "multitone" }), let levels = s.levels else { continue }
            let r = Resampler(from: ratio.inRate, to: ratio.outRate)
            let x = ResampleSignals.make("multitone", rate: ratio.inRate, samples: ratio.samples, seed: ratio.noiseSeed,
                                         tones: ratio.tones, amp: fx.toneAmp)
            let y = r.process(x)
            let meter = ToneMeter(inRate: ratio.inRate, outRate: ratio.outRate, count: y.count, beta: fx.analysisBeta)
            let lowNyquist = Double(min(ratio.inRate, ratio.outRate)) / 2
            let twoToOne = ratio.inRate == 2 * ratio.outRate || ratio.outRate == 2 * ratio.inRate
            var passWorst = 0.0, edgeWorst = 0.0, deepWorst = 0.0, spurOurs = -400.0, spurSoxr = -400.0
            var delays: [Double] = []
            for level in levels {
                if let soxrGain = level.gainDB {
                    let ours = meter.levelDB(y, level.f, amp: fx.toneAmp)
                    if level.f <= 0.9 * lowNyquist + 1 {
                        passWorst = max(passWorst, abs(ours - soxrGain))
                        delays.append(meter.delay(y, level.f))
                    } else if soxrGain > -3 {
                        edgeWorst = max(edgeWorst, abs(ours - soxrGain))
                    } else {
                        deepWorst = max(deepWorst, abs(ours - soxrGain))
                    }
                }
                for spur in level.spurs {
                    spurOurs = max(spurOurs, meter.levelDB(y, spur[0], amp: fx.toneAmp))
                    spurSoxr = max(spurSoxr, spur[1])
                }
            }
            let delay = delays.map(abs).max() ?? 0
            lines.append("  \(ratio.label): gains within \(String(format: "%.1e", passWorst)) dB of soxr's to 0.9 of the "
                         + "lower Nyquist, \(Py.fixed(edgeWorst, 3)) dB in the transition above -3 dB, "
                         + "\(Py.fixed(deepWorst, 2)) dB below; worst alias or image \(Py.fixed(spurOurs, 1)) dB "
                         + "(soxr \(Py.fixed(spurSoxr, 1))); delay \(String(format: "%.0e", delay)) output samples "
                         + "(soxr \(String(format: "%.0e", s.delayMax ?? .nan)))")
            #expect(passWorst < (twoToOne ? 1e-4 : 0.01), "\(ratio.label)")
            #expect(edgeWorst < (twoToOne ? 0.001 : 0.1), "\(ratio.label)")
            #expect(deepWorst < (twoToOne ? 0.01 : 3), "\(ratio.label)")
            #expect(spurOurs < -120, "\(ratio.label)")
            #expect(delay < 1e-5, "\(ratio.label)")
        }
        print("resampler tones against soxr:\n" + lines.joined(separator: "\n"))
    }

    /// The filter's own response, from its taps (every phase interleaved on the fine grid, zero-padded, one FFT):
    /// passband ripple to 0.45 and to 0.9 of the lower rate's Nyquist frequency, the -3 and -6 dB points, and the
    /// highest stopband level from that Nyquist frequency on; with soxr's, measured the same way from its impulse
    /// responses by the script.
    @Test func filterResponse() {
        var lines: [String] = []
        for ratio in fx.ratios {
            let r = Resampler(from: ratio.inRate, to: ratio.outRate)
            let (L, K, D) = (r.up, r.tapsPerPhase, r.leading)
            let minU = (D - (K - 1)) * L, maxU = (L - 1) + D * L
            var size = 1
            while size < 4 * (maxU - minU + 1) { size *= 2 }
            var h = [Double](repeating: 0, count: size)
            for p in 0..<L { for j in 0..<K { h[p + (D - j) * L - minU] += Double(r.coefficients[p * K + j]) } }
            let (re, im) = RealFFT(size: size).forward(h)
            let dc = hypot(re[0], im[0])
            let fine = Double(ratio.inRate * L), lowNyquist = Double(min(ratio.inRate, ratio.outRate)) / 2
            var lo45 = 0.0, hi45 = 0.0, lo90 = 0.0, hi90 = 0.0, stop = -400.0
            var minus3 = 0.0, minus6 = 0.0
            for k in 0..<re.count {
                let f = Double(k) * fine / Double(size)
                let dB = 20 * log10(max(hypot(re[k], im[k]) / dc, 1e-30))
                if f <= 0.45 * lowNyquist { lo45 = min(lo45, dB); hi45 = max(hi45, dB) }
                if f <= 0.9 * lowNyquist { lo90 = min(lo90, dB); hi90 = max(hi90, dB) }
                if f >= lowNyquist { stop = max(stop, dB) }
                if minus3 == 0 && dB < -3 { minus3 = f / lowNyquist }
                if minus6 == 0 && dB < -20 * log10(2.0) { minus6 = f / lowNyquist }
            }
            let soxr = ratio.response
            func e(_ x: Double) -> String { String(format: "%.1e", x) }
            lines.append("  \(ratio.label) (\(r.up)/\(r.down), \(K) taps a phase): ripple \(e(hi45 - lo45)) dB to 0.45 "
                         + "and \(e(hi90 - lo90)) dB to 0.9 of the lower Nyquist (soxr \(e(soxr.ripple045DB)), "
                         + "\(e(soxr.ripple090DB))); -3 dB at \(Py.fixed(minus3, 4)), -6 dB at \(Py.fixed(minus6, 4)) "
                         + "(soxr \(Py.fixed(soxr.minus3DBAt, 4)), \(Py.fixed(soxr.minus6DBAt, 4))); stopband "
                         + "\(Py.fixed(stop, 1)) dB (soxr \(Py.fixed(soxr.stopbandDB, 1)))")
            #expect(hi90 - lo90 < 1e-4 && hi45 - lo45 < 1e-4, "\(ratio.label)")
            #expect(stop < -120, "\(ratio.label)")
            #expect(abs(minus6 - soxr.minus6DBAt) < 0.002, "\(ratio.label)")
        }
        print("resampler filter response:\n" + lines.joined(separator: "\n"))
    }

    /// A constant comes out unchanged away from the ends (each phase sums to 1), equal rates copy, and a stereo buffer
    /// is each channel resampled.
    @Test func basics() {
        for ratio in fx.ratios {
            let r = Resampler(from: ratio.inRate, to: ratio.outRate)
            let y = r.process([Float](repeating: 0.5, count: 4000))
            let lower = Double(min(ratio.inRate, ratio.outRate))
            let edge = Int((Resampler.Design.soxrHQ.halfLength * Double(ratio.outRate) / lower).rounded(.up)) + 2
            let worst = y[edge..<(y.count - edge)].map { abs(Double($0) - 0.5) }.max()!
            #expect(worst < 2e-7, "\(ratio.label): \(worst)")
        }
        let same = Resampler(from: 44100, to: 44100)
        #expect(same.process([1, 2, 3]) == [1, 2, 3])
        let left = ResampleSignals.make("noise", rate: 48000, samples: 4801, seed: 7, tones: [], amp: 0)
        let right = ResampleSignals.make("sweep", rate: 48000, samples: 4801, seed: 0, tones: [], amp: 0)
        let stereo = AudioBuffer(sampleRate: 48000, channelCount: 2, samples: zip(left, right).flatMap { [$0, $1] })
        let r = Resampler(from: 48000, to: 44100)
        let out = r.process(stereo)
        #expect(out.sampleRate == 44100 && out.channelCount == 2 && out.frames == r.outputCount(for: 4801))
        #expect(out.channel(0) == r.process(left) && out.channel(1) == r.process(right))
        #expect(Resampler.resample(stereo, to: 44100) == out)
    }

    /// Cost: four minutes of stereo through four of the ratios: 0.5 to 0.8 s each in a release build here
    /// (`swift test -c release --filter ResamplerTests/speed`), the target being under 1 s; a debug build runs 15 s,
    /// scales it up, and uses the plain-Float loop (the same arithmetic), about ten times slower. The times are printed;
    /// the ceilings are loose, as in the other speed checks, so only a real regression fails.
    @Test func speed() {
        #if DEBUG
        let length = 15.0, build = "debug build, 15 s scaled up", ceiling = 80.0
        #else
        let length = 240.0, build = "release build", ceiling = 8.0
        #endif
        var lines: [String] = []
        for (fin, fout) in [(44100, 22050), (44100, 16000), (48000, 44100), (22050, 44100)] {
            let n = Int(length * Double(fin))
            var g = SplitMix64(UInt64(fin + fout))
            let buffer = AudioBuffer(sampleRate: fin, channelCount: 2,
                                     samples: (0..<(2 * n)).map { _ in Float(0.5 * (2 * g.uniform() - 1)) })
            let clock = ContinuousClock()
            var r: Resampler? = nil
            let design = seconds(clock.measure { r = Resampler(from: fin, to: fout) })
            var out: AudioBuffer? = nil
            let fourMinutes = seconds(clock.measure { out = r!.process(buffer) }) * 240 / length
            lines.append("  \(fin) -> \(fout): \(Py.fixed(fourMinutes, 2)) s for 4 min of stereo, filter design "
                         + "\(Py.fixed(design * 1000, 1)) ms")
            #expect(out!.frames == r!.outputCount(for: n))
            #expect(fourMinutes < ceiling, "\(fin) -> \(fout)")
        }
        print("resampler speed (\(build)):\n" + lines.joined(separator: "\n"))
    }
}
