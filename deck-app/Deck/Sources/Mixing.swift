import Foundation
import DeckieCore

/// Port of the web player's joinInfo / keyVerdict, plus the picks list (the shortlist, ordered by the Shuffle dial, then the rest of the crate by score).

let MNUM: [String: Double] = ["1": 1, "1/2": 0.5, "2": 2, "3/4": 0.75, "4/3": 4.0 / 3, "2/3": 2.0 / 3, "3/2": 1.5]

func keyVerdict(_ ka: String, _ kb: String, _ reasons: [String]) -> String {
    func parse(_ k: String) -> (Int, Character)? {
        guard let last = k.last, last == "A" || last == "B", let n = Int(k.dropLast()), (1...12).contains(n) else { return nil }
        return (n, last)
    }
    // A key not read is neither good nor bad for the pair (D16; the core's scoring leaves it out too).
    guard let pa = parse(ka), let pb = parse(kb) else { return "key not read" }
    if ka == kb { return "same key" }
    let d = ((pb.0 - pa.0) % 12 + 12) % 12
    if pa.1 == pb.1 && (d == 1 || d == 11) { return "neighbour" }
    if pa.0 == pb.0 { return "relative" }
    if pa.1 == pb.1 && d == 2 { return "boost" }
    for r in reasons {
        if let a = r.range(of: "(pitch-shift"), let e = r[a.lowerBound...].firstIndex(of: ")") {
            return String(r[r.index(after: a.lowerBound)..<e]).replacingOccurrences(of: " B by", with: "")
        }
    }
    return "clash"
}

struct JoinInfo {
    let beatMatch: Bool
    let pitch: Double?        // incoming deck pitch fader %, already corrected for deck A's pitch
    let pitchText: String
    let keyText: String
    let verdict: String
    let verdictKind: Int      // 0 good, 1 pitch-shift/unsure, 2 clash
    let scaleB: Double        // lane B x-scale in lane-A samples per B sample
}

/// deckAPitch: the pitch-fader percent detected on the playing deck (moves its tempo), 0 if unknown.
func joinInfo(_ a: Track, _ b: Track, _ p: Pair?, deckAPitch: Double) -> JoinInfo {
    var k = 1.0, pitch: Double? = nil, ml = "1"
    let tr = p?.tr ?? ""
    if let p {
        ml = p.m; k = MNUM[ml] ?? 1; pitch = p.pitch
    } else {
        let ao = a.bpmOut ?? a.bpmShown, bi = b.bpmIn ?? b.bpmShown
        for (kk, l) in [(1.0, "1"), (0.5, "1/2"), (2.0, "2")] {
            let pp = (ao / kk / bi - 1) * 100
            if pitch == nil || abs(pp) < abs(pitch!) { pitch = pp; k = kk; ml = l }
        }
    }
    if let pp = pitch, deckAPitch != 0 { pitch = ((1 + deckAPitch / 100) * (1 + pp / 100) - 1) * 100 }
    let okP = pitch.map { $0.isFinite } ?? false
    let bm = tr != "brake_cut" && ["1", "1/2", "2"].contains(ml) && okP && abs(pitch!) <= 16
    let pt: String
    if tr == "brake_cut" { pt = "cut in, no beat-match" }
    else if bm { pt = "PITCH " + signed1(pitch!) + "%" + (ml != "1" ? " · x" + ml : "") }
    else if ml != "1" { pt = "PITCH n/a · x" + ml }
    else { pt = "PITCH n/a" + (okP ? " · " + signed1(pitch!) + "%" : "") }
    let ka = p?.ka ?? a.key ?? "?", kb = p?.kb ?? b.key ?? "?"
    let v = keyVerdict(ka, kb, p?.reasons ?? [])
    let vk = v == "clash" ? 2 : (v.hasPrefix("pitch-shift") || v.contains("unsure")) ? 1 : 0
    let sB = bm ? k : ((a.bpm != nil && b.bpm != nil) ? a.bpm! / b.bpm! : 1)
    return JoinInfo(beatMatch: bm, pitch: pitch, pitchText: pt, keyText: "\(ka) → \(kb)", verdict: v, verdictKind: vk, scaleB: sB)
}

// MARK: - suggestions

enum SuggestMode: String, CaseIterable { case simple = "SIMPLE", full = "FULL" }
/// Which tracks the picks may come from: the crate's discs, each on or off (every disc on by default), and the rest
/// of the catalogue (off by default). Keyed by the disc's own label (`Disc.disc`), so it follows whatever discs the
/// crate has.
struct LibraryFilter: Equatable {
    var offDiscs: Set<String> = []   // discs switched off
    var other = false                // everything else in the catalogue (alternates, benched tracks)
    func isOn(_ disc: String) -> Bool { !offDiscs.contains(disc) }
    mutating func set(_ disc: String, on: Bool) { if on { offDiscs.remove(disc) } else { offDiscs.insert(disc) } }
    mutating func toggle(_ disc: String) { set(disc, on: !isOn(disc)) }
    /// A crate with no discs has nothing "on the discs", so every track is allowed there.
    func allows(_ t: Track) -> Bool {
        Library.shared.data.discs.isEmpty || (t.on ? t.disc.map(isOn) ?? other : other)
    }
    /// "CD1+CD2", "Singalongs+all": the discs that are on, by their short names, then "all" when the rest is on.
    var label: String {
        (Library.shared.data.discs.filter { isOn($0.disc) }.map(\.short) + (other ? ["all"] : [])).joined(separator: "+")
    }
}

