import Foundation

/// Reads a crate and checks it (docs/architecture/crate-format.md, "What the reader checks"). Keys and files it does
/// not know are ignored; anything wrong in what it knows is reported, every problem at once where it can, each
/// naming the file, the field path and the track.
public enum CrateReader {
    /// Reads the package folder at `package`.
    public static func read(from package: URL) throws -> Crate {
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: package.path, isDirectory: &isFolder), isFolder.boolValue else {
            throw problem(package.lastPathComponent, "", "is not a crate package folder")
        }
        return try decode(file: { try? Data(contentsOf: package.appendingPathComponent($0)) },
                          exists: { FileManager.default.fileExists(atPath: package.appendingPathComponent($0).path) })
    }

    private static func problem(_ file: String, _ path: String, _ message: String) -> CrateError {
        CrateError([CrateProblem(file: file, path: path, message: message)])
    }

    /// Reads a crate from its files, keyed by their path inside the package (as `CrateWriter.encode` gives them, plus
    /// any signature files).
    public static func decode(_ files: [String: Data]) throws -> Crate {
        try decode(file: { files[$0] }, exists: { files[$0] != nil })
    }

    static func decode(file: (String) -> Data?, exists: (String) -> Bool) throws -> Crate {
        let mf = CrateFormat.manifestFile, tf = CrateFormat.tracksFile
        guard let manifestData = file(mf) else { throw problem(mf, "", "is missing") }
        let manifest = try decodeJSON(CrateManifest.self, manifestData, file: mf, ids: [])
        if manifest.minReader > CrateFormat.schema {
            throw problem(mf, "min_reader", "the crate needs a reader of format \(manifest.minReader) or later; " +
                                            "this one reads format \(CrateFormat.schema)")
        }

        guard let tracksData = file(tf) else { throw problem(tf, "", "is missing") }
        let ids = (try? JSONDecoder().decode(IDs.self, from: tracksData))?.tracks?.map(\.id) ?? []
        var tracks = try decodeJSON(TracksFile.self, tracksData, file: tf, ids: ids).tracks
        let listed = try decodeJSON(ListedFile.self, tracksData, file: tf, ids: ids).tracks

        var problems: [CrateProblem] = []
        for i in tracks.indices {
            var t = tracks[i]
            let list = listed[i].featuresPresent
            func add(_ file: String, _ path: String, _ message: String) {
                problems.append(CrateProblem(file: file, path: path, track: t.id, message: message))
            }
            let fpPath = "tracks[\(i)].features_present"
            if Set(list).count != list.count { add(tf, fpPath, "names a feature twice") }
            let has = Set(t.featuresPresent)
            for f in CrateFormat.Feature.blocks {
                if list.contains(f) && !has.contains(f) { add(tf, fpPath, "lists \(f), but the record has no \(f)") }
                if has.contains(f) && !list.contains(f) { add(tf, fpPath, "does not list \(f), but the record has it") }
            }
            // The id names the sidecar files: one that is not file-safe (reported below) could point outside the
            // package, so its sidecars are not opened.
            guard isFileSafe(t.id) else { continue }

            let seriesNames = list.filter { $0.hasPrefix(CrateFormat.Feature.barsPrefix) }
                .map { String($0.dropFirst(CrateFormat.Feature.barsPrefix.count)) }
            let barsPath = CrateFormat.barsPath(t.id)
            if !seriesNames.isEmpty {
                if let n = t.grid?.nBars {
                    if let data = file(barsPath) {
                        switch Sidecar.readBars(data, names: seriesNames, nBars: n, file: barsPath, track: t.id,
                                                gridPath: "tracks[\(i)].grid.n_bars") {
                        case .success(let b): t.bars = b
                        case .failure(let e): problems += e.problems
                        }
                    } else {
                        let listed = seriesNames.joined(separator: ", ")
                        add(barsPath, "", "is missing; features_present lists the series \(listed)")
                    }
                } else {
                    add(tf, fpPath, "lists per-bar series, which need the grid's bar count, but grid is null")
                }
            }
            if let style = t.style {
                let stylePath = CrateFormat.stylePath(t.id)
                if let data = file(stylePath) {
                    switch Sidecar.readStyle(data, dims: style.dims, file: stylePath, track: t.id,
                                             dimsPath: "tracks[\(i)].style.dims") {
                    case .success(let values): t.style?.values = values
                    case .failure(let e): problems += e.problems
                    }
                } else {
                    add(stylePath, "", "is missing; the record has a style vector")
                }
            }
            for variant in t.signatures.keys.sorted(by: byteOrder) where isFileSafe(variant, also: ["-", "_", "+"]) {
                let path = CrateFormat.signaturePath(t.id, variant)
                if !exists(path) { add(tf, "tracks[\(i)].signatures.\(variant)", "\(path) is not in the package") }
            }
            tracks[i] = t
        }
        let crate = Crate(manifest: manifest, tracks: tracks)
        // The model's own checks, less the count of a style vector whose sidecar was not read (already reported).
        let unread = Set(tracks.indices.filter { tracks[$0].style.map { $0.values.isEmpty && $0.dims > 0 } ?? false })
        problems += crate.problems().filter { p in !unread.contains { p.path == "tracks[\($0)].style.dims" } }
        if !problems.isEmpty { throw CrateError(problems) }
        return crate
    }

    private struct TracksFile: Decodable { var tracks: [CrateTrack] }
    private struct Listed: Decodable {
        var featuresPresent: [String]
        enum CodingKeys: String, CodingKey { case featuresPresent = "features_present" }
    }
    private struct ListedFile: Decodable { var tracks: [Listed] }
    private struct IDs: Decodable {
        struct One: Decodable { var id: String? }
        var tracks: [One]?
    }

    /// Decodes JSON, turning a decoding error into a problem with its field path (and the track's id when the path
    /// is inside `tracks[i]`).
    private static func decodeJSON<T: Decodable>(_ type: T.Type, _ data: Data, file: String, ids: [String?]) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let error as DecodingError {
            let path: [CodingKey], message: String
            switch error {
            case .keyNotFound(let key, let c): (path, message) = (c.codingPath + [key], "is missing (a required field)")
            case .valueNotFound(_, let c): (path, message) = (c.codingPath, "is null where a value is required")
            case .typeMismatch(let t, let c): (path, message) = (c.codingPath, "is not \(kind(t))")
            case .dataCorrupted(let c): (path, message) = (c.codingPath, c.debugDescription)
            @unknown default: (path, message) = ([], "\(error)")
            }
            var track: String? = nil
            if path.count >= 2, path[0].stringValue == "tracks", let i = path[1].intValue, i < ids.count { track = ids[i] }
            throw CrateError([CrateProblem(file: file, path: fieldPath(path), track: track, message: message)])
        } catch {
            throw CrateError([CrateProblem(file: file, path: "", message: "cannot be read: \(error)")])
        }
    }

    private static func kind(_ t: Any.Type) -> String {
        switch t {
        case is Int.Type: return "a whole number"
        case is Double.Type, is Float.Type: return "a number"
        case is String.Type: return "text"
        case is Bool.Type: return "true or false"
        default:
            let name = "\(t)"
            if name.hasPrefix("Array") { return "a list" }
            if name.hasPrefix("Dictionary") { return "an object" }
            return name
        }
    }
}
