import Foundation
import Testing
@testable import DeckieDecode

// The FLAC backend (FLACReader: dr_flac plus the checks for damaged frames). tone.flac holds tone.wav's samples;
// tone24.flac the same signal quantised to 24 bits; tone.oga tone.wav's samples as Ogg-FLAC. Variants are made here
// in memory, as for MP3 and AIFF. Measured Oct 28, 2026 against the lab's decoder, soundfile 0.14.0 (libsndfile
// 1.2.2, which decodes FLAC through libFLAC): every number below that the lab can read was checked against it.

func decodeFLAC(_ bytes: Data) -> Result<FLACReader.Decoded, AudioDecodeError> {
    do throws(AudioDecodeError) {
        return .success(try FLACReader.decodeWithDetails(Data(bytes), file: "in memory"))
    } catch {
        return .failure(error)
    }
}

/// "ID3", version 3.0, no flags, size 64 in four 7-bit bytes, then 64 bytes of padding: 74 bytes.
let id3v23Tag = Data("ID3".utf8) + Data([3, 0, 0, 0, 0, 0, 64]) + Data(count: 64)

@Suite struct FLACFixtureTests {
    // Measured Oct 28, 2026, the same for both files except where shown: 176,400 frames = 4.0000 s at 44,100 Hz,
    // 2 channels; left 440 Hz -6.000 dBFS (+124 dB over the other bins; tone24.flac +170 dB), right 1000 Hz
    // -12.000 dBFS (+109 dB; tone24.flac +160 dB); click at sample 88,200, 0.000 ms from 2.000 s.
    // Against the lab's decode of the same files, offset found by cross-correlating the channel mean over 4,096
    // samples around the click (lags -3,000 to 3,000): offset 0 samples, the same length, every sample identical
    // (largest difference 0) for both. The lab's tone.flac is tone.wav exactly; its tone24.flac is the 24-bit
    // integers the fixture script wrote, each divided by 2^23, exactly.
    @Test(arguments: [("tone.flac", 16), ("tone24.flac", 24)])
    func decodesTheToneAtItsOwnRate(_ name: String, _ bits: Int) throws {
        let d = try decodeFLAC(try fixtureBytes(name)).get()
        #expect(d.bitsPerSample == bits && d.fileChannels == 2 && !d.ogg && d.streamOffset == 0)
        #expect(d.declaredFrames == 176_400)
        let b = try AudioDecoder.decode(Fixture.url(name))
        #expect(b == d.buffer)
        checkTone(b, name: name, rate: 44100)
        #expect(b.frames == 176_400 && clickIndex(b.mono()) == 88_200)
    }

    /// Lossless and in the same 16-bit quantisation, so nothing may differ: not the length, not one sample.
    @Test func the16BitFileIsTheWavSampleForSample() throws {
        let flac = try AudioDecoder.decode(Fixture.url("tone.flac"))
        let wav = try AudioDecoder.decode(Fixture.url("tone.wav"))
        #expect(flac == wav, "tone.flac differs from tone.wav")
    }

    /// The same signal quantised to 24 bits instead of 16. Measured: largest difference from tone.wav 3.04e-5, at
    /// the full-scale click (32,767 / 32,768 against 8,388,607 / 8,388,608), 2.99e-5 elsewhere (the 16-bit
    /// rounding, up to half of 2^-15, plus the two scales' difference at the peaks), RMS 1.22e-5.
    @Test func the24BitFileIsWithin1e4OfTheWav() throws {
        let flac = try AudioDecoder.decode(Fixture.url("tone24.flac"))
        let wav = try AudioDecoder.decode(Fixture.url("tone.wav"))
        #expect(flac.frames == wav.frames && flac.channelCount == wav.channelCount)
        var largest: Float = 0, squares = 0.0
        for (a, b) in zip(flac.samples, wav.samples) {
            largest = max(largest, abs(a - b))
            squares += Double(a - b) * Double(a - b)
        }
        let rms = (squares / Double(flac.samples.count)).squareRoot()
        #expect(largest <= 1e-4, "largest difference from tone.wav \(largest)")
        // Every sample is a whole number of 2^-23 steps, and most are not whole 2^-15 steps: real 24-bit audio.
        #expect(flac.samples.allSatisfy { ($0 * 8_388_608).rounded() == $0 * 8_388_608 })
        #expect(flac.samples.filter { ($0 * 32768).rounded() != $0 * 32768 }.count > flac.samples.count / 2)
        #expect(flac.channel(0)[88_200] == Float(8_388_607) / 8_388_608)  // the click at full scale
        print("DeckieDecode tone24.flac vs tone.wav: largest difference \(largest), RMS \(rms)")
    }

