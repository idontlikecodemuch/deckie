import Foundation

// The words DJs and catalogues write after a song's title, as data (D39; research AC, section 5.5): the kinds of
// version, the words and spellings that map to each, whether each is other audio than the plain one, which say clean
// or dirty, the bracket contents that are not a version, and the words that join the names in a credit. One place,
// read by everything that reads, compares or shows a version: `NameReading` (a title, a file name or a tag, read into
// its parts), Desk's lookup (a song against a catalogue's candidate), the trial tool and the booth.
//
// How to extend it: add a phrase to a kind's `words` (lower case, as `VersionWords.fold` leaves text: no full stops,
// hyphens and underscores as spaces, `12"` as `12 inch`), or a whole kind to `kinds`. Matching ignores case, accents,
// full stops, hyphens and a plural "s"; "mix", "version", "edit" and "cut" after a kind's words add nothing
// ("Extended Mix" is "Extended"). A phrase marked uncertain is one letter AC found in use but could not source, or
// whose kind is a guess: it is read like any other, and `uncertain` lets a report count it apart.

/// The kind of a version (research AC, 5.5). The raw value is the vocabulary's own name for it.
public enum VersionKind: String, CaseIterable, Codable, Sendable {
    case plain, remaster, radio, extended, club, remix, dub, vip, bootleg, mashup
    case djEdit = "dj-edit"
    case instrumental, acapella, tool, intro, outro, short
    case acapIn = "acap-in", acapOut = "acap-out"
    case transition, redrum, party, live
    case otherTake = "other-take"
    case mixed, altered
}

/// The families of letter AC's table 1.2, as 5.5 groups the kinds.
public enum VersionFamily: String, Codable, Sendable {
    case plain, length, remake, edit, parts, pool, performance, mixedRelease = "mixed-release", sound
}

/// Clean or dirty: whether the swearing is removed or left in (D39). "Not said" is the absence of a value, never
/// shown as clean.
public enum Lyrics: String, CaseIterable, Codable, Sendable {
    case clean, dirty
}

/// One kind of version and everything Deckie knows about it.
public struct VersionKindInfo: Sendable {
    public let kind: VersionKind
    public let family: VersionFamily
    /// The phrases that name it on their own.
    public let words: [String]
    /// Phrases that name it only when a name stands beside them ("Marlo Remix" needs no name; "Marlo Edit" is a DJ's
    /// edit, "Edit" alone a radio edit; "Marlo Mix" is a remix, "Mix" alone nothing).
    public let withName: [String]
    /// Other audio than the plain one. Only the plain one and a remaster are the same recording (D24; AC 1.4).
    public let differentAudio: Bool
    /// How far it is from the original, which is what a catalogue's entry for the original can give (AC 1.4).
    public let distance: Distance
    /// What it says about the lyrics: `safe` (no words, so it fits a clean filter), `cleanHint` (a hint, never an
    /// answer: "Radio" is clean in hip-hop and only short in dance music), or nothing.
    public let lyricsHint: LyricsHint?
    /// Phrases of this kind that letter AC marks as uncertain (found in use, not sourced; or grouped by guess).
    public let uncertain: Set<String>

    public enum Distance: String, Sendable { case sameRecording, sameTakeSameLength, sameTakeOtherLength, otherProduction, otherPerformance }
    public enum LyricsHint: String, Sendable { case safe, cleanHint }

    public init(_ kind: VersionKind, _ family: VersionFamily, words: [String], withName: [String] = [], differentAudio: Bool = true,
                distance: Distance, lyricsHint: LyricsHint? = nil, uncertain: Set<String> = []) {
        self.kind = kind; self.family = family; self.words = words; self.withName = withName
        self.differentAudio = differentAudio; self.distance = distance; self.lyricsHint = lyricsHint; self.uncertain = uncertain
    }
}

/// One phrase that says clean or dirty, and whether it is read only when it stands alone in its bracket (a word such
/// as "street" or "raw" is a remixer's name as often as it is a lyrics word).
public struct LyricsWord: Sendable {
    public let phrase: String
    public let lyrics: Lyrics
    public let aloneOnly: Bool
    public let uncertain: Bool
    public init(_ phrase: String, _ lyrics: Lyrics, aloneOnly: Bool = false, uncertain: Bool = false) {
        self.phrase = phrase; self.lyrics = lyrics; self.aloneOnly = aloneOnly; self.uncertain = uncertain
    }
}

public enum VersionWords {
    // MARK: the kinds (research AC, 5.5)

