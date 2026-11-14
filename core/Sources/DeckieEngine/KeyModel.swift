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
        if let p = ProcessInfo.processInfo.environment[environmentVariable], !p.isEmpty { return [p] }
        return OnnxRuntime.candidates(named: LearnedKey.Model.fileName, in: "models",
                                      checkout: OnnxRuntime.coreFolder.appendingPathComponent(".models").appendingPathComponent(LearnedKey.Model.fileName))
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

    /// The lean toward minor keys, as a share of minor (0 to 1), or nil for none beyond the pinned model's own. **Off
    /// until the owner chooses one** (research X4, `docs/research/x4-key-complete.md`, section 2b, lists the candidates
    /// and what each does): setting a value here is the whole change.
    public static let chosenMinorShare: Double? = nil
    /// Set to a share of minor keys in percent (`65`) to try a lean without changing the code; it wins over
    /// `chosenMinorShare`.
    public static let minorShareEnvironmentVariable = "DECKIE_KEY_MINOR_SHARE"

    /// The share in force: the environment variable's, else `chosenMinorShare`; nil when neither, or when the
    /// variable is not a number strictly between 0 and 100.
    public static var minorShare: Double? {
        if let v = ProcessInfo.processInfo.environment[minorShareEnvironmentVariable], let x = Double(v), x > 0, x < 100 { return x / 100 }
        return chosenMinorShare
    }

    /// `model` with the lean in force, or as it is when there is none.
    public static func withLean(_ model: LearnedKey.Model) -> LearnedKey.Model { minorShare.map { model.leaned(toMinorShare: $0) } ?? model }

    /// The model where it is looked for, with the lean in force, or nil when the file is not there, cannot be read or
    /// is not the pinned file byte for byte: the untrained three-answer reader then reads the keys, and `note` says
    /// why.
    public static func loadDefault() -> LearnedKey.Model? { usable(locate()) }

    /// The model in the file at `path` with the lean in force, or nil when `path` is nil or the file is not usable.
    public static func usable(_ path: String?) -> LearnedKey.Model? {
        guard let path, let model = try? load(path: path) else { return nil }
        return withLean(model)
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
}
