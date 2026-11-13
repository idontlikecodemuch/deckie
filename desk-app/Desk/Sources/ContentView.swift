import SwiftUI
import DeckieCrate
import DeckieDesk

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
            let here = FileManager.default.fileExists(atPath: p.folder)
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                Text(Words.stoppedReading(p.name))
                if here { Button(Words.carryOn) { model.carryOn() } }
                else { Text(Words.putBack(p.name)).foregroundStyle(.secondary) }
            }
            .font(.callout).padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct RunView: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(Words.runTitle).font(.title2)
            Text(Words.runReading(model.runRead, into: model.current?.name ?? "")).foregroundStyle(.secondary)
            if model.runTotal > 0 {
                ProgressView(value: Double(model.runDone), total: Double(model.runTotal))
                HStack {
                    Text(Words.songsOf(model.runDone, model.runTotal))
                    Text(stage).foregroundStyle(.secondary)
                    Spacer()
                    if let r = model.runRemaining { Text(Words.timeLeft(r)).foregroundStyle(.secondary) }
                }.font(.callout)
            } else { ProgressView().controlSize(.small) }
            List(model.runLines.indices, id: \.self) { i in
                Text(model.runLines[i]).font(.system(.caption, design: .monospaced)).lineLimit(1)
            }
        }.padding(20)
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
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle").font(.system(size: 48)).foregroundStyle(.secondary)
            Text(Words.finishedTitle(report.read, report.crate)).font(.title2)
            VStack(alignment: .leading, spacing: 6) {
                Text(report.notInCount == 0 ? Words.everySongWentIn : Words.wentIn(report.wentIn))
                if report.notInCount > 0 {
                    Text(Words.didntGoIn(report.notInCount))
                    ForEach(report.notIn.keys.sorted(), id: \.self) { r in
                        Text(Words.reasonCount(r, report.notIn[r]!)).foregroundStyle(.secondary).padding(.leading, 12)
                    }
                }
                if report.foldersLeftOut > 0 { Text(Words.foldersLeftOut(report.foldersLeftOut)).foregroundStyle(.secondary) }
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
        .safeAreaInset(edge: .bottom) { StatusBar() }
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
                if let log = c.manifest.importLog {
                    let out = log.entries.filter { $0.reason != CrateManifest.ImportLog.Reason.damagedFrames }.count
                    if out > 0 {
                        Button(Words.filesDidntGoIn(out)) { model.showImportLog = true }.buttonStyle(.link)
                    }
                }
            }
            Spacer()
        }
        .font(.callout).padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
    }
}
