// Discs and folders: how a DJ organises the crate for a night. A disc is the set of songs taken to a night; its
// folders are the groups inside it, in the order the DJ's player shows them; each folder's songs are numbered 1..n.
// The labels are the crate's own `ident.disc`, `ident.folder` and `ident.track` (crate v1, no new field), so a track
// sits in at most one folder of one disc. These operations are plain Swift, shared by every desk (Mac, Windows,
// Linux); the booth reads the same labels. Every operation leaves each folder numbered 1..n in order, no gaps.

/// One disc as the crate holds it: its folders in name order.
public struct DiscPlan: Equatable, Sendable {
    public var name: String
    public var folders: [FolderPlan]
    public init(name: String, folders: [FolderPlan]) { self.name = name; self.folders = folders }
}

/// One folder of a disc: its track ids in track-number order.
public struct FolderPlan: Equatable, Sendable {
    public var name: String
    public var trackIds: [String]
    public init(name: String, trackIds: [String]) { self.name = name; self.trackIds = trackIds }
}

extension Crate {
    /// The discs in name order, each with its folders in name order, each with its track ids in `track` order (the
    /// order the booth's CDs tab shows). A track with a disc and no folder is in the folder named "".
    public var discPlan: [DiscPlan] {
        let groups = folderGroups()
        let discs = Set(groups.keys.map(\.disc)).sorted()
        return discs.map { d in
            DiscPlan(name: d, folders: groups.keys.filter { $0.disc == d }.map(\.folder).sorted().map { f in
                FolderPlan(name: f, trackIds: groups[FolderKey(disc: d, folder: f)]!.map { tracks[$0].id })
            })
        }
    }

    /// The ids of one folder's tracks in order (empty when there is no such folder).
    public func trackIds(disc: String, folder: String) -> [String] {
        (folderGroups()[FolderKey(disc: disc, folder: folder)] ?? []).map { tracks[$0].id }
    }

    /// "Singalongs / Peak 3": where a track sits, or nil when it is on no disc.
    public static func discLine(_ t: CrateTrack) -> String? {
        guard let d = t.ident.disc else { return nil }
        var s = d
        if let f = t.ident.folder, !f.isEmpty { s += " / " + f }
        if let n = t.ident.track { s += " \(n)" }
        return s
    }

    /// Puts those tracks into that folder of that disc, in the order given: appended, or inserted at `index` (0 is
    /// the top; clamped). Each is taken out of wherever it was first, so placing a track already in a folder moves
    /// it. Unknown ids and repeats are ignored.
    public mutating func place(_ ids: [String], disc: String, folder: String, at index: Int? = nil) {
        let moving = knownUnique(ids)
        guard !moving.isEmpty else { return }
        let movingSet = Set(moving)
        var order = trackIds(disc: disc, folder: folder).filter { !movingSet.contains($0) }
        let at = min(max(index ?? order.count, 0), order.count)
        order.insert(contentsOf: moving, at: at)
        let pos = positions()
        for id in moving {
            tracks[pos[id]!].ident.disc = disc; tracks[pos[id]!].ident.folder = folder
        }
        for (n, id) in order.enumerated() { tracks[pos[id]!].ident.track = n + 1 }
        renumber()
    }

    /// Takes those tracks off their discs: clears disc, folder and track. Unknown ids are ignored.
    public mutating func remove(_ ids: [String]) {
        let pos = positions()
        for id in ids { if let i = pos[id] { clearLabels(i) } }
        renumber()
    }

    /// Moves a track to `index` (0 is the top; clamped) within its own folder. Nothing happens for a track on no disc.
    public mutating func move(_ id: String, to index: Int) {
        guard let i = positions()[id], let d = tracks[i].ident.disc else { return }
        place([id], disc: d, folder: tracks[i].ident.folder ?? "", at: index)
    }

    /// Renames a disc. Renaming onto a disc that exists joins the two; a folder of the same name on both keeps the
    /// other disc's songs first and these after them.
    public mutating func renameDisc(_ name: String, to new: String) {
        guard name != new else { return }
        let groups = folderGroups()
        for key in groups.keys.sorted(by: { $0.folder < $1.folder }) where key.disc == name {
            let after = trackIds(disc: new, folder: key.folder).count
            for i in groups[key]! {
                tracks[i].ident.disc = new
                tracks[i].ident.track = after + (tracks[i].ident.track ?? 0)
            }
        }
        renumber()
    }

    /// Renames a folder of a disc. Renaming onto a folder that exists joins them, that folder's songs first.
    public mutating func renameFolder(_ folder: String, inDisc disc: String, to new: String) {
        guard folder != new, let members = folderGroups()[FolderKey(disc: disc, folder: folder)] else { return }
        let after = trackIds(disc: disc, folder: new).count
        for (n, i) in members.enumerated() { tracks[i].ident.folder = new; tracks[i].ident.track = after + n + 1 }
        renumber()
    }

    /// Deletes a disc: its tracks lose their disc, folder and track labels (the tracks stay in the crate).
    public mutating func deleteDisc(_ name: String) {
        for i in tracks.indices where tracks[i].ident.disc == name { clearLabels(i) }
        renumber()
    }

    /// Deletes a folder of a disc: its tracks lose their labels (the tracks stay in the crate).
    public mutating func deleteFolder(_ folder: String, inDisc disc: String) {
        for i in folderGroups()[FolderKey(disc: disc, folder: folder)] ?? [] { clearLabels(i) }
        renumber()
    }

    /// Numbers each folder's tracks 1..n in their present order (track number, then crate order for ties and for
    /// tracks with no number). Every operation ends with it; a desk may also call it on a crate made elsewhere.
    public mutating func renumber() {
        for (_, members) in folderGroups() {
            for (n, i) in members.enumerated() where tracks[i].ident.track != n + 1 { tracks[i].ident.track = n + 1 }
        }
    }

    // MARK: helpers

    private struct FolderKey: Hashable { let disc: String; let folder: String }

    /// Track indices per (disc, folder), each in order: track number, then crate order.
    private func folderGroups() -> [FolderKey: [Int]] {
        var g: [FolderKey: [Int]] = [:]
        for (i, t) in tracks.enumerated() {
            guard let d = t.ident.disc else { continue }
            g[FolderKey(disc: d, folder: t.ident.folder ?? ""), default: []].append(i)
        }
        for k in g.keys {
            g[k]!.sort { a, b in
                let x = tracks[a].ident.track ?? Int.max, y = tracks[b].ident.track ?? Int.max
                return x != y ? x < y : a < b
            }
        }
        return g
    }

    private func positions() -> [String: Int] {
        Dictionary(tracks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func knownUnique(_ ids: [String]) -> [String] {
        let known = Set(tracks.map(\.id)); var seen = Set<String>()
        return ids.filter { known.contains($0) && seen.insert($0).inserted }
    }

    private mutating func clearLabels(_ i: Int) {
        tracks[i].ident.disc = nil; tracks[i].ident.folder = nil; tracks[i].ident.track = nil
    }
}
