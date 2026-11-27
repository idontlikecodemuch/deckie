import Foundation
import Testing
import DeckieAudio
import DeckieCrate
import DeckieBuild
import DeckieTestSupport
@testable import DeckieDesk

/// A Windows drive with no label (Nov 27, 2026): it was named by its letter and a colon ("E:"), so every song's path
/// in the crate ("E:/House/01 One.wav") looked like a path from the top of a disk, and the crate refused every song
/// after it was analysed. It is "Drive E" now; no source's name can make a song's path look like that; and a run with
/// such a name stops before it reads anything.
@Suite struct DriveNameTests {
    @Test func aDriveWithNoLabelIsNamedDriveAndItsLetter() {
        #expect(DeskDrives.name(label: "", letter: "E") == "Drive E")
        #expect(DeskDrives.name(label: nil, letter: "e") == "Drive E")
        #expect(DeskDrives.name(label: "  ", letter: "F") == "Drive F")
        // A label is kept as it is.
        #expect(DeskDrives.name(label: "STICK", letter: "E") == "STICK")
        #expect(DeskDrives.name(label: "Music 2", letter: "G") == "Music 2")
        for n in [DeskDrives.name(label: "", letter: "E"), DeskDrives.name(label: "USB", letter: "E")] {
            #expect(SourceReading.keepsPathsRelative(n), "\(n)")
        }
    }

    /// The name a source is settled under: ordinary names stay exactly as they are; only names that would break
    /// the paths of its songs change.
    @Test func wildNamesAreMadeSafeAndOrdinaryOnesKept() {
        for kept in ["USB", "Stick 3", "FRIDAY", "Music 12:30", "Disc (CD)", ".Music", "SSD.", "Drive E", " Stick "] {
            #expect(SourceReading.safeName(kept) == kept, "\(kept)")
        }
        let wild: [(String, String)] = [
            ("E:", "Drive E"), ("e:", "Drive E"), ("E:\\", "Drive E"), ("E:/", "Drive E"),
            ("A:B", "A-B"),             // a Mac folder Finder shows as "A/B"
            ("Stick/2", "Stick-2"), ("\\USB", "-USB"), ("/Music", "-Music"), ("C: live", "C- live"),
            ("", "Music"), ("   ", "Music"), (".", "Music"), ("..", "Music"), ("/", "-"),
        ]
        for (name, safe) in wild {
            let made = SourceReading.safeName(name)
            #expect(made == safe, "\(name) gave \(made)")
            #expect(SourceReading.isSafeName(made) && SourceReading.keepsPathsRelative(made), "\(made)")
        }
        #expect(!SourceReading.keepsPathsRelative("E:") && !SourceReading.keepsPathsRelative(""))
        #expect(SourceReading.name(volumeName: nil, folderName: "A:B") == "A-B")
        #expect(SourceReading.name(volumeName: "E:", folderName: "x") == "Drive E")
    }

    /// The chooser makes a name safe, and never reads into a source kept under a name its songs could not go in
    /// under, even the same drive's.
    @Test func aSourceKeptAsTheLetterAndAColonIsNotChosenAgain() {
        let root = URL(fileURLWithPath: "/Volumes/USB")
        let a = SourceIdentityTests.a
        let old = SourceNaming.Recorded(name: "E:", root: root, identity: a, files: [])
        #expect(SourceNaming.choose("E:", root: root, found: SourceIdentityTests.onA, recorded: [old]) == "Drive E")
        #expect(SourceNaming.choose("Drive E", root: root, found: SourceIdentityTests.onA, recorded: [old]) == "Drive E")
        // A source read before names were made safe, whose songs went in, stays that source.
        let slash = SourceNaming.Recorded(name: "Stick/2", root: root, identity: a, files: [])
        #expect(SourceNaming.choose("Stick/2", root: root, found: SourceIdentityTests.onA, recorded: [slash]) == "Stick/2")
    }

