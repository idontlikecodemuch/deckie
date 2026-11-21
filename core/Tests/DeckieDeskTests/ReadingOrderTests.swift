import Foundation
import Testing
import DeckieAudio
import DeckieCrate
import DeckieBuild
import DeckieTestSupport
@testable import DeckieDesk

/// The reading screen's one order (owner's note, Nov 20, 2026, "the top moves on to a song before the card below shows
/// it"): a song leaves the song card only as it joins the song info card, and no line names a song read before then.
/// Checked on the calls a run makes (RunOrder), on a made-up sequence and on a real run of several songs at once.
@Suite struct ReadingOrderTests {
    /// What a window shows, from the calls in the order they go out: the songs in progress (the song card), the songs
    /// on the screen (the info card is the last of them), and every song a line has named. A song named by a line,
    /// or let go of by the song card, must be on the screen already.
    struct Screen {
        var working: [String] = []
        var landed = Set<String>()
        var problems: [String] = []
        mutating func take(_ p: RunProgress) {
            if let r = p.landed { landed.insert(r) }
            // A file that did not go in is let go by its line: it has no song to show.
            if case let .file(rel, .failed)? = p.line { landed.insert(rel) }
            let now = p.working.map(\.rel)
            if p.stage == .reading {
                for r in working where !now.contains(r) && !landed.contains(r) { problems.append("card let go of \(r) before it joined") }
            }
            working = p.stage == .reading ? now : []
            if case let .file(rel, _)? = p.line, !landed.contains(rel) { problems.append("list named \(rel) before it joined") }
        }
    }

    func call(_ working: [String], line: RunLine? = nil, song: Bool = false, landed: String? = nil, done: Int = 0) -> RunProgress {
        var p = RunProgress(stage: .reading, done: done, total: 4, remaining: nil, line: line)
        p.working = working.map { RunNow(rel: $0, number: nil, step: "key") }
        p.landed = landed
        if song { p.song = RunSong(id: landed ?? "x", title: "T", artist: nil, bpm: nil, key: .init(kind: .none), bars: nil, seconds: 1,
                                   place: nil, folder: nil, wave: [], introBars: nil, before: false) }
        return p
    }

    /// A folder read four at once, as the engine's threads call: song A's line comes before its song (which is made on
    /// another queue); B and C move on meanwhile. Unordered, the list names A first; ordered, A joins first.
    @Test func aSongLeavesTheCardOnlyAsItJoins() {
        let calls = [
            call(["A", "B", "C", "D"]),
            call(["B", "C", "D"], line: .file(rel: "A", outcome: .analysed(seconds: 2))),   // A read; its song not yet made
            call(["B", "C", "D", "E"]),                                                     // another job takes E
            call(["B", "C", "D", "E"], song: true, landed: "A"),                            // A joins the screen
            call(["C", "D", "E"], line: .file(rel: "B", outcome: .failed(FileFailure(reason: "unsupported", message: "")))),
            call(["D", "E"], song: true, landed: "C"),                                      // C joins before its line
            call(["D", "E"], line: .file(rel: "C", outcome: .analysed(seconds: 2)), done: 1),
        ]
        var raw = Screen()
        for p in calls { raw.take(p) }
        #expect(!raw.problems.isEmpty)
        var order = RunOrder(), screen = Screen()
        var out: [RunProgress] = []
        for p in calls { out += order.take(p) }
        for p in out { screen.take(p) }
        #expect(screen.problems.isEmpty, "\(screen.problems)")
        // Nothing is lost, and the order of everything else is kept.
        #expect(out.filter { $0.line != nil }.count == 3 && out.filter { $0.song != nil }.count == 2)
        #expect(out.last?.working.map(\.rel) == ["D", "E"] && order.waiting.isEmpty)
        // A's own call comes out beside the songs as they were last let out (A still among them), then the rest.
        let a = out.firstIndex { $0.landed == "A" }!
        #expect(out[a].working.map(\.rel) == ["A", "B", "C", "D"])
        #expect(out.firstIndex { if case .file(rel: "A", _)? = $0.line { return true }; return false }! > a)
        // Another stage lets everything out.
        var o2 = RunOrder()
        _ = o2.take(call(["A"]))
        #expect(o2.take(call([], line: .file(rel: "A", outcome: .analysed(seconds: 1)))).isEmpty)
        #expect(o2.take(RunProgress(stage: .finishing, done: 1, total: 1, remaining: nil, line: nil)).count == 2)
    }
}

