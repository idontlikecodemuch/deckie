import Foundation
import Testing
import DeckieCovers
import DeckieCrate
import DeckieTestSupport

// A picture to a cover: the size, the shape kept, what is refused, and the same bytes on every system.

@Suite struct CoverTests {
    @Test func aPictureBecomesASmallJPEGNamedByThePicturesHash() throws {
        let picture = TestPicture.sleeve(side: 600)
        let cover = try Cover.make(picture)
        #expect(cover.hash == CrateIDs.sha256(of: picture) && CrateIDs.isSHA256(cover.hash))
        #expect(cover.jpeg.starts(with: [0xFF, 0xD8, 0xFF]))
        #expect(cover.width == 128 && cover.height == 128)
        #expect(cover.jpeg.count <= CrateFormat.coverMaxBytes)
        // The same picture again is the same cover; another picture is another.
        #expect(try Cover.make(picture) == cover)
        #expect(try Cover.make(TestPicture.sleeve(side: 600, seed: 2)).hash != cover.hash)
    }

    /// The vendored code gives the same thumbnail bytes on Linux and on Windows: this hash is checked on both.
    @Test func thePortableThumbnailIsTheSameBytesEverywhere() throws {
        let made = try Cover.portableThumbnail(TestPicture.sleeve(side: 600))
        #expect(made.width == 128 && made.height == 128)
        print("portable thumbnail of the 600-pixel sleeve: \(made.jpeg.count) bytes, SHA-256 \(CrateIDs.sha256(of: made.jpeg))")
        #expect(CrateIDs.sha256(of: made.jpeg) == Self.pinned)
        // A JPEG source (the same sleeve written as a full-size JPEG by the same code) decodes and scales too.
        let asJPEG = try Cover.portableThumbnail(TestPicture.sleeve(side: 600), side: 600, quality: 90).jpeg
        let fromJPEG = try Cover.portableThumbnail(asJPEG)
        #expect(fromJPEG.width == 128 && fromJPEG.height == 128)
        print("from the JPEG: \(fromJPEG.jpeg.count) bytes, SHA-256 \(CrateIDs.sha256(of: fromJPEG.jpeg))")
        #expect(CrateIDs.sha256(of: fromJPEG.jpeg) == Self.pinnedFromJPEG)
    }
    static let pinned = "93abd59d9ee8ddd2a6238efa9e9085e8b2ba9bf24bc7469d81f0551d96623484"
    static let pinnedFromJPEG = "afb77e688c160fd52245cce787f9f2e2e0d2c6cc9d4102d5097cfb217aadb8b0"

    @Test func theShapeIsKeptAndNothingIsScaledUp() throws {
        let wide = try Cover.portableThumbnail(TestPicture.sleeve(side: 200, width: 800))
        #expect(wide.width == 128 && wide.height == 32)
        let tall = try Cover.portableThumbnail(TestPicture.png(width: 100, height: 1000) { _, y in (UInt8(y % 256), 0, 0, 255) })
        #expect(tall.width == 13 && tall.height == 128)
        let small = try Cover.portableThumbnail(TestPicture.sleeve(side: 40, width: 50))
        #expect(small.width == 50 && small.height == 40)
        let seeThrough = try Cover.portableThumbnail(TestPicture.png(width: 300, height: 300, alpha: true) { x, _ in (0, 0, 0, UInt8(x % 256)) })
        #expect(seeThrough.width == 128)
    }

    @Test func aBrokenOrEnormousPictureIsRefusedNotGuessedAt() throws {
        let picture = TestPicture.sleeve(side: 300)
        #expect(throws: Cover.Failure.unreadable) { try Cover.make(picture.prefix(picture.count / 2)) }
        #expect(throws: Cover.Failure.unreadable) { try Cover.make(Data("this is not a picture".utf8)) }
        #expect(throws: Cover.Failure.unreadable) { try Cover.make(Data()) }
        #expect(throws: Cover.Failure.unreadable) { try Cover.make(Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 16] + Array(repeating: 0, count: 64))) }
        // A GIF's first bytes: another kind of picture.
        #expect(throws: Cover.Failure.unreadable) { try Cover.make(Data(Array("GIF89a".utf8) + Array(repeating: 1, count: 64))) }
        // Wider than 8,192 pixels: not decoded at all.
        let enormous = TestPicture.png(width: 9000, height: 4) { _, _ in (10, 20, 30, 255) }
        #expect(throws: Cover.Failure.tooLarge) { try Cover.make(enormous) }
        // More bytes than a cover's source may have (an uncompressed 4,000-pixel PNG is 48 MB): not read either.
        #expect(throws: Cover.Failure.tooLarge) { try Cover.make(Data(count: CrateFormat.coverMaxSourceBytes + 1)) }
        // A large one inside both limits is fine: 2,500 pixels a side, 19 MB.
        let large = try Cover.make(TestPicture.png(width: 2500, height: 2500) { x, y in (UInt8(x * 255 / 2500), UInt8(y * 255 / 2500), 90, 255) })
        #expect(large.width == 128 && large.height == 128)
    }

    @Test func eventheWorstPictureStaysUnderTheCap() throws {
        let noise = try Cover.make(TestPicture.noise(side: 512))
        print("covers: the 600-pixel sleeve \(try Cover.make(TestPicture.sleeve(side: 600)).jpeg.count) bytes; "
              + "512 pixels of random colour \(noise.jpeg.count) bytes (cap \(CrateFormat.coverMaxBytes))")
        #expect(noise.jpeg.count <= CrateFormat.coverMaxBytes)
    }

    @Test func aCoverIsWrittenOnceIntoThePackage() throws {
        let package = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-cover-\(UUID().uuidString).deckiecrate")
        defer { try? FileManager.default.removeItem(at: package) }
        let cover = try Cover.make(TestPicture.sleeve(side: 300))
        try cover.write(into: package)
        try cover.write(into: package)
        let file = package.appendingPathComponent("covers").appendingPathComponent(cover.hash + ".jpg")
        #expect(try Data(contentsOf: file) == cover.jpeg)
        #expect(try FileManager.default.contentsOfDirectory(atPath: package.appendingPathComponent("covers").path).count == 1)
    }
}
