import Foundation

/// Byte fixtures for music CDs, made from the formats' descriptions (never read from a real disc): CD-Text packs as
/// Red Book annex J and MMC's READ TOC format 5 lay them out, and the table of contents as format 0 gives it. Used by
/// the CD-Text decoder's tests and by the stand-in drive in Desk's tests.
public enum DiscFixture {
    /// The format's check: CRC-16, polynomial 0x1021, from 0, over bytes 0 to 15, stored inverted.
    public static func crc(_ bytes: ArraySlice<UInt8>) -> UInt16 {
        var c: UInt16 = 0
        for b in bytes {
            c ^= UInt16(b) << 8
            for _ in 0..<8 { c = c & 0x8000 != 0 ? (c << 1) ^ 0x1021 : c << 1 }
        }
        return c ^ 0xFFFF
    }

    /// One block's packs: for each pack type, the text of the disc (index 0) and each song (1...), one string each,
    /// cut into packs of twelve bytes with the song and character position each pack starts at; then the size
    /// information. `charset` is the size information's code (0x00 ISO 8859-1, 0x01 ASCII, 0x80 MS-JIS).
    /// Strings are given as bytes, already in the block's characters.
    public static func packs(_ texts: [(type: UInt8, strings: [[UInt8]])], block: UInt8 = 0, charset: UInt8 = 0x00,
                             doubleByte: Bool = false, firstSong: UInt8 = 1, lastSong: UInt8? = nil,
                             language: UInt8 = 0x09, withSizeInfo: Bool = true) -> [[UInt8]] {
        var out: [[UInt8]] = []
        var seq: UInt8 = 0
        var counts = [UInt8](repeating: 0, count: 16)
        let unit = doubleByte ? 2 : 1
        for (type, strings) in texts {
            // The stream: each string then its end mark; each byte remembers its song and position.
            var stream: [(byte: UInt8, song: Int, pos: Int)] = []
            for (song, s) in strings.enumerated() {
                for (i, b) in s.enumerated() { stream.append((b, song, i / unit)) }
                for _ in 0..<unit { stream.append((0, song, s.count / unit)) }
            }
            var i = 0
            while i < stream.count {
                let first = stream[i]
                var p: [UInt8] = [type, UInt8(first.song), seq,
                                  (doubleByte ? 0x80 : 0) | (block << 4) | UInt8(min(first.pos, 15))]
                for k in 0..<12 { p.append(i + k < stream.count ? stream[i + k].byte : 0) }
                let c = crc(p[0..<16])
                p += [UInt8(c >> 8), UInt8(c & 0xFF)]
                out.append(p)
                seq &+= 1
                counts[Int(type - 0x80)] &+= 1
                i += 12
            }
        }
        if withSizeInfo {
            counts[0x0F] = 3
            var info = [UInt8](repeating: 0, count: 36)
            info[0] = charset; info[1] = firstSong
            info[2] = lastSong ?? UInt8(max(1, (texts.first?.strings.count ?? 2) - 1))
            info[3] = 0
            for k in 0..<16 { info[4 + k] = counts[k] }
            info[20 + Int(block)] = seq &+ 2
            info[28 + Int(block)] = language
            for part in 0..<3 {
                var p: [UInt8] = [0x8F, UInt8(part), seq, block << 4]
                p += info[(part * 12)..<(part * 12 + 12)]
                let c = crc(p[0..<16])
                p += [UInt8(c >> 8), UInt8(c & 0xFF)]
                out.append(p)
                seq &+= 1
            }
        }
        return out
    }

    /// The drive's answer: a four-byte header (the length of what follows, two reserved bytes), then the packs.
    public static func response(_ packs: [[UInt8]]) -> [UInt8] {
        let n = packs.count * 18 + 2
        return [UInt8(n >> 8), UInt8(n & 0xFF), 0, 0] + packs.flatMap { $0 }
    }

    /// Latin-1 bytes of a string (each character's code point, which must be below 256).
    public static func latin1(_ s: String) -> [UInt8] { s.unicodeScalars.map { UInt8($0.value) } }

    /// The answer to "read table of contents", format 0, sector addresses: track starts (audio unless listed in
    /// `data`), and the lead-out.
    public static func toc(starts: [Int], leadOut: Int, data: Set<Int> = [], first: Int = 1) -> [UInt8] {
        var d: [UInt8] = []
        func entry(_ number: Int, _ lba: Int, _ isData: Bool) {
            let v = UInt32(bitPattern: Int32(lba))
            d += [0, 0x10 | (isData ? 0x04 : 0x00), UInt8(number), 0,
                  UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
        }
        for (i, s) in starts.enumerated() { entry(first + i, s, data.contains(first + i)) }
        entry(0xAA, leadOut, false)
        let n = d.count + 2
        return [UInt8(n >> 8), UInt8(n & 0xFF), UInt8(first), UInt8(first + starts.count - 1)] + d
    }

    /// A stand-in drive's folder (see DeckieDisc's StandInDrive): the table, the CD-Text answer (none when nil) and
    /// the sound of each song given as samples (stereo 16-bit, interleaved), laid end to end from sector 0, each
    /// padded to whole sectors with `gap` sectors of silence before every song after the first.
    @discardableResult
    public static func writeStandIn(_ folder: URL, songs: [[Int16]], cdText: [UInt8]?, gap: Int = 0) throws -> [Int] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var pcm = Data()
        var starts: [Int] = []
        for (i, s) in songs.enumerated() {
            if i > 0 { pcm.append(Data(count: gap * 2352)) }
            starts.append(pcm.count / 2352)
            var bytes = s.withUnsafeBufferPointer { Data(buffer: $0) }
            let pad = (2352 - bytes.count % 2352) % 2352
            bytes.append(Data(count: pad))
            pcm.append(bytes)
        }
        let leadOut = pcm.count / 2352
        try pcm.write(to: folder.appendingPathComponent("audio.pcm"))
        try Data(toc(starts: starts, leadOut: leadOut)).write(to: folder.appendingPathComponent("toc.bin"))
        if let cdText { try Data(cdText).write(to: folder.appendingPathComponent("cdtext.bin")) }
        return starts
    }
}
