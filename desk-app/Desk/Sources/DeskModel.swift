import Foundation
import AppKit
import DeckieCrate
import DeckieBuild
import DeckieEngine

/// What the window shows: one crate at a time, a build in progress, or nothing yet.
@MainActor
final class DeskModel: ObservableObject {
    @Published var crate: Crate?
    @Published var crateURL: URL?
    @Published var sourceFolder: URL?
    @Published var selection: Set<String> = []
    @Published var dirty = false

    @Published var building = false
    @Published var buildLines: [String] = []
    @Published var buildDone = 0
    @Published var buildTotal = 0
    @Published var buildRemaining: Double?
    @Published var buildSummary: String?

    @Published var signing = false
    @Published var signProgress = ""

    @Published var errorText: String?
    @Published var showImportLog = false

    // MARK: open and new

    func askOpenCrate() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = true; p.allowsMultipleSelection = false
        p.treatsFilePackagesAsDirectories = false
        p.message = "Choose a crate (a .deckiecrate package)."
        p.begin { [weak self] r in
            guard r == .OK, let url = p.url, let self else { return }
            self.open(url)
        }
    }

    func open(_ url: URL) {
        do {
            let c = try CrateReader.read(from: url)
            crate = c; crateURL = url; dirty = false; selection = []
            sourceFolder = Remembered.sourceFolder(for: c.manifest.crateId)
            buildSummary = nil
        } catch { errorText = "Could not open the crate: \(error)" }
    }

    func askNewCrate() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.prompt = "Build"
        p.message = "Choose the folder of music. Deckie analyses every audio file below it and writes a crate; the music stays where it is."
        p.begin { [weak self] r in
            guard r == .OK, let folder = p.url, let self else { return }
            self.askWhereToSave(folder: folder)
        }
    }

    private func askWhereToSave(folder: URL) {
        let s = NSSavePanel()
        s.nameFieldStringValue = folder.lastPathComponent + ".deckiecrate"
        s.directoryURL = Remembered.cratesFolder()
        s.message = "Where the crate goes. A work folder beside it keeps finished tracks, so a second build only looks at what changed."
        s.begin { [weak self] r in
            guard r == .OK, let out = s.url, let self else { return }
            Remembered.setCratesFolder(out.deletingLastPathComponent())
            self.build(folder: folder, output: out)
        }
    }

    func build(folder: URL, output: URL, rekordbox: URL? = nil, fileBPMTags: Bool = true) {
        building = true; buildLines = []; buildDone = 0; buildTotal = 0; buildRemaining = nil; buildSummary = nil
        crate = nil; crateURL = nil; selection = []
        let options = BuildOptions(folder: folder, output: output, rekordbox: rekordbox, jobs: max(1, min(ProcessInfo.processInfo.activeProcessorCount / 2, 4)),
                                   fileBPMTags: fileBPMTags, fresh: false, name: nil, device: Device.modelLabel())
        if let note = Builder.vocalTaggerNote { buildLines.append(note) }
        let model = self
        Task.detached(priority: .userInitiated) {
            do {
                let builder = try Builder(options: options)
                let result = try builder.run { event in
                    Task { @MainActor in model.handle(event) }
                }
                await MainActor.run {
                    model.building = false
                    model.buildSummary = result.summary
                    model.crate = result.crate; model.crateURL = result.output; model.dirty = false
                    model.sourceFolder = folder
                    Remembered.setSourceFolder(folder, for: result.crate.manifest.crateId)
                }
            } catch {
                await MainActor.run {
                    model.building = false
                    model.errorText = "The build stopped: \(error)"
                }
            }
        }
    }

    private func handle(_ event: BuildEvent) {
        switch event {
        case let .started(files, unchanged, queued, jobs, rekordbox):
            buildTotal = queued
            var line = "\(files) audio files found; \(unchanged) unchanged since last time; \(queued) to analyse, \(jobs) at a time."
            if let r = rekordbox { line += " rekordbox: \(r.matched) of \(r.tracks) tracks matched." }
            buildLines.append(line)
        case let .file(p):
            buildDone = p.done; buildTotal = p.total; buildRemaining = p.remaining
            switch p.outcome {
            case let .analysed(seconds): buildLines.append(String(format: "%@  (%.1f s)", p.rel, seconds))
            case .reused: buildLines.append("\(p.rel)  (kept from last time)")
            case let .failed(f): buildLines.append("\(p.rel)  not analysed: \(f)")
            }
            if buildLines.count > 400 { buildLines.removeFirst(buildLines.count - 400) }
        case let .writing(tracks):
            buildLines.append("Writing the crate: \(tracks) tracks.")
        }
    }

    // MARK: edit and save

    func binding(for id: String) -> CrateTrack? { crate?.tracks.first { $0.id == id } }

    func update(_ id: String, _ change: (inout CrateTrack) -> Void) {
        guard var c = crate, let i = c.tracks.firstIndex(where: { $0.id == id }) else { return }
        change(&c.tracks[i]); crate = c; dirty = true
    }

    func save() {
        guard let c = crate, let url = crateURL else { return }
        do { try CrateWriter.write(c, to: url); dirty = false }
        catch { errorText = "Could not save the crate: \(error)" }
    }

    func revealInFinder() {
        guard let url = crateURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func chooseSourceFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.message = "Where the music for this crate is on this Mac (needed to make recognition signatures)."
        p.begin { [weak self] r in
            guard r == .OK, let url = p.url, let self, let c = self.crate else { return }
            self.sourceFolder = url; Remembered.setSourceFolder(url, for: c.manifest.crateId)
        }
    }

    // MARK: signatures

    /// One recognition signature per track (the plain `o` variant), made with Apple's ShazamKit on this Mac and
    /// kept inside the crate. The iPad builds its catalogue from these. Pitch variants come later.
    func makeSignatures() {
        guard let c = crate, let url = crateURL else { return }
        guard let folder = sourceFolder else { chooseSourceFolder(); return }
        signing = true; signProgress = "Starting…"
        let todo = c.tracks.filter { $0.signatures["o"] == nil && $0.file.rel != nil }
        let madeBy = Device.modelLabel()
        let model = self
        Task.detached(priority: .userInitiated) {
            var made: [String: CrateTrack.Signature] = [:]
            var failed: [String] = []
            let sigFolder = url.appendingPathComponent("signatures")
            try? FileManager.default.createDirectory(at: sigFolder, withIntermediateDirectories: true)
            for (n, t) in todo.enumerated() {
                let audio = folder.appendingPathComponent(t.file.rel!)
                await MainActor.run { model.signProgress = "\(n + 1) of \(todo.count): \(t.ident.title)" }
                do {
                    let data = try Signatures.signature(of: audio)
                    try data.write(to: sigFolder.appendingPathComponent("\(t.id)_o.shazamsignature"), options: .atomic)
                    made[t.id] = CrateTrack.Signature(madeBy: madeBy, madeAt: Signatures.utcNow())
                } catch { failed.append("\(t.ident.title): \(error.localizedDescription)") }
            }
            await MainActor.run {
                for (id, sig) in made { model.update(id) { $0.signatures["o"] = sig } }
                model.save()
                model.signing = false
                model.signProgress = "\(made.count) signatures made" + (failed.isEmpty ? "." : "; \(failed.count) failed: " + failed.prefix(3).joined(separator: "; "))
            }
        }
    }
}

/// Small things the app remembers between launches: where crates go, and where each crate's music is on this Mac.
/// The crate itself never holds an absolute path.
enum Remembered {
    static func cratesFolder() -> URL {
        if let p = UserDefaults.standard.string(forKey: "cratesFolder") { return URL(fileURLWithPath: p) }
        let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first ?? FileManager.default.homeDirectoryForCurrentUser
        let u = music.appendingPathComponent("Deckie")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    static func setCratesFolder(_ u: URL) { UserDefaults.standard.set(u.path, forKey: "cratesFolder") }
    static func sourceFolder(for crateId: String) -> URL? {
        UserDefaults.standard.string(forKey: "source." + crateId).map { URL(fileURLWithPath: $0) }
    }
    static func setSourceFolder(_ u: URL, for crateId: String) { UserDefaults.standard.set(u.path, forKey: "source." + crateId) }
}

enum Device {
    /// The Mac's model label (`Mac15,6`), never the user's device name.
    static func modelLabel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var chars = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &chars, &size, nil, 0)
        return String(cString: chars)
    }
}
