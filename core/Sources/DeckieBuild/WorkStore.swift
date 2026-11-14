import Foundation
import DeckieCrate

/// The builder's work folder, `<name>.deckiebuild` next to the crate, which makes a build resumable: every finished
/// file is kept as it finishes, so a second run takes what is already done and an interrupted run loses only the
/// files that were being analysed when it stopped (one per job).
///
///   records/<id>.json   one finished record per file content (the id is the file's SHA-256, as in the crate),
///                       written whole or not at all
///   records/<id>.dkl    that file's fingerprint (D35), the bytes the crate file carries as `prints/<id>.dkl`; the
///                       record's `print` says who made it when, so a record lists a fingerprint only once its bytes
///                       are kept
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
        /// Whether the record had its fingerprint when the line was written. A line from before the fingerprint
        /// (D35) has none, so its file is looked at once more, and fingerprinted from one decode.
        var fingerprint: Bool? = nil

        enum CodingKeys: String, CodingKey {
            case rel, size, modified, status, engine, id, tags, reason, message, bpmTag = "bpm_tag", fingerprint = "print"
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

    /// `records/` in the work folder, or a shared folder given (`BuildOptions.sharedRecords`).
    let recordsFolder: URL
    var linesFile: URL { folder.appendingPathComponent("files.jsonl") }

    /// Opens (or makes) the work folder; `fresh` empties it first (never a shared `records` folder).
    init(folder: URL, fresh: Bool, records: URL? = nil) throws {
        self.folder = folder
        self.recordsFolder = records ?? folder.appendingPathComponent("records")
        let fm = FileManager.default
        let marker = folder.appendingPathComponent("work.json")
        if fresh { try? DeckieFiles.remove(folder) }
        if fm.fileExists(atPath: folder.path) {
            let format = (try? JSONDecoder().decode([String: Int].self, from: Data(contentsOf: marker)))?["format"]
            // A folder with nothing but the work folder's own names (a run stopped before it wrote work.json) is one.
            let names = Set((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
            let ours = format == nil && names.isSubset(of: ["records", "files.jsonl", "work.json"])
            guard format == Self.format || ours else {
                throw BuildError("\(folder.path) is not a work folder of this deckie-build; remove it or use --fresh")
            }
        }
        try DeckieFiles.createDirectory(folder)
        try DeckieFiles.createDirectory(recordsFolder)
        try DeckieFiles.write(Data("{\"format\":\(Self.format)}\n".utf8), to: marker)
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
    func record(_ id: String) -> Record? { WorkRecords.record(id, in: recordsFolder) }

    /// Keeps a finished record, whole or not at all.
    func save(_ record: Record) throws { try WorkRecords.save(record, in: recordsFolder) }

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
        if log == nil { log = try DeckieFiles.openForAppending(linesFile) }
        try log!.seekToEnd()
        try log!.write(contentsOf: data)
    }
}

/// The finished records of a records folder, for the work folder and for a caller that shares the folder with it
/// (Deckie Desk's store of what it worked out for each file, `BuildOptions.sharedRecords`).
public enum WorkRecords {
    static func recordURL(_ id: String, in records: URL) -> URL { records.appendingPathComponent("\(id).json") }
    /// Where a record's fingerprint is kept: `<id>.dkl` beside `<id>.json`.
    public static func fingerprintURL(_ id: String, in records: URL) -> URL { records.appendingPathComponent("\(id).dkl") }

    /// The finished record for `id` with its fingerprint's bytes in place, or nil. A record that lists a fingerprint
    /// whose bytes are gone or damaged reads as having none, so the builder makes it again.
    static func record(_ id: String, in records: URL) -> WorkStore.Record? {
        guard let data = try? Data(contentsOf: recordURL(id, in: records)),
              var record = try? JSONDecoder().decode(WorkStore.Record.self, from: data) else { return nil }
        if let listed = record.track.fingerprint {
            let kept = (try? Data(contentsOf: fingerprintURL(id, in: records)))
                .flatMap { CrateTrack.Fingerprint(data: $0, madeBy: listed.madeBy, madeAt: listed.madeAt) }
            record.track.fingerprint = kept?.points == listed.points ? kept : nil
        }
        return record
    }

    /// Keeps a record: its fingerprint's bytes first, then the record that lists them.
    static func save(_ record: WorkStore.Record, in records: URL) throws {
        let id = record.track.id
        if let f = record.track.fingerprint { try DeckieFiles.write(f.data, to: fingerprintURL(id, in: records)) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try DeckieFiles.write(try encoder.encode(record), to: recordURL(id, in: records))
    }

    /// The fingerprint kept for the file `id`, or nil when it has no record or its record has none.
    public static func fingerprint(_ id: String, in records: URL) -> CrateTrack.Fingerprint? {
        record(id, in: records)?.track.fingerprint
    }

    /// Keeps `fingerprint` with the record of the file `id`, replacing the one it had; false, and nothing kept, when
    /// the file has no record yet (a fingerprint is kept with the analysis it belongs to).
    @discardableResult
    public static func keep(_ fingerprint: CrateTrack.Fingerprint, id: String, in records: URL) throws -> Bool {
        guard var r = record(id, in: records) else { return false }
        r.track.fingerprint = fingerprint
        try save(r, in: records)
        return true
    }
}
