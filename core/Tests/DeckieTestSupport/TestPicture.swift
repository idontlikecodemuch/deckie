import Foundation

/// Pictures made by code for the cover tests: a PNG written with no compression (so no compressor is needed), from a
/// function that gives each pixel's colour.
public enum TestPicture {
    /// A PNG, 8 bits a channel, with alpha when `alpha` is true.
    public static func png(width: Int, height: Int, alpha: Bool = false,
                           _ pixel: (Int, Int) -> (UInt8, UInt8, UInt8, UInt8)) -> Data {
        let channels = alpha ? 4 : 3
        var raw = [UInt8]()
        raw.reserveCapacity(height * (1 + width * channels))
        for y in 0..<height {
            raw.append(0)  // no filter
            for x in 0..<width {
                let p = pixel(x, y)
                raw += alpha ? [p.0, p.1, p.2, p.3] : [p.0, p.1, p.2]
            }
        }
        // zlib: a header, the bytes in stored blocks of at most 65,535, and their Adler-32.
        var z: [UInt8] = [0x78, 0x01]
        var at = 0
        repeat {
            let n = min(65535, raw.count - at)
            let last: UInt8 = at + n == raw.count ? 1 : 0
            z += [last, UInt8(n & 0xFF), UInt8(n >> 8), UInt8(~n & 0xFF), UInt8((~n >> 8) & 0xFF)]
            z += raw[at..<(at + n)]
            at += n
        } while at < raw.count
        var a: UInt32 = 1, b: UInt32 = 0
        for v in raw { a = (a + UInt32(v)) % 65521; b = (b + a) % 65521 }
        let adler = b << 16 | a
        z += [UInt8(adler >> 24), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)]

        func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
        func chunk(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let typed = Array(type.utf8) + body
            return be32(UInt32(body.count)) + typed + be32(crc32(typed))
        }
        var out: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        out += chunk("IHDR", be32(UInt32(width)) + be32(UInt32(height)) + [8, alpha ? 6 : 2, 0, 0, 0])
        out += chunk("IDAT", z)
        out += chunk("IEND", [])
        return Data(out)
    }

    static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 == 1 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xFFFF_FFFF
        for b in bytes { c = table[Int((c ^ UInt32(b)) & 0xFF)] ^ (c >> 8) }
        return c ^ 0xFFFF_FFFF
    }

    /// A picture with large shapes and soft shading, something like a record sleeve: a diagonal blend, a disc and
    /// stripes. `seed` changes the colours, so two seeds are two different pictures.
    public static func sleeve(side: Int, seed: Int = 1, width: Int? = nil) -> Data {
        let w = width ?? side, h = side
        return png(width: w, height: h) { x, y in
            let u = Double(x) / Double(w), v = Double(y) / Double(h)
            let d = ((u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5)).squareRoot()
            var r = 40 + 180 * u, g = 60 + 150 * v, b = 200 - 120 * (u + v) / 2
            if d < 0.3 { r = 230 - 300 * d; g = 80 + Double(seed * 37 % 120); b = 60 + 400 * d }
            if Int(v * 24) % 6 == 0 { r *= 0.6; g *= 0.6; b *= 0.6 }
            r += Double((seed * 53) % 40)
            return (UInt8(max(0, min(255, r))), UInt8(max(0, min(255, g))), UInt8(max(0, min(255, b))), 255)
        }
    }

    /// The worst case for a JPEG: every pixel its own random colour.
    public static func noise(side: Int) -> Data {
        var s: UInt64 = 0x9E37_79B9_7F4A_7C15
        return png(width: side, height: side) { _, _ in
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return (UInt8(s >> 56), UInt8(s >> 48 & 0xFF), UInt8(s >> 40 & 0xFF), 255)
        }
    }
}
