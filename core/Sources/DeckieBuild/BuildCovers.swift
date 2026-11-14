import Foundation
import DeckieCovers
import DeckieCrate

/// What a build did about covers (D36), for a caller to report.
public struct CoverCounts: Codable, Equatable, Sendable {
    /// Songs in the crate file that have a cover.
    public var songs = 0
    /// Distinct covers: the files in the crate file's `covers/` that those songs name. Songs that share a picture
    /// share one.
    public var distinct = 0
    /// The bytes of those cover files together.
    public var bytes = 0
    /// Pictures found that could not be made into a cover, by reason (`CoverCounts.Reason`), each distinct picture
    /// once. Their songs are in the crate file without a cover.
    public var unusable: [String: Int] = [:]
    /// Thumbnails made in this run; a second run over unchanged files makes none.
    public var made = 0
    /// Pictures read in this run, from a file's tags or from beside it; a second run over unchanged files reads none.
    public var picturesRead = 0

    public init() {}

    /// Why a picture gave no cover, as `Cover.Failure` names them.
    public enum Reason {
        /// Damaged, cut short, or not a JPEG or PNG.
        public static let unreadable = "unreadable"
        /// More bytes or more pixels than a cover's source may have.
        public static let tooLarge = "too_large"
        /// No thumbnail small enough could be made of it.
        public static let tooDetailed = "too_detailed"
        public static let all = [unreadable, tooLarge, tooDetailed]
        /// The thumbnail was made but could not be kept in the work folder: no cover in this run, and the picture is
        /// tried again in the next (this reason is never remembered against a file).
        public static let notKept = "not_kept"

        static func of(_ failure: Cover.Failure) -> String {
            switch failure {
            case .unreadable: return unreadable
            case .tooLarge: return tooLarge
            case .tooDetailed: return tooDetailed
            }
        }
    }

    enum CodingKeys: String, CodingKey { case songs, distinct, bytes, unusable, made, picturesRead = "pictures_read" }

    /// The command-line summary's line about covers.
    public var summaryLine: String {
        var s = "covers: "
        if songs == 0 { s += "no song has one" } else {
            s += "\(songs) song\(songs == 1 ? "" : "s") with a cover, \(distinct) distinct picture\(distinct == 1 ? "" : "s"), "
                + "\(bytes) bytes in the crate (\(made) made in this run)"
        }
        let bad = unusable.values.reduce(0, +)
        if bad > 0 {
            let known = Reason.all
            let list = (known + unusable.keys.sorted().filter { !known.contains($0) }).compactMap { r in
                unusable[r].map { "\(r) \($0)" }
            }
            s += "; \(bad) picture\(bad == 1 ? "" : "s") not usable (\(list.joined(separator: ", ")))"
        }
        return s
    }
}

/// What the work folder remembers about one file's cover (`WorkStore.FileLine.cover`), so a second run restores the
/// cover without reading the music file or making the thumbnail again. A line without it was written before covers
/// (or by a run stopped before it got there): its file is looked at once, for its picture only.
struct CoverNote: Codable, Equatable {
    /// Where the picture was found: `tag` (in the file), `beside` (a picture file in its folder), or `none`.
    var from: String
    /// The SHA-256 of the picture's bytes; nil when there is none, or when it was too large to be read.
    var picture: String?
    /// Why the picture gave no cover (`CoverCounts.Reason`); nil when it did, or when there is no picture.
    var problem: String?
    /// The picture file beside the music that was used, as it was then. A file with no picture of its own is asked
    /// again on every run which picture file its folder has now (a listing, nothing is read): when that is still this
    /// one, the note stands; when the DJ has added, changed or removed it, only the picture file is read again.
    var beside: BesideFile?

    struct BesideFile: Codable, Equatable {
        var name: String
        var size: Int
        var modified: Double
    }

    static let tag = "tag", beside = "beside", none = "none"

    /// The cover's name, when the picture gave one.
    var cover: String? { problem == nil ? picture : nil }
}