    /// dr_flac reads Ogg-FLAC by default; the lab cannot (libsndfile 1.2.2 fails to open tone.oga: "unknown error
    /// in flac decoder"), so this has no lab numbers. ffmpeg's Ogg writer leaves STREAMINFO's frame count at 0
    /// ("unknown"), so the count is not checked: an Ogg-FLAC file cut short decodes as far as it goes.
    @Test func oggFLACDecodesLikeTheWav() throws {
        let bytes = try fixtureBytes("tone.oga")
        #expect(AudioFormat.sniff(bytes) == .flac)
        let d = try decodeFLAC(bytes).get()
        #expect(d.ogg && d.bitsPerSample == 16 && d.fileChannels == 2 && d.declaredFrames == nil)
        let b = try AudioDecoder.decode(Fixture.url("tone.oga"))
        checkTone(b, name: "tone.oga", rate: 44100)
        #expect(b == (try AudioDecoder.decode(Fixture.url("tone.wav"))), "tone.oga differs from tone.wav")
        // Cut in half: what is there decodes, with no error.
        let half = try decodeFLAC(bytes.prefix(bytes.count / 2)).get().buffer
        #expect(half.frames > 0 && half.frames < 176_400)
        #expect(half.samples == Array(b.samples.prefix(half.samples.count)))
    }

    /// ID3v2 tags in front of "fLaC": the lab reads through them (176,400 frames, identical); dr_flac by itself
    /// fails to open such a file (its metadata reader goes back to byte 42, inside the tag), so FLACReader skips
    /// the tags first.
    @Test func id3v2TagsInFrontChangeNothing() throws {
        let file = try fixtureBytes("tone.flac")
        let plain = try decodeFLAC(file).get().buffer
        // ID3v2.4 with a footer (flag 0x10): size 20, then 20 bytes, then the 10-byte footer "3DI".
        let id3v24 = Data("ID3".utf8) + Data([4, 0, 0x10, 0, 0, 0, 20]) + Data(count: 20) + Data("3DI".utf8)
            + Data([4, 0, 0x10, 0, 0, 0, 20])
        let cases: [(String, Data, offset: Int)] = [
            ("an ID3v2.3 tag", id3v23Tag + file, 74),
            ("an ID3v2.3 tag, then an ID3v2.4 tag with a footer", id3v23Tag + id3v24 + file, 74 + 40),
        ]
        for (what, bytes, offset) in cases {
            #expect(AudioFormat.sniff(bytes) == .flac, "\(what)")
            let d = try decodeFLAC(bytes).get()
            #expect(d.streamOffset == offset && d.buffer == plain, "\(what): \(d.buffer.frames) frames")
            #expect(try decodeBytes(bytes).get() == plain, "\(what), through AudioDecoder")
        }
        // An ID3 tag in front of MPEG audio is still MP3.
        #expect(AudioFormat.sniff(id3v23Tag + (try fixtureBytes("tone.mp3"))) == .mp3)
    }

