import Foundation

/// Writes a crate in its canonical form (docs/architecture/crate-format.md, "How it is written"), so the same crate
/// always gives the same bytes. It checks the crate first and writes nothing when there is a problem.
public enum CrateWriter {
    /// The crate's files, by their path inside the package folder: `manifest.json`, `crate.json`, and a
    /// `bars/<id>.bin`, `style/<id>.bin` and `prints/<id>.dkl` for each track that has them. Signature files are not
    /// among them: they are made on an Apple device and only listed in the records.
    public static func encode(_ crate: Crate) throws -> [String: Data] {
        // Checked in the written order, so a problem's tracks[i] is the record a reader would see there.
        var crate = crate
        crate.tracks.sort { byteOrder($0.id, $1.id) }
        var problems = crate.problems()
        if crate.manifest.schema > CrateFormat.schema {
            problems.append(CrateProblem(file: CrateFormat.manifestFile, path: "schema", message:
                "the crate was written by a newer Deckie (format \(crate.manifest.schema)); this one writes format " +
                "\(CrateFormat.schema) and would drop fields it does not know, so it can read the crate but not rewrite it"))
        }
        if !problems.isEmpty { throw CrateError(problems) }

        let tracks = crate.tracks
        var files: [String: Data] = [:]
        guard case .object(var manifest) = try CanonicalJSON.tree(crate.manifest, decimals: CrateFormat.decimals)
        else { preconditionFailure("the manifest encodes as an object") }
        manifest["engines_used"] = .array(crate.enginesUsed.map(JSONValue.string))
        files[CrateFormat.manifestFile] = Data(CanonicalJSON.text(.object(manifest)).utf8)
        var records: [JSONValue] = []
        for (i, t) in tracks.enumerated() {
            do {
                records.append(try CanonicalJSON.tree(t, decimals: CrateFormat.decimals))
            } catch let EncodingError.invalidValue(_, context) {
                let path = "tracks[\(i)]." + fieldPath(context.codingPath)
                throw CrateError([CrateProblem(file: CrateFormat.tracksFile, path: path, track: t.id,
                                               message: context.debugDescription)])
            }
        }
        files[CrateFormat.tracksFile] = Data(CanonicalJSON.text(.object(["tracks": .array(records)]),
                                                               linePerTopLevelItem: true).utf8)
        for t in tracks {
            if let bars = t.bars, let n = t.grid?.nBars { files[CrateFormat.barsPath(t.id)] = Sidecar.bars(bars, nBars: n) }
            if let style = t.style { files[CrateFormat.stylePath(t.id)] = Sidecar.style(style.values) }
            if let print = t.fingerprint { files[CrateFormat.printPath(t.id)] = print.data }
        }
        return files
    }

