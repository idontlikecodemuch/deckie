import Foundation
import Testing
@testable import DeckieDecode

// Windows' Media Foundation on the AAC test tone, measured before it is trusted: tone.m4a is four seconds of two
// sines with one full-scale click at exactly 2.000 s (sample 88,200 at 44.1 kHz), encoded by ffmpeg, whose AAC
// encoder puts 1,024 samples of lead-in in front and says so in the file's edit list. Where the click comes out says
// whether Media Foundation removed the lead-in. The numbers are printed for the workflow's log.

@Suite struct MediaFoundationTests {
    static let tone = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        .appendingPathComponent("tone.m4a")

    @Test func elsewhereItSaysItIsNotAvailable() throws {
        #if !os(Windows)
        #expect(throws: MediaFoundationReader.Failure.self) { try MediaFoundationReader.decodeRaw(Self.tone) }
        #endif
    }

    #if os(Windows)
    @Test func whereTheClickLandsInTheAACTone() throws {
        let raw: MediaFoundationReader.Raw
        do {
            raw = try MediaFoundationReader.decodeRaw(Self.tone)
        } catch let e as MediaFoundationReader.Failure {
            if case .unavailable(let why) = e { print("Media Foundation measurement skipped: \(why)"); return }
            throw e
        }
        let b = raw.buffer
        let frames = b.samples.count / b.channelCount
        // The click: the largest jump between neighbouring samples of the first channel.
        var peak = 0, jump: Float = 0
        for i in 1..<frames {
            let d = abs(b.samples[i * b.channelCount] - b.samples[(i - 1) * b.channelCount])
            if d > jump { jump = d; peak = i }
        }
        // The largest sample itself, too.
        var top = 0, level: Float = 0
        for i in 0..<frames where abs(b.samples[i * b.channelCount]) > level { level = abs(b.samples[i * b.channelCount]); top = i }
        let firstSound = (0..<frames).first { abs(b.samples[$0 * b.channelCount]) > 0.001 } ?? -1
        print("MEDIA FOUNDATION MEASUREMENT tone.m4a: rate \(b.sampleRate), channels \(b.channelCount), frames \(frames) "
              + "(the tone is 176400), first block's time stamp \(raw.firstTimestamp) s, blocks \(raw.blocks), "
              + "largest sample at frame \(top) (level \(level)), largest jump at frame \(peak), "
              + "click offset from 88200: \(top - 88200) frames, first sample above -60 dB at frame \(firstSound)")
        #expect(b.sampleRate == 44100)
        #expect(b.channelCount == 2)
        #expect(frames > 170_000)
    }
    #endif
}
