import Foundation
import DeckieCore
import DeckieCrate
import DeckieBuild
import DeckieEngine
import DeckieDecode
import DeckieDisc

/// What a run reads: a source (a CD, a drive, or a folder read as one) or the ordinary music folder (`source` nil),
/// with a rekordbox collection for the rekordbox route. Kept as `pending.json` while the run goes, so a run that was
/// stopped (Desk quit, the Mac slept for good) can be carried on: the builder's work folder and the file store keep
/// everything finished, so carrying on does only what is left.
public struct RunRequest: Codable, Equatable, Sendable {
    public var folder: String
    public var source: String?
    public var rekordbox: String?
    /// A music CD (research AA): where the disc is (`MusicCDs.Found.location`, also `folder`) and its id. Its songs
    /// are read off the disc one at a time and none is kept (`DiscSongs.swift`); a run that stopped carries on when
    /// the same disc is in a drive again.
    public var musicCD: String?
    public var discId: String?
    public init(folder: URL, source: String?, rekordbox: URL? = nil, musicCD: String? = nil, discId: String? = nil) {
        self.folder = folder.path; self.source = source; self.rekordbox = rekordbox?.path
        self.musicCD = musicCD; self.discId = discId
    }
    public var folderURL: URL { URL(fileURLWithPath: folder) }
    /// What the run reads, by its own name: the source's, or the folder's.
    public var name: String { source ?? URL(fileURLWithPath: folder).lastPathComponent }
}

/// The stage a run is in. One count goes through all of them: a song is done when it is read, its signature made and
/// its print made.
public enum RunStage: String, Codable, Sendable { case reading, finishing, saving }

/// A run's progress: songs done of the songs found, and an estimate of the seconds left (nil until there is
/// something to estimate from).
public struct RunProgress: Sendable {
    public var stage: RunStage
    public var done: Int
    public var total: Int
    public var remaining: Double?
    /// What just happened, for the run's list, or nil.
    public var line: RunLine?
}

/// One line of a run's list, as data; a desk says it in its own words.
public enum RunLine: Sendable, Equatable {
    /// The folder is listed: audio files found, unchanged since the last run, and to read now.
    case started(files: Int, unchanged: Int, queued: Int)
    /// A file was read: its path (the source's name first) and what happened.
    case file(rel: String, outcome: FileProgress.Outcome)
    /// Part of a music CD's song could not be read even on a second try: its number, and the sectors (1/75 s each)
    /// that were read as silence.
    case discDamaged(number: Int, sectors: Int)
}

/// What a run did, measured as it ran (no tuning: these are for collecting real timings). Shown on the finished
/// screen and written as one line of the crate's `runs.jsonl`.
public struct RunReport: Codable, Equatable, Sendable {
    public var crate: String
    /// What was read, by its own name.
    public var read: String
    public var startedAt: String
    /// Wall-clock seconds of the whole run, and of its parts: the builder (with finishing alongside), and the
    /// finishing and saving after it.
    public var seconds: Double
    public var buildSeconds: Double
    public var finishSeconds: Double
    /// Audio files found in what was read, how many went in, and the ones that did not, by the import log's reason.
    public var songsSeen: Int
    public var wentIn: Int
    public var notIn: [String: Int]
    /// Folders left out by the "_" rule (the music folder only), and songs in with damaged frames.
    public var foldersLeftOut: Int
    public var damaged: Int
    /// Files analysed in this run, and taken from what was worked out before (this crate's or another's).
    public var analysed: Int
    public var reused: Int
    public var signaturesMade: Int
    public var signaturesKept: Int
    public var signaturesFailed: Int
    public var printsMade: Int
    public var printsKept: Int
    public var printsFailed: Int
    /// Entries now in a group of copies of one recording, and songs in the crate after the run.
    public var copies: Int
    public var songsInCrate: Int
    /// Songs found per minute of the whole run.
    public var songsPerMinute: Double
    public var jobs: Int
    public var device: String
    public var engine: String
    /// Whether the run carried on one that had stopped.
    public var carriedOn: Bool
    /// The keys and names taken from what is already on the computer (D30): where each key came from, the songs still
    /// with no key or no name, the DJ libraries read. Nil in a line written before it.
    public var local: LocalFactsSummary? = nil
    /// A music CD's part of the run (research AA): what the drive said about names, the songs named from the disc,
    /// and the sound that could not be read. Nil for anything else.
    public var disc: DiscReport? = nil
    /// Covers (D36), as the builder counted them: songs with one, distinct covers and their bytes, pictures that could
    /// not be used. Nil in a line written before covers.
    public var covers: CoverCounts? = nil