struct Option: Identifiable, Hashable {
    enum Kind: Hashable { case pinned, pick }
    let id: String          // target track id
    let pair: Pair?         // nil only for a pinned song the scoring has no pair for (a computed join)
    let kind: Kind
    let tags: [String]      // what is unexpected about it (half time, tempo change, to CD2, deep cut, ...)
}

struct Suggester {
    let lib = Library.shared

    /// Candidate pairs for `cur`, limited to the target discs; one row per song; nothing recently played.
    /// One song is one recording (D24): copies of it (the same `cut`) make one row, never versions with a similar
    /// title, and so do the other places of one file (D27). The row is the copy whose place leads among the places the
    /// filter allows: on the playing song's disc, else on the first disc in the crate's order. A song is allowed when
    /// any of its places is; places on discs switched off still show on the row as "also on". A song played recently,
    /// by any copy, is left out, as is the playing song.
    func candidates(for cur: Track, target: LibraryFilter, exclude: Set<String>) -> [Pair] {
        let pairs = lib.pairs(from: cur.id)
        let excluded = Set(exclude.compactMap { lib.byId[$0]?.cut })
        var byCut: [String: [Pair]] = [:]
        var order: [String] = []
        for p in pairs {
            guard let t = lib.byId[p.b], t.cut != cur.cut, !excluded.contains(t.cut), lib.allows(t, target) else { continue }
            if byCut[t.cut] == nil { order.append(t.cut) }
            byCut[t.cut, default: []].append(p)
        }
        return order.compactMap { cut -> Pair? in
            guard let ps = byCut[cut], let first = ps.first else { return nil }
            if ps.count == 1 { return first }
            let lead = lib.places(of: first.b, playingDisc: cur.disc, among: target.allows).first?.id
            return ps.first { $0.b == lead } ?? ps.max { $0.s < $1.s }
        }.sorted { $0.s > $1.s }
    }

    func surpriseTags(_ cur: Track, _ p: Pair, target: LibraryFilter, deepCut: Bool) -> [String] {
        // The place the row shows (D27): the one that leads among those the filter allows.
        guard let t = lib.placed(p.b, playingDisc: cur.disc, among: target.allows) else { return [] }
        var tags: [String] = []
        if p.m == "1/2" { tags.append("half time") }
        else if p.m == "2" { tags.append("double time") }
        else if p.m != "1" { tags.append("x\(p.m) tempo") }
        let ao = cur.bpmOut ?? cur.bpmShown, bi = (t.bpmIn ?? t.bpmShown) * (MNUM[p.m] ?? 1)
        if p.st >= 4 || (ao > 0 && abs(bi / ao - 1) >= 0.04) { tags.append("tempo change") }
        if t.hal && !cur.hal { tags.append("Halloween") }
        if let d = t.disc, let cd = cur.disc, d != cd { tags.append("to " + (lib.data.discs.first { $0.disc == d }?.short ?? d)) }
        // not on any source the booth has: say which folder it is in (a crate file with no sources has no "off")
        else if !t.on && !lib.data.discs.isEmpty { tags.append(t.folder.isEmpty ? "in the crate" : "in " + t.folder) }
        if !t.era.isEmpty && !cur.era.isEmpty && t.era != cur.era { tags.append(t.era) }
        if deepCut { tags.append("deep cut") }
        return tags
    }

    /// The picks for `cur`, one ranked list: the shortlist (the best tenth of the library, never fewer than 10, of
    /// what the filter leaves) in the order the Shuffle dial gives (0 = pure rank by score, 1 = a fair shuffle),
    /// with a pinned song first, then every other candidate in plain score order, best first (no dice).
    /// `shortlist` is how many shortlist picks the list holds; "deep cut" marks the lower half of the shortlist by score.
    func ranked<R: RandomNumberGenerator>(cur: Track, target: LibraryFilter, exclude: Set<String>, pinned: String?, shuffle: Double, rng: inout R) -> (list: [Option], shortlist: Int) {
        let best = candidates(for: cur, target: target, exclude: exclude.union(pinned.map { [$0] } ?? []))
        let n = min(best.count, Shortlist.size(libraryCount: lib.songCount))
        let order = Shortlist.order(scores: best.prefix(n).map(\.s), shuffle: shuffle, rng: &rng)
        var out: [Option] = []
        out.reserveCapacity(best.count + 1)
        if let pid = pinned, lib.byId[pid] != nil { out.append(Option(id: pid, pair: pair(from: cur.id, to: pid), kind: .pinned, tags: [])) }
        for i in order {
            let p = best[i]
            out.append(Option(id: p.b, pair: p, kind: .pick, tags: surpriseTags(cur, p, target: target, deepCut: i >= (n + 1) / 2)))
        }
        for p in best.dropFirst(n) { out.append(Option(id: p.b, pair: p, kind: .pick, tags: surpriseTags(cur, p, target: target, deepCut: false))) }
        return (out, n)
    }

    /// The pair for a pinned target: every scored song is in the list; a song the scoring gave no pair (outside the
    /// crate, or failing its gates) gets nil, and the join is computed from the two tracks.
    func pair(from a: String, to b: String) -> Pair? { lib.pairs(from: a).first { $0.b == b } }
}

extension Array where Element == String {
    /// "CD1, CD2 or All": the words joined for a sentence.
    var joinedWithOr: String { count < 2 ? joined() : dropLast().joined(separator: ", ") + " or " + last! }
}
