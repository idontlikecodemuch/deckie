import Foundation
import DeckieCrate
import DeckieBuild
import DeckieDisc
import DeckieLookup

/// "Look up songs via MusicBrainz" (D36; the note on D30; research AA, 3.8 to 3.12), as both windows do it: what each
/// song would send, the sentence shown before anything is sent, the lookup itself (one request a second, through
/// DeckieLookup, which is the only code that uses the network), the candidates for each song ranked by how well
/// their length fits, the review with a tick per field, and applying what the DJ ticked as one step of undo.
///
/// The rules it keeps:
/// - Nothing is sent until the DJ has read the sentence and said yes; nothing is applied until the DJ has seen it.
/// - What is applied goes into the same fields as everything else (names, and the facts of D34) with the origin
///   `lookup:musicbrainz`; it fills what is empty unless the DJ ticks otherwise, and never touches the DJ's own entry.
/// - A version in the DJ's title is never dropped or replaced by another; a candidate that is plainly another
///   version is shown but never preferred.
/// - Genre is not taken: MusicBrainz's genres are tags, which its licence keeps for non-commercial use.
public enum DeskLookup {
    public static let service = MusicBrainz.service
    /// The origin of whatever a lookup fills (crate-format.md, the addition with D34).
    public static let origin = SongFacts.Origin.lookup(MusicBrainz.service)
    /// The version in the User-Agent: Desk's own (desk-app/project.yml, CFBundleShortVersionString).
    public static let appVersion = "0.1"
    /// Two lengths are the same version's within this many seconds (letter AA, 6.4.3), as for a playlist.
    public static let allowance = DeskNaming.lengthAllowance
    /// The most candidates a song shows.
    public static let shownCandidates = 8
    /// The most releases a disc's name search looks into (one request each).
    public static let releasesLookedInto = 3

    /// The client every window uses: the system's way out (or `DECKIE_LOOKUP_RECORDED`'s answers), the shared gate.
    public static func client(environment: [String: String] = ProcessInfo.processInfo.environment) -> MusicBrainz {
        MusicBrainz(version: appVersion, transport: LookupTransports.forEnvironment(environment))
    }

    // MARK: what a song would send

    /// What one song's lookup sends: its ISRC (`isrc`), its bare title, first credited artist and release (`words`),
    /// the same read from its file name when it has no title (`fileName`), or nothing (`none`: no title and a file name
    /// such as "Track 04", which only a disc's lookup can name).
    public struct Ask: Codable, Equatable, Sendable {
        public var kind: String
        public var isrc: String?
        public var query: RecordingQuery?
    }

    /// What a song would send (D39; research AC, 5.1): the bare title (its version, clean or dirty, marks, numbers,
    /// keys and websites' names left out; a part of the title, such as "Part 2", kept) and the first credited artist.
    /// Everything else of the song is kept as it is and used afterwards, to judge the candidates. An ISRC beats words
    /// (letter AA, 6.4.5: one ISRC is one version); the words go too, as the second request when it finds nothing.
    public static func ask(_ s: DeskNaming.Song, isrc: String? = nil) -> Ask {
        let t = s.track
        let code = (isrc ?? t.ident.facts[SongFacts.isrc]?.values.first).map { $0.uppercased().filter { $0.isLetter || $0.isNumber } }
        let goodIsrc = code.flatMap { $0.count == 12 ? $0 : nil }
        var query: RecordingQuery? = nil
        if LocalNames.isUsableTitle(t.ident.title) {
            let r = NameReading.readTags(title: t.ident.title, artist: t.ident.artist)
            let title = r.title.isEmpty ? t.ident.title : r.title
            let artist = LocalNames.isUsableArtist(t.ident.artist) ? (r.firstArtist ?? t.ident.artist) : nil
            query = RecordingQuery(title: title, artist: artist, release: t.ident.facts[SongFacts.release]?.values.first)
        } else {
            let stem = (t.file.name as NSString).deletingPathExtension
            if LocalNames.isUsableTitle(stem) {
                let r = NameReading.readFileName(stem, number: t.ident.track)
                let title = r.title.isEmpty ? stem : r.title
                if let a = r.firstArtist, LocalNames.isUsableArtist(a), LocalNames.isUsableTitle(title) {
                    query = RecordingQuery(title: title, artist: a)
                } else {
                    query = RecordingQuery(words: title)
                }
                if let g = goodIsrc { return Ask(kind: "isrc", isrc: g, query: query) }
                return Ask(kind: "fileName", isrc: nil, query: query)
            }
        }
        if let g = goodIsrc { return Ask(kind: "isrc", isrc: g, query: query) }
        if let query { return Ask(kind: "words", isrc: nil, query: query) }
        return Ask(kind: "none", isrc: nil, query: nil)
    }

    /// The second ask (AC 5.3, suggestion 3), when title and artist found nothing: the bare title and the first
    /// credited artist as free words, so a cut or swapped artist still finds the song; then, when that finds nothing
    /// and the version names a person, the title with that person (a bootleg's "artist" is often its remixer). What
    /// comes back is never chosen from without a whole-name match (`order`).
    public static func secondAsks(_ s: DeskNaming.Song, first: Ask) -> [RecordingQuery] {
        guard let q = first.query, let title = q.title, let artist = q.artist else { return [] }
        var out = [RecordingQuery(words: "\(title) \(artist)")]
        let known = Known(s, ask: first)
        if let name = known.version?.names.first, !NameReading.compareWords(artist).elementsEqual(NameReading.compareWords(name)) {
            out.append(RecordingQuery(words: "\(title) \(name)"))
        }
        return out
    }

    // MARK: the plan and its sentence

    /// A music CD's lookup: its table as MusicBrainz counts it, its name when it has one, and each song's number.
    public struct DiscPlan: Sendable {
        public var source: String
        public var table: DiscTable
        public var name: String?
        public var numbers: [String: Int]
    }

    /// What a lookup will do, before it does it: the songs, what each sends, and for a disc its table.
    public struct Plan: @unchecked Sendable {
        /// `song` (one song), `songs` (a batch), `disc`.
        public var scope: String
        public var songs: [DeskNaming.Song]
        public var asks: [Ask]
        public var disc: DiscPlan?
        public var summary: Summary
    }

