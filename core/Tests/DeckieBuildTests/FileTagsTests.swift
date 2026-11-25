import Foundation
import Testing
@testable import DeckieBuild

/// ID3v2 tags and Vorbis comments built byte by byte, in files of their own.
@Suite struct FileTagsTests {
    static func be32(_ v: Int) -> [UInt8] { [UInt8(v >> 24 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v & 0xFF)] }
    static func le32(_ v: Int) -> [UInt8] { be32(v).reversed() }
    static func synchsafe(_ v: Int) -> [UInt8] { [UInt8(v >> 21 & 0x7F), UInt8(v >> 14 & 0x7F), UInt8(v >> 7 & 0x7F), UInt8(v & 0x7F)] }

    /// An ID3v2 tag of `version` (2, 3 or 4) with the given text frames (frame id, encoding byte, text bytes).
    static func id3(version: UInt8, frames: [(String, UInt8, [UInt8])], padding: Int = 16) -> [UInt8] {
        var body: [UInt8] = []
        for (id, encoding, text) in frames {
            let data = [encoding] + text
            body += Array(id.utf8)
            switch version {
            case 2: body += Array(be32(data.count).suffix(3))
            case 3: body += be32(data.count) + [0, 0]
            default: body += synchsafe(data.count) + [0, 0]
            }
            body += data
        }
        body += [UInt8](repeating: 0, count: padding)
        return Array("ID3".utf8) + [version, 0, 0] + synchsafe(body.count) + body
    }

    static func utf16WithBOM(_ s: String) -> [UInt8] { [0xFF, 0xFE] + s.utf16.flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] } }

    static func write(_ bytes: [UInt8], _ name: String) throws -> URL {
        let url = try temporaryFolder("tags").appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    /// A few bytes that look like the start of MPEG audio, after the tag.
    static let mpegFrame: [UInt8] = [0xFF, 0xFB, 0x90, 0x64] + [UInt8](repeating: 0, count: 60)

    @Test func id3v23WithLatin1AndUTF16() throws {
        let tag = Self.id3(version: 3, frames: [("TIT2", 1, Self.utf16WithBOM("Café Night") + [0, 0]),
                                                ("TPE1", 0, Array("DJ Test".utf8)), ("TBPM", 0, Array("124".utf8))])
        let tags = FileTags.read(try Self.write(tag + Self.mpegFrame, "v23.mp3"))
        #expect(tags == FileTags(bpm: 124, title: "Café Night", artist: "DJ Test"))
    }

    @Test func id3v24WithUTF8AndAFractionalTempo() throws {
        let tag = Self.id3(version: 4, frames: [("TBPM", 3, Array("127.5".utf8)), ("TIT2", 3, Array("Über".utf8) + [0])])
        #expect(FileTags.read(try Self.write(tag + Self.mpegFrame, "v24.mp3")) == FileTags(bpm: 127.5, title: "Über"))
    }

    @Test func id3v22() throws {
        let tag = Self.id3(version: 2, frames: [("TT2", 0, Array("Old".utf8)), ("TBP", 0, Array("98".utf8))])
        #expect(FileTags.read(try Self.write(tag + Self.mpegFrame, "v22.mp3")) == FileTags(bpm: 98, title: "Old"))
    }

    @Test func id3ChunkInAWAVFile() throws {
        let tag = Self.id3(version: 3, frames: [("TBPM", 0, Array("120".utf8))], padding: 1)
        let fmt = Array("fmt ".utf8) + Self.le32(16) + [1, 0, 1, 0] + Self.le32(44100) + Self.le32(88200) + [2, 0, 16, 0]
        let data = Array("data".utf8) + Self.le32(4) + [0, 0, 0, 0]
        let chunk = Array("id3 ".utf8) + Self.le32(tag.count) + tag + (tag.count % 2 == 1 ? [0] : [])
        let body = Array("WAVE".utf8) + fmt + data + chunk
        let wav = Array("RIFF".utf8) + Self.le32(body.count) + body
        #expect(FileTags.read(try Self.write(wav, "tagged.wav")).bpm == 120)
    }

    @Test func flacVorbisComment() throws {
        func comment(_ s: String) -> [UInt8] { Self.le32(s.utf8.count) + Array(s.utf8) }
        let vendor = "reference libFLAC"
        let block = Self.le32(vendor.utf8.count) + Array(vendor.utf8) + Self.le32(3)
            + comment("TITLE=Flac Song") + comment("artist=Someone") + comment("BPM=126")
        let streaminfo: [UInt8] = [0x00, 0, 0, 34] + [UInt8](repeating: 0, count: 34)
        let flac = Array("fLaC".utf8) + streaminfo + [0x84] + Array(Self.be32(block.count).suffix(3)) + block
        #expect(FileTags.read(try Self.write(flac, "tagged.flac")) == FileTags(bpm: 126, title: "Flac Song", artist: "Someone"))
    }

    @Test func nothingFromUntaggedOrBrokenFiles() throws {
        #expect(FileTags.read(try Self.write(Self.mpegFrame, "plain.mp3")).isEmpty)
        // A tag claiming more bytes than the file holds.
        #expect(FileTags.read(try Self.write(Array("ID3".utf8) + [3, 0, 0, 0x7F, 0x7F, 0x7F, 0x7F, 0x41], "short.mp3")).isEmpty)
        #expect(FileTags.read(URL(fileURLWithPath: "/no/such/file.mp3")).isEmpty)
        #expect(FileTags.bpm("0") == nil && FileTags.bpm("128 BPM") == 128 && FileTags.bpm("") == nil)
    }
}

