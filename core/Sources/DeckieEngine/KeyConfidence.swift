import Foundation
import DeckieCore

/// The key confidence: research R's rule for the whitened-HPCP key (`HPCPKey`, docs/research/r-key-parity.md) on the
/// record's documented scale, the lab's B.9 levels (mixer/analyze.py), on which `key_uncertain` marks anything under
/// 0.5:
///
///   sure: all three profiles (edma, bgate, braw) pick the key on their own and the margin is at least 0.08   1.0
///   anything else (fewer than three agree, or a smaller margin)                                           0.45
///
/// The memo's rule is a yes or no, so it takes two of the lab's levels: 1.0, the lab's level for three detectors
/// agreeing with strength, and 0.45, its level for a decision with a dissent, below the line that sets
/// `key_uncertain`. A finer mapping is unmeasured (the memo's open question); the margin and the agreement are in the
/// lab JSON's `deckie.key` for whoever measures it. On research R's held-out tracks, sure keys were 92.0 percent exact
/// against the lab (88 tracks) and unsure ones 65.1 (43); on the 373-track sheet (mixer/key_parity_keys.tsv) 217 are
/// sure, so 156 would be flagged `key_uncertain` (the three-profile vote flagged 88, the lab 58). Nothing here was
/// fitted beyond the memo's 0.08, which research R set on its dev split.
public struct KeyConfidence: Sendable, Equatable {
    /// 1.0 (sure) or 0.45.
    public var value: Double
    /// The rule that gave it: a prefix naming the method and its profiles, then the words of the case.
    public var rule: String

    public init(value: Double, rule: String) {
        self.value = value
        self.rule = rule
    }

    /// What the record's rule starts with.
    public static let prefix = "hpcp-whitened (edma, bgate, braw): "
    /// The two levels.
    public static let sure = 1.0, unsure = 0.45

    /// The confidence of a decision of the HPCP key method.
    public static func hpcp(_ d: HPCPKey.Decision) -> KeyConfidence {
        if d.sure {
            return KeyConfidence(value: sure, rule: prefix + "sure: all three profiles agree, margin at least 0.08")
        }
        let agree = d.agree == 3 ? "all three profiles agree" : "\(d.agree) of 3 profiles agree"
        let margin = d.margin >= HPCPKey.marginSure ? "margin at least 0.08" : "margin under 0.08"
        return KeyConfidence(value: unsure, rule: prefix + "unsure: \(agree), \(margin)")
    }
}
