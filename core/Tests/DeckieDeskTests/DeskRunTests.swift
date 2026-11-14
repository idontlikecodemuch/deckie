import Foundation
import Testing
import DeckieAudio
import DeckieCrate
import DeckieBuild
import DeckieEngine
import DeckieTestSupport
@testable import DeckieDesk

enum Engine {
    static let available: Bool = (try? Builder.checkEngine()) != nil
}

/// The one run on two made-up sticks, A and B, read into one crate and then into a second:
///
///   A/House/01 Song X.wav    bytes X
///   A/House/02 Song Y.wav    bytes Y
///   B/Set/01 Song X.wav      bytes X: the same file as on A
@Suite(.enabled(if: Engine.available, "needs ONNX Runtime and the Beat This! model"))
struct DeskRunTests {
    @Test func oneRunReadsSignsPrintsKeepsFixesAndSharesWhatItWorkedOut() async throws {
        let root = try scratch("run")
        let fm = FileManager.default
        let a = root.appendingPathComponent("A"), b = root.appendingPathComponent("B")
        try fm.createDirectory(at: a.appendingPathComponent("House"), withIntermediateDirectories: true)
        try fm.createDirectory(at: b.appendingPathComponent("Set"), withIntermediateDirectories: true)
        let buffer = TestTrack.render()
        let x = TestTrack.wav(buffer)
        let y = TestTrack.wav(AudioBuffer(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount,
                                          samples: buffer.samples.map { $0 * 0.5 }))
        try x.write(to: a.appendingPathComponent("House/01 Song X.wav"))
        try y.write(to: a.appendingPathComponent("House/02 Song Y.wav"))
        try x.write(to: b.appendingPathComponent("Set/01 Song X.wav"))
        let idX = CrateIDs.id(forFileBytes: x), idY = CrateIDs.id(forFileBytes: y)

        let home = DeskHome(root: root.appendingPathComponent("home"))
        let analyser = try Builder.makeAnalyser(jobs: 2)
        let signer: DeskRun.SignatureMaker = { url in Data("sig of \(url.lastPathComponent)".utf8) }
        func run(_ crate: CrateInfo, _ folder: URL, _ source: String) throws -> (crate: Crate, report: RunReport) {
            try DeskRun(home: home, crateId: crate.id, request: RunRequest(folder: folder, source: source), jobs: 2,
                        device: "Mac15,6", analyser: analyser, signer: signer, printer: DeskRun.portablePrint).run()
        }

        // 1. A into a new crate: read, signed and printed in one run.
        let night = try home.shelf.make(name: "A")
        let one = try await CPUTurns.exclusive { try run(night, a, "A") }
        #expect(one.report.songsSeen == 2 && one.report.wentIn == 2 && one.report.analysed == 2)
        #expect(one.report.signaturesMade == 2 && one.report.printsMade == 2)
        #expect(one.crate.tracks.allSatisfy { $0.signatures["o"] != nil })
        #expect(fm.fileExists(atPath: home.shelf.package(night.id).appendingPathComponent("signatures/\(idX)_o.shazamsignature").path))
        #expect(DeskRun.pending(home: home, crateId: night.id) == nil)
        #expect(DeskRun.runs(home: home, crateId: night.id).count == 1)
        #expect(one.report.songsPerMinute > 0)
        // A folder is read where it is: no song of it is copied into Desk's storage (the note on D33, Nov 14).
        #expect(musicFiles(under: home.root).isEmpty)

        // 2. The DJ fixes X's name; B is added: X gains B's place, nothing is analysed again, and the fix stays.
        var fixes = NameCorrections()
        var fixed = one.crate
        let ix = try #require(fixed.tracks.firstIndex { $0.id == idX })
        fixed.tracks[ix].ident.title = "Song X (fixed)"
        fixes.note(from: one.crate, to: fixed)
        try fixes.save(to: home.shelf.file(DeskRun.correctionsFile, of: night.id))
        let two = try await CPUTurns.exclusive { try run(night, b, "B") }
        #expect(two.report.analysed == 0 && two.report.signaturesMade == 0 && two.report.printsMade == 0)
        let x2 = try #require(two.crate.tracks.first { $0.id == idX })
        #expect(x2.ident.title == "Song X (fixed)")
        #expect(x2.ident.allPlaces.compactMap(\.disc).sorted() == ["A", "B"])

        // 3. A is read again without X: X's own place moves to B, its path is filled from what the desk remembered,
        // and its file is found there. The fix is kept across the re-read.
        try fm.removeItem(at: a.appendingPathComponent("House/01 Song X.wav"))
        let three = try await CPUTurns.exclusive { try run(night, a, "A") }
        let x3 = try #require(three.crate.tracks.first { $0.id == idX })
        #expect(x3.ident.disc == "B" && x3.file.rel == "Set/01 Song X.wav")
        #expect(x3.ident.title == "Song X (fixed)")
        let paths = PlacePaths.load(from: home.shelf.file(DeskRun.placesFile, of: night.id))
        let info = try #require(home.shelf.info(night.id))
        #expect(paths.locate(x3, roots: info.roots, musicFolder: nil) == b.appendingPathComponent("Set/01 Song X.wav"))

        // 4. A second crate from A: nothing is analysed, signed or printed again.
        let other = try home.shelf.make(name: "Other")
        let four = try await CPUTurns.exclusive { try run(other, a, "A") }
        #expect(four.report.analysed == 0 && four.report.reused == 1)
        #expect(four.report.signaturesMade == 0 && four.report.signaturesKept == 1 && four.report.printsMade == 0)
        #expect(four.crate.tracks.map(\.id) == [idY])
        #expect(home.shelf.mostRecent?.id == other.id)

        // 5. A run that was stopped (its pending note left behind) is carried on.
        try JSONFile.write(RunRequest(folder: b, source: "B"), to: home.shelf.file(DeskRun.pendingFile, of: other.id))
        #expect(DeskRun.pending(home: home, crateId: other.id)?.source == "B")
        let five = try await CPUTurns.exclusive { try run(other, b, "B") }
        #expect(five.report.carriedOn && five.report.analysed == 0)
        #expect(DeskRun.pending(home: home, crateId: other.id) == nil)
    }

