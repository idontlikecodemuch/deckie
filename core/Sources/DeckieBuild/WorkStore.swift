import Foundation
import DeckieCrate

/// The builder's work folder, `<name>.deckiebuild` next to the crate, which makes a build resumable: every finished
/// file is kept as it finishes, so a second run takes what is already done and an interrupted run loses only the
/// files that were being analysed when it stopped (one per job).
///
///   records/<id>.json   one finished record per file content (the id is the file's SHA-256, as in the crate),
///                       written whole or not at all
///   files.jsonl         one line per finished file, appended as it finishes: its path below the folder, size and
///                       modification time, the engine that ran, the tag tempo given, and the record's id or why it
///                       failed; the last line for a path wins, and a line cut short by an interruption is ignored
///   work.json           the folder's own format number
///
/// Deleting the folder, or `--fresh`, starts from nothing; nothing in it is needed once the crate is written.
final class WorkStore: @unchecked Sendable {
    static let format = 1

    /// One finished file.
    struct FileLine: Codable, Equatable {
        var rel: String
        var size: Int
        var modified: Double
        /// `ok` or `failed`.
        var status: String
        /// The engine label (`deckie-0.4.0`): a line from another engine or engine version is not reused.
        var engine: String
        /// The record's id, when `ok`.
        var id: String?
        /// The tag tempo the analysis was given, when `ok`.
        var bpmTag: Double?
        /// The file's own tags, as read then.
        var tags: FileTags?
        /// Why it failed, when `failed`.
        var reason: String?
        var message: String?

        enum CodingKeys: String, CodingKey {
            case rel, size, modified, status, engine, id, tags, reason, message, bpmTag = "bpm_tag"
        }
    }

    /// One finished record: the engine's crate record as it came from the analysis (the builder adds the names,
    /// the rekordbox block and the file's current path when it writes the crate), its per-bar series and style vector
    /// (which the crate keeps in sidecars, not in the record's JSON), and what it was made with.
    struct Record: Codable {
        var engine: String
        var bpmTag: Double?
        var track: CrateTrack
        var bars: [String: [Double]]?
        var style: [Double]?

        enum CodingKeys: String, CodingKey { case engine, track, bars, style, bpmTag = "bpm_tag" }

        /// The record with its per-bar series and style vector in place.
        var crateTrack: CrateTrack {
            var t = track
            t.bars = bars.map(BarSeries.init)
            if let model = t.style?.model { t.style = CrateTrack.Style(model: model, values: style ?? []) }
            return t
        }
    }

    let folder: URL
    private let lock = NSLock()
    private var lines: [String: FileLine] = [:]
    private var log: FileHandle?

    var recordsFolder: URL { folder.appendingPathComponent("records") }
    var linesFile: URL { folder.appendingPathComponent("files.jsonl") }

    /// Opens (or makes) the work folder; `fresh` empties it first.
    init(folder: URL, fresh: Bool) throws {
        self.folder = folder
        let fm = FileManager.default
        let marker = folder.appendingPathComponent("work.json")
        if fresh { try? fm.removeItem(at: folder) }
        if fm.fileExists(atPath: folder.path) {
            let format = (try? JSONDecoder().decode([String: Int].self, from: Data(contentsOf: marker)))?["format"]
            // A folder with nothing but the work folder's own names (a run stopped before it wrote work.json) is one.
            let names = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
            let ours = format == nil && names.isSubset(of: ["records", "files.jsonl", "work.json"])
            guard format == Self.format || ours else {
                throw BuildError("\(folder.path) is not a work folder of this deckie-build; remove it or use --fresh")
            }
        }
        try fm.createDirectory(at: recordsFolder, withIntermediateDirectories: true)
        try Data("{\"format\":\(Self.format)}\n".utf8).write(to: marker, options: .atomic)
        if let text = try? String(contentsOf: linesFile, encoding: .utf8) {
            let decoder = JSONDecoder()
            for row in text.split(separator: "\n") {
                if let line = try? decoder.decode(FileLine.self, from: Data(row.utf8)) { lines[line.rel] = line }
            }
            // A last line cut short leaves no newline: start the next on a fresh line.
            if !text.isEmpty && !text.hasSuffix("\n") { try appendRaw(Data("\n".utf8)) }
        }
    }

    deinit { try? log?.close() }

    /// The last finished line for `rel`.
    func line(for rel: String) -> FileLine? {
        lock.lock(); defer { lock.unlock() }
        return lines[rel]
    }

    func recordURL(_ id: String) -> URL { recordsFolder.appendingPathComponent("\(id).json") }

    /// The finished record for `id`, or nil.
    func record(_ id: String) -> Record? {
        guard let data = try? Data(contentsOf: recordURL(id)) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    /// Keeps a finished record, whole or not at all.
    func save(_ record: Record) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(to: recordURL(record.track.id), options: .atomic)
    }

    /// Notes a finished file (after its record is saved).
    func append(_ line: FileLine) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(line)
        data.append(0x0A)
        lock.lock(); defer { lock.unlock() }
        try appendRaw(data)
        lines[line.rel] = line
    }

    private func appendRaw(_ data: Data) throws {
        if log == nil {
            if !FileManager.default.fileExists(atPath: linesFile.path) {
                _ = FileManager.default.createFile(atPath: linesFile.path, contents: nil)
            }
            log = try FileHandle(forWritingTo: linesFile)
        }
        try log!.seekToEnd()
        try log!.write(contentsOf: data)
    }
}
