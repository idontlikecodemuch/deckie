import Foundation

// Deckie's own resampler, written for the sound lookup: a Kaiser-windowed sinc filter evaluated on an exact polyphase
// table. It is not a port of anything. Chromaprint's LGPL resampler (src/avresample, taken from FFmpeg) was not read
// for it; the numbers it is tuned to are the ones Chromaprint's own MIT-licensed code passes to FFmpeg's resampler
// when `fpcalc` reads a file (src/audio/ffmpeg_audio_processor_swresample.h): a filter of 16 taps at the lower of the
// two rates, the pass band ending at 0.8 of the lower rate's half, and FFmpeg's default Kaiser window (beta 9).
// Matching those numbers keeps the samples close to `fpcalc`'s, so the fingerprints agree bit for bit nearly
// everywhere (docs/research/aa4-lookup-by-sound.md has the measured agreement).
//
// How it works. Output sample n sits at input position n * inRate / outRate. With g the greatest common divisor of
// the two rates, L = outRate / g and M = inRate / g, that position is (n * M) / L whole input samples plus a fraction
// k / L, where k = (n * M) mod L. So there are only L different fractions, and the filter's taps for each are worked
// out once (a "phase"); every output is then a dot product of one phase with the input around its position. When L
// is very large (odd rates), the fraction is rounded to the nearest of `maxPhases`.

public struct Resampler: Sendable {
    public let inRate: Int
    public let outRate: Int
    /// The share of the lower rate's half (its Nyquist frequency) that passes.
    public static let cutoff = 0.8
    /// Taps of the filter at the lower rate.
    public static let filterSize = 16
    /// The Kaiser window's beta.
    public static let kaiserBeta = 9.0
    /// The most phases kept; above this the fraction of a sample is rounded.
    public static let maxPhases = 4096

    let phases: Int        // L, or maxPhases
    let exact: Bool        // L <= maxPhases
    let l: Int, m: Int
    let taps: Int
    let left: Int          // taps before the position: index i - left + 1 ... i + taps - left
    let table: [Double]    // phases * taps

    public init(inRate: Int, outRate: Int) {
        precondition(inRate > 0 && outRate > 0)
        self.inRate = inRate; self.outRate = outRate
        var a = inRate, b = outRate
        while b != 0 { (a, b) = (b, a % b) }
        l = outRate / a; m = inRate / a
        exact = l <= Self.maxPhases
        phases = exact ? l : Self.maxPhases
        // The filter's cutoff in cycles per input sample, times two: 1 is the input's Nyquist frequency.
        let factor = min(1.0, Self.cutoff * Double(outRate) / Double(inRate))
        var t = Int((Double(Self.filterSize) / factor).rounded(.up))
        if t % 2 == 1 { t += 1 }
        taps = max(2, t)
        left = taps / 2
        let half = Double(taps) / 2
        let i0beta = Self.besselI0(Self.kaiserBeta)
        var tab = [Double](repeating: 0, count: phases * taps)
        for p in 0..<phases {
            let frac = Double(p) / Double(phases)
            var sum = 0.0
            for j in 0..<taps {
                // Distance in input samples from this tap to the output's position.
                let x = Double(j - left + 1) - frac
                let s = x == 0 ? 1.0 : sin(Double.pi * factor * x) / (Double.pi * factor * x)
                let r = x / half
                let w = abs(r) >= 1 ? 0 : Self.besselI0(Self.kaiserBeta * (1 - r * r).squareRoot()) / i0beta
                tab[p * taps + j] = s * w
                sum += s * w
            }
            // Each phase passes a constant level unchanged.
            if sum != 0 { for j in 0..<taps { tab[p * taps + j] /= sum } }
        }
        table = tab
    }

    /// The modified Bessel function of the first kind, order 0, by its power series.
    static func besselI0(_ x: Double) -> Double {
        var sum = 1.0, term = 1.0, k = 1.0
        let q = x * x / 4
        while term > 1e-17 * sum {
            term *= q / (k * k)
            sum += term
            k += 1
        }
        return sum
    }

    /// How many output samples `count` input samples make.
    public func outputCount(_ count: Int) -> Int { Int((Int64(count) * Int64(outRate)) / Int64(inRate)) }

    /// Resamples `input`, giving at most `limit` output samples. Samples before the start and after the end are 0.
    public func process(_ input: [Float], limit: Int = .max) -> [Double] {
        let n = min(limit, outputCount(input.count))
        guard n > 0 else { return [] }
        if inRate == outRate { return input.prefix(n).map(Double.init) }
        var out = [Double](repeating: 0, count: n)
        let count = input.count
        input.withUnsafeBufferPointer { x in
            table.withUnsafeBufferPointer { tab in
                for o in 0..<n {
                    let pos = Int64(o) * Int64(m)
                    let i = Int(pos / Int64(l))
                    var p = Int(pos % Int64(l))
                    var base = i
                    if !exact {
                        p = Int((Double(p) / Double(l) * Double(phases)).rounded())
                        if p == phases { p = 0; base += 1 }
                    }
                    let start = base - left + 1
                    let row = p * taps
                    var acc = 0.0
                    if start >= 0 && start + taps <= count {
                        var j = 0
                        while j < taps { acc += Double(x[start + j]) * tab[row + j]; j += 1 }
                    } else {
                        for j in 0..<taps {
                            let k = start + j
                            if k >= 0 && k < count { acc += Double(x[k]) * tab[row + j] }
                        }
                    }
                    out[o] = acc
                }
            }
        }
        return out
    }
}
