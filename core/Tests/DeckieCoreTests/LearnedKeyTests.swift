import Foundation
import Testing
import DeckieAudio
import DeckieTestSupport
@testable import DeckieCore

/// Fixtures/learned_key.json, written by mixer/keytrial/kt_x4.py (`fixture`): the Python reference of the learned key
/// reader on the generated clips of three_answer.json (made here again from that fixture's recipe, so both sides read
/// the very same samples). The model in it is one of made-up numbers that both sides write down from the same
/// recipe (`madeUpModel`), so the test needs no trained number: the trained file is not in the repository. The
/// trained model's parity, on 270 recordings of the three outside key sets, is run by hand with `kt_x4.py parity`.
struct LearnedKeyFixture: Decodable {
    struct Case: Decodable {
        var name: String
        var frames: Int
        var spectrogramRows: [String: [Double]]
        var scores: [Double]
        var probabilities: [Double]
        var answer: String
        var key: Int
        var home: Int
        enum CodingKeys: String, CodingKey {
            case name, frames, scores, probabilities, answer, key, home
            case spectrogramRows = "spectrogram_rows"
        }
    }
    var minorLean: Double
    var temperature: Double
    var numbers: Int
    var numbersSum: Double
    var cases: [Case]
    enum CodingKeys: String, CodingKey {
        case cases, temperature, numbers
        case minorLean = "minor_lean", numbersSum = "numbers_sum"
    }
}

@Suite struct LearnedKeyTests {
    static let fx = try! RepoPaths.fixture("learned_key.json", as: LearnedKeyFixture.self)
    static let clips = try! RepoPaths.fixture("three_answer.json", as: ThreeAnswerFixture.self)

    /// kt_x4.py's `synthetic_flat`: a linear congruential generator from 12345; each draw is (s >> 8) mod 2001 - 1000;
    /// a weight is the draw / 1000 * 1.7 / sqrt(inputs to one output), a bias the draw / 1000 * 0.05, as 32-bit
    /// floats; the input's scale 1 and shift 0.
    static func madeUpNumbers() -> [Float] {
        var st: UInt32 = 12345
        var v: [Float] = [1, 0]
        func draw() -> Double {
            st = st &* 1664525 &+ 1013904223
            return Double(Int((st >> 8) % 2001) - 1000)
        }
        for (o, i, kh, kw) in LearnedKey.Model.shapes {
            let scale = 1.7 / Double(i * kh * kw).squareRoot()
            for _ in 0..<(o * i * kh * kw) { v.append(Float(draw() / 1000.0 * scale)) }
            for _ in 0..<o { v.append(Float(draw() / 1000.0 * 0.05)) }
        }
        return v
    }
    static let model = try! LearnedKey.Model(values: madeUpNumbers(), minorLean: fx.minorLean, temperature: fx.temperature, name: "made-up")

    @Test func bothSidesWroteTheSameMadeUpModel() {
        let v = Self.madeUpNumbers()
        #expect(v.count == Self.fx.numbers && v.count == 235_598)
        #expect(abs(v.reduce(0.0) { $0 + Double($1) } - Self.fx.numbersSum) < 1e-6)
    }

