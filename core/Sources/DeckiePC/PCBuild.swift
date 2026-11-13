import Foundation
import DeckieBuild
import DeckieCore
import DeckieCrate
import DeckieEngine
import DeckieInference

/// The run behind the PC program a DJ drags a music folder onto (D29, first step): read the folder, make the crate
/// file in its single-file form next to the folder (never inside it), named after the folder, say in plain words what
/// went in and what did not, and write a log beside the crate file. Everything a second run can reuse is kept out of
/// the DJ's sight, in the program's own storage, so only the crate file and the log appear beside the music.
///
/// It is the command-line builder (`Builder`) with nothing changed inside: the same engine, the same records, the
/// same import log. What is added is where things go, the words, the log, and the single file at the end.
public struct PCBuild: Sendable {
    public static let version = "0.1.0"

    /// The engine's files: ONNX Runtime's library and the two models.
    public struct EngineFiles: Sendable {
        public var library: String
        public var beatModel: String
        /// The vocal tagger's model; without it the records have no vocal block (flag `vocal_unknown`).
        public var vocalModel: String?
        public init(library: String, beatModel: String, vocalModel: String?) {
            self.library = library; self.beatModel = beatModel; self.vocalModel = vocalModel
        }

        /// Where the engine's files are: the environment variables the core already reads if they are set; else in
        /// `folder` (the folder the program is in, as the zip lays it out: `onnxruntime.dll` or its name on this
        /// platform, and `models/`); else the checkout's defaults, for a developer's run. Throws `PCError.partsMissing`
        /// naming what was not found.
        public static func locate(beside folder: URL?) throws -> EngineFiles {
            let fm = FileManager.default
            let env = ProcessInfo.processInfo.environment
            func first(_ candidates: [String?]) -> String? { candidates.compactMap { $0 }.first { fm.fileExists(atPath: $0) } }
            let library = first([env[OnnxRuntime.libraryEnvironmentVariable],
                                 folder?.appendingPathComponent(OnnxRuntime.libraryFileName).path,
                                 OnnxRuntime.locateLibrary()])
            let beat = first([env[BeatTracker.modelEnvironmentVariable],
                              folder?.appendingPathComponent("models").appendingPathComponent(BeatTracker.modelFileName).path,
                              BeatTracker.locateModel()])
            let vocal = first([env[YAMNet.modelEnvironmentVariable],
                               folder?.appendingPathComponent("models").appendingPathComponent(YAMNet.modelFileName).path,
                               YAMNet.locateModel()])
            guard let library else { throw PCError.partsMissing(OnnxRuntime.libraryFileName) }
            guard let beat else { throw PCError.partsMissing("models/" + BeatTracker.modelFileName) }
            return EngineFiles(library: library, beatModel: beat, vocalModel: vocal)
        }

        /// One analyser for all jobs, as `Builder.makeAnalyser` makes it, from these files.
        public func analyser(jobs: Int) throws -> Analyser {
            let threads = jobs <= 1 ? 0 : max(1, processorCount / jobs)
            let options = OnnxRuntime.SessionOptions(intraOpThreads: threads)
            let runtime = try OnnxRuntime.load(libraryPath: library)
            let tracker = try BeatTracker(modelPath: beatModel, runtime: runtime, options: options)
            let tagger = try vocalModel.map {
                DeckieVocalTagger(yamnet: try YAMNet(modelPath: $0, runtime: runtime, options: options))
            }
            return try Analyser(beatTracker: tracker, vocalTagger: tagger)
        }
    }

    /// Where one run reads and writes.
    public struct Plan: Sendable, Equatable {
        /// The music folder.
        public var folder: URL
        /// The crate's name: the folder's.
        public var name: String
        /// The crate file, single-file form: next to the music folder, `<name>.deckiecrate`.
        public var crateFile: URL
        /// The log, beside the crate file: `<name> Deckie log.txt`.
        public var logFile: URL
        /// The program's own storage for this folder: the crate as a package and the builder's work folder.
        public var work: URL
        /// True when the crate file could not go next to the music folder and went to `crateFile`'s folder instead.
        public var elsewhere: Bool

