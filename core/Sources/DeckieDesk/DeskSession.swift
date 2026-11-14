import Foundation
import DeckieCrate
import DeckieBuild

/// What a desk's window works on, with no window (D32): the crate showing (one of the crates the desk keeps, D28), its
/// name fixes and remembered paths, a run that stopped, and the edits the DJ makes, each one step of undo and saved at
/// once. The Windows and Linux engine program (`deckie-desk-engine`) drives Desk through this; the Mac's window
/// (`desk-app/`, DeskModel) does the same things with the system's undo manager, and can move onto this.
///
/// Not thread-safe: one caller at a time (the engine program's loop holds it behind a lock).
public final class DeskSession {
    public let home: DeskHome
    public var shelf: CrateShelf { home.shelf }

    /// The crate showing, or nil for the first screen (a new crate, made when music is added).
    public private(set) var current: CrateInfo?
    /// Its crate file as Desk keeps it; nil until music has been added.
    public private(set) var crate: Crate?
    public private(set) var corrections = NameCorrections()
    public private(set) var placePaths = PlacePaths()
    /// A run of the crate showing that stopped before it finished.
    public private(set) var pending: RunRequest?

    /// One step of undo: what it puts back, and its name (a word's name in `DeskWords`, as "undoNameFix").
    struct Snapshot {
        var crate: Crate?
        var corrections: NameCorrections
        var placePaths: PlacePaths
        var info: CrateInfo?
    }
    private var undoSteps: [(name: String, state: Snapshot)] = []
    private var redoSteps: [(name: String, state: Snapshot)] = []
    /// The name of the step Undo would take back, and of the one Redo would put again (word names), or nil.
    public var undoName: String? { undoSteps.last?.name }
    public var redoName: String? { redoSteps.last?.name }

    /// Opens on the crate opened most recently, or the first screen when there is none.
    public init(home: DeskHome) {
        self.home = home
        if let first = shelf.list().first { show(first.id) }
    }

    public var crates: [CrateInfo] { shelf.list() }

    // MARK: the crates

    /// Shows a crate: its crate file, fixes and paths. Undo starts afresh.
    @discardableResult
    public func show(_ id: String) -> Bool {
        guard let info = shelf.info(id) else { return false }
        current = (try? shelf.touch(id)) ?? info
        let pkg = shelf.package(id)
        crate = FileManager.default.fileExists(atPath: pkg.appendingPathComponent(CrateFormat.manifestFile).path)
            ? (try? CrateReader.read(from: pkg)) : nil
        corrections = NameCorrections.load(from: shelf.file(DeskRun.correctionsFile, of: id))
        placePaths = PlacePaths.load(from: shelf.file(DeskRun.placesFile, of: id))
        pending = DeskRun.pending(home: home, crateId: id)
        undoSteps = []; redoSteps = []
        return true
    }

    /// The first screen: the crate is made, named after what is read, when music is added.
    public func newCrate() {
        current = nil; crate = nil; pending = nil
        corrections = NameCorrections(); placePaths = PlacePaths()
        undoSteps = []; redoSteps = []
    }

    public func rename(_ id: String, to name: String) throws {
        let i = try shelf.rename(id, to: name)
        if current?.id == i.id {
            current = i
            crate?.manifest.name = i.name
        }
    }

    /// Deletes a crate for good (its folder in the desk's storage; the music and any crate file sent are not
    /// touched), then shows the next most recent crate, or the first screen.
    public func delete(_ id: String) throws {
        try shelf.delete(id)
        if current?.id == id {
            if let next = shelf.list().first { show(next.id) } else { newCrate() }
        }
    }

    /// Brings in a crate file made elsewhere as a new crate, and shows it.
    public func importCrate(_ url: URL) throws {
        let info = try shelf.importCopy(of: url)
        show(info.id)
    }

    // MARK: Add music: the request for the one run

    /// What Add music reads for a CD, a drive or a folder at `url` (D31: whatever is added is a source, named after the
    /// drive or the top folder chosen): a source named `name` when given (a drive's own name), else after the drive
    /// when `url` is the top of one, else after the folder; made unique among the crate's sources.
    public func addRequest(_ url: URL, name: String? = nil) -> RunRequest {
        let base = name ?? DeskDrives.sourceName(of: url)
        let unique = SourceNaming.unique(base, root: url, roots: current?.roots ?? [:])
        return RunRequest(folder: url, source: unique)
    }

    /// The crate a run goes into: the one showing, else a new one named after what is read (made now).
    public func crateForRun(_ request: RunRequest) throws -> CrateInfo {
        if let c = current { return c }
        let info = try shelf.make(name: request.name)
        current = info
        return info
    }

    /// After a run of crate `id` (finished or stopped): shows it again as saved.
    public func runEnded(_ id: String) {
        _ = show(id)
    }

    // MARK: edits, each one step of undo, saved at once

    private var snapshot: Snapshot { Snapshot(crate: crate, corrections: corrections, placePaths: placePaths, info: current) }

    private func restore(_ s: Snapshot) throws {
        crate = s.crate; corrections = s.corrections; placePaths = s.placePaths
        if let i = s.info, i.id == current?.id { current = i }
        try save()
    }