    public static let kinds: [VersionKindInfo] = [
        .init(.plain, .plain, words: ["original mix", "original", "original version", "album version", "album mix", "lp version",
                                      "lp", "main", "main mix", "main version", "single version", "standard", "full version",
                                      "full length", "stereo"],
              differentAudio: false, distance: .sameRecording,
              // "Main" and "LP" lean dirty on hip-hop promos [use]; not sourced, so they are left as not said.
              uncertain: ["main", "lp", "main mix", "main version"]),
        .init(.remaster, .plain, words: ["remaster", "remastered", "digital remaster", "digitally remastered", "remastered version"],
              differentAudio: false, distance: .sameRecording),
        .init(.radio, .length, words: ["radio edit", "radio mix", "radio version", "radio", "edit", "single edit", "7 inch edit",
                                       "7 inch version", "7 inch", "7 inch mix", "video edit", "video version", "short version", "short mix"],
              distance: .sameTakeOtherLength, lyricsHint: .cleanHint,
              // "Edit" alone is a label's radio edit or a DJ's edit; with a name it is a DJ's (`djEdit`). Length corrects it.
              uncertain: ["edit"]),
        .init(.extended, .length, words: ["extended mix", "extended", "extended version", "ext", "xtd", "extd", "12 inch mix",
                                          "12 inch version", "12 inch", "long version", "full length version", "maxi version",
                                          "extended edit"],
              distance: .sameTakeOtherLength),
        .init(.club, .length, words: ["club mix", "club version", "club edit", "club"],
              distance: .sameTakeOtherLength,
              // Kept apart from `extended`: a club mix can be another mix altogether (AC 5.5, uncertain).
              uncertain: ["club"]),
        .init(.remix, .remake, words: ["remix", "rmx", "rmix", "remixed", "rework", "re work", "refix", "re fix", "flip", "remake",
                                       "reboot", "re rub", "rerub", "remode", "re mix"],
              withName: ["mix", "version", "dub mix"], distance: .otherProduction,
              // "Mix" with a name is read as a remix; some are the artist's own mixes named for a place or a mood.
              uncertain: ["mix", "version", "flip", "reboot"]),
        .init(.dub, .remake, words: ["dub", "dub mix", "dub version", "dubstrumental", "vocal dub"],
              distance: .otherProduction, lyricsHint: .safe),
        .init(.vip, .remake, words: ["vip", "v i p", "vip mix", "vip edit"], distance: .otherProduction),
        .init(.bootleg, .remake, words: ["bootleg", "boot", "booty", "unofficial remix", "white label"],
              distance: .otherProduction, uncertain: ["booty"]),
        .init(.mashup, .remake, words: ["mashup", "mash up", "mash", "blend"], distance: .otherProduction),
        .init(.djEdit, .edit, words: ["re edit", "reedit", "dj edit", "rework edit"], withName: ["edit", "rework"],
              distance: .sameTakeOtherLength),
        .init(.instrumental, .parts, words: ["instrumental", "inst", "instr", "instru", "instrumental mix", "tv track", "tv mix",
                                             "karaoke version", "karaoke"],
              distance: .otherProduction, lyricsHint: .safe),
        .init(.acapella, .parts, words: ["acapella", "a cappella", "acappella", "accapella", "a capella", "acap", "acca", "pella",
                                         "vocal only", "vox", "acapella version"],
              distance: .otherProduction),
        .init(.tool, .parts, words: ["bonus beats", "bonus beat", "beats", "drum tool", "dj tool", "tool", "loop", "sample", "scratch",
                                     "drums", "drum loop"],
              distance: .otherProduction, lyricsHint: .safe, uncertain: ["sample", "loop", "drums"]),
        .init(.intro, .pool, words: ["intro", "intro edit", "dj intro", "intro version", "8 bar intro", "16 bar intro",
                                     "32 bar intro", "8 bar in", "4 bar in", "16 bar in", "clap intro", "intro mix"],
              distance: .sameTakeOtherLength),
        .init(.outro, .pool, words: ["outro", "outro edit", "intro outro", "in out", "intro out"], distance: .sameTakeOtherLength),
        .init(.short, .pool, words: ["short edit", "short", "se", "quick edit", "quick hit", "quick hitter", "quick hitz", "qh",
                                     "cutdown", "cut down", "super short", "super short edit", "hook only", "snip", "snippet",
                                     "mixshow", "mixshow edit"],
              distance: .sameTakeOtherLength, uncertain: ["snip", "snippet", "se", "short"]),
        .init(.acapIn, .pool, words: ["acap in", "acapella in", "acapella intro", "acca in", "acap intro", "clapapella"],
              distance: .sameTakeOtherLength),
        .init(.acapOut, .pool, words: ["acap out", "acapella out", "acapella outro", "acca out", "acap in out", "acap in and out"],
              distance: .sameTakeOtherLength),
        .init(.transition, .pool, words: ["transition", "trans"], distance: .otherProduction,
              // The two tempos ("100-128", "100 to 128") are read by `NameReading` from the text itself.
              uncertain: ["trans"]),
        .init(.redrum, .pool, words: ["redrum", "re drum"], distance: .sameTakeOtherLength),
        .init(.party, .pool, words: ["hype", "hype edit", "hype intro", "party break", "slam", "slam edit", "wordplay", "segue",
                                     "drop in", "jump off", "8 bar chor", "4 bar chor", "chor out", "4 bar brk in", "8 bar brk in"],
              distance: .otherProduction,
              // AC: found in use, no pool's own definition; grouped by guess. Each means "a pool tool, not in a catalogue".
              uncertain: ["hype", "hype edit", "hype intro", "slam", "slam edit", "segue", "wordplay", "jump off"]),
        .init(.live, .performance, words: ["live", "live at", "live in", "live from", "live version", "concert", "live mix"],
              distance: .otherPerformance),
        .init(.otherTake, .performance, words: ["acoustic", "unplugged", "stripped", "piano version", "demo", "re recorded",
                                                "re record", "rerecorded", "session", "orchestral", "acoustic version"],
              distance: .otherPerformance, uncertain: ["session", "stripped"]),
        .init(.mixed, .mixedRelease, words: ["mixed", "continuous mix", "dj mix", "mix cut", "mixed version"],
              distance: .otherProduction),
        .init(.altered, .sound, words: ["sped up", "slowed", "slowed reverb", "slowed and reverb", "nightcore", "bass boosted",
                                        "8d", "mono"],
              distance: .otherProduction, uncertain: ["mono"]),
    ]

