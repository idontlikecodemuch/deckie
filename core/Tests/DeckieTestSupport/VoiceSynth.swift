import Foundation
import DeckieAudio

/// A sung-like line for the vocal tagger's tests: no recording, only arithmetic. Each note is a harmonic tone (every
/// harmonic below 7 kHz, falling 6 dB an octave) shaped by four formant resonances of a vowel (the magnitude of a
/// cascade of second-order resonators at each harmonic, gliding halfway toward the next note's vowel), with a pitch
/// glide from the previous note over 60 ms, a vibrato of 3.5 % at 5.6 Hz that sets in over 0.1 to 0.25 s, a slow
/// random wobble of the pitch (0.6 %), a slow swell of the level (8 % at 3.1 Hz), breath noise, a 50 ms gap and a
/// 30 ms attack at the start and a 50 ms release at the end. Each note is scaled to unit RMS before the envelopes.
///
/// How well it passes for singing: on YAMNet, alone, it scores like a chant or a hum more than a song, and over drums
/// and chords its vocal score is a few hundredths, against a few ten-thousandths without it (measured with the
/// fixture script's recipe in Python while choosing the parameters, Oct 28, 2026); real singing scores far higher.
/// The tests use it for what it is: a voice-like line the tagger must tell apart from the instruments under it.
public enum VoiceSynth {
    /// Formant frequency and bandwidth pairs (Hz) of six vowels: ah, ee, oo, eh, aw, ih.
    public static let vowels: [[(f: Double, bw: Double)]] = [
        [(730, 90), (1090, 110), (2440, 170), (3400, 250)],
        [(270, 60), (2290, 100), (3010, 150), (3500, 250)],
        [(300, 70), (870, 90), (2240, 150), (3300, 250)],
        [(530, 80), (1840, 100), (2480, 160), (3500, 250)],
        [(570, 80), (840, 90), (2410, 160), (3300, 250)],
        [(390, 70), (1990, 100), (2550, 160), (3500, 250)],
    ]

    /// A melody between 196 and 392 Hz (MIDI 55 to 67), one note a beat at 124 BPM.
    public static let melody: [Double] = [57, 60, 62, 64, 62, 60, 59, 57, 55, 59, 62, 67, 65, 64, 62, 60]

    /// Magnitude of a second-order resonator with unit gain at 0 Hz, at frequency f.
    @inline(__always)
    static func resonator(_ f: Double, _ fc: Double, _ bw: Double) -> Double {
        let x = f / fc
        let a = 1 - x * x, b = f * bw / (fc * fc)
        return 1 / (a * a + b * b).squareRoot()
    }

    /// `n` samples at `rate`: the notes `midi` in turn, each `noteSeconds` long, from `start` seconds, as long as they
    /// fit; zero elsewhere.
    public static func render(rate: Int, samples n: Int, start: Double, noteSeconds: Double, midi: [Double],
                              seed: UInt64) -> [Double] {
        let r = Double(rate)
        var y = [Double](repeating: 0, count: n)
        // The pitch wobble: noise through a one-pole low-pass at 12 Hz, scaled to a standard deviation of 0.6 %.
        var g = SplitMix64(seed)
        var wobble = [Double](repeating: 0, count: n)
        let a1 = exp(-2 * Double.pi * 12 / r)
        var acc = 0.0, sum = 0.0, sumSq = 0.0
        for i in 0..<n {
            acc = a1 * acc + (1 - a1) * (2 * g.uniform() - 1)
            wobble[i] = acc
            sum += acc; sumSq += acc * acc
        }
        let sd = (sumSq / Double(max(n, 1)) - (sum / Double(max(n, 1))) * (sum / Double(max(n, 1)))).squareRoot()
        let wobbleScale = sd > 0 ? 0.006 / sd : 0
        var breath = SplitMix64(seed &+ 1)
        var previousNoise = 2 * breath.uniform() - 1
        let block = 32
        for (q, m) in midi.enumerated() {
            let a = Int((start + Double(q) * noteSeconds) * r + 0.5)
            if a >= n { break }
            let length = min(Int(noteSeconds * r), n - a)
            let f0 = 440 * pow(2, (m - 69) / 12)
            let prev = q > 0 ? 440 * pow(2, (midi[q - 1] - 69) / 12) : f0
            let vowel = vowels[q % vowels.count], next = vowels[(q + 1) % vowels.count]
            var harmonics = 0
            while f0 * Double(harmonics + 1) * 1.06 < min(7000, r / 2 - 200) { harmonics += 1 }
            var tone = [Double](repeating: 0, count: length)
            var amp = [Double](repeating: 0, count: harmonics + 1)
            var phase = 0.0
            var power = 0.0
            for j in 0..<length {
                let t = Double(j) / r
                let glide = prev + (f0 - prev) * min(1, t / 0.06)
                let depth = 0.035 * min(1, max(0, (t - 0.1) / 0.15))
                let f = glide * (1 + depth * sin(2 * Double.pi * 5.6 * t) + wobbleScale * wobble[a + j])
                phase += 2 * Double.pi * f / r
                if j % block == 0 {
                    let mix = 0.5 * min(1, max(0, (t - 0.25) / 0.2))
                    for k in stride(from: 1, through: harmonics, by: 1) {
                        let fk = f * Double(k)
                        var v = 1.0 / Double(k)
                        for i in 0..<4 {
                            let fc = vowel[i].f + (next[i].f - vowel[i].f) * mix
                            v *= resonator(fk, fc, vowel[i].bw)
                        }
                        amp[k] = v
                    }
                }
                // sin(k phase) by the recurrence s_k = 2 cos(phase) s_(k-1) - s_(k-2).
                let c2 = 2 * cos(phase)
                var s1 = sin(phase), s0 = 0.0, v = 0.0
                var k = 1
                while k <= harmonics {
                    v += amp[k] * s1
                    let s2 = c2 * s1 - s0
                    s0 = s1; s1 = s2
                    k += 1
                }
                tone[j] = v
                power += v * v
            }
            let norm = power > 0 ? 1 / (power / Double(length)).squareRoot() : 0
            for j in 0..<length {
                let t = Double(j) / r
                let env = min(1, min(max(0, t - 0.05) / 0.03, Double(length - j) / r / 0.05))
                let swell = 1 + 0.08 * sin(2 * Double.pi * 3.1 * t + Double(q))
                let u = 2 * breath.uniform() - 1
                let hiss = u - previousNoise
                previousNoise = u
                y[a + j] += env * (swell * norm * tone[j] + 0.03 * hiss)
            }
        }
        return y
    }
}

