import SwiftUI
import DeckieCrate

struct ContentView: View {
    @EnvironmentObject var model: DeskModel

    var body: some View {
        Group {
            if model.building { BuildView() }
            else if model.crate != nil { CrateView() }
            else { EmptyCrateView() }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { model.askNewCrate() } label: { Label("New crate from folder", systemImage: "folder.badge.plus") }
                    .disabled(model.building)
                Button { model.askOpenCrate() } label: { Label("Open crate", systemImage: "shippingbox") }
                    .disabled(model.building)
                if model.crate != nil {
                    Button { model.save() } label: { Label("Save", systemImage: "square.and.arrow.down") }.disabled(!model.dirty)
                    Button { model.makeSignatures() } label: { Label("Make signatures", systemImage: "waveform.badge.magnifyingglass") }
                        .disabled(model.signing)
                    Button { model.showImportLog = true } label: { Label("Import log", systemImage: "list.bullet.rectangle") }
                    Button { model.revealInFinder() } label: { Label("Show in Finder", systemImage: "arrow.up.forward.app") }
                }
            }
        }
        .sheet(isPresented: $model.showImportLog) { ImportLogView() }
        .alert("Deckie Desk", isPresented: Binding(get: { model.errorText != nil }, set: { if !$0 { model.errorText = nil } })) {
            Button("OK") { model.errorText = nil }
        } message: { Text(model.errorText ?? "") }
    }
}

struct EmptyCrateView: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox").font(.system(size: 56)).foregroundStyle(.secondary)
            Text("Your crate starts here.").font(.title2)
            Text("Point Deckie at a folder of music. It reads the beat, the key, the structure and the loudness of every track and writes a crate, a small file you move to the iPad. The music never leaves this Mac.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 520)
            HStack {
                Button("New crate from folder…") { model.askNewCrate() }.buttonStyle(.borderedProminent)
                Button("With a rekordbox collection…") { model.askNewCrate(withRekordbox: true) }
                Button("Open a crate…") { model.askOpenCrate() }
            }
        }.padding(40)
    }
}

struct BuildView: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Building the crate").font(.title2)
            if model.buildTotal > 0 {
                ProgressView(value: Double(model.buildDone), total: Double(model.buildTotal))
                HStack {
                    Text("\(model.buildDone) of \(model.buildTotal) tracks")
                    Spacer()
                    if let r = model.buildRemaining { Text("about \(Int(r / 60)) min left").foregroundStyle(.secondary) }
                }.font(.callout)
            } else { ProgressView().controlSize(.small) }
            List(model.buildLines.indices, id: \.self) { i in
                Text(model.buildLines[i]).font(.system(.caption, design: .monospaced)).lineLimit(1)
            }
        }.padding(20)
    }
}

struct CrateView: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        HSplitView {
            TrackTable().frame(minWidth: 560)
            Inspector().frame(minWidth: 260, idealWidth: 300, maxWidth: 380)
        }
        .safeAreaInset(edge: .bottom) { StatusBar() }
    }
}

struct StatusBar: View {
    @EnvironmentObject var model: DeskModel
    var body: some View {
        HStack(spacing: 12) {
            if let c = model.crate {
                Text("\(c.tracks.count) tracks").bold()
                Text(c.manifest.name).foregroundStyle(.secondary)
                let signed = c.tracks.filter { !$0.signatures.isEmpty }.count
                Text("\(signed) with signatures").foregroundStyle(.secondary)
                if let log = c.manifest.importLog, !log.entries.isEmpty {
                    Button("\(log.entries.count) files not in the crate or with a note") { model.showImportLog = true }.buttonStyle(.link)
                }
            }
            Spacer()
            if model.signing { ProgressView().controlSize(.small); Text(model.signProgress).foregroundStyle(.secondary) }
            else if !model.signProgress.isEmpty { Text(model.signProgress).foregroundStyle(.secondary) }
            if let s = model.buildSummary { Text(s).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary) }
            if model.dirty { Text("Unsaved changes").foregroundStyle(.orange) }
        }
        .font(.callout).padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
    }
}
