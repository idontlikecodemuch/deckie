import Foundation
import DeckieCore
import DeckieCrate
import DeckieEngine
import DeckieInference

/// What a build is asked to do (`deckie-build <folder> --out <name>.deckiecrate ...`).
public struct BuildOptions: Sendable {
    /// The folder of music.
    public var folder: URL
    /// The crate package to write (`<name>.deckiecrate`).
    public var output: URL
    /// A rekordbox collection export (XML) to take names, the DJ's tempo and key, cues and playlists from.
    public var rekordbox: URL?
    /// Files analysed at once; the default is the processor count, or fewer when memory is short (`defaultJobs`).
    public var jobs: Int
    /// Take a file's own tempo tag (ID3 TBPM, FLAC BPM) as the tag tempo the octave alignment follows, when rekordbox
    /// gives none.
    public var fileBPMTags: Bool
    /// Ignore and empty the work folder first.
    public var fresh: Bool
    /// The crate's name; the default keeps an existing crate's name, else the output's file name.
    public var name: String?
    /// The device label written to each record and to `devices_seen`: the platform, never a name the user gave the
    /// machine.
    public var device: String
    /// Folders whose name starts with one of these are left out of the build, with an import-log entry each; the
    /// default leaves out `_` folders (`_old`, `_stale - safe to delete`), the usual way a DJ parks files.
    public var skipFolderPrefixes: [String]
    /// Read the folder as a source of this name (D25, D26): a burned CD, a USB stick or an SD card, read as it is. Its
    /// files are labelled with their places (`SourceReading`: the source's name, the folder below its top, the number
    /// a player shows) and their `file.rel` is the path below the source's top. The crate at `output`, if there is
    /// one, keeps every place that is not on this source as it is; this source's places, an entry's own and its other
    /// places alike (D27), are replaced by what is read now. A file whose bytes are already in the crate adds its
    /// place to that entry. Nothing is left out by folder name, since the player shows every folder. In the import
    /// log and the progress, a source's files are named by the source's name, then the path below it.
    public var source: String?
    /// For a build from an ordinary folder (`source` nil) into an existing crate: the sources read into it before,
    /// whose places are kept as they are. Places with no source, or any other disc label, are read again from the
    /// folder, as before; a file in the folder whose bytes are on a kept source is a place with no source (its
    /// folder) of that entry.
    public var keepSources: Set<String>
    /// Where finished records are kept, when not in the work folder's own `records/`: a folder shared by several
    /// crates (Deckie Desk's store of what it worked out for each file), so a file read for one crate is not analysed
    /// again for another. Records are keyed by the file's id, so sharing them is safe; `fresh` does not empty it.
    public var sharedRecords: URL?

    public init(folder: URL, output: URL, rekordbox: URL? = nil, jobs: Int = defaultJobs, fileBPMTags: Bool = false,
                fresh: Bool = false, name: String? = nil, device: String = Analysis.platform,
                skipFolderPrefixes: [String] = ["_"], source: String? = nil, keepSources: Set<String> = [],
                sharedRecords: URL? = nil) {
        self.folder = folder; self.output = output; self.rekordbox = rekordbox; self.jobs = max(1, jobs)
        self.fileBPMTags = fileBPMTags; self.fresh = fresh; self.name = name; self.device = device
        self.skipFolderPrefixes = source == nil ? skipFolderPrefixes : []
        self.source = source; self.keepSources = keepSources; self.sharedRecords = sharedRecords
    }

    /// What the import log and the progress put before a path below the folder: the source's name and a "/", or
    /// nothing for an ordinary folder.
    var logPrefix: String { source.map { $0 + "/" } ?? "" }

    /// The work folder: `<name>.deckiebuild` beside the crate.
    public var workFolder: URL {
        output.deletingLastPathComponent()
            .appendingPathComponent(output.deletingPathExtension().lastPathComponent + "." + Builder.workExtension)
    }
}

