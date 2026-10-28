import Foundation
import Testing
import DeckieDecode

/// The fixture files, written by core/Tools/make_audio_fixtures.py.
enum Fixture {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    static func url(_ name: String) -> URL { dir.appendingPathComponent(name) }
}

@Suite struct AudioBufferTests {
    @Test func channelsAndMonoFromInterleavedSamples() {
        let b = AudioBuffer(sampleRate: 8000, channelCount: 2, samples: [1, 3, -1, 0.5, 0.25, 0.25])
        #expect(b.frames == 3)
        #expect(b.duration == 3.0 / 8000)
        #expect(b.channel(0) == [1, -1, 0.25])
        #expect(b.channel(1) == [3, 0.5, 0.25])
        #expect(b.mono() == [2, -0.25, 0.25])
        let m = AudioBuffer(sampleRate: 8000, channelCount: 1, samples: [0.5, -0.5])
        #expect(m.frames == 2 && m.channel(0) == m.samples && m.mono() == m.samples)
    }
}

@Suite struct DecodeErrorTests {
    /// Decodes and returns the typed error, or records an issue when nothing is thrown.
    func decodeError(_ url: URL) -> AudioDecodeError? {
        do throws(AudioDecodeError) {
            _ = try AudioDecoder.decode(url)
            Issue.record("decoding \(url.lastPathComponent) did not throw")
            return nil
        } catch {
            return error
        }
    }

    @Test func missingFileThrowsTheTypedError() throws {
        let url = Fixture.url("no-such-file.wav")
        let error = try #require(decodeError(url))
        #expect(error.kind == .cannotRead)
        #expect(error.file == url.path)
        #expect(error.message == "no such file")
        #expect(error.description.contains("no-such-file.wav"))
    }

    @Test func mp3AndAACAreRecognisedButNotSupportedYet() throws {
        let mp3 = try #require(decodeError(Fixture.url("tone.mp3")))
        #expect(mp3.kind == .unsupported && mp3.format == .mp3)
        #expect(mp3.message.hasPrefix("MP3 is not supported on this platform yet"), "\(mp3.message)")
        let aac = try #require(decodeError(Fixture.url("tone.m4a")))
        #expect(aac.kind == .unsupported && aac.format == .aac)
        #expect(aac.message.hasPrefix("AAC is not supported on this platform yet"), "\(aac.message)")
        #expect(aac.description.contains("tone.m4a (AAC)"))
    }
}
