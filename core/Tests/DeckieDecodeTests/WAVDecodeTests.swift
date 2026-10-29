import Foundation
import Testing
import DeckieDecode

/// What core/Tools/make_audio_fixtures.py put into every fixture: 4 s of stereo; left 440 Hz at -6 dBFS, right
/// 1000 Hz at -12 dBFS (peak); a full-scale single-sample click on both channels at 2.000 s. tone_mono.mp3 holds
/// the channel mean instead.
enum Tone {
    static let seconds = 4.0
    static let clickSeconds = 2.0
    static let leftHz = 440.0, leftDb = -6.0
    static let rightHz = 1000.0, rightDb = -12.0
}

/// Amplitude of the sine at `hz` in `x[start..<start + count]` (Goertzel: one DFT bin), exact when the window holds
/// a whole number of cycles.
func amplitude(_ x: [Float], hz: Double, rate: Int, start: Int, count: Int) -> Double {
    let c = 2 * cos(2 * Double.pi * hz / Double(rate))
    var s1 = 0.0, s2 = 0.0
    for i in start..<(start + count) {
        let s0 = Double(x[i]) + c * s1 - s2
        s2 = s1
        s1 = s0
    }
    return 2 * max(0, s1 * s1 + s2 * s2 - c * s1 * s2).squareRoot() / Double(count)
}

func dB(_ a: Double) -> Double { 20 * log10(max(a, 1e-12)) }

/// One channel's sine: its level at `hz` in dBFS, and how far (dB) it stands above the loudest of the other bins.
func sine(_ x: [Float], hz: Double, rate: Int) -> (db: Double, marginDb: Double) {
    let start = rate / 2, count = rate  // 0.5 s to 1.5 s: a whole second, clear of the edges and the click
    let others = [110.0, 220, 330, 440, 500, 550, 660, 880, 1000, 1500, 2000, 3000, 5000].filter { $0 != hz }
    let level = amplitude(x, hz: hz, rate: rate, start: start, count: count)
    let loudestOther = others.map { amplitude(x, hz: $0, rate: rate, start: start, count: count) }.max()!
    return (dB(level), dB(level) - dB(loudestOther))
}

/// The click's sample index: the biggest jump between neighbouring samples (the sines change slowly), then the
/// biggest magnitude within three samples of it.
func clickIndex(_ x: [Float]) -> Int {
    var best = 1
    for i in 1..<x.count where abs(x[i] - x[i - 1]) > abs(x[best] - x[best - 1]) { best = i }
    let lo = max(0, best - 3), hi = min(x.count - 1, best + 3)
    return (lo...hi).max { abs(x[$0]) < abs(x[$1]) }!
}

/// Pearson correlation of `a[i]` with `b[i + shift]` over every index both have.
func correlation(_ a: [Float], _ b: [Float], shift: Int) -> Double {
    let lo = max(0, -shift), hi = min(a.count, b.count - shift)
    guard hi - lo > 1 else { return 0 }
    var ma = 0.0, mb = 0.0
    for i in lo..<hi { ma += Double(a[i]); mb += Double(b[i + shift]) }
    ma /= Double(hi - lo)
    mb /= Double(hi - lo)
    var sab = 0.0, saa = 0.0, sbb = 0.0
    for i in lo..<hi {
        let da = Double(a[i]) - ma, db = Double(b[i + shift]) - mb
        sab += da * db
        saa += da * da
        sbb += db * db
    }
    return sab / (saa * sbb).squareRoot()
}

func ms(_ samples: Int, _ rate: Int) -> Double { Double(samples) / Double(rate) * 1000 }
func fixed(_ v: Double, _ digits: Int) -> String {
    let p = pow(10, Double(digits))
    return "\((v * p).rounded() / p)"
}

