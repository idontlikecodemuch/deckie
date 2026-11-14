import Foundation

/// A music CD's table of contents as MusicBrainz counts it, and its MusicBrainz disc id, written from MusicBrainz's
/// own description ("Disc ID Calculation", musicbrainz.org/doc/Disc_ID_Calculation, read Nov 14, 2026), not from
/// libdiscid: libdiscid is LGPL 2.1 or later, which Deckie's rule ships only as a separate library file, and its
/// recipe is short enough to write.
///
/// The recipe: the audio tracks only (an enhanced CD's data track is not counted, and the lead-out is where the audio
/// ends: the data session's start less 11,400 sectors); every address is the sector number plus 150 (the two-second
/// lead-in before sector 0); then the SHA-1 of the ASCII text made of the first track's number (`%02X`), the last
/// track's (`%02X`), the lead-out (`%08X`) and 99 track offsets (`%08X` each, 0 for the numbers not on the disc), in
/// upper-case hexadecimal; then that digest in Base64 with `.` for `+`, `_` for `/` and `-` for `=`: 28 characters.
public struct DiscTable: Sendable, Equatable, Codable {
    public var first: Int
    public var last: Int
    /// Where the audio ends, with the 150 added.
    public var leadOut: Int
    /// Each audio track's start, with the 150 added, in order from `first`.
    public var offsets: [Int]

    public init(first: Int, last: Int, leadOut: Int, offsets: [Int]) {
        self.first = first; self.last = last; self.leadOut = leadOut; self.offsets = offsets
    }

    /// From sector numbers as a drive reports them (starting at 0), the audio tracks' numbers and starts and the end
    /// of the audio.
    public init(tracks: [(number: Int, start: Int)], audioEnd: Int) {
        let t = tracks.sorted { $0.number < $1.number }
        first = t.first?.number ?? 1
        last = t.last?.number ?? 1
        leadOut = audioEnd + 150
        offsets = t.map { $0.start + 150 }
    }

    public var musicBrainzId: String {
        var s = String(format: "%02X%02X%08X", first, last, leadOut)
        for i in 0..<99 {
            let n = first + i
            let off = (n <= last && i < offsets.count) ? offsets[i] : 0
            s += String(format: "%08X", off)
        }
        let digest = SHA1.hash(Array(s.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: ".").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "-")
    }

    /// The `toc` parameter: first track, last track, lead-out, then each track's offset, joined by `+`.
    public var tocParameter: String {
        ([first, last, leadOut] + offsets).map(String.init).joined(separator: "+")
    }

    /// Each track's length in seconds, from the table (75 sectors a second).
    public var seconds: [Double] {
        offsets.enumerated().map { i, o in Double((i + 1 < offsets.count ? offsets[i + 1] : leadOut) - o) / 75 }
    }
}

/// SHA-1 (FIPS 180-4), for the disc id only: no other part of Deckie uses it, and Foundation has none on Linux and
/// Windows.
enum SHA1 {
    static func hash(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x67452301, 0xEFCDAB89, 0x98BADCFE, 0x10325476, 0xC3D2E1F0]
        var m = message
        let bits = UInt64(message.count) * 8
        m.append(0x80)
        while m.count % 64 != 56 { m.append(0) }
        for i in (0..<8).reversed() { m.append(UInt8((bits >> (UInt64(i) * 8)) & 0xFF)) }
        var w = [UInt32](repeating: 0, count: 80)
        for chunk in stride(from: 0, to: m.count, by: 64) {
            for i in 0..<16 {
                let b = chunk + i * 4
                w[i] = UInt32(m[b]) << 24 | UInt32(m[b + 1]) << 16 | UInt32(m[b + 2]) << 8 | UInt32(m[b + 3])
            }
            for i in 16..<80 {
                let x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]
                w[i] = (x << 1) | (x >> 31)
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4]
            for i in 0..<80 {
                let f: UInt32, k: UInt32
                switch i {
                case 0..<20: f = (b & c) | (~b & d); k = 0x5A827999
                case 20..<40: f = b ^ c ^ d; k = 0x6ED9EBA1
                case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8F1BBCDC
                default: f = b ^ c ^ d; k = 0xCA62C1D6
                }
                let t = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ w[i]
                e = d; d = c; c = (b << 30) | (b >> 2); b = a; a = t
            }
            h[0] = h[0] &+ a; h[1] = h[1] &+ b; h[2] = h[2] &+ c; h[3] = h[3] &+ d; h[4] = h[4] &+ e
        }
        return h.flatMap { v in (0..<4).map { UInt8((v >> (24 - UInt32($0) * 8)) & 0xFF) } }
    }
}
