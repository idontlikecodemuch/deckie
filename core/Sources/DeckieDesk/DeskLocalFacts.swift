import Foundation
import DeckieCrate
import DeckieBuild

/// The DJ libraries a desk reads for keys and names (D30): found where each program keeps one, plus those the DJ chose
/// by hand (`libraries.json` in the desk's storage), and the gathering itself (`LocalFacts`) for a crate the desk
/// keeps. Every library is read from a copy and never written.
public struct DJLibraryChoices: Codable, Equatable, Sendable {
    public struct Choice: Codable, Equatable, Hashable, Sendable {
        public var program: DJProgram
        public var path: String
        public init(program: DJProgram, path: String) { self.program = program; self.path = path }
    }
    public var chosen: [Choice]
    public init(chosen: [Choice] = []) { self.chosen = chosen }

    public static let file = "libraries.json"
    public static func load(_ home: DeskHome) -> DJLibraryChoices {
        JSONFile.read(Self.self, from: home.root.appendingPathComponent(file)) ?? DJLibraryChoices()
    }
    public func save(_ home: DeskHome) throws { try JSONFile.write(self, to: home.root.appendingPathComponent(Self.file)) }

    /// Adds the library file at `url`, its program told from the file; throws when it is no library Desk reads.
    public mutating func add(_ url: URL) throws -> DJProgram {
        guard let program = DJProgram.of(file: url) else {
            throw DeskError(DeskWords.text("error.notALibrary", ["file": url.lastPathComponent]))
        }
        let c = Choice(program: program, path: url.standardizedFileURL.path)
        if !chosen.contains(c) { chosen.append(c) }
        return program
    }
}

public enum DeskLocalFacts {
    /// Names the home folder whose DJ libraries are looked for. A desk whose storage is anywhere but its standard
    /// place (moved by `DECKIE_DESK_HOME` for a test or a manual run, or made in a scratch folder by a test) looks in
    /// no home folder unless this is set, so a test never opens a DJ's real libraries.
    public static let djHomeVariable = "DECKIE_DJ_HOME"

