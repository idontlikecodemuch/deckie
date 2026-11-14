import Foundation
import Testing
import DeckieAudio
import DeckieCrate
import DeckieBuild
import DeckieTestSupport
@testable import DeckieDesk

/// Adding music (research AE): the three ways in, a new crate's name, the big-drive rule, counting before a large read,
/// renaming with undo, and Stop keeping the songs already read.
@Suite struct AddMusicTests {
    @Test func theThreeWaysAreOneListWithTheirWordsAndIcons() throws {
        #expect(DeskAddMusic.ways.map(\.id) == ["drive", "cd", "folder"])
        for w in DeskAddMusic.ways {
            #expect(DeskWords.table[w.word] != nil && DeskWords.table[w.help] != nil, "\(w.id)")
            #expect(!w.macSymbol.isEmpty && !w.pageIcon.isEmpty)
        }
        #expect(DeskWords.text("addDrive") == "Add drive" && DeskWords.text("addCD") == "Add CD"
                && DeskWords.text("addFolder") == "Add folder")
        // The pages get the same list in the engine's first message.
        let out = Lines()
        let p = DeskProtocol(home: DeskHome(root: try scratch("ways")), output: out.add, makeRun: Self.noRun, analysisCheck: {})
        p.start()
        let hello = try #require(out.all.first { $0["event"] as? String == "hello" })
        let ways = try #require(hello["addWays"] as? [[String: String]])
        #expect(ways.map { $0["id"] } == ["drive", "cd", "folder"])
        #expect(ways.map { $0["word"] } == DeskAddMusic.ways.map(\.word))
        #expect(ways.map { $0["icon"] } == DeskAddMusic.ways.map(\.pageIcon))
    }

    @Test func aNewCrateIsMyCrateNumberedAndNeverTheSourcesName() throws {
        let home = DeskHome(root: try scratch("default-name"))
        try home.prepare()
        #expect(DeskAddMusic.newCrateName(shelf: home.shelf) == "My crate")
        let s = DeskSession(home: home)
        #expect(s.current == nil && s.newCrateName == "My crate")
        let first = try s.crateForRun(s.addRequest(URL(fileURLWithPath: "/nowhere/Friday stick"), name: "Friday stick"))
        #expect(first.name == "My crate")
        s.newCrate()
        #expect(s.newCrateName == "My crate 2")
        s.setNewCrateName("  Gig Friday ")
        s.setNewCrateName("   ")   // an empty name keeps the one there was
        #expect(s.newCrateName == "Gig Friday")
        #expect(try s.crateForRun(s.addRequest(URL(fileURLWithPath: "/nowhere/Stick 3"))).name == "Gig Friday")
    }

    @Test func renamingTheCrateIsOneStepOfUndoAndADuringRunNameWaits() throws {
        let home = DeskHome(root: try scratch("rename-undo"))
        try home.prepare()
        let info = try home.shelf.make(name: "My crate")
        try CrateWriter.write(crate([entry("aaaa", "Song A", disc: "Stick 3", folder: "House", track: 1, rel: "House/01.mp3")],
                                    name: "My crate"), to: home.shelf.package(info.id))
        let s = DeskSession(home: home)
        try s.rename(info.id, to: "Gig Friday")
        #expect(s.current?.name == "Gig Friday" && s.undoName == "undoRename")
        #expect(home.shelf.info(info.id)?.name == "Gig Friday")
        #expect(try CrateReader.read(from: home.shelf.package(info.id)).manifest.name == "Gig Friday")
        try s.undo()
        #expect(s.current?.name == "My crate" && home.shelf.info(info.id)?.name == "My crate")
        #expect(try CrateReader.read(from: home.shelf.package(info.id)).manifest.name == "My crate")
        try s.redo()
        #expect(s.current?.name == "Gig Friday")
        // While a run reads it: shown at once, kept off the disk, applied as the run ends.
        s.renameDuringRun("Saturday")
        #expect(s.shownName == "Saturday" && home.shelf.info(info.id)?.name == "Gig Friday")
        s.runEnded(info.id)
        #expect(s.current?.name == "Saturday" && s.shownName == "Saturday" && s.undoName == "undoRename")
        #expect(home.shelf.info(info.id)?.name == "Saturday")
    }

    @Test func aBigDriveIsDecidedBySizeAloneWithANamedLimit() throws {
        #expect(DeskAddMusic.bigDriveBytes == 256_000_000_000)
        #expect(!DeskAddMusic.isBig(bytes: 64_000_000_000, environment: [:]))
        #expect(!DeskAddMusic.isBig(bytes: 256_000_000_000, environment: [:]))
        #expect(DeskAddMusic.isBig(bytes: 2_000_000_000_000, environment: [:]))
        #expect(!DeskAddMusic.isBig(bytes: nil, environment: [:]))
        let small = [DeskAddMusic.bigDriveVariable: "1000"]
        #expect(DeskAddMusic.isBig(bytes: 5000, environment: small))
        #expect(DeskAddMusic.sizeWords(16_000_000_000) == "16 GB")
        #expect(DeskAddMusic.sizeWords(2_000_000_000_000) == "2 TB")
        #expect(DeskAddMusic.sizeWords(1_500_000_000_000) == "1.5 TB")
        #expect(DeskAddMusic.sizeWords(512_000_000) == "512 MB")

        // Stand-in drives: each folder a drive, with its volume's size; " (CD)" stands in for a data CD.
        let root = try scratch("stand-in-drives")
        for n in ["Stick 3", "Backup", "Friday burn (CD)"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(n), withIntermediateDirectories: true)
        }
        let env = [DeskDrives.standInVariable: root.path, DeskAddMusic.bigDriveVariable: "0"]
        let drives = DeskDrives.list(environment: env)
        #expect(drives.map(\.name) == ["Backup", "Friday burn", "Stick 3"])
        #expect(drives.first { $0.name == "Friday burn" }?.kind == DeskDrives.Kind.cd)
        #expect(drives.first { $0.name == "Friday burn" }?.big == false)   // a disc is never big
        #expect(drives.filter { $0.kind == DeskDrives.Kind.drive }.allSatisfy { $0.big && $0.bytes != nil && $0.size != nil })
        let roomy = DeskDrives.list(environment: [DeskDrives.standInVariable: root.path,
                                                  DeskAddMusic.bigDriveVariable: String(Int64.max)])
        #expect(roomy.allSatisfy { !$0.big })
    }

    @Test func countingFindsWhatARunWouldAndAsksAboveTheLine() throws {
        let root = try scratch("count")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Music/House/.hidden"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Music/Old.deckiecrate"), withIntermediateDirectories: true)
        for i in 1...60 { try Data(count: 100).write(to: root.appendingPathComponent("Music/House/\(i).mp3")) }
        try Data(count: 100).write(to: root.appendingPathComponent("Music/cover.jpg"))
        try Data(count: 100).write(to: root.appendingPathComponent("Music/House/.hidden/x.mp3"))
        try Data(count: 100).write(to: root.appendingPathComponent("Music/.y.flac"))
        try Data(count: 100).write(to: root.appendingPathComponent("Music/Old.deckiecrate/z.wav"))
        try Data(count: 100).write(to: root.appendingPathComponent("Music/Song.FLAC"))
        var seen: [Int] = []
        let c = DeskAddMusic.count(root.appendingPathComponent("Music")) { seen.append($0) }
        #expect(c.songs == 61 && c.bytes == 6100 && !c.stopped)
        // The count rises as it goes, not only at the end.
        #expect(seen.count >= 3 && seen == seen.sorted() && seen.last == 61)

        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        #expect(DeskAddMusic.askAboveSongs == 1_000)
        let quiet = DeskAddMusic.check(root.appendingPathComponent("Music"), home: home, environment: [:])
        #expect(!quiet.ask && quiet.songs == 61)
        // With no run timed here, the estimate is the cautious default rate.
        #expect(abs(quiet.seconds - 61 / DeskAddMusic.defaultSongsPerMinute * 60) < 0.01)
        let asked = DeskAddMusic.check(root.appendingPathComponent("Music"), home: home,
                                       environment: [DeskAddMusic.askAboveVariable: "50"])
        #expect(asked.ask)
        #expect(DeskAddMusic.aboutWords(600) == "10 minutes" && DeskAddMusic.aboutWords(4 * 3600) == "4 hours")
        // A count can be cancelled.
        let stop = DeskAddMusic.CountStop()
        stop.set()
        let cancelled = DeskAddMusic.check(root.appendingPathComponent("Music"), home: home, environment: [:], stop: stop)
        #expect(cancelled.stopped && !cancelled.ask)
    }

    @Test func theEngineCountsThenSaysWhetherToAsk() throws {
        let root = try scratch("engine-count")
        let music = root.appendingPathComponent("Big Drive/Music")
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        for i in 1...30 { try Data(count: 10).write(to: music.appendingPathComponent("\(i).mp3")) }
        let out = Lines()
        let p = DeskProtocol(home: DeskHome(root: root.appendingPathComponent("home")), output: out.add, makeRun: Self.noRun,
                             analysisCheck: {}, environment: [DeskAddMusic.askAboveVariable: "20"])
        p.start()
        p.handle(line: #"{"id": 1, "type": "add.count", "path": "\#(music.deletingLastPathComponent().path)"}"#)
        let counted = try #require(out.wait { $0["event"] as? String == "add.counted" })
        #expect((counted["songs"] as? NSNumber)?.intValue == 30 && counted["ask"] as? Bool == true)
        #expect(counted["name"] as? String == "Big Drive" && (counted["about"] as? String)?.isEmpty == false)
        // The first screen's name for the new crate travels in the state.
        p.handle(line: #"{"id": 2, "type": "crate.newName", "name": "Gig Friday"}"#)
        #expect(out.wait { $0["event"] as? String == "state" && $0["newName"] as? String == "Gig Friday" } != nil)
    }

    /// The count's events carry the folder back exactly as the page sent it, which is how the page knows they are its
    /// own. Here it is sent with a slash at the end (and, on Windows, with backslashes, as Windows' choosers give it);
    /// Foundation's own form of the path differs in both, and a page waiting for its string never heard the count end.
    @Test func theCountsEventsCarryThePathAsThePageSentIt() throws {
        let root = try scratch("engine-count-path")
        let music = root.appendingPathComponent("Stick 3")
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        for i in 1...3 { try Data(count: 10).write(to: music.appendingPathComponent("\(i).mp3")) }
        var sent = music.path + "/"
        #if os(Windows)
        sent = sent.replacingOccurrences(of: "/", with: "\\")
        #endif
        let out = Lines()
        let p = DeskProtocol(home: DeskHome(root: root.appendingPathComponent("home")), output: out.add, makeRun: Self.noRun,
                             analysisCheck: {})
        p.start()
        let line = try JSONSerialization.data(withJSONObject: ["id": 1, "type": "add.count", "path": sent])
        p.handle(line: String(decoding: line, as: UTF8.self))
        let counted = try #require(out.wait { $0["event"] as? String == "add.counted" })
        #expect(counted["path"] as? String == sent)
        #expect((counted["songs"] as? NSNumber)?.intValue == 3 && counted["name"] as? String == "Stick 3")
        let reply = try #require(out.wait { ($0["re"] as? NSNumber)?.intValue == 1 })
        #expect(reply["path"] as? String == sent)
    }

    static let noRun: DeskProtocol.RunMaker = { home, id, request in
        DeskRun(home: home, crateId: id, request: request, jobs: 1, device: "test", signer: nil, printer: DeskRun.portablePrint)
    }
}

/// Stop: the songs read are kept, the run stays to carry on, and carrying on reads only the rest.
@Suite(.enabled(if: Engine.available, "needs ONNX Runtime and the Beat This! model"))
struct StopKeepsSongsTests {
    @Test func stopKeepsTheSongsReadAndCarryOnReadsTheRest() async throws {
        let root = try scratch("stop")
        let stick = root.appendingPathComponent("Stick 3/House")
        try FileManager.default.createDirectory(at: stick, withIntermediateDirectories: true)
        let buffer = TestTrack.render()
        for (i, gain) in [1.0, 0.6, 0.35].enumerated() {
            try TestTrack.wav(AudioBuffer(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount,
                                          samples: buffer.samples.map { $0 * Float(gain) }))
                .write(to: stick.appendingPathComponent("0\(i + 1) Song.wav"))
        }
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        let info = try home.shelf.make(name: "My crate")
        let analyser = try Builder.makeAnalyser(jobs: 1)
        let request = RunRequest(folder: root.appendingPathComponent("Stick 3"), source: "Stick 3")
        let run = DeskRun(home: home, crateId: info.id, request: request, jobs: 1, device: "Mac15,6", analyser: analyser,
                          signer: nil, printer: DeskRun.portablePrint)
        // Stop as soon as the first song is read.
        let (crate, report) = try await CPUTurns.exclusive {
            try run.run { p in if case .file? = p.line { run.stop() } }
        }
        #expect(run.stopAsked)
        #expect(report.stopped == true)
        #expect(crate.tracks.count >= 1 && crate.tracks.count < 3, "\(crate.tracks.count)")
        #expect(try CrateReader.read(from: home.shelf.package(info.id)).tracks.count == crate.tracks.count)
        // Nothing the run did not reach is said to have failed.
        #expect(report.notInCount == 0 && (crate.manifest.importLog?.entries ?? []).isEmpty)
        // The run stays, to carry on.
        #expect(DeskRun.pending(home: home, crateId: info.id) == request)
        let again = DeskRun(home: home, crateId: info.id, request: request, jobs: 1, device: "Mac15,6", analyser: analyser,
                            signer: nil, printer: DeskRun.portablePrint)
        let (all, rest) = try await CPUTurns.exclusive { try again.run() }
        #expect(all.tracks.count == 3 && rest.stopped == nil)
        #expect(rest.analysed == 3 - crate.tracks.count)   // the songs read before are not read again
        #expect(DeskRun.pending(home: home, crateId: info.id) == nil)
    }

    /// A source already in the crate is read again because its files changed, and the DJ stops part-way: every song
    /// the crate had before stays (the ones not reached yet as they were), the ones read so far are the new reading,
    /// and Carry on reads only the songs not reached.
    @Test func stopDuringAReReadKeepsTheSongsThatWereThere() async throws {
        let root = try scratch("stop-reread")
        let stick = root.appendingPathComponent("Stick 3/House")
        try FileManager.default.createDirectory(at: stick, withIntermediateDirectories: true)
        let buffer = TestTrack.render()
        func write(_ gains: [Double], at date: Date? = nil) throws {
            for (i, gain) in gains.enumerated() {
                let url = stick.appendingPathComponent("0\(i + 1) Song.wav")
                try TestTrack.wav(AudioBuffer(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount,
                                              samples: buffer.samples.map { $0 * Float(gain) })).write(to: url)
                // The same length is the same size: the time it changed is what says it changed.
                if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
            }
        }
        try write([1.0, 0.6, 0.35])
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        let info = try home.shelf.make(name: "My crate")
        let analyser = try Builder.makeAnalyser(jobs: 1)
        let request = RunRequest(folder: root.appendingPathComponent("Stick 3"), source: "Stick 3")
        func run() -> DeskRun {
            DeskRun(home: home, crateId: info.id, request: request, jobs: 1, device: "Mac15,6", analyser: analyser,
                    signer: nil, printer: DeskRun.portablePrint)
        }
        let (first, _) = try await CPUTurns.exclusive { try run().run() }
        #expect(first.tracks.count == 3)
        let before = Set(first.tracks.map(\.id))

        // Every file changes (new bytes, a later time), and the stick is read again; Stop once one song is read.
        try write([0.9, 0.5, 0.3], at: Date().addingTimeInterval(120))
        let again = run()
        let (stopped, report) = try await CPUTurns.exclusive {
            try again.run { p in if case .file? = p.line { again.stop() } }
        }
        #expect(report.stopped == true)
        let readNow = Set(stopped.tracks.map(\.id)).subtracting(before)
        #expect(readNow.count >= 1 && readNow.count < 3, "\(readNow.count)")
        // Nothing taken away: the songs not reached yet are there as they were, one entry per file.
        #expect(stopped.tracks.count == 3, "\(stopped.tracks.count)")
        #expect(Set(stopped.tracks.map(\.id)).intersection(before).count == 3 - readNow.count)
        #expect(Set(stopped.tracks.compactMap(\.file.rel)) == ["House/01 Song.wav", "House/02 Song.wav", "House/03 Song.wav"])
        #expect(try CrateReader.read(from: home.shelf.package(info.id)).tracks.count == 3)
        #expect(DeskRun.pending(home: home, crateId: info.id) == request)

        // Carry on: only the songs not reached are read; the old readings are replaced, none is left behind.
        let (all, rest) = try await CPUTurns.exclusive { try run().run() }
        #expect(rest.stopped == nil && rest.analysed == 3 - readNow.count)
        #expect(all.tracks.count == 3 && Set(all.tracks.map(\.id)).isDisjoint(with: before))
        #expect(DeskRun.pending(home: home, crateId: info.id) == nil)
    }
}

/// Collects the messages a protocol in this process sends.
final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [[String: Any]] = []
    var all: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return lines }
    func add(_ d: Data) {
        guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        lock.lock(); lines.append(o); lock.unlock()
    }
    func wait(seconds: Double = 10, _ match: ([String: Any]) -> Bool) -> [String: Any]? {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if let m = all.first(where: match) { return m }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }
}
