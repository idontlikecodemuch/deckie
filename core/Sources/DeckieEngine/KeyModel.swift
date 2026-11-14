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

    /// Where the file is looked for: `DECKIE_KEY_MODEL` alone if it is set, else core/.models in the checkout.
    public static var candidates: [String] {
        if let p = ProcessInfo.processInfo.environment[environmentVariable], !p.isEmpty { return [p] }
        return [OnnxRuntime.coreFolder.appendingPathComponent(".models").appendingPathComponent(LearnedKey.Model.fileName).path]
    }

    /// The first place the file exists, or nil.
    public static func locate() -> String? { candidates.first { FileManager.default.fileExists(atPath: $0) } }

    /// The model in the file at `path`, which must be the pinned file, byte for byte.
    public static func load(path: String) throws -> LearnedKey.Model {
        guard let data = FileManager.default.contents(atPath: path) else { throw LoadError.unreadable(path) }
        let hash = CrateIDs.sha256(of: data)
        guard hash == LearnedKey.Model.pinnedSHA256 else { throw LoadError.notThePinnedFile(path: path, sha256: hash) }
        return try LearnedKey.Model(pinnedFile: data)
    }

    /// The model where it is looked for, or nil when the file is not there. A file that is there and is not the
    /// pinned one is an error.
    public static func loadDefault() throws -> LearnedKey.Model? { try locate().map(load(path:)) }

    /// The name of the model a default analyser will have, or nil.
    public static var defaultName: String? { locate() == nil ? nil : LearnedKey.Model.pinnedName }
}
