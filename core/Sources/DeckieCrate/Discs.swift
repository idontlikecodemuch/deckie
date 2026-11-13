// Sources and their folders, and the corrections a DJ may make to them. A source (D26) is the thing a DJ holds that
// the songs were read from: a burned CD, a USB stick, an SD card; in the code and the format it is still called a
// disc. Its folders are the groups inside it, in the order the DJ's player shows them; each folder's songs are
// numbered from 1. The labels are the crate's own `ident.disc`, `ident.folder` and `ident.track` (an entry's own place)
// and, since D27, `ident.other_places` (the same file found somewhere else, each with the same three parts). Every
// operation here works on every place of an entry, its own and its other places alike, so a song on two sources is in
// both sources' folders. Since D25, Desk reads a source as it is (SourcePlaces.swift) and these operations are for
// corrections (a name, an order read wrongly); building a source by hand stays possible here for later desks (D20).
// Plain Swift, shared by every desk (Mac, Windows, Linux); the booth reads the same labels.
//
// Numbers: a folder that an operation changes is numbered 1..n in order, no gaps. A folder an operation does not touch
// keeps its numbers, so a source read with a gap (a file on the stick that is not in the crate, where the player still
// counts it) keeps the player's numbers until the DJ changes that folder.

/// One disc as the crate holds it: its folders in name order.
public struct DiscPlan: Equatable, Sendable {
    public var name: String
    public var folders: [FolderPlan]
    public init(name: String, folders: [FolderPlan]) { self.name = name; self.folders = folders }
}

/// One folder of a disc: its track ids in track-number order. An entry with two places in one folder (two files
/// with the same bytes there) is listed twice.
public struct FolderPlan: Equatable, Sendable {
    public var name: String
    public var trackIds: [String]
    public init(name: String, trackIds: [String]) { self.name = name; self.trackIds = trackIds }
}

extension Crate {
    /// The discs in name order, each with its folders in the order a player walks them
    /// (`SourceReading.groupComesBefore`), each with its track ids in `track` order (the order the booth's Crate tab
    /// shows). A place with a disc and no folder is in the folder named "". Every place counts, own and other, so an
    /// entry is listed under each folder it is in.
    public var discPlan: [DiscPlan] {
        let groups = folderGroups()
        let discs = Set(groups.keys.map(\.disc)).sorted()
        return discs.map { d in
            DiscPlan(name: d, folders: groups.keys.filter { $0.disc == d }.map(\.folder)
                .sorted(by: SourceReading.groupComesBefore).map { f in
                FolderPlan(name: f, trackIds: groups[FolderKey(disc: d, folder: f)]!.map { tracks[$0.track].id })
            })
        }
    }

    /// The ids of one folder's tracks in order (empty when there is no such folder).
    public func trackIds(disc: String, folder: String) -> [String] {
        folderPlaces(disc: disc, folder: folder).map(\.id)
    }

    /// One folder's songs in order, each with its number there (the number of that place, which for an entry with
    /// several places is not its own place's).
    public func folderPlaces(disc: String, folder: String) -> [(id: String, number: Int?)] {
        (folderGroups()[FolderKey(disc: disc, folder: folder)] ?? []).map { (tracks[$0.track].id, place(at: $0).track) }
    }

    /// "Singalongs / Peak 3": where a track's own place is, or nil when it is on no disc.
    public static func discLine(_ t: CrateTrack) -> String? { placeLine(t.ident.ownPlace) }

    /// "Singalongs / Peak 3": a place on a disc, or nil for a place with no disc.
    public static func placeLine(_ p: CrateTrack.Place) -> String? {
        guard let d = p.disc else { return nil }
        var s = d
        if let f = p.folder, !f.isEmpty { s += " / " + f }
        if let n = p.track { s += " \(n)" }
        return s
    }

    /// Puts those tracks into that folder of that disc, in the order given: appended, or inserted at `index` (0 is
    /// the top; clamped). A track that already has a place in that folder is moved within it; otherwise its own
    /// place is taken out of wherever it was and put there (its other places stay), so placing a track already in
    /// another folder moves it. Unknown ids and repeats are ignored.
    public mutating func place(_ ids: [String], disc: String, folder: String, at index: Int? = nil) {
        let moving = knownUnique(ids)
        guard !moving.isEmpty else { return }
        let pos = positions()
        let target = FolderKey(disc: disc, folder: folder)
        let there = folderGroups()[target] ?? []
        let slots = moving.map { id in there.first { $0.track == pos[id]! } ?? Slot(track: pos[id]!, other: nil) }
        let movingSet = Set(slots)
        var order = there.filter { !movingSet.contains($0) }
        let at = min(max(index ?? order.count, 0), order.count)
        order.insert(contentsOf: slots, at: at)
        var left = Set<FolderKey>()
        for s in slots where !there.contains(s) {
            if let k = key(of: s) { left.insert(k) }
            setPlace(s, CrateTrack.Place(disc: disc, folder: folder, track: nil))
        }
        for (n, s) in order.enumerated() { var p = place(at: s); p.track = n + 1; setPlace(s, p) }
        left.remove(target)
        dropRepeats()
        renumber(left)
    }

