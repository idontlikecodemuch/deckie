import Foundation

/// Writes a crate in its canonical form (docs/architecture/crate-format.md, "How it is written"), so the same crate
/// always gives the same bytes. It checks the crate first and writes nothing when there is a problem.
public enum CrateWriter {
    /// The crate's files, by their path inside the package folder: `manifest.json`, `crate.json`, and a
    /// `bars/<id>.bin` and `style/<id>.bin` for each track that has them. Signature files are not among them: they
    /// are made on an Apple device and only listed in the records.
    public static func encode(_ crate: Crate) throws -> [String: Data] {
        // Checked in the written order, so a problem's tracks[i] is the record a reader would see there.
        var crate = crate
        crate.tracks.sort { byteOrder($0.id, $1.id) }
        var problems = crate.problems()
        if crate.manifest.schema > CrateFormat.schema {
            problems.append(CrateProblem(file: CrateFormat.manifestFile, path: "schema", message:
                "the crate was written by a newer Deckie (format \(crate.manifest.schema)); this one writes format " +
                "\(CrateFormat.schema) and would drop fields it does not know, so it can read the crate but not rewrite it"))
        }
        if !problems.isEmpty { throw CrateError(problems) }

        let tracks = crate.tracks
        var files: [String: Data] = [:]
        guard case .object(var manifest) = try CanonicalJSON.tree(crate.manifest, decimals: CrateFormat.decimals)
        else { preconditionFailure("the manifest encodes as an object") }
        manifest["engines_used"] = .array(crate.enginesUsed.map(JSONValue.string))
        files[CrateFormat.manifestFile] = Data(CanonicalJSON.text(.object(manifest)).utf8)
        var records: [JSONValue] = []
        for (i, t) in tracks.enumerated() {
            do {
                records.append(try CanonicalJSON.tree(t, decimals: CrateFormat.decimals))
            } catch let EncodingError.invalidValue(_, context) {
                throw CrateError([CrateProblem(file: CrateFormat.tracksFile, path: "tracks[\(i)]." + fieldPath(context.codingPath),
                                               track: t.id, message: context.debugDescription)])
            }
        }
        files[CrateFormat.tracksFile] = Data(CanonicalJSON.text(.object(["tracks": .array(records)]),
                                                               linePerTopLevelItem: true).utf8)
        for t in tracks {
            if let bars = t.bars, let n = t.grid?.nBars { files[CrateFormat.barsPath(t.id)] = Sidecar.bars(bars, nBars: n) }
            if let style = t.style { files[CrateFormat.stylePath(t.id)] = Sidecar.style(style.values) }
        }
        return files
    }

    /// Writes the crate into the package folder at `package` (made if missing): replaces `manifest.json`,
    /// `crate.json` and the sidecars of its tracks, deletes the `.bin` sidecars of tracks no longer in it, and leaves
    /// every other file alone (`prefs.json`, `history/`, `signatures/`, `catalog/`, ...). Each listed signature's
    /// file must already be in the package.
    public static func write(_ crate: Crate, to package: URL) throws {
        let files = try encode(crate)
        let fm = FileManager.default
        var missing: [CrateProblem] = []
        for (i, t) in crate.tracks.sorted(by: { byteOrder($0.id, $1.id) }).enumerated() {
            for variant in t.signatures.keys.sorted(by: byteOrder) {
                let path = CrateFormat.signaturePath(t.id, variant)
                if !fm.fileExists(atPath: package.appendingPathComponent(path).path) {
                    missing.append(CrateProblem(file: CrateFormat.tracksFile, path: "tracks[\(i)].signatures.\(variant)",
                                                track: t.id, message: "\(path) is not in the package"))
                }
            }
        }
        if !missing.isEmpty { throw CrateError(missing) }

        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        for folder in [CrateFormat.barsFolder, CrateFormat.styleFolder] {
            let dir = package.appendingPathComponent(folder)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasSuffix(".bin") && files["\(folder)/\(name)"] == nil {
                try fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
        for path in files.keys.sorted() {
            let url = package.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files[path]!.write(to: url, options: .atomic)
        }
    }
}