        var package: URL { work.appendingPathComponent(name + "." + CrateFormat.packageExtension) }
    }

    /// The jobs to run at once on this machine: research P's rule (docs/research/p-machine-estimates.md, summary 5),
    /// one job for every two processors, each given 1 GB, leaving the larger of 3 GB and a quarter of memory for
    /// everything else, so a laptop with 8 GB runs at most 5 and stays usable.
    public static var defaultJobs: Int {
        let gb = Double(ProcessInfo.processInfo.physicalMemory) / Double(1 << 30)
        return max(1, min(processorCount / 2, Int(gb - max(3, gb / 4))))
    }

    /// The program's own storage: `%LOCALAPPDATA%\Deckie` on Windows, `~/.cache/deckie` elsewhere.
    public static var defaultWorkRoot: URL {
        let env = ProcessInfo.processInfo.environment
        if let local = env["LOCALAPPDATA"], !local.isEmpty {
            return URL(fileURLWithPath: local).appendingPathComponent("Deckie").appendingPathComponent("builds")
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/deckie/builds")
    }

    /// Plans a run for `folder`. The crate file goes into the folder that holds the music folder; when that cannot
    /// be written (a drive's top folder, a read-only disc), into `fallback` (the DJ's Documents folder).
    public static func plan(folder: URL, workRoot: URL = defaultWorkRoot, fallback: URL? = nil) throws -> Plan {
        let fm = FileManager.default
        let folder = folder.standardizedFileURL
        var isFolder: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isFolder) else { throw PCError.notThere(folder.path) }
        guard isFolder.boolValue else { throw PCError.isAFile(folder.lastPathComponent) }

        let parent = folder.deletingLastPathComponent().standardizedFileURL
        let isTop = parent.path == folder.path || folder.pathComponents.count <= 1
        var name = isTop ? "" : folder.lastPathComponent
        // A drive's top folder has no name of its own ("D:\").
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "/\\: ")).isEmpty ? "Music" : name
        var out = parent
        var elsewhere = false
        if isTop || !canWrite(in: parent) {
            let other = fallback ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? fm.homeDirectoryForCurrentUser
            try? fm.createDirectory(at: other, withIntermediateDirectories: true)
            out = other
            elsewhere = true
        }
        // The storage for this folder: its name, and eight digits of the hash of its path so two folders with one
        // name do not share.
        let digest = CrateIDs.id(forSHA256: CrateIDs.sha256(of: Data(folder.path.lowercased().utf8)))
        let work = workRoot.appendingPathComponent(safe(name) + "-" + digest.prefix(8))
        return Plan(folder: folder, name: name,
                    crateFile: out.appendingPathComponent(name + "." + CrateFormat.packageExtension),
                    logFile: out.appendingPathComponent(name + " Deckie log.txt"), work: work, elsewhere: elsewhere)
    }

    static func canWrite(in folder: URL) -> Bool {
        let probe = folder.appendingPathComponent(".deckie-write-test-\(UUID().uuidString)")
        guard (try? Data().write(to: probe)) != nil else { return false }
        try? FileManager.default.removeItem(at: probe)
        return true
    }

    /// `name` with only characters every file system takes.
    static func safe(_ name: String) -> String {
        let kept = name.unicodeScalars.map { s -> Character in
            (s.isASCII && (CharacterSet.alphanumerics.contains(s) || "-_ ".unicodeScalars.contains(s))) ? Character(s) : "_"
        }
        return String(String(kept).prefix(40))
    }

    /// What a run did.
    public struct Outcome: Sendable {
        public var plan: Plan
        /// Songs in the crate file.
        public var songs: Int
        public var filesFound: Int
        /// Read in this run, and the seconds each took.
        public var readNow: Int
        public var secondsPerSong: [Double]
        /// The files that are not in the crate file, by reason then type, with a count.
        public var notAdded: [(reason: String, ext: String, count: Int)]
        public var copies: Int
        public var damagedSpots: Int
        public var seconds: Double
        public var jobs: Int
    }

    /// Runs the build for `plan`, saying each line through `say`. Writes the crate file and the log; on failure writes
    /// the log with what went wrong and rethrows as `PCError`.
    public static func run(_ plan: Plan, engine: EngineFiles, jobs: Int = defaultJobs,
                           say: @escaping @Sendable (String) -> Void) throws -> Outcome {
        let started = Date()
        var log = RunLog(plan: plan, jobs: jobs, engine: engine)
        do {
            let outcome = try build(plan, engine: engine, jobs: jobs, started: started, log: &log, say: say)
            log.finish(outcome)
            try? log.text.write(to: plan.logFile, atomically: true, encoding: .utf8)
            return outcome
        } catch {
            let what = (error as? PCError)?.words ?? scrub("\(error)", plan)
            log.failed(what, seconds: Date().timeIntervalSince(started))
            try? log.text.write(to: plan.logFile, atomically: true, encoding: .utf8)
            throw (error as? PCError) ?? PCError.failed(what)
        }
    }

    private static func scrub(_ text: String, _ plan: Plan) -> String {
        text.replacingOccurrences(of: plan.folder.path, with: "<music folder>")
            .replacingOccurrences(of: plan.work.path, with: "<Deckie's storage>")
            .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "<home>")
    }

    private static func build(_ plan: Plan, engine: EngineFiles, jobs: Int, started: Date, log: inout RunLog,
                              say: @escaping @Sendable (String) -> Void) throws -> Outcome {
        let fm = FileManager.default
        say(PCWords.reading(plan.name))

        // What is already next to the music folder under the crate file's name: a crate file from an earlier run is
        // replaced at the end; anything else is never overwritten.
        var isFolder: ObjCBool = false
        let exists = fm.fileExists(atPath: plan.crateFile.path, isDirectory: &isFolder)
        if exists {
            guard !isFolder.boolValue, (try? CrateReader.read(from: plan.crateFile)) != nil else {
                throw PCError.inTheWay(plan.crateFile.lastPathComponent)
            }
        }
        try fm.createDirectory(at: plan.work, withIntermediateDirectories: true)
        // The crate as a package in the program's storage carries the crate's id and name from run to run. When the
        // storage is gone but the crate file is there (another PC, a cleared profile), it is unpacked first.
        let hasPackage = fm.fileExists(atPath: plan.package.appendingPathComponent(CrateFormat.manifestFile).path)
        if !hasPackage, exists { try CrateArchive.unpack(plan.crateFile, to: plan.package) }
        if hasPackage, (try? CrateReader.read(from: plan.package)) == nil { try? fm.removeItem(at: plan.package) }

        let options = BuildOptions(folder: plan.folder, output: plan.package, jobs: jobs, name: plan.name,
                                   skipFolderPrefixes: [])
        guard try !AudioFiles.find(in: plan.folder).isEmpty else { throw PCError.noSongs(plan.name) }
        let builder = try Builder(options: options, analyser: try engine.analyser(jobs: jobs))

        final class Counter: @unchecked Sendable { var files = 0; var unchanged = 0 }
        let counter = Counter()
        let result = try builder.run { event in
            switch event {
            case .started(let files, let unchanged, let queued, _, _):
                counter.files = files; counter.unchanged = unchanged
                say(PCWords.found(songs: files, toRead: queued))
            case .file(let p):
                let name = CratePath.lastName(p.rel)
                let done = counter.unchanged + p.done
                switch p.outcome {
                case .analysed, .reused:
                    say(PCWords.progress(done: done, of: counter.files, name: name, left: p.remaining))
                case .failed(let failure):
                    say(PCWords.progressNotRead(done: done, of: counter.files, name: name, left: p.remaining,
                                                why: PCWords.why(reason: failure.reason,
                                                                 ext: CratePath.fileExtension(of: name).lowercased())))
                }
            case .writing:
                say(PCWords.writing)
            }
        }

        // The package as one file, checked by reading it back before the DJ is told it is there.
        let staged = plan.work.appendingPathComponent("staged." + CrateFormat.packageExtension)
        try CrateArchive.pack(package: plan.package, to: staged)
        guard try CrateReader.read(from: staged) == CrateReader.read(from: plan.package) else { throw PCError.failed("the crate file did not read back as it was written") }
        if fm.fileExists(atPath: plan.crateFile.path) { try fm.removeItem(at: plan.crateFile) }
        try fm.moveItem(at: staged, to: plan.crateFile)

        typealias R = CrateManifest.ImportLog.Reason
        let entries = result.entries
        var groups: [String: Int] = [:]
        for e in entries where e.reason != R.damagedFrames && e.reason != R.duplicate && e.reason != R.skipped {
            groups[e.reason + "\n" + e.ext, default: 0] += 1
        }
        let order = R.all
        let notAdded = groups.map { key, n -> (reason: String, ext: String, count: Int) in
            let parts = key.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            return (parts[0], parts[1], n)
        }.sorted {
            let a = order.firstIndex(of: $0.reason) ?? order.count, b = order.firstIndex(of: $1.reason) ?? order.count
            return a != b ? a < b : $0.ext < $1.ext
        }
        log.entries = entries
        return Outcome(plan: plan, songs: result.crate.tracks.count, filesFound: result.filesSeen,
                       readNow: result.analysed, secondsPerSong: result.analysisSeconds, notAdded: notAdded,
                       copies: entries.filter { $0.reason == R.duplicate }.count,
                       damagedSpots: entries.filter { $0.reason == R.damagedFrames }.count,
                       seconds: Date().timeIntervalSince(started), jobs: jobs)
    }

    /// The closing words for a finished run.
    public static func summary(_ o: Outcome) -> String {
        var lines = ["", PCWords.done(songs: o.songs)]
        let total = o.notAdded.reduce(0) { $0 + $1.count }
        if total > 0 {
            lines.append(PCWords.notAdded(total))
            // One line per reason, its types counted: "12  AAC and Apple Lossless ... (m4a 12)".
            var seen: [String] = []
            for item in o.notAdded where !seen.contains(item.reason) {
                seen.append(item.reason)
                let same = o.notAdded.filter { $0.reason == item.reason }
                let why = same.count == 1 ? PCWords.why(reason: item.reason, ext: item.ext)
                    : PCWords.why(reason: item.reason, ext: Set(same.map { PCWords.why(reason: $0.reason, ext: $0.ext) }).count == 1 ? item.ext : "")
                lines.append(PCWords.notAddedLine(same.reduce(0) { $0 + $1.count }, why,
                                                  types: same.map { "\($0.ext.isEmpty ? "no type" : $0.ext) \($0.count)" }.joined(separator: ", ")))
            }
        }
        if o.copies > 0 { lines.append(PCWords.copies(o.copies)) }
        if o.damagedSpots > 0 { lines.append(PCWords.damagedSpots(o.damagedSpots)) }
        lines.append(PCWords.took(o.seconds))
        lines.append("")
        if o.plan.elsewhere { lines.append(PCWords.writtenElsewhere(o.plan.crateFile.deletingLastPathComponent().path)) }
        lines.append(PCWords.crateFileIs(o.plan.crateFile.path))
        lines.append(PCWords.logIs(o.plan.logFile.path))
        lines.append("")
        lines.append(PCWords.notYet)
        return lines.joined(separator: "\n")
    }
}

