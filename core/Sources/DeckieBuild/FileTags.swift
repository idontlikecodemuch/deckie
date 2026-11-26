import Foundation

/// The few tags of an audio file the builder reads: its tempo tag (for `--bpm-tags`), title, artist, album, track
/// number, the key a DJ's program wrote, and the comment (where Mixed In Key may write the key). Read from an ID3v2 tag
/// (versions 2.2 to 2.4: TBPM, TIT2, TPE1, TALB, TRCK, TKEY, COMM, and TXXX frames named INITIALKEY, KEY or COMMENT, with their
/// 2.2 names) at the start of the file (MP3, FLAC or AAC with ID3 in front) or in a WAV or AIFF file's `id3 ` chunk;
/// from a FLAC file's Vorbis comment (BPM, TITLE, ARTIST, ALBUM, TRACKNUMBER, INITIALKEY or KEY, COMMENT or
/// DESCRIPTION); from a WAV file's LIST INFO chunk (INAM, IART, IPRD, ITRK, ICMT; its IKEY is "keywords", not a
/// musical key, and is not read); from an MP4's (`.m4a`, `.mp4`, `.m4b`) list of tags in `moov/udta/meta/ilst` (©nam,
/// ©ART, ©alb, trkn, tmpo, ©cmt, and iTunes' free-form `----:com.apple.iTunes:` atoms named INITIALKEY, KEY or INITIAL
/// KEY); and from an MP3's ID3v1 tag at its end, for what the ID3v2 tag does not have. The key is kept as written
/// (`key`): `KeyNotation` reads it. Nothing is read but the tags, and a tag that does not hold together gives nothing
/// rather than an error.
public struct FileTags: Codable, Equatable, Sendable {
    public var bpm: Double?
    public var title: String?
    public var artist: String?
    public var album: String?
    /// The track number tag's number ("2", "02" or "2/12" give 2).
    public var trackNumber: Int?
    /// The key tag as written (TKEY, INITIALKEY): `Am`, `8A`, `1m`, ...
    public var key: String?
    public var comment: String?

    public init(bpm: Double? = nil, title: String? = nil, artist: String? = nil, album: String? = nil,
                trackNumber: Int? = nil, key: String? = nil, comment: String? = nil) {
        self.bpm = bpm; self.title = title; self.artist = artist; self.album = album; self.trackNumber = trackNumber
        self.key = key; self.comment = comment
    }

    public var isEmpty: Bool {
        bpm == nil && title == nil && artist == nil && album == nil && trackNumber == nil && key == nil && comment == nil
    }

