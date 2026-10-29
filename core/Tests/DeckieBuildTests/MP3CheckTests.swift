import Foundation
import Testing
import DeckieBuild
import DeckieDecode

/// `deckie-build mp3-check` on DeckieDecode's MP3 fixtures: the clean tones decode to exactly dr_mp3's own samples,
/// and tone_damaged.mp3 (one frame's Huffman data overwritten, core/Tools/make_damaged_mp3_fixture.py) differs only
/// over its damaged frame and the next, where the burst's true peak of +8.7 dBTP comes down to the tone's -1.8.
@Suite struct MP3CheckTests {
    @Test func cleanFilesAreUnchangedAndTheDamagedFrameIsTheOnlyChange() throws {
        let folder = try temporaryFolder("mp3-check")
        let fixtures = repositoryRoot.appendingPathComponent("core/Tests/DeckieDecodeTests/Fixtures")
        for name in ["tone.mp3", "tone48k.mp3", "tone_mono.mp3", "tone_damaged.mp3"] {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
            try FileManager.default.copyItem(at: fixtures.appendingPathComponent(name), to: folder.appendingPathComponent(name))
        }
        let results = try MP3Check.run(folder: folder, jobs: 2)
        #expect(results.map(\.rel) == ["tone.mp3", "tone48k.mp3", "tone_damaged.mp3", "tone_mono.mp3"])
        for r in results where r.rel != "tone_damaged.mp3" {
            #expect(r.error == nil && r.damagedFrames.isEmpty && r.differing == nil, "\(MP3Check.line(r))")
        }
        let damaged = try #require(results.first { $0.rel == "tone_damaged.mp3" })
        let start = Double(60 * 1152 - 576 - 529) / 44100, length = 1152.0 / 44100
        #expect(damaged.damagedFrames == [DamagedFrame(startSeconds: start, seconds: length)])
        let d = try #require(damaged.differing)
        #expect(d.lowerBound >= start && d.upperBound < start + 2 * length, "\(d)")
        // One span, the frame and the next: at most two frames' sample frames differ in it.
        #expect(damaged.spans.count == 1 && damaged.spans[0].count <= 2 * 1152 && damaged.spans[0].count > 1152,
                "\(damaged.spans)")
        #expect(MP3Check.line(damaged).contains("in 1 span: ") && MP3Check.line(damaged).contains(" sample frames)"))
        #expect((damaged.truePeakBefore ?? 0) > 8 && abs((damaged.truePeakAfter ?? 0) + 1.76) < 0.01)
        let (text, holds) = MP3Check.summary(results)
        print(text)
        #expect(holds && damaged.holds)
        #expect(text.hasPrefix("4 MP3 files: 3 decode to exactly dr_mp3's own samples (as before the concealment), "
                               + "1 with damaged frames, 0 not decoded\n"))
    }
}