/// The briefed checks on a decoded tone: rate, channels, duration, both sines, the click. Prints the numbers.
func checkTone(_ b: AudioBuffer, name: String, rate: Int) {
    #expect(b.sampleRate == rate)
    #expect(b.channelCount == 2)
    #expect(b.samples.count == b.frames * 2)
    #expect(abs(b.duration - Tone.seconds) <= 0.060, "duration \(b.duration) s")
    let left = sine(b.channel(0), hz: Tone.leftHz, rate: b.sampleRate)
    let right = sine(b.channel(1), hz: Tone.rightHz, rate: b.sampleRate)
    #expect(abs(left.db - Tone.leftDb) <= 1.5, "left \(left.db) dBFS")
    #expect(abs(right.db - Tone.rightDb) <= 1.5, "right \(right.db) dBFS")
    #expect(left.marginDb >= 30, "440 Hz stands \(left.marginDb) dB above the other bins on the left")
    #expect(right.marginDb >= 30, "1000 Hz stands \(right.marginDb) dB above the other bins on the right")
    let click = clickIndex(b.mono())
    let clickMs = ms(click - Int(Tone.clickSeconds * Double(b.sampleRate)), b.sampleRate)
    #expect(abs(clickMs) <= 5, "click \(clickMs) ms from 2.000 s")
    print("DeckieDecode \(name): \(b.sampleRate) Hz, \(b.channelCount) channels, \(b.frames) frames = "
          + "\(fixed(b.duration, 4)) s; left 440 Hz \(fixed(left.db, 3)) dBFS (+\(fixed(left.marginDb, 0)) dB over "
          + "other bins), right 1000 Hz \(fixed(right.db, 3)) dBFS (+\(fixed(right.marginDb, 0)) dB); click at "
          + "sample \(click), \(fixed(clickMs, 3)) ms from 2.000 s")
}

@Suite struct WAVFixtureTests {
    @Test(arguments: [("tone.wav", 44100), ("tone48k.wav", 48000)])
    func decodesTheToneAtItsOwnRate(_ name: String, _ rate: Int) throws {
        let b = try AudioDecoder.decode(Fixture.url(name))
        checkTone(b, name: name, rate: rate)
        // 16-bit PCM arrives exactly: nothing added or lost, each value over 32768.
        #expect(b.frames == 4 * rate)
        #expect(b.channel(0)[2 * rate] == 32767 / 32768 && b.channel(1)[2 * rate] == 32767 / 32768)
    }

    // MP3 through dr_mp3 with the lab's gapless trimming (MP3Reader). Written against ffmpeg's decode of tone.mp3
    // on Oct 28, 2026 (176,400 frames, -6.26 and -12.26 dBFS, click at 0 ms, correlation 1.00000 and 0.99999);
    // DeckieDecode's own numbers, measured the same day:
    //   tone.mp3     176,400 frames = 4.0000 s; left 440 Hz -6.265 dBFS (+108 dB over the other bins), right
    //                1000 Hz -12.265 dBFS (+107 dB); click at sample 88,200, 0.000 ms; correlation with tone.wav
    //                1.00000 and 0.99999 at shift 0
    //   tone48k.mp3  192,000 frames = 4.0000 s; -6.264 dBFS (+102 dB), -12.265 dBFS (+96 dB); click at sample
    //                96,000, 0.000 ms; correlation 1.00000 and 0.99998 at shift 0
    // Against the lab's own decode of the same files (soundfile 0.14.0: libsndfile 1.2.2, which decodes MP3 through
    // mpg123), offset found by cross-correlating the channel mean over 4,096 samples around the click (lags
    // -3,000 to 3,000): offset 0 samples (correlation 1.000000), the same length, and after alignment
    //   tone.mp3       largest difference 1.3e-6, RMS 7.9e-8
    //   tone48k.mp3    largest difference 7.2e-7, RMS 7.6e-8
    //   tone_mono.mp3  largest difference 5.1e-7, RMS 5.9e-8
    // ffmpeg 6.1.1's decode, which trims the same way, is also at offset 0 from the lab's, with differences up to
    // 1.3e-6, 1.1e-6 and 7.8e-7 (RMS 1.8e-7, 1.8e-7, 1.3e-7). Before trimming, dr_mp3 gives 178,560 frames for
    // tone.mp3 with the click 1,105 samples (25.057 ms) late: the encoder's 576 plus the decoder's 529.
    @Test(arguments: [("tone.mp3", "tone.wav", 44100), ("tone48k.mp3", "tone48k.wav", 48000)])
    func mp3MatchesTheWav(_ name: String, _ wavName: String, _ rate: Int) throws {
        let wav = try AudioDecoder.decode(Fixture.url(wavName))
        let mp3 = try AudioDecoder.decode(Fixture.url(name))
        checkTone(mp3, name: name, rate: rate)
        let shift = clickIndex(mp3.mono()) - clickIndex(wav.mono())
        let corrL = correlation(wav.channel(0), mp3.channel(0), shift: shift)
        let corrR = correlation(wav.channel(1), mp3.channel(1), shift: shift)
        #expect(corrL > 0.99 && corrR > 0.99, "correlation with the WAV: left \(corrL), right \(corrR)")
        // Gapless: exactly the WAV's length, the click on the WAV's sample.
        #expect(mp3.frames == wav.frames && shift == 0, "\(mp3.frames) frames, click shifted \(shift) samples")
        print("DeckieDecode \(name) vs \(wavName): aligned on the click, shift \(shift) samples; "
              + "correlation left \(fixed(corrL, 5)), right \(fixed(corrR, 5))")
    }
}