/// A synthesised track for the vocal tagger's tests: drums at 124 BPM (`DrumPattern`) and an A minor progression
/// (`ChordSynth`, one chord a bar) throughout, and in alternate 8-bar stretches the same plus the sung-like line
/// (`VoiceSynth`, one note a beat) at twice the instruments' RMS level: bars 1 to 8 instrumental, 9 to 16 with the
/// voice, 17 to 24 instrumental, 25 to 32 with the voice. The first beat is at 0.5 s; 1 s of silence follows bar 32.
public enum VocalTrack {
    public static let bpm = 124.0
    public static let firstBeat = 0.5
    public static let bars = 32
    public static let stretch = 8
    public static var barS: Double { 4 * 60 / bpm }
    public static var musicEnd: Double { firstBeat + Double(bars) * barS }

    /// Whether bar `b` (0-based) has the voice.
    public static func isVocal(bar b: Int) -> Bool { (b / stretch) % 2 == 1 }

    /// The track at `rate`: (instruments, voice), mono, each `samples(rate:)` long; their sum is the track.
    public static func parts(rate: Int) -> (instruments: [Double], voice: [Double]) {
        let r = Double(rate), n = samples(rate: rate)
        let beats = DrumPattern.steadyBeats(first: firstBeat, bpm: bpm, end: musicEnd - 1e-6)
        let drums = DrumPattern.render(rate: rate, samples: n, beats: beats, seed: 7)
        let start = DrumPattern.onset(firstBeat, rate: rate), span = DrumPattern.onset(musicEnd, rate: rate) - start
        let chords = ChordSynth.render(rate: rate, samples: n,
                                       chords: ChordSynth.progression(rate: rate, samples: span, chordSeconds: barS,
                                                                      [ChordSynth.Am, ChordSynth.Dm, ChordSynth.E, ChordSynth.Am],
                                                                      offset: start),
                                       harmonics: 5, noise: 0, seed: 11, exact: false)
        var instruments = (0..<n).map { Double(drums[$0]) + 0.25 * chords[$0] }
        for i in Int(musicEnd * r)..<n { instruments[i] = 0 }
        var voice = [Double](repeating: 0, count: n)
        let beatS = 60 / bpm
        for s in stride(from: stretch, to: bars, by: 2 * stretch) {
            let t0 = firstBeat + Double(s) * barS
            let notes = (0..<(4 * stretch)).map { VoiceSynth.melody[$0 % VoiceSynth.melody.count] }
            let part = VoiceSynth.render(rate: rate, samples: n, start: t0, noteSeconds: beatS, midi: notes,
                                         seed: UInt64(100 + s))
            for i in 0..<n { voice[i] += part[i] }
        }
        // The voice at twice the instruments' RMS (both measured over the vocal stretches).
        func rms(_ x: [Double]) -> Double {
            var s = 0.0, c = 0
            for b in 0..<bars where isVocal(bar: b) {
                let a = Int((firstBeat + Double(b) * barS) * r), e = Int((firstBeat + Double(b + 1) * barS) * r)
                for i in a..<min(e, n) { s += x[i] * x[i]; c += 1 }
            }
            return (s / Double(max(c, 1))).squareRoot()
        }
        let scale = 2 * rms(instruments) / max(rms(voice), 1e-12)
        return (instruments, voice.map { $0 * scale })
    }

