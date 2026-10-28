import Foundation

/// Small helpers that make Swift arithmetic land on the same numbers as the Python and numpy calls in the lab
/// scripts (mixer/analyze.py, mixer/score.py). The parity tests depend on these details.
public enum Py {
    /// Python's `round(x, places)`: the exact binary value, correctly rounded, ties to even.
    /// C's printf does the same, so the number is formatted and parsed back.
    public static func round(_ x: Double, _ places: Int) -> Double {
        Double(String(format: "%.\(places)f", x)) ?? x
    }

    /// `numpy.round` and Python's `round()` to a whole number: ties to even (Swift's `.rounded()` is ties away).
    @inlinable public static func roundEven(_ x: Double) -> Double { x.rounded(.toNearestOrEven) }

    /// Python's `%` on integers: the result takes the sign of the divisor, so it is never negative here.
    @inlinable public static func mod(_ a: Int, _ n: Int) -> Int {
        let r = a % n
        return r < 0 ? r + n : r
    }

    /// `numpy.mod` for a positive divisor: result in `[0, n)`.
    @inlinable public static func fmod(_ a: Double, _ n: Double) -> Double {
        let r = Foundation.fmod(a, n)
        return r < 0 ? r + n : r
    }

    /// `numpy.median` of a non-empty array (the mean of the two middle values when the count is even).
    public static func median(_ a: [Double]) -> Double {
        precondition(!a.isEmpty, "median of an empty array")
        let s = a.sorted()
        let n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    /// `numpy.mean` of an array; 0 for an empty one (numpy would warn and give NaN; callers guard).
    @inlinable public static func mean(_ a: [Double]) -> Double {
        a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count)
    }

    /// `numpy.percentile(a, q)` with numpy's default linear method, of a non-empty array: the value at position
    /// (n - 1) q / 100 of the sorted values, interpolated between its neighbours the way numpy's `_lerp` does it
    /// (from the upper neighbour when the fraction is at least one half).
    public static func percentile(_ a: [Double], _ q: Double) -> Double {
        precondition(!a.isEmpty, "percentile of an empty array")
        let s = a.sorted()
        let n = s.count
        let virtual = Double(n - 1) * (q / 100)
        if virtual >= Double(n - 1) { return s[n - 1] }
        if virtual < 0 { return s[0] }
        let below = virtual.rounded(.down)
        let lo = s[Int(below)], hi = s[Int(below) + 1]
        let t = virtual - below
        let diff = hi - lo
        return t >= 0.5 ? hi - diff * (1 - t) : lo + diff * t
    }

    /// Python's `f"{x:.{places}f}"`.
    public static func fixed(_ x: Double, _ places: Int) -> String { String(format: "%.\(places)f", x) }

    /// Python's `f"{x:+.{places}f}"` (always with a sign).
    public static func signedFixed(_ x: Double, _ places: Int) -> String { String(format: "%+.\(places)f", x) }

    /// `numpy.searchsorted(sorted, x, side="right")`: how many values are at most `x`.
    public static func countAtMost(_ x: Double, in sorted: [Double]) -> Int {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] <= x { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}
