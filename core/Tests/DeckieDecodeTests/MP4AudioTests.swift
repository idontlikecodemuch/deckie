import Foundation
import Testing
@testable import DeckieDecode

// What an MP4 says about its lead-in, and the trim that follows. Plain Swift, so it runs on every platform; the
// decoding itself is Windows' (MediaFoundationTests).

@Suite struct MP4AudioTests {
    /// The edit list's box name overwritten, so the file states its lead-in nowhere.
    static func withoutEditList(_ m4a: Data) throws -> Data {
        var d = m4a
        let at = try #require(d.range(of: Data("edts".utf8)))
        d.replaceSubrange(at, with: Data("skip".utf8))
        return d
    }

    @Test func theToneSaysItsLeadInInItsEditList() throws {
        let info = try #require(MP4AudioInfo.read(try fixtureBytes("tone.m4a")))
        #expect(info.codec == "mp4a")
        #expect(info.mediaTimescale == 44100 && info.movieTimescale == 1000)
        #expect(info.mediaSamples == 177_424)  // 173 blocks of 1,024 and one of 272
        #expect(info.edit?.start == 1024 && info.edit?.duration == 4000)
        #expect(info.smpb == nil)
        #expect(MP4AudioInfo.read(try fixtureBytes("tone.wav")) == nil)
        #expect(MP4AudioInfo.read(try fixtureBytes("tone.m4a").prefix(70_000)) == nil)  // cut before its moov
    }

    @Test func theTrimPutsTheToneBackWhereItWas() throws {
        let info = try #require(MP4AudioInfo.read(try fixtureBytes("tone.m4a")))
        // What Windows was measured to hand back: every block whole, 178,176 frames.
        #expect(try MP4Trim.plan(info: info, decoded: 178_176, rate: 44100) == MP4Trim(drop: 1024, keep: 176_400, startUncertain: nil))
        // A decoder that hands back exactly the track.
        #expect(try MP4Trim.plan(info: info, decoded: 177_424, rate: 44100) == MP4Trim(drop: 1024, keep: 176_400, startUncertain: nil))
        // A decoder that already took the lead-in off: nothing more is dropped.
        #expect(try MP4Trim.plan(info: info, decoded: 177_152, rate: 44100) == MP4Trim(drop: 0, keep: 176_400, startUncertain: nil))
        #expect(try MP4Trim.plan(info: info, decoded: 176_400, rate: 44100) == MP4Trim(drop: 0, keep: 176_400, startUncertain: nil))
        // A length that fits neither is refused, not guessed at.
        #expect(throws: MP4Trim.Refusal.self) { try MP4Trim.plan(info: info, decoded: 100_000, rate: 44100) }
        #expect(throws: MP4Trim.Refusal.self) { try MP4Trim.plan(info: info, decoded: 400_000, rate: 44100) }
        // The samples kept.
        let trim = MP4Trim(drop: 2, keep: 3, startUncertain: nil)
        #expect(trim.apply([0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5], channels: 2) == [2, 2, 3, 3, 4, 4])
    }

    @Test func aFileThatStatesNoLeadInIsKeptWholeAndMarked() throws {
        let info = try #require(MP4AudioInfo.read(try Self.withoutEditList(try fixtureBytes("tone.m4a"))))
        #expect(info.edit == nil && info.smpb == nil)
        let trim = try MP4Trim.plan(info: info, decoded: 178_176, rate: 44100)
        #expect(trim.drop == 0 && trim.keep == 178_176)
        #expect(trim.startUncertain == "the file does not say how much lead-in its encoder added")
        // A raw AAC stream has no boxes at all.
        #expect(try MP4Trim.plan(info: nil, decoded: 5000, rate: 44100).startUncertain != nil)
    }

    @Test func iTunesSaysItInATag() throws {
        // tone.m4a with its edit list gone and an iTunSMPB tag put into its moov, as iTunes writes it: lead-in
        // 2,112 (hex 840), padding 0x1CA, 176,400 samples (hex 2B110).
        func box(_ type: String, _ body: [UInt8]) -> [UInt8] {
            let n = UInt32(8 + body.count)
            return [UInt8(n >> 24), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)] + Array(type.utf8) + body
        }
        let text = " 00000000 00000840 000001CA 000000000002B110 00000000 00000000 00000000 00000000"
        let item = box("----", box("mean", [0, 0, 0, 0] + Array("com.apple.iTunes".utf8))
                       + box("name", [0, 0, 0, 0] + Array("iTunSMPB".utf8))
                       + box("data", [0, 0, 0, 1, 0, 0, 0, 0] + Array(text.utf8)))
        let udta = box("udta", box("meta", [0, 0, 0, 0] + box("ilst", item)))
        var d = try Self.withoutEditList(try fixtureBytes("tone.m4a"))
        // The moov is the last box of this file: grow it by the tag.
        let moov = try #require(d.range(of: Data("moov".utf8))).lowerBound - 4
        let size = d[moov..<(moov + 4)].reduce(0) { $0 << 8 | Int($1) }
        #expect(moov + size == d.count)
        let grown = UInt32(size + udta.count)
        d.replaceSubrange(moov..<(moov + 4), with: [UInt8(grown >> 24), UInt8(grown >> 16 & 0xFF), UInt8(grown >> 8 & 0xFF), UInt8(grown & 0xFF)])
        d.append(contentsOf: udta)
        let info = try #require(MP4AudioInfo.read(d))
        #expect(info.smpb?.leadIn == 2112 && info.smpb?.padding == 0x1CA && info.smpb?.samples == 176_400)
        #expect(try MP4Trim.plan(info: info, decoded: 178_176, rate: 44100) == MP4Trim(drop: 2112, keep: 176_064, startUncertain: nil))
    }

    @Test func appleLosslessHasNoLeadIn() throws {
        let info = MP4AudioInfo(codec: "alac", mediaTimescale: 44100, mediaSamples: 176_400, movieTimescale: 1000, edit: nil, smpb: nil)
        #expect(try MP4Trim.plan(info: info, decoded: 176_400, rate: 44100) == MP4Trim(drop: 0, keep: 176_400, startUncertain: nil))
        // A decoder that rounds the end up to a whole block is cut back to the file's length.
        #expect(try MP4Trim.plan(info: info, decoded: 180_224, rate: 44100) == MP4Trim(drop: 0, keep: 176_400, startUncertain: nil))
    }

    @Test func aDecoderThatDoublesTheRateIsCountedInItsOwnFrames() throws {
        // HE-AAC: the track counts at 22,050, the decoder gives 44,100.
        let info = MP4AudioInfo(codec: "mp4a", mediaTimescale: 22050, mediaSamples: 90_112, movieTimescale: 1000,
                                edit: (start: 1024, duration: 4000), smpb: nil)
        #expect(try MP4Trim.plan(info: info, decoded: 180_224, rate: 44100) == MP4Trim(drop: 2048, keep: 176_400, startUncertain: nil))
    }
}
