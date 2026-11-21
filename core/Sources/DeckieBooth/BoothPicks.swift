import Foundation
import DeckieCore

/// One scored pair, from the playing song to `b`, as the picks show it: score, stretch, tempo multiple, the incoming
/// deck's pitch, the move and its words, the two keys, the scoring's reasons, up to three moves. The iPad app's `Pair`.
public struct BoothPair: Codable, Hashable, Sendable {
    public let b: String
    public let s: Double
    public let st: Double
    public let m: String
    public let pitch: Double?
    public let tr: String
    public let trl: String
    public let ka: String
    public let kb: String
    public let reasons: [String]
    public let mv: [String]?        // up to three moves, primary first (labels)
    public let ks: Int?
    /// D36: true when either song has only a home note, so `ka` and `kb` are the codes the scoring compared it as (the
    /// better fit of the two keys on the note), not keys that were read.
    public var kh: Bool? = nil
    public init(b: String, s: Double, st: Double, m: String, pitch: Double?, tr: String, trl: String, ka: String, kb: String,
                reasons: [String], mv: [String]?, ks: Int?, kh: Bool? = nil) {
        self.b = b; self.s = s; self.st = st; self.m = m; self.pitch = pitch; self.tr = tr; self.trl = trl; self.ka = ka
        self.kb = kb; self.reasons = reasons; self.mv = mv; self.ks = ks; self.kh = kh
    }
}

/// Which songs the picks may come from: the crate's discs, each on or off (every disc on by default), and the rest of the
/// crate (off by default). Keyed by the disc's own label. The iPad app's `LibraryFilter`.
public struct BoothFilter: Equatable, Sendable {
    public var offDiscs: Set<String> = []   // discs switched off
    public var other = false                // everything else in the crate
    public init() {}
    public func isOn(_ disc: String) -> Bool { !offDiscs.contains(disc) }
    public mutating func set(_ disc: String, on: Bool) { if on { offDiscs.remove(disc) } else { offDiscs.insert(disc) } }
    public mutating func toggle(_ disc: String) { set(disc, on: !isOn(disc)) }
    /// Whether one place is allowed. A crate with no discs has nothing "on the discs", so every song is allowed there.
    public func allows(on: Bool, disc: String?, crateHasDiscs: Bool) -> Bool {
        !crateHasDiscs || (on ? disc.map(isOn) ?? other : other)
    }
    /// "CD1+CD2", "Singalongs+all": the discs that are on, by their short names, then "all" when the rest is on.
    public func label(_ discs: [BoothDisc]) -> String {
        (discs.filter { isOn($0.disc) }.map(\.short) + (other ? [BoothWords.t("pick.filterAll")] : [])).joined(separator: BoothWords.t("pick.filterJoin"))
    }
}

/// One row of the picks. The iPad app's `Option`.
public struct BoothPick: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case pinned, pick }
    public let id: String          // the song picked
    public let pair: BoothPair?    // nil only for a pinned song the scoring has no pair for (a computed join)
    public let kind: Kind
    public let tags: [String]      // what is unexpected about it (half time, tempo change, to CD2, deep cut, ...)
    public init(id: String, pair: BoothPair?, kind: Kind, tags: [String]) { self.id = id; self.pair = pair; self.kind = kind; self.tags = tags }
}

/// The picks list (the iPad app's `Suggester`): candidates for the playing song, one row per song, the shortlist in the
/// Shuffle dial's order, the tags.
public struct BoothPicks {
    public let lib: BoothLibrary
    /// The scored pairs from a song (the iPad keeps the last few; nil: scored each time from `lib`).
    public let pairs: (String) -> [BoothPair]
    public init(_ lib: BoothLibrary, pairs: ((String) -> [BoothPair])? = nil) {
        self.lib = lib
        self.pairs = pairs ?? { lib.picks(from: $0) }
    }

