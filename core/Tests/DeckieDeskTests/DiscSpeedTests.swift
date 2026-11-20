import Foundation
import Testing
import DeckieAudio
import DeckieCore
import DeckieCrate
import DeckieBuild
import DeckieDecode
import DeckieDisc
import DeckieEngine
import DeckieTestSupport
@testable import DeckieDesk

/// A stand-in drive that takes its time over each part and counts the sectors it read, from any thread: a disc
/// being read while the song before it is analysed.
final class SlowDrive: SectorDevice, @unchecked Sendable {
    let inner: StandInDrive
    let pause: Double
    private let lock = NSLock()
    private var read = 0
    private var outFrom: Int?
    init(_ inner: StandInDrive, pause: Double) { self.inner = inner; self.pause = pause }
    var sectorsRead: Int { lock.lock(); defer { lock.unlock() }; return read }
    /// The disc comes out when a sector at or past `lba` is asked for.
    func takeOut(at lba: Int) { lock.lock(); outFrom = lba; lock.unlock() }
    func tocBytes() throws -> (bytes: [UInt8], format: Int) {
        lock.lock(); let out = outFrom == -1; lock.unlock()
        if out { throw DiscError("no disc") }
        return try inner.tocBytes()
    }
    func cdTextBytes() throws -> [UInt8] { try inner.cdTextBytes() }
    func audio(from lba: Int, sectors: Int) throws -> [UInt8] {
        Thread.sleep(forTimeInterval: pause)
        lock.lock()
        if let o = outFrom, o == -1 || lba >= o { outFrom = -1; lock.unlock(); throw DiscError("no disc") }
        read += sectors
        lock.unlock()
        return try inner.audio(from: lba, sectors: sectors)
    }
}

/// Reading a music CD once a song, in memory, with the next song read ahead (owner's items C and E, Nov 20, 2026).
@Suite struct ReadAheadTests {
    static func tone(seconds: Double, gain: Float) -> [Int16] {
        let n = Int(seconds * 44100)
        var out = [Int16](repeating: 0, count: n * 2)
        for i in 0..<n {
            let v = Int16(sin(Double(i) * 2 * .pi * 440 / 44100) * 12000 * Double(gain))
            out[2 * i] = v; out[2 * i + 1] = v
        }
        return out
    }

    func disc(_ name: String, pause: Double, seconds: [Double] = [6, 6, 6])
        throws -> (files: DiscSongFiles, drive: SlowDrive, songs: [SourceFile], home: DeskHome, toc: DiscTOC) {
        let root = try scratch(name)
        let folder = root.appendingPathComponent("E")
        try DiscFixture.writeStandIn(folder, songs: seconds.enumerated().map { Self.tone(seconds: $0.element, gain: 1 / Float($0.offset + 1)) },
                                     cdText: nil)
        let drive = SlowDrive(StandInDrive(folder: folder), pause: pause)
        let cd = SectorMusicCD(location: folder.path, device: drive)
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        let toc = try cd.tableOfContents()
        let record = DiscRecords.Record(toc: toc, reading: .none, fileExtension: cd.fileExtension)
        let files = DiscSongFiles(cd: cd, record: record, home: home, store: home.store, needsSignature: false, stop: BuildStop())
        return (files, drive, try files.list(), home, toc)
    }

