import Foundation
import Testing
import DeckieCapture
import DeckieCrate
import DeckieRecognition
import DeckieTestSupport

/// A crate of generated songs with their fingerprints, as Desk's run would make them (the fingerprint from the song's
/// own sound at `rate`).
func generatedCrate(songs: Int = 6, seconds: Double = 40, rate: Int = 44100) -> (crate: Crate, audio: [[Float]]) {
    var tracks: [CrateTrack] = []
    var audio: [[Float]] = []
    let engine = CrateTrack.Engine(family: CrateFormat.EngineFamily.deckie, version: "0.1", platform: "test", fidelity: 1,
                                   models: [], decoder: .init(name: "test"))
    for i in 0..<songs {
        let a = ListenSongs.song(seed: UInt64(500 + i), seconds: seconds, rate: rate)
        audio.append(a)
        var t = CrateTrack(id: "song\(i)", file: .init(name: "Song \(i).wav", rel: "Song \(i).wav", bytes: a.count * 2, sha1Head: nil,
                                                       durationS: seconds),
                           ident: .init(title: "Song \(i)", artist: "Generated"),
                           analysis: .init(engine: "test", analysedAt: "2026-11-20T00:00:00Z", device: "test", secs: nil, level: 1),
                           engine: engine)
        t.grid = .init(source: "test", confidence: 1, bpm: 120 + Double(i), firstDownbeatS: 0, nBars: 20, fitMadMs: 0,
                       bpmIn: 120, bpmOut: 120, inTrusted: true, outTrusted: true)
        t.fingerprint = CrateTrack.Fingerprint(Landmarks(mono: a, sampleRate: rate), madeBy: "test", madeAt: "2026-11-20T00:00:00Z")
        tracks.append(t)
    }
    let crate = Crate(manifest: CrateManifest(crateId: "generated", name: "Generated", createdAt: "2026-11-20T00:00:00Z",
                                              devicesSeen: ["test"]), tracks: tracks)
    return (crate, audio)
}

func scratchFile(_ name: String) -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-capture-tests-\(ProcessInfo.processInfo.processIdentifier)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(name + "-" + UUID().uuidString.prefix(8))
}

final class Collected: @unchecked Sendable {
    let lock = NSLock()
    var readings: [ListenReading] = []
    var levels: [SoundLevel] = []
    var ended: [CaptureError] = []
    var frames = 0
}

@Suite(.serialized) struct CaptureTests {
    static let built = generatedCrate()
    static let index: RecognitionIndex = { try! built.crate.recognitionIndex(cachedAt: scratchFile("index.dkx")) }()

    /// Plays song `song` from `from` seconds through a stand-in input at `rate` with `channels` channels and returns the
    /// readings the booth's listener made of it.
    func hear(song: Int, from: Double, seconds: Double, rate: Int, channels: Int) throws -> [ListenReading] {
        let mono = ListenSongs.excerpt(ListenSongs.song(seed: UInt64(500 + song), seconds: 40, rate: rate), rate: rate, from: from, seconds: seconds)
        let samples = channels == 2 ? ListenSongs.stereo(mono) : mono
        let got = Collected()
        let booth = BoothRecogniser(index: Self.index) { r in got.lock.lock(); got.readings.append(r); got.lock.unlock() }
        let source = SampleSource(samples: samples, format: SoundFormat(rate: rate, channels: channels))
        let capture = LiveCapture(source)
        let format = try capture.start(sound: { s, f in booth.feed(s, channels: f.channels, sampleRate: f.rate) },
                                       level: { l in got.lock.lock(); got.levels.append(l); got.lock.unlock() },
                                       ended: { _ in })
        #expect(format == SoundFormat(rate: rate, channels: channels))
        source.waitUntilPlayed()
        capture.stop()
        booth.finish()
        capture.flushLevels()
        #expect(capture.framesHeard == mono.count, "every frame counted")
        // About five levels a second of sound, counted by samples.
        #expect(abs(got.levels.count - Int(seconds * 5)) <= 1)
        return got.readings
    }

    @Test(arguments: [(44100, 1), (44100, 2), (48000, 1), (48000, 2)])
    func theListenerNamesTheSongCapturedAtTheInputsOwnFormat(_ format: (Int, Int)) throws {
        // The crate's fingerprints were made at 44.1 kHz; the input gives 44.1 or 48 kHz, one or two channels.
        let readings = try hear(song: 3, from: 9, seconds: 10, rate: format.0, channels: format.1)
        let named = readings.filter { $0.state != .nothingYet }
        #expect(!named.isEmpty)
        #expect(named.allSatisfy { $0.id == "song3" }, "\(named.map { $0.id ?? "-" })")
        let last = try #require(named.last)
        // Where in the song: 9 s in, plus the 10 s heard.
        #expect(abs((last.positionSeconds ?? 0) - 19) < 0.6)
        #expect(abs(last.time - 10) < 0.01, "time is samples heard")
    }

    @Test func aSecondSongIsNamedAfterTheFirst() throws {
        let rate = 48000
        let a = ListenSongs.excerpt(ListenSongs.song(seed: 501, rate: rate), rate: rate, from: 5, seconds: 10)
        let b = ListenSongs.excerpt(ListenSongs.song(seed: 504, rate: rate), rate: rate, from: 20, seconds: 12)
        let got = Collected()
        let booth = BoothRecogniser(index: Self.index) { r in got.lock.lock(); got.readings.append(r); got.lock.unlock() }
        let source = SampleSource(samples: a + b, format: SoundFormat(rate: rate, channels: 1))
        let capture = LiveCapture(source)
        try capture.start(sound: { s, f in booth.feed(s, channels: f.channels, sampleRate: f.rate) }, level: { _ in }, ended: { _ in })
        source.waitUntilPlayed(); capture.stop(); booth.finish()
        let ids = got.readings.compactMap { $0.state == .nothingYet ? nil : $0.id }
        #expect(ids.first == "song1")
        #expect(ids.last == "song4")
        #expect(Set(ids).isSubset(of: ["song1", "song4"]))
    }

