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

    /// What one song's lookup sends: its ISRC (`isrc`), its title, artist and release as written (`words`), the words
    /// of its file name when it has no title (`fileName`), or nothing (`none`: no title and a file name such as
    /// "Track 04", which only a disc's lookup can name).
    public struct Ask: Codable, Equatable, Sendable {
        public var kind: String
        public var isrc: String?
        public var query: RecordingQuery?
    }

    /// What a song would send. An ISRC beats words (letter AA, 6.4.5: one ISRC is one version); the words go too, as
    /// the second request when the ISRC finds nothing.
    public static func ask(_ s: DeskNaming.Song, isrc: String? = nil) -> Ask {
        let t = s.track
        let code = (isrc ?? t.ident.facts[SongFacts.isrc]?.values.first).map { $0.uppercased().filter { $0.isLetter || $0.isNumber } }
        let goodIsrc = code.flatMap { $0.count == 12 ? $0 : nil }
        var query: RecordingQuery? = nil
        if LocalNames.isUsableTitle(t.ident.title) {
            let version = t.ident.version.flatMap { $0.isEmpty ? nil : $0 }
            let title = version.map { "\(t.ident.title) (\($0))" } ?? t.ident.title
            query = RecordingQuery(title: title, artist: LocalNames.isUsableArtist(t.ident.artist) ? t.ident.artist : nil,
                                   release: t.ident.facts[SongFacts.release]?.values.first)
        } else {
            let stem = (t.file.name as NSString).deletingPathExtension.replacingOccurrences(of: "_", with: " ")
            if LocalNames.isUsableTitle(stem) {
                let r = DeskNaming.readLine(stem)
                if let a = r.artist, LocalNames.isUsableTitle(r.title) {
                    query = RecordingQuery(title: r.version.map { "\(r.title) (\($0))" } ?? r.title, artist: a)
                } else {
                    query = RecordingQuery(words: r.version.map { "\(r.title) \($0)" } ?? r.title)
                }
                if let g = goodIsrc { return Ask(kind: "isrc", isrc: g, query: query) }
                return Ask(kind: "fileName", isrc: nil, query: query)
            }
        }
        if let g = goodIsrc { return Ask(kind: "isrc", isrc: g, query: query) }
        if let query { return Ask(kind: "words", isrc: nil, query: query) }
        return Ask(kind: "none", isrc: nil, query: nil)
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
        /// `video`, `versionDiffers`, `lengthDiffers`, `original` (the song has a version, this has none: its year and
        /// label are the original's), `disc` (this disc, by its id), `fuzzy` (a disc like this one), `byName`.
        public var notes: [String]
        /// How well it agrees with what Desk already knows (title, artist, release, year, ISRC).
        public var agree: Int
        /// What it would change, field by field, with a tick each (DeskNaming.Change: `before`, `after`, `tick`
        /// for when this candidate is the one used, `locked`, `note`).
        public var changes: [DeskNaming.Change]
        var score: Int
    }

    /// What Desk knows of a song, as the ranking compares it.
    struct Known {
        var title: String?
        var version: String?
        var artist: String?
        var release: String?
        var year: String?
        var isrc: String?
        var seconds: Double
        var kind: String

        init(_ s: DeskNaming.Song, ask: Ask) {
            let t = s.track
            if LocalNames.isUsableTitle(t.ident.title) {
                let split = DeskNaming.splitVersion(t.ident.title)
                title = split.title
                version = t.ident.version.flatMap { $0.isEmpty ? nil : $0 } ?? split.version
            } else if let q = ask.query, let qt = q.title {
                let split = DeskNaming.splitVersion(qt)
                title = split.title; version = split.version
            }
            artist = LocalNames.isUsableArtist(t.ident.artist) ? t.ident.artist : ask.query?.artist
            release = t.ident.facts[SongFacts.release]?.values.first
            year = t.ident.facts[SongFacts.year]?.values.first
            isrc = ask.isrc
            seconds = t.file.durationS
            kind = ask.kind
        }
    }

    /// Words that mean no version at all ("Original Mix", "Album Version"; letter AA, 6.4.2).
    static let plain: Set<String> = ["original mix", "original", "album version", "original version", "single version",
                                     "remastered", "remaster"]

    /// Text compared loosely: lower case, accents and punctuation gone, "&" as "and", one space between words.
    static func norm(_ s: String?) -> String {
        guard let s else { return "" }
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .replacingOccurrences(of: "&", with: " and ")
        let kept = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        var out = String(kept).split(separator: " ").joined(separator: " ")
        if out.hasPrefix("the ") { out.removeFirst(4) }
        return out
    }

    /// A version's words that make it another recording (letter AA, 6.2): live, remix, edit, dub and the like.
    static func markers(_ s: String?) -> Set<String> {
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

    /// A candidate from a recording: its version from the brackets at the end of its title (MusicBrainz's own rule
    /// for writing one, letter AA, 6.2), else from its disambiguation when that names a version; the release Desk
    /// already knows when the recording is on it, else its earliest official release that is not a compilation; the
    /// year of its first release.
    static func candidate(_ r: MBRecording, known: Known) -> Candidate {
        let split = DeskNaming.splitVersion(r.title ?? "")
        let dis = r.disambiguation?.trimmingCharacters(in: .whitespaces)
        var notes: [String] = []
        let disNorm = norm(dis)
        let djMix = disNorm.contains("dj mix") || disNorm.contains("dj‐mix") || (disNorm.hasPrefix("part of") && disNorm.contains("mix"))
        if djMix { notes.append("djMix") }
        if r.video == true || disNorm.contains("music video") || disNorm == "video" { notes.append("video") }
        var version = split.version
        if version == nil, let d = dis, !d.isEmpty, !djMix, !markers(d).isEmpty { version = d }
        let release = pickRelease(r.releases ?? [], known: known.release)
        let year = (r.firstReleaseDate ?? release?.date).flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
        return Candidate(recording: r.id, title: split.title.isEmpty ? (r.title ?? "") : split.title, version: version,
                         artist: r.artistCredit?.line, release: release?.title, releaseId: release?.id, year: year,
                         label: release?.labels.first, seconds: r.length.map { Double($0) / 1000 }, fit: "unknown",
                         difference: nil, otherVersion: false, notes: notes, agree: 0, changes: [], score: r.score ?? 0)
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

    /// Rates a candidate against the song: how its length fits (within `allowance`), whether it is plainly another
    /// version, and how well it agrees with what Desk knows.
    static func rate(_ c: inout Candidate, known: Known, isrcs: [String] = []) {
        if let secs = c.seconds, known.seconds > 0 {
            c.difference = secs - known.seconds
            c.fit = abs(secs - known.seconds) <= allowance ? "fits" : "off"
        }
        let songMarks = markers(known.version)
        let candMarks = markers(c.version)
        if songMarks != candMarks {
            for m in candMarks.subtracting(songMarks).sorted() where ["live", "remix", "edit"].contains(m) && !c.notes.contains(m) { c.notes.append(m) }
        }
        let songVersion = norm(known.version), candVersion = norm(c.version)
        let versionsDiffer = !songVersion.isEmpty && !plain.contains(songVersion) && songVersion != candVersion
            && !(plain.contains(candVersion) && songVersion.isEmpty)
        if versionsDiffer {
            c.notes.append(candVersion.isEmpty || plain.contains(candVersion) ? "original" : "versionDiffers")
        } else if songVersion.isEmpty && !candMarks.isEmpty {
            c.notes.append("versionDiffers")
        }
        if c.fit == "off" { c.notes.append("lengthDiffers") }
        c.otherVersion = c.fit == "off" || songMarks != candMarks || versionsDiffer || c.notes.contains("djMix")
            || c.notes.contains("video") || (songVersion.isEmpty && !candMarks.isEmpty)
        var agree = 0
        let kt = norm(known.title), ct = norm(c.title)
        if !kt.isEmpty { agree += kt == ct ? 2 : (kt.contains(ct) || ct.contains(kt) ? 1 : 0) }
        let ka = norm(known.artist), ca = norm(c.artist)
        if !ka.isEmpty, !ca.isEmpty { agree += ka == ca ? 2 : (ka.contains(ca) || ca.contains(ka) ? 1 : 0) }
        if let r = known.release, !norm(r).isEmpty, norm(r) == norm(c.release) { agree += 1 }
        if let y = known.year, y.prefix(4) == (c.year ?? "") { agree += 1 }
        if let i = known.isrc, isrcs.contains(i) { agree += 3 }
        c.agree = agree
    }

    /// The candidates in order: those whose length fits and that are not another version first, then those with no
    /// length, then the rest; within each, the most agreement with what Desk knows, then the closest length, then
    /// MusicBrainz's own score. Copies of one answer (the same title, artist and version within `allowance`) are
    /// shown once. `chosen` is the one Desk would use, when exactly one answer fits and agrees; nil when none does or
    /// when several different ones do ("several").
    static func order(_ all: [Candidate], known: Known) -> (candidates: [Candidate], chosen: Int?, several: Bool) {
        func group(_ c: Candidate) -> Int { c.otherVersion ? 2 : (c.fit == "fits" ? 0 : (c.fit == "unknown" ? 1 : 2)) }
        let sorted = all.sorted { a, b in
            if group(a) != group(b) { return group(a) < group(b) }
            if a.agree != b.agree { return a.agree > b.agree }
            let da = abs(a.difference ?? 1e9), db = abs(b.difference ?? 1e9)
            if da != db { return da < db }
            return a.score > b.score
        }
        var kept: [Candidate] = []
        for c in sorted {
            if kept.contains(where: { k in
                norm(k.title) == norm(c.title) && norm(k.artist) == norm(c.artist) && norm(k.version) == norm(c.version)
                    && abs((k.seconds ?? -100) - (c.seconds ?? -100)) <= allowance
            }) { continue }
            kept.append(c)
            if kept.count == shownCandidates { break }
        }
        let fitting = kept.filter { group($0) == 0 }
        let names = Set(fitting.map { norm($0.title) + "|" + norm($0.artist) })
        let several = names.count > 1
        guard let first = kept.first, group(first) == 0, !several else { return (kept, nil, several) }
        // It must agree with the title Desk has, and with the artist when Desk has one.
        let kt = norm(known.title), ka = norm(known.artist)
        let titleOK = kt.isEmpty || norm(first.title) == kt || norm(first.title).contains(kt) || kt.contains(norm(first.title))
        let artistOK = ka.isEmpty || norm(first.artist).contains(ka) || ka.contains(norm(first.artist))
        return (kept, titleOK && artistOK ? 0 : nil, false)
    }

    /// The changes a candidate would make to a song, field by field (title, artist, version, release, year, label).
    /// Ticked by default only where the field is empty or holds Desk's own guess; a DJ's own entry is locked; a
    /// version the song has is never replaced or taken away; for a candidate that is another version, the release,
    /// year and label are not ticked (they would be another recording's).
    static func changes(_ c: Candidate, song s: DeskNaming.Song) -> [DeskNaming.Change] {
        var out: [DeskNaming.Change] = []
        let t = s.track
        let f = s.facts
        func nameChange(_ field: String, _ before: String?, _ after: String?, empty: Bool) {
            guard let after, !after.isEmpty else { return }
            let fact = f.fact(field)
            if let b = before, norm(b) == norm(after) { return }
            let yours = fact.from.map(DeskNaming.djOrigins.contains) == true || fact.checked
            var ch = DeskNaming.Change(song: t.id, field: field, before: before, after: after, tick: false, locked: yours, note: nil)
            if yours { ch.note = "yours" } else if empty || fact.guess { ch.tick = true } else { ch.note = "filled" }
            out.append(ch)
        }
        let titleUsable = LocalNames.isUsableTitle(t.ident.title)
        // The title: the candidate's without its version. A title whose brackets hold a version keeps them: the
        // change is offered only when the rest differs, and then with the song's own brackets kept.
        let own = DeskNaming.splitVersion(t.ident.title)
        if titleUsable, own.version != nil {
            if norm(own.title) != norm(c.title) { nameChange("title", t.ident.title, "\(c.title) (\(own.version!))", empty: false) }
        } else {
            nameChange("title", titleUsable ? t.ident.title : nil, c.title, empty: !titleUsable)
        }
        nameChange("artist", t.ident.artist, c.artist, empty: !LocalNames.isUsableArtist(t.ident.artist))
        // The version: only ever added to a song that has none.
        let songVersion = t.ident.version.flatMap { $0.isEmpty ? nil : $0 } ?? own.version
        if let v = c.version, !v.isEmpty, !plain.contains(norm(v)) {
            if let sv = songVersion {
                if norm(sv) != norm(v) {
                    out.append(DeskNaming.Change(song: t.id, field: "version", before: sv, after: v, tick: false, locked: true,
                                                 note: "yourVersion"))
                }
            } else {
                let fact = f.version
                let yours = fact.from.map(DeskNaming.djOrigins.contains) == true
                out.append(DeskNaming.Change(song: t.id, field: "version", before: nil, after: v, tick: !yours && !c.otherVersion,
                                             locked: yours, note: yours ? "yours" : (c.otherVersion ? "otherVersion" : nil)))
            }
        }
        for (name, value) in [(SongFacts.release, c.release), (SongFacts.year, c.year), (SongFacts.label, c.label)] {
            guard let value, !value.isEmpty else { continue }
            let have = t.ident.facts[name]
            if let h = have, norm(h.text) == norm(value) { continue }
            let yours = have?.from == SongFacts.Origin.user
            var ch = DeskNaming.Change(song: t.id, field: name, before: have?.text, after: value, tick: false, locked: yours, note: nil)
            if yours { ch.note = "yours" }
            else if c.otherVersion { ch.note = c.notes.contains("original") ? "original" : "otherVersion" }
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
        public var found: Int { songs.filter { $0.outcome == "found" }.count }
        public var asked: Int { songs.filter { $0.outcome == "found" || $0.outcome == "nothing" || $0.outcome == "failed" }.count }
    }

    /// The review's summary line: "9 of 14 found. 5 not found: edits and bootlegs often aren't." (letter AA, 3.9).
    public static func summaryLine(_ r: Review) -> String {
        if let f = r.failure { return DeskWords.coded("lookupFailure", f) }
        let nothing = r.songs.filter { $0.outcome == "nothing" }.count
        if r.scope == "song", let s = r.songs.first {
            if s.outcome == "nothing" { return DeskWords.text("lookupNothingOne") }
            if s.outcome == "nothingToSend" { return DeskWords.text("lookupNothingToSendOne") }
        }
        var line = DeskWords.count("lookupFound", r.found, ["asked": "\(r.asked)"])
        if nothing > 0 { line += " " + DeskWords.count("lookupNotFound", nothing) }
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
                    let now = facts.fact(ch.field)
                    if now.from.map(DeskNaming.djOrigins.contains) == true || now.checked { continue }
                    if ch.field == "title" { t.ident.title = value }
                    if ch.field == "artist" { t.ident.artist = value }
                    if ch.field == "version" {
                        guard (t.ident.version ?? "").isEmpty, DeskNaming.splitVersion(t.ident.title).version == nil else { continue }
                        t.ident.version = value
                    }
                    t.ident.source = "user"
                    corrections.give(t.id, field: ch.field, value: value, how: origin)
                default:
                    guard SongFacts.known.contains(ch.field) else { continue }
                    let have = t.ident.facts[ch.field]
                    if have?.from == SongFacts.Origin.user { continue }
                    var next = t.ident.facts
                    next[ch.field] = CrateTrack.Fact([value], from: origin)
                    guard SongFacts.bytes(next.mapValues(\.values)) <= SongFacts.maxFactBytes else { continue }
                    t.ident.facts = next
                    if have != nil { corrections.giveFact(t.id, name: ch.field, values: [value], how: origin) }
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
