import Foundation
import Testing
@testable import DeckieDecode

// The MP3 backend (MP3Reader: dr_mp3 plus the lab's gapless trimming). Variants of tone.mp3 are made here in
// memory and decoded through MP3Reader directly, so no file is written. Every frame count and click position below
// that the lab's decoder can read was checked against it on Oct 28, 2026: soundfile 0.14.0 (libsndfile 1.2.2,
// which decodes MP3 through mpg123) on the same bytes gave the same numbers.

func fixtureBytes(_ name: String) throws -> Data { try Data(contentsOf: Fixture.url(name)) }

func decodeMP3(_ bytes: Data) -> Result<AudioBuffer, AudioDecodeError> {
    do throws(AudioDecodeError) {
        return .success(try MP3Reader.decode(Data(bytes), file: "in memory"))
    } catch {
        return .failure(error)
    }
}

/// Deterministic noise bytes (the C library's old rand formula), the same as the measuring script used.
func noise(_ count: Int) -> Data {
    var x: UInt32 = 12345
    return Data((0..<count).map { _ in
        x = (x &* 1_103_515_245 &+ 12345) & 0x7FFF_FFFF
        return UInt8(truncatingIfNeeded: x >> 16)
    })
}

/// Where tone.mp3's Info tag sits: its first frame starts at byte 20, after ffmpeg's empty ID3v2.4 tag; the tag
/// after the frame header and 32 bytes of side information; LAME's extension after the tag's four fields (flags
/// 0x0F: frame count, stream size, 100-byte seek table, quality).
enum ToneMP3 {
    static let firstFrame = 20, frameBytes = 626  // 1152 × 192 kbit/s / 8 / 44.1 kHz, no padding slot
    static let info = 20 + 4 + 32
    static let lame = info + 8 + 4 + 4 + 100 + 4
}

@Suite struct MP3ReaderTests {
    /// What dr_mp3 decodes before trimming, and what the tags hold. On its own (its built-in trimming left on),
    /// dr_mp3 skips the tag frame and trims tone.mp3 to 176,400 frames with the click on sample 88,200 too; the
    /// numbers here are with that switched off, as MP3Reader runs it.
    @Test(arguments: [("tone.mp3", 44100, 155, 1584, 176_400), ("tone48k.mp3", 48000, 168, 960, 192_000),
                      ("tone_mono.mp3", 44100, 155, 1584, 176_400)])
    func untrimmedDecodeAndTheInfoTag(_ name: String, _ rate: Int, _ frames: Int, _ padding: Int,
                                      _ kept: Int) throws {
        let u = try MP3Reader.decodeUntrimmed(try fixtureBytes(name), file: name)
        #expect(u.firstFrameOffset == 20 && u.samplesPerFrame == 1152)
        #expect(u.tag == .init(frameCount: frames, lame: .init(encoder: "Lavf lame", delay: 576, padding: padding)))
        #expect(u.buffer.sampleRate == rate)
        // Every frame after the tag frame: 178,560 for tone.mp3, with the click 576 + 529 samples late (25.057 ms).
        #expect(u.buffer.frames == frames * 1152)
        #expect(clickIndex(u.buffer.mono()) == 2 * rate + 576 + 529)
        #expect(u.kept == (576 + 529)..<(frames * 1152 - padding + 529))
        let b = u.trimmed()
        #expect(b.frames == kept && clickIndex(b.mono()) == 2 * rate)
    }

    /// The trimming rule where mpg123 (the lab's decoder) and ffmpeg differ: MP3Reader follows mpg123.
    @Test func gaplessTrimmingFollowsTheLabsDecoder() throws {
        let file = try fixtureBytes("tone.mp3")
        func edited(_ edit: (inout Data) -> Void) -> Data {
            var d = file
            edit(&d)
            return d
        }
        let lame = ToneMP3.lame, info = ToneMP3.info
        let cases: [(String, Data, frames: Int, click: Int)] = [
            ("as written: encoder string \"Lavf lame\", delay 576, padding 1584", file, 176_400, 88_200),
            // ffmpeg trusts only "LAME", "Lavf" and "Lavc", so it trims nothing here (178,560 frames, click 89,305).
            ("encoder string \"XXXX\"", edited { $0.replaceSubrange(lame..<(lame + 4), with: Data("XXXX".utf8)) },
             176_400, 88_200),
            // No extension: only the decoder's 529 go. ffmpeg trims nothing.
            ("LAME extension zeroed", edited { $0.replaceSubrange(lame..<(lame + 36), with: Data(count: 36)) },
             178_031, 88_776),
            // No frame count: nothing trimmed. ffmpeg (and dr_mp3 by itself) still skip delay + 529 (177,455).
            ("frame count left out", edited {
                $0[info + 7] &= 0xFE
                $0.removeSubrange((info + 8)..<(info + 12))
                $0.insert(contentsOf: [0, 0, 0, 0], at: ToneMP3.firstFrame + ToneMP3.frameBytes - 4)  // same length
            }, 178_560, 89_305),
            // Padding under the decoder's 529: the end stays where the decoding ends (ffmpeg agrees).
            ("padding 100", edited { $0[lame + 22] &= 0xF0; $0[lame + 23] = 100 }, 177_455, 88_200),
        ]
        for (what, bytes, frames, click) in cases {
            let b = try decodeMP3(bytes).get()
            let at = clickIndex(b.mono())
            #expect(b.frames == frames && at == click, "\(what): \(b.frames) frames, click at \(at)")
        }
    }