/// What stops a run, each with its plain words.
public enum PCError: Error, Equatable {
    case notThere(String)
    case isAFile(String)
    case noSongs(String)
    case inTheWay(String)
    case partsMissing(String)
    case failed(String)

    public var words: String {
        switch self {
        case .notThere(let path): return PCWords.notThere(path)
        case .isAFile(let name): return PCWords.isAFile(name)
        case .noSongs(let name): return PCWords.noSongs(name)
        case .inTheWay(let name): return PCWords.inTheWay(name)
        case .partsMissing(let what): return PCWords.partsMissing(what)
        case .failed(let what): return PCWords.wentWrong(what)
        }
    }
}

/// The log written beside the crate file: what the program and the machine are, what was counted, how long it took,
/// and each file that is not in the crate file with its reason. No song audio and nothing about the songs that are
/// in; a file's name appears only when the file could not be added or has a damaged spot, as its path below the music
/// folder. The music folder's own path is not written (it usually holds the Windows user name), only its name.
struct RunLog {
    var lines: [String] = []
    var entries: [CrateManifest.ImportLog.Entry] = []

    init(plan: PCBuild.Plan, jobs: Int, engine: PCBuild.EngineFiles) {
        let info = ProcessInfo.processInfo
        let f = ISO8601DateFormatter()
        lines = [
            "Deckie for PC, first test: log of one run",
            "What is in this file: the program's version, this computer's type, counts, timings, and the files that could",
            "not be added with the reason for each. No song audio. File names only for files that could not be added or",
            "have a damaged spot.",
            "",
            "program: deckie-make \(PCBuild.version), builder \(Builder.version), engine \(Builder.engineLabel)",
            "vocal model: \(engine.vocalModel == nil ? "missing" : "present")",
            "platform: \(Analysis.platform)",
            "system: \(info.operatingSystemVersionString)",
            "processors: \(info.activeProcessorCount), memory: \(String(format: "%.1f", Double(info.physicalMemory) / Double(1 << 30))) GB, songs read at once: \(jobs)",
            "started (UTC): \(f.string(from: Date()))",
            "music folder's name: \(plan.name)",
            "crate file written next to the music folder: \(plan.elsewhere ? "no, in the Documents folder" : "yes")",
        ]
    }

