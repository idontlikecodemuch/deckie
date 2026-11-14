import SwiftUI
import DeckieCrate
import DeckieDesk
import DeckieBuild
import DeckieDisc

struct ContentView: View {
    @EnvironmentObject var model: DeskModel
    @Environment(\.undoManager) private var undoManager
    @State private var renameText = ""

    var body: some View {
        Group {
            if model.running { RunView() }
            else if let r = model.finished { FinishedView(report: r) }
            else if model.crate != nil { CrateView() }
            else { EmptyCrateView() }
        }
        .navigationTitle(model.current?.name ?? Words.appName)
        .toolbar {
            ToolbarItem(placement: .navigation) { CrateMenu() }
            ToolbarItemGroup(placement: .primaryAction) {
                AddMusicMenu()
                if model.crate != nil {
                    Menu {
                        Button(Words.t("pasteList")) { model.tool = "paste" }
                        Button(Words.t("namesFromFileNames")) { model.tool = "pattern" }
                        Button(Words.t("namesFromPlaylist")) { model.tool = "playlist" }
                        Divider()
                        Button(Words.t("looksRight")) { model.check(Array(model.selection)) }
                            .disabled(!model.selection.contains { id in model.crate?.tracks.first { $0.id == id }.map { model.reason($0) == "guess" } == true })
                    } label: { Label(Words.t("nameTools"), systemImage: "character.cursor.ibeam") }
                    .disabled(model.running)
                    Button { model.showSources.toggle() } label: {
                        Label(model.showSources ? Words.hideSources : Words.sources, systemImage: "externaldrive")
                    }
                    .help(Words.sourcesHelp).disabled(model.running)
                    Button { model.showImportLog = true } label: { Label(Words.whatDidntGoIn, systemImage: "list.bullet.rectangle") }
                        .disabled(model.running)
                    Button { model.sendToIPad() } label: { Label(Words.sendToIPad, systemImage: "square.and.arrow.up") }
                        .help(Words.sendHelp).disabled(model.running)
                }
            }
        }
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { _, u in model.undoManager = u }
        .sheet(isPresented: $model.showImportLog) { ImportLogView() }
        .alert(Words.appName, isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) {
            Button(Words.ok) { model.errorText = nil }
        } message: { Text(model.errorText ?? "") }
        .alert(model.renaming.map { Words.renameTitle($0.name) } ?? "",
               isPresented: Binding(get: { model.renaming != nil }, set: { if !$0 { model.renaming = nil } })) {
            TextField(Words.nameField, text: $renameText)
            Button(Words.ok) { if let c = model.renaming { model.rename(c, to: renameText) }; model.renaming = nil }
            Button(Words.cancel, role: .cancel) { model.renaming = nil }
        }
        .onChange(of: model.renaming) { _, c in if let c { renameText = c.name } }
        .confirmationDialog(model.deleting.map { Words.deleteCrateTitle($0.name) } ?? "",
                            isPresented: Binding(get: { model.deleting != nil }, set: { if !$0 { model.deleting = nil } })) {
            Button(Words.delete, role: .destructive) { if let c = model.deleting { model.delete(c) }; model.deleting = nil }
            Button(Words.cancel, role: .cancel) { model.deleting = nil }
        } message: { Text(Words.deleteCrateBody) }
        .confirmationDialog(removeTitle, isPresented: Binding(get: { model.removing != nil }, set: { if !$0 { model.removing = nil } })) {
            Button(Words.remove, role: .destructive) { if let s = model.removing { model.removeSource(s) }; model.removing = nil }
            Button(Words.cancel, role: .cancel) { model.removing = nil }
        } message: { Text(Words.removeBody(model.crate?.entriesOnlyOn(source: model.removing ?? nil).count ?? 0)) }
    }

    private var removeTitle: String {
        guard let s = model.removing else { return "" }
        return Words.removeTitle(s ?? Words.musicFolderName, model.current?.name ?? "")
    }
}

