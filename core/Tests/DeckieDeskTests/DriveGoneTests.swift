import Foundation
import Testing
import DeckieAudio
import DeckieCrate
import DeckieBuild
import DeckieEngine
import DeckieTestSupport
@testable import DeckieDesk

/// A drive taken out part-way through a run (the hand test of Nov 25, 2026): the songs it had not read yet were listed
/// as "Could not be decoded", and the run ended with a tick and "That's the lot". Now they are `source_gone`, "The
/// drive was taken out", and the run ends saying so; a file that cannot be read while its drive is there is still the
/// file's own problem. No real drive: the folder read is moved away part-way, at a point the run itself reaches.
@Suite struct DriveGoneTests {
    typealias R = CrateManifest.ImportLog.Reason

    /// What tells a drive gone from a file that cannot be read: the folder read and the file's own folder.
    @Test func aDriveGoneIsToldFromAFileThatCannotBeRead() throws {
        let fm = FileManager.default
        let top = try scratch("gone")
        let stick = top.appendingPathComponent("Stick")
        try fm.createDirectory(at: stick.appendingPathComponent("House"), withIntermediateDirectories: true)
        let song = stick.appendingPathComponent("House/01 Song.wav"), other = stick.appendingPathComponent("02 Other.wav")
        try Data("x".utf8).write(to: song)
        try Data("y".utf8).write(to: other)
        #expect(!FileFailure.placeIsGone(root: stick, file: song))
        // The file alone is gone, its folder and the drive are there: the file is blamed.
        try fm.removeItem(at: song)
        #expect(!FileFailure.placeIsGone(root: stick, file: song))
        #expect(!FileFailure.placeIsGone(root: stick, file: other))
        // Its folder is gone.
        try fm.removeItem(at: stick.appendingPathComponent("House"))
        #expect(FileFailure.placeIsGone(root: stick, file: song))
        // The drive's top is still there but empty, as a mount point left behind.
        try fm.removeItem(at: other)
        #expect(FileFailure.placeIsGone(root: stick, file: other))
        // The drive's top is gone, or is not a folder that can be listed.
        try fm.moveItem(at: stick, to: top.appendingPathComponent("Away"))
        #expect(FileFailure.placeIsGone(root: stick, file: other))
        try Data("not a folder".utf8).write(to: stick)
        #expect(FileFailure.placeIsGone(root: stick, file: other))
    }

    /// A drive's words for a drive, a folder's for a folder: what was asked to be read says which.
    @Test func aFolderMovedIsSaidAsAFolder() throws {
        let top = try scratch("which")
        let stick = top.appendingPathComponent("Stick")
        try FileManager.default.createDirectory(at: stick.appendingPathComponent("House"), withIntermediateDirectories: true)
        // A folder somewhere is no drive; one the drive list names (here a stand-in list) is.
        #expect(!DeskDrives.readsADrive(stick.appendingPathComponent("House"), environment: [:]))
        #expect(DeskDrives.readsADrive(stick, environment: [DeskDrives.standInVariable: top.path]))
        #expect(!DeskDrives.readsADrive(stick.appendingPathComponent("House"), environment: [DeskDrives.standInVariable: top.path]))
        #expect(FileFailure.gone(drive: true).reason == R.sourceGone && FileFailure.gone(drive: false).reason == R.folderGone)
        #expect(DeskWords.coded("reason", R.folderGone) == "The folder was moved or removed")
        #expect(DeskWords.text("goneTitle.folder") == "Stopped: the folder was moved or removed")
        #expect(DeskWords.count("goneBody.folder", 3) == "3 songs were not read. Put the folder back and add it again to read the rest.")
    }

    @Test func theNewReasonHasItsWords() {
        #expect(R.all.contains(R.sourceGone) && R.sourceGone == "source_gone")
        #expect(DeskWords.coded("reason", R.sourceGone) == "The drive was taken out")
        #expect(DeskWords.coded("reason", R.decodeError) == "Could not be decoded")
        #expect(DeskWords.text("goneTitle") == "Stopped: the drive was taken out")
        #expect(DeskWords.count("goneBody", 8) == "8 songs were not read. Plug it back in and add it again to read the rest.")
        #expect(DeskWords.count("goneBody", 1) == "1 song was not read. Plug it back in and add it again to read the rest.")
    }

