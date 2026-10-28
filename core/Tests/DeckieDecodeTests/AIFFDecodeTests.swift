import Foundation
import Testing
@testable import DeckieDecode

// AIFF and AIFF-C (AIFFReader). The variants are built byte by byte here, like the WAV ones. Every variant below
// that decodes, and the cut and unfilled files, were also read by the lab's decoder on Oct 28, 2026 (soundfile
// 0.14.0, libsndfile 1.2.2): the same rate, frames and samples, once its channels are cut to two as the lab cuts
// them. libsndfile also reads "twos", "ulaw", "alaw", "ima4" and "fl64",
// which DeckieDecode reports as not supported.

@Suite struct AIFFFixtureTests {
    // tone.aiff (AIFF, 16-bit big-endian) and tone_sowt.aifc (AIFF-C "sowt", 16-bit little-endian) hold tone.wav's
    // samples, written by ffmpeg. Measured Oct 28, 2026, the same for both: 176,400 frames = 4.0000 s at 44,100 Hz,
    // 2 channels; left 440 Hz -6.000 dBFS (+124 dB over the other bins), right 1000 Hz -12.000 dBFS (+109 dB);
    // click at sample 88,200, 0.000 ms from 2.000 s; every sample equal to tone.wav's. The lab's decoder reads both
    // files to the same samples as tone.wav too (offset 0, largest difference 0).
    @Test(arguments: ["tone.aiff", "tone_sowt.aifc"])
    func decodesTheToneSampleForSampleLikeTheWav(_ name: String) throws {
        let aiff = try AudioDecoder.decode(Fixture.url(name))
        checkTone(aiff, name: name, rate: 44100)
        let wav = try AudioDecoder.decode(Fixture.url("tone.wav"))
        // The same signal in the same 16-bit quantisation, so nothing may differ: not the length, not one sample.
        #expect(aiff.frames == wav.frames && clickIndex(aiff.mono()) == 88_200)
        #expect(aiff == wav, "\(name) differs from tone.wav")
    }

    /// ffmpeg, not this file's encoder, wrote the sample rate in tone.aiff: 44,100 as an 80-bit float.
    @Test func theSampleRateBytesFfmpegWrote() throws {
        let file = [UInt8](try fixtureBytes("tone.aiff"))
        // FORM header (12 bytes), then COMM's id and size (8), channels (2), frames (4), bits (2): the rate at 28.
        let rate = Array(file[28..<38])
        #expect(rate == [0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0])
        #expect(AIFFReader.extended80(rate) == 44100)
    }

    /// A file cut short is read as far as it goes; so is what ffmpeg writes to a pipe, where it cannot go back to
    /// fill in the sizes: FORM size, COMM frame count and SSND size all 0. libsndfile reads both the same way.
    @Test func aCutFileAndUnfilledSizesAreReadAsFarAsTheyGo() throws {
        let file = try fixtureBytes("tone.aiff")
        let wav = try AudioDecoder.decode(Fixture.url("tone.wav"))
        // 54 bytes of header (FORM 12, COMM 8 + 18, SSND 8 + offset and block size 8), then 4 bytes a frame.
        let cut = try decodeBytes(file.prefix(100_001)).get()
        #expect(cut.frames == 24_986)  // (100,001 - 54) / 4, the partial frame dropped
        #expect(cut.samples == Array(wav.samples.prefix(cut.samples.count)))
        var piped = file
        for at in [4, 22, 42] { piped.replaceSubrange(at..<(at + 4), with: be32(0)) }
        #expect(try decodeBytes(piped).get() == wav)
        var unbounded = file
        unbounded.replaceSubrange(42..<46, with: be32(0xFFFF_FFFF))  // the SSND size
        #expect(try decodeBytes(unbounded).get() == wav)
    }
}

// The AIFF reader's variants, built here.

func be16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
func be32(_ v: Int) -> [UInt8] { [24, 16, 8, 0].map { UInt8((v >> $0) & 0xFF) } }

/// The 80-bit extended float of a positive whole number: this file's own encoder, written apart from the reader's
/// decoder (layout in AIFFReader.extended80).
func extended80Bytes(_ n: UInt64) -> [UInt8] {
    precondition(n > 0)
    let top = 63 - n.leadingZeroBitCount  // the highest set bit
    let significand = n << (63 - top)
    return be16(16383 + top) + (0..<8).map { UInt8((significand >> (56 - 8 * $0)) & 0xFF) }
}

/// An AIFF or AIFF-C file: "FORM", size, "AIFF" or "AIFC", then the chunks in order, each padded to an even length.
func aiffFile(_ formType: String, _ chunks: [(String, [UInt8])]) -> Data {
    var body = Array(formType.utf8)
    for (id, bytes) in chunks { body += Array(id.utf8) + be32(bytes.count) + bytes + (bytes.count % 2 == 1 ? [0] : []) }
    return Data(Array("FORM".utf8) + be32(body.count) + body)
}