    /// Makes a change as one step of undo, and saves it; nothing is recorded when nothing changed.
    private func change(_ name: String, _ body: () -> Void) throws {
        let before = snapshot
        body()
        guard crate != before.crate || current != before.info else { return }
        undoSteps.append((name, before))
        redoSteps = []
        try save()
    }

    public func undo() throws {
        guard let step = undoSteps.popLast() else { return }
        redoSteps.append((step.name, snapshot))
        try restore(step.state)
    }

    public func redo() throws {
        guard let step = redoSteps.popLast() else { return }
        undoSteps.append((step.name, snapshot))
        try restore(step.state)
    }

    /// A DJ's name fix to one song: each field given replaces the song's (an empty artist or version clears it); kept
    /// as a correction, so reading the song again keeps it.
    public func fixName(_ id: String, title: String? = nil, artist: String? = nil, version: String? = nil,
                        tags: [String]? = nil) throws {
        guard let i = crate?.tracks.firstIndex(where: { $0.id == id }) else { throw DeskError("no song \(id)") }
        try change("undoNameFix") {
            let before = crate!.tracks[i]
            var t = before
            if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { t.ident.title = title }
            if let artist { t.ident.artist = artist.isEmpty ? nil : artist }
            if let version { t.ident.version = version.isEmpty ? nil : version }
            if let tags { t.ident.tags = tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            guard t != before else { return }
            t.ident.source = "user"
            crate!.tracks[i] = t
            corrections.note(before: before, after: t)
        }
    }

    /// Corrects a source's name (D26) everywhere Desk keeps it: the crate, where it was read from, its paths.
    public func renameSource(_ name: String, to new: String) throws {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != name, crate != nil else { return }
        try change("undoRename") {
            crate!.renameDisc(name, to: n)
            if let p = current?.sourceRoots.removeValue(forKey: name) { current?.sourceRoots[n] = p }
            placePaths.renameSource(name, to: n)
        }
    }

    public func renameFolder(_ folder: String, inSource source: String, to new: String) throws {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != folder, crate != nil else { return }
        try change("undoRename") { crate!.renameFolder(folder, inDisc: source, to: n) }
    }

    /// Moves a song up (`by` -1) or down (+1) within one folder of a source; the folder is numbered again from 1.
    public func move(_ id: String, inSource source: String, folder: String, by step: Int) throws {
        guard let c = crate, let i = c.trackIds(disc: source, folder: folder).firstIndex(of: id) else { return }
        try change("undoMove") { crate!.move(id, inDisc: source, folder: folder, to: i + step) }
    }

    /// How many songs would leave the crate if `source` (nil: the music folder) were taken out.
    public func songsOnlyOn(_ source: String?) -> Int { crate?.entriesOnlyOn(source: source).count ?? 0 }

    /// Takes a source (or the music folder, nil) out of the crate; undo puts it back.
    public func removeSource(_ source: String?) throws {
        guard crate != nil else { return }
        try change("undoRemove") {
            crate!.removeSource(source)
            placePaths.forget(source: source)
            placePaths.fillMissingPaths(&crate!)
            if let s = source { current?.sourceRoots[s] = nil } else { current?.musicFolder = nil }
        }
    }

    /// "Look again for keys and names" (D30) for the crate showing, without reading its music again. One step of
    /// undo.
    public func lookAgain(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LocalFactsSummary {
        guard let info = current, crate != nil else { throw DeskError("no crate with songs is showing") }
        try save()
        let (c, summary) = try DeskLocalFacts.lookAgain(home: home, crateId: info.id, environment: environment)
        try change("undoLookAgain") { crate = c }
        return summary
    }

    /// A DJ library chosen by hand, read on every run from now on; its program.
    public func chooseLibrary(_ url: URL) throws -> DJProgram {
        var choices = DJLibraryChoices.load(home)
        let program = try choices.add(url)
        try choices.save(home)
        return program
    }

    /// Writes the crate showing: the crate file, the fixes, the paths, the crate's details.
    public func save() throws {
        guard let info = current else { return }
        if let c = crate { try CrateWriter.write(c, to: shelf.package(info.id)) }
        try corrections.save(to: shelf.file(DeskRun.correctionsFile, of: info.id))
        try placePaths.save(to: shelf.file(DeskRun.placesFile, of: info.id))
        try shelf.save(info)
    }

    // MARK: out

    /// The crate file written into `folder` under the crate's name; its path. This is the one place where Desk on
    /// Windows and Linux hands a crate file out: when the single-file form of a crate file is ready (being built on the
    /// branch pc/windows-builder), the export switches to it here.
    public func export(into folder: URL) throws -> URL {
        guard let info = current, crate != nil else { throw DeskError("the crate has no songs yet, so there is no crate file to write") }
        try save()
        let safe = info.name.map { "/\\:*?\"<>|".contains($0) ? "-" : $0 }
        let dest = folder.appendingPathComponent(String(safe) + "." + CrateFormat.packageExtension, isDirectory: true)
        try shelf.exportCopy(info.id, to: dest)
        return dest
    }
}
