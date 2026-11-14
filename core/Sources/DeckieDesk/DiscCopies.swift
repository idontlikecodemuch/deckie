import Foundation
import DeckieCrate
import DeckieBuild
import DeckieDisc

/// The songs of a music CD, copied off into Desk's own storage so they can be read, fingerprinted and listened to
/// (research AA, 2.6; the DJ plays the disc, not the copy):
///
///     <home>/Discs/<disc id>/        one folder a disc, by the id its table of contents gives (`DiscTOC.id`), so the
///                                    same disc put in again is known and not copied twice
///       disc.json                    the table, what the drive said about CD-Text (the names, or none, or that it
///                                    could not say), and each song copied
///       Track 01.wav ...             the songs, cut where the table says (on a Mac, the system's own AIFF files)
///
/// Room: CD audio is 10.1 MB a minute (44,100 frames a second of two 16-bit channels), so a full 74-minute disc takes
/// about 750 MB, and a typical 60-minute mix about 600 MB. The copy is the source's folder in the crate. It is deleted
/// when no crate has that disc as a source any more: after the source is removed from its crate, or the crate is
/// deleted (`prune`). Undoing a removal puts the songs back in the crate, but not the copy; listening then asks for
/// the disc.
public enum DiscCopies {
    public static let folderName = "Discs"
    public static let recordFile = "disc.json"

    public static func folder(_ home: DeskHome) -> URL { home.root.appendingPathComponent(folderName, isDirectory: true) }
    public static func folder(_ home: DeskHome, disc id: String) -> URL { folder(home).appendingPathComponent(id, isDirectory: true) }

    /// What Desk keeps about a disc it copied.
    public struct Record: Codable, Equatable, Sendable {
        public var toc: DiscTOC
        /// `names`, `none` or `drive` (TextReading's code), and the drive's own words when it could not say.
        public var text: String
        public var textDetail: String?
        public var discTitle: String?
        public var discPerformer: String?
        public var titles: [Int: String]
        public var performers: [Int: String]
        public var isrcs: [Int: String]
        /// The rest of what CD-Text carries (D34), by song number (0 is the disc); nil in a record made before.
        public var composers: [Int: String]?
        public var songwriters: [Int: String]?
        public var messages: [Int: String]?
        public var barcode: String?
        /// The songs copied whole: number, file name and the sectors that were silence.
        public var copied: [Copied]
        public var fileExtension: String
        public struct Copied: Codable, Equatable, Sendable {
            public var number: Int
            public var file: String
            public var damagedSectors: Int
        }

        public init(toc: DiscTOC, reading: TextReading, fileExtension: String) {
            self.toc = toc
            text = reading.code
            if case let .unknown(why) = reading { textDetail = why }
            let b = reading.text?.main
            discTitle = b?.discTitle; discPerformer = b?.discPerformer
            titles = (b?.titles ?? [:]).filter { $0.key > 0 }
            performers = (b?.performers ?? [:]).filter { $0.key > 0 }
            isrcs = b?.isrcs ?? [:]
            composers = b?.composers; songwriters = b?.songwriters; messages = b?.messages; barcode = b?.barcode
            copied = []
            self.fileExtension = fileExtension
        }

        enum CodingKeys: String, CodingKey {
            case toc, text, titles, performers, isrcs, copied, composers, songwriters, messages, barcode
            case textDetail = "text_detail", discTitle = "disc_title", discPerformer = "disc_performer"
            case fileExtension = "file_extension"
        }

        public var damagedSectors: Int { copied.reduce(0) { $0 + $1.damagedSectors } }

        /// A song's file name in the copy: "Track 07.wav", as a PC shows a music CD's songs.
        public func fileName(_ number: Int) -> String { String(format: "Track %02d.", number) + fileExtension }
    }

    public static func record(_ folder: URL) -> Record? { JSONFile.read(Record.self, from: folder.appendingPathComponent(recordFile)) }

    /// The disc in the drive at `location`, read just far enough to add it: its table and CD-Text (both quick), noted
    /// in its folder. The songs are copied in the run (`copySongs`).
    public static func prepare(_ cd: MusicCD, home: DeskHome) throws -> (folder: URL, record: Record) {
        let toc = try cd.tableOfContents()
        let folder = folder(home, disc: toc.id)
        if var old = record(folder), old.toc == toc {
            // The same disc again: keep what was copied; read the text again only if the drive could not say before.
            if old.text == "drive" {
                let again = Record(toc: toc, reading: cd.readText(), fileExtension: old.fileExtension)
                if again.text != "drive" { let copied = old.copied; old = again; old.copied = copied }
                try JSONFile.write(old, to: folder.appendingPathComponent(recordFile))
            }
            return (folder, old)
        }
        let r = Record(toc: toc, reading: cd.readText(), fileExtension: cd.fileExtension)
        try DeckieFiles.createDirectory(folder)
        try JSONFile.write(r, to: folder.appendingPathComponent(recordFile))
        return (folder, r)
    }

