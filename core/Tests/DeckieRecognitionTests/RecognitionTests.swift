import Foundation
import Testing
import DeckieCore
import DeckieRecognition

// The trial recogniser on generated songs: every song here is synthesised in the test; no music file is read.
// A "song" is a seeded run of notes (each a few harmonics with a sharp start), so two seeds share nothing and one
// seed rendered at another tempo is the same song with the key held, exactly.

@Suite struct RecognitionTests {
    static let rate = 8000

    struct RNG { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

    /// `seconds` of song `seed`, with every time divided by `tempo` and every frequency multiplied by `pitch`.
    static func song(seed: UInt64, seconds: Double = 40, tempo: Double = 1, pitch: Double = 1) -> [Float] {
        var rng = RNG(s: seed)
        let n = Int(seconds / tempo * Double(rate))
        var out = [Float](repeating: 0, count: n)
        var t = 0.0
        while t < seconds {
            let f = 320 * pow(2, rng.next() * 3.2) * pitch, length = 0.15 + 0.5 * rng.next(), amp = 0.2 + 0.8 * rng.next()
            let start = Int(t / tempo * Double(rate)), count = Int(length / tempo * Double(rate))
            for i in 0..<count where start + i < n {
                let x = Double(i) / Double(rate)
                let env = exp(-3 * x * tempo) * min(1, Double(i) / 40)
                out[start + i] += Float(amp * env * (sin(2 * .pi * f * x) + 0.4 * sin(2 * .pi * 2 * f * x)))
            }
            t += 0.08 + 0.12 * rng.next()
        }
        return out
    }

    static func noise(_ n: Int, seed: UInt64, level: Float) -> [Float] {
        var rng = RNG(s: seed)
        return (0..<n).map { _ in Float(rng.next() * 2 - 1) * level }
    }

    static let index: RecognitionIndex = {
        RecognitionIndex(songs: (0..<8).map { ("song\($0)", Landmarks(mono: song(seed: UInt64(100 + $0)), sampleRate: rate)) })
    }()

    static func excerpt(_ x: [Float], from: Double, seconds: Double) -> [Float] {
        Array(x[Int(from * Double(rate))..<Int((from + seconds) * Double(rate))])
    }

    @Test func aConstellationSurvivesItsBytes() throws {
        let marks = Landmarks(mono: Self.song(seed: 5, seconds: 10), sampleRate: Self.rate)
        #expect(marks.count > 100)
        #expect(Landmarks(encoded: marks.encoded()) == marks)
        #expect(marks.encoded().count < 4 * marks.count + 12)
        #expect(Landmarks(encoded: Data([1, 2, 3])) == nil)
        // Damaged bytes are refused, never a reason to stop: a count the bytes cannot hold, and frame gaps that add
        // up past the largest frame number (a crate file's reader takes these bytes from a file it did not write).
        let head = Data("DKL2".utf8) + Data([0, 0, 0, 0])
        #expect(Landmarks(encoded: head + Data([0xFF, 0xFF, 0xFF, 0xFF, 1, 2, 3])) == nil)
        let farGap: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF, 0x0F, 0, 0]
        #expect(Landmarks(encoded: head + Data([2, 0, 0, 0] + farGap + farGap)) == nil)
        #expect(Landmarks(encoded: head + Data([1, 0, 0, 0] + farGap))?.frames == [UInt32.max])
    }

    @Test func anExcerptIsFoundWithItsPlace() throws {
        let q = Self.excerpt(Self.song(seed: 103), from: 17.3, seconds: 5)
        let found = Recogniser(index: Self.index).match(Landmarks(mono: q, sampleRate: Self.rate))
        let best = try #require(found.first)
        #expect(best.id == "song3")
        #expect(abs(best.offsetSeconds - 17.3) < 0.05)
        #expect(abs(best.speedPercent) < 0.25)
        #expect(best.score > 20)
        #expect(best.isVinyl == nil)
    }