/// What happened to one file of the queue.
public struct FileProgress: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// Analysed now, in `seconds`.
        case analysed(seconds: Double)
        /// Taken from the work folder: the same bytes were analysed before (found by the file's hash).
        case reused
        /// Not analysed; goes into the import log.
        case failed(FileFailure)
    }
    /// Files of the queue finished so far, this one included, and the queue's length.
    public var done: Int
    public var total: Int
    public var rel: String
    public var outcome: Outcome
    /// Seconds since the queue started, and the estimate of the seconds left (nil until a file has been analysed).
    public var elapsed: Double
    public var remaining: Double?
    /// The file's id (its content's hash) when it has a record, so a caller can do more with it as it finishes.
    public var id: String? = nil
}

/// The build's progress, as it goes.
public enum BuildEvent: Sendable {
    /// The folder is listed: `files` audio files, `unchanged` of them taken from the work folder as they are (same
    /// size and modification time as last time), `queued` to look at, `jobs` at a time.
    case started(files: Int, unchanged: Int, queued: Int, jobs: Int, rekordbox: CrateManifest.ImportLog.Rekordbox?)
    case file(FileProgress)
    /// Writing the crate.
    case writing(tracks: Int)
}

/// What a build did.
public struct BuildResult: Sendable {
    public var crate: Crate
    public var output: URL
    public var filesSeen: Int
    /// Files analysed in this run, and the seconds each took.
    public var analysed: Int
    public var analysisSeconds: [Double]
    /// Files' contents taken from the work folder (unchanged since the last run, or the same bytes found by their
    /// hash): the entries read now that were not analysed in this run.
    public var reused: Int
    /// The import log's entries: the files without a record of their own, and the files whose record is in the crate
    /// but whose decoder silenced damaged frames (reason `damaged_frames`).
    public var entries: [CrateManifest.ImportLog.Entry]
    public var rekordbox: CrateManifest.ImportLog.Rekordbox?
    /// Wall-clock seconds of the whole build.
    public var seconds: Double
    /// Every file read in this run that is in the crate, by entry id: its place and its path below the folder read
    /// (below the source's top for a source), so a caller can remember where each place's file is.
    public var placesRead: [String: [ReadPlace]] = [:]

    /// The summary printed at the end: the counts, the files not in the crate by reason and extension, the files in
    /// it with damaged frames, and where the import log is.
    public var summary: String {
        typealias Reason = CrateManifest.ImportLog.Reason
        var s = "\(filesSeen) audio file\(filesSeen == 1 ? "" : "s"): \(analysed) analysed"
        if analysed > 0, let m = mean(analysisSeconds) {
            s += " (\(Py.fixed(analysisSeconds.reduce(0, +), 1)) s of analysis, \(Py.fixed(m, 1)) s a file on average)"
        }
        let left = entries.filter { $0.reason != Reason.damagedFrames }
        let damaged = entries.filter { $0.reason == Reason.damagedFrames }
        s += ", \(reused) taken from the work folder, \(left.count) not in the crate"
        if left.isEmpty { s += "\n" } else {
            s += ":\n"
            let log = CrateManifest.ImportLog(builtBy: "", builtAt: "", filesSeen: 0, tracks: 0, entries: left)
            let reasons = log.counts
            let known = Reason.all
            for reason in known + reasons.keys.sorted().filter({ !known.contains($0) }) where reasons[reason] != nil {
                let byExt = reasons[reason]!
                let total = byExt.values.reduce(0, +)
                let list = byExt.keys.sorted().map { "\($0) \(byExt[$0]!)" }.joined(separator: ", ")
                s += "  " + reason.padding(toLength: 15, withPad: " ", startingAt: 0) + String(format: "%5d", total)
                    + "   " + list + "\n"
            }
        }
        if !damaged.isEmpty {
            s += "\(damaged.count) file\(damaged.count == 1 ? "" : "s") in the crate with damaged frames, played as "
                + "silence (faulty but playable):\n"
            for e in damaged { s += "  \(e.rel): \(e.message)\n" }
        }
        if !entries.isEmpty {
            s += "  each file and its reason: import_log in \(output.lastPathComponent)/manifest.json\n"
        }
        if let rb = rekordbox { s += "rekordbox: \(rb.matched) of \(rb.tracks) collection tracks matched a file\n" }
        s += "wrote \(output.path): \(crate.tracks.count) track\(crate.tracks.count == 1 ? "" : "s") in "
            + "\(clock(seconds))\n"
        return s
    }
}