    /// Copies every song not yet copied, in order, noting each in the record as it is done (so a run stopped part way
    /// carries on from the next song). `progress(song, of, sectorsDone, sectorsTotal)`.
    @discardableResult
    public static func copySongs(_ cd: MusicCD, folder: URL,
                                 progress: (_ index: Int, _ count: Int, _ done: Int, _ total: Int) -> Void = { _, _, _, _ in },
                                 copiedSong: (_ number: Int, _ damaged: Int) -> Void = { _, _ in }) throws -> Record {
        guard var r = record(folder) else { throw DeskError("no record of the disc in \(folder.path)") }
        let songs = r.toc.songs
        for (i, song) in songs.enumerated() {
            let name = r.fileName(song.number)
            let url = folder.appendingPathComponent(name)
            if r.copied.contains(where: { $0.number == song.number }) && FileManager.default.fileExists(atPath: url.path) {
                progress(i + 1, songs.count, song.sectors, song.sectors)
                continue
            }
            let damaged = try cd.copy(song, to: url) { done, total in progress(i, songs.count, done, total) }
            r.copied.removeAll { $0.number == song.number }
            r.copied.append(.init(number: song.number, file: name, damagedSectors: damaged))
            r.copied.sort { $0.number < $1.number }
            try JSONFile.write(r, to: folder.appendingPathComponent(recordFile))
            copiedSong(song.number, damaged)
        }
        return r
    }

    /// Whether a folder is a disc copy in this desk's storage.
    public static func isCopy(_ url: URL, home: DeskHome) -> Bool {
        url.standardizedFileURL.deletingLastPathComponent().path == folder(home).standardizedFileURL.path
    }

    /// The bytes the copies take.
    public static func size(_ home: DeskHome) -> Int64 {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: folder(home), includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var n: Int64 = 0
        for case let u as URL in e { n += Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return n
    }

    /// Deletes every disc copy no crate reads from any more. Returns the ids deleted.
    @discardableResult
    public static func prune(_ home: DeskHome) -> [String] {
        let used = Set(home.shelf.list().flatMap { $0.sourceRoots.values }.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder(home).path)) ?? []
        var gone: [String] = []
        for n in names where !n.hasPrefix(".") {
            let f = folder(home, disc: n)
            if used.contains(f.standardizedFileURL.path) { continue }
            if (try? DeckieFiles.remove(f)) != nil { gone.append(n) }
        }
        return gone
    }
}

/// What a music CD's run did, for the finished screen (letter AA, 3.2) and the run's line.
public struct DiscReport: Codable, Equatable, Sendable {
    /// `names`, `none` or `drive`.
    public var text: String
    public var songs: Int
    /// Songs named from the disc's CD-Text.
    public var named: Int
    public var damagedSectors: Int
    /// Whether the disc's own title named the source; when not, the window asks for the name written on it.
    public var titled: Bool
    /// The room Desk's copy of the disc's songs takes, in bytes.
    public var bytes: Int64 = 0
    enum CodingKeys: String, CodingKey { case text, songs, named, titled, bytes, damagedSectors = "damaged_sectors" }
}

/// The names step after keys and names were gathered from the computer (D30) and before the DJ's own names go back:
/// a music CD's songs take their titles and performers from its CD-Text, recorded as `cdtext` ("from the disc"),
/// where they have nothing better (no usable name, or one guessed from a file name or folder); then where each name
/// came from, and each song's release, are noted in the crate's `NameBook`. Used by the run and by "Look again".
public enum DeskNamesStep {
    /// Applies the disc names and returns the book. `tagsAlbum` reads a file's album tag (the release); tests pass
    /// their own.
    @discardableResult
    public static func run(_ crate: inout Crate, home: DeskHome, info: CrateInfo, paths: PlacePaths,
                           book old: NameBook) -> (book: NameBook, discNamed: [String: Int]) {
        var discs: [String: DiscCopies.Record] = [:]
        for (source, root) in info.roots where DiscCopies.isCopy(root, home: home) {
            if let r = DiscCopies.record(root) { discs[source] = r }
        }
        var named: [String: Int] = [:]
        var releases: [String: (String, String)] = [:]
        let refs = DeskLocalFacts.files(for: crate, paths: paths, roots: info.roots, musicFolder: info.musicFolderURL)
        for i in crate.tracks.indices {
            let t = crate.tracks[i]
            // A disc's song: its place on the disc's source, by number.
            if let (source, number) = t.ident.allPlaces.lazy.compactMap({ p -> (String, Int)? in
                guard let d = p.disc, discs[d] != nil, let n = p.track else { return nil }
                return (d, n)
            }).first, let r = discs[source] {
                if let title = r.discTitle { releases[t.id] = (title, "cdtext") }
                else { releases[t.id] = (source, "disc") }
                guard t.ident.source != "user" else { continue }
                let titleFrom = DeskNaming.derived(t, "title") ?? "filename"
                let artistFrom = DeskNaming.derived(t, "artist")
                let weak: Set<String> = ["filename", "folder"]
                var id = t.ident
                var tf = titleFrom, af = artistFrom
                if let title = r.titles[number], !LocalNames.isUsableTitle(id.title) || weak.contains(titleFrom) {
                    id.title = title; tf = "cdtext"
                }
                if let artist = r.performers[number] ?? r.discPerformer,
                   !LocalNames.isUsableArtist(id.artist) || weak.contains(artistFrom ?? "filename") {
                    id.artist = artist; af = "cdtext"
                }
                if tf == "cdtext" || af == "cdtext" {
                    id.source = id.artist == nil || af == tf ? tf : "\(tf)+\(af ?? tf)"
                    crate.tracks[i].ident = id
                    named[source, default: 0] += 1
                }
                continue
            }
            // Any other song: its album tag, when its file is here.
            if let ref = refs[t.id]?.first(where: { FileManager.default.fileExists(atPath: $0.url.path) }),
               let album = FileTags.read(ref.url).album?.trimmingCharacters(in: .whitespaces), !album.isEmpty {
                releases[t.id] = (album, "tag")
            }
        }
        var book = old
        book.record(crate, releases: releases)
        return (book, named)
    }
}