    /// The next song is read while the one before is worked on, in memory: nothing goes to disk, and the song the
    /// builder then asks for is the one read ahead, not read a second time. Its bytes are the WAV the drive gives.
    @Test func theNextSongIsReadAheadInMemoryAndReadOnce() throws {
        let d = try disc("ahead", pause: 0.001)
        _ = try d.files.fetch(d.songs[0])
        let first = try #require(d.files.bytes(d.songs[0]))
        #expect(first.count == d.songs[0].size)
        #expect(d.files.bytes(d.songs[0]) == nil)     // handed over once
        d.files.readAhead(d.songs[1])
        #expect(d.files.readingAhead == "Track 02.wav")
        let url = try d.files.fetch(d.songs[1])        // waits for the read ahead
        #expect(d.files.readingAhead == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let second = try #require(d.files.bytes(d.songs[1]))
        #expect(second.count == d.songs[1].size)
        // Each song came off the disc once.
        #expect(d.drive.sectorsRead == d.toc.songs[0].sectors + d.toc.songs[1].sectors)
        var expected = Data()
        _ = try SectorMusicCD(location: "x", device: StandInDrive(folder: d.drive.inner.folder))
            .read(d.toc.songs[1], into: { expected.append($0) }, progress: { _, _ in })
        #expect(second == expected)
        #expect(musicFiles(under: d.home.root).isEmpty)
        d.files.release(d.songs[0]); d.files.release(d.songs[1])
        d.files.clear()
    }

    /// Stop, the end of the run, or another song asked for: the read ahead stops part way and leaves nothing.
    @Test func aReadAheadIsCancelledCleanly() throws {
        let d = try disc("cancel", pause: 0.01, seconds: [3, 30, 3])
        d.files.readAhead(d.songs[1])
        Thread.sleep(forTimeInterval: 0.15)
        let before = d.drive.sectorsRead
        #expect(before > 0 && before < d.toc.songs[1].sectors)
        d.files.cancelReadAhead()                      // returns once the read has stopped
        #expect(d.files.readingAhead == nil)
        let stopped = d.drive.sectorsRead
        Thread.sleep(forTimeInterval: 0.1)
        #expect(d.drive.sectorsRead == stopped)        // the drive is no longer being read
        #expect(stopped < d.toc.songs[1].sectors)
        #expect(musicFiles(under: d.home.root).isEmpty)

        // Stop asked for while a song is read ahead: it stops too, and nothing more is read ahead.
        d.files.readAhead(d.songs[1])
        Thread.sleep(forTimeInterval: 0.05)
        d.files.stop?.set()
        d.files.clear()
        let after = d.drive.sectorsRead
        Thread.sleep(forTimeInterval: 0.1)
        #expect(d.drive.sectorsRead == after)
        d.files.readAhead(d.songs[2])
        #expect(d.files.readingAhead == nil)

        // Another song asked for than the one read ahead: the read ahead is let go first, and only the song asked
        // for is read.
        let e = try disc("cancel-other", pause: 0.01, seconds: [3, 30, 3])
        e.files.readAhead(e.songs[1])
        Thread.sleep(forTimeInterval: 0.05)
        _ = try e.files.fetch(e.songs[2])
        #expect(e.files.readingAhead == nil)
        #expect(try #require(e.files.bytes(e.songs[2])).count == e.songs[2].size)
        e.files.clear()
    }

    /// No song longer than 15 minutes of sound is read ahead (it would sit in memory beside the song analysed).
    @Test func aLongSongIsNotReadAhead() throws {
        let root = try scratch("cap")
        let folder = root.appendingPathComponent("E")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let short = 75 * 60, long = 75 * Int(DiscSongFiles.readAheadMostSeconds) + 75
        try Data(DiscFixture.toc(starts: [0, short], leadOut: short + long)).write(to: folder.appendingPathComponent("toc.bin"))
        try Data(count: 2352 * 10).write(to: folder.appendingPathComponent("audio.pcm"))
        let drive = SlowDrive(StandInDrive(folder: folder), pause: 0.02)
        let cd = SectorMusicCD(location: folder.path, device: drive)
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        let toc = try cd.tableOfContents()
        #expect(toc.songs[1].seconds > DiscSongFiles.readAheadMostSeconds)
        let files = DiscSongFiles(cd: cd, record: DiscRecords.Record(toc: toc, reading: .none, fileExtension: "wav"),
                                  home: home, store: home.store, needsSignature: false)
        let songs = try files.list()
        files.readAhead(songs[1])
        #expect(files.readingAhead == nil)
        #expect(drive.sectorsRead == 0)
        files.readAhead(songs[0])                       // a minute: read ahead
        #expect(files.readingAhead == "Track 01.wav")
        files.clear()
        #expect(files.readingAhead == nil)
    }