    /// Cut or damaged copies of tone.flac (99,104 bytes: 60 bytes of header, then 39 frames of 4,608 samples, the
    /// last one 1,104; frame 19 runs from byte 49,121 to 51,963). The lab refuses each of them too ("flac decoder
    /// lost sync", or for the cut header "File contains data in an unimplemented format" and "Internal psf_fseek()
    /// failed"). dr_flac read 4,096 samples at a time, as its own whole-file functions read, returns 87,552 frames
    /// for the first without complaint, and for the damaged frames goes on past them, giving 171,792 frames (one
    /// byte flipped, or the header's checksum) and 167,184 (ten bytes zeroed), with everything after the damage 104
    /// or 209 ms early.
    @Test func damagedFilesGiveAClearError() throws {
        let file = try fixtureBytes("tone.flac")
        func edited(_ edit: (inout Data) -> Void) -> Data {
            var d = file
            edit(&d)
            return d
        }
        // Frame 19's header: the sync code FF F8, 0x59 (4,608 samples at 44.1 kHz), the channel layout, the frame
        // number 19, then its checksum (CRC-8).
        let frame19 = 49_121
        #expect(file[frame19..<(frame19 + 3)] == Data([0xFF, 0xF8, 0x59]) && file[frame19 + 4] == 19)
        let cases: [(String, Data, String)] = [
            ("cut to 50,000 bytes, inside frame 19", file.prefix(50_000),
             "decoding stopped at 1.985 s of 4.000 s (87552 of 176400 samples per channel): the file is cut short"),
            ("cut to 100 bytes, inside the first frame", file.prefix(100),
             "decoding stopped at 0.000 s of 4.000 s (0 of 176400 samples per channel): the file is cut short"),
            ("cut to 41 bytes, inside STREAMINFO", file.prefix(41), "the file is cut short inside the FLAC header"),
            ("one byte flipped in frame 19", edited { $0[50_000] ^= 0xFF },
             "decoding stopped at 1.985 s of 4.000 s (87552 of 176400 samples per channel): the frame there is "
                + "damaged"),
            ("ten bytes zeroed in frame 19", edited { $0.replaceSubrange(50_000..<50_010, with: Data(count: 10)) },
             "decoding stopped at 1.985 s of 4.000 s (87552 of 176400 samples per channel): the frame there is "
                + "damaged"),
            ("frame 19's header checksum flipped", edited { $0[frame19 + 5] ^= 0xFF },
             "the frame at 1.985 s (sample 87552) is damaged or missing: decoding past it would bring the audio "
                + "after it early"),
            ("noise after \"fLaC\"", file.prefix(4) + noise(4096),
             "dr_flac could not read the stream header (STREAMINFO and the metadata blocks after it): the file is "
                + "cut short or damaged there"),
            ("a metadata block claiming more bytes than the file holds", edited { $0[43] = 0x7F },
             "dr_flac could not read the stream header"),
            ("an ID3v2 tag claiming more bytes than the file holds, \"fLaC\" inside it",
             Data("ID3".utf8) + Data([4, 0, 0, 0x7F, 0x7F, 0x7F, 0x7F]) + file,
             "the ID3v2 tag at the start claims more bytes than the file holds"),
            ("no stream after the tag", id3v23Tag + noise(100), "no \"fLaC\" or Ogg-FLAC header after the ID3v2 tag"),
        ]
        for (what, bytes, message) in cases {
            guard case .failure(let e) = decodeFLAC(bytes) else {
                Issue.record("\(what): decoded")
                continue
            }
            #expect(e.kind == .damaged && e.format == .flac, "\(what)")
            #expect(e.message.hasPrefix(message), "\(what): \(e.message)")
        }
        // Through AudioDecoder too, for the first.
        let e = try #require(decodeFailure(file.prefix(50_000)))
        #expect(e.kind == .damaged && e.format == .flac && e.message.hasSuffix("the file is cut short"))
    }