/// Which crate is showing, and the way to the others: each crate, then New crate, rename and delete.
struct CrateMenu: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        Menu {
            ForEach(model.crates, id: \.id) { c in
                Button { model.show(c) } label: {
                    if c.id == model.current?.id { Label(c.name, systemImage: "checkmark") } else { Text(c.name) }
                }
            }
            if !model.crates.isEmpty { Divider() }
            Button(Words.newCrate) { model.newCrate() }
            if let c = model.current {
                Divider()
                Button(Words.renameCrate) { model.renaming = c }
                Button(Words.deleteCrate) { model.deleting = c }
            }
        } label: {
            Label(model.current?.name ?? Words.newCrate, systemImage: "shippingbox")
                .labelStyle(.titleAndIcon)
        }
        .help(Words.crateMenuHelp)
        .disabled(model.running)
    }
}

struct EmptyCrateView: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox").font(.system(size: 56)).foregroundStyle(.secondary)
            Text(Words.firstTitle).font(.title2)
            Text(Words.firstBody)
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 520)
            PendingBanner()
            HStack {
                AddMusicMenu().fixedSize().buttonStyle(.borderedProminent)
                Button(Words.withRekordbox) { model.askRekordbox() }
                Button(Words.importCrateFile) { model.askImport() }
            }
        }.padding(40)
    }
}

/// A run of this crate that stopped before it finished, and the way to carry it on.
struct PendingBanner: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        if let p = model.pending {
            let here = DeskRun.canCarryOn(p, home: model.home)
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                Text(Words.stoppedReading(p.name))
                if here { Button(Words.carryOn) { model.carryOn() } }
                else { Text(p.musicCD != nil ? Words.t("putDiscBack", ["read": p.name]) : Words.putBack(p.name)).foregroundStyle(.secondary) }
            }
            .font(.callout).padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// The run (D37): the plain facts first (songs done, time left, what didn't go in, that it can be left), a quiet line
/// that changes, the song Desk just read with what it found, the figures so far, and the crate as a wall of waves
/// (RunScreen.swift). The run's list of files is kept, folded away.
struct RunView: View {
    @EnvironmentObject var model: DeskModel
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var showList = false
    var body: some View {
        ScrollView {
            content.padding(20).frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
        }
        .onAppear { model.watch.reduceMotion = reduce }
        .onChange(of: reduce) { _, r in model.watch.reduceMotion = r }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didChangeOcclusionStateNotification)) { n in
            // Drawing stops while the window is hidden; the songs keep arriving and show when it is back.
            if let w = n.object as? NSWindow, !w.isSheet { model.watch.visible = w.occlusionState.contains(.visible) }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: RunLook.gap) {
            Text(Words.runTitle).font(.title2)
            Text(Words.runReading(model.runRead, into: model.current?.name ?? "")).foregroundStyle(.secondary)
            if model.discAsk != nil {
                // A music CD with no name of its own: asked once, in passing; the run never waits (letter AA, 2.5).
                VStack(alignment: .leading, spacing: 6) {
                    (Text(Words.t("askDiscNameTitle")).bold() + Text(" " + Words.t("askDiscNameBody")).foregroundColor(.secondary))
                    HStack {
                        TextField(Words.nameField, text: $model.discAnswer).textFieldStyle(.roundedBorder).onSubmit { model.nameDisc() }
                        Button(Words.ok) { model.nameDisc() }.buttonStyle(.borderedProminent)
                    }
                }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
            RunProgressLine(watch: model.watch)
            SayingLine(watch: model.watch)
            Text(DeskWords.text("leaveRunning")).font(.caption).foregroundStyle(.tertiary)
            StageView(watch: model.watch)
            FiguresView(watch: model.watch)
            WallView(watch: model.watch, title: DeskWords.text("wallTitle"))
            DisclosureGroup(DeskWords.text("runListTitle"), isExpanded: $showList) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(model.runLines.suffix(200).indices, id: \.self) { i in
                        Text(model.runLines.suffix(200)[i]).font(.system(.caption, design: .monospaced)).lineLimit(1)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.callout).foregroundStyle(.secondary)
        }
    }
}

