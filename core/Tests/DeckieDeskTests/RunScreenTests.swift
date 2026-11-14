import Foundation
import Testing
import DeckieCrate
import DeckieBuild
@testable import DeckieDesk

/// The run screen's data (D37): each song as it joins, the running totals, the true things said about them, the
/// moments, and how they travel to the pages without flooding them.
@Suite struct RunScreenTests {
    func song(_ id: String, bpm: Double? = 124, key: RunSong.Key = .init(kind: .key, camelot: "8A", note: 9, minor: true),
              seconds: Double = 240, title: String? = nil, artist: String? = "Ola Brandt", intro: Int? = nil) -> RunSong {
        RunSong(id: id, title: title ?? "Song \(id)", artist: artist, bpm: bpm, key: key, bars: 96, seconds: seconds,
                place: "Stick 3 / House 1", folder: nil, wave: [Int](repeating: 50, count: RunSong.waveLength),
                introBars: intro, before: false)
    }

    @Test func theWaveIsTheLoudestBarOfEachStretchOnOneScale() {
        #expect(RunSong.wave(nil).isEmpty && RunSong.wave([]).isEmpty)
        // 128 bars: two a value; the louder of each pair is kept.
        var lufs = [Double](repeating: -30, count: 128)
        lufs[5] = -4
        let w = RunSong.wave(lufs)
        #expect(w.count == 64)
        #expect(w[2] == 99 && w[0] == 0 && w[3] == 0)
        // Quieter than the floor is 0, louder than the ceiling 99, and the middle of the scale is about half.
        #expect(RunSong.wave([-60, -1, -17])[0] == 0)
        #expect(RunSong.wave([-1]).allSatisfy { $0 == 99 })
        #expect(RunSong.wave([-17]).first == 50)
        // Fewer bars than values: each bar is drawn over several values, and none is lost.
        let short = RunSong.wave([-30, -4, -30, -30])
        #expect(short.count == 64 && short.filter { $0 == 99 }.count == 16)
        // Silence the analysis wrote as minus infinity draws as nothing, not as a gap.
        #expect(RunSong.wave([-.infinity, -4]).count == 64)
    }

    @Test func theKeyIsWhatDeskDecided() {
        func k(_ source: String, _ c: Double, _ camelot: String = "8A") -> CrateTrack.Key {
            .init(source: source, confidence: c, camelot: camelot, key: "A", scale: "minor", votes: [:], changes: nil)
        }
        let sure = RunSong.key(k("three-answer", 1.0))
        #expect(sure.kind == .key && sure.camelot == "8A" && sure.note == 9 && sure.minor == true && sure.name == "A")
        let home = RunSong.key(k("three-answer", 0.45, "8B"))
        #expect(home.kind == .home && home.note == 0 && home.camelot == nil && home.minor == nil && home.name == "C")
        #expect(RunSong.key(k("three-answer", 0.2)).kind == .none)
        #expect(RunSong.key(nil).kind == .none)
        // An earlier reader's key is shown as it is, marked not sure under its line.
        let old = RunSong.key(k("hpcp-whitened", 0.45))
        #expect(old.kind == .key && old.uncertain)
    }

    @Test func theFiguresCountTheSongsOnTheScreen() {
        var tally = RunTally()
        var a = song("a", bpm: 124, seconds: 3000)
        var b = song("b", bpm: 90, key: .init(kind: .home, note: 2), seconds: 700)
        var c = song("c", bpm: nil, key: .init(kind: .none), seconds: 100)
        _ = tally.add(&a); _ = tally.add(&b); _ = tally.add(&c)
        var again = a
        #expect(tally.add(&again).isEmpty)
        let f = tally.figures
        #expect(f.songs == 3 && a.number == 1 && c.number == 3)
        #expect(f.seconds == 3800)
        #expect(f.tempos[Int((124 - RunFigures.tempoFloor) / RunFigures.tempoBin)] == 1)
        #expect(f.tempos[15] == 1 && f.noTempo == 1 && f.tempos.reduce(0, +) == 2)
        #expect(f.slowest == 90 && f.fastest == 124)
        #expect(f.minor[9] == 1 && f.home[2] == 1 && f.noKey == 1 && f.keysFound == 1)
        // Tempos past either end are counted in the end bins.
        var slow = song("s", bpm: 40), fast = song("f", bpm: 260)
        _ = tally.add(&slow); _ = tally.add(&fast)
        #expect(tally.figures.tempos.first == 1 && tally.figures.tempos.last == 1)
        #expect(tally.figures.tempos.count == RunFigures.tempoBins)
    }