/// The covers of one build (D36; docs/architecture/crate-format.md, "Addition with D36"). For each song that gets a
/// record: its picture (the file's own, else one beside it: `CoverReader`, `CoverBeside`), made into a thumbnail once
/// for each distinct picture, kept in the work folder (`<work>/covers/<hash>.jpg`) and put into the crate package's
/// `covers/` before the records that name it are written.
///
/// A second run does none of that again. The work folder's line for a file says which picture it had and whether it
/// made a cover (`CoverNote`), and the thumbnail is in the work folder (or already in the package), so a file
/// unchanged since the last run gets its cover back with no music file opened and no picture decoded. The thumbnails
/// in the work folder are small (2 to 5 KB) and are left there when their songs go, as the records are.
final class BuildCovers: @unchecked Sendable {
    let work: WorkStore
    let output: URL
    /// False for songs that are not files in a folder (a music CD read by sector): they carry no pictures.
    let enabled: Bool

    private let state = NSCondition()
    private var notes: [String: CoverNote] = [:]
    /// Each folder's picture file as it is now, looked up once a run.
    private var folders: [String: CoverNote.BesideFile?] = [:]
    /// Pictures settled in this run, by hash: "" for one with a thumbnail, else why it has none.
    private var settled: [String: String] = [:]
    private var making: Set<String> = []
    private var made = 0
    private var picturesRead = 0
    private var placed: [URL] = []

    init(work: WorkStore, output: URL, enabled: Bool) {
        self.work = work; self.output = output; self.enabled = enabled
    }

    var workCovers: URL { work.folder.appendingPathComponent(CrateFormat.coversFolder) }
    func workCover(_ hash: String) -> URL { workCovers.appendingPathComponent(hash + ".jpg") }
    func outputCover(_ hash: String) -> URL {
        output.appendingPathComponent(CrateFormat.coversFolder).appendingPathComponent(hash + ".jpg")
    }

    /// Finds the cover of each of `files` (the files that have a record), several at once.
    func find(_ files: [SourceFile], jobs: Int) {
        guard enabled else { return }
        runParallel(count: files.count, workers: jobs) { [self] i in
            let f = files[i]
            let line = work.line(for: f.rel)
            let note = resolve(f, known: line?.cover)
            state.lock()
            notes[f.rel] = note
            state.unlock()
            if var line, line.cover != note, note.problem != CoverCounts.Reason.notKept {
                line.cover = note
                try? work.append(line)
            }
        }
    }

    /// The cover's name (`file.cover`) for a file given to `find`, or nil.
    func cover(of f: SourceFile) -> String? {
        state.lock(); defer { state.unlock() }
        return notes[f.rel]?.cover
    }

    private func resolve(_ f: SourceFile, known: CoverNote?) -> CoverNote {
        let folder = f.url.deletingLastPathComponent()
        guard var note = known else { return look(at: f) }
        if note.from != CoverNote.tag {
            // The file has no picture of its own (it is unchanged, so it still has none): is the folder's the same?
            let now = besideFile(of: folder)
            if now != note.beside { return besideNote(now, in: folder) }
        }
        if let hash = note.cover, !hasThumbnail(hash) {
            // The thumbnail is gone from the work folder and the package: made again from the picture.
            note = note.from == CoverNote.tag ? look(at: f) : besideNote(besideFile(of: folder), in: folder)
        }
        return note
    }

    /// Reads the file's picture, or the one beside it.
    private func look(at f: SourceFile) -> CoverNote {
        switch CoverReader.embedded(in: f.url) {
        case .picture(let data):
            let hash = Cover.hash(of: data)
            return CoverNote(from: CoverNote.tag, picture: hash, problem: thumbnail(of: data, hash: hash))
        case .tooLarge:
            state.lock(); picturesRead += 1; state.unlock()
            return CoverNote(from: CoverNote.tag, picture: nil, problem: CoverCounts.Reason.tooLarge)
        case .none:
            let folder = f.url.deletingLastPathComponent()
            return besideNote(besideFile(of: folder), in: folder)
        }
    }

    private func besideNote(_ file: CoverNote.BesideFile?, in folder: URL) -> CoverNote {
        guard let file else { return CoverNote(from: CoverNote.none) }
        switch CoverBeside.read(folder.appendingPathComponent(file.name)) {
        case .picture(let data):
            let hash = Cover.hash(of: data)
            return CoverNote(from: CoverNote.beside, picture: hash, problem: thumbnail(of: data, hash: hash), beside: file)
        case .tooLarge:
            return CoverNote(from: CoverNote.beside, picture: nil, problem: CoverCounts.Reason.tooLarge, beside: file)
        case .none:
            return CoverNote(from: CoverNote.beside, picture: nil, problem: CoverCounts.Reason.unreadable, beside: file)
        }
    }

