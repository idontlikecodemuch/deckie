import Foundation
import Testing
import DeckieAudio
import DeckieCore
import DeckieTestSupport

/// Fixtures/bands.json, written by Tools/make_resample_fixtures.py (scipy's butter and sosfilt, the lab's per-bar loop
/// and first / last sound rule).
struct BandsFixture: Decodable {
    struct Band: Decodable {
        var rate: Int, samples: Int
        var barFrames: [Int]
        var sosLow: [Double], sosHigh: [Double]
        var index: [Int]
        var low: [Double], high: [Double]
        var lowDB: [Double], highDB: [Double]
        enum CodingKeys: String, CodingKey {
            case rate, samples, index, low, high
            case barFrames = "bar_frames", sosLow = "sos_low", sosHigh = "sos_high", lowDB = "low_db", highDB = "high_db"
        }
    }
    /// [first sample, end sample, channel mask, kind, value]
    struct Event: Decodable {
        var first: Int, end: Int, mask: Int, kind: String, value: Double
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            first = try c.decode(Int.self); end = try c.decode(Int.self); mask = try c.decode(Int.self)
            kind = try c.decode(String.self); value = try c.decode(Double.self)
        }
    }
    struct Bounds: Decodable {
        var name: String
        var rate: Int, channels: Int, samples: Int
        var base: Double, seed: UInt64
        var events: [Event]
        var first: Double, last: Double, loudFrames: Int
        enum CodingKeys: String, CodingKey {
            case name, rate, channels, samples, base, seed, events, first, last, loudFrames = "loud_frames"
        }
    }
    var versions: [String: String]
    /// [start s, end s, Hz, amplitude, channel mask]
    var tones: [[Double]]
    var seconds: Double, noise: Double
    var zero: [Double]
    var beatS: Double, firstBarS: Double, bars: Int
    var bands: [Band]
    var bounds: [Bounds]
    enum CodingKeys: String, CodingKey {
        case versions, tones, seconds, noise, zero, bars, bands, bounds
        case beatS = "beat_s", firstBarS = "first_bar_s"
    }

    static let shared = try! RepoPaths.fixture("bands.json", as: BandsFixture.self)

    /// The script's `band_signal`: the tones (amp sin(w i), w = 2 pi f / rate), noise on each channel (SplitMix64 seeds
    /// 21 and 22), exact zeros over `zero`; stereo float32.
    func signal(rate: Int) -> AudioBuffer {
        let sr = Double(rate)
        let n = Int(seconds * sr)
        var l = [Double](repeating: 0, count: n), r = [Double](repeating: 0, count: n)
        for t in tones {
            let s = Int(t[0] * sr), e = Int(t[1] * sr), amp = t[3], mask = Int(t[4])
            let w = 2.0 * Double.pi * t[2] / sr
            for i in s..<e {
                let v = amp * sin(w * Double(i))
                if mask & 1 != 0 { l[i] += v }
                if mask & 2 != 0 { r[i] += v }
            }
        }
        var gl = SplitMix64(21), gr = SplitMix64(22)
        for i in 0..<n {
            l[i] += noise * (2.0 * gl.uniform() - 1.0)
            r[i] += noise * (2.0 * gr.uniform() - 1.0)
        }
        for i in Int(zero[0] * sr)..<Int(zero[1] * sr) { l[i] = 0; r[i] = 0 }
        var out = [Float](repeating: 0, count: 2 * n)
        for i in 0..<n { out[2 * i] = Float(l[i]); out[2 * i + 1] = Float(r[i]) }
        return AudioBuffer(sampleRate: rate, channelCount: 2, samples: out)
    }
}

