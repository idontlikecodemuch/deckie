import Foundation
import DeckieDecode

/// Damages one frame of an MPEG-1 layer III file on purpose, as core/Tools/make_damaged_mp3_fixture.py made
/// tone_damaged.mp3 (that script's comment says where a frame's main data is): the bytes lying wholly inside the
/// Huffman codes of one granule of one channel of one frame are set to one value, so that the decoder's big values run
/// past the granule's end; frame headers and side information stay as they are, and so does the file's length. The
/// DeckieDecode tests check this gives the script's bytes; the engine's and the builder's tests use it on an MP3 of
/// the test track.
public enum MP3Damage {
    /// One granule of one channel, as its side information gives it.
    public struct Granule: Sendable {
        public var part23Length: Int, bigValues: Int, scalefacCompress: Int
        /// False for the long blocks the damage is placed in (window switching off).
        public var windowSwitching: Bool
    }

    /// One frame: where it is, where its main data begins (main_data_begin bytes back in the bit reservoir) and its
    /// granules ([granule][channel]).
    public struct Frame: Sendable {
        public var offset: Int, length: Int
        /// The file offset of the frame's own main data, after its header and side information.
        public var mainOffset: Int
        public var mainDataBegin: Int
        public var scfsi: [Int]
        public var granules: [[Granule]]
    }

