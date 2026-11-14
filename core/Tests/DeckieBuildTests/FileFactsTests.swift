import Foundation
import Testing
import DeckieCrate
@testable import DeckieBuild

/// A song's facts from its file's tags (D34), on files built byte by byte: every ID3 version and text encoding, ID3v1,
/// Vorbis comments, WAV and AIFF chunks, MP4 atoms, several genres, pictures and private data left out, and the bounds.
@Suite struct FileFactsTests {
    typealias T = FileTagsTests
    typealias F = SongFacts

    /// An ID3v2 frame of `version` 3 or 4 with raw bytes after the header.
    static func frame(_ id: String, _ data: [UInt8], version: UInt8 = 3) -> [UInt8] {
        Array(id.utf8) + (version == 4 ? T.synchsafe(data.count) : T.be32(data.count)) + [0, 0] + data
    }
    static func text(_ id: String, _ s: String, encoding: UInt8 = 3, version: UInt8 = 3) -> [UInt8] {
        let bytes: [UInt8]
        switch encoding {
        case 0: bytes = s.unicodeScalars.map { UInt8($0.value) }
        case 1: bytes = T.utf16WithBOM(s)
        case 2: bytes = s.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        default: bytes = Array(s.utf8)
        }
        return frame(id, [encoding] + bytes, version: version)
    }
    static func tag(_ frames: [[UInt8]], version: UInt8 = 3) -> [UInt8] {
        let body = frames.flatMap { $0 } + [UInt8](repeating: 0, count: 8)
        return Array("ID3".utf8) + [version, 0, 0] + T.synchsafe(body.count) + body
    }
    static func read(_ bytes: [UInt8], _ name: String) throws -> FileFacts { FileFacts.read(try T.write(bytes, "facts-" + name)) }

    @Test func id3v23EveryFactAndEncoding() throws {
        let frames: [[UInt8]] = [
            Self.text("TIT2", "Night Drive"), Self.text("TPE1", "DJ Test", encoding: 0),
            Self.text("TALB", "Friday Night", encoding: 1),
            Self.text("TPE2", "Various Artists"),
            // Latin-1 as most taggers write it: 0x92 is Windows-1252's right quote.
            Self.frame("TPUB", [0] + Array("Nervous".utf8) + [0x92, 0x73]),
            Self.text("TYER", "1999"), Self.text("TDAT", "0105"),
            Self.text("TCON", "(13)(35)Deep House", encoding: 0),
            Self.text("TRCK", "02/12"), Self.text("TPOS", "1/2"),
            Self.text("TCOM", "A Writer"), Self.text("TPE4", "Some Remixer"), Self.text("TSRC", "USABC9900001"),
            Self.text("TBPM", "124"), Self.text("TKEY", "Am"),
            Self.frame("COMM", [0] + Array("eng".utf8) + [0] + Array("8A - Energy 6".utf8)),
            Self.frame("COMM", [0] + Array("eng".utf8) + Array("iTunNORM".utf8) + [0] + Array(" 000002A3 00000".utf8)),
            Self.frame("TXXX", [0] + Array("CATALOGNUMBER".utf8) + [0] + Array("NER 123".utf8)),
            Self.frame("TXXX", [0] + Array("Crowd".utf8) + [0] + Array("peak time".utf8)),
            Self.text("TSSE", "LAME 3.100"),
            Self.frame("APIC", [0] + Array("image/jpeg".utf8) + [0, 3, 0, 0xFF, 0xD8, 0xFF]),
            Self.frame("PRIV", Array("TRAKTOR4".utf8) + [0, 1, 2, 3]),
        ]
        let f = try Self.read(Self.tag(frames) + T.mpegFrame, "v23.mp3")
        #expect(f.facts[F.release] == ["Friday Night"])
        #expect(f.facts[F.releaseArtist] == ["Various Artists"])
        #expect(f.facts[F.label] == ["Nervous\u{2019}s"])
        #expect(f.facts[F.year] == ["1999"] && f.facts[F.date] == ["1999-05-01"])
        #expect(f.facts[F.genre] == ["Pop", "House", "Deep House"])
        #expect(f.facts[F.trackNumber] == ["2"] && f.facts[F.trackCount] == ["12"])
        #expect(f.facts[F.discNumber] == ["1"] && f.facts[F.discCount] == ["2"])
        #expect(f.facts[F.composer] == ["A Writer"] && f.facts[F.remixer] == ["Some Remixer"])
        #expect(f.facts[F.isrc] == ["USABC9900001"] && f.facts[F.catalogNumber] == ["NER 123"])
        #expect(f.facts[F.bpmText] == ["124"] && f.facts[F.keyText] == ["Am"])
        #expect(f.facts[F.comment] == ["8A - Energy 6"])
        // The title and artist are the record's own, not facts.
        #expect(f.facts["title"] == nil && f.other.tags["TIT2"] == nil && f.other.tags["TPE1"] == nil)
        #expect(f.other.tags == ["TSSE": ["LAME 3.100"], "TXXX:Crowd": ["peak time"]])
        #expect(f.other.formats == ["id3v2.3"])
        #expect(f.other.leftOut == [F.LeftOut.picture: 1, F.LeftOut.private: 1, F.LeftOut.binary: 1])
    }

