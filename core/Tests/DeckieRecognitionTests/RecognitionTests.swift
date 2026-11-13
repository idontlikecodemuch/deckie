import Foundation
import Testing
import DeckieCore
import DeckieRecognition

// The trial recogniser on generated songs: every song here is synthesised in the test; no music file is read.
// A "song" is a seeded run of notes (each a few harmonics with a sharp start), so two seeds share nothing and one
// seed rendered at another tempo is the same song with the key held, exactly.

@Suite struct RecognitionTests {
    static let rate = 8000

    struct RNG { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

    /// `seconds` of song `seed`, with every time divided by `tempo` and every frequency multiplied by `pitch`.
    static func song(seed: UInt64, seconds: Double = 40, tempo: Double = 1, pitch: Double = 1) -> [Float] {
        var rng = RNG(s: seed)
        let n = Int(seconds / tempo * Double(rate))
        var out = [Float](repeating: 0, count: n)
        var t = 0.0
        while t < seconds {
            let f = 320 * pow(2, rng.next() * 3.2) * pitch, length = 0.15 + 0.5 * rng.next(), amp = 0.2 + 0.8 * rng.next()
            let start = Int(t / tempo * Double(rate)), count = Int(length / tempo * Double(rate))
            for i in 0..<count where start + i < n {
                let x = Double(i) / Double(rate)
                let env = exp(-3 * x * tempo) * min(1, Double(i) / 40)
                out[start + i] += Float(amp * env * (sin(2 * .pi * f * x) + 0.4 * sin(2 * .pi * 2 * f * x)))
            }
            t += 0.08 + 0.12 * rng.next()
        }
        return out
    }

    static func noise(_ n: Int, seed: UInt64, level: Float) -> [Float] {
        var rng = RNG(s: seed)
        return (0..<n).map { _ in Float(rng.next() * 2 - 1) * level }
    }

    static let index: RecognitionIndex = {
        RecognitionIndex(songs: (0..<8).map { ("song\($0)", Landmarks(mono: song(seed: UInt64(100 + $0)), sampleRate: rate)) })
    }()

    static func excerpt(_ x: [Float], from: Double, seconds: Double) -> [Float] {
        Array(x[Int(from * Double(rate))..<Int((from + seconds) * Double(rate))])
    }

    @Test func aConstellationSurvivesItsBytes() throws {
        let marks = Landmarks(mono: Self.song(seed: 5, seconds: 10), sampleRate: Self.rate)
        #expect(marks.count > 100)
        #expect(Landmarks(encoded: marks.encoded()) == marks)
        #expect(marks.encoded().count < 4 * marks.count + 12)
        #expect(Landmarks(encoded: Data([1, 2, 3])) == nil)
    }

    @Test func anExcerptIsFoundWithItsPlace() throws {
        let q = Self.excerpt(Self.song(seed: 103), from: 17.3, seconds: 5)
        let found = Recogniser(index: Self.index).match(Landmarks(mono: q, sampleRate: Self.rate))
        let best = try #require(found.first)
        #expect(best.id == "song3")
        #expect(abs(best.offsetSeconds - 17.3) < 0.05)
        #expect(abs(best.speedPercent) < 0.25)
        #expect(best.score > 20)
        #expect(best.isVinyl == nil)
    }

    @Test func aTurntableSpeedIsFoundAndRead() throws {
        // Vinyl-style: time and frequency move together.
        for percent in [-16.0, -7.0, 3.0, 12.0] {
            let v = 1 + percent / 100
            let played = Self.song(seed: 105, tempo: v, pitch: v)
            let q = Self.excerpt(played, from: 10 / v, seconds: 6)
            let best = try #require(Recogniser(index: Self.index).match(Landmarks(mono: q, sampleRate: Self.rate)).first)
            #expect(best.id == "song5")
            #expect(abs(best.speedPercent - percent) < 0.15, "tempo read \(best.speedPercent) at \(percent)")
            #expect(abs((best.pitchRatio - 1) * 100 - percent) < 0.15, "pitch read \(best.pitchRatio) at \(percent)")
            #expect(abs(best.offsetSeconds - 10) < 0.1)
            #expect(best.isVinyl == true)
        }
    }

    @Test func aKeyHeldSpeedIsFoundAndRead() throws {
        // Tempo only: the key is held ("master tempo").
        for percent in [-15.0, -6.0, 4.0, 13.0] {
            let v = 1 + percent / 100
            let played = Self.song(seed: 101, tempo: v)
            let q = Self.excerpt(played, from: 20 / v, seconds: 6)
            let best = try #require(Recogniser(index: Self.index).match(Landmarks(mono: q, sampleRate: Self.rate)).first)
            #expect(best.id == "song1")
            #expect(abs(best.speedPercent - percent) < 0.15, "tempo read \(best.speedPercent) at \(percent)")
            #expect(abs(best.pitchRatio - 1) < 0.0015)
            #expect(best.isVinyl == false)
        }
    }

    @Test func noiseAndAnotherRateDoNotLoseIt() throws {
        // The excerpt at 44.1 kHz under white noise at the excerpt's own level (0 dB).
        let clean = Self.excerpt(Self.song(seed: 106), from: 8, seconds: 8)
        let rms = (clean.reduce(0) { $0 + $1 * $1 } / Float(clean.count)).squareRoot()
        let noise = Self.noise(clean.count, seed: 9, level: rms * Float(3).squareRoot())
        let q = Resampler.resample(zip(clean, noise).map { $0 + $1 }, from: Self.rate, to: 44100)
        let found = Recogniser(index: Self.index).match(Landmarks(mono: q, sampleRate: 44100))
        let best = try #require(found.first)
        #expect(best.id == "song6")
        #expect(best.score > 10)
    }

    @Test func aSongThatIsNotThereScoresLow() throws {
        let q = Self.excerpt(Self.song(seed: 999), from: 5, seconds: 8)
        let found = Recogniser(index: Self.index).match(Landmarks(mono: q, sampleRate: Self.rate))
        #expect((found.first?.score ?? 0) < 6)
        let silence = Recogniser(index: Self.index).match(Landmarks(mono: [Float](repeating: 0, count: 40000), sampleRate: Self.rate))
        #expect(silence.isEmpty)
    }

    @Test func twoSongsAtOnceAreBothFound() throws {
        let a = Self.excerpt(Self.song(seed: 102), from: 12, seconds: 8), b = Self.excerpt(Self.song(seed: 107), from: 25, seconds: 8)
        let found = Recogniser(index: Self.index).match(Landmarks(mono: zip(a, b).map { $0 + $1 }, sampleRate: Self.rate))
        #expect(Set(found.prefix(2).map(\.id)) == ["song2", "song7"])
    }
}