    /// The disc taken out while the next song is read ahead: the builder is told when it asks for that song, as it
    /// would have been reading it then, and nothing is left.
    @Test func aDiscTakenOutDuringAReadAheadIsSaidWhenTheSongIsAskedFor() throws {
        let d = try disc("ahead-out", pause: 0.002)
        d.drive.takeOut(at: d.toc.songs[1].start + 100)
        d.files.readAhead(d.songs[1])
        #expect(throws: DiscError.self) { _ = try d.files.fetch(d.songs[1]) }
        #expect(d.files.bytes(d.songs[1]) == nil)
        d.files.clear()
        #expect(musicFiles(under: d.home.root).isEmpty)
    }

    /// The Mac's music CD (cddafs shows each song as an AIFF file) read in pieces: the bytes are the file's own, and
    /// the progress rises to the song's whole length.
    @Test func theMacsSongFileIsReadInPiecesWithProgress() throws {
        let root = try scratch("mac-pieces")
        let b = AudioBuffer(sampleRate: 44100, channelCount: 2, samples: Self.tone(seconds: 8, gain: 1).map { Float($0) / 32768 })
        let aiff = TestTrack.aiff16(b)
        try aiff.write(to: root.appendingPathComponent("1 Night drive.aiff"))
        let cd = MacMusicCD(volume: root)
        let toc = try cd.tableOfContents()
        var got = Data(), steps: [Int] = []
        _ = try cd.read(toc.songs[0], into: { got.append($0) }, progress: { done, total in steps.append(done); #expect(total == toc.songs[0].sectors) })
        #expect(got == aiff)
        #expect(steps.last == toc.songs[0].sectors && steps == steps.sorted())
    }
}

/// The names the finished screen and the run's line give for a disc named from its CD-Text (the hand test of Nov 20:
/// the crate held the disc's names, the report counted the file names).
@Suite struct DiscNamesReportTests {
    @Test func theReportCountsTheNamesTheCrateHolds() {
        var a = named("a", "Night drive", artist: "Artist A", from: "cdtext")
        var b = named("b", "Café Ünder", artist: "DJ Vera", from: "cdtext")
        a.ident.source = "cdtext"; b.ident.source = "cdtext"
        let user = named("c", "Mine", artist: "Me", from: "user")
        let c = Crate(manifest: crate([]).manifest, tracks: [a, b, user])
        var report = LocalFacts.Report()
        report.namesFrom = ["filename": 2]
        report.needName = 2
        DeskRun.recount(&report, before: ["a": "filename", "b": "filename", "c": "user"], crate: c)
        #expect(report.namesFrom == ["cdtext": 2])
        #expect(report.needName == 0)
    }

    @Test func theRunScreenShowsADiscSongByItsCDTextName() throws {
        let toc = try DiscTOC.format0(DiscFixture.toc(starts: [0, 300], leadOut: 600))
        var r = DiscRecords.Record(toc: toc, reading: .none, fileExtension: "aiff")
        r.titles = [1: "Night drive"]; r.performers = [1: "Artist A"]; r.discPerformer = "DJ Vera"
        let one = "Friday night/Track 01.aiff", two = "Friday night/Track 02.aiff"
        #expect(DiscSongFiles.shownName(rel: one, title: "Track 01", artist: nil, record: r) == ("Night drive", "Artist A"))
        #expect(DiscSongFiles.shownName(rel: one, title: "Tagged title", artist: "Tagged artist", record: r)
                == ("Tagged title", "Tagged artist"))
        #expect(DiscSongFiles.shownName(rel: two, title: "Track 02", artist: nil, record: r) == ("Track 02", nil))
    }
}

/// One read a song, and the same results: the analysis from bytes in memory is the analysis from the file, and the
/// print made from the analysis's own audio is the print made from the file (owner's item C, Nov 20, 2026).
@Suite(.enabled(if: Engine.available, "needs ONNX Runtime and the Beat This! model"))
struct OneReadSameResultTests {
    /// Every analysis field the crate file carries, as JSON, with the times of day left out.
    static func json(_ a: Analysis) throws -> String {
        var t = a.crateTrack(options: .init(analysedAt: "2026-11-20T00:00:00Z", device: "test"))
        t.analysis.secs = 0   // how long it took
        if var f = t.fingerprint { f.madeAt = "2026-11-20T00:00:00Z"; t.fingerprint = f }
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]
        return String(decoding: try e.encode(t), as: UTF8.self)
    }