/// The plain facts, always in view: songs done of songs found, the step, what didn't go in, the time left.
struct RunProgressLine: View {
    @EnvironmentObject var model: DeskModel
    @ObservedObject var watch: RunWatch
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        if model.runTotal > 0 {
            ProgressView(value: Double(model.runDone), total: Double(model.runTotal))
                .tint(RunLook.accent)
                .shadow(color: RunLook.accent.opacity(watch.moment == "songs" && !reduce ? 0.9 : 0), radius: 6)
                .animation(.easeOut(duration: RunLook.moment / 2), value: watch.moment)
            HStack {
                Text(Words.songsOf(model.runDone, model.runTotal))
                Text(stage).foregroundStyle(.secondary)
                if watch.figures.notIn > 0 { Text(Words.filesDidntGoIn(watch.figures.notIn)).foregroundStyle(.orange) }
                Spacer()
                if let r = model.runRemaining { Text(Words.timeLeft(r)).foregroundStyle(.secondary) }
            }.font(.callout)
        } else { ProgressView().controlSize(.small) }
    }

    private var stage: String {
        switch model.runStage {
        case .reading: return Words.stageReading
        case .finishing: return Words.stageFinishing
        case .saving: return Words.stageSaving
        }
    }
}

/// After a run: how many songs went in, how many did not and why, how long it took, and the next step.
struct FinishedView: View {
    @EnvironmentObject var model: DeskModel
    let report: RunReport

    var body: some View {
        ScrollView {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(Words.finishedTitle(report.read, report.crate)).font(.title2)
            // The crate as sound (D37): the run's songs, one line each, as they joined, and the run's last moment.
            if !model.watch.songs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    if let line = model.watch.finishedLine { Text(line).fontWeight(.semibold) }
                    WallView(watch: model.watch, title: DeskWords.text("wallTitleDone", ["read": report.read]))
                }
                .frame(maxWidth: 760)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(report.notInCount == 0 ? Words.everySongWentIn : Words.wentIn(report.wentIn))
                if report.notInCount > 0 {
                    Text(Words.didntGoIn(report.notInCount))
                    ForEach(report.notIn.keys.sorted(), id: \.self) { r in
                        Text(Words.reasonCount(r, report.notIn[r]!)).foregroundStyle(.secondary).padding(.leading, 12)
                    }
                }
                if report.foldersLeftOut > 0 { Text(Words.foldersLeftOut(report.foldersLeftOut)).foregroundStyle(.secondary) }
                if let local = report.local {
                    ForEach(LocalLines.keyLines(local), id: \.self) { Text($0) }
                    if let d = report.disc, d.text != "names" { Text(Words.t(d.text == "none" ? "discNoNames" : "discDriveNoNames")) }
                    if let d = report.disc, d.named > 0 { Text(Words.c("discNamed", d.named)) }
                    // The count is the list's (letter AA, 3.2): no title, no artist, or Desk's guess.
                    let need = model.needingNames.count
                    HStack {
                        Text(need == 0 ? Words.everySongHasAName : Words.needName(need))
                        if need > 0 {
                            Button(report.disc.map { $0.text != "names" } == true ? Words.t("nameThem") : Words.showThem) {
                                model.onlyNeedName = true; model.finished = nil
                            }.buttonStyle(.link)
                        }
                    }
                    if need > 0 { Text(Words.t("needNameHelp")).foregroundStyle(.secondary) }
                    if let d = report.disc, d.damagedSectors > 0 { Text(Words.t("discDamaged")).foregroundStyle(.secondary) }
                    ForEach(LocalLines.notes(local), id: \.self) { Text($0).foregroundStyle(.secondary) }
                }
                Text(Words.took(report.seconds, perMinute: report.songsPerMinute)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 420, alignment: .leading)
            Text(Words.nextStep).padding(.top, 6)
            HStack {
                Button(Words.sendToIPad) { model.sendToIPad() }.buttonStyle(.borderedProminent)
                if report.notInCount > 0 || report.damaged > 0 { Button(Words.whatDidntGoIn) { model.showImportLog = true } }
                Button(Words.seeSongs) { model.finished = nil }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        }
    }
}

