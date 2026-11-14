import Foundation
import Testing
import DeckieCrate

// The single-file form of a crate file (CrateArchive): the same files in one uncompressed zip. It comes back as it
// went in, the same contents always give the same bytes on every platform, and damage is found.

@Suite struct ArchiveTests {
    /// The example crate as one file, committed, made on Linux by `CrateArchive.pack` (Tools/make_crate_fixture.sh).
    static let single = Paths.core.appendingPathComponent("fixtures/example-single.deckiecrate")

    func sampleFiles() throws -> [String: Data] {
        let crate = sampleCrate()
        return withSignatureFiles(try CrateWriter.encode(crate), crate)
    }

    @Test func roundTripInMemory() throws {
        let files = try sampleFiles()
        let archive = try CrateArchive.encode(files)
        #expect(try CrateArchive.decode(archive) == files)
        #expect(try CrateArchive.encode(try CrateArchive.decode(archive)) == archive)
        #expect(try CrateReader.decode(try CrateArchive.decode(archive)) == sampleCrate())
    }

    @Test func theBytesAreAPlainStoredZip() throws {
        let files = ["manifest.json": Data("{}\n".utf8), "crate.json": Data("abc".utf8), "bars/a.bin": Data([0, 1, 2])]
        let b = [UInt8](try CrateArchive.encode(files))
        // manifest.json leads, then crate.json, then the rest by path; each stored whole after a 30-byte header.
        #expect(Array(b[0..<4]) == [0x50, 0x4B, 0x03, 0x04])
        #expect(Array(b[8..<10]) == [0, 0])  // method 0: stored
        #expect(Array(b[30..<43]) == Array("manifest.json".utf8))
        #expect(Array(b[43..<46]) == Array("{}\n".utf8))
        let text = String(decoding: b, as: UTF8.self)
        let order = ["manifest.json", "crate.json", "bars/a.bin"].map { text.range(of: $0)!.lowerBound }
        #expect(order == order.sorted())
        // The end record closes the file: 3 entries, no comment.
        #expect(Array(b[(b.count - 22)..<(b.count - 18)]) == [0x50, 0x4B, 0x05, 0x06])
        #expect(b[b.count - 12] == 3 && b[b.count - 2] == 0 && b[b.count - 1] == 0)
        #expect(try CrateArchive.decode(Data(b))["crate.json"] == Data("abc".utf8))
    }

    @Test func crc32IsTheStandardOne() throws {
        // The check value of CRC-32 (ISO 3309, as zip uses it): "123456789" gives CBF43926. It is read back from the
        // archive's own header, bytes 14 to 17 of the first entry.
        let b = [UInt8](try CrateArchive.encode(["manifest.json": Data("123456789".utf8)]))
        #expect(Array(b[14..<18]) == [0x26, 0x39, 0xF4, 0xCB])
    }

