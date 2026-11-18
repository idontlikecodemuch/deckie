import Foundation

// A song's facts (D34, Nov 14, 2026; crate-format.md, "Addition with D34"): whatever a song's file, its disc, a DJ
// program's library or the DJ says about it beyond its title, artist and version, each fact with where it came from.
// Two places in a record, both left out when empty so a record without them keeps its bytes:
//
//   ident.facts        the facts Deckie knows the meaning of, by name (`release`, `year`, `label`, `genre`, ...), each
//                      `{"from": origin, "values": [text, ...]}`
//   file.other_tags    the rest of the file's text tags, by the tag's own name, as the file has them, with the tag
//                      formats read and what was left out, counted
//
// A later lookup fills the same `ident.facts` under its own origin (`lookup:<service>`), never a separate set, and
// never over the DJ's own entry (`SongFacts.rank`).

extension CrateTrack {
    /// One fact about a song (`ident.facts.<name>`): its values, as text, one or more (a file may give several genres),
    /// and where they came from (`SongFacts.Origin`).
    public struct Fact: Codable, Equatable, Hashable, Sendable {
        public var from: String
        public var values: [String]
        public init(_ values: [String], from: String) { self.values = values; self.from = from }
        public init(_ value: String, from: String) { self.init([value], from: from) }
        /// The values as one line: "House, Deep house".
        public var text: String { values.joined(separator: ", ") }
    }

    /// The rest of a file's text tags (`file.other_tags`): the tag formats read (`id3v2.4`, `vorbis`, ...), every
    /// text tag Deckie has no fact for, by the tag's own name, and what was left out, counted by reason
    /// (`SongFacts.LeftOut`).
    public struct OtherTags: Codable, Equatable, Sendable {
        public var formats: [String]
        public var tags: [String: [String]]
        public var leftOut: [String: Int]
        public init(formats: [String] = [], tags: [String: [String]] = [:], leftOut: [String: Int] = [:]) {
            self.formats = formats; self.tags = tags; self.leftOut = leftOut
        }
        enum CodingKeys: String, CodingKey { case formats, tags, leftOut = "left_out" }
        public var isEmpty: Bool { formats.isEmpty && tags.isEmpty && leftOut.isEmpty }
    }
}

/// The fixed parts of a song's facts: the names Deckie knows, where a fact can come from, which source wins, and the
/// bounds on what a file's tags may put into a crate file.
public enum SongFacts {
    // MARK: the facts Deckie knows

    /// The release (album, EP, single or compilation) the song is on.
    public static let release = "release"
    /// The release's own artist, kept only where it differs from the song's.
    public static let releaseArtist = "release_artist"
    /// The year, four digits, and the full date when the file gives more than the year, as written.
    public static let year = "year", date = "date"
    /// The year and date of the first release, when the file says this copy is a later one.
    public static let originalYear = "original_year", originalDate = "original_date"
    public static let label = "label"
    public static let catalogNumber = "catalog_number"
    public static let genre = "genre"
    /// The song's number on the release and how many songs it has; the disc's number in a set and how many discs.
    public static let trackNumber = "track_number", trackCount = "track_count"
    public static let discNumber = "disc_number", discCount = "disc_count"
    public static let composer = "composer", lyricist = "lyricist", remixer = "remixer", producer = "producer"
    public static let originalArtist = "original_artist"
    /// The recording's code (ISRC, one per version), and the release's barcode (UPC or EAN).
    public static let isrc = "isrc", barcode = "barcode"
    /// The tempo and the key the file's own tags state, as the DJ's software wrote them: text, never Deckie's reading.
    public static let bpmText = "bpm_text", keyText = "key_text"
    public static let comment = "comment", grouping = "grouping", mood = "mood"
    /// A line under the title the tag standards keep apart from the version ("Subtitle/Description refinement").
    public static let subtitle = "subtitle"
    /// "1" when the file marks the release as a compilation of several artists.
    public static let compilation = "compilation"
    public static let copyright = "copyright", language = "language"
    /// Clean or dirty (D39): `clean` or `dirty`, from the name and tags (`tag`, `filename`) or the DJ (`user`), never
    /// from a lookup. Not said is no fact at all, never shown as clean.
    public static let lyrics = "lyrics"
    /// The label the song first came out on (D39), beside `original_year`: what a lookup gives for a song on a
    /// compilation, or the original's for a DJ's edit, while `label` stays the copy's own.
    public static let originalLabel = "original_label"

    /// Every fact name above, in the order a window lists them.
    public static let known = [release, releaseArtist, year, date, originalYear, originalDate, label, catalogNumber,
                               genre, trackNumber, trackCount, discNumber, discCount, composer, lyricist, remixer,
                               producer, originalArtist, isrc, barcode, bpmText, keyText, comment, grouping, mood,
                               subtitle, compilation, copyright, language, lyrics, originalLabel]

    /// The facts a window shows as their own fields (release, year, label, genre); the rest are listed.
    public static let shown = [release, year, label, genre]

    /// Facts that may hold several values from one source; the others take the first value.
    public static let several: Set<String> = [genre, composer, lyricist, remixer, producer, originalArtist, mood, comment]

    // MARK: where a fact came from