    public static func djHome(for home: DeskHome, environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        if let p = environment[djHomeVariable], !p.isEmpty { return URL(fileURLWithPath: (p as NSString).expandingTildeInPath) }
        guard home.root == DeskHome.standard(environment: [:]).root else { return nil }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// Every library to read for a crate: in the DJ home folder, at the top of each of the crate's sources and its
    /// music folder, and the ones chosen by hand; each file once.
    public static func find(home: DeskHome, info: CrateInfo,
                            environment: [String: String] = ProcessInfo.processInfo.environment)
        -> (found: [DJLibraryLocations.Found], rekordboxLocked: Bool, rekordboxExport: Bool) {
        let tops = Array(info.roots.values) + (info.musicFolderURL.map { [$0] } ?? [])
        let chosen = DJLibraryChoices.load(home).chosen.map { DJLibraryLocations.Found(program: $0.program, url: URL(fileURLWithPath: $0.path)) }
        return LocalFacts.find(djHome: djHome(for: home, environment: environment), tops: tops, chosen: chosen)
    }

    /// Each entry's files on this computer, from the paths the desk remembers: the own place's first.
    public static func files(for crate: Crate, paths: PlacePaths, roots: [String: URL], musicFolder: URL?)
        -> [String: [LocalFacts.FileRef]] {
        var out: [String: [LocalFacts.FileRef]] = [:]
        for t in crate.tracks {
            var refs: [LocalFacts.FileRef] = []
            for p in paths.byId[t.id] ?? [] {
                guard let root = p.source.map({ roots[$0] }) ?? musicFolder else { continue }
                let place = t.ident.allPlaces.first { $0.disc == p.source && ($0.folder ?? "") == (p.folder ?? "") }
                    ?? CrateTrack.Place(disc: p.source, folder: p.folder, track: nil)
                let ref = LocalFacts.FileRef(url: root.appendingPathComponent(p.rel), rel: p.rel, place: place)
                if place == t.ident.ownPlace { refs.insert(ref, at: 0) } else { refs.append(ref) }
            }
            if refs.isEmpty, let rel = t.file.rel, let root = t.ident.disc.map({ roots[$0] }) ?? musicFolder {
                refs.append(.init(url: root.appendingPathComponent(rel), rel: rel, place: t.ident.ownPlace))
            }
            out[t.id] = refs
        }
        return out
    }

    /// Reads the libraries found and puts their keys and names, and the files' own, into `crate`. Deckie's own reading
    /// of each song comes from the desk's store of records.
    public static func gather(_ crate: inout Crate, home: DeskHome, info: CrateInfo, paths: PlacePaths,
                              environment: [String: String] = ProcessInfo.processInfo.environment) -> LocalFactsSummary {
        let tops = Array(info.roots.values) + (info.musicFolderURL.map { [$0] } ?? [])
        let chosen = DJLibraryChoices.load(home).chosen.map { DJLibraryLocations.Found(program: $0.program, url: URL(fileURLWithPath: $0.path)) }
        let refs = files(for: crate, paths: paths, roots: info.roots, musicFolder: info.musicFolderURL)
        var summary = LocalFacts.gather(&crate, files: refs, djHome: djHome(for: home, environment: environment), tops: tops,
                                        chosen: chosen, records: home.store.records)
        let fromDisc = discFacts(&crate, home: home, info: info)
        var from = summary.report.factsFrom ?? [:]
        from[SongFacts.Origin.disc] = fromDisc > 0 ? fromDisc : nil
        summary.report.factsFrom = from
        return summary
    }

    /// A music CD's facts from its CD-Text (D34), as `cdtext`: the disc's title as the release, its performer as the
    /// release's artist where it differs from the song's, and each song's ISRC, composer (or songwriter) and message.
    /// Replaces what the disc gave before; a song's file or library, or the DJ, ranks higher. Returns the songs given
    /// facts.
    @discardableResult
    public static func discFacts(_ crate: inout Crate, home: DeskHome, info: CrateInfo) -> Int {
        var discs: [String: DiscRecords.Record] = [:]
        for (source, id) in info.discs { if let r = DiscRecords.record(home, disc: id) { discs[source] = r } }
        var given = 0
        for i in crate.tracks.indices {
            crate.tracks[i].ident.dropFacts { $0 == SongFacts.Origin.disc }
            guard let (r, n) = crate.tracks[i].ident.allPlaces.lazy.compactMap({ p -> (DiscRecords.Record, Int)? in
                guard let d = p.disc, let r = discs[d], let n = p.track else { return nil }
                return (r, n)
            }).first else { continue }
            var id = crate.tracks[i].ident
            let from = SongFacts.Origin.disc
            func offer(_ name: String, _ v: String?) { if let v { id.offer(name, .init(v, from: from)) } }
            offer(SongFacts.release, r.discTitle)
            if let p = r.discPerformer, p.compare(r.performers[n] ?? id.artist ?? "", options: .caseInsensitive) != .orderedSame {
                offer(SongFacts.releaseArtist, p)
            }
            offer(SongFacts.isrc, r.isrcs[n])
            offer(SongFacts.composer, r.composers?[n] ?? r.songwriters?[n])
            offer(SongFacts.comment, r.messages?[n])
            offer(SongFacts.barcode, r.barcode)
            if id.facts.values.contains(where: { $0.from == from }) { given += 1 }
            crate.tracks[i].ident = id
        }
        return given
    }

    /// "Look again for keys and names" on a crate the desk keeps, without reading its music again: gathers, puts the
    /// DJ's name fixes back, and saves.
    public static func lookAgain(home: DeskHome, crateId: String,
                                 environment: [String: String] = ProcessInfo.processInfo.environment) throws -> (Crate, LocalFactsSummary) {
        let shelf = home.shelf
        guard let info = shelf.info(crateId) else { throw DeskError(DeskWords.text("error.noCrate", ["id": crateId])) }
        var crate = try CrateReader.read(from: shelf.package(crateId))
        let paths = PlacePaths.load(from: shelf.file(DeskRun.placesFile, of: crateId))
        let summary = gather(&crate, home: home, info: info, paths: paths, environment: environment)
        let (book, _) = DeskNamesStep.run(&crate, home: home, info: info, paths: paths,
                                          book: NameBook.load(from: shelf.file(DeskRun.namesFile, of: crateId)))
        try book.save(to: shelf.file(DeskRun.namesFile, of: crateId))
        NameCorrections.load(from: shelf.file(DeskRun.correctionsFile, of: crateId)).apply(to: &crate)
        try CrateWriter.write(crate, to: shelf.package(crateId))
        return (crate, summary)
    }
}
