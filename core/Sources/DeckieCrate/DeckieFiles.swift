import Foundation
#if os(Windows)
import WinSDK
#endif

/// Every write, replace, move, copy and delete Deckie does to its own files goes through here: Desk's storage, the
/// crate file writer, the builder's work folder, export and import.
///
/// Why: on Windows another program can hold a file Deckie has just written for a moment (a virus scanner, the
/// search indexer, a backup or sync client), and replacing, moving or deleting it then fails with a sharing violation
/// (Win32 error 32) or access denied (5), which Foundation reports as Cocoa error 513, "You don't have permission".
/// Seen on the Windows CI runner on Nov 13 and 14, 2026. A moment later the same operation succeeds, so a save must
/// not fail for it. Each operation here is tried again a few times over about a second (a delete, over about five)
/// when it fails that way, then the error is thrown with the path and what happened. Any other error is thrown at
/// once, as it was.
///
/// Nothing about what is written changes: a file is still written whole to a temporary file and moved into place
/// (`Data.write(options: .atomic)`), as before.
public enum DeckieFiles {
    /// The pauses between attempts: six attempts in all, about one second of waiting at most.
    public static let pauses: [Double] = [0.05, 0.1, 0.15, 0.25, 0.4]

    /// The pauses for a delete: the same, then longer ones, eleven attempts and about five seconds in all. Deleting
    /// a folder needs every file in it to be free at the same moment, and one file held anywhere inside stops it.
    /// Seen on the Windows CI runner on Nov 14, 2026 (twice in eight runs): a crate's folder could not be deleted
    /// within a second, because a temporary file that an interrupted save had left in it was still held by another
    /// program. A delete that waits a few seconds is better than one a DJ has to ask for twice.
    public static let removePauses: [Double] = pauses + [0.6, 0.8, 1.0, 1.0, 1.0]

    /// The error thrown when a file stayed held by another program through every attempt.
    public struct HeldError: Error, CustomStringConvertible, LocalizedError {
        public let operation: String
        public let path: String
        public let attempts: Int
        /// How long the attempts waited in all, in seconds.
        public var waited: Double = 1
        public let underlying: Error
        public var description: String {
            let long = waited < 1.5 ? "about a second" : "about \(Int(waited.rounded())) seconds"
            return "Couldn't \(operation) \(path): another program kept the file open (tried \(attempts) times over \(long)). "
                + "\((underlying as? LocalizedError)?.errorDescription ?? "\(underlying)")"
        }
        public var errorDescription: String? { description }
    }

    /// Whether `error` is one that goes away when another program lets go of the file. On Windows only: elsewhere an
    /// open file never blocks a write, and a permission error is real.
    public static func isTransient(_ error: Error) -> Bool {
        #if os(Windows)
        let ns = error as NSError
        func win32(_ e: NSError) -> Bool {
            // Foundation on Windows carries the Win32 code as the underlying error (`Win32Error(code: 32)`).
            let text = "\(e)"
            return text.contains("code: 32)") || text.contains("code: 5)") || text.contains("code: 33)")
        }
        if let u = ns.userInfo[NSUnderlyingErrorKey] as? NSError, win32(u) { return true }
        if ns.domain == NSCocoaErrorDomain,
           [CocoaError.fileWriteNoPermission.rawValue, CocoaError.fileReadNoPermission.rawValue,
            CocoaError.fileWriteUnknown.rawValue].contains(ns.code) { return true }
        return win32(ns)
        #else
        return false
        #endif
    }

    /// Runs `body`, again after each pause while it fails with an error `transient` accepts; then throws `HeldError`
    /// naming `path`. `transient` and `pauses` are given by the tests; everyone else takes the defaults.
    @discardableResult
    public static func retrying<T>(_ operation: String, _ path: String, pauses: [Double] = DeckieFiles.pauses,
                                   transient: (Error) -> Bool = DeckieFiles.isTransient,
                                   cleanUp: () -> Void = {}, _ body: () throws -> T) throws -> T {
        var attempt = 0
        while true {
            do { return try body() } catch {
                guard transient(error) else { throw error }
                guard attempt < pauses.count else {
                    throw HeldError(operation: operation, path: path, attempts: attempt + 1, waited: pauses.reduce(0, +),
                                    underlying: error)
                }
                cleanUp()
                Thread.sleep(forTimeInterval: pauses[attempt])
                attempt += 1
            }
        }
    }

    // MARK: the operations

    /// Writes `data` to `url` whole: to a temporary file first, then into place. Makes the folder when needed.
    public static func write(_ data: Data, to url: URL) throws {
        try createDirectory(url.deletingLastPathComponent())
        try retrying("write", url.path) { try data.write(to: url, options: .atomic) }
    }

    /// Makes a folder and the folders above it.
    public static func createDirectory(_ url: URL) throws {
        try retrying("make the folder", url.path) {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    /// Deletes a file or a folder with everything in it; nothing when it is not there.
    public static func remove(_ url: URL) throws {
        let fm = FileManager.default
        try retrying("delete", url.path, pauses: removePauses) {
            guard fm.fileExists(atPath: url.path) else { return }
            try fm.removeItem(at: url)
        }
    }

    /// Copies a file or a folder to `destination`, which must not exist. A copy cut short by a held file is taken
    /// away before the next attempt.
    public static func copy(_ source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try retrying("copy", source.path, cleanUp: { try? fm.removeItem(at: destination) }) {
            try fm.copyItem(at: source, to: destination)
        }
    }

    /// Moves a file or a folder to `destination`, which must not exist.
    public static func move(_ source: URL, to destination: URL) throws {
        try retrying("move", source.path) { try FileManager.default.moveItem(at: source, to: destination) }
    }

    /// Adds `data` to the end of the file at `url` (made when missing), and closes it.
    public static func append(_ data: Data, to url: URL) throws {
        let handle = try openForAppending(url)
        defer { try? handle.close() }
        try handle.write(contentsOf: data)
    }

    /// The file at `url` (made when missing), open for writing at its end. The caller closes it.
    public static func openForAppending(_ url: URL) throws -> FileHandle {
        try retrying("open", url.path) {
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) { _ = fm.createFile(atPath: url.path, contents: nil) }
            let h = try FileHandle(forWritingTo: url)
            #if os(Windows)
            // Not one a child program inherits (Foundation in Swift 6.4.1 makes it so): a child that held it would
            // keep the file from being deleted or replaced for as long as it ran.
            SetHandleInformation(h._handle, DWORD(HANDLE_FLAG_INHERIT), 0)
            #endif
            try h.seekToEnd()
            return h
        }
    }
}