    /// Writes the crate into the package folder at `package` (made if missing): replaces `manifest.json`,
    /// `crate.json` and the sidecars of its tracks, deletes the `.bin` sidecars and the `.dkl` fingerprints of tracks
    /// no longer in it (or no longer with one), and the covers no song names any more, and leaves
    /// every other file alone (`prefs.json`, `history/`, `signatures/`, `catalog/`, ...). Each listed signature's
    /// file must already be in the package.
    ///
    /// A save that cannot tear (the review of Nov 21, 2026): a stop at any moment (the window closed, the program
    /// killed, the power cut) leaves the old crate or the new one, never a crate that will not open. How:
    ///
    /// 1. A file at a path the package does not have yet (a new song's sidecars) is written straight in: no record of
    ///    the old crate lists it, so the old crate still reads.
    /// 2. Every other change (`crate.json`, `manifest.json`, a sidecar replaced) is written whole into the save's
    ///    folder beside the package (`<package>.saving/files/`), then the save's list: those files, and the files to
    ///    delete (`saving.json`, written whole in one step). Until the list is there, the package is the old crate as
    ///    it was; a save stopped before it is undone at the next open (the save's folder deleted).
    /// 3. Once the list is there, the save is decided: its files are put in place (sidecars first, `manifest.json`
    ///    last), the files no longer wanted deleted, and the save's folder removed. A save stopped in this step is
    ///    finished at the next open (`finishInterruptedSave`), by the list, the same way: the package is the new crate.
    ///
    /// A file already as the new crate has it is not written again. The files a completed save leaves are the same,
    /// byte for byte, as before this was done; only how they get there changed.
    public static func write(_ crate: Crate, to package: URL) throws {
        let files = try encode(crate)
        let fm = FileManager.default
        var missing: [CrateProblem] = []
        for (i, t) in crate.tracks.sorted(by: { byteOrder($0.id, $1.id) }).enumerated() {
            for variant in t.signatures.keys.sorted(by: byteOrder) {
                let path = CrateFormat.signaturePath(t.id, variant)
                if !fm.fileExists(atPath: package.appendingPathComponent(path).path) {
                    missing.append(CrateProblem(file: CrateFormat.tracksFile, path: "tracks[\(i)].signatures.\(variant)",
                                                track: t.id, message: "\(path) is not in the package"))
                }
            }
            if let cover = t.file.cover, CrateIDs.isSHA256(cover),
               !fm.fileExists(atPath: package.appendingPathComponent(CrateFormat.coverPath(cover)).path) {
                missing.append(CrateProblem(file: CrateFormat.tracksFile, path: "tracks[\(i)].file.cover", track: t.id,
                                            message: "\(CrateFormat.coverPath(cover)) is not in the package"))
            }
        }
        if !missing.isEmpty { throw CrateError(missing) }

        saving.lock(); defer { saving.unlock() }
        try finishLocked(package)
        try DeckieFiles.createDirectory(package)
        // What goes, deleted last (step 3): the sidecars of tracks no longer in the crate (or no longer with one), and
        // covers no song names any more (taking the last song of a release out of a crate takes its cover out).
        var remove: [String] = []
        for (folder, ext) in [(CrateFormat.barsFolder, ".bin"), (CrateFormat.styleFolder, ".bin"),
                              (CrateFormat.printsFolder, ".dkl")] {
            let dir = package.appendingPathComponent(folder)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names.sorted() where name.hasSuffix(ext) && files["\(folder)/\(name)"] == nil {
                remove.append("\(folder)/\(name)")
            }
        }
        let covers = Set(crate.tracks.compactMap(\.file.cover))
        let coversDir = package.appendingPathComponent(CrateFormat.coversFolder)
        for name in ((try? fm.contentsOfDirectory(atPath: coversDir.path)) ?? []).sorted() where name.hasSuffix(".jpg") {
            if !covers.contains(String(name.dropLast(4))) { remove.append("\(CrateFormat.coversFolder)/\(name)") }
        }
        // What changes: a new path straight in (step 1), the rest through the save's folder (step 2). A first save
        // stopped early can leave new sidecars and no manifest: Desk takes that for a crate with no crate file yet,
        // and the builder for an empty package (`Builder.existingCrate`).
        var staged: [String] = []
        for path in placingOrder(files.keys) {
            let url = package.appendingPathComponent(path)
            if fm.fileExists(atPath: url.path) {
                if (try? Data(contentsOf: url)) == files[path] { continue }
                staged.append(path)
            } else if path == CrateFormat.manifestFile || path == CrateFormat.tracksFile {
                staged.append(path)
            } else {
                try DeckieFiles.write(files[path]!, to: url)
                try step(package, "wrote \(path)")
            }
        }
        if staged.isEmpty && remove.isEmpty { return }
        let folder = savingFolder(for: package)
        try DeckieFiles.remove(folder)
        let stagedRoot = folder.appendingPathComponent(stagedFolder, isDirectory: true)
        for path in staged {
            try DeckieFiles.write(files[path]!, to: stagedRoot.appendingPathComponent(path))
            try step(package, "staged \(path)")
        }
        let list = SaveList(place: staged, remove: remove,
                            sha256: Dictionary(uniqueKeysWithValues: staged.map { ($0, CrateIDs.sha256(of: files[$0]!)) }))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try DeckieFiles.write(try encoder.encode(list), to: folder.appendingPathComponent(listFile))
        try step(package, "decided")
        try finish(list, from: folder, into: package)
    }

    // MARK: the save's folder

    /// The folder a save is made in, beside the package: `<package>.saving` (`crate.deckie.saving`). It is there only
    /// while a save goes, or after one was stopped; the next write or read finishes or undoes it.
    public static func savingFolder(for package: URL) -> URL {
        let p = package.standardizedFileURL
        return p.deletingLastPathComponent().appendingPathComponent(p.lastPathComponent + savingExtension, isDirectory: true)
    }
    public static let savingExtension = ".saving"
    static let listFile = "saving.json"
    static let stagedFolder = "files"

    /// The save's list, written once every changed file is in the save's folder: the files to put in place, in that
    /// order, and the files to delete after.
    struct SaveList: Codable, Equatable {
        var format = 1
        var place: [String]
        var remove: [String]
        /// Each file's SHA-256, by its path: a file to put in place that is no longer in the save's folder counts as
        /// put in place only when the package's file has these bytes.
        var sha256: [String: String] = [:]
    }

    /// Saves, and the finishing of a stopped one, go one at a time in this program; a read waits for a save going
    /// (`CrateReader.read`), so it never sees one half done.
    static let saving = NSRecursiveLock()

