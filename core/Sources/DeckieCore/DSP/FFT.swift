import Foundation

// The fast Fourier transform for the DSP pieces (the key estimator's chroma first), in double precision with no
// dependency: a complex radix-2 transform, and a real-input transform built on it by the usual trick of packing the
// even and odd samples into one complex sequence of half the length. Both follow numpy.fft's conventions (no scaling
// on the forward transform, e^(-2 pi i k n / N)) and are tested against it (Tests/DeckieCoreTests/DSPTests.swift,
// fixture written by Tools/make_dsp_fixtures.py). The loops use pointers and `while` so that a debug build, where
// Swift does not inline or unroll, is still quick enough for four minutes of audio.

/// The twiddle factors cos(2 pi k / n) and sin(2 pi k / n) for k in 0..<count (n a power of two, count <= n / 2),
/// each taken from an angle of at most pi / 4 by symmetry, so that cos(pi / 2) is exactly 0, cos(pi / 4) equals
/// sin(pi / 4), and every value is within about half a unit in the last place.
func twiddles(_ n: Int, count: Int) -> (cos: [Double], sin: [Double]) {
    precondition(n & (n - 1) == 0 && count <= max(1, n / 2))
    var c = [Double](repeating: 0, count: count), s = [Double](repeating: 0, count: count)
    let step = 2 * Double.pi / Double(n)
    for k in 0..<count {
        // The angle in eighths of a turn: up to 1/8 directly; up to 1/4 from its complement pi/2 - angle; up to 3/8
        // as pi/2 plus a small angle; below 1/2 from its supplement pi - angle. (k > n/8 implies n >= 4 here.)
        if 8 * k <= n {
            c[k] = cos(step * Double(k)); s[k] = sin(step * Double(k))
        } else if 4 * k <= n {
            let a = step * Double(n / 4 - k)
            c[k] = sin(a); s[k] = cos(a)
        } else {
            let j = k - n / 4
            if 8 * j <= n {
                c[k] = -sin(step * Double(j)); s[k] = cos(step * Double(j))
            } else {
                let a = step * Double(n / 2 - k)
                c[k] = -cos(a); s[k] = sin(a)
            }
        }
    }
    return (c, s)
}

/// The discrete Fourier transform of `size` complex values, size a power of two:
/// X[k] = sum over n of x[n] e^(-2 pi i k n / size), unscaled, as `numpy.fft.fft` computes it.
/// Iterative radix-2 decimation in time: the input in bit-reversed order, then log2(size) passes of butterflies.
public struct FFT: Sendable {
    public let size: Int
    let cosTable: [Double]  // cos(2 pi k / size), k < size / 2
    let sinTable: [Double]  // sin(2 pi k / size)
    let bitReversed: [Int32]

    public init(size: Int) {
        precondition(size >= 1 && size & (size - 1) == 0, "FFT size \(size) is not a power of two")
        precondition(size <= 1 << 30, "FFT size \(size) too large")
        self.size = size
        (cosTable, sinTable) = twiddles(size, count: size / 2)
        var rev = [Int32](repeating: 0, count: size)
        var bits = 0
        while 1 << bits < size { bits += 1 }
        for i in 0..<size {
            var r = 0, v = i
            for _ in 0..<bits { r = (r << 1) | (v & 1); v >>= 1 }
            rev[i] = Int32(r)
        }
        bitReversed = rev
    }

    /// Transforms `real` and `imag` (each `size` values) in place.
    public func forward(real: inout [Double], imag: inout [Double]) {
        precondition(real.count == size && imag.count == size, "FFT of size \(size) given \(real.count) and \(imag.count) values")
        real.withUnsafeMutableBufferPointer { re in
            imag.withUnsafeMutableBufferPointer { im in forward(real: re.baseAddress!, imag: im.baseAddress!) }
        }
    }

