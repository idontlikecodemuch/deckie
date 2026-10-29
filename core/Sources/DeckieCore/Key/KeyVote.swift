import Foundation

// The engine's key: three votes over the one chroma the key estimator computes, decided by the lab's own rule.
//
// The lab decided its key by a vote of three detectors (mixer/analyze.py, B.9): Essentia's key extractor with the edma
// profile, the same with the bgate profile, and madmom's CNN. Essentia and madmom cannot ship, so the engine fills
// the three slots with what it already has: the whole-track key from its STFT chroma (`KeyEstimator`) with the edma
// profile (the engine's estimator until now), the bgate profile, and the Krumhansl-Kessler profile in madmom's slot,
// and runs the lab's rule on them unchanged. Every profile is a published one (`KeyProfile`), none fitted to the lab's
// tracks, and the rule has no number of its own beyond the lab's strength of 0.6. core/Tools/key_vote_eval.py chose
// the two extra profiles from the lab's own sweep (mixer/key_light_stft.tsv): on the lab's 311 confident tracks the
// vote is exact on 237 (76.2 percent, the engine alone 74.6), exact or a Camelot neighbour on 90.0 (89.1), and changes
// the key of 7 of the 373 tracks, the gain spread over four of the lab's folders with none losing. That script's
// held-out check also says the gain of any second profile on the same chroma is within the noise of choosing it, so
// this is the quick vote the charter mark asked for, not a better estimator.

/// The key vote of a track: three whole-track keys over the same chroma, each by its own key profile, and the lab's
/// decision and confidence (mixer/analyze.py, B.9).
public struct KeyVote: Sendable, Equatable {
    /// One vote: its name in the crate's `key.votes`, its profile and its whole-track key.
    public struct Vote: Sendable, Equatable {
        public var name: String
        public var profile: KeyProfile
        public var estimate: KeyEstimate

        public init(name: String, profile: KeyProfile, estimate: KeyEstimate) {
            self.name = name
            self.profile = profile
            self.estimate = estimate
        }

        public var camelot: String { estimate.camelot }
    }

    /// The votes in the lab's slot order (`slots`).
    public var votes: [Vote]
    /// The decided key, the lab's `top`: the key two or three votes give, else the first vote's.
    public var camelot: String
    /// How many votes give the decided key: 3, 2, or 1 when no two agree.
    public var agreeing: Int
    /// The lab's `strength`: the first slot's r when it holds the decided key, else the second's, else the larger of
    /// the two (the third slot's r is never read, as the lab never reads madmom's).
    public var strength: Double
    /// The lab's key confidence `kc`: 1.0, 0.65, 0.6, 0.45 or 0.3.
    public var confidence: Double
    /// The lab's `confidence_rule`, word for word.
    public var rule: String

    /// The three slots: the lab's Essentia edma, Essentia bgate and madmom CNN, filled with the engine's STFT chroma
    /// and the edma, bgate and Krumhansl-Kessler profiles. The names are the votes' names in the crate's `key.votes`.
    public static let slots: [(name: String, profile: KeyProfile)] = [
        ("deckie-key-edma", .edma), ("deckie-key-bgate", .bgate), ("deckie-key-krumhansl", .krumhansl),
    ]
    /// The lab's strength threshold: below it, all three agreeing gives 0.6 instead of 1.0, and two agreeing gives 0.3.
    public static let minStrength = 0.6

    /// The first vote that gives the decided key; its tonic and mode spell the key (`key`, `scale` in the crate).
    public var decided: KeyEstimate { votes.first { $0.camelot == camelot }!.estimate }

    /// The vote on a whole track: the chroma's mean over all frames (`KeyEstimator.meanChroma`), the best key by each
    /// slot's profile (`KeyEstimator.bestKey`), and `decide`.
    public static func whole(_ chroma: Chromagram) -> KeyVote {
        let mean = KeyEstimator.meanChroma(chroma, frames: 0..<chroma.frames)
        return decide(slots.map { Vote(name: $0.name, profile: $0.profile, estimate: KeyEstimator.bestKey(mean, profile: $0.profile)) })
    }

    /// The lab's B.9 rule on three votes, in its slot order, as mixer/analyze.py writes it with madmom present:
    ///
    ///   two or three votes agree -> that key; no two agree -> the first vote's key
    ///   all three agree                                   1.0 (0.6 when the strength is under 0.6)
    ///   two agree, the third a Camelot neighbour of them  0.65  (same key, one step round on the same letter, or
    ///                                                            the relative major or minor: `Camelot.isNeighbour`)
    ///   two agree, the third anything else                0.45
    ///   two agree with the strength under 0.6             0.3
    ///   no two agree                                      0.3
    public static func decide(_ votes: [Vote]) -> KeyVote {
        precondition(votes.count == 3, "the lab's rule takes three votes, not \(votes.count)")
        let c1 = votes[0].camelot, c2 = votes[1].camelot, c3 = votes[2].camelot
        let s1 = votes[0].estimate.r, s2 = votes[1].estimate.r
        // Counter(votes).most_common(1): with three votes the most common is unique unless all differ.
        let codes = [c1, c2, c3]
        let counts = codes.map { c in codes.filter { $0 == c }.count }
        let nt = counts.max()!
        let top = nt == 1 ? c1 : codes[counts.firstIndex(of: nt)!]
        let strength = top == c1 ? s1 : (top == c2 ? s2 : max(s1, s2))
        let kc: Double, rule: String
        switch nt {
        case 3:
            kc = strength >= minStrength ? 1.0 : 0.6
            rule = "all three agree"
        case 2:
            let dissent = codes.first { $0 != top }!
            var k: Double, r: String
            if Camelot.isNeighbour(top, dissent) {
                (k, r) = (0.65, "2 of 3 agree, dissenter is a Camelot neighbour")
            } else {
                (k, r) = (0.45, "2 of 3 agree, dissenter incompatible")
            }
            if strength < minStrength {
                k = 0.3
                r += "; strength < 0.6"
            }
            (kc, rule) = (k, r)
        default:
            kc = 0.3
            rule = "no two detectors agree"
        }
        return KeyVote(votes: votes, camelot: top, agreeing: nt, strength: strength, confidence: kc, rule: rule)
    }
}