    @Test func id3v24SeveralValuesAndUTF16BigEndian() throws {
        let frames: [[UInt8]] = [
            Self.text("TPE1", "Ünïcode Artist", version: 4),
            Self.frame("TCON", [3] + Array("House".utf8) + [0] + Array("Disco; Nu-Disco".utf8) + [0] + Array("35".utf8), version: 4),
            Self.text("TDRC", "2003-07-14T21:00", version: 4),
            Self.text("TPE2", "ünïcode artist", version: 4),   // the same artist: not kept as the release's
            Self.text("TALB", "Ünïcode Release", encoding: 2, version: 4),
            Self.frame("TCOM", [1] + T.utf16WithBOM("First") + [0, 0] + T.utf16WithBOM("Second") + [0, 0], version: 4),
            Self.text("TDOR", "1983", version: 4),
        ]
        let f = try Self.read(Self.tag(frames, version: 4) + T.mpegFrame, "v24.mp3")
        #expect(f.facts[F.genre] == ["House", "Disco", "Nu-Disco"])   // "35" is House again: each value once
        #expect(f.facts[F.year] == ["2003"] && f.facts[F.date] == ["2003-07-14T21:00"])
        #expect(f.facts[F.releaseArtist] == nil)
        #expect(f.facts[F.release] == ["Ünïcode Release"])
        #expect(f.facts[F.composer] == ["First", "Second"])
        #expect(f.facts[F.originalYear] == ["1983"])
        #expect(f.other.formats == ["id3v2.4"])
    }

    @Test func id3v22ThreeLetterFrames() throws {
        func f22(_ id: String, _ s: String) -> [UInt8] { let d = [0] + Array(s.utf8); return Array(id.utf8) + Array(T.be32(d.count).suffix(3)) + d }
        let body = f22("TT2", "Old") + f22("TAL", "Old Album") + f22("TYE", "1987") + f22("TCO", "(4)") + f22("TPB", "Old Label")
            + f22("TEN", "iTunes v1") + Array("PIC".utf8) + [0, 0, 5, 0, 0x4A, 0x50, 0x47, 0] + [UInt8](repeating: 0, count: 8)
        let tag = Array("ID3".utf8) + [2, 0, 0] + T.synchsafe(body.count) + body
        let f = try Self.read(tag + T.mpegFrame, "v22.mp3")
        #expect(f.facts[F.release] == ["Old Album"] && f.facts[F.year] == ["1987"])
        #expect(f.facts[F.genre] == ["Disco"] && f.facts[F.label] == ["Old Label"])
        #expect(f.other.tags == ["TEN": ["iTunes v1"]])
        #expect(f.other.leftOut == [F.LeftOut.picture: 1])
    }

    @Test func id3v1Alone() throws {
        var v1 = Array("TAG".utf8)
        func pad(_ s: String, _ n: Int) -> [UInt8] { Array((Array(s.utf8) + [UInt8](repeating: 0, count: n)).prefix(n)) }
        v1 += pad("Title", 30) + pad("Artist", 30) + pad("Album One", 30) + pad("1995", 4) + pad("a comment", 28) + [0, 7] + [35]
        let f = try Self.read(T.mpegFrame + v1, "v1.mp3")
        #expect(f.facts[F.release] == ["Album One"] && f.facts[F.year] == ["1995"] && f.facts[F.trackNumber] == ["7"])
        #expect(f.facts[F.genre] == ["House"] && f.facts[F.comment] == ["a comment"])
        #expect(f.other.formats == ["id3v1"] && f.other.tags.isEmpty)
    }

