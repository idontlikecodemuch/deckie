import Foundation
import Testing
import DeckieCrate
import DeckieRecognition
import DeckieCapture
import DeckieTestSupport
@testable import DeckieDesk

/// Listening inside Desk (research booth-in-desk, step 1): the index made and kept per crate, a stand-in input heard
/// with the shared listener, and the `booth.*` messages. No real input is listed or opened: the system's sound is a
/// stand-in. Every wait has an end and each test a time limit, so a stuck test fails on its own.
@Suite(.serialized, .timeLimit(.minutes(2))) struct BoothTests {
    static let rate = 44100
    /// The longest the index and a stand-in's few seconds of sound take here.
    static let started = 60.0

    /// A crate of generated songs with fingerprints, kept in a desk's storage as a run would leave it.
    /// `scored`: each song also has what the picks' scoring needs (mix windows, loudness, a style vector).
    /// `waves`: each song also has its per-bar loudness, so the song shown carries its wave (step 3).
    static func home(_ name: String, songs: Int = 5, scored: Bool = false, waves: Bool = false) throws -> (home: DeskHome, id: String, crate: Crate) {
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
            if scored {
                t.mixIn = .init(startBar: 1, endBar: 5, vocalFreeBars: 4)
                t.mixOut = .init(startBar: 16, endBar: 21, vocalFreeBars: 4)
                t.loudness = .init(source: "test", confidence: nil, integratedLufs: -9, lra: 4, truePeakDb: -0.5)
                t.style = .init(model: "test", values: (0..<16).map { sin(Double($0 + i)) })
            }
            if waves { t.bars = BarSeries([BarSeries.lufs: (0..<20).map { -14 + 4 * sin(Double($0) / 3 + Double(i)) }]) }
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
            try #require(booth.waitUntilStarted(within: Self.started))
            try #require(source.waitUntilPlayed(within: Self.started))
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
        // Shorter than DeskBooth.noSoundAfter: a pause, not an input giving no sound (that is the test below).
        let silence = SampleSource(samples: [Float](repeating: 0, count: 48000 * 4), format: SoundFormat(rate: 48000, channels: 1))
        let one = DeskBooth(crate: crate, indexAt: home.shelf.file(DeskBooth.indexFile, of: id), source: silence, out: quiet.add)
        one.start()
        try #require(one.waitUntilStarted(within: Self.started) && silence.waitUntilPlayed(within: Self.started))
        one.finishReading()
        #expect(quiet.states.last?.state == "nothingHeard")
        #expect(quiet.heard.isEmpty)
        one.stop()

        let events = Events()
        let source = SampleSource(samples: [Float](repeating: 0.01, count: 4800), format: SoundFormat(rate: 48000, channels: 1),
                                  endsWith: CaptureError("gone", "unplugged"))
        let booth = DeskBooth(crate: crate, indexAt: home.shelf.file(DeskBooth.indexFile, of: id), source: source, out: events.add)
        booth.start()
        try #require(booth.waitUntilStarted(within: Self.started) && source.waitUntilPlayed(within: Self.started))
        Thread.sleep(forTimeInterval: 0.3)
        #expect(events.states.last?.state == "error" && events.states.last?.error?.code == "gone")
        booth.stop()
    }

    /// The Windows pass, Nov 21, 2026: a virtual machine's microphone gave pure silence, and the mode said "Nothing
    /// heard yet from" the crate, as if the crate were at fault. An input that gives no sound, or almost none, for
    /// `noSoundAfter` seconds is `noSound`; sound arriving is never `noSound`; and sound coming back is `listening`.
    @Test func anInputGivingNoSoundIsSaidApartFromNothingHeard() throws {
        let (home, id, crate) = try Self.home("booth-no-sound", songs: 3)
        let index = home.shelf.file(DeskBooth.indexFile, of: id)
        let rate = 48000
        func heard(_ samples: [Float]) throws -> Events {
            let events = Events()
            let source = SampleSource(samples: samples, format: SoundFormat(rate: rate, channels: 1))
            let booth = DeskBooth(crate: crate, indexAt: index, source: source, out: events.add)
            booth.start()
            try #require(booth.waitUntilStarted(within: Self.started) && source.waitUntilPlayed(within: Self.started))
            booth.finishReading()
            booth.stop()
            return events
        }
        let long = Int(DeskBooth.noSoundAfter + 3) * rate
        // Digital silence, and a hiss at about -80 dB (under the floor; a fixed pattern, no randomness).
        var seed: UInt32 = 1
        let hiss = (0..<long).map { _ -> Float in seed = seed &* 1_664_525 &+ 1_013_904_223; return (Float(seed >> 8) / Float(1 << 24) - 0.5) * 0.0002 }
        for (name, samples) in [("silence", [Float](repeating: 0, count: long)), ("hiss", hiss)] {
            let states = try heard(samples).states.map(\.state)
            #expect(states.contains("noSound"), "\(name): \(states)")
            #expect(states.dropLast().last == "noSound", "\(name): \(states)")   // the last before stop
        }
        // Music, and a quiet song (40 dB down) for as long: never noSound, and the song is named.
        let song = Self.sound(song: 1, from: 5, seconds: DeskBooth.noSoundAfter + 3, rate: rate, stereo: false)
        for (name, samples) in [("music", song), ("quiet music", song.map { $0 * 0.01 })] {
            let events = try heard(samples)
            #expect(!events.states.map(\.state).contains("noSound"), "\(name)")
            #expect(events.heard.contains { $0.id == "song1" }, "\(name)")
        }
        // No sound, then music: noSound, then back to listening by itself, and the song named.
        let both = try heard([Float](repeating: 0, count: long) + song)
        let states = both.states.map(\.state)
        let firstNoSound = try #require(states.firstIndex(of: "noSound"), "\(states)")
        #expect(states[firstNoSound...].contains("listening") && states.dropLast().last == "listening", "\(states)")
        #expect(both.heard.contains { $0.id == "song1" })

        // Sound that is no song of the crate (a loud hiss): "nothing heard yet" at first; after a song was named, and
        // the music then gives way to it, "nothing playing right now", never "yet" again.
        seed = 7
        let other = (0..<(12 * rate)).map { _ -> Float in seed = seed &* 1_664_525 &+ 1_013_904_223; return (Float(seed >> 8) / Float(1 << 24) - 0.5) * 0.2 }
        let first = try heard(other).states.map(\.state)
        #expect(first.contains("nothingHeard") && !first.contains("nothingNow") && !first.contains("noSound"), "\(first)")
        let after = try heard(song + other)
        let afterStates = after.states.map(\.state)
        let named = try #require(afterStates.firstIndex(of: "listening"), "\(afterStates)")
        #expect(after.heard.contains { $0.id == "song1" })
        #expect(afterStates.dropLast().last == "nothingNow" && !afterStates[named...].contains("nothingHeard"), "\(afterStates)")
        #expect(DeskWords.text("booth.state.nothingNow", ["crate": "My crate"]) == "Listening. Nothing from My crate is playing right now.")
    }

    /// An input that opens and then gives no samples at all (no levels to measure): `noSound` by the clock.
    @Test func anInputGivingNoSamplesAtAllIsNoSound() throws {
        let (home, id, crate) = try Self.home("booth-no-samples", songs: 2)
        let events = Events()
        let source = SampleSource(samples: [], format: SoundFormat(rate: 48000, channels: 1))
        let booth = DeskBooth(crate: crate, indexAt: home.shelf.file(DeskBooth.indexFile, of: id), source: source, out: events.add)
        booth.start()
        try #require(booth.waitUntilStarted(within: Self.started))
        let end = Date().addingTimeInterval(DeskBooth.noSoundAfter + 5)
        while Date() < end && events.states.last?.state != "noSound" { Thread.sleep(forTimeInterval: 0.1) }
        #expect(events.states.last?.state == "noSound", "\(events.states.map(\.state))")
        booth.stop()
        #expect(events.states.last?.state == "stopped")
    }

    @Test func anInputThatCannotOpenIsAPlainError() throws {
        let (home, id, crate) = try Self.home("booth-refused", songs: 2)
        let events = Events()
        let source = SampleSource(samples: [], format: SoundFormat(rate: 48000, channels: 1), failsToStart: CaptureError("notAllowed", "denied"))
        let booth = DeskBooth(crate: crate, indexAt: home.shelf.file(DeskBooth.indexFile, of: id), source: source, out: events.add)
        booth.start()
        try #require(booth.waitUntilStarted(within: Self.started))
        #expect(events.states.last?.state == "error" && events.states.last?.error?.code == "notAllowed")
        booth.stop()
    }

    // MARK: the messages

    /// Step 2 (D42): the song shown is the shared switching rule's, and its picks come with it. One song, then a hard
    /// cut to another: the rule shows the first, then the second once its wait is over; the picks are for the song on
    /// screen, never the song itself, and the song before is left out of the second's. When listening stops the
    /// listener's times line is said once and kept beside the index.
    @Test func theSongShownIsTheSharedRulesAndItsPicksComeWithIt() throws {
        let (home, id, crate) = try Self.home("booth-rule", songs: 5, scored: true)
        let index = home.shelf.file(DeskBooth.indexFile, of: id)
        let events = Events()
        let sound = Self.sound(song: 2, from: 5, seconds: 12) + Self.sound(song: 4, from: 3, seconds: 14)
        let source = SampleSource(samples: sound, format: SoundFormat(rate: 48000, channels: 2))
        let booth = DeskBooth(crate: crate, indexAt: index, source: source, shuffle: 0, out: events.add)
        booth.start()
        try #require(booth.waitUntilStarted(within: Self.started) && source.waitUntilPlayed(within: Self.started))
        booth.finishReading()
        booth.stop()
        let all = events.all
        let playing = all.compactMap { if case let .playing(p) = $0 { return p }; return nil }
        let picks = all.compactMap { if case let .picks(p) = $0 { return p }; return nil }
        let shownIds = playing.compactMap { $0.song?.id }
        #expect(shownIds.first == "song2")
        #expect(shownIds.last == "song4")
        // Shown in that order, each once: no flicker back.
        var order: [String] = []
        for s in shownIds where order.last != s { order.append(s) }
        #expect(order == ["song2", "song4"], "\(order)")
        #expect(playing.filter(\.newSong).count == 2)
        #expect(playing.last?.song?.title == "Song 4" && playing.last?.song?.bpm == 124)
        let first = try #require(picks.first { $0.forId == "song2" })
        let second = try #require(picks.last { $0.forId == "song4" })
        #expect(!first.picks.isEmpty && !first.picks.contains { $0.id == "song2" })
        #expect(!second.picks.isEmpty && !second.picks.contains { $0.id == "song4" || $0.id == "song2" })
        #expect(first.shuffle == 0 && first.shortlist == min(10, 4))
        // The iPad's words for each pick.
        for p in second.picks {
            #expect(p.bpmLine.contains("BPM") && !p.moveLine.isEmpty && p.keys.contains("→") && p.key == "8A")
        }
        let times = all.compactMap { if case let .times(t) = $0 { return t }; return nil }
        #expect(times.count == 1 && times.first?.hasPrefix("listener: ") == true, "\(times)")
        let kept = try String(contentsOf: index.deletingLastPathComponent().appendingPathComponent(DeskBooth.timesFile), encoding: .utf8)
        #expect(kept.contains(times.first ?? "-"))
    }

    /// Step 3 (the Booth screen): the Shuffle dial moved while listening rolls the picks for the song on screen again,
    /// at once, with the new dial (the iPad rolls them when the dial is let go); the dial is held to 0...1 and a value
    /// that is not a number leaves it as it was. The song shown carries its wave and bars from the crate.
    @Test func theShuffleDialMovedWhileListeningRollsThePicksAgain() throws {
        let (home, id, crate) = try Self.home("booth-shuffle", songs: 5, scored: true, waves: true)
        let events = Events()
        let source = SampleSource(samples: Self.sound(song: 2, from: 5, seconds: 12), format: SoundFormat(rate: 48000, channels: 2))
        let booth = DeskBooth(crate: crate, indexAt: home.shelf.file(DeskBooth.indexFile, of: id), source: source, shuffle: 0,
                              out: events.add)
        // Before listening starts the dial is only kept, for the first roll.
        #expect(booth.setShuffle(0.25) == 0.25 && booth.shuffleNow == 0.25)
        booth.start()
        try #require(booth.waitUntilStarted(within: Self.started) && source.waitUntilPlayed(within: Self.started))
        booth.finishReading()
        func picks() -> [DeskBooth.Picks] { events.all.compactMap { if case let .picks(p) = $0 { return p }; return nil } }
        let first = try #require(picks().last)
        #expect(first.forId == "song2" && first.shuffle == 0.25)
        let before = picks().count
        #expect(booth.setShuffle(1) == 1)
        let rolled = picks()
        #expect(rolled.count == before + 1, "one roll, said at once")
        let again = try #require(rolled.last)
        #expect(again.forId == "song2" && again.shuffle == 1 && again.shortlist == first.shortlist)
        // The same shortlist, in the dial's order; nothing beyond it, so More holds none of it.
        #expect(Set(again.picks.map(\.id)) == Set(first.picks.map(\.id)) && again.morePicks.isEmpty)
        #expect(again.picks.allSatisfy { !$0.keysClash }, "every song is in 8A")
        #expect(booth.setShuffle(7) == 1 && booth.setShuffle(-1) == 0 && booth.setShuffle(.nan) == 0)
        // The song shown carries the crate's wave (64 values, 0 to 99) and its bars.
        let shown = try #require(events.all.compactMap { e -> DeskBooth.Heard? in if case let .playing(p) = e { return p.song }; return nil }.last)
        let wave = try #require(shown.wave)
        #expect(wave.count == RunSong.waveLength && wave.allSatisfy { (0...99).contains($0) } && Set(wave).count > 1)
        #expect(shown.bars == 20)
        booth.stop()
        let after = picks().count
        booth.setShuffle(0.5)
        #expect(picks().count == after, "nothing rolled after stop")
    }

    /// Step 3's protocol addition: `booth.shuffle` while listening rolls the picks again (`booth.picks` with the new
    /// dial); not listening, it is answered and nothing is rolled; not a number is a bad request. The picks carry
    /// `keysClash` and `morePicks`, the song shown its `wave` and `bars`.
    @Test func theProtocolMovesTheShuffleDialWhileListening() throws {
        let (home, id, _) = try Self.home("booth-protocol-shuffle", songs: 5, scored: true, waves: true)
        let out = Lines()
        let p = DeskProtocol(home: home, output: out.add, makeRun: AddMusicTests.noRun, analysisCheck: {})
        let sound = Self.sound(song: 3, from: 5, seconds: 9, rate: 44100, stereo: false)
        p.makeSoundSource = { name in SampleSource(name: name ?? "Stand-in", samples: sound, format: SoundFormat(rate: 44100, channels: 1)) }
        p.listSoundInputs = { SoundInputs.Listed(inputs: [SoundInput(name: "Stand-in", isDefault: true)], system: "stand-in") }
        p.start()
        #expect(out.wait { ($0["event"] as? String) == "state" } != nil)

        p.handle(line: #"{"id": 1, "type": "booth.shuffle", "shuffle": 0.3}"#)
        let idle = try #require(out.wait { ($0["re"] as? Int) == 1 })
        #expect(idle["ok"] as? Bool == true && idle["listening"] as? Bool == false && (idle["shuffle"] as? NSNumber)?.doubleValue == 0.3)
        p.handle(line: #"{"id": 2, "type": "booth.shuffle", "shuffle": "lots"}"#)
        #expect(((out.wait { ($0["re"] as? Int) == 2 })?["error"] as? [String: Any])?["code"] as? String == "bad_request")

        p.handle(line: #"{"id": 3, "type": "booth.listen", "input": "Stand-in", "crate": "\#(id)", "shuffle": 0}"#)
        #expect(out.wait { ($0["re"] as? Int) == 3 }?["ok"] as? Bool == true)
        let first = try #require(out.wait(seconds: 30) { ($0["event"] as? String) == "booth.picks" && $0["for"] as? String == "song3" })
        #expect((first["shuffle"] as? NSNumber)?.doubleValue == 0 && first["morePicks"] is [[String: Any]])
        let firstPicks = try #require(first["picks"] as? [[String: Any]])
        #expect(!firstPicks.isEmpty && firstPicks.allSatisfy { $0["keysClash"] as? Bool == false })
        let playing = try #require(out.all.last { ($0["event"] as? String) == "booth.playing" && $0["song"] is [String: Any] })
        let song = try #require(playing["song"] as? [String: Any])
        #expect((song["wave"] as? [Any])?.count == RunSong.waveLength && (song["bars"] as? NSNumber)?.intValue == 20)

        p.handle(line: #"{"id": 4, "type": "booth.shuffle", "shuffle": 1}"#)
        let moved = try #require(out.wait { ($0["re"] as? Int) == 4 })
        #expect(moved["ok"] as? Bool == true && moved["listening"] as? Bool == true && (moved["shuffle"] as? NSNumber)?.doubleValue == 1)
        let rolled = try #require(out.wait { ($0["event"] as? String) == "booth.picks" && ($0["shuffle"] as? NSNumber)?.doubleValue == 1 })
        #expect(rolled["for"] as? String == "song3")
        #expect(Set(((rolled["picks"] as? [[String: Any]]) ?? []).compactMap { $0["id"] as? String })
                == Set(firstPicks.compactMap { $0["id"] as? String }))
        p.handle(line: #"{"id": 5, "type": "booth.stop"}"#)
        #expect(out.wait { ($0["re"] as? Int) == 5 }?["ok"] as? Bool == true)
    }

    @Test func theProtocolListsInputsListensSaysWhatItHearsAndStops() throws {
        let (home, id, _) = try Self.home("booth-protocol", songs: 4)
        let out = Lines()
        let p = DeskProtocol(home: home, output: out.add, makeRun: AddMusicTests.noRun, analysisCheck: {})
        let sound = Self.sound(song: 1, from: 5, seconds: 7, rate: 44100, stereo: false)
        p.makeSoundSource = { name in SampleSource(name: name ?? "Stand-in", samples: sound, format: SoundFormat(rate: 44100, channels: 1)) }
        p.listSoundInputs = { SoundInputs.Listed(inputs: [SoundInput(name: "Stand-in", isDefault: true), SoundInput(name: "Line In", isDefault: false)],
                                                 system: "stand-in") }
        p.start()
        #expect(out.wait { ($0["event"] as? String) == "state" } != nil)

        p.handle(line: #"{"id": 1, "type": "booth.inputs"}"#)
        let inputs = try #require(out.wait { ($0["re"] as? Int) == 1 })
        #expect(inputs["ok"] as? Bool == true && inputs["system"] as? String == "stand-in")
        let listed = try #require(inputs["inputs"] as? [[String: Any]])
        #expect(listed.map { $0["name"] as? String } == ["Stand-in", "Line In"] && listed.map { $0["default"] as? Bool } == [true, false])

        p.handle(line: #"{"id": 2, "type": "booth.listen", "input": "Stand-in", "crate": "\#(id)"}"#)
        let listen = try #require(out.wait { ($0["re"] as? Int) == 2 })
        #expect(listen["ok"] as? Bool == true && listen["crate"] as? String == id && (listen["songs"] as? NSNumber)?.intValue == 4)
        let heard = try #require(out.wait(seconds: 30) { ($0["event"] as? String) == "booth.heard" })
        let song = try #require(heard["song"] as? [String: Any])
        #expect(song["id"] as? String == "song1" && song["title"] as? String == "Song 1" && song["artist"] as? String == "Generated")
        #expect((song["bpm"] as? NSNumber)?.doubleValue == 121 && song["camelot"] as? String == "8A" && song["key"] as? String == "A")
        #expect(heard["place"] is NSNumber && heard["confidence"] is NSNumber && heard["reading"] is String)
        // Step 2: what the shared rule shows, and its picks (none: these songs have nothing the scoring reads).
        let playing = try #require(out.wait(seconds: 30) { ($0["event"] as? String) == "booth.playing" && $0["song"] is [String: Any] })
        #expect((playing["song"] as? [String: Any])?["id"] as? String == "song1" && playing["crate"] as? String == id)
        #expect(playing["notHeard"] as? Bool == false && playing["paused"] as? Bool == false && playing["pitch"] is NSNumber)
        let picks = try #require(out.wait(seconds: 30) { ($0["event"] as? String) == "booth.picks" })
        #expect(picks["for"] as? String == "song1" && (picks["picks"] as? [[String: Any]])?.isEmpty == true && picks["shortlist"] is NSNumber)
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

    /// A machine whose sound system does not answer (no PulseAudio, a stopped Windows Audio service): the inputs are a
    /// plain no_sound and listening a plain noSystem, each at the time limit, and the engine answers other requests
    /// meanwhile; the input that opens late is closed again at once.
    @Test func aSoundSystemThatDoesNotAnswerIsAPlainErrorInTimeAndHoldsNothingUp() throws {
        let (home, id, _) = try Self.home("booth-stuck", songs: 2)
        let out = Lines()
        let p = DeskProtocol(home: home, output: out.add, makeRun: AddMusicTests.noRun, analysisCheck: {})
        p.soundWait = 0.3
        p.listSoundInputs = { Thread.sleep(forTimeInterval: 3); return SoundInputs.Listed(inputs: [], system: "stand-in") }
        let late = SampleSource(samples: [Float](repeating: 0.1, count: 48000 * 10), format: SoundFormat(rate: 48000, channels: 1),
                                pace: 1, opensAfter: 1.5)
        p.makeSoundSource = { [soundWait = p.soundWait] _ in BoundedSource(late, within: soundWait) }
        p.start()
        #expect(out.wait { ($0["event"] as? String) == "state" } != nil)

        let t0 = Date()
        p.handle(line: #"{"id": 1, "type": "booth.inputs"}"#)
        p.handle(line: #"{"id": 2, "type": "booth.stop"}"#)
        #expect(Date().timeIntervalSince(t0) < 0.25, "the loop does not wait on the system's sound")
        #expect(out.wait(seconds: 1) { ($0["re"] as? Int) == 2 }?["ok"] as? Bool == true)
        let inputs = try #require(out.wait(seconds: 2) { ($0["re"] as? Int) == 1 })
        #expect(Date().timeIntervalSince(t0) < 2, "given up on at the limit, not when the system answered")
        #expect(inputs["ok"] as? Bool == false && (inputs["error"] as? [String: Any])?["code"] as? String == "no_sound"
                && (inputs["error"] as? [String: Any])?["detail"] as? String == "noSystem")

        p.handle(line: #"{"id": 3, "type": "booth.listen", "crate": "\#(id)"}"#)
        #expect(out.wait { ($0["re"] as? Int) == 3 }?["ok"] as? Bool == true)
        let failed = try #require(out.wait(seconds: 30) { ($0["event"] as? String) == "booth.state" && $0["state"] as? String == "error" })
        #expect((failed["error"] as? [String: Any])?["code"] as? String == "noSystem")
        #expect(!out.all.contains { ($0["event"] as? String) == "booth.state" && $0["state"] as? String == "listening" })
        // The input that opens after all is stopped again: it does not play its ten seconds.
        Thread.sleep(forTimeInterval: 1.6)
        let delivered = late.delivered
        Thread.sleep(forTimeInterval: 0.5)
        #expect(late.delivered == delivered && delivered < 48000)
        #expect(!out.all.contains { ($0["event"] as? String) == "booth.level" }, "nothing heard from an input given up on")
        p.handle(line: #"{"id": 4, "type": "booth.stop"}"#)
        #expect(out.wait { ($0["re"] as? Int) == 4 }?["ok"] as? Bool == true)
    }

    // MARK: the words and the look

    @Test func everyStateAndErrorHasItsWords() {
        for s in ["starting", "index", "listening", "nothingHeard", "nothingNow", "noSound", "stopped"] { #expect(DeskWords.table["booth.state." + s] != nil, "\(s)") }
        for c in ["noInput", "notAllowed", "busy", "gone", "noSystem", "noPrints", "index", "other"] {
            #expect(DeskWords.table["booth.error." + c] != nil, "\(c)")
        }
        // The mode's words sit beside Desk's and take none of their names.
        #expect(Set(DeskWords.boothTable.keys).isDisjoint(with: DeskWords.baseTable.keys))
        #expect(DeskWords.boothTable.allSatisfy { !$0.value.contains("track") && !$0.value.contains("AI") })
    }

    /// The Mac asks for the microphone with the words the app carries: the native Desk's (project.yml and the Info.plist
    /// made from it) and the test window's (desk-shell/Info-mac.plist) are DeskWords' booth.micPermission.
    @Test func theMicrophoneQuestionUsesTheWordsInTheList() {
        let words = DeskWords.text("booth.micPermission")
        #expect(VariablesTests.read("desk-app/project.yml").contains("NSMicrophoneUsageDescription: \"\(words)\""))
        for plist in ["desk-app/Desk/Info.plist", "desk-shell/Info-mac.plist"] {
            let text = VariablesTests.read(plist)
            #expect(text.contains("<key>NSMicrophoneUsageDescription</key>\n\t<string>\(words)</string>"), "\(plist)")
        }
    }

    @Test func theModesStyleSheetHoldsNoValuesAndReadsOnlyDesksVariables() {
        let css = VariablesTests.read("desk-web/booth.css"), desk = VariablesTests.read("desk-web/desk.css")
        #expect(!css.isEmpty)
        let rules = css.replacingOccurrences(of: #"/\*[\s\S]*?\*/"#, with: "", options: .regularExpression)
        let values = #"(#[0-9a-fA-F]{3,8}\b|rgba?\(|hsla?\(|(?<![\w.-])-?\d*\.?\d+(?:px|em|rem|vh|vw|ms|s|fr)\b)"#
        var found: [String] = []
        for line in rules.split(separator: "\n") {
            let l = String(line).replacingOccurrences(of: #"var\([^)]*\)"#, with: "", options: .regularExpression)
            found += VariablesTests.matches(values, l).map { "\($0) in \(line)" }
        }
        #expect(found.isEmpty, "\(found.joined(separator: "\n"))")
        #expect(VariablesTests.matches(#"(?<![\w-])content:"#, rules).isEmpty)
        let defined = Set(VariablesTests.matches(#"(--[\w-]+)\s*:"#, desk))
        let used = Set(VariablesTests.matches(#"var\((--[\w-]+)\)"#, css))
        #expect(!used.isEmpty && used.subtracting(defined).isEmpty, "\(used.subtracting(defined).sorted())")
        // The pages name both files, the script before desk.js (which opens the mode).
        let html = VariablesTests.read("desk-web/index.html")
        #expect(html.contains(#"href="booth.css""#))
        let b = html.range(of: #"src="booth.js""#), d = html.range(of: #"src="desk.js""#)
        #expect(b != nil && d != nil && b!.lowerBound < d!.lowerBound)
    }
}