/// MP4 tags (`moov/udta/meta/ilst`) built box by box, as an `.m4a` carries them (bug of Nov 25, 2026: M4A songs were
/// named from their file names though their tags named them).
@Suite struct MP4TagsTests {
    static func box(_ type: String, _ body: [UInt8]) -> [UInt8] { FileTagsTests.be32(8 + body.count) + Array(type.utf8) + body }
    static func box(_ type: [UInt8], _ body: [UInt8]) -> [UInt8] { FileTagsTests.be32(8 + body.count) + type + body }
    /// A `data` box: version 0, the type in three bytes, four bytes of locale, the value.
    static func data(_ kind: UInt8, _ value: [UInt8]) -> [UInt8] { box("data", [0, 0, 0, kind, 0, 0, 0, 0] + value) }
    static func text(_ s: String) -> [UInt8] { data(1, Array(s.utf8)) }
    static func item(_ name: String, _ body: [UInt8]) -> [UInt8] {
        // The copyright sign is one byte (0xA9) in an MP4 box type.
        let type: [UInt8] = name.unicodeScalars.map { UInt8($0.value) }
        return box(type, body)
    }
    static func freeForm(mean: String = "com.apple.iTunes", _ name: String, _ value: String) -> [UInt8] {
        box("----", box("mean", [0, 0, 0, 0] + Array(mean.utf8)) + box("name", [0, 0, 0, 0] + Array(name.utf8)) + text(value))
    }
    /// A minimal MP4: `ftyp`, then a `moov` holding `udta/meta/ilst` with the items, then some stand-in audio.
    static func m4a(_ items: [[UInt8]]) -> [UInt8] {
        let ilst = box("ilst", items.flatMap { $0 })
        let meta = box("meta", [0, 0, 0, 0] + ilst)
        let moov = box("moov", box("udta", meta))
        return box("ftyp", Array("M4A ".utf8) + [0, 0, 2, 0] + Array("M4A mp42isom".utf8)) + moov
            + box("mdat", [UInt8](repeating: 0x21, count: 64))
    }
    static func tags(_ bytes: [UInt8], _ name: String = "song.m4a") throws -> FileTags {
        // A name of its own: the tests run at once, in one folder.
        let fromFile = FileTags.read(try FileTagsTests.write(bytes, UUID().uuidString + "-" + name))
        // The same answer from bytes in memory as from the file.
        #expect(FileTags.read(bytes: Data(bytes)) == fromFile)
        return fromFile
    }

