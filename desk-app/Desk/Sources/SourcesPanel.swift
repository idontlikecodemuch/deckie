import SwiftUI
import DeckieCrate

/// One row of the Discs panel: a disc, a folder of a disc, or a track in its folder.
enum DiscItem: Hashable {
    case disc(String)
    case folder(disc: String, folder: String)
    case track(String)
}

/// A disc (folder nil) or a folder made in the panel that holds no song yet. The crate itself has no place for an
/// empty disc or folder, so these live in the window until a song goes in, and are not saved.
struct DraftFolder: Hashable { var disc: String; var folder: String? }

// MARK: - the operations, through the shared core

extension DeskModel {
    /// The discs as the crate holds them (DeckieCrate's `discPlan`), plus the empty ones made here, in name order.
    var discOutline: [DiscPlan] {
        var plan = crate?.discPlan ?? []
        for d in draftFolders {
            if let i = plan.firstIndex(where: { $0.name == d.disc }) {
                if let f = d.folder, !plan[i].folders.contains(where: { $0.name == f }) {
                    plan[i].folders.append(FolderPlan(name: f, trackIds: []))
                }
            } else {
                plan.append(DiscPlan(name: d.disc, folders: d.folder.map { [FolderPlan(name: $0, trackIds: [])] } ?? []))
            }
        }
        for i in plan.indices { plan[i].folders.sort { $0.name < $1.name } }
        return plan.sorted { $0.name < $1.name }
    }

    /// The disc of what is selected in the panel.
    var selectedDisc: String? {
        switch discSelection {
        case let .disc(d)?: return d
        case let .folder(d, _)?: return d
        case let .track(id)?: return binding(for: id)?.ident.disc
        case nil: return nil
        }
    }

    /// The folder of what is selected in the panel (a folder, or a track's folder).
    var selectedFolder: (disc: String, folder: String)? {
        switch discSelection {
        case let .folder(d, f)?: return (d, f)
        case let .track(id)?:
            guard let t = binding(for: id), let d = t.ident.disc else { return nil }
            return (d, t.ident.folder ?? "")
        default: return nil
        }
    }

    /// The table's selected tracks, in crate order.
    var selectedTrackIds: [String] { (crate?.tracks ?? []).map(\.id).filter { selection.contains($0) } }

    func newDisc(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        if !discOutline.contains(where: { $0.name == n }) { draftFolders.append(DraftFolder(disc: n, folder: nil)) }
        discSelection = .disc(n)
    }

    func newFolder(_ name: String, inDisc disc: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        let exists = discOutline.first { $0.name == disc }?.folders.contains { $0.name == n } ?? false
        if !exists { draftFolders.append(DraftFolder(disc: disc, folder: n)) }
        discSelection = .folder(disc: disc, folder: n)
    }

    /// Puts tracks into a folder (appending, or at `index`), out of wherever they were.
    func place(_ ids: [String], disc: String, folder: String, at index: Int? = nil) {
        updateCrate { $0.place(ids, disc: disc, folder: folder, at: index) }
        dropFilledDrafts()
    }

    func removeFromDiscs(_ ids: [String]) {
        if case let .track(id)? = discSelection, ids.contains(id) { discSelection = nil }
        updateCrate { $0.remove(ids) }
    }

    /// Moves a track up (-1) or down (+1) within its folder.
    func nudge(_ id: String, by step: Int) {
        guard let sf = selectedFolder, let i = crate?.trackIds(disc: sf.disc, folder: sf.folder).firstIndex(of: id) else { return }
        updateCrate { $0.move(id, to: i + step) }
    }

    /// The panel's drag within a folder: SwiftUI's `onMove` offsets turned into the core's `move`.
    func moveInFolder(disc: String, folder: String, from: IndexSet, to: Int) {
        guard let c = crate else { return }
        let ids = c.trackIds(disc: disc, folder: folder)
        let moving = from.map { ids[$0] }
        let target = to - from.filter { $0 < to }.count
        updateCrate { $0.place(moving, disc: disc, folder: folder, at: target) }
    }

