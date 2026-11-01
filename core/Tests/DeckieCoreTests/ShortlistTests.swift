import Testing
import DeckieCore

/// A small seeded generator (SplitMix64) so the shuffle tests are repeatable.
struct ShortlistRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite("Shortlist") struct ShortlistTests {
    /// 20 distinct scores in a scrambled order; index 7 holds the best.
    let scores: [Double] = (0..<20).map { Double(($0 * 7 + 13) % 20) / 20 }
    var topIndex: Int { scores.indices.max { scores[$0] < scores[$1] }! }

    @Test func size() {
        #expect(Shortlist.size(libraryCount: 0) == 10)
        #expect(Shortlist.size(libraryCount: 50) == 10)
        #expect(Shortlist.size(libraryCount: 100) == 10)
        #expect(Shortlist.size(libraryCount: 101) == 11)
        #expect(Shortlist.size(libraryCount: 238) == 24)
        #expect(Shortlist.size(libraryCount: 373) == 38)
    }

    @Test func dialAtZeroIsThePureRank() {
        var rng = ShortlistRNG(seed: 1)
        let got = Shortlist.order(scores: scores, shuffle: 0, rng: &rng)
        let want = scores.indices.sorted { scores[$0] > scores[$1] }
        #expect(got == want)
        // below 0 clamps to 0
        #expect(Shortlist.order(scores: scores, shuffle: -3, rng: &rng) == want)
    }

    func meanTopPosition(_ shuffle: Double, draws: Int = 2000) -> Double {
        var rng = ShortlistRNG(seed: 42)
        var sum = 0
        for _ in 0..<draws {
            let o = Shortlist.order(scores: scores, shuffle: shuffle, rng: &rng)
            #expect(o.sorted() == Array(scores.indices))      // a permutation
            sum += o.firstIndex(of: topIndex)!
        }
        return Double(sum) / Double(draws)
    }

    @Test func dialAtOneIsAFairShuffle() {
        let m = meanTopPosition(1)
        print("shuffle 1: the top entry's mean position \(m) of 0...19")
        #expect(abs(m - 9.5) < 1.0, "mean position of the top entry \(m)")
        let m2 = meanTopPosition(7)     // above 1 clamps to 1
        #expect(abs(m2 - 9.5) < 1.0)
    }

    @Test func dialHalfwayKeepsTheTopNearTheTop() {
        let m = meanTopPosition(0.5)
        print("shuffle 0.5: the top entry's mean position \(m) of 0...19")
        #expect(m > 0.3 && m < 8.5, "mean position of the top entry \(m)")
    }

    @Test func emptyAndEqual() {
        var rng = ShortlistRNG(seed: 3)
        #expect(Shortlist.order(scores: [], shuffle: 0.5, rng: &rng).isEmpty)
        #expect(Shortlist.order(scores: [0.4, 0.4, 0.4], shuffle: 0, rng: &rng) == [0, 1, 2])
        let o = Shortlist.order(scores: [0.4, 0.4, 0.4, 0.4], shuffle: 1, rng: &rng)
        #expect(o.sorted() == [0, 1, 2, 3])
        #expect(Shortlist.order(scores: [0.9], shuffle: 1, rng: &rng) == [0])
    }
}
