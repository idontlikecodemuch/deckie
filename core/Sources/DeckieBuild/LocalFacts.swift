import Foundation
import DeckieCore
import DeckieCrate

/// Keys and names already on the computer (D30), put into a crate: the keys the DJ's own programs wrote (in the
/// files' tags and in the programs' libraries), and names for songs that arrived without one. Nothing leaves the
/// computer, and nothing outside the crate is written: every file is only read.
///
/// **Which key.** Under D16 and D17, and the owner's note on D30 and D16 (a key is preferred, shown when the reader is
/// sure). A record read by Apple's framework (engine family `apple-mu`) keeps its reading as its key; the DJ's keys
/// are added beside it as votes. Any other record (Deckie's own engine, on any computer) takes the DJ's key when
/// there is one, with Deckie's own reading kept beside it as the vote `deckie`; with no key from the DJ, it keeps
/// Deckie's own reading exactly as the engine wrote it (its block, its confidence, its `key_uncertain` flag). Whether
/// that reading is shown at all, song by song, is the "when sure" rule the key trial will give; it goes in
/// `decideKey`, where it is marked. When several of the DJ's programs have a key for the song, the rule is: **the program whose library was written most recently** (the program in use now), the libraries before
/// the file's own tags; then the file's key tag, then a key in its comment, then one in its title. The chosen key is
/// `key.source`; every key found is in `key.votes` under its origin, so the others stay visible; `key.confidence` is
/// the share of the keys found that agree with the chosen one (1 when there is one, or all agree), and the record is
/// flagged `key_uncertain` when fewer than half agree.
///
/// **Which name.** For a song whose title is not usable or that has no artist (`LocalNames`), each missing part is
/// taken from the first of these that has it, and `ident.source` says where from (two origins joined by "+" when the
/// title and the artist came from different places: "filename+folder"): the file's tags (`tag`); its file name read by
/// pattern (`filename`); its folder, as the artist (`folder`); a tracklist file beside it (`cue`, `m3u`,
/// `tracklist`); the DJ programs' libraries, in the key's order (the program's name); a named copy of the same
/// recording in the crate (`copy`). A song still without a usable title keeps its file name as its title. A name
/// the DJ fixed (`ident.source` `user`) is never touched, and a rekordbox import's names (`rekordbox-xml`) stand as
/// the DJ's choice.
public enum LocalFacts {
    /// One file of an entry: where it is now, its path below its source's top or the music folder, and its place.
    public struct FileRef: Sendable, Equatable {
        public var url: URL
        public var rel: String
        public var place: CrateTrack.Place
        public init(url: URL, rel: String, place: CrateTrack.Place) { self.url = url; self.rel = rel; self.place = place }
    }

