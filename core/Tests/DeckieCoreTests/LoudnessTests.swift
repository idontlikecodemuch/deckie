import Foundation
import Testing
import DeckieAudio
import DeckieCore

/// Synthesised test signals; no files.
enum Signal {
    /// A 1 kHz sine in both channels, one level after another: each level in dBFS gives a sine of amplitude
    /// 10^(dB/20), held for the given seconds, with the phase running on across the changes.
    static func tone(_ parts: [(db: Double, seconds: Double)], rate: Int, frequency: Double = 1000) -> AudioBuffer {
        let counts = parts.map { Int(($0.seconds * Double(rate)).rounded()) }
        let total = counts.reduce(0, +)
        var samples = [Float](repeating: 0, count: 2 * total)
        let omega = 2 * Double.pi * frequency / Double(rate)
        // A table of one period is exact for 1 kHz at 44.1 and 48 kHz over 10 ms (441 and 480 samples), and quick.
        let period = rate / 100
        let table = (0..<period).map { sin(omega * Double($0)) }
        samples.withUnsafeMutableBufferPointer { out in
            var i = 0
            for (part, count) in zip(parts, counts) {
                let amp = pow(10, part.db / 20)
                for _ in 0..<count {
                    let v = Float(amp * table[i % period])
                    out[2 * i] = v
                    out[2 * i + 1] = v
                    i += 1
                }
            }
        }
        return AudioBuffer(sampleRate: rate, channelCount: 2, samples: samples)
    }

    /// Something music-like for the speed check and the span check: two tones and noise under a slow swell,
    /// different in each channel. The noise is a fixed linear congruential sequence, so every run is the same.
    static func busy(seconds: Double, rate: Int) -> AudioBuffer {
        let frames = Int(seconds * Double(rate))
        var seed: UInt64 = 0x2545F4914F6CDD1D
        let samples = [Float](unsafeUninitializedCapacity: 2 * frames) { out, count in
            var phaseA = 0.0, phaseB = 0.0, env = 0.0
            let stepA = 2 * Double.pi * 110 / Double(rate), stepB = 2 * Double.pi * 2637 / Double(rate)
            var f = 0
            while f < frames {
                if f % 64 == 0 {  // the slow parts every 64 frames keep generation quick in a debug build
                    env = 0.35 + 0.3 * sin(Double(f) * 2 * Double.pi / (8 * Double(rate)))
                }
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                let noise = Double(Int64(bitPattern: seed) >> 11) * 0x1p-52
                let a = sin(phaseA), b = sin(phaseB)
                out[2 * f] = Float(env * (0.6 * a + 0.2 * b + 0.15 * noise))
                out[2 * f + 1] = Float(env * (0.5 * a + 0.25 * b - 0.15 * noise))
                phaseA += stepA; phaseB += stepB
                if phaseA > Double.pi { phaseA -= 2 * Double.pi }
                if phaseB > Double.pi { phaseB -= 2 * Double.pi }
                f += 1
            }
            count = 2 * frames
        }
        return AudioBuffer(sampleRate: rate, channelCount: 2, samples: samples)
    }
}

func seconds(_ d: Duration) -> Double {
    Double(d.components.seconds) + Double(d.components.attoseconds) * 1e-18
}

@Suite struct KWeightingTests {
    func coefficients(_ f: Biquad) -> [Double] { [f.b0, f.b1, f.b2, f.a1, f.a2] }