    @Test func aTurntableSpeedIsFoundAndRead() throws {
        // Vinyl-style: time and frequency move together.
        for percent in [-16.0, -7.0, 3.0, 12.0] {
            let v = 1 + percent / 100
            let played = Self.song(seed: 105, tempo: v, pitch: v)
            let q = Self.excerpt(played, from: 10 / v, seconds: 6)
            let best = try #require(Recogniser(index: Self.index).match(Landmarks(mono: q, sampleRate: Self.rate)).first)
            #expect(best.id == "song5")
            #expect(abs(best.speedPercent - percent) < 0.15, "tempo read \(best.speedPercent) at \(percent)")
            #expect(abs((best.pitchRatio - 1) * 100 - percent) < 0.15, "pitch read \(best.pitchRatio) at \(percent)")
            #expect(abs(best.offsetSeconds - 10) < 0.1)
            #expect(best.isVinyl == true)
        }
    }

    @Test func aKeyHeldSpeedIsFoundAndRead() throws {
        // Tempo only: the key is held ("master tempo").
        for percent in [-15.0, -6.0, 4.0, 13.0] {
            let v = 1 + percent / 100
            let played = Self.song(seed: 101, tempo: v)
            let q = Self.excerpt(played, from: 20 / v, seconds: 6)
            let best = try #require(Recogniser(index: Self.index).match(Landmarks(mono: q, sampleRate: Self.rate)).first)
            #expect(best.id == "song1")
            #expect(abs(best.speedPercent - percent) < 0.15, "tempo read \(best.speedPercent) at \(percent)")
            #expect(abs(best.pitchRatio - 1) < 0.0015)
            #expect(best.isVinyl == false)
        }
    }

    @Test func noiseAndAnotherRateDoNotLoseIt() throws {
        // The excerpt at 44.1 kHz under white noise at the excerpt's own level (0 dB).
        let clean = Self.excerpt(Self.song(seed: 106), from: 8, seconds: 8)
        let rms = (clean.reduce(0) { $0 + $1 * $1 } / Float(clean.count)).squareRoot()
        let noise = Self.noise(clean.count, seed: 9, level: rms * Float(3).squareRoot())
        let q = Resampler.resample(zip(clean, noise).map { $0 + $1 }, from: Self.rate, to: 44100)
        let found = Recogniser(index: Self.index).match(Landmarks(mono: q, sampleRate: 44100))
        let best = try #require(found.first)
        #expect(best.id == "song6")
        #expect(best.score > 10)
    }

    @Test func aSongThatIsNotThereScoresLow() throws {
        let q = Self.excerpt(Self.song(seed: 999), from: 5, seconds: 8)
        let found = Recogniser(index: Self.index).match(Landmarks(mono: q, sampleRate: Self.rate))
        #expect((found.first?.score ?? 0) < 6)
        let silence = Recogniser(index: Self.index).match(Landmarks(mono: [Float](repeating: 0, count: 40000), sampleRate: Self.rate))
        #expect(silence.isEmpty)
    }

    @Test func twoSongsAtOnceAreBothFound() throws {
        let a = Self.excerpt(Self.song(seed: 102), from: 12, seconds: 8), b = Self.excerpt(Self.song(seed: 107), from: 25, seconds: 8)
        let found = Recogniser(index: Self.index).match(Landmarks(mono: zip(a, b).map { $0 + $1 }, sampleRate: Self.rate))
        #expect(Set(found.prefix(2).map(\.id)) == ["song2", "song7"])
    }

    // MARK: The index as a file, and the listener