    /// The tags of the file at `url`; empty when it has none the builder reads or cannot be read.
    public static func read(_ url: URL) -> FileTags {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return FileTags() }
        defer { try? handle.close() }
        return read(TagFile(handle: handle))
    }

    /// The tags in a file's bytes already in memory: the same as `read(url)` for the same bytes.
    public static func read(bytes: Data) -> FileTags { read(TagFile(bytes: bytes)) }

    static func read(_ file: TagFile) -> FileTags {
        guard let head = file.read(at: 0, count: 12), head.count >= 12 else { return FileTags() }
        let b = [UInt8](head)
        func ascii(_ at: Int, _ s: String) -> Bool { Array(b[at..<(at + s.utf8.count)]) == Array(s.utf8) }
        if ascii(0, "RIFF") && ascii(8, "WAVE") { return riffTags(file, bigEndian: false) }
        if ascii(0, "FORM") && (ascii(8, "AIFF") || ascii(8, "AIFC")) { return riffTags(file, bigEndian: true) }
        if ascii(4, "ftyp") { return mp4Tags(file) }
        var offset = 0
        var tags = FileTags()
        if ascii(0, "ID3") {
            guard let size = ID3.tagSize(b) else { return FileTags() }
            if let tag = file.read(at: 0, count: size) { tags = ID3.parse(tag) }
            offset = size
        }
        if let marker = file.read(at: offset, count: 4), marker.elementsEqual("fLaC".utf8) {
            tags = tags.filled(from: flacComment(file, at: offset + 4))
        } else if let v1 = id3v1(file) {
            tags = tags.filled(from: v1)
        }
        return tags
    }

    /// These tags, with the missing ones taken from `other`.
    func filled(from other: FileTags) -> FileTags {
        FileTags(bpm: bpm ?? other.bpm, title: title ?? other.title, artist: artist ?? other.artist,
                 album: album ?? other.album, trackNumber: trackNumber ?? other.trackNumber, key: key ?? other.key,
                 comment: comment ?? other.comment)
    }

    /// A track number tag's number: "2", "02", "2/12"; nil for none or zero.
    static func number(_ text: String?) -> Int? {
        guard let text else { return nil }
        let digits = text.trimmingCharacters(in: .whitespaces).prefix { $0.isASCII && $0.isNumber }
        guard let n = Int(digits), n > 0 else { return nil }
        return n
    }

    /// The ID3v1 tag in a file's last 128 bytes ("TAG", then title, artist and album of 30 bytes each, the year, a
    /// comment of 30 bytes whose last byte is the track number when the one before it is zero, and the genre), read as
    /// Latin-1; nil when there is none.
    static func id3v1(_ file: TagFile) -> FileTags? {
        guard let size = file.size, size >= 128, let d = file.read(at: size - 128, count: 128) else { return nil }
        let b = [UInt8](d)
        guard b[0] == 0x54, b[1] == 0x41, b[2] == 0x47 else { return nil }
        func text(_ r: Range<Int>) -> String? {
            let bytes = b[r].prefix { $0 != 0 }
            return nonEmpty(String(bytes.map { Character(Unicode.Scalar($0)) }))
        }
        let track = b[125] == 0 && b[126] != 0 ? Int(b[126]) : nil
        return FileTags(title: text(3..<33), artist: text(33..<63), album: text(63..<93), trackNumber: track,
                        comment: text(97..<(track == nil ? 127 : 125)))
    }

    /// A tempo tag's text as a number: the digits and point only, as the lab's add_tracks.py reads TBPM; nil for none
    /// or zero.
    static func bpm(_ text: String?) -> Double? {
        guard let text else { return nil }
        let kept = text.replacingOccurrences(of: ",", with: ".").filter { $0.isASCII && ($0.isNumber || $0 == ".") }
        guard let v = Double(kept), v.isFinite, v > 0, v < 1000 else { return nil }
        return v
    }

    /// The ID3v2 tag inside a WAV (`id3 ` or `ID3 ` chunk, little-endian sizes) or AIFF (`ID3 `, big-endian) file,
    /// with what it lacks taken from a WAV file's LIST INFO chunk.
    private static func riffTags(_ file: TagFile, bigEndian: Bool) -> FileTags {
        var at = 12
        var id3: FileTags? = nil
        var info = FileTags()
        for _ in 0..<64 {
            guard let h = file.read(at: at, count: 8), h.count == 8 else { break }
            let b = [UInt8](h)
            let id = String(decoding: b[0..<4], as: UTF8.self)
            let size = bigEndian
                ? Int(b[4]) << 24 | Int(b[5]) << 16 | Int(b[6]) << 8 | Int(b[7])
                : Int(b[7]) << 24 | Int(b[6]) << 16 | Int(b[5]) << 8 | Int(b[4])
            if id == "id3 " || id == "ID3 " {
                guard size <= ID3.maxTagBytes, let tag = file.read(at: at + 8, count: size) else { break }
                id3 = ID3.parse(tag)
            } else if id == "LIST", !bigEndian, size >= 4, size <= 1 << 20, let list = file.read(at: at + 8, count: size),
                      list.prefix(4).elementsEqual("INFO".utf8) {
                info = listInfo([UInt8](list.dropFirst(4)))
            }
            at += 8 + size + (size & 1)
        }
        return (id3 ?? FileTags()).filled(from: info)
    }

    /// A RIFF LIST INFO chunk's items: four letters, a 32-bit little-endian size, the text (NUL-terminated, padded to
    /// an even length). Read as UTF-8, or Latin-1 when it is not valid UTF-8.
    static func listInfo(_ b: [UInt8]) -> FileTags {
        var tags = FileTags()
        var at = 0
        while at + 8 <= b.count {
            let id = String(decoding: b[at..<(at + 4)], as: UTF8.self)
            let n = Int(b[at + 4]) | Int(b[at + 5]) << 8 | Int(b[at + 6]) << 16 | Int(b[at + 7]) << 24
            guard n >= 0, at + 8 + n <= b.count else { break }
            let bytes = Array(b[(at + 8)..<(at + 8 + n)].prefix { $0 != 0 })
            let text = nonEmpty(String(bytes: bytes, encoding: .utf8) ?? String(bytes.map { Character(Unicode.Scalar($0)) }))
            switch id {
            case "INAM": tags.title = tags.title ?? text
            case "IART": tags.artist = tags.artist ?? text
            case "IPRD": tags.album = tags.album ?? text
            case "ITRK", "IPRT": tags.trackNumber = tags.trackNumber ?? number(text)
            case "ICMT": tags.comment = tags.comment ?? text
            default: break
            }
            at += 8 + n + (n & 1)
        }
        return tags
    }

    /// The tags in an MP4's `ilst` (found by `FileFacts.mp4Items`, which the cover reader shares). Each item is a box
    /// whose `data` boxes hold its value: four bytes of version and type (1 UTF-8, 2 UTF-16 big-endian; 0 and 21 the
    /// number atoms), four of locale, then the value. Text is cut at a NUL and trimmed, and an empty one is no value,
    /// as in an ID3v2 tag; the first item of a kind that gives a value is kept. A box whose length runs past the box
    /// around it, or is shorter than its header, ends the reading of that box: what was read before it stays, nothing
    /// is read from it.
    static func mp4Tags(_ file: TagFile) -> FileTags {
        guard let (m, ilst) = FileFacts.mp4Items(file) else { return FileTags() }
        var tags = FileTags()
        for (type, body) in MP4Boxes.strict(m, ilst) {
            let item = MP4Boxes.strict(m, body)
            func datas() -> [(kind: Int, value: ArraySlice<UInt8>)] {
                item.compactMap { t, r in
                    guard t == "data", r.count >= 8 else { return nil }
                    let kind = Int(m[r.lowerBound + 1]) << 16 | Int(m[r.lowerBound + 2]) << 8 | Int(m[r.lowerBound + 3])
                    return (kind, m[(r.lowerBound + 8)..<r.upperBound])
                }
            }
            func text() -> String? { datas().lazy.compactMap { MP4Boxes.text(kind: $0.kind, $0.value) }.first }
            switch type {
            case "\u{A9}nam": tags.title = tags.title ?? text()
            case "\u{A9}ART": tags.artist = tags.artist ?? text()
            case "\u{A9}alb": tags.album = tags.album ?? text()
            case "\u{A9}cmt": tags.comment = tags.comment ?? text()
            case "trkn":
                // Two bytes kept, the track number, the track count (and two more kept): the number is all we read.
                let n = datas().lazy.compactMap { d -> Int? in
                    guard d.kind == 0 || d.kind == 21, d.value.count >= 6 else { return nil }
                    let a = Array(d.value)
                    let n = Int(a[2]) << 8 | Int(a[3])
                    return n > 0 ? n : nil
                }.first
                tags.trackNumber = tags.trackNumber ?? n
            case "tmpo":
                let v = datas().lazy.compactMap { d -> Double? in
                    guard d.kind == 0 || d.kind == 21, let n = MP4Boxes.integer(d.value), n > 0 else { return nil }
                    return FileTags.bpm(String(n))
                }.first
                tags.bpm = tags.bpm ?? v
            case "----":
                // iTunes' free-form atom: `mean` (four bytes of version and flags, then the name space), `name` (the
                // same, then the name), then the value. Only Apple's name space, as Mixed In Key and iTunes write it.
                func label(_ box: String) -> String? {
                    guard let r = item.first(where: { $0.0 == box })?.1, r.count >= 4 else { return nil }
                    return String(bytes: m[(r.lowerBound + 4)..<r.upperBound], encoding: .utf8)
                }
                guard label("mean")?.lowercased() == "com.apple.itunes", let name = label("name") else { continue }
                switch name.lowercased() {
                case "initialkey", "key", "initial key": tags.key = tags.key ?? text()
                default: break
                }
            default: break
            }
        }
        return tags
    }

    /// The Vorbis comment of a FLAC file whose metadata blocks start at `at`.
    private static func flacComment(_ file: TagFile, at start: Int) -> FileTags {
        var at = start
        for _ in 0..<128 {
            guard let h = file.read(at: at, count: 4), h.count == 4 else { break }
            let b = [UInt8](h)
            let last = b[0] & 0x80 != 0, type = b[0] & 0x7F
            let size = Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
            if type == 4 {
                guard let block = file.read(at: at + 4, count: size) else { break }
                return vorbisComment(block)
            }
            if last { break }
            at += 4 + size
        }
        return FileTags()
    }

    /// A Vorbis comment block: vendor string, then `KEY=value` strings, all lengths 32-bit little-endian.
    static func vorbisComment(_ block: Data) -> FileTags {
        var r = ByteCursor(block)
        guard let vendor = r.u32le(), r.skip(Int(vendor)), let count = r.u32le() else { return FileTags() }
        var tags = FileTags()
        for _ in 0..<min(Int(count), 10_000) {
            guard let n = r.u32le(), let bytes = r.take(Int(n)) else { break }
            let s = String(decoding: bytes, as: UTF8.self)
            guard let eq = s.firstIndex(of: "=") else { continue }
            let key = s[..<eq].uppercased(), value = String(s[s.index(after: eq)...])
            switch key {
            case "BPM", "TEMPO": tags.bpm = tags.bpm ?? bpm(value)
            case "TITLE": tags.title = tags.title ?? nonEmpty(value)
            case "ARTIST": tags.artist = tags.artist ?? nonEmpty(value)
            case "ALBUM": tags.album = tags.album ?? nonEmpty(value)
            case "TRACKNUMBER": tags.trackNumber = tags.trackNumber ?? number(value)
            case "INITIALKEY", "KEY", "INITIAL KEY": tags.key = tags.key ?? nonEmpty(value)
            case "COMMENT", "DESCRIPTION": tags.comment = tags.comment ?? nonEmpty(value)
            default: break
            }
        }
        return tags
    }
}

