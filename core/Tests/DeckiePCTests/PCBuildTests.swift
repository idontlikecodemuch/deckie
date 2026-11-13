import Foundation
import Testing
import DeckieAudio
import DeckieBuild
import DeckieCrate
import DeckiePC
import DeckieTestSupport

// The run behind the PC program: where things go, the words, the log, the single file, and a second run.

private func scratch(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("deckie-pc-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString.prefix(8))")
        .appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let engineFiles: PCBuild.EngineFiles? = {
    do { return try PCBuild.EngineFiles.locate(beside: nil) } catch {
        print("the PC program's engine tests are skipped: \(error)")
        return nil
    }
}()

private final class Lines: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [String] = []
    func add(_ s: String) { lock.lock(); list.append(s); lock.unlock() }
    var text: String { lock.lock(); defer { lock.unlock() }; return list.joined(separator: "\n") }
}

@Suite struct PCPlanTests {
    @Test func theCrateFileGoesNextToTheMusicFolderNamedAfterIt() throws {
        let root = try scratch("plan")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let music = root.appendingPathComponent("My M\u{fc}sic 2024")
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let plan = try PCBuild.plan(folder: music, workRoot: root.appendingPathComponent("work"))
        #expect(plan.name == "My M\u{fc}sic 2024")
        #expect(plan.crateFile.lastPathComponent == "My M\u{fc}sic 2024.deckiecrate")
        #expect(plan.logFile.lastPathComponent == "My M\u{fc}sic 2024 Deckie log.txt")
        #expect(plan.crateFile.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path)
        #expect(!plan.elsewhere)
        // Never inside the music folder, and the work is not beside the music.
        #expect(plan.crateFile.deletingLastPathComponent().standardizedFileURL.path != music.standardizedFileURL.path)
        #expect(plan.work.deletingLastPathComponent().lastPathComponent == "work")
        // Two folders with one name in different places do not share their storage.
        let other = root.appendingPathComponent("elsewhere").appendingPathComponent("My M\u{fc}sic 2024")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        #expect(try PCBuild.plan(folder: other, workRoot: root.appendingPathComponent("work")).work != plan.work)
    }

    @Test func aMissingFolderAndAFileAreSaidPlainly() throws {
        let root = try scratch("plan-errors")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        #expect(throws: PCError.self) { try PCBuild.plan(folder: root.appendingPathComponent("nope"), workRoot: root) }
        let file = root.appendingPathComponent("song.mp3")
        try Data([1]).write(to: file)
        #expect(throws: PCError.isAFile("song.mp3")) { try PCBuild.plan(folder: file, workRoot: root) }
        #expect(PCError.isAFile("song.mp3").words.contains("is a file, not a folder"))
    }

    @Test func theWordsAreInTheVoice() {
        // Plain, sentence case, "songs" not "tracks", never "AI" (docs/product/voice.md).
        let all = [PCWords.hello(version: "1"), PCWords.askForFolder, PCWords.found(songs: 3, toRead: 3),
                   PCWords.found(songs: 3, toRead: 0), PCWords.found(songs: 3, toRead: 1), PCWords.done(songs: 1),
                   PCWords.notYet, PCWords.interrupted, PCWords.copies(2), PCWords.damagedSpots(1), PCWords.took(400),
                   PCWords.partsMissing("x"), PCWords.inTheWay("x"), PCWords.noSongs("x")]
            + ["unsupported", "protected", "damaged", "decode_error", "analysis_error", "duplicate"].flatMap { r in
                ["m4a", "wma", "ogg", "mp3"].map { PCWords.why(reason: r, ext: $0) }
            }
        for line in all {
            #expect(!line.lowercased().contains("track"), "\(line)")
            #expect(!line.contains("AI") && !line.contains("!"), "\(line)")
        }
        #expect(PCWords.timeLeft(30).hasPrefix("under a minute left"))
        #expect(PCWords.timeLeft(600).hasPrefix("about 10 minutes left"))
        #expect(PCWords.timeLeft(3 * 3600).hasPrefix("about 3.0 hours left"))
        #expect(PCWords.found(songs: 1, toRead: 1).hasPrefix("Found 1 music file."))
    }
}

@Suite(.enabled(if: engineFiles != nil, "needs ONNX Runtime and the Beat This! model (core/README.md)"))
struct PCBuildTests {
    /// A music folder: the test track as WAV and FLAC in a nested folder, a file of a type not read everywhere yet, a
    /// protected one, and one that is too short.
    func music(_ root: URL) throws -> URL {
        let folder = root.appendingPathComponent("Friday Set")
        let fm = FileManager.default
        let deep = folder.appendingPathComponent("Warm up").appendingPathComponent("Deep")
        try fm.createDirectory(at: deep, withIntermediateDirectories: true)
        let track = TestTrack.render()
        try TestTrack.wav(track).write(to: folder.appendingPathComponent("Warm up").appendingPathComponent("One.wav"))
        try FLACWriter.flac16(track).write(to: deep.appendingPathComponent("Zw\u{f6}lf.flac"))
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DeckieDecodeTests").appendingPathComponent("Fixtures")
        // The start of an Ogg stream that is not FLAC (Opus), which no platform's decoder here reads.
        try Data(Array("OggS".utf8) + [UInt8](repeating: 0, count: 24) + Array("OpusHead".utf8) + [UInt8](repeating: 0, count: 64))
            .write(to: folder.appendingPathComponent("old.opus"))
        try fm.copyItem(at: fixtures.appendingPathComponent("protected.m4p"), to: folder.appendingPathComponent("locked.m4p"))
        try fm.copyItem(at: fixtures.appendingPathComponent("tone.mp3"), to: folder.appendingPathComponent("jingle.mp3"))
        return folder
    }