    /// The folder's picture file now (`CoverBeside.find`), with its size and time.
    private func besideFile(of folder: URL) -> CoverNote.BesideFile? {
        state.lock()
        if let known = folders[folder.path] { state.unlock(); return known }
        state.unlock()
        var found: CoverNote.BesideFile? = nil
        if let url = CoverBeside.find(in: folder),
           let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
            found = .init(name: url.lastPathComponent, size: (attributes[.size] as? NSNumber)?.intValue ?? 0,
                          modified: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)
        }
        state.lock(); folders[folder.path] = .some(found); state.unlock()
        return found
    }

    private func hasThumbnail(_ hash: String) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: workCover(hash).path) || fm.fileExists(atPath: outputCover(hash).path)
    }

    /// Makes sure the picture's thumbnail exists, making it at most once a run however many songs carry the picture
    /// and not at all when an earlier run left it; returns why there is none, or nil.
    private func thumbnail(of picture: Data, hash: String) -> String? {
        state.lock()
        picturesRead += 1
        while making.contains(hash) { state.wait() }
        if let known = settled[hash] { state.unlock(); return known.isEmpty ? nil : known }
        making.insert(hash)
        state.unlock()

        var problem = ""
        var didMake = false
        if !hasThumbnail(hash) {
            do {
                let cover = try Cover.make(picture)
                try DeckieFiles.write(cover.jpeg, to: workCover(hash))
                didMake = true
            } catch let failure as Cover.Failure {
                problem = CoverCounts.Reason.of(failure)
            } catch {
                problem = CoverCounts.Reason.notKept
            }
        }
        state.lock()
        settled[hash] = problem
        if didMake { made += 1 }
        making.remove(hash)
        state.broadcast()
        state.unlock()
        return problem.isEmpty ? nil : problem
    }

    /// Puts the thumbnail of every cover `tracks` name into the package (unless it is there), before the writer
    /// checks for them, and counts. A record whose thumbnail cannot be found anywhere loses its cover rather than
    /// stopping the crate.
    func place(_ tracks: inout [CrateTrack]) throws -> CoverCounts {
        let fm = FileManager.default
        var sizes: [String: Int] = [:]
        var counts = CoverCounts()
        for i in tracks.indices {
            guard let hash = tracks[i].file.cover else { continue }
            if sizes[hash] == nil {
                let dest = outputCover(hash)
                if !fm.fileExists(atPath: dest.path) {
                    guard let jpeg = try? Data(contentsOf: workCover(hash)) else { tracks[i].file.cover = nil; continue }
                    try DeckieFiles.write(jpeg, to: dest)
                    placed.append(dest)
                }
                sizes[hash] = ((try? fm.attributesOfItem(atPath: dest.path))?[.size] as? NSNumber)?.intValue ?? 0
            }
            counts.songs += 1
        }
        counts.distinct = sizes.count
        counts.bytes = sizes.values.reduce(0, +)
        state.lock(); defer { state.unlock() }
        // Each unusable picture once: by its hash, or (too large to have been read) by where it is.
        var bad: [String: Set<String>] = [:]
        for (rel, note) in notes {
            guard let problem = note.problem else { continue }
            let folder = CratePath.lastName(rel).isEmpty ? rel : String(rel.dropLast(CratePath.lastName(rel).count))
            bad[problem, default: []].insert(note.picture ?? note.beside.map { folder + $0.name } ?? rel)
        }
        counts.unusable = bad.mapValues(\.count)
        counts.made = made
        counts.picturesRead = picturesRead
        return counts
    }

    /// Takes back what `place` put into the package, when the crate could not be written after all: a package left
    /// with covers and no manifest would not be taken for a crate file by the next run.
    func undo() {
        let fm = FileManager.default
        for url in placed { try? DeckieFiles.remove(url) }
        placed = []
        for folder in [output.appendingPathComponent(CrateFormat.coversFolder), output] {
            if let names = try? fm.contentsOfDirectory(atPath: folder.path), names.isEmpty { try? DeckieFiles.remove(folder) }
        }
    }
}