func nonEmpty(_ s: String?) -> String? {
    guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
    return t
}

/// MP4 boxes for the tag reader: strict about lengths, never reading past the bytes.
enum MP4Boxes {
    /// The boxes inside `range` of `m`: each box's four-letter type and the range of its body. A box with a 64-bit
    /// length (a length of 1, then eight bytes) is read; a length of 0 runs to the end of `range`. A length shorter than
    /// the box's header, or one that runs past `range`, ends the list there.
    static func strict(_ m: [UInt8], _ range: Range<Int>) -> [(String, Range<Int>)] {
        guard range.lowerBound >= 0, range.upperBound <= m.count else { return [] }
        var out: [(String, Range<Int>)] = []
        var o = range.lowerBound
        while range.upperBound - o >= 8 {
            var size = Int(m[o]) << 24 | Int(m[o + 1]) << 16 | Int(m[o + 2]) << 8 | Int(m[o + 3])
            var header = 8
            if size == 1 {
                guard range.upperBound - o >= 16, m[o + 8] < 0x80 else { break }
                size = m[(o + 8)..<(o + 16)].reduce(0) { $0 << 8 | Int($1) }; header = 16
            } else if size == 0 { size = range.upperBound - o }
            guard size >= header, size <= range.upperBound - o else { break }
            out.append((String(m[(o + 4)..<(o + 8)].map { Character(Unicode.Scalar($0)) }), (o + header)..<(o + size)))
            o += size
        }
        return out
    }