    /// Candidate pairs for `cur`, limited to the target discs; one row per song; nothing recently played. One song is
    /// one recording (D24): copies of it (the same `cut`) make one row, never versions with a similar title, and so do
    /// the other places of one file (D27). The row is the copy whose place leads among the places the filter allows: on
    /// the playing song's disc, else on the first disc in the crate's order. A song is allowed when any of its places
    /// is; places on discs switched off still show on the row as "also on". A song played recently, by any copy, is
    /// left out, as is the playing song.
    public func candidates(for cur: BoothSong, target: BoothFilter, exclude: Set<String>) -> [BoothPair] {
        let pairs = self.pairs(cur.id)
        let excluded = Set(exclude.compactMap { lib.byId[$0]?.cut })
        var byCut: [String: [BoothPair]] = [:]
        var order: [String] = []
        for p in pairs {
            guard let t = lib.byId[p.b], t.cut != cur.cut, !excluded.contains(t.cut), lib.allows(t, target) else { continue }
            if byCut[t.cut] == nil { order.append(t.cut) }
            byCut[t.cut, default: []].append(p)
        }
        let allows = allowsPlace(target)
        return order.compactMap { cut -> BoothPair? in
            guard let ps = byCut[cut], let first = ps.first else { return nil }
            if ps.count == 1 { return first }
            let lead = lib.places(of: first.b, playingDisc: cur.disc, among: allows).first?.id
            return ps.first { $0.b == lead } ?? ps.max { $0.s < $1.s }
        }.sorted { $0.s > $1.s }
    }

    /// The filter as a test of one song at one place.
    public func allowsPlace(_ target: BoothFilter) -> (BoothSong) -> Bool {
        let hasDiscs = !lib.discs.isEmpty
        return { target.allows(on: $0.on, disc: $0.disc, crateHasDiscs: hasDiscs) }
    }

    public func surpriseTags(_ cur: BoothSong, _ p: BoothPair, target: BoothFilter, deepCut: Bool) -> [String] {
        // The place the row shows (D27): the one that leads among those the filter allows.
        guard let t = lib.placed(p.b, playingDisc: cur.disc, among: allowsPlace(target)) else { return [] }
        var tags: [String] = []
        if p.m == "1/2" { tags.append(BoothWords.t("pick.tag.halfTime")) }
        else if p.m == "2" { tags.append(BoothWords.t("pick.tag.doubleTime")) }
        else if p.m != "1" { tags.append(BoothWords.t("pick.tag.tempoMultiple", ["m": p.m])) }
        let ao = cur.bpmOut ?? cur.bpmShown, bi = (t.bpmIn ?? t.bpmShown) * (BoothJoin.multiples[p.m] ?? 1)
        if p.st >= 4 || (ao > 0 && abs(bi / ao - 1) >= 0.04) { tags.append(BoothWords.t("pick.tag.tempoChange")) }
        if t.hal && !cur.hal { tags.append(BoothWords.t("pick.tag.halloween")) }
        if let d = t.disc, let cd = cur.disc, d != cd { tags.append(BoothWords.t("pick.tag.to", ["source": lib.discs.first { $0.disc == d }?.short ?? d])) }
        // not on any source the booth has: say which folder it is in (a crate file with no sources has no "off")
        else if !t.on && !lib.discs.isEmpty {
            tags.append(t.folder.isEmpty ? BoothWords.t("pick.tag.inCrate") : BoothWords.t("pick.tag.in", ["folder": t.folder]))
        }
        if !t.era.isEmpty && !cur.era.isEmpty && t.era != cur.era { tags.append(t.era) }
        if deepCut { tags.append(BoothWords.t("pick.tag.deepCut")) }
        return tags
    }