    /// The backstop: a run handed a source whose name breaks its songs' paths stops at once, with plain words, and
    /// reads nothing.
    @Test func aRunWithABadNameStopsBeforeItReadsAnything() throws {
        let root = try scratch("drive-name-stop")
        let drive = root.appendingPathComponent("Volumes/USB")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        try Data(repeating: 7, count: 10).write(to: drive.appendingPathComponent("01 One.wav"))
        let home = DeskHome(root: root.appendingPathComponent("home"))
        let info = try home.shelf.make(name: "Friday")
        let run = DeskRun(home: home, crateId: info.id, request: RunRequest(folder: drive, source: "E:"), jobs: 1,
                          device: "Mac15,6", signer: nil, printer: DeskRun.portablePrint)
        let progressed = Counter()
        #expect(throws: DeskError.self) { _ = try run.run { _ in progressed.add() } }
        do { _ = try run.run() } catch {
            #expect("\(error)" == "Songs can't be kept under the name E:, so Desk read nothing. "
                    + "Add the drive or folder again and Desk gives it a name that works.")
        }
        #expect(progressed.n == 0)
        #expect(!FileManager.default.fileExists(atPath: home.shelf.file(DeskRun.pendingFile, of: info.id).path))
    }

    final class Counter: @unchecked Sendable {
        let lock = NSLock()
        private(set) var n = 0
        func add() { lock.lock(); n += 1; lock.unlock() }
    }
}

/// A whole run of a drive with no label, through the record check, with a source kept as "E:" by a build before
/// Nov 27, 2026: the songs go in under "Drive E", and the old name is forgotten.
@Suite(.enabled(if: Engine.available, "needs ONNX Runtime and the Beat This! model"))
struct DriveWithNoLabelRunTests {
    @Test func songsOfADriveWithNoLabelGoIn() async throws {
        let root = try scratch("drive-name-run")
        let fm = FileManager.default
        let drive = root.appendingPathComponent("Volumes/USB")
        try fm.createDirectory(at: drive.appendingPathComponent("House"), withIntermediateDirectories: true)
        // The test track's first 16 s (a steady 124 BPM beat), at two levels: two songs, kept short.
        let buffer = TestTrack.render()
        let cut = Array(buffer.samples.prefix(16 * TestTrack.rate * buffer.channelCount))
        func song(_ gain: Float) -> Data {
            TestTrack.wav(AudioBuffer(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount, samples: cut.map { $0 * gain }))
        }
        try song(1).write(to: drive.appendingPathComponent("House/01 One.wav"))
        try song(0.7).write(to: drive.appendingPathComponent("02 Two.wav"))
        let a = SourceIdentityTests.a
        let identify: SourceIdentity.Reader = { _ in .init(identity: a, ownDisk: false) }

        let home = DeskHome(root: root.appendingPathComponent("home"))
        let s = DeskSession(home: home)
        // The crate as the build before had left it: a source "E:" for this drive, with no songs.
        var info = try home.shelf.make(name: "Friday")
        info.sourceRoots["E:"] = drive.path
        info.sourceIds["E:"] = a
        try home.shelf.save(info)
        _ = s.show(info.id)

        let request = s.addRequest(drive, name: DeskDrives.name(label: "", letter: "E"), identify: identify)
        #expect(request.source == "Drive E")
        let crateInfo = try s.crateForRun(request)
        let run = DeskRun(home: home, crateId: crateInfo.id, request: request, jobs: 1, device: "Mac15,6",
                          analyser: try Builder.makeAnalyser(jobs: 1), signer: nil, printer: DeskRun.portablePrint)
        run.identify = identify
        let (saved, report) = try await CPUTurns.exclusive { try run.run() }
        s.runEnded(crateInfo.id, saved: saved)

        #expect(report.wentIn == 2)
        let tracks = s.crate?.tracks ?? []
        #expect(tracks.count == 2 && tracks.allSatisfy { $0.ident.disc == "Drive E" })
        #expect(Set(tracks.compactMap(\.file.rel)) == ["House/01 One.wav", "02 Two.wav"])
        #expect(s.current?.sourceIds["Drive E"] == a)
        #expect(s.current?.sourceRoots["E:"] == nil && s.current?.sourceIds["E:"] == nil)
    }
}
