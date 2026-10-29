import Foundation
import DeckieCore
import DeckieEngine
import DeckieLab

/// What the bench is asked to do (`deckie-build bench <folder> --features ... --candidates ...`).
public struct BenchOptions: Sendable {
    /// Where the lab's audio is on this machine.
    public var folder: URL
    /// The lab's feature files (mixer/features).
    public var features: URL
    /// The lab's candidates (mixer/candidates.json): each row's `path` and `id`.
    public var candidates: URL
    /// The folder the rows' paths start with on the lab's machine; nil takes the folder the paths share.
    public var musicRoot: String?
    /// The bench's JSON; nil writes none.
    public var output: URL?
    /// Where the engine's records are kept, one lab-shaped JSON per track (`<id>.json`, beside the lab's own for the
    /// lab's tools), and taken again on a later run when the file, the tag tempo and the engine are the same; nil
    /// keeps none. The default is `<output>.records` beside the JSON.
    public var records: URL?
    /// Tracks analysed at once (`defaultJobs`).
    public var jobs: Int
    /// Only these lab ids.
    public var ids: [String]?
    /// Analyse every track again, ignoring kept records.
    public var fresh: Bool

    public init(folder: URL, features: URL, candidates: URL, musicRoot: String? = nil, output: URL? = nil,
                records: URL? = nil, jobs: Int = defaultJobs, ids: [String]? = nil, fresh: Bool = false) {
        self.folder = folder; self.features = features; self.candidates = candidates; self.musicRoot = musicRoot
        self.output = output; self.jobs = max(1, jobs); self.ids = ids; self.fresh = fresh
        self.records = records ?? output.map {
            $0.deletingLastPathComponent().appendingPathComponent($0.deletingPathExtension().lastPathComponent + ".records")
        }
    }
}

/// The bench's result: one score per track found and analysed, the summary, and what could not be compared.
public struct BenchReport: Sendable {
    public var musicRoot: String
    public var candidates: Int
    public var scores: [TrackScore]
    public var summary: BenchSummary
    /// Lab tracks whose audio is not under the folder (lab id and the path looked for, below the folder).
    public var notFound: [(id: String, rel: String)]
    /// Tracks found but not analysed: the lab id, the path below the folder and why.
    public var failed: [(id: String, rel: String, failure: FileFailure)]
    /// Records taken from the records folder.
    public var reused: Int

    public func json() -> JSONValue {
        .object([
            .init("tool", .string(Builder.builtBy)), .init("engine", .string(Builder.engineLabel)),
            .init("platform", .string(Analysis.platform)), .init("music_root", .string(musicRoot)),
            .init("candidates", .int(candidates)), .init("compared", .int(scores.count)),
            .init("taken_from_records", .int(reused)),
            .init("not_found", .array(notFound.map { .object([.init("id", .string($0.id)), .init("rel", .string($0.rel))]) })),
            .init("failed", .array(failed.map {
                .object([.init("id", .string($0.id)), .init("rel", .string($0.rel)), .init("reason", .string($0.failure.reason)),
                         .init("message", .string($0.failure.message))])
            })),
            .init("summary", summary.json()),
            .init("tracks", .array(scores.map { $0.json() })),
        ])
    }

