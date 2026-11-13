import Foundation
import Testing
import DeckieCore
import DeckieTestSupport

// The same-recording rule (D24) on generated songs: copies of one recording (another rate, level, added silence,
// quantisation and encoder-like noise) are found as the same; an extended mix, an edit, a remix, a live take and an
// unrelated song are not. Every song here is synthesised in the test; no music file is read.

@Suite struct RecordingPrintTests {
    static let rate = 44100

    /// A generated song, mono at `rate`: `lead` seconds of silence, then `bars` bars of 4/4 drums at `bpm` with one
    /// chord a bar from `chords` (in turn, so a progression longer than four bars does not repeat every four), then
    /// `tail` seconds of silence. `intro` bars of drums alone come before the chords start.
    static func song(bpm: Double = 124, bars: Int = 24, chords: [[Double]] = Self.progression, drumSeed: UInt64 = 7,
                     harmonics: Int = 5, halfTimeDrums: Bool = false, intro: Int = 0, lead: Double = 0.5,
                     tail: Double = 1.0, rate: Int = rate) -> [Float] {
        let bar = 240 / bpm
        let musicEnd = lead + Double(intro + bars) * bar
        let n = Int((musicEnd + tail) * Double(rate))
        let beats = DrumPattern.steadyBeats(first: lead, bpm: halfTimeDrums ? bpm / 2 : bpm, end: musicEnd - 1e-6)
        let drums = DrumPattern.render(rate: rate, samples: n, beats: beats, seed: drumSeed)
        let start = DrumPattern.onset(lead + Double(intro) * bar, rate: rate)
        let span = DrumPattern.onset(musicEnd, rate: rate) - start
        let harmony = ChordSynth.render(rate: rate, samples: n,
                                        chords: ChordSynth.progression(rate: rate, samples: span, chordSeconds: bar,
                                                                       chords, offset: start),
                                        harmonics: harmonics, noise: 0, seed: 11, exact: false)
        return (0..<n).map { Float(Double(drums[$0]) + 0.25 * harmony[$0]) }
    }

    /// Twelve chords that do not repeat in fours, so a cut of a few bars changes what lines up.
    static let progression = [ChordSynth.Am, ChordSynth.F, ChordSynth.C, ChordSynth.G, ChordSynth.Dm, ChordSynth.E,
                              ChordSynth.Fs, ChordSynth.B, ChordSynth.Cs, ChordSynth.D, ChordSynth.A, ChordSynth.Am]

    static func print(_ x: [Float], rate: Int = rate) -> RecordingPrint { RecordingPrint(mono: x, sampleRate: rate) }

    static let original = song()
    static let originalPrint = print(original)

    @Test func theSameAudioIsTheSameRecording() {
        let c = RecordingPrint.compare(Self.originalPrint, Self.print(Self.original))
        #expect(c.sameRecording)
        #expect(c.worstBER == 0)
    }

    /// Another copy of the same recording: at 48 kHz, 3 dB down, rounded to 16 bits, with noise that follows the
    /// signal (as a lossy encoder's does, about 30 dB under it), 0.3 s more silence at the start and 0.6 s more at
    /// the end.
    @Test func aCopyInAnotherFormatIsTheSameRecording() {
        var g = SplitMix64(5)
        let gain = Float(pow(10, -3.0 / 20))
        var x = Self.original.map { v -> Float in
            let noisy = v * (1 + Float(0.03 * (2 * g.uniform() - 1)))
            return (noisy * gain * 32767).rounded() / 32767
        }
        x = [Float](repeating: 0, count: Int(0.3 * Double(Self.rate))) + x + [Float](repeating: 0, count: Int(0.6 * Double(Self.rate)))
        let at48 = Resampler.resample(x, from: Self.rate, to: 48000)
        let c = RecordingPrint.compare(Self.originalPrint, Self.print(at48, rate: 48000))
        #expect(c.sameRecording, "worst block BER \(c.worstBER ?? -1), length difference \(c.lengthDifferenceS) s")
        #expect((c.worstBER ?? 1) < 0.2)
    }

    /// An extended mix: the same song with eight bars of drums before it. Its sound is 15 s longer.
    @Test func anExtendedMixIsNot() {
        let c = RecordingPrint.compare(Self.originalPrint, Self.print(Self.song(intro: 8)))
        #expect(!c.sameRecording)
        #expect(c.lengthDifferenceS > 10)
    }

    /// An edit that keeps the length: two bars cut from the middle and two bars more at the end, so only where the
    /// music was cut differs. The rule's whole-song check is what catches it.
    @Test func anEditOfTheSameLengthIsNot() {
        let bar = Int(240.0 / 124 * Double(Self.rate))
        let lead = Int(0.5 * Double(Self.rate))
        let longer = Self.song(bars: 26)
        let cutFrom = lead + 12 * bar, cutTo = lead + 14 * bar
        let edit = Array(longer[..<cutFrom]) + Array(longer[cutTo...])
        let c = RecordingPrint.compare(Self.originalPrint, Self.print(edit))
        #expect(c.lengthDifferenceS < RecordingPrint.lengthToleranceS)
        #expect(!c.sameRecording, "worst block BER \(c.worstBER ?? -1)")
    }

    /// A remix: the same chords at the same tempo and length, with half-time drums and another timbre.
    @Test func aRemixIsNot() {
        let c = RecordingPrint.compare(Self.originalPrint, Self.print(Self.song(drumSeed: 99, harmonics: 2, halfTimeDrums: true)))
        #expect(c.lengthDifferenceS < RecordingPrint.lengthToleranceS)
        #expect(!c.sameRecording, "worst block BER \(c.worstBER ?? -1)")
    }

    /// A live take: the same song played 1 % faster (its length within the 1 s allowance), so it drifts off the
    /// record within a few bars.
    @Test func aLiveTakeIsNot() {
        let c = RecordingPrint.compare(Self.originalPrint, Self.print(Self.song(bpm: 124 * 1.01, drumSeed: 8)))
        #expect(c.lengthDifferenceS < RecordingPrint.lengthToleranceS)
        #expect(!c.sameRecording, "worst block BER \(c.worstBER ?? -1)")
    }

    @Test func anotherSongIsNot() {
        let other = Self.song(chords: Array(Self.progression.reversed()), drumSeed: 3, harmonics: 3)
        let c = RecordingPrint.compare(Self.originalPrint, Self.print(other))
        #expect(!c.sameRecording)
        #expect((c.worstBER ?? 0) > RecordingPrint.berThreshold)
    }

    @Test func silenceHasNoSound() {
        let p = Self.print([Float](repeating: 0, count: 5 * Self.rate))
        #expect(p.soundSpan == nil)
        #expect(!RecordingPrint.sameRecording(p, p))
    }

    /// The paper's numbers, as the type states them.
    @Test func theNumbers() {
        #expect(RecordingPrint.frameLength == Int((0.37 * Double(RecordingPrint.sampleRate)).rounded()))
        #expect(RecordingPrint.hop == Int((Double(RecordingPrint.frameLength) / 32).rounded()))
        #expect(RecordingPrint.bandCount == 33 && RecordingPrint.blockFrames == 256 && RecordingPrint.berThreshold == 0.35)
        #expect(Self.originalPrint.words.count > 3 * RecordingPrint.blockFrames)
    }
}