    /// An ID3v2.3 tag in front of tone.mp3 (whose own empty ID3v2.4 tag follows it), or a few stray bytes between
    /// the tag and the first frame, change nothing. dr_mp3 alone, given these bytes, misses the Info tag behind
    /// them: it decodes the tag frame as 1,152 samples of silence and trims nothing (179,712 frames, click 51 ms
    /// late); mpg123 finds it.
    @Test func id3v2TagsAndStrayBytesInFrontChangeNothing() throws {
        let file = try fixtureBytes("tone.mp3")
        let plain = try decodeMP3(file).get()
        // "ID3", version 3.0, no flags, size 64 in four 7-bit bytes, then 64 bytes of padding.
        let id3v23 = Data("ID3".utf8) + Data([3, 0, 0, 0, 0, 0, 64]) + Data(count: 64)
        let cases: [(String, Data)] = [
            ("an ID3v2.3 tag in front of the file's own", id3v23 + file),
            ("an ID3v2.3 tag in place of the file's own", id3v23 + file.dropFirst(ToneMP3.firstFrame)),
            ("7 stray zero bytes after the tag", file.prefix(ToneMP3.firstFrame) + Data(count: 7)
                + file.dropFirst(ToneMP3.firstFrame)),
            ("no tag at all", Data(file.dropFirst(ToneMP3.firstFrame))),
        ]
        for (what, bytes) in cases {
            let b = try decodeMP3(bytes).get()
            #expect(b == plain, "\(what): \(b.frames) frames")
        }
        #expect(AudioFormat.sniff(id3v23 + file) == .mp3)
    }

    /// Measured Oct 28, 2026: 176,400 frames; 440 Hz at -12.466 dBFS, 1000 Hz at -18.466 dBFS (+98 dB over the
    /// other bins); click on sample 88,200; correlation with tone.wav's channel mean 0.99999.
    @Test func monoMP3StaysMono() throws {
        let b = try AudioDecoder.decode(Fixture.url("tone_mono.mp3"))
        #expect(b.sampleRate == 44100 && b.channelCount == 1 && b.frames == 176_400)
        let x = b.channel(0)
        #expect(clickIndex(x) == 88_200)
        // The stereo tone's channel mean: each sine at half its level (-6.02 dB).
        let window = (start: 22050, count: 44100)  // 0.5 s to 1.5 s
        let low = dB(amplitude(x, hz: 440, rate: 44100, start: window.start, count: window.count))
        let high = dB(amplitude(x, hz: 1000, rate: 44100, start: window.start, count: window.count))
        let others = [110.0, 220, 330, 500, 550, 660, 880, 1500, 2000, 3000, 5000]
            .map { dB(amplitude(x, hz: $0, rate: 44100, start: window.start, count: window.count)) }.max()!
        #expect(abs(low - (Tone.leftDb - 6.02)) <= 1.5, "440 Hz at \(low) dBFS")
        #expect(abs(high - (Tone.rightDb - 6.02)) <= 1.5, "1000 Hz at \(high) dBFS")
        #expect(high - others >= 30, "1000 Hz stands \(high - others) dB above the other bins")
        let wav = try AudioDecoder.decode(Fixture.url("tone.wav")).mono()
        let corr = correlation(wav, x, shift: 0)
        #expect(corr > 0.99, "correlation with tone.wav's channel mean: \(corr)")
        print("DeckieDecode tone_mono.mp3: \(b.frames) frames; 440 Hz \(fixed(low, 3)) dBFS, 1000 Hz "
              + "\(fixed(high, 3)) dBFS (+\(fixed(high - others, 0)) dB over other bins); click at sample "
              + "\(clickIndex(x)); correlation with tone.wav's channel mean \(fixed(corr, 5))")
    }

