import Foundation
import Testing
import DeckieCrate
import DeckieRecognition
import DeckieCapture
import DeckieTestSupport
@testable import DeckieDesk

/// Listening inside Desk (research booth-in-desk, step 1): the index made and kept per crate, a stand-in input heard
/// with the shared listener, and the `booth.*` messages. No real microphone is opened.
@Suite(.serialized) struct BoothTests {
    static let rate = 44100

    /// A crate of generated songs with fingerprints, kept in a desk's storage as a run would leave it.
    static func home(_ name: String, songs: Int = 5) throws -> (home: DeskHome, id: String, crate: Crate) {
        let home = DeskHome(root: try scratch(name))
        try home.prepare()
        let info = try home.shelf.make(name: "Generated")
        var tracks: [CrateTrack] = []
        let engine = CrateTrack.Engine(family: CrateFormat.EngineFamily.deckie, version: "0.1", platform: "test", fidelity: 1,
                                       models: [], decoder: .init(name: "test"))
        for i in 0..<songs {
            let a = ListenSongs.song(seed: UInt64(700 + i), seconds: 40, rate: rate)
            var t = CrateTrack(id: "song\(i)", file: .init(name: "Song \(i).wav", rel: "Song \(i).wav", bytes: 1, sha1Head: nil, durationS: 40),
                               ident: .init(title: "Song \(i)", artist: "Generated"),
                               analysis: .init(engine: "test", analysedAt: "2026-11-20T00:00:00Z", device: "test", secs: nil, level: 1),
                               engine: engine)
            t.grid = .init(source: "test", confidence: 1, bpm: 120 + Double(i), firstDownbeatS: 0, nBars: 20, fitMadMs: 0,
                           bpmIn: 120, bpmOut: 120, inTrusted: true, outTrusted: true)
            t.key = .init(source: "test", confidence: 1, camelot: "8A", key: "A", scale: "minor", votes: [:], changes: nil)
            t.fingerprint = CrateTrack.Fingerprint(Landmarks(mono: a, sampleRate: rate), madeBy: "test", madeAt: "2026-11-20T00:00:00Z")
            tracks.append(t)
        }
        let crate = Crate(manifest: CrateManifest(crateId: info.id, name: "Generated", createdAt: "2026-11-20T00:00:00Z",
                                                  devicesSeen: ["test"]), tracks: tracks)
        try CrateWriter.write(crate, to: home.shelf.package(info.id))
        return (home, info.id, try CrateReader.read(from: home.shelf.package(info.id)))
    }

    static func sound(song: Int, from: Double, seconds: Double, rate: Int = 48000, stereo: Bool = true) -> [Float] {
        let mono = ListenSongs.excerpt(ListenSongs.song(seed: UInt64(700 + song), seconds: 40, rate: rate), rate: rate, from: from, seconds: seconds)
        return stereo ? ListenSongs.stereo(mono) : mono
    }

    final class Events: @unchecked Sendable {
        let lock = NSLock()
        var all: [DeskBooth.Event] = []
        func add(_ e: DeskBooth.Event) { lock.lock(); all.append(e); lock.unlock() }
        var states: [DeskBooth.Status] { lock.lock(); defer { lock.unlock() }; return all.compactMap { if case let .status(s) = $0 { return s }; return nil } }
        var heard: [DeskBooth.Heard] { lock.lock(); defer { lock.unlock() }; return all.compactMap { if case let .heard(h) = $0 { return h }; return nil } }
        var levels: Int { lock.lock(); defer { lock.unlock() }; return all.filter { if case .level = $0 { return true }; return false }.count }
    }

