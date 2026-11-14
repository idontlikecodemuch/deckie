import Foundation
import Testing
@testable import DeckieChroma
import DeckieDecode

// DeckieChroma against Chromaprint's own `fpcalc` (v1.6.2, the official macOS build from the project's GitHub
// releases), without needing either fpcalc or the network: the four test sounds below are made here, the same on
// every computer (whole-number arithmetic for the noise, 16-bit samples in a WAV file), and what fpcalc printed for
// each of them once is kept as numbers. To make them again: run these tests with DECKIE_CHROMA_WRITE_WAVS=<folder>,
// which writes the four files there, then `fpcalc <file>` and `fpcalc -raw <file>` on each.

enum TestSounds {
    /// An exponential sweep from 50 Hz to 4 kHz, 12 seconds, mono at 44,100 a second.
    static func sweep() -> (rate: Int, channels: Int, samples: [Int16]) {
        let rate = 44100, secs = 12.0, f0 = 50.0, f1 = 4000.0
        let k = log(f1 / f0) / secs
        let n = Int(Double(rate) * secs)
        return (rate, 1, (0..<n).map { i in
            let t = Double(i) / Double(rate)
            return Int16((11000 * sin(2 * Double.pi * f0 * (exp(k * t) - 1) / k)).rounded())
        })
    }

    /// Short 1 kHz clicks every half second over a quiet low hum, 12 seconds, mono at 44,100 a second.
    static func clicks() -> (rate: Int, channels: Int, samples: [Int16]) {
        let rate = 44100, n = rate * 12, period = rate / 2
        return (rate, 1, (0..<n).map { i in
            let j = i % period
            let click = j < 300 ? 18000 * exp(-Double(j) / 40) * sin(2 * Double.pi * 1000 * Double(j) / Double(rate)) : 0
            let hum = 1500 * sin(2 * Double.pi * 110 * Double(i) / Double(rate))
            return Int16((click + hum).rounded())
        })
    }

    /// White noise from a fixed seed (a 32-bit xorshift), different in each ear, 12 seconds, stereo at 48,000.
    static func noise() -> (rate: Int, channels: Int, samples: [Int16]) {
        let rate = 48000, n = rate * 12
        var s: UInt32 = 2463534242
        var out = [Int16](repeating: 0, count: n * 2)
        for i in 0..<(n * 2) {
            s ^= s << 13; s ^= s >> 17; s ^= s << 5
            out[i] = Int16(truncatingIfNeeded: Int32(bitPattern: s) >> 19)   // -4096 ... 4095
        }
        return (rate, 2, out)
    }

    /// Four chords, two seconds each, played twice: 16 seconds, mono at 11,025 (no resampling).
    static func chords() -> (rate: Int, channels: Int, samples: [Int16]) {
        let rate = 11025, n = rate * 16
        let chords: [[Double]] = [[261.63, 329.63, 392.0], [293.66, 369.99, 440.0], [220.0, 277.18, 329.63], [349.23, 440.0, 523.25]]
        return (rate, 1, (0..<n).map { i in
            let c = chords[(i / (2 * rate)) % 4]
            return Int16((7000 * c.reduce(0) { $0 + sin(2 * Double.pi * $1 * Double(i) / Double(rate)) }).rounded())
        })
    }

    static func make(_ name: String) -> (rate: Int, channels: Int, samples: [Int16]) {
        switch name {
        case "sweep": return sweep()
        case "clicks": return clicks()
        case "noise": return noise()
        default: return chords()
        }
    }

    /// A 16-bit WAV file.
    static func wav(_ s: (rate: Int, channels: Int, samples: [Int16])) -> Data {
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let bytes = s.samples.count * 2
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(s.channels); u32(s.rate)
        u32(s.rate * s.channels * 2); u16(s.channels * 2); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        for v in s.samples { u16(Int(UInt16(bitPattern: v))) }
        return d
    }
}

@Suite struct ChromaprintAgreementTests {
    /// What fpcalc 1.6.2 printed for each test sound: DURATION and FINGERPRINT.
    static let fpcalc: [String: (duration: Int, fingerprint: String)] = FpcalcPrints.all

