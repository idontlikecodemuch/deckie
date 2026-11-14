import SwiftUI
import DeckieInference
import DeckieBuild
import DeckieEngine
import DeckieCrate
import DeckieCore

/// Deckie Desk: the crate is built and looked after here. Folder in, crate out; names fixed; recognition
/// signatures made on this Mac; the crate then moves to the iPad by AirDrop, iCloud Drive or Files.
@main
struct DeskApp: App {
    @StateObject private var model = DeskModel()

    init() {
        Bundled.pointEngineAtBundle()
        Headless.runIfAsked()
        HeadlessDesk.runIfAsked()
    }

    var body: some Scene {
        WindowGroup(Words.appName) {
            ContentView().environmentObject(model).frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    if let n = Headless.openOnLaunch { model.show(named: n) }
                    if let w = NamingWalk.request { NamingWalk.run(model: model, out: w.out, music: w.music) }
                    if let w = LookupWalk.request { LookupWalk.run(model: model, out: w.out, music: w.music) }
                    if let s = Snapshot.request {
                        if let n = s.crate { model.show(named: n) }
                        Snapshot.run(model: model, out: s.out)
                    }
                    if let c = WindowCheck.request { WindowCheck.run(model: model, out: c.out, add: c.add) }
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(Words.newCrate) { model.newCrate() }.keyboardShortcut("n").disabled(model.running)
                Menu(model.current.map { Words.addMusicTo($0.name) } ?? Words.addMusic) {
                    ForEach(model.musicCDs, id: \.location) { cd in Button(MusicCDItem.label(cd)) { model.addMusicCD(cd) } }
                    ForEach(model.mountedSources, id: \.url) { m in Button(m.name) { model.addSource(m.url, name: m.name) } }
                    Divider()
                    Button(Words.chooseFolder) { model.askSourceFolder() }
                }.disabled(model.running)
                Button(Words.withRekordboxMenu) { model.askRekordbox() }.disabled(model.running)
                Divider()
                Button(Words.lookAgain) { model.lookAgain() }.disabled(model.crate == nil || model.running)
                Button(Words.chooseLibrary) { model.chooseLibrary() }.disabled(model.running)
                Divider()
                Button(Words.importCrateFile) { model.askImport() }.keyboardShortcut("o").disabled(model.running)
                Button(Words.exportCrateFile) { model.askExport() }.keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(model.crate == nil || model.running)
                Button(Words.sendToIPad) { model.sendToIPad() }.disabled(model.crate == nil || model.running)
            }
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(after: .sidebar) {
                Button(model.showSources ? Words.hideSources : Words.showSourcesMenu) { model.showSources.toggle() }
                    .keyboardShortcut("d", modifiers: [.command, .shift]).disabled(model.crate == nil)
            }
        }
    }
}

/// The engine looks for ONNX Runtime and the models by environment variable first; the app points those at its own
/// bundle before anything else runs, unless the environment already says where they are (a developer's checkout).
enum Bundled {
    static func pointEngineAtBundle() {
        let bundle = Bundle.main
        if let fw = bundle.privateFrameworksURL?.appendingPathComponent("libonnxruntime.1.31.1.dylib"),
           FileManager.default.fileExists(atPath: fw.path) {
            setenv(OnnxRuntime.libraryEnvironmentVariable, fw.path, 0)
        }
        if let models = bundle.resourceURL?.appendingPathComponent("models") {
            let beat = models.appendingPathComponent(BeatTracker.modelFileName)
            let yam = models.appendingPathComponent(YAMNet.modelFileName)
            if FileManager.default.fileExists(atPath: beat.path) { setenv(BeatTracker.modelEnvironmentVariable, beat.path, 0) }
            if FileManager.default.fileExists(atPath: yam.path) { setenv(YAMNet.modelEnvironmentVariable, yam.path, 0) }
        }
    }
}

/// A way to drive the app without its window, for checks and for long builds from a terminal:
///   "Deckie Desk" --check-engine                      says where the runtime and the models were found, and exits
///   "Deckie Desk" --build <folder> <out.deckiecrate> [jobs]   builds a crate with the bundled engine, printing progress
///   "Deckie Desk" --add-source <crate> <CD, drive or folder> [jobs]   reads it as a source into that crate file (Add music)
///   "Deckie Desk" --find-copies <crate> <folder>      prints every track's audio and sets cut_key on copies of one recording
///   "Deckie Desk" --sign <crate> <folder>             makes one plain signature per track of a crate file, into it
///   "Deckie Desk" --open <crate name>                 opens that crate of Desk's own in the window
///   "Deckie Desk" --snapshot <folder> [crate name]    opens it, steps through it and writes PNGs of the window (Snapshot.swift)
/// These work on crate files anywhere and are tools for the developer; Desk's own crates (D28) have their own modes in
/// HeadlessDesk.swift. A source's songs are looked for below the music folder given, by the path below the source.
enum Headless {
    /// "Deckie Desk" --open <crate name>: show that crate of Desk's own in the window on launch.
    static var openOnLaunch: String? {
        let a = CommandLine.arguments
        return a.count >= 3 && a[1] == "--open" ? a[2] : nil
    }