    /// The run on a made-up stick:
    ///
    ///   S/House/00 broken.mp3   an ID3 tag and no audio: damaged, whatever happens to the drive
    ///   S/House/01 Song X.wav   the drive is taken out while it is analysed: its analysis ends from the bytes read,
    ///                           but its signature (made from the file) cannot be, so it is source_gone, not half made
    ///   S/House/02 Song Y.wav   not reached before the drive went: source_gone
    ///
    /// Then the drive is put back with a fourth file, and added again: X is finished from its kept analysis, only Y is
    /// analysed, and the fourth, deleted while Y is analysed with the drive there, is the file's own problem:
    /// decode_error.
    @Test(.enabled(if: Engine.available, "needs ONNX Runtime and the Beat This! model"))
    func aDriveTakenOutPartWaySaysSoAndAddingItAgainReadsTheRest() async throws {
        let fm = FileManager.default
        let root = try scratch("drive-gone")
        let stick = root.appendingPathComponent("S"), away = root.appendingPathComponent("S (taken out)")
        let house = stick.appendingPathComponent("House")
        try fm.createDirectory(at: house, withIntermediateDirectories: true)
        let buffer = TestTrack.render()
        let x = TestTrack.wav(buffer)
        let y = TestTrack.wav(AudioBuffer(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount,
                                          samples: buffer.samples.map { $0 * 0.5 }))
        try Data(Array("ID3".utf8) + [3, 0, 0, 0, 0, 0, 0] + Array("not audio at all".utf8))
            .write(to: house.appendingPathComponent("00 broken.mp3"))
        try x.write(to: house.appendingPathComponent("01 Song X.wav"))
        try y.write(to: house.appendingPathComponent("02 Song Y.wav"))

        // The run's own step while a song is analysed: the song's decoded audio, handed over on the analysing
        // thread (one job, so the songs go in order). That is where the drive is taken out, or a file deleted.
        final class Hook: @unchecked Sendable {
            let lock = NSLock()
            var action: ((URL) -> Void)?
            func run(_ url: URL) { lock.lock(); let a = action; action = nil; lock.unlock(); a?(url) }
        }
        let hook = Hook()
        final class Notes: @unchecked Sendable {
            let lock = NSLock(); var all: [RunNote] = []; var lines: [RunLine] = []
            func add(_ p: RunProgress) { lock.lock(); all += p.notes; if let l = p.line { lines.append(l) }; lock.unlock() }
        }
        let home = DeskHome(root: root.appendingPathComponent("home"))
        let analyser = try Builder.makeAnalyser(jobs: 1)
        let printer: DeskRun.AudioPrintMaker = { url, audio in
            hook.run(url)
            return DeskRun.portableAudioPrint(url, audio)
        }
        // A signature made from the song's file after its analysis, as the Mac's is (ShazamKit reads the file).
        let signer: DeskRun.SignatureMaker = { url in Data("sig ".utf8) + (try Data(contentsOf: url)).prefix(64) }
        let info = try home.shelf.make(name: "Night")
        func run(_ notes: Notes) throws -> (crate: Crate, report: RunReport) {
            let r = DeskRun(home: home, crateId: info.id, request: RunRequest(folder: stick, source: "S"), jobs: 1,
                            device: "Mac15,6", analyser: analyser, signer: signer, printer: DeskRun.portablePrint,
                            audioPrinter: printer)
            r.readsADrive = true   // a stick: a made-up one is a folder, which `DeskDrives.readsADrive` would say
            return try r.run(progress: { notes.add($0) })
        }

        // 1. Taken out while X is analysed. X's analysis ends from the bytes already read, but its signature, made
        // from its file after that, cannot be: X is not kept half made, it is not read for the drive gone, as Y is.
        hook.action = { url in
            #expect(url.lastPathComponent == "01 Song X.wav")
            try? fm.moveItem(at: stick, to: away)
        }
        let notes1 = Notes()
        let one = try await CPUTurns.exclusive { try run(notes1) }
        #expect(one.report.notIn == [R.damaged: 1, R.sourceGone: 2], "\(one.report.notIn)")
        #expect(one.report.wentIn == 0 && one.report.analysed == 1 && one.report.notReadGone == 2)
        #expect(one.report.songsRead == 0 && one.crate.tracks.isEmpty)
        let log = try #require(one.crate.manifest.importLog)
        #expect(log.entries.map(\.rel) == ["S/House/00 broken.mp3", "S/House/01 Song X.wav", "S/House/02 Song Y.wav"])
        #expect(log.entries.map(\.reason) == [R.damaged, R.sourceGone, R.sourceGone])
        #expect(log.tracks == 0)
        #expect(!log.entries.contains { $0.message.contains(root.path) })
        #expect(try CrateReader.read(from: home.shelf.package(info.id)).tracks.isEmpty)
        // No "That's the lot", no tick: the finished screen's words (both windows read them from the report).
        #expect(!notes1.all.contains { $0.code == "finished" })
        #expect(one.report.stopped == nil && !one.report.goneWasFolder)
        #expect(one.report.goneTitle == "Stopped: the drive was taken out")
        #expect(one.report.goneBody == "2 songs were not read. Plug it back in and add it again to read the rest.")
        #expect(DeskWords.text("reasonCount", ["reason": DeskWords.coded("reason", R.sourceGone), "n": "2"])
                == "The drive was taken out (2)")
        #expect(notes1.lines.contains { if case .file("S/House/02 Song Y.wav", .failed(let f)) = $0 { f.reason == R.sourceGone } else { false } })

        // 2. Put back, with a fourth file, and added again: X is finished now from its kept analysis (signed, not
        // analysed again) and Y is read (a drive gone is never a lasting result); the fourth file is deleted while Y
        // is analysed, the drive still there: the file's own problem, "Could not be decoded".
        try fm.moveItem(at: away, to: stick)
        try TestTrack.wav(AudioBuffer(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount,
                                      samples: buffer.samples.map { $0 * 0.25 }))
            .write(to: house.appendingPathComponent("03 Song Z.wav"))
        hook.action = { url in
            #expect(url.lastPathComponent == "02 Song Y.wav")
            try? fm.removeItem(at: house.appendingPathComponent("03 Song Z.wav"))
        }
        let notes2 = Notes()
        let two = try await CPUTurns.exclusive { try run(notes2) }
        #expect(two.report.analysed == 1 && two.report.notReadGone == 0)
        #expect(two.report.notIn == [R.damaged: 1, R.decodeError: 1], "\(two.report.notIn)")
        #expect(Set(two.crate.tracks.map(\.file.rel)) == ["House/01 Song X.wav", "House/02 Song Y.wav"])
        #expect(two.crate.tracks.allSatisfy { $0.signatures["o"] != nil && $0.fingerprint != nil }, "every song whole")
        #expect(DeskWords.coded("reason", R.decodeError) == "Could not be decoded")
        // Nothing was lost to a drive this time: the run ends as it always did.
        #expect(notes2.all.contains { $0.code == "finished" })
    }
}
