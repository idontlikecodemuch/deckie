import Foundation
import Testing
import DeckieAudio
import DeckieTestSupport
@testable import DeckieCore

/// Fixtures/learned_key.json, written by mixer/keytrial/kt_x4.py (`export`): the Python reference of the learned key
/// reader on the generated clips of three_answer.json (made here again from that fixture's recipe, so both sides read
/// the very same samples), with the SHA-256 of the numbers it used.
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
    var weightsSha256: String
    var cases: [Case]
    enum CodingKeys: String, CodingKey { case cases; case weightsSha256 = "weights_sha256" }
}

@Suite struct LearnedKeyTests {
    static let fx = try! RepoPaths.fixture("learned_key.json", as: LearnedKeyFixture.self)
    static let clips = try! RepoPaths.fixture("three_answer.json", as: ThreeAnswerFixture.self)

    @Test func theFixtureWasMadeWithTheNumbersThatShip() {
        #expect(Self.fx.weightsSha256 == LearnedKeyWeights.sha256)
        #expect(LearnedKey.Model.shipped.name == "deckie-key-" + LearnedKeyWeights.sha256.prefix(8))
    }

    @Test func theGeneratedClipsMatchTheReference() throws {
        #expect(Self.fx.cases.count >= 6)
        var kinds = Set<String>()
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
            let s = try #require(LearnedKey.scores(spectrogram: spec, frames: n))
            for k in 0..<24 { #expect(abs(s[k] - c.scores[k]) < 2e-2, "\(c.name): score \(k): \(s[k]) against \(c.scores[k])") }
            let r = try LearnedKey.read(audio, sampleRate: 44_100)
            for k in 0..<24 { #expect(abs(r.probabilities[k] - c.probabilities[k]) < 1e-2, "\(c.name): probability \(k)") }
            #expect(r.best == c.key, "\(c.name): key")
            switch r.answer {
            case .key(let pc, let minor): #expect(c.answer == "key" && pc + (minor ? 12 : 0) == c.key, "\(c.name): answer")
            case .home(let pc): #expect(c.answer == "home" && pc == c.home, "\(c.name): answer")
            case .notSure: #expect(c.answer == "none", "\(c.name): answer")
            }
            kinds.insert(c.answer)
        }
        #expect(kinds.contains("key"))
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

    @Test func theNumbersAreReadAsSixteenBitFloats() {
        #expect(LearnedKey.Model.half(0x3c00) == 1)
        #expect(LearnedKey.Model.half(0xc000) == -2)
        #expect(LearnedKey.Model.half(0x3555) == Float(0.33325195))
        #expect(LearnedKey.Model.half(0x0001) == Float(5.9604645e-8))
        #expect(LearnedKey.Model.half(0) == 0)
        #expect(throws: LearnedKey.Model.BadWeights.self) { try LearnedKey.Model(base64: "AAAA", minorLean: 0, temperature: 1, name: "x") }
    }

    @Test func tooShortToRead() throws {
        let r = try LearnedKey.read([Float](repeating: 0, count: 3000), sampleRate: 44_100)
        #expect(r.answer == .notSure && r.best == nil && r.probabilities.isEmpty)
        #expect(throws: HPCPKey.EstimateError.self) { try LearnedKey.read([0, 0], sampleRate: 48_000) }
    }

    @Test func aLongSongIsReadInStretches() throws {
        // 700 frames: one stretch of 600 and one of 100, averaged by length.
        var spec = [Float](repeating: 0, count: 700 * LearnedKey.bands)
        var state: UInt32 = 7
        for i in spec.indices { state = state &* 1664525 &+ 1013904223; spec[i] = Float(state >> 8) / Float(1 << 24) * 3 }
        let whole = try #require(LearnedKey.scores(spectrogram: spec, frames: 700))
        let a = try #require(LearnedKey.scores(spectrogram: Array(spec[..<(600 * LearnedKey.bands)]), frames: 600))
        let b = try #require(LearnedKey.scores(spectrogram: Array(spec[(600 * LearnedKey.bands)...]), frames: 100))
        for k in 0..<24 { #expect(abs(whole[k] - (a[k] * 600 + b[k] * 100) / 700) < 1e-9) }
    }
}