    /// A `data` box's text: type 1 UTF-8 (not valid UTF-8 is no value), type 2 UTF-16 big-endian (a byte-order mark,
    /// when there is one, is followed; an odd length is no value). Cut at a NUL and trimmed; empty is no value. Other
    /// types are not text.
    static func text(kind: Int, _ d: ArraySlice<UInt8>) -> String? {
        var s: String
        switch kind {
        case 1:
            guard let t = String(bytes: d, encoding: .utf8) else { return nil }
            s = t
        case 2:
            guard d.count % 2 == 0 else { return nil }
            let b = Array(d)
            var i = 0
            var bigEndian = true
            if b.count >= 2 {
                if b[0] == 0xFE && b[1] == 0xFF { i = 2 }
                else if b[0] == 0xFF && b[1] == 0xFE { bigEndian = false; i = 2 }
            }
            var units: [UInt16] = []
            while i + 1 < b.count {
                units.append(bigEndian ? UInt16(b[i]) << 8 | UInt16(b[i + 1]) : UInt16(b[i + 1]) << 8 | UInt16(b[i]))
                i += 2
            }
            if let nul = units.firstIndex(of: 0) { units = Array(units[..<nul]) }
            s = String(decoding: units, as: UTF16.self)
        default: return nil
        }
        if let nul = s.firstIndex(of: "\u{0}") { s = String(s[..<nul]) }
        return nonEmpty(s)
    }