    @Test func titleArtistAlbumTrackTempoKeyAndComment() throws {
        let file = Self.m4a([
            Self.item("\u{A9}nam", Self.text("  Night Drive \n")), Self.item("\u{A9}ART", Self.text("Marlo Dune")),
            Self.item("\u{A9}alb", Self.text("Late Set")), Self.item("aART", Self.text("Various Artists")),
            Self.item("trkn", Self.data(0, [0, 0, 0, 7, 0, 12, 0, 0])), Self.item("tmpo", Self.data(21, [0, 124])),
            Self.freeForm("initialkey", "8A"), Self.item("\u{A9}cmt", Self.text("8A - Energy 6")),
        ])
        #expect(try Self.tags(file) == FileTags(bpm: 124, title: "Night Drive", artist: "Marlo Dune", album: "Late Set",
                                               trackNumber: 7, key: "8A", comment: "8A - Energy 6"))
        // The same bytes under the other names an MP4 goes by.
        for name in ["song.mp4", "book.m4b", "SONG.M4A"] { #expect(try Self.tags(file, name).title == "Night Drive") }
    }

    @Test func utf16TextAndTheOtherKeySpellings() throws {
        let utf16 = "Café Noir".utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        let file = Self.m4a([Self.item("\u{A9}nam", Self.data(2, utf16)), Self.freeForm("KEY", "Am")])
        #expect(try Self.tags(file) == FileTags(title: "Café Noir", key: "Am"))
        #expect(try Self.tags(Self.m4a([Self.freeForm("Initial Key", "11B")])).key == "11B")
        // Another program's name space is not the key a DJ program wrote for iTunes.
        #expect(try Self.tags(Self.m4a([Self.freeForm(mean: "com.serato.dj", "initialkey", "5A")])).key == nil)
        // A tempo as one, two, four or eight bytes; zero, or a length no number has, is none.
        #expect(try Self.tags(Self.m4a([Self.item("tmpo", Self.data(21, [0, 0, 0, 128]))])).bpm == 128)
        #expect(try Self.tags(Self.m4a([Self.item("tmpo", Self.data(21, [0, 0]))])).bpm == nil)
        #expect(try Self.tags(Self.m4a([Self.item("tmpo", Self.data(21, [0, 0, 124]))])).bpm == nil)
        #expect(try Self.tags(Self.m4a([Self.item("tmpo", Self.data(21, [0xFF, 0x84]))])).bpm == nil)  // -124
    }

    @Test func whatDoesNotHoldTogetherGivesNothingAndNeverACrash() throws {
        let artist = Self.item("\u{A9}ART", Self.text("Kaya Venn"))
        // An item with no `data` box, or an empty or blank one, or text that is not UTF-8: no value, the rest read.
        #expect(try Self.tags(Self.m4a([Self.item("\u{A9}nam", []), artist])) == FileTags(artist: "Kaya Venn"))
        #expect(try Self.tags(Self.m4a([Self.item("\u{A9}nam", Self.text("   ")), artist])) == FileTags(artist: "Kaya Venn"))
        #expect(try Self.tags(Self.m4a([Self.item("\u{A9}nam", Self.data(1, [0xC3, 0x28])), artist])) == FileTags(artist: "Kaya Venn"))
        // UTF-16 of an odd length.
        #expect(try Self.tags(Self.m4a([Self.item("\u{A9}nam", Self.data(2, [0, 0x41, 0])), artist])) == FileTags(artist: "Kaya Venn"))
        // A `data` box shorter than its header, and a track number too short to hold one.
        #expect(try Self.tags(Self.m4a([Self.item("\u{A9}nam", Self.box("data", [0, 0, 0, 1])), artist])).title == nil)
        #expect(try Self.tags(Self.m4a([Self.item("trkn", Self.data(0, [0, 0, 0])), artist])).trackNumber == nil)

        // A `data` box whose length runs past its item: nothing read from it, the next item still read.
        var long = Self.text("Too Long")
        long.replaceSubrange(0..<4, with: FileTagsTests.be32(200))
        #expect(try Self.tags(Self.m4a([Self.item("\u{A9}nam", long), artist])) == FileTags(artist: "Kaya Venn"))
        // An item whose length runs past the list: the list ends there, what came before it stays.
        var overLong = Self.item("\u{A9}alb", Self.text("Never"))
        overLong.replaceSubrange(0..<4, with: FileTagsTests.be32(0x7FFF_FFF0))
        #expect(try Self.tags(Self.m4a([artist, overLong])) == FileTags(artist: "Kaya Venn"))
        // A 64-bit length as large as can be, at the top level and in the list.
        let huge: [UInt8] = FileTagsTests.be32(1) + Array("free".utf8) + [0x7F, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        let plain = Self.m4a([artist]), ftyp = 28  // the length of `m4a`'s ftyp box
        #expect(try Self.tags(Array(plain.prefix(ftyp)) + huge + Array(plain.dropFirst(ftyp))).isEmpty)
        #expect(try Self.tags(Self.m4a([artist, huge])) == FileTags(artist: "Kaya Venn"))

        // The file cut short at every length: never a crash, and nothing is made up (only tags that were there).
        let whole = Self.m4a([Self.item("\u{A9}nam", Self.text("Night Drive")), artist, Self.freeForm("initialkey", "8A")])
        for n in 0..<whole.count {
            let tags = FileTags.read(bytes: Data(whole.prefix(n)))
            #expect(tags.title == nil || tags.title == "Night Drive")
            #expect(tags.artist == nil || tags.artist == "Kaya Venn")
            #expect(tags.key == nil || tags.key == "8A")
        }
        // An MP4 with no tags at all.
        #expect(try Self.tags(Self.m4a([])).isEmpty)
    }
}