/// The quiet line under the progress: a line for the step Desk is on, or something true it just found, or a moment.
/// It changes every several seconds and never jumps: a fade, or under reduced motion a plain change.
struct SayingLine: View {
    @ObservedObject var watch: RunWatch
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        Text(watch.saying)
            .fontWeight(watch.sayingIsMoment ? .semibold : .regular)
            .foregroundStyle(watch.sayingIsMoment ? .primary : .secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            .id(watch.saying)
            .transition(.opacity)
            .animation(reduce ? nil : .easeInOut(duration: RunLook.fade), value: watch.saying)
    }
}

struct CrateView: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        VStack(spacing: 0) {
            if model.pending != nil { PendingBanner().padding(8) }
            HSplitView {
                TrackTable().frame(minWidth: 560)
                if model.showSources { SourcesPanel().frame(minWidth: 260, idealWidth: 300, maxWidth: 420) }
                Inspector().frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if model.listener.song != nil { PlayerBar(listener: model.listener) }
                StatusBar()
            }
        }
        .sheet(isPresented: Binding(get: { model.tool != nil }, set: { if !$0 { model.tool = nil } })) {
            if let kind = model.tool { ToolSheet(kind: kind).environmentObject(model) }
        }
    }
}

struct StatusBar: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        HStack(spacing: 12) {
            if let c = model.crate {
                Text(Words.songs(c.tracks.count)).bold()
                let unsigned = c.tracks.filter { $0.signatures.isEmpty }.count
                if unsigned > 0 { Text(Words.cantBeRecognised(unsigned)).foregroundStyle(.secondary) }
                let unnamed = model.needingNames.count
                if unnamed > 0 || model.onlyNeedName {
                    Button(model.onlyNeedName ? Words.showAllSongs : Words.needNameCount(unnamed)) { model.onlyNeedName.toggle() }
                        .buttonStyle(.link)
                }
                if model.onlyNeedName { Text(Words.onlyNeedName).foregroundStyle(.secondary) }
                if let log = c.manifest.importLog {
                    let out = log.entries.filter { $0.reason != CrateManifest.ImportLog.Reason.damagedFrames }.count
                    if out > 0 {
                        Button(Words.filesDidntGoIn(out)) { model.showImportLog = true }.buttonStyle(.link)
                    }
                }
            }
            Spacer()
            if let u = model.undoLine, model.undoManager?.canUndo == true {
                Text(u)
                Button(Words.t("undo")) { model.undoLine = nil; model.undoManager?.undo() }.buttonStyle(.link)
            }
        }
        .font(.callout).padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
    }
}

/// The finished screen's and Look again's sentences about keys and names (D30).
enum LocalLines {
    /// "Keys: 212 from rekordbox, 40 from the file's tag.", the songs with no key, and where programs disagree.
    static func keyLines(_ s: LocalFactsSummary) -> [String] {
        var out: [String] = []
        let counts = s.report.keysFrom.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { (origin: $0.key, n: $0.value) }
        if !counts.isEmpty { out.append(Words.keysLine(counts)) }
        if s.report.keysNotRead > 0 { out.append(Words.keysNone(s.report.keysNotRead)) }
        if s.report.keysDisagree > 0 { out.append(Words.keysDisagree(s.report.keysDisagree)) }
        return out
    }

    /// The libraries read, the ones that could not be, and rekordbox's locked library.
    static func notes(_ s: LocalFactsSummary) -> [String] {
        var out: [String] = []
        if !s.libraries.isEmpty { out.append(Words.librariesRead(s.libraries.map { Words.programName($0.program.rawValue) })) }
        out += s.failed.map(Words.couldntReadLibrary)
        if s.rekordboxLocked { out.append(Words.rekordboxLocked) }
        if s.rekordboxExport { out.append(Words.rekordboxExportNotRead) }
        return out
    }

    static func lines(_ s: LocalFactsSummary) -> [String] {
        keyLines(s) + [s.report.needName == 0 ? Words.everySongHasAName : Words.needName(s.report.needName)] + notes(s)
    }
}