/// A COMM chunk. AIFF-C's adds the compression type and an empty Pascal string for its name.
func commChunk(channels: Int, frames: Int = 4, bits: Int, rate: [UInt8], compression: String? = nil) -> (String, [UInt8]) {
    var b = be16(channels) + be32(frames) + be16(bits) + rate
    if let compression { b += Array(compression.utf8) + [0, 0] }
    return ("COMM", b)
}

func commChunk(channels: Int, frames: Int = 4, bits: Int, rate: UInt64, compression: String? = nil) -> (String, [UInt8]) {
    commChunk(channels: channels, frames: frames, bits: bits, rate: extended80Bytes(rate), compression: compression)
}

/// An SSND chunk: the offset, block size 0, `offset` bytes of padding, the samples.
func ssndChunk(_ samples: [UInt8], offset: Int = 0) -> (String, [UInt8]) {
    ("SSND", be32(offset) + be32(0) + [UInt8](repeating: 0xEE, count: offset) + samples)
}

/// Samples as AIFF bytes: integers of `bits` bits, left-justified in whole bytes (value × 2^(8 × bytes - 1)),
/// big-endian or little-endian ("sowt"); or 32-bit big-endian float.
func aiffPCM(_ values: [Float], bits: Int, littleEndian: Bool = false, float: Bool = false) -> [UInt8] {
    values.flatMap { v -> [UInt8] in
        if float { return be32(Int(v.bitPattern)) }
        let bytes = (bits + 7) / 8
        let i = Int(Double(v) * Double(1 << (8 * bytes - 1)))
        let big = (0..<bytes).map { UInt8((i >> (8 * (bytes - 1 - $0))) & 0xFF) }
        return littleEndian ? big.reversed() : big
    }
}

@Suite struct AIFFReaderTests {
    // Values every encoding holds exactly, 8-bit included.
    let frames: [[Float]] = [[0, 0.5], [-0.25, -1], [0.75, 0.125], [-0.5, 0]]

    @Test func everyEncodingAndLayoutDecodesExactly() throws {
        let stereo = frames.flatMap { $0 }, mono = frames.map { $0[0] }
        let three: [Float] = frames.flatMap { $0 + [0.25] }
        let anno: (String, [UInt8]) = ("ANNO", Array("odd".utf8))  // odd length, so a pad byte follows
        let mark: (String, [UInt8]) = ("MARK", [0, 0])
        let fver: (String, [UInt8]) = ("FVER", be32(0xA280_5140))  // AIFF-C version 1
        let cases: [(String, Data, rate: Int, channels: Int, [Float])] = [
            ("16-bit stereo", aiffFile("AIFF", [commChunk(channels: 2, bits: 16, rate: 44100),
                                                ssndChunk(aiffPCM(stereo, bits: 16))]), 44100, 2, stereo),
            ("8-bit stereo (signed, unlike WAV)",
             aiffFile("AIFF", [commChunk(channels: 2, bits: 8, rate: 44100), ssndChunk(aiffPCM(stereo, bits: 8))]),
             44100, 2, stereo),
            ("24-bit stereo at 48 kHz",
             aiffFile("AIFF", [commChunk(channels: 2, bits: 24, rate: 48000), ssndChunk(aiffPCM(stereo, bits: 24))]),
             48000, 2, stereo),
            ("32-bit integer stereo at 96 kHz",
             aiffFile("AIFF", [commChunk(channels: 2, bits: 32, rate: 96000), ssndChunk(aiffPCM(stereo, bits: 32))]),
             96000, 2, stereo),
            ("16-bit mono at 22,050 Hz",
             aiffFile("AIFF", [commChunk(channels: 1, bits: 16, rate: 22050), ssndChunk(aiffPCM(mono, bits: 16))]),
             22050, 1, mono),
            ("24-bit, three channels cut to two",
             aiffFile("AIFF", [commChunk(channels: 3, bits: 24, rate: 44100), ssndChunk(aiffPCM(three, bits: 24))]),
             44100, 2, stereo),
            ("20-bit, left-justified in 3 bytes",
             aiffFile("AIFF", [commChunk(channels: 2, bits: 20, rate: 44100), ssndChunk(aiffPCM(stereo, bits: 20))]),
             44100, 2, stereo),
            ("SSND before COMM, an odd-sized ANNO between them, MARK after",
             aiffFile("AIFF", [ssndChunk(aiffPCM(stereo, bits: 16)), anno, commChunk(channels: 2, bits: 16, rate: 44100),
                               mark]), 44100, 2, stereo),
            ("SSND offset 6 (block alignment)",
             aiffFile("AIFF", [commChunk(channels: 2, bits: 16, rate: 44100),
                               ssndChunk(aiffPCM(stereo, bits: 16), offset: 6)]), 44100, 2, stereo),
            ("COMM frame count wrong: SSND decides, as in libsndfile",
             aiffFile("AIFF", [commChunk(channels: 2, frames: 2, bits: 16, rate: 44100),
                               ssndChunk(aiffPCM(stereo, bits: 16))]), 44100, 2, stereo),
            ("AIFF-C NONE, 16-bit, with FVER",
             aiffFile("AIFC", [fver, commChunk(channels: 2, bits: 16, rate: 44100, compression: "NONE"),
                               ssndChunk(aiffPCM(stereo, bits: 16))]), 44100, 2, stereo),
            ("AIFF-C sowt, 16-bit little-endian at 11,025 Hz",
             aiffFile("AIFC", [fver, commChunk(channels: 2, bits: 16, rate: 11025, compression: "sowt"),
                               ssndChunk(aiffPCM(stereo, bits: 16, littleEndian: true))]), 11025, 2, stereo),
            ("AIFF-C sowt, 24-bit little-endian mono",
             aiffFile("AIFC", [commChunk(channels: 1, bits: 24, rate: 44100, compression: "sowt"),
                               ssndChunk(aiffPCM(mono, bits: 24, littleEndian: true))]), 44100, 1, mono),
            ("AIFF-C fl32", aiffFile("AIFC", [commChunk(channels: 2, bits: 32, rate: 44100, compression: "fl32"),
                                              ssndChunk(aiffPCM(stereo, bits: 32, float: true))]), 44100, 2, stereo),
            ("AIFF-C FL32, bits field left at 0",
             aiffFile("AIFC", [commChunk(channels: 2, bits: 0, rate: 48000, compression: "FL32"),
                               ssndChunk(aiffPCM([1.5, -2] + stereo.dropFirst(2), bits: 32, float: true))]),
             48000, 2, [1.5, -2] + stereo.dropFirst(2)),
        ]
        for (what, data, rate, channels, want) in cases {
            let b = try decodeBytes(data).get()
            #expect(b.sampleRate == rate && b.channelCount == channels && b.frames == 4, "\(what)")
            #expect(b.samples == want, "\(what): \(b.samples)")
        }
    }