    @Test func momentsMarkRealEvents() {
        var tally = RunTally()
        var all: [RunNote] = []
        let keys = (0..<24).map { i in RunSong.Key(kind: .key, camelot: "\(i % 12 + 1)\(i < 12 ? "A" : "B")", note: (i * 7) % 12, minor: i < 12) }
        for i in 0..<60 {
            var s = song("s\(i)", key: keys[i % 24], seconds: 150)
            all += tally.add(&s)
        }
        let moments = all.filter { $0.kind == .moment }
        #expect(moments.first?.code == "first" && moments.first?.values["title"] == "Song s0")
        #expect(moments.filter { $0.code == "songs" }.map(\.n) == [10, 50])
        // 60 songs of 2:30 is two and a half hours: two hour marks.
        #expect(moments.filter { $0.code == "hour" }.map(\.n) == [1, 2])
        #expect(moments.filter { $0.code == "wheel" }.count == 1)
        #expect(tally.finished().code == "finished" && tally.finished().values["seconds"] == "9000")
        // The thousands, with their separator.
        #expect(RunTally.grouped(1000) == "1,000" && RunTally.grouped(12500) == "12,500" && RunTally.grouped(500) == "500")
    }

    @Test func factsAreTrueWhenTheyAreMade() {
        var tally = RunTally()
        var notes: [RunNote] = []
        for (i, bpm) in [124.0, 124, 124, 126, 128].enumerated() {
            var s = song("t\(i)", bpm: bpm); notes += tally.add(&s)
        }
        // Three in a row at one tempo, said once at three.
        #expect(notes.filter { $0.code == "tempoRun" }.map(\.n) == [3])
        // "Slowest so far" only from the fifth song, and only when it is.
        var slow = song("slow", bpm: 98, seconds: 600, intro: 32)
        let n = tally.add(&slow)
        #expect(n.contains { $0.code == "slowest" && $0.values["bpm"] == "98" && $0.values["title"] == "Song slow" })
        #expect(n.contains { $0.code == "longest" && $0.values["length"] == "10:00" })
        #expect(n.contains { $0.code == "longestIntro" && $0.values["bars"] == "32" })
        #expect(!n.contains { $0.code == "fastest" })
        // A song with no artist needs a name, said the first time.
        var bare = song("bare", artist: nil)
        #expect(tally.add(&bare).contains { $0.code == "needName" })
        #expect(tally.figures.needName == 1)
        // The same file in a second place.
        let two = tally.again("bare", title: "Song bare", place: "Stick 3 / Set 2")
        #expect(two.first?.code == "twoPlaces" && two.first?.values["place"] == "Stick 3 / Set 2")
        #expect(tally.figures.sameFile == 1)
        #expect(tally.again("nobody", title: "x", place: nil).isEmpty)
        // Copies are known only once linked.
        #expect(tally.figures.copies == nil)
        #expect(tally.copies(4).first?.n == 4 && tally.figures.copies == 4)
    }

