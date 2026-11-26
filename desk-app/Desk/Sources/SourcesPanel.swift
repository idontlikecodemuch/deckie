import SwiftUI
import DeckieDisc
import DeckieCrate
import DeckieDesk

// The Sources panel (D25, D26, D31). A source is the thing a DJ holds that the songs were read from: a burned CD, a USB
// stick, an SD card, or a folder the DJ added (named after that top folder, its folders inside as groups). Desk reads one as it is (Add music, DeskModel.addSource), so the panel shows what was read and is
// for corrections: a name, or an order Desk read wrongly; and for taking a source back out of the crate. On screen a
// source is shown by its own name; the word "source" is ours, in documents and code. The operations are the shared
// core's (DeckieCrate's Discs.swift, where the field is still called disc; DeckieDesk's removeSource).

/// One row of the Sources panel: a source, a folder of a source, or a song in its folder. A song with more than one
/// place (D27) has a row in each folder it is in, so a song row says which folder it is.
enum SourceItem: Hashable {
    case source(String)
    case folder(source: String, folder: String)
    case track(String, source: String, folder: String)
}

/// A folder's or a song's identity in the Sources panel's one list: which source and folder it is in, and for a song
/// which song, so it is unique across the whole list (a song is in a folder once; `nth` keeps the id unique even if
/// one were there twice). The list reuses a row by its id, so an id that repeated in another folder showed that
/// folder's row in its place.
struct SourceRowID: Hashable {
    var item: SourceItem
    var nth = 0

    var folder: String {
        switch item {
        case let .folder(_, f), let .track(_, _, f): return f
        case .source: return ""
        }
    }

    /// One song's row in a folder: its id in the list, the song, and its number there.
    struct Song { var id: SourceRowID; var song: String; var number: Int? }

    /// A folder's songs in their order, each with its own id.
    static func songs(_ places: [(id: String, number: Int?)], source: String, folder: String) -> [Song] {
        var seen: [String: Int] = [:]
        return places.map { p in
            let n = seen[p.id, default: 0]
            seen[p.id] = n + 1
            return Song(id: SourceRowID(item: .track(p.id, source: source, folder: folder), nth: n), song: p.id, number: p.number)
        }
    }
}

// MARK: - the corrections, through the shared core

extension DeskModel {
    /// The sources as the crate holds them (DeckieCrate's `discPlan`): sources by name, folders in the order a player
    /// walks them, songs by their number.
    var sourceOutline: [DiscPlan] { crate?.discPlan ?? [] }

    /// Whether some songs are in the music folder (no source): only in a crate made before D31, when the rekordbox
    /// route read the music folder with no source. Every way of adding music now reads a source, so the panel's
    /// "Remove the music folder…" shows only for such a crate.
    var hasMusicFolderSongs: Bool { crate?.tracks.contains { $0.ident.allPlaces.contains { $0.disc == nil } } ?? false }

    /// The folder of what is selected in the panel (a folder, or a song's folder).
    var selectedSourceFolder: (source: String, folder: String)? {
        switch sourceSelection {
        case let .folder(s, f)?: return (s, f)
        case let .track(_, s, f)?: return (s, f)
        default: return nil
        }
    }

    /// Moves a song up (-1) or down (+1) within the folder its selected row is in (any of its places); the folder is
    /// numbered again from 1.
    func nudge(_ id: String, by step: Int) {
        guard let sf = selectedSourceFolder, let i = crate?.trackIds(disc: sf.source, folder: sf.folder).firstIndex(of: id) else { return }
        updateCrate(Words.undoMove) { $0.move(id, inDisc: sf.source, folder: sf.folder, to: i + step) }
    }

    /// The panel's drag within a folder: SwiftUI's `onMove` offsets turned into the core's `place`.
    func moveInFolder(source: String, folder: String, from: IndexSet, to: Int) {
        guard let c = crate else { return }
        let ids = c.trackIds(disc: source, folder: folder)
        let moving = from.map { ids[$0] }
        let target = to - from.filter { $0 < to }.count
        updateCrate(Words.undoMove) { $0.place(moving, disc: source, folder: folder, at: target) }
    }

    func renameFolder(_ folder: String, inSource source: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != folder else { return }
        updateCrate(Words.undoRename) { $0.renameFolder(folder, inDisc: source, to: n) }
        sourceSelection = .folder(source: source, folder: n)
    }
}

// MARK: - the panel

/// The Sources panel: each source read, by its own name, its folders in the order the player shows them, and each
/// folder's songs by their number there. Rename and reorder correct what was read; Remove takes a source back out.
struct SourcesPanel: View {
    @EnvironmentObject var model: DeskModel
    @State private var prompt: NamePrompt?
    @State private var promptText = ""

    enum NamePrompt: Identifiable {
        case renameSource(String), renameFolder(String, String)
        var id: String {
            switch self {
            case let .renameSource(s): return "rs" + s
            case let .renameFolder(s, f): return "rf" + s + "/" + f
            }
        }
        var title: String {
            switch self {
            case let .renameSource(s): return Words.renameTitle(s)
            case let .renameFolder(_, f): return Words.renameFolderTitle(f)
            }
        }
    }