    @Test func rejectsWhatItCannotRead() throws {
        let samples = ssndChunk(aiffPCM(frames.flatMap { $0 }, bits: 16))
        func comm(channels: Int = 2, bits: Int = 16, rate: [UInt8] = extended80Bytes(44100),
                  _ c: String? = nil) -> (String, [UInt8]) {
            commChunk(channels: channels, bits: bits, rate: rate, compression: c)
        }
        let cut = try fixtureBytes("tone.aiff").prefix(30)  // inside the COMM chunk
        let cases: [(String, Data, AudioDecodeError.Kind, String)] = [
            ("compression ima4", aiffFile("AIFC", [comm("ima4"), samples]), .unsupported,
             "AIFF-C compression type 'ima4' is not supported (NONE, sowt and fl32 are)"),
            ("compression ulaw", aiffFile("AIFC", [comm("ulaw"), samples]), .unsupported,
             "AIFF-C compression type 'ulaw' is not supported (NONE, sowt and fl32 are)"),
            ("compression fl64", aiffFile("AIFC", [comm(bits: 64, "fl64"), samples]), .unsupported,
             "AIFF-C compression type 'fl64' is not supported (NONE, sowt and fl32 are)"),
            ("40-bit integers", aiffFile("AIFF", [comm(bits: 40), samples]), .unsupported,
             "40-bit integer PCM is not supported (up to 32 bits is)"),
            ("no COMM", aiffFile("AIFF", [samples]), .damaged, "no COMM chunk"),
            ("no SSND", aiffFile("AIFF", [comm()]), .damaged, "no SSND chunk"),
            ("COMM too short", aiffFile("AIFF", [("COMM", [0, 2, 0, 0, 0, 4, 0, 16]), samples]), .damaged,
             "the COMM chunk is too short"),
            ("AIFF-C COMM without its compression type", aiffFile("AIFC", [comm(), samples]), .damaged,
             "the AIFF-C COMM chunk has no compression type"),
            ("no channels", aiffFile("AIFF", [comm(channels: 0), samples]), .damaged, "the COMM chunk gives no channels"),
            ("sample size 0", aiffFile("AIFF", [comm(bits: 0), samples]), .damaged, "the COMM chunk gives no sample size"),
            ("sample rate 0", aiffFile("AIFF", [comm(rate: [UInt8](repeating: 0, count: 10)), samples]), .damaged,
             "the COMM chunk gives no usable sample rate (0.0)"),
            ("sample rate negative", aiffFile("AIFF", [comm(rate: [0xC0, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]), samples]),
             .damaged, "the COMM chunk gives no usable sample rate (-44100.0)"),
            ("sample rate infinite", aiffFile("AIFF", [comm(rate: [0x7F, 0xFF, 0x80, 0, 0, 0, 0, 0, 0, 0]), samples]),
             .damaged, "the COMM chunk gives no usable sample rate (inf)"),
            ("sample rate not a number", aiffFile("AIFF", [comm(rate: [0x7F, 0xFF, 0xC0, 0, 0, 0, 0, 0, 0, 0]), samples]),
             .damaged, "the COMM chunk gives no usable sample rate (nan)"),
            ("sample rate 2^32", aiffFile("AIFF", [comm(rate: extended80Bytes(1 << 32)), samples]), .damaged,
             "the COMM chunk gives no usable sample rate (4294967296.0)"),
            ("SSND shorter than its offset and block size", aiffFile("AIFF", [comm(), ("SSND", [0, 0, 0, 0])]),
             .damaged, "the SSND chunk is too short"),
            ("SSND offset past its end", aiffFile("AIFF", [comm(), ("SSND", be32(1000) + be32(0) + [0, 0, 0, 0])]),
             .damaged, "the SSND chunk's offset points past its end"),
            ("cut inside COMM", Data(cut), .damaged, "the COMM chunk is too short"),
        ]
        for (what, data, kind, message) in cases {
            guard case .failure(let e) = decodeBytes(data) else {
                Issue.record("\(what): decoded")
                continue
            }
            #expect(e.kind == kind && e.format == .aiff, "\(what): \(e.kind), \(e.format)")
            #expect(e.message == message, "\(what): \(e.message)")
        }
    }