    /// Every note a run can make has its words, and the sayings are lists the copy audit can change.
    @Test func everyNoteAndSayingHasWords() {
        let facts = ["slowest", "fastest", "tempoRun", "commonTempo", "newKey", "keysFound", "homeNote", "notSure", "longest",
                     "shortest", "longestIntro", "twoPlaces", "needName", "copies"]
        let moments = ["first", "songs", "hour", "wheel", "disc", "finished"]
        for code in facts { #expect(DeskWords.table["fact.\(code)"] != nil || DeskWords.table["fact.\(code).other"] != nil, "\(code)") }
        for code in moments { #expect(DeskWords.table["moment.\(code)"] != nil || DeskWords.table["moment.\(code).other"] != nil, "\(code)") }
        for step in ["reading", "finishing", "disc", "saving"] { #expect(DeskWords.list("saying.\(step)").count >= 3, "\(step)") }
        #expect(DeskWords.list("saying.reading").count == DeskWords.table.keys.filter { $0.hasPrefix("saying.reading.") }.count)
        #expect(DeskWords.list("saying.reading").contains { $0.contains(DeskWords.text("thisComputer.\(DeskWords.computerKind)")) })
        // Deckie's voice (voice.md): no exclamation marks, never "AI".
        let run = DeskWords.table.filter { $0.key.hasPrefix("saying.") || $0.key.hasPrefix("fact.") || $0.key.hasPrefix("moment.") }
        #expect(run.count >= 30)
        for (k, w) in run {
            #expect(!w.contains("!"), "\(k)")
            #expect(w.range(of: "\\bAI\\b", options: .regularExpression) == nil, "\(k)")
        }
    }

    /// Songs travel in batches at most four times a second, in the order they joined, so a burst of 5,000 songs is a
    /// handful of lines; and a song that arrives alone is not held back long.
    @Test func songsTravelInSmallBatches() throws {
        final class Lines: @unchecked Sendable {
            let lock = NSLock(); var all: [Data] = []
            func add(_ m: [String: Any]) {
                let d = try! JSONSerialization.data(withJSONObject: m, options: [.sortedKeys])
                lock.lock(); all.append(d); lock.unlock()
            }
            var count: Int { lock.lock(); defer { lock.unlock() }; return all.count }
        }
        let lines = Lines()
        let out = RunScreenOut { lines.add($0) }
        var tally = RunTally()
        let t0 = Date()
        for i in 0..<5000 {
            var s = song(String(format: "%016x", i), bpm: Double(70 + i % 100), seconds: 200 + Double(i % 300),
                         title: "A song title of a usual length \(i)", artist: "An artist")
            let notes = tally.add(&s)
            var p = RunProgress(stage: .finishing, done: i, total: 5000, remaining: nil, line: nil)
            p.song = s; p.notes = notes; p.figures = tally.figures
            out.offer(p)
        }
        out.flush()
        let elapsed = Date().timeIntervalSince(t0)
        #expect(lines.count <= Int(elapsed / RunScreenOut.every) + 2 + 5000 / RunScreenOut.maxSongs)
        var numbers: [Int] = []
        var bytes = 0
        for d in lines.all {
            bytes += d.count + 1
            let m = try #require(try JSONSerialization.jsonObject(with: d) as? [String: Any])
            #expect(m["event"] as? String == "run.songs")
            numbers += ((m["songs"] as? [[String: Any]]) ?? []).compactMap { ($0["number"] as? NSNumber)?.intValue }
        }
        #expect(numbers == Array(1...5000))
        // About 400 bytes a song: 5,000 songs are about 2 MB however they are batched.
        let one = try JSONEncoder().encode(song("0123456789abcdef", title: "A song title of a usual length", artist: "An artist"))
        #expect(one.count < 600, "\(one.count) bytes a song")
        print("run screen: 5,000 songs in a burst: \(lines.count) lines, \(bytes) bytes; one song \(one.count) bytes")

        // One song alone goes out within the batch time.
        let alone = Lines()
        let out2 = RunScreenOut { alone.add($0) }
        var t = RunTally()
        var a = song("a"), b = song("b")
        _ = t.add(&a); _ = t.add(&b)
        for s in [a, b] {
            var p = RunProgress(stage: .reading, done: 0, total: 2, remaining: nil, line: nil)
            p.song = s; p.figures = t.figures
            out2.offer(p)
        }
        let end = Date().addingTimeInterval(2)
        while alone.count < 2 && Date() < end { Thread.sleep(forTimeInterval: 0.02) }
        #expect(alone.count == 2)
    }
}
