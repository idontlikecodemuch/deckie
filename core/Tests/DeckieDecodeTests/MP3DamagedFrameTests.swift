import Foundation
import Testing
import DeckieCore
import DeckieTestSupport
@testable import DeckieDecode

// The damaged-frame check and concealment (MP3Reader's comment, Sources/CDrMp3/dr_mp3.c). tone_damaged.mp3 is
// tone.mp3 with the Huffman codes of audio frame 60, granule 1, channel 0 set to 0x33
// (core/Tools/make_damaged_mp3_fixture.py), so its big values run past the granule's end. The lab's decoder (mpg123,
// through soundfile 0.14.0 and libsndfile 1.2.2) says "dequantization failed!" on it and plays that granule as 576
// zeros; ffmpeg 6.1.1 decodes the same burst as dr_mp3.

/// The damaged frame: audio frame 60 of tone_damaged.mp3, 1,152 samples a frame, before the gapless trim.
enum DamagedTone {
    static let frame = 60, samplesPerFrame = 1152
    static var range: Range<Int> { (frame * samplesPerFrame)..<((frame + 1) * samplesPerFrame) }
    /// Where the concealed samples can differ from what dr_mp3 alone decodes: the frame and the one after it, whose
    /// first granule carries the damaged frame's overlap; from the frame after that on, the decoder's state is the
    /// same either way.
    static var reach: Range<Int> { range.lowerBound..<(range.upperBound + samplesPerFrame) }
    /// The gapless trim at the start (LAME's 576 and the decoder's 529).
    static let trim = 576 + 529
}

/// The largest absolute sample in frames `r` of `b`.
func peak(_ b: AudioBuffer, _ r: Range<Int>) -> Float {
    b.samples[(r.lowerBound * b.channelCount)..<(r.upperBound * b.channelCount)].reduce(0) { max($0, abs($1)) }
}

func sameBits(_ a: [Float], _ b: [Float]) -> Bool {
    a.count == b.count && zip(a, b).allSatisfy { $0.bitPattern == $1.bitPattern }
}

@Suite struct MP3DamagedFrameTests {
    /// The committed fixture is what the test helper makes from tone.mp3 (so the two implementations of the damage, the
    /// script and `MP3Damage`, agree), and only bytes of the frame's main data differ from tone.mp3; they lie in the
    /// frame before it, the bit reservoir.
    @Test func theFixtureIsToneMp3WithOneFramesMainDataDamaged() throws {
        let clean = try fixtureBytes("tone.mp3"), damaged = try fixtureBytes("tone_damaged.mp3")
        let made = MP3Damage.damaged(clean, frame: DamagedTone.frame, granule: 1, channel: 0, byte: 0x33)
        #expect(made == damaged)
        let changed = zip(clean, damaged).enumerated().filter { $0.element.0 != $0.element.1 }.map(\.offset)
        let frames = MP3Damage.frames([UInt8](clean))
        let frame = frames[DamagedTone.frame + 1]  // after the Info tag frame
        #expect(changed.count == 69 && clean.count == damaged.count)
        // Nothing in any frame's header or side information.
        for f in frames {
            #expect(!changed.contains { $0 >= f.offset && $0 < f.mainOffset })
        }
        print("DeckieDecode tone_damaged.mp3: \(changed.count) bytes changed, file bytes \(changed.first!) to "
              + "\(changed.last!); frame \(DamagedTone.frame) starts at byte \(frame.offset), main_data_begin "
              + "\(frame.mainDataBegin)")
    }

    /// The frame loop gives exactly the samples of dr_mp3's own pull reader, for the fixtures and the edited copies the
    /// MP3 tests decode, so the check changes nothing by itself; and with nothing flagged, concealing changes nothing.
    @Test func theFrameLoopGivesDrMp3sOwnSamples() throws {
        let tone = try fixtureBytes("tone.mp3")
        let id3v23 = Data("ID3".utf8) + Data([3, 0, 0, 0, 0, 0, 64]) + Data(count: 64)
        let cases: [(String, Data)] = [
            ("tone.mp3", tone), ("tone48k.mp3", try fixtureBytes("tone48k.mp3")),
            ("tone_mono.mp3", try fixtureBytes("tone_mono.mp3")), ("tone_damaged.mp3", try fixtureBytes("tone_damaged.mp3")),
            ("tone.mp3 behind a second ID3v2 tag", id3v23 + tone),
            ("tone.mp3 without its tags", Data(tone.dropFirst(ToneMP3.firstFrame))),
            ("tone.mp3 with noise inside", tone.prefix(40_000) + noise(2000) + tone.dropFirst(42_000)),
            ("half of tone.mp3", tone.prefix(tone.count / 2)),
            ("tone.mp3 with an ID3v1 tag after it", tone + Data("TAG".utf8) + Data(count: 125)),
        ]
        for (what, bytes) in cases {
            let pull = try MP3Reader.decodeUntrimmed(bytes, file: what, driver: .pullReader)
            let checked = try MP3Reader.decodeUntrimmed(bytes, file: what, driver: .checking)
            let concealed = try MP3Reader.decodeUntrimmed(bytes, file: what, driver: .concealing)
            #expect(sameBits(checked.buffer.samples, pull.buffer.samples), "\(what)")
            #expect(checked.buffer.channelCount == pull.buffer.channelCount && checked.kept == pull.kept, "\(what)")
            #expect(checked.damagedFrames == concealed.damagedFrames, "\(what)")
            if concealed.damagedFrames.isEmpty {
                #expect(sameBits(concealed.buffer.samples, pull.buffer.samples), "\(what)")
            }
            let flagged = what == "tone_damaged.mp3" ? [DamagedTone.range] : []
            #expect(concealed.damagedFrames == flagged, "\(what): \(concealed.damagedFrames)")
        }
    }