    mutating func finish(_ o: PCBuild.Outcome) {
        typealias R = CrateManifest.ImportLog.Reason
        lines += ["", "result: finished",
                  "music files found: \(o.filesFound)", "songs in the crate file: \(o.songs)",
                  "read in this run: \(o.readNow)", "whole run: \(String(format: "%.1f", o.seconds)) s"]
        if !o.secondsPerSong.isEmpty {
            let s = o.secondsPerSong.sorted()
            lines.append("seconds per song (each song's own reading time): mean \(String(format: "%.1f", s.reduce(0, +) / Double(s.count))), "
                         + "median \(String(format: "%.1f", s[s.count / 2])), longest \(String(format: "%.1f", s.last!))")
            lines.append("seconds per song by the clock (the run's reading time over the songs read, \(o.jobs) at once): "
                         + String(format: "%.1f", o.seconds / Double(max(1, o.readNow))))
        }
        let left = entries.filter { $0.reason != R.damagedFrames }
        let damaged = entries.filter { $0.reason == R.damagedFrames }
        lines += ["", "files not added: \(left.count)"]
        for e in left { lines.append("  \(e.reason)  \(e.rel)  [\(e.message)]") }
        if !damaged.isEmpty {
            lines += ["", "songs added that have a damaged spot: \(damaged.count)"]
            for e in damaged { lines.append("  \(e.rel)  [\(e.message)]") }
        }
    }

    mutating func failed(_ what: String, seconds: Double) {
        lines += ["", "result: stopped without writing a crate file, after \(String(format: "%.1f", seconds)) s", "why: \(what)"]
    }

    /// Windows line endings, so Notepad on any Windows shows it as written.
    var text: String { lines.joined(separator: "\r\n") + "\r\n" }
}