    /// Takes those tracks off their discs: every place on a disc is cleared, so the track keeps at most the places it
    /// has with no disc (a folder on the Mac). Unknown ids are ignored.
    public mutating func remove(_ ids: [String]) {
        let pos = positions()
        var left = Set<FolderKey>()
        for id in ids {
            guard let i = pos[id] else { continue }
            for s in slots(of: i) { if let k = key(of: s) { left.insert(k) } }
            tracks[i].ident.otherPlaces.removeAll { $0.disc != nil }
            clearOwn(i)
        }
        renumber(left)
    }

    /// Moves a track to `index` (0 is the top; clamped) within its own place's folder. Nothing happens for a track
    /// whose own place is on no disc.
    public mutating func move(_ id: String, to index: Int) {
        guard let i = positions()[id], let d = tracks[i].ident.disc else { return }
        place([id], disc: d, folder: tracks[i].ident.folder ?? "", at: index)
    }

    /// Moves a track to `index` (0 is the top; clamped) within that folder of that disc, whichever of its places is
    /// there. Nothing happens when the track has no place there.
    public mutating func move(_ id: String, inDisc disc: String, folder: String, to index: Int) {
        guard trackIds(disc: disc, folder: folder).contains(id) else { return }
        place([id], disc: disc, folder: folder, at: index)
    }

    /// Renames a disc, in every place that names it. Renaming onto a disc that exists joins the two; a folder of the
    /// same name on both keeps the other disc's songs first and these after them, numbered again. A folder that does
    /// not join keeps its numbers.
    public mutating func renameDisc(_ name: String, to new: String) {
        guard name != new else { return }
        let groups = folderGroups()
        var joined = Set<FolderKey>()
        for key in groups.keys.sorted(by: { $0.folder < $1.folder }) where key.disc == name {
            let after = groups[FolderKey(disc: new, folder: key.folder)]?.count ?? 0
            if after > 0 { joined.insert(FolderKey(disc: new, folder: key.folder)) }
            for s in groups[key]! {
                var p = place(at: s)
                p.disc = new
                if after > 0 { p.track = after + (p.track ?? 0) }
                setPlace(s, p)
            }
        }
        dropRepeats()
        renumber(joined)
    }

    /// Renames a folder of a disc, in every place that names it; its songs keep their numbers. Renaming onto a folder
    /// that exists joins them, that folder's songs first, numbered again.
    public mutating func renameFolder(_ folder: String, inDisc disc: String, to new: String) {
        guard folder != new, let members = folderGroups()[FolderKey(disc: disc, folder: folder)] else { return }
        let after = folderGroups()[FolderKey(disc: disc, folder: new)]?.count ?? 0
        for (n, s) in members.enumerated() {
            var p = place(at: s)
            p.folder = new
            if after > 0 { p.track = after + n + 1 }
            setPlace(s, p)
        }
        dropRepeats()
        if after > 0 { renumber([FolderKey(disc: disc, folder: new)]) }
    }

    /// Deletes a disc: every place on it is cleared (the tracks stay in the crate). An entry whose own place was on
    /// it and that has other places takes one of them as its own (`promoteOtherPlace`).
    public mutating func deleteDisc(_ name: String) {
        for i in tracks.indices {
            tracks[i].ident.otherPlaces.removeAll { $0.disc == name }
            if tracks[i].ident.disc == name { clearOwn(i) }
        }
    }

    /// Deletes a folder of a disc: every place in it is cleared (the tracks stay in the crate), as `deleteDisc`.
    public mutating func deleteFolder(_ folder: String, inDisc disc: String) {
        func isIt(_ p: CrateTrack.Place) -> Bool { p.disc == disc && (p.folder ?? "") == folder }
        for i in tracks.indices {
            tracks[i].ident.otherPlaces.removeAll(where: isIt)
            if isIt(tracks[i].ident.ownPlace) { clearOwn(i) }
        }
    }

    /// Numbers each folder's tracks 1..n in their present order (track number, then crate order for ties and for
    /// tracks with no number). The operations number only the folders they change; a desk may call this on a crate
    /// made elsewhere, which also closes the gaps a source was read with.
    public mutating func renumber() { renumber(nil) }

