import Foundation
import Testing
import DeckieCrate
import DeckieBuild
@testable import DeckieDesk

/// The song card's one "now" (owner's suggestion, Nov 20, 2026): the song being worked on, named, with its step; the
/// next song of a disc while it is read ahead, apart; several songs at once named consistently; and the count beside
/// the bar in words that cannot be read as the card's song number.
@Suite struct NowSongTests {
    let one = "Sunday Session/Track 01.wav", two = "Sunday Session/Track 02.wav", three = "Sunday Session/Track 03.wav"

    /// One at a time (a music CD): the card's song is the song taken, from the moment it is taken, by its CD-Text
    /// name; its own read and its analysis steps are its steps.
    @Test func oneAtATimeTheSongTakenIsTheSongNow() {
        var w = RunWorking(oneAtATime: true)
        #expect(w.now == nil && w.songs.isEmpty)
        w.took(RunNow(rel: one, number: 1, step: "started", title: "Night drive", artist: "Artist A"))
        #expect(w.now?.rel == one && w.now?.name == "Night drive")
        #expect(w.now?.line(total: 6) == "Reading song 1 of 6 from the disc")
        w.step(one, step: "reading", read: 0.4)
        #expect(w.now?.read == 0.4 && w.ahead == nil)
        // The tags of a WAV off a disc give only its file name: the CD-Text name stays.
        w.named(one, title: nil, artist: nil)
        #expect(w.now?.name == "Night drive")
        w.step(one, step: "beatthis")
        #expect(w.now?.line(total: 6) == "Song 1 of 6: finding the beat")
        #expect(w.now?.share == 0.4)
        w.done(one)
        #expect(w.now == nil && w.songs.isEmpty)
    }

    /// Read ahead: while song 2 is analysed the drive reads song 3; that read is said apart and never moves the card's
    /// song. When song 3 is taken its read ahead becomes its own read, and the read ahead line goes.
    @Test func aReadAheadIsSaidApartFromTheSongNow() {
        var w = RunWorking(oneAtATime: true)
        w.took(RunNow(rel: two, number: 2, step: "started"))
        w.step(two, step: "reading", read: 1)
        w.step(two, step: "key")
        w.step(three, step: "reading", read: 0.25)
        #expect(w.now?.rel == two && w.now?.step == "key")
        #expect(w.ahead?.rel == three && w.ahead?.number == 3 && w.ahead?.read == 0.25)
        w.step(three, step: "reading", read: 0.5)
        #expect(w.ahead?.read == 0.5)
        #expect(w.songs.count == 1)
        // Read whole: the drive stops, so the line goes.
        w.step(three, step: "reading", read: 1)
        #expect(w.ahead == nil)
        // Read ahead again, then taken part way: its read is now the song's own.
        w.step(three, step: "reading", read: 0.6)
        w.done(two)
        w.took(RunNow(rel: three, number: 3, step: "started"))
        #expect(w.ahead == nil && w.now?.rel == three)
        w.step(three, step: "reading", read: 0.8)
        #expect(w.now?.read == 0.8 && w.ahead == nil)
        // A read ahead cancelled (Stop) is let go.
        w.step(one, step: "reading", read: 0.1)
        #expect(w.ahead?.rel == one)
        w.aheadEnded(one)
        #expect(w.ahead == nil)
        // An analysis step of a song not in hand moves nothing.
        w.step(two, step: "key")
        #expect(w.now?.rel == three && w.ahead == nil)
    }

    /// Several at once (a folder read with four jobs): no one song is "the" song (`now` is nil); every song in hand is
    /// listed in the order taken, by its name, each with its own step.
    @Test func severalAtOnceAreListedWithTheirSteps() {
        var w = RunWorking(oneAtATime: false)
        let songs = ["Friday Set/House/a.mp3", "Friday Set/House/b.flac", "Friday Set/Disco/c.wav", "Friday Set/d.m4a"]
        for s in songs { w.took(RunNow(rel: s, number: nil, step: "started")) }
        #expect(w.now == nil)
        #expect(w.songs.map(\.rel) == songs)
        #expect(w.songs.map(\.name) == ["a", "b", "c", "d"])
        w.named(songs[1], title: "Slow Bloom", artist: "Artist D")
        w.step(songs[0], step: "beatthis")
        w.step(songs[1], step: "key")
        #expect(w.songs[0].stage == "finding the beat" && w.songs[1].stage == "working out the key")
        #expect(w.songs[2].stage == "opening it")
        #expect(w.songs[1].name == "Slow Bloom" && w.songs[1].artist == "Artist D")
        // The card: the song furthest along, kept while it is worked on; the rest are rows, in the order taken.
        #expect(RunNow.cardSong(w.songs, keeping: nil)?.rel == songs[1])
        #expect(RunNow.cardSong(w.songs, keeping: songs[2])?.rel == songs[2])
        #expect(RunNow.cardSong(w.songs, keeping: "gone.mp3")?.rel == songs[1])
        #expect(RunNow.rows(w.songs, card: songs[1]).map(\.rel) == [songs[0], songs[2], songs[3]])
        w.done(songs[0])
        w.took(RunNow(rel: "Friday Set/e.mp3", number: nil, step: "started"))
        #expect(w.songs.map(\.name) == ["Slow Bloom", "c", "d", "e"])
        #expect(RunNow.alsoLine(3) == "Also working on 3 songs" && RunNow.alsoLine(1) == "Also working on 1 song")
    }