    enum CodingKeys: String, CodingKey {
        case crate, read, seconds, analysed, reused, copies, jobs, device, engine, damaged
        case startedAt = "started_at", buildSeconds = "build_seconds", finishSeconds = "finish_seconds"
        case songsSeen = "songs_seen", wentIn = "went_in", notIn = "not_in", foldersLeftOut = "folders_left_out"
        case signaturesMade = "signatures_made", signaturesKept = "signatures_kept", signaturesFailed = "signatures_failed"
        case printsMade = "prints_made", printsKept = "prints_kept", printsFailed = "prints_failed"
        case songsInCrate = "songs_in_crate", songsPerMinute = "songs_per_minute", carriedOn = "carried_on"
        case local, disc, covers
    }

    /// Songs that did not go in.
    public var notInCount: Int { notIn.values.reduce(0, +) }
}

/// The one run (D28, desk.md section 2): everything a crate needs from what was added, in one go. The builder reads
/// and analyses (keeping its records in the shared file store); as each song is read, its recognition signature and
/// its print are made, or taken from the store; then copies of one recording are linked, the keys and names already on
/// the computer are gathered (`DeskLocalFacts`, D30), the DJ's name fixes are put back, every place's path is remembered, and the crate file is written. Stopping at any point loses nothing
/// already done; running again carries on.
public final class DeskRun: @unchecked Sendable {
    /// Makes a recognition signature from a song's file (ShazamKit on Apple's systems); nil where there is none.
    public typealias SignatureMaker = @Sendable (URL) throws -> Data
    /// Makes the print that finds copies of one recording from a song's file.
    public typealias PrintMaker = @Sendable (URL) throws -> RecordingPrint

    public let home: DeskHome
    public let crateId: String
    public let request: RunRequest
    public let jobs: Int
    public let device: String
    public let fileBPMTags: Bool
    let analyser: Analyser?
    let signer: SignatureMaker?
    let printer: PrintMaker
    /// Opens a music CD by its location (`MusicCDs.open`; a test gives a stand-in), and lists the drives holding
    /// one (to find the disc when it is in another drive).
    public var openMusicCD: (String) throws -> MusicCD = { try MusicCDs.open($0) }
    public var findMusicCDs: () -> [MusicCDs.Found] = { MusicCDs.list() }

    public init(home: DeskHome, crateId: String, request: RunRequest, jobs: Int, device: String,
                fileBPMTags: Bool = true, analyser: Analyser? = nil, signer: SignatureMaker?, printer: @escaping PrintMaker) {
        self.home = home; self.crateId = crateId; self.request = request; self.jobs = max(1, jobs); self.device = device
        self.fileBPMTags = fileBPMTags; self.analyser = analyser; self.signer = signer; self.printer = printer
    }

    public static let pendingFile = "pending.json"
    public static let runsFile = "runs.jsonl"
    public static let correctionsFile = "corrections.json"
    public static let placesFile = "places.json"
    public static let namesFile = NameBook.file

    /// Whether a run that stopped can carry on now: its folder is here, or for a music CD, the same disc is in a
    /// drive.
    public static func canCarryOn(_ r: RunRequest, home: DeskHome,
                                  open: (String) throws -> MusicCD = { try MusicCDs.open($0) },
                                  musicCDs: () -> [MusicCDs.Found] = { MusicCDs.list() }) -> Bool {
        guard let id = r.discId, r.musicCD != nil else { return FileManager.default.fileExists(atPath: r.folder) }
        return DiscRecords.find(id, near: r.musicCD, open: open, musicCDs: musicCDs) != nil
    }

    /// The run a crate has left unfinished, if any.
    public static func pending(home: DeskHome, crateId: String) -> RunRequest? {
        JSONFile.read(RunRequest.self, from: home.shelf.file(pendingFile, of: crateId))
    }

    /// The crate's finished runs, oldest first.
    public static func runs(home: DeskHome, crateId: String) -> [RunReport] {
        guard let text = try? String(contentsOf: home.shelf.file(runsFile, of: crateId), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(RunReport.self, from: Data($0.utf8)) }
    }