    /// (a) The coefficients ITU-R BS.1770-4 publishes for 48 kHz, and what the lab's design gives instead.
    @Test func coefficientsAt48kHz() {
        let publishedShelf = [1.53512485958697, -2.69169618940638, 1.19839281085285, -1.69065929318241, 0.73248077421585]
        let publishedHighPass = [1.0, -2.0, 1.0, -1.99004745483398, 0.99007225036621]

        let itu = KWeighting(sampleRate: 48000, design: .bs1770)
        let ituDev = zip(coefficients(itu.shelf) + coefficients(itu.highPass), publishedShelf + publishedHighPass)
            .map { abs($0 - $1) }.max()!
        print("K-weighting, BS.1770 design at 48 kHz: largest difference from the published coefficients \(ituDev)")
        #expect(ituDev <= 1e-6)

        // At 44.1 kHz: the same analogue filters through the bilinear transform (values from the derivation in
        // KWeighting.init, worked in Python; they guard against a change in that derivation).
        let itu44 = KWeighting(sampleRate: 44100, design: .bs1770)
        let want44 = [1.5308412300503478, -2.6509799951547297, 1.169079079921587, -1.6636551132560204,
                      0.7125954280732254, 1, -2, 1, -1.9891696736297957, 0.9891990357870394]
        for (got, want) in zip(coefficients(itu44.shelf) + coefficients(itu44.highPass), want44) {
            #expect(abs(got - want) <= 1e-9, "BS.1770 design at 44.1 kHz: \(got) vs \(want)")
        }

        // The lab's (pyloudnorm's) design: the Audio EQ Cookbook formulas, values as numpy computes them.
        let lab = KWeighting(sampleRate: 48000)
        let labWant = [1.5351828863637502, -2.691804030199196, 1.198426263333146, -1.6906995865986896,
                       0.7325047060963897, 0.9950442970178917, -1.9900885940357833, 0.9950442970178917,
                       -1.990076284018423, 0.9901009040531438]
        for (got, want) in zip(coefficients(lab.shelf) + coefficients(lab.highPass), labWant) {
            #expect(abs(got - want) <= 1e-12, "pyloudnorm design at 48 kHz: \(got) vs \(want)")
        }
        let lab44 = KWeighting(sampleRate: 44100)
        let lab44Want = [1.5309095946396625, -2.651169032402396, 1.1691668584809876, -1.663750110244495,
                         0.7126575309627482, 0.994607809439911, -1.989215618879822, 0.994607809439911,
                         -1.9892010416922554, 0.9892301960673886]
        for (got, want) in zip(coefficients(lab44.shelf) + coefficients(lab44.highPass), lab44Want) {
            #expect(abs(got - want) <= 1e-12, "pyloudnorm design at 44.1 kHz: \(got) vs \(want)")
        }
        let shelfDev = zip(coefficients(lab.shelf), publishedShelf).map { abs($0 - $1) }.max()!
        let highPassDev = zip(coefficients(lab.highPass), publishedHighPass).map { abs($0 - $1) }.max()!
        func gain(_ k: KWeighting, _ hz: Double) -> Double {
            k.shelf.gainDB(at: hz, sampleRate: 48000) + k.highPass.gainDB(at: hz, sampleRate: 48000)
        }
        let at1k = gain(lab, 1000) - gain(itu, 1000), at10k = gain(lab, 10000) - gain(itu, 10000)
        print("K-weighting, pyloudnorm design at 48 kHz: largest difference from the published shelf \(shelfDev), "
              + "high pass \(highPassDev); response minus BS.1770's: \(at1k) dB at 1 kHz, \(at10k) dB at 10 kHz")
        #expect(shelfDev < 1.2e-4)
        #expect(abs(at1k + 0.043) < 0.005 && abs(at10k + 0.043) < 0.01)
    }
}

@Suite struct LoudnessTests {
    /// (b) EBU Tech 3341, table 1, cases 1 to 5: integrated loudness within 0.1 LU, at 44.1 and 48 kHz, with both
    /// filter designs.
    @Test(arguments: [44100, 48000]) func integratedLoudnessTech3341(rate: Int) {
        let cases: [(name: String, parts: [(db: Double, seconds: Double)], want: Double)] = [
            ("1: -23 dBFS 20 s", [(-23, 20)], -23.0),
            ("2: -33 dBFS 20 s", [(-33, 20)], -33.0),
            ("3: -36, -23, -36", [(-36, 10), (-23, 60), (-36, 10)], -23.0),
            ("4: -72, -36, -23, -36, -72", [(-72, 10), (-36, 10), (-23, 60), (-36, 10), (-72, 10)], -23.0),
            // The 20.1 s makes the mean power of all three parts come to -23.0; nothing is gated out.
            ("5: -26, -20, -26", [(-26, 20), (-20, 20.1), (-26, 20)], -23.0),
        ]
        for c in cases {
            let buffer = Signal.tone(c.parts, rate: rate)
            for design in [KWeighting.Design.pyloudnorm, .bs1770] {
                let got = Loudness.integrated(buffer, design: design)
                print("Tech 3341 case \(c.name), \(rate) Hz, \(design): \(got.map { Py.fixed($0, 4) } ?? "nil") LUFS, "
                      + "expected \(c.want)")
                #expect(got != nil && abs(got! - c.want) <= 0.1, "case \(c.name) at \(rate) Hz, \(design)")
            }
        }
    }

