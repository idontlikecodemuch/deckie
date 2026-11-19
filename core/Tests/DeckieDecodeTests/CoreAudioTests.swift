import Foundation
import Testing
@testable import DeckieDecode

// AAC and Apple Lossless on a Mac, through Core Audio (`AppleAudioReader`), as `AudioDecoder` reads them: the AAC test
// tone (ffmpeg's, with its edit list), and the WAV test tone made into AAC in an MP4, Apple Lossless in an MP4, and a raw
// AAC stream by Apple's own `afconvert`. The tone is four seconds of two sines with one full-scale click at exactly
// 2.000 s (frame 88,200 at 44.1 kHz): where the click comes out says whether the encoder's lead-in was left out.

#if canImport(AudioToolbox)
@Suite struct CoreAudioTests {
    /// The largest sample of the first channel, by frame.
    static func click(_ b: AudioBuffer) -> Int {
        var top = 0, level: Float = 0
        for i in 0..<(b.samples.count / b.channelCount) where abs(b.samples[i * b.channelCount]) > level {
            level = abs(b.samples[i * b.channelCount]); top = i
        }
        return top
    }

    /// `afconvert` (every Mac has it) from the WAV tone into `name`, with its file type and data format.
    static func convert(_ name: String, file: String, data: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-coreaudio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let out = folder.appendingPathComponent(name)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        p.arguments = ["-f", file, "-d", data, Fixture.url("tone.wav").path, out.path]
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        return out
    }

    @Test func ffmpegsAACToneComesBackWholeWithTheClickInPlace() throws {
        let d = try AudioDecoder.decodeReporting(Fixture.url("tone.m4a"))
        #expect(d.buffer.sampleRate == 44100 && d.buffer.channelCount == 2)
        #expect(d.buffer.frames == 176_400)
        #expect(abs(Self.click(d.buffer) - 88_200) <= 2, "click at \(Self.click(d.buffer))")
        #expect(d.startUncertain == nil)
    }

    @Test func applesOwnAACInAnMP4() throws {
        let d = try AudioDecoder.decodeReporting(try Self.convert("tone.m4a", file: "m4af", data: "aac"))
        #expect(d.buffer.sampleRate == 44100 && d.buffer.channelCount == 2)
        #expect(d.buffer.frames == 176_400)
        #expect(abs(Self.click(d.buffer) - 88_200) <= 2, "click at \(Self.click(d.buffer))")
        #expect(d.startUncertain == nil)
    }

    @Test func appleLosslessInAnMP4IsTheWAVSampleForSample() throws {
        let d = try AudioDecoder.decodeReporting(try Self.convert("tone lossless.m4a", file: "m4af", data: "alac"))
        let wav = try AudioDecoder.decode(Fixture.url("tone.wav"))
        #expect(d.buffer.sampleRate == wav.sampleRate && d.buffer.channelCount == wav.channelCount)
        #expect(d.buffer.frames == wav.frames)
        #expect(zip(d.buffer.samples, wav.samples).allSatisfy { abs($0 - $1) < 1e-4 })
        #expect(d.startUncertain == nil)
    }

    @Test func aRawAACStreamIsReadAndItsStartMarkedUncertain() throws {
        let file = try Self.convert("tone.aac", file: "adts", data: "aac")
        #expect(AudioFormat.sniff(try Data(contentsOf: file)) == .aac)
        let d = try AudioDecoder.decodeReporting(file)
        #expect(d.buffer.sampleRate == 44100 && d.buffer.channelCount == 2)
        // A raw stream says nowhere how much lead-in its encoder put in front (up to 2,112 frames at most).
        #expect(d.startUncertain != nil)
        #expect((88_200 - 2...88_200 + 2_112 + 2).contains(Self.click(d.buffer)), "click at \(Self.click(d.buffer))")
    }

    @Test func anMP4WithNoAudioInItIsNotReadAndNotCalledDamaged() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-coreaudio-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // An MP4 file type box and nothing else.
        let ftyp: [UInt8] = [0, 0, 0, 20] + Array("ftypisom".utf8) + [0, 0, 2, 0] + Array("isom".utf8)
        let file = folder.appendingPathComponent("clip.mp4")
        try Data(ftyp).write(to: file)
        #expect(throws: AudioDecodeError.self) { try AudioDecoder.decode(file) }
        do { _ = try AudioDecoder.decode(file) } catch { #expect(error.kind == .unsupported, "\(error)") }
        // A cut-off AAC file: its audio stops after a few kilobytes.
        let aac = try Data(contentsOf: Fixture.url("tone.m4a"))
        let cut = folder.appendingPathComponent("cut.m4a")
        try aac.prefix(3_000).write(to: cut)
        do { _ = try AudioDecoder.decode(cut) } catch { #expect(error.kind == .damaged || error.kind == .unsupported, "\(error)") }
    }
}
#endif
