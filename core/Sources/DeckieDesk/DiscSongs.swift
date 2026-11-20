import Foundation
import DeckieCrate
import DeckieBuild
import DeckieDisc

/// A music CD as a source, without keeping its music (the note on D33, Nov 14: "The crate file shouldn't rip the
/// music. Its just the crate file."). Desk reads a disc's songs to work them out and keeps what it learned, never
/// the sound:
///
///     <home>/Files/discs/<disc id>.json   what Desk learned from a disc, by the id its table of contents gives
///                                         (`DiscTOC.id`): the table, what the drive said about CD-Text, and each
///                                         song's id once it is worked out, so the same disc put in again is known
///                                         and only what is new on it is read
///     <home>/Reading/                     written by versions before Nov 20, 2026 (the song being read by sector, as a
///                                         WAV file); nothing is written there now, and anything found there is
///                                         removed when a desk or a run starts.
///
/// So Desk uses no disc space for a disc's music, on any computer: each song is read once into memory
/// (`DiscSongFiles`), 10.1 MB a minute of that song as CD audio (44,100 frames a second of two 16-bit channels), and
/// let go as soon as it is decoded.
public enum DiscRecords {
    public static func folder(_ home: DeskHome) -> URL { home.filesFolder.appendingPathComponent("discs", isDirectory: true) }
    public static func file(_ home: DeskHome, disc id: String) -> URL { folder(home).appendingPathComponent(id + ".json") }

    /// What Desk keeps about a disc: everything it learned, none of its music.
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
        /// The songs worked out: number, the song's id (the hash of its sound, as an entry's id is) and the sectors
        /// that could not be read even on a second try (silence in what was read).
        public var songs: [Song]
        public var fileExtension: String
        public struct Song: Codable, Equatable, Sendable {
            public var number: Int
            public var id: String
            public var damagedSectors: Int
            enum CodingKeys: String, CodingKey { case number, id, damagedSectors = "damaged_sectors" }
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
            songs = []
            self.fileExtension = fileExtension
        }

        enum CodingKeys: String, CodingKey {
            case toc, text, titles, performers, isrcs, songs, composers, songwriters, messages, barcode
            case textDetail = "text_detail", discTitle = "disc_title", discPerformer = "disc_performer"
            case fileExtension = "file_extension"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            toc = try c.decode(DiscTOC.self, forKey: .toc)
            text = try c.decode(String.self, forKey: .text)
            textDetail = try c.decodeIfPresent(String.self, forKey: .textDetail)
            discTitle = try c.decodeIfPresent(String.self, forKey: .discTitle)
            discPerformer = try c.decodeIfPresent(String.self, forKey: .discPerformer)
            titles = try c.decodeIfPresent([Int: String].self, forKey: .titles) ?? [:]
            performers = try c.decodeIfPresent([Int: String].self, forKey: .performers) ?? [:]
            isrcs = try c.decodeIfPresent([Int: String].self, forKey: .isrcs) ?? [:]
            composers = try c.decodeIfPresent([Int: String].self, forKey: .composers)
            songwriters = try c.decodeIfPresent([Int: String].self, forKey: .songwriters)
            messages = try c.decodeIfPresent([Int: String].self, forKey: .messages)
            barcode = try c.decodeIfPresent(String.self, forKey: .barcode)
            songs = try c.decodeIfPresent([Song].self, forKey: .songs) ?? []
            fileExtension = try c.decodeIfPresent(String.self, forKey: .fileExtension) ?? "wav"
        }

        public var damagedSectors: Int { songs.reduce(0) { $0 + $1.damagedSectors } }

        /// A song's file name as the crate shows it: "Track 07.wav", as a PC shows a music CD's songs.
        public func fileName(_ number: Int) -> String { String(format: "Track %02d.", number) + fileExtension }