    /// (c) EBU Tech 3342, table 1, cases 1 to 4: loudness range within 1 LU, at 44.1 and 48 kHz.
    @Test(arguments: [44100, 48000]) func loudnessRangeTech3342(rate: Int) {
        let cases: [(name: String, parts: [(db: Double, seconds: Double)], want: Double)] = [
            ("1: -20, -30", [(-20, 20), (-30, 20)], 10),
            ("2: -20, -15", [(-20, 20), (-15, 20)], 5),
            ("3: -40, -20", [(-40, 20), (-20, 20)], 20),
            ("4: -50, -35, -20, -35, -50", [(-50, 20), (-35, 20), (-20, 20), (-35, 20), (-50, 20)], 15),
        ]
        for c in cases {
            let got = Loudness.range(Signal.tone(c.parts, rate: rate))
            print("Tech 3342 case \(c.name), \(rate) Hz: \(got.map { Py.fixed($0, 4) } ?? "nil") LU, expected \(c.want)")
            #expect(got != nil && abs(got! - c.want) <= 1, "case \(c.name) at \(rate) Hz")
        }
    }

    /// Edge cases follow pyloudnorm: too short for one block is nil, silence is minus infinity for the integrated
    /// loudness and nil for the range.
    @Test func shortAndSilentAudio() {
        let short = Signal.tone([(-23, 0.3)], rate: 48000)
        #expect(Loudness.integrated(short) == nil)
        #expect(Loudness.range(short) == nil)  // 0.3 s plus 1.5 s of silence is shorter than a 3 s block
        let silent = AudioBuffer(sampleRate: 48000, channelCount: 2, samples: [Float](repeating: 0, count: 2 * 48000 * 5))
        #expect(Loudness.integrated(silent) == -.infinity)
        #expect(Loudness.range(silent) == nil)
        #expect(TruePeak.decibels(silent) == -180)
    }

    /// (e) The loudness of any span from the running sum agrees with recomputing it from the filtered samples.
    @Test func spanPowerMatchesTheFilteredSamples() {
        let buffer = Signal.busy(seconds: 12, rate: 44100)
        let k = KWeighted(buffer)
        let z = k.weighting.filtered(buffer)
        #expect(k.frames == buffer.frames && k.prefixSum.count == buffer.frames + 1)
        func direct(_ a: Int, _ b: Int) -> Double {
            let lo = min(max(a, 0), buffer.frames), hi = min(max(b, lo), buffer.frames)
            if hi == lo { return 0 }
            return z.map { ch in ch[lo..<hi].reduce(0.0) { $0 + $1 * $1 } / Double(hi - lo) }.reduce(0, +)
        }
        // Bars of about 2 s with the lab's rounding of bar times to frames, a few odd spans, and spans cut by the end.
        var spans: [(Int, Int)] = []
        var t = 0.37
        while t < 12.5 { spans.append((k.frame(at: t), k.frame(at: t + 1.9354))); t += 1.9354 }
        spans += [(0, 1), (17, 18), (100, 100), (5000, 4000), (0, buffer.frames), (buffer.frames - 3, buffer.frames + 50),
                  (buffer.frames + 10, buffer.frames + 20)]
        var worst = 0.0
        for (a, b) in spans {
            let want = direct(a, b), got = k.powerOver(frames: a..<max(a, b))
            let rel = want == 0 ? abs(got) : abs(got - want) / want
            worst = max(worst, rel)
            #expect(rel < 1e-9, "span \(a)..<\(b): \(got) vs \(want)")
            let lufs = want > 0 ? -0.691 + max(-120, 10 * log10(want)) : -120.691
            #expect(abs(k.loudness(from: a, to: b) - lufs) < 1e-8, "span \(a)..<\(b)")
        }
        print("span power vs the filtered samples: \(spans.count) spans, largest relative difference \(worst)")
        #expect(k.loudness(from: 100, to: 100) == -120.691)
    }