    static func vorbisBlock(_ comments: [[UInt8]]) -> [UInt8] {
        let vendor = Array("test".utf8)
        return T.le32(vendor.count) + vendor + T.le32(comments.count) + comments.flatMap { T.le32($0.count) + $0 }
    }
    static func flac(_ comments: [[UInt8]], picture: Bool = true) -> [UInt8] {
        let block = vorbisBlock(comments)
        let pic: [UInt8] = picture ? [6] + Array(T.be32(4).suffix(3)) + [1, 2, 3, 4] : []
        let vc: [UInt8] = [0x84] + Array(T.be32(block.count).suffix(3)) + block
        return Array("fLaC".utf8) + [0, 0, 0, 0] + pic + vc
    }

    @Test func flacVorbisCommentsWithSeveralGenres() throws {
        let c: [[UInt8]] = [
            Array("TITLE=Song".utf8), Array("GENRE=House".utf8), Array("genre=Deep House;Garage".utf8),
            Array("ALBUM=The EP".utf8), Array("LABEL=Strictly".utf8), Array("DATE=1992-03".utf8),
            Array("TRACKNUMBER=3".utf8), Array("TRACKTOTAL=04".utf8), Array("ISRC=GBXYZ9200003".utf8),
            Array("SERATO_MARKERS_V2=AAAAAAAAAA".utf8), Array("METADATA_BLOCK_PICTURE=AAAA".utf8),
            Array("REPLAYGAIN_TRACK_GAIN=-6.5 dB".utf8),
            // Not valid UTF-8: read as Windows-1252.
            Array("COMPOSER=".utf8) + [0x4A, 0xF6, 0x72, 0x67],
        ]
        let f = try Self.read(Self.flac(c), "tagged.flac")
        #expect(f.facts[F.genre] == ["House", "Deep House", "Garage"])
        #expect(f.facts[F.release] == ["The EP"] && f.facts[F.label] == ["Strictly"])
        #expect(f.facts[F.year] == ["1992"] && f.facts[F.date] == ["1992-03"])
        #expect(f.facts[F.trackNumber] == ["3"] && f.facts[F.trackCount] == ["4"])
        #expect(f.facts[F.isrc] == ["GBXYZ9200003"] && f.facts[F.composer] == ["Jörg"])
        #expect(f.other.tags == ["REPLAYGAIN_TRACK_GAIN": ["-6.5 dB"]])
        #expect(f.other.formats == ["vorbis"])
        #expect(f.other.leftOut == [F.LeftOut.picture: 2, F.LeftOut.private: 1])
    }

    static func chunk(_ id: String, _ body: [UInt8], bigEndian: Bool) -> [UInt8] {
        Array(id.utf8) + (bigEndian ? T.be32(body.count) : T.le32(body.count)) + body + (body.count % 2 == 1 ? [0] : [])
    }

    @Test func wavID3ChunkThenListInfo() throws {
        func item(_ id: String, _ s: String) -> [UInt8] { let d = Array(s.utf8) + [0]; return Array(id.utf8) + T.le32(d.count) + d + (d.count % 2 == 1 ? [0] : []) }
        let info = Array("INFO".utf8) + item("IPRD", "Info Album") + item("IGNR", "Techno") + item("ICRD", "2001-02-03")
            + item("ISFT", "Lavf58") + item("INAM", "Name")
        let id3 = Self.tag([Self.text("TALB", "ID3 Album")])
        let body = Array("WAVE".utf8) + Self.chunk("fmt ", [UInt8](repeating: 0, count: 16), bigEndian: false)
            + Self.chunk("LIST", info, bigEndian: false) + Self.chunk("id3 ", id3, bigEndian: false)
        let wav = Array("RIFF".utf8) + T.le32(body.count) + body
        let f = try Self.read(wav, "tagged.wav")
        #expect(f.facts[F.release] == ["ID3 Album"])            // the ID3 chunk comes first
        #expect(f.facts[F.genre] == ["Techno"] && f.facts[F.year] == ["2001"] && f.facts[F.date] == ["2001-02-03"])
        #expect(f.other.tags == ["ISFT": ["Lavf58"]])
        #expect(f.other.formats == ["id3v2.3", "riff-info"])
    }