    /// STREAMINFO's frame count decides the length, as in the lab: the lab reads tone.flac with the count edited to
    /// 100,000 as 100,000 frames (dr_flac by itself decodes all 176,400). A count of 0 means "unknown", and then
    /// everything decodes (the lab fails on that file: libsndfile reports its length as 2^63 - 1 frames).
    @Test func streamInfosFrameCountDecidesTheLength() throws {
        let file = try fixtureBytes("tone.flac"), wav = try AudioDecoder.decode(Fixture.url("tone.wav"))
        /// tone.flac with STREAMINFO's 36-bit frame count (the low bits of bytes 21 to 25) set.
        func counting(_ n: Int) -> Data {
            var d = file
            d[21] = d[21] & 0xF0 | UInt8(n >> 32)
            for i in 0..<4 { d[22 + i] = UInt8((n >> (24 - 8 * i)) & 0xFF) }
            return d
        }
        #expect(try decodeFLAC(counting(176_400)).get().buffer == wav)  // the edit as a no-op
        let short = try decodeFLAC(counting(100_000)).get()
        #expect(short.declaredFrames == 100_000 && short.buffer.frames == 100_000)
        #expect(short.buffer.samples == Array(wav.samples.prefix(200_000)))
        let unknown = try decodeFLAC(counting(0)).get()
        #expect(unknown.declaredFrames == nil && unknown.buffer == wav)
        guard case .failure(let e) = decodeFLAC(counting(200_000)) else {
            Issue.record("a count of 200,000: decoded")
            return
        }
        #expect(e.message == "decoding stopped at 4.000 s of 4.535 s (176400 of 200000 samples per channel): "
                + "the file is cut short")
    }
}

// FLAC files built here: STREAMINFO, then frames whose subframes are verbatim (each sample written as it is, in
// `bits` bits), with the checksums dr_flac checks.

/// Bits, most significant first, as FLAC packs them.
struct BitWriter {
    var bytes: [UInt8] = []
    var used = 0  // bits used in the last byte; 0 starts a new one

    mutating func put(_ value: Int, _ count: Int) {
        for i in stride(from: count - 1, through: 0, by: -1) {
            if used == 0 { bytes.append(0) }
            if (value >> i) & 1 != 0 { bytes[bytes.count - 1] |= UInt8(0x80 >> used) }
            used = (used + 1) % 8
        }
    }

    /// FLAC's variant of UTF-8 for frame and sample numbers, up to 2^31 - 1.
    mutating func utf8(_ n: Int) {
        if n < 0x80 { return put(n, 8) }
        let extra = n < 0x800 ? 1 : n < 0x10000 ? 2 : n < 0x200000 ? 3 : n < 0x4000000 ? 4 : 5
        put((0xFF00 >> (extra + 1)) & 0xFF | n >> (6 * extra), 8)
        for k in stride(from: extra - 1, through: 0, by: -1) { put(0x80 | (n >> (6 * k)) & 0x3F, 8) }
    }
}

func crc8(_ bytes: [UInt8]) -> UInt8 {
    var c: UInt8 = 0
    for b in bytes {
        c ^= b
        for _ in 0..<8 { c = c & 0x80 != 0 ? c << 1 ^ 0x07 : c << 1 }
    }
    return c
}

func crc16(_ bytes: [UInt8]) -> UInt16 {
    var c: UInt16 = 0
    for b in bytes {
        c ^= UInt16(b) << 8
        for _ in 0..<8 { c = c & 0x8000 != 0 ? c << 1 ^ 0x8005 : c << 1 }
    }
    return c
}