    static func temporaryFile(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-recognition-tests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    @Test func anIndexOpenedFromItsFileAnswersAsTheOneBuilt() throws {
        let url = Self.temporaryFile("crate.dkx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Self.index.write(to: url)
        let q = Landmarks(mono: Self.excerpt(Self.song(seed: 104), from: 9, seconds: 6), sampleRate: Self.rate)
        let built = try #require(Recogniser(index: Self.index).match(q).first)
        for mapped in [true, false] {
            let opened = try RecognitionIndex(contentsOf: url, mapped: mapped)
            #expect(opened.ids == Self.index.ids)
            let again = try #require(Recogniser(index: opened).match(q).first)
            #expect(again == built)
        }
        // A file that is not an index is refused, not read.
        try Data("not an index".utf8).write(to: url)
        #expect(throws: IndexFileError.self) { try RecognitionIndex(contentsOf: url) }
    }

    /// A damaged or crafted index file whose header numbers are near the top of the range (a place and a length that
    /// would overflow when added, a number too large for an Int) is refused with the usual error, never a crash.
    @Test func anIndexFileWithHugeNumbersInItsHeaderIsRefused() throws {
        let good = Self.index.fileData()
        #expect(throws: Never.self) { try RecognitionIndex(file: good) }
        func with(_ value: UInt64, at offset: Int) -> Data {
            var d = good
            withUnsafeBytes(of: value.littleEndian) { d.replaceSubrange(offset..<(offset + 8), with: $0) }
            return d
        }
        let firstPlace = 24, firstLength = 32
        for crafted in [with(UInt64(Int.max), at: firstLength),             // place + length would overflow
                        with(UInt64(Int.max - 7), at: firstPlace),          // a place far past the end
                        with(UInt64.max, at: firstPlace),                   // too large for an Int
                        with(UInt64.max, at: firstLength),
                        with(UInt64.max, at: 8)] {                          // the timeline's length, too large
            #expect(throws: IndexFileError.self) { try RecognitionIndex(file: crafted) }
        }
    }

    @Test func theCachedIndexIsBuiltOnceAndMadeAgainWhenTheSongsChange() throws {
        let url = Self.temporaryFile("crate.dkx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let songs = (0..<3).map { (id: "song\($0)", landmarks: Landmarks(mono: Self.song(seed: UInt64(300 + $0), seconds: 20), sampleRate: Self.rate)) }
        let stamp = RecognitionIndex.stamp(of: songs.map { ($0.id, $0.landmarks.count, $0.landmarks.frameCount) })
        var builds = 0
        let first = try RecognitionIndex.cached(at: url, stamp: stamp) { builds += 1; return songs }
        let second = try RecognitionIndex.cached(at: url, stamp: stamp) { builds += 1; return songs }
        #expect(builds == 1)
        #expect(first.ids == second.ids && second.songCount == 3)
        let fewer = Array(songs.prefix(2))
        let other = RecognitionIndex.stamp(of: fewer.map { ($0.id, $0.landmarks.count, $0.landmarks.frameCount) })
        #expect(other != stamp)
        let third = try RecognitionIndex.cached(at: url, stamp: other) { builds += 1; return fewer }
        #expect(builds == 2 && third.songCount == 2)
    }

    /// Song 2 from 10 s in for 20 s, then song 6 (at +6 %, key held) from 5 s in for 20 s, fed in tenths of a second.
    static let set: [Float] = {
        let a = excerpt(song(seed: 102), from: 10, seconds: 20)
        let b = excerpt(song(seed: 106, tempo: 1.06), from: 5 / 1.06, seconds: 20)
        return a + b
    }()

    @Test func theListenerNamesFollowsAndNoticesTheNextSong() throws {
        let listener = SongListener(index: Self.index)
        var readings: [ListenReading] = []
        var at = 0
        while at < Self.set.count {
            let end = min(Self.set.count, at + Self.rate / 10)
            readings += listener.hear(Array(Self.set[at..<end]), sampleRate: Self.rate)
            at = end
        }
        #expect(readings.count == 38)                               // one a second from the third second on
        let first = try #require(readings.first)
        #expect(first.time == 3 && first.state == .named && first.id == "song2")
        // The first song: held, at the right place, at zero.
        for r in readings where r.time >= 4 && r.time <= 20 {
            #expect(r.id == "song2" && r.state == .held)
            #expect(abs((r.positionSeconds ?? 0) - (10 + r.time)) < 0.15)
            #expect(abs(r.speedPercent ?? 9) < 0.3)
        }
        // The second: named within a few seconds of starting, then at the right place, speed and key lock.
        let change = try #require(readings.first { $0.id == "song6" })
        #expect(change.time <= 26)
        for r in readings where r.time >= 30 {
            #expect(r.id == "song6")
            #expect(abs((r.positionSeconds ?? 0) - (5 + (r.time - 20) * 1.06)) < 0.2)
            #expect(abs((r.speedPercent ?? 0) - 6) < 0.3)
            #expect(r.keyLock == true)
        }
        // Sound that is no song of the crate: nothing is named.
        listener.reset()
        let none = listener.hear(Self.excerpt(Self.song(seed: 999), from: 0, seconds: 12), sampleRate: Self.rate)
        #expect(none.allSatisfy { $0.state == .nothingYet })
    }

    // MARK: The listeners compared for a quicker change of name (docs/research/faster-listening-proposals.md)

    static func readings(_ sound: [Float], _ settings: ListenSettings, index: RecognitionIndex = Self.index) -> [ListenReading] {
        let listener = SongListener(index: index, settings: settings)
        var out: [ListenReading] = []
        var at = 0
        while at < sound.count {
            let end = min(sound.count, at + Self.rate / 10)
            out += listener.hear(Array(sound[at..<end]), sampleRate: Self.rate)
            at = end
        }
        return out
    }

    /// Readings as runs: "3 named song2, 4-24 held song2, ..." (each reading's whole second, state and song).
    static func runs(_ readings: [ListenReading]) -> String {
        var out: [(from: Int, to: Int, what: String)] = []
        for r in readings {
            let t = Int(r.time.rounded()), what = "\(r.state.rawValue) \(r.id ?? "-")"
            if let last = out.last, last.what == what, last.to == t - 1 { out[out.count - 1].to = t } else { out.append((t, t, what)) }
        }
        return out.map { ($0.from == $0.to ? "\($0.from)" : "\($0.from)-\($0.to)") + " " + $0.what }.joined(separator: ", ")
    }

    /// Songs 2 and 6 in turn, 10 s each, each picking up where it left off.
    static let turns: [Float] = (0..<4).flatMap { k in excerpt(song(seed: k % 2 == 0 ? 102 : 106), from: 5 + Double(k / 2) * 10, seconds: 10) }

    @Test func theProductsListenerIsA() throws {
        // D41: the iPad app, Desk's Booth mode and deckie-listen all take the default settings, and the default is A.
        #expect(ListenSettings.Listener.product == .a)
        #expect(ListenSettings() == ListenSettings(.a))
        #expect(ListenSettings().name == "a")
        #expect(ListenSettings.Listener.allCases.filter(\.isProduct) == [.a])
        #expect(SongListener(index: Self.index).settings == ListenSettings(.a))
        #expect(BoothRecogniser(index: Self.index) { _ in }.listenerName == "a")
        // A's numbers are the ones chosen on the research branch's dev half and run once on its held-out half; the
        // rest are today's listener's.
        let a = ListenSettings(.a)
        var expected = ListenSettings(.main)
        expected.challenger = true; expected.challengeWindow = 4; expected.challengeMargin = 2; expected.searchSinceMiss = 4
        #expect(a == expected)
        #expect(ListenSettings(.main).name == "main" && ListenSettings(.fast).name == "fast" && ListenSettings(.b).name == "b")
        var changed = a; changed.challengeMargin = 3
        #expect(changed.name == "custom")
    }

    @Test func mainIsStillTheListenerBeforeD41ReadingForReading() throws {
        // Written from main at 205d35c (before A became the products' listener), its default settings on these sounds.
        #expect(!ListenSettings(.main).challenger && !ListenSettings(.main).cutWatch && ListenSettings(.main).searchSinceMiss == nil)
        #expect(Self.runs(Self.readings(Self.set, ListenSettings(.main)))
                == "3 named song2, 4-24 held song2, 25 named song6, 26-40 held song6")
        #expect(Self.runs(Self.readings(Self.turns, ListenSettings(.main)))
                == "3 named song2, 4-14 held song2, 15 named song6, 16-24 held song6, 25 named song2, 26-34 held song2, 35 named song6, 36-40 held song6")
        #expect(Self.runs(Self.readings(Self.excerpt(Self.song(seed: 104), from: 1, seconds: 38), ListenSettings(.main)))
                == "3 named song4, 4-38 held song4")
    }

