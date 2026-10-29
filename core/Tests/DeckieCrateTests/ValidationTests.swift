import Foundation
import Testing
import DeckieCrate

// The reader refuses what the format does not allow and says where: the file, the field path and the track.

@Suite struct ValidationTests {
    let crate = sampleCrate()
    var files: [String: Data] { withSignatureFiles(try! CrateWriter.encode(crate), crate) }

    @Test func theSampleReads() {
        #expect(readProblems(files).isEmpty)
    }

    @Test func aCrateForANewerReaderIsRefused() throws {
        var f = files
        var m = try JSONSerialization.jsonObject(with: f["manifest.json"]!) as! [String: Any]
        m["schema"] = 2
        m["min_reader"] = 2
        f["manifest.json"] = try JSONSerialization.data(withJSONObject: m)
        let p = readProblems(f)
        #expect(p.map(\.description) == [
            "manifest.json: min_reader: the crate needs a reader of format 2 or later; this one reads format 1"])
    }

    @Test func aVersionBelowOneIsRefused() throws {
        var f = files
        var m = try JSONSerialization.jsonObject(with: f["manifest.json"]!) as! [String: Any]
        m["schema"] = 0
        f["manifest.json"] = try JSONSerialization.data(withJSONObject: m)
        let p = readProblems(f).map(\.description)
        #expect(p.contains("manifest.json: schema: 0 is not a format version (1 or more)"), "\(p)")
        #expect(p.contains("crate.json: tracks[0].schema (track a1): 1 must be between 1 and the manifest's 0"), "\(p)")
    }

    @Test func aMissingVersionIsRefused() throws {
        var f = files
        var m = try JSONSerialization.jsonObject(with: f["manifest.json"]!) as! [String: Any]
        m["schema"] = nil
        f["manifest.json"] = try JSONSerialization.data(withJSONObject: m)
        #expect(readProblems(f).map(\.description) == ["manifest.json: schema: is missing (a required field)"])
    }

    @Test func aMissingRequiredFieldIsNamed() throws {
        let f = try editTracks(files) { set(&$0, ["tracks", 1, "grid", "bpm"], nil) }
        #expect(readProblems(f).map(\.description) == ["crate.json: tracks[1].grid.bpm (track b2): is missing (a required field)"])
        let g = try editTracks(files) { set(&$0, ["tracks", 0, "features_present"], nil) }
        #expect(readProblems(g).map(\.description) == ["crate.json: tracks[0].features_present (track a1): is missing (a required field)"])
        let h = try editTracks(files) { set(&$0, ["tracks", 0, "grid", "n_bars"], "115") }
        #expect(readProblems(h).map(\.description) == ["crate.json: tracks[0].grid.n_bars (track a1): is not a whole number"])
    }

    @Test func aBarCountThatDoesNotMatchTheSidecarIsRefused() throws {
        let f = try editTracks(files) { set(&$0, ["tracks", 0, "grid", "n_bars"], 116) }
        let p = readProblems(f).map(\.description)
        #expect(p == ["bars/a1.bin (track a1): holds 115 bars but tracks[0].grid.n_bars is 116"])
    }

    @Test func aSeriesOfTheWrongLengthIsRefusedBeforeWriting() throws {
        var c = crate
        c.tracks[0].bars?[BarSeries.lufs] = Array(repeating: -20, count: 114)
        c.tracks[0].onsetPattern16?.removeLast()
        let error = try #require(throws: CrateError.self) { try CrateWriter.encode(c) }
        #expect(error.problems.map(\.description) == [
            "crate.json: tracks[0].onset_pattern_16 (track a1): has 15 values, not 16",
            "crate.json: tracks[0].bars.lufs (track a1): has 114 values for the grid's 115 bars"])
    }

    @Test func aSidecarOfTheWrongSizeOrSeriesCountIsRefused() throws {
        var f = files
        f["bars/b2.bin"]!.removeLast()
        #expect(readProblems(f).map(\.description) == ["bars/b2.bin (track b2): is 255 bytes; 3 series of 40 bars make 256"])
        let g = try editTracks(files) { set(&$0, ["tracks", 1, "features_present"],
            ["bars.lufs", "bars.vocal", "ends", "grid", "key", "loudness", "mix_windows", "onset_pattern", "phrase",
             "sections", "tempo_segments", "vocal"]) }
        #expect(readProblems(g).map(\.description) == [
            "bars/b2.bin (track b2): holds 3 series but features_present lists 2 (lufs, vocal)"])
        var h = files
        h["bars/b2.bin"] = nil
        #expect(readProblems(h).map(\.description) == [
            "bars/b2.bin (track b2): is missing; features_present lists the series drum, lufs, vocal"])
    }

    @Test func anOutOfRangeBarIsNamed() throws {
        let f = try editTracks(files) { set(&$0, ["tracks", 0, "mix_out", "end_bar"], 117) }
        #expect(readProblems(f).map(\.description) == [
            "crate.json: tracks[0].mix_out.end_bar (track a1): 117 is past the end of the grid (115 bars, so at most 116)"])
        let g = try editTracks(files) { set(&$0, ["tracks", 1, "sections", 0, "start_bar"], 0) }
        #expect(readProblems(g).map(\.description) == ["crate.json: tracks[1].sections[0].start_bar (track b2): 0 is before bar 1"])
        let h = try editTracks(files) { set(&$0, ["tracks", 0, "key", "changes", 1, "start_bar"], 116) }
        #expect(readProblems(h).map(\.description) == [
            "crate.json: tracks[0].key.changes[1].start_bar (track a1): 116 is past the last bar (115 bars)",
            "crate.json: tracks[0].key.changes[1].end_bar (track a1): 116 is not after start_bar 116"])
        let i = try editTracks(files) { set(&$0, ["tracks", 1, "phrase", "boundaries_bars"], [1, 9, 9, 42]) }
        #expect(readProblems(i).map(\.description) == [
            "crate.json: tracks[1].phrase.boundaries_bars[2] (track b2): 9 is not after 9",
            "crate.json: tracks[1].phrase.boundaries_bars[3] (track b2): 42 is past the end of the grid (40 bars, so at most 41)"])
    }

    @Test func featuresPresentMustMatchTheBlocks() throws {
        let f = try editTracks(files) { set(&$0, ["tracks", 1, "loudness"], NSNull()) }
        #expect(readProblems(f).map(\.description) == [
            "crate.json: tracks[1].features_present (track b2): lists loudness, but the record has no loudness"])
        let g = try editTracks(files) { set(&$0, ["tracks", 1, "mix_in"], NSNull()) }
        #expect(readProblems(g).map(\.description) == [
            "crate.json: tracks[1].mix_in (track b2): is null while the other mix window is not; there are both or neither"])
    }

    @Test func otherChecks() throws {
        let f = try editTracks(files) { set(&$0, ["tracks", 1, "id"], "a1") }
        let p = readProblems(f).map(\.description)
        #expect(p.contains("crate.json: tracks[1].id (track a1): the same id as tracks[0]"), "\(p)")
        let g = try editTracks(files) { set(&$0, ["tracks", 0, "key", "camelot"], "13A") }
        #expect(readProblems(g).map(\.description) == [
            "crate.json: tracks[0].key.camelot (track a1): \"13A\" is not a Camelot code (1A to 12B)"])
        var h = files
        h["signatures/a1_o.shazamsignature"] = nil
        #expect(readProblems(h).map(\.description) == [
            "crate.json: tracks[0].signatures.o (track a1): signatures/a1_o.shazamsignature is not in the package"])
        let i = try editTracks(files) { set(&$0, ["tracks", 0, "style", "dims"], 63) }
        #expect(readProblems(i).map(\.description) == ["style/a1.bin (track a1): holds 64 values but tracks[0].style.dims is 63"])
        let j = try editTracks(files) { set(&$0, ["tracks", 0, "file", "rel"], "/Users/someone/Music/a.mp3") }
        #expect(readProblems(j).map(\.description) == [
            "crate.json: tracks[0].file.rel (track a1): \"/Users/someone/Music/a.mp3\" is an absolute path; the crate keeps paths relative"])
        // An id that would lead out of the package is reported, and its sidecars are not looked for.
        let l = try editTracks(files) { set(&$0, ["tracks", 0, "id"], "../a1") }
        #expect(readProblems(l).map(\.description) == [
            "crate.json: tracks[0].id (track ../a1): \"../a1\" must be letters, digits, - and _ only, as it names the sidecar files"])
        var k = files
        k["crate.json"] = Data("{\"tracks\": [".utf8)
        #expect(readProblems(k).count == 1 && readProblems(k)[0].file == "crate.json")
    }

    @Test func aNonFiniteNumberIsRefusedBeforeWriting() throws {
        var c = crate
        c.tracks[1].ends?.lastSoundS = .infinity
        let error = try #require(throws: CrateError.self) { try CrateWriter.encode(c) }
        #expect(error.problems.map(\.description) == ["crate.json: tracks[1].ends.last_sound_s (track b2): inf is not a finite number"])
    }
}