    func renameDisc(_ name: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != name else { return }
        updateCrate { $0.renameDisc(name, to: n) }
        for i in draftFolders.indices where draftFolders[i].disc == name { draftFolders[i].disc = n }
        discSelection = .disc(n)
    }

    func renameFolder(_ folder: String, inDisc disc: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != folder else { return }
        updateCrate { $0.renameFolder(folder, inDisc: disc, to: n) }
        for i in draftFolders.indices where draftFolders[i] == DraftFolder(disc: disc, folder: folder) { draftFolders[i].folder = n }
        discSelection = .folder(disc: disc, folder: n)
    }

    /// Deletes a disc; its songs lose their disc and folder labels and stay in the crate.
    func deleteDisc(_ name: String) {
        updateCrate { $0.deleteDisc(name) }
        draftFolders.removeAll { $0.disc == name }
        discSelection = nil
    }

    func deleteFolder(_ folder: String, inDisc disc: String) {
        updateCrate { $0.deleteFolder(folder, inDisc: disc) }
        draftFolders.removeAll { $0 == DraftFolder(disc: disc, folder: folder) }
        discSelection = .disc(disc)
    }

    private func dropFilledDrafts() {
        let plan = crate?.discPlan ?? []
        draftFolders.removeAll { d in
            guard let disc = plan.first(where: { $0.name == d.disc }) else { return false }
            return d.folder.map { f in disc.folders.contains { $0.name == f } } ?? true
        }
    }
}

// MARK: - the panel

/// The Discs panel: the crate's discs, their folders in the order the DJ's player shows them, and each folder's songs
/// numbered in order. Songs come in from the table (the button below, or the table's context menu).
struct DiscsPanel: View {
    @EnvironmentObject var model: DeskModel
    @State private var prompt: NamePrompt?
    @State private var promptText = ""

    enum NamePrompt: Identifiable {
        case newDisc, newFolder(String), renameDisc(String), renameFolder(String, String)
        var id: String {
            switch self {
            case .newDisc: return "nd"
            case let .newFolder(d): return "nf" + d
            case let .renameDisc(d): return "rd" + d
            case let .renameFolder(d, f): return "rf" + d + "/" + f
            }
        }
        var title: String {
            switch self {
            case .newDisc: return "New disc"
            case let .newFolder(d): return "New folder in \(d)"
            case let .renameDisc(d): return "Rename the disc \(d)"
            case let .renameFolder(_, f): return "Rename the folder \(f)"
            }
        }
    }

    var body: some View {
        let outline = model.discOutline
        VStack(spacing: 0) {
            HStack {
                Text("Discs").font(.headline)
                Spacer()
                Button { ask(.newDisc, "") } label: { Label("New disc", systemImage: "opticaldisc") }
                Button { if let d = model.selectedDisc { ask(.newFolder(d), "") } } label: { Label("New folder", systemImage: "folder.badge.plus") }
                    .disabled(model.selectedDisc == nil)
            }
            .labelStyle(.iconOnly).padding(.horizontal, 12).padding(.vertical, 8)
            Divider()
            if outline.isEmpty {
                VStack(spacing: 8) {
                    Text("No discs yet.").foregroundStyle(.secondary)
                    Text("A disc is the set of songs you take to a night; its folders are the groups inside it, in the order your player shows them. Make a disc, a folder in it, then add songs from the table.")
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("New disc…") { ask(.newDisc, "") }
                }
                .padding(16).frame(maxHeight: .infinity)
            } else {
                List(selection: $model.discSelection) {
                    ForEach(outline, id: \.name) { d in
                        let count = d.folders.reduce(0) { $0 + $1.trackIds.count }
                        Label("\(d.name)  ·  \(count) song\(count == 1 ? "" : "s")", systemImage: "opticaldisc")
                            .font(.body.bold()).tag(DiscItem.disc(d.name))
                        ForEach(d.folders, id: \.name) { f in
                            Label(f.name.isEmpty ? "(no folder)" : f.name, systemImage: "folder")
                                .padding(.leading, 14).tag(DiscItem.folder(disc: d.name, folder: f.name))
                            ForEach(Array(f.trackIds.enumerated()), id: \.element) { n, id in
                                trackRow(n + 1, id).tag(DiscItem.track(id))
                            }
                            .onMove { from, to in model.moveInFolder(disc: d.name, folder: f.name, from: from, to: to) }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            Divider()
            actions.padding(10)
        }
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } })) {
            TextField("Name", text: $promptText)
            Button("OK") { commit() }
            Button("Cancel", role: .cancel) { prompt = nil }
        }
    }