    /// The picks for `cur`, one ranked list: the shortlist (the best tenth of the library, never fewer than 10, of what
    /// the filter leaves) in the order the Shuffle dial gives (0 = pure rank by score, 1 = a fair shuffle), with a pinned
    /// song first, then every other candidate in plain score order, best first (no dice). `shortlist` is how many
    /// shortlist picks the list holds; "deep cut" marks the lower half of the shortlist by score.
    public func ranked<R: RandomNumberGenerator>(cur: BoothSong, target: BoothFilter, exclude: Set<String>, pinned: String?,
                                                 shuffle: Double, rng: inout R) -> (list: [BoothPick], shortlist: Int) {
        let best = candidates(for: cur, target: target, exclude: exclude.union(pinned.map { [$0] } ?? []))
        let n = min(best.count, Shortlist.size(libraryCount: lib.songCount))
        let order = Shortlist.order(scores: best.prefix(n).map(\.s), shuffle: shuffle, rng: &rng)
        var out: [BoothPick] = []
        out.reserveCapacity(best.count + 1)
        if let pid = pinned, lib.byId[pid] != nil { out.append(BoothPick(id: pid, pair: pair(from: cur.id, to: pid), kind: .pinned, tags: [])) }
        for i in order {
            let p = best[i]
            out.append(BoothPick(id: p.b, pair: p, kind: .pick, tags: surpriseTags(cur, p, target: target, deepCut: i >= (n + 1) / 2)))
        }
        for p in best.dropFirst(n) { out.append(BoothPick(id: p.b, pair: p, kind: .pick, tags: surpriseTags(cur, p, target: target, deepCut: false))) }
        return (out, n)
    }

    /// The pair for a pinned target: a song the scoring gave no pair (outside the crate, or failing its gates) gets nil,
    /// and the join is computed from the two songs.
    public func pair(from a: String, to b: String) -> BoothPair? { pairs(a).first { $0.b == b } }

    /// The Listen page's split of a ranked list: the picks shown (5 in Simple, 10 in Full, of the shortlist, and a pinned
    /// song first) and More (the rest of the shortlist, then the rest of the crate); `restShortlist` is how many of More
    /// are from the shortlist.
    public static func split(_ list: [BoothPick], shortlist: Int, full: Bool) -> (shown: [BoothPick], more: [BoothPick], restShortlist: Int) {
        let lead = list.first?.kind == .pinned ? 1 : 0
        let n = min(shortlist, full ? 10 : 5) + lead
        return (Array(list.prefix(n)), Array(list.dropFirst(n)), shortlist + lead - n)
    }
}

/// How one pick joins the playing song (the web player's joinInfo and keyVerdict): beat-matched or not, the incoming
/// deck's pitch and its words, the two keys and the verdict. The iPad app's `JoinInfo`.
public struct BoothJoin: Sendable, Equatable {
    public let beatMatch: Bool
    public let pitch: Double?        // incoming deck pitch fader %, already corrected for deck A's pitch
    public let pitchText: String
    public let keyText: String
    public let verdict: String
    public let verdictKind: Int      // 0 good, 1 pitch-shift/unsure, 2 clash
    public let scaleB: Double        // lane B x-scale in lane-A samples per B sample

    /// The tempo multiples by the scoring's code.
    public static let multiples: [String: Double] = ["1": 1, "1/2": 0.5, "2": 2, "3/4": 0.75, "4/3": 4.0 / 3, "2/3": 2.0 / 3, "3/2": 1.5]