    @Test func packAndUnpackKeepEveryFileAsItIs() throws {
        let files = try sampleFiles()
        let tmp = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let package = tmp.appendingPathComponent("Sample.deckiecrate")
        for (path, data) in files {
            let url = package.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        // The apps' own files travel too; a dot-file does not.
        try Data("{\"x\":1}".utf8).write(to: package.appendingPathComponent("prefs.json"))
        try FileManager.default.createDirectory(at: package.appendingPathComponent("history"), withIntermediateDirectories: true)
        try Data("line\n".utf8).write(to: package.appendingPathComponent("history/ipad.jsonl"))
        try Data("x".utf8).write(to: package.appendingPathComponent(".DS_Store"))

        let file = tmp.appendingPathComponent("Single.deckiecrate")
        try CrateArchive.pack(package: package, to: file)
        #expect(CrateArchive.isArchive(file))
        #expect(!CrateArchive.isArchive(package))
        var expected = files
        expected["prefs.json"] = Data("{\"x\":1}".utf8)
        expected["history/ipad.jsonl"] = Data("line\n".utf8)
        #expect(try CrateArchive.read(file) == expected)

        // The one call every reader makes takes either form and gives the same crate.
        #expect(try CrateReader.read(from: file) == CrateReader.read(from: package))

        let again = tmp.appendingPathComponent("Again.deckiecrate")
        try CrateArchive.unpack(file, to: again)
        for (path, data) in expected {
            #expect(try Data(contentsOf: again.appendingPathComponent(path)) == data, "\(path)")
        }
        let repacked = tmp.appendingPathComponent("Repacked.deckiecrate")
        try CrateArchive.pack(package: again, to: repacked)
        #expect(try Data(contentsOf: repacked) == Data(contentsOf: file))
    }

    /// A file made on one platform reads on another, and every platform writes the same bytes: the committed file
    /// was made on Linux, and this test runs on Linux, Windows and macOS.
    @Test func theCommittedSingleFileIsWhatEveryPlatformWritesAndReads() throws {
        let committed = try Data(contentsOf: Self.single)
        let tmp = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let made = tmp.appendingPathComponent("example-single.deckiecrate")
        try CrateArchive.pack(package: Paths.example, to: made)
        #expect(try Data(contentsOf: made) == committed)
        #expect(try CrateReader.read(from: Self.single) == CrateReader.read(from: Paths.example))
    }

    @Test func aZipFromAnotherToolReadsWhenStored() throws {
        // What Info-ZIP's `zip -0 -r` writes for one file in a folder: a folder entry, version 1.0 headers with a
        // time stamp and an extra field, and an archive comment. Built by hand so the test needs no zip program.
        func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func le32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8(v >> UInt32(8 * $0) & 0xFF) } }
        let body = Array("{}\n".utf8)
        let real = [UInt8](try CrateArchive.encode(["manifest.json": Data(body)]))
        let sum = Array(real[14..<18])
        let extra: [UInt8] = [0x55, 0x54, 0x05, 0x00, 0x03, 1, 2, 3, 4]  // an "extended timestamp" field
        var z: [UInt8] = []
        let folderAt = z.count
        z += [0x50, 0x4B, 0x03, 0x04] + le16(10) + le16(0) + le16(0) + le16(0x6000) + le16(0x5B6D) + le32(0) + le32(0) + le32(0)
            + le16(5) + le16(0) + Array("bars/".utf8)
        let fileAt = z.count
        z += [0x50, 0x4B, 0x03, 0x04] + le16(10) + le16(0) + le16(0) + le16(0x6000) + le16(0x5B6D) + sum + le32(3) + le32(3)
            + le16(13) + le16(extra.count) + Array("manifest.json".utf8) + extra + body
        let centralAt = z.count
        z += [0x50, 0x4B, 0x01, 0x02] + le16(0x031E) + le16(10) + le16(0) + le16(0) + le16(0x6000) + le16(0x5B6D) + le32(0)
            + le32(0) + le32(0) + le16(5) + le16(0) + le16(0) + le16(0) + le16(0) + le32(0x41ED_0010) + le32(UInt32(folderAt))
            + Array("bars/".utf8)
        z += [0x50, 0x4B, 0x01, 0x02] + le16(0x031E) + le16(10) + le16(0) + le16(0) + le16(0x6000) + le16(0x5B6D) + sum
            + le32(3) + le32(3) + le16(13) + le16(extra.count) + le16(0) + le16(0) + le16(0) + le32(0x81A4_0000)
            + le32(UInt32(fileAt)) + Array("manifest.json".utf8) + extra
        let centralSize = z.count - centralAt
        let comment = Array("made elsewhere".utf8)
        z += [0x50, 0x4B, 0x05, 0x06] + le16(0) + le16(0) + le16(2) + le16(2) + le32(UInt32(centralSize)) + le32(UInt32(centralAt))
            + le16(comment.count) + comment
        #expect(try CrateArchive.decode(Data(z)) == ["manifest.json": Data(body)])
    }

    // MARK: Damage

    func message(_ data: Data) -> String {
        do {
            _ = try CrateArchive.decode(data, name: "Set.deckiecrate")
            return "read without complaint"
        } catch { return "\(error)" }
    }

    @Test func aChangedByteAnywhereInAFileIsFound() throws {
        let files = try sampleFiles()
        let archive = try CrateArchive.encode(files)
        // Flip one bit in every 97th byte of the archive, one at a time: nothing damaged ever reads as the original.
        var silent = 0
        for at in stride(from: 0, to: archive.count, by: 97) {
            var damaged = archive
            damaged[at] ^= 0x10
            if let back = try? CrateArchive.decode(damaged), back == files { silent += 1 }
        }
        // The only bytes whose change shows nowhere are header fields that carry no content (the time stamp, the
        // version numbers, attributes): the files that come back are still exactly the files that went in.
        #expect(silent <= archive.count / 97 / 20)

        // A changed byte inside a file's contents names the file.
        let b = [UInt8](archive)
        let start = 30 + "manifest.json".utf8.count
        var damaged = archive
        damaged[start + 5] ^= 0x01
        #expect(message(damaged).contains("Set.deckiecrate: manifest.json: is damaged (its bytes do not match their checksum)"))
        #expect(b[start] == UInt8(ascii: "{"))
    }

    @Test func aFileCutShortIsRefused() throws {
        let archive = try CrateArchive.encode(try sampleFiles())
        for keep in [0, 3, 21, 100, archive.count / 2, archive.count - 30, archive.count - 1] {
            let m = message(archive.prefix(keep))
            #expect(m != "read without complaint", "cut to \(keep) bytes")
            if keep >= 22 { #expect(m.contains("cut short"), "cut to \(keep) bytes: \(m)") }
        }
        #expect(message(Data("this is not a zip at all, just some text".utf8)).contains("is not a crate file"))
    }

    @Test func compressedEncryptedAndUnsafeEntriesAreRefusedInWords() throws {
        let archive = try CrateArchive.encode(["manifest.json": Data("{}\n".utf8)])
        let centralAt = 30 + 13 + 3
        var compressed = archive
        compressed[centralAt + 10] = 8  // the method in the table of contents: deflate
        #expect(message(compressed).contains("manifest.json: is compressed"))
        var encrypted = archive
        encrypted[centralAt + 8] |= 1
        #expect(message(encrypted).contains("manifest.json: is encrypted"))
        // A path that would leave the package is never written and never read.
        for bad in ["../x.json", "/abs.json", "a\\b.json", "C:/x.json", "a//b", ""] {
            #expect(throws: CrateError.self) { try CrateArchive.encode([bad: Data()]) }
        }
        var climbing = try CrateArchive.encode(["xx/m.json": Data("{}\n".utf8)])
        let table = 30 + 9 + 3
        climbing.replaceSubrange(30..<32, with: Array("..".utf8))
        climbing.replaceSubrange((table + 46)..<(table + 48), with: Array("..".utf8))
        #expect(message(climbing).contains("does not stay inside"))
    }

    @Test func moreFilesThanAPlainZipCountsStillRoundTrip() throws {
        // Past 65,535 files the archive carries the zip64 count (about 20,000 songs with signatures).
        var files: [String: Data] = ["manifest.json": Data("{}\n".utf8)]
        for i in 0..<66_000 { files["bars/\(i).bin"] = Data([UInt8(i & 0xFF)]) }
        let archive = try CrateArchive.encode(files)
        let back = try CrateArchive.decode(archive)
        #expect(back.count == files.count)
        #expect(back == files)
    }

    @Test func readingSomethingThatIsNeitherFormSaysSo() throws {
        let tmp = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: tmp) }
        let stray = tmp.appendingPathComponent("song.deckiecrate")
        try Data("not a crate file".utf8).write(to: stray)
        #expect(throws: CrateError.self) { try CrateReader.read(from: stray) }
        #expect(throws: CrateError.self) { try CrateReader.read(from: tmp.appendingPathComponent("missing.deckiecrate")) }
    }
}
