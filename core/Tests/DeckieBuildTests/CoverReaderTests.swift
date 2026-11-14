import Foundation
import Testing
import DeckieAudio
import DeckieCovers
import DeckieCrate
import DeckieTestSupport
@testable import DeckieBuild

/// A song's picture read from its file's tags (D36), on files built byte by byte with pictures made in code: every
/// tag type the readers know, the front cover before any other picture, and the picture beside the music.
@Suite struct CoverReaderTests {
    typealias T = FileTagsTests
    typealias FF = FileFactsTests

    /// Two pictures as taggers embed them: a PNG and a JPEG (the JPEG made from another PNG by the thumbnail code).
    static let png = TestPicture.sleeve(side: 48, seed: 1)
    static let jpeg: Data = try! Cover.portableThumbnail(TestPicture.sleeve(side: 64, seed: 2), side: 64, quality: 90).jpeg
    static let other = TestPicture.sleeve(side: 40, seed: 3)

    /// An APIC frame's data: the encoding, the kind, the picture type, a description in that encoding, the picture.
    static func apic(_ picture: Data, type: UInt8 = 3, encoding: UInt8 = 0, mime: String = "image/png",
                     description: String = "") -> [UInt8] {
        let text: [UInt8]
        switch encoding {
        case 1: text = T.utf16WithBOM(description) + [0, 0]
        case 2: text = description.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] } + [0, 0]
        default: text = Array(description.utf8) + [0]
        }
        return [encoding] + Array(mime.utf8) + [0, type] + text + [UInt8](picture)
    }
    /// Unsynchronisation: a zero after every 0xFF.
    static func unsynchronised(_ bytes: [UInt8]) -> [UInt8] { bytes.flatMap { $0 == 0xFF ? [0xFF, 0] : [$0] } }

    static func read(_ bytes: [UInt8], _ name: String) throws -> (found: CoverReader.Found, url: URL) {
        let url = try T.write(bytes, "cover-" + name)
        return (CoverReader.embedded(in: url), url)
    }

    @Test func id3v23APICAndTheTagsStillCountItAsLeftOut() throws {
        let tag = FF.tag([FF.text("TIT2", "Night Drive"), FF.frame("APIC", Self.apic(Self.jpeg, mime: "image/jpeg", description: "front")),
                          FF.text("TALB", "Friday Night")])
        let (found, url) = try Self.read(tag + T.mpegFrame, "v23.mp3")
        #expect(found == .picture(Self.jpeg))
        // The text tags are read as before: the picture is counted as left out of them, the cover is its own thing.
        let facts = FileFacts.read(url)
        #expect(facts.other.leftOut == [SongFacts.LeftOut.picture: 1] && facts.facts[SongFacts.release] == ["Friday Night"])
    }

    @Test func id3v24WithAUTF16DescriptionADataLengthAndUnsynchronisation() throws {
        // UTF-16 with a byte-order mark: the description ends at two zeros on an even step, and holds single zeros.
        let plain = Self.apic(Self.jpeg, encoding: 1, mime: "image/jpeg", description: "Front \u{2014} sleeve")
        let v24 = FF.tag([FF.frame("APIC", plain, version: 4)], version: 4)
        #expect(try Self.read(v24 + T.mpegFrame, "v24.mp3").found == .picture(Self.jpeg))
        // UTF-16 big-endian without one.
        let big = FF.tag([FF.frame("APIC", Self.apic(Self.png, encoding: 2, description: "caf\u{e9}"), version: 4)], version: 4)
        #expect(try Self.read(big + T.mpegFrame, "v24-be.mp3").found == .picture(Self.png))
        // One frame unsynchronised, with its data length before it (frame flags 0x02 and 0x01), as 2.4 allows.
        let coded = Self.unsynchronised(plain)
        #expect(coded.count > plain.count)   // a JPEG has 0xFF bytes
        let frame = Array("APIC".utf8) + T.synchsafe(coded.count + 4) + [0, 0x03] + T.synchsafe(plain.count) + coded
        let body = frame + [UInt8](repeating: 0, count: 8)
        let tag = Array("ID3".utf8) + [4, 0, 0] + T.synchsafe(body.count) + body
        #expect(try Self.read(tag + T.mpegFrame, "v24-unsync.mp3").found == .picture(Self.jpeg))
    }

    @Test func id3v23WithTheWholeTagUnsynchronised() throws {
        let frames = FF.text("TIT2", "Title") + FF.frame("APIC", Self.apic(Self.jpeg, mime: "image/jpeg"))
        let body = Self.unsynchronised(frames)
        let tag = Array("ID3".utf8) + [3, 0, 0x80] + T.synchsafe(body.count) + body
        #expect(try Self.read(tag + T.mpegFrame, "v23-unsync.mp3").found == .picture(Self.jpeg))
    }

    @Test func id3v22PIC() throws {
        // PIC: the encoding, three letters for the kind, the picture type, a description, the picture.
        let data = [0] + Array("PNG".utf8) + [3] + Array("cover".utf8) + [0] + [UInt8](Self.png)
        let frame = Array("PIC".utf8) + Array(T.be32(data.count).suffix(3)) + data
        let body = frame + [UInt8](repeating: 0, count: 8)
        let tag = Array("ID3".utf8) + [2, 0, 0] + T.synchsafe(body.count) + body
        let (found, url) = try Self.read(tag + T.mpegFrame, "v22.mp3")
        #expect(found == .picture(Self.png))
        #expect(FileFacts.read(url).other.leftOut == [SongFacts.LeftOut.picture: 1])
    }

    @Test func theFrontCoverIsTakenBeforeAnyOtherPictureElseTheFirst() throws {
        // The back (type 4) comes first in the file; the front (type 3) is the cover.
        let both = FF.tag([FF.frame("APIC", Self.apic(Self.other, type: 4)), FF.frame("APIC", Self.apic(Self.png, type: 3)),
                           FF.frame("APIC", Self.apic(Self.jpeg, type: 6, mime: "image/jpeg"))])
        #expect(try Self.read(both + T.mpegFrame, "front.mp3").found == .picture(Self.png))
        // No picture says it is the front: the first one.
        let none = FF.tag([FF.frame("APIC", Self.apic(Self.other, type: 0)), FF.frame("APIC", Self.apic(Self.png, type: 4))])
        #expect(try Self.read(none + T.mpegFrame, "first.mp3").found == .picture(Self.other))
        // Two fronts: the first of them.
        let two = FF.tag([FF.frame("APIC", Self.apic(Self.png, type: 3)), FF.frame("APIC", Self.apic(Self.other, type: 3))])
        #expect(try Self.read(two + T.mpegFrame, "two-fronts.mp3").found == .picture(Self.png))
        // A link to a picture is not a picture.
        let link = FF.tag([FF.frame("APIC", [0] + Array("-->".utf8) + [0, 3, 0] + Array("http://example.com/a.jpg".utf8))])
        #expect(try Self.read(link + T.mpegFrame, "link.mp3").found == .none)
    }

    /// A FLAC picture block's body.
    static func pictureBlock(_ picture: Data, type: Int = 3, mime: String = "image/png", description: String = "") -> [UInt8] {
        T.be32(type) + T.be32(mime.utf8.count) + Array(mime.utf8) + T.be32(description.utf8.count) + Array(description.utf8)
            + T.be32(48) + T.be32(48) + T.be32(24) + T.be32(0) + T.be32(picture.count) + [UInt8](picture)
    }
    static func flacBlock(_ type: UInt8, _ body: [UInt8], last: Bool = false) -> [UInt8] {
        [type | (last ? 0x80 : 0)] + Array(T.be32(body.count).suffix(3)) + body
    }
    static let streamInfo = flacBlock(0, [UInt8](repeating: 0, count: 34))

    @Test func flacPictureBlocks() throws {
        let one = Array("fLaC".utf8) + Self.streamInfo + Self.flacBlock(6, Self.pictureBlock(Self.png, description: "the sleeve"), last: true)
        let (found, url) = try Self.read(one, "picture.flac")
        #expect(found == .picture(Self.png))
        #expect(FileFacts.read(url).other.leftOut == [SongFacts.LeftOut.picture: 1])
        // The disc's label (type 6) first, then the front.
        let two = Array("fLaC".utf8) + Self.streamInfo + Self.flacBlock(6, Self.pictureBlock(Self.other, type: 6))
            + Self.flacBlock(6, Self.pictureBlock(Self.jpeg, type: 3, mime: "image/jpeg"), last: true)
        #expect(try Self.read(two, "two-pictures.flac").found == .picture(Self.jpeg))
        // The writer the other tests use puts the same block.
        let buffer = AudioBuffer(sampleRate: 44100, channelCount: 1, samples: [Float](repeating: 0, count: 4096))
        let written = try T.write([UInt8](FLACWriter.flac16(buffer, picture: Self.png)), "cover-writer.flac")
        #expect(CoverReader.embedded(in: written) == .picture(Self.png))
        // An ID3 tag in front of a FLAC file: its picture is found too, and a front cover in either wins.
        let tagged = FF.tag([FF.frame("APIC", Self.apic(Self.other, type: 4))]) + one
        #expect(try Self.read(tagged, "id3-then.flac").found == .picture(Self.png))
    }

    @Test func flacPicturesInAVorbisComment() throws {
        let block = Data(Self.pictureBlock(Self.jpeg, mime: "image/jpeg")).base64EncodedString()
        let comment = FF.vorbisBlock([Array("TITLE=Song".utf8), Array("metadata_block_picture=\(block)".utf8)])
        let file = Array("fLaC".utf8) + Self.streamInfo + Self.flacBlock(4, comment, last: true)
        #expect(try Self.read(file, "comment-picture.flac").found == .picture(Self.jpeg))
        // The older COVERART: the picture alone.
        let old = FF.vorbisBlock([Array("COVERARTMIME=image/png".utf8), Array("COVERART=\(Self.png.base64EncodedString())".utf8)])
        #expect(try Self.read(Array("fLaC".utf8) + Self.streamInfo + Self.flacBlock(4, old, last: true), "coverart.flac").found
                == .picture(Self.png))
    }

    @Test func mp4Covr() throws {
        func file(_ covr: [UInt8]) -> [UInt8] {
            let ilst = FF.item("\u{A9}nam", "Title") + FF.box("covr", covr) + FF.item("\u{A9}alb", "Album")
            let meta = FF.box("meta", [0, 0, 0, 0] + FF.box("hdlr", [UInt8](repeating: 0, count: 25)) + FF.box("ilst", ilst))
            let moov = FF.box("moov", FF.box("mvhd", [UInt8](repeating: 0, count: 100)) + FF.box("udta", meta))
            return FF.box("ftyp", Array("M4A ".utf8) + [0, 0, 0, 0]) + FF.box("mdat", [UInt8](repeating: 0, count: 64)) + moov
        }
        let (found, url) = try Self.read(file(FF.data(13, [UInt8](Self.jpeg))), "covr.m4a")
        #expect(found == .picture(Self.jpeg))
        #expect(FileFacts.read(url).other.leftOut == [SongFacts.LeftOut.picture: 1])
        // Two pictures in one covr: the first, as players take it.
        #expect(try Self.read(file(FF.data(14, [UInt8](Self.png)) + FF.data(13, [UInt8](Self.jpeg))), "covr-two.m4a").found
                == .picture(Self.png))
    }

    @Test func wavAndAIFFWithAnID3Chunk() throws {
        let id3 = FF.tag([FF.text("TALB", "Album"), FF.frame("APIC", Self.apic(Self.png))])
        let wavBody = Array("WAVE".utf8) + FF.chunk("fmt ", [UInt8](repeating: 0, count: 16), bigEndian: false)
            + FF.chunk("data", [UInt8](repeating: 0, count: 33), bigEndian: false) + FF.chunk("id3 ", id3, bigEndian: false)
        #expect(try Self.read(Array("RIFF".utf8) + T.le32(wavBody.count) + wavBody, "tagged.wav").found == .picture(Self.png))
        let aiffBody = Array("AIFF".utf8) + FF.chunk("COMM", [UInt8](repeating: 0, count: 18), bigEndian: true)
            + FF.chunk("ID3 ", id3, bigEndian: true)
        #expect(try Self.read(Array("FORM".utf8) + T.be32(aiffBody.count) + aiffBody, "tagged.aif").found == .picture(Self.png))
    }

    @Test func nothingFromAFileWithNoPictureOrABrokenTag() throws {
        #expect(try Self.read(FF.tag([FF.text("TIT2", "Title")]) + T.mpegFrame, "none.mp3").found == .none)
        #expect(try Self.read(T.mpegFrame, "bare.mp3").found == .none)
        // A frame that claims more than the tag holds.
        let cut = Array("ID3".utf8) + [3, 0, 0] + T.synchsafe(30) + Array("APIC".utf8) + T.be32(5000) + [0, 0] + [UInt8](repeating: 1, count: 20)
        #expect(try Self.read(cut, "cut.mp3").found == .none)
        #expect(CoverReader.embedded(in: URL(fileURLWithPath: "/nowhere/at/all.mp3")) == .none)
        // A stray byte before the picture (a description ended one zero too many): the picture is found from its start.
        let stray = [0] + Array("image/png".utf8) + [0, 3, 0, 0] + [UInt8](Self.png)
        #expect(try Self.read(FF.tag([FF.frame("APIC", stray)]) + T.mpegFrame, "stray.mp3").found == .picture(Self.png))
    }

    @Test func aPictureOverTheSourceLimitIsNotRead() throws {
        // 32 MB and one byte in an APIC frame: found, and refused before anything is made of it.
        let big = [UInt8](repeating: 7, count: CrateFormat.coverMaxSourceBytes + 1)
        let tag = FF.tag([FF.frame("APIC", [0] + Array("image/jpeg".utf8) + [0, 3, 0] + big)])
        #expect(try Self.read(tag + T.mpegFrame, "too-large.mp3").found == .tooLarge)
        let folder = try temporaryFolder("cover-too-large")
        let file = folder.appendingPathComponent("cover.jpg")
        try Data(big).write(to: file)
        #expect(CoverBeside.read(file) == .tooLarge)
    }

    // MARK: beside the music

    @Test func eachNameBesideTheMusicInItsOrderWhateverItsCase() throws {
        let fm = FileManager.default
        #expect(CoverBeside.names == ["cover", "folder", "front", "albumart", "album"])
        #expect(CoverBeside.extensions == ["jpg", "jpeg", "png"])
        // Every accepted name, alone in a folder, in mixed case.
        for (i, name) in CoverBeside.names.enumerated() {
            for (j, ext) in CoverBeside.extensions.enumerated() {
                let folder = try temporaryFolder("beside-\(name)-\(ext)")
                let written = (i + j) % 2 == 0 ? "\(name.capitalized).\(ext.uppercased())" : "\(name).\(ext)"
                try Self.png.write(to: folder.appendingPathComponent(written))
                try Data("x".utf8).write(to: folder.appendingPathComponent("back.jpg"))
                #expect(CoverBeside.find(in: folder)?.lastPathComponent == written)
                #expect(CoverBeside.read(try #require(CoverBeside.find(in: folder))) == .picture(Self.png))
            }
        }
        // All of them in one folder: taken away one at a time, the next in the order is found.
        let all = try temporaryFolder("beside-all")
        var order: [String] = []
        for name in CoverBeside.names { for ext in CoverBeside.extensions { order.append("\(name).\(ext)") } }
        for name in order { try Self.png.write(to: all.appendingPathComponent(name)) }
        for name in order {
            #expect(CoverBeside.find(in: all)?.lastPathComponent == name)
            try fm.removeItem(at: all.appendingPathComponent(name))
        }
        #expect(CoverBeside.find(in: all) == nil)
        // Other names and other kinds are not taken, and a folder with such a name is not a picture.
        let none = try temporaryFolder("beside-none")
        for name in ["back.jpg", "cover.gif", "cover.webp", "cover.jpg.txt", "my cover.jpg", "AlbumArtSmall.jpg"] {
            try Self.png.write(to: none.appendingPathComponent(name))
        }
        try fm.createDirectory(at: none.appendingPathComponent("folder.jpg"), withIntermediateDirectories: true)
        #expect(CoverBeside.find(in: none) == nil)
        #expect(CoverBeside.find(in: none.appendingPathComponent("not there")) == nil)
    }
}