    /// The bench as text: a line per track, then the summary and the pass marks.
    public var table: String {
        func f(_ x: Double?, _ d: Int = 3, signed: Bool = false) -> String {
            guard let x else { return "-" }
            return (signed && x >= 0 ? "+" : "") + Py.fixed(x, d)
        }
        func pad(_ s: String, _ n: Int, left: Bool = false) -> String {
            s.count >= n ? String(s.prefix(n)) : (left ? String(repeating: " ", count: n - s.count) + s
                                                       : s + String(repeating: " ", count: n - s.count))
        }
        var out = "Bench: \(candidates) lab tracks, \(scores.count) compared"
        out += " (\(reused) taken from the records folder), \(notFound.count) not found under the folder, "
            + "\(failed.count) failed\n\n"
        let head = [pad("id", 11), pad("title", 24), pad("beatF det", 9, left: true), pad("grid", 6, left: true),
                    pad("dbF det", 8, left: true), pad("grid", 6, left: true), pad("bpm e/l", 8, left: true),
                    pad("key", 9, left: true), pad("LU d", 6, left: true), pad("TP d", 6, left: true),
                    pad("sec r", 6, left: true), pad("voc r", 6, left: true), pad("bar1 ms", 8, left: true),
                    pad("bars e/l", 9, left: true)]
        out += head.joined(separator: " ") + "\n"
        for s in scores {
            out += [pad(s.id, 11), pad(s.title ?? "", 24), pad(f(s.beatFDetected), 9, left: true),
                    pad(f(s.beatFGrid), 6, left: true), pad(f(s.downbeatFDetected), 8, left: true),
                    pad(f(s.downbeatFGrid), 6, left: true), pad(f(s.bpmRatio, 4), 8, left: true),
                    pad(s.keyRelation, 9, left: true), pad(f(s.lufsDelta, 2, signed: true), 6, left: true),
                    pad(f(s.truePeakDelta, 2, signed: true), 6, left: true), pad(f(s.sectionRecall, 2), 6, left: true),
                    pad(f(s.vocalR, 2), 6, left: true), pad(f(s.bar1OffsetMs, 1, signed: true), 8, left: true),
                    pad("\(s.nBarsEngine)/\(s.nBarsLab)", 9, left: true)].joined(separator: " ") + "\n"
        }
        for x in failed { out += "\(pad(x.id, 11)) \(x.rel): \(x.failure.reason): \(x.failure.message)\n" }
        let m = summary
        func stat(_ name: String, _ s: BenchSummary.Stat, _ d: Int = 3) -> String {
            var line = "  " + pad(name, 42) + " median \(f(s.median, d))  mean \(f(s.mean, d))"
            if let b = s.below08 { line += "  below 0.8: \(Py.fixed(100 * b, 1)) percent" }
            if let a = s.medianAbs { line += "  median |x| \(f(a, d))" }
            return line + "  (n \(s.n))\n"
        }
        func pct(_ x: Double?) -> String { x.map { Py.fixed(100 * $0, 1) + " percent" } ?? "-" }
        out += "\nOver \(m.tracks) tracks:\n"
        out += stat("beat F@70ms, detected vs detected", m.beatFDetected)
        out += stat("beat F@70ms, grid vs grid", m.beatFGrid)
        out += stat("beat F, best octave", m.beatFBestOctave)
        out += stat("downbeat F, detected vs detected", m.downbeatFDetected)
        out += stat("downbeat F, grid vs grid", m.downbeatFGrid)
        for (source, s) in m.gridByLabSource.sorted(by: { $0.key < $1.key }) {
            out += stat("  lab grid from \(source): beat, grid", s.beat)
            out += stat("  lab grid from \(source): downbeat, grid", s.downbeat)
        }
        out += "  tempo within 2 percent: \(pct(m.tempoWithin2Octave)) after octave normalisation, \(pct(m.tempoWithin2)) "
            + "without; an octave apart: \(pct(m.octaveApart))\n"
        out += "  key, all tracks: exact \(pct(m.keyAll["exact"])), neighbour \(pct(m.keyAll["neighbour"])), other "
            + "\(pct(m.keyAll["other"]))\n"
        out += "  key, lab confident (\(m.keyConfidentCount)): exact \(pct(m.keyConfident["exact"])), neighbour "
            + "\(pct(m.keyConfident["neighbour"])), other \(pct(m.keyConfident["other"]))\n"
        out += stat("integrated loudness delta (LU)", m.lufsDelta, 2)
        out += "  " + pad("", 42) + " more than 1 LU off: \(pct(m.lufsOver1))\n"
        out += stat("true peak delta (dB)", m.truePeakDelta, 2)
        out += stat("section recall (within a bar)", m.sectionRecall, 2)
        out += stat("section precision", m.sectionPrecision, 2)
        out += m.vocalR.n == 0 ? "  vocal correlation: absent (no vocal tagger yet)\n" : stat("vocal correlation", m.vocalR, 2)
        out += stat("bar 1 offset (ms, engine - lab)", m.bar1OffsetMs, 1)
        out += "  bar counts equal: \(pct(m.nBarsMatch))\n"
        if m.seconds.n > 0 {
            out += "  seconds per track: median \(f(m.seconds.median, 1)), p90 \(f(m.secondsP90, 1)), max "
                + "\(f(m.seconds.maxAbs, 1)) (n \(m.seconds.n))\n"
        }
        out += "\nPass marks (charter: at least Apple's framework on beats and loudness, stage 1 1a; the key estimator's 75 "
            + "percent exact). Reference marks are Apple's other figures:\n"
        for k in m.marks {
            let verdict = k.pass.map { $0 ? "pass" : "FAIL" } ?? "n/a"
            out += "  " + pad(k.charter ? "charter" : "reference", 9) + " " + pad(k.name, 56) + " "
                + pad(f(k.value, k.decimals), 7, left: true) + "  \(k.rule) \(Py.fixed(k.target, k.decimals))  \(verdict)\n"
        }
        out += "charter pass marks: " + (m.charterPass.map { $0 ? "all met" : "not all met" } ?? "not all measurable") + "\n"
        return out
    }
}