    public enum Origin {
        /// The file's own tags.
        public static let tag = "tag"
        /// A music CD's CD-Text.
        public static let disc = "cdtext"
        /// The DJ, in Desk.
        public static let user = "user"
        /// The file's name, read (D39: clean or dirty written in a file name).
        public static let fileName = "filename"
        /// A lookup's answer for the original of a DJ's edit (D39): `lookup:musicbrainz:original`.
        public static let originalSuffix = ":original"
        /// A lookup the DJ asked for, by its service: `lookup:musicbrainz`.
        public static let lookupPrefix = "lookup:"
        public static func lookup(_ service: String) -> String { lookupPrefix + service }
        /// The DJ programs, by the names the crate file already uses for them (`key.source`, `ident.source`).
        public static let programs: Set<String> = ["rekordbox-xml", "traktor", "engine-dj", "serato", "virtualdj"]
    }

    /// Which source wins when two give the same fact: the DJ, then the file's own tags, then a DJ program's library,
    /// then the disc, then a lookup. Lower wins. A lookup only fills what nothing else gives, and nothing but the DJ
    /// replaces the DJ's own entry.
    public static func rank(_ origin: String) -> Int {
        if origin == Origin.user { return 0 }
        if origin == Origin.tag { return 1 }
        if Origin.programs.contains(origin) || origin == Origin.fileName { return 2 }
        if origin == Origin.disc { return 3 }
        if origin.hasPrefix(Origin.lookupPrefix) { return 4 }
        return 5
    }

    // MARK: bounds

    /// One value: at most this many bytes of UTF-8; a longer one is left out (`too_long`).
    public static let maxValueBytes = 1024
    /// One fact or tag: at most this many values; the rest are left out (`too_many`).
    public static let maxValues = 16
    /// A tag's name: at most this many bytes; a tag with a longer name is left out (`too_long`).
    public static let maxNameBytes = 64
    /// The other tags of one file, names and values together: at most this many bytes; tags past it, in name order,
    /// are left out (`over_total`).
    public static let maxOtherBytes = 4096
    /// The facts of one song, names and values together: at most this many bytes; facts past it, in `known`'s order,
    /// are left out (`over_total`).
    public static let maxFactBytes = 8192

    /// The bytes a set of facts takes by the bounds' count: names and values.
    public static func bytes(_ facts: [String: [String]]) -> Int {
        facts.reduce(0) { $0 + $1.key.utf8.count + $1.value.reduce(0) { $0 + $1.utf8.count } }
    }

    /// Why something a file holds is not in the crate file, as `file.other_tags.left_out` counts it.
    public enum LeftOut {
        /// A picture (cover art): never put in a crate file.
        public static let picture = "picture"
        /// Data that is not text (play counts, ratings, volume settings, ids in binary, ...).
        public static let binary = "binary"
        /// A DJ program's or a player's own data in a text tag (Serato's markers, iTunes' volume and gapless data).
        public static let `private` = "private"
        public static let tooLong = "too_long"
        public static let tooMany = "too_many"
        public static let overTotal = "over_total"
        public static let all = [picture, binary, `private`, tooLong, tooMany, overTotal]
    }

    /// A value as a crate file keeps it: trimmed, and nil when empty or not plain text (a control character other than
    /// a tab or a line break, which binary data read as text has).
    public static func clean(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        guard t.unicodeScalars.allSatisfy({ $0.value >= 0x20 || $0 == "\t" || $0 == "\n" || $0 == "\r" }),
              !t.unicodeScalars.contains(where: { (0x7F...0x9F).contains($0.value) || $0.value == 0xFFFD }) else { return nil }
        return t
    }

    /// Values within the bounds: each cleaned (`clean`), at most `maxValueBytes`, each once, at most `maxValues`.
    public static func bounded(_ values: [String]) -> [String] {
        var out: [String] = []
        for v in values {
            guard let c = clean(v), c.utf8.count <= maxValueBytes, !out.contains(c) else { continue }
            out.append(c)
            if out.count == maxValues { break }
        }
        return out
    }

    /// Whether a fact name is well formed: lower-case letters, digits and "_", starting with a letter.
    public static func isName(_ s: String) -> Bool {
        guard let f = s.unicodeScalars.first, ("a"..."z").contains(f), s.utf8.count <= maxNameBytes else { return false }
        return s.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
    }

    /// Whether an origin is well formed: letters, digits, "-", "_", "." and ":", 1 to 64 bytes.
    public static func isOrigin(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.count <= 64
            && s.unicodeScalars.allSatisfy { ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0))) || "-_.:".unicodeScalars.contains($0) }
    }
}

extension CrateTrack.Ident {
    /// Puts a fact in, unless a fact of that name from a source that ranks higher (or the same) is there already.
    /// Returns whether it went in.
    /// The values are bounded first (`SongFacts.bounded`), and a fact that would take the song's facts past their
    /// total is not put in.
    @discardableResult
    public mutating func offer(_ name: String, _ fact: CrateTrack.Fact) -> Bool {
        let values = SongFacts.bounded(fact.values)
        guard SongFacts.isName(name), SongFacts.isOrigin(fact.from), !values.isEmpty else { return false }
        if let have = facts[name], SongFacts.rank(have.from) <= SongFacts.rank(fact.from) { return false }
        var next = facts
        next[name] = .init(values, from: fact.from)
        guard SongFacts.bytes(next.mapValues(\.values)) <= SongFacts.maxFactBytes else { return false }
        facts = next
        return true
    }

    /// Takes out every fact whose origin `drop` picks (before a source is read again).
    public mutating func dropFacts(where drop: (String) -> Bool) {
        facts = facts.filter { !drop($0.value.from) }
    }

    /// A fact's values as one line, or nil.
    public func factText(_ name: String) -> String? { facts[name]?.text }
}
