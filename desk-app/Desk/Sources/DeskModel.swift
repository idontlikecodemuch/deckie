import Foundation
import AppKit
import UniformTypeIdentifiers
import DeckieCrate
import DeckieBuild
import DeckieEngine
import DeckieCore
import DeckieDesk
import DeckieDisc
import DeckieLookup
import AVFoundation

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
    /// Where each name was read from, field by field, and each song's release (research AA; `names.json`).
    @Published private(set) var book = NameBook()
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
    /// The music CDs in this Mac's drives (research AA), offered beside drives and folders.
    @Published var musicCDs: [MusicCDs.Found] = []

    // Naming (research AA): a batch tool's sheet, the line after a batch, a music CD's name asked during its run, and
    // Listen.
    @Published var tool: String?
    /// Text a tool's sheet starts with (the naming walk).
    var toolPrefill: String?
    @Published var undoLine: String?
    @Published var discAsk: String?
    @Published var discAnswer = ""
    private var discName: (source: String, name: String)?
    let listener = Listener()
    private var watchers: [NSObjectProtocol] = []

    // "Look up songs via MusicBrainz" (D36; Lookup.swift): its sheet, "What Desk has sent", the lookup going.
    @Published var lookup: LookupSheetState?
    @Published var showSent = false
    /// Whether the one-song sentence has been shown once (kept in Desk's storage with the sent list).
    @Published var lookupExplained = false
    let lookupClient = DeskLookup.client()
    var lookupRun: DeskLookupRun?
    /// One lock for every write to the sent list (the lookup's thread writes it).
    let sentLock = NSLock()

    /// The window's undo manager, given by the window (ContentView).
    weak var undoManager: UndoManager?
    private var saveTask: Task<Void, Never>?
    private var needsSave = false

    init() {
        DiscReading.clearLeftovers(home)
        mountedSources = MountedSource.all()
        musicCDs = MusicCDs.list()
        listener.onSong = { [weak self] in self?.objectWillChange.send() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification, NSWorkspace.didRenameVolumeNotification] {
            watchers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.mountedSources = MountedSource.all(); self?.musicCDs = MusicCDs.list() }
            })
        }
        watchers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil,
                                                               queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        })
        reloadCrates()
        lookupExplained = LookupLog.load(home).explained
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
        book = NameBook.load(from: shelf.file(DeskRun.namesFile, of: info.id))
        pending = DeskRun.pending(home: home, crateId: info.id)
        listener.stop(); undoLine = nil
        selection = []; sourceSelection = nil; finished = nil; onlyNeedName = false
        reloadCrates()
    }

    func show(named name: String) { if let i = crates.first(where: { $0.name == name }) { show(i) } }

    /// "New crate": the first screen; the crate is made, named after what is read, when music is added.
    func newCrate() {
        saveNow()
        undoManager?.removeAllActions()
        current = nil; crate = nil; pending = nil; finished = nil; selection = []; sourceSelection = nil
        book = NameBook(); listener.stop(); undoLine = nil
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
        start(RunRequest(folder: url, source: current?.sourceName(name, root: url) ?? name))
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

    /// The rekordbox route, where it was: a collection export, then the folder of music, read as a source named after
    /// that folder like any folder added (D31), with the names, tempos, keys and cues from rekordbox.
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
                let name = MountedSource.name(of: folder)
                let source = self.current?.sourceName(name, root: folder) ?? name
                self.start(RunRequest(folder: folder, source: source, rekordbox: xml))
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
        listener.stop()
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
                    model.applyDiscName()
                }
            } catch {
                await MainActor.run {
                    model.running = false
                    model.reloadCrates()
                    if let i = model.crates.first(where: { $0.id == info.id }) { model.show(i) }
                    model.applyDiscName()
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
        case let .discDamaged(number, _)?:
            runLines.append(Words.t("lineDiscDamaged", ["number": "\(number)"]))
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
        var book: NameBook
    }
    private var state: State { State(crate: crate, corrections: corrections, placePaths: placePaths, info: current, book: book) }

    private func restore(_ s: State, name: String) {
        let now = state
        crate = s.crate; corrections = s.corrections; placePaths = s.placePaths; book = s.book
        if let i = s.info, i.id == current?.id { current = i }
        scheduleSave()
        undoManager?.registerUndo(withTarget: self) { m in MainActor.assumeIsolated { m.restore(now, name: name) } }
        undoManager?.setActionName(name)
    }

    /// Makes a change as one undo step, and saves it.
    private func change(_ name: String, _ body: () -> Void) {
        let before = state
        body()
        guard crate != before.crate || current != before.info || corrections != before.corrections else { return }
        undoManager?.registerUndo(withTarget: self) { m in MainActor.assumeIsolated { m.restore(before, name: name) } }
        undoManager?.setActionName(name)
        scheduleSave()
    }

    /// A lookup's apply as one undo step (Lookup.swift): the crate, the corrections and the book, changed together.
    func changeForLookup(_ name: String, _ body: (inout Crate, inout NameCorrections, inout NameBook) -> Void) {
        guard crate != nil else { return }
        change(name) { body(&crate!, &corrections, &book) }
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
            book.keep(before)
            var t = before
            edit(&t)
            guard t != before else { return }
            t.ident.source = "user"
            crate!.tracks[i] = t
            corrections.note(before: before, after: t)
        }
    }

    /// A song's facts as the DJ gives them (D34): kept beside the name fixes, so reading the song again keeps them; the
    /// name stays where it came from.
    func setFacts(_ id: String, _ given: [String: String]) {
        guard let i = crate?.tracks.firstIndex(where: { $0.id == id }) else { return }
        change(Words.undoNameFix) {
            var t = crate!.tracks[i]
            if DeskNaming.fixFacts(&t, given, corrections: &corrections) { crate!.tracks[i] = t }
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
            if let s = source { current?.forget(source: s) } else { current?.musicFolder = nil }
        }
        sourceSelection = nil
        saveNow()
    }

    /// Corrects a source's name (D26), everywhere Desk keeps it: the crate, where it was read from, its paths.
    func renameSource(_ name: String, to new: String) {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != name, crate != nil else { return }
        change(Words.undoRename) {
            crate!.renameDisc(name, to: n)
            current?.renameSource(name, to: n)
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
            try book.save(to: shelf.file(DeskRun.namesFile, of: info.id))
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
                    let read = NameBook.load(from: self.shelf.file(DeskRun.namesFile, of: info.id))
                    self.change(Words.undoLookAgain) { self.crate = c; self.book = read }
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

    // MARK: naming a song (research AA, route A; the logic is DeckieDesk's DeskNaming)

    func facts(_ t: CrateTrack) -> DeskNaming.Facts { DeskNaming.facts(t, book: book, corrections: corrections) }
    func reason(_ t: CrateTrack) -> String? { DeskNaming.reason(t, facts(t)) }
    var needingNames: [CrateTrack] { crate?.tracks.filter { reason($0) != nil } ?? [] }

    func toolSongs(source: String?, ids: [String]?) -> [DeskNaming.Song] {
        guard let c = crate else { return [] }
        return DeskNaming.order(c, source: source, ids: ids).map { DeskNaming.Song(track: $0, facts: facts($0)) }
    }

    /// A tool's preview: `paste`, `pattern`, `playlist` (a file the DJ chose) or `check`.
    func preview(_ kind: String, source: String?, text: String = "", pattern: String = "", playlist: URL? = nil,
                 onlyEmpty: Bool = true) -> DeskNaming.Preview {
        let songs = toolSongs(source: source, ids: nil)
        switch kind {
        case "paste": return DeskNaming.pasteList(text, songs: songs, onlyEmpty: onlyEmpty)
        case "pattern": return DeskNaming.fromFileNames(pattern: pattern.isEmpty ? DeskNaming.patterns[0] : pattern, songs: songs, onlyEmpty: onlyEmpty)
        case "playlist":
            guard let playlist, let data = try? Data(contentsOf: playlist) else {
                return DeskNaming.fromPlaylist([], songs: songs, onlyEmpty: onlyEmpty)
            }
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            return DeskNaming.fromPlaylist(DeskNaming.readPlaylist(text), songs: songs, onlyEmpty: onlyEmpty)
        default: return DeskNaming.looksRight(songs: songs)
        }
    }

    /// Applies a preview's ticked changes as one undo step.
    func apply(_ p: DeskNaming.Preview, ticks: Set<Int>) {
        guard crate != nil, p.problem == nil else { return }
        var n = 0
        change(p.tool == "check" ? Words.t("undoCheck") : Words.t("undoNames")) {
            for t in crate!.tracks where p.changes.contains(where: { $0.song == t.id }) { book.keep(t) }
            n = DeskNaming.apply(p, ticks: ticks, to: &crate!, corrections: &corrections)
        }
        if n > 0 { undoLine = p.tool == "check" ? Words.c("namesChecked", n) : Words.c("namesAdded", n) }
    }

    /// "Looks right" on songs, or Return on one guessed field: Desk's guesses become the DJ's, unchanged.
    func check(_ ids: [String], field: String? = nil) {
        var p = DeskNaming.looksRight(songs: toolSongs(source: nil, ids: ids))
        if let field { p.changes = p.changes.filter { $0.field == field } }
        guard !p.changes.isEmpty else { return }
        apply(p, ticks: Set(p.changes.indices))
    }

    /// A split of what the DJ typed into the title: artist, title and version, as the DJ's.
    func applySplit(_ id: String, artist: String?, title: String, version: String?) {
        update(id) { t in
            t.ident.title = title
            if let artist { t.ident.artist = artist }
            if let version { t.ident.version = version }
        }
        var given: [(String, String)] = [("title", title)]
        if let artist { given.append(("artist", artist)) }
        if let version { given.append(("version", version)) }
        for (f, v) in given where corrections.byId[id]?.from?[f] == nil { corrections.give(id, field: f, value: v, how: "user") }
        scheduleSave()
    }

    // MARK: a music CD (research AA)

    func addMusicCD(_ cd: MusicCDs.Found) {
        do {
            let (request, ask) = try DeskSession.musicCDRequest(cd.location, home: home, current: current)
            discAsk = ask; discAnswer = ask ?? ""
            start(request)
        } catch { errorText = Words.runStopped(error.localizedDescription) }
    }

    /// The name written on the disc, given while its run goes on; applied when the run ends.
    func nameDisc() {
        guard let source = discAsk else { return }
        let n = discAnswer.trimmingCharacters(in: .whitespaces)
        discAsk = nil
        guard !n.isEmpty, n != source else { return }
        if running { discName = (source, n) } else { renameDisc(source, to: n) }
    }

    func applyDiscName() {
        discAsk = nil
        guard let (source, name) = discName else { return }
        discName = nil
        renameDisc(source, to: name)
    }

    private func renameDisc(_ source: String, to name: String) {
        renameSource(source, to: name)
        sourceSelection = nil
        if let c = current, c.name == source { rename(c, to: name) }
        if var f = finished, f.read == source { f.read = name; if f.crate == source { f.crate = name }; finished = f }
    }

    // MARK: Listen (D33)

    /// Plays a song from a third of the way in, from where it is: its file on a drive or folder, or on a music CD in
    /// the drive (the system's own file on the disc; nothing is copied). Says which source to put back when it is not
    /// here.
    func listen(_ t: CrateTrack) {
        do {
            switch try DeskAudio.find(t, info: current, paths: placePaths) {
            case let .file(url):
                listener.play(url, id: t.id, title: t.ident.title, start: DeskListen.start(t.file.durationS))
            case .disc:
                // Only a stand-in drive (DECKIE_DESK_MUSIC_CD) gives a disc read by sector on a Mac.
                errorText = Words.t("listenCouldntPlay", ["title": t.ident.title, "detail": ""])
            }
        } catch let e as DeskAudio.NotHere {
            errorText = Words.t("listenPutBack", ["source": e.source])
        } catch {
            errorText = Words.t("listenCouldntPlay", ["title": t.ident.title, "detail": error.localizedDescription])
        }
    }

    /// Plays the song, or pauses or plays again the one playing: the play button on each row of the table.
    func playOrPause(_ t: CrateTrack) {
        if listener.song == t.id { listener.toggle() } else { listen(t) }
    }

    // MARK: the music on this Mac

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
                  v.volumeIsRemovable == true || v.volumeIsEjectable == true || v.volumeIsInternal == false,
                  !MusicCDs.isMacMusicCD(u) else { return nil }   // a music CD is offered as one
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

/// Listen (D33): the system's player for one song at a time, with its position and length for the scrub bar. It
/// stops when another song starts, when the panel closes, and when a run starts.
@MainActor
final class Listener: ObservableObject {
    /// The song playing (or paused); a change tells the window (the position's ticks do not, so the table is not
    /// redrawn for them).
    @Published private(set) var song: String? { didSet { if song != oldValue { onSong?() } } }
    var onSong: (() -> Void)?
    @Published private(set) var title = ""
    @Published private(set) var position: Double = 0
    @Published private(set) var length: Double = 0
    /// Whether it is playing now; a change tells the window too (the row's play button shows pause).
    @Published private(set) var playing = false { didSet { if playing != oldValue { onSong?() } } }
    private var player: AVPlayer?
    private var observer: Any?

    func play(_ url: URL, id: String, title: String, start: Double) {
        stop()
        let p = AVPlayer(url: url)
        player = p; song = id; self.title = title; position = start
        observer = p.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, let item = self.player?.currentItem else { return }
                self.position = t.seconds
                let d = item.duration.seconds
                if d.isFinite { self.length = d }
                self.playing = (self.player?.rate ?? 0) > 0
            }
        }
        p.seek(to: CMTime(seconds: start, preferredTimescale: 600))
        p.play()
        playing = true
    }

    func toggle() {
        guard let p = player else { return }
        if p.rate > 0 { p.pause(); playing = false } else { p.play(); playing = true }
    }

    func seek(_ seconds: Double) {
        position = max(0, length > 0 ? min(seconds, length) : seconds)
        player?.seek(to: CMTime(seconds: position, preferredTimescale: 600))
    }

    func stop() {
        if let o = observer { player?.removeTimeObserver(o) }
        observer = nil
        player?.pause(); player = nil
        song = nil; playing = false; position = 0; length = 0
    }
}
