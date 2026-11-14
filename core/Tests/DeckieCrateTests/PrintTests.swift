import Foundation
import Testing
import DeckieCrate
import DeckieRecognition

// The fingerprint in the crate file (D35; crate-format.md, "Addition with D35"): a record's `print` and its file
// `prints/<id>.dkl`, an addition that changes no field. Proved here: a crate with fingerprints comes back as it went
// in, as a package folder and as a single file; one without them reads and writes as before; a fingerprint of a later
// version is ignored, not refused; and the checks find a missing file, a wrong mark and a wrong count. Made-up
// constellations only: no audio.

@Suite struct PrintTests {
    /// A constellation of `n` points, a few frames apart (some far enough to need two bytes for the gap).
    static func landmarks(_ n: Int) -> Landmarks {
        var frame: UInt32 = 0
        var frames: [UInt32] = []
        for i in 0..<n { frame += UInt32(i % 7 == 6 ? 300 : i % 3); frames.append(frame) }
        let pitches = (0..<n).map { UInt16(($0 * 977) % 14000) | UInt16($0 % 4) << 14 }
        return Landmarks(frames: frames, pitches: pitches, frameCount: Int(frame) + 10)
    }

    /// The sample crate with a fingerprint on its first song only.
    func printed() -> Crate {
        var c = sampleCrate()
        c.tracks[0].fingerprint = .init(Self.landmarks(200), madeBy: "linux-x86_64", madeAt: "2026-11-14T09:00:00Z")
        return c
    }

    @Test func aCrateWithPrintsReadsBackAsItWasWritten() throws {
        let c = printed()
        let files = try CrateWriter.encode(c)
        // The file is exactly the constellation's own bytes, beside the other sidecars, for that song only.
        #expect(files["prints/a1.dkl"] == Self.landmarks(200).encoded() && files["prints/b2.dkl"] == nil)
        let json = String(decoding: files["crate.json"]!, as: UTF8.self)
        #expect(json.contains(#""print":{"format":"DKL2","made_at":"2026-11-14T09:00:00Z","made_by":"linux-x86_64","points":200,"version":1}"#))
        #expect(json.components(separatedBy: "\"print\"").count == 2)
        let back = try CrateReader.decode(withSignatureFiles(files, c))
        #expect(back == c && back.problems().isEmpty)
        #expect(back.tracks[0].fingerprint?.landmarks == Self.landmarks(200))
        #expect(back.tracks[0].canBeRecognised && !back.tracks[1].canBeRecognised)
        // The version is unchanged: a reader of version 1 may open it.
        #expect(String(decoding: files["manifest.json"]!, as: UTF8.self).contains(#""min_reader":1"#))
    }

    @Test func thePackageFolderAndTheSingleFileCarryThePrints() throws {
        let c = printed()
        let dir = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let package = dir.appendingPathComponent("Sample.deckiecrate")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("signatures"), withIntermediateDirectories: true)
        try Data([1]).write(to: package.appendingPathComponent("signatures/a1_o.shazamsignature"))
        try CrateWriter.write(c, to: package)
        #expect(try Data(contentsOf: package.appendingPathComponent("prints/a1.dkl")) == Self.landmarks(200).encoded())
        #expect(try CrateReader.read(from: package) == c)

        // As one file: the same files inside, the fingerprint among them.
        let single = dir.appendingPathComponent("Single.deckiecrate")
        try CrateArchive.pack(package: package, to: single)
        #expect(try CrateArchive.read(single)["prints/a1.dkl"] == Self.landmarks(200).encoded())
        #expect(try CrateReader.read(from: single) == c)
        let unpacked = dir.appendingPathComponent("Unpacked.deckiecrate")
        try CrateArchive.unpack(single, to: unpacked)
        #expect(try CrateReader.read(from: unpacked) == c)