    /// Transforms `size` values at `real` and `imag` in place.
    public func forward(real re: UnsafeMutablePointer<Double>, imag im: UnsafeMutablePointer<Double>) {
        let n = size
        if n == 1 { return }
        bitReversed.withUnsafeBufferPointer { rev in
            var i = 0
            while i < n {
                let j = Int(rev[i])
                if j > i {
                    let tr = re[i], ti = im[i]
                    re[i] = re[j]; im[i] = im[j]
                    re[j] = tr; im[j] = ti
                }
                i += 1
            }
        }
        // Pass 1, butterflies of 2 with the twiddle 1.
        var i = 0
        while i < n {
            let ar = re[i], ai = im[i], br = re[i + 1], bi = im[i + 1]
            re[i] = ar + br; im[i] = ai + bi
            re[i + 1] = ar - br; im[i + 1] = ai - bi
            i += 2
        }
        if n == 2 { return }
        // Pass 2, butterflies of 4 with the twiddles 1 and -i (multiplying by -i maps (x, y) to (y, -x)).
        i = 0
        while i < n {
            let ar = re[i], ai = im[i], br = re[i + 2], bi = im[i + 2]
            re[i] = ar + br; im[i] = ai + bi
            re[i + 2] = ar - br; im[i + 2] = ai - bi
            let cr = re[i + 1], ci = im[i + 1], dr = im[i + 3], di = -re[i + 3]
            re[i + 1] = cr + dr; im[i + 1] = ci + di
            re[i + 3] = cr - dr; im[i + 3] = ci - di
            i += 4
        }
        // The other passes: within each block of `len`, x[j] and x[j + half] combine with w = e^(-2 pi i j / len),
        // which is table entry j * (n / len). The twiddle is the outer loop, so each is read once per pass.
        cosTable.withUnsafeBufferPointer { ct in
            sinTable.withUnsafeBufferPointer { st in
                var len = 8
                while len <= n {
                    let half = len >> 1, step = n / len
                    var j = 0
                    while j < half {
                        let wr = ct[j * step], wi = -st[j * step]
                        var a = j
                        while a < n {
                            let b = a + half
                            let br = re[b], bi = im[b]
                            let vr = br * wr - bi * wi, vi = br * wi + bi * wr
                            let ar = re[a], ai = im[a]
                            re[a] = ar + vr; im[a] = ai + vi
                            re[b] = ar - vr; im[b] = ai - vi
                            a += len
                        }
                        j += 1
                    }
                    len <<= 1
                }
            }
        }
    }
}

/// The discrete Fourier transform of `size` real values, size a power of two, as `numpy.fft.rfft` gives it: the
/// size / 2 + 1 bins from 0 (the sum) to size / 2 (the Nyquist bin); the others are their complex conjugates.
///
/// The real-input trick: with m = size / 2, the complex sequence z[n] = x[2n] + i x[2n + 1] is transformed by an
/// m-point FFT to Z. Its even and odd halves are E[k] = (Z[k] + conj(Z[m - k])) / 2 and
/// O[k] = (Z[k] - conj(Z[m - k])) / 2i (indices mod m), and X[k] = E[k] + W^k O[k] with W = e^(-2 pi i / size).
/// Since E and O are the transforms of real sequences, X[m - k] = conj(E[k] - W^k O[k]), so each pair k, m - k is
/// computed together and the whole result fits in place in the m + 1 output values.
public struct RealFFT: Sendable {
    public let size: Int
    let half: FFT
    let wr: [Double]  // cos(2 pi k / size), k < size / 4
    let wi: [Double]  // -sin(2 pi k / size)

    public init(size: Int) {
        precondition(size >= 1 && size & (size - 1) == 0, "FFT size \(size) is not a power of two")
        self.size = size
        half = FFT(size: max(1, size / 2))
        let t = twiddles(size, count: size / 4)
        wr = t.cos
        wi = t.sin.map { -$0 }
    }

    /// Number of output bins: size / 2 + 1.
    public var bins: Int { size / 2 + 1 }

    /// The transform of `x` (`size` values): real and imaginary parts of bins 0 through size / 2.
    public func forward(_ x: [Double]) -> (real: [Double], imag: [Double]) {
        precondition(x.count == size, "real FFT of size \(size) given \(x.count) values")
        var re = [Double](repeating: 0, count: bins), im = [Double](repeating: 0, count: bins)
        x.withUnsafeBufferPointer { xb in
            re.withUnsafeMutableBufferPointer { rb in
                im.withUnsafeMutableBufferPointer { ib in forward(xb.baseAddress!, real: rb.baseAddress!, imag: ib.baseAddress!) }
            }
        }
        return (re, im)
    }

    /// The transform of the `size` values at `x` into `real` and `imag`, which must each hold size / 2 + 1 values
    /// (and may not overlap `x`).
    public func forward(_ x: UnsafePointer<Double>, real re: UnsafeMutablePointer<Double>, imag im: UnsafeMutablePointer<Double>) {
        if size == 1 { re[0] = x[0]; im[0] = 0; return }
        let m = size / 2
        var n = 0
        while n < m { re[n] = x[2 * n]; im[n] = x[2 * n + 1]; n += 1 }
        half.forward(real: re, imag: im)
        let z0r = re[0], z0i = im[0]
        re[0] = z0r + z0i; im[0] = 0
        re[m] = z0r - z0i; im[m] = 0
        if m == 1 { return }
        wr.withUnsafeBufferPointer { cw in
            wi.withUnsafeBufferPointer { sw in
                var k = 1
                while k < m - k {
                    let ar = re[k], ai = im[k], br = re[m - k], bi = im[m - k]
                    let er = (ar + br) * 0.5, ei = (ai - bi) * 0.5
                    let odr = (ai + bi) * 0.5, odi = (br - ar) * 0.5
                    let c = cw[k], s = sw[k]
                    let tr = c * odr - s * odi, ti = c * odi + s * odr
                    re[k] = er + tr; im[k] = ei + ti
                    re[m - k] = er - tr; im[m - k] = ti - ei
                    k += 1
                }
            }
        }
        // k = m / 2 pairs with itself: E = Re Z, O = Im Z, W^(m/2) = -i, so X = conj(Z).
        im[m / 2] = -im[m / 2]
    }
}