    /// The plan as the sentence and the windows need it.
    public struct Summary: Codable, Equatable, Sendable {
        public var scope: String
        public var songs: Int
        public var byIsrc: Int
        public var byWords: Int
        public var byFileName: Int
        public var nothingToSend: Int
        /// The most requests it can make, and about how long that takes at one a second.
        public var requests: Int
        public var seconds: Int
        public var discName: String?
        /// The sentence, line by line, in DeskWords.
        public var sentence: [String]
        /// For one song: what it would send, as the line under the button says it.
        public var what: [[String]]?
    }

    /// The plan for these songs (one: `song`; more: `songs`). `isrcs` gives a disc's own ISRCs by song id.
    public static func plan(_ songs: [DeskNaming.Song], isrcs: [String: String] = [:]) -> Plan {
        let asks = songs.map { ask($0, isrc: isrcs[$0.track.id]) }
        let scope = songs.count == 1 ? "song" : "songs"
        var s = Summary(scope: scope, songs: songs.count, byIsrc: asks.filter { $0.kind == "isrc" }.count,
                        byWords: asks.filter { $0.kind == "words" }.count,
                        byFileName: asks.filter { $0.kind == "fileName" }.count,
                        nothingToSend: asks.filter { $0.kind == "none" }.count, requests: 0, seconds: 0, discName: nil,
                        sentence: [], what: nil)
        // A search a song, a second when an ISRC finds nothing, and one for the label of the release that fits.
        s.requests = asks.reduce(0) { $0 + ($1.kind == "none" ? 0 : ($1.kind == "isrc" && $1.query != nil ? 3 : 2)) }
        s.seconds = Int((Double(s.requests) * MusicBrainzRules.interval).rounded(.up))
        if songs.count == 1, let a = asks.first {
            var what: [[String]] = []
            if let i = a.isrc { what.append(["isrc", i]) }
            what += a.query?.fields ?? []
            s.what = what
        }
        s.sentence = sentence(s)
        return Plan(scope: scope, songs: songs, asks: asks, disc: nil, summary: s)
    }

    /// The plan a window asks for (both windows use this): `scope` `disc` for the music CD added as `source`;
    /// otherwise the songs given (`ids`), a source's songs (`source`), or, with neither, the songs that need a name.
    public static func plan(scope: String, ids: [String]?, source: String?, crate c: Crate, info: CrateInfo?,
                            paths: PlacePaths, home: DeskHome, facts: (CrateTrack) -> DeskNaming.Facts) throws -> Plan {
        if scope == "disc" {
            guard let source, let discId = info?.discs[source], let record = DiscRecords.record(home, disc: discId) else {
                throw DeskError(DeskWords.text("error.notAMusicCD", ["source": source ?? DeskWords.text("error.thatSource")]))
            }
            var numbers: [String: Int] = [:]
            var songs: [DeskNaming.Song] = []
            for t in DeskNaming.order(c, source: source, ids: nil) {
                guard let p = t.ident.allPlaces.first(where: { $0.disc == source }),
                      let n = DeskAudio.discNumber(t, at: p, paths: paths) else { continue }
                numbers[t.id] = n
                songs.append(DeskNaming.Song(track: t, facts: facts(t)))
            }
            // The disc's name: its own title (CD-Text), else the name the DJ gave the source, never the placeholder.
            let placeholder = DeskSession.placeholderName(record.toc)
            let name = record.discTitle ?? (source.hasPrefix(placeholder) ? nil : source)
            return discPlan(source: source, record: record, songs: songs, numbers: numbers, name: name)
        }
        var songs: [DeskNaming.Song]
        let song = { (t: CrateTrack) in DeskNaming.Song(track: t, facts: facts(t)) }
        if let ids { songs = DeskNaming.order(c, source: nil, ids: ids).map(song) }
        else if let source { songs = DeskNaming.order(c, source: source, ids: nil).map(song) }
        else { songs = c.tracks.map(song).filter { DeskNaming.reason($0.track, $0.facts) != nil } }
        // What each song's folder is (D39): read from the songs of the crate that share it.
        let folders = folderReadings(c)
        for i in songs.indices { songs[i].folder = folders[songs[i].track.id] }
        // A music CD's own ISRCs (its sub-code), by song.
        var isrcs: [String: String] = [:]
        for s in songs {
            for p in s.track.ident.allPlaces {
                guard let d = p.disc, let id = info?.discs[d], let r = DiscRecords.record(home, disc: id),
                      let n = DeskAudio.discNumber(s.track, at: p, paths: paths), let isrc = r.isrcs[n] else { continue }
                isrcs[s.track.id] = isrc
            }
        }
        return plan(songs, isrcs: isrcs)
    }

    /// Each song's folder read (`LocalNames.readFolder`) with the other songs of the crate in the same folder: their
    /// file names, and the artists and compilation marks their tags gave.
    public static func folderReadings(_ c: Crate) -> [String: LocalNames.FolderReading] {
        func folder(_ t: CrateTrack) -> String {
            if let d = t.ident.disc { return d + "/" + (t.ident.folder ?? "") }
            return CratePath.folder(of: t.file.rel ?? t.file.name)
        }
        var byFolder: [String: [CrateTrack]] = [:]
        for t in c.tracks { byFolder[folder(t), default: []].append(t) }
        var out: [String: LocalNames.FolderReading] = [:]
        for (key, tracks) in byFolder {
            let siblings = tracks.map { t in
                LocalNames.Sibling(stem: (t.file.name as NSString).deletingPathExtension,
                                   tagArtist: (t.ident.source ?? "").hasPrefix("tag") || t.ident.source == "user" ? t.ident.artist : nil,
                                   compilationMark: t.ident.facts[SongFacts.compilation]?.values.first == "1",
                                   releaseArtist: t.ident.facts[SongFacts.releaseArtist]?.values.first)
            }
            let names = key.split(separator: "/").map(String.init)
            let reading = LocalNames.readFolder(names, siblings: siblings)
            for t in tracks { out[t.id] = reading }
        }
        return out
    }

    /// The plan for a music CD added as `source`: its table from what Desk keeps about the disc (`DiscRecords`), its
    /// name (the disc's own title, else the source's name when the DJ gave it one), its songs by number.
    public static func discPlan(source: String, record: DiscRecords.Record, songs: [DeskNaming.Song],
                                numbers: [String: Int], name: String?) -> Plan {
        let audio = record.toc.tracks.filter(\.audio)
        let table = DiscTable(tracks: audio.map { ($0.number, $0.start) }, audioEnd: record.toc.leadOut)
        return discPlan(source: source, table: table, songs: songs, numbers: numbers, name: name)
    }