/// Builds a crate from a folder of music: finds the audio files, analyses each with the engine (several at once),
/// keeps every finished file in the work folder so a second run skips what is done, and writes the crate with every
/// file that has no record listed in the manifest's import log, and every file whose decoder silenced damaged frames
/// listed there too, with their times.
public final class Builder: Sendable {
    /// The builder's own version, raised with the engine's when what the builder writes changes (0.2.0: the import
    /// log's device label and the record's `imported` block; 0.2.1: the import log's `damaged_frames` entries).
    public static let version = "0.2.1"
    /// The program and its version (`deckie-build 0.2.1`), printed when a build starts and written as the bench
    /// report's `tool`. Not written in the crate: the manifest's `import_log.built_by` names the device instead.
    public static var programLabel: String { "deckie-build \(version)" }
    /// The work folder's extension.
    public static let workExtension = "deckiebuild"
    /// The engine's label (`deckie-0.4.0`, as `analysis.engine` writes it).
    public static var engineLabel: String { "\(Analysis.engineFamily)-\(Analysis.engineVersion)" }

    /// What a work record must have been made with to be reused: the engine's label and the vocal tagger's model, or
    /// none (`deckie-0.4.0 vocal:yamnet`, `deckie-0.4.0 vocal:none`), so records made before the vocal model was
    /// installed are made again once it is, and so are records of an older engine version.
    public static func engineKey(vocalModel: String?) -> String { "\(engineLabel) vocal:\(vocalModel ?? "none")" }

    /// The vocal tagger's model a default analyser will have: YAMNet's name when its model file is there, else nil.
    public static var defaultVocalModel: String? { YAMNet.locateModel() == nil ? nil : YAMNet.modelName }

    /// Why a default analyser will have no vocal tagger (what is missing and how to get it), or nil when it will.
    public static var vocalTaggerNote: String? {
        defaultVocalModel != nil ? nil : "no vocal tagger, so the records have no vocal block (flag vocal_unknown): "
            + DeckieVocalTagger.missingModels().map(\.description).joined(separator: "; ")
    }

    /// The vocal model this build's analyser has (or will have).
    var vocalModel: String? { analyser.map { $0.vocalTagger?.modelName } ?? Builder.defaultVocalModel }

    public let options: BuildOptions
    /// The analyser given; nil makes one when there is something to analyse (`makeAnalyser`).
    public let analyser: Analyser?

    /// A builder with `analyser`, or, without one, a check that ONNX Runtime and the beat model can be found (the
    /// analyser itself is made once the queue is known, with threads for the jobs that will really run).
    public init(options: BuildOptions, analyser: Analyser? = nil) throws {
        self.options = options
        self.analyser = analyser
        if analyser == nil { try Builder.checkEngine() }
    }

    /// Throws, with what was looked for and how to fix it, when ONNX Runtime or the Beat This! model is missing.
    public static func checkEngine() throws {
        guard OnnxRuntime.locateLibrary() != nil else {
            throw BuildError("ONNX Runtime not found (looked at: \(OnnxRuntime.libraryCandidates().joined(separator: ", "))); "
                             + "set \(OnnxRuntime.libraryEnvironmentVariable) or run core/Tools/fetch-onnxruntime.sh")
        }
        guard BeatTracker.locateModel() != nil else {
            throw BuildError(BeatTrackerError.modelNotFound(searched: BeatTracker.modelCandidates()).description)
        }
    }

    /// One analyser shared by all jobs, with the vocal tagger when its model is there (as `Analyser()` has it): the
    /// models' ONNX Runtime sessions may be run from several threads at once (`OnnxSession`), and everything else in
    /// an analysis is the call's own. Each run gets the processor count over the jobs in threads of its own, so the
    /// jobs do not fight over the cores.
    public static func makeAnalyser(jobs: Int) throws -> Analyser {
        let threads = jobs <= 1 ? 0 : max(1, processorCount / jobs)
        let options = OnnxRuntime.SessionOptions(intraOpThreads: threads)
        let tracker = try BeatTracker(options: options)
        let tagger = try YAMNet.locateModel().map {
            DeckieVocalTagger(yamnet: try YAMNet(modelPath: $0, runtime: tracker.session.runtime, options: options))
        }
        return try Analyser(beatTracker: tracker, vocalTagger: tagger)
    }