    func fingerprint(_ name: String) throws -> SoundFingerprint {
        let s = TestSounds.make(name)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-chroma-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent(name + ".wav")
        try TestSounds.wav(s).write(to: url)
        if let keep = ProcessInfo.processInfo.environment["DECKIE_CHROMA_WRITE_WAVS"], !keep.isEmpty {
            try? TestSounds.wav(s).write(to: URL(fileURLWithPath: keep).appendingPathComponent(name + ".wav"))
        }
        return try Chromaprint.fingerprint(file: url)
    }

    @Test(arguments: ["sweep", "clicks", "noise", "chords"])
    func agreesWithFpcalc(_ name: String) throws {
        let mine = try fingerprint(name)
        let theirs = try #require(Self.fpcalc[name])
        let decoded = try #require(Chromaprint.decompress(theirs.fingerprint))
        #expect(decoded.algorithm == 1)
        #expect(mine.duration == theirs.duration)
        #expect(mine.frames.count == decoded.frames.count)
        // On the Mac every bit agrees; another computer's sine and exp may differ in the last place, which can move
        // a value across a threshold now and then, so a little is allowed.
        let diff = Chromaprint.bitDifference(mine.frames, decoded.frames)
        #expect(diff <= 0.005, "\(name): \(diff * 100)% of bits differ")
        #if os(macOS)
        #expect(mine.compressed == theirs.fingerprint)
        #endif
    }

    @Test func rawFramesOfTheClicks() throws {
        // `fpcalc -raw` on the clicks, the first 24 frames.
        let mine = try fingerprint("clicks")
        let raw = FpcalcPrints.clicksRawHead
        #expect(Chromaprint.bitDifference(Array(mine.frames.prefix(raw.count)), raw) <= 0.005)
        let decoded = try #require(Chromaprint.decompress(Self.fpcalc["clicks"]!.fingerprint))
        #expect(Array(decoded.frames.prefix(raw.count)) == raw)
    }
}

@Suite struct ChromaprintPartsTests {
    @Test func compressionRoundTrips() {
        var s: UInt32 = 12345
        var frames: [UInt32] = []
        for _ in 0..<500 { s ^= s << 13; s ^= s >> 17; s ^= s << 5; frames.append(frames.last.map { $0 ^ (s & 0x0101_0F03) } ?? s) }
        frames += [0, 0, 0xFFFF_FFFF, 0x8000_0000, 1]
        let text = Chromaprint.compress(frames)
        #expect(!text.contains("=") && !text.contains("+") && !text.contains("/"))
        let back = Chromaprint.decompress(text)
        #expect(back?.algorithm == 1)
        #expect(back?.frames == frames)
        #expect(Chromaprint.compress([]) == "AQAAAA")
        #expect(Chromaprint.decompress("not base64!") == nil)
    }

    @Test func tooShortGivesNothing() {
        #expect(Chromaprint.frames([Int16](repeating: 100, count: 4000)).isEmpty)
        let silence = Chromaprint.frames([Int16](repeating: 0, count: 11025 * 5))
        #expect(!silence.isEmpty)
    }

    @Test func resamplerKeepsLevelAndTone() {
        let r = Resampler(inRate: 44100, outRate: 11025)
        let dc = r.process([Float](repeating: 0.5, count: 44100))
        #expect(abs(dc[5000] - 0.5) < 1e-9)
        #expect(dc.count == 11025)
        // 1 kHz passes; 6 kHz, above the new rate's half, is removed.
        let tone = (0..<44100).map { Float(sin(2 * Double.pi * 1000 * Double($0) / 44100)) }
        let high = (0..<44100).map { Float(sin(2 * Double.pi * 6000 * Double($0) / 44100)) }
        func rms(_ x: [Double]) -> Double { (x[1000..<10000].reduce(0) { $0 + $1 * $1 } / 9000).squareRoot() }
        #expect(abs(rms(r.process(tone)) - 0.7071) < 0.01)
        #expect(rms(r.process(high)) < 0.001)
        // An odd rate pair takes the rounded-phase path and still passes a constant level.
        let odd = Resampler(inRate: 44057, outRate: 11025)
        #expect(abs(odd.process([Float](repeating: 0.25, count: 44057))[3000] - 0.25) < 1e-6)
    }
}
