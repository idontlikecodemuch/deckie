import Foundation

/// The few tags of an audio file the builder reads: its tempo tag (for `--bpm-tags`), title and artist. Read from an
/// ID3v2 tag (versions 2.2 to 2.4: TBPM, TIT2, TPE1 and their 2.2 names) at the start of the file (MP3, FLAC or AAC
/// with ID3 in front) or in a WAV or AIFF file's `id3 ` chunk, and from a FLAC file's Vorbis comment (BPM, TITLE,
/// ARTIST). MP4 tags are not read: those files cannot be decoded on Linux yet. Nothing is read but the tags, and a tag
/// that does not hold together gives nothing rather than an error.
public struct FileTags: Codable, Equatable, Sendable {
    public var bpm: Double?
    public var title: String?
    public var artist: String?

    public init(bpm: Double? = nil, title: String? = nil, artist: String? = nil) {
        self.bpm = bpm; self.title = title; self.artist = artist
    }

    public var isEmpty: Bool { bpm == nil && title == nil && artist == nil }

    /// The tags of the file at `url`; empty when it has none the builder reads or cannot be read.
    public static func read(_ url: URL) -> FileTags {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return FileTags() }
        defer { try? handle.close() }
        let file = TagFile(handle: handle)
        guard let head = file.read(at: 0, count: 12), head.count >= 12 else { return FileTags() }
        let b = [UInt8](head)
        func ascii(_ at: Int, _ s: String) -> Bool { Array(b[at..<(at + s.utf8.count)]) == Array(s.utf8) }
        if ascii(0, "RIFF") && ascii(8, "WAVE") { return riffID3(file, bigEndian: false) }
        if ascii(0, "FORM") && (ascii(8, "AIFF") || ascii(8, "AIFC")) { return riffID3(file, bigEndian: true) }
        var offset = 0
        var tags = FileTags()
        if ascii(0, "ID3") {
            guard let size = ID3.tagSize(b) else { return FileTags() }
            if let tag = file.read(at: 0, count: size) { tags = ID3.parse(tag) }
            offset = size
        }
        if let marker = file.read(at: offset, count: 4), marker.elementsEqual("fLaC".utf8) {
            tags = tags.filled(from: flacComment(file, at: offset + 4))
        }
        return tags
    }

    /// These tags, with the missing ones taken from `other`.
    func filled(from other: FileTags) -> FileTags {
        FileTags(bpm: bpm ?? other.bpm, title: title ?? other.title, artist: artist ?? other.artist)
    }

    /// A tempo tag's text as a number: the digits and point only, as the lab's add_tracks.py reads TBPM; nil for none
    /// or zero.
    static func bpm(_ text: String?) -> Double? {
        guard let text else { return nil }
        let kept = text.replacingOccurrences(of: ",", with: ".").filter { $0.isASCII && ($0.isNumber || $0 == ".") }
        guard let v = Double(kept), v.isFinite, v > 0, v < 1000 else { return nil }
        return v
    }

    /// The ID3v2 tag inside a WAV (`id3 ` or `ID3 ` chunk, little-endian sizes) or AIFF (`ID3 `, big-endian) file.
    private static func riffID3(_ file: TagFile, bigEndian: Bool) -> FileTags {
        var at = 12
        for _ in 0..<64 {
            guard let h = file.read(at: at, count: 8), h.count == 8 else { break }
            let b = [UInt8](h)
            let id = String(decoding: b[0..<4], as: UTF8.self)
            let size = bigEndian
                ? Int(b[4]) << 24 | Int(b[5]) << 16 | Int(b[6]) << 8 | Int(b[7])
                : Int(b[7]) << 24 | Int(b[6]) << 16 | Int(b[5]) << 8 | Int(b[4])
            if id == "id3 " || id == "ID3 " {
                guard size <= ID3.maxTagBytes, let tag = file.read(at: at + 8, count: size) else { break }
                return ID3.parse(tag)
            }
            at += 8 + size + (size & 1)
        }
        return FileTags()
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
            guard ["TBPM", "TBP", "TIT2", "TT2", "TPE1", "TP1"].contains(id) else { continue }
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
            let text = textFrame(data)
            switch id {
            case "TBPM", "TBP": tags.bpm = tags.bpm ?? FileTags.bpm(text)
            case "TIT2", "TT2": tags.title = tags.title ?? nonEmpty(text)
            default: tags.artist = tags.artist ?? nonEmpty(text)
            }
        }
        return tags
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

/// Reads byte ranges of an open file; nil past the end or on an error.
struct TagFile {
    let handle: FileHandle
    func read(at offset: Int, count: Int) -> Data? {
        guard offset >= 0, count >= 0, count <= ID3.maxTagBytes else { return nil }
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