    private func trackRow(_ n: Int, _ id: String) -> some View {
        let t = model.binding(for: id)
        return HStack(spacing: 6) {
            Text(String(format: "%02d", n)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            Text(t?.ident.title ?? id).foregroundStyle(.primary).lineLimit(1)
            if let a = t?.ident.artist { Text(a).foregroundStyle(.secondary).lineLimit(1) }
        }
        .padding(.leading, 30)
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            let picked = model.selectedTrackIds
            if let sf = model.selectedFolder {
                Button("Add \(picked.count) selected to \(sf.folder.isEmpty ? sf.disc : sf.folder)") { model.place(picked, disc: sf.disc, folder: sf.folder) }
                    .buttonStyle(.borderedProminent).disabled(picked.isEmpty)
            } else {
                Text("Select a folder to add the table's selected songs to it.").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                switch model.discSelection {
                case let .track(id)?:
                    Button("Move up") { model.nudge(id, by: -1) }
                    Button("Move down") { model.nudge(id, by: 1) }
                    Button("Remove from folder") { model.removeFromDiscs([id]) }
                case let .folder(d, f)?:
                    Button("Rename…") { ask(.renameFolder(d, f), f) }
                    Button("Delete folder") { model.deleteFolder(f, inDisc: d) }
                        .help("The folder's songs lose their disc and folder; they stay in the crate.")
                case let .disc(d)?:
                    Button("Rename…") { ask(.renameDisc(d), d) }
                    Button("Delete disc") { model.deleteDisc(d) }
                        .help("The disc's songs lose their disc and folder; they stay in the crate.")
                case nil:
                    EmptyView()
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
        case .newDisc: model.newDisc(promptText)
        case let .newFolder(d): model.newFolder(promptText, inDisc: d)
        case let .renameDisc(d): model.renameDisc(d, to: promptText)
        case let .renameFolder(d, f): model.renameFolder(f, inDisc: d, to: promptText)
        }
    }
}

/// The table's context menu: Add to disc ▸ folder, and off the discs.
struct DiscsMenu: View {
    @EnvironmentObject var model: DeskModel
    let ids: Set<String>
    var body: some View {
        let ordered = (model.crate?.tracks ?? []).map(\.id).filter { ids.contains($0) }
        let outline = model.discOutline
        Menu("Add to disc") {
            if outline.isEmpty { Text("No discs yet: make one in the Discs panel") }
            ForEach(outline, id: \.name) { d in
                Menu(d.name) {
                    if d.folders.isEmpty { Text("No folders yet") }
                    ForEach(d.folders, id: \.name) { f in
                        Button(f.name.isEmpty ? "(no folder)" : f.name) { model.place(ordered, disc: d.name, folder: f.name) }
                    }
                }
            }
        }
        .disabled(ordered.isEmpty)
        if ordered.contains(where: { model.binding(for: $0)?.ident.disc != nil }) {
            Button("Remove from disc") { model.removeFromDiscs(ordered) }
        }
        Divider()
        Button(model.showDiscs ? "Hide Discs" : "Show Discs") { model.showDiscs.toggle() }
    }
}