    /// A stop injected by the tests after each step of a save (a file written, staged, the list written, a file put
    /// in place, a file deleted): throwing from it stops the save there, as a closed window or a kill would.
    nonisolated(unsafe) static var stepHook: ((URL, String) throws -> Void)?
    private static func step(_ package: URL, _ what: String) throws { try stepHook?(package, what) }

    /// Finishes or undoes a save to `package` that was stopped (`write`): when its list was written, its files are
    /// put in place and the files no longer wanted deleted, so the package is the new crate; when not, the save's
    /// folder is deleted and the package is the old crate, as it was. Nothing when there is none. `CrateReader.read`
    /// and `write` call it themselves; Desk calls it before it looks whether a crate has a crate file yet.
    public static func finishInterruptedSave(_ package: URL) throws {
        saving.lock(); defer { saving.unlock() }
        try finishLocked(package)
    }

    /// Whether a stopped save to `package` is waiting to be finished or undone.
    public static func hasInterruptedSave(_ package: URL) -> Bool {
        FileManager.default.fileExists(atPath: savingFolder(for: package).path)
    }

    /// Runs `body` with no save going in this program (a read of a crate file).
    static func withNoSaveGoing<T>(_ body: () throws -> T) rethrows -> T {
        saving.lock(); defer { saving.unlock() }
        return try body()
    }

    private static func finishLocked(_ package: URL) throws {
        let folder = savingFolder(for: package)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        let listURL = folder.appendingPathComponent(listFile)
        if FileManager.default.fileExists(atPath: listURL.path) {
            let data = try DeckieFiles.retrying("read", listURL.path) { try Data(contentsOf: listURL) }
            // The list is written whole in one step, so a list that is there and does not read was not written by a
            // save: nothing of it is trusted, and the folder goes as an undone save's does.
            if let list = try? JSONDecoder().decode(SaveList.self, from: data), list.format == 1,
               (list.place + list.remove).allSatisfy(isPackagePath) {
                try finish(list, from: folder, into: package)
                return
            }
        }
        try DeckieFiles.remove(folder)
        try step(package, "undone")
    }

    /// Step 3, the same for a save going and for one finished at the next open: each file still in the save's folder
    /// is put in place (written whole, then taken from the folder), the files no longer wanted deleted, the folder
    /// removed. Doing it again after a stop does what doing it once does.
    ///
    /// A file that is neither in the save's folder nor in the package with the bytes the list names means the save's
    /// folder is not what this save left (two programs at one crate at once: a window closed and opened again while
    /// the first engine still saved). Then nothing more is put in place and nothing deleted, so no file the package's
    /// own list of songs names goes; the folder is removed.
    private static func finish(_ list: SaveList, from folder: URL, into package: URL) throws {
        let fm = FileManager.default
        let staged = folder.appendingPathComponent(stagedFolder, isDirectory: true)
        for path in list.place {
            let from = staged.appendingPathComponent(path)
            guard fm.fileExists(atPath: from.path) else {
                // Put in place already, when the package has its bytes.
                let there = try? Data(contentsOf: package.appendingPathComponent(path))
                if let want = list.sha256[path], there.map(CrateIDs.sha256(of:)) != want {
                    try DeckieFiles.remove(folder)
                    try step(package, "abandoned")
                    return
                }
                continue
            }
            let data = try DeckieFiles.retrying("read", from.path) { try Data(contentsOf: from) }
            if let want = list.sha256[path], CrateIDs.sha256(of: data) != want {
                try DeckieFiles.remove(folder)
                try step(package, "abandoned")
                return
            }
            try DeckieFiles.write(data, to: package.appendingPathComponent(path))
            try step(package, "placed \(path)")
            try DeckieFiles.remove(from)
        }
        for path in list.remove {
            try DeckieFiles.remove(package.appendingPathComponent(path))
            try step(package, "deleted \(path)")
        }
        try DeckieFiles.remove(folder)
        try step(package, "finished")
    }

    /// The order files are put in place: sidecars first, then `crate.json`, then `manifest.json`, so the manifest,
    /// by which Desk knows a crate has a crate file, comes last.
    static func placingOrder<S: Sequence>(_ paths: S) -> [String] where S.Element == String {
        func rank(_ p: String) -> Int { p == CrateFormat.manifestFile ? 2 : p == CrateFormat.tracksFile ? 1 : 0 }
        return paths.sorted { rank($0) != rank($1) ? rank($0) < rank($1) : $0 < $1 }
    }

    /// A path a save's list may name: relative, inside the package, no part of it empty, `.` or `..`.
    static func isPackagePath(_ p: String) -> Bool {
        let parts = p.split(separator: "/", omittingEmptySubsequences: false)
        return !p.isEmpty && !p.contains("\\") && !p.contains(":")
            && parts.allSatisfy { !$0.isEmpty && $0 != ".." && $0 != "." }
    }
}