    /// Where a song's file is: below the music folder given.
    static func audio(_ t: CrateTrack, folder: URL) -> URL { folder.appendingPathComponent(t.file.rel ?? t.file.name) }

    static func runIfAsked() {
        let a = CommandLine.arguments
        guard a.count >= 2 else { return }
        setvbuf(stdout, nil, _IOLBF, 0)   // progress lines reach a log file as they happen
        if a[1] == "--check-engine" {
            do {
                try Builder.checkEngine()
                print("runtime:", OnnxRuntime.locateLibrary() ?? "not found")
                print("beat model:", BeatTracker.locateModel() ?? "not found")
                print("vocal model:", YAMNet.locateModel() ?? "not found")
                print("engine:", Builder.engineLabel, "on", Analysis.platform, "device", Device.modelLabel())
                exit(0)
            } catch { print("engine check failed:", error); exit(1) }
        }
        if a[1] == "--build", a.count >= 4 {
            let folder = URL(fileURLWithPath: a[2]); let out = URL(fileURLWithPath: a[3])
            let jobs = a.count >= 5 ? Int(a[4]) ?? 2 : 2
            let options = BuildOptions(folder: folder, output: out, rekordbox: nil, jobs: jobs, fileBPMTags: true,
                                       fresh: false, name: nil, device: Device.modelLabel())
            do {
                if let note = Builder.vocalTaggerNote { print(note) }
                let builder = try Builder(options: options)
                let result = try builder.run { event in
                    switch event {
                    case let .started(files, unchanged, queued, jobs, _): print("\(files) files, \(unchanged) unchanged, \(queued) to analyse, \(jobs) at a time")
                    case let .file(p): print("[\(p.done)/\(p.total)] \(p.rel)")
                    case let .writing(n): print("writing \(n) tracks")
                    }
                }
                print(result.summary)
                exit(0)
            } catch { print("build failed:", error); exit(1) }
        }
        if a[1] == "--add-source", a.count >= 4 {
            // "Deckie Desk" --add-source <crate.deckiecrate> <CD, drive or folder> [jobs]: the window's Add music, read as
            // it is into that crate file (made if missing), the source named after its volume or folder.
            let out = URL(fileURLWithPath: a[2]); let root = URL(fileURLWithPath: a[3])
            let name = MountedSource.name(of: root)
            let jobs = a.count >= 5 ? Int(a[4]) ?? 2 : 2
            let options = BuildOptions(folder: root, output: out, jobs: jobs, fileBPMTags: true, device: Device.modelLabel(),
                                       source: name)
            do {
                print("reading \(name) as a source")
                let result = try Builder(options: options).run { event in
                    if case let .file(p) = event { print("[\(p.done)/\(p.total)] \(p.rel)") }
                }
                print(result.summary)
                for d in result.crate.discPlan {
                    for f in d.folders {
                        for (id, n) in result.crate.folderPlaces(disc: d.name, folder: f.name) {
                            guard let t = result.crate.tracks.first(where: { $0.id == id }) else { continue }
                            let here = Crate.placeLine(.init(disc: d.name, folder: f.name, track: n)) ?? ""
                            let more = t.ident.otherPlaces.isEmpty ? "" : "  (\(TrackTable.places(t).count) places)"
                            print("  \(here)  \(t.ident.title)\(more)")
                        }
                    }
                }
                exit(0)
            } catch { print("reading the source failed:", error); exit(1) }
        }
        if a[1] == "--apply", a.count >= 4 {
            // "Deckie Desk" --apply <crate.deckiecrate> <names.tsv>: names and facts from a table, by track id or rel path.
            // Columns (header row, tab-separated, any order): id or rel, then any of title, artist, version, era, kind, tags
            // (comma-separated). An empty cell leaves the field as it is; "-" clears it.
            let crateURL = URL(fileURLWithPath: a[2]); let tsv = URL(fileURLWithPath: a[3])
            do {
                var crate = try CrateReader.read(from: crateURL)
                let text = try String(contentsOf: tsv, encoding: .utf8)
                var lines = text.split(whereSeparator: \.isNewline).map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
                guard let header = lines.first else { print("empty table"); exit(1) }
                lines.removeFirst()
                let col = Dictionary(uniqueKeysWithValues: header.enumerated().map { ($1.lowercased(), $0) })
                var byId: [String: Int] = [:], byRel: [String: Int] = [:]
                for (i, t) in crate.tracks.enumerated() { byId[t.id] = i; if let r = t.file.rel { byRel[r] = i } }
                var changed = 0, missed = 0
                for row in lines {
                    func cell(_ k: String) -> String? { col[k].flatMap { $0 < row.count ? row[$0] : nil } }
                    guard let i = cell("id").flatMap({ byId[$0] }) ?? cell("rel").flatMap({ byRel[$0] }) else { missed += 1; continue }
                    var t = crate.tracks[i]; let before = t
                    func set(_ v: String?, _ apply: (String?) -> Void) { guard let v, !v.isEmpty else { return }; apply(v == "-" ? nil : v) }
                    set(cell("title")) { if let v = $0 { t.ident.title = v } }
                    set(cell("artist")) { t.ident.artist = $0 }
                    set(cell("version")) { t.ident.version = $0 }
                    set(cell("era")) { t.ident.era = $0 }
                    set(cell("kind")) { t.ident.kind = $0 }
                    set(cell("tags")) { t.ident.tags = ($0 ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                    if t != before { crate.tracks[i] = t; changed += 1 }
                }
                try CrateWriter.write(crate, to: crateURL)
                print("\(changed) tracks changed, \(missed) rows matched no track; crate saved")
                exit(0)
            } catch { print("apply failed:", error); exit(1) }
        }
        if a[1] == "--find-copies", a.count >= 4 {
            // "Deckie Desk" --find-copies <crate.deckiecrate> <music folder>: the same as the Find copies button.
            let crateURL = URL(fileURLWithPath: a[2]); let folder = URL(fileURLWithPath: a[3])
            do {
                var crate = try CrateReader.read(from: crateURL)
                var prints: [String: RecordingPrint] = [:]
                for t in crate.tracks where t.file.rel != nil {
                    do { prints[t.id] = try Signatures.recordingPrint(of: Headless.audio(t, folder: folder)) }
                    catch { print("could not read: \(t.file.rel!): \(error)") }
                }
                let grouped = crate.setCutKeys(prints: prints)
                try CrateWriter.write(crate, to: crateURL)
                for g in crate.sameSongGroups where g.count > 1 {
                    print("same recording: " + g.compactMap { id in crate.tracks.first { $0.id == id }?.file.rel }.joined(separator: " | "))
                }
                print("\(prints.count) tracks printed, \(grouped) are copies; crate saved")
                exit(0)
            } catch { print("finding copies failed:", error); exit(1) }
        }
        if a[1] == "--sign", a.count >= 4 {
            // "Deckie Desk" --sign <crate.deckiecrate> <music folder>: one plain signature per track, into the crate.
            let crateURL = URL(fileURLWithPath: a[2]); let folder = URL(fileURLWithPath: a[3])
            do {
                var crate = try CrateReader.read(from: crateURL)
                let sigFolder = crateURL.appendingPathComponent("signatures")
                try FileManager.default.createDirectory(at: sigFolder, withIntermediateDirectories: true)
                let madeBy = Device.modelLabel(); var made = 0, failed = 0
                for i in crate.tracks.indices where crate.tracks[i].signatures["o"] == nil && crate.tracks[i].file.rel != nil {
                    let t = crate.tracks[i]
                    do {
                        let data = try Signatures.signature(of: Headless.audio(t, folder: folder))
                        try data.write(to: sigFolder.appendingPathComponent("\(t.id)_o.shazamsignature"), options: .atomic)
                        crate.tracks[i].signatures["o"] = CrateTrack.Signature(madeBy: madeBy, madeAt: Signatures.utcNow())
                        made += 1; print("[\(made)] \(t.ident.title) \(data.count / 1024) KB")
                    } catch { failed += 1; print("failed: \(t.ident.title): \(error)") }
                    if made % 25 == 0 { try CrateWriter.write(crate, to: crateURL) }
                }
                try CrateWriter.write(crate, to: crateURL)
                print("\(made) signatures made, \(failed) failed; crate saved")
                exit(0)
            } catch { print("signing failed:", error); exit(1) }
        }
    }
}
