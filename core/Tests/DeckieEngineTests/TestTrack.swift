import Foundation
import DeckieAudio
import DeckieCore
import DeckieTestSupport

/// The synthesised "track" the engine is tested on: 32 bars of 4/4 drums at 124 BPM (`DrumPattern`, accents on the
/// downbeats) with an A minor progression (Am, Dm, E, Am, one chord a bar; `ChordSynth`), stereo at 44.1 kHz. The
/// first beat is at 0.5 s after silence; the first 8 bars are 15 dB down (a quiet intro); the last 8 bars fade
/// linearly in dB from full level to -40 dB, then the music stops and 1 s of silence follows: 63.4 s in all.
///
/// Why just over a minute and not 60 s: the lab counts an ending as a fade only when there is more than a minute of
/// sound (`last_sound - first_sound > 60` in mixer/analyze.py), so a 60 s track could never show one.
///
/// The level: the body (bars 9 to 24) is scaled to `bodyLufs` integrated loudness, measured with the loudness module
/// on the body alone, which is the "synthesised level" the whole track's integrated loudness is checked against.
enum TestTrack {
    static let rate = 44100
    static let bpm = 124.0
    static let firstBeat = 0.5
    static let bars = 32
    static let introBars = 8
    static let fadeBars = 8
    static let introDB = -15.0
    static let fadeEndDB = -40.0
    static let tail = 1.0
    static let bodyLufs = -16.0
    /// A minor.
    static let camelot = "8A"
    static let chords = [ChordSynth.Am, ChordSynth.Dm, ChordSynth.E, ChordSynth.Am]

    static var beatS: Double { 60 / bpm }
    static var barS: Double { 4 * beatS }
    /// The end of bar 32, where the music stops.
    static var musicEnd: Double { firstBeat + Double(bars) * barS }
    static var samples: Int { Int((musicEnd + tail) * Double(rate)) }
    static var fadeStart: Double { firstBeat + Double(bars - fadeBars) * barS }
    static var introEnd: Double { firstBeat + Double(introBars) * barS }

    /// The track, interleaved stereo float32.
    static func render() -> AudioBuffer {
        let n = samples, r = Double(rate)
        let beats = DrumPattern.steadyBeats(first: firstBeat, bpm: bpm, end: musicEnd - 1e-6)
        let drums = DrumPattern.render(rate: rate, samples: n, beats: beats, seed: 7)
        let start = DrumPattern.onset(firstBeat, rate: rate)
        let span = DrumPattern.onset(musicEnd, rate: rate) - start
        let harmony = ChordSynth.render(rate: rate, samples: n,
                                        chords: ChordSynth.progression(rate: rate, samples: span, chordSeconds: barS,
                                                                       chords, offset: start),
                                        harmonics: 5, noise: 0, seed: 11, exact: false)
        func gain(_ i: Int) -> Double {
            let t = Double(i) / r
            if t >= musicEnd { return 0 }
            if t < introEnd { return pow(10, introDB / 20) }
            if t >= fadeStart { return pow(10, fadeEndDB * (t - fadeStart) / (musicEnd - fadeStart) / 20) }
            return 1
        }
        var mixed = [Double](repeating: 0, count: 2 * n)
        for i in 0..<n {
            let g = gain(i), d = Double(drums[i]), c = 0.25 * harmony[i]
            mixed[2 * i] = g * (d + 0.9 * c)
            mixed[2 * i + 1] = g * (0.9 * d + c)
        }
        // Scale so the body sits at bodyLufs.
        let a = DrumPattern.onset(introEnd, rate: rate), b = DrumPattern.onset(fadeStart, rate: rate)
        let body = AudioBuffer(sampleRate: rate, channelCount: 2, samples: mixed[(2 * a)..<(2 * b)].map { Float($0) })
        let scale = pow(10, (bodyLufs - Loudness.integrated(body)!) / 20)
        return AudioBuffer(sampleRate: rate, channelCount: 2, samples: mixed.map { Float($0 * scale) })
    }

    /// The first and last sample (any channel) above -60 dBFS, in seconds: the sound's bounds found sample by sample,
    /// against which the engine's 10 ms frames are checked.
    static func soundBounds(_ buffer: AudioBuffer) -> (first: Double, last: Double) {
        let thr = Float(0.001)
        let s = buffer.samples, ch = buffer.channelCount
        let first = s.firstIndex { abs($0) > thr }.map { $0 / ch } ?? 0
        let last = s.lastIndex { abs($0) > thr }.map { $0 / ch } ?? 0
        return (Double(first) / Double(buffer.sampleRate), Double(last + 1) / Double(buffer.sampleRate))
    }

    /// A 32-bit float WAV file of `buffer`.
    static func wav(_ buffer: AudioBuffer) -> Data {
        var d = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let ch = buffer.channelCount, bytes = buffer.samples.count * 4
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(3); u16(ch); u32(buffer.sampleRate)
        u32(buffer.sampleRate * ch * 4); u16(ch * 4); u16(32)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        buffer.samples.withUnsafeBufferPointer { d.append(UnsafeBufferPointer(start: $0.baseAddress, count: $0.count)) }
        return d
    }
}

/// A folder of its own under the system's temporary folder, for the files a test writes.
func temporaryFolder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("deckie-engine-tests-\(ProcessInfo.processInfo.processIdentifier)")
        .appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// The ffmpeg program, if one is installed where programs usually are (used only to make the MP3 test file).
func findFFmpeg() -> String? {
    let dirs = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        + ["/usr/bin", "/usr/local/bin", "/opt/homebrew/bin"]
    return dirs.map { $0 + "/ffmpeg" }.first { FileManager.default.isExecutableFile(atPath: $0) }
}

/// The repository's root, found from this file's place in it.
let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
