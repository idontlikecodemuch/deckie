// deckie-e2e: the end-to-end check of the crate builder that both workflows run (core-linux.yml, core-windows.yml),
// the same on Linux and Windows. A development tool, never shipped.
//
//   deckie-e2e make <folder> --mp3 <file>   writes the small music folder below; <file> is the MP3 of the test track
//                                      (made by `deckie-e2e mp3`, on a machine that has the ffmpeg program)
//   deckie-e2e check <crate file>      reads the crate file with the core's validator (CrateReader, either form) and
//                                      checks it holds what the folder should give; exits with 1 and says why if not
//   deckie-e2e check-pc <crate file>   the same for the PC program's crate file, which reads every folder (it has no
//                                      rule that leaves out folders starting with "_"), so 4 songs
//   deckie-e2e pack <package> <file>   the package folder as one file (CrateArchive), for the workflow to keep
//   deckie-e2e mp3 <file>              the synthesised test track as a 64 kbps mono MP3, encoded by the ffmpeg
//                                      program (Linux and macOS). No audio is committed: the workflows make this file
//                                      once per run, on Linux, and hand the same bytes to both platforms.
//   deckie-e2e songs <folder> [--count 4] [--seconds 240]   a folder of full-length synthesised songs (drums and
//                                      chords, each at its own tempo), as WAV and FLAC by turns, to time the builder
//                                      on songs of a real length
//
// The folder (songs are the engine's synthesised test track, `TestTrack`: 63 s of drums at 124 BPM in A minor):
//
//   Singles/Track One.wav                 32-bit float WAV; a space in the name
//   Singles/Deep Cuts/Träck Zwei.flac     16-bit FLAC, written here with no encoder; a nested folder, a name that is
//                                         not ASCII (ä as one character, U+00E4)
//   Album/03 Track Three.mp3              the MP3 of the test track given with --mp3
//   Album/short tone.mp3                  DeckieDecode's 4-second test tone: too short to analyse, so not in the crate
//   Album/locked.m4p                      the stand-in for a copy-protected file: not in the crate, "protected"
//   Album/cover.jpg                       not audio: not counted
//   .hidden.wav                           a hidden file (its name starts with a dot; on Windows also marked hidden)
//   Hidden By Windows.wav                 Windows only: an ordinary name, marked hidden the Windows way
//   .hidden folder/inside.wav             a hidden folder
//   _old/parked.wav                       a folder left out by the builder's rule, with an import-log entry
//
// So a correct build has 3 songs, 2 files that did not go in (one analysis_error, one protected) and one left-out folder.

import Foundation
import DeckieAudio
import DeckieCore
import DeckieCrate
import DeckieTestSupport
#if os(Windows)
import WinSDK
#endif

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("deckie-e2e: \(message)\n".utf8))
    exit(1)
}

let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
let decodeFixtures = repository.appendingPathComponent("core/Tests/DeckieDecodeTests/Fixtures")

let wavRel = "Singles/Track One.wav"
let flacRel = "Singles/Deep Cuts/Tr\u{e4}ck Zwei.flac"
let mp3Rel = "Album/03 Track Three.mp3"
let toneRel = "Album/short tone.mp3"
let lockedRel = "Album/locked.m4p"

func url(_ root: URL, _ rel: String) -> URL {
    rel.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
}

func hide(_ file: URL) {
    #if os(Windows)
    file.path.withCString(encodedAs: UTF16.self) { _ = SetFileAttributesW($0, DWORD(FILE_ATTRIBUTE_HIDDEN)) }
    #endif
}