    @Test func aiffID3AndItsOwnText() throws {
        let id3 = Self.tag([Self.text("TCON", "Electro"), Self.text("TALB", "AIFF Album")])
        let body = Array("AIFF".utf8) + Self.chunk("COMM", [UInt8](repeating: 0, count: 18), bigEndian: true)
            + Self.chunk("ANNO", Array("burned at home".utf8), bigEndian: true)
            + Self.chunk("(c) ", Array("2004 Someone".utf8), bigEndian: true)
            + Self.chunk("ID3 ", id3, bigEndian: true)
        let aiff = Array("FORM".utf8) + T.be32(body.count) + body
        let f = try Self.read(aiff, "tagged.aif")
        #expect(f.facts[F.genre] == ["Electro"] && f.facts[F.release] == ["AIFF Album"])
        #expect(f.facts[F.comment] == ["burned at home"] && f.facts[F.copyright] == ["2004 Someone"])
        #expect(f.other.formats == ["id3v2.3", "aiff-text"])
    }

    // MARK: MP4

    static func box(_ type: [UInt8], _ body: [UInt8]) -> [UInt8] { T.be32(8 + body.count) + type + body }
    static func box(_ type: String, _ body: [UInt8]) -> [UInt8] { box(Array(type.unicodeScalars.map { UInt8($0.value) }), body) }
    static func data(_ kind: Int, _ value: [UInt8]) -> [UInt8] { box("data", [0, 0, 0, UInt8(kind)] + [0, 0, 0, 0] + value) }
    static func item(_ type: String, _ s: String) -> [UInt8] { box(type, data(1, Array(s.utf8))) }
    static func freeForm(_ name: String, _ s: String) -> [UInt8] {
        box("----", box("mean", [0, 0, 0, 0] + Array("com.apple.iTunes".utf8)) + box("name", [0, 0, 0, 0] + Array(name.utf8))
            + data(1, Array(s.utf8)))
    }

    @Test func mp4Atoms() throws {
        let ilst = Self.item("\u{A9}nam", "Title") + Self.item("\u{A9}ART", "Artist") + Self.item("\u{A9}alb", "M4A Album")
            + Self.item("\u{A9}day", "2010-06-01T07:00:00Z") + Self.item("\u{A9}gen", "Funk")
            + Self.box("trkn", Self.data(0, [0, 0, 0, 5, 0, 9, 0, 0])) + Self.box("disk", Self.data(0, [0, 0, 0, 1, 0, 1]))
            + Self.box("tmpo", Self.data(21, [0, 118])) + Self.box("cpil", Self.data(21, [1]))
            + Self.box("covr", Self.data(13, [0xFF, 0xD8])) + Self.item("\u{A9}too", "Lavf60")
            + Self.freeForm("LABEL", "Defected") + Self.freeForm("iTunSMPB", " 00000000 00000840") + Self.freeForm("DJ NOTE", "big room")
        let meta = Self.box("meta", [0, 0, 0, 0] + Self.box("hdlr", [UInt8](repeating: 0, count: 25)) + Self.box("ilst", ilst))
        let moov = Self.box("moov", Self.box("mvhd", [UInt8](repeating: 0, count: 100)) + Self.box("udta", meta))
        let file = Self.box("ftyp", Array("M4A ".utf8) + [0, 0, 0, 0]) + Self.box("mdat", [UInt8](repeating: 0, count: 64)) + moov
        let f = try Self.read(file, "tagged.m4a")
        #expect(f.facts[F.release] == ["M4A Album"] && f.facts[F.genre] == ["Funk"])
        #expect(f.facts[F.year] == ["2010"] && f.facts[F.date] == ["2010-06-01T07:00:00Z"])
        #expect(f.facts[F.trackNumber] == ["5"] && f.facts[F.trackCount] == ["9"])
        #expect(f.facts[F.discNumber] == ["1"] && f.facts[F.discCount] == ["1"])
        #expect(f.facts[F.bpmText] == ["118"] && f.facts[F.compilation] == ["1"] && f.facts[F.label] == ["Defected"])
        #expect(f.other.tags == ["\u{A9}too": ["Lavf60"], "----:com.apple.iTunes:DJ NOTE": ["big room"]])
        #expect(f.other.formats == ["mp4"])
        #expect(f.other.leftOut == [F.LeftOut.picture: 1, F.LeftOut.private: 1])
    }

    // MARK: the bounds