    /// Words that add nothing after a kind's words ("Extended Mix" is "Extended", "Dub Version" is "Dub").
    public static let filler: Set<String> = ["mix", "version", "edit", "cut", "vers", "ver"]

    // MARK: clean and dirty (the lyrics fact; AC, 5.5 and 5.2)

    public static let lyricsWords: [LyricsWord] = [
        .init("clean", .clean), .init("clean edit", .clean), .init("clean version", .clean), .init("clean mix", .clean),
        .init("radio clean", .clean), .init("super clean", .clean), .init("squeaky clean", .clean),
        .init("edited", .clean, aloneOnly: true), .init("censored", .clean), .init("amended", .clean, uncertain: true),
        .init("clean intro", .clean), .init("clean lyrics", .clean),
        .init("dirty", .dirty), .init("explicit", .dirty), .init("explicit version", .dirty), .init("uncensored", .dirty),
        .init("unedited", .dirty, aloneOnly: true), .init("dirty intro", .dirty), .init("dirty version", .dirty),
        .init("explicit lyrics", .dirty),
        // "Raw" and "Street" are remixers' and labels' names as often as lyrics words: read only alone.
        .init("raw", .dirty, aloneOnly: true, uncertain: true), .init("street", .dirty, aloneOnly: true, uncertain: true),
    ]
    /// Hashtags DJs put in a comment or grouping ("#Clean"), read anywhere in the text.
    public static let lyricsHashtags: [String: Lyrics] = ["#clean": .clean, "#dirty": .dirty, "#explicit": .dirty]

    /// The values of the tags that state it as data (AC section 4; iTunes' advisory): `ITUNESADVISORY` and MP4's
    /// `rtng` (1 or 4 explicit, 2 clean, 0 not said), and the free-text `EXPLICIT` some taggers write.
    public static func lyrics(advisory: String) -> Lyrics? {
        switch advisory.trimmingCharacters(in: .whitespaces).lowercased() {
        case "1", "4", "explicit", "yes", "true", "dirty": return .dirty
        case "2", "clean", "edited": return .clean
        default: return nil
        }
    }

    // MARK: what is not a version (AC, 5.5)