    /// What was found, for the finished screen and the run's log.
    public struct Report: Codable, Equatable, Sendable {
        /// Songs whose key came from each origin (`rekordbox-xml`, `traktor`, `tag`, ...; `apple-mu` for Apple's).
        public var keysFrom: [String: Int] = [:]
        /// Songs with no key: none of the DJ's programs or tags had one, and Deckie's own reader did not give one.
        public var keysNotRead = 0
        /// Of those, the songs Deckie's reader read and was not sure of (D33).
        public var keysNotSure = 0
        /// Songs with no key and a home note: Deckie's reader found the note and left the mode open (D36). Not
        /// counted in `keysNotRead`.
        public var keysHomeNote = 0
        /// Songs whose programs and tags gave more than one key.
        public var keysDisagree = 0
        /// Songs named, in part or whole, by each way past the tags (`filename`, `folder`, `cue`, `copy`, ...).
        public var namesFrom: [String: Int] = [:]
        /// Songs that still need a name: no usable title, or no artist.
        public var needName = 0
        /// Songs with facts (D34) from each origin (`tag`, a DJ program, ...); nil in a report written before them.
        public var factsFrom: [String: Int]?
        public init() {}
        enum CodingKeys: String, CodingKey {
            case keysFrom = "keys_from", keysNotRead = "keys_not_read", keysDisagree = "keys_disagree"
            case namesFrom = "names_from", needName = "need_name", factsFrom = "facts_from"
            case keysNotSure = "keys_not_sure", keysHomeNote = "keys_home_note"
        }
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            keysFrom = try c.decodeIfPresent([String: Int].self, forKey: .keysFrom) ?? [:]
            keysNotRead = try c.decodeIfPresent(Int.self, forKey: .keysNotRead) ?? 0
            keysDisagree = try c.decodeIfPresent(Int.self, forKey: .keysDisagree) ?? 0
            namesFrom = try c.decodeIfPresent([String: Int].self, forKey: .namesFrom) ?? [:]
            needName = try c.decodeIfPresent(Int.self, forKey: .needName) ?? 0
            keysNotSure = try c.decodeIfPresent(Int.self, forKey: .keysNotSure) ?? 0
            keysHomeNote = try c.decodeIfPresent(Int.self, forKey: .keysHomeNote) ?? 0
            factsFrom = try c.decodeIfPresent([String: Int].self, forKey: .factsFrom)
        }
    }

    /// The vote under which Deckie's own reading is kept beside a DJ's key, and the name a report counts it under.
    public static let ownVote = "deckie"

    /// Deckie's own reading of a record's key: its key block when that is not a DJ's (as the builder writes a record).
    public static func ownReading(_ t: CrateTrack) -> CrateTrack.Key? {
        guard let k = t.key, !djOrigins.contains(k.source) else { return nil }
        return k
    }

    /// Deckie's own reading from the builder's records (`<records>/<id>.json`), for a record whose key block is now a
    /// DJ's; else `ownReading`.
    public static func ownReading(records: URL?) -> @Sendable (CrateTrack) -> CrateTrack.Key? {
        { t in
            if let records, let data = try? Data(contentsOf: records.appendingPathComponent("\(t.id).json")),
               let r = try? JSONDecoder().decode(WorkStore.Record.self, from: data) {
                return r.track.key
            }
            return ownReading(t)
        }
    }

    /// Deckie's own home note for a record (D36): its `key_home` block, or, for a record of engine 0.5.0, the home
    /// note of a three-answer key block at the "mode open" confidence.
    public static func ownHome(_ t: CrateTrack) -> CrateTrack.KeyHome? {
        if let h = t.keyHome { return h }
        if let k = t.key, k.source == threeAnswerSource, k.confidence >= modeOpenConfidence, k.confidence < 0.5,
           let tonic = Camelot.tonic(k.camelot) {
            return .init(source: threeAnswerSource, pitchClass: tonic.pitchClass)
        }
        return nil
    }

    /// Deckie's own home note from the builder's records, for a record that now carries a DJ's key; else `ownHome`.
    public static func ownHome(records: URL?) -> @Sendable (CrateTrack) -> CrateTrack.KeyHome? {
        { t in
            if let records, let data = try? Data(contentsOf: records.appendingPathComponent("\(t.id).json")),
               let r = try? JSONDecoder().decode(WorkStore.Record.self, from: data) {
                return ownHome(r.track)
            }
            return ownHome(t)
        }
    }

    /// The origins of a DJ's key that are the file's own tags, in the order they are taken.
    public static let tagOrigins = ["tag", "tag-comment", "tag-title"]
    /// Every origin a DJ's key can have.
    public static var djOrigins: Set<String> { Set(DJProgram.allCases.map(\.rawValue) + tagOrigins) }

    /// Whether a song needs a name: its title is not usable, or it has no artist.
    public static func needsName(_ t: CrateTrack) -> Bool {
        !LocalNames.isUsableTitle(t.ident.title) || !LocalNames.isUsableArtist(t.ident.artist)
    }

    struct Reading {
        var origin: String
        var camelot: String
        var written: Date?
        var order: Int
    }

    struct Named {
        var title: String
        var titleFrom: String
        var titleUsable: Bool
        var artist: String?
        var artistFrom: String?
        var version: String?
    }

    /// Gathers the keys and names for every entry of `crate` from its files (`files`, by entry id; a file not there now
    /// is matched in the libraries by its path but its tags are not read) and the DJ program libraries read.
    @discardableResult
    public static func apply(to crate: inout Crate, files: [String: [FileRef]], libraries: [DJLibrary],
                             own: (CrateTrack) -> CrateTrack.Key? = LocalFacts.ownReading,
                             ownHome: (CrateTrack) -> CrateTrack.KeyHome? = LocalFacts.ownHome,
                             fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) -> Report {
        var report = Report()
        // One library per program: the most recently written.
        var newest: [DJProgram: DJLibrary] = [:]
        for lib in libraries {
            if let have = newest[lib.program], (have.written ?? .distantPast) >= (lib.written ?? .distantPast) { continue }
            newest[lib.program] = lib
        }
        let libs = newest.values.sorted {
            let a = $0.written ?? .distantPast, b = $1.written ?? .distantPast
            return a != b ? a > b : $0.program.tieOrder < $1.program.tieOrder
        }
        let matcher = DJLibraryMatcher(libs)
        var tracklists: [String: LocalNames.Tracklists] = [:]
        var named: [String: Named] = [:]

        // Each file's tags, read once, and what every file in a folder says of itself, so a folder is read with all
        // its files (D39: the artist from a folder only when it is plainly one artist's album).
        var tagsById: [String: FileTags] = [:]
        var presentById: [String: FileRef] = [:]
        var siblings: [String: [LocalNames.Sibling]] = [:]
        for t in crate.tracks {
            let refs = files[t.id] ?? []
            guard let present = refs.first(where: { fileExists($0.url) }) else { continue }
            presentById[t.id] = present
            let tags = FileTags.read(present.url)
            tagsById[t.id] = tags
            let folder = present.url.deletingLastPathComponent().path
            let facts = FileFacts.read(present.url).facts
            siblings[folder, default: []].append(LocalNames.Sibling(
                stem: (PathKey.lastName(present.rel) as NSString).deletingPathExtension, tagArtist: tags.artist,
                compilationMark: facts[SongFacts.compilation]?.first == "1", releaseArtist: facts[SongFacts.releaseArtist]?.first))
        }

        for i in crate.tracks.indices {
            var t = crate.tracks[i]
            let refs = files[t.id] ?? []
            let present = presentById[t.id]
            let tags = tagsById[t.id]
            let matches = matcher.match(paths: refs.map { PathKey.slashes($0.url.path) }, rels: refs.map(\.rel), size: t.file.bytes)

            // Keys: the libraries (newest first; rekordbox's import with them, dated when it was taken), then the tags.
            var readings: [Reading] = []
            for (li, e) in matches { if let c = e.camelot { readings.append(.init(origin: libs[li].program.rawValue, camelot: c, written: libs[li].written, order: libs[li].program.tieOrder)) } }
            if let rb = t.imported?.rekordbox, let tone = rb.tonality, let c = KeyNotation.camelot(tone),
               !readings.contains(where: { $0.origin == DJProgram.rekordbox.rawValue }) {
                readings.append(.init(origin: DJProgram.rekordbox.rawValue, camelot: c, written: parseUTC(rb.importedAt),
                                      order: DJProgram.rekordbox.tieOrder))
            }
            readings.sort { a, b in
                let x = a.written ?? .distantPast, y = b.written ?? .distantPast
                return x != y ? x > y : a.order < b.order
            }
            var titleKey: (camelot: String, title: String)? = nil
            if let tags {
                if let k = tags.key.flatMap(KeyNotation.camelot) { readings.append(.init(origin: "tag", camelot: k, written: nil, order: 100)) }
                if let k = tags.comment.flatMap(LocalNames.key(inComment:)) {
                    readings.append(.init(origin: "tag-comment", camelot: k, written: nil, order: 101))
                }
                titleKey = tags.title.flatMap(LocalNames.key(inTitle:))
                if let k = titleKey { readings.append(.init(origin: "tag-title", camelot: k.camelot, written: nil, order: 102)) }
            } else if let old = t.key {
                // The file is not here to read: the keys its tags gave last time stay.
                for o in tagOrigins { if let c = old.votes[o] { readings.append(.init(origin: o, camelot: c, written: nil, order: 100 + tagOrigins.firstIndex(of: o)!)) } }
            }
            decideKey(&t, readings, own: own(t), ownHome: ownHome(t), &report)

            // Names, part one: everything but a copy's.
            if t.ident.source != "user" && t.ident.source != DJProgram.rekordbox.rawValue {
                let folderKey = (present ?? refs.first).map { $0.url.deletingLastPathComponent().path }
                if let n = name(t, ref: present ?? refs.first, tags: tags, titleKey: titleKey, matches: matches.map(\.entry),
                                libs: matches.map { libs[$0.library].program.rawValue }, tracklists: &tracklists,
                                siblings: folderKey.flatMap { siblings[$0] } ?? []) {
                    named[t.id] = n
                }
            }
            crate.tracks[i] = t
        }

        // Names, part two: a named copy of the same recording lends what is missing.
        var donors: [String: Named] = [:]
        for t in crate.tracks {
            let n = named[t.id] ?? Named(title: t.ident.title, titleFrom: t.ident.source ?? "tag",
                                         titleUsable: LocalNames.isUsableTitle(t.ident.title), artist: t.ident.artist,
                                         artistFrom: t.ident.source, version: t.ident.version)
            guard n.titleUsable, LocalNames.isUsableArtist(n.artist) else { continue }
            if donors[t.recordingKey] == nil { donors[t.recordingKey] = n }
        }
        for i in crate.tracks.indices {
            guard var n = named[crate.tracks[i].id] else {
                if needsName(crate.tracks[i]) { report.needName += 1 }
                continue
            }
            if let d = donors[crate.tracks[i].recordingKey] {
                if !n.titleUsable { n.title = d.title; n.titleFrom = "copy"; n.titleUsable = true; n.version = d.version }
                if !LocalNames.isUsableArtist(n.artist) { n.artist = d.artist; n.artistFrom = "copy" }
            }
            var id = crate.tracks[i].ident
            id.title = n.title
            id.artist = n.artist
            id.version = n.version
            let from = n.artist == nil || n.artistFrom == n.titleFrom ? n.titleFrom : "\(n.titleFrom)+\(n.artistFrom!)"
            id.source = from
            crate.tracks[i].ident = id
            for step in Set([n.titleFrom] + (n.artist == nil ? [] : [n.artistFrom!])) where step != "tag" {
                report.namesFrom[step, default: 0] += 1
            }
            if needsName(crate.tracks[i]) { report.needName += 1 }
        }
        return report
    }

    /// The "when sure" rule alone, for a builder that gathers nothing from the computer (`deckie-make`): each record's
    /// key becomes what `decideKey` shows of Deckie's own reading with no key from the DJ: a key the reader was sure
    /// of, the home note alone, or neither. Names and DJ's keys are not touched. Returns the counts.
    @discardableResult
    public static func ownKeysOnly(_ crate: inout Crate) -> Report {
        var report = Report()
        for i in crate.tracks.indices {
            var t = crate.tracks[i]
            if let k = t.key, djOrigins.contains(k.source) { continue }
            decideKey(&t, [], own: ownReading(t), ownHome: ownHome(t), &report)
            crate.tracks[i] = t
        }
        return report
    }

    /// The key block from the readings, by the rule above. `own` is Deckie's own reading of the song, if any.
    static func decideKey(_ t: inout CrateTrack, _ readings: [Reading], own: CrateTrack.Key?,
                          ownHome: CrateTrack.KeyHome? = nil, _ report: inout Report) {
        var votes: [String: String] = [:]
        for r in readings where votes[r.origin] == nil { votes[r.origin] = r.camelot }
        if Set(readings.map(\.camelot)).count > 1 { report.keysDisagree += 1 }
        let djOrigins = Self.djOrigins
        if t.engine.family == CrateFormat.EngineFamily.appleMU, var k = t.key {
            // Apple's reading stays the key; the DJ's keys sit beside it.
            k.votes = k.votes.filter { !djOrigins.contains($0.key) }.merging(votes) { _, new in new }
            t.key = k
            t.keyHome = nil
            report.keysFrom[CrateFormat.EngineFamily.appleMU, default: 0] += 1
            return
        }

        // The "when sure" rule (D33; research X2). Deckie's three-answer reader (`ThreeAnswerKey`, `key.source`
        // `three-answer`) gives a key (a block at confidence 1.0), the home note alone (a `key_home` block and no key
        // block, D36; engine 0.5.0 wrote a key block at 0.45 instead, which `ownHome` reads), or is not sure (a block
        // at 0.2, its best guess, which is never shown). Only a key at 0.5 or more is the record's key. With no key,
        // the home note is written as `key_home`; a song the reader was not sure of has neither. A reading from an
        // engine before 0.5.0 (any other source) is shown as it was.
        var shown: CrateTrack.Key? = own
        var notSure = false
        if let o = own, ownKeySources.contains(o.source), o.confidence < 0.5 {
            shown = nil
            notSure = ownHome == nil
        }

        guard let first = readings.first else {
            // No key from the DJ: Deckie's own reading, exactly as the engine wrote it, or none.
            if let shown {
                if t.key != shown {
                    t.key = shown
                    t.flags.removeAll { $0 == "key_uncertain" }
                    if shown.confidence < 0.5 { t.flags.append("key_uncertain") }  // the engine's rule (Flags)
                }
                report.keysFrom[ownVote, default: 0] += 1
                t.keyHome = nil
            } else {
                t.key = nil
                t.flags.removeAll { $0 == "key_uncertain" }
                t.keyHome = ownHome
                if ownHome != nil {
                    report.keysHomeNote += 1
                } else {
                    report.keysNotRead += 1
                    if notSure { report.keysNotSure += 1 }
                }
            }
            return
        }
        t.keyHome = nil
        // The DJ's key wins; Deckie's own reading stays beside it as a vote.
        t.flags.removeAll { $0 == "key_uncertain" }
        if let shown { votes[ownVote] = shown.camelot }
        let agree = readings.filter { $0.camelot == first.camelot }.count
        let confidence = (Double(agree) / Double(readings.count) * 1000).rounded() / 1000
        let spelled = Camelot.tonic(first.camelot)
        t.key = CrateTrack.Key(source: first.origin, confidence: confidence, camelot: first.camelot,
                               key: spelled.map { noteNames[$0.pitchClass] }, scale: spelled.map { $0.major ? "major" : "minor" },
                               votes: votes, changes: nil)
        if confidence < 0.5 { t.flags.append("key_uncertain"); t.flags.sort() }
        report.keysFrom[first.origin, default: 0] += 1
    }

    static let noteNames = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

    /// The three-answer reader's `key.source`, and the confidence it gives "home note, mode open" (DeckieEngine's
    /// `Analysis.keySource` and `KeyConfidence.modeOpen`, which this module does not import).
    public static let threeAnswerSource = "three-answer"
    /// The sources of a key Deckie read itself and shows only when sure (confidence at least one half): the
    /// three-answer reader's and the learned reader's (`Analysis.learnedKeySource`, engine 0.7.0).
    public static let learnedKeySource = "learned-key"
    public static let ownKeySources: Set<String> = [threeAnswerSource, learnedKeySource]
    public static let modeOpenConfidence = 0.45

    /// The ladder for one song, or nil when its tags name it fully (nothing to change but a key taken off its title).
    static func name(_ t: CrateTrack, ref: FileRef?, tags: FileTags?, titleKey: (camelot: String, title: String)?,
                     matches: [DJLibraryEntry], libs: [String], tracklists: inout [String: LocalNames.Tracklists],
                     siblings: [LocalNames.Sibling] = []) -> Named? {
        var title: (String, String)? = nil      // value, origin
        var artist: (String, String)? = nil
        var version: String? = nil
        let tagTitle = titleKey?.title ?? tags?.title
        if LocalNames.isUsableTitle(tagTitle) { title = (tagTitle!, "tag") }
        if LocalNames.isUsableArtist(tags?.artist) { artist = (tags!.artist!, "tag") }
        if tags == nil {
            // The file is not here: what the entry has stands, unless it is not usable.
            if LocalNames.isUsableTitle(t.ident.title) { title = (t.ident.title, t.ident.source ?? "tag") }
            if LocalNames.isUsableArtist(t.ident.artist) { artist = (t.ident.artist!, t.ident.source ?? "tag") }
        }
        let fileName = ref.map { PathKey.lastName($0.rel) } ?? t.file.name
        let stem = (fileName as NSString).deletingPathExtension
        let number = ref?.place.track ?? tags?.trackNumber
        // The file name read the way a DJ means it (D39): the title part kept as written there, a version after a
        // second dash kept as the song's version, the artist as credited.
        let read = NameReading.readFileName(stem, number: number)
        let fromName = (title: read.titleWritten, artist: read.artist.flatMap { LocalNames.isUsableArtist($0) ? $0 : nil })
        func done() -> Bool { title != nil && artist != nil }

        if !done() {
            if title == nil, LocalNames.isUsableTitle(fromName.title) {
                title = (fromName.title, "filename")
                version = read.dashedVersion
            }
            if artist == nil, let a = fromName.artist { artist = (a, "filename") }
        }
        // The artist from the folder only when the folder is plainly one artist's album (AC 3.1).
        if artist == nil, let ref {
            let folders = CratePath.folder(of: ref.rel).split(separator: "/").map(String.init)
            let f = LocalNames.readFolder(folders, siblings: siblings.isEmpty ? [LocalNames.Sibling(stem: stem)] : siblings)
            if f.kind == .artistAlbum, let a = f.artist { artist = (a, "folder") }
        }
        if !done(), let ref {
            let folderURL = ref.url.deletingLastPathComponent()
            let key = folderURL.path
            if tracklists[key] == nil { tracklists[key] = LocalNames.Tracklists.read(folder: folderURL) }
            let leading = Int(stem.prefix { $0.isASCII && $0.isNumber }.prefix(3))
            if let l = tracklists[key]!.name(fileName: fileName, number: leading ?? ref.place.track) {
                if title == nil, LocalNames.isUsableTitle(l.title) { title = (l.title!, l.origin) }
                if artist == nil, LocalNames.isUsableArtist(l.artist) { artist = (l.artist!, l.origin) }
            }
        }
        if !done() {
            for (e, origin) in zip(matches, libs) {
                if title == nil, LocalNames.isUsableTitle(e.title) { title = (e.title!, origin); version = e.version }
                if artist == nil, LocalNames.isUsableArtist(e.artist) { artist = (e.artist!, origin) }
                if done() { break }
            }
        }
        let usable = title != nil
        let finalTitle = title ?? (tags == nil ? (t.ident.title, t.ident.source ?? "filename") : (fromName.title.isEmpty ? stem : fromName.title, "filename"))
        let n = Named(title: finalTitle.0, titleFrom: finalTitle.1, titleUsable: usable, artist: artist?.0,
                      artistFrom: artist?.1, version: version)
        // A song its tags name fully, unchanged: nothing to write.
        if n.titleFrom == "tag" && n.artistFrom == "tag" && n.title == t.ident.title && n.artist == t.ident.artist
            && t.ident.source == "tag" && n.version == t.ident.version {
            return nil
        }
        return n
    }

    /// The names Desk gives a song from its file name and its folder alone (no tags, no tracklist, no library): the
    /// title part kept as written, a version after a second dash, the artist from the name, else from the folder when
    /// it is plainly one artist's album. `ident.source` as `apply` writes it. For the lookup's trial with tags hidden.
    public static func nameFromFile(rel: String, number: Int?, siblings: [LocalNames.Sibling])
        -> (title: String, artist: String?, version: String?, source: String) {
        let stem = (PathKey.lastName(rel) as NSString).deletingPathExtension
        let read = NameReading.readFileName(stem, number: number)
        var artist = read.artist.flatMap { LocalNames.isUsableArtist($0) ? $0 : nil }
        var artistFrom = "filename"
        if artist == nil {
            let folders = CratePath.folder(of: rel).split(separator: "/").map(String.init)
            let f = LocalNames.readFolder(folders, siblings: siblings.isEmpty ? [LocalNames.Sibling(stem: stem)] : siblings)
            if f.kind == .artistAlbum, let a = f.artist { artist = a; artistFrom = "folder" }
        }
        let title = LocalNames.isUsableTitle(read.titleWritten) ? read.titleWritten : stem
        return (title, artist, read.dashedVersion, artist == nil || artistFrom == "filename" ? "filename" : "filename+folder")
    }

    static func parseUTC(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}

