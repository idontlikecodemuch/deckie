import Foundation
import DeckieCrate
import DeckieDecode
import DeckieEngine
import DeckieInference

/// One audio file of the folder being built.
public struct SourceFile: Sendable, Equatable {
    public var url: URL
    /// The path below the folder, with `/` between names.
    public var rel: String
    /// The extension, lower case, without the dot.
    public var ext: String
    public var size: Int
    /// The modification time, seconds since 1970.
    public var modified: Double
}

/// Finding the audio files of a folder.
public enum AudioFiles {
    /// What counts as an audio file, by extension: everything a DJ's folder is likely to hold, decodable here or not
    /// (P18: what cannot be decoded is counted and logged, never skipped silently), plus the protected `.m4p`.
    public static let extensions: Set<String> = ["mp3", "flac", "wav", "aif", "aiff", "aifc", "m4a", "mp4", "aac",
                                                 "wma", "ogg", "opus", "m4p"]

    /// The audio files below `folder`, sorted by path. Hidden files and folders (a name starting with a dot) are left
    /// out, and so are crate packages and builder work folders (`.deckiecrate`, `.deckiebuild`), so an output inside
    /// the folder is never read as music. A link to a file counts as the file.
    public static func find(in folder: URL) throws -> [SourceFile] {
        let fm = FileManager.default
        let root = folder.standardizedFileURL
        var isFolder: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isFolder), isFolder.boolValue else {
            throw BuildError("\(folder.path) is not a folder")
        }
        guard let walker = fm.enumerator(atPath: root.path) else { throw BuildError("cannot list \(folder.path)") }
        var found: [SourceFile] = []
        while let rel = walker.nextObject() as? String {
            let name = (rel as NSString).lastPathComponent
            let url = root.appendingPathComponent(rel)
            if name.hasPrefix(".") {
                walker.skipDescendants()
                continue
            }
            let ext = (name as NSString).pathExtension.lowercased()
            if ext == CrateFormat.packageExtension || ext == Builder.workExtension {
                walker.skipDescendants()
                continue
            }
            guard extensions.contains(ext) else { continue }
            guard var attrs = try? fm.attributesOfItem(atPath: url.path) else { continue }
            if attrs[.type] as? FileAttributeType == .typeSymbolicLink {
                guard let target = try? fm.attributesOfItem(atPath: url.resolvingSymlinksInPath().path) else { continue }
                attrs = target
            }
            guard attrs[.type] as? FileAttributeType == .typeRegular else { continue }
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            let modified = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            found.append(SourceFile(url: url, rel: rel.split(separator: "/").joined(separator: "/"), ext: ext, size: size,
                                    modified: modified))
        }
        return found.sorted { $0.rel.utf8.lexicographicallyPrecedes($1.rel.utf8) }
    }
}

/// A problem that stops the build (not one file's failure, which goes into the import log).
public struct BuildError: Error, CustomStringConvertible {
    public var description: String
    public init(_ description: String) { self.description = description }
}

/// Why one file could not be analysed, as the import log records it.
public struct FileFailure: Sendable, Equatable {
    /// One of `CrateManifest.ImportLog.Reason`.
    public var reason: String
    public var message: String

    public init(reason: String, message: String) {
        self.reason = reason
        self.message = message
    }

    /// The import log's reason and text for an error thrown while decoding or analysing the file at `path`: the
    /// decoder's kinds (unsupported, protected, damaged; a file that cannot be read is a decode error), the analyser's
    /// (no grid, too few bars) and the model's are analysis errors. The text never carries the file's absolute path.
    public static func classify(_ error: Error, path: String) -> FileFailure {
        typealias R = CrateManifest.ImportLog.Reason
        if let e = error as? AudioDecodeError {
            let reason: String
            switch e.kind {
            case .unsupported: reason = R.unsupported
            case .protected: reason = R.protected
            case .damaged: reason = R.damaged
            case .cannotRead: reason = R.decodeError
            }
            return FileFailure(reason: reason, message: scrub(e.message, path: path))
        }
        if let e = error as? AnalyserError { return FileFailure(reason: R.analysisError, message: e.description) }
        if let e = error as? OnnxRuntimeError {
            return FileFailure(reason: R.analysisError, message: scrub("the beat model failed: \(e)", path: path))
        }
        return FileFailure(reason: R.analysisError, message: scrub("\(error)", path: path))
    }

    /// `message` without the file's absolute path (the crate keeps no absolute path).
    static func scrub(_ message: String, path: String) -> String {
        message.replacingOccurrences(of: path, with: (path as NSString).lastPathComponent)
    }

    /// Whether a later run may take this result as it is while the file is unchanged: everything but a file that
    /// could not be read, which may be a passing problem (a disk not mounted, a permission).
    var isLasting: Bool { reason != CrateManifest.ImportLog.Reason.decodeError }
}
