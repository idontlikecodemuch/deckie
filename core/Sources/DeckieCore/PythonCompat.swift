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

    /// `numpy.sum` of a contiguous float64 array, added in numpy's order: pairwise in blocks of up to 128 values, each
    /// block with eight running sums combined as ((s0 + s1) + (s2 + s3)) + ((s4 + s5) + (s6 + s7)) and the remainder
    /// added after; fewer than eight values are added in turn from 0. (Checked against numpy 2.5 on 2,000 arrays of
    /// each of eight lengths: identical to the last bit.) `reduce(0, +)` adds in turn, which differs in the last bits
    /// from 8 values up.
    public static func pairwiseSum(_ a: UnsafeBufferPointer<Double>) -> Double {
        let n = a.count
        if n < 8 {
            var s = 0.0
            for v in a { s += v }
            return s
        }
        if n <= 128 {
            var r0 = a[0], r1 = a[1], r2 = a[2], r3 = a[3], r4 = a[4], r5 = a[5], r6 = a[6], r7 = a[7]
            var i = 8
            while i < n - n % 8 {
                r0 += a[i]; r1 += a[i + 1]; r2 += a[i + 2]; r3 += a[i + 3]
                r4 += a[i + 4]; r5 += a[i + 5]; r6 += a[i + 6]; r7 += a[i + 7]
                i += 8
            }
            var s = ((r0 + r1) + (r2 + r3)) + ((r4 + r5) + (r6 + r7))
            while i < n { s += a[i]; i += 1 }
            return s
        }
        var half = n / 2
        half -= half % 8
        return pairwiseSum(UnsafeBufferPointer(rebasing: a[0..<half]))
            + pairwiseSum(UnsafeBufferPointer(rebasing: a[half..<n]))
    }

    /// `numpy.sum` of an array (pairwise, see above).
    public static func pairwiseSum(_ a: [Double]) -> Double { a.withUnsafeBufferPointer { pairwiseSum($0) } }

    /// `numpy.mean` of a non-empty contiguous array or of a Python list: the pairwise sum divided by the count.
    public static func pairwiseMean(_ a: [Double]) -> Double { pairwiseSum(a) / Double(a.count) }

    /// `numpy.dot` of two float64 vectors as numpy's OpenBLAS computes it for short vectors (fewer than 16 values,
    /// such as the 12 pitch classes): the products added in turn, each with a fused multiply-add. (Checked against
    /// numpy 2.5 with OpenBLAS 0.3.34 on x86-64: identical on 5,000 pairs of 12-value vectors, where multiplying and
    /// then adding differs in the last bit about half the time.) Another BLAS may round the last bit differently.
    public static func dot(_ x: [Double], _ y: [Double]) -> Double {
        precondition(x.count == y.count, "dot of \(x.count) and \(y.count) values")
        var s = 0.0
        for i in x.indices { s.addProduct(x[i], y[i]) }
        return s
    }

    /// `numpy.linalg.norm` of a float64 vector: the square root of its dot product with itself.
    public static func norm(_ x: [Double]) -> Double { dot(x, x).squareRoot() }

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

    /// `numpy.searchsorted(sorted, x)` with numpy's default `side="left"`: how many values are below `x`, which is
    /// the index of the first value at least `x`.
    public static func countBelow(_ x: Double, in sorted: [Double]) -> Int {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] < x { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }
}