    /// The count beside the bar says what is done, not a song's number; a song not on a disc says "this song".
    @Test func theCountAndTheCardSayDifferentThings() {
        #expect(DeskWords.count("doneOf", 6, ["done": "1", "total": "6"]) == "1 of 6 done")
        #expect(DeskWords.count("doneOf", 1, ["done": "0", "total": "1"]) == "0 of 1 done")
        let folder = RunNow(rel: "Friday Set/House/track07.mp3", number: nil, step: "started")
        #expect(folder.line(total: 9) == "Reading this song")
        #expect(folder.name == "track07")
        var hashed = folder; hashed.step = "hash"
        #expect(hashed.line(total: 9) == "This song: reading it through")
        #expect(RunNow.aheadLine == "Reading the next song from the disc")
    }

    /// A wave as bars: stretched to the song's own range so peaks and valleys show; a level song at full height; one bar
    /// a bar of music for a short song; nothing with no wave.
    @Test func aWaveBecomesBarsStretchedToItsOwnRange() {
        // A real song's shape (the demo crate's "Sweet They": loud body, quiet tail), loudest at the top, the quiet
        // tail at the floor, the body's dips clearly below its peaks.
        var wave = Array(repeating: 64, count: 64)
        for i in stride(from: 0, to: 56, by: 8) { wave[i] = 50 }
        for i in 58..<64 { wave[i] = 13 }
        let h = RunSong.barHeights(wave, bars: 112, rangeMin: 8, floor: 0.12)
        #expect(h.count == 64)
        #expect(abs((h.max() ?? 0) - 1) < 1e-9)
        #expect(abs(h[63] - 0.12) < 1e-9 && h[0] < 0.5)
        // Without the tenth-quietest rule the silent tail would have squashed the body into the top of the room.
        #expect(h[1] - h[0] > 0.5)
        // A level song stands at full height.
        let level = RunSong.barHeights(Array(repeating: 44, count: 64), bars: 20, rangeMin: 8, floor: 0.12)
        #expect(level.count == 20 && level.allSatisfy { abs($0 - 1) < 1e-9 })
        // A short song: one bar a bar of music, each its stretch's loudest.
        let short = RunSong.barHeights((0..<64).map { $0 }, bars: 8, rangeMin: 8, floor: 0)
        #expect(short.count == 8 && short.last == 1 && short == short.sorted())
        #expect(RunSong.barHeights([], bars: 10, rangeMin: 8, floor: 0.12).isEmpty)
    }

    /// The protocol's additions: `working` and `ahead` beside `now`, with each song's name; what changed is sent at
    /// once (songs, steps, names, the read ahead starting or ending), not how much is read.
    @Test func theProtocolCarriesTheSongsWorkedOnAndTheReadAhead() {
        var p = RunProgress(stage: .reading, done: 1, total: 6, remaining: nil, line: nil)
        #expect(DeskProtocol.workingKey(p) == nil)
        let now = RunNow(rel: two, number: 2, step: "key", title: "Café Ünder", artist: "DJ Vera")
        p.now = now; p.working = [now]
        let m = DeskProtocol.now(now)
        #expect(m["title"] as? String == "Café Ünder" && m["artist"] as? String == "DJ Vera" && m["number"] as? Int == 2)
        let k1 = DeskProtocol.workingKey(p)
        p.ahead = RunNow(rel: three, number: 3, step: "reading", read: 0.2)
        let k2 = DeskProtocol.workingKey(p)
        p.ahead?.read = 0.7
        #expect(k1 != k2 && DeskProtocol.workingKey(p) == k2)
        p.working[0].step = "spectral"
        #expect(DeskProtocol.workingKey(p) != k2)
    }
}