    @Test func theLevelSaysHowLoudAndWhenItClips() throws {
        let rate = 48000
        // Half a second of a sine at half scale (-9 dB average, -6 dB peak), then half a second clipping.
        var s = (0..<rate / 2).map { Float(0.5 * sin(2 * Double.pi * 440 * Double($0) / Double(rate))) }
        s += (0..<rate / 2).map { _ in Float(1.0) }
        let got = Collected()
        let source = SampleSource(samples: s, format: SoundFormat(rate: rate, channels: 1))
        let capture = LiveCapture(source)
        try capture.start(sound: { _, _ in }, level: { l in got.lock.lock(); got.levels.append(l); got.lock.unlock() }, ended: { _ in })
        source.waitUntilPlayed(); capture.stop(); capture.flushLevels()
        #expect(got.levels.count == 5)
        let first = got.levels[0]
        #expect(abs(first.rmsDB - -9.03) < 0.1 && abs(first.peakDB - -6.02) < 0.1)
        #expect(first.clipped == 0 && first.meter > 0.8 && first.meter < 0.9)
        #expect(got.levels[4].clipped == rate / 5)
        #expect(got.levels.allSatisfy { !$0.silent })
        #expect(abs(got.levels[4].seconds - 1) < 1e-9)
    }

    @Test func nothingButZerosIsSaidToBeNoSound() throws {
        let rate = 16000
        let got = Collected()
        let source = SampleSource(samples: [Float](repeating: 0, count: rate * 4), format: SoundFormat(rate: rate, channels: 1))
        let capture = LiveCapture(source)
        try capture.start(sound: { _, _ in }, level: { l in got.lock.lock(); got.levels.append(l); got.lock.unlock() }, ended: { _ in })
        source.waitUntilPlayed(); capture.stop(); capture.flushLevels()
        #expect(got.levels.first?.silent == false)
        #expect(got.levels.last?.silent == true)
        #expect(got.levels.last?.peakDB == -120)
    }

    @Test func anInputThatGoesAwayEndsWithAPlainErrorAndAnInputThatCannotOpenThrows() throws {
        let got = Collected()
        let source = SampleSource(samples: [Float](repeating: 0.1, count: 4800), format: SoundFormat(rate: 48000, channels: 1),
                                  endsWith: CaptureError("gone", "unplugged"))
        let capture = LiveCapture(source)
        try capture.start(sound: { _, _ in }, level: { _ in }, ended: { e in got.lock.lock(); got.ended.append(e); got.lock.unlock() })
        source.waitUntilPlayed()
        capture.stop()
        #expect(got.ended == [CaptureError("gone", "unplugged")])

        let refused = SampleSource(samples: [], format: SoundFormat(rate: 48000, channels: 1), failsToStart: CaptureError("notAllowed"))
        #expect(throws: CaptureError("notAllowed")) {
            try LiveCapture(refused).start(sound: { _, _ in }, level: { _ in }, ended: { _ in })
        }
    }

    @Test func startAndStopTwiceAndStopBeforeStart() throws {
        let source = SampleSource(samples: [Float](repeating: 0.1, count: 48000 * 20), format: SoundFormat(rate: 48000, channels: 1), pace: 1)
        source.stop()   // before start: nothing happens
        let capture = LiveCapture(source)
        for _ in 0..<2 {
            let got = Collected()
            try capture.start(sound: { s, _ in got.lock.lock(); got.frames += s.count; got.lock.unlock() }, level: { _ in }, ended: { _ in })
            #expect(throws: CaptureError.self) { try source.start(sound: { _, _ in }, ended: { _ in }) }   // already going
            Thread.sleep(forTimeInterval: 0.3)
            capture.stop()
            got.lock.lock(); let after = got.frames; got.lock.unlock()
            Thread.sleep(forTimeInterval: 0.2)
            got.lock.lock(); let later = got.frames; got.lock.unlock()
            #expect(after > 0 && later == after, "nothing arrives once stop returns")
            capture.stop()   // twice: nothing happens
        }
    }

    /// The real inputs are listed without opening one (no permission is asked); on a machine with no sound system at
    /// all (a build machine), listing says so with a plain error instead.
    @Test func theInputsAreListedOrTheirAbsenceIsSaidPlainly() {
        do {
            let listed = try SoundInputs.list()
            #expect(!listed.system.isEmpty)
            #expect(listed.inputs.filter(\.isDefault).count <= 1)
            if let d = listed.inputs.firstIndex(where: \.isDefault) { #expect(d == 0, "the default comes first") }
            for i in listed.inputs { #expect(SoundInputs.named(i.name, in: listed.inputs)?.name == i.name) }
            #expect(SoundInputs.named("no such input \(UUID())", in: listed.inputs) == nil)
            #expect(SoundInputs.named(nil, in: listed.inputs) == nil)
        } catch let e as CaptureError {
            #expect(e.code == "noSystem")
        } catch {
            Issue.record("listing threw \(error)")
        }
    }
}