extension BandsFixture.Bounds {
    /// The script's `bounds_signal`.
    var buffer: AudioBuffer {
        var y = [[Double]](repeating: [Double](repeating: 0, count: samples), count: channels)
        if base > 0 {
            for c in 0..<channels {
                var g = SplitMix64(seed * 10 + UInt64(c))
                for i in 0..<samples { y[c][i] = base * (2.0 * g.uniform() - 1.0) }
            }
        }
        for (e, ev) in events.enumerated() {
            for c in 0..<channels where (ev.mask >> c) & 1 == 1 {
                switch ev.kind {
                case "noise":
                    var g = SplitMix64(seed * 10 + 5 + UInt64(e))
                    for i in ev.first..<ev.end { y[c][i] += ev.value * (2.0 * g.uniform() - 1.0) }
                case "dc":
                    for i in ev.first..<ev.end { y[c][i] += ev.value }
                default:
                    y[c][ev.first] = ev.value
                }
            }
        }
        var out = [Float](repeating: 0, count: samples * channels)
        for i in 0..<samples { for c in 0..<channels { out[i * channels + c] = Float(y[c][i]) } }
        return AudioBuffer(sampleRate: rate, channelCount: channels, samples: out)
    }
}

@Suite struct BandSplitTests {
    let fx = BandsFixture.shared

    /// The sections are scipy's `butter(2, fc, btype, fs=rate, output="sos")` at 44.1 and 48 kHz: bit for bit on
    /// Linux, and within two units in the last place elsewhere (Windows' maths library rounds tan differently in
    /// the last bit, which the first Windows run showed; the filtered samples still match).
    @Test func coefficientsMatchScipy() {
        for band in fx.bands {
            let split = BandSplit(sampleRate: band.rate)
            for (q, want) in [(split.lowPass, band.sosLow), (split.highPass, band.sosHigh)] {
                let got = [q.b0, q.b1, q.b2, 1, q.a1, q.a2]
                for (g, w) in zip(got, want) {
                    #expect(abs(g - w) <= 2 * w.ulp, "\(band.rate) Hz: \(q) against scipy \(want)")
                }
            }
        }
    }

    /// The filtered mono signal against scipy's sosfilt (within 1e-9, the requirement; in fact identical), and the
    /// per-bar low_db and high_db against the lab's loop (within 1e-6 dB), including a bar running past the end, one
    /// after it (-120) and bars of digital silence (-120).
    @Test func matchesTheLab() {
        for band in fx.bands {
            let buffer = fx.signal(rate: band.rate)
            #expect(buffer.frames == band.samples)
            let mono = buffer.mono()
            let split = BandSplit(sampleRate: band.rate)
            let low = split.low(mono), high = split.high(mono)
            var worst = 0.0, identical = 0
            for (k, i) in band.index.enumerated() {
                worst = max(worst, abs(low[i] - band.low[k]), abs(high[i] - band.high[k]))
                identical += (low[i] == band.low[k] ? 1 : 0) + (high[i] == band.high[k] ? 1 : 0)
            }
            #expect(worst <= 1e-9, "\(band.rate) Hz: filtered samples differ by up to \(worst)")
            let grid = BarGrid(firstDownbeatS: fx.firstBarS, beatS: fx.beatS, nBars: fx.bars)
            let levels = split.levels(mono, barTimes: grid.barTimes)
            #expect(levels == split.levels(mono, barFrames: band.barFrames))
            #expect(levels.lowDB.count == fx.bars && levels.highDB.count == fx.bars)
            var worstDB = 0.0
            for k in 0..<min(levels.lowDB.count, band.lowDB.count) {
                worstDB = max(worstDB, abs(levels.lowDB[k] - band.lowDB[k]), abs(levels.highDB[k] - band.highDB[k]))
            }
            #expect(worstDB <= 1e-6, "\(band.rate) Hz: per-bar levels differ by up to \(worstDB) dB")
            #expect(levels.lowDB.last == -120 && levels.highDB.last == -120)
            print("band split at \(band.rate) Hz against scipy \(fx.versions["scipy"] ?? "?"): \(identical) of "
                  + "\(2 * band.index.count) filtered samples identical, largest difference \(worst); \(fx.bars) bars, "
                  + "low_db and high_db within \(String(format: "%.1e", worstDB)) dB")
        }
    }

