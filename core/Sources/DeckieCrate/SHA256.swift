import Foundation

/// SHA-256 (FIPS 180-4), written out here so the crate needs no library on any system. Feed it bytes with `update`,
/// in as many pieces as convenient, then take the digest with `finalize`. Internal, so it never clashes with
/// CryptoKit's type of the same name in the Apple apps; `CrateIDs` is the public way in.
struct SHA256: Sendable {
    private var h: [UInt32] = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
                               0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]
    /// Bytes waiting for a whole 64-byte block.
    private var pending: [UInt8] = []
    /// Bytes fed so far.
    private var length: UInt64 = 0

    init() {}

    mutating func update(_ data: Data) { data.withUnsafeBytes { update($0) } }
    mutating func update(_ bytes: [UInt8]) { bytes.withUnsafeBytes { update($0) } }

    mutating func update(_ bytes: UnsafeRawBufferPointer) {
        length &+= UInt64(bytes.count)
        var i = 0
        if !pending.isEmpty {
            i = min(64 - pending.count, bytes.count)
            pending += bytes[0..<i]
            guard pending.count == 64 else { return }
            pending.withUnsafeBytes { compress($0) }
            pending.removeAll(keepingCapacity: true)
        }
        while bytes.count - i >= 64 {
            compress(UnsafeRawBufferPointer(rebasing: bytes[i..<(i + 64)]))
            i += 64
        }
        pending += bytes[i...]
    }

    /// The 32-byte digest of everything fed so far.
    func finalize() -> [UInt8] {
        var last = self
        let bits = length &* 8
        // A 1 bit, zeros up to 8 bytes short of a block's end, then the length in bits, big-endian.
        var tail: [UInt8] = [0x80] + [UInt8](repeating: 0, count: (55 - Int(length % 64) + 64) % 64)
        tail += (0..<8).map { UInt8(truncatingIfNeeded: bits >> (56 - 8 * $0)) }
        last.update(tail)
        return last.h.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (24 - 8 * $0)) } }
    }

    private static let k: [UInt32] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
        0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
        0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
        0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
        0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
        0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
        0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ]

    /// Mixes one 64-byte block into the state. Written for a debug build too, where the engine hashes every audio
    /// file it analyses: the rotations use the masking shifts (`&>>`, `&<<`), which compile to single instructions
    /// there while `>>` and `<<` are generic calls, and the loops run on raw pointers. About 60 MB a second in a debug
    /// build, ten times the plain version.
    private mutating func compress(_ block: UnsafeRawBufferPointer) {
        let bytes = block.baseAddress!.assumingMemoryBound(to: UInt8.self)
        withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 64) { wb in
            let w = wb.baseAddress!
            var t = 0
            while t < 16 {
                let o = bytes + 4 * t
                w[t] = UInt32(o[0]) &<< 24 | UInt32(o[1]) &<< 16 | UInt32(o[2]) &<< 8 | UInt32(o[3])
                t += 1
            }
            while t < 64 {
                let x = w[t - 15], y = w[t - 2]
                let s0 = (x &>> 7 | x &<< 25) ^ (x &>> 18 | x &<< 14) ^ (x &>> 3)
                let s1 = (y &>> 17 | y &<< 15) ^ (y &>> 19 | y &<< 13) ^ (y &>> 10)
                w[t] = w[t - 16] &+ s0 &+ w[t - 7] &+ s1
                t += 1
            }
            Self.k.withUnsafeBufferPointer { kb in
                h.withUnsafeMutableBufferPointer { hb in
                    let k = kb.baseAddress!, s = hb.baseAddress!
                    var a = s[0], b = s[1], c = s[2], d = s[3], e = s[4], f = s[5], g = s[6], hh = s[7]
                    var t = 0
                    while t < 64 {
                        let s1 = (e &>> 6 | e &<< 26) ^ (e &>> 11 | e &<< 21) ^ (e &>> 25 | e &<< 7)
                        let t1 = hh &+ s1 &+ ((e & f) ^ (~e & g)) &+ k[t] &+ w[t]
                        let s0 = (a &>> 2 | a &<< 30) ^ (a &>> 13 | a &<< 19) ^ (a &>> 22 | a &<< 10)
                        let t2 = s0 &+ ((a & b) ^ (a & c) ^ (b & c))
                        hh = g; g = f; f = e; e = d &+ t1; d = c; c = b; b = a; a = t1 &+ t2
                        t += 1
                    }
                    s[0] = s[0] &+ a; s[1] = s[1] &+ b; s[2] = s[2] &+ c; s[3] = s[3] &+ d
                    s[4] = s[4] &+ e; s[5] = s[5] &+ f; s[6] = s[6] &+ g; s[7] = s[7] &+ hh
                }
            }
        }
    }
}
