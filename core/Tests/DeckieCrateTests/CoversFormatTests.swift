import Foundation
import Testing
import DeckieCrate

// Covers in the crate file (D36): `file.cover` on a record and `covers/<hash>.jpg` in the package, in both
// directions, in both forms.

@Suite struct CoversFormatTests {
    static let hash = String(repeating: "ab", count: 32)
    static let other = String(repeating: "cd", count: 32)
    /// Enough of a JPEG for the reader: it checks the first bytes and the size, not the picture.
    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0] + Array(repeating: UInt8(7), count: 200))

    func crate(covers: [String?]) -> Crate {
        var c = sampleCrate()
        for (i, h) in covers.enumerated() where i < c.tracks.count { c.tracks[i].file.cover = h }
        return c
    }

    func files(_ c: Crate, covers: [String: Data]) throws -> [String: Data] {
        var f = withSignatureFiles(try CrateWriter.encode(c), c)
        for (h, d) in covers { f["covers/\(h).jpg"] = d }
        return f
    }

    @Test func aRecordWithoutACoverKeepsItsBytesAndOneWithItRoundTrips() throws {
        let plain = sampleCrate()
        #expect(!String(decoding: try CrateWriter.encode(plain)["crate.json"]!, as: UTF8.self).contains("\"cover\""))
        let c = crate(covers: [Self.hash, Self.hash])
        let text = String(decoding: try CrateWriter.encode(c)["crate.json"]!, as: UTF8.self)
        #expect(text.contains(#""cover":"\#(Self.hash)""#))
        let back = try CrateReader.decode(try files(c, covers: [Self.hash: Self.jpeg]))
        #expect(back == c)
        #expect(back.tracks.map(\.file.cover) == [Self.hash, Self.hash])
        // A crate file written before covers reads as it did: the committed example has none.
        #expect(try CrateReader.read(from: Paths.example).tracks.allSatisfy { $0.file.cover == nil })
    }

    @Test func theReaderNamesWhatIsWrongWithACover() throws {
        let c = crate(covers: [Self.hash])
        #expect(readProblems(try files(c, covers: [:])).map(\.description).joined().contains("covers/\(Self.hash).jpg is not in the package"))
        #expect(readProblems(try files(c, covers: [Self.hash: Data("not a jpeg".utf8)])).map(\.description).joined().contains("is not a JPEG picture"))
        let big = Data([0xFF, 0xD8, 0xFF] + Array(repeating: UInt8(0), count: CrateFormat.coverMaxBytes))
        #expect(readProblems(try files(c, covers: [Self.hash: big])).map(\.description).joined().contains("a cover is at most"))
        var bad = sampleCrate()
        bad.tracks[0].file.cover = "ABC"
        #expect(bad.problems().contains { $0.path.hasSuffix("file.cover") })
        #expect(throws: CrateError.self) { try CrateWriter.encode(bad) }
        // A cover no record names is ignored by the reader, like any file it does not know.
        #expect(readProblems(try files(sampleCrate(), covers: [Self.other: Self.jpeg])).isEmpty)
    }

    @Test func theWriterNeedsTheCoverThereAndTakesOutCoversNoSongNames() throws {
        let package = try temporaryFolder().appendingPathComponent("Covers.deckiecrate")
        defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }
        let c = crate(covers: [Self.hash, Self.other])
        for (path, data) in withSignatureFiles([:], c) {
            let url = package.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        // Not there yet: refused, naming the file.
        #expect(throws: CrateError.self) { try CrateWriter.write(c, to: package) }
        let covers = package.appendingPathComponent("covers")
        try FileManager.default.createDirectory(at: covers, withIntermediateDirectories: true)
        try Self.jpeg.write(to: covers.appendingPathComponent(Self.hash + ".jpg"))
        try Self.jpeg.write(to: covers.appendingPathComponent(Self.other + ".jpg"))
        try CrateWriter.write(c, to: package)
        #expect(try CrateReader.read(from: package) == c)

        // The single-file form carries the folder as it is.
        let single = package.deletingLastPathComponent().appendingPathComponent("Single.deckiecrate")
        try CrateArchive.pack(package: package, to: single)
        #expect(try CrateArchive.read(single)["covers/\(Self.hash).jpg"] == Self.jpeg)
        #expect(try CrateReader.read(from: single) == c)

        // The second song loses its cover (or leaves the crate): its picture goes, the other stays.
        var fewer = c
        fewer.tracks[1].file.cover = nil
        try CrateWriter.write(fewer, to: package)
        #expect(try FileManager.default.contentsOfDirectory(atPath: covers.path) == [Self.hash + ".jpg"])
        #expect(try CrateReader.read(from: package) == fewer)
    }

    @Test func aReaderAppGetsACoversBytesOnlyWhenTheyAreACover() throws {
        let package = try temporaryFolder().appendingPathComponent("Shown.deckiecrate")
        defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }
        let covers = package.appendingPathComponent("covers")
        try FileManager.default.createDirectory(at: covers, withIntermediateDirectories: true)
        try Self.jpeg.write(to: covers.appendingPathComponent(Self.hash + ".jpg"))
        #expect(CrateReader.coverData(in: package, hash: Self.hash) == Self.jpeg)
        // No file, a hash that is not one, a file that is not a JPEG or is too large: no cover, never an error.
        #expect(CrateReader.coverData(in: package, hash: Self.other) == nil)
        #expect(CrateReader.coverData(in: package, hash: "../" + Self.hash) == nil)
        try Data("not a jpeg".utf8).write(to: covers.appendingPathComponent(Self.other + ".jpg"))
        #expect(CrateReader.coverData(in: package, hash: Self.other) == nil)
        try Data([0xFF, 0xD8, 0xFF] + Array(repeating: UInt8(0), count: CrateFormat.coverMaxBytes))
            .write(to: covers.appendingPathComponent(Self.other + ".jpg"))
        #expect(CrateReader.coverData(in: package, hash: Self.other) == nil)
    }
}