    /// Words that open a featured credit in brackets ("feat. Kaya Venn"): kept in the credit, never a version.
    /// "with" is left out of brackets: "(With His Song)" is as often a part of the title (uncertain).
    public static let featuredWords: [String] = ["feat", "featuring", "ft", "f", "f/", "w/", "prod", "prod by", "produced by"]
    /// Bracket contents that are part of the title: kept in the title.
    public static let titlePartWords: [String] = ["part", "pt", "reprise", "interlude", "skit", "chapter", "vol", "volume", "no"]
    /// Bracket contents that are notes, not a version: kept as written and offered for clean-up (AC 5.3, suggestion 2).
    public static let junkWords: [String] = ["free download", "free dl", "official video", "official music video", "official audio",
                                             "official lyric video", "lyric video", "lyrics video", "lyrics", "audio", "hq", "hd",
                                             "high quality", "promo", "promo only", "master", "final", "preview", "visualizer",
                                             "visualiser", "music video", "video", "full song", "out now", "premiere", "exclusive",
                                             "mp3", "flac", "wav", "kbps", "320", "320kbps", "256kbps", "192kbps", "128kbps",
                                             "web", "vinyl", "bonus track", "hidden track", "unreleased"]
    /// Working notes a producer leaves at the end of a file name ("MASTER2", "final", "v3").
    public static let workingNote = #"^(master|mastered|final|finished|mixdown|bounce|print|v)\d*$"#
    /// A website's name: a word with a known ending, or "www".
    public static let websiteEndings = [".com", ".net", ".org", ".ru", ".info", ".io", ".co", ".uk", ".fm", ".me", ".to", ".cc",
                                        ".biz", ".pl", ".de", ".fr", ".es", ".it", ".nl", ".club", ".xyz", ".tv", ".in", ".online"]

    // MARK: the words that join the names in a credit (AC, 5.5)

    /// For comparing only: a credit is never split to be stored. `strong` joins also choose the first credited
    /// artist, who is sent to a lookup; the weak ones ("and", "y", "e", "et", "und", "con", "with") are as often part of
    /// a band's name, so they only help a comparison.
    public static let joins: [(word: String, strong: Bool, featuring: Bool)] = [
        ("feat.", true, true), ("feat", true, true), ("featuring", true, true), ("ft.", true, true), ("ft", true, true),
        ("f.", true, true), ("f/", true, true), ("w/", true, true), ("with", false, true),
        ("&", true, false), ("+", true, false), ("x", true, false), ("vs.", true, false), ("vs", true, false),
        ("versus", true, false), ("meets", true, false), ("pres.", true, false), ("presents", true, false),
        (",", true, false), (";", true, false), ("/", true, false),
        ("and", false, false), ("y", false, false), ("con", false, true), ("e", false, false), ("et", false, false),
        ("und", false, false),
    ]

    // MARK: folding text for matching