/// What gathering keys and names found, with the libraries it read: shown on a desk's finished screen, kept in the
/// run's line, and printed by `deckie-build`.
public struct LocalFactsSummary: Codable, Equatable, Sendable {
    public var report: LocalFacts.Report
    /// Each library read: the program, the file, its songs.
    public var libraries: [Library]
    /// Libraries that could not be read, each in a sentence.
    public var failed: [String]
    /// rekordbox's own library is on this computer (it is encrypted and not read): an XML export would bring its keys.
    public var rekordboxLocked: Bool
    /// A folder read holds a rekordbox USB export, which is not read in this version.
    public var rekordboxExport: Bool

    public struct Library: Codable, Equatable, Sendable {
        public var program: DJProgram
        public var path: String
        public var songs: Int
    }
    enum CodingKeys: String, CodingKey {
        case report, libraries, failed, rekordboxLocked = "rekordbox_locked", rekordboxExport = "rekordbox_export"
    }

    /// The summary as lines for a terminal.
    public var text: String {
        let r = report
        var s = "keys from: " + (r.keysFrom.isEmpty ? "none" : r.keysFrom.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            + "; no key: \(r.keysNotRead) (Deckie not sure: \(r.keysNotSure)); home note only: \(r.keysHomeNote); programs disagree: \(r.keysDisagree)\n"
        s += "names from: " + (r.namesFrom.isEmpty ? "tags only" : r.namesFrom.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
            + "; still need a name: \(r.needName)\n"
        if let f = r.factsFrom {
            s += "songs with facts from: " + (f.isEmpty ? "none" : f.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")) + "\n"
        }
        for lib in libraries { s += "  read \(lib.program.rawValue): \(lib.path) (\(lib.songs) songs)\n" }
        for f in failed { s += "  could not read \(f)\n" }
        if rekordboxLocked { s += "  rekordbox's own library is on this computer (encrypted, not read): export the collection as XML\n" }
        if rekordboxExport { s += "  a rekordbox USB export is here (not read)\n" }
        return s
    }
}

extension LocalFacts {
    /// Every DJ library to read: in the DJ's home folder (none when nil), at the top of each folder or drive read,
    /// and the ones chosen by hand; each file once. Also whether rekordbox's own library is in the home folder, and
    /// whether a rekordbox USB export is on a folder read.
    public static func find(djHome: URL?, tops: [URL], chosen: [DJLibraryLocations.Found] = [])
        -> (found: [DJLibraryLocations.Found], rekordboxLocked: Bool, rekordboxExport: Bool) {
        var found: [DJLibraryLocations.Found] = []
        if let djHome { found += DJLibraryLocations.inHome(djHome) }
        for top in tops { found += DJLibraryLocations.onDrive(top) }
        found += chosen
        var seen = Set<String>()
        found = found.filter { seen.insert($0.url.standardizedFileURL.path).inserted }
        let locked = djHome.map { DJLibraryLocations.rekordboxDatabase(inHome: $0) } ?? false
        let export = tops.contains { DJLibraryLocations.rekordboxExport(onDrive: $0) }
        return (found, locked, export)
    }

    /// The whole step, as a desk's run and `deckie-build` do it: finds and reads the libraries (each from a copy),
    /// gathers into `crate`, and says what it found. `records` is the builder's records folder, where Deckie's own
    /// reading of each song is kept.
    public static func gather(_ crate: inout Crate, files: [String: [FileRef]], djHome: URL?, tops: [URL],
                              chosen: [DJLibraryLocations.Found] = [], records: URL?) -> LocalFactsSummary {
        let (found, locked, export) = find(djHome: djHome, tops: tops, chosen: chosen)
        var libs: [DJLibrary] = []
        var failed: [String] = []
        for f in found {
            do { libs.append(try DJLibrary.read(f.program, at: f.url)) }
            catch { failed.append("\(f.program.rawValue): \(error)") }
        }
        var report = apply(to: &crate, files: files, libraries: libs, own: ownReading(records: records),
                           ownHome: ownHome(records: records))
        report.factsFrom = gatherFacts(&crate, files: files, libraries: libs)
        return LocalFactsSummary(report: report,
                                 libraries: libs.map { .init(program: $0.program, path: $0.file, songs: $0.entries.count) },
                                 failed: failed,
                                 rekordboxLocked: locked && !crate.tracks.contains { $0.imported?.rekordbox != nil }
                                     && !libs.contains { $0.program == .rekordbox },
                                 rekordboxExport: export)
    }

    /// Each entry's files from a build of the folder `top` (its `placesRead`), for `gather`.
    public static func files(read: [String: [ReadPlace]], top: URL) -> [String: [FileRef]] {
        read.mapValues { list in list.map { FileRef(url: top.appendingPathComponent($0.rel), rel: $0.rel, place: $0.place) } }
    }
}