        /// Notes a song worked out.
        public mutating func learned(_ number: Int, id: String, damaged: Int) {
            songs.removeAll { $0.number == number }
            songs.append(Song(number: number, id: id, damagedSectors: damaged))
            songs.sort { $0.number < $1.number }
        }
    }

    public static func record(_ home: DeskHome, disc id: String) -> Record? { JSONFile.read(Record.self, from: file(home, disc: id)) }
    public static func save(_ r: Record, home: DeskHome) throws { try JSONFile.write(r, to: file(home, disc: r.toc.id)) }

    /// The disc in the drive, read just far enough to add it: its table and CD-Text (both quick). A disc known
    /// before keeps what was learned; its text is read again only if the drive could not say before.
    @discardableResult
    public static func prepare(_ cd: MusicCD, home: DeskHome) throws -> Record {
        let toc = try cd.tableOfContents()
        if var old = record(home, disc: toc.id), old.toc == toc {
            if old.text == "drive" {
                var again = Record(toc: toc, reading: cd.readText(), fileExtension: old.fileExtension)
                if again.text != "drive" { again.songs = old.songs; old = again; try save(old, home: home) }
            }
            return old
        }
        let r = Record(toc: toc, reading: cd.readText(), fileExtension: cd.fileExtension)
        try save(r, home: home)
        return r
    }

    /// The disc with this id in one of this computer's drives: the drive it was last in first (`near`), then every
    /// drive holding a music CD. Nil when it is not in.
    public static func find(_ id: String, near: String?, open: (String) throws -> MusicCD,
                            musicCDs: () -> [MusicCDs.Found]) -> MusicCD? {
        if let near, let cd = try? open(near), (try? cd.tableOfContents().id) == id { return cd }
        for f in musicCDs() where f.discId == id && f.location != near {
            if let cd = try? open(f.location), (try? cd.tableOfContents().id) == id { return cd }
        }
        return nil
    }
}

/// `<home>/Reading/`, where versions before Nov 20, 2026 wrote the song being read off a disc by sector; nothing is
/// written there now, and what an older version left is removed.
public enum DiscReading {
    public static let folderName = "Reading"
    public static func folder(_ home: DeskHome) -> URL { home.root.appendingPathComponent(folderName, isDirectory: true) }

    /// Removes anything a stopped run left in `Reading/`, and the `Discs/` store the first build of music CDs kept
    /// (a copy of each disc's songs): what it learned moves to `Files/discs/`, its crates keep the disc's id, and the
    /// copied songs go. Called when a desk starts and when a run starts.
    public static func clearLeftovers(_ home: DeskHome) {
        try? DeckieFiles.remove(folder(home))
        let old = home.root.appendingPathComponent("Discs", isDirectory: true)
        guard FileManager.default.fileExists(atPath: old.path) else { return }
        let ids = ((try? FileManager.default.contentsOfDirectory(atPath: old.path)) ?? []).filter { !$0.hasPrefix(".") }
        for id in ids {
            let f = old.appendingPathComponent(id, isDirectory: true)
            if DiscRecords.record(home, disc: id) == nil, let r = JSONFile.read(DiscRecords.Record.self, from: f.appendingPathComponent("disc.json")) {
                try? DiscRecords.save(r, home: home)
            }
            for var info in home.shelf.list() {
                let sources = info.sourceRoots.filter { URL(fileURLWithPath: $0.value).standardizedFileURL.path == f.standardizedFileURL.path }.keys
                guard !sources.isEmpty else { continue }
                for s in sources { info.discs[s] = id }
                try? home.shelf.save(info)
            }
        }
        try? DeckieFiles.remove(old)
    }
}

/// A music CD's songs for the builder (`BuildFiles`), one at a time, each read once, into memory, and nothing of it
/// written to disk: on the Mac from the system's own file on the disc (`MacMusicCD`), elsewhere by sector. The
/// builder hashes, tags and analyses those bytes (`bytes`), and the print that finds copies is made from the audio
/// the analysis decoded, so the drive reads each song one time. A song whose id the disc's record has, with its
/// analysis and print in the store, is not read at all.
///
/// Read ahead: while the builder analyses a song, the next one it will ask for is read in the background
/// (`readAhead`), into memory only, so the drive keeps reading instead of stopping and starting between songs. At
/// most one song is read ahead, and none longer than `readAheadMostSeconds` of sound (a whole disc burned as one long
/// song would otherwise sit in memory twice). Stop, the disc coming out, an error and the end of the run all cancel
/// it (`clear`), and what it held goes with it. What is in memory at any moment: the song being analysed (its bytes
/// until they are decoded, then its decoded sound) and the next song's bytes as they come off the disc, about 10 MB
/// a minute of that song as CD audio. A crash leaves nothing behind: nothing of the music is ever on disk.
final class DiscSongFiles: BuildFiles, @unchecked Sendable {
    let cd: MusicCD
    let home: DeskHome
    let store: FileStore
    let needsSignature: Bool
    let stop: BuildStop?
    private let lock = NSLock()
    /// The disc as it was when the run began (its table and file type do not change); `record` gains the songs.
    let base: DiscRecords.Record
    private var record: DiscRecords.Record
    private var fetched: [String: (url: URL, damaged: Int, bytes: Data?)] = [:]
    private var ahead: Ahead?
    /// Told as a song comes off the disc: the song (its path as the builder names it), and sectors read of its
    /// sectors. At most once a percent. On the reading thread, or the read-ahead's.
    var onRead: (@Sendable (_ rel: String, _ done: Int, _ total: Int) -> Void)?
    /// Told when a read ahead ends: read whole, cancelled or failed (the song as the builder names it). On the read
    /// ahead's thread.
    var onAheadEnded: (@Sendable (_ rel: String) -> Void)?