    /// The plan for a disc whose table is given (as MusicBrainz counts it).
    public static func discPlan(source: String, table: DiscTable, songs: [DeskNaming.Song], numbers: [String: Int],
                                name: String?) -> Plan {
        let disc = DiscPlan(source: source, table: table, name: name, numbers: numbers)
        var s = Summary(scope: "disc", songs: table.offsets.count, byIsrc: 0, byWords: 0, byFileName: 0, nothingToSend: 0,
                        requests: 1 + (name == nil ? 0 : 1 + releasesLookedInto), seconds: 0, discName: name,
                        sentence: [], what: nil)
        s.seconds = Int((Double(s.requests) * MusicBrainzRules.interval).rounded(.up))
        s.sentence = sentence(s)
        return Plan(scope: "disc", songs: songs, asks: [], disc: disc, summary: s)
    }

    /// The sentence shown before anything is sent (letter AA, 3.8): what will be sent, to whom, what will not, and
    /// how long a batch takes. Every word is in DeskWords.
    public static func sentence(_ s: Summary) -> [String] {
        var lines: [String] = []
        switch s.scope {
        case "disc":
            lines.append(DeskWords.count(s.discName == nil ? "lookupSendDisc" : "lookupSendDiscNamed", s.songs,
                                         ["name": s.discName ?? ""]))
        case "song":
            let key = s.byIsrc > 0 ? "lookupSendOneIsrc" : (s.byFileName > 0 ? "lookupSendOneFileName" : "lookupSendOne")
            lines.append(DeskWords.text(s.nothingToSend > 0 ? "lookupNothingToSendOne" : key))
            // Then exactly what goes, word for word.
            if s.nothingToSend == 0, let what = s.what, !what.isEmpty {
                lines.append(DeskWords.text("lookupSendExactly", ["what": what.map {
                    DeskWords.text("lookupWhat." + $0[0], ["value": $0[1]]) }.joined(separator: ", ")]))
            }
        default:
            let asked = s.songs - s.nothingToSend
            lines.append(DeskWords.count("lookupSendMany", asked, ["duration": DeskWords.duration(s.seconds)]))
            if s.byIsrc > 0 { lines.append(DeskWords.count("lookupSendManyIsrc", s.byIsrc)) }
            if s.byFileName > 0 { lines.append(DeskWords.count("lookupSendManyFileName", s.byFileName)) }
            if s.nothingToSend > 0 { lines.append(DeskWords.count("lookupSendManyNothing", s.nothingToSend)) }
        }
        if s.scope != "disc" && s.nothingToSend < s.songs { lines.append(DeskWords.text("lookupSendLabel")) }
        lines.append(DeskWords.text("lookupSendNotSent"))
        return lines
    }

    // MARK: candidates

    /// One answer for one song, as the review shows it beside the others.
    public struct Candidate: Codable, Equatable, Sendable {
        /// MusicBrainz's id of the recording (CC0, kept with the review, never in the crate file).
        public var recording: String?
        public var title: String
        public var version: String?
        public var artist: String?
        public var release: String?
        public var releaseId: String?
        public var year: String?
        public var label: String?
        public var seconds: Double?
        /// `fits` (within `allowance` of the song's length), `off` (further), `unknown` (no length).
        public var fit: String
        /// The candidate's length less the song's, in seconds.
        public var difference: Double?
        /// Plainly another version: shown, never preferred.
        public var otherVersion: Bool
        /// Why, and what else to know, as codes (words `lookupNote.<code>`): `live`, `remix`, `edit`, `djMix`,
        /// `video`, `versionDiffers`, `lengthDiffers`, `original` (the song is a DJ's or a pool's edit and this the
        /// original: its year and label are the original's), `catalogueWord` (the same record under the catalogue's
        /// word for its version), `sameTake` (the clean or dirty twin), `notInCatalogue`, `disc`, `fuzzy`, `byName`,
        /// `fromFolder` (the artist sent was read from the folder), `askedAgain` (found by the second ask).
        public var notes: [String]
        /// How well it agrees with what Desk already knows (title, artist, release, year, ISRC).
        public var agree: Int
        /// What it would change, field by field, with a tick each (DeskNaming.Change: `before`, `after`, `tick`
        /// for when this candidate is the one used, `locked`, `note`).
        public var changes: [DeskNaming.Change]
        var score: Int
        /// The credit's names as the catalogue splits them, and which of them were joined as featured guests.
        public var credited: [String]?
        public var featuring: [Bool]?
        /// How its version reads against the song's (`VersionMatch`), and whether its title and its credited names
        /// stand whole in the song's (D39, AC 5.3 suggestion 6).
        public var match: String?
        public var titleAgrees: Bool?
        public var artistAgrees: Bool?
        /// Clean or dirty as the catalogue's title or note says it (shown, never taken).
        public var lyrics: String?
        /// The fields that candidates folded with this one disagree on (`release`, `year`, `label`): left unticked.
        public var disagree: [String]?
    }

    /// What Desk knows of a song, as the ranking compares it: its name read the way a DJ means it (D39).
    struct Known {
        var title: String?
        var version: VersionReading?
        var artist: String?
        var firstArtist: String?
        var featured: String?
        var release: String?
        var year: String?
        var isrc: String?
        var seconds: Double
        var kind: String
        /// The song is on a compilation: its copy's release stays, the lookup gives when the song first came out.
        var compilation: Bool
        /// The artist was read from the folder.
        var artistFromFolder: Bool