    @Test func aListenerKeepsHowLongItsReadingsTook() throws {
        var t = ReadingTimes()
        #expect(t.line(listener: "a") == "listener: a, no readings")
        for ms in [12.4, 61.2, 61.9, 240.4, 30.0] { t.add(ms) }
        #expect(t.count == 5 && t.typicalMilliseconds == 61 && abs(t.slowestMilliseconds - 240.4) < 1e-9)
        #expect(abs(t.meanMilliseconds - (12.4 + 61.2 + 61.9 + 240.4 + 30) / 5) < 1e-9)
        #expect(t.line(listener: "a") == "listener: a, 5 readings, typical 61 ms, slowest 240 ms")
        var u = ReadingTimes()
        u.add(5000); u.add(3)
        t.merge(u)
        #expect(t.count == 7 && t.typicalMilliseconds == 61 && t.slowestMilliseconds == 5000)
        // The listener's own record: one entry a reading, kept through a reset.
        let listener = SongListener(index: Self.index)
        var n = 0
        var at = 0
        while at < Self.set.count {
            let end = min(Self.set.count, at + Self.rate / 10)
            n += listener.hear(Array(Self.set[at..<end]), sampleRate: Self.rate).count
            at = end
        }
        #expect(n > 30 && listener.times.count == n)
        listener.reset()
        #expect(listener.times.count == n)
        #expect(listener.timesLine.hasPrefix("listener: a, \(n) readings, typical "))
    }