    public static func samples(rate: Int) -> Int { Int((musicEnd + 1) * Double(rate)) }
}

/// The vocal-structure test track: 40 bars of drums at 124 BPM (`DrumPattern`) and the A minor progression
/// (`ChordSynth`, one chord a bar) throughout, with the sung-like line (`VoiceSynth`, one note a beat, at twice the
/// instruments' RMS level) over two stretches: from beat 4 of bar 8 (a pickup, one beat before bar 9's downbeat) to the
/// end of bar 16, and over bars 25 to 32. The first beat is at 0.5 s; 1 s of silence follows bar 40. So the record
/// should read: spans from bar 8 beat 4 to bar 17 beat 1 and from bar 25 beat 1 to bar 33 beat 1, the first sung beat a
/// pickup, 7 free intro bars (bar 8 holds the pickup), 8 free outro bars, both beat-only, free gaps of bars 17 to 24 and
/// 33 to 40, and the sung stretches as the loud repeated sections.
public enum VocalStructureTrack {
    public static let bpm = 124.0
    public static let firstBeat = 0.5
    public static let bars = 40
    /// The voiced stretches, as beat indices from bar 1's downbeat (0-based), the end exclusive: beat 31 is bar 8's
    /// fourth beat.
    public static let voiced = [31..<64, 96..<128]
    public static var beatS: Double { 60 / bpm }
    public static var barS: Double { 4 * beatS }
    public static var musicEnd: Double { firstBeat + Double(bars) * barS }

    public static func samples(rate: Int) -> Int { Int((musicEnd + 1) * Double(rate)) }

    /// The track at `rate`: (instruments, voice), mono, each `samples(rate:)` long; their sum is the track.
    public static func parts(rate: Int) -> (instruments: [Double], voice: [Double]) {
        let r = Double(rate), n = samples(rate: rate)
        let beats = DrumPattern.steadyBeats(first: firstBeat, bpm: bpm, end: musicEnd - 1e-6)
        let drums = DrumPattern.render(rate: rate, samples: n, beats: beats, seed: 7)
        let start = DrumPattern.onset(firstBeat, rate: rate), span = DrumPattern.onset(musicEnd, rate: rate) - start
        let chords = ChordSynth.render(rate: rate, samples: n,
                                       chords: ChordSynth.progression(rate: rate, samples: span, chordSeconds: barS,
                                                                      [ChordSynth.Am, ChordSynth.Dm, ChordSynth.E, ChordSynth.Am],
                                                                      offset: start),
                                       harmonics: 5, noise: 0, seed: 11, exact: false)
        var instruments = (0..<n).map { Double(drums[$0]) + 0.25 * chords[$0] }
        for i in Int(musicEnd * r)..<n { instruments[i] = 0 }
        var voice = [Double](repeating: 0, count: n)
        for (q, beatsVoiced) in voiced.enumerated() {
            let notes = (0..<beatsVoiced.count).map { VoiceSynth.melody[$0 % VoiceSynth.melody.count] }
            let part = VoiceSynth.render(rate: rate, samples: n, start: firstBeat + Double(beatsVoiced.lowerBound) * beatS,
                                         noteSeconds: beatS, midi: notes, seed: UInt64(200 + q))
            for i in 0..<n { voice[i] += part[i] }
        }
        // The voice at twice the instruments' RMS, both measured over the voiced stretches.
        var si = 0.0, sv = 0.0
        for b in voiced {
            let a = Int((firstBeat + Double(b.lowerBound) * beatS) * r)
            let e = Int((firstBeat + Double(b.upperBound) * beatS) * r)
            for i in a..<min(e, n) { si += instruments[i] * instruments[i]; sv += voice[i] * voice[i] }
        }
        let scale = 2 * (si / max(sv, 1e-12)).squareRoot()
        return (instruments, voice.map { $0 * scale })
    }

    /// The track as stereo float32 audio: the instruments slightly wider on the left, the voice in the middle, as the
    /// vocal engine tests mix `VocalTrack`.
    public static func render(rate: Int) -> AudioBuffer {
        let (instruments, voice) = parts(rate: rate)
        var stereo = [Float](repeating: 0, count: 2 * instruments.count)
        for i in 0..<instruments.count {
            stereo[2 * i] = Float(0.5 * (instruments[i] + voice[i]))
            stereo[2 * i + 1] = Float(0.5 * (0.9 * instruments[i] + voice[i]))
        }
        return AudioBuffer(sampleRate: rate, channelCount: 2, samples: stereo)
    }
}
