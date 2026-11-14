import Foundation

// The compressed fingerprint AcoustID's web service takes, and reading it back. Ported from Chromaprint's
// MIT-licensed src/fingerprint_compressor.cpp and src/fingerprint_decompressor.cpp, with the bit packing of
// src/utils/pack_int3_array.h and pack_int5_array.h and the alphabet of src/utils/base64.h.
// Copyright (C) 2010-2016 Lukas Lalinsky; MIT licence, kept in LICENSE-chromaprint beside this file.
//
// The format: one byte for the algorithm, three for the number of frames (big-endian); then each frame XORed with
// the one before it (the first as it is), written as the gaps between its set bits from the lowest, each gap a 3-bit
// number ending with a 0 for the frame; a gap of 7 or more is written as 7 there and the rest (gap - 7) as a 5-bit
// number in a second list after the first. Both lists are packed lowest bit first. The bytes are in base64 with `-`
// and `_` for the last two letters and no `=` at the end.

extension Chromaprint {
    static let base64Letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_".utf8)

    /// The compressed, base64 form of a raw fingerprint.
    public static func compress(_ frames: [UInt32], algorithm: Int = algorithm) -> String {
        var normal: [UInt8] = [], exceptional: [UInt8] = []
        normal.reserveCapacity(frames.count * 8)
        var previous: UInt32 = 0
        for (i, f) in frames.enumerated() {
            var x = i == 0 ? f : f ^ previous
            previous = f
            var bit = 1, last = 0
            while x != 0 {
                if x & 1 != 0 {
                    let gap = bit - last
                    if gap >= 7 {
                        normal.append(7); exceptional.append(UInt8(gap - 7))
                    } else {
                        normal.append(UInt8(gap))
                    }
                    last = bit
                }
                x >>= 1
                bit += 1
            }
            normal.append(0)
        }
        var bytes: [UInt8] = [UInt8(algorithm & 255), UInt8((frames.count >> 16) & 255),
                              UInt8((frames.count >> 8) & 255), UInt8(frames.count & 255)]
        bytes += pack(normal, bits: 3)
        bytes += pack(exceptional, bits: 5)
        return base64(bytes)
    }

    /// The raw fingerprint and algorithm in a compressed one; nil if it is not one.
    public static func decompress(_ text: String) -> (algorithm: Int, frames: [UInt32])? {
        guard let bytes = unbase64(text), bytes.count >= 4 else { return nil }
        let algorithm = Int(bytes[0])
        let count = Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        let body = Array(bytes[4...])
        // Read 3-bit numbers until `count` frames have ended (a 0 each).
        let all3 = unpack(body, bits: 3)
        var normal: [UInt8] = []
        var ended = 0, i = 0
        while ended < count {
            guard i < all3.count else { return nil }
            normal.append(all3[i])
            if all3[i] == 0 { ended += 1 }
            i += 1
        }
        let used = (normal.count * 3 + 7) / 8
        let exceptional = unpack(Array(body[min(used, body.count)...]), bits: 5)
        var frames: [UInt32] = []
        frames.reserveCapacity(count)
        var x: UInt32 = 0, bit = 0, e = 0
        for v in normal {
            if v == 0 {
                let f = frames.isEmpty ? x : frames[frames.count - 1] ^ x
                frames.append(f)
                x = 0; bit = 0
                continue
            }
            var gap = Int(v)
            if v == 7 {
                guard e < exceptional.count else { return nil }
                gap += Int(exceptional[e]); e += 1
            }
            bit += gap
            guard bit <= 32 else { return nil }
            x |= 1 << UInt32(bit - 1)
        }
        return (algorithm, frames)
    }

    /// Small numbers of `bits` bits each, packed lowest bit first.
    static func pack(_ values: [UInt8], bits: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: (values.count * bits + 7) / 8)
        var pos = 0
        for v in values {
            for b in 0..<bits where (v >> UInt8(b)) & 1 != 0 {
                out[(pos + b) / 8] |= 1 << UInt8((pos + b) % 8)
            }
            pos += bits
        }
        return out
    }

    /// Every whole `bits`-bit number in `bytes`, lowest bit first.
    static func unpack(_ bytes: [UInt8], bits: Int) -> [UInt8] {
        let n = bytes.count * 8 / bits
        var out = [UInt8](repeating: 0, count: n)
        for i in 0..<n {
            var v: UInt8 = 0
            for b in 0..<bits {
                let p = i * bits + b
                if (bytes[p / 8] >> UInt8(p % 8)) & 1 != 0 { v |= 1 << UInt8(b) }
            }
            out[i] = v
        }
        return out
    }

    static func base64(_ bytes: [UInt8]) -> String {
        var out: [UInt8] = []
        out.reserveCapacity((bytes.count * 4 + 2) / 3)
        var i = 0
        while i < bytes.count {
            let b0 = Int(bytes[i]), b1 = i + 1 < bytes.count ? Int(bytes[i + 1]) : 0, b2 = i + 2 < bytes.count ? Int(bytes[i + 2]) : 0
            let left = bytes.count - i
            out.append(base64Letters[b0 >> 2])
            out.append(base64Letters[((b0 & 3) << 4) | (b1 >> 4)])
            if left > 1 { out.append(base64Letters[((b1 & 15) << 2) | (b2 >> 6)]) }
            if left > 2 { out.append(base64Letters[b2 & 63]) }
            i += 3
        }
        return String(decoding: out, as: UTF8.self)
    }

    static func unbase64(_ text: String) -> [UInt8]? {
        var value = [Int](repeating: -1, count: 256)
        for (i, c) in base64Letters.enumerated() { value[Int(c)] = i }
        let chars = Array(text.utf8)
        var out: [UInt8] = []
        var acc = 0, n = 0
        for c in chars {
            let v = value[Int(c)]
            guard v >= 0 else { return nil }
            acc = (acc << 6) | v
            n += 6
            if n >= 8 {
                n -= 8
                out.append(UInt8((acc >> n) & 255))
            }
        }
        return out
    }
}
