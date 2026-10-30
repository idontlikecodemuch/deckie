import Foundation

/// Port of the web player's joinInfo / keyVerdict, plus the suggestion sampler.

let MNUM: [String: Double] = ["1": 1, "1/2": 0.5, "2": 2, "3/4": 0.75, "4/3": 4.0 / 3, "2/3": 2.0 / 3, "3/2": 1.5]

func keyVerdict(_ ka: String, _ kb: String, _ reasons: [String]) -> String {
    func parse(_ k: String) -> (Int, Character)? {
        guard let last = k.last, last == "A" || last == "B", let n = Int(k.dropLast()), (1...12).contains(n) else { return nil }
        return (n, last)
    }
    guard let pa = parse(ka), let pb = parse(kb) else { return "key unsure" }
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
/// Which tracks the picks may come from: both discs (default), one disc, or the whole catalogue.
struct LibraryFilter: Equatable {
    var cd1 = true      // CD1 Singalongs
    var cd2 = true      // CD2 Mix-ins
    var other = false   // everything else in the catalogue (alternates, benched tracks)
    /// A crate with no discs has nothing "on the discs", so every track is allowed there.
    func allows(_ t: Track) -> Bool { Library.shared.data.discs.isEmpty || (t.on ? (t.disc == "S" ? cd1 : cd2) : other) }
    var label: String { [cd1 ? "CD1" : nil, cd2 ? "CD2" : nil, other ? "all" : nil].compactMap { $0 }.joined(separator: "+") }
}

struct Option: Identifiable, Hashable {
    enum Kind: Hashable { case pinned, best, hard, more }
    let id: String          // target track id
    let pair: Pair
    let kind: Kind
    let tags: [String]      // why it is "hard / unexpected"
}

struct Suggester {
    let lib = Library.shared

    /// Candidate pairs for `cur`, limited to the target discs; one cut per song; nothing recently played.
    func candidates(for cur: Track, target: LibraryFilter, exclude: Set<String>) -> [Pair] {
        let pairs = lib.data.pairs[cur.id] ?? []
        var bestPerCut: [String: Pair] = [:]
        var order: [String] = []
        for p in pairs {
            guard let t = lib.byId[p.b], t.id != cur.id, t.cut != cur.cut, t.songKey != cur.songKey, !exclude.contains(t.id) else { continue }
            if !target.allows(t) { continue }
            if let old = bestPerCut[t.songKey] {
                // prefer the on-disc cut, then the longest cut, then the better score
                let ot = lib.byId[old.b]!
                let better = (t.on && !ot.on) || (t.on == ot.on && ((t.longest && !ot.longest) || (t.longest == ot.longest && p.s > old.s)))
                if better { bestPerCut[t.songKey] = p }
            } else { bestPerCut[t.songKey] = p; order.append(t.songKey) }
        }
        return order.compactMap { bestPerCut[$0] }.sorted { $0.s > $1.s }
    }

    func surpriseTags(_ cur: Track, _ p: Pair, belowBand: Bool) -> [String] {
        guard let t = lib.byId[p.b] else { return [] }
        var tags: [String] = []
        if p.m == "1/2" { tags.append("half time") }
        else if p.m == "2" { tags.append("double time") }
        else if p.m != "1" { tags.append("x\(p.m) tempo") }
        let ao = cur.bpmOut ?? cur.bpmShown, bi = (t.bpmIn ?? t.bpmShown) * (MNUM[p.m] ?? 1)
        if p.st >= 4 || (ao > 0 && abs(bi / ao - 1) >= 0.04) { tags.append("tempo change") }
        if t.hal && !cur.hal { tags.append("Halloween") }
        if let d = t.disc, let cd = cur.disc, d != cd { tags.append(d == "S" ? "to CD1" : "to CD2") }
        else if !t.on { tags.append("off the discs") }
        if !t.era.isEmpty && !cur.era.isEmpty && t.era != cur.era { tags.append(t.era) }
        if belowBand { tags.append("deep cut") }
        return tags
    }

    /// Sets for the swipeable grid: each set = nBest from the top band of what is left + nHard surprising ones.
    /// `rest` = what remains afterwards, best first (compact rows).
    func rollSets<R: RandomNumberGenerator>(cur: Track, mode: SuggestMode, target: LibraryFilter, exclude: Set<String>, pinned: String?, nSets: Int, rng: inout R) -> (sets: [[Option]], rest: [Option]) {
        var pool = candidates(for: cur, target: target, exclude: exclude.union(pinned.map { [$0] } ?? []))
        let nBest = mode == .full ? 3 : 2, nHard = mode == .full ? 2 : 1
        var sets: [[Option]] = []
        for _ in 0..<nSets {
            guard !pool.isEmpty else { break }
            let top = pool[0].s
            let bandN = min(pool.count, max(6, min(12, pool.filter { $0.s >= top - 0.10 }.count)))
            var band = Array(pool.prefix(bandN))
            var set: [Option] = []
            for _ in 0..<min(nBest, band.count) {
                let i = weightedIndex(band.map { exp(($0.s - top) / 0.05) }, &rng)
                set.append(Option(id: band[i].b, pair: band[i], kind: .best, tags: []))
                band.remove(at: i)
            }
            var taken = Set(set.map(\.id))
            pool.removeAll { taken.contains($0.b) }
            let bandSet = Set(pool.prefix(max(0, bandN - set.count)).map(\.b))
            var hardPool = pool.map { p in (p, surpriseTags(cur, p, belowBand: !bandSet.contains(p.b))) }.filter { !$0.1.isEmpty }
            var usedPrimary = Set<String>()
            for _ in 0..<nHard {
                guard !hardPool.isEmpty else { break }
                let w = hardPool.map { (p, tags) -> Double in
                    max(0.05, p.s) * (0.4 + Double(tags.filter { $0 != "deep cut" }.count)) * (usedPrimary.contains(tags[0]) ? 0.3 : 1)
                }
                let (p, tags) = hardPool.remove(at: weightedIndex(w, &rng))
                usedPrimary.insert(tags[0])
                set.append(Option(id: p.b, pair: p, kind: .hard, tags: Array(tags.prefix(2))))
            }
            taken = Set(set.map(\.id))
            pool.removeAll { taken.contains($0.b) }
            sets.append(set)
        }
        return (sets, pool.prefix(12).map { Option(id: $0.b, pair: $0, kind: .more, tags: []) })
    }

    /// The pair for a pinned target (may be absent from the trimmed list: then a nil pair -> computed join).
    func pair(from a: String, to b: String) -> Pair? { lib.data.pairs[a]?.first { $0.b == b } }
}

func weightedIndex<R: RandomNumberGenerator>(_ w: [Double], _ rng: inout R) -> Int {
    let total = w.reduce(0, +)
    guard total > 0 else { return Int.random(in: 0..<w.count, using: &rng) }
    var x = Double.random(in: 0..<total, using: &rng)
    for (i, v) in w.enumerated() { x -= v; if x < 0 { return i } }
    return w.count - 1
}
