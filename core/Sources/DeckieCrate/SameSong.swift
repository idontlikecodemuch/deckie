import DeckieCore

// What "the same song" is, in one place (D24). Two crate entries are the same song only when they are the same
// recording, which the crate says with its existing `ident.cut_key`: entries with the same key are copies of one
// recording; an entry with no key (or an empty one) is a song on its own, keyed by its id. Nothing is folded by title,
// so a remix, an edit or a live version is its own song. Folding changes what an app shows, never what the crate keeps:
// every copy stays its own entry with its own disc, folder and track.
//
// One entry can also have more than one place (D27, `ident.other_places`): the same file, byte for byte, read from two
// sources or found in a folder on the Mac as well. Those places are treated like the places of copies: a song's places
// are every place of every entry behind it, own and other, ordered together by one rule (`ordered`).
//
// Desk fills the key (`Crate.setCutKeys(prints:)`) from a print of each file's audio (`RecordingPrint`), so copies of
// one recording under two names, in two folders or in two formats are found as one song.

public enum SameSong {
    /// The key that says which recording an entry is: its `cut_key` when set and not empty, else its own id.
    public static func key(id: String, cutKey: String?) -> String {
        guard let k = cutKey, !k.isEmpty else { return id }
        return k
    }

    /// Items grouped by key, each group in the items' order, the groups in the order their first item comes.
    public static func groups<T>(_ items: [T], key: (T) -> String) -> [[T]] {
        var at: [String: Int] = [:]
        var out: [[T]] = []
        for x in items {
            let k = key(x)
            if let i = at[k] { out[i].append(x) } else { at[k] = out.count; out.append([x]) }
        }
        return out
    }

    /// Where one copy of a song lives: the entry's id and its disc, folder and track (each nil when it has none). An
    /// entry with other places (D27) gives one of these for each of its places, all with its id.
    public struct Place: Hashable, Sendable {
        public var id: String
        public var disc: String?
        public var folder: String?
        public var track: Int?
        public init(id: String, disc: String?, folder: String?, track: Int?) {
            self.id = id; self.disc = disc; self.folder = folder; self.track = track
        }
    }

    /// The places of one song in the order an app shows them: the one that leads first, the others after it as
    /// "also on". The place that leads is on `playingDisc` (the disc the playing song is on); failing that, on the
    /// first disc in `discOrder` (the DJ's order of discs) that holds a copy. After the leading place come the other
    /// discs in the DJ's order, then discs not in that order by name, then copies on no disc; within one disc, by
    /// folder, then track number, then the order given. Give it every place of the song: each copy's own place and
    /// its other places alike (`CrateTrack.places`, `Crate.songPlaces`).
    public static func ordered(_ places: [Place], playingDisc: String?, discOrder: [String]) -> [Place] {
        let rank = Dictionary(discOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        func discRank(_ p: Place) -> (Int, String) {
            guard let d = p.disc else { return (Int.max, "") }
            if d == playingDisc { return (-1, "") }
            if let r = rank[d] { return (r, "") }
            return (discOrder.count, d)
        }
        return places.enumerated().sorted { x, y in
            let a = discRank(x.element), b = discRank(y.element)
            if a != b { return a < b }
            let fa = x.element.folder ?? "", fb = y.element.folder ?? ""
            if fa != fb { return fa < fb }
            let ta = x.element.track ?? Int.max, tb = y.element.track ?? Int.max
            if ta != tb { return ta < tb }
            return x.offset < y.offset
        }.map(\.element)
    }

    /// Copies of the same recording among `prints` (entry id to its print), by `RecordingPrint.sameRecording`, taken
    /// together through any chain of matches. Each group of two or more is keyed by the smallest id in it; the
    /// result maps every entry in such a group to that key, and leaves out entries with no copy.
    public static func copies(_ prints: [String: RecordingPrint]) -> [String: String] {
        // Only prints whose sound lasts about as long can match, so compare neighbours in order of length.
        let items = prints.compactMap { id, p in p.soundSpan.map { (id: id, p: p, len: Double($0.count) * RecordingPrint.frameStepS) } }
            .sorted { $0.len != $1.len ? $0.len < $1.len : $0.id < $1.id }
        var parent = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.id) })
        func root(_ x: String) -> String {
            var r = x
            while parent[r]! != r { r = parent[r]! }
            var y = x
            while parent[y]! != r { let n = parent[y]!; parent[y] = r; y = n }
            return r
        }
        for i in items.indices {
            var j = i + 1
            while j < items.count, items[j].len - items[i].len <= RecordingPrint.lengthToleranceS {
                let a = root(items[i].id), b = root(items[j].id)
                if a != b, RecordingPrint.sameRecording(items[i].p, items[j].p) {
                    if a < b { parent[b] = a } else { parent[a] = b }
                }
                j += 1
            }
        }
        var members: [String: [String]] = [:]
        for it in items { members[root(it.id), default: []].append(it.id) }
        var out: [String: String] = [:]
        for (_, ids) in members where ids.count > 1 {
            let key = ids.min()!
            for id in ids { out[id] = key }
        }
        return out
    }
}

extension CrateTrack {
    /// Which recording this entry is (`SameSong.key`): entries with the same value are copies of one song.
    public var recordingKey: String { SameSong.key(id: id, cutKey: ident.cutKey) }

    /// Every place of this entry, for `SameSong.ordered`: its own place first, then its other places (D27).
    public var places: [SameSong.Place] {
        ident.allPlaces.map { SameSong.Place(id: id, disc: $0.disc, folder: $0.folder, track: $0.track) }
    }
}

extension Crate {
    /// The crate's songs: entry ids grouped by recording, in crate order.
    public var sameSongGroups: [[String]] { SameSong.groups(tracks, key: \.recordingKey).map { $0.map(\.id) } }

    /// Every place of the song the entry `id` is, in the order an app shows them (`SameSong.ordered`): the places of
    /// every copy of the recording, each copy's own and other places together. Empty for an unknown id.
    public func songPlaces(of id: String, playingDisc: String?, discOrder: [String]) -> [SameSong.Place] {
        guard let t = tracks.first(where: { $0.id == id }) else { return [] }
        let k = t.recordingKey
        return SameSong.ordered(tracks.filter { $0.recordingKey == k }.flatMap(\.places),
                                playingDisc: playingDisc, discOrder: discOrder)
    }

    /// Sets `cut_key` from prints of the entries' audio: copies of one recording get the same key (the smallest id
    /// among them) and an entry printed with no copy gets none. Entries with no print (their audio was not read) keep
    /// what they had. Returns how many entries are now in a group of copies.
    @discardableResult
    public mutating func setCutKeys(prints: [String: RecordingPrint]) -> Int {
        let keys = SameSong.copies(prints)
        for i in tracks.indices where prints[tracks[i].id] != nil {
            tracks[i].ident.cutKey = keys[tracks[i].id]
        }
        return keys.count
    }
}