    /// No song longer than this is read ahead (15 minutes of sound, about 150 MB as CD audio).
    static let readAheadMostSeconds = 15.0 * 60

    init(cd: MusicCD, record: DiscRecords.Record, home: DeskHome, store: FileStore, needsSignature: Bool, stop: BuildStop? = nil) {
        self.cd = cd; self.base = record; self.record = record; self.home = home; self.store = store
        self.needsSignature = needsSignature; self.stop = stop
    }

    var current: DiscRecords.Record { lock.lock(); defer { lock.unlock() }; return record }
    /// Where the song's name points on Linux and Windows (nothing is written there now: it names the song in
    /// messages and in the analysis, as the file read by sector once did).
    var reading: URL { DiscReading.folder(home).appendingPathComponent(base.toc.id, isDirectory: true) }

    /// The same for the same disc and different for another, so the builder's "unchanged since last time" holds
    /// only for the disc it was read from.
    var stamp: Double { Double(UInt32(String(base.toc.id.suffix(8)), radix: 16) ?? 0) }

    func song(_ f: SourceFile) -> DiscTOC.Song? {
        base.toc.songs.first { base.fileName($0.number) == CratePath.lastName(f.rel) }
    }

    func list() throws -> [SourceFile] {
        base.toc.songs.map { s in
            let name = base.fileName(s.number)
            let own = cd.file(of: s)
            let size = own.flatMap { (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.size] as? Int }
                ?? cd.wavBytes(s)
            return SourceFile(url: own ?? reading.appendingPathComponent(name), rel: name, ext: base.fileExtension,
                              size: size, modified: stamp)
        }
    }

    func knownId(_ f: SourceFile) -> String? {
        guard let s = song(f), let id = current.songs.first(where: { $0.number == s.number })?.id,
              store.hasRecord(id), store.print(id) != nil, !needsSignature || store.signature(id) != nil else { return nil }
        return id
    }

    /// A song being read ahead on a thread of its own.
    final class Ahead: @unchecked Sendable {
        let name: String
        private let lock = NSLock()
        private var cancelled = false
        let finished = DispatchSemaphore(value: 0)
        var result: Result<(data: Data, damaged: Int), Error> = .failure(Cancelled())
        init(name: String) { self.name = name }
        func cancel() { lock.lock(); cancelled = true; lock.unlock() }
        var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    }
    struct Cancelled: Error {}

    /// Reads a song's bytes into memory, reporting as it goes; `cancelled` is asked before each piece is kept.
    func read(_ s: DiscTOC.Song, rel: String, expected: Int, cancelled: @escaping () -> Bool) throws -> (data: Data, damaged: Int) {
        var data = Data()
        data.reserveCapacity(max(0, expected))
        var said = -1
        let tell = onRead
        let damaged = try cd.read(s, into: { piece in
            if cancelled() { throw Cancelled() }
            data.append(piece)
        }, progress: { done, total in
            let pct = total > 0 ? done * 100 / total : 100
            if pct != said { said = pct; tell?(rel, done, total) }
        })
        if cancelled() { throw Cancelled() }
        return (data, damaged)
    }