    static let kbps = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]
    static let rates = [44100, 48000, 32000]
    static let slen: [(Int, Int)] = [(0, 0), (0, 1), (0, 2), (0, 3), (3, 0), (1, 1), (1, 2), (1, 3), (2, 1), (2, 2),
                                     (2, 3), (3, 1), (3, 2), (3, 3), (4, 2), (4, 3)]

    /// The MPEG-1 layer III frames after the file's ID3v2 tag, up to the first bytes that are not such a frame.
    public static func frames(_ b: [UInt8]) -> [Frame] {
        var o = 0
        if b.count >= 10, b[0] == 0x49, b[1] == 0x44, b[2] == 0x33 {
            o = 10 + (Int(b[6]) << 21 | Int(b[7]) << 14 | Int(b[8]) << 7 | Int(b[9]))
        }
        var out: [Frame] = []
        while o + 36 <= b.count, b[o] == 0xFF, b[o + 1] & 0xFE == 0xFA, b[o + 2] >> 4 != 0, b[o + 2] >> 4 != 15,
              (b[o + 2] >> 2) & 3 != 3 {
            let length = 144_000 * kbps[Int(b[o + 2] >> 4)] / rates[Int((b[o + 2] >> 2) & 3)] + Int((b[o + 2] >> 1) & 1)
            let mono = b[o + 3] >> 6 == 3
            let side = o + 4 + (b[o + 1] & 1 == 1 ? 0 : 2)  // a CRC follows the header when the protection bit is 0
            var pos = side * 8
            func get(_ n: Int) -> Int {
                var v = 0
                for _ in 0..<n {
                    v = v << 1 | Int(b[pos >> 3] >> (7 - UInt8(pos & 7)) & 1)
                    pos += 1
                }
                return v
            }
            let mainDataBegin = get(9)
            _ = get(mono ? 5 : 3)  // private bits
            let scfsi = (0..<(mono ? 1 : 2)).map { _ in get(4) }
            var granules: [[Granule]] = []
            for _ in 0..<2 {
                var channels: [Granule] = []
                for _ in 0..<(mono ? 1 : 2) {
                    let part23 = get(12), bigValues = get(9)
                    _ = get(8)  // global gain
                    let compress = get(4), switching = get(1) == 1
                    _ = get(switching ? 2 + 1 + 10 + 9 : 15 + 4 + 3)  // block type, tables, gains or region counts
                    _ = get(3)  // preflag, scalefac_scale, count1table_select
                    channels.append(Granule(part23Length: part23, bigValues: bigValues, scalefacCompress: compress,
                                            windowSwitching: switching))
                }
                granules.append(channels)
            }
            out.append(Frame(offset: o, length: length, mainOffset: side + (mono ? 17 : 32), mainDataBegin: mainDataBegin,
                             scfsi: scfsi, granules: granules))
            o += length
        }
        return out
    }

    /// Whether the first frame holds a Xing or Info tag (so is not audio).
    static func hasTagFrame(_ b: [UInt8], _ fs: [Frame]) -> Bool {
        guard let f = fs.first, f.mainOffset + 4 <= b.count else { return false }
        let word = Array(b[f.mainOffset..<(f.mainOffset + 4)])
        return word == Array("Xing".utf8) || word == Array("Info".utf8)
    }

    /// `data` with the Huffman codes of granule `granule`, channel `channel` of audio frame `frame` (counted from 0,
    /// the tag frame not counted) set to `byte`; nil when there is no such frame or the granule uses short blocks.
    public static func damaged(_ data: Data, frame: Int, granule: Int, channel: Int, byte: UInt8) -> Data? {
        var b = [UInt8](data)
        let fs = frames(b)
        let k = frame + (hasTagFrame(b, fs) ? 1 : 0)
        guard k < fs.count, granule < 2, channel < fs[k].granules[granule].count else { return nil }
        // The main data stream: the file offsets of its bytes, frame after frame.
        var stream: [Int] = [], starts: [Int] = []
        for f in fs {
            starts.append(stream.count)
            stream += Array(f.mainOffset..<(f.offset + f.length))
        }
        let f = fs[k]
        var begin = (starts[k] - f.mainDataBegin) * 8
        for gr in 0...granule {
            for ch in 0..<f.granules[gr].count where (gr, ch) < (granule, channel) {
                begin += f.granules[gr][ch].part23Length
            }
        }
        let g = f.granules[granule][channel]
        guard !g.windowSwitching, begin >= 0 else { return nil }
        // Long blocks: bands 0-5 and 6-10 take slen1 bits each, 11-15 and 16-20 slen2; in granule 1 a group whose
        // scfsi bit is set reuses granule 0's scale factors and is not sent.
        let (slen1, slen2) = slen[g.scalefacCompress]
        let groups = [6 * slen1, 5 * slen1, 5 * slen2, 5 * slen2]
        let scfsi = granule == 1 ? f.scfsi[channel] : 0
        let scaleBits = groups.enumerated().filter { scfsi & (8 >> $0.offset) == 0 }.map(\.element).reduce(0, +)
        let first = (begin + scaleBits + 7) / 8, last = (begin + g.part23Length) / 8  // whole bytes only
        guard first < last, last <= stream.count else { return nil }
        for i in first..<last { b[stream[i]] = byte }
        return Data(b)
    }

    /// A copy of the MP3 at `source`, written to `output`, with one frame near `seconds` damaged so that the decoder
    /// flags it: the granules of that frame with long blocks are tried, most big values first, with a few byte values,
    /// until `AudioDecoder.decodeReporting` reports exactly one damaged frame (which byte works depends on the
    /// encoder's bits, so on the ffmpeg build that made the MP3). Returns that frame, or nil when none of the tries is
    /// flagged.
    public static func damagedCopy(of source: URL, nearSeconds seconds: Double, to output: URL) throws -> DamagedFrame? {
        let data = try Data(contentsOf: source)
        let b = [UInt8](data)
        let fs = frames(b)
        guard let header = fs.first else { return nil }
        let rate = rates[Int((b[header.offset + 2] >> 2) & 3)]
        let audio = fs.dropFirst(hasTagFrame(b, fs) ? 1 : 0)
        for frame in Int(seconds * Double(rate) / 1152)..<(Int(seconds * Double(rate) / 1152) + 8) where frame < audio.count {
            let f = audio[audio.startIndex + frame]
            let choices = (0..<2).flatMap { gr in (0..<f.granules[gr].count).map { (gr, $0) } }
                .filter { !f.granules[$0.0][$0.1].windowSwitching }
                .sorted { f.granules[$0.0][$0.1].bigValues > f.granules[$1.0][$1.1].bigValues }
            for (gr, ch) in choices {
                for byte: UInt8 in [0x33, 0x30, 0x60, 0x81, 0x3E, 0x06] {
                    guard let d = damaged(data, frame: frame, granule: gr, channel: ch, byte: byte) else { continue }
                    try d.write(to: output)
                    if let found = try? AudioDecoder.decodeReporting(output).damagedFrames, found.count == 1 {
                        return found[0]
                    }
                }
            }
        }
        return nil
    }
}
