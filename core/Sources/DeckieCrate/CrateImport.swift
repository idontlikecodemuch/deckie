import Foundation

/// Takes a crate file a DJ hands an app (from Files, AirDrop, a share sheet, a cable) into the app's own storage, as
/// a package, whichever form it came in (docs/architecture/crate-format.md, "The single-file form"): a package folder
/// is copied, a single file is unpacked with `CrateArchive.unpack`. The copy is read whole with `CrateReader` before it
/// takes the place of anything, so a damaged crate file leaves the app's storage as it was. The file the DJ gave is
/// only read, never moved or changed.
///
/// This is what the iPad app needs to open a crate file made on a PC (point 2 of "What the iPad app needs"); after it
/// everything the app does is on a package, as before.
public enum CrateImport {
    /// What came in: the package in the app's storage, and the crate read from it.
    public struct Result: Sendable {
        public let package: URL
        public let crate: Crate
        /// Whether the crate file came as one file (made on a PC) rather than a package folder (made on a Mac).
        public let wasSingleFile: Bool
    }

    /// Copies or unpacks the crate file at `source` into `folder` (made if missing), as `<crate id>.deckiecrate`, and
    /// reads it. A crate file with the same crate id already there is replaced, but only once the new copy has read
    /// cleanly. Throws a `CrateError` saying what is wrong, in the reader's words, when `source` is not a crate file
    /// or is damaged; nothing is left behind in `folder` then.
    public static func copy(_ source: URL, into folder: URL) throws -> Result {
        let fm = FileManager.default
        var isFolder: ObjCBool = false
        let shown = source.lastPathComponent
        guard fm.fileExists(atPath: source.path, isDirectory: &isFolder) else {
            throw CrateError([CrateProblem(file: shown, path: "", message: "is not there")])
        }
        if !isFolder.boolValue && !CrateArchive.isArchive(source) {
            throw CrateError([CrateProblem(file: shown, path: "", message: "is not a crate file (neither a crate package folder nor the single-file form)")])
        }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let incoming = folder.appendingPathComponent(".incoming-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: incoming) }
        if isFolder.boolValue {
            try fm.copyItem(at: source, to: incoming)
        } else {
            try CrateArchive.unpack(source, to: incoming)  // checks the whole archive before writing anything
        }
        let crate: Crate
        do { crate = try CrateReader.read(from: incoming) } catch var e as CrateError {
            // The reader names the copy; say the DJ's file instead.
            for i in e.problems.indices where e.problems[i].file.hasPrefix(".incoming-") { e.problems[i].file = shown }
            throw e
        }
        let target = folder.appendingPathComponent(storedName(crate.manifest.crateId), isDirectory: true)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: incoming, to: target)
        return Result(package: target, crate: crate, wasSingleFile: !isFolder.boolValue)
    }

    /// The package's name in the app's storage: the crate id made safe for a file name, so the same crate sent twice
    /// replaces itself and two crates never share a name.
    public static func storedName(_ crateId: String) -> String {
        let safe = String(crateId.unicodeScalars.map { s -> Character in
            CharacterSet.alphanumerics.contains(s) && s.isASCII || s == "-" || s == "_" ? Character(s) : "_"
        }).prefix(80)
        return (safe.isEmpty ? "crate" : String(safe)) + "." + CrateFormat.packageExtension
    }
}
