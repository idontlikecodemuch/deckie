import Foundation
import DeckieCore
import DeckieCrate
import DeckieInference

/// Where the learned key reader's numbers are found and how they are checked (`LearnedKey.Model`; research X4). The
/// file is one of the engine's model files, beside the beat tracker's and the vocal tagger's, and like the vocal
/// tagger's it is optional: without it the engine reads keys with the untrained three-answer reader.
public enum KeyModel {
    /// Set to a file's path to use that file alone.
    public static let environmentVariable = "DECKIE_KEY_MODEL"

    public enum LoadError: Error, CustomStringConvertible {
        case unreadable(String)
        case notThePinnedFile(path: String, sha256: String)
        public var description: String {
            switch self {
            case .unreadable(let p): return "the key model at \(p) cannot be read"
            case .notThePinnedFile(let p, let h):
                return "the key model at \(p) is not the pinned file (SHA-256 \(h), wanted \(LearnedKey.Model.pinnedSHA256))"
            }
        }
    }

    /// Where the file is looked for: `DECKIE_KEY_MODEL` alone if it is set; else `models/` beside a shipped program
    /// (`OnnxRuntime.programFolder`), then core/.models in the checkout.
    public static var candidates: [String] {
        candidates(environment: ProcessInfo.processInfo.environment, programFolder: OnnxRuntime.programFolder)
    }

    /// The same for a given environment, program folder and checkout (`core/`), so a test can name each place.
    public static func candidates(environment: [String: String], programFolder: URL?,
                                  coreFolder: URL = OnnxRuntime.coreFolder) -> [String] {
        if let p = environment[environmentVariable], !p.isEmpty { return [p] }
        var out: [String] = []
        if let programFolder { out.append(programFolder.appendingPathComponent("models").appendingPathComponent(LearnedKey.Model.fileName).path) }
        out.append(coreFolder.appendingPathComponent(".models").appendingPathComponent(LearnedKey.Model.fileName).path)
        return out
    }

    /// The first of `candidates` that exists, or nil.
    public static func locate(in candidates: [String]) -> String? { candidates.first { FileManager.default.fileExists(atPath: $0) } }

    /// The first place the file exists, or nil.
    public static func locate() -> String? { candidates.first { FileManager.default.fileExists(atPath: $0) } }

    /// The model in the file at `path`, which must be the pinned file, byte for byte.
    public static func load(path: String) throws -> LearnedKey.Model {
        guard let data = FileManager.default.contents(atPath: path) else { throw LoadError.unreadable(path) }
        let hash = CrateIDs.sha256(of: data)
        guard hash == LearnedKey.Model.pinnedSHA256 else { throw LoadError.notThePinnedFile(path: path, sha256: hash) }
        return try LearnedKey.Model(pinnedFile: data)
    }

    /// The model where it is looked for, or nil when the file is not there, cannot be read or is not the pinned file
    /// byte for byte: the untrained three-answer reader then reads the keys, and `note` says
    /// why.
    public static func loadDefault() -> LearnedKey.Model? { usable(locate()) }

    /// The model in the file at `path`, or nil when `path` is nil or the file is not usable (absent, unreadable, or
    /// not the pinned file).
    public static func usable(_ path: String?) -> LearnedKey.Model? {
        guard let path else { return nil }
        return try? load(path: path)
    }

    /// Why a default analyser has no learned key reader, or nil when it has one.
    public static var note: String? {
        guard let path = locate() else {
            return "no learned key reader: \(LearnedKey.Model.fileName) is not there (core/Tools/fetch-key-model.sh); keys are read by the untrained reader"
        }
        do { _ = try load(path: path); return nil } catch {
            return "no learned key reader: \(error); keys are read by the untrained reader"
        }
    }

    /// The name of the model a default analyser will have, or nil.
    public static var defaultName: String? { loadDefault()?.name }

    /// One line for a tester's log: `key reader: learned, <model>, <path>` when the pinned file was found, else
    /// `key reader: untrained (<why>)`.
    public static var readerLine: String { readerLine(path: locate()) }

    /// The same for the file at `path` (nil: not found).
    public static func readerLine(path: String?) -> String {
        guard let path else {
            return "key reader: untrained (\(LearnedKey.Model.fileName) was not found; core/Tools/fetch-key-model.sh)"
        }
        do { return "key reader: learned, \(try load(path: path).name), \(path)" } catch {
            return "key reader: untrained (\(error))"
        }
    }
}
