import Foundation

// Test signals with known beats, shared by the DeckieCore and DeckieInference tests. A library target of its own
// (not a product) so both test targets can use it; nothing outside the tests depends on it.

/// SplitMix64, the random numbers of the fixture scripts (Tools/make_*_fixtures.py): integer arithmetic, so Swift
/// and Python draw the same values.
public struct SplitMix64Generator: Sendable {
    public var state: UInt64
    public init(_ seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1): (z >> 11) * 2^-53, exact.
    public mutating func uniform() -> Double { Double(next() >> 11) * 0x1p-53 }
}

/// The drum-like pattern of Tools/make_beat_fixtures.py (`drum_pattern`, `steady_beats`, `tempo_change_beats`),
/// operation for operation, so the samples are the fixture's to the bit wherever the C library's sin and exp are
/// the same as the one Python used (glibc on Linux; elsewhere they may differ in the last bit of a double, which
/// float32 rounding almost always hides).
public enum DrumPattern {
    public struct Beat: Sendable, Equatable {
        public var time: Double
        public var accent: Bool
        public init(time: Double, accent: Bool) {
            self.time = time
            self.accent = accent
        }
    }

    /// Beats from `first` every 60 / bpm seconds while before `end`; every fourth, from the first, accented.
    public static func steadyBeats(first: Double, bpm: Double, end: Double) -> [Beat] {
        var times: [Double] = []
        var k = 0
        while true {
            let t = first + Double(k) * (60.0 / bpm)
            if t >= end { break }
            times.append(t)
            k += 1
        }
        return times.enumerated().map { Beat(time: $0.element, accent: $0.offset % 4 == 0) }
    }

    /// Beats every 60 / bpm1 s from `first`; the first beat at or after `change` (still on that grid) starts beats
    /// every 60 / bpm2 s, until `end`. Every fourth accented, counting straight through the change.
    public static func tempoChangeBeats(first: Double, bpm1: Double, bpm2: Double, change: Double, end: Double) -> [Beat] {
        var times: [Double] = []
        var k = 0
        while first + Double(k) * (60.0 / bpm1) < change {
            times.append(first + Double(k) * (60.0 / bpm1))
            k += 1
        }
        let pivot = first + Double(k) * (60.0 / bpm1)
        var j = 0
        while pivot + Double(j) * (60.0 / bpm2) < end {
            times.append(pivot + Double(j) * (60.0 / bpm2))
            j += 1
        }
        return times.enumerated().map { Beat(time: $0.element, accent: $0.offset % 4 == 0) }
    }

    /// The sample a beat at `t` seconds starts on: floor(t rate + 0.5).
    public static func onset(_ t: Double, rate: Int) -> Int { Int((t * Double(rate) + 0.5).rounded(.down)) }

    /// `n` samples at `rate`: a kick on every beat (full level on accents, 0.6 otherwise), a light snare on every
    /// second beat, a hi-hat on every beat and halfway to the next; halved and rounded to float32.
    public static func render(rate: Int, samples n: Int, beats: [Beat], seed: UInt64) -> [Float] {
        let r = Double(rate)
        let kickLength = Int(0.25 * r), hatLength = Int(0.06 * r), snareLength = Int(0.2 * r)
        let kick = (0..<kickLength).map { j -> Double in
            let t = Double(j) / r
            let phase = 2.0 * Double.pi * (45.0 * t + 3.15 * (1.0 - exp(-t / 0.03)))
            return exp(-t / 0.12) * sin(phase) + 0.4 * exp(-t / 0.002)
        }
        let hat = (0..<hatLength).map { j in exp(-(Double(j) / r) / 0.015) }
        let snare = (0..<snareLength).map { j in exp(-(Double(j) / r) / 0.05) }
        var g = SplitMix64Generator(seed)
        var previous = 2.0 * g.uniform() - 1.0
        var bright = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let u = 2.0 * g.uniform() - 1.0
            bright[i] = u - previous
            previous = u
        }
        var y = [Double](repeating: 0, count: n)
        y.withUnsafeMutableBufferPointer { yb in
            bright.withUnsafeBufferPointer { bb in
                func addKick(_ i: Int, _ gain: Double) {
                    let m = min(kickLength, n - i)
                    var j = 0
                    while j < m { yb[i + j] += gain * kick[j]; j += 1 }
                }
                func addNoise(_ i: Int, _ gain: Double, _ env: [Double]) {
                    let m = min(env.count, n - i)
                    var j = 0
                    while j < m { yb[i + j] += gain * env[j] * bb[i + j]; j += 1 }
                }
                for (k, beat) in beats.enumerated() {
                    let i = onset(beat.time, rate: rate)
                    addKick(i, beat.accent ? 1.0 : 0.6)
                    if k % 2 == 1 { addNoise(i, 0.2, snare) }
                    addNoise(i, 0.12, hat)
                    if k + 1 < beats.count { addNoise(onset((beat.time + beats[k + 1].time) / 2.0, rate: rate), 0.12, hat) }
                }
            }
        }
        return y.map { Float(0.5 * $0) }
    }
}
