import SwiftUI
import DeckieInference

/// Deckie Desk: the crate is built and looked after here. Folder in, crate out; names fixed; recognition
/// signatures made on this Mac; the crate then moves to the iPad by AirDrop, iCloud Drive or Files.
@main
struct DeskApp: App {
    @StateObject private var model = DeskModel()

    init() { Bundled.pointEngineAtBundle() }

    var body: some Scene {
        WindowGroup("Deckie Desk") {
            ContentView().environmentObject(model).frame(minWidth: 900, minHeight: 560)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Crate from Folder…") { model.askNewCrate() }.keyboardShortcut("n")
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
