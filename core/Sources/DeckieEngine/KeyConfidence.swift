import Foundation
import DeckieCore

/// The key confidence, the lab's B.9 rule reduced to the one estimator the engine has (`KeyEstimator`, the FFT chroma
/// with the edma profile, mixer/key_light.py). **A departure from the lab, to confirm on the Mac.**
///
/// The lab votes three detectors (Essentia's edma and bgate profiles and madmom's CNN): all three agree, 1.0 (0.6 when
/// Essentia's strength is under 0.6); two agree and the third is a Camelot neighbour, 0.65; two agree otherwise, 0.45;
/// a two-of-three case with strength under 0.6, or no agreement, 0.3; without madmom, edma == bgate with strength at
/// least 0.6 gives 0.7, else 0.3. With one estimator there is nothing to agree with. A lone vote is not read as "all
/// three agree": that would give every track 1.0 (or 0.6), yet the estimator alone is right on 75 percent of the
/// lab's confident keys. So the agreement levels 1.0, 0.7 and 0.6 are never given, and the estimator's own margin (its
/// correlation with the best key minus that with the runner-up) stands in for agreement:
///
///   r < 0.6                         -> 0.3   (the lab's "strength < 0.6 -> 0.3"; Essentia's strength and this r are
///                                             both Pearson correlations of a chroma with a key profile)
///   margin >= 0.10                  -> 0.65  (as sure as two agreeing with a neighbour dissenting)
///   0.04 <= margin < 0.10           -> 0.45  (two agreeing, the third incompatible)
///   margin < 0.04                   -> 0.3   (no agreement); 0.04 is the estimator's own `min_margin` for key changes
///
/// On the lab's 311 tracks with a key confidence of 0.65 or more (mixer/key_light_stft.tsv, the lab's own run of this
/// estimator), the three levels are right on 84, 77 and 60 percent of tracks (exact key) and 97, 90 and 78 percent
/// (exact or a Camelot neighbour), holding 155, 72 and 146 of the 373 tracks; the 0.10 step is where the exact rate
/// jumps (67 percent between 0.06 and 0.08, 81 between 0.08 and 0.10, 82 to 83 above). Everything under 0.5 is flagged
/// `key_uncertain`, as in the lab, so the engine flags more tracks than the lab does (218 of 373 against 58): the Mac
/// run of `deckie-build bench` decides whether the steps hold on the audio and whether 0.45 should rise.
public struct KeyConfidence: Sendable, Equatable {
    /// 0.65, 0.45 or 0.3.
    public var value: Double
    /// The rule that gave it, in the lab's `confidence_rule` style.
    public var rule: String

    public init(value: Double, rule: String) {
        self.value = value
        self.rule = rule
    }

    /// Below this correlation the key gets 0.3 whatever its margin.
    public static let minR = 0.6
    /// A margin at least this gives 0.65.
    public static let strongMargin = 0.10
    /// A margin at least this (and under `strongMargin`) gives 0.45.
    public static let minMargin = 0.04

    /// The confidence of one estimate.
    public static func oneEstimator(_ e: KeyEstimate) -> KeyConfidence {
        let prefix = "one estimator (deckie edma): "
        if !(e.r >= minR) { return KeyConfidence(value: 0.3, rule: prefix + "r < 0.6 -> 0.3") }
        if e.margin >= strongMargin { return KeyConfidence(value: 0.65, rule: prefix + "margin >= 0.10 -> 0.65") }
        if e.margin >= minMargin { return KeyConfidence(value: 0.45, rule: prefix + "margin 0.04 to 0.10 -> 0.45") }
        return KeyConfidence(value: 0.3, rule: prefix + "margin < 0.04 -> 0.3")
    }
}