    @Test func oversizedValuesAndTooManyAreLeftOutAndCounted() throws {
        var frames: [[UInt8]] = [Self.text("COMM", "x")]   // replaced below with a real comment
        frames = [Self.frame("COMM", [3] + Array("eng".utf8) + [0] + Array(String(repeating: "long ", count: 400).utf8))]
        frames.append(Self.frame("TCON", [3] + Array((1...20).map { "Genre \($0)" }.joined(separator: ";").utf8)))
        // Other tags past the total: 10 of 600 bytes each.
        for i in 0..<10 { frames.append(Self.frame("TXXX", [3] + Array("N\(i)".utf8) + [0] + Array(String(repeating: "v", count: 600).utf8))) }
        frames.append(Self.frame("TXXX", [3] + Array(String(repeating: "n", count: 100).utf8) + [0] + Array("short".utf8)))
        let f = try Self.read(Self.tag(frames) + T.mpegFrame, "big.mp3")
        #expect(f.facts[F.comment] == nil)
        #expect(f.facts[F.genre]?.count == F.maxValues && f.facts[F.genre]?.first == "Genre 1")
        let total = f.other.tags.reduce(0) { $0 + $1.key.utf8.count + $1.value.reduce(0) { $0 + $1.utf8.count } }
        #expect(total <= F.maxOtherBytes && f.other.tags.count == 6)
        #expect(f.other.leftOut[F.LeftOut.tooLong] == 2)     // the comment and the long name
        #expect(f.other.leftOut[F.LeftOut.tooMany] == 4)
        #expect(f.other.leftOut[F.LeftOut.overTotal] == 4)
        // A record with them passes the crate file's own checks.
        var c = sampleCrateForFacts()
        f.apply(to: &c.tracks[0])
        #expect(c.problems().isEmpty)
    }

    @Test func nothingFromAFileWithNoTagsOrABrokenOne() throws {
        #expect(try Self.read(T.mpegFrame, "plain.mp3").isEmpty)
        #expect(try Self.read(Array("ID3".utf8) + [3, 0, 0, 0x7F, 0x7F, 0x7F, 0x7F, 0x41], "short.mp3").isEmpty)
        #expect(FileFacts.read(URL(fileURLWithPath: "/no/such/file.mp3")).isEmpty)
        #expect(try Self.read(Self.box("ftyp", Array("M4A ".utf8)) + Self.box("moov", [1, 2, 3]), "broken.m4a").isEmpty)
    }

    @Test func intoARecordTheDJsEntryStays() throws {
        let f = try Self.read(Self.tag([Self.text("TALB", "From The File"), Self.text("TCON", "House"), Self.text("TSSE", "x")]) + T.mpegFrame, "rec.mp3")
        var c = sampleCrateForFacts()
        c.tracks[0].ident.facts[F.release] = .init("Mine", from: F.Origin.user)
        c.tracks[0].ident.facts[F.label] = .init("Old Tag Label", from: F.Origin.tag)
        c.tracks[0].ident.facts[F.year] = .init("1990", from: F.Origin.lookup("musicbrainz"))
        f.apply(to: &c.tracks[0])
        let facts = c.tracks[0].ident.facts
        #expect(facts[F.release] == .init("Mine", from: "user"))            // the DJ's, never overwritten
        #expect(facts[F.label] == nil)                                       // the file no longer says it
        #expect(facts[F.genre] == .init("House", from: "tag"))
        #expect(facts[F.year] == .init("1990", from: "lookup:musicbrainz"))  // fills what nothing else gives
        #expect(c.tracks[0].file.otherTags?.tags == ["TSSE": ["x"]])
    }
}

/// A one-track crate for the facts tests.
func sampleCrateForFacts() -> Crate {
    let t = CrateTrack(id: "abc123", file: .init(name: "a.mp3", rel: "a.mp3", bytes: 10, sha1Head: nil, durationS: 200),
                       ident: .init(title: "A", artist: "B"),
                       analysis: .init(engine: "deckie-0.4.0", analysedAt: "2026-11-14T00:00:00Z", device: "Mac15,6", secs: nil, level: 3),
                       engine: .init(family: "deckie", version: "0.4.0", platform: "macos-arm64", fidelity: 0, models: [], decoder: nil))
    return Crate(manifest: .init(crateId: "c", name: "Facts", createdAt: "2026-11-14T00:00:00Z", devicesSeen: []), tracks: [t])
}