/// The yardstick bench (charter step 6): the engine run over the lab's tracks, each record compared with the lab's
/// committed feature file by the stage 1 measures.
public enum Bench {
    /// The folder `paths` share, without a trailing slash (`/` when they share nothing).
    public static func commonFolder(_ paths: [String]) -> String {
        let folders = paths.map { $0.split(separator: "/", omittingEmptySubsequences: false).dropLast().map(String.init) }
        guard var common = folders.first else { return "/" }
        for f in folders.dropFirst() {
            var n = 0
            while n < common.count && n < f.count && common[n] == f[n] { n += 1 }
            common = Array(common.prefix(n))
        }
        let joined = common.joined(separator: "/")
        return joined.isEmpty ? "/" : joined
    }

    private final class Collected: @unchecked Sendable {
        let lock = NSLock()
        var scores: [Int: TrackScore] = [:]
        var failed: [Int: FileFailure] = [:]
        var reused = 0
        var done = 0
    }

    /// Runs the bench, reporting each finished track through `progress` (one line each).
    public static func run(_ o: BenchOptions, analyser: Analyser? = nil,
                           progress: @escaping @Sendable (String) -> Void = { _ in }) throws -> BenchReport {
        let rows = try CandidateRecord.loadAll(o.candidates)
        let paths = rows.compactMap(\.path)
        let root = o.musicRoot.map { $0.hasSuffix("/") && $0.count > 1 ? String($0.dropLast()) : $0 } ?? commonFolder(paths)
        let prefix = root == "/" ? "/" : root + "/"
        let wanted = o.ids.map(Set.init)

        struct Job { var row: CandidateRecord; var url: URL; var rel: String; var lab: URL }
        var jobs: [Job] = []
        var notFound: [(id: String, rel: String)] = []
        for row in rows where wanted?.contains(row.id) ?? true {
            guard let path = row.path, path.hasPrefix(prefix) else {
                notFound.append((row.id, row.path ?? "(no path)"))
                continue
            }
            let rel = String(path.dropFirst(prefix.count))
            let url = o.folder.appendingPathComponent(rel)
            let lab = o.features.appendingPathComponent("\(row.id).json")
            guard FileManager.default.fileExists(atPath: lab.path) else { continue }
            guard FileManager.default.fileExists(atPath: url.path) else {
                notFound.append((row.id, rel))
                continue
            }
            jobs.append(Job(row: row, url: url, rel: rel, lab: lab))
        }
        if let records = o.records { try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true) }
        if analyser == nil && !jobs.isEmpty { try Builder.checkEngine() }
        let engine = jobs.isEmpty ? nil : try analyser ?? Builder.makeAnalyser(jobs: min(o.jobs, jobs.count))
        let label = Builder.engineLabel
        let collected = Collected()
        let all = jobs
        progress("bench: \(rows.count) lab tracks; \(all.count) found under \(o.folder.path) (music root on the lab's "
                 + "machine: \(root)), \(notFound.count) not found; \(min(o.jobs, max(all.count, 1))) at a time")
        let t0 = Date()
        runParallel(count: all.count, workers: o.jobs) { k in
            let job = all[k]
            let decoder = JSONDecoder()
            var seconds: Double? = nil
            var reused = false
            let outcome: Result<TrackScore, Error> = Result {
                let lab = try decoder.decode(BenchRecord.self, from: Data(contentsOf: job.lab))
                let tag = job.row.bpmTag.flatMap { $0 > 0 ? $0 : nil } ?? lab.bpmTag
                let size = ((try? FileManager.default.attributesOfItem(atPath: job.url.path))?[.size] as? NSNumber)?.intValue
                let kept = o.records?.appendingPathComponent("\(job.row.id).json")
                var engineData: Data? = nil
                if !o.fresh, let kept, let data = try? Data(contentsOf: kept),
                   let old = try? decoder.decode(BenchRecord.self, from: data),
                   old.deckie?.engine == label, old.deckie?.bytes == size, old.bpmTag == tag {
                    engineData = data
                    reused = true
                }
                if engineData == nil {
                    let t = Date()
                    let a = try engine!.analyse(url: job.url, options: AnalysisOptions(bpmTag: tag, title: job.row.title))
                    seconds = Date().timeIntervalSince(t)
                    let data = a.labJSONData()
                    if let kept { try data.write(to: kept, options: .atomic) }
                    engineData = data
                }
                let mine = try decoder.decode(BenchRecord.self, from: engineData!)
                var score = BenchMetrics.compare(engine: mine, lab: lab, rel: job.rel, seconds: seconds)
                score.id = job.row.id  // the candidates row's id, which names the lab's file
                return score
            }
            collected.lock.lock()
            defer { collected.lock.unlock() }
            collected.done += 1
            let count = "[\(collected.done)/\(all.count)] \(clock(Date().timeIntervalSince(t0)))"
            switch outcome {
            case .success(let s):
                collected.scores[k] = s
                if reused { collected.reused += 1 }
                let how = reused ? "kept record" : seconds.map { Py.fixed($0, 1) + " s" } ?? ""
                progress("\(count)  \(how)  \(job.row.id)  beat F \(s.beatFDetected.map { Py.fixed($0, 3) } ?? "-")  "
                         + "grid \(s.beatFGrid.map { Py.fixed($0, 3) } ?? "-")  bpm x\(Py.fixed(s.bpmRatio, 4))  "
                         + "key \(s.keyRelation)  \(job.rel)")
            case .failure(let error):
                let f = FileFailure.classify(error, path: job.url.path)
                collected.failed[k] = f
                progress("\(count)  \(f.reason)  \(job.row.id)  \(job.rel): \(f.message)")
            }
        }
        let scores = (0..<all.count).compactMap { collected.scores[$0] }
        let failed = (0..<all.count).compactMap { k in collected.failed[k].map { (all[k].row.id, all[k].rel, $0) } }
        let report = BenchReport(musicRoot: root, candidates: rows.count, scores: scores, summary: BenchSummary(scores),
                                 notFound: notFound, failed: failed, reused: collected.reused)
        if let out = o.output {
            var data = report.json().data
            data.append(0x0A)
            try data.write(to: out, options: .atomic)
        }
        return report
    }
}
