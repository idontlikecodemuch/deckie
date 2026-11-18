import Foundation

// Reading a song's name the way a DJ means it (D39; research AC, sections 2 and 5): a title, a file name or a tag,
// read into its title, its version as written, the version's kinds, the people a version names, clean or dirty, the
// artists of a credit, and what is neither (a track number, a key or tempo a key tool wrote in front, an energy
// number, a DJ's mark, a website's name, a scene group's tag). Nothing is thrown away: every part keeps its text as
// written, and `written` is the whole text read. The words are `VersionWords`'.
//
// Three things are kept apart (AC 5.1): what is **kept** (everything, as the DJ or the file has it; this reader never
// changes a song's name, it only reads it), what is **shown** (the title with its version, `shown`), and what is
// **sent** to a lookup (the bare title and the first credited artist, `sentTitle` and `firstArtist`).

/// A version, read: its text as written, its kinds, the names in it (a remixer, an editor, a pool), clean or dirty,
/// and a transition's two tempos.
public struct VersionReading: Equatable, Codable, Sendable {
    /// The whole version as written (several brackets joined by a space, as they stood).
    public var written: String
    public var kinds: [VersionKind]
    /// The names in it, folded (`VersionWords.fold`): "dj ostro", "klangkarussell".
    public var names: [String]
    public var lyrics: Lyrics?
    /// A transition's tempos, in beats per minute (`[100, 128]`).
    public var tempos: [Int]?
    /// Read through a phrase letter AC marks as uncertain.
    public var uncertain: Bool

    public init(written: String, kinds: [VersionKind] = [], names: [String] = [], lyrics: Lyrics? = nil, tempos: [Int]? = nil,
                uncertain: Bool = false) {
        self.written = written; self.kinds = kinds; self.names = names; self.lyrics = lyrics; self.tempos = tempos; self.uncertain = uncertain
    }

    /// The kinds that make it another version than the plain one: everything but `plain` and `remaster`.
    public var core: Set<VersionKind> { Set(kinds).subtracting([.plain, .remaster]) }
    /// Whether it says nothing but "the plain one" (or a remaster, the same recording).
    public var isPlain: Bool { core.isEmpty }
    public var families: Set<VersionFamily> { Set(core.map { VersionWords.info($0).family }) }

    /// Two readings put together (a stored version and the brackets of a title).
    public func merged(_ o: VersionReading?) -> VersionReading {
        guard let o else { return self }
        var r = self
        r.written = [written, o.written].filter { !$0.isEmpty }.joined(separator: " ")
        for k in o.kinds where !r.kinds.contains(k) { r.kinds.append(k) }
        for n in o.names where !r.names.contains(n) { r.names.append(n) }
        if r.lyrics == nil { r.lyrics = o.lyrics } else if let l = o.lyrics, l != r.lyrics { r.lyrics = nil; r.uncertain = true }
        r.tempos = r.tempos ?? o.tempos
        r.uncertain = r.uncertain || o.uncertain
        return r
    }
}

/// One name in a credit, and whether the word before it said "featuring".
public struct CreditName: Equatable, Sendable {
    public var name: String
    public var featuring: Bool
}

/// A name, read. Every text is as written.
public struct ReadName: Equatable, Sendable {
    /// The whole text read (a file name's stem, or the title tag).
    public var written: String
    /// A track number in front: "07", "1-07", "1.04", "307".
    public var number: String?
    /// A key and a tempo a key tool wrote in front ("8A", "128"), and an energy number.
    public var key: String?
    public var tempo: String?
    public var energy: String?
    /// A mark the DJ put in front ("*"). What it means is the DJ's own (AC 2.2).
    public var mark: String?
    /// The credit as written: "Marlo Dune ft. Kaya Venn".
    public var artist: String?
    /// The title as written, without its version, its featured credit and its notes; brackets that are part of the
    /// title ("Part 2") stay in it.
    public var title: String
    /// A featured credit written with the title: "feat. Kaya Venn".
    public var featured: String?
    public var version: VersionReading?
    /// What is neither name nor version, as written: a website's name, "Official Video", a bitrate, a year, a key or
    /// a tempo in brackets, a scene group's tag, a working note.
    public var notes: [String]
    /// The release a Bandcamp file name gives ("Artist - Album - 02 Title").
    public var release: String?
    /// Read as "Title - Artist": the part before the dash carried the version and the part after it none.
    public var swapped: Bool
    /// A file name's title part exactly as written there, its brackets with it ("Night Drive (Intro - Dirty)"), and a
    /// version that stood after a second dash, as written ("DJ Ostro Remix"). What Desk keeps as the song's title and
    /// version when it names a song from its file name.
    public var titleWritten: String
    public var dashedVersion: String?

