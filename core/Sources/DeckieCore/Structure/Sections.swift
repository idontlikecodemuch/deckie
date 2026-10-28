import Foundation

/// A stretch between two section boundaries, the lab's `sections` entries. Bars are 1-based, `endBar` exclusive.
public struct Section: Sendable, Equatable {
    public var startBar: Int
    public var endBar: Int
    /// "intro" (the first section), "outro" (the one ending at the last bar), otherwise "main" or "break" by energy.
    public var label: String
    /// "high" when the section's mean bar loudness is at least the median bar loudness - 1.5 LU, otherwise "low".
    public var energy: String
    /// Mean per-bar loudness of the section in LUFS (the lab writes it to 2 decimals).
    public var lufs: Double
    /// Mean per-bar vocal probability of the section (3 decimals in the file).
    public var vocal: Double

    public init(startBar: Int, endBar: Int, label: String, energy: String, lufs: Double, vocal: Double) {
        self.startBar = startBar
        self.endBar = endBar
        self.label = label
        self.energy = energy
        self.lufs = lufs
        self.vocal = vocal
    }

    /// Margin below the median bar loudness, in LU, down to which a section still counts as high energy.
    public static let highEnergyMargin = 1.5

    /// The sections between consecutive boundaries (1-based, as `Phrase.boundaries` gives them, the last being
    /// `nBars + 1`), from the per-bar loudness `lufsSt` and vocal probability `vocalProb` (one value per bar, so
    /// `nBars` is their length). Means are numpy's (pairwise sums); the median is numpy's.
    public static func sections(boundariesBars: [Int], lufsSt: [Double], vocalProb: [Double]) -> [Section] {
        precondition(lufsSt.count == vocalProb.count, "per-bar loudness and vocal probability differ in length")
        let nBars = lufsSt.count
        guard nBars > 0 else { return [] }
        let body = Py.median(lufsSt)
        let b0 = boundariesBars.map { $0 - 1 }
        precondition(b0.allSatisfy { $0 >= 0 && $0 <= nBars }, "boundaries outside bars 1...\(nBars + 1)")
        var out: [Section] = []
        for i in 0..<max(0, b0.count - 1) {
            let a = b0[i], b2 = b0[i + 1]
            if b2 <= a { continue }
            let e = Py.pairwiseMean(Array(lufsSt[a..<b2]))
            let energy = e >= body - highEnergyMargin ? "high" : "low"
            let label: String
            if i == 0 {
                label = "intro"
            } else if b2 == nBars {
                label = "outro"
            } else {
                label = energy == "high" ? "main" : "break"
            }
            out.append(Section(startBar: a + 1, endBar: b2 + 1, label: label, energy: energy, lufs: e,
                               vocal: Py.pairwiseMean(Array(vocalProb[a..<b2]))))
        }
        return out
    }
}
