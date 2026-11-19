import Foundation
import Testing
@testable import DeckieDecode

/// An MP3 cut short (a download that stopped, a copy that did not finish): the audio that is there is decoded as usual,
/// and the decode says the file is cut short, so a file too short to read is reported as damaged or incomplete and not
/// as a song with no beat. Two signs, either enough: the last frame stops before its own length, or the tag frame
/// counts more audio than is there. A whole file says neither.
@Suite struct CutShortTests {
    static func cut(_ data: Data, keep: Int) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-cut-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("cut.mp3")
        try data.prefix(keep).write(to: file)
        return file
    }

    @Test func aWholeFileIsNotCutShort() throws {
        for name in ["tone.mp3", "tone48k.mp3", "tone_mono.mp3", "tone_damaged.mp3"] {
            let d = try AudioDecoder.decodeReporting(Fixture.url(name))
            #expect(d.cutShort == nil, "\(name): \(String(describing: d.cutShort))")
        }
    }

    @Test func aFileCutPartWaySaysSo() throws {
        let data = try Data(contentsOf: Fixture.url("tone.mp3"))
        // Cut in the middle of a frame, at a third and at two thirds of the file.
        for keep in [data.count / 3 + 7, data.count * 2 / 3 + 3] {
            let d = try AudioDecoder.decodeReporting(try Self.cut(data, keep: keep))
            #expect(d.cutShort != nil, "kept \(keep) of \(data.count) bytes")
            #expect(d.buffer.frames > 0)
        }
    }

    @Test func eachSignOnItsOwn() throws {
        // With a tag frame that counts its frames, the count says how much is missing, wherever the cut falls.
        let tagged = try Data(contentsOf: Fixture.url("tone.mp3"))
        try #require(try MP3Reader.decodeUntrimmed(tagged, file: "tone.mp3").tag?.frameCount != nil)
        let u = try MP3Reader.decodeUntrimmed(tagged.prefix(tagged.count / 2), file: "cut.mp3")
        #expect(u.cutShort?.hasPrefix("it says it holds 0:04 of audio") == true, "\(String(describing: u.cutShort))")
        // Without one (the tag frame's bytes made into plain audio's: its "Info" or "Xing" word spoiled), the last
        // frame stopping part way says it.
        var plain = tagged
        for word in ["Xing", "Info"] { if let r = plain.range(of: Data(word.utf8)) { plain.replaceSubrange(r, with: Data("Xxxx".utf8)) } }
        try #require(try MP3Reader.decodeUntrimmed(plain, file: "plain.mp3").tag == nil)
        #expect(try MP3Reader.decodeUntrimmed(plain, file: "plain.mp3").cutShort == nil)
        let p = try MP3Reader.decodeUntrimmed(plain.prefix(plain.count / 2 + 5), file: "cut.mp3")
        #expect(p.cutShort?.hasPrefix("it ends in the middle of a frame") == true, "\(String(describing: p.cutShort))")
    }
}