func make(_ root: URL, mp3: URL) throws {
    let fm = FileManager.default
    try? fm.removeItem(at: root)
    func write(_ data: Data, _ rel: String) throws {
        let file = url(root, rel)
        try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
    }
    let track = TestTrack.render()
    let wav = TestTrack.wav(track)
    try write(wav, wavRel)
    try write(FLACWriter.flac16(track), flacRel)
    try write(try Data(contentsOf: mp3), mp3Rel)
    try write(try Data(contentsOf: decodeFixtures.appendingPathComponent("tone.mp3")), toneRel)
    try write(try Data(contentsOf: decodeFixtures.appendingPathComponent("protected.m4p")), lockedRel)
    try write(Data([0xFF, 0xD8, 0xFF, 0xE0]), "Album/cover.jpg")
    // Hidden things, each with other bytes than any song, so one that was read by mistake would show as a fourth song.
    func quieter(_ gain: Float) -> Data {
        TestTrack.wav(AudioBuffer(sampleRate: track.sampleRate, channelCount: track.channelCount,
                                  samples: track.samples.map { $0 * gain }))
    }
    try write(quieter(0.9), ".hidden.wav")
    hide(url(root, ".hidden.wav"))
    try write(quieter(0.8), ".hidden folder/inside.wav")
    hide(url(root, ".hidden folder"))
    try write(quieter(0.7), "_old/parked.wav")
    #if os(Windows)
    try write(quieter(0.6), "Hidden By Windows.wav")
    hide(url(root, "Hidden By Windows.wav"))
    #endif
    print("wrote the test music folder: \(root.path)")
}

/// A synthesised song of `seconds` at `bpm`: `TestTrack`'s drums and chords for as many bars as fit, a quiet first
/// eight bars, no fade.
func song(seconds: Double, bpm: Double, seed: UInt64) -> AudioBuffer {
    let rate = TestTrack.rate, r = Double(rate)
    let barS = 4 * 60 / bpm, first = 0.5
    let bars = max(16, Int((seconds - first - 1) / barS))
    let end = first + Double(bars) * barS
    let n = Int((end + 1) * r)
    let beats = DrumPattern.steadyBeats(first: first, bpm: bpm, end: end - 1e-6)
    let drums = DrumPattern.render(rate: rate, samples: n, beats: beats, seed: seed)
    let start = DrumPattern.onset(first, rate: rate)
    let span = DrumPattern.onset(end, rate: rate) - start
    let harmony = ChordSynth.render(rate: rate, samples: n,
                                    chords: ChordSynth.progression(rate: rate, samples: span, chordSeconds: barS,
                                                                   TestTrack.chords, offset: start),
                                    harmonics: 5, noise: 0, seed: seed &+ 4, exact: false)
    let introEnd = first + 8 * barS
    var out = [Float](repeating: 0, count: 2 * n)
    for i in 0..<n {
        let t = Double(i) / r
        let g = t >= end ? 0 : (t < introEnd ? 0.09 : 0.5)
        let d = Double(drums[i]), c = 0.25 * harmony[i]
        out[2 * i] = Float(g * (d + 0.9 * c))
        out[2 * i + 1] = Float(g * (0.9 * d + c))
    }
    return AudioBuffer(sampleRate: rate, channelCount: 2, samples: out)
}

func songs(_ root: URL, count: Int, seconds: Double) throws {
    let fm = FileManager.default
    try? fm.removeItem(at: root)
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    for i in 0..<count {
        let bpm = 118.0 + 3.0 * Double(i)
        let buffer = song(seconds: seconds, bpm: bpm, seed: UInt64(20 + i))
        let name = "Song \(i + 1) at \(Int(bpm))"
        if i % 2 == 0 { try TestTrack.wav(buffer).write(to: root.appendingPathComponent(name + ".wav")) }
        else { try FLACWriter.flac16(buffer).write(to: root.appendingPathComponent(name + ".flac")) }
    }
    print("wrote \(count) songs of \(Int(seconds)) s to \(root.path)")
}