    /// Bars as frames: none, empty spans, spans before, across and after the end.
    @Test func barEdges() {
        let split = BandSplit(sampleRate: 44100)
        let x = (0..<10000).map { Float(0.5 * sin(2 * Double.pi * 100 * Double($0) / 44100)) }
        #expect(split.levels(x, barFrames: []) == BandSplit.Levels(lowDB: [], highDB: []))
        #expect(split.levels(x, barFrames: [500]) == BandSplit.Levels(lowDB: [], highDB: []))
        let v = split.levels(x, barFrames: [0, 4410, 4410, 8820, 12000, 15000])
        #expect(v.lowDB.count == 5 && v.lowDB[1] == -120 && v.lowDB[4] == -120 && v.highDB[4] == -120)
        // Each bar on its own gives the same value as within the run (the filters always start from sample 0).
        let low = split.low(x)
        func db(_ a: Int, _ b: Int) -> Double {
            let ms = low[a..<b].map { $0 * $0 }.reduce(0, +) / Double(b - a)
            return max(-120, 10 * log10(max(ms, 1e-30)))
        }
        #expect(abs(v.lowDB[0] - db(0, 4410)) < 1e-12 && abs(v.lowDB[2] - db(4410, 8820)) < 1e-12)
        #expect(abs(v.lowDB[3] - db(8820, 10000)) < 1e-12)
        #expect(abs(split.levels(x, barFrames: [8820, 12000]).lowDB[0] - v.lowDB[3]) < 1e-12)
        // A 100 Hz sine of amplitude 0.5 (power 0.125) over ten whole cycles: the low band passes it at the
        // Butterworth gain squared, 1 / (1 + (100 / 150)^4) (the bilinear transform's warping is negligible here);
        // the high band is far down.
        let expected = 10 * log10(0.125) + 20 * log10(1 / (1 + pow(100.0 / 150, 4)))
        #expect(abs(v.lowDB[2] - expected) < 0.002 && v.highDB[2] < -80, "\(v.lowDB[2]) against \(expected)")
    }

    /// Four minutes of mono at 44.1 kHz through both bands and 120 bars.
    @Test func speed() {
        let n = 240 * 44100
        var g = SplitMix64(5)
        let mono = (0..<n).map { _ in Float(0.5 * (2 * g.uniform() - 1)) }
        let bars = (0...120).map { 22050 + $0 * 88000 }
        let clock = ContinuousClock()
        var levels: BandSplit.Levels? = nil
        let s = seconds(clock.measure { levels = BandSplit(sampleRate: 44100).levels(mono, barFrames: bars) })
        print("band split: 4 min of mono, 120 bars, \(Py.fixed(s, 3)) s")
        #expect(levels!.lowDB.count == 120)
        #expect(s < 5)  // a loose ceiling (about 0.2 s in a debug build here); only a real regression fails
    }
}

@Suite struct SoundBoundsTests {
    let fx = BandsFixture.shared

    /// The lab's first and last sound on the script's cases, exactly: silence at both ends, all quiet, all zero, sound
    /// from the first to the last sample, sound only in the dropped partial frame, one channel, samples at the threshold
    /// and one float32 step above it, shorter than a frame, empty, 48 kHz, mono at 22.05 kHz.
    @Test func matchesTheLab() {
        for c in fx.bounds {
            let b = SoundBounds(c.buffer)
            #expect(b.firstSound == c.first && b.lastSound == c.last && b.loudFrames == c.loudFrames,
                    "\(c.name): \(b), the lab's \(c.first), \(c.last), \(c.loudFrames)")
        }
        print("first and last sound: \(fx.bounds.count) cases identical to the lab's rule")
    }

    @Test func thresholdAndFrames() {
        #expect(SoundBounds.threshold == Float(0.001))
        #expect(SoundBounds.frameLength(sampleRate: 44100) == 441 && SoundBounds.frameLength(sampleRate: 48000) == 480)
        // A NaN frame is not sound (numpy's max is NaN, and NaN > threshold is false), even with a loud sample in it.
        var x = [Float](repeating: 0, count: 441 * 4)
        x[441 + 3] = 0.5; x[441 + 7] = .nan; x[2 * 441] = 0.5
        let b = SoundBounds(AudioBuffer(sampleRate: 44100, channelCount: 1, samples: x))
        #expect(b == SoundBounds(firstSound: 0.02, lastSound: 0.03, loudFrames: 1))
    }
}
