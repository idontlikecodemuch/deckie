import Foundation
import Testing
import DeckieAudio
import DeckieBuild
import DeckieCovers
import DeckieCrate
import DeckieTestSupport

/// The builder writes covers (D36): a music folder with pictures made in code, built, built again, and changed.
///
///   Album/01.wav, Album/02.wav   no picture of their own; Album/folder.jpg (a JPEG) beside them: one cover for both
///   Album/03.flac                a PNG in its own PICTURE block: its own wins over the folder's
///   Wide/04.wav                  Wide/Cover.PNG, 300 by 150: a cover of 128 by 64
///   Huge/05.wav                  Huge/front.png, 8,200 pixels wide: no cover, counted as too large
///   Broken/06.wav                Broken/cover.jpg, not a picture: no cover, counted as unreadable
///   Plain/07.wav                 no picture anywhere
///
/// Every song is the test track at its own level, so each has its own bytes and its own record.
@Suite(.enabled(if: Available.engine, "needs ONNX Runtime (core/Tools/fetch-onnxruntime.sh) and the Beat This! model (core/Tools/export_beat_this.py)"))
struct CoverBuildTests {
    static let folderJPEG: Data = try! Cover.portableThumbnail(TestPicture.sleeve(side: 300, seed: 1), side: 300, quality: 90).jpeg
    static let ownPNG = TestPicture.sleeve(side: 160, seed: 2)
    static let widePNG = TestPicture.sleeve(side: 150, seed: 3, width: 300)
    static let hugePNG = TestPicture.sleeve(side: 2, seed: 4, width: 8200)
    static let brokenJPEG = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array("not a picture at all".utf8))
    /// A time every music file is given, in whole seconds, so a file rewritten in a test can be given it back.
    static let stamp = Date(timeIntervalSince1970: 1_700_000_000)

    func coverFiles(_ package: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: package.appendingPathComponent("covers").path)) ?? []).sorted()
    }

    @Test func coversAreWrittenSharedKeptOnASecondRunAndRemovedWithTheirLastSong() async throws {
        let fm = FileManager.default
        let analyser = try await Fixture.shared.analyser()
        let root = try temporaryFolder("cover-build")
        try? fm.removeItem(at: root)
        let music = root.appendingPathComponent("Music")
        let track = TestTrack.render()
        func song(_ gain: Float) -> AudioBuffer {
            AudioBuffer(sampleRate: track.sampleRate, channelCount: track.channelCount, samples: track.samples.map { $0 * gain })
        }
        func write(_ data: Data, _ rel: String) throws {
            let url = rel.split(separator: "/").reduce(music) { $0.appendingPathComponent(String($1)) }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            try fm.setAttributes([.modificationDate: Self.stamp], ofItemAtPath: url.path)
        }
        try write(TestTrack.wav(song(1.0)), "Album/01.wav")
        try write(TestTrack.wav(song(0.9)), "Album/02.wav")
        try write(FLACWriter.flac16(song(0.8), picture: Self.ownPNG), "Album/03.flac")
        try write(Self.folderJPEG, "Album/folder.jpg")
        try write(TestTrack.wav(song(0.7)), "Wide/04.wav")
        try write(Self.widePNG, "Wide/Cover.PNG")
        try write(TestTrack.wav(song(0.6)), "Huge/05.wav")
        try write(Self.hugePNG, "Huge/front.png")
        try write(TestTrack.wav(song(0.5)), "Broken/06.wav")
        try write(Self.brokenJPEG, "Broken/cover.jpg")
        try write(TestTrack.wav(song(0.4)), "Plain/07.wav")

        let package = root.appendingPathComponent("Covers.deckiecrate")
        let options = BuildOptions(folder: music, output: package, jobs: 2, fresh: true)
        func cover(_ crate: Crate, _ rel: String) -> String? { crate.tracks.first { $0.file.rel == rel }?.file.cover }
        let shared = Cover.hash(of: Self.folderJPEG), own = Cover.hash(of: Self.ownPNG), wide = Cover.hash(of: Self.widePNG)

        // 1. The first run: every song is in; five have a cover, three covers in all.
        let first = try await CPUTurns.exclusive { try Builder(options: options, analyser: analyser).run() }
        print(first.summary)
        #expect(first.analysed == 7 && first.crate.tracks.count == 7)
        let crate = try CrateReader.read(from: package)   // the reader checks each named cover is there and a JPEG
        #expect(crate.tracks.count == 7)
        #expect(cover(crate, "Album/01.wav") == shared && cover(crate, "Album/02.wav") == shared)   // one picture, one cover
        #expect(cover(crate, "Album/03.flac") == own)                                               // its own, not the folder's
        #expect(cover(crate, "Wide/04.wav") == wide)
        #expect(cover(crate, "Huge/05.wav") == nil && cover(crate, "Broken/06.wav") == nil && cover(crate, "Plain/07.wav") == nil)
        #expect(coverFiles(package) == [shared, own, wide].map { $0 + ".jpg" }.sorted())
        // The thumbnails are what `Cover.make` gives for each picture: 128 pixels on the longest side, the shape kept.
        for (hash, picture, size) in [(shared, Self.folderJPEG, (128, 128)), (own, Self.ownPNG, (128, 128)), (wide, Self.widePNG, (128, 64))] {
            let made = try Cover.make(picture)
            #expect(made.width == size.0 && made.height == size.1)
            #expect(try Data(contentsOf: package.appendingPathComponent("covers/\(hash).jpg")) == made.jpeg)
        }
        // What the caller reports.
        let bytes = try coverFiles(package).reduce(0) { $0 + (try Data(contentsOf: package.appendingPathComponent("covers/\($1)")).count) }
        #expect(first.covers.songs == 4 && first.covers.distinct == 3 && first.covers.bytes == bytes && bytes > 0)
        #expect(first.covers.unusable == [CoverCounts.Reason.tooLarge: 1, CoverCounts.Reason.unreadable: 1])
        #expect(first.covers.made == 3 && first.covers.picturesRead == 6)   // the folder's picture read for each of its two songs
        #expect(first.summary.contains("covers: 4 songs with a cover, 3 distinct pictures, \(bytes) bytes in the crate (3 made in this run)"
                                       + "; 2 pictures not usable (unreadable 1, too_large 1)"), "\(first.summary)")
        // The tags still say a picture was left out of them; the record's bytes besides `file.cover` are as before.
        #expect(crate.tracks.first { $0.file.rel == "Album/03.flac" }?.file.otherTags?.leftOut == [SongFacts.LeftOut.picture: 1])

        // 2. A second run redoes nothing: no file analysed, no picture read, no thumbnail made, the same crate and the
        // same cover bytes. To show the music files are not opened for it, the FLAC's picture is swapped for another
        // of the same length with the file's size and time kept: the cover stays the one remembered.
        let before = try Dictionary(uniqueKeysWithValues: coverFiles(package).map {
            ($0, try Data(contentsOf: package.appendingPathComponent("covers/\($0)")))
        })
        let swapped = TestPicture.sleeve(side: 160, seed: 9)
        #expect(swapped.count == Self.ownPNG.count && swapped != Self.ownPNG)
        try write(FLACWriter.flac16(song(0.8), picture: swapped), "Album/03.flac")
        var again = options
        again.fresh = false
        let events = Events()
        let second = try await CPUTurns.exclusive { try Builder(options: again, analyser: analyser).run(progress: { events.add($0) }) }
        #expect(second.analysed == 0 && events.started?.queued == 0 && events.started?.unchanged == 7)
        #expect(second.covers.made == 0 && second.covers.picturesRead == 0)
        #expect(second.covers.songs == 4 && second.covers.distinct == 3 && second.covers.bytes == bytes)
        #expect(second.covers.unusable == first.covers.unusable)   // still told, from what was remembered
        let crate2 = try CrateReader.read(from: package)
        #expect(crate2.tracks == crate.tracks)
        #expect(cover(crate2, "Album/03.flac") == own)
        for (name, data) in before { #expect(try Data(contentsOf: package.appendingPathComponent("covers/\(name)")) == data) }
        #expect(coverFiles(package) == before.keys.sorted())

        // 3. A picture put beside a song that had none is found on the next run without the song being read again;
        // only that picture is read.
        try write(Self.ownPNG, "Plain/album.png")
        let third = try await CPUTurns.exclusive { try Builder(options: again, analyser: analyser).run() }
        #expect(third.analysed == 0 && third.covers.picturesRead == 1 && third.covers.made == 0)   // the thumbnail was there
        #expect(third.covers.songs == 5 && third.covers.distinct == 3)
        #expect(cover(third.crate, "Plain/07.wav") == own)

        // 4. Songs go: one of the two that share the folder's picture (the cover stays for the other), and the only
        // song with the wide one (its cover goes from the crate file).
        try fm.removeItem(at: music.appendingPathComponent("Album/02.wav"))
        try fm.removeItem(at: music.appendingPathComponent("Wide/04.wav"))
        let fourth = try await CPUTurns.exclusive { try Builder(options: again, analyser: analyser).run() }
        #expect(fourth.crate.tracks.count == 5 && fourth.analysed == 0)
        #expect(coverFiles(package) == [shared, own].map { $0 + ".jpg" }.sorted())
        #expect(fourth.covers.songs == 3 && fourth.covers.distinct == 2)
        let crate4 = try CrateReader.read(from: package)
        #expect(cover(crate4, "Album/01.wav") == shared && crate4.tracks.allSatisfy { $0.file.cover != wide })

        // 5. The last song with the folder's picture goes too, and the folder's picture with it.
        try fm.removeItem(at: music.appendingPathComponent("Album/01.wav"))
        let fifth = try await CPUTurns.exclusive { try Builder(options: again, analyser: analyser).run() }
        #expect(coverFiles(package) == [own + ".jpg"] && fifth.covers.distinct == 1 && fifth.covers.songs == 2)
        _ = try CrateReader.read(from: package)

        // 6. The wide song comes back: its thumbnail is still in the work folder, so none is made.
        try write(TestTrack.wav(song(0.7)), "Wide/04.wav")
        let sixth = try await CPUTurns.exclusive { try Builder(options: again, analyser: analyser).run() }
        #expect(sixth.analysed == 0 && sixth.covers.made == 0 && sixth.covers.picturesRead == 0)
        #expect(coverFiles(package) == [own, wide].map { $0 + ".jpg" }.sorted())
    }
}