        init(_ s: DeskNaming.Song, ask: Ask) {
            let t = s.track
            var read: ReadName? = nil
            if LocalNames.isUsableTitle(t.ident.title) {
                read = NameReading.readTags(title: t.ident.title, artist: t.ident.artist)
            } else if let q = ask.query {
                let stem = (t.file.name as NSString).deletingPathExtension
                read = NameReading.readFileName(stem, number: t.ident.track)
                if read?.title.isEmpty ?? true { read?.title = q.title ?? q.words ?? "" }
            }
            title = read?.title
            let stored = t.ident.version.flatMap { $0.isEmpty ? nil : NameReading.readVersion($0) }
            version = stored.map { $0.merged(read?.version) } ?? read?.version
            artist = LocalNames.isUsableArtist(t.ident.artist) ? t.ident.artist : (read?.artist ?? ask.query?.artist)
            if let a = artist, LocalNames.isUsableTitle(t.ident.title) { artist = NameReading.readTags(title: "x", artist: a).artist ?? a }
            firstArtist = artist.flatMap(NameReading.firstArtist)
            featured = read?.featured
            release = t.ident.facts[SongFacts.release]?.values.first
            year = t.ident.facts[SongFacts.year]?.values.first
            isrc = ask.isrc
            seconds = t.file.durationS
            kind = ask.kind
            let releaseArtist = t.ident.facts[SongFacts.releaseArtist]?.values.first
            compilation = t.ident.facts[SongFacts.compilation]?.values.first == "1"
                || (releaseArtist.map { !LocalNames.isUsableArtist($0) } ?? false) || s.folder?.kind == .compilation
            artistFromFolder = DeskNaming.derived(t, "artist") == "folder"
        }

        /// The words of everything the DJ wrote for the artist: the credit and a featured credit in the title.
        var artistWords: [String] { NameReading.compareWords([artist, featured].compactMap { $0 }.joined(separator: " ")) }
    }

    /// Words that mean no version at all ("Original Mix", "Album Version"; letter AA, 6.4.2). Kept for the old
    /// comparison the trial scores beside the new one; the lookup reads versions by kind (`VersionWords`).
    static let plain: Set<String> = ["original mix", "original", "album version", "original version", "single version",
                                     "remastered", "remaster"]

    /// Text compared loosely: lower case, accents and punctuation gone, "&" as "and", one space between words.
    public static func norm(_ s: String?) -> String {
        guard let s else { return "" }
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        var out = String(kept).split(separator: " ").joined(separator: " ")
        if out.hasPrefix("the ") { out.removeFirst(4) }
        return out
    }

    /// A version's words that make it another recording (letter AA, 6.2), as the lookup read them before D39: kept
    /// for the trial's old comparison and for the review's short notes (`live`, `remix`, `edit`).
    public static func markers(_ s: String?) -> Set<String> {
        let n = norm(s)
        guard !n.isEmpty, !plain.contains(n) else { return [] }
        let words = Set(n.split(separator: " ").map(String.init))
        var out = Set<String>()
        if words.contains("live") { out.insert("live") }
        if words.contains("remix") || words.contains("rmx") || words.contains("rework") { out.insert("remix") }
        if words.contains("edit") || words.contains("radio") { out.insert("edit") }
        if words.contains("dub") { out.insert("dub") }
        if words.contains("instrumental") { out.insert("instrumental") }
        if words.contains("acapella") || words.contains("cappella") { out.insert("acapella") }
        if words.contains("extended") || words.contains("club") { out.insert("extended") }
        if words.contains("acoustic") || words.contains("demo") || words.contains("unplugged") { out.insert("other") }
        if words.contains("mix") && out.isEmpty && !words.contains("dj") { out.insert("mix") }
        return out
    }

    /// The version a catalogue's title and note give, read by kind: the brackets at the end of its title (MusicBrainz's
    /// own rule for writing one), else its disambiguation when that reads as a version.
    static func candidateVersion(title: String, disambiguation: String?) -> (title: String, version: String?, reading: VersionReading?, featured: String?) {
        let r = NameReading.readTitle(title)
        var reading = r.version
        var written = r.version?.written
        if reading == nil, let d = disambiguation?.trimmingCharacters(in: .whitespaces), !d.isEmpty {
            if case let .version(v) = NameReading.piece(d), !v.kinds.isEmpty || v.lyrics != nil { reading = v; written = d }
        } else if let d = disambiguation, case let .version(v) = NameReading.piece(d), v.lyrics != nil, reading?.lyrics == nil {
            reading?.lyrics = v.lyrics
        }
        return (r.title.isEmpty ? title : r.title, written, reading, r.featured)
    }

    /// A candidate from a recording: its version by kind; the release Desk already knows when the recording is on it,
    /// else its earliest official release that is not a compilation; the year of its first release.
    static func candidate(_ r: MBRecording, known: Known) -> Candidate {
        let dis = r.disambiguation?.trimmingCharacters(in: .whitespaces)
        var notes: [String] = []
        let disNorm = norm(dis)
        let djMix = disNorm.contains("dj mix") || disNorm.contains("dj‐mix") || (disNorm.hasPrefix("part of") && disNorm.contains("mix"))
        if djMix { notes.append("djMix") }
        if r.video == true || disNorm.contains("music video") || disNorm == "video" { notes.append("video") }
        let v = candidateVersion(title: r.title ?? "", disambiguation: djMix ? nil : dis)
        let release = pickRelease(r.releases ?? [], known: known.release)
        let year = (r.firstReleaseDate ?? release?.date).flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
        let credit = r.artistCredit ?? []
        return Candidate(recording: r.id, title: v.title, version: v.version,
                         artist: credit.line, release: release?.title, releaseId: release?.id, year: year,
                         label: release?.labels.first, seconds: r.length.map { Double($0) / 1000 }, fit: "unknown",
                         difference: nil, otherVersion: false, notes: notes, agree: 0, changes: [], score: r.score ?? 0,
                         credited: credit.compactMap(\.name), featuring: featuringFlags(credit),
                         match: nil, titleAgrees: nil, artistAgrees: nil, lyrics: v.reading?.lyrics?.rawValue, disagree: nil)
    }

    /// Which names of a catalogue's credit were joined as featured guests ("A feat. B": B).
    static func featuringFlags(_ credit: [MBCredit]) -> [Bool] {
        var out: [Bool] = []
        var next = false
        for c in credit {
            out.append(next)
            let j = (c.joinphrase ?? "").lowercased()
            // Once the credit says "featuring", every name after it is a guest.
            next = next || j.contains("feat") || j.contains(" ft") || j.contains("with") || j.hasPrefix("ft")
        }
        return out
    }

    static func pickRelease(_ releases: [MBRelease], known: String?) -> MBRelease? {
        if let k = known, !norm(k).isEmpty, let same = releases.first(where: { norm($0.title) == norm(k) }) { return same }
        func rank(_ r: MBRelease) -> (Int, Int, String) {
            let official = r.status == nil || r.status == "Official" ? 0 : 1
            let types = r.releaseGroup?.secondaryTypes ?? []
            let plainRelease = types.isEmpty ? 0 : 1
            return (official, plainRelease, (r.date?.isEmpty == false ? r.date! : "9999"))
        }
        return releases.min { rank($0) < rank($1) }
    }

