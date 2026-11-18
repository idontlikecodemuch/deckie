import Foundation
import DeckieCrate

/// Whatever a song's file says about it beyond its title and artist (D34), read from its tags: the facts Deckie knows
/// (`SongFacts`: release, year, label, genre, numbers, composer, remixer, ISRC, the tagged tempo and key as text, ...)
/// and every other text tag by its own name, within `SongFacts`' bounds, with what was left out counted.
///
/// Read, in this order (the first that gives a single-valued fact wins; a fact that may hold several values gathers
/// them from every format, each value once):
///
/// - **ID3v2** (versions 2.2, 2.3 and 2.4) at the start of an MP3 or FLAC file, or in a WAV or AIFF file's `id3 `
///   chunk; text in Latin-1 (read as Windows-1252, which most taggers write), UTF-16 with a byte-order mark, UTF-16
///   big-endian, or UTF-8; several values in one frame (2.4's NUL between them) kept apart.
/// - **Vorbis comments** in a FLAC file: UTF-8 as the format says, Latin-1 when a value is not valid UTF-8; a key may
///   repeat.
/// - **RIFF `LIST INFO`** in a WAV file: UTF-8, or Latin-1 when not valid UTF-8.
/// - **AIFF's own text chunks** (`NAME`, `AUTH`, `(c) `, `ANNO`).
/// - **MP4 atoms** (`moov/udta/meta/ilst`) in an `.m4a`: UTF-8 and UTF-16 text, the number atoms (`trkn`, `disk`,
///   `tmpo`, `cpil`, `gnre`), and iTunes' free-form `----` atoms by their names.
/// - **ID3v1** at the end of an MP3, for what nothing above gave.
///
/// Never read: pictures (counted as `picture`), any other data that is not text (`binary`), and the private data DJ
/// programs and players keep in text tags (`private`: Serato's, Traktor's, iTunes' volume and gapless notes). A tag
/// that does not hold together gives nothing rather than an error. Nothing is read but the tags.
public struct FileFacts: Equatable, Sendable {
    /// The facts, by `SongFacts` name, each with its values.
    public var facts: [String: [String]] = [:]
    /// The other text tags, the formats read and what was left out.
    public var other = CrateTrack.OtherTags()

    public init(facts: [String: [String]] = [:], other: CrateTrack.OtherTags = .init()) {
        self.facts = facts; self.other = other
    }

    public var isEmpty: Bool { facts.isEmpty && other.isEmpty }

    /// Puts these into a record as the file's (`from: tag`): every fact from the file's tags is replaced, a fact from
    /// any other source is kept where it ranks higher, and `file.other_tags` is these tags.
    public func apply(to t: inout CrateTrack) {
        t.ident.dropFacts { $0 == SongFacts.Origin.tag }
        for (name, values) in facts { t.ident.offer(name, .init(values, from: SongFacts.Origin.tag)) }
        // Kept when the file's tags gave a fact, another tag, or something left out; the formats alone say nothing.
        t.file.otherTags = other.tags.isEmpty && other.leftOut.isEmpty && facts.isEmpty ? nil : other
    }