/// A native FLAC file: "fLaC", STREAMINFO (frame count `total`, by default the frames given), then one frame per
/// block of interleaved integer samples, numbered 0, 1, 2... With `variable`, the frames carry their first sample's
/// number instead, as a variable-block-size stream does. `numbers` overrides what the frames carry.
func flacFile(rate: Int = 44100, channels: Int, bits: Int, blocks: [[Int]], total: Int? = nil,
              numbers: [Int]? = nil, variable: Bool = false) -> Data {
    let sizes = blocks.map { $0.count / channels }
    var info = BitWriter()
    info.put(sizes.max()!, 16)  // smallest block size: the same, as for a fixed block size
    info.put(sizes.max()!, 16)
    info.put(0, 24)  // smallest and largest frame in bytes: unknown
    info.put(0, 24)
    info.put(rate, 20)
    info.put(channels - 1, 3)
    info.put(bits - 1, 5)
    info.put(total ?? sizes.reduce(0, +), 36)
    info.put(0, 128)  // MD5 of the samples: not computed
    var file = Array("fLaC".utf8) + [0x80, 0, 0, 34] + info.bytes  // last metadata block, type 0, 34 bytes
    var first = 0
    for (i, block) in blocks.enumerated() {
        var w = BitWriter()
        w.put(variable ? 0xFFF9 : 0xFFF8, 16)  // sync code, then the blocking strategy bit
        w.put(7, 4)  // block size: 16 bits after the frame number, less one
        w.put(0, 4)  // sample rate: STREAMINFO's
        w.put(channels - 1, 4)  // independent channels
        w.put(0, 3)  // sample size: STREAMINFO's
        w.put(0, 1)
        w.utf8(numbers?[i] ?? (variable ? first : i))
        w.put(sizes[i] - 1, 16)
        w.put(Int(crc8(w.bytes)), 8)
        for c in 0..<channels {
            w.put(0b0000_0010, 8)  // a zero bit, subframe type 1 (verbatim), no wasted bits
            for f in 0..<sizes[i] { w.put(block[f * channels + c], bits) }
        }
        w.used = 0  // zero bits up to the byte boundary
        w.put(Int(crc16(w.bytes)), 16)
        file += w.bytes
        first += sizes[i]
    }
    return Data(file)
}

@Suite struct FLACReaderTests {
    // Values every bit depth holds exactly, as in the WAV and AIFF tests.
    let frames: [[Float]] = [[0, 0.5], [-0.25, -1], [0.75, 0.125], [-0.5, 0]]

    /// Samples as integers of `bits` bits, in blocks of 3 and 1 frames: two FLAC frames, the second of one sample.
    func blocks(_ values: [[Float]], bits: Int) -> [[Int]] {
        let ints = values.map { $0.map { Int(Double($0) * Double(1 << (bits - 1))) } }
        return [Array(ints[0..<3].joined()), Array(ints[3])]
    }