    /// `renumber` for those folders only (every folder when nil).
    private mutating func renumber(_ only: Set<FolderKey>?) {
        if let only, only.isEmpty { return }
        for (k, members) in folderGroups() where only?.contains(k) ?? true {
            for (n, s) in members.enumerated() where place(at: s).track != n + 1 {
                var p = place(at: s); p.track = n + 1; setPlace(s, p)
            }
        }
    }

    // MARK: helpers

    private struct FolderKey: Hashable { let disc: String; let folder: String }

    /// One place of one entry: its own (`other` nil) or its other place at that index.
    private struct Slot: Hashable { let track: Int; let other: Int? }

    private func place(at s: Slot) -> CrateTrack.Place {
        s.other.map { tracks[s.track].ident.otherPlaces[$0] } ?? tracks[s.track].ident.ownPlace
    }

    private mutating func setPlace(_ s: Slot, _ p: CrateTrack.Place) {
        if let k = s.other { tracks[s.track].ident.otherPlaces[k] = p } else { tracks[s.track].ident.ownPlace = p }
    }

    private func slots(of i: Int) -> [Slot] {
        [Slot(track: i, other: nil)] + tracks[i].ident.otherPlaces.indices.map { Slot(track: i, other: $0) }
    }

    /// Places on a disc per (disc, folder), each in order: track number, then crate order, an entry's own place before
    /// its other places.
    private func folderGroups() -> [FolderKey: [Slot]] {
        var g: [FolderKey: [Slot]] = [:]
        for i in tracks.indices {
            for s in slots(of: i) {
                let p = place(at: s)
                guard let d = p.disc else { continue }
                g[FolderKey(disc: d, folder: p.folder ?? ""), default: []].append(s)
            }
        }
        for k in g.keys {
            g[k]!.sort { a, b in
                let x = place(at: a).track ?? Int.max, y = place(at: b).track ?? Int.max
                if x != y { return x < y }
                if a.track != b.track { return a.track < b.track }
                return (a.other ?? -1) < (b.other ?? -1)
            }
        }
        return g
    }

    private func key(of s: Slot) -> FolderKey? {
        let p = place(at: s)
        return p.disc.map { FolderKey(disc: $0, folder: p.folder ?? "") }
    }

    private func positions() -> [String: Int] {
        Dictionary(tracks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func knownUnique(_ ids: [String]) -> [String] {
        let known = Set(tracks.map(\.id)); var seen = Set<String>()
        return ids.filter { known.contains($0) && seen.insert($0).inserted }
    }

    /// Clears an entry's own place. When it has other places on a disc, the one that leads by the booth's rule
    /// (sources in name order; `SameSong.ordered`) becomes its own (`promoteOtherPlace`); places with no disc stay
    /// other places.
    private mutating func clearOwn(_ i: Int) {
        tracks[i].ident.disc = nil; tracks[i].ident.folder = nil; tracks[i].ident.track = nil
        if tracks[i].ident.otherPlaces.contains(where: { $0.disc != nil }) { tracks[i].promoteOtherPlace() }
    }

    /// After a rename joins two places of one entry into the same place, keeps it once.
    private mutating func dropRepeats() {
        for i in tracks.indices where !tracks[i].ident.otherPlaces.isEmpty {
            var seen: Set<CrateTrack.Place> = [tracks[i].ident.ownPlace]
            tracks[i].ident.otherPlaces = tracks[i].ident.otherPlaces.filter { seen.insert($0).inserted }
        }
    }
}

extension CrateTrack {
    /// Makes the other place that leads by the rule (`SameSong.ordered` with no playing source and sources in name
    /// order: the first source by name, a place with no source last) the entry's own place, and takes it out of the
    /// other places. The entry's `file.rel` named the file at the own place it had, so it is set to null: the crate
    /// file does not hold the path at an other place, and the next read of that source writes it again. Nothing
    /// happens when there is no other place.
    public mutating func promoteOtherPlace() {
        guard let lead = CrateTrack.leadingPlace(ident.otherPlaces),
              let k = ident.otherPlaces.firstIndex(of: lead) else { return }
        ident.otherPlaces.remove(at: k)
        ident.ownPlace = lead
        file.rel = nil
    }

    /// The place that leads among `places` by `SameSong.ordered`, with no playing source and sources in name order.
    public static func leadingPlace(_ places: [Place]) -> Place? {
        let items = places.enumerated().map { SameSong.Place(id: String($0.offset), disc: $0.element.disc,
                                                             folder: $0.element.folder, track: $0.element.track) }
        return SameSong.ordered(items, playingDisc: nil, discOrder: []).first.map { places[Int($0.id)!] }
    }
}