    /// A number atom's value: 1, 2, 4 or 8 bytes, big-endian, signed (type 21 is a signed integer; the tempo and the
    /// number atoms are never large enough for the sign bit to be theirs). Nil for any other length.
    static func integer(_ d: ArraySlice<UInt8>) -> Int? {
        guard [1, 2, 4, 8].contains(d.count) else { return nil }
        let bits = d.count * 8
        let raw = d.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        if bits == 64 { return Int(Int64(bitPattern: raw)) }
        let signBit = UInt64(1) << UInt64(bits - 1)
        return raw & signBit != 0 ? Int(raw) - Int(UInt64(1) << UInt64(bits)) : Int(raw)
    }
}

/// ID3v2 tags, versions 2.2, 2.3 and 2.4.
enum ID3 {
    /// A tag claiming more than this is not read.
    static let maxTagBytes = 64 << 20

    /// The whole tag's length, header (and footer) included, from its first ten bytes; nil when they are not an
    /// ID3v2 header.
    static func tagSize(_ b: [UInt8]) -> Int? {
        guard b.count >= 10, b[0] == 0x49, b[1] == 0x44, b[2] == 0x33, (2...4).contains(b[3]),
              b[6..<10].allSatisfy({ $0 < 0x80 }) else { return nil }
        let body = synchsafe(b[6], b[7], b[8], b[9])
        let footer = b[3] == 4 && b[5] & 0x10 != 0 ? 10 : 0
        let size = 10 + body + footer
        return size <= maxTagBytes ? size : nil
    }

    static func synchsafe(_ a: UInt8, _ b: UInt8, _ c: UInt8, _ d: UInt8) -> Int {
        Int(a & 0x7F) << 21 | Int(b & 0x7F) << 14 | Int(c & 0x7F) << 7 | Int(d & 0x7F)
    }

