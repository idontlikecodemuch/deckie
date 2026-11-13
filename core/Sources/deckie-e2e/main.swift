// deckie-e2e: the end-to-end check of the crate builder that both workflows run (core-linux.yml, core-windows.yml),
// the same on Linux and Windows. A development tool, never shipped.
//
//   deckie-e2e make <folder> --mp3 <file>   writes the small music folder below; <file> is the MP3 of the test track
//                                      (made by `deckie-e2e mp3`, on a machine that has the ffmpeg program)
//   deckie-e2e check <crate file>      reads the crate file with the core's validator (CrateReader, either form) and
//                                      checks it holds what the folder should give; exits with 1 and says why if not
//   deckie-e2e pack <package> <file>   the package folder as one file (CrateArchive), for the workflow to keep
//   deckie-e2e mp3 <file>              the synthesised test track as a 64 kbps mono MP3, encoded by the ffmpeg
//                                      program (Linux and macOS). No audio is committed: the workflows make this file
//                                      once per run, on Linux, and hand the same bytes to both platforms.
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

func check(_ file: URL) {
    let crate: Crate
    do {
        crate = try CrateReader.read(from: file)
    } catch {
        fail("the core's validator refuses \(file.lastPathComponent):\n\(error)")
    }
    var wrong: [String] = []
    func expect(_ ok: Bool, _ what: @autoclosure () -> String) { if !ok { wrong.append(what()) } }

    let rels = crate.tracks.compactMap(\.file.rel).sorted()
    expect(rels == [mp3Rel, flacRel, wavRel].sorted(), "the songs are \(rels), expected \([mp3Rel, flacRel, wavRel].sorted())")
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
    let expected = ["\(lockedRel): protected", "\(toneRel): analysis_error", "_old: skipped"].sorted()
    expect(entries == expected, "the import log has \(entries), expected \(expected)")
    expect(log?.filesSeen == 5, "files seen: \(log?.filesSeen ?? -1), expected 5 (three songs and two that did not go in)")
    expect(log?.tracks == 3, "the import log counts \(log?.tracks ?? -1) songs, expected 3")
    let text = (try? CrateWriter.encode(crate)).flatMap { $0[CrateFormat.tracksFile] }.map { String(decoding: $0, as: UTF8.self) } ?? ""
    expect(text.contains("Tr\u{e4}ck Zwei.flac"), "the name that is not ASCII did not come through as written")

    if !wrong.isEmpty { fail("\(file.lastPathComponent) is a valid crate file but not the expected one:\n  " + wrong.joined(separator: "\n  ")) }
    print("\(file.lastPathComponent): valid (\(CrateArchive.isArchive(file) ? "single-file form" : "package folder")), "
          + "3 songs, 2 files not in it with their reasons, 1 folder left out, hidden files not read")
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
    case ("pack", 3):
        try CrateArchive.pack(package: URL(fileURLWithPath: args[1]), to: URL(fileURLWithPath: args[2]))
        print("wrote \(args[2])")
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
