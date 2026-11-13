import Foundation
import AppKit
import UniformTypeIdentifiers
import DeckieCrate
import DeckieBuild
import DeckieEngine
import DeckieCore
import DeckieDesk

/// What the window shows: the crate that is showing (one of the crates Desk keeps, D28), a run in progress, the
/// finished screen after one, or the first screen when there is no crate yet. Desk saves as it goes: every change is
/// written at once and can be undone with the standard commands.
@MainActor
final class DeskModel: ObservableObject {
    let home = DeskHome.standard()

    /// Every crate, the most recent first, and the one showing (nil: the first screen, for a new crate).
    @Published var crates: [CrateInfo] = []
    @Published var current: CrateInfo?
    @Published var crate: Crate?
    @Published var selection: Set<String> = []
    /// The table shows only the songs that still need a name (D30).
    @Published var onlyNeedName = false
    private(set) var corrections = NameCorrections()
    private(set) var placePaths = PlacePaths()
    /// A run of the crate showing that stopped before it finished.
    @Published var pending: RunRequest?

    // The run.
    @Published var running = false
    @Published var runRead = ""
    @Published var runStage: RunStage = .reading
    @Published var runDone = 0
    @Published var runTotal = 0
    @Published var runRemaining: Double?
    @Published var runLines: [String] = []
    /// The finished screen's report, until the DJ moves on.
    @Published var finished: RunReport?

    @Published var errorText: String?
    @Published var showImportLog = false
    @Published var renaming: CrateInfo?
    @Published var deleting: CrateInfo?
    @Published var removing: String??

    // Sources (SourcesPanel.swift): whether the panel shows and what is selected in it; the CDs and drives mounted now.
    @Published var showSources = false
    @Published var sourceSelection: SourceItem?
    @Published var mountedSources: [MountedSource] = []
    private var watchers: [NSObjectProtocol] = []

    /// The window's undo manager, given by the window (ContentView).
    weak var undoManager: UndoManager?
    private var saveTask: Task<Void, Never>?
    private var needsSave = false

