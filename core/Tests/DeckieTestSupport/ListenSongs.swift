import Foundation

/// Generated "songs" for the listener's tests (booth inside Desk): a seeded scatter of short tones with harmonics, as
/// DeckieRecognitionTests' songs are, at any rate, mono or as interleaved stereo with the two channels a little
/// different. Nothing from anyone's music.
public enum ListenSongs {
    struct RNG { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

    /// `seconds` of song `seed` at `rate`, mono, peaking under full scale.
    public static func song(seed: UInt64, seconds: Double = 40, rate: Int = 44100) -> [Float] {
        var rng = RNG(s: seed)
        let n = Int(seconds * Double(rate))
        var out = [Float](repeating: 0, count: n)
        var t = 0.0
        while t < seconds {
            let f = 320 * pow(2, rng.next() * 3.2), length = 0.15 + 0.5 * rng.next(), amp = 0.2 + 0.8 * rng.next()
            let start = Int(t * Double(rate)), count = Int(length * Double(rate))
            for i in 0..<count where start + i < n {
                let x = Double(i) / Double(rate)
                let env = exp(-3 * x) * min(1, Double(i) / 40)
                out[start + i] += Float(amp * env * (sin(2 * .pi * f * x) + 0.4 * sin(2 * .pi * 2 * f * x)))
            }
            t += 0.08 + 0.12 * rng.next()
        }
        let peak = out.reduce(0) { max($0, abs($1)) }
        if peak > 0 { for i in out.indices { out[i] *= 0.7 / peak } }
        return out
    }

    /// Mono samples as two interleaved channels, the right a little quieter.
    public static func stereo(_ mono: [Float]) -> [Float] {
        var out = [Float](repeating: 0, count: mono.count * 2)
        for i in mono.indices { out[2 * i] = mono[i]; out[2 * i + 1] = mono[i] * 0.8 }
        return out
    }

    /// A piece of a mono song, from `from` seconds, `seconds` long.
    public static func excerpt(_ x: [Float], rate: Int, from: Double, seconds: Double) -> [Float] {
        Array(x[min(x.count, Int(from * Double(rate)))..<min(x.count, Int((from + seconds) * Double(rate)))])
    }
}
