import Foundation

/// CD-Text: names written on a music CD beside the music, in the lead-in's sub-channel (research AA, section 2.1).
/// A drive hands it over in answer to the standard command "read table of contents" in its format 5 (MMC: READ
/// TOC/PMA/ATIP, format 0101b): a four-byte header, then packs of 18 bytes. This decodes those bytes; it is the same
/// on every computer and needs no library.
///
/// A pack, as the format defines it (Red Book annex J; MMC's description of format 5):
///
///     byte 0      the pack's type: 0x80 title, 0x81 performer, 0x82 songwriter, 0x83 composer, 0x84 arranger,
///                 0x85 message, 0x86 the disc's id, 0x87 genre, 0x88 to 0x8D the format's own (not read here),
///                 0x8E the barcode (track 0) and each song's ISRC, 0x8F the block's size information
///     byte 1      the number of the song the first character of this pack belongs to (0: the disc itself); bit 7
///                 is the extension flag
///     byte 2      the pack's sequence number in its block
///     byte 3      bit 7: two bytes to a character (double-byte text); bits 6 to 4: the block's number (0 to 7, one
///                 block per language); bits 3 to 0: how many characters of that song's text came in earlier packs
///                 (15 means 15 or more)
///     bytes 4-15  twelve bytes of text: each song's text ends with a 0 byte (two in double-byte text) and the next
///                 song's begins; a text of only a tab (0x09) means "the same as the song before"
///     bytes 16-17 a check on bytes 0 to 15: CRC-16 with the polynomial x^16 + x^12 + x^5 + 1 (0x1021), starting
///                 from 0, stored with every bit inverted
///
/// The size information (type 0x8F, three packs, 36 bytes) says which characters the block's text is in: 0x00
/// ISO 8859-1 (Western European), 0x01 ISO 646 (plain ASCII), 0x80 MS-JIS (Japanese); 0x81 Korean and 0x82
/// Mandarin are defined but not read here, and their text is left out rather than shown wrong.
///
/// **Damage.** A pack whose check fails is dropped. The packs that follow say where they belong (the song and how
/// far into its text), so a missing pack loses only the text it held: a song's text with a piece missing is left out
/// and counted, never shown with a hole in it. Bytes cut off mid-pack are ignored. Some drives hand the packs over
/// with every check set to zero; then no check can be made and the packs are read as they are.
public struct CDText: Equatable, Sendable {
    public enum Characters: String, Codable, Equatable, Sendable {
        case latin1 = "iso-8859-1", ascii, msJIS = "ms-jis", korean, mandarin, unknown

        init(code: UInt8) {
            switch code {
            case 0x00: self = .latin1
            case 0x01: self = .ascii
            case 0x80: self = .msJIS
            case 0x81: self = .korean
            case 0x82: self = .mandarin
            default: self = .unknown
            }
        }

        /// Whether this decoder can turn the block's bytes into text.
        public var readable: Bool { self == .latin1 || self == .ascii || self == .msJIS }
    }

    /// One block: the text in one language.
    public struct Block: Equatable, Sendable {
        public var number: Int
        /// The language code the size information gives (EBU Tech 3264: 0x09 English, 0x08 German, 0x0F French,
        /// 0x69 Japanese, ...), when there was size information.
        public var language: UInt8?
        public var characters: Characters
        public var firstSong: Int?
        public var lastSong: Int?
        /// By song number; 0 is the disc itself (its title, its performer).
        public var titles: [Int: String] = [:]
        public var performers: [Int: String] = [:]
        public var songwriters: [Int: String] = [:]
        public var composers: [Int: String] = [:]
        public var arrangers: [Int: String] = [:]
        public var messages: [Int: String] = [:]
        /// The disc's id (type 0x86) and barcode (0x8E, song 0), and each song's ISRC (0x8E).
        public var discId: String?
        public var barcode: String?
        public var isrcs: [Int: String] = [:]
        /// Songs whose text of some kind was damaged and left out, by pack type.
        public var damaged: [UInt8: Set<Int>] = [:]

        public var discTitle: String? { titles[0] }
        public var discPerformer: String? { performers[0] }
    }

    public var blocks: [Block]
    /// Packs read whole, and packs dropped because their check failed or their type is not one of the format's.
    public var packsRead: Int
    public var packsDamaged: Int
    /// Whether the packs carried checks (false when every check was zero, so none could be made).
    public var checked: Bool

    /// The first block (the main language), or nil when there is no text.
    public var main: Block? { blocks.first }

