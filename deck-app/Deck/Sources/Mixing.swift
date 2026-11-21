import Foundation
import DeckieCore
import DeckieBooth

// The picks list and how each pick joins the playing song (the shortlist, ordered by the Shuffle dial, then the rest of
// the crate by score; the join's pitch and key words) are the core's, shared with Desk's Booth (DeckieBooth's
// `BoothPicks` and `BoothJoin`, D42). This file turns the app's tracks into the shared songs and back.

/// The tempo multiples by the scoring's code.
let MNUM: [String: Double] = BoothJoin.multiples

/// How a pick joins the playing song (the core's `BoothJoin`).
typealias JoinInfo = BoothJoin

/// The key verdict for two wheel codes (the core's `BoothJoin.keyVerdict`).
func keyVerdict(_ ka: String, _ kb: String, _ reasons: [String], homeNote: Bool = false, notSure: Bool = false) -> String {
    BoothJoin.keyVerdict(ka, kb, reasons, homeNote: homeNote, notSure: notSure)
}

/// deckAPitch: the pitch-fader percent detected on the playing deck (moves its tempo), 0 if unknown.
func joinInfo(_ a: Track, _ b: Track, _ p: Pair?, deckAPitch: Double) -> JoinInfo {
    let lib = Library.shared
    return BoothJoin(lib.song(a)!, lib.song(b)!, p, deckAPitch: deckAPitch)
}

// MARK: - suggestions

enum SuggestMode: String, CaseIterable { case simple = "SIMPLE", full = "FULL" }

/// Which tracks the picks may come from: the crate's discs, each on or off (every disc on by default), and the rest
/// of the catalogue (off by default). Keyed by the disc's own label (`Disc.disc`), so it follows whatever discs the
/// crate has. The core's `BoothFilter`.
typealias LibraryFilter = BoothFilter
extension BoothFilter {
    /// A crate with no discs has nothing "on the discs", so every track is allowed there.
    func allows(_ t: Track) -> Bool { allows(on: t.on, disc: t.disc, crateHasDiscs: !Library.shared.data.discs.isEmpty) }
    /// "CD1+CD2", "Singalongs+all": the discs that are on, by their short names, then "all" when the rest is on.
    var label: String { label(Library.shared.booth.discs) }
}

/// One row of the picks (the core's `BoothPick`).
typealias Option = BoothPick

/// The picks list for the app's tracks (the core's `BoothPicks`, with the app's kept scoring of the last few songs).
struct Suggester {
    let lib = Library.shared
    private var picks: BoothPicks { BoothPicks(lib.booth) { [lib] in lib.pairs(from: $0) } }

    /// Candidate pairs for `cur`, limited to the target discs; one row per song; nothing recently played.
    func candidates(for cur: Track, target: LibraryFilter, exclude: Set<String>) -> [Pair] {
        guard let s = lib.song(cur) else { return [] }
        return picks.candidates(for: s, target: target, exclude: exclude)
    }

    func surpriseTags(_ cur: Track, _ p: Pair, target: LibraryFilter, deepCut: Bool) -> [String] {
        guard let s = lib.song(cur) else { return [] }
        return picks.surpriseTags(s, p, target: target, deepCut: deepCut)
    }

    /// The picks for `cur`, one ranked list: the shortlist in the Shuffle dial's order, a pinned song first, then every
    /// other candidate in plain score order (`BoothPicks.ranked`).
    func ranked<R: RandomNumberGenerator>(cur: Track, target: LibraryFilter, exclude: Set<String>, pinned: String?, shuffle: Double, rng: inout R) -> (list: [Option], shortlist: Int) {
        guard let s = lib.song(cur) else { return ([], 0) }
        return picks.ranked(cur: s, target: target, exclude: exclude, pinned: pinned, shuffle: shuffle, rng: &rng)
    }

    /// The pair for a pinned target (nil: the join is computed from the two tracks).
    func pair(from a: String, to b: String) -> Pair? { picks.pair(from: a, to: b) }
}

extension Array where Element == String {
    /// "CD1, CD2 or All": the words joined for a sentence.
    var joinedWithOr: String { Words.orList(self) }
}