    /// The tag tempo a file's analysis follows: the DJ's rekordbox tempo, else (with `fileBPMTags`) the file's own tag.
    /// The record keeps the tempo (`file.tag_bpm`) and not where it came from: rekordbox's is taken whenever it has
    /// one, so it came from rekordbox exactly when it equals `imported.rekordbox.bpm`.
    func tagTempo(rekordbox: RekordboxCollection.Track?, tags: FileTags?) -> Double? {
        if let bpm = rekordbox?.averageBpm { return bpm }
        if options.fileBPMTags, let bpm = tags?.bpm { return bpm }
        return nil
    }

    private enum Done {
        case ok(id: String, tags: FileTags?)
        case failed(FileFailure)
    }

    /// Collects the queue's results from the jobs.
    private final class Results: @unchecked Sendable {
        let lock = NSLock()
        var done: [String: Done] = [:]
        var finished = 0
        var analysedSeconds: [Double] = []
        var analysedIDs: Set<String> = []
        var reused = 0
        let started = Date()
    }

    /// Runs the build, reporting through `progress` (called from the jobs' threads, one call at a time).
    public func run(progress: @escaping @Sendable (BuildEvent) -> Void = { _ in }) throws -> BuildResult {
        let t0 = Date()
        var (found, skippedFolders) = try AudioFiles.find(in: options.folder, skippingFolderPrefixes: options.skipFolderPrefixes)
        // A source's places come from every audio file on it, analysable or not, so the numbers are the player's.
        let places = options.source.map { SourceReading.places(source: $0, paths: found.map(\.rel)) } ?? [:]
        let prefix = options.logPrefix
        if !prefix.isEmpty {
            for i in found.indices { found[i].rel = prefix + found[i].rel }
            for i in skippedFolders.indices { skippedFolders[i].rel = prefix + skippedFolders[i].rel }
        }
        let files = found
        var collection: RekordboxCollection? = nil
        var matcher: RekordboxMatcher? = nil
        let importedAt = utcNow()
        if let xml = options.rekordbox {
            let c = try RekordboxCollection.read(xml)
            collection = c
            matcher = RekordboxMatcher(c)
        }
        let existing = try existingCrate()
        let work = try WorkStore(folder: options.workFolder, fresh: options.fresh, records: options.sharedRecords)
        let label = Builder.engineKey(vocalModel: vocalModel)
        // Matched by the path below the folder chosen, without the source's name put before it for the log: a folder
        // read as a source (D31) is named after itself, or "Music 2", which is not a folder in rekordbox's paths.
        let rekordboxOf = files.map { f in
            matcher?.match(absolutePath: f.url.path, rel: String(f.rel.dropFirst(prefix.count)), size: f.size)
        }
        let rbSummary = collection.map {
            CrateManifest.ImportLog.Rekordbox(tracks: $0.tracks.count, matched: rekordboxOf.compactMap { $0 }.count)
        }

        // Files unchanged since a finished run (same size and modification time) are taken as they are.
        var done: [String: Done] = [:]
        var queue: [Int] = []
        for (i, f) in files.enumerated() {
            if let line = work.line(for: f.rel), line.size == f.size, line.modified == f.modified, line.engine == label {
                if line.status == "ok", let id = line.id,
                   tagTempo(rekordbox: rekordboxOf[i], tags: line.tags) == line.bpmTag,
                   FileManager.default.fileExists(atPath: work.recordURL(id).path) {
                    done[f.rel] = .ok(id: id, tags: line.tags)
                    continue
                }
                if line.status == "failed", let reason = line.reason {
                    let failure = FileFailure(reason: reason, message: line.message ?? "")
                    if failure.isLasting {
                        done[f.rel] = .failed(failure)
                        continue
                    }
                }
            }
            queue.append(i)
        }
        let unchanged = done.count
        progress(.started(files: files.count, unchanged: unchanged, queued: queue.count, jobs: options.jobs,
                          rekordbox: rbSummary))

        let results = Results()
        let total = queue.count
        let queued = queue
        let engine = total == 0 ? nil : try analyser ?? Builder.makeAnalyser(jobs: min(options.jobs, total))
        runParallel(count: total, workers: options.jobs) { [self] k in
            let i = queued[k]
            let f = files[i]
            var seconds: Double? = nil
            let outcome = self.process(f, rekordbox: rekordboxOf[i], work: work, engine: engine!, label: label,
                                       seconds: &seconds)
            results.lock.lock()
            defer { results.lock.unlock() }
            results.done[f.rel] = outcome
            results.finished += 1
            let reported: FileProgress.Outcome
            var doneId: String? = nil
            switch outcome {
            case .failed(let failure): reported = .failed(failure)
            case .ok(let id, _):
                doneId = id
                if let seconds {
                    results.analysedSeconds.append(seconds)
                    results.analysedIDs.insert(id)
                    reported = .analysed(seconds: seconds)
                } else {
                    results.reused += 1
                    reported = .reused
                }
            }
            let elapsed = Date().timeIntervalSince(results.started)
            let remaining: Double? = results.analysedSeconds.isEmpty ? nil
                : elapsed / Double(results.finished) * Double(total - results.finished)
            progress(.file(FileProgress(done: results.finished, total: total, rel: f.rel, outcome: reported,
                                        elapsed: elapsed, remaining: remaining, id: doneId)))
        }
        done.merge(results.done) { _, new in new }

        // Places (D27): every file read now is a place of the entry for its bytes. A place belongs to this read when it
        // is on the source being read, or, for an ordinary folder, has no source or one not kept (`belongsToRead`);
        // those places are replaced by what is read now, own and other alike, and every other place stays.
        typealias Place = CrateTrack.Place
        typealias Reason = CrateManifest.ImportLog.Reason
        func belongsToRead(_ p: Place) -> Bool {
            if let s = options.source { return p.disc == s }
            return p.disc.map { !options.keepSources.contains($0) } ?? true
        }
        /// Where a file read now is: on a source, its place there; in an ordinary folder, no source and its folder.
        func placeRead(_ f: SourceFile) -> Place {
            let rel = String(f.rel.dropFirst(prefix.count))
            if let p = places[rel] { return Place(disc: p.source, folder: p.group, track: p.number) }
            return Place(disc: nil, folder: SourceReading.group(of: rel), track: nil)
        }

        // What the crate keeps from before: each entry with the places that do not belong to this read. Their
        // import-log entries stay too.
        var kept: [String: (entry: CrateTrack, own: Place?, others: [Place])] = [:]
        var keptEntries: [CrateManifest.ImportLog.Entry] = []
        if let existing {
            for t in existing.tracks {
                // An entry only in a folder on the Mac keeps no folder label; as a place, it is `file.rel`'s folder.
                var mine = t.ident.ownPlace
                if mine.disc == nil && mine.folder == nil { mine.folder = SourceReading.group(of: t.file.rel ?? "") }
                let own = belongsToRead(mine) ? nil : mine
                let others = t.ident.otherPlaces.filter { !belongsToRead($0) }
                if own != nil || !others.isEmpty { kept[t.id] = (t, own, others) }
            }
            for e in existing.manifest.importLog?.entries ?? [] {
                let fromSource = { (s: String) in e.rel.hasPrefix(s + "/") }
                let keep = options.source.map { !fromSource($0) } ?? options.keepSources.contains(where: fromSource)
                if keep { keptEntries.append(e) }
            }
        }
        let keptPlaces = kept.values.reduce(0) { $0 + ($1.own == nil ? 0 : 1) + $1.others.count }

        // The files read now, by their bytes: each file is a place of its entry. A second file with the same bytes
        // in a place already listed (two copies in one folder on the Mac, which has no numbers) is logged.
        var entries: [CrateManifest.ImportLog.Entry] = []
        for sf in skippedFolders {
            entries.append(.init(rel: sf.rel, ext: "", reason: Reason.skipped,
                                 message: "folder left out by the build's rule (its name starts with \"\(options.skipFolderPrefixes.first ?? "_")\"); "
                                 + "\(sf.audioFiles) audio file\(sf.audioFiles == 1 ? "" : "s") not looked at"))
        }
        var read: [String: [(file: Int, place: Place)]] = [:]
        var readOrder: [String] = []
        for (i, f) in files.enumerated() {
            switch done[f.rel] {
            case .failed(let failure)?:
                entries.append(.init(rel: f.rel, ext: f.ext, reason: failure.reason, message: failure.message))
            case .ok(let id, _)?:
                let p = placeRead(f)
                if let same = read[id]?.first(where: { $0.place == p }) {
                    entries.append(.init(rel: f.rel, ext: f.ext, reason: Reason.duplicate,
                                         message: "the same bytes as \(files[same.file].rel), which has the record"))
                    continue
                }
                if read[id] == nil {
                    guard work.record(id) != nil else {
                        entries.append(.init(rel: f.rel, ext: f.ext, reason: Reason.analysisError,
                                             message: "its finished record could not be read back from the work folder"))
                        continue
                    }
                    readOrder.append(id)
                }
                read[id, default: []].append((i, p))
            case nil:
                entries.append(.init(rel: f.rel, ext: f.ext, reason: Reason.analysisError, message: "not finished"))
            }
        }

        // One entry per file content, with every place it has. An entry whose own place stays (it is on a source not
        // read now) keeps its record and gains the places read now. Otherwise the place read now that leads by the
        // booth's rule (`CrateTrack.leadingPlace`: sources by name, then folder and number; no source last) is the
        // own place and its file gives the record (its name and path); the rest are other places. An entry not read
        // now whose own place was read away takes its leading other place as its own (`promoteOtherPlace`).
        func ordered(_ ps: [Place], without own: Place) -> [Place] {
            var seen: Set<Place> = [own]
            let unique = ps.filter { seen.insert($0).inserted }
            let items = unique.enumerated().map { SameSong.Place(id: String($0.offset), disc: $0.element.disc,
                                                                 folder: $0.element.folder, track: $0.element.track) }
            return SameSong.ordered(items, playingDisc: nil, discOrder: []).map { unique[Int($0.id)!] }
        }
        var tracks: [CrateTrack] = []
        for id in readOrder {
            let here = read[id]!
            let before = kept.removeValue(forKey: id)
            if let before, let own = before.own, own.disc != nil {
                var t = before.entry
                t.ident.otherPlaces = ordered(before.others + here.map(\.place), without: own)
                tracks.append(t)
                continue
            }
            let lead = CrateTrack.leadingPlace(here.map(\.place))!
            let from = here.first { $0.place == lead }!
            let f = files[from.file]
            guard case .ok(_, let tags)? = done[f.rel], let record = work.record(id) else { continue }
            var t = dressed(record, file: f, tags: tags, rekordbox: rekordboxOf[from.file], collection: collection,
                            importedAt: importedAt)
            // An ordinary folder's entry keeps no folder label of its own, as before: its place is `file.rel`'s.
            t.ident.ownPlace = options.source == nil ? Place(disc: nil, folder: nil, track: nil) : lead
            let rest = (before?.own.map { [$0] } ?? []) + (before?.others ?? []) + here.map(\.place).filter { $0 != lead }
            t.ident.otherPlaces = ordered(rest, without: t.ident.ownPlace)
            if let old = existing?.tracks.first(where: { $0.id == id }) {
                t.signatures = old.signatures
                // The same bytes are the same recording, so copies found before (D24) stay found.
                if t.ident.cutKey == nil { t.ident.cutKey = old.ident.cutKey }
                // An entry imported again unchanged keeps the time it was first imported, so a rebuild from the
                // same export leaves the record as it was.
                if var now = t.imported?.rekordbox, let was = old.imported?.rekordbox {
                    now.importedAt = was.importedAt
                    if now == was { t.imported?.rekordbox = was }
                }
            }
            tracks.append(t)
            // Analysed and in the crate, but faulty: the DJ is told where.
            if let frames = t.file.damagedFrames, !frames.isEmpty {
                entries.append(.init(rel: f.rel, ext: f.ext, reason: Reason.damagedFrames,
                                     message: Builder.damagedFramesMessage(frames)))
            }
        }
        for (_, k) in kept {
            var t = k.entry
            if let own = k.own {
                t.ident.otherPlaces = ordered(k.others, without: own)
            } else {
                t.ident.otherPlaces = k.others
                t.promoteOtherPlace()
                t.ident.otherPlaces = ordered(t.ident.otherPlaces, without: t.ident.ownPlace)
            }
            tracks.append(t)
        }

        // Files seen: this read's, plus those behind what is kept (a place each, and each logged file but a damaged
        // one, which has an entry too, or a left-out folder, which is not a file).
        let keptFiles = keptPlaces + keptEntries.filter { $0.reason != Reason.damagedFrames && $0.reason != Reason.skipped }.count
        entries = (keptEntries + entries).sorted { $0.rel.utf8.lexicographicallyPrecedes($1.rel.utf8) }

        let builtAt = utcNow()
        // built_by is the device label the records' analysis.device carries, never the machine's own name.
        let log = CrateManifest.ImportLog(builtBy: options.device, builtAt: builtAt, filesSeen: files.count + keptFiles,
                                          tracks: tracks.count, entries: entries, rekordbox: rbSummary)
        let devices = Set((existing?.manifest.devicesSeen ?? []) + [options.device]).sorted()
        let manifest = CrateManifest(
            crateId: existing?.manifest.crateId ?? UUID().uuidString.lowercased(),
            name: options.name ?? existing?.manifest.name ?? options.output.deletingPathExtension().lastPathComponent,
            createdAt: existing?.manifest.createdAt ?? builtAt, devicesSeen: devices, importLog: log)
        let crate = Crate(manifest: manifest, tracks: tracks.sorted { $0.id.utf8.lexicographicallyPrecedes($1.id.utf8) })
        progress(.writing(tracks: tracks.count))
        try CrateWriter.write(crate, to: options.output)
        var result = BuildResult(crate: crate, output: options.output, filesSeen: files.count,
                                 analysed: results.analysedSeconds.count, analysisSeconds: results.analysedSeconds,
                                 reused: readOrder.filter { !results.analysedIDs.contains($0) }.count,
                                 entries: entries, rekordbox: rbSummary, seconds: Date().timeIntervalSince(t0))
        let inCrate = Set(crate.tracks.map(\.id))
        for (id, list) in read where inCrate.contains(id) {
            result.placesRead[id] = list.map { ReadPlace(place: $0.place, rel: String(files[$0.file].rel.dropFirst(prefix.count))) }
        }
        return result
    }