    /// Short-term loudness of a steady tone reads its level; a span under a quarter second reads -120, as `st_lufs`.
    @Test func shortTermLoudness() {
        let buffer = Signal.tone([(-23, 12)], rate: 44100)
        let st = Loudness.shortTerm(buffer, endingAt: 10)
        print("short-term loudness of a -23 dBFS tone over 7 to 10 s: \(st) LUFS")
        #expect(abs(st + 23) < 0.1)
        #expect(Loudness.shortTerm(buffer, endingAt: -5) == -120)  // 0 to 0.1 s
        #expect(Loudness.shortTerm(buffer, endingAt: 40) == -120)  // past the end
        #expect(abs(Loudness.shortTerm(buffer, endingAt: 13) - st) < 0.1)  // cut by the end, still 2 s long
    }
}

@Suite struct TruePeakTests {
    /// (d) A -6 dBFS sine whose peaks fall between samples, and a full-scale click.
    @Test func peaksBetweenSamples() {
        let rate = 44100, amp = pow(10, -6.0 / 20)
        // 11,025 Hz is a quarter of the rate: four samples a cycle at 45, 135, 225 and 315 degrees, each at
        // sin(45 degrees) = 0.707 of the amplitude, so the samples peak 3 dB below the sine.
        let frames = rate * 2
        var samples = [Float](repeating: 0, count: frames)
        for i in 0..<frames { samples[i] = Float(amp * sin(Double.pi / 2 * Double(i) + Double.pi / 4)) }
        let sine = AudioBuffer(sampleRate: rate, channelCount: 1, samples: samples)
        let samplePeak = 20 * log10(Double(samples.map { abs($0) }.max()!))
        let tp = TruePeak.decibels(sine)
        print("true peak of a -6 dBFS sine at 11,025 Hz: sample peak \(samplePeak) dBFS, true peak \(tp) dBTP")
        #expect(abs(samplePeak + 9.0) < 0.05)
        #expect(abs(tp + 6.0) <= 0.2)

        // A full-scale click in silence, once in the middle of a block and once on the edge between two 10 s blocks.
        for at in [rate, rate * 10, rate * 10 - 1] {
            var click = [Float](repeating: 0, count: rate * 12)
            click[at] = 1
            let db = TruePeak.decibels(AudioBuffer(sampleRate: rate, channelCount: 1, samples: click))
            print("true peak of a full-scale click at frame \(at): \(db) dBTP")
            #expect(abs(db) <= 0.1)
        }
    }

    /// The filter is scipy's: symmetric, summing to 4, a centre tap of about 1, and zero on every fourth tap.
    @Test func interpolationFilterShape() {
        let h = TruePeak.interpolationFilter
        #expect(h.count == 81)
        #expect(abs(h.reduce(0, +) - 4) < 1e-12)
        for k in 0..<81 { #expect(h[k] == h[80 - k]) }
        #expect(abs(h[40] - 1) < 0.01)
        for k in stride(from: 0, through: 80, by: 4) where k != 40 { #expect(abs(h[k]) < 1e-15) }
    }
}

@Suite struct LoudnessSpeedTests {
    /// (f) Four minutes of stereo at 44.1 kHz: K-weighted, measured (integrated, range, every 2 s bar) and
    /// true-peaked in under 2 s, in a debug build.
    @Test func fourMinutesInUnderTwoSeconds() {
        let buffer = Signal.busy(seconds: 240, rate: 44100)
        var integrated: Double? = nil, range: Double? = nil, peak = 0.0, bars: [Double] = []
        let clock = ContinuousClock()
        var kTime = 0.0, measureTime = 0.0
        let total = clock.measure {
            var k: KWeighted? = nil
            kTime = seconds(clock.measure { k = KWeighted(buffer) })
            measureTime = seconds(clock.measure {
                integrated = Loudness.integrated(k!)
                range = Loudness.range(k!)
                bars = stride(from: 0.0, to: 240.0, by: 2.0).map { k!.loudness(from: k!.frame(at: $0), to: k!.frame(at: $0 + 2)) }
            })
            peak = TruePeak.decibels(buffer)
        }
        let t = seconds(total)
        print("4 min stereo at 44.1 kHz: \(Py.fixed(t, 3)) s in all (K-weighting \(Py.fixed(kTime, 3)) s, "
              + "integrated, range and \(bars.count) bars \(Py.fixed(measureTime, 3)) s, true peak "
              + "\(Py.fixed(t - kTime - measureTime, 3)) s); integrated \(integrated ?? .nan) LUFS, range \(range ?? .nan) LU, "
              + "true peak \(peak) dBTP")
        #expect(integrated != nil && range != nil && bars.count == 120)
        #expect(t < 2.0)
    }
}