    /// The rekordbox route reads the folder chosen as a source like any folder added (D31): its places carry the
    /// source's name, the folders inside it are its groups, where it was read from is kept as that source's top, and
    /// rekordbox's entries are still matched by the path below the folder, even when the source is not named as the
    /// folder is in rekordbox's paths ("Music 2", made unique) and rekordbox knew the music under another home.
    @Test func theRekordboxRouteReadsTheFolderAsASource() async throws {
        let root = try scratch("rekordbox-source")
        let fm = FileManager.default
        let music = root.appendingPathComponent("Music")
        try fm.createDirectory(at: music.appendingPathComponent("House"), withIntermediateDirectories: true)
        try TestTrack.wav(TestTrack.render()).write(to: music.appendingPathComponent("House/01 Song X.wav"))
        let xml = root.appendingPathComponent("collection.xml")
        try Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <DJ_PLAYLISTS Version="1.0.0">
              <PRODUCT Name="rekordbox" Version="6.8.5" Company="AlphaTheta"/>
              <COLLECTION Entries="1">
                <TRACK TrackID="7" Name="Named By Rekordbox" Artist="The Synths" AverageBpm="124.00" Tonality="Am"
                       Location="file://localhost/Users/someone/Music/House/01%20Song%20X.wav"/>
              </COLLECTION>
            </DJ_PLAYLISTS>
            """.utf8).write(to: xml)

        let home = DeskHome(root: root.appendingPathComponent("home"))
        let crate = try home.shelf.make(name: "Friday")
        let analyser = try Builder.makeAnalyser(jobs: 1)
        let request = RunRequest(folder: music, source: "Music 2", rekordbox: xml)
        let (out, report) = try await CPUTurns.exclusive {
            try DeskRun(home: home, crateId: crate.id, request: request, jobs: 1, device: "Mac15,6", analyser: analyser,
                        signer: { _ in Data("sig".utf8) }, printer: DeskRun.portablePrint).run()
        }
        #expect(report.read == "Music 2" && report.wentIn == 1)
        let t = try #require(out.tracks.first)
        #expect(t.ident.disc == "Music 2" && t.ident.folder == "House" && t.ident.track == 1)
        #expect(t.file.rel == "House/01 Song X.wav")
        #expect(t.ident.title == "Named By Rekordbox" && t.ident.artist == "The Synths")
        #expect(t.imported?.rekordbox?.trackId == "7")
        #expect(out.discPlan.map(\.name) == ["Music 2"])
        let info = try #require(home.shelf.info(crate.id))
        #expect(info.sourceRoots["Music 2"] == music.path && info.musicFolder == nil)
    }
}
