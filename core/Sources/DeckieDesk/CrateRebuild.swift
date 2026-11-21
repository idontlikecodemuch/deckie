import Foundation
import DeckieCrate
import DeckieBuild

/// "Rebuild this crate": a crate file that does not read, put right from what Desk keeps (the review of Nov 21, 2026).
///
/// What a stopped save could leave, before saves could not tear (`CrateWriter.write`), is a crate file whose list of
/// songs (`crate.json`) names a file that is not there, or not as the list says: a new song's fingerprint or style
/// vector written after the list, a removed song's sidecar deleted before it. The list itself and the manifest are each
/// written whole, so they read. So the songs whose files are wrong are put right from Desk's store of what it worked
/// out for each file (`Files/records/<id>.json` and its fingerprint, the same analysis the crate was made from): their
/// per-bar series, style vector and fingerprint, and a signature or cover that is not there is left out. Every other
/// song stays exactly as it was. A song that still does not hold together is left out, and comes back when its music
/// is added again (quickly: its analysis is kept).
///
/// When the manifest or the list itself does not read, there is nothing to start from here: `rebuild` throws, and the
/// crate's songs come back by adding their music again. Before anything is written, the two files as they were are
/// copied to `unreadable-<time>/` in the crate's folder.
public enum CrateRebuild {
    public struct Result: Equatable, Sendable {
        /// Songs kept as they were, songs put right from the store, songs left out.
        public var kept: Int
        public var putRight: Int
        public var leftOut: Int
    }

    public struct CannotRebuild: Error, CustomStringConvertible, LocalizedError {
        public let detail: String
        public var description: String { DeskWords.text("crateCannotRebuild") }
        public var errorDescription: String? { description }
    }

    /// Whether `rebuild` has something to start from: the crate file's manifest and list of songs both read.
    public static func possible(home: DeskHome, crateId: String) -> Bool {
        (try? start(home.shelf.package(crateId))) != nil
    }

    private static func start(_ pkg: URL) throws -> (manifest: Data, list: [[String: Any]]) {
        guard let manifest = try? Data(contentsOf: pkg.appendingPathComponent(CrateFormat.manifestFile)),
              (try? JSONDecoder().decode(CrateManifest.self, from: manifest)) != nil else {
            throw CannotRebuild(detail: "\(CrateFormat.manifestFile) does not read")
        }
        guard let data = try? Data(contentsOf: pkg.appendingPathComponent(CrateFormat.tracksFile)),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = top["tracks"] as? [[String: Any]] else {
            throw CannotRebuild(detail: "\(CrateFormat.tracksFile) does not read")
        }
        return (manifest, list)
    }

    /// Rebuilds the crate file of `crateId` in place, as above. Nothing is written when the crate file reads already.
    @discardableResult
    public static func rebuild(home: DeskHome, crateId: String, now: Date = Date()) throws -> Result {
        let shelf = home.shelf, store = home.store
        let pkg = shelf.package(crateId)
        try CrateWriter.finishInterruptedSave(pkg)
        if let c = try? CrateReader.read(from: pkg) { return Result(kept: c.tracks.count, putRight: 0, leftOut: 0) }
        let (manifestData, list) = try start(pkg)
        let fm = FileManager.default

        // The package's files, as the reader takes them.
        var files: [String: Data] = [CrateFormat.manifestFile: manifestData]
        for folder in [CrateFormat.barsFolder, CrateFormat.styleFolder, CrateFormat.printsFolder,
                       CrateFormat.signaturesFolder, CrateFormat.coversFolder] {
            for name in (try? fm.contentsOfDirectory(atPath: pkg.appendingPathComponent(folder).path)) ?? [] {
                if let d = try? Data(contentsOf: pkg.appendingPathComponent(folder).appendingPathComponent(name)) {
                    files["\(folder)/\(name)"] = d
                }
            }
        }
        func listFile(_ records: [[String: Any]]) throws -> Data {
            try JSONSerialization.data(withJSONObject: ["tracks": records])
        }

        // The songs the reader finds a problem with are taken out of the list until the rest reads.
        var bad: [String: [String: Any]] = [:]
        var rest = list
        var good: Crate?
        for _ in 0...list.count {
            files[CrateFormat.tracksFile] = try listFile(rest)
            do { good = try CrateReader.decode(files); break } catch let e as CrateError {
                let ids = Set(e.problems.compactMap(\.track))
                let before = rest.count
                for r in rest where ids.contains(r["id"] as? String ?? "") { bad[r["id"] as! String] = r }
                rest.removeAll { ids.contains($0["id"] as? String ?? "") }
                if rest.count == before {
                    throw CannotRebuild(detail: e.problems.map(\.description).joined(separator: "; "))
                }
            }
        }
        guard var crate = good else { throw CannotRebuild(detail: "the crate's songs do not read") }

        // Each of those songs put right from the store, or left out.
        var putRight = 0
        for id in bad.keys.sorted() {
            guard let r = bad[id], let data = try? JSONSerialization.data(withJSONObject: r),
                  var t = try? JSONDecoder().decode(CrateTrack.self, from: data) else { continue }
            let kept = Builder.finishedRecord(id, records: store.records)
            let listed = (r["features_present"] as? [String]) ?? []
            if t.grid != nil, listed.contains(where: { $0.hasPrefix(CrateFormat.Feature.barsPrefix) }) {
                t.bars = kept?.grid?.nBars == t.grid?.nBars ? kept?.bars : nil
            }
            if t.style != nil {
                if let s = kept?.style, s.model == t.style?.model, s.values.count == t.style?.dims { t.style = s } else { t.style = nil }
            }
            if t.fingerprint != nil { t.fingerprint = store.fingerprint(id) }
            t.signatures = t.signatures.filter { files["\(CrateFormat.signaturesFolder)/\(id)_\($0.key).shazamsignature"] != nil }
            if let cover = t.file.cover, files[CrateFormat.coverPath(cover)] == nil { t.file.cover = nil }
            var one = crate
            one.tracks.append(t)
            if (try? CrateWriter.encode(one)) != nil { crate = one; putRight += 1 }
        }

        // The two files as they were, kept beside the crate file; then the crate file written as it now is.
        let stamp = DeskRun.utc(now).replacingOccurrences(of: ":", with: "-")
        let aside = shelf.folder(crateId).appendingPathComponent("unreadable-\(stamp)", isDirectory: true)
        try DeckieFiles.write(manifestData, to: aside.appendingPathComponent(CrateFormat.manifestFile))
        if let d = try? Data(contentsOf: pkg.appendingPathComponent(CrateFormat.tracksFile)) {
            try DeckieFiles.write(d, to: aside.appendingPathComponent(CrateFormat.tracksFile))
        }
        try CrateWriter.write(crate, to: pkg)
        return Result(kept: crate.tracks.count - putRight, putRight: putRight, leftOut: bad.count - putRight)
    }
}
