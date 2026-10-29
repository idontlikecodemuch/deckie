import Foundation
import Testing
import DeckieAudio
import DeckieBuild
import DeckieEngine
import DeckieInference
import DeckieTestSupport

/// Whether ONNX Runtime, the Beat This! model and the ffmpeg program are there; the reason is printed once when not.
enum Available {
    static let engine: Bool = {
        do {
            try Builder.checkEngine()
            return true
        } catch {
            print("\(error): the crate builder's engine tests are skipped")
            return false
        }
    }()

    static let ffmpeg: String? = {
        let found = TestTrack.findFFmpeg()
        if found == nil { print("the ffmpeg program was not found: the second test track is a WAV, not an MP3") }
        return found
    }()
}

/// The music folder the builder's tests read, made once per test process, and one analyser shared by the tests:
///
///   CD1/Track One.wav     the engine's synthesised test track (`TestTrack`, 63 s at 124 BPM in A minor)
///   CD2/Track Two.mp3     the same audio as a 192 kbps MP3 with title, artist and tempo tags (ffmpeg); without
///                         ffmpeg, Track Two.wav, the track at half the level (other bytes, another record)
///   CD2/broken.mp3        an ID3 tag and no audio: damaged
///   locked.m4p            DeckieDecode's FairPlay stand-in: protected
///   cover.jpg             not audio, not counted
actor Fixture {
    static let shared = Fixture()

    private var folder: URL?
    private var engine: Analyser?

    /// The track the bench test compares with itself: its path below the folder.
    static let firstTrack = "CD1/Track One.wav"
    static var secondTrack: String { Available.ffmpeg == nil ? "CD2/Track Two.wav" : "CD2/Track Two.mp3" }

    func analyser() throws -> Analyser {
        if let engine { return engine }
        let a = try Builder.makeAnalyser(jobs: 2)
        engine = a
        return a
    }

    func music() throws -> URL {
        if let folder { return folder }
        let root = try temporaryFolder("music")
        try? FileManager.default.removeItem(at: root)
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("CD1"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("CD2"), withIntermediateDirectories: true)
        let buffer = TestTrack.render()
        let first = root.appendingPathComponent(Self.firstTrack)
        try TestTrack.wav(buffer).write(to: first)
        if let ffmpeg = Available.ffmpeg {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: ffmpeg)
            p.arguments = ["-y", "-hide_banner", "-loglevel", "error", "-i", first.path, "-codec:a", "libmp3lame",
                           "-b:a", "192k", "-id3v2_version", "3", "-metadata", "title=Track Two",
                           "-metadata", "artist=Tagged Artist", "-metadata", "TBPM=124",
                           root.appendingPathComponent(Self.secondTrack).path]
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 { throw CocoaError(.fileWriteUnknown) }
        } else {
            let half = AudioBuffer(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount,
                                   samples: buffer.samples.map { $0 * 0.5 })
            try TestTrack.wav(half).write(to: root.appendingPathComponent(Self.secondTrack))
        }
        try Data(Array("ID3".utf8) + [3, 0, 0, 0, 0, 0, 0] + Array("not audio at all".utf8))
            .write(to: root.appendingPathComponent("CD2/broken.mp3"))
        try fm.copyItem(at: repositoryRoot.appendingPathComponent("core/Tests/DeckieDecodeTests/Fixtures/protected.m4p"),
                        to: root.appendingPathComponent("locked.m4p"))
        try Data([0xFF, 0xD8, 0xFF, 0xE0]).write(to: root.appendingPathComponent("cover.jpg"))
        folder = root
        return root
    }
}

/// The repository's root, found from this file's place in it.
let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()

/// Collects a build's events.
final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [BuildEvent] = []
    func add(_ e: BuildEvent) { lock.lock(); list.append(e); lock.unlock() }
    var all: [BuildEvent] { lock.lock(); defer { lock.unlock() }; return list }
    var started: (files: Int, unchanged: Int, queued: Int)? {
        for e in all { if case .started(let f, let u, let q, _, _) = e { return (f, u, q) } }
        return nil
    }
    var outcomes: [String: FileProgress.Outcome] {
        var d: [String: FileProgress.Outcome] = [:]
        for e in all { if case .file(let p) = e { d[p.rel] = p.outcome } }
        return d
    }
}