    /// The crate already at the output, read so its id, name, creation date and devices are kept and its signatures
    /// carried over; nil when there is none.
    func existingCrate() throws -> Crate? {
        let fm = FileManager.default
        var isFolder: ObjCBool = false
        guard fm.fileExists(atPath: options.output.path, isDirectory: &isFolder) else { return nil }
        guard isFolder.boolValue else { throw BuildError("\(options.output.path) exists and is not a crate package") }
        guard fm.fileExists(atPath: options.output.appendingPathComponent(CrateFormat.manifestFile).path) else {
            let empty = (try? fm.contentsOfDirectory(atPath: options.output.path))?.isEmpty ?? false
            if empty { return nil }
            throw BuildError("\(options.output.path) exists and is not a crate package (no manifest.json)")
        }
        do {
            return try CrateReader.read(from: options.output)
        } catch {
            throw BuildError("the crate at \(options.output.path) cannot be read, so it is not overwritten:\n\(error)")
        }
    }

    /// One queued file: tags, hash, then the work folder's record for those bytes or a fresh analysis.
    private func process(_ f: SourceFile, rekordbox: RekordboxCollection.Track?, work: WorkStore, engine: Analyser,
                         label: String, seconds: inout Double?) -> Done {
        typealias R = CrateManifest.ImportLog.Reason
        let tags = FileTags.read(f.url)
        let tag = tagTempo(rekordbox: rekordbox, tags: tags)
        func line(_ status: String, id: String? = nil, failure: FileFailure? = nil) -> WorkStore.FileLine {
            .init(rel: f.rel, size: f.size, modified: f.modified, status: status, engine: label, id: id,
                  bpmTag: status == "ok" ? tag : nil, tags: tags.isEmpty ? nil : tags, reason: failure?.reason,
                  message: failure?.message)
        }
        func failed(_ failure: FileFailure) -> Done {
            if failure.isLasting { try? work.append(line("failed", failure: failure)) }
            return .failed(failure)
        }

        let data: Data
        do {
            data = try Data(contentsOf: f.url)
        } catch {
            return failed(FileFailure(reason: R.decodeError, message: "could not be read (\(error.localizedDescription))"))
        }
        let id = CrateIDs.id(forSHA256: CrateIDs.sha256(of: data))
        if let record = work.record(id), record.engine == label, record.bpmTag == tag {
            try? work.append(line("ok", id: id))
            return .ok(id: id, tags: tags)
        }
        do {
            let t0 = Date()
            let analysis = try engine.analyse(url: f.url, options: AnalysisOptions(bpmTag: tag))
            let elapsed = Date().timeIntervalSince(t0)
            var track = analysis.crateTrack(options: .init(analysedAt: utcNow(), device: options.device))
            track.file.rel = f.rel
            // A record the crate would refuse is this file's failure, not the whole crate's.
            let probe = CrateManifest(crateId: "probe", name: "probe", createdAt: utcNow(), devicesSeen: [])
            do {
                _ = try CrateWriter.encode(Crate(manifest: probe, tracks: [track]))
            } catch {
                return failed(FileFailure(reason: R.analysisError, message: "the record does not hold together: \(error)"))
            }
            try work.save(WorkStore.Record(engine: label, bpmTag: tag, track: track, bars: track.bars?.series,
                                           style: track.style?.values))
            try work.append(line("ok", id: analysis.id))
            seconds = elapsed
            return .ok(id: analysis.id, tags: tags)
        } catch {
            return failed(FileFailure.classify(error, path: f.url.path))
        }
    }