    @Test(arguments: ListenSettings.Listener.allCases)
    func everyListenerNamesFollowsAndNoticesTheNextSong(_ which: ListenSettings.Listener) throws {
        let readings = Self.readings(Self.set, ListenSettings(which))
        let first = try #require(readings.first { $0.state != .nothingYet })
        #expect(first.id == "song2" && first.time <= 3)
        #expect(readings.filter { $0.time <= 20 && $0.state != .nothingYet }.allSatisfy { $0.id == "song2" })
        let change = try #require(readings.first { $0.id == "song6" })
        // The cut is at 20 s. The default names the next song by 26 s; the others are meant to be quicker.
        #expect(change.time <= (which == .main ? 26 : 24), "\(which): named at \(change.time)")
        #expect(readings.filter { $0.time >= 26 }.allSatisfy { $0.id == "song6" })
    }

    @Test(arguments: ListenSettings.Listener.allCases)
    func backAndForthEveryTenSecondsIsFollowed(_ which: ListenSettings.Listener) throws {
        // Songs 2 and 6 in turn, 10 s each, each picking up where it left off, as a DJ cutting between two decks.
        var sound: [Float] = []
        for k in 0..<4 { sound += Self.excerpt(Self.song(seed: k % 2 == 0 ? 102 : 106), from: 5 + Double(k / 2) * 10, seconds: 10) }
        let readings = Self.readings(sound, ListenSettings(which))
        for k in 1..<4 {
            let id = k % 2 == 0 ? "song2" : "song6"
            let cut = Double(k) * 10
            let named = try #require(readings.first { $0.time > cut && $0.id == id }, "\(which): segment \(k) never named")
            #expect(named.time - cut <= (which == .main ? 7 : 5), "\(which): segment \(k) named \(named.time - cut) s after its cut")
        }
    }