    /// Undoes unsynchronisation: every 0xFF 0x00 becomes 0xFF.
    static func resynchronised(_ bytes: [UInt8]) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            out.append(bytes[i])
            if bytes[i] == 0xFF && i + 1 < bytes.count && bytes[i + 1] == 0 { i += 1 }
            i += 1
        }
        return out
    }

    /// The tags in a whole ID3v2 tag (header included).
    static func parse(_ tag: Data) -> FileTags {
        let all = [UInt8](tag)
        guard let size = tagSize(all), all.count >= 10 else { return FileTags() }
        let version = all[3], flags = all[5]
        var body = Array(all[10..<min(size, all.count)])
        if version == 4 && flags & 0x10 != 0 && body.count >= 10 { body.removeLast(10) }  // the footer
        if version < 4 && flags & 0x80 != 0 { body = resynchronised(body) }
        var r = ByteCursor(Data(body))
        if version >= 3 && flags & 0x40 != 0 {  // extended header
            guard let e = r.take(4) else { return FileTags() }
            let n = version == 4 ? synchsafe(e[0], e[1], e[2], e[3]) - 4
                : Int(e[0]) << 24 | Int(e[1]) << 16 | Int(e[2]) << 8 | Int(e[3])
            guard n >= 0, r.skip(n) else { return FileTags() }
        }
        var tags = FileTags()
        while r.remaining > 0 {
            let idLength = version == 2 ? 3 : 4
            guard let head = r.take(version == 2 ? 6 : 10), head[0] != 0 else { break }
            let id = String(decoding: head[0..<idLength], as: UTF8.self)
            let size: Int
            switch version {
            case 2: size = Int(head[3]) << 16 | Int(head[4]) << 8 | Int(head[5])
            case 3: size = Int(head[4]) << 24 | Int(head[5]) << 16 | Int(head[6]) << 8 | Int(head[7])
            default: size = synchsafe(head[4], head[5], head[6], head[7])
            }
            guard size >= 0, var data = r.take(size) else { break }
            guard ["TBPM", "TBP", "TIT2", "TT2", "TPE1", "TP1", "TALB", "TAL", "TRCK", "TRK", "TKEY", "TKE", "COMM", "COM",
                   "TXXX", "TXX"].contains(id) else { continue }
            if version >= 3 {
                let format = head[9]
                if version == 3 {
                    if format & 0xC0 != 0 { continue }  // compressed or encrypted
                    if format & 0x20 != 0 { data = Array(data.dropFirst()) }  // group id
                } else {
                    if format & 0x0C != 0 { continue }  // compressed or encrypted
                    if format & 0x40 != 0 { data = Array(data.dropFirst()) }  // group id
                    if format & 0x02 != 0 || flags & 0x80 != 0 { data = resynchronised(data) }
                    if format & 0x01 != 0 { data = Array(data.dropFirst(4)) }  // data length indicator
                }
            }
            switch id {
            case "COMM", "COM":
                // Comments the players and taggers keep for themselves are not the DJ's comment.
                if let f = describedFrame(data, skippingLanguage: true),
                   !f.0.lowercased().hasPrefix("itun"), !f.0.lowercased().hasPrefix("songs-db") {
                    tags.comment = tags.comment ?? nonEmpty(f.1)
                }
                continue
            case "TXXX", "TXX":
                if let f = describedFrame(data, skippingLanguage: false) {
                    switch f.0.lowercased() {
                    case "initialkey", "key", "initial key": tags.key = tags.key ?? nonEmpty(f.1)
                    // ffmpeg writes a comment this way, not as COMM.
                    case "comment": tags.comment = tags.comment ?? nonEmpty(f.1)
                    default: break
                    }
                }
                continue
            default: break
            }
            let text = textFrame(data)
            switch id {
            case "TBPM", "TBP": tags.bpm = tags.bpm ?? FileTags.bpm(text)
            case "TIT2", "TT2": tags.title = tags.title ?? nonEmpty(text)
            case "TALB", "TAL": tags.album = tags.album ?? nonEmpty(text)
            case "TRCK", "TRK": tags.trackNumber = tags.trackNumber ?? FileTags.number(text)
            case "TKEY", "TKE": tags.key = tags.key ?? nonEmpty(text)
            default: tags.artist = tags.artist ?? nonEmpty(text)
            }
        }
        return tags
    }

    /// A frame with a description before its text (COMM, after a three-letter language; TXXX): the description and the
    /// text, each in the frame's encoding. Nil when the frame does not hold together.
    static func describedFrame(_ data: [UInt8], skippingLanguage: Bool) -> (String, String)? {
        guard let encoding = data.first else { return nil }
        var body = Array(data.dropFirst())
        if skippingLanguage { guard body.count >= 3 else { return nil }; body.removeFirst(3) }
        // The description ends at a NUL: one byte in Latin-1 and UTF-8, two (on an even offset) in UTF-16.
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
        let description = textFrame([encoding] + body[..<end]) ?? ""
        let rest = Array(body[(end + (wide ? 2 : 1))...])
        // A UTF-16 text after a description carries its own byte-order mark, or follows the description's.
        var textBytes = rest
        if encoding == 1, rest.count >= 2, !(rest[0] == 0xFF && rest[1] == 0xFE) && !(rest[0] == 0xFE && rest[1] == 0xFF),
           body.count >= 2 {
            textBytes = Array(body[0..<2]) + rest
        }
        return (description, textFrame([encoding] + textBytes) ?? "")
    }

    /// A text frame's first value: an encoding byte (0 Latin-1, 1 UTF-16 with a byte-order mark, 2 UTF-16 big-endian,
    /// 3 UTF-8), then the text, values separated by a NUL.
    static func textFrame(_ data: [UInt8]) -> String? {
        guard let encoding = data.first else { return nil }
        let bytes = Array(data.dropFirst())
        var text: String
        switch encoding {
        case 0: text = String(bytes.map { Character(Unicode.Scalar($0)) })
        case 1, 2:
            var units: [UInt16] = []
            var i = 0
            var bigEndian = encoding == 2
            if encoding == 1, bytes.count >= 2 {
                if bytes[0] == 0xFE && bytes[1] == 0xFF { bigEndian = true; i = 2 }
                else if bytes[0] == 0xFF && bytes[1] == 0xFE { bigEndian = false; i = 2 }
            }
            while i + 1 < bytes.count {
                units.append(bigEndian ? UInt16(bytes[i]) << 8 | UInt16(bytes[i + 1])
                                       : UInt16(bytes[i + 1]) << 8 | UInt16(bytes[i]))
                i += 2
            }
            if let nul = units.firstIndex(of: 0) { units = Array(units[..<nul]) }
            text = String(decoding: units, as: UTF16.self)
        default: text = String(decoding: bytes, as: UTF8.self)
        }
        if let nul = text.firstIndex(of: "\u{0}") { text = String(text[..<nul]) }
        return text
    }
}