    @Test func theGeneratedClipsMatchTheReference() throws {
        #expect(Self.fx.cases.count >= 6)
        for c in Self.fx.cases {
            let clip = try #require(Self.clips.cases.first { $0.name == c.name })
            let audio = ThreeAnswerFixture.render(clip).samples
            let (n, spec) = LearnedKey.spectrogram(audio)
            #expect(n == c.frames, "\(c.name): frames")
            for (row, want) in c.spectrogramRows {
                let r = try #require(Int(row))
                for j in 0..<LearnedKey.bands {
                    #expect(abs(Double(spec[r * LearnedKey.bands + j]) - want[j]) < 2e-3, "\(c.name): spectrogram row \(r) band \(j)")
                }
            }
            let s = try #require(LearnedKey.scores(spectrogram: spec, frames: n, model: Self.model))
            for k in 0..<24 { #expect(abs(s[k] - c.scores[k]) < 2e-3, "\(c.name): score \(k): \(s[k]) against \(c.scores[k])") }
            let r = try LearnedKey.read(audio, sampleRate: 44_100, model: Self.model)
            for k in 0..<24 { #expect(abs(r.probabilities[k] - c.probabilities[k]) < 2e-2, "\(c.name): probability \(k)") }
            #expect(r.best == c.key, "\(c.name): key")
            switch r.answer {
            case .key(let pc, let minor): #expect(c.answer == "key" && pc + (minor ? 12 : 0) == c.key, "\(c.name): answer")
            case .home(let pc): #expect(c.answer == "home" && pc == c.home, "\(c.name): answer")
            case .notSure: #expect(c.answer == "none", "\(c.name): answer")
            }
        }
    }

    @Test func theLeanAndTheTemperature() {
        // Equal scores: without a lean every key is 1 in 24; a lean of log 2 makes each minor key twice a major one.
        var m = Self.model
        m.minorLean = 0; m.temperature = 1
        let flat = LearnedKey.probabilities(scores: [Double](repeating: 0.3, count: 24), model: m)
        #expect(flat.allSatisfy { abs($0 - 1.0 / 24) < 1e-12 })
        m.minorLean = log(2.0)
        let leaned = LearnedKey.probabilities(scores: [Double](repeating: 0.3, count: 24), model: m)
        #expect(abs(leaned[12] / leaned[0] - 2) < 1e-9 && abs(leaned.reduce(0, +) - 1) < 1e-12)
        // A temperature above 1 pulls the probabilities together; under 1 it drives them apart.
        var s = [Double](repeating: 0, count: 24); s[21] = 2
        m.minorLean = 0
        m.temperature = 1; let p1 = LearnedKey.probabilities(scores: s, model: m)[21]
        m.temperature = 2; let p2 = LearnedKey.probabilities(scores: s, model: m)[21]
        m.temperature = 0.5; let p05 = LearnedKey.probabilities(scores: s, model: m)[21]
        #expect(p2 < p1 && p1 < p05)
    }

    @Test func theThreeAnswersFollowTheProbabilities() {
        func p(_ pairs: [Int: Double]) -> [Double] {
            var v = [Double](repeating: 0, count: 24)
            let rest = (1 - pairs.values.reduce(0, +)) / Double(24 - pairs.count)
            for k in 0..<24 { v[k] = pairs[k] ?? rest }
            return v
        }
        // A key at one half or more: that key.
        #expect(LearnedKey.decide(p([21: 0.6])).answer == .key(pitchClass: 9, minor: true))
        #expect(LearnedKey.decide(p([21: 0.5, 9: 0.4])).answer == .key(pitchClass: 9, minor: true))
        // No key at one half, the two keys on A together at one half or more: the home note.
        #expect(LearnedKey.decide(p([21: 0.4, 9: 0.3])).answer == .home(pitchClass: 9))
        // Neither: not sure.
        #expect(LearnedKey.decide(p([21: 0.3, 0: 0.3])).answer == .notSure)
    }

    @Test func theNumbersAreReadAsSixteenBitFloats() throws {
        #expect(LearnedKey.Model.half(0x3c00) == 1)
        #expect(LearnedKey.Model.half(0xc000) == -2)
        #expect(LearnedKey.Model.half(0x3555) == Float(0.33325195))
        #expect(LearnedKey.Model.half(0x0001) == Float(5.9604645e-8))
        #expect(LearnedKey.Model.half(0) == 0)
        #expect(throws: LearnedKey.Model.BadWeights.self) { try LearnedKey.Model(base64: "AAAA", minorLean: 0, temperature: 1, name: "x") }
        // A file of the right size reads; one byte short does not; the pinned file must have the pinned size.
        let zeros = Data(count: 2 * 235_598)
        let read = try LearnedKey.Model(data: zeros, minorLean: 0, temperature: 1, name: "x")
        #expect(read.name == "x")
        #expect(throws: LearnedKey.Model.BadWeights.self) { try LearnedKey.Model(data: zeros.dropLast(2), minorLean: 0, temperature: 1, name: "x") }
        let pinned = try LearnedKey.Model(pinnedFile: zeros)
        #expect(LearnedKey.Model.pinnedByteCount == zeros.count && pinned.name == LearnedKey.Model.pinnedName)
        #expect(throws: LearnedKey.Model.BadWeights.self) { try LearnedKey.Model(pinnedFile: Data(count: 10)) }
    }

    @Test func tooShortToRead() throws {
        let r = try LearnedKey.read([Float](repeating: 0, count: 3000), sampleRate: 44_100, model: Self.model)
        #expect(r.answer == .notSure && r.best == nil && r.probabilities.isEmpty)
        #expect(throws: HPCPKey.EstimateError.self) { try LearnedKey.read([0, 0], sampleRate: 48_000, model: Self.model) }
    }

    @Test func aLongSongIsReadInStretches() throws {
        // 700 frames: one stretch of 600 and one of 100, averaged by length.
        var spec = [Float](repeating: 0, count: 700 * LearnedKey.bands)
        var state: UInt32 = 7
        for i in spec.indices { state = state &* 1664525 &+ 1013904223; spec[i] = Float(state >> 8) / Float(1 << 24) * 3 }
        let whole = try #require(LearnedKey.scores(spectrogram: spec, frames: 700, model: Self.model))
        let a = try #require(LearnedKey.scores(spectrogram: Array(spec[..<(600 * LearnedKey.bands)]), frames: 600, model: Self.model))
        let b = try #require(LearnedKey.scores(spectrogram: Array(spec[(600 * LearnedKey.bands)...]), frames: 100, model: Self.model))
        for k in 0..<24 { #expect(abs(whole[k] - (a[k] * 600 + b[k] * 100) / 700) < 1e-9) }
    }
}