    @Test func aFolderBecomesOneCrateFileWithALogAndASecondRunReadsNothing() throws {
        let root = try scratch("run")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let folder = try music(root)
        let plan = try PCBuild.plan(folder: folder, workRoot: root.appendingPathComponent("storage"))
        let said = Lines()
        let outcome = try PCBuild.run(plan, engine: engineFiles!, jobs: 2) { said.add($0) }

        // One file next to the music folder, in the single-file form, that the core's validator reads.
        #expect(CrateArchive.isArchive(plan.crateFile))
        let crate = try CrateReader.read(from: plan.crateFile)
        #expect(crate.manifest.name == "Friday Set")
        #expect(crate.tracks.compactMap(\.file.rel).sorted() == ["Warm up/Deep/Zw\u{f6}lf.flac", "Warm up/One.wav"])
        #expect(outcome.songs == 2 && outcome.filesFound == 5 && outcome.readNow == 2)
        // Nothing else appears beside the music, and nothing inside it.
        let beside = try FileManager.default.contentsOfDirectory(atPath: root.path).sorted()
        #expect(beside == ["Friday Set", "Friday Set Deckie log.txt", "Friday Set.deckiecrate", "storage"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["Warm up", "jingle.mp3", "locked.m4p", "old.opus"])

        // What did not go in, by reason and type, in plain words.
        let reasons = Dictionary(uniqueKeysWithValues: outcome.notAdded.map { ($0.ext, $0.reason) })
        #expect(reasons == ["m4p": "protected", "mp3": "analysis_error", "opus": "unsupported"])
        let summary = PCBuild.summary(outcome)
        #expect(summary.contains("Done. 2 songs are in the crate file."))
        #expect(summary.contains("3 files could not be added:"))
        #expect(summary.contains("1  Ogg and Opus files (.opus) cannot be read by this version yet (opus 1)"))
        #expect(summary.contains("copy-protected"))
        #expect(summary.contains(plan.crateFile.path))
        #expect(said.text.contains("Found 5 music files. Reading them now."))
        #expect(said.text.contains("of 5") && said.text.contains("Zw\u{f6}lf.flac"))

        // The log: counts and the files not added by their path below the folder; not the songs that went in, and
        // not the folder's own path.
        let log = try String(contentsOf: plan.logFile, encoding: .utf8)
        #expect(log.contains("songs in the crate file: 2") && log.contains("files not added: 3"))
        #expect(log.contains("unsupported  old.opus") && log.contains("protected  locked.m4p"))
        #expect(!log.contains("One.wav") && !log.contains("Zw\u{f6}lf"))
        #expect(!log.contains(root.path))
        #expect(log.contains("\r\n"))

        // A second run reads nothing again and writes the same crate file (same id, same songs).
        let again = Lines()
        let second = try PCBuild.run(plan, engine: engineFiles!, jobs: 2) { again.add($0) }
        #expect(second.readNow == 0 && second.songs == 2)
        #expect(again.text.contains("Nothing has changed since last time."))
        let crate2 = try CrateReader.read(from: plan.crateFile)
        #expect(crate2.manifest.crateId == crate.manifest.crateId)
        #expect(crate2.tracks == crate.tracks)

        // A new song is the only one read on the next run.
        let half = AudioBuffer(sampleRate: TestTrack.rate, channelCount: 2, samples: TestTrack.render().samples.map { $0 * 0.5 })
        try TestTrack.wav(half).write(to: folder.appendingPathComponent("New.wav"))
        let third = try PCBuild.run(plan, engine: engineFiles!, jobs: 2) { _ in }
        #expect(third.readNow == 1 && third.songs == 3)

        // With the program's storage gone (another PC, a cleared profile), the crate file itself carries the crate's
        // id on; the songs are read again.
        try FileManager.default.removeItem(at: root.appendingPathComponent("storage"))
        let fourth = try PCBuild.run(plan, engine: engineFiles!, jobs: 2) { _ in }
        #expect(fourth.readNow == 3 && fourth.songs == 3)
        #expect(try CrateReader.read(from: plan.crateFile).manifest.crateId == crate.manifest.crateId)
    }

    @Test func somethingElseUnderTheCrateFilesNameIsNeverOverwritten() throws {
        let root = try scratch("in-the-way")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let folder = try music(root)
        let plan = try PCBuild.plan(folder: folder, workRoot: root.appendingPathComponent("storage"))
        try Data("my notes".utf8).write(to: plan.crateFile)
        #expect(throws: PCError.inTheWay("Friday Set.deckiecrate")) {
            try PCBuild.run(plan, engine: engineFiles!, jobs: 1) { _ in }
        }
        #expect(try Data(contentsOf: plan.crateFile) == Data("my notes".utf8))
        // The log says why nothing was written.
        #expect(try String(contentsOf: plan.logFile, encoding: .utf8).contains("result: stopped without writing a crate file"))
    }

    @Test func aFolderWithNoMusicIsSaidPlainly() throws {
        let root = try scratch("empty")
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        let folder = root.appendingPathComponent("Photos")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data([1]).write(to: folder.appendingPathComponent("a.jpg"))
        let plan = try PCBuild.plan(folder: folder, workRoot: root.appendingPathComponent("storage"))
        #expect(throws: PCError.noSongs("Photos")) { try PCBuild.run(plan, engine: engineFiles!, jobs: 1) { _ in } }
        #expect(!FileManager.default.fileExists(atPath: plan.crateFile.path))
    }
}
