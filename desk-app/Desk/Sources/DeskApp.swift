import SwiftUI
import DeckieInference
import DeckieBuild
import DeckieEngine
import DeckieCrate

/// Deckie Desk: the crate is built and looked after here. Folder in, crate out; names fixed; recognition
/// signatures made on this Mac; the crate then moves to the iPad by AirDrop, iCloud Drive or Files.
@main
struct DeskApp: App {
    @StateObject private var model = DeskModel()

    init() {
        Bundled.pointEngineAtBundle()
        Headless.runIfAsked()
    }

    var body: some Scene {
        WindowGroup("Deckie Desk") {
            ContentView().environmentObject(model).frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Crate from Folder…") { model.askNewCrate() }.keyboardShortcut("n")
                Button("New Crate from Folder with rekordbox Collection…") { model.askNewCrate(withRekordbox: true) }
                Button("Open Crate…") { model.askOpenCrate() }.keyboardShortcut("o")
                Button("Save") { model.save() }.keyboardShortcut("s").disabled(model.crate == nil)
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
enum Headless {
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
                Remembered.setSourceFolder(folder, for: result.crate.manifest.crateId)
                exit(0)
            } catch { print("build failed:", error); exit(1) }
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
                        let data = try Signatures.signature(of: folder.appendingPathComponent(t.file.rel!))
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