    init() {
        mountedSources = MountedSource.all()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            watchers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.mountedSources = MountedSource.all() }
            })
        }
        watchers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        })
        reloadCrates()
        if let first = crates.first { show(first) }
    }

    // MARK: the crates

    var shelf: CrateShelf { home.shelf }
    var roots: [String: URL] { current?.roots ?? [:] }
    var musicFolder: URL? { current?.musicFolderURL }

    func reloadCrates() { crates = shelf.list() }

    /// Shows a crate: its crate file, its fixes and its remembered paths. Undo starts afresh for it.
    func show(_ info: CrateInfo) {
        saveNow()
        undoManager?.removeAllActions()
        current = (try? shelf.touch(info.id)) ?? info
        let pkg = shelf.package(info.id)
        crate = FileManager.default.fileExists(atPath: pkg.appendingPathComponent(CrateFormat.manifestFile).path)
            ? (try? CrateReader.read(from: pkg)) : nil
        corrections = NameCorrections.load(from: shelf.file(DeskRun.correctionsFile, of: info.id))
        placePaths = PlacePaths.load(from: shelf.file(DeskRun.placesFile, of: info.id))
        pending = DeskRun.pending(home: home, crateId: info.id)
        selection = []; sourceSelection = nil; finished = nil; onlyNeedName = false
        reloadCrates()
    }

    func show(named name: String) { if let i = crates.first(where: { $0.name == name }) { show(i) } }

    /// "New crate": the first screen; the crate is made, named after what is read, when music is added.
    func newCrate() {
        saveNow()
        undoManager?.removeAllActions()
        current = nil; crate = nil; pending = nil; finished = nil; selection = []; sourceSelection = nil
    }

    func rename(_ info: CrateInfo, to name: String) {
        saveNow()
        do {
            let i = try shelf.rename(info.id, to: name)
            if current?.id == i.id {
                current = i
                if crate != nil { crate?.manifest.name = i.name }
            }
            reloadCrates()
        } catch { errorText = Words.couldntRename(error.localizedDescription) }
    }

    /// Deletes a crate (after the window asked): to the Trash, or for good when Desk's storage is a test folder
    /// (`DECKIE_DESK_HOME`). Shows the next most recent crate, or the first screen.
    func delete(_ info: CrateInfo) {
        do {
            if current?.id == info.id { saveTask?.cancel(); saveTask = nil; needsSave = false; current = nil; crate = nil }
            if ProcessInfo.processInfo.environment[DeskHome.environmentVariable] == nil {
                try FileManager.default.trashItem(at: shelf.folder(info.id), resultingItemURL: nil)
            } else {
                try shelf.delete(info.id)
            }
            reloadCrates()
            if current == nil { if let next = crates.first { show(next) } else { newCrate() } }
        } catch { errorText = Words.couldntDelete(error.localizedDescription) }
    }

    // MARK: out and in (D28)

    /// The share sheet with the crate file, so AirDrop to the iPad is one click.
    func sendToIPad() {
        guard let info = current, crate != nil else { errorText = Words.nothingToSendYet; return }
        saveNow()
        do { Share.show(try shelf.outboxCopy(info.id)) }
        catch { errorText = Words.couldntExport(error.localizedDescription) }
    }

    func askExport() {
        guard let info = current, crate != nil else { errorText = Words.nothingToSendYet; return }
        saveNow()
        let s = NSSavePanel()
        s.nameFieldStringValue = info.name + "." + CrateFormat.packageExtension
        s.message = Words.exportMessage
        s.begin { [weak self] r in
            guard r == .OK, let url = s.url, let self else { return }
            do { try self.shelf.exportCopy(info.id, to: url) }
            catch { self.errorText = Words.couldntExport(error.localizedDescription) }
        }
    }

    func askImport() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = true; p.allowsMultipleSelection = false
        p.treatsFilePackagesAsDirectories = false
        p.message = Words.importMessage
        p.begin { [weak self] r in
            guard r == .OK, let url = p.url, let self else { return }
            self.importCrate(url)
        }
    }

    func importCrate(_ url: URL) {
        do {
            let info = try shelf.importCopy(of: url)
            reloadCrates(); show(info)
        } catch { errorText = Words.couldntOpen(error.localizedDescription) }
    }

    // MARK: Add music: the one run

    /// Reads a CD, a drive or a folder as a source into the crate showing, or into a new crate named after it.
    func addSource(_ url: URL, name: String) {
        let unique = SourceNaming.unique(name, root: url, roots: roots)
        start(RunRequest(folder: url, source: unique))
    }

    /// The fallback: any folder, read as a source named after its volume (when it is the top of one) or itself.
    func askSourceFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.prompt = Words.chooseSourcePrompt
        p.message = Words.chooseSourceMessage
        p.begin { [weak self] r in
            guard r == .OK, let url = p.url, let self else { return }
            self.addSource(url, name: MountedSource.name(of: url))
        }
    }

    /// The rekordbox route, where it was: a collection export, then the folder of music, read as the music folder
    /// (no source) with the names, tempos, keys and cues from rekordbox.
    func askRekordbox() {
        let x = NSOpenPanel()
        x.canChooseDirectories = false; x.canChooseFiles = true; x.allowsMultipleSelection = false
        x.allowedContentTypes = [.xml]
        x.message = Words.rekordboxMessage
        x.begin { [weak self] r in
            guard r == .OK, let xml = x.url, let self else { return }
            let p = NSOpenPanel()
            p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
            p.prompt = Words.start
            p.message = Words.rekordboxFolderMessage
            p.begin { [weak self] r in
                guard r == .OK, let folder = p.url, let self else { return }
                self.start(RunRequest(folder: folder, source: nil, rekordbox: xml))
            }
        }
    }

    /// Carries on the run that stopped.
    func carryOn() { if let p = pending { start(p) } }

    var jobs: Int { max(1, min(ProcessInfo.processInfo.activeProcessorCount / 2, 4)) }

    /// The one run: into the crate showing, or a new crate named after what is read.
    func start(_ request: RunRequest) {
        guard !running else { return }
        saveNow()
        let info: CrateInfo
        do {
            if let c = current { info = c } else { info = try shelf.make(name: request.name); current = info }
        } catch { errorText = Words.runStopped(error.localizedDescription); return }
        running = true; finished = nil; runRead = request.name; runStage = .reading
        runDone = 0; runTotal = 0; runRemaining = nil; runLines = []
        if let note = Builder.vocalTaggerNote { runLines.append(note) }
        undoManager?.removeAllActions()
        let run = DeskRun(home: home, crateId: info.id, request: request, jobs: jobs, device: Device.modelLabel(),
                          signer: { try Signatures.signature(of: $0) }, printer: { try Signatures.recordingPrint(of: $0) })
        let model = self
        Task.detached(priority: .userInitiated) {
            do {
                let (crate, report) = try run.run { p in Task { @MainActor in model.handle(p) } }
                await MainActor.run {
                    model.running = false
                    model.reloadCrates()
                    if let i = model.crates.first(where: { $0.id == info.id }) { model.show(i) }
                    model.crate = crate
                    model.finished = report
                }
            } catch {
                await MainActor.run {
                    model.running = false
                    model.reloadCrates()
                    if let i = model.crates.first(where: { $0.id == info.id }) { model.show(i) }
                    model.errorText = Words.runStopped(error.localizedDescription)
                }
            }
        }
    }

    private func handle(_ p: RunProgress) {
        guard running else { return }
        runStage = p.stage; runDone = p.done; runTotal = p.total; runRemaining = p.remaining
        switch p.line {
        case let .started(files, unchanged, queued)?:
            runLines.append(Words.lineStarted(files: files, unchanged: unchanged, queued: queued))
        case let .file(rel, outcome)?:
            switch outcome {
            case let .analysed(s): runLines.append(Words.lineRead(rel, seconds: s))
            case .reused: runLines.append(Words.lineReadBefore(rel))
            case let .failed(f): runLines.append(Words.lineNotRead(rel, reason: f.reason))
            }
        case nil: break
        }
        if runLines.count > 400 { runLines.removeFirst(runLines.count - 400) }
    }

    // MARK: edits, saved as they go, with undo

    /// What one undo step puts back.
    private struct State {
        var crate: Crate?
        var corrections: NameCorrections
        var placePaths: PlacePaths
        var info: CrateInfo?
    }
    private var state: State { State(crate: crate, corrections: corrections, placePaths: placePaths, info: current) }

    private func restore(_ s: State, name: String) {
        let now = state
        crate = s.crate; corrections = s.corrections; placePaths = s.placePaths
        if let i = s.info, i.id == current?.id { current = i }
        scheduleSave()
        undoManager?.registerUndo(withTarget: self) { m in MainActor.assumeIsolated { m.restore(now, name: name) } }
        undoManager?.setActionName(name)
    }

    /// Makes a change as one undo step, and saves it.
    private func change(_ name: String, _ body: () -> Void) {
        let before = state
        body()
        guard crate != before.crate || current != before.info else { return }
        undoManager?.registerUndo(withTarget: self) { m in MainActor.assumeIsolated { m.restore(before, name: name) } }
        undoManager?.setActionName(name)
        scheduleSave()
    }

    func binding(for id: String) -> CrateTrack? { crate?.tracks.first { $0.id == id } }

    /// The other entries of the same recording as `t` (the same `cut_key`), in crate order.
    func copies(of t: CrateTrack) -> [CrateTrack] {
        let k = t.recordingKey
        return crate?.tracks.filter { $0.id != t.id && $0.recordingKey == k } ?? []
    }

    /// A name fix: kept as a correction, so reading the song again keeps it.
    func update(_ id: String, _ edit: (inout CrateTrack) -> Void) {
        guard let i = crate?.tracks.firstIndex(where: { $0.id == id }) else { return }
        change(Words.undoNameFix) {
            let before = crate!.tracks[i]
            var t = before
            edit(&t)
            guard t != before else { return }
            t.ident.source = "user"
            crate!.tracks[i] = t
            corrections.note(before: before, after: t)
        }
    }

    /// A change to the whole crate (the source and folder corrections in DeckieCrate).
    func updateCrate(_ name: String, _ edit: (inout Crate) -> Void) {
        guard crate != nil else { return }
        change(name) { edit(&crate!) }
    }

    /// Takes a source (or the music folder, nil) out of the crate after the window asked; undo puts it back.
    func removeSource(_ source: String?) {
        guard crate != nil else { return }
        change(Words.undoRemove) {
            crate!.removeSource(source)
            placePaths.forget(source: source)
            placePaths.fillMissingPaths(&crate!)
            if let s = source { current?.sourceRoots[s] = nil } else { current?.musicFolder = nil }
        }
        sourceSelection = nil
    }

    /// Corrects a source's name (D26), everywhere Desk keeps it: the crate, where it was read from, its paths.
    func renameSource(_ name: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != name, crate != nil else { return }
        change(Words.undoRename) {
            crate!.renameDisc(name, to: n)
            if let p = current?.sourceRoots.removeValue(forKey: name) { current?.sourceRoots[n] = p }
            placePaths.renameSource(name, to: n)
        }
        sourceSelection = .source(n)
    }

    private func scheduleSave() {
        needsSave = true
        saveTask?.cancel()
        saveTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes what changed: the crate file, the fixes, the paths, the crate's details.
    func saveNow() {
        saveTask?.cancel(); saveTask = nil
        guard needsSave, let info = current else { return }
        needsSave = false
        do {
            if let c = crate { try CrateWriter.write(c, to: shelf.package(info.id)) }
            try corrections.save(to: shelf.file(DeskRun.correctionsFile, of: info.id))
            try placePaths.save(to: shelf.file(DeskRun.placesFile, of: info.id))
            try shelf.save(info)
        } catch { errorText = Words.couldntSave(error.localizedDescription) }
    }

    // MARK: keys and names already on this Mac (D30)

    /// "Look again for keys and names": the files' tags, the DJ libraries and the rest read again for the crate
    /// showing, without reading its music again. One undo step.
    func lookAgain() {
        guard let info = current, crate != nil, !running else { return }
        saveNow()
        let home = self.home
        Task.detached(priority: .userInitiated) {
            let result = Result { try DeskLocalFacts.lookAgain(home: home, crateId: info.id) }
            await MainActor.run {
                switch result {
                case .success(let (c, summary)):
                    self.change(Words.undoLookAgain) { self.crate = c }
                    self.errorText = Words.lookedAgain(LocalLines.lines(summary))
                case .failure(let error):
                    self.errorText = Words.runStopped(error.localizedDescription)
                }
            }
        }
    }

    /// A DJ library chosen by hand, read on every run from now on.
    func chooseLibrary() {
        let p = NSOpenPanel()
        p.canChooseDirectories = false; p.canChooseFiles = true; p.allowsMultipleSelection = false
        p.treatsFilePackagesAsDirectories = true
        p.message = Words.chooseLibraryMessage
        p.begin { [weak self] r in
            guard r == .OK, let url = p.url, let self else { return }
            do {
                var choices = DJLibraryChoices.load(self.home)
                let program = try choices.add(url)
                try choices.save(self.home)
                self.errorText = Words.libraryChosen(program.rawValue)
            } catch { self.errorText = Words.couldntReadLibrary(error.localizedDescription) }
        }
    }

    // MARK: the music on this Mac

    /// Where a song's file is on this Mac: each place it was read at, in turn, the first whose source is plugged in.
    func audioURL(for t: CrateTrack) -> URL? { placePaths.locate(t, roots: roots, musicFolder: musicFolder) }

    func chooseMusicFolder() {
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false
        p.message = Words.musicFolderMessage
        p.begin { [weak self] r in
            guard r == .OK, let url = p.url, let self, self.current != nil else { return }
            self.current?.musicFolder = url.path
            self.needsSave = true
            self.saveNow()
        }
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

/// The Mac's share sheet, shown at the top right of the window.
enum Share {
    @MainActor static func show(_ url: URL) {
        guard let w = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }), let v = w.contentView else { return }
        let picker = NSSharingServicePicker(items: [url])
        let y = v.isFlipped ? 1 : v.bounds.maxY - 1
        picker.show(relativeTo: NSRect(x: v.bounds.maxX - 140, y: y, width: 1, height: 1), of: v, preferredEdge: .minY)
    }
}