        // A song that loses its fingerprint, or leaves the crate, loses the file too; nothing else is touched.
        var without = c
        without.tracks[0].fingerprint = nil
        try CrateWriter.write(without, to: package)
        #expect(!FileManager.default.fileExists(atPath: package.appendingPathComponent("prints/a1.dkl").path))
        #expect(try CrateReader.read(from: package) == without)
    }

    @Test func aCrateWithoutPrintsReadsAndWritesAsBefore() throws {
        let c = sampleCrate()
        let files = try CrateWriter.encode(c)
        #expect(!String(decoding: files["crate.json"]!, as: UTF8.self).contains("\"print\""))
        #expect(!files.keys.contains { $0.hasPrefix("prints/") })
        #expect(try CrateReader.decode(withSignatureFiles(files, c)) == c)
        // The committed example crate, written before D35, has none and writes back byte for byte.
        let example = try CrateReader.read(from: Paths.example)
        #expect(example.tracks.allSatisfy { $0.fingerprint == nil } && example.problems().isEmpty)
        #expect(try CrateWriter.encode(example)["crate.json"]
                == (try Data(contentsOf: Paths.example.appendingPathComponent("crate.json"))))
        // A fingerprint's file that no record lists is left alone, like any file the reader does not know.
        var extra = withSignatureFiles(files, c)
        extra["prints/zz.dkl"] = Data("anything".utf8)
        #expect(try CrateReader.decode(extra) == c)
    }

    @Test func aPrintOfALaterVersionIsIgnoredNotRefused() throws {
        let c = printed()
        let files = withSignatureFiles(try CrateWriter.encode(c), c)
        // Version 2, with a shape this reader has never seen and a file it could not read.
        var later = try editTracks(files) {
            set(&$0, ["tracks", 0, "print"], ["format": "DKL3", "version": 2, "bands": [1, 2, 3]] as [String: Any])
        }
        later["prints/a1.dkl"] = Data("DKL3 and whatever follows".utf8)
        let back = try CrateReader.decode(later)
        #expect(back.tracks[0].fingerprint == nil && back.tracks[0].canBeRecognised)  // its signature still names it
        var expected = c
        expected.tracks[0].fingerprint = nil
        #expect(back == expected)
        // A version this reader knows must hold together.
        let broken = try editTracks(files) { set(&$0, ["tracks", 0, "print", "points"], nil) }
        #expect(readProblems(broken).map(\.description) == [
            "crate.json: tracks[0].print.points (track a1): is missing (a required field)"])
    }

    @Test func theChecksFindAMissingFileAWrongMarkAndAWrongCount() throws {
        let c = printed()
        let files = withSignatureFiles(try CrateWriter.encode(c), c)
        #expect(readProblems(files).isEmpty)

        var missing = files
        missing["prints/a1.dkl"] = nil
        #expect(readProblems(missing).map(\.description) == [
            "crate.json: tracks[0].print (track a1): prints/a1.dkl is not in the package"])

        var mark = files
        mark["prints/a1.dkl"] = Data("DKL1".utf8) + files["prints/a1.dkl"]!.dropFirst(4)
        #expect(readProblems(mark).map(\.description) == [
            "prints/a1.dkl (track a1): not a fingerprint (it must start with DKL2)"])

        let count = try editTracks(files) { set(&$0, ["tracks", 0, "print", "points"], 199) }
        #expect(readProblems(count).map(\.description) == [
            "prints/a1.dkl (track a1): holds 200 points but tracks[0].print.points is 199"])

        // Cut short, or with bytes after its last point: not a fingerprint. A count far past the file's length is
        // refused without the reader setting memory aside for it.
        var short = files
        short["prints/a1.dkl"] = files["prints/a1.dkl"]!.dropLast(2)
        #expect(readProblems(short).map(\.description) == [
            "prints/a1.dkl (track a1): cannot be read as a fingerprint (its points do not fill the file exactly)"])
        var huge = files
        huge["prints/a1.dkl"] = Data("DKL2".utf8) + Data([0, 0, 0, 0, 0xFF, 0xFF, 0xFF, 0xFF, 1, 2, 3])
        #expect(readProblems(huge).count == 1)

        let format = try editTracks(files) { set(&$0, ["tracks", 0, "print", "format"], "DKL9") }
        #expect(readProblems(format).map(\.description) == ["crate.json: tracks[0].print.format (track a1): \"DKL9\" must be DKL2"])
        // The writer runs the same checks before writing.
        var bad = c
        bad.tracks[0].fingerprint?.points = 7
        #expect(throws: CrateError.self) { try CrateWriter.encode(bad) }
    }

    /// What the booth's index is made from: the songs with fingerprints, their same-recording keys, and the stamp.
    @Test func aCrateGivesTheBoothsIndexItsSongs() throws {
        var c = sampleCrate()
        let base = c.tracks[1]
        c.tracks = ["t0", "t1", "t2", "t3"].enumerated().map { i, id in
            var t = base
            t.id = id
            t.ident.cutKey = i < 2 ? "t0" : nil
            t.fingerprint = i == 3 ? nil : .init(Self.landmarks(150 + 10 * i), madeBy: "linux-x86_64", madeAt: "2026-11-14T09:00:00Z")
            return t
        }
        let r = c.recognitionSongs()
        // The song without a fingerprint is left out; the first two share a key and the third has none.
        #expect(r.songs.map(\.id) == ["t0", "t1", "t2"] && r.sameRecording == ["t0", "t0", nil])
        #expect(r.songs[2].landmarks == Self.landmarks(170))
        #expect(r.stamp == RecognitionIndex.stamp(of: r.songs.map { ($0.id, $0.landmarks.count, $0.landmarks.frameCount) }))
        var other = c
        other.tracks.removeLast(2)
        #expect(other.recognitionSongs().stamp != r.stamp)

        let dir = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("index.dkx")
        let index = try c.recognitionIndex(cachedAt: url)
        #expect(index.ids == ["t0", "t1", "t2"] && index.stamp == r.stamp)
        // The second time the kept file is opened, not built again.
        let made = try Data(contentsOf: url)
        #expect(try c.recognitionIndex(cachedAt: url).ids == index.ids)
        #expect(try Data(contentsOf: url) == made)
    }
}