    func fetch(_ f: SourceFile) throws -> URL {
        guard let s = song(f) else { throw DeskError(DeskWords.text("error.noSongOnDisc", ["rel": f.rel])) }
        let name = CratePath.lastName(f.rel)
        let url = cd.file(of: s) ?? reading.appendingPathComponent(base.fileName(s.number))
        // The song read ahead, when it is this one (waiting for the rest of it); another read ahead is let go first,
        // so only one read uses the drive.
        lock.lock()
        let a = ahead
        ahead = nil
        lock.unlock()
        var got: (data: Data, damaged: Int)? = nil
        if let a {
            if a.name != name { a.cancel() }
            a.finished.wait()
            if a.name == name {
                switch a.result {
                case .success(let r):
                    got = r
                    // Read while the song before it was worked on: said as read, whole.
                    onRead?(f.rel, s.sectors, s.sectors)
                case .failure(let e) where !(e is Cancelled): throw e
                case .failure: break
                }
            }
        }
        // A song asked for is read to its end, as before: Stop lets the song being read finish.
        let read = try got ?? read(s, rel: f.rel, expected: f.size, cancelled: { false })
        lock.lock(); fetched[name] = (url, read.damaged, read.data); lock.unlock()
        return url
    }

    func bytes(_ f: SourceFile) -> Data? {
        lock.lock(); defer { lock.unlock() }
        let name = CratePath.lastName(f.rel)
        let d = fetched[name]?.bytes
        fetched[name]?.bytes = nil
        return d
    }

    func readAhead(_ f: SourceFile) {
        guard let s = song(f), Double(s.sectors) / Double(DiscTOC.sectorsPerSecond) <= Self.readAheadMostSeconds,
              stop?.isSet != true, knownId(f) == nil else { return }
        let a = Ahead(name: CratePath.lastName(f.rel))
        lock.lock()
        guard ahead == nil else { lock.unlock(); return }
        ahead = a
        lock.unlock()
        let stop = self.stop, rel = f.rel, expected = f.size
        let thread = Thread { [self] in
            do {
                a.result = .success(try read(s, rel: rel, expected: expected, cancelled: { a.isCancelled || stop?.isSet == true }))
            } catch {
                a.result = .failure(error)
            }
            // Said before the read is counted as over, so whoever waits for it hears of it first.
            onAheadEnded?(rel)
            a.finished.signal()
        }
        thread.start()
    }

    /// The song being read ahead now, or nil (for tests).
    var readingAhead: String? { lock.lock(); defer { lock.unlock() }; return ahead?.name }

    /// Lets go of the song being read ahead, waiting for its read to stop.
    func cancelReadAhead() {
        lock.lock()
        let a = ahead
        ahead = nil
        lock.unlock()
        a?.cancel()
        a?.finished.wait()
    }

    /// The URL a song fetched and not yet let go was read from (`rel` as the builder reports it, the source's name
    /// first): the Mac's own file on the disc, or on Linux and Windows the name of a file that is not there.
    func file(rel: String) -> URL? {
        lock.lock(); defer { lock.unlock() }
        return fetched[CratePath.lastName(rel)]?.url
    }

    /// Notes in the disc's record that a song fetched now is the entry `id`.
    func learned(rel: String, id: String) {
        lock.lock()
        let name = CratePath.lastName(rel)
        let damaged = fetched[name]?.damaged ?? 0
        if let s = base.toc.songs.first(where: { base.fileName($0.number) == name }) {
            record.learned(s.number, id: id, damaged: damaged)
            try? DiscRecords.save(record, home: home)
        }
        lock.unlock()
    }

    /// The sectors of a song fetched now that could not be read.
    func damaged(rel: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return fetched[CratePath.lastName(rel)]?.damaged ?? 0
    }

    func release(_ f: SourceFile) {
        lock.lock()
        fetched.removeValue(forKey: CratePath.lastName(f.rel))
        lock.unlock()
    }

    /// The run ended, or stopped: the read ahead is cancelled and waited for, everything held is let go, and whatever
    /// an older version left in `Reading/` is removed.
    func clear() {
        cancelReadAhead()
        lock.lock(); fetched = [:]; lock.unlock()
        try? DeckieFiles.remove(DiscReading.folder(home))
    }
}

/// Where a song's sound is, for Listen (D33): a file on a source that is plugged in, or a song on a music CD that is
/// in a drive (on the Mac that too is a file, on the disc). Nothing is copied to play it.
public enum DeskAudio {
    public enum Sound {
        case file(URL)
        /// A song read off the disc by sector when it is asked for (Linux, Windows).
        case disc(MusicCD, DiscTOC.Song)
    }