    /// No usable name at all: no title or performer for the disc or for any song.
    public var hasNames: Bool {
        guard let b = main else { return false }
        return !b.titles.isEmpty || !b.performers.isEmpty
    }

    /// Decodes a drive's answer to "read table of contents, format 5": with its four-byte header (the length of what
    /// follows, then two reserved bytes) or as bare packs.
    public static func decode(_ bytes: [UInt8]) -> CDText {
        let packs = Self.packs(bytes)
        // Checks: when every pack's is zero, the drive did not hand them over.
        let allZero = !packs.isEmpty && packs.allSatisfy { $0[$0.startIndex + 16] == 0 && $0[$0.startIndex + 17] == 0 }
        var good: [ArraySlice<UInt8>] = []
        var damaged = 0
        for p in packs {
            guard (0x80...0x8F).contains(p[p.startIndex]) else { damaged += 1; continue }
            if !allZero && !checkPasses(p) { damaged += 1; continue }
            good.append(p)
        }
        var byBlock: [Int: [ArraySlice<UInt8>]] = [:]
        for p in good { byBlock[Int((p[p.startIndex + 3] >> 4) & 0x07), default: []].append(p) }
        var blocks: [Block] = []
        for number in byBlock.keys.sorted() {
            blocks.append(block(number, byBlock[number]!))
        }
        return CDText(blocks: blocks, packsRead: good.count, packsDamaged: damaged, checked: !allZero)
    }

    /// The 18-byte packs in a drive's answer.
    static func packs(_ bytes: [UInt8]) -> [ArraySlice<UInt8>] {
        var start = 0
        var end = bytes.count
        if bytes.count >= 4 {
            let declared = Int(bytes[0]) << 8 | Int(bytes[1])
            let looksLikeHeader = !(0x80...0x8F).contains(bytes[0]) || (declared >= 2 && (declared - 2) % 18 == 0)
            if looksLikeHeader {
                start = 4
                if declared >= 2 { end = min(bytes.count, 2 + declared) }
            }
        }
        var out: [ArraySlice<UInt8>] = []
        var i = start
        while i + 18 <= end {
            out.append(bytes[i..<(i + 18)])
            i += 18
        }
        return out
    }

    /// The format's check: CRC-16 (0x1021, from 0) over bytes 0 to 15, stored inverted in bytes 16 and 17.
    static func checkPasses(_ p: ArraySlice<UInt8>) -> Bool {
        let s = p.startIndex
        let stored = UInt16(p[s + 16]) << 8 | UInt16(p[s + 17])
        return crc16(p[s..<(s + 16)]) ^ 0xFFFF == stored
    }

    public static func crc16<C: Collection>(_ bytes: C) -> UInt16 where C.Element == UInt8 {
        var crc: UInt16 = 0
        for b in bytes {
            crc ^= UInt16(b) << 8
            for _ in 0..<8 { crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x1021 : crc << 1 }
        }
        return crc
    }

    static let textTypes: Set<UInt8> = [0x80, 0x81, 0x82, 0x83, 0x84, 0x85, 0x8E]

