import Foundation

// Part of the loudness module; its overview and sources are at the top of Loudness.swift.

/// A second-order recursive filter (a "biquad"), normalised so a0 = 1 and run in direct form II transposed in double
/// precision, in the order of operations scipy.signal.lfilter uses, so the output matches the lab's to rounding.
///
/// For each input x: y = z1 + b0 x; then z1 = z2 + b1 x - a1 y; z2 = b2 x - a2 y.
public struct Biquad: Sendable, Equatable {
    public var b0: Double, b1: Double, b2: Double
    public var a1: Double, a2: Double

    /// Coefficients as written, divided through by `a0`.
    public init(b0: Double, b1: Double, b2: Double, a0: Double = 1, a1: Double, a2: Double) {
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
    }

    /// The high shelf of Robert Bristow-Johnson's Audio EQ Cookbook, as pyloudnorm's IIRfilter computes it, for a gain
    /// of `gain` dB above `frequency` Hz at the given sample rate:
    ///
    ///     A = 10^(G/40), w0 = 2 pi (fc / rate), alpha = sin(w0) / (2 Q)
    ///     b0 =    A ((A+1) + (A-1) cos(w0) + 2 sqrt(A) alpha)
    ///     b1 = -2 A ((A-1) + (A+1) cos(w0))
    ///     b2 =    A ((A+1) + (A-1) cos(w0) - 2 sqrt(A) alpha)
    ///     a0 =       (A+1) - (A-1) cos(w0) + 2 sqrt(A) alpha
    ///     a1 =     2 ((A-1) - (A+1) cos(w0))
    ///     a2 =       (A+1) - (A-1) cos(w0) - 2 sqrt(A) alpha
    public static func highShelf(gain: Double, q: Double, frequency: Double, sampleRate: Double) -> Biquad {
        let A = pow(10, gain / 40.0)
        let w0 = 2.0 * Double.pi * (frequency / sampleRate)
        let alpha = sin(w0) / (2.0 * q)
        let c = cos(w0), r = A.squareRoot()
        return Biquad(b0: A * ((A + 1) + (A - 1) * c + 2 * r * alpha),
                      b1: -2 * A * ((A - 1) + (A + 1) * c),
                      b2: A * ((A + 1) + (A - 1) * c - 2 * r * alpha),
                      a0: (A + 1) - (A - 1) * c + 2 * r * alpha,
                      a1: 2 * ((A - 1) - (A + 1) * c),
                      a2: (A + 1) - (A - 1) * c - 2 * r * alpha)
    }

    /// The high pass of the Audio EQ Cookbook, as pyloudnorm's IIRfilter computes it (the gain plays no part):
    ///
    ///     w0 = 2 pi (fc / rate), alpha = sin(w0) / (2 Q)
    ///     b0 = (1 + cos(w0)) / 2, b1 = -(1 + cos(w0)), b2 = (1 + cos(w0)) / 2
    ///     a0 = 1 + alpha, a1 = -2 cos(w0), a2 = 1 - alpha
    public static func highPass(q: Double, frequency: Double, sampleRate: Double) -> Biquad {
        let w0 = 2.0 * Double.pi * (frequency / sampleRate)
        let alpha = sin(w0) / (2.0 * q)
        let c = cos(w0)
        return Biquad(b0: (1 + c) / 2, b1: -(1 + c), b2: (1 + c) / 2, a0: 1 + alpha, a1: -2 * c, a2: 1 - alpha)
    }

    /// The filter's memory between samples: direct form II transposed keeps two values. Zero is "at rest".
    public struct State: Sendable, Equatable {
        public var z1: Double = 0
        public var z2: Double = 0
        public init() {}
    }

    /// One sample through the filter.
    @inlinable public func step(_ x: Double, _ s: inout State) -> Double {
        let y = s.z1 + b0 * x
        s.z1 = s.z2 + x * b1 - y * a1
        s.z2 = x * b2 - y * a2
        return y
    }

    /// A whole signal through the filter from rest, like `scipy.signal.lfilter(b, a, x)`.
    public func filter(_ x: [Double]) -> [Double] {
        var s = State()
        return x.map { step($0, &s) }
    }

    /// The gain in decibels at `frequency` Hz, from the transfer function on the unit circle.
    public func gainDB(at frequency: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * frequency / sampleRate
        // H(e^jw) = (b0 + b1 e^-jw + b2 e^-2jw) / (1 + a1 e^-jw + a2 e^-2jw)
        let nr = b0 + b1 * cos(w) + b2 * cos(2 * w), ni = -(b1 * sin(w) + b2 * sin(2 * w))
        let dr = 1 + a1 * cos(w) + a2 * cos(2 * w), di = -(a1 * sin(w) + a2 * sin(2 * w))
        return 10 * log10((nr * nr + ni * ni) / (dr * dr + di * di))
    }
}
