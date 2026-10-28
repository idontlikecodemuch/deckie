import Foundation
import Testing
import DeckieCrate

// The two additions the crate builder proposes: the manifest's import log and the record's `deckie` block.

@Suite struct BuilderFieldTests {
    /// A crate with both additions filled.
    static func crateWithAdditions() -> Crate {
        var crate = sampleCrate()
        crate.manifest.importLog = .init(
            builtBy: "deckie-build 0.1.0", builtAt: "2026-10-28T13:00:00Z", filesSeen: 5, tracks: 2,
            entries: [.init(rel: "CD1/locked.m4p", ext: "m4p", reason: "protected", message: "protected, cannot be read"),
                      .init(rel: "CD1/odd.m4a", ext: "m4a", reason: "unsupported", message: "AAC is not supported here"),
                      .init(rel: "CD2/broken.mp3", ext: "mp3", reason: "damaged", message: "no complete MPEG audio frame")],
            rekordbox: .init(tracks: 12, matched: 2))
        crate.tracks[0].deckie = .init(
            bpmTag: .init(bpm: 125.0, source: "rekordbox-xml"),
            rekordbox: .init(trackId: "17", bpm: 125.0, tonality: "Dm",
                             grid: [.init(startS: 0.041, bpm: 125.0, meter: "4/4", beatInBar: 1)],
                             cues: [.init(name: "Drop", kind: "cue", hotCue: 0, startS: 61.481, endS: nil),
                                    .init(name: "", kind: "loop", hotCue: nil, startS: 12.0, endS: 19.68)],
                             playlists: [["Gigs", "Halloween"], ["Warm-up"]]))
        return crate
    }

    @Test func importLogAndDeckieBlockRoundTrip() throws {
        let crate = Self.crateWithAdditions()
        #expect(crate.problems().isEmpty, "\(crate.problems())")
        let files = try CrateWriter.encode(crate)
        let back = try CrateReader.decode(withSignatureFiles(files, crate))
        #expect(back == crate)
        #expect(try CrateWriter.encode(back) == files)
        let manifest = String(decoding: files["manifest.json"]!, as: UTF8.self)
        // The counts are written from the entries, reason then extension.
        #expect(manifest.contains(#""counts":{"damaged":{"mp3":1},"protected":{"m4p":1},"unsupported":{"m4a":1}}"#))
        #expect(manifest.contains(#""rekordbox":{"matched":2,"tracks":12}"#))
        let tracks = String(decoding: files["crate.json"]!, as: UTF8.self)
        #expect(tracks.contains(#""deckie":{"bpm_tag":{"bpm":125.0,"source":"rekordbox-xml"},"rekordbox":{"bpm":125.0,"#))
        #expect(tracks.contains(#"{"end_s":19.68,"hot_cue":null,"kind":"loop","name":"","start_s":12.0}"#))
        #expect(tracks.contains(#""playlists":[["Gigs","Halloween"],["Warm-up"]]"#))
    }

    @Test func importLogKeepsPathsRelative() throws {
        var crate = Self.crateWithAdditions()
        crate.manifest.importLog?.entries[1].rel = "/Users/someone/Music/odd.m4a"
        #expect(crate.problems().map(\.description) == [
            "manifest.json: import_log.entries[1].rel: \"/Users/someone/Music/odd.m4a\" is an absolute path; the crate keeps paths relative"])
        crate = Self.crateWithAdditions()
        crate.tracks[0].deckie?.rekordbox?.cues[1].endS = 3
        #expect(crate.problems().map(\.description) == [
            "crate.json: tracks[0].deckie.rekordbox.cues[1].end_s (track a1): 3.0 is before start_s 12.0"])
    }
}