    /// Whether a candidate's title agrees with the song's: the same whole words, once the versions and the featured
    /// credits are taken out of both (AC 5.3, suggestion 6). A one-word title inside a longer one is another song.
    static func titleAgrees(_ c: Candidate, known: Known) -> Bool {
        let kt = NameReading.compareWords(known.title), ct = NameReading.compareWords(c.title)
        return !kt.isEmpty && kt == ct
    }

    /// Whether a candidate's credit agrees with the song's, by whole credited names (AC 5.3, suggestion 6; 2.3): the
    /// catalogue's first credited name stands whole in the DJ's credit, and so does each of its other names except a
    /// featured guest, whom a file often leaves out; and the DJ's first credited artist stands whole in the
    /// catalogue's credit. The DJ's credit is never split for this: a duo with "&" in its name stays whole.
    static func artistAgrees(_ c: Candidate, known: Known) -> Bool {
        let dj = known.artistWords
        guard !dj.isEmpty else { return false }
        let names = c.credited?.isEmpty == false ? c.credited! : (c.artist.map { NameReading.credit($0).map(\.name) } ?? [])
        guard let first = names.first, NameReading.containsWhole(NameReading.compareWords(first), in: dj) else { return false }
        let flags = c.featuring ?? []
        for (i, n) in names.enumerated().dropFirst() where !(i < flags.count && flags[i]) {
            if !NameReading.containsWhole(NameReading.compareWords(n), in: dj) { return false }
        }
        let cw = NameReading.compareWords(c.artist ?? names.joined(separator: " "))
        let kf = NameReading.compareWords(known.firstArtist ?? known.artist)
        return NameReading.containsWhole(kf, in: cw)
    }

    /// Rates a candidate against the song: how its length fits (within `allowance`), how its version reads against
    /// the song's by kind (`VersionCompare`), whether its title and credited names agree whole, and a score for the
    /// order shown.
    static func rate(_ c: inout Candidate, known: Known, isrcs: [String] = []) {
        if let secs = c.seconds, known.seconds > 0 {
            c.difference = secs - known.seconds
            c.fit = abs(secs - known.seconds) <= allowance ? "fits" : "off"
        }
        let cv = c.version.map(NameReading.readVersion).map { r -> VersionReading in
            var r = r; if r.lyrics == nil, let l = c.lyrics { r.lyrics = Lyrics(rawValue: l) }; return r
        } ?? c.lyrics.flatMap { Lyrics(rawValue: $0) }.map { VersionReading(written: "", lyrics: $0) }
        let m = VersionCompare.compare(song: known.version, candidate: cv, fits: c.fit == "fits")
        c.match = m.rawValue
        // The review's short notes: what this candidate is that the song is not.
        let songMarks = markers(known.version?.written)
        for mk in markers(c.version).subtracting(songMarks).sorted() where ["live", "remix", "edit"].contains(mk) && !c.notes.contains(mk) {
            c.notes.append(mk)
        }
        switch m {
        case .original: c.notes.append("original")
        case .catalogueWord: c.notes.append("catalogueWord")
        case .sameTake: c.notes.append("sameTake")
        case .notInCatalogue: c.notes.append("notInCatalogue")
        case .other:
            // The song has a version and this is the plain one: its facts are the original's (shown, not chosen).
            if !(known.version?.isPlain ?? true) && (cv?.isPlain ?? true) { c.notes.append("original") }
            else if !(known.version?.isPlain ?? true) || !(cv?.isPlain ?? true) { c.notes.append("versionDiffers") }
        case .same: break
        }
        if c.fit == "off" { c.notes.append("lengthDiffers") }
        c.otherVersion = !m.chooses || c.fit == "off" || c.notes.contains("djMix") || c.notes.contains("video")
        c.titleAgrees = titleAgrees(c, known: known)
        c.artistAgrees = artistAgrees(c, known: known)
        var agree = 0
        if c.titleAgrees == true { agree += 2 } else if !NameReading.compareWords(known.title).isEmpty,
            NameReading.containsWhole(NameReading.compareWords(known.title), in: NameReading.compareWords(c.title)) { agree += 1 }
        if c.artistAgrees == true { agree += 2 }
        if let r = known.release, !norm(r).isEmpty, norm(r) == norm(c.release) { agree += 1 }
        if let y = known.year, y.prefix(4) == (c.year ?? "") { agree += 1 }
        if let i = known.isrc, isrcs.contains(i) { agree += 3 }
        c.agree = agree
    }