// The WAV reader's variants, built byte by byte here rather than kept as files.

func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
func le32(_ v: Int) -> [UInt8] { (0..<4).map { UInt8((v >> (8 * $0)) & 0xFF) } }

/// A WAV file: "RIFF", size, "WAVE", then the chunks in order, each padded to an even length.
func riff(_ chunks: [(String, [UInt8])]) -> Data {
    var body = Array("WAVE".utf8)
    for (id, bytes) in chunks { body += Array(id.utf8) + le32(bytes.count) + bytes + (bytes.count % 2 == 1 ? [0] : []) }
    return Data(Array("RIFF".utf8) + le32(body.count) + body)
}

/// A fmt chunk; `code` 1 is integer PCM, 3 is float. Extensible puts the code in the sub-format GUID.
func fmtChunk(code: Int, channels: Int, rate: Int, bits: Int, extensible: Bool = false) -> (String, [UInt8]) {
    let align = channels * bits / 8
    var b = le16(extensible ? 0xFFFE : code) + le16(channels) + le32(rate) + le32(rate * align) + le16(align) + le16(bits)
    if extensible {
        b += le16(22) + le16(bits) + le32(0)
        b += le16(code) + [0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]
    }
    return ("fmt ", b)
}

/// Samples as little-endian bytes: integers of `bits` bits (value times 2^(bits-1)), or 32-bit float.
func pcm(_ values: [Float], bits: Int, float: Bool) -> [UInt8] {
    values.flatMap { v -> [UInt8] in
        if float { return le32(Int(v.bitPattern)) }
        let i = Int(Double(v) * Double(1 << (bits - 1)))
        return (0..<(bits / 8)).map { UInt8((i >> (8 * $0)) & 0xFF) }
    }
}

/// Writes the bytes to a temporary file and decodes it.
func decodeBytes(_ data: Data) -> Result<AudioBuffer, AudioDecodeError> {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-\(UUID().uuidString).wav")
    try! data.write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    do throws(AudioDecodeError) {
        return .success(try AudioDecoder.decode(url))
    } catch {
        return .failure(error)
    }
}

@Suite struct WAVReaderTests {
    // Values every encoding holds exactly.
    let frames: [[Float]] = [[0, 0.5], [-0.25, -1], [0.75, 0.125], [-0.5, 0]]