/// Reads byte ranges of an open file, or of a file's bytes already in memory (a song read once, off a music CD); nil
/// past the end or on an error. The two give the same answers for the same bytes.
struct TagFile {
    let handle: FileHandle?
    let bytes: Data?
    init(handle: FileHandle) { self.handle = handle; bytes = nil }
    init(bytes: Data) { handle = nil; self.bytes = bytes }
    /// The file's length in bytes, or nil when it cannot be told.
    var size: Int? {
        if let bytes { return bytes.count }
        guard let end = try? handle?.seekToEnd() else { return nil }
        return Int(end)
    }
    func read(at offset: Int, count: Int) -> Data? {
        guard offset >= 0, count >= 0, count <= ID3.maxTagBytes else { return nil }
        if let bytes {
            // As a file handle: nothing asked for is nothing, wherever; past the end is nil.
            if count == 0 { return Data() }
            guard offset <= bytes.count, count <= bytes.count - offset else { return nil }
            let start = bytes.startIndex + offset
            return Data(bytes[start..<(start + count)])
        }
        guard let handle else { return nil }
        do {
            try handle.seek(toOffset: UInt64(offset))
            let d = try handle.read(upToCount: count) ?? Data()
            return d.count == count ? d : nil
        } catch {
            return nil
        }
    }
}

/// A bounds-checked reader over bytes.
struct ByteCursor {
    let bytes: [UInt8]
    var at = 0
    init(_ data: Data) { bytes = [UInt8](data) }
    var remaining: Int { bytes.count - at }
    mutating func take(_ n: Int) -> [UInt8]? {
        guard n >= 0, n <= remaining else { return nil }
        defer { at += n }
        return Array(bytes[at..<(at + n)])
    }
    mutating func skip(_ n: Int) -> Bool { take(n) != nil }
    mutating func u32le() -> UInt32? {
        guard let b = take(4) else { return nil }
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }
}