    @Test func theModeBuildsTheIndexOnceThenHearsTheSongAndStopsCleanly() throws {
        let (home, id, crate) = try Self.home("booth")
        let url = home.shelf.file(DeskBooth.indexFile, of: id)
        for round in 0..<2 {
            let events = Events()
            let source = SampleSource(samples: Self.sound(song: 2, from: 12, seconds: 8), format: SoundFormat(rate: 48000, channels: 2))
            let booth = DeskBooth(crate: crate, indexAt: url, source: source, out: events.add)
            booth.start()
            booth.waitUntilStarted()
            source.waitUntilPlayed()
            booth.finishReading()
            let states = events.states
            #expect(states.first?.state == "starting")
            let percents = states.filter { $0.state == "index" }.compactMap(\.percent)
            #expect(percents.first == 0 && percents.last == 100 && percents == percents.sorted())
            let on = try #require(states.first { $0.state == "listening" })
            #expect(on.indexKept == (round == 1), "made the first time, opened as kept the second")
            #expect(on.rate == 48000 && on.channels == 2 && on.songs == 5)
            let heard = events.heard
            #expect(!heard.isEmpty)
            #expect(heard.allSatisfy { $0.id == "song2" && $0.title == "Song 2" && $0.artist == "Generated" && $0.bpm == 122 && $0.camelot == "8A" })
            #expect(abs((heard.last?.place ?? 0) - 20) < 0.6)
            #expect(events.levels >= 35)
            booth.stop()
            #expect(events.states.last?.state == "stopped")
            let after = events.all.count
            booth.stop()
            Thread.sleep(forTimeInterval: 0.2)
            #expect(events.all.count == after, "nothing after stop")
        }
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    @Test func silenceIsNothingHeardAndAnInputGoingAwayIsAPlainError() throws {
        let (home, id, crate) = try Self.home("booth-gone", songs: 3)
        let quiet = Events()
        let silence = SampleSource(samples: [Float](repeating: 0, count: 48000 * 5), format: SoundFormat(rate: 48000, channels: 1))
        let one = DeskBooth(crate: crate, indexAt: home.shelf.file(DeskBooth.indexFile, of: id), source: silence, out: quiet.add)
        one.start(); one.waitUntilStarted(); silence.waitUntilPlayed(); one.finishReading()
        #expect(quiet.states.last?.state == "nothingHeard")
        #expect(quiet.heard.isEmpty)
        one.stop()

        let events = Events()
        let source = SampleSource(samples: [Float](repeating: 0.01, count: 4800), format: SoundFormat(rate: 48000, channels: 1),
                                  endsWith: CaptureError("gone", "unplugged"))
        let booth = DeskBooth(crate: crate, indexAt: home.shelf.file(DeskBooth.indexFile, of: id), source: source, out: events.add)
        booth.start(); booth.waitUntilStarted(); source.waitUntilPlayed()
        Thread.sleep(forTimeInterval: 0.3)
        #expect(events.states.last?.state == "error" && events.states.last?.error?.code == "gone")
        booth.stop()
    }

    @Test func anInputThatCannotOpenIsAPlainError() throws {
        let (home, id, crate) = try Self.home("booth-refused", songs: 2)
        let events = Events()
        let source = SampleSource(samples: [], format: SoundFormat(rate: 48000, channels: 1), failsToStart: CaptureError("notAllowed", "denied"))
        let booth = DeskBooth(crate: crate, indexAt: home.shelf.file(DeskBooth.indexFile, of: id), source: source, out: events.add)
        booth.start(); booth.waitUntilStarted()
        #expect(events.states.last?.state == "error" && events.states.last?.error?.code == "notAllowed")
        booth.stop()
    }

    // MARK: the messages

    @Test func theProtocolListsInputsListensSaysWhatItHearsAndStops() throws {
        let (home, id, _) = try Self.home("booth-protocol", songs: 4)
        let out = Lines()
        let p = DeskProtocol(home: home, output: out.add, makeRun: AddMusicTests.noRun, analysisCheck: {})
        let sound = Self.sound(song: 1, from: 5, seconds: 7, rate: 44100, stereo: false)
        p.makeSoundSource = { name in SampleSource(name: name ?? "Stand-in", samples: sound, format: SoundFormat(rate: 44100, channels: 1)) }
        p.start()
        #expect(out.wait { ($0["event"] as? String) == "state" } != nil)

        p.handle(line: #"{"id": 1, "type": "booth.inputs"}"#)
        let inputs = try #require(out.wait { ($0["re"] as? Int) == 1 })
        // The real inputs of this computer (listing opens none), or a plain no_sound on a machine with no sound system.
        if inputs["ok"] as? Bool == true {
            #expect(inputs["inputs"] is [[String: Any]] && inputs["system"] is String)
        } else {
            #expect((inputs["error"] as? [String: Any])?["code"] as? String == "no_sound")
        }

        p.handle(line: #"{"id": 2, "type": "booth.listen", "input": "Stand-in", "crate": "\#(id)"}"#)
        let listen = try #require(out.wait { ($0["re"] as? Int) == 2 })
        #expect(listen["ok"] as? Bool == true && listen["crate"] as? String == id && (listen["songs"] as? NSNumber)?.intValue == 4)
        let heard = try #require(out.wait(seconds: 30) { ($0["event"] as? String) == "booth.heard" })
        let song = try #require(heard["song"] as? [String: Any])
        #expect(song["id"] as? String == "song1" && song["title"] as? String == "Song 1" && song["artist"] as? String == "Generated")
        #expect((song["bpm"] as? NSNumber)?.doubleValue == 121 && song["camelot"] as? String == "8A" && song["key"] as? String == "A")
        #expect(heard["place"] is NSNumber && heard["confidence"] is NSNumber && heard["reading"] is String)
        let level = try #require(out.wait { ($0["event"] as? String) == "booth.level" })
        #expect(level["meter"] is NSNumber && level["rmsDb"] is NSNumber && level["peakDb"] is NSNumber && level["silent"] as? Bool == false)
        let states = out.all.filter { ($0["event"] as? String) == "booth.state" }
        #expect(states.first?["state"] as? String == "starting")
        #expect(states.contains { $0["state"] as? String == "index" && ($0["percent"] as? NSNumber)?.intValue == 100 })
        let on = try #require(states.first { $0["state"] as? String == "listening" })
        #expect(on["input"] as? String == "Stand-in" && (on["rate"] as? NSNumber)?.intValue == 44100 && on["crate"] as? String == id)

        p.handle(line: #"{"id": 3, "type": "booth.stop"}"#)
        #expect(out.wait { ($0["re"] as? Int) == 3 }?["ok"] as? Bool == true)
        #expect(out.wait { ($0["event"] as? String) == "booth.state" && $0["state"] as? String == "stopped" } != nil)
        // Stop again, and a request with no crate showing.
        p.handle(line: #"{"id": 4, "type": "booth.stop"}"#)
        #expect(out.wait { ($0["re"] as? Int) == 4 }?["ok"] as? Bool == true)
        p.handle(line: #"{"id": 5, "type": "crate.new"}"#)
        p.handle(line: #"{"id": 6, "type": "booth.listen"}"#)
        #expect(((out.wait { ($0["re"] as? Int) == 6 })?["error"] as? [String: Any])?["code"] as? String == "no_crate")
    }

    @Test func listeningStopsWhenTheCrateChangesAndIsTwiceStartable() throws {
        let (home, _, _) = try Self.home("booth-twice", songs: 3)
        let out = Lines()
        let p = DeskProtocol(home: home, output: out.add, makeRun: AddMusicTests.noRun, analysisCheck: {})
        let sound = [Float](repeating: 0.01, count: 48000 * 30)
        p.makeSoundSource = { _ in SampleSource(samples: sound, format: SoundFormat(rate: 48000, channels: 1), pace: 1) }
        p.start()
        for k in 0..<2 {
            p.handle(line: #"{"id": \#(10 + k), "type": "booth.listen"}"#)
            #expect(out.wait { ($0["re"] as? Int) == 10 + k }?["ok"] as? Bool == true)
            #expect(out.wait(seconds: 20) { ($0["event"] as? String) == "booth.state" && $0["state"] as? String == "listening" && $0["indexKept"] as? Bool == (k == 1) } != nil)
        }
        // A second listen stopped the first: one stop each, and the crate going away stops the second.
        p.handle(line: #"{"id": 20, "type": "crate.new"}"#)
        Thread.sleep(forTimeInterval: 0.3)
        let stops = out.all.filter { ($0["event"] as? String) == "booth.state" && $0["state"] as? String == "stopped" }
        #expect(stops.count == 2)
        let n = out.all.count
        Thread.sleep(forTimeInterval: 0.5)
        #expect(!out.all.dropFirst(n).contains { ($0["event"] as? String)?.hasPrefix("booth.") == true }, "nothing heard after it stopped")
    }
}