    public init(written: String, title: String) {
        self.written = written; self.title = title; notes = []; swapped = false; titleWritten = title
    }

    /// The credit's names, in order (for sending and comparing only: the credit is kept as written).
    public var credit: [CreditName] { artist.map { NameReading.credit($0) } ?? [] }
    /// The first credited artist: the one a song is filed under and sent to a lookup.
    public var firstArtist: String? { artist.flatMap(NameReading.firstArtist) }
    public var lyrics: Lyrics? { version?.lyrics }
    /// The title as shown: with its version in brackets, as DJs write it.
    public var shown: String { NameReading.shown(title: title, version: version?.written) }
}

public enum NameReading {
    // MARK: a version's text

    /// What one bracket or one dashed part holds.
    public enum Piece: Equatable, Sendable {
        case version(VersionReading)
        case featured(String)
        /// Part of the title ("Part 2", "Reprise", a phrase with no version word).
        case titlePart
        /// A note: a website, a bitrate, a year, a key, a tempo, "Official Video", a scene group's tag.
        case note
    }

    /// Reads one bracket's or one dashed part's text. `square` is true for square brackets, where a text with no
    /// version word is a note (a scene group's tag, a site) rather than part of the title.
    public static func piece(_ text: String, square: Bool = false) -> Piece {
        let raw = text.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return .note }
        let lower = raw.lowercased()
        if lower.contains("www.") || isWebsite(lower) { return .note }
        let words = VersionWords.fold(raw).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return .note }
        if lower.hasPrefix("w/") || lower.hasPrefix("f/") { return .featured(raw) }
        if let f = words.first, ["feat", "featuring", "ft", "prod"].contains(f) || (f == "f" && words.count > 1 && lower.hasPrefix("f.")) {
            return .featured(raw)
        }
        let joined = words.joined(separator: " ")
        if VersionWords.junkWords.contains(joined) || words.allSatisfy({ VersionWords.junkWords.contains($0) || Int($0) != nil }) && words.contains(where: { VersionWords.junkWords.contains($0) }) {
            return .note
        }
        if isYear(joined) || isKeyCode(raw) || isTempo(raw) || isBitrate(lower) { return .note }
        // "From" a film or a show ("from the film X", "Love Theme from X"): a note, kept as written (AC 5.5).
        if words.contains("from") && !hasKindWord(words) { return .note }
        if let first = words.first, VersionWords.titlePartWords.contains(first),
           !(words.count > 1 && hasKindWord(Array(words.dropFirst()))) {
            return .titlePart
        }
        let v = readVersion(raw)
        if !v.kinds.isEmpty || v.lyrics != nil || v.tempos != nil { return .version(v) }
        return square ? .note : .titlePart
    }

    static func isWebsite(_ lower: String) -> Bool {
        lower.split(separator: " ").contains { w in VersionWords.websiteEndings.contains { w.hasSuffix($0) && w.count > $0.count } }
    }
    /// A year alone ("1999").
    public static func isYearText(_ s: String) -> Bool { isYear(s.trimmingCharacters(in: .whitespaces)) }
    static func isYear(_ s: String) -> Bool {
        guard s.count == 4, let n = Int(s) else { return false }
        return (1900...2100).contains(n)
    }
    /// A key tool's code: Camelot ("8A", "08B"), Open Key ("8m", "1d"), or a musical key ("C#", "Am", "F#m", "Ebmin").
    public static func isKeyCode(_ s: String) -> Bool {
        s.range(of: #"^(0?[1-9]|1[0-2])[ABabdm]$"#, options: .regularExpression) != nil
            || s.range(of: #"^[A-Ga-g][#b♯♭]?(m|min|maj|minor|major)?$"#, options: .regularExpression) != nil && s.count <= 6 && s.first!.isUppercase
    }
    static func isTempo(_ s: String) -> Bool {
        let t = s.lowercased().replacingOccurrences(of: "bpm", with: "").trimmingCharacters(in: .whitespaces)
        guard let d = Double(t) else { return false }
        return (60...200).contains(d) && (s.lowercased().contains("bpm") || t.contains(".") || t.count == 3)
    }
    static func isBitrate(_ lower: String) -> Bool {
        lower.range(of: #"\b\d{2,3}\s*kbps\b"#, options: .regularExpression) != nil
    }
    static func hasKindWord(_ words: [String]) -> Bool {
        let v = scan(words)
        return v.contains { if case .kind = $0.what { return true }; return false }
    }

    /// One span of a scanned text: a phrase of the vocabulary, a filler word, a number, or a word of a name.
    struct Span { var what: What; var count: Int; var uncertain: Bool
        enum What { case kind(VersionKind, needsName: Bool), lyrics(Lyrics, aloneOnly: Bool), filler, number(String), name(String) }
    }

    /// The words matched against the vocabulary's phrases, longest first at each place.
    static func scan(_ words: [String]) -> [Span] {
        var spans: [Span] = []
        var i = 0
        outer: while i < words.count {
            for p in VersionWords.phrases where i + p.words.count <= words.count {
                if zip(words[i..<(i + p.words.count)], p.words).allSatisfy({ VersionWords.same($0, $1) }) {
                    switch p.meaning {
                    case let .kind(k, n): spans.append(Span(what: .kind(k, needsName: n), count: p.words.count, uncertain: p.uncertain))
                    case let .lyrics(l, a): spans.append(Span(what: .lyrics(l, aloneOnly: a), count: p.words.count, uncertain: p.uncertain))
                    }
                    i += p.words.count
                    continue outer
                }
            }
            let w = words[i]
            if VersionWords.filler.contains(w) { spans.append(Span(what: .filler, count: 1, uncertain: false)) }
            else if w.allSatisfy(\.isNumber) { spans.append(Span(what: .number(w), count: 1, uncertain: false)) }
            else { spans.append(Span(what: .name(w), count: 1, uncertain: false)) }
            i += 1
        }
        return spans
    }

    /// Single words of the vocabulary that are seldom a remixer's name: kept as a kind even when a name follows.
    static let strongWords: Set<String> = ["extended", "remix", "rmx", "rmix", "remixed", "instrumental", "inst", "acapella", "acap",
                                           "intro", "outro", "redrum", "remaster", "remastered", "bootleg", "mashup", "vip", "edit",
                                           "reedit", "rework", "refix", "dubstrumental", "transition", "unplugged", "acoustic",
                                           "karaoke", "clapapella", "cutdown", "acappella", "accapella", "remake"]

    /// A version's text read into its kinds, names, lyrics and tempos (AC 5.5, "Reading a version"): split on " - ",
    /// "/" and ","; in each piece, lyrics words, then kind words; the words left over are a name.
    public static func readVersion(_ text: String) -> VersionReading {
        var out = VersionReading(written: text.trimmingCharacters(in: .whitespaces))
        var pieces = [text]
        for sep in [" - ", " – ", " — ", "/", ","] { pieces = pieces.flatMap { $0.components(separatedBy: sep) } }
        for raw in pieces {
            var p = raw
            // A transition's tempos: "100-128", "100 to 128", "100>128".
            if let m = p.range(of: #"\b(\d{2,3})\s*(-|–|to|>)\s*(\d{2,3})\b"#, options: .regularExpression) {
                let nums = p[m].split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
                if nums.count == 2, nums.allSatisfy({ (50...220).contains($0) }) {
                    out.tempos = nums
                    if !out.kinds.contains(.transition) { out.kinds.append(.transition) }
                    p.removeSubrange(m)
                }
            }
            let words = VersionWords.fold(p).split(separator: " ").map(String.init)
            // Hashtags.
            for w in words { if let l = VersionWords.lyricsHashtags[w] { out.lyrics = out.lyrics ?? l } }
            let plain = words.filter { !$0.hasPrefix("#") }
            var spans = scan(plain)
            func isName(_ k: Int) -> Bool {
                guard k >= 0, k < spans.count else { return false }
                if case .name = spans[k].what { return true }
                return false
            }
            // A single word of the vocabulary just before a name word is part of the name ("Dub Pistols", "Radio Slave"),
            // unless it is one of the strong words; a lyrics word beside a name is a name too ("Clean Bandit", "Dirty South").
            for j in spans.indices where spans[j].count == 1 {
                let w = plain[offset(spans, j)]
                switch spans[j].what {
                case .kind(_, false) where isName(j + 1) && !strongWords.contains(w): spans[j].what = .name(w)
                case .lyrics where isName(j + 1) || isName(j - 1): spans[j].what = .name(w)
                default: break
                }
            }
            // A phrase that needs a name ("Mix", "Version") with none is filler; "Edit" with a name is a DJ's edit.
            let hasName = spans.indices.contains(where: isName)
            for j in spans.indices {
                if case .kind(_, true) = spans[j].what, !hasName { spans[j].what = .filler }
                if case .kind(.radio, false) = spans[j].what, spans[j].count == 1, hasName, plain[offset(spans, j)] == "edit" {
                    spans[j].what = .kind(.djEdit, needsName: false)
                }
            }
            let otherThanLyrics = spans.contains { s in
                switch s.what { case .kind, .name: return true; default: return false }
            }
            // Names: runs of name words, each run one name.
            var run: [String] = []
            func flush() { if !run.isEmpty { let n = run.joined(separator: " "); if !out.names.contains(n) { out.names.append(n) }; run = [] } }
            var years: [String] = []
            for s in spans {
                switch s.what {
                case let .name(n): run.append(n)
                case let .kind(k, _):
                    flush()
                    if !out.kinds.contains(k) { out.kinds.append(k) }
                    if s.uncertain { out.uncertain = true }
                case let .lyrics(l, aloneOnly):
                    flush()
                    if aloneOnly && otherThanLyrics { continue }
                    if out.lyrics == nil { out.lyrics = l } else if out.lyrics != l { out.lyrics = nil; out.uncertain = true }
                    if s.uncertain { out.uncertain = true }
                case let .number(n): flush(); years.append(n)
                case .filler: flush()
                }
            }
            flush()
            // "2011 Version": a year and "version" with nothing else is another take.
            if out.kinds.isEmpty, out.names.isEmpty, years.contains(where: { isYear($0) }), words.contains("version") {
                out.kinds.append(.otherTake)
            }
        }
        // The plain one beside another kind says nothing ("Original Radio Edit" is a radio edit).
        if out.kinds.count > 1 { out.kinds.removeAll { $0 == .plain } }
        return out
    }

    /// The index into the scanned words where span `j` starts.
    static func offset(_ spans: [Span], _ j: Int) -> Int { spans[..<j].reduce(0) { $0 + $1.count } }

    // MARK: a title

    /// A title as written, read: the version brackets and a version after a dash at its end, a featured credit, and
    /// notes peeled off; brackets that are part of the title stay. The title itself is not changed: this is a reading.
    public static func readTitle(_ written: String) -> ReadName {
        var r = ReadName(written: written, title: written.trimmingCharacters(in: .whitespaces))
        var t = collapse(r.title.replacingOccurrences(of: " – ", with: " - ").replacingOccurrences(of: " — ", with: " - "))
        var version: VersionReading? = nil
        var pieces: [VersionReading] = []
        // A working note at the very end ("MASTER2").
        if let last = t.split(separator: " ").last, String(last).lowercased().range(of: VersionWords.workingNote, options: .regularExpression) != nil,
           t.split(separator: " ").count > 1 {
            r.notes.insert(String(last), at: 0)
            t = String(t.dropLast(last.count)).trimmingCharacters(in: .whitespaces)
        }
        // Brackets at the end, last first.
        peeling: while let (inner, square, rest) = lastBracket(t), !rest.isEmpty {
            switch piece(inner, square: square) {
            case let .version(v): pieces.insert(v, at: 0); t = rest
            case let .featured(f): r.featured = r.featured ?? f; t = rest
            case .note: r.notes.insert((square ? "[" : "(") + inner + (square ? "]" : ")"), at: 0); t = rest
            case .titlePart: break peeling
            }
        }
        // A featured credit without brackets: "Night Drive feat. Kaya Venn".
        if let m = t.range(of: #"\s(feat\.?|ft\.?|featuring)\s+\S.*$"#, options: [.regularExpression, .caseInsensitive]) {
            r.featured = r.featured ?? String(t[m]).trimmingCharacters(in: .whitespaces)
            t = String(t[..<m.lowerBound]).trimmingCharacters(in: .whitespaces)
        }
        // A version after a dash at the end: "Night Drive - Extended Mix".
        let dashed = dashes(t)
        if dashed.count >= 2, case let .version(v) = piece(dashed.last!), !dashed.dropLast().joined(separator: " - ").isEmpty {
            pieces.insert(v, at: 0)
            t = dashed.dropLast().joined(separator: " - ")
        }
        for v in pieces { version = version.map { $0.merged(v) } ?? v }
        r.title = t
        r.version = version
        return r
    }

    /// The last bracket group of a text, if the text ends with one: its inside, whether it is square, and the text
    /// before it.
    static func lastBracket(_ t: String) -> (String, Bool, String)? {
        guard let last = t.last, last == ")" || last == "]" else { return nil }
        let open: Character = last == ")" ? "(" : "["
        var depth = 0
        var i = t.endIndex
        while i > t.startIndex {
            i = t.index(before: i)
            if t[i] == last { depth += 1 }
            else if t[i] == open { depth -= 1; if depth == 0 { break } }
        }
        guard depth == 0, t[i] == open else { return nil }
        let inner = String(t[t.index(after: i)..<t.index(before: t.endIndex)])
        let rest = String(t[..<i]).trimmingCharacters(in: .whitespaces)
        return (inner, last == "]", rest)
    }

    // MARK: a credit

    /// A credit's names, split on the join words (`VersionWords.joins`). For comparing and for finding the first
    /// credited artist only; a credit is never stored split.
    public static func credit(_ s: String, strongOnly: Bool = false) -> [CreditName] {
        var out: [CreditName] = []
        var current = ""
        var featuring = false
        let tokens = s.replacingOccurrences(of: ",", with: " , ").replacingOccurrences(of: ";", with: " ; ")
            .replacingOccurrences(of: "&", with: " & ").replacingOccurrences(of: " / ", with: " / ")
            .split(separator: " ").map(String.init)
        for tok in tokens {
            let low = tok.lowercased()
            if let j = VersionWords.joins.first(where: { $0.word == low }), !strongOnly || j.strong, !current.isEmpty {
                out.append(CreditName(name: current, featuring: featuring))
                current = ""
                // Once a credit says "featuring", every name after it is a guest ("A feat. B & C": B and C).
                featuring = featuring || j.featuring
                continue
            }
            if tok.contains("/") && !tok.hasPrefix("w/") && !tok.hasPrefix("f/") && tok.count > 1 {
                let parts = tok.split(separator: "/").map(String.init)
                for (k, p) in parts.enumerated() {
                    current += (current.isEmpty ? "" : " ") + p
                    if k < parts.count - 1 { out.append(CreditName(name: current, featuring: featuring)); current = ""; featuring = false }
                }
                continue
            }
            current += (current.isEmpty ? "" : " ") + tok
        }
        if !current.isEmpty { out.append(CreditName(name: current, featuring: featuring)) }
        return out.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// The first credited artist: the credit up to its first strong join ("Marlo Dune" of "Marlo Dune ft. Kaya Venn").
    public static func firstArtist(_ s: String) -> String? {
        credit(s, strongOnly: true).first?.name.trimmingCharacters(in: .whitespaces)
    }

    // MARK: a file name

    /// A file name's stem read (AC 2.1): a track number, a key tool's prefix, a DJ's mark, "[Artist] Title", the
    /// artist and the title split at a dash, a version after a second dash, a Bandcamp release, a scene name with
    /// underscores, "Title (Version) - Artist", then the title's own brackets. `number` is the song's place number:
    /// a bare number in front ("07 Song") is taken off only when it is that number, or when a dash follows it and
    /// another dash comes later, so an artist whose name is a number keeps it.
    public static func readFileName(_ stem: String, number placeNumber: Int? = nil) -> ReadName {
        var s = stem
        var r = ReadName(written: stem, title: stem)
        let scene = !s.contains(" ") && s.contains("_")
        if scene { s = s.replacingOccurrences(of: "_", with: " ") }
        s = collapse(s.replacingOccurrences(of: " – ", with: " - ").replacingOccurrences(of: " — ", with: " - "))
        // A track number in front.
        let patterns: [(String, Bool)] = [
            (#"^\((\d{1,4})\)\s+"#, false),                 // "(307) " a set's numbers in brackets
            (#"^(\d{1,2}[.-]\d{1,3})\s+(?:-\s+)?"#, false),  // "1-07 ", "1.04 " a disc and a track
            (#"^(\d{1,3})\.\s+"#, false),                   // "07. "
            (#"^(\d{1,3})\)\s*"#, false),                   // "07) "
            (#"^(\d{1,3})\s+-\s+"#, true),                  // "07 - " (guarded: "112 - Only You")
            (#"^(\d{1,3})-(?=\S)"#, false),                  // "101-" a scene name
            (#"^(\d{1,3})\s+"#, true),                      // "07 " (guarded: "50 Cent - ...")
        ]
        for (p, guarded) in patterns {
            guard let m = s.range(of: p, options: .regularExpression) else { continue }
            let digits = String(s[m]).filter { $0.isNumber || $0 == "." || $0 == "-" }.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
            let rest = String(s[m.upperBound...])
            if guarded {
                // A number with a leading zero is a track number; one without is taken off only when it is the song's
                // place number, or for "07 - Artist - Title", where another dash follows.
                let n = Int(digits)
                let dashForm = p.contains("-")
                guard (n != nil && n == placeNumber) || digits.hasPrefix("0") || (dashForm && rest.contains(" - ")) else { continue }
            }
            guard !rest.trimmingCharacters(in: .whitespaces).isEmpty else { break }
            r.number = digits
            s = rest
            break
        }
        // A key tool's prefix: "8A - 128 - Artist - Title", "[8A] Artist - Title", "8A - Artist - Title".
        if let m = s.range(of: #"^\[((?:0?[1-9]|1[0-2])[ABabdm])\]\s*"#, options: .regularExpression) {
            r.key = String(s[m]).trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            s = String(s[m.upperBound...])
        } else {
            var parts = s.components(separatedBy: " - ")
            if parts.count >= 2, isKeyCode(parts[0].trimmingCharacters(in: .whitespaces)),
               parts[0].trimmingCharacters(in: .whitespaces).range(of: #"^(0?[1-9]|1[0-2])[ABabdm]$"#, options: .regularExpression) != nil {
                r.key = parts.removeFirst().trimmingCharacters(in: .whitespaces)
                if parts.count >= 2, let d = Double(parts[0].trimmingCharacters(in: .whitespaces)), (50...220).contains(d) {
                    r.tempo = parts.removeFirst().trimmingCharacters(in: .whitespaces)
                }
                s = parts.joined(separator: " - ")
            }
        }
        // A DJ's mark: a symbol alone in front ("* Artist - Title").
        if let m = s.range(of: #"^[*!+~•#@^=]+\s+"#, options: .regularExpression) {
            r.mark = String(s[m]).trimmingCharacters(in: .whitespaces)
            s = String(s[m.upperBound...])
        }
        // "[Artist] Title": the artist in square brackets in front.
        var artist: String? = nil
        var title = s
        if let m = s.range(of: #"^\[([^\]]+)\]\s+(\S.*)$"#, options: .regularExpression), s[m].count == s.count,
           let close = s.firstIndex(of: "]") {
            let inner = String(s[s.index(after: s.startIndex)..<close])
            if case .titlePart = piece(inner), SongName.isUsableArtist(inner) {
                artist = inner
                title = String(s[s.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            } else if case .note = piece(inner, square: true), SongName.isUsableArtist(inner), !isKeyCode(inner) {
                artist = inner
                title = String(s[s.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        if artist == nil {
            var parts = dashes(s).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            // A scene name: "artist-title-group", dashes with no spaces.
            if parts.count == 1, scene, s.contains("-") {
                parts = s.split(separator: "-").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                // The last part, one short word that is no version, is the group's tag.
                if parts.count >= 3, let last = parts.last, !last.contains(" "), last.count <= 12 {
                    if case .version = piece(last) {} else { r.notes.append(parts.removeLast()) }
                }
            }
            var dashedVersion: VersionReading? = nil
            // A version after a second dash: the last part, with no brackets and no number in front, reads as one.
            if parts.count >= 3, let last = parts.last, !last.contains("("), !last.contains("["), !(last.first?.isNumber ?? false),
               case let .version(v) = piece(last) {
                dashedVersion = v
                parts.removeLast()
            }
            if parts.count >= 3, let m = parts[2].range(of: #"^(\d{1,3})\s+"#, options: .regularExpression) {
                // Bandcamp: "Artist - Album - 02 Title".
                artist = parts[0]; r.release = parts[1]
                title = String(parts[2][m.upperBound...]) + (parts.count > 3 ? " - " + parts[3...].joined(separator: " - ") : "")
                if r.number == nil { r.number = String(parts[2][m]).trimmingCharacters(in: .whitespaces) }
            } else if parts.count >= 2 {
                let a = parts[0], rest = parts.dropFirst().joined(separator: " - ")
                // "Title (Remix) - Artist": the version belongs to the title.
                let aRead = readTitle(a), restRead = readTitle(rest)
                if aRead.version != nil && restRead.version == nil && !rest.contains("(") && !rest.contains("[") && parts.count == 2
                    && SongName.isUsableArtist(rest) {
                    artist = rest; title = a; r.swapped = true
                } else if SongName.isUsableArtist(a) && SongName.isUsableTitle(rest) {
                    artist = a; title = rest
                } else {
                    title = parts.joined(separator: " - ")
                }
            } else {
                title = parts.first ?? s
            }
            if let v = dashedVersion {
                let t = readTitle(title)
                r.titleWritten = title.trimmingCharacters(in: .whitespaces)
                r.dashedVersion = v.written
                r.title = t.title
                r.featured = t.featured
                r.notes += t.notes
                r.version = t.version.map { $0.merged(v) } ?? v
                r.artist = artist
                return r
            }
        }
        let t = readTitle(title)
        r.titleWritten = title.trimmingCharacters(in: .whitespaces)
        r.title = t.title
        r.featured = t.featured
        r.version = t.version
        r.notes += t.notes
        r.artist = artist
        return r
    }

    /// The name a title tag and an artist tag give: the title read (`readTitle`), and a key tool's code taken off the
    /// front of either ("8A - Night Drive", "8A - Marlo Dune"), kept in `key`.
    public static func readTags(title: String, artist: String?) -> ReadName {
        var t = title
        var key: String? = nil
        func offKey(_ s: String) -> (String?, String) {
            let parts = s.components(separatedBy: " - ")
            if parts.count >= 2, parts[0].trimmingCharacters(in: .whitespaces).range(of: #"^(0?[1-9]|1[0-2])[ABabdm]$"#, options: .regularExpression) != nil {
                return (parts[0].trimmingCharacters(in: .whitespaces), parts.dropFirst().joined(separator: " - "))
            }
            return (nil, s)
        }
        (key, t) = offKey(t)
        var r = readTitle(t)
        r.written = title
        if let a = artist {
            let (k, rest) = offKey(a)
            r.artist = rest
            key = key ?? k
        }
        r.key = key
        return r
    }

    // MARK: comparing

    /// Text compared as whole words: folded, "&" as "and", "Pt" as "Part", a leading "The" gone.
    public static func compareWords(_ s: String?) -> [String] {
        guard let s else { return [] }
        var w = VersionWords.fold(s).replacingOccurrences(of: "&", with: " and ").split(separator: " ").map(String.init)
        w = w.map { $0 == "pt" ? "part" : $0 }
        if w.first == "the", w.count > 1 { w.removeFirst() }
        return w
    }

    /// Whether `needle`'s words stand whole, in order and together, in `hay`'s.
    public static func containsWhole(_ needle: [String], in hay: [String]) -> Bool {
        guard !needle.isEmpty, needle.count <= hay.count else { return false }
        for i in 0...(hay.count - needle.count) where Array(hay[i..<(i + needle.count)]) == needle { return true }
        return false
    }

    // MARK: shown

    /// The title as shown: the title with the version in brackets, as DJs write it, unless the title already carries
    /// it as written.
    public static func shown(title: String, version: String?) -> String {
        guard let v = version?.trimmingCharacters(in: .whitespaces), !v.isEmpty else { return title }
        let ft = VersionWords.fold(title), fv = VersionWords.fold(v)
        if !fv.isEmpty, ft.hasSuffix(fv) { return title }
        return "\(title) (\(v))"
    }

    /// A text split at " - ", except inside brackets ("Night Drive (Intro - Dirty)" is one part).
    public static func dashes(_ s: String) -> [String] {
        var out: [String] = []
        var depth = 0
        var cur = ""
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "(" || c == "[" { depth += 1 } else if (c == ")" || c == "]") && depth > 0 { depth -= 1 }
            if depth == 0, c == " ", s[i...].hasPrefix(" - ") {
                out.append(cur); cur = ""
                i = s.index(i, offsetBy: 3)
                continue
            }
            cur.append(c)
            i = s.index(after: i)
        }
        out.append(cur)
        return out
    }

    static func collapse(_ s: String) -> String {
        s.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}