    @Test func bytesInMemoryGiveTheSameAnalysisPrintTagsAndFacts() async throws {
        let root = try scratch("one-read")
        let buffer = TestTrack.render()
        let files = [("song.wav", TestTrack.wav(buffer)), ("1 Night drive.aiff", TestTrack.aiff16(buffer))]
        let analyser = try Builder.makeAnalyser(jobs: 1)
        for (name, bytes) in files {
            let url = root.appendingPathComponent(name)
            try bytes.write(to: url)
            let fromFile = try await CPUTurns.exclusive { try analyser.analyse(url: url) }
            final class Seen: @unchecked Sendable { var stages: [String] = []; var audio: AudioBuffer? }
            let seen = Seen()
            let inMemory = try await CPUTurns.exclusive {
                try analyser.analyse(url: url, bytes: FileBytes(bytes), sha256: nil, onStage: { seen.stages.append($0) },
                                     onDecoded: { seen.audio = $0 })
            }
            #expect(try Self.json(fromFile) == Self.json(inMemory))
            #expect(fromFile.id == inMemory.id && fromFile.id == CrateIDs.id(forFileBytes: bytes))
            #expect(fromFile.landmarks == inMemory.landmarks)
            let audio = try #require(seen.audio)
            #expect(try DeskRun.portablePrint(url) == DeskRun.portableAudioPrint(url, audio))
            #expect(Array(seen.stages.prefix(5)) == ["hash", "decode", "resample", "beatthis", "key"])
            #expect(seen.stages.last == "windows")
            #expect(FileTags.read(url) == FileTags.read(bytes: bytes))
            #expect(FileFacts.read(url) == FileFacts.read(bytes: bytes))
        }
    }

