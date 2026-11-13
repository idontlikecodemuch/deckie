import Foundation
import Testing
import DeckieAudio
import DeckieBuild
import DeckieCrate
import DeckieEngine
import DeckieTestSupport

/// A source read as it is (D25, D26), on a made-up folder tree standing in for a USB stick, built into the same crate
/// as an ordinary folder on the Mac:
///
///   mac/Song X.wav               bytes X (only on the Mac, then also on the stick)
///   stick/House/02 Second.wav    bytes Y
///   stick/House/01 First.wav     bytes X: the same file as on the Mac
///   stick/_old/Parked.wav        bytes Z (a "_" folder, which a source does not leave out)
///   stick/.hidden.wav            a hidden file: never read
@Suite(.enabled(if: Available.engine, "needs ONNX Runtime and the Beat This! model"))
struct SourceBuildTests {
    @Test func aSourceIsReadAsItIsAndKeepsTheRestOfTheCrate() async throws {
        let analyser = try await Fixture.shared.analyser()
        let root = try temporaryFolder("source-build")
        try? FileManager.default.removeItem(at: root)
        let fm = FileManager.default
        let mac = root.appendingPathComponent("mac"), stick = root.appendingPathComponent("stick")
        for d in [mac, stick.appendingPathComponent("House"), stick.appendingPathComponent("_old")] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        let buffer = TestTrack.render()
        func scaled(_ g: Float) -> Data {
            TestTrack.wav(AudioBuffer(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount,
                                      samples: buffer.samples.map { $0 * g }))
        }
        let x = TestTrack.wav(buffer), y = scaled(0.5), z = scaled(0.25)
        try x.write(to: mac.appendingPathComponent("Song X.wav"))
        try y.write(to: stick.appendingPathComponent("House/02 Second.wav"))
        try x.write(to: stick.appendingPathComponent("House/01 First.wav"))
        try z.write(to: stick.appendingPathComponent("_old/Parked.wav"))
        try z.write(to: stick.appendingPathComponent(".hidden.wav"))
        let crateURL = root.appendingPathComponent("Night.deckiecrate")
        func id(_ d: Data) -> String { CrateIDs.id(forSHA256: CrateIDs.sha256(of: d)) }

        // 1. The Mac folder: one entry, no source.
        let one = try await CPUTurns.exclusive {
            try Builder(options: BuildOptions(folder: mac, output: crateURL, jobs: 2, fresh: true), analyser: analyser).run()
        }
        #expect(one.crate.tracks.count == 1)
        #expect(one.crate.tracks[0].ident.disc == nil)

        // 2. The stick as a source: three entries with their places; the copy of X on the stick takes the record
        // (a place on a source beats a folder on the Mac), and the Mac's copy is logged.
        let two = try await CPUTurns.exclusive {
            try Builder(options: BuildOptions(folder: stick, output: crateURL, jobs: 2, source: "Stick 3"),
                        analyser: analyser).run()
        }
        let c2 = try CrateReader.read(from: crateURL)
        #expect(c2.tracks.count == 3)
        func entry(_ c: Crate, _ d: Data) -> CrateTrack? { c.tracks.first { $0.id == id(d) } }
        let ex = try #require(entry(c2, x)), ey = try #require(entry(c2, y)), ez = try #require(entry(c2, z))
        #expect(ex.file.rel == "House/01 First.wav")
        #expect([ex.ident.disc, ex.ident.folder] == ["Stick 3", "House"] && ex.ident.track == 1)
        #expect([ey.ident.disc, ey.ident.folder] == ["Stick 3", "House"] && ey.ident.track == 2)
        #expect([ez.ident.disc, ez.ident.folder] == ["Stick 3", "_old"] && ez.ident.track == 1)
        let log2 = try #require(c2.manifest.importLog)
        #expect(log2.entries.map(\.rel) == ["Song X.wav"])
        #expect(log2.entries.first?.reason == CrateManifest.ImportLog.Reason.duplicate)
        #expect(log2.entries.first?.message == "the same bytes as Stick 3/House/01 First.wav, which has the record")
        #expect(two.filesSeen == 3 && log2.filesSeen == 4)

        // 3. The Mac folder again, keeping the stick: the stick's entries stay as they are, the Mac's copy is logged.
        _ = try await CPUTurns.exclusive {
            try Builder(options: BuildOptions(folder: mac, output: crateURL, jobs: 2, keepSources: ["Stick 3"]),
                        analyser: analyser).run()
        }
        let c3 = try CrateReader.read(from: crateURL)
        #expect(c3.tracks.count == 3)
        #expect(entry(c3, x)?.ident.disc == "Stick 3")
        #expect(c3.manifest.importLog?.entries.map(\.message) == ["the same bytes as Stick 3 / House 1, which has the record"])

        // 4. The stick read again after a file left it: its entries are what is on it now; the numbers are the
        // player's, counted over the files there.
        try fm.removeItem(at: stick.appendingPathComponent("House/02 Second.wav"))
        try y.write(to: stick.appendingPathComponent("House/00 Opener.wav"))
        _ = try await CPUTurns.exclusive {
            try Builder(options: BuildOptions(folder: stick, output: crateURL, jobs: 2, source: "Stick 3"),
                        analyser: analyser).run()
        }
        let c4 = try CrateReader.read(from: crateURL)
        #expect(c4.tracks.count == 3)
        #expect(entry(c4, y)?.file.rel == "House/00 Opener.wav" && entry(c4, y)?.ident.track == 1)
        #expect(entry(c4, x)?.ident.track == 2)
        #expect(c4.discPlan.map(\.name) == ["Stick 3"])
        #expect(c4.discPlan[0].folders.map(\.name) == ["House", "_old"])
    }
}