    /// dr_mp3 alone (the check noting, not concealing) flags exactly the damaged frame and decodes a burst there and
    /// in the next frame (the damaged granule's overlap): measured Oct 29, 2026, peaks 2.733 and 2.201 against 0.486
    /// in the frames around (the left channel's -6 dBFS sine).
    @Test func drMp3AloneDecodesABurst() throws {
        let u = try MP3Reader.decodeUntrimmed(try fixtureBytes("tone_damaged.mp3"), file: "tone_damaged.mp3",
                                              driver: .checking)
        #expect(u.damagedFrames == [DamagedTone.range])
        let n = DamagedTone.samplesPerFrame, at = DamagedTone.range.lowerBound
        let around = [at - 2 * n, at - n, at + 2 * n, at + 3 * n].map { peak(u.buffer, $0..<($0 + n)) }.max()!
        let burst = peak(u.buffer, DamagedTone.reach)
        #expect(burst > 5 * around, "burst \(burst), frames around \(around)")
        print("DeckieDecode tone_damaged.mp3, dr_mp3 alone: frame \(DamagedTone.frame) peak "
              + "\(fixed(Double(peak(u.buffer, DamagedTone.range)), 4)), next frame "
              + "\(fixed(Double(peak(u.buffer, DamagedTone.range.upperBound..<(DamagedTone.range.upperBound + n))), 4)), "
              + "frames around \(fixed(Double(around), 4))")
    }

    /// Concealed, the damaged frame is silent, entered and left through the decoder's own windows, and every sample
    /// outside the frame and the next is exactly tone.mp3's: the damage touched only that frame's data, and the
    /// decoder's state is the same again after the next frame. The fade can overshoot the music around it a little
    /// (the half block that is not completed keeps its time-domain alias, at most (1 + sqrt 2) / 2, 1.21 times):
    /// measured 0.584 against 0.486.
    @Test func theDamagedFrameIsSilencedAndNothingElseChanges() throws {
        let clean = try MP3Reader.decodeUntrimmed(try fixtureBytes("tone.mp3"), file: "tone.mp3")
        let u = try MP3Reader.decodeUntrimmed(try fixtureBytes("tone_damaged.mp3"), file: "tone_damaged.mp3")
        #expect(u.damagedFrames == [DamagedTone.range])
        let c = u.buffer.channelCount, reach = DamagedTone.reach
        #expect(u.buffer.frames == clean.buffer.frames)
        #expect(sameBits(Array(u.buffer.samples[..<(reach.lowerBound * c)]),
                         Array(clean.buffer.samples[..<(reach.lowerBound * c)])))
        #expect(sameBits(Array(u.buffer.samples[(reach.upperBound * c)...]),
                         Array(clean.buffer.samples[(reach.upperBound * c)...])))
        let n = DamagedTone.samplesPerFrame, at = DamagedTone.range.lowerBound
        let around = peak(clean.buffer, reach)
        let concealed = peak(u.buffer, reach)
        #expect(concealed <= 1.21 * around, "concealed \(concealed), tone.mp3 there \(around)")
        // The frame's second granule, once the filter bank's 512-sample memory of the first has run out: silence.
        let quiet = peak(u.buffer, (at + n - 64)..<(at + n))
        #expect(quiet < 1e-3, "the end of the concealed frame peaks at \(quiet)")
        print("DeckieDecode tone_damaged.mp3, concealed: peak \(fixed(Double(concealed), 4)) over the frame and the "
              + "next (tone.mp3 there \(fixed(Double(around), 4))); the frame's last 64 samples peak at \(quiet)")
    }

    /// Through the public API: the frame's time in the trimmed audio, the length unchanged, nothing reported for the
    /// clean file; and the true peak, which the burst raised by 10 dB, is tone.mp3's again (its click's, at 2 s).
    @Test func theDecoderReportsTheFrameAndTheTruePeakIsRestored() throws {
        let decoded = try AudioDecoder.decodeReporting(Fixture.url("tone_damaged.mp3"))
        let start = Double(DamagedTone.range.lowerBound - DamagedTone.trim) / 44100
        #expect(decoded.damagedFrames == [DamagedFrame(startSeconds: start, seconds: 1152.0 / 44100)])
        #expect(decoded.buffer.frames == 176_400)
        let clean = try AudioDecoder.decodeReporting(Fixture.url("tone.mp3"))
        #expect(clean.damagedFrames.isEmpty)
        let raw = try MP3Reader.decodeUntrimmed(try fixtureBytes("tone_damaged.mp3"), file: "tone_damaged.mp3",
                                                driver: .checking).trimmed()
        let tpClean = TruePeak.decibels(clean.buffer), tpRaw = TruePeak.decibels(raw)
        let tpConcealed = TruePeak.decibels(decoded.buffer)
        #expect(tpRaw > tpClean + 9, "dr_mp3 alone \(tpRaw) dBTP, tone.mp3 \(tpClean)")
        #expect(abs(tpConcealed - tpClean) < 0.01, "concealed \(tpConcealed) dBTP, tone.mp3 \(tpClean)")
        print("DeckieDecode tone_damaged.mp3: damaged frame at \(fixed(start, 6)) s for \(fixed(1152.0 / 44100, 6)) s; "
              + "true peak \(fixed(tpRaw, 2)) dBTP decoded by dr_mp3 alone, \(fixed(tpConcealed, 2)) concealed, "
              + "\(fixed(tpClean, 2)) for tone.mp3")
    }
}