    static func block(_ number: Int, _ packs: [ArraySlice<UInt8>]) -> Block {
        let inOrder = packs.enumerated().sorted { a, b in
            let x = a.element[a.element.startIndex + 2], y = b.element[b.element.startIndex + 2]
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)

        // The size information, when its three packs are all here.
        var characters = Characters.latin1
        var language: UInt8? = nil
        var first: Int? = nil, last: Int? = nil
        let size = inOrder.filter { $0[$0.startIndex] == 0x8F }
            .sorted { $0[$0.startIndex + 1] < $1[$1.startIndex + 1] }
        if size.count >= 3 {
            let info = size.prefix(3).flatMap { Array($0[($0.startIndex + 4)..<($0.startIndex + 16)]) }
            characters = Characters(code: info[0])
            first = Int(info[1]); last = Int(info[2])
            language = info[28 + number]
        } else if let one = size.first(where: { $0[$0.startIndex + 1] == 0 }) {
            characters = Characters(code: one[one.startIndex + 4])
            first = Int(one[one.startIndex + 5]); last = Int(one[one.startIndex + 6])
        }

        var b = Block(number: number, language: language, characters: characters, firstSong: first, lastSong: last)
        for type in textTypes.sorted() {
            let typed = inOrder.filter { $0[$0.startIndex] == type }
            guard !typed.isEmpty else { continue }
            let doubleByte = typed.contains { $0[$0.startIndex + 3] & 0x80 != 0 }
            let (raw, broken) = strings(typed, doubleByte: doubleByte)
            if !broken.isEmpty { b.damaged[type] = broken }
            var texts: [Int: String] = [:]
            for song in raw.keys.sorted() {
                let bytes = raw[song]!
                let isTab = doubleByte ? bytes == [0x09, 0x09] : bytes == [0x09]
                if isTab {
                    if let before = texts[song - 1] { texts[song] = before }
                    continue
                }
                // ISRCs and the barcode are plain ASCII whatever the block's characters.
                let chars: Characters = type == 0x8E ? .ascii : characters
                guard let s = decodeText(bytes, chars) else {
                    b.damaged[type, default: []].insert(song)
                    continue
                }
                let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { texts[song] = trimmed }
            }
            switch type {
            case 0x80: b.titles = texts
            case 0x81: b.performers = texts
            case 0x82: b.songwriters = texts
            case 0x83: b.composers = texts
            case 0x84: b.arrangers = texts
            case 0x85: b.messages = texts
            case 0x8E:
                b.barcode = texts[0]
                b.isrcs = texts.filter { $0.key > 0 }
            default: break
            }
        }
        // The disc's id is one string for the disc (type 0x86).
        let ids = inOrder.filter { $0[$0.startIndex] == 0x86 }
        if !ids.isEmpty {
            let (raw, _) = strings(ids, doubleByte: false)
            b.discId = raw[0].flatMap { decodeText($0, .ascii) }?.trimmingCharacters(in: .whitespaces)
        }
        return b
    }

    /// The text of each song in one pack type's packs, in sequence, as bytes; and the songs whose text was cut by a
    /// missing pack. Each pack says which song its first character belongs to and how many of that song's characters
    /// came before it; when that does not follow from the packs before (a pack was dropped), the text being built is
    /// left out and reading starts again where the pack says.
    static func strings(_ packs: [ArraySlice<UInt8>], doubleByte: Bool) -> ([Int: [UInt8]], Set<Int>) {
        var out: [Int: [UInt8]] = [:]
        var broken = Set<Int>()
        var song: Int? = nil
        var buf: [UInt8] = []
        var bufBroken = false
        var lastSeq: Int? = nil
        let unit = doubleByte ? 2 : 1
        for p in packs {
            let s = p.startIndex
            let packSong = Int(p[s + 1] & 0x7F)
            let position = Int(p[s + 3] & 0x0F)
            let seq = Int(p[s + 2])
            let chars = buf.count / unit
            let follows = song == packSong && (position == chars || (position == 15 && chars >= 15))
                && (lastSeq.map { seq == ($0 + 1) & 0xFF } ?? true)
            if song == nil {
                song = packSong
                bufBroken = position != 0
            } else if !follows {
                // Something is missing before this pack.
                if let cur = song {
                    if !buf.isEmpty || bufBroken { broken.insert(cur) }
                    // Whole songs that fell in the gap.
                    if packSong > cur + 1 { for x in (cur + 1)..<packSong where out[x] == nil { broken.insert(x) } }
                }
                song = packSong
                buf = []
                bufBroken = position != 0
            }
            lastSeq = seq
            var i = s + 4
            while i + unit <= s + 16 {
                let isEnd = doubleByte ? (p[i] == 0 && p[i + 1] == 0) : p[i] == 0
                if isEnd {
                    if let cur = song {
                        if bufBroken { broken.insert(cur) } else if !buf.isEmpty { out[cur] = buf }
                        song = cur + 1
                    }
                    buf = []
                    bufBroken = false
                } else {
                    buf.append(contentsOf: p[i..<(i + unit)])
                }
                i += unit
            }
        }
        if let cur = song, !buf.isEmpty || bufBroken { broken.insert(cur) }
        return (out, broken.subtracting(out.keys))
    }

    /// Bytes as text in the block's characters; nil when they cannot be read.
    static func decodeText(_ bytes: [UInt8], _ chars: Characters) -> String? {
        switch chars {
        case .latin1:
            return String(bytes.map { Character(Unicode.Scalar($0)) })
        case .ascii:
            guard bytes.allSatisfy({ $0 < 0x80 }) else { return nil }
            return String(decoding: bytes, as: UTF8.self)
        case .msJIS:
            return String(data: Data(bytes), encoding: .shiftJIS)
        case .korean, .mandarin, .unknown:
            return nil
        }
    }
}