    /// No place of the song is here: `source` is the one to put back ("Put Friday night back in to listen").
    public struct NotHere: Error { public let source: String }

    public static func find(_ t: CrateTrack, info: CrateInfo?, paths: PlacePaths,
                            open: (String) throws -> MusicCD = { try MusicCDs.open($0) },
                            musicCDs: () -> [MusicCDs.Found] = { MusicCDs.list() }) throws -> Sound {
        if let u = paths.locate(t, roots: info?.roots ?? [:], musicFolder: info?.musicFolderURL) { return .file(u) }
        for p in t.placesInOrder {
            guard let source = p.disc, let id = info?.discs[source],
                  let number = discNumber(t, at: p, paths: paths),
                  let cd = DiscRecords.find(id, near: info?.sourceRoots[source], open: open, musicCDs: musicCDs),
                  let song = try? cd.tableOfContents().songs.first(where: { $0.number == number }) else { continue }
            if let u = cd.file(of: song) { return .file(u) }
            return .disc(cd, song)
        }
        throw NotHere(source: t.ident.disc ?? info?.musicFolderURL?.lastPathComponent ?? "")
    }

    /// The disc's own number of a song at a place on a music CD: from its file name there ("Track 07.wav"), else the
    /// place's number.
    static func discNumber(_ t: CrateTrack, at p: CrateTrack.Place, paths: PlacePaths) -> Int? {
        if let rel = paths.rel(for: t.id, at: p) ?? (p == t.ident.ownPlace ? t.file.rel : nil),
           let n = DiscSongFiles.number(of: rel) { return n }
        return p.track
    }

    /// A song's whole sound off the disc, as WAV bytes (Linux, Windows): read now, held in memory only while it is
    /// handed over.
    public static func read(_ cd: MusicCD, _ song: DiscTOC.Song) throws -> Data {
        var d = Data(capacity: cd.wavBytes(song))
        _ = try cd.read(song, into: { d.append($0) }, progress: { _, _ in })
        return d
    }
}

extension DiscSongFiles {
    /// The name the run screen shows for a disc's song as it is read: the builder's first name (the file's tags, else
    /// its file name), with the disc's CD-Text title and performer where the name is only the file's name ("Track 02"),
    /// as the crate will hold it once the names step has run (`DeskNamesStep`).
    static func shownName(rel: String, title: String?, artist: String?, record r: DiscRecords.Record) -> (title: String?, artist: String?) {
        guard let n = number(of: rel) else { return (title, artist) }
        let fileName = (CratePath.lastName(rel) as NSString).deletingPathExtension
        let fromFileName = title == nil || title == fileName
        let shown = fromFileName ? (r.titles[n] ?? title) : title
        let by = artist ?? (fromFileName && r.titles[n] != nil ? r.performers[n] ?? r.discPerformer : nil)
        return (shown, by)
    }

    /// 7 for "Track 07.wav".
    static func number(of rel: String) -> Int? {
        let name = CratePath.lastName(rel)
        guard name.hasPrefix("Track ") else { return nil }
        return Int(name.dropFirst(6).prefix { $0.isNumber })
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
    /// When `text` is `drive`: what the drive said when asked for CD-Text (the system's error), so a run's line shows
    /// whether a disc with no names was a refusal or a failure. Nil otherwise, and in a line written before it.
    public var textDetail: String? = nil
    enum CodingKeys: String, CodingKey { case text, songs, named, titled, damagedSectors = "damaged_sectors", textDetail = "text_detail" }
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
        var discs: [String: DiscRecords.Record] = [:]
        for (source, id) in info.discs { if let r = DiscRecords.record(home, disc: id) { discs[source] = r } }
        var named: [String: Int] = [:]
        var releases: [String: (String, String)] = [:]
        let refs = DeskLocalFacts.files(for: crate, paths: paths, roots: info.roots, musicFolder: info.musicFolderURL)
        for i in crate.tracks.indices {
            let t = crate.tracks[i]
            // A disc's song: its place on the disc's source, by the disc's own number.
            if let (source, number) = t.ident.allPlaces.lazy.compactMap({ p -> (String, Int)? in
                guard let d = p.disc, discs[d] != nil, let n = DeskAudio.discNumber(t, at: p, paths: paths) else { return nil }
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
