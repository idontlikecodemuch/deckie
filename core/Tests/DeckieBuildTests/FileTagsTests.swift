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

/// A fresh folder of its own under the system's temporary folder, one per test process.
func temporaryFolder(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("deckie-build-tests-\(ProcessInfo.processInfo.processIdentifier)")
        .appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