    var body: some View {
        let outline = model.sourceOutline
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Look.Space.sourcesHead) {
                Text(Words.sourcesTitle).font(Look.Fonts.panelTitle)
                Text(Words.sourcesCaption).font(Look.Fonts.sourcesCaption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Look.Space.sourcesHeadH).padding(.vertical, Look.Space.sourcesHeadV)
            Divider()
            if outline.isEmpty {
                VStack(spacing: Look.Space.sourcesEmpty) {
                    Text(Words.nothingReadYet).foregroundStyle(.secondary)
                    Text(Words.sourcesEmptyBody)
                        .font(Look.Fonts.sourcesEmptyBody).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    AddMusicMenu(label: Words.addMusicMore)
                }
                .padding(Look.Space.sourcesEmptyPadding).frame(maxHeight: .infinity)
            } else {
                // One list holds every source, folder and song, and the list tells its rows apart by their ids alone:
                // each id says which source, folder and song it is (`SourceRowID`), so no two rows anywhere share one.
                // (Ids that were only a song's index in its folder repeated in every folder, and the list showed one
                // folder's songs under the others; Nov 25, 2026.)
                List(selection: $model.sourceSelection) {
                    ForEach(outline, id: \.name) { s in
                        let count = DeskSourceRow.songs(in: s)
                        Label(Words.sourceLine(s.name, songs: count), systemImage: "externaldrive")
                            .font(Look.Fonts.sourceName).tag(SourceItem.source(s.name))
                        ForEach(s.folders.map { SourceRowID(item: .folder(source: s.name, folder: $0.name)) }, id: \.self) { fid in
                            let f = fid.folder
                            Label(f.isEmpty ? Words.topFolder : f, systemImage: "folder")
                                .padding(.leading, Look.Space.sourcesFolderIndent).tag(fid.item)
                            let rows = SourceRowID.songs(model.crate?.folderPlaces(disc: s.name, folder: f) ?? [], source: s.name, folder: f)
                            ForEach(rows, id: \.id) { row in
                                trackRow(row.song, number: row.number, source: s.name).tag(row.id.item)
                            }
                            .onMove { from, to in model.moveInFolder(source: s.name, folder: f, from: from, to: to) }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            Divider()
            actions.padding(Look.Space.sourcesActions)
        }
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            TextField(Words.nameField, text: $promptText)
            Button(Words.renameButton) { commit() }
            Button(Words.cancel, role: .cancel) { prompt = nil }
        } message: { Text(Words.t("renameNote")) }
    }

    /// A song by the number it has in this folder (the player's, as read; numbered again after a move). A song that
    /// is in other places too says how many, and where on hover.
    private func trackRow(_ id: String, number: Int?, source: String) -> some View {
        let t = model.binding(for: id)
        let elsewhere = t.map { TrackTable.places($0).count - 1 } ?? 0
        return HStack(spacing: Look.Space.sourcesSong) {
            Text(number.map(Words.twoDigits) ?? Words.none).font(Look.Fonts.sourcesSongNumber).foregroundStyle(.secondary)
            Text(t?.ident.title ?? id).foregroundStyle(.primary).lineLimit(1)
            if let a = t?.ident.artist { Text(a).foregroundStyle(.secondary).lineLimit(1) }
            if elsewhere > 0 {
                Text(Words.plusMore(elsewhere)).font(Look.Fonts.sourcesSongMore).foregroundStyle(.secondary)
                    .help(Words.alsoIn(t.map { Words.alsoInPlaces(TrackTable.places($0)) } ?? ""))
            }
        }
        .padding(.leading, Look.Space.sourcesSongIndent)
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: Look.Space.sourcesActionsStack) {
            Text(Words.fixHint).font(Look.Fonts.sourcesHint).foregroundStyle(.secondary)
            HStack {
                switch model.sourceSelection {
                case let .track(id, _, _)?:
                    Button(Words.moveUp) { model.nudge(id, by: -1) }
                    Button(Words.moveDown) { model.nudge(id, by: 1) }
                case let .folder(s, f)?:
                    Button(Words.rename) { ask(.renameFolder(s, f), f) }.disabled(f.isEmpty)
                case let .source(s)?:
                    Button(Words.rename) { ask(.renameSource(s), s) }
                    Button(Words.removeFromCrate) { model.removing = .some(s) }
                case nil:
                    if model.hasMusicFolderSongs {
                        Button(Words.removeMusicFolder) { model.removing = .some(nil) }
                    }
                }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ask(_ p: NamePrompt, _ text: String) { promptText = text; prompt = p }

    private func commit() {
        guard let p = prompt else { return }
        prompt = nil
        switch p {
        case let .renameSource(s): model.renameSource(s, to: promptText)
        case let .renameFolder(s, f): model.renameFolder(f, inSource: s, to: promptText)
        }
    }
}