@Suite struct XMLScannerTests {
    func events(_ text: String) throws -> [String] {
        var out: [String] = []
        try XMLScanner.scan(Data(text.utf8)) { e in
            switch e {
            case .start(let name, let attributes):
                out.append("<\(name)" + attributes.keys.sorted().map { " \($0)=\(attributes[$0]!)" }.joined() + ">")
            case .end(let name): out.append("</\(name)>")
            }
        }
        return out
    }

    @Test func elementsAttributesAndEntities() throws {
        let text = "\u{FEFF}<?xml version=\"1.0\"?><!DOCTYPE x [<!ENTITY a \"b\">]><!-- c --><a x='1 &amp; 2' y=\"&lt;&#65;&#x42;&gt;\">"
            + "text<![CDATA[<b>]]><b z=\"a\tb\"/></a>"
        #expect(try events(text) == ["<a x=1 & 2 y=<AB>>", "<b z=a b>", "</b>", "</a>"])
    }

    @Test func namesTheLineOfAProblem() {
        for (text, message) in [("<a>\n<b>\n</a>", "line 3: </a> closes <b>"), ("<a x=1/>", "line 1: attribute x of <a> is not in quotes"),
                                ("<a>\n", "line 2: <a> is never closed"), ("<!-- x", "line 1: \"-->\" never comes")] {
            do {
                _ = try events(text)
                Issue.record("no error for \(text)")
            } catch {
                #expect("\(error)" == message)
            }
        }
    }
}

/// A folder of its own under the system's temporary folder, one per test process (the music folder is about 13 MB).
/// The folders of earlier runs whose process has ended are removed the first time.
func temporaryFolder(_ name: String) throws -> URL {
    _ = removeEarlierRuns
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(temporaryPrefix)\(ProcessInfo.processInfo.processIdentifier)")
        .appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let temporaryPrefix = "deckie-build-tests-"

private let removeEarlierRuns: Void = {
    #if !os(Windows)
    let fm = FileManager.default, tmp = fm.temporaryDirectory
    for name in (try? fm.contentsOfDirectory(atPath: tmp.path)) ?? [] where name.hasPrefix(temporaryPrefix) {
        // kill with signal 0 only asks whether the process is still there.
        if let pid = Int32(name.dropFirst(temporaryPrefix.count)), pid != getpid(), kill(pid, 0) != 0 {
            try? fm.removeItem(at: tmp.appendingPathComponent(name))
        }
    }
    #endif
}()