/// The same on a real run: four songs read at once, then Stop and Carry on, whose count carries on from the songs
/// read before and whose time is the whole reading time.
@Suite(.enabled(if: Engine.available, "needs ONNX Runtime and the Beat This! model"))
struct ReadingOrderRunTests {
    /// Stop comes from the run's own calls, not a clock: as soon as the first song is taken, so whatever the
    /// machine's speed, the songs already in hand (one to `jobs`) are read and the rest wait for Carry on.
    @Test(arguments: [1, 4]) func aRealRunNeverNamesASongBeforeItJoinsAndCarryOnCarriesOn(jobs: Int) async throws {
        let root = try scratch("reading-order")
        let folder = root.appendingPathComponent("Gig/House")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let buffer = TestTrack.render()
        for (i, gain) in [1.0, 0.85, 0.7, 0.6, 0.5, 0.4].enumerated() {
            try TestTrack.wav(AudioBuffer(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount,
                                          samples: buffer.samples.map { $0 * Float(gain) }))
                .write(to: folder.appendingPathComponent("0\(i + 1) Song.wav"))
        }
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        let info = try home.shelf.make(name: "Gig")
        let analyser = try Builder.makeAnalyser(jobs: jobs)
        let request = RunRequest(folder: root.appendingPathComponent("Gig"), source: "Gig")
        func run() -> DeskRun {
            DeskRun(home: home, crateId: info.id, request: request, jobs: jobs, device: "Mac15,6", analyser: analyser,
                    signer: nil, printer: DeskRun.portablePrint)
        }
        final class Calls: @unchecked Sendable { let lock = NSLock(); var all: [RunProgress] = [] }
        let first = Calls(), second = Calls()
        // Stopped as the first song is taken: the songs in hand finish, no other is started.
        let one = run()
        let (part, stopped) = try await CPUTurns.exclusive {
            try one.run { p in
                first.lock.lock(); first.all.append(p); first.lock.unlock()
                if !p.working.isEmpty { one.stop() }
            }
        }
        #expect(stopped.stopped == true)
        #expect((1...jobs).contains(part.tracks.count), "\(part.tracks.count) read before Stop, \(jobs) at once")
        let (all, rest) = try await CPUTurns.exclusive {
            try run().run { p in second.lock.lock(); second.all.append(p); second.lock.unlock() }
        }
        #expect(all.tracks.count == 6 && rest.stopped == nil && rest.carriedOn)
        for calls in [first.all, second.all] {
            var screen = ReadingOrderTests.Screen()
            for p in calls { screen.take(p) }
            #expect(screen.problems.isEmpty, "\(screen.problems)")
        }
        // The song card's parts (the owner's note, Nov 20, 2026): each is sent as soon as it is final and never changes,
        // and the finished song says the same: length, tempo, bars, key, wave and where.
        for calls in [first.all, second.all] {
            var seen: [String: RunNow] = [:]
            for p in calls {
                for n in p.working {
                    if let was = seen[n.rel] {
                        for (a, b) in [(was.seconds, n.seconds), (was.bpm, n.bpm)] where a != nil { #expect(a == b, "\(n.rel) changed a part") }
                        if was.bars != nil { #expect(was.bars == n.bars) }
                        if was.key != nil { #expect(was.key == n.key) }
                        if was.wave != nil { #expect(was.wave == n.wave) }
                        if was.place != nil { #expect(was.place == n.place && was.folder == n.folder) }
                    }
                    seen[n.rel] = n
                }
                if let song = p.song, let rel = song.rel, let n = seen[rel], n.hasParts {
                    #expect(n.seconds == song.seconds && n.bpm == song.bpm && n.bars == song.bars, "\(rel)")
                    #expect(n.key == song.key && n.wave == song.wave, "\(rel)")
                    #expect(n.place == song.place && n.folder == song.folder, "\(rel)")
                }
            }
            #expect(seen.values.contains { $0.wave != nil && $0.key != nil && $0.bpm != nil && $0.seconds != nil && $0.bars != nil })
        }
        // Carry on: the count starts at the songs already read, not at 0.
        let started = try #require(second.all.first { if case .started? = $0.line { return true }; return false })
        if case let .started(_, unchanged, _)? = started.line { #expect(unchanged == part.tracks.count && started.done == unchanged) }
        #expect(second.all.map(\.done) == second.all.map(\.done).sorted())
        // The whole reading time, the part before Stop included, and the rate from it.
        #expect(rest.secondsBefore == stopped.seconds)
        #expect(rest.seconds > stopped.seconds)
        #expect(abs(rest.songsPerMinute - Double(rest.songsSeen) / rest.seconds * 60) < 1e-9)
        #expect(DeskRun.runs(home: home, crateId: info.id).last?.secondsBefore == stopped.seconds)
    }
}