    /// The candidates in order (those whose length fits and that are not another version first, then those with no
    /// length, then the rest; within each, the most agreement, then the closest length, then MusicBrainz's own score;
    /// copies of one answer shown once), and the one Desk would use by itself (D39):
    ///
    /// - A candidate may be chosen when its length fits, its version reads as the song's by kind (`VersionMatch`), its
    ///   title agrees by whole words and its credit by whole names. A song with no artist known gives a list, unless it
    ///   was found by its ISRC or its disc.
    /// - Candidates that differ only in how the credit or the title is spelled fold into one name (AC 5.3, suggestion
    ///   4); never across a version kind, clean against explicit, or years more than one apart. Several names left is
    ///   "several": a list. What folded candidates disagree on is noted on the chosen one (`disagree`), left unticked.
    /// - A DJ's or a pool's edit whose original is the one name that agrees (by title and whole names; its length
    ///   cannot fit) is chosen as the original (`mode` `original`): only the original's year and label are offered.
    ///
    /// `rules` says what let the choice through, for the trial.
    static func order(_ all: [Candidate], known: Known) -> (candidates: [Candidate], chosen: Int?, several: Bool, mode: String?, rules: [String]) {
        func group(_ c: Candidate) -> Int { c.otherVersion ? 2 : (c.fit == "fits" ? 0 : (c.fit == "unknown" ? 1 : 2)) }
        let sorted = all.sorted { a, b in
            if group(a) != group(b) { return group(a) < group(b) }
            if a.agree != b.agree { return a.agree > b.agree }
            let da = abs(a.difference ?? 1e9), db = abs(b.difference ?? 1e9)
            if da != db { return da < db }
            return a.score > b.score
        }
        var kept: [Candidate] = []
        // Copies of one answer (the same title, artist and version as written, within the allowance) are shown once,
        // as before D39: to a DJ they are one answer. The fold below is for answers written differently.
        for c in sorted {
            if kept.contains(where: { k in
                norm(k.title) == norm(c.title) && norm(k.artist) == norm(c.artist) && norm(k.version) == norm(c.version)
                    && abs((k.seconds ?? -100) - (c.seconds ?? -100)) <= allowance
            }) { continue }
            kept.append(c)
            if kept.count == shownCandidates { break }
        }
        let anyNumber = known.kind == "isrc" || known.kind == "disc"
        // A title with no artist names many songs (letter AA, option B's risks): a list to choose from, not an answer.
        if known.artistWords.isEmpty && !anyNumber { return (kept, nil, false, nil, []) }
        func agrees(_ c: Candidate) -> Bool {
            let titleOK = c.titleAgrees == true || (anyNumber && NameReading.compareWords(known.title).isEmpty)
            let artistOK = c.artistAgrees == true || (anyNumber && known.artistWords.isEmpty)
            return titleOK && artistOK
        }
        let candidates = kept.indices.filter { i in
            let c = kept[i]
            return c.fit == "fits" && VersionMatch(rawValue: c.match ?? "")?.chooses == true && agrees(c)
                && !c.notes.contains("djMix") && !c.notes.contains("video")
        }
        // The same kind first: a plain song takes a plain candidate before one under the catalogue's word, and a radio
        // edit takes a radio edit before a plain one of the same length (AC 5.5); the second tier only when the first
        // is empty, so the two never count as several names.
        let songCore = known.version?.core ?? []
        let sameKind = candidates.filter { (kept[$0].version.map(NameReading.readVersion)?.core ?? []) == songCore }
        let acceptable = sameKind.isEmpty ? candidates : sameKind
        var rules: [String] = []
        if !acceptable.isEmpty {
            let groups = fold(acceptable.map { kept[$0] })
            if groups.count > 1 { return (kept, nil, true, nil, []) }
            let members = groups[0].map { acceptable[$0] }
            let chosen = members[0]
            rules.append("fits")
            if members.count > 1 { rules.append("fold") }
            if let m = kept[chosen].match, m != VersionMatch.same.rawValue { rules.append("kind:" + m) }
            if sameKind.isEmpty { rules.append("kind:secondTier") }
            if !songCore.isEmpty { rules.append("kind:" + songCore.map(\.rawValue).sorted().joined(separator: "+")) }
            kept[chosen].disagree = disagreement(members.map { kept[$0] })
            if known.artistFromFolder { rules.append("folder") }
            return (kept, chosen, false, nil, rules)
        }
        // Several names that fit and agree, none acceptable by version: as before, "several" only among fitting ones.
        // A DJ's or a pool's edit: the original, when it is the one name that agrees.
        if let v = known.version, !v.core.isEmpty, v.core.isSubset(of: VersionCompare.djEditKinds) {
            let originals = kept.indices.filter { kept[$0].match == VersionMatch.original.rawValue && agrees(kept[$0]) }
            if !originals.isEmpty {
                let groups = fold(originals.map { kept[$0] })
                if groups.count == 1 {
                    let members = groups[0].map { originals[$0] }
                    kept[members[0]].disagree = disagreement(members.map { kept[$0] })
                    var r = ["original"]
                    if members.count > 1 { r.append("fold") }
                    if known.artistFromFolder { r.append("folder") }
                    return (kept, members[0], false, "original", r)
                }
            }
        }
        let fitting = kept.filter { group($0) == 0 }
        let names = Set(fitting.map { norm($0.title) + "|" + norm($0.artist) })
        return (kept, nil, names.count > 1, nil, [])
    }

    /// The candidates in groups of one name each (AC 5.3, suggestion 4): the same title and the same first credited
    /// name, a featured guest added or not, written with any join; the same version kinds and names; the same clean
    /// or dirty; years at most one apart. Indexes into `cs`, in order.
    static func fold(_ cs: [Candidate]) -> [[Int]] {
        func key(_ c: Candidate) -> String {
            let v = c.version.map(NameReading.readVersion)
            let first = c.credited?.first ?? c.artist.flatMap(NameReading.firstArtist) ?? ""
            return [NameReading.compareWords(c.title).joined(separator: " "), NameReading.compareWords(first).joined(separator: " "),
                    (v?.core ?? []).map(\.rawValue).sorted().joined(separator: ","), (v?.names ?? []).sorted().joined(separator: ","),
                    c.lyrics ?? ""].joined(separator: "|")
        }
        var groups: [[Int]] = []
        for (i, c) in cs.enumerated() {
            let k = key(c)
            let y = c.year.flatMap { Int($0) }
            if let g = groups.firstIndex(where: { g in
                key(cs[g[0]]) == k && g.allSatisfy { j in
                    guard let y, let yj = cs[j].year.flatMap({ Int($0) }) else { return true }
                    return abs(y - yj) <= 1
                }
            }) {
                groups[g].append(i)
            } else {
                groups.append([i])
            }
        }
        return groups
    }

    /// The facts candidates folded into one name disagree on: their releases, their years, their labels (a label
    /// belongs to its release, so releases that differ leave the label unticked too).
    static func disagreement(_ members: [Candidate]) -> [String]? {
        guard members.count > 1 else { return nil }
        var out: [String] = []
        if Set(members.map { norm($0.release) }).count > 1 { out += [SongFacts.release, SongFacts.label] }
        if Set(members.compactMap(\.year)).count > 1 { out.append(SongFacts.year) }
        return out.isEmpty ? nil : out
    }

