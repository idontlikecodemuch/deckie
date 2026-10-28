/// IEEE 754 half precision (float16), the sidecars' number format, converted by hand: Swift's `Float16` type is
/// missing on Intel Macs, and the crate must read the same everywhere.
public enum Half {
    /// The float16 nearest to `x` (ties to even), as its 16 bits. Values beyond the range become infinity; NaN stays NaN.
    public static func bits(_ x: Double) -> UInt16 {
        let b = x.bitPattern
        let sign = UInt16(truncatingIfNeeded: (b >> 48) & 0x8000)
        let exponent = Int((b >> 52) & 0x7ff)
        let fraction = b & 0x000f_ffff_ffff_ffff
        if exponent == 0x7ff { return sign | 0x7c00 | (fraction != 0 ? 0x200 : 0) }
        let e = exponent - 1023 + 15
        if e >= 31 { return sign | 0x7c00 }
        if e <= 0 {
            // A float16 subnormal, m * 2^-24 with m below 2^10, or zero.
            if e < -10 { return sign }
            let m = fraction | (1 << 52)
            let shift = UInt64(43 - e)
            var h = m >> shift
            let rest = m & ((1 << shift) - 1), halfway = UInt64(1) << (shift - 1)
            if rest > halfway || (rest == halfway && h & 1 == 1) { h += 1 }
            return sign | UInt16(h)
        }
        var h = UInt64(e) << 10 | fraction >> 42
        let rest = fraction & ((1 << 42) - 1), halfway = UInt64(1) << 41
        if rest > halfway || (rest == halfway && h & 1 == 1) { h += 1 }  // a carry into the exponent is correct
        return sign | UInt16(h)
    }

    /// The value of a float16, exactly.
    public static func value(_ h: UInt16) -> Double {
        let negative = h & 0x8000 != 0
        let exponent = Int((h >> 10) & 0x1f)
        let fraction = Double(h & 0x3ff)
        let magnitude: Double
        switch exponent {
        case 0: magnitude = fraction * 0x1p-24
        case 31: magnitude = fraction == 0 ? .infinity : .nan
        default: magnitude = (1 + fraction / 1024) * Double(sign: .plus, exponent: exponent - 15, significand: 1)
        }
        return negative ? -magnitude : magnitude
    }

    /// `x` rounded to the nearest float16, as a Double: what a sidecar gives back for `x`.
    public static func rounded(_ x: Double) -> Double { value(bits(x)) }
}
