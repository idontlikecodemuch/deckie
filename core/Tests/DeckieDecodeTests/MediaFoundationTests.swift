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
        // Measured on GitHub's Windows runner (Windows Server 2025, build 26100), core-windows run 43536290887:
        // Media Foundation does not remove the lead-in. It hands back every AAC frame whole, 174 of 1,024, so the
        // click is 1,024 frames late and the audio 1,776 frames too long. The file's own edit list says both numbers
        // (start at 1,024, play 4.000 s), so a reader has to apply it itself. Pinned, so that the day a Windows
        // update starts trimming, this fails and the rule is looked at again instead of trimming twice.
        #expect(frames == 178_176)
        #expect(top - 88_200 == 1_024)
    }

    /// The decoder as the builder calls it: the tone comes back at its own length with the click where it was.
    @Test func theDecoderPutsTheClickBackAt88200() throws {
        let decoded: DecodedAudio
        do {
            decoded = try AudioDecoder.decodeReporting(Self.tone)
        } catch {
            if error.message.contains("no media features") { print("skipped: \(error.message)"); return }
            throw error
        }
        let b = decoded.buffer
        let frames = b.samples.count / b.channelCount
        var top = 0, level: Float = 0
        for i in 0..<frames where abs(b.samples[i * b.channelCount]) > level { level = abs(b.samples[i * b.channelCount]); top = i }
        #expect(b.sampleRate == 44100 && b.channelCount == 2)
        #expect(frames == 176_400)
        #expect(top == 88_200)
        #expect(decoded.startUncertain == nil)
    }

    /// The same file with its edit list gone: read whole, the click 1,024 frames late, and marked.
    @Test func aFileWithNoStatedLeadInIsReadAndMarkedUncertain() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-mf-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("no lead-in stated.m4a")
        try MP4AudioTests.withoutEditList(try Data(contentsOf: Self.tone)).write(to: file)
        let decoded: DecodedAudio
        do {
            decoded = try AudioDecoder.decodeReporting(file)
        } catch {
            if error.message.contains("no media features") { print("skipped: \(error.message)"); return }
            throw error
        }
        let b = decoded.buffer
        let frames = b.samples.count / b.channelCount
        var top = 0, level: Float = 0
        for i in 0..<frames where abs(b.samples[i * b.channelCount]) > level { level = abs(b.samples[i * b.channelCount]); top = i }
        print("MEDIA FOUNDATION, edit list removed: frames \(frames), click at \(top)")
        #expect(decoded.startUncertain != nil)
        #expect(top - 88_200 == 1_024 || top == 88_200, "click at \(top)")
    }
    #endif
}
