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

    public init(folder: URL, output: URL, rekordbox: URL? = nil, jobs: Int = defaultJobs, fileBPMTags: Bool = false,
                fresh: Bool = false, name: String? = nil, device: String = Analysis.platform) {
        self.folder = folder; self.output = output; self.rekordbox = rekordbox; self.jobs = max(1, jobs)
        self.fileBPMTags = fileBPMTags; self.fresh = fresh; self.name = name; self.device = device
    }

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
    /// Files taken from the work folder: unchanged since the last run, or the same bytes found by their hash.
    public var reused: Int
    /// The files without a record of their own (the import log's entries).
    public var entries: [CrateManifest.ImportLog.Entry]
    public var rekordbox: CrateManifest.ImportLog.Rekordbox?
    /// Wall-clock seconds of the whole build.
    public var seconds: Double

    /// The summary printed at the end: the counts, the files not in the crate by reason and extension, and where the
    /// import log is.
    public var summary: String {
        var s = "\(filesSeen) audio file\(filesSeen == 1 ? "" : "s"): \(analysed) analysed"
        if analysed > 0, let m = mean(analysisSeconds) {
            s += " (\(Py.fixed(analysisSeconds.reduce(0, +), 1)) s of analysis, \(Py.fixed(m, 1)) s a file on average)"
        }
        s += ", \(reused) taken from the work folder, \(entries.count) not in the crate"
        if entries.isEmpty { s += "\n" } else {
            s += ":\n"
            let log = CrateManifest.ImportLog(builtBy: "", builtAt: "", filesSeen: 0, tracks: 0, entries: entries)
            let reasons = log.counts
            let known = CrateManifest.ImportLog.Reason.all
            for reason in known + reasons.keys.sorted().filter({ !known.contains($0) }) where reasons[reason] != nil {
                let byExt = reasons[reason]!
                let total = byExt.values.reduce(0, +)
                let list = byExt.keys.sorted().map { "\($0) \(byExt[$0]!)" }.joined(separator: ", ")
                s += "  " + reason.padding(toLength: 15, withPad: " ", startingAt: 0) + String(format: "%5d", total)
                    + "   " + list + "\n"
            }
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
/// file that has no record listed in the manifest's import log.
public final class Builder: Sendable {
    public static let version = "0.1.0"
    public static var builtBy: String { "deckie-build \(version)" }
    /// The work folder's extension.
    public static let workExtension = "deckiebuild"
    /// The engine's label (`deckie-0.1.0`, as `analysis.engine` writes it).
    public static var engineLabel: String { "\(Analysis.engineFamily)-\(Analysis.engineVersion)" }

    /// What a work record must have been made with to be reused: the engine's label and the vocal tagger's model, or
    /// none (`deckie-0.1.0 vocal:yamnet`, `deckie-0.1.0 vocal:none`), so records made before the vocal model was
    /// installed are made again once it is.
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
    func tagTempo(rekordbox: RekordboxCollection.Track?, tags: FileTags?) -> CrateTrack.Deckie.TagTempo? {
        if let bpm = rekordbox?.averageBpm { return .init(bpm: bpm, source: "rekordbox-xml") }
        if options.fileBPMTags, let bpm = tags?.bpm { return .init(bpm: bpm, source: "file-tag") }
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
        let files = try AudioFiles.find(in: options.folder)
        var collection: RekordboxCollection? = nil
        var matcher: RekordboxMatcher? = nil
        if let xml = options.rekordbox {
            let c = try RekordboxCollection.read(xml)
            collection = c
            matcher = RekordboxMatcher(c)
        }
        let existing = try existingCrate()
        let work = try WorkStore(folder: options.workFolder, fresh: options.fresh)
        let label = Builder.engineKey(vocalModel: vocalModel)
        let rekordboxOf = files.map { f in matcher?.match(absolutePath: f.url.path, rel: f.rel, size: f.size) }
        let rbSummary = collection.map {
            CrateManifest.ImportLog.Rekordbox(tracks: $0.tracks.count, matched: rekordboxOf.compactMap { $0 }.count)
        }

        // Files unchanged since a finished run (same size and modification time) are taken as they are.
        var done: [String: Done] = [:]
        var queue: [Int] = []
        for (i, f) in files.enumerated() {
            if let line = work.line(for: f.rel), line.size == f.size, line.modified == f.modified, line.engine == label {
                if line.status == "ok", let id = line.id,
                   tagTempo(rekordbox: rekordboxOf[i], tags: line.tags)?.bpm == line.bpmTag,
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
            switch outcome {
            case .failed(let failure): reported = .failed(failure)
            case .ok(let id, _):
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
                                        elapsed: elapsed, remaining: remaining)))
        }
        done.merge(results.done) { _, new in new }

        // The crate: files in path order; the first file with given bytes has the record, a copy is logged.
        var tracks: [CrateTrack] = []
        var entries: [CrateManifest.ImportLog.Entry] = []
        var firstWithID: [String: String] = [:]
        for (i, f) in files.enumerated() {
            switch done[f.rel] {
            case .failed(let failure)?:
                entries.append(.init(rel: f.rel, ext: f.ext, reason: failure.reason, message: failure.message))
            case .ok(let id, let tags)?:
                if let first = firstWithID[id] {
                    entries.append(.init(rel: f.rel, ext: f.ext, reason: CrateManifest.ImportLog.Reason.duplicate,
                                         message: "the same bytes as \(first), which has the record"))
                    continue
                }
                guard let record = work.record(id) else {
                    entries.append(.init(rel: f.rel, ext: f.ext, reason: CrateManifest.ImportLog.Reason.analysisError,
                                         message: "its finished record could not be read back from the work folder"))
                    continue
                }
                firstWithID[id] = f.rel
                var t = dressed(record, file: f, tags: tags, rekordbox: rekordboxOf[i], collection: collection)
                if let old = existing?.tracks.first(where: { $0.id == id }) { t.signatures = old.signatures }
                tracks.append(t)
            case nil:
                entries.append(.init(rel: f.rel, ext: f.ext, reason: CrateManifest.ImportLog.Reason.analysisError,
                                     message: "not finished"))
            }
        }

        let builtAt = utcNow()
        let log = CrateManifest.ImportLog(builtBy: Builder.builtBy, builtAt: builtAt, filesSeen: files.count,
                                          tracks: tracks.count, entries: entries, rekordbox: rbSummary)
        let devices = Set((existing?.manifest.devicesSeen ?? []) + [options.device]).sorted()
        let manifest = CrateManifest(
            crateId: existing?.manifest.crateId ?? UUID().uuidString.lowercased(),
            name: options.name ?? existing?.manifest.name ?? options.output.deletingPathExtension().lastPathComponent,
            createdAt: existing?.manifest.createdAt ?? builtAt, devicesSeen: devices, importLog: log)
        let crate = Crate(manifest: manifest, tracks: tracks.sorted { $0.id.utf8.lexicographicallyPrecedes($1.id.utf8) })
        progress(.writing(tracks: tracks.count))
        try CrateWriter.write(crate, to: options.output)
        return BuildResult(crate: crate, output: options.output, filesSeen: files.count,
                           analysed: results.analysedSeconds.count, analysisSeconds: results.analysedSeconds,
                           reused: tracks.filter { !results.analysedIDs.contains($0.id) }.count,
                           entries: entries, rekordbox: rbSummary, seconds: Date().timeIntervalSince(t0))
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
                  bpmTag: status == "ok" ? tag?.bpm : nil, tags: tags.isEmpty ? nil : tags, reason: failure?.reason,
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
        if let record = work.record(id), record.engine == label, record.bpmTag == tag?.bpm {
            try? work.append(line("ok", id: id))
            return .ok(id: id, tags: tags)
        }
        do {
            let t0 = Date()
            let analysis = try engine.analyse(url: f.url, options: AnalysisOptions(bpmTag: tag?.bpm))
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
            try work.save(WorkStore.Record(engine: label, bpmTag: tag?.bpm, track: track, bars: track.bars?.series,
                                           style: track.style?.values))
            try work.append(line("ok", id: analysis.id))
            seconds = elapsed
            return .ok(id: analysis.id, tags: tags)
        } catch {
            return failed(FileFailure.classify(error, path: f.url.path))
        }
    }

    /// A work record made ready for the crate: the file's current name and path, the track's names (from rekordbox,
    /// else the file's tags, else the file name), the DJ's key as a vote, and the `deckie` block.
    func dressed(_ record: WorkStore.Record, file f: SourceFile, tags: FileTags?, rekordbox rb: RekordboxCollection.Track?,
                 collection: RekordboxCollection?) -> CrateTrack {
        var t = record.crateTrack
        t.file.name = (f.rel as NSString).lastPathComponent
        t.file.rel = f.rel
        let fileName = ((f.rel as NSString).lastPathComponent as NSString).deletingPathExtension
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
        var block = CrateTrack.Deckie()
        if let bpm = record.bpmTag {
            block.bpmTag = .init(bpm: bpm, source: rb?.averageBpm == bpm ? "rekordbox-xml" : "file-tag")
        }
        if let rb, let collection { block.rekordbox = collection.crateBlock(for: rb) }
        t.deckie = block.bpmTag == nil && block.rekordbox == nil ? nil : block
        return t
    }
}