    /// Counts shared between the builder's jobs and the finishing queue.
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var total = 0
        var done = 0
        var finishedIds = Set<String>()
        var finishSeconds: [Double] = []
        var waiting = 0
        var builderRemaining: Double?
        var builderStamp = Date()
        var sigMade = 0, sigKept = 0, sigFailed = 0, printMade = 0, printKept = 0, printFailed = 0
    }

    public func run(progress: @escaping @Sendable (RunProgress) -> Void = { _ in }) throws -> (crate: Crate, report: RunReport) {
        let t0 = Date()
        try home.prepare()
        let shelf = home.shelf, store = home.store
        guard var info = shelf.info(crateId) else { throw DeskError("no crate \(crateId)") }
        let pkg = shelf.package(crateId)
        let pendingURL = shelf.file(Self.pendingFile, of: crateId)
        let carriedOn = FileManager.default.fileExists(atPath: pendingURL.path)
        try JSONFile.write(request, to: pendingURL)

        let fm = FileManager.default
        // 0. A music CD: the disc in a drive (the one asked for; a stopped run carries on only with it), what Desk
        // knows of it, and its songs for the builder, read one at a time and none kept.
        DiscReading.clearLeftovers(home)
        let disc = try request.discId.flatMap { id -> DiscSongFiles? in
            guard request.musicCD != nil else { return nil }
            guard let cd = DiscRecords.find(id, near: request.musicCD, open: openMusicCD, musicCDs: findMusicCDs) else {
                throw DeskError("\(request.name) is not in a drive. Put \(request.name) back in to carry on.")
            }
            return DiscSongFiles(cd: cd, record: try DiscRecords.prepare(cd, home: home), home: home, store: store,
                                 needsSignature: signer != nil)
        }
        let folder = disc.map { URL(fileURLWithPath: $0.cd.location) } ?? request.folderURL
        defer { disc?.clear() }
        let before = fm.fileExists(atPath: pkg.appendingPathComponent(CrateFormat.manifestFile).path)
            ? try CrateReader.read(from: pkg) : nil
        let keep: Set<String> = request.source == nil
            ? Set(info.sourceRoots.keys).union(before?.tracks.flatMap { $0.ident.allPlaces.compactMap(\.disc) } ?? [])
            : []
        let options = BuildOptions(folder: folder, output: pkg, rekordbox: request.rekordbox.map { URL(fileURLWithPath: $0) },
                                   jobs: jobs, fileBPMTags: fileBPMTags, fresh: false, name: info.name, device: device,
                                   source: request.source, keepSources: keep, sharedRecords: store.records,
                                   files: disc)
        let prefix = request.source.map { $0 + "/" } ?? ""
        let state = State()
        let queue = DispatchQueue(label: "deckie.desk.finish", qos: .userInitiated)
        let signer = self.signer, printer = self.printer, device = self.device

        @Sendable func estimate() -> Double? {
            // Called with the lock held.
            let mean = state.finishSeconds.isEmpty ? nil : state.finishSeconds.reduce(0, +) / Double(state.finishSeconds.count)
            let finishing = mean.map { Double(state.waiting) * $0 }
            let reading = state.builderRemaining.map { max(0, $0 - Date().timeIntervalSince(state.builderStamp)) }
            switch (reading, finishing) {
            case let (r?, f?): return max(r, f)
            case let (r?, nil): return r
            case let (nil, f?): return f
            default: return nil
            }
        }
        @Sendable func emit(_ stage: RunStage, _ line: RunLine?) {
            state.lock.lock()
            let p = RunProgress(stage: stage, done: min(state.done, state.total), total: state.total, remaining: estimate(),
                                line: line)
            state.lock.unlock()
            progress(p)
        }
        /// Makes (or takes from the store) the signature and the print of one file. Called on the finishing queue.
        @Sendable func finish(_ id: String, _ url: URL) {
            let t = Date()
            var made = false
            if let signer {
                if store.signature(id) != nil {
                    state.lock.lock(); state.sigKept += 1; state.lock.unlock()
                } else {
                    do {
                        let data = try signer(url)
                        try store.saveSignature(data, made: .init(madeBy: device, madeAt: Self.utcNow()), id: id)
                        made = true
                        state.lock.lock(); state.sigMade += 1; state.lock.unlock()
                    } catch { state.lock.lock(); state.sigFailed += 1; state.lock.unlock() }
                }
            }
            if store.print(id) != nil {
                state.lock.lock(); state.printKept += 1; state.lock.unlock()
            } else {
                do {
                    try store.savePrint(try printer(url), id: id)
                    made = true
                    state.lock.lock(); state.printMade += 1; state.lock.unlock()
                } catch { state.lock.lock(); state.printFailed += 1; state.lock.unlock() }
            }
            state.lock.lock()
            state.finishedIds.insert(id)
            if made { state.finishSeconds.append(Date().timeIntervalSince(t)) }
            state.lock.unlock()
        }

        // 1. Read: the builder, with each song finished as soon as it is read.
        let builder = try Builder(options: options, analyser: analyser)
        let result: BuildResult
        do { result = try builder.run { event in
            switch event {
            case let .started(files, unchanged, queued, _, _):
                state.lock.lock(); state.total = files; state.lock.unlock()
                emit(.reading, .started(files: files, unchanged: unchanged, queued: queued))
            case let .file(p):
                state.lock.lock()
                state.builderRemaining = p.remaining; state.builderStamp = Date()
                if p.id == nil { state.done += 1 } else { state.waiting += 1 }
                state.lock.unlock()
                if let id = p.id, let disc {
                    // A music CD's song is finished now, while its file is here; then the builder lets it go.
                    // One worked out before was not read: its signature and print are in the store already.
                    let url = disc.file(rel: p.rel)
                    if url != nil { disc.learned(rel: p.rel, id: id) }
                    finish(id, url ?? folder.appendingPathComponent(String(p.rel.dropFirst(prefix.count))))
                    state.lock.lock(); state.waiting -= 1; state.done += 1; state.lock.unlock()
                    let damaged = disc.damaged(rel: p.rel)
                    if damaged > 0, let n = DiscSongFiles.number(of: p.rel) { emit(.reading, .discDamaged(number: n, sectors: damaged)) }
                } else if let id = p.id {
                    let url = folder.appendingPathComponent(String(p.rel.dropFirst(prefix.count)))
                    queue.async {
                        finish(id, url)
                        state.lock.lock(); state.waiting -= 1; state.done += 1; state.lock.unlock()
                        emit(.reading, nil)
                    }
                }
                emit(.reading, .file(rel: p.rel, outcome: p.outcome))
            case .writing:
                break
            }
        } } catch let e as DiscError where disc != nil {
            // The disc came out, or the drive stopped answering: nothing of this read is written; carry on asks for it.
            throw DeskError("\(request.name) could not be read (\(e.description)). Put \(request.name) back in to carry on.")
        }
        queue.sync {}
        let buildSeconds = Date().timeIntervalSince(t0)
        let t1 = Date()

        // 2. Finish: every song of the crate gets its signature and print, from the store when they were made before
        // (songs unchanged since the last run, or read for another crate), else from its file.
        var crate = result.crate
        let paths = PlacePaths.load(from: shelf.file(Self.placesFile, of: crateId))
        var newPaths = paths
        newPaths.record(result.placesRead, source: request.source, keep: keep)
        newPaths.fillMissingPaths(&crate)
        if let s = request.source {
            info.sourceRoots[s] = folder.path
            info.discs[s] = disc?.base.toc.id
        } else { info.musicFolder = folder.path }
        let roots = info.roots, music = info.musicFolderURL
        let todo = crate.tracks.filter { t in
            state.lock.lock(); defer { state.lock.unlock() }
            return !state.finishedIds.contains(t.id)
        }
        state.lock.lock(); state.waiting = todo.count; state.lock.unlock()
        for t in todo {
            let readNow = result.placesRead[t.id]?.first.map { folder.appendingPathComponent($0.rel) }
            let url = readNow.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil }
                ?? newPaths.locate(t, roots: roots, musicFolder: music)
            if let url { finish(t.id, url) } else {
                state.lock.lock(); state.finishedIds.insert(t.id); state.lock.unlock()
            }
            state.lock.lock()
            state.waiting -= 1
            state.done += result.placesRead[t.id]?.count ?? 0
            state.lock.unlock()
            emit(.finishing, nil)
        }
        state.lock.lock(); state.done = state.total; state.lock.unlock()
        emit(.saving, nil)

        // 3. Save: signatures into the crate file, copies linked, the DJ's fixes put back, the crate's name.
        let sigFolder = pkg.appendingPathComponent(CrateFormat.signaturesFolder)
        try DeckieFiles.createDirectory(sigFolder)
        var prints: [String: RecordingPrint] = [:]
        for i in crate.tracks.indices {
            let id = crate.tracks[i].id
            if let s = store.signature(id) {
                let dest = sigFolder.appendingPathComponent("\(id)_o.shazamsignature")
                if !fm.fileExists(atPath: dest.path) { try DeckieFiles.write(s.data, to: dest) }
                if crate.tracks[i].signatures["o"] == nil { crate.tracks[i].signatures["o"] = s.made }
            }
            if let p = store.print(id) { prints[id] = p }
        }
        let copies = crate.setCutKeys(prints: prints)
        // Keys and names already on the computer: the files' tags, the DJ programs' libraries, tracklists, copies.
        let local = DeskLocalFacts.gather(&crate, home: home, info: info, paths: newPaths)
        // A music CD's names from its CD-Text; where every name came from, and each song's release (research AA).
        let (book, discNamed) = DeskNamesStep.run(&crate, home: home, info: info, paths: newPaths,
                                                  book: NameBook.load(from: shelf.file(Self.namesFile, of: crateId)))
        try book.save(to: shelf.file(Self.namesFile, of: crateId))
        let corrections = NameCorrections.load(from: shelf.file(Self.correctionsFile, of: crateId))
        corrections.apply(to: &crate)
        crate.manifest.name = info.name
        try CrateWriter.write(crate, to: pkg)
        newPaths.keepOnly(Set(crate.tracks.map(\.id)))
        try newPaths.save(to: shelf.file(Self.placesFile, of: crateId))
        info.openedAt = max(Date().timeIntervalSince1970, (shelf.list().first?.openedAt ?? 0) + 0.001)
        try shelf.save(info)

        // 4. The report, and the run's line in the crate's log.
        typealias Reason = CrateManifest.ImportLog.Reason
        let mine = result.entries.filter { e in
            if let s = request.source { return e.rel.hasPrefix(s + "/") }
            return !keep.contains { e.rel.hasPrefix($0 + "/") }
        }
        var notIn: [String: Int] = [:]
        for e in mine where e.reason != Reason.damagedFrames && e.reason != Reason.skipped { notIn[e.reason, default: 0] += 1 }
        let seconds = Date().timeIntervalSince(t0)
        state.lock.lock()
        let report = RunReport(
            crate: info.name, read: request.name, startedAt: Self.utc(t0), seconds: seconds, buildSeconds: buildSeconds,
            finishSeconds: Date().timeIntervalSince(t1), songsSeen: result.filesSeen,
            wentIn: max(0, result.filesSeen - notIn.values.reduce(0, +)), notIn: notIn,
            foldersLeftOut: mine.filter { $0.reason == Reason.skipped }.count,
            damaged: mine.filter { $0.reason == Reason.damagedFrames }.count,
            analysed: result.analysed, reused: result.reused,
            signaturesMade: state.sigMade, signaturesKept: state.sigKept, signaturesFailed: state.sigFailed,
            printsMade: state.printMade, printsKept: state.printKept, printsFailed: state.printFailed,
            copies: copies, songsInCrate: crate.tracks.count,
            songsPerMinute: seconds > 0 ? Double(result.filesSeen) / seconds * 60 : 0,
            jobs: jobs, device: device, engine: Builder.engineLabel, carriedOn: carriedOn, local: local,
            disc: disc.map(\.current).map { r in
                DiscReport(text: r.text, songs: r.toc.songs.count, named: request.source.flatMap { discNamed[$0] } ?? 0,
                           damagedSectors: r.damagedSectors, titled: r.discTitle != nil)
            }, covers: result.covers)
        state.lock.unlock()
        try Self.appendRun(report, to: shelf.file(Self.runsFile, of: crateId))
        try? DeckieFiles.remove(pendingURL)
        return (crate, report)
    }

    static func appendRun(_ r: RunReport, to url: URL) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        var line = try e.encode(r)
        line.append(0x0A)
        try DeckieFiles.append(line, to: url)
    }

    public static func utc(_ d: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }
    public static func utcNow() -> String { utc(Date()) }
}

extension DeskRun {
    /// The print of a song's file through the shared decoder (WAV, AIFF, MP3, FLAC), for a desk with no system
    /// decoder of its own; the Mac's desk reads with AVFoundation, which also reads AAC and Apple Lossless.
    public static let portablePrint: PrintMaker = { url in
        let b = try AudioDecoder.decode(url)
        return RecordingPrint(interleaved: b.samples, channels: b.channelCount, sampleRate: b.sampleRate)
    }
}