    /// A whole music CD through the run, as a PC reads it (by sector) and as a Mac does (the system's AIFF files):
    /// each song comes off the disc once, the song now is said step by step, the print is made from the analysis's
    /// audio and is the print of the song's own bytes, and the report's names are the crate's.
    @Test func aDiscRunReadsEachSongOnceAndSaysWhatItIsDoing() async throws {
        let root = try scratch("disc-once")
        let disc = root.appendingPathComponent("E")
        try MusicCDRunTests.makeDisc(disc, names: true)
        let drive = SlowDrive(StandInDrive(folder: disc), pause: 0)
        let open: (String) throws -> MusicCD = { _ in SectorMusicCD(location: disc.path, device: drive) }
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        let s = DeskSession(home: home)
        let (request, _) = try s.addMusicCDRequest(disc.path, open: open)
        let info = try s.crateForRun(request)
        let toc = try open(disc.path).tableOfContents()
        final class Seen: @unchecked Sendable { var now: [RunNow] = []; var titles: [String] = []; var counts: [Int] = [] }
        let seen = Seen()
        let run = DeskRun(home: home, crateId: info.id, request: request, jobs: 1, device: "test",
                          analyser: try Builder.makeAnalyser(jobs: 1), signer: nil, printer: { (_: URL) throws -> RecordingPrint in
                              Issue.record("the print was made from a file"); throw DiscError("no file")
                          }, audioPrinter: DeskRun.portableAudioPrint)
        run.openMusicCD = open
        run.findMusicCDs = { [] }
        let (c, report) = try await CPUTurns.exclusive {
            try run.run { p in
                if let n = p.now { seen.now.append(n) }
                if let t = p.song?.title { seen.titles.append(t) }
                seen.counts.append(p.done)
            }
        }
        s.runEnded(info.id)
        // Each song off the disc once (reading the table and text is not reading sound).
        #expect(drive.sectorsRead == toc.songs.reduce(0) { $0 + $1.sectors })
        #expect(report.printsMade == 2 && report.printsFailed == 0 && report.wentIn == 2)
        // The song now: taken, read off the disc to the end, then each analysis stage, for song 1 then song 2.
        for number in [1, 2] {
            let mine = seen.now.filter { $0.number == number }
            #expect(mine.first?.step == "started")
            let reads = mine.compactMap(\.read)
            #expect(!reads.isEmpty && reads == reads.sorted() && reads.last == 1)
            let stages = mine.map(\.step).filter { $0 != "started" && $0 != "reading" }
            #expect(Array(stages.prefix(4)) == ["hash", "decode", "resample", "beatthis"])
        }
        #expect(seen.counts == seen.counts.sorted())
        // The run screen, the report and the crate all have the disc's names.
        #expect(Set(seen.titles) == ["Night drive", "Café Ünder"])
        #expect(report.local?.report.namesFrom["filename"] == nil && report.local?.report.namesFrom["cdtext"] == 2)
        #expect(report.local?.report.needName == 0)
        // The prints are the prints of the songs' own bytes, as read off the disc.
        for t in c.tracks {
            let number = try #require(t.ident.track)
            var wav = Data()
            _ = try SectorMusicCD(location: "x", device: StandInDrive(folder: disc))
                .read(toc.songs[number - 1], into: { wav.append($0) }, progress: { _, _ in })
            #expect(CrateIDs.id(forFileBytes: wav) == t.id)
            let file = root.appendingPathComponent("song-\(number).wav")
            try wav.write(to: file)
            #expect(home.store.print(t.id) == (try DeskRun.portablePrint(file)))
        }
        #expect(musicFiles(under: home.root).isEmpty)
    }

    /// The Mac's way: the disc as the system's AIFF files, read once each into memory; the ids are the files' own.
    @Test func aMacDiscRunReadsTheSystemsFilesOnce() async throws {
        let root = try scratch("mac-disc")
        let volume = root.appendingPathComponent("Audio CD")
        try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: true)
        let b = TestTrack.render()
        let quiet = AudioBuffer(sampleRate: b.sampleRate, channelCount: b.channelCount, samples: b.samples.map { $0 * 0.5 })
        let songs = [("1 Night drive.aiff", TestTrack.aiff16(b)), ("2 Low tide.aiff", TestTrack.aiff16(quiet))]
        for (name, bytes) in songs { try bytes.write(to: volume.appendingPathComponent(name)) }
        let open: (String) throws -> MusicCD = { _ in MacMusicCD(volume: volume) }
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        let s = DeskSession(home: home)
        let (request, _) = try s.addMusicCDRequest(volume.path, open: open)
        let info = try s.crateForRun(request)
        let run = DeskRun(home: home, crateId: info.id, request: request, jobs: 1, device: "test",
                          analyser: try Builder.makeAnalyser(jobs: 1), signer: nil, printer: DeskRun.portablePrint,
                          audioPrinter: DeskRun.portableAudioPrint)
        run.openMusicCD = open
        run.findMusicCDs = { [] }
        let (c, report) = try await CPUTurns.exclusive { try run.run() }
        s.runEnded(info.id)
        #expect(report.wentIn == 2 && report.printsMade == 2)
        #expect(Set(c.tracks.map(\.id)) == Set(songs.map { CrateIDs.id(forFileBytes: $0.1) }))
        for (name, bytes) in songs {
            let id = CrateIDs.id(forFileBytes: bytes)
            #expect(home.store.print(id) == (try DeskRun.portablePrint(volume.appendingPathComponent(name))))
        }
    }
}