    /// The facts of the file at `url`; empty when it has none or cannot be read.
    public static func read(_ url: URL) -> FileFacts {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return FileFacts() }
        defer { try? handle.close() }
        let file = TagFile(handle: handle)
        guard let head = file.read(at: 0, count: 12), head.count >= 12 else { return FileFacts() }
        let b = [UInt8](head)
        func ascii(_ at: Int, _ s: String) -> Bool { Array(b[at..<(at + s.utf8.count)]) == Array(s.utf8) }
        var c = Collector()
        if ascii(0, "RIFF") && ascii(8, "WAVE") {
            riff(file, bigEndian: false, into: &c)
        } else if ascii(0, "FORM") && (ascii(8, "AIFF") || ascii(8, "AIFC")) {
            riff(file, bigEndian: true, into: &c)
        } else if ascii(4, "ftyp") {
            mp4(file, into: &c)
        } else {
            var offset = 0
            if ascii(0, "ID3"), let size = ID3.tagSize(b) {
                if let tag = file.read(at: 0, count: size) { id3(tag, into: &c) }
                offset = size
            }
            if let marker = file.read(at: offset, count: 4), marker.elementsEqual("fLaC".utf8) {
                flac(file, at: offset + 4, into: &c)
            } else {
                id3v1(file, into: &c)
            }
        }
        return c.finish()
    }

    // MARK: gathering, and the bounds

    /// What a reader found, in the order found, made into facts and other tags by `finish`.
    struct Collector {
        var known: [(String, [String])] = []
        var other: [(String, [String])] = []
        var formats: [String] = []
        var leftOut: [String: Int] = [:]
        /// The file's own artist tag, to tell whether the release's artist differs.
        var artist: String?
        /// ID3v2.3's year and day-and-month, joined into a date at the end.
        var id3Year: String?, id3DayMonth: String?

        mutating func format(_ f: String) { if !formats.contains(f) { formats.append(f) } }
        mutating func fact(_ name: String, _ values: [String]) { known.append((name, values)) }
        mutating func fact(_ name: String, _ value: String?) { if let value { known.append((name, [value])) } }
        mutating func tag(_ name: String, _ values: [String]) { other.append((name, values)) }
        mutating func leave(_ reason: String, _ n: Int = 1) { leftOut[reason, default: 0] += n }

        /// A date as written ("1999", "1999-05-01", "1999-05-01T20:00"): its year, and the whole when it says more.
        mutating func date(_ text: String?, original: Bool = false) {
            guard let raw = text, let t = SongFacts.clean(raw) else { return }
            let digits = t.prefix(4)
            if digits.count == 4, digits.allSatisfy({ $0.isASCII && $0.isNumber }) {
                fact(original ? SongFacts.originalYear : SongFacts.year, String(digits))
                if t.count > 4 { fact(original ? SongFacts.originalDate : SongFacts.date, t) }
            } else {
                fact(original ? SongFacts.originalDate : SongFacts.date, t)
            }
        }

        /// "2", "02", "2/12": the number and the count, as plain numbers.
        mutating func numbers(_ text: String?, number: String, count: String) {
            guard let text else { return }
            let parts = text.split(separator: "/", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if let n = parts.first.flatMap({ Int($0) }), n > 0 { fact(number, String(n)) }
            if parts.count > 1, let n = Int(parts[1]), n > 0 { fact(count, String(n)) }
        }

        /// One cleaned value, or nil with the reason counted.
        mutating func value(_ v: String) -> String? {
            guard let c = SongFacts.clean(v) else {
                // Empty is nothing; anything else that is not text is data.
                if !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { leave(SongFacts.LeftOut.binary) }
                return nil
            }
            if c.utf8.count > SongFacts.maxValueBytes { leave(SongFacts.LeftOut.tooLong); return nil }
            return c
        }

        /// Values cleaned, each once, at most `maxValues`.
        mutating func values(_ vs: [String], into have: [String] = []) -> [String] {
            var out = have
            for v in vs {
                guard let c = value(v), !out.contains(c) else { continue }
                if out.count >= SongFacts.maxValues { leave(SongFacts.LeftOut.tooMany); continue }
                out.append(c)
            }
            return out
        }

        mutating func finish() -> FileFacts {
            var r = FileFacts()
            if let y = id3Year {
                // ID3v2.3: TYER "1999" and TDAT "0105" (day, month) make 1999-05-01.
                if let dm = id3DayMonth, dm.count == 4, dm.allSatisfy({ $0.isASCII && $0.isNumber }), y.count == 4 {
                    known.insert((SongFacts.date, ["\(y)-\(dm.suffix(2))-\(dm.prefix(2))"]), at: 0)
                }
            }
            for (name, vs) in known {
                if let have = r.facts[name] {
                    guard SongFacts.several.contains(name) else { continue }
                    r.facts[name] = values(vs, into: have)
                } else {
                    let kept = values(SongFacts.several.contains(name) ? vs : Array(vs.prefix(1)), into: [])
                    if !kept.isEmpty { r.facts[name] = kept }
                }
            }
            if let ra = r.facts[SongFacts.releaseArtist]?.first, let a = artist,
               ra.compare(a, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame {
                r.facts[SongFacts.releaseArtist] = nil
            }
            // The facts together within their total, in the order a window lists them.
            var factBytes = 0
            for name in SongFacts.known where r.facts[name] != nil {
                let size = SongFacts.bytes([name: r.facts[name]!])
                if factBytes + size > SongFacts.maxFactBytes { r.facts[name] = nil; leave(SongFacts.LeftOut.overTotal); continue }
                factBytes += size
            }
            // The other tags, gathered by name, then kept in name order up to the total.
            var byName: [String: [String]] = [:]
            var order: [String] = []
            for (name, vs) in other {
                guard let n = SongFacts.clean(name), n.utf8.count <= SongFacts.maxNameBytes else { leave(SongFacts.LeftOut.tooLong); continue }
                if byName[n] == nil { order.append(n) }
                byName[n] = values(vs, into: byName[n] ?? [])
            }
            var total = 0
            for n in order.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
                guard let vs = byName[n], !vs.isEmpty else { continue }
                let size = n.utf8.count + vs.reduce(0) { $0 + $1.utf8.count }
                if total + size > SongFacts.maxOtherBytes { leave(SongFacts.LeftOut.overTotal); continue }
                total += size
                r.other.tags[n] = vs
            }
            r.other.formats = formats
            r.other.leftOut = leftOut
            return r
        }
    }

    // MARK: ID3v2

    /// Frames whose meaning `SongFacts` has, by their 2.3 and 2.4 names.
    static let id3Facts: [String: String] = [
        "TALB": SongFacts.release, "TPE2": SongFacts.releaseArtist, "TPUB": SongFacts.label, "TCON": SongFacts.genre,
        "TCOM": SongFacts.composer, "TEXT": SongFacts.lyricist, "TPE4": SongFacts.remixer,
        "TOPE": SongFacts.originalArtist, "TSRC": SongFacts.isrc, "TBPM": SongFacts.bpmText, "TKEY": SongFacts.keyText,
        "GRP1": SongFacts.grouping, "TIT1": SongFacts.grouping, "TMOO": SongFacts.mood, "TIT3": SongFacts.subtitle,
        "TCMP": SongFacts.compilation, "TCOP": SongFacts.copyright, "TLAN": SongFacts.language,
    ]
    /// TXXX descriptions with a `SongFacts` meaning, lower case.
    static let describedFacts: [String: String] = [
        "catalognumber": SongFacts.catalogNumber, "catalog number": SongFacts.catalogNumber,
        "catalog #": SongFacts.catalogNumber, "catalog": SongFacts.catalogNumber, "label": SongFacts.label,
        "publisher": SongFacts.label, "barcode": SongFacts.barcode, "upc": SongFacts.barcode, "ean": SongFacts.barcode,
        "isrc": SongFacts.isrc, "mood": SongFacts.mood, "producer": SongFacts.producer, "remixer": SongFacts.remixer,
        "mixartist": SongFacts.remixer, "initialkey": SongFacts.keyText, "initial key": SongFacts.keyText,
        "key": SongFacts.keyText, "comment": SongFacts.comment, "grouping": SongFacts.grouping,
        "album artist": SongFacts.releaseArtist, "albumartist": SongFacts.releaseArtist,
        "original artist": SongFacts.originalArtist, "lyricist": SongFacts.lyricist, "language": SongFacts.language,
    ]
    /// ID3v2.2's three-letter frames by their 2.3 names, for reading them the same way (their own names are kept for
    /// the other tags).
    static let id3v22: [String: String] = [
        "TT1": "TIT1", "TT2": "TIT2", "TT3": "TIT3", "TP1": "TPE1", "TP2": "TPE2", "TP3": "TPE3", "TP4": "TPE4",
        "TCM": "TCOM", "TXT": "TEXT", "TLA": "TLAN", "TCO": "TCON", "TAL": "TALB", "TPA": "TPOS", "TRK": "TRCK",
        "TRC": "TSRC", "TYE": "TYER", "TDA": "TDAT", "TIM": "TIME", "TRD": "TRDA", "TMT": "TMED", "TFT": "TFLT",
        "TBP": "TBPM", "TCR": "TCOP", "TPB": "TPUB", "TEN": "TENC", "TSS": "TSSE", "TOF": "TOFN", "TLE": "TLEN",
        "TSI": "TSIZ", "TDY": "TDLY", "TKE": "TKEY", "TOT": "TOAL", "TOA": "TOPE", "TOL": "TOLY", "TOR": "TORY",
        "TXX": "TXXX", "WAF": "WOAF", "WAR": "WOAR", "WAS": "WOAS", "WCM": "WCOM", "WCP": "WCOP", "WPB": "WPUB",
        "WXX": "WXXX", "COM": "COMM", "PIC": "APIC", "ULT": "USLT", "TCP": "TCMP", "GP1": "GRP1",
    ]
    /// Clean or dirty stated as data (D39; research AC, section 4): iTunes' advisory (`ITUNESADVISORY`: 1 explicit,
    /// 2 clean) and the `EXPLICIT` some taggers write, by the tag's name and its value.
    static func advisory(_ name: String, _ value: String?) -> String? {
        let n = name.uppercased().trimmingCharacters(in: .whitespaces)
        guard ["ITUNESADVISORY", "EXPLICIT", "CONTENTADVISORY", "PARENTAL ADVISORY", "PARENTALADVISORY"].contains(n),
              let v = value, let l = VersionWords.lyrics(advisory: v) else { return nil }
        return l.rawValue
    }

    /// Descriptions (lower case, by their start) of text that a program keeps for itself.
    static let privatePrefixes = ["itun", "serato", "traktor", "songs-db", "rekordbox", "musicmatch", "mediajukebox"]
    static func isPrivate(_ name: String) -> Bool {
        let n = name.lowercased()
        return privatePrefixes.contains { n.hasPrefix($0) }
    }

    /// Every frame of a whole ID3v2 tag (header included).
    static func id3(_ tag: Data, into c: inout Collector) {
        let all = [UInt8](tag)
        guard let size = ID3.tagSize(all), all.count >= 10 else { return }
        let version = all[3], flags = all[5]
        c.format("id3v2.\(version)")
        var body = Array(all[10..<min(size, all.count)])
        if version == 4 && flags & 0x10 != 0 && body.count >= 10 { body.removeLast(10) }
        if version < 4 && flags & 0x80 != 0 { body = ID3.resynchronised(body) }
        var r = ByteCursor(Data(body))
        if version >= 3 && flags & 0x40 != 0 {
            guard let e = r.take(4) else { return }
            let n = version == 4 ? ID3.synchsafe(e[0], e[1], e[2], e[3]) - 4
                : Int(e[0]) << 24 | Int(e[1]) << 16 | Int(e[2]) << 8 | Int(e[3])
            guard n >= 0, r.skip(n) else { return }
        }
        while r.remaining > 0 {
            let idLength = version == 2 ? 3 : 4
            guard let head = r.take(version == 2 ? 6 : 10), head[0] != 0 else { break }
            let own = String(decoding: head[0..<idLength], as: UTF8.self)
            guard own.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else { break }
            let size: Int
            switch version {
            case 2: size = Int(head[3]) << 16 | Int(head[4]) << 8 | Int(head[5])
            case 3: size = Int(head[4]) << 24 | Int(head[5]) << 16 | Int(head[6]) << 8 | Int(head[7])
            default: size = ID3.synchsafe(head[4], head[5], head[6], head[7])
            }
            guard size >= 0, var data = r.take(size) else { break }
            let id = version == 2 ? (id3v22[own] ?? own) : own
            if id == "APIC" { c.leave(SongFacts.LeftOut.picture); continue }
            if version >= 3 {
                let format = head[9]
                if version == 3 {
                    if format & 0xC0 != 0 { c.leave(SongFacts.LeftOut.binary); continue }  // compressed or encrypted
                    if format & 0x20 != 0 { data = Array(data.dropFirst()) }
                } else {
                    if format & 0x0C != 0 { c.leave(SongFacts.LeftOut.binary); continue }
                    if format & 0x40 != 0 { data = Array(data.dropFirst()) }
                    if format & 0x02 != 0 || flags & 0x80 != 0 { data = ID3.resynchronised(data) }
                    if format & 0x01 != 0 { data = Array(data.dropFirst(4)) }
                }
            }
            frame(id: id, own: own, data, version: version, into: &c)
        }
    }

    /// One frame, by its 2.3 or 2.4 name (`id`) and its name in the file (`own`).
    static func frame(id: String, own: String, _ data: [UInt8], version: UInt8, into c: inout Collector) {
        switch id {
        case "TIT2": return  // the title: the record's own
        case "TPE1": c.artist = c.artist ?? textValues(data).first; return
        case "TXXX":
            guard let (d, vs) = described(data, skippingLanguage: false) else { return }
            if let l = advisory(d, vs.first) { c.fact(SongFacts.lyrics, l); return }
            if isPrivate(d) { c.leave(SongFacts.LeftOut.private); return }
            let key = d.lowercased().trimmingCharacters(in: .whitespaces)
            if let name = describedFacts[key] { c.fact(name, vs) }
            else if key == "originalyear" || key == "original year" { c.date(vs.first, original: true) }
            else if key == "originaldate" || key == "original release date" { c.date(vs.first, original: true) }
            else { c.tag("\(own):\(d)", vs) }
        case "COMM", "USLT":
            guard let (d, vs) = described(data, skippingLanguage: true) else { return }
            if isPrivate(d) { c.leave(SongFacts.LeftOut.private); return }
            if id == "COMM" && d.isEmpty { c.fact(SongFacts.comment, vs) }
            else { c.tag(d.isEmpty ? own : "\(own):\(d)", vs) }
        case "WXXX":
            guard let (d, vs) = described(data, skippingLanguage: false, urlText: true) else { return }
            c.tag(d.isEmpty ? own : "\(own):\(d)", vs)
        case "TDRC": c.date(textValues(data).first)
        case "TDOR": c.date(textValues(data).first, original: true)
        case "TORY": c.date(textValues(data).first, original: true)
        case "TYER":
            if let y = textValues(data).first.flatMap(SongFacts.clean) { c.id3Year = c.id3Year ?? y; c.date(y) }
        case "TDAT": c.id3DayMonth = c.id3DayMonth ?? textValues(data).first.flatMap(SongFacts.clean)
        case "TRCK": c.numbers(textValues(data).first, number: SongFacts.trackNumber, count: SongFacts.trackCount)
        case "TPOS": c.numbers(textValues(data).first, number: SongFacts.discNumber, count: SongFacts.discCount)
        case "TCON": c.fact(SongFacts.genre, genres(textValues(data), id3: true))
        case "TIPL", "IPLS":
            // Pairs of role and name: a producer or a remixer is a fact; the rest stay as written.
            let vs = textValues(data)
            var rest: [String] = []
            var i = 0
            while i + 1 < vs.count {
                switch vs[i].lowercased() {
                case "producer": c.fact(SongFacts.producer, [vs[i + 1]])
                case "mix", "remixer", "dj-mix": c.fact(SongFacts.remixer, [vs[i + 1]])
                default: rest.append("\(vs[i]): \(vs[i + 1])")
                }
                i += 2
            }
            if !rest.isEmpty { c.tag(own, rest) }
        default:
            if let name = id3Facts[id] { c.fact(name, textValues(data)); return }
            if id.hasPrefix("T") { c.tag(own, textValues(data)); return }
            if id.hasPrefix("W") { c.tag(own, [latin1([0] + data)]); return }  // a URL: Latin-1, no encoding byte
            c.leave(SongFacts.LeftOut.binary)
        }
    }

    /// A frame with a description before its text (TXXX, WXXX; COMM and USLT after a language): the description
    /// and the values. A URL after a WXXX description is Latin-1 whatever the frame's encoding.
    static func described(_ data: [UInt8], skippingLanguage: Bool, urlText: Bool = false) -> (String, [String])? {
        guard let encoding = data.first else { return nil }
        var body = Array(data.dropFirst())
        if skippingLanguage { guard body.count >= 3 else { return nil }; body.removeFirst(3) }
        let wide = encoding == 1 || encoding == 2
        var end: Int? = nil
        var i = 0
        while i < body.count {
            if wide {
                if i + 1 < body.count && body[i] == 0 && body[i + 1] == 0 { end = i; break }
                i += 2
            } else {
                if body[i] == 0 { end = i; break }
                i += 1
            }
        }
        guard let end else { return nil }
        let description = textValues([encoding] + body[..<end]).first ?? ""
        let rest = Array(body[(end + (wide ? 2 : 1))...])
        if urlText { return (description, [latin1([0] + rest)]) }
        var textBytes = rest
        if encoding == 1, rest.count >= 2, !(rest[0] == 0xFF && rest[1] == 0xFE) && !(rest[0] == 0xFE && rest[1] == 0xFF),
           body.count >= 2, (body[0] == 0xFF && body[1] == 0xFE) || (body[0] == 0xFE && body[1] == 0xFF) {
            textBytes = Array(body[0..<2]) + rest
        }
        return (description, textValues([encoding] + textBytes))
    }

    /// A text frame's values: an encoding byte (0 Latin-1, 1 UTF-16 with a byte-order mark, 2 UTF-16 big-endian, 3
    /// UTF-8), then the text, several values separated by NUL (each UTF-16 value may carry its own byte-order mark).
    static func textValues(_ data: [UInt8]) -> [String] {
        guard let encoding = data.first else { return [] }
        let bytes = Array(data.dropFirst())
        var out: [String] = []
        switch encoding {
        case 1, 2:
            var bigEndian = encoding == 2
            var units: [UInt16] = []
            var i = 0
            func flush() { out.append(String(decoding: units, as: UTF16.self)); units = [] }
            var atStart = true
            while i + 1 < bytes.count {
                if atStart && encoding == 1 {
                    if bytes[i] == 0xFE && bytes[i + 1] == 0xFF { bigEndian = true; i += 2; atStart = false; continue }
                    if bytes[i] == 0xFF && bytes[i + 1] == 0xFE { bigEndian = false; i += 2; atStart = false; continue }
                }
                atStart = false
                let u = bigEndian ? UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1]) : UInt16(bytes[i + 1]) << 8 | UInt16(bytes[i])
                i += 2
                if u == 0 { flush(); atStart = true } else { units.append(u) }
            }
            if !units.isEmpty { flush() }
        default:
            for part in bytes.split(separator: 0, omittingEmptySubsequences: false) {
                out.append(encoding == 3 ? String(decoding: part, as: UTF8.self) : latin1([0] + part))
            }
        }
        while let last = out.last, last.isEmpty { out.removeLast() }
        return out.filter { !$0.isEmpty }
    }

    /// Bytes as Windows-1252 (the Latin-1 most taggers write), after a leading encoding byte.
    static func latin1(_ data: [UInt8]) -> String {
        var s = String.UnicodeScalarView()
        for b in data.dropFirst() {
            if b == 0 { break }
            if (0x80...0x9F).contains(b), let u = cp1252[Int(b - 0x80)] { s.append(u) }
            else { s.append(Unicode.Scalar(b)) }
        }
        return String(s)
    }
    /// Windows-1252's characters at 0x80 to 0x9F (nil where it has none).
    static let cp1252: [Unicode.Scalar?] = [
        "\u{20AC}", nil, "\u{201A}", "\u{0192}", "\u{201E}", "\u{2026}", "\u{2020}", "\u{2021}", "\u{02C6}", "\u{2030}",
        "\u{0160}", "\u{2039}", "\u{0152}", nil, "\u{017D}", nil, nil, "\u{2018}", "\u{2019}", "\u{201C}", "\u{201D}",
        "\u{2022}", "\u{2013}", "\u{2014}", "\u{02DC}", "\u{2122}", "\u{0161}", "\u{203A}", "\u{0153}", nil, "\u{017E}",
        "\u{0178}",
    ]
    /// UTF-8 text, or Windows-1252 when the bytes are not valid UTF-8.
    static func text(_ bytes: some Collection<UInt8>) -> String {
        let a = Array(bytes)
        return String(bytes: a, encoding: .utf8) ?? latin1([0] + a)
    }

    /// Genres as written: several values, each split at ";"; in ID3, "(13)", "(13)Pop", a bare number, "(RX)" remix
    /// and "(CR)" cover read by the ID3v1 list.
    static func genres(_ values: [String], id3: Bool = false) -> [String] {
        var out: [String] = []
        for v in values {
            for part in v.split(separator: ";").map({ $0.trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
                guard id3 else { out.append(part); continue }
                var rest = Substring(part)
                var any = false
                while rest.hasPrefix("("), !rest.hasPrefix("(("), let close = rest.firstIndex(of: ")") {
                    let code = rest[rest.index(after: rest.startIndex)..<close]
                    if code == "RX" { out.append("Remix") } else if code == "CR" { out.append("Cover") }
                    else if let n = Int(code), let g = id3v1Genre(n) { out.append(g) }
                    rest = rest[rest.index(after: close)...]
                    any = true
                }
                if rest.hasPrefix("((") { rest = rest.dropFirst() }
                let tail = rest.trimmingCharacters(in: .whitespaces)
                if !tail.isEmpty {
                    if let n = Int(tail), let g = id3v1Genre(n) { out.append(g) } else { out.append(tail) }
                } else if !any { out.append(part) }
            }
        }
        return out
    }

    /// The ID3v1 genre list (0 to 79 from the standard, 80 to 191 Winamp's), by number. One name in Winamp's list is
    /// a slur and is not given: its number stays as written.
    static func id3v1Genre(_ n: Int) -> String? {
        guard n >= 0, n < id3v1Genres.count, n != 133 else { return nil }
        return id3v1Genres[n]
    }
    static let id3v1Genres = [
        "Blues", "Classic Rock", "Country", "Dance", "Disco", "Funk", "Grunge", "Hip-Hop", "Jazz", "Metal", "New Age",
        "Oldies", "Other", "Pop", "R&B", "Rap", "Reggae", "Rock", "Techno", "Industrial", "Alternative", "Ska",
        "Death Metal", "Pranks", "Soundtrack", "Euro-Techno", "Ambient", "Trip-Hop", "Vocal", "Jazz+Funk", "Fusion",
        "Trance", "Classical", "Instrumental", "Acid", "House", "Game", "Sound Clip", "Gospel", "Noise", "Alternative Rock",
        "Bass", "Soul", "Punk", "Space", "Meditative", "Instrumental Pop", "Instrumental Rock", "Ethnic", "Gothic",
        "Darkwave", "Techno-Industrial", "Electronic", "Pop-Folk", "Eurodance", "Dream", "Southern Rock", "Comedy",
        "Cult", "Gangsta", "Top 40", "Christian Rap", "Pop/Funk", "Jungle", "Native American", "Cabaret", "New Wave",
        "Psychedelic", "Rave", "Showtunes", "Trailer", "Lo-Fi", "Tribal", "Acid Punk", "Acid Jazz", "Polka", "Retro",
        "Musical", "Rock & Roll", "Hard Rock", "Folk", "Folk-Rock", "National Folk", "Swing", "Fast Fusion", "Bebop",
        "Latin", "Revival", "Celtic", "Bluegrass", "Avantgarde", "Gothic Rock", "Progressive Rock", "Psychedelic Rock",
        "Symphonic Rock", "Slow Rock", "Big Band", "Chorus", "Easy Listening", "Acoustic", "Humour", "Speech", "Chanson",
        "Opera", "Chamber Music", "Sonata", "Symphony", "Booty Bass", "Primus", "Porn Groove", "Satire", "Slow Jam",
        "Club", "Tango", "Samba", "Folklore", "Ballad", "Power Ballad", "Rhythmic Soul", "Freestyle", "Duet",
        "Punk Rock", "Drum Solo", "A Cappella", "Euro-House", "Dance Hall", "Goa", "Drum & Bass", "Club-House",
        "Hardcore", "Terror", "Indie", "BritPop", "", "Polsk Punk", "Beat", "Christian Gangsta Rap", "Heavy Metal",
        "Black Metal", "Crossover", "Contemporary Christian", "Christian Rock", "Merengue", "Salsa", "Thrash Metal",
        "Anime", "JPop", "Synthpop", "Abstract", "Art Rock", "Baroque", "Bhangra", "Big Beat", "Breakbeat", "Chillout",
        "Downtempo", "Dub", "EBM", "Eclectic", "Electro", "Electroclash", "Emo", "Experimental", "Garage", "Global",
        "IDM", "Illbient", "Industro-Goth", "Jam Band", "Krautrock", "Leftfield", "Lounge", "Math Rock", "New Romantic",
        "Nu-Breakz", "Post-Punk", "Post-Rock", "Psytrance", "Shoegaze", "Space Rock", "Trop Rock", "World Music",
        "Neoclassical", "Audiobook", "Audio Theatre", "Neue Deutsche Welle", "Podcast", "Indie Rock", "G-Funk",
        "Dubstep", "Garage Rock", "Psybient",
    ]

    // MARK: ID3v1

    static func id3v1(_ file: TagFile, into c: inout Collector) {
        guard let size = file.size, size >= 128, let d = file.read(at: size - 128, count: 128) else { return }
        let b = [UInt8](d)
        guard b[0] == 0x54, b[1] == 0x41, b[2] == 0x47 else { return }
        c.format("id3v1")
        func text(_ r: Range<Int>) -> String { latin1([0] + b[r]) }
        c.artist = c.artist ?? SongFacts.clean(text(33..<63))
        c.fact(SongFacts.release, text(63..<93))
        c.date(text(93..<97))
        let track = b[125] == 0 && b[126] != 0 ? Int(b[126]) : nil
        c.fact(SongFacts.comment, text(97..<(track == nil ? 127 : 125)))
        if let track { c.fact(SongFacts.trackNumber, String(track)) }
        if let g = id3v1Genre(Int(b[127])) { c.fact(SongFacts.genre, g) }
    }

    // MARK: FLAC and Vorbis comments

    static let vorbisFacts: [String: String] = [
        "ALBUM": SongFacts.release, "ALBUMARTIST": SongFacts.releaseArtist, "ALBUM ARTIST": SongFacts.releaseArtist,
        "ALBUM_ARTIST": SongFacts.releaseArtist, "LABEL": SongFacts.label, "ORGANIZATION": SongFacts.label,
        "PUBLISHER": SongFacts.label, "CATALOGNUMBER": SongFacts.catalogNumber, "CATALOG NUMBER": SongFacts.catalogNumber,
        "CATALOG": SongFacts.catalogNumber, "LABELNO": SongFacts.catalogNumber, "COMPOSER": SongFacts.composer,
        "LYRICIST": SongFacts.lyricist, "REMIXER": SongFacts.remixer, "MIXARTIST": SongFacts.remixer,
        "PRODUCER": SongFacts.producer, "ORIGINALARTIST": SongFacts.originalArtist, "ISRC": SongFacts.isrc,
        "BARCODE": SongFacts.barcode, "UPC": SongFacts.barcode, "EAN": SongFacts.barcode, "BPM": SongFacts.bpmText,
        "TEMPO": SongFacts.bpmText, "INITIALKEY": SongFacts.keyText, "KEY": SongFacts.keyText,
        "INITIAL KEY": SongFacts.keyText, "COMMENT": SongFacts.comment, "DESCRIPTION": SongFacts.comment,
        "GROUPING": SongFacts.grouping, "CONTENTGROUP": SongFacts.grouping, "MOOD": SongFacts.mood,
        "SUBTITLE": SongFacts.subtitle, "COMPILATION": SongFacts.compilation, "COPYRIGHT": SongFacts.copyright,
        "LANGUAGE": SongFacts.language, "TRACKTOTAL": SongFacts.trackCount, "TOTALTRACKS": SongFacts.trackCount,
        "DISCTOTAL": SongFacts.discCount, "TOTALDISCS": SongFacts.discCount,
    ]

    static func flac(_ file: TagFile, at start: Int, into c: inout Collector) {
        var at = start
        for _ in 0..<128 {
            guard let h = file.read(at: at, count: 4), h.count == 4 else { break }
            let b = [UInt8](h)
            let last = b[0] & 0x80 != 0, type = b[0] & 0x7F
            let size = Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
            if type == 4, let block = file.read(at: at + 4, count: size) { vorbis(block, into: &c) }
            if type == 6 { c.leave(SongFacts.LeftOut.picture) }
            if last { break }
            at += 4 + size
        }
    }

    /// A Vorbis comment block: vendor string, then `KEY=value` strings, all lengths 32-bit little-endian.
    static func vorbis(_ block: Data, into c: inout Collector) {
        var r = ByteCursor(block)
        guard let vendor = r.u32le(), r.skip(Int(vendor)), let count = r.u32le() else { return }
        c.format("vorbis")
        for _ in 0..<min(Int(count), 10_000) {
            guard let n = r.u32le(), let bytes = r.take(Int(n)) else { break }
            guard let eq = bytes.firstIndex(of: 0x3D) else { continue }
            let key = String(decoding: bytes[..<eq], as: UTF8.self)
            let upper = key.uppercased()
            if upper == "METADATA_BLOCK_PICTURE" || upper == "COVERART" { c.leave(SongFacts.LeftOut.picture); continue }
            if upper == "COVERARTMIME" { continue }
            if let l = advisory(upper, text(bytes[(eq + 1)...])) { c.fact(SongFacts.lyrics, l); continue }
            if isPrivate(upper) { c.leave(SongFacts.LeftOut.private); continue }
            let value = text(bytes[(eq + 1)...])
            switch upper {
            case "TITLE": continue
            case "ARTIST": c.artist = c.artist ?? SongFacts.clean(value)
            case "DATE", "YEAR": c.date(value)
            case "ORIGINALDATE", "ORIGINALYEAR": c.date(value, original: true)
            case "TRACKNUMBER": c.numbers(value, number: SongFacts.trackNumber, count: SongFacts.trackCount)
            case "DISCNUMBER": c.numbers(value, number: SongFacts.discNumber, count: SongFacts.discCount)
            case "GENRE": c.fact(SongFacts.genre, genres([value]))
            case "TRACKTOTAL", "TOTALTRACKS", "DISCTOTAL", "TOTALDISCS":
                if let n = Int(value.trimmingCharacters(in: .whitespaces)), n > 0 { c.fact(vorbisFacts[upper]!, String(n)) }
            default:
                if let name = vorbisFacts[upper] { c.fact(name, [value]) } else { c.tag(key, [value]) }
            }
        }
    }

    // MARK: WAV and AIFF

    static let infoFacts: [String: String] = [
        "IPRD": SongFacts.release, "ICMT": SongFacts.comment, "ICOP": SongFacts.copyright, "ILNG": SongFacts.language,
    ]

    /// The chunks of a WAV (little-endian sizes) or AIFF (big-endian) file: ID3 first, then the container's own text.
    static func riff(_ file: TagFile, bigEndian: Bool, into c: inout Collector) {
        var at = 12
        var id3Tag: Data? = nil
        var info: [UInt8]? = nil
        var aiffText: [(String, [UInt8])] = []
        for _ in 0..<64 {
            guard let h = file.read(at: at, count: 8), h.count == 8 else { break }
            let b = [UInt8](h)
            let id = String(decoding: b[0..<4], as: UTF8.self)
            let size = bigEndian
                ? Int(b[4]) << 24 | Int(b[5]) << 16 | Int(b[6]) << 8 | Int(b[7])
                : Int(b[7]) << 24 | Int(b[6]) << 16 | Int(b[5]) << 8 | Int(b[4])
            if id == "id3 " || id == "ID3 " {
                if size <= ID3.maxTagBytes, let tag = file.read(at: at + 8, count: size) { id3Tag = tag }
            } else if id == "LIST", !bigEndian, size >= 4, size <= 1 << 20, let list = file.read(at: at + 8, count: size),
                      list.prefix(4).elementsEqual("INFO".utf8) {
                info = [UInt8](list.dropFirst(4))
            } else if bigEndian, ["NAME", "AUTH", "(c) ", "ANNO"].contains(id), size <= 1 << 16,
                      let d = file.read(at: at + 8, count: size) {
                aiffText.append((id, [UInt8](d)))
            }
            at += 8 + size + (size & 1)
        }
        if let id3Tag { id3(id3Tag, into: &c) }
        if let info { listInfo(info, into: &c) }
        if !aiffText.isEmpty {
            c.format("aiff-text")
            for (id, d) in aiffText {
                let v = latin1([0] + d)
                switch id {
                case "NAME": continue
                case "AUTH": c.artist = c.artist ?? SongFacts.clean(v)
                case "(c) ": c.fact(SongFacts.copyright, v)
                default: c.fact(SongFacts.comment, v)
                }
            }
        }
    }

    /// A RIFF LIST INFO chunk's items: four letters, a 32-bit little-endian size, the text (NUL-terminated, padded to
    /// an even length).
    static func listInfo(_ b: [UInt8], into c: inout Collector) {
        c.format("riff-info")
        var at = 0
        while at + 8 <= b.count {
            let id = String(decoding: b[at..<(at + 4)], as: UTF8.self)
            let n = Int(b[at + 4]) | Int(b[at + 5]) << 8 | Int(b[at + 6]) << 16 | Int(b[at + 7]) << 24
            guard n >= 0, at + 8 + n <= b.count else { break }
            let value = text(b[(at + 8)..<(at + 8 + n)].prefix { $0 != 0 })
            switch id {
            case "INAM": break
            case "IART": c.artist = c.artist ?? SongFacts.clean(value)
            case "ICRD": c.date(value)
            case "IGNR": c.fact(SongFacts.genre, genres([value]))
            case "ITRK", "IPRT": c.numbers(value, number: SongFacts.trackNumber, count: SongFacts.trackCount)
            default:
                if let name = infoFacts[id] { c.fact(name, value) } else { c.tag(id, [value]) }
            }
            at += 8 + n + (n & 1)
        }
    }

    // MARK: MP4

    static let mp4Facts: [String: String] = [
        "\u{A9}alb": SongFacts.release, "aART": SongFacts.releaseArtist, "\u{A9}wrt": SongFacts.composer,
        "\u{A9}cmt": SongFacts.comment, "\u{A9}grp": SongFacts.grouping, "cprt": SongFacts.copyright,
    ]
    /// iTunes' free-form names (`----:com.apple.iTunes:<name>`), upper case, with a `SongFacts` meaning.
    static let freeFormFacts: [String: String] = [
        "LABEL": SongFacts.label, "PUBLISHER": SongFacts.label, "CATALOGNUMBER": SongFacts.catalogNumber,
        "ISRC": SongFacts.isrc, "BARCODE": SongFacts.barcode, "UPC": SongFacts.barcode, "INITIALKEY": SongFacts.keyText,
        "KEY": SongFacts.keyText, "REMIXER": SongFacts.remixer, "MIXARTIST": SongFacts.remixer,
        "PRODUCER": SongFacts.producer, "LYRICIST": SongFacts.lyricist, "MOOD": SongFacts.mood,
        "SUBTITLE": SongFacts.subtitle, "LANGUAGE": SongFacts.language, "ORIGINALARTIST": SongFacts.originalArtist,
    ]

    /// An MP4's `moov` box, found among the top-level boxes (it may come after the audio), and its `ilst`.
    static func mp4(_ file: TagFile, into c: inout Collector) {
        guard let (m, ilst) = mp4Items(file) else { return }
        c.format("mp4")
        for (type, body) in boxes(m, ilst) { mp4Item(type: type, m, body, into: &c) }
    }

    /// The bytes of an MP4's `moov` box and where its list of tags (`ilst`) is in them; nil when the file has none.
    /// Shared with the cover reader (`CoverReader`), which looks for `covr` in the same list.
    static func mp4Items(_ file: TagFile) -> (moov: [UInt8], ilst: Range<Int>)? {
        guard let size = file.size else { return nil }
        var at = 0
        for _ in 0..<64 {
            guard at + 8 <= size, let h = file.read(at: at, count: 8) else { return nil }
            let b = [UInt8](h)
            var boxSize = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
            var header = 8
            if boxSize == 1 {
                guard let big = file.read(at: at + 8, count: 8) else { return nil }
                boxSize = big.reduce(0) { $0 << 8 | Int($1) }; header = 16
            } else if boxSize == 0 { boxSize = size - at }
            guard boxSize >= header else { return nil }
            if b[4...7].elementsEqual("moov".utf8) {
                guard boxSize - header <= ID3.maxTagBytes, let moov = file.read(at: at + header, count: boxSize - header) else { return nil }
                let m = [UInt8](moov)
                let meta = child(m, 0..<m.count, "udta").flatMap { child(m, $0, "meta") } ?? child(m, 0..<m.count, "meta")
                guard let meta, meta.count >= 4 else { return nil }
                // `meta` is a full box: four bytes of version and flags before its children.
                guard let ilst = child(m, (meta.lowerBound + 4)..<meta.upperBound, "ilst") else { return nil }
                return (m, ilst)
            }
            at += boxSize
        }
        return nil
    }

    static func boxes(_ m: [UInt8], _ range: Range<Int>) -> [(String, Range<Int>)] {
        var out: [(String, Range<Int>)] = []
        var o = range.lowerBound
        while o + 8 <= range.upperBound {
            var size = Int(m[o]) << 24 | Int(m[o + 1]) << 16 | Int(m[o + 2]) << 8 | Int(m[o + 3])
            var header = 8
            if size == 1 {
                guard o + 16 <= range.upperBound else { break }
                size = m[(o + 8)..<(o + 16)].reduce(0) { $0 << 8 | Int($1) }; header = 16
            } else if size == 0 { size = range.upperBound - o }
            guard size >= header else { break }
            let end = o + min(size, range.upperBound - o)
            out.append((String(m[(o + 4)..<(o + 8)].map { Character(Unicode.Scalar($0)) }), (o + header)..<end))
            o = end
        }
        return out
    }

    static func child(_ m: [UInt8], _ range: Range<Int>, _ name: String) -> Range<Int>? {
        boxes(m, range).first { $0.0 == name }?.1
    }

    /// One item of `ilst`: its `data` boxes (type 1 UTF-8, 2 UTF-16, 21 a signed number, 0 the number atoms' own
    /// layout, 13 and 14 pictures), and for `----` its `mean` and `name`.
    static func mp4Item(type: String, _ m: [UInt8], _ body: Range<Int>, into c: inout Collector) {
        var name = type
        var datas: [(Int, ArraySlice<UInt8>)] = []
        for (t, r) in boxes(m, body) {
            switch t {
            case "mean", "name":
                guard r.count >= 4 else { continue }
                let s = String(decoding: m[(r.lowerBound + 4)..<r.upperBound], as: UTF8.self)
                name = t == "mean" ? "----:\(s)" : "\(name):\(s)"
            case "data":
                guard r.count >= 8 else { continue }
                let kind = Int(m[r.lowerBound + 1]) << 16 | Int(m[r.lowerBound + 2]) << 8 | Int(m[r.lowerBound + 3])
                datas.append((kind, m[(r.lowerBound + 8)..<r.upperBound]))
            default: break
            }
        }
        if type == "covr" { c.leave(SongFacts.LeftOut.picture, max(1, datas.count)); return }
        func number(_ d: ArraySlice<UInt8>) -> Int? {
            guard (1...8).contains(d.count) else { return nil }
            return d.reduce(0) { $0 << 8 | Int($1) }
        }
        var texts: [String] = []
        for (kind, d) in datas {
            switch kind {
            case 1: texts.append(String(decoding: d, as: UTF8.self))
            case 2:
                var units: [UInt16] = []
                var i = d.startIndex
                while i + 1 < d.endIndex { units.append(UInt16(d[i]) << 8 | UInt16(d[i + 1])); i += 2 }
                texts.append(String(decoding: units, as: UTF16.self))
            case 0, 21:
                let a = Array(d)
                switch type {
                case "trkn", "disk":
                    guard a.count >= 6 else { continue }
                    let n = Int(a[2]) << 8 | Int(a[3]), of = Int(a[4]) << 8 | Int(a[5])
                    let (num, cnt) = type == "trkn" ? (SongFacts.trackNumber, SongFacts.trackCount)
                        : (SongFacts.discNumber, SongFacts.discCount)
                    if n > 0 { c.fact(num, String(n)) }
                    if of > 0 { c.fact(cnt, String(of)) }
                case "tmpo": if let n = number(d), n > 0 { c.fact(SongFacts.bpmText, String(n)) }
                case "cpil": if let n = number(d) { c.fact(SongFacts.compilation, String(n)) }
                case "rtng": if let n = number(d), let l = VersionWords.lyrics(advisory: String(n)) { c.fact(SongFacts.lyrics, l.rawValue) }
                case "gnre": if let n = number(d), let g = id3v1Genre(n - 1) { c.fact(SongFacts.genre, g) }
                default: c.leave(SongFacts.LeftOut.binary)
                }
            case 13, 14, 27: c.leave(SongFacts.LeftOut.picture)
            default: c.leave(SongFacts.LeftOut.binary)
            }
        }
        guard !texts.isEmpty else { return }
        if name.hasPrefix("----:") {
            let short = String(name.split(separator: ":").last ?? "")
            if let l = advisory(short, texts.first) { c.fact(SongFacts.lyrics, l); return }
            if isPrivate(short) || name.lowercased().contains("serato") || name.lowercased().contains("traktor") {
                c.leave(SongFacts.LeftOut.private); return
            }
            let upper = short.uppercased()
            if let f = freeFormFacts[upper] { c.fact(f, texts) }
            else if upper == "ORIGINALDATE" || upper == "ORIGINALYEAR" { c.date(texts.first, original: true) }
            else { c.tag(name, texts) }
            return
        }
        switch type {
        case "\u{A9}nam": return
        case "\u{A9}ART": c.artist = c.artist ?? texts.first.flatMap(SongFacts.clean)
        case "\u{A9}day": c.date(texts.first)
        case "\u{A9}gen": c.fact(SongFacts.genre, genres(texts))
        default:
            if let f = mp4Facts[type] { c.fact(f, texts) } else { c.tag(type, texts) }
        }
    }
}