    @Test(arguments: [ListenSettings.Listener.main, .a, .b, .ab])
    func aSongThatSharesAPassageIsNotNamedWhileTheFollowedSongPlays(_ which: ListenSettings.Listener) throws {
        // Song 10 holds 8 s of song 2 (from its 15th second) in its own middle, as a remix or a sample would. While song
        // 2 plays on through that passage, the listener is to keep naming song 2.
        let other = Self.song(seed: 110)
        let version = Array(other.prefix(15 * Self.rate)) + Self.excerpt(Self.song(seed: 102), from: 15, seconds: 8) + Array(other.suffix(from: 23 * Self.rate))
        let songs = (0..<8).map { ("song\($0)", Landmarks(mono: Self.song(seed: UInt64(100 + $0)), sampleRate: Self.rate)) }
            + [("song10", Landmarks(mono: version, sampleRate: Self.rate))]
        let index = RecognitionIndex(songs: songs)
        let readings = Self.readings(Self.excerpt(Self.song(seed: 102), from: 2, seconds: 36), ListenSettings(which), index: index)
        #expect(readings.filter { $0.state != .nothingYet }.allSatisfy { $0.id == "song2" },
                "\(which): \(readings.filter { $0.id != "song2" && $0.state != .nothingYet }.map { "\($0.time) \($0.id ?? "")" })")
    }

    @Test func theCutWatchDoesNotRaiseAnAlarmOnASongThatPlaysOn() throws {
        // On one song, unbroken, B is the default reading for reading.
        let sound = Self.excerpt(Self.song(seed: 104), from: 1, seconds: 38)
        let main = Self.readings(sound, ListenSettings(.main)).map { "\($0.time) \($0.state) \($0.id ?? "-")" }
        let b = Self.readings(sound, ListenSettings(.b)).map { "\($0.time) \($0.state) \($0.id ?? "-")" }
        #expect(main == b)
    }

    @Test func theBoothRecogniserTakesSoundWithoutWaitingAndReadsItInOrder() throws {
        final class Box: @unchecked Sendable { let lock = NSLock(); var readings: [ListenReading] = [] }
        let box = Box()
        let booth = BoothRecogniser(index: Self.index) { r in box.lock.lock(); box.readings.append(r); box.lock.unlock() }
        // Stereo at 44.1 kHz, as a microphone might deliver it, a quarter of a second at a time.
        let stereo = Resampler.resample(Array(Self.set.prefix(12 * Self.rate)), from: Self.rate, to: 44100).flatMap { [$0, $0] }
        var at = 0
        while at < stereo.count {
            let end = min(stereo.count, at + 2 * 11025)
            booth.feed(Array(stereo[at..<end]), channels: 2, sampleRate: 44100)
            at = end
        }
        // Feeding did not wait for the readings: when the last piece has been handed over, readings are still to come.
        box.lock.lock(); let seenWhenFed = box.readings.count; box.lock.unlock()
        booth.finish()
        #expect(seenWhenFed < box.readings.count)
        #expect(box.readings.count == 10)                           // one a second from the third second of twelve
        #expect(box.readings.map(\.time) == box.readings.map(\.time).sorted())
        #expect(box.readings.last?.id == "song2")
        #expect(booth.latest == box.readings.last)
        // Its record of how long the readings took, for the log line where listening stops.
        #expect(booth.times.count == 10)
        #expect(booth.timesLine.hasPrefix("listener: a, 10 readings, typical "))
    }

    // MARK: Songs that hold the same sound

    @Test func aSecondFileOfARecordingAndAFileThatContainsItDoNotCountAgainstIt() throws {
        // The eight songs, a second file of song 3 (the same recording, quieter and at another rate), and a long file
        // that is songs 1 and 2 end to end, as a continuous mix kept as one track is.
        var songs = (0..<8).map { (id: "song\($0)", landmarks: Landmarks(mono: Self.song(seed: UInt64(100 + $0)), sampleRate: Self.rate)) }
        let again = Resampler.resample(Self.song(seed: 103).map { $0 * 0.5 }, from: Self.rate, to: 11025)
        songs.append((id: "song3 again", landmarks: Landmarks(mono: again, sampleRate: 11025)))
        songs.append((id: "the mix", landmarks: Landmarks(mono: Self.song(seed: 101) + Self.song(seed: 102), sampleRate: Self.rate)))
        songs.append((id: "song3 a third time", landmarks: Landmarks(mono: Self.song(seed: 103).map { $0 * 0.8 }, sampleRate: Self.rate)))
        let index = RecognitionIndex(songs: songs)
        #expect(index.isRelated(3, 8) && index.isRelated(8, 3) && index.isRelated(3, 10) && index.isRelated(8, 10))
        #expect(index.isRelated(1, 9) && index.isRelated(2, 9))
        #expect(!index.isRelated(1, 2) && !index.isRelated(3, 4) && !index.isRelated(0, 9))
        // Without the search the three files of song 3 stand against each other (a match is judged against the
        // third best) and the match looks unsure.
        let plain = RecognitionIndex(songs: songs, findCopies: false)
        let q3 = Landmarks(mono: Self.excerpt(Self.song(seed: 103), from: 17.3, seconds: 5), sampleRate: Self.rate)
        let alone = try #require(Recogniser(index: Self.index).match(q3).first)
        let unsure = try #require(Recogniser(index: plain).match(q3).first)
        let sure = try #require(Recogniser(index: index).match(q3).first)
        #expect(["song3", "song3 again", "song3 a third time"].contains(sure.id))
        #expect(sure.copies.count == 2)
        #expect(sure.confidence > 0.6 * alone.confidence && sure.confidence > 3)
        #expect(unsure.confidence < 0.5 * sure.confidence)
        // A song inside the long file: named as the song or as the file, surely either way.
        let q2 = Landmarks(mono: Self.excerpt(Self.song(seed: 102), from: 8, seconds: 5), sampleRate: Self.rate)
        let inMix = try #require(Recogniser(index: index).match(q2).first)
        #expect(["song2", "the mix"].contains(inMix.id) && inMix.confidence > 3)
        // The crate file's own keys do the same with no search, and the index file keeps what was found.
        let keyed = RecognitionIndex(songs: songs, sameRecording: [nil, nil, nil, "k", nil, nil, nil, nil, "k", nil, nil], findCopies: false)
        #expect(keyed.isRelated(3, 8) && !keyed.isRelated(1, 9))
        let url = Self.temporaryFile("copies.dkx")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try index.write(to: url)
        #expect(try RecognitionIndex(contentsOf: url).related == index.related)
    }
}