    /// The changes a candidate would make to a song, field by field (D39):
    ///
    /// - **Names**: a lookup never changes a name the song has (the DJ's, the file's tags' or its file name's). A
    ///   title is offered only for a song with no usable title, an artist only for a song with none. A version is
    ///   never ticked: for a song with none, the catalogue's word is offered unticked; for a song with one, a different
    ///   word is shown locked ("your version stays"). Clean or dirty is never taken.
    /// - **Facts**: release, year and label, ticked where the field is empty. For a song on a compilation, the copy's
    ///   release stays and the year and label go to `original_year` and `original_label` (when the song first came
    ///   out). For the original of a DJ's edit (`mode` `original`), only `original_year` and `original_label`, marked
    ///   the original's. A DJ's own entry is locked; a field folded candidates disagree on is left unticked.
    /// - Genre is never offered.
    static func changes(_ c: Candidate, song s: DeskNaming.Song, mode: String? = nil) -> [DeskNaming.Change] {
        var out: [DeskNaming.Change] = []
        let t = s.track
        let f = s.facts
        let known = Known(s, ask: Ask(kind: "words", isrc: nil, query: nil))
        func nameChange(_ field: String, _ after: String?) {
            guard let after, !after.isEmpty else { return }
            let fact = f.fact(field)
            let yours = fact.from.map(DeskNaming.djOrigins.contains) == true || fact.checked
            var ch = DeskNaming.Change(song: t.id, field: field, before: nil, after: after, tick: false, locked: yours, note: nil)
            if yours { ch.note = "yours" } else { ch.tick = !c.otherVersion }
            out.append(ch)
        }
        if !LocalNames.isUsableTitle(t.ident.title) { nameChange("title", c.title) }
        if !LocalNames.isUsableArtist(t.ident.artist) { nameChange("artist", c.artist) }
        let songVersion = t.ident.version.flatMap { $0.isEmpty ? nil : $0 } ?? known.version?.written
        if let v = c.version, !v.isEmpty, !(NameReading.readVersion(v).isPlain && NameReading.readVersion(v).lyrics == nil) {
            if let sv = songVersion, !sv.isEmpty {
                if norm(sv) != norm(v) {
                    out.append(DeskNaming.Change(song: t.id, field: "version", before: sv, after: v, tick: false, locked: true,
                                                 note: "yourVersion"))
                }
            } else {
                let yours = f.version.from.map(DeskNaming.djOrigins.contains) == true
                out.append(DeskNaming.Change(song: t.id, field: "version", before: nil, after: v, tick: false, locked: yours,
                                             note: yours ? "yours" : (c.otherVersion ? "otherVersion" : "catalogueWord")))
            }
        }
        // Where each fact goes, and why it is not ticked when it is not.
        var facts: [(String, String?, String?)] = []   // name, value, a note that unticks it
        if mode == "original" {
            facts = [(SongFacts.originalYear, c.year, nil), (SongFacts.originalLabel, c.label, nil)]
        } else if known.compilation {
            facts = [(SongFacts.release, c.release, "firstRelease"), (SongFacts.originalYear, c.year, nil),
                     (SongFacts.originalLabel, c.label, nil)]
        } else {
            facts = [(SongFacts.release, c.release, nil), (SongFacts.year, c.year, nil), (SongFacts.label, c.label, nil)]
        }
        let disagree = Set(c.disagree ?? [])
        for (name, value, untick) in facts {
            guard let value, !value.isEmpty else { continue }
            let have = t.ident.facts[name]
            if let h = have, norm(h.text) == norm(value) { continue }
            let yours = have?.from == SongFacts.Origin.user
            var ch = DeskNaming.Change(song: t.id, field: name, before: have?.text, after: value, tick: false, locked: yours, note: nil)
            let base = name == SongFacts.originalYear ? SongFacts.year : (name == SongFacts.originalLabel ? SongFacts.label : name)
            if yours { ch.note = "yours" }
            else if mode == "original" { ch.note = "original"; ch.tick = have == nil && !disagree.contains(base) }
            else if c.otherVersion { ch.note = c.notes.contains("original") ? "original" : "otherVersion" }
            else if let u = untick { ch.note = u }
            else if disagree.contains(base) { ch.note = "disagree" }
            else if have == nil { ch.tick = true }
            else { ch.note = "filled" }
            out.append(ch)
        }
        return out
    }

    // MARK: the review

    /// One song's lookup, as the review shows it.
    public struct SongResult: Codable, Equatable, Sendable {
        public var song: String
        /// The song as the table shows it now, and its length.
        public var title: String
        public var seconds: Double
        public var ask: Ask
        /// `found`, `nothing` (MusicBrainz doesn't know it), `failed` (`failure` says why), `notAsked` (the lookup was
        /// stopped first), `nothingToSend`.
        public var outcome: String
        public var failure: String?
        public var candidates: [Candidate]
        /// The candidate Desk would use, or nil (none fits, or several do: `several`).
        public var chosen: Int?
        public var several: Bool
        /// `original` when the chosen candidate is the original of the song's edit (D39): only its year and label.
        public var mode: String? = nil
        /// What let the choice through (`fits`, `fold`, `kind:catalogueWord`, `kind:sameTake`, `kind:named`,
        /// `original`, `folder`, `askedAgain`), for the trial and for tracing a wrong fill to a rule.
        public var rules: [String]? = nil
        /// How many more asks were made with free words (the second ask), 0 when none.
        public var askedAgain: Int? = nil

        public init(song: String, title: String, seconds: Double, ask: Ask, outcome: String, failure: String?,
                    candidates: [Candidate], chosen: Int?, several: Bool) {
            self.song = song; self.title = title; self.seconds = seconds; self.ask = ask; self.outcome = outcome
            self.failure = failure; self.candidates = candidates; self.chosen = chosen; self.several = several
        }
    }

    /// A finished (or stopped) lookup, kept until it is applied or another starts.
    public struct Review: Codable, Equatable, Sendable {
        public var scope: String
        public var source: String?
        public var songs: [SongResult]
        public var stopped: Bool
        /// A failure that ended the whole lookup (no connection, busy, not on this computer), as a code.
        public var failure: String?
        /// How many requests it made.
        public var requests: Int
        /// For a disc: whether MusicBrainz knew this disc by its id (`exact`), found discs like it (`fuzzy`), found
        /// it by its name (`byName`), or nothing.
        public var discMatch: String?
        public init(scope: String, source: String?, songs: [SongResult], stopped: Bool, failure: String?, requests: Int,
                    discMatch: String?) {
            self.scope = scope; self.source = source; self.songs = songs; self.stopped = stopped; self.failure = failure
            self.requests = requests; self.discMatch = discMatch
        }
        public var found: Int { songs.filter { $0.outcome == "found" }.count }
        public var asked: Int { songs.filter { $0.outcome == "found" || $0.outcome == "nothing" || $0.outcome == "failed" }.count }
    }