    /// The import log's words for a file's damaged frames, times as minutes and seconds from the start of the track:
    /// "damaged frame at 1:01.234 (26 ms), played as silence; the track is in the crate", or with several, "3 damaged
    /// frames, played as silence: at 0:12.345 (26 ms), ...; the track is in the crate" (the first 10 listed).
    static func damagedFramesMessage(_ frames: [CrateTrack.File.DamagedFrame]) -> String {
        func at(_ f: CrateTrack.File.DamagedFrame) -> String {
            let ms = Int((f.startS * 1000).rounded())
            return "at \(ms / 60_000):" + String(format: "%02d.%03d", ms / 1000 % 60, ms % 1000)
                + " (\(Int((f.seconds * 1000).rounded())) ms)"
        }
        var times = frames.prefix(10).map(at).joined(separator: ", ")
        if frames.count > 10 { times += " and \(frames.count - 10) more" }
        return frames.count == 1 ? "damaged frame \(times), played as silence; the track is in the crate"
            : "\(frames.count) damaged frames, played as silence: \(times); the track is in the crate"
    }

    /// A work record made ready for the crate: the file's current name and path, the track's names (from rekordbox,
    /// else the file's tags, else the file name), the DJ's key as a vote, and the `imported` block, its rekordbox entry
    /// taken at `importedAt`. The tag tempo is already in the record (`file.tag_bpm`), as the analysis was given it.
    func dressed(_ record: WorkStore.Record, file f: SourceFile, tags: FileTags?, rekordbox rb: RekordboxCollection.Track?,
                 collection: RekordboxCollection?, importedAt: String) -> CrateTrack {
        var t = record.crateTrack
        t.file.name = CratePath.lastName(f.rel)  // split on "/" only, on every platform (CratePath)
        t.file.rel = String(f.rel.dropFirst(options.logPrefix.count))
        let fileName = (t.file.name as NSString).deletingPathExtension
        if let name = rb?.name {
            t.ident.title = name
            t.ident.artist = rb?.artist
            t.ident.version = rb?.mix
            t.ident.source = "rekordbox-xml"
        } else if let title = tags?.title {
            t.ident.title = title
            t.ident.artist = tags?.artist
            t.ident.version = nil
            t.ident.source = "tag"
        } else {
            t.ident.title = fileName
            t.ident.artist = nil
            t.ident.version = nil
            t.ident.source = "filename"
        }
        if let tonality = rb?.tonality, let code = RekordboxCollection.camelot(fromTonality: tonality) {
            t.key?.votes["rekordbox-xml"] = code
        }
        // The DJ's own data under the name of the program it came from; null when nothing was imported.
        if let rb, let collection {
            t.imported = .init(rekordbox: collection.crateBlock(for: rb, importedAt: importedAt))
        } else {
            t.imported = nil
        }
        return t
    }
}