    /// Text as the vocabulary's phrases are written: lower case, accents gone, "12\"" and "12''" as "12 inch", full
    /// stops gone, hyphens, underscores and other punctuation as spaces (except `#`, `/` after w or f, and `&`),
    /// possessive "'s" gone, one space between words.
    public static func fold(_ s: String) -> String {
        var t = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        t = t.replacingOccurrences(of: "’", with: "'").replacingOccurrences(of: "”", with: "\"").replacingOccurrences(of: "″", with: "\"")
        t = t.replacingOccurrences(of: #"(\d)\s*(\"|'')"#, with: "$1 inch ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"(\d)\s*in\b"#, with: "$1 inch", options: .regularExpression)
        t = t.replacingOccurrences(of: "'s\\b", with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: ".", with: "")
        var out = ""
        for ch in t {
            if ch.isLetter || ch.isNumber || ch == "#" || ch == "&" { out.append(ch) } else { out.append(" ") }
        }
        return out.split(separator: " ").joined(separator: " ")
    }

    /// The vocabulary's phrases, each as words, with what they mean, longest first, for matching.
    public enum Meaning: Sendable, Equatable {
        case kind(VersionKind, needsName: Bool)
        case lyrics(Lyrics, aloneOnly: Bool)
    }
    public struct Phrase: Sendable {
        public let words: [String]
        public let meaning: Meaning
        public let uncertain: Bool
    }
    public static let phrases: [Phrase] = {
        var out: [Phrase] = []
        for k in kinds {
            for w in k.words { out.append(Phrase(words: w.split(separator: " ").map(String.init), meaning: .kind(k.kind, needsName: false),
                                                 uncertain: k.uncertain.contains(w))) }
            for w in k.withName { out.append(Phrase(words: w.split(separator: " ").map(String.init), meaning: .kind(k.kind, needsName: true),
                                                    uncertain: true)) }
        }
        for l in lyricsWords {
            out.append(Phrase(words: l.phrase.split(separator: " ").map(String.init), meaning: .lyrics(l.lyrics, aloneOnly: l.aloneOnly),
                              uncertain: l.uncertain))
        }
        // Longest first; among equals, a phrase that needs no name first.
        return out.sorted { a, b in
            if a.words.count != b.words.count { return a.words.count > b.words.count }
            if case .kind(_, let na) = a.meaning, case .kind(_, let nb) = b.meaning, na != nb { return !na }
            return false
        }
    }()

    public static func info(_ k: VersionKind) -> VersionKindInfo { kinds.first { $0.kind == k }! }

    /// Whether a word of a name matches a vocabulary word, a plural "s" ignored.
    static func same(_ word: String, _ vocab: String) -> Bool {
        word == vocab || (vocab.count >= 3 && (word == vocab + "s" || word == vocab + "es"))
    }
}

// MARK: comparing a song with a candidate (research AC, 5.5, "Comparing a song with a candidate")

/// What a catalogue's candidate is to the DJ's song, by their versions' kinds, the names in them and whether the
/// lengths fit (within the lookup's allowance), never by spelling.
public enum VersionMatch: String, Codable, Sendable {
    /// The same version, any spelling. Choose.
    case same
    /// The song has no version and the candidate is a radio, extended or club cut of the same length: the same record
    /// under the catalogue's word. Choose; the word is offered unticked.
    case catalogueWord
    /// The same take, one of the two said clean or dirty: choose for artist, year, label and release; the lyrics fact
    /// stays the song's.
    case sameTake
    /// The song is a pool's or a DJ's edit and the candidate the original: its facts are the original's.
    case original
    /// Another version or another recording. List.
    case other
    /// Nothing in a catalogue is this file (a mashup, a transition, a party tool, a DJ tool, a sped-up copy, a cut from
    /// a mixed release). At most the original of its first title, as a list.
    case notInCatalogue

    /// Whether Desk may choose the candidate by itself for this reading (with the other rules met).
    public var chooses: Bool { self == .same || self == .catalogueWord || self == .sameTake }
}

public enum VersionCompare {
    /// Kinds a DJ's or a pool's edit is made of: the same take, rearranged or with bars added (AC 1.4). A candidate
    /// that is the original gives the original's year and label (D39, the owner's yes).
    public static let djEditKinds: Set<VersionKind> = [.intro, .outro, .short, .acapIn, .acapOut, .redrum, .djEdit]
    /// Kinds no catalogue holds as this file.
    public static let notInCatalogue: Set<VersionKind> = [.mashup, .transition, .party, .tool, .altered, .mixed]
    /// Kinds whose name must match: two remixes are the same only with the same name in both.
    public static let named: Set<VersionKind> = [.remix, .dub, .vip, .djEdit, .bootleg]
    /// The length family that a plain song may meet under a catalogue's word.
    public static let lengthWords: Set<VersionKind> = [.radio, .extended, .club]

    /// The reading of a candidate for a song, by AC 5.5's table.
    public static func compare(song: VersionReading?, candidate: VersionReading?, fits: Bool) -> VersionMatch {
        let s = song?.core ?? [], c = candidate?.core ?? []
        let lyricsDiffer = (song?.lyrics != nil || candidate?.lyrics != nil) && song?.lyrics != candidate?.lyrics
        func take(_ m: VersionMatch) -> VersionMatch { m == .same && lyricsDiffer ? .sameTake : m }
        if !s.isDisjoint(with: notInCatalogue) { return .notInCatalogue }
        if s.isEmpty {
            if c.isEmpty { return fits ? take(.same) : .other }
            if c.isSubset(of: lengthWords) { return fits ? (lyricsDiffer ? .sameTake : .catalogueWord) : .other }
            return .other
        }
        // A pool's or a DJ's edit against the plain one: the original, whatever its length.
        if s.isSubset(of: djEditKinds) && c.isEmpty { return .original }
        // Otherwise only the same kinds (a radio edit against a plain one is another version: the table has no row
        // that chooses it).
        guard s == c, fits else { return .other }
        // The same kinds: a named kind needs the same names in both.
        if !s.isDisjoint(with: named) {
            let sn = Set(song?.names ?? []), cn = Set(candidate?.names ?? [])
            guard !sn.isEmpty, sn == cn else { return .other }
        }
        return take(.same)
    }
}
