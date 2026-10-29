import Foundation
import Testing
import DeckieCrate

// The crate builder's additions, as the main session accepted them: the manifest's import log, the record's
// `imported` block (the DJ's own data, keyed by source) and the file's tag tempo, `file.tag_bpm`.

@Suite struct BuilderFieldTests {
    /// A crate with all three filled.
    static func crateWithAdditions() -> Crate {
        var crate = sampleCrate()
        crate.manifest.importLog = .init(
            builtBy: "Mac15,6", builtAt: "2026-10-28T13:00:00Z", filesSeen: 5, tracks: 2,
            entries: [.init(rel: "CD1/locked.m4p", ext: "m4p", reason: "protected", message: "protected, cannot be read"),
                      .init(rel: "CD1/odd.m4a", ext: "m4a", reason: "unsupported", message: "AAC is not supported here"),
                      .init(rel: "CD2/broken.mp3", ext: "mp3", reason: "damaged", message: "no complete MPEG audio frame")],
            rekordbox: .init(tracks: 12, matched: 2))
        crate.tracks[0].file.tagBpm = 125.0
        crate.tracks[0].imported = .init(rekordbox: .init(
            importedAt: "2026-10-28T12:59:00Z", trackId: "17", bpm: 125.0, tonality: "Dm",
            gridMarkers: [.init(startS: 0.041, bpm: 125.0, meter: "4/4", beatInBar: 1)],
            cues: [.init(name: "Drop", kind: "cue", hotCue: 0, startS: 61.481)],
            loops: [.init(name: "", hotCue: nil, startS: 12.0, endS: 19.68)],
            playlists: [["Gigs", "Halloween"], ["Warm-up"]]))
        return crate
    }

    @Test func importLogAndImportedBlockRoundTrip() throws {
        let crate = Self.crateWithAdditions()
        #expect(crate.problems().isEmpty, "\(crate.problems())")
        let files = try CrateWriter.encode(crate)
        let back = try CrateReader.decode(withSignatureFiles(files, crate))
        #expect(back == crate)
        #expect(try CrateWriter.encode(back) == files)
        let manifest = String(decoding: files["manifest.json"]!, as: UTF8.self)
        #expect(manifest.contains(#""import_log":{"built_at":"2026-10-28T13:00:00Z","built_by":"Mac15,6","#))
        // The counts are written from the entries, reason then extension.
        #expect(manifest.contains(#""counts":{"damaged":{"mp3":1},"protected":{"m4p":1},"unsupported":{"m4a":1}}"#))
        #expect(manifest.contains(#""rekordbox":{"matched":2,"tracks":12}"#))
        let tracks = String(decoding: files["crate.json"]!, as: UTF8.self)
        #expect(tracks.contains(#""sha256":null,"tag_bpm":125.0},"#))
        #expect(tracks.contains(#""imported":{"rekordbox":{"bpm":125.0,"cues":[{"hot_cue":0,"kind":"cue","name":"Drop","start_s":61.481}],"#
                                + #""grid_markers":[{"beat_in_bar":1,"bpm":125.0,"meter":"4/4","start_s":0.041}],"#
                                + #""imported_at":"2026-10-28T12:59:00Z","loops":[{"end_s":19.68,"hot_cue":null,"name":"","start_s":12.0}],"#
                                + #""playlists":[["Gigs","Halloween"],["Warm-up"]],"tonality":"Dm","track_id":"17"}}"#))
        // The other track has nothing imported and no tag tempo: both null, never left out.
        #expect(tracks.contains(#""imported":null"#) && tracks.contains(#""tag_bpm":null"#))
    }

    @Test func importLogKeepsPathsRelativeAndImportedTimesHold() throws {
        var crate = Self.crateWithAdditions()
        crate.manifest.importLog?.entries[1].rel = "/Users/someone/Music/odd.m4a"
        #expect(crate.problems().map(\.description) == [
            "manifest.json: import_log.entries[1].rel: \"/Users/someone/Music/odd.m4a\" is an absolute path; the crate keeps paths relative"])
        crate = Self.crateWithAdditions()
        crate.tracks[0].imported?.rekordbox?.loops[0].endS = 3
        #expect(crate.problems().map(\.description) == [
            "crate.json: tracks[0].imported.rekordbox.loops[0].end_s (track a1): 3.0 is before start_s 12.0"])
        crate = Self.crateWithAdditions()
        crate.tracks[0].file.tagBpm = 0
        #expect(crate.problems().map(\.description) == ["crate.json: tracks[0].file.tag_bpm (track a1): 0.0 must be above 0"])
    }

    /// A record written before these fields existed (no `tag_bpm`, no `imported`) still reads, as nulls.
    @Test func recordsWithoutTheFieldsStillRead() throws {
        let crate = sampleCrate()
        var files = withSignatureFiles(try CrateWriter.encode(crate), crate)
        let text = String(decoding: files["crate.json"]!, as: UTF8.self)
        let older = text.replacingOccurrences(of: #","tag_bpm":null"#, with: "")
            .replacingOccurrences(of: #","imported":null"#, with: "")
        #expect(older != text && !older.contains("tag_bpm") && !older.contains("imported"))
        files["crate.json"] = Data(older.utf8)
        let back = try CrateReader.decode(files)
        #expect(back == crate && back.tracks.allSatisfy { $0.file.tagBpm == nil && $0.imported == nil })
    }
}