    /// `homeNote`: the codes are the ones the scoring compared a home-note song as (D36), not keys that were read. Such a
    /// pair is a clash only when even the better of the two keys on the note clashes; otherwise it fits on the home note,
    /// which is all the pair can honestly claim (the mode is open). `notSure`: a song with no key that Deckie read and was
    /// not sure of (D33), said apart from a key that was never read; both are left out of the score alike (D16).
    public static func keyVerdict(_ ka: String, _ kb: String, _ reasons: [String], homeNote: Bool = false, notSure: Bool = false) -> String {
        func parse(_ k: String) -> (Int, Character)? {
            guard let last = k.last, last == "A" || last == "B", let n = Int(k.dropLast()), (1...12).contains(n) else { return nil }
            return (n, last)
        }
        // A key not read is neither good nor bad for the pair (D16; the core's scoring leaves it out too).
        guard let pa = parse(ka), let pb = parse(kb) else { return notSure ? BoothWords.t("pick.verdict.keyNotSure") : "key not read" }
        if homeNote {
            let v = keyVerdict(ka, kb, reasons)
            return v == "clash" ? v : BoothWords.t("pick.verdict.homeNote")
        }
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

    /// deckAPitch: the pitch-fader percent detected on the playing deck (moves its tempo), 0 if unknown.
    public init(_ a: BoothSong, _ b: BoothSong, _ p: BoothPair?, deckAPitch: Double) {
        var k = 1.0, pitch: Double? = nil, ml = "1"
        let tr = p?.tr ?? ""
        if let p {
            ml = p.m; k = Self.multiples[ml] ?? 1; pitch = p.pitch
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
        let W = BoothWords.self
        let pt: String
        if tr == "brake_cut" { pt = W.t("pick.pitch.cutIn") }
        else if bm { pt = W.t("pick.pitch.caps", ["pitch": W.signed1(pitch!)]) + (ml != "1" ? W.t("pick.pitch.multiple", ["m": ml]) : "") }
        else if ml != "1" { pt = W.t("pick.pitch.na") + W.t("pick.pitch.multiple", ["m": ml]) }
        else { pt = W.t("pick.pitch.na") + (okP ? W.t("pick.pitch.aside", ["pitch": W.signed1(pitch!)]) : "") }
        let ka = p?.ka ?? a.key ?? "?", kb = p?.kb ?? b.key ?? "?"
        let v = Self.keyVerdict(ka, kb, p?.reasons ?? [], homeNote: p?.kh == true, notSure: a.keyNotSure == true || b.keyNotSure == true)
        let homeV = W.t("pick.verdict.homeNote"), notSureV = W.t("pick.verdict.keyNotSure")
        let vk = v == "clash" ? 2 : (v.hasPrefix("pitch-shift") || v.contains("unsure") || v == homeV || v == notSureV) ? 1 : 0
        let sB = bm ? k : ((a.bpm != nil && b.bpm != nil) ? a.bpm! / b.bpm! : 1)
        // The keys as the songs show them (D36): a code, "Home note A", "not sure" or "?".
        let keyText = p?.kh == true || a.keyShownIsWords || b.keyShownIsWords ? W.t("pick.keys", ["a": a.keyShown, "b": b.keyShown])
                                                                              : W.t("pick.keys", ["a": ka, "b": kb])
        beatMatch = bm; self.pitch = pitch; pitchText = pt; self.keyText = keyText; verdict = v; verdictKind = vk; scaleB = sB
    }

    /// "128 BPM · pitch +3.2%" ("120→126 BPM" when the song changes tempo; no pitch when it can't be beat-matched).
    public static func bpmLine(_ t: BoothSong, _ pair: BoothPair?, _ ji: BoothJoin) -> String {
        var bpm = BoothWords.bpm(t.bpmShown)
        if let bi = t.bpmIn, abs(bi / max(1, t.bpmShown) - 1) > 0.02 { bpm = BoothWords.bpmChange(bi, t.bpmShown) }
        guard pair?.tr != "brake_cut", ji.beatMatch, let p = ji.pitch else { return bpm }
        return BoothWords.t("pick.pitchAfterBPM", ["bpm": bpm, "pitch": BoothWords.signed1(p)])
            + (pair.map { $0.m != "1" ? BoothWords.t("pick.tempoMultiple", ["m": $0.m]) : "" } ?? "")
    }

    /// The move: "blend", "echo out · keys may clash", "no beat-match · brake".
    public static func moveLine(_ pair: BoothPair?, _ ji: BoothJoin) -> String {
        let W = BoothWords.self
        var parts: [String] = []
        if pair?.tr == "brake_cut" || !ji.beatMatch { parts.append(W.t("pick.noBeatMatch")) }
        if let p = pair {
            // the moves as a small menu: primary / alternative
            let brakeCut = W.t("pick.move.brake_cut")
            let mv = (p.mv?.isEmpty == false ? p.mv! : [p.trl]).map { $0 == brakeCut ? W.t("pick.brake") : $0 }
            parts.append(mv.prefix(2).joined(separator: W.t("pick.movesJoin")))
        }
        if ji.verdict == "clash" { parts.append(W.t("pick.keyClash")) }
        // A home-note pair that fits (D36): the fit rests on the note alone, with major or minor open.
        else if ji.verdict == W.t("pick.verdict.homeNote") { parts.append(W.t("pick.moveHomeNote")) }
        return parts.joined(separator: W.t("pick.moveLineJoin"))
    }
}