    @Test func eightyBitSampleRates() throws {
        let known: [(Double, [UInt8])] = [
            (44100, [0x40, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]),
            (48000, [0x40, 0x0E, 0xBB, 0x80, 0, 0, 0, 0, 0, 0]),
            (22050, [0x40, 0x0D, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]),
            (96000, [0x40, 0x0F, 0xBB, 0x80, 0, 0, 0, 0, 0, 0]),
            (11025, [0x40, 0x0C, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]),
            (384000, [0x40, 0x11, 0xBB, 0x80, 0, 0, 0, 0, 0, 0]),
            (1, [0x3F, 0xFF, 0x80, 0, 0, 0, 0, 0, 0, 0]),
        ]
        for (value, bytes) in known {
            #expect(AIFFReader.extended80(bytes) == value, "\(value)")
            #expect(extended80Bytes(UInt64(value)) == bytes, "\(value)")
        }
        #expect(AIFFReader.extended80([0x3F, 0xFE, 0x80, 0, 0, 0, 0, 0, 0, 0]) == 0.5)
        #expect(AIFFReader.extended80([0xC0, 0x0E, 0xAC, 0x44, 0, 0, 0, 0, 0, 0]) == -44100)
        #expect(AIFFReader.extended80([UInt8](repeating: 0, count: 10)) == 0)
        #expect(AIFFReader.extended80([0x7F, 0xFF, 0x80, 0, 0, 0, 0, 0, 0, 0]) == .infinity)
        #expect(AIFFReader.extended80([0x7F, 0xFF, 0xC0, 0, 0, 0, 0, 0, 0, 0]).isNaN)
        // Every whole number up to 2^53 comes back exactly.
        for n: UInt64 in [2, 3, 8000, 16000, 32000, 44056, 47952, 88200, 176_400, 192_000, 352_800, 0xFFFF_FFFF,
                          1 << 53, (1 << 53) - 1] {
            #expect(AIFFReader.extended80(extended80Bytes(n)) == Double(n), "\(n)")
        }
        // Early Macs sampled at 22,254.5454... Hz (244,800 / 11): a full 64-bit significand, rounded to a Double;
        // a file at that rate decodes at 22,254 Hz, the fraction dropped as libsndfile drops it.
        let mac: [UInt8] = [0x40, 0x0D, 0xAD, 0xDD, 0x17, 0x45, 0xD1, 0x74, 0x5D, 0x17]
        #expect(abs(AIFFReader.extended80(mac) - 244_800.0 / 11) < 1e-9)
        let b = try decodeBytes(aiffFile("AIFF", [commChunk(channels: 2, bits: 16, rate: mac),
                                                  ssndChunk(aiffPCM(frames.flatMap { $0 }, bits: 16))])).get()
        #expect(b.sampleRate == 22254 && b.frames == 4)
    }
}