    /// The review's summary line: "9 of 14 found. 5 not found: edits and bootlegs often aren't." (letter AA, 3.9).
    public static func summaryLine(_ r: Review) -> String {
        if let f = r.failure { return DeskWords.fill(DeskWords.coded("lookupFailure", f), DeskWords.withComputer([:])) }
        let nothing = r.songs.filter { $0.outcome == "nothing" }.count
        if r.scope == "song", let s = r.songs.first {
            if s.outcome == "nothing" { return DeskWords.text("lookupNothingOne") }
            if s.outcome == "nothingToSend" { return DeskWords.text("lookupNothingToSendOne") }
        }
        var line = DeskWords.count("lookupFound", r.found, ["asked": "\(r.asked)"])
        if nothing > 0 { line += " " + DeskWords.count("lookupNotFound", nothing) }
        // The second ask doubled the wait for some songs: said, with how many (AC 5.3, suggestion 3).
        let again = r.songs.filter { ($0.askedAgain ?? 0) > 0 }.count
        if again > 0 { line += " " + DeskWords.count("lookupAskedAgain", again) }
        if r.stopped { line += " " + DeskWords.text("lookupStoppedLine") }
        return line
    }

    // MARK: applying

    /// What the DJ chose for one song: the candidate (its index in the song's list) and the fields ticked.
    public struct Choice: Codable, Equatable, Sendable {
        public var song: String
        public var candidate: Int
        public var fields: [String]
        public init(song: String, candidate: Int, fields: [String]) { self.song = song; self.candidate = candidate; self.fields = fields }
    }

    /// The choices Desk would make by itself: each song's chosen candidate with its ticked fields.
    public static func defaultChoices(_ r: Review) -> [Choice] {
        r.songs.compactMap { s in
            guard let i = s.chosen, i < s.candidates.count else { return nil }
            let fields = s.candidates[i].changes.filter { $0.tick && !$0.locked }.map(\.field)
            return fields.isEmpty ? nil : Choice(song: s.song, candidate: i, fields: fields)
        }
    }

    /// Applies the DJ's choices to the crate (the caller makes it one step of undo): each ticked field takes the
    /// candidate's value, marked `lookup:musicbrainz`. Names go into the DJ's corrections with that origin, so a
    /// re-read keeps them; a fact goes into the crate file's facts with that origin, and into the corrections too when
    /// it replaced something (so the file's tags do not put it back on a re-read). A field that is now the DJ's own
    /// (typed since the lookup) is never touched. Returns how many songs changed.
    @discardableResult
    public static func apply(_ r: Review, _ choices: [Choice], to crate: inout Crate, corrections: inout NameCorrections,
                             book: inout NameBook) -> Int {
        var changed = Set<String>()
        for choice in choices {
            guard let result = r.songs.first(where: { $0.song == choice.song }), choice.candidate >= 0,
                  choice.candidate < result.candidates.count,
                  let ti = crate.tracks.firstIndex(where: { $0.id == choice.song }) else { continue }
            let c = result.candidates[choice.candidate]
            var t = crate.tracks[ti]
            book.keep(t)
            let facts = DeskNaming.facts(t, book: book, corrections: corrections)
            for ch in c.changes where choice.fields.contains(ch.field) && !ch.locked {
                guard let value = ch.after else { continue }
                switch ch.field {
                case "title", "artist", "version":
                    // A lookup never changes a name the song has (D39): it fills only an empty one.
                    let now = facts.fact(ch.field)
                    if now.from.map(DeskNaming.djOrigins.contains) == true || now.checked { continue }
                    if ch.field == "title" { guard !LocalNames.isUsableTitle(t.ident.title) else { continue }; t.ident.title = value }
                    if ch.field == "artist" { guard !LocalNames.isUsableArtist(t.ident.artist) else { continue }; t.ident.artist = value }
                    if ch.field == "version" {
                        guard (t.ident.version ?? "").isEmpty, NameReading.readTitle(t.ident.title).version == nil else { continue }
                        t.ident.version = value
                    }
                    t.ident.source = "user"
                    corrections.give(t.id, field: ch.field, value: value, how: origin)
                default:
                    // Never genre, never clean or dirty (D39): those are the DJ's and the file's.
                    guard SongFacts.known.contains(ch.field), ch.field != SongFacts.genre, ch.field != SongFacts.lyrics else { continue }
                    let have = t.ident.facts[ch.field]
                    if have?.from == SongFacts.Origin.user { continue }
                    // The original's year and label for a DJ's edit say so in their origin.
                    let from = ch.note == "original" ? origin + SongFacts.Origin.originalSuffix : origin
                    var next = t.ident.facts
                    next[ch.field] = CrateTrack.Fact([value], from: from)
                    guard SongFacts.bytes(next.mapValues(\.values)) <= SongFacts.maxFactBytes else { continue }
                    t.ident.facts = next
                    if have != nil { corrections.giveFact(t.id, name: ch.field, values: [value], how: from) }
                }
            }
            if t != crate.tracks[ti] { crate.tracks[ti] = t; changed.insert(t.id) }
        }
        return changed.count
    }
}

/// "What Desk has sent" (letter AA, 3.8; the note on D3: the DJ can see, export and delete it): every request any
/// lookup made, when, to whom, what it carried and what came back; and whether the one-song sentence has been shown
/// once. Kept in Desk's storage (`lookups.json` at its top), written through DeckieFiles, clearable.
public struct LookupLog: Codable, Equatable, Sendable {
    public var explained: Bool
    public var sent: [SentRequest]
    public init(explained: Bool = false, sent: [SentRequest] = []) { self.explained = explained; self.sent = sent }

    public static let file = "lookups.json"
    /// The most requests kept; the oldest go first.
    public static let kept = 5000

    public static func url(_ home: DeskHome) -> URL { home.root.appendingPathComponent(file) }

    public static func load(_ home: DeskHome) -> LookupLog {
        guard let data = try? Data(contentsOf: url(home)) else { return LookupLog() }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return (try? d.decode(LookupLog.self, from: data)) ?? LookupLog()
    }

    public func save(_ home: DeskHome) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        e.dateEncodingStrategy = .iso8601
        try DeckieFiles.write(try e.encode(self), to: Self.url(home))
    }

    public mutating func add(_ r: SentRequest) {
        sent.append(r)
        if sent.count > Self.kept { sent.removeFirst(sent.count - Self.kept) }
    }

    /// Adds one request and saves at once (the lookup's thread calls this as each request is made).
    public static func record(_ r: SentRequest, home: DeskHome, lock: NSLock) {
        lock.lock(); defer { lock.unlock() }
        var log = load(home)
        log.add(r)
        try? log.save(home)
    }
}