func check(_ file: URL, pc: Bool = false) {
    let crate: Crate
    do {
        crate = try CrateReader.read(from: file)
    } catch {
        fail("the core's validator refuses \(file.lastPathComponent):\n\(error)")
    }
    var wrong: [String] = []
    func expect(_ ok: Bool, _ what: @autoclosure () -> String) { if !ok { wrong.append(what()) } }

    let rels = crate.tracks.compactMap(\.file.rel).sorted()
    let songs = ([mp3Rel, flacRel, wavRel] + (pc ? ["_old/parked.wav"] : [])).sorted()
    expect(rels == songs, "the songs are \(rels), expected \(songs)")
    for t in crate.tracks {
        let rel = t.file.rel ?? "?"
        expect(!rel.contains("\\"), "\(rel): a backslash in a crate path")
        expect(t.file.name == CratePath.lastName(rel), "\(rel): file.name is \(t.file.name)")
        expect(t.grid.map { abs($0.bpm - TestTrack.bpm) < 0.5 } ?? false, "\(rel): tempo \(t.grid?.bpm ?? 0), expected \(TestTrack.bpm)")
        expect(t.grid?.nBars == TestTrack.bars, "\(rel): \(t.grid?.nBars ?? 0) bars, expected \(TestTrack.bars)")
        expect(t.file.sha256?.hasPrefix(t.id) ?? false, "\(rel): the id is not the start of the file's SHA-256")
        expect(t.signatures.isEmpty, "\(rel): has recognition signatures, which this builder cannot make")
        expect(t.bars != nil, "\(rel): no per-bar series")
    }
    let log = crate.manifest.importLog
    let entries = (log?.entries ?? []).map { "\($0.rel): \($0.reason)" }.sorted()
    let expected = (["\(lockedRel): protected", "\(toneRel): analysis_error"] + (pc ? [] : ["_old: skipped"])).sorted()
    expect(entries == expected, "the import log has \(entries), expected \(expected)")
    expect(log?.filesSeen == songs.count + 2, "files seen: \(log?.filesSeen ?? -1), expected \(songs.count + 2) (the songs and two that did not go in)")
    expect(log?.tracks == songs.count, "the import log counts \(log?.tracks ?? -1) songs, expected \(songs.count)")
    let text = (try? CrateWriter.encode(crate)).flatMap { $0[CrateFormat.tracksFile] }.map { String(decoding: $0, as: UTF8.self) } ?? ""
    expect(text.contains("Tr\u{e4}ck Zwei.flac"), "the name that is not ASCII did not come through as written")

    if !wrong.isEmpty { fail("\(file.lastPathComponent) is a valid crate file but not the expected one:\n  " + wrong.joined(separator: "\n  ")) }
    print("\(file.lastPathComponent): valid (\(CrateArchive.isArchive(file) ? "single-file form" : "package folder")), "
          + "\(songs.count) songs, 2 files not in it with their reasons, \(pc ? "no" : "1") folder left out, hidden files not read")
    for t in crate.tracks.sorted(by: { ($0.file.rel ?? "") < ($1.file.rel ?? "") }) {
        print("  \(t.file.rel ?? "?"): \(t.grid?.bpm ?? 0) BPM, \(t.grid?.nBars ?? 0) bars, key \(t.key?.camelot ?? "none"), "
              + "\(t.loudness?.integratedLufs ?? 0) LUFS, analysed in \(t.analysis.secs.map { "\($0)" } ?? "?") s")
    }
}

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch (args.first, args.count) {
    case ("make", 4) where args[2] == "--mp3":
        try make(URL(fileURLWithPath: args[1]), mp3: URL(fileURLWithPath: args[3]))
    case ("check", 2): check(URL(fileURLWithPath: args[1]))
    case ("check-pc", 2): check(URL(fileURLWithPath: args[1]), pc: true)
    case ("pack", 3):
        try CrateArchive.pack(package: URL(fileURLWithPath: args[1]), to: URL(fileURLWithPath: args[2]))
        print("wrote \(args[2])")
    case ("songs", _) where args.count >= 2:
        func value(_ name: String, _ fallback: Double) -> Double {
            args.firstIndex(of: name).flatMap { $0 + 1 < args.count ? Double(args[$0 + 1]) : nil } ?? fallback
        }
        try songs(URL(fileURLWithPath: args[1]), count: Int(value("--count", 4)), seconds: value("--seconds", 240))
    case ("mp3", 2):
        guard let ffmpeg = TestTrack.findFFmpeg() else { fail("the ffmpeg program was not found; it encodes the test MP3") }
        let out = URL(fileURLWithPath: args[1])
        let wav = out.deletingPathExtension().appendingPathExtension("wav")
        try TestTrack.wav(TestTrack.render()).write(to: wav)
        defer { try? FileManager.default.removeItem(at: wav) }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: ffmpeg)
        p.arguments = ["-y", "-hide_banner", "-loglevel", "error", "-i", wav.path, "-ac", "1", "-codec:a", "libmp3lame",
                       "-b:a", "64k", "-id3v2_version", "3", "-metadata", "title=Track Three",
                       "-metadata", "artist=Test Artist", out.path]
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 { fail("ffmpeg could not encode the test MP3") }
        print("wrote \(out.path)")
    default: fail("usage: deckie-e2e make <folder> --mp3 <file> | check <crate file> | pack <package> <file> | mp3 <file>")
    }
} catch {
    fail("\(error)")
}