    @Test func damagedMP3sGiveAClearError() throws {
        let file = try fixtureBytes("tone.mp3")
        let cases: [(String, Data, String)] = [
            ("cut to 300 bytes, inside the first frame", file.prefix(300),
             "no complete MPEG audio frame found after the ID3v2 tag (20 bytes); the file may be cut short"),
            ("noise after the tag", file.prefix(ToneMP3.firstFrame) + noise(4096),
             "no complete MPEG audio frame found after the ID3v2 tag (20 bytes)"),
            ("a tag claiming more bytes than the file holds",
             Data("ID3".utf8) + Data([4, 0, 0, 0x7F, 0x7F, 0x7F, 0x7F]) + file.dropFirst(10),
             "the ID3v2 tag at the start claims more bytes than the file holds"),
            ("one frame header and nothing else", Data([0xFF, 0xFB, 0xB0, 0x00]),
             "no complete MPEG audio frame found; the file may be cut short, or not be MP3"),
        ]
        for (what, bytes, message) in cases {
            guard case .failure(let e) = decodeMP3(bytes) else {
                Issue.record("\(what): decoded")
                continue
            }
            #expect(e.kind == .damaged && e.format == .mp3, "\(what)")
            #expect(e.message == message || e.message.hasPrefix(message), "\(what): \(e.message)")
        }
    }

    /// Damage after the first frames is decoded past, as ffmpeg does, rather than refused: dr_mp3 finds the frames
    /// again after it. The lab's decoder gives up on the noise below (mpg123 stops resyncing after 1,024 bytes)
    /// and decodes the half file to the same 86,447 frames.
    @Test func damageFurtherInIsDecodedPast() throws {
        let file = try fixtureBytes("tone.mp3")
        let patched = try decodeMP3(file.prefix(40_000) + noise(2000) + file.dropFirst(42_000)).get()
        #expect(patched.sampleRate == 44100 && patched.channelCount == 2)
        #expect(patched.frames == 171_695)  // 5 frames lost with the noise; the end is where decoding ends
        #expect(patched.samples.allSatisfy { $0.isFinite && abs($0) <= 1.5 })
        let half = try decodeMP3(file.prefix(file.count / 2)).get()
        #expect(half.frames == 86_447)
    }

    /// Frame lengths and samples per frame from the header, as dr_mp3 computes them (MP3Reader uses them to find
    /// where the first frame starts).
    @Test func frameHeaders() {
        let cases: [([UInt8], length: Int?, samples: Int)] = [
            ([0xFF, 0xFB, 0xB0, 0x00], 626, 1152),  // MPEG-1 layer III, 192 kbit/s, 44.1 kHz: tone.mp3
            ([0xFF, 0xFB, 0xB2, 0x00], 627, 1152),  // the same with the padding slot
            ([0xFF, 0xFB, 0xB4, 0x00], 576, 1152),  // 48 kHz: tone48k.mp3
            ([0xFF, 0xF3, 0x90, 0xC4], 261, 576),  // MPEG-2 layer III, 80 kbit/s, 22.05 kHz
            ([0xFF, 0xE3, 0x40, 0xC4], 208, 576),  // MPEG-2.5 layer III, 32 kbit/s, 11.025 kHz
            ([0xFF, 0xFD, 0x90, 0x00], 522, 1152),  // MPEG-1 layer II, 160 kbit/s, 44.1 kHz
            ([0xFF, 0xFF, 0x92, 0x00], 316, 384),  // MPEG-1 layer I, 288 kbit/s, 44.1 kHz, padded: 312 + 4
        ]
        for (h, length, samples) in cases {
            let f = MP3Reader.FrameHeader(h)
            #expect(f?.length(freeFormatBytes: 0) == length && f?.samplesPerFrame == samples, "\(h)")
        }
        // A free-format frame takes the length dr_mp3 measured; reserved fields are not headers.
        #expect(MP3Reader.FrameHeader([0xFF, 0xFB, 0x00, 0x00])?.length(freeFormatBytes: 700) == 700)
        for h: [UInt8] in [[0xFF, 0xFB, 0xF0, 0x00], [0xFF, 0xFB, 0xBC, 0x00], [0xFF, 0xF9, 0xB0, 0x00],
                           [0xFF, 0xEB, 0xB0, 0x00], [0xFE, 0xFB, 0xB0, 0x00]] {
            #expect(MP3Reader.FrameHeader(h) == nil, "\(h)")
        }
    }
}