    @Test func everyEncodingAndLayoutDecodesExactly() throws {
        let stereo = frames.flatMap { $0 }
        let list: (String, [UInt8]) = ("LIST", Array("INFOISFT\u{5}\u{0}\u{0}\u{0}test\u{0}".utf8))
        let odd: (String, [UInt8]) = ("junk", [1, 2, 3])  // odd length, so a pad byte follows
        let cases: [(String, Data, Int, [Float])] = [
            ("16-bit stereo, LIST before fmt, odd chunk before data",
             riff([list, fmtChunk(code: 1, channels: 2, rate: 44100, bits: 16), odd,
                   ("data", pcm(stereo, bits: 16, float: false))]), 2, stereo),
            ("24-bit stereo", riff([fmtChunk(code: 1, channels: 2, rate: 44100, bits: 24),
                                    ("data", pcm(stereo, bits: 24, float: false))]), 2, stereo),
            ("32-bit integer stereo", riff([fmtChunk(code: 1, channels: 2, rate: 44100, bits: 32),
                                            ("data", pcm(stereo, bits: 32, float: false))]), 2, stereo),
            ("32-bit float stereo, LIST after data", riff([fmtChunk(code: 3, channels: 2, rate: 44100, bits: 32),
                                                           ("data", pcm(stereo, bits: 32, float: true)), list]), 2, stereo),
            ("16-bit mono", riff([fmtChunk(code: 1, channels: 1, rate: 44100, bits: 16),
                                  ("data", pcm(frames.map { $0[0] }, bits: 16, float: false))]), 1, frames.map { $0[0] }),
            ("24-bit extensible, three channels cut to two",
             riff([fmtChunk(code: 1, channels: 3, rate: 44100, bits: 24, extensible: true),
                   ("data", pcm(frames.flatMap { $0 + [0.25] }, bits: 24, float: false))]), 2, stereo),
            ("32-bit float extensible", riff([fmtChunk(code: 3, channels: 2, rate: 44100, bits: 32, extensible: true),
                                              ("data", pcm(stereo, bits: 32, float: true))]), 2, stereo),
        ]
        for (what, data, channels, want) in cases {
            let b = try decodeBytes(data).get()
            #expect(b.sampleRate == 44100 && b.channelCount == channels && b.frames == 4, "\(what)")
            #expect(b.samples == want, "\(what): \(b.samples)")
        }
    }

    @Test func rejectsWhatItCannotRead() {
        func kind(_ data: Data) -> (AudioDecodeError.Kind, AudioFormat)? {
            if case .failure(let e) = decodeBytes(data) { return (e.kind, e.format) }
            return nil
        }
        #expect(kind(riff([("data", [0, 0, 0, 0])]))! == (.damaged, .wav))  // no fmt chunk
        #expect(kind(riff([fmtChunk(code: 1, channels: 2, rate: 44100, bits: 16)]))! == (.damaged, .wav))  // no data
        #expect(kind(riff([fmtChunk(code: 1, channels: 2, rate: 44100, bits: 8), ("data", [128, 128])]))!
                == (.unsupported, .wav))  // 8-bit PCM
        #expect(kind(riff([fmtChunk(code: 2, channels: 2, rate: 44100, bits: 16), ("data", [0, 0, 0, 0])]))!
                == (.unsupported, .wav))  // ADPCM
        #expect(kind(Data("not audio at all".utf8))! == (.unsupported, .unknown))
    }

    @Test func aDataChunkRunningPastTheEndIsReadAsFarAsItGoes() throws {
        var data = riff([fmtChunk(code: 1, channels: 2, rate: 44100, bits: 16),
                         ("data", pcm(frames.flatMap { $0 }, bits: 16, float: false) + [7])])  // half a sample over
        let size = try #require(data.range(of: Data("data".utf8))).upperBound
        data.replaceSubrange(size..<(size + 4), with: le32(0xFFFF_FFFF))  // the size a streaming writer leaves
        let b = try decodeBytes(data).get()
        #expect(b.frames == 4 && b.samples == frames.flatMap { $0 })
    }
}
