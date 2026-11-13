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

        // 2. The stick as a source: three entries with their places. X was in the crate from the Mac: the place read
        // on the stick leads (a source before a folder on the Mac) and becomes its own place, with its file's path;
        // the Mac's folder stays as an other place (D27), and nothing is logged as a duplicate.
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
        #expect(ex.ident.otherPlaces == [CrateTrack.Place(disc: nil, folder: "", track: nil)])
        #expect([ey.ident.disc, ey.ident.folder] == ["Stick 3", "House"] && ey.ident.track == 2)
        #expect([ez.ident.disc, ez.ident.folder] == ["Stick 3", "_old"] && ez.ident.track == 1)
        #expect(ey.ident.otherPlaces.isEmpty && ez.ident.otherPlaces.isEmpty)
        let log2 = try #require(c2.manifest.importLog)
        #expect(log2.entries.isEmpty)
        #expect(two.filesSeen == 3 && log2.filesSeen == 4)

        // 3. The Mac folder again, keeping the stick: the stick's entries stay as they are, and the Mac's copy is X's
        // other place again, read now.
        _ = try await CPUTurns.exclusive {
            try Builder(options: BuildOptions(folder: mac, output: crateURL, jobs: 2, keepSources: ["Stick 3"]),
                        analyser: analyser).run()
        }
        let c3 = try CrateReader.read(from: crateURL)
        #expect(c3.tracks.count == 3)
        #expect(entry(c3, x)?.ident.disc == "Stick 3" && entry(c3, x)?.file.rel == "House/01 First.wav")
        #expect(entry(c3, x)?.ident.otherPlaces == [CrateTrack.Place(disc: nil, folder: "", track: nil)])
        #expect(c3.manifest.importLog?.entries.isEmpty == true)
        #expect(c3.manifest.importLog?.filesSeen == 4)

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
        #expect(entry(c4, x)?.ident.otherPlaces == [CrateTrack.Place(disc: nil, folder: "", track: nil)])
        #expect(c4.discPlan.map(\.name) == ["Stick 3"])
        #expect(c4.discPlan[0].folders.map(\.name) == ["House", "_old"])
    }

    /// One file on two sources and in a folder on the Mac (D27), as two burned CDs and the folder they were burned
    /// from would hold it:
    ///
    ///   mac/Burned/X.wav             bytes X
    ///   friday/Set/01 X.wav          bytes X        (source "Friday")
    ///   friday/Set/02 Y.wav          bytes Y
    ///   stick/House/01 X.wav         bytes X        (source "Stick 3")
    ///   stick/Peak/01 X again.wav    bytes X: the same file twice on one source
    ///   mac/Burned/X copy.wav        bytes X, the same folder, added last: one of the two is still logged as a duplicate
    @Test func oneFileOnTwoSourcesAndTheMacIsOneEntryWithEveryPlace() async throws {
        typealias Place = CrateTrack.Place
        let analyser = try await Fixture.shared.analyser()
        let root = try temporaryFolder("other-places")
        try? FileManager.default.removeItem(at: root)
        let fm = FileManager.default
        let mac = root.appendingPathComponent("mac"), friday = root.appendingPathComponent("friday"),
            stick = root.appendingPathComponent("stick")
        for d in [mac.appendingPathComponent("Burned"), friday.appendingPathComponent("Set"),
                  stick.appendingPathComponent("House"), stick.appendingPathComponent("Peak")] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        let buffer = TestTrack.render()
        let x = TestTrack.wav(buffer)
        let y = TestTrack.wav(AudioBuffer(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount,
                                          samples: buffer.samples.map { $0 * 0.5 }))
        try x.write(to: mac.appendingPathComponent("Burned/X.wav"))
        try x.write(to: friday.appendingPathComponent("Set/01 X.wav"))
        try y.write(to: friday.appendingPathComponent("Set/02 Y.wav"))
        try x.write(to: stick.appendingPathComponent("House/01 X.wav"))
        try x.write(to: stick.appendingPathComponent("Peak/01 X again.wav"))
        let crateURL = root.appendingPathComponent("Night.deckiecrate")
        let ix = CrateIDs.id(forSHA256: CrateIDs.sha256(of: x))
        func build(_ folder: URL, source: String? = nil, keep: Set<String> = []) async throws -> BuildResult {
            try await CPUTurns.exclusive {
                try Builder(options: BuildOptions(folder: folder, output: crateURL, jobs: 1, source: source,
                                                  keepSources: keep), analyser: analyser).run()
            }
        }
        func read() throws -> (Crate, CrateTrack) {
            let c = try CrateReader.read(from: crateURL)
            return (c, try #require(c.tracks.first { $0.id == ix }))
        }

        // The Mac folder, then Friday, then Stick 3.
        _ = try await build(mac)
        _ = try await build(friday, source: "Friday")
        var (c, ex) = try read()
        #expect(ex.ident.ownPlace == Place(disc: "Friday", folder: "Set", track: 1) && ex.file.rel == "Set/01 X.wav")
        #expect(ex.ident.otherPlaces == [Place(disc: nil, folder: "Burned", track: nil)])
        let three = try await build(stick, source: "Stick 3")
        (c, ex) = try read()
        #expect(c.tracks.count == 2)
        // Friday's place stays its own (a source already in the crate file keeps it); the stick's two are added,
        // in the order of the rule: sources by name, then folder and number, the Mac's folder last.
        #expect(ex.ident.ownPlace == Place(disc: "Friday", folder: "Set", track: 1) && ex.file.rel == "Set/01 X.wav")
        #expect(ex.ident.otherPlaces == [Place(disc: "Stick 3", folder: "House", track: 1),
                                         Place(disc: "Stick 3", folder: "Peak", track: 1),
                                         Place(disc: nil, folder: "Burned", track: nil)])
        #expect(c.manifest.importLog?.entries.isEmpty == true)
        #expect(three.filesSeen == 2 && c.manifest.importLog?.filesSeen == 5)
        #expect(c.discPlan.map(\.name) == ["Friday", "Stick 3"])
        #expect(c.trackIds(disc: "Stick 3", folder: "Peak") == [ix])
        #expect(c.problems().isEmpty)

        // X leaves Friday, which is read again: its own place was there, so the place that leads among the others
        // becomes its own. The crate file does not hold the path on the stick, so `file.rel` is null until the stick
        // is read again.
        try fm.removeItem(at: friday.appendingPathComponent("Set/01 X.wav"))
        _ = try await build(friday, source: "Friday")
        (c, ex) = try read()
        #expect(ex.ident.ownPlace == Place(disc: "Stick 3", folder: "House", track: 1) && ex.file.rel == nil)
        #expect(ex.ident.otherPlaces == [Place(disc: "Stick 3", folder: "Peak", track: 1),
                                         Place(disc: nil, folder: "Burned", track: nil)])
        #expect(c.trackIds(disc: "Friday", folder: "Set").count == 1)
        _ = try await build(stick, source: "Stick 3")
        (c, ex) = try read()
        #expect(ex.ident.ownPlace == Place(disc: "Stick 3", folder: "House", track: 1) && ex.file.rel == "House/01 X.wav")
        #expect(ex.ident.otherPlaces == [Place(disc: "Stick 3", folder: "Peak", track: 1),
                                         Place(disc: nil, folder: "Burned", track: nil)])

        // A second copy in the same folder on the Mac adds no place (a folder on the Mac has no numbers): logged.
        try x.write(to: mac.appendingPathComponent("Burned/X copy.wav"))
        _ = try await build(mac, keep: ["Friday", "Stick 3"])
        (c, ex) = try read()
        #expect(ex.ident.otherPlaces == [Place(disc: "Stick 3", folder: "Peak", track: 1),
                                         Place(disc: nil, folder: "Burned", track: nil)])
        // In path order "X copy.wav" comes first (a space before a dot), so it is the file the place is read from.
        #expect(c.manifest.importLog?.entries.map(\.rel) == ["Burned/X.wav"])
        #expect(c.manifest.importLog?.entries.first?.reason == CrateManifest.ImportLog.Reason.duplicate)
        #expect(c.manifest.importLog?.entries.first?.message == "the same bytes as Burned/X copy.wav, which has the record")
        // Seen: the Mac's two files and the three places kept on the sources (Friday's Y, the stick's X twice).
        #expect(c.manifest.importLog?.filesSeen == 5)
    }
}
