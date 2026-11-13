import Foundation
import AppKit
import UniformTypeIdentifiers
import DeckieCrate
import DeckieBuild
import DeckieEngine
import DeckieCore

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
    @Published var findingCopies = false

    @Published var errorText: String?
    @Published var showImportLog = false

    // Sources (SourcesPanel.swift): whether the panel shows and what is selected in it; where this crate's sources
    // were read from on this Mac (by the source's name); the CDs and drives mounted now, for Add music.
    @Published var showSources = false
    @Published var sourceSelection: SourceItem?
    @Published var sourceRoots: [String: URL] = [:]
    @Published var mountedSources: [MountedSource] = []
    private var mountWatchers: [NSObjectProtocol] = []

    init() {
        mountedSources = MountedSource.all()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            mountWatchers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.mountedSources = MountedSource.all() }
            })
        }
    }

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
            sourceSelection = nil
            sourceFolder = Remembered.sourceFolder(for: c.manifest.crateId)
            sourceRoots = Remembered.sourceRoots(for: c.manifest.crateId)
            buildSummary = nil
        } catch { errorText = "Could not open the crate: \(error)" }
    }

    func askNewCrate(withRekordbox: Bool = false) {
        if withRekordbox {
            let x = NSOpenPanel()
            x.canChooseDirectories = false; x.canChooseFiles = true; x.allowsMultipleSelection = false
            x.allowedContentTypes = [.xml]
            x.message = "Choose the collection you exported from rekordbox (File > Export Collection in xml format). Deckie takes names, tempos, keys, cues and playlists from it; nothing is sent anywhere."
            x.begin { [weak self] r in
                guard r == .OK, let xml = x.url, let self else { return }
                self.askFolder(rekordbox: xml)
            }
        } else { askFolder(rekordbox: nil) }
    }

    private func askFolder(rekordbox: URL?) {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.prompt = "Build"
        p.message = "Choose the folder of music. Deckie analyses every audio file below it and writes a crate; the music stays where it is."
        p.begin { [weak self] r in
            guard r == .OK, let folder = p.url, let self else { return }
            self.askWhereToSave(folder: folder, rekordbox: rekordbox)
        }
    }

    private func askWhereToSave(folder: URL, rekordbox: URL?) {
        let s = NSSavePanel()
        s.nameFieldStringValue = folder.lastPathComponent + ".deckiecrate"
        s.directoryURL = Remembered.cratesFolder()
        s.message = "Where the crate goes. A work folder beside it keeps finished tracks, so a second build only looks at what changed."
        s.begin { [weak self] r in
            guard r == .OK, let out = s.url, let self else { return }
            Remembered.setCratesFolder(out.deletingLastPathComponent())
            self.build(folder: folder, output: out, rekordbox: rekordbox)
        }
    }

    /// Builds the crate file at `output` from `folder`: an ordinary folder of music (`source` nil), whose songs have no
    /// source and keep the sources read into that crate file before; or a source read as it is, added to the crate
    /// file there (or making one), which keeps everything that is not from that source.
    func build(folder: URL, output: URL, rekordbox: URL? = nil, fileBPMTags: Bool = true, source: String? = nil) {
        // The sources an existing crate file at `output` was given before, so a build from a folder keeps them.
        let existingId = (try? CrateReader.read(from: output))?.manifest.crateId
        let keep = Set(existingId.map { Remembered.sourceRoots(for: $0).keys.map { $0 } } ?? [])
        building = true; buildLines = []; buildDone = 0; buildTotal = 0; buildRemaining = nil; buildSummary = nil
        crate = nil; crateURL = nil; selection = []; sourceSelection = nil
        let options = BuildOptions(folder: folder, output: output, rekordbox: rekordbox, jobs: max(1, min(ProcessInfo.processInfo.activeProcessorCount / 2, 4)),
                                   fileBPMTags: fileBPMTags, fresh: false, name: nil, device: Device.modelLabel(),
                                   source: source, keepSources: keep)
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
                    let id = result.crate.manifest.crateId
                    if let source {
                        Remembered.setSourceRoot(folder, name: source, for: id)
                        model.showSources = true
                    } else {
                        Remembered.setSourceFolder(folder, for: id)
                    }
                    model.sourceFolder = Remembered.sourceFolder(for: id)
                    model.sourceRoots = Remembered.sourceRoots(for: id)
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

    /// The other entries of the same recording as `t` (the same `cut_key`), in crate order.
    func copies(of t: CrateTrack) -> [CrateTrack] {
        let k = t.recordingKey
        return crate?.tracks.filter { $0.id != t.id && $0.recordingKey == k } ?? []
    }

    func update(_ id: String, _ change: (inout CrateTrack) -> Void) {
        guard var c = crate, let i = c.tracks.firstIndex(where: { $0.id == id }) else { return }
        change(&c.tracks[i]); crate = c; dirty = true
    }

    /// A change to the whole crate (the source and folder corrections in DeckieCrate), marked as unsaved.
    func updateCrate(_ change: (inout Crate) -> Void) {
        guard var c = crate else { return }
        let before = c
        change(&c)
        if c != before { crate = c; dirty = true }
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

    // MARK: add music from a source

    /// Reads a CD or a drive (or a folder the DJ says is one) as it is, into the open crate file, or into a new crate
    /// file named after it when none is open. Unsaved changes are saved first, since the build reads the crate file.
    func addSource(_ url: URL, name: String) {
        guard !building else { return }
        if let out = crateURL {
            if dirty { save() }
            build(folder: url, output: out, source: name)
        } else {
            let s = NSSavePanel()
            s.nameFieldStringValue = name + ".deckiecrate"
            s.directoryURL = Remembered.cratesFolder()
            s.message = "Where the crate file goes. Deckie reads \(name) where it is and copies nothing."
            s.begin { [weak self] r in
                guard r == .OK, let out = s.url, let self else { return }
                Remembered.setCratesFolder(out.deletingLastPathComponent())
                self.build(folder: url, output: out, source: name)
            }
        }
    }

    /// The fallback: any folder, read as a source named after its volume (when it is the top of one) or itself.
    func askSourceFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.prompt = "Add"
        p.message = "Choose a CD, a drive or a folder. Deckie reads its name, its folders and the order of its songs as they are."
        p.begin { [weak self] r in
            guard r == .OK, let url = p.url, let self else { return }
            self.addSource(url, name: MountedSource.name(of: url))
        }
    }

    /// Where a song's file is on this Mac: below the place its source was read from, or below the crate's music folder
    /// for a song with no source. Nil when Desk does not know.
    func audioURL(for t: CrateTrack) -> URL? {
        guard let rel = t.file.rel else { return nil }
        if let s = t.ident.disc, let root = sourceRoots[s] { return root.appendingPathComponent(rel) }
        return sourceFolder?.appendingPathComponent(rel)
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
        guard sourceFolder != nil || !sourceRoots.isEmpty else { chooseSourceFolder(); return }
        signing = true; signProgress = "Starting…"
        let todo = c.tracks.filter { $0.signatures["o"] == nil }.compactMap { t in audioURL(for: t).map { (t, $0) } }
        let madeBy = Device.modelLabel()
        let model = self
        Task.detached(priority: .userInitiated) {
            var made: [String: CrateTrack.Signature] = [:]
            var failed: [String] = []
            let sigFolder = url.appendingPathComponent("signatures")
            try? FileManager.default.createDirectory(at: sigFolder, withIntermediateDirectories: true)
            for (n, (t, audio)) in todo.enumerated() {
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

extension DeskModel {
    /// Finds copies of the same recording (D24): every track's audio is read from the music folder and printed
    /// (`RecordingPrint`), the prints are compared, and copies get the same `cut_key`, so the booth shows them as
    /// one song with every place it lives. A remix, an edit or a live version does not match. Tracks whose file
    /// cannot be read keep the key they had. The crate is saved afterwards, as with signatures.
    func findCopies() {
        guard let c = crate, crateURL != nil else { return }
        guard sourceFolder != nil || !sourceRoots.isEmpty else { chooseSourceFolder(); return }
        findingCopies = true; signProgress = "Reading the music…"
        let todo = c.tracks.compactMap { t in audioURL(for: t).map { (t, $0) } }
        let model = self
        Task.detached(priority: .userInitiated) {
            var prints: [String: RecordingPrint] = [:]
            var failed = 0
            for (n, (t, audio)) in todo.enumerated() {
                await MainActor.run { model.signProgress = "Finding copies: \(n + 1) of \(todo.count)" }
                do { prints[t.id] = try Signatures.recordingPrint(of: audio) }
                catch { failed += 1 }
            }
            await MainActor.run {
                var grouped = 0
                model.updateCrate { grouped = $0.setCutKeys(prints: prints) }
                if model.dirty { model.save() }
                let songs = Set(model.crate?.tracks.compactMap { prints[$0.id] == nil ? nil : $0.ident.cutKey } ?? []).count
                model.findingCopies = false
                model.signProgress = grouped == 0 ? "No copies of the same recording found." :
                    "\(grouped) tracks are copies of \(songs) recording\(songs == 1 ? "" : "s")." +
                    (failed == 0 ? "" : " \(failed) could not be read.")
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

    /// Where each source of a crate was last read from on this Mac, by the source's name (a mounted volume's path, or
    /// the folder chosen). The crate file holds only the name and the paths below it.
    static func sourceRoots(for crateId: String) -> [String: URL] {
        let d = UserDefaults.standard.dictionary(forKey: "sources." + crateId) as? [String: String] ?? [:]
        return d.mapValues { URL(fileURLWithPath: $0) }
    }
    static func setSourceRoot(_ u: URL, name: String, for crateId: String) {
        var d = UserDefaults.standard.dictionary(forKey: "sources." + crateId) as? [String: String] ?? [:]
        d[name] = u.path
        UserDefaults.standard.set(d, forKey: "sources." + crateId)
    }
    static func renameSourceRoot(_ name: String, to new: String, for crateId: String) {
        var d = UserDefaults.standard.dictionary(forKey: "sources." + crateId) as? [String: String] ?? [:]
        guard let p = d.removeValue(forKey: name) else { return }
        d[new] = p
        UserDefaults.standard.set(d, forKey: "sources." + crateId)
    }
}

/// A CD or a drive mounted on this Mac that Add music offers: removable, ejectable or external, never the Mac's own
/// disk; shown by its own name.
struct MountedSource: Hashable {
    let name: String
    let url: URL

    static func all() -> [MountedSource] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeIsInternalKey,
                                      .volumeIsRootFileSystemKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { u in
            guard let v = try? u.resourceValues(forKeys: Set(keys)), v.volumeIsRootFileSystem != true,
                  v.volumeIsBrowsable != false,
                  v.volumeIsRemovable == true || v.volumeIsEjectable == true || v.volumeIsInternal == false else { return nil }
            return MountedSource(name: SourceReading.name(volumeName: v.volumeName, folderName: u.lastPathComponent), url: u)
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// A chosen folder's source name: its volume's name when it is the top of a volume, else its own name.
    static func name(of url: URL) -> String {
        let v = try? url.resourceValues(forKeys: [.volumeNameKey, .volumeURLKey])
        let isTop = v?.volume?.standardizedFileURL.path == url.standardizedFileURL.path
        return SourceReading.name(volumeName: isTop ? v?.volumeName : nil, folderName: url.lastPathComponent)
    }
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
