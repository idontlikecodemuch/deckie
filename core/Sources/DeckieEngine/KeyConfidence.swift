import Foundation
import DeckieCore

/// The key confidence: the lab's B.9 rule (mixer/analyze.py) on the engine's three key votes (`KeyVote`: the STFT
/// chroma with the edma, bgate and Krumhansl-Kessler profiles, in the slots of the lab's Essentia edma, Essentia bgate
/// and madmom CNN). The levels are the lab's, unchanged:
///
///   all three agree                                    1.0   (0.6 when the strength is under 0.6)
///   two agree, the third a Camelot neighbour           0.65
///   two agree, the third incompatible                  0.45
///   two agree with the strength under 0.6              0.3
///   no two agree                                       0.3   (the key is then the edma vote's)
///
/// The strength is the edma vote's r when it holds the decided key, else the bgate vote's, else the larger of the two,
/// as the lab reads Essentia's strengths; 0.6 is the lab's own threshold. Nothing here was fitted to the lab's tracks.
/// On the lab's 373 tracks (core/Tools/key_vote_eval.py, from the lab's own run of the estimator) the levels hold 217,
/// 25, 43, 36 and 52 tracks and are exact on 81, 76, 75, 62 and 60 percent of those the lab is confident on; 88 tracks
/// fall under 0.5 and are flagged `key_uncertain`, against 58 in the lab and 218 under the one-estimator steps this
/// replaces (whose margin steps had been read off the same tracks).
public struct KeyConfidence: Sendable, Equatable {
    /// 1.0, 0.65, 0.6, 0.45 or 0.3.
    public var value: Double
    /// The rule that gave it: the lab's `confidence_rule` words after a prefix naming the engine's votes.
    public var rule: String

    public init(value: Double, rule: String) {
        self.value = value
        self.rule = rule
    }

    /// What the record's rule starts with.
    public static let prefix = "deckie votes (edma, bgate, krumhansl): "

    /// The confidence of a key vote.
    public static func votes(_ vote: KeyVote) -> KeyConfidence {
        KeyConfidence(value: vote.confidence, rule: prefix + vote.rule)
    }
}
