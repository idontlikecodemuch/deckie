import Testing
import DeckieCore

/// Fixtures/camelot.json holds every value the lab's Python gives for the Camelot functions.
struct CamelotFixture: Decodable {
    var codes: [String: String]
    var keyRaw: [String: [RawEntry]]
    var shift: [String: String]
    var neighbour: [String: Bool]
    enum CodingKeys: String, CodingKey { case codes, shift, neighbour, keyRaw = "key_raw" }
}

/// key_raw returns (number, text); JSON gives them as a two-element list.
enum RawEntry: Decodable {
    case number(Double), text(String)
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) { self = .number(d) } else { self = .text(try c.decode(String.self)) }
    }
}

@Suite struct CamelotTests {
    let fx = try! RepoPaths.fixture("camelot.json", as: CamelotFixture.self)

    @Test func everyKeyNameAndScaleMapsLikeTheLab() {
        #expect(fx.codes.count == 42)
        for (k, want) in fx.codes {
            let parts = k.split(separator: " ")
            #expect(Camelot.code(key: String(parts[0]), scale: String(parts[1])) == want, "\(k)")
        }
        #expect(Camelot.code(key: "H", scale: "major") == nil)
    }

    @Test func compatibilityTableMatchesTheLab() {
        #expect(fx.keyRaw.count == 24 * 24)
        for (k, want) in fx.keyRaw {
            let ab = k.split(separator: ">").map(String.init)
            let got = Camelot.rawCompatibility(ab[0], ab[1])
            guard case .number(let score) = want[0], case .text(let why) = want[1] else { Issue.record("bad fixture \(k)"); continue }
            #expect(got.score == score && got.why == why, "\(k): got \(got), want \(score) \(why)")
        }
    }

    @Test func pitchShiftsAndNeighboursMatchTheLab() {
        for (k, want) in fx.shift {
            let code = String(k.dropLast(2)), semis = Int(k.suffix(2))!
            #expect(Camelot.shifted(code, semitones: semis) == want, "\(k)")
        }
        for (k, want) in fx.neighbour {
            let ab = k.split(separator: ">").map(String.init)
            #expect(Camelot.isNeighbour(ab[0], ab[1]) == want, "\(k)")
        }
    }
}
