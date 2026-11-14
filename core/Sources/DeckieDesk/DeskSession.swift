import Foundation
import DeckieCrate
import DeckieBuild
import DeckieDisc

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
    /// Where each name was read from, field by field, and each song's release (research AA; `names.json`).
    public private(set) var book = NameBook()
    /// A run of the crate showing that stopped before it finished.
    public private(set) var pending: RunRequest?

    /// One step of undo: what it puts back, and its name (a word's name in `DeskWords`, as "undoNameFix").
    struct Snapshot {
        var crate: Crate?
        var corrections: NameCorrections
        var placePaths: PlacePaths
        var info: CrateInfo?
        var book: NameBook
    }
    private var undoSteps: [(name: String, state: Snapshot)] = []
    private var redoSteps: [(name: String, state: Snapshot)] = []
    /// The name of the step Undo would take back, and of the one Redo would put again (word names), or nil.
    public var undoName: String? { undoSteps.last?.name }
    public var redoName: String? { redoSteps.last?.name }

    /// Opens on the crate opened most recently, or the first screen when there is none.
    public init(home: DeskHome) {
        self.home = home
        DiscReading.clearLeftovers(home)
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
        book = NameBook.load(from: shelf.file(DeskRun.namesFile, of: id))
        pending = DeskRun.pending(home: home, crateId: id)
        undoSteps = []; redoSteps = []
        return true
    }

    /// The first screen: the crate is made, named after what is read, when music is added.
    public func newCrate() {
        current = nil; crate = nil; pending = nil
        corrections = NameCorrections(); placePaths = PlacePaths(); book = NameBook()
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
        return RunRequest(folder: url, source: current?.sourceName(base, root: url) ?? base)
    }

    /// The crate a run goes into: the one showing, else a new one named after what is read (made now).
    public func crateForRun(_ request: RunRequest) throws -> CrateInfo {
        if let c = current { return c }
        let info = try shelf.make(name: request.name)
        current = info
        return info
    }

    /// After a run of crate `id` (finished or stopped): shows it again as saved, then gives a music CD the name the DJ
    /// typed for it while it was read (one step of undo).
    public func runEnded(_ id: String) {
        _ = show(id)
        if let (source, name) = discName, current?.id == id {
            discName = nil
            try? renameSource(source, to: name)
            // A crate made from this disc took the placeholder too: it follows.
            if let c = current, c.name == source { try? rename(c.id, to: name) }
        }
    }

    // MARK: Add music: a music CD (research AA)

    /// The name the DJ gave a music CD while its run went on: the source it was added as, and the new name.
    public private(set) var discName: (source: String, name: String)?

    /// What Add music reads for the music CD at `location` (as `MusicCDs.list` gave it): the table and CD-Text are read
    /// now (both quick) and noted in what Desk keeps about the disc (`DiscRecords`); the songs are read in the run, one
    /// at a time, and none is kept. The source is named after
    /// the disc's own title when CD-Text has one; otherwise `askName` is the placeholder ("Music CD, 14 songs, 71:12")
    /// the window offers when it asks, once, for the name written on the disc.
    public func addMusicCDRequest(_ location: String, open: (String) throws -> MusicCD = { try MusicCDs.open($0) }) throws
        -> (request: RunRequest, askName: String?) {
        try Self.musicCDRequest(location, home: home, current: current, open: open)
    }

    /// As `addMusicCDRequest`, for a window that keeps its own state (the Mac's): `current` is the crate showing.
    public static func musicCDRequest(_ location: String, home: DeskHome, current: CrateInfo?,
                                      open: (String) throws -> MusicCD = { try MusicCDs.open($0) }) throws
        -> (request: RunRequest, askName: String?) {
        let cd = try open(location)
        try home.prepare()
        let record = try DiscRecords.prepare(cd, home: home)
        let placeholder = Self.placeholderName(record.toc)
        let base = record.discTitle ?? placeholder
        // The same disc already a source of this crate keeps its name; another never takes a name in use.
        let existing = current?.discs.first { $0.value == record.toc.id }?.key
        let names = Set(current.map { Array($0.sourceRoots.keys) } ?? [])
        let unique = existing ?? SourceNaming.unique(base, root: URL(fileURLWithPath: "/"), roots: [:], taken: names)
        let request = RunRequest(folder: URL(fileURLWithPath: cd.location), source: unique, musicCD: cd.location,
                                 discId: record.toc.id)
        return (request, record.discTitle == nil && existing == nil ? unique : nil)
    }

    /// "Music CD, 14 songs, 71:12": a disc's name until the DJ gives one (letter AA, 2.6).
    public static func placeholderName(_ toc: DiscTOC) -> String {
        let secs = Int(toc.audioSeconds.rounded())
        return DeskWords.count("musicCDPlaceholder", toc.songs.count, ["length": "\(secs / 60):" + String(format: "%02d", secs % 60)])
    }

    /// The name written on the disc, given while its run goes on (or after: then it is a rename now).
    public func nameDisc(source: String, to name: String, running: Bool) throws {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != source else { return }
        if running { discName = (source, n) } else { try renameSource(source, to: n) }
    }

    // MARK: edits, each one step of undo, saved at once

    private var snapshot: Snapshot { Snapshot(crate: crate, corrections: corrections, placePaths: placePaths, info: current, book: book) }

    private func restore(_ s: Snapshot) throws {
        crate = s.crate; corrections = s.corrections; placePaths = s.placePaths; book = s.book
        if let i = s.info, i.id == current?.id { current = i }
        try save()
    }

    /// Makes a change as one step of undo, and saves it; nothing is recorded when nothing changed.
    private func change(_ name: String, _ body: () -> Void) throws {
        let before = snapshot
        body()
        guard crate != before.crate || current != before.info || corrections != before.corrections else { return }
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
            book.keep(before)
            var t = before
            if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty { t.ident.title = title }
            if let artist { t.ident.artist = artist.isEmpty ? nil : artist }
            if let version { t.ident.version = version.isEmpty ? nil : version }
            if let tags { t.ident.tags = tags.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
            if t != before {
                t.ident.source = "user"
                crate!.tracks[i] = t
                corrections.note(before: before, after: t)
            }
            // A field the DJ gave as it already was (a split that kept the title, Return on a guess) is the DJ's too.
            for (field, given, now) in [("title", title, t.ident.title), ("artist", artist, t.ident.artist ?? ""),
                                        ("version", version, t.ident.version ?? "")]
                where given != nil && !given!.isEmpty && given == now && corrections.byId[id]?.from?[field] == nil {
                corrections.give(id, field: field, value: given, how: "user")
            }
        }
    }

    /// A DJ's facts for one song (D34): release, year, label, genre or any other known fact, by name, as text ("" clears
    /// one); kept as corrections beside the names, so reading the song again keeps them. One step of undo.
    public func fixFacts(_ id: String, _ given: [String: String]) throws {
        guard let i = crate?.tracks.firstIndex(where: { $0.id == id }) else { throw DeskError("no song \(id)") }
        guard !given.isEmpty else { return }
        try change("undoNameFix") {
            var t = crate!.tracks[i]
            if DeskNaming.fixFacts(&t, given, corrections: &corrections) { crate!.tracks[i] = t }
        }
    }

    /// Corrects a source's name (D26) everywhere Desk keeps it: the crate, where it was read from, its paths.
    public func renameSource(_ name: String, to new: String) throws {
        let n = new.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != name, crate != nil else { return }
        try change("undoRename") {
            crate!.renameDisc(name, to: n)
            current?.renameSource(name, to: n)
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
            if let s = source { current?.forget(source: s) } else { current?.musicFolder = nil }
        }
    }

    /// "Look again for keys and names" (D30) for the crate showing, without reading its music again. One step of
    /// undo.
    public func lookAgain(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LocalFactsSummary {
        guard let info = current, crate != nil else { throw DeskError("no crate with songs is showing") }
        try save()
        let (c, summary) = try DeskLocalFacts.lookAgain(home: home, crateId: info.id, environment: environment)
        let read = NameBook.load(from: shelf.file(DeskRun.namesFile, of: info.id))
        try change("undoLookAgain") { crate = c; book = read }
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
        try book.save(to: shelf.file(DeskRun.namesFile, of: info.id))
        try shelf.save(info)
    }

    // MARK: naming (research AA, route A)

    public func facts(_ t: CrateTrack) -> DeskNaming.Facts { DeskNaming.facts(t, book: book, corrections: corrections) }

    /// The table's rows, with each song's names and why it needs one.
    public var rows: [DeskSongRow] { crate?.tracks.map { DeskSongRow($0, facts: facts($0)) } ?? [] }

    /// The songs a batch tool works on: a source's songs in the order the player shows them, or the songs given.
    public func toolSongs(source: String?, ids: [String]?) -> [DeskNaming.Song] {
        guard let c = crate else { return [] }
        return DeskNaming.order(c, source: source, ids: ids).map { DeskNaming.Song(track: $0, facts: facts($0)) }
    }

    /// The last preview a tool made, until it is applied or another is made.
    public private(set) var preview: DeskNaming.Preview?

    /// A batch tool's preview (letter AA, 3.6): `tool` is `paste` (text), `pattern` (pattern), `playlist` (path of an
    /// .m3u or .m3u8 file, read only) or `check` (Looks right); it works on a source's songs or the songs given.
    public func makePreview(tool: String, source: String?, ids: [String]?, text: String? = nil, pattern: String? = nil,
                            playlist: URL? = nil, onlyEmpty: Bool = true) throws -> DeskNaming.Preview {
        let songs = toolSongs(source: source, ids: ids)
        let p: DeskNaming.Preview
        switch tool {
        case "paste": p = DeskNaming.pasteList(text ?? "", songs: songs, onlyEmpty: onlyEmpty)
        case "pattern": p = DeskNaming.fromFileNames(pattern: pattern ?? DeskNaming.patterns[0], songs: songs, onlyEmpty: onlyEmpty)
        case "playlist":
            guard let playlist else { throw DeskError("no playlist given") }
            let data = try Data(contentsOf: playlist)
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            p = DeskNaming.fromPlaylist(DeskNaming.readPlaylist(text), songs: songs, onlyEmpty: onlyEmpty)
        case "check": p = DeskNaming.looksRight(songs: songs)
        default: throw DeskError("no tool \(tool)")
        }
        preview = p
        return p
    }

    /// Applies the last preview with the ticks given (indexes into its changes; nil: its own ticks), as one step of
    /// undo. Returns how many songs changed.
    @discardableResult
    public func applyPreview(ticks: Set<Int>?) throws -> Int {
        guard let p = preview, crate != nil else { throw DeskError("there is nothing to apply") }
        guard p.problem == nil else { throw DeskError("the list does not match the songs yet") }
        var n = 0
        try change(p.tool == "check" ? "undoCheck" : "undoNames") {
            for t in crate!.tracks where p.changes.contains(where: { $0.song == t.id }) { book.keep(t) }
            n = DeskNaming.apply(p, ticks: ticks, to: &crate!, corrections: &corrections)
        }
        preview = nil
        return n
    }

    /// "Looks right" on songs, or Return on one guessed field (`field`): Desk's guesses become the DJ's, unchanged.
    @discardableResult
    public func check(_ ids: [String], field: String? = nil) throws -> Int {
        var p = DeskNaming.looksRight(songs: toolSongs(source: nil, ids: ids))
        if let field { p.changes = p.changes.filter { $0.field == field } }
        guard !p.changes.isEmpty, crate != nil else { return 0 }
        var n = 0
        try change("undoCheck") {
            for t in crate!.tracks where ids.contains(t.id) { book.keep(t) }
            n = DeskNaming.apply(p, to: &crate!, corrections: &corrections)
        }
        return n
    }

    // MARK: Listen (D33)

    /// A song's sound to play: the first of its places whose source is here, a file on a drive or folder, or the song
    /// on a music CD in a drive (read off it when asked; nothing is copied). Throws `DeskAudio.NotHere` with the
    /// source's name when none is (so the window can say "Put Friday night back in to listen").
    public func audio(_ id: String, open: (String) throws -> MusicCD = { try MusicCDs.open($0) },
                      musicCDs: () -> [MusicCDs.Found] = { MusicCDs.list() }) throws -> DeskAudio.Sound {
        guard let t = crate?.tracks.first(where: { $0.id == id }) else { throw DeskError("no song \(id)") }
        return try DeskAudio.find(t, info: current, paths: placePaths, open: open, musicCDs: musicCDs)
    }

    // MARK: covers (D36)

    /// A song's cover for the window to show: the bytes of `covers/<hash>.jpg` in the crate file Desk keeps, or nil
    /// when there is none to show (no such song, a song without a cover, a file that is gone, too large or not a
    /// JPEG). The hash is the record's own and is checked before it names a file, so nothing a window sends can
    /// reach any other file; a cover that cannot be read is no cover, never an error, because a missing picture
    /// must not stop a DJ naming a song.
    public func cover(_ id: String) -> Data? {
        guard let info = current, let hash = crate?.tracks.first(where: { $0.id == id })?.file.cover,
              CrateIDs.isSHA256(hash) else { return nil }
        let file = shelf.package(info.id).appendingPathComponent(CrateFormat.coverPath(hash))
        // Only an ordinary file is read (a link in a crate file brought in from elsewhere could point anywhere), and
        // its size is asked first, so a file put there by mistake is never loaded whole.
        guard let facts = try? FileManager.default.attributesOfItem(atPath: file.path),
              facts[.type] as? FileAttributeType == .typeRegular,
              let size = facts[.size] as? NSNumber, size.intValue <= CrateFormat.coverMaxBytes,
              let data = try? Data(contentsOf: file), data.count <= CrateFormat.coverMaxBytes,
              data.starts(with: [0xFF, 0xD8, 0xFF]) else { return nil }
        return data
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
