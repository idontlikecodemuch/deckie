import Foundation

/// SplitMix64, the random numbers of Tools/make_dsp_fixtures.py and Tools/make_key_fixtures.py: integer arithmetic,
/// so Swift and Python draw the same values.
struct SplitMix64 {
    var x: UInt64
    init(_ seed: UInt64) { x = seed }

    mutating func next() -> UInt64 {
        x &+= 0x9E37_79B9_7F4A_7C15
        var z = x
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1): (z >> 11) * 2^-53, exact.
    mutating func uniform() -> Double { Double(next() >> 11) * 0x1p-53 }

    /// Python's `int(uniform() * n)`.
    mutating func below(_ n: Int) -> Int { Int(uniform() * Double(n)) }
}

/// Chords with harmonics plus noise: the recipe of `synth` in Tools/make_dsp_fixtures.py.
enum ChordSynth {
    /// (first sample, end sample, MIDI notes; C4 = 60, fractions allowed)
    typealias Chord = (start: Int, end: Int, notes: [Double])

    /// Each note: the sum over harmonics k (below rate / 2) of (0.2 / k) env sin(2 pi f k / rate * i), with
    /// f = 440 * 2^((m - 69) / 12), i the absolute sample index and env a 10 ms linear ramp in and out; then noise
    /// times (2u - 1), u from SplitMix64(seed). `exact` computes every sine as the Python script does, so the result
    /// is bit for bit the fixture's signal; otherwise each partial is a rotating phasor, resynchronised every 1024
    /// samples (within about 1e-13 of the exact values, and quick in a debug build) for the long test signals.
    static func render(rate: Int, samples n: Int, chords: [Chord], harmonics: Int, noise: Double, seed: UInt64,
                       exact: Bool = true) -> [Double] {
        var y = [Double](repeating: 0, count: n)
        let ramp = Double(Int(0.01 * Double(rate)))
        y.withUnsafeMutableBufferPointer { yb in
            let out = yb.baseAddress!
            for (a, b, notes) in chords {
                let length = b - a
                for m in notes {
                    let f = 440.0 * pow(2.0, (m - 69) / 12.0)
                    for k in 1...harmonics {
                        if f * Double(k) >= Double(rate) / 2 { break }
                        let w = 2.0 * Double.pi * f * Double(k) / Double(rate)
                        let amp = 0.2 / Double(k)
                        var j = 0
                        if exact {
                            while j < length {
                                let env = min(1.0, min((Double(j) + 1) / ramp, (Double(length) - Double(j)) / ramp))
                                out[a + j] += amp * env * sin(w * Double(a + j))
                                j += 1
                            }
                        } else {
                            let cw = cos(w), sw = sin(w)
                            var c = 0.0, s = 0.0
                            while j < length {
                                if j % 1024 == 0 { c = cos(w * Double(a + j)); s = sin(w * Double(a + j)) }
                                let env = min(1.0, min((Double(j) + 1) / ramp, (Double(length) - Double(j)) / ramp))
                                out[a + j] += amp * env * s
                                let c2 = c * cw - s * sw
                                s = s * cw + c * sw
                                c = c2
                                j += 1
                            }
                        }
                    }
                }
            }
            var g = SplitMix64(seed)
            var i = 0
            while i < n { out[i] += noise * (2.0 * g.uniform() - 1.0); i += 1 }
        }
        return y
    }

    /// The chords in turn, each `chordSeconds` long (rounded down to samples), repeated to fill `n` samples, starting at
    /// sample `offset` (the script's `progression`).
    static func progression(rate: Int, samples n: Int, chordSeconds: Double, _ chords: [[Double]], offset: Int = 0) -> [Chord] {
        let step = Int(chordSeconds * Double(rate))
        var out: [Chord] = []
        var a = 0, c = 0
        while a < n {
            out.append((offset + a, offset + min(a + step, n), chords[c % chords.count]))
            a += step
            c += 1
        }
        return out
    }

    // Triads with the root an octave and a half below as bass (MIDI, C4 = 60), as in the script.
    static let C: [Double] = [48, 60, 64, 67], F: [Double] = [41, 65, 69, 72], G: [Double] = [43, 67, 71, 74]
    static let Am: [Double] = [45, 57, 60, 64], Dm: [Double] = [38, 62, 65, 69], E: [Double] = [40, 64, 68, 71]
    static let Fs: [Double] = [42, 66, 70, 73], B: [Double] = [47, 59, 63, 66], Cs: [Double] = [49, 61, 65, 68]
    static let D: [Double] = [38, 62, 66, 69], A: [Double] = [45, 69, 73, 76]
}