    /// Each was also read by the lab on Oct 28, 2026: the same rate, frames and samples, once its channels are cut
    /// to two, except the 20-bit file, which libsndfile refuses ("File contains data in an unimplemented format";
    /// it reads 8, 16 and 24 bits).
    @Test func everyDepthAndLayoutDecodesExactly() throws {
        let stereo = frames.flatMap { $0 }, mono = frames.map { [$0[0]] }
        let six = frames.map { $0 + [0.25, -0.25, 0.5, -0.5] }
        let cases: [(String, Data, rate: Int, channels: Int, bits: Int, [Float])] = [
            ("16-bit stereo", flacFile(channels: 2, bits: 16, blocks: blocks(frames, bits: 16)), 44100, 2, 16,
             stereo),
            ("16-bit mono at 22,050 Hz", flacFile(rate: 22050, channels: 1, bits: 16, blocks: blocks(mono, bits: 16)),
             22050, 1, 16, mono.flatMap { $0 }),
            ("8-bit stereo", flacFile(channels: 2, bits: 8, blocks: blocks(frames, bits: 8)), 44100, 2, 8, stereo),
            ("20-bit stereo at 96 kHz, samples across byte boundaries",
             flacFile(rate: 96000, channels: 2, bits: 20, blocks: blocks(frames, bits: 20)), 96000, 2, 20, stereo),
            ("24-bit, three channels cut to two",
             flacFile(channels: 3, bits: 24, blocks: blocks(frames.map { $0 + [0.25] }, bits: 24)), 44100, 2, 24,
             stereo),
            ("16-bit, six channels cut to two", flacFile(channels: 6, bits: 16, blocks: blocks(six, bits: 16)),
             44100, 2, 16, stereo),
            ("16-bit stereo, variable block size",
             flacFile(channels: 2, bits: 16, blocks: blocks(frames, bits: 16), variable: true), 44100, 2, 16, stereo),
        ]
        for (what, data, rate, channels, bits, want) in cases {
            #expect(AudioFormat.sniff(data) == .flac, "\(what)")
            let d = try decodeFLAC(data).get()
            #expect(d.buffer.sampleRate == rate && d.buffer.channelCount == channels && d.buffer.frames == 4,
                    "\(what)")
            #expect(d.bitsPerSample == bits && d.declaredFrames == 4, "\(what)")
            #expect(d.buffer.samples == want, "\(what): \(d.buffer.samples)")
            #expect(try decodeBytes(data).get() == d.buffer, "\(what), through AudioDecoder")
        }
    }

    /// A frame whose checksum fails, or a frame missing between two good ones (the second numbered 2, or starting at
    /// sample 4), is refused rather than letting the audio after it come early. The lab refuses the first ("Internal
    /// psf_fseek() failed") but reads the frames numbered 0 and 2 as 6 samples, the numbering ignored.
    @Test func aDamagedOrMissingFrameIsRefused() throws {
        let three = blocks(frames, bits: 16)[0]
        func file(_ numbers: [Int], variable: Bool = false) -> Data {
            flacFile(channels: 2, bits: 16, blocks: [three, three], numbers: numbers, variable: variable)
        }
        #expect(try decodeFLAC(file([0, 1])).get().buffer.frames == 6)
        #expect(try decodeFLAC(file([0, 3], variable: true)).get().buffer.frames == 6)
        // The first channel's second sample (-0.25: E0 00) one bit off, so the frame's checksum fails: 42 bytes of
        // "fLaC" and STREAMINFO, the 8-byte frame header, the subframe's own byte, then 16 bits a sample. dr_flac
        // drops that frame and decodes the next.
        var flipped = file([0, 1])
        #expect(flipped[42..<44] == Data([0xFF, 0xF8]) && flipped[50] == 0x02 && flipped[53] == 0xE0)
        flipped[53] ^= 1
        // What the frames carry, and the sample where the gap shows (3 samples are 0.07 ms at 44.1 kHz).
        let cases: [(String, Data, at: Int)] = [
            ("a sample bit flipped in the first frame", flipped, 0),
            ("frames 0 and 2", file([0, 2]), 3), ("variable, samples 0 and 4", file([0, 4], variable: true), 3),
            ("frames 1 and 2", file([1, 2]), 0), ("variable, samples 3 and 6", file([3, 6], variable: true), 0),
        ]
        for (what, data, at) in cases {
            guard case .failure(let e) = decodeFLAC(data) else {
                Issue.record("\(what): decoded")
                continue
            }
            #expect(e.kind == .damaged && e.message == "the frame at 0.000 s (sample \(at)) is damaged or missing: "
                    + "decoding past it would bring the audio after it early", "\(what): \(e.message)")
        }
    }

    /// More than 24 bits: dr_flac reads no frame marked 32-bit and the lab refuses such a file ("File contains data
    /// in an unimplemented format"; checked on a 32-bit file from ffmpeg, whose frames are marked so).
    @Test func moreThan24BitsIsNotSupported() throws {
        let data = flacFile(channels: 2, bits: 32, blocks: blocks(frames, bits: 32))
        guard case .failure(let e) = decodeFLAC(data) else {
            Issue.record("decoded")
            return
        }
        #expect(e.kind == .unsupported && e.format == .flac)
        #expect(e.message == "32-bit FLAC is not supported (up to 24 bits is)")
    }
}
