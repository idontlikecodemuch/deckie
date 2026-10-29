import Foundation
import Testing
import DeckieCrate

// The two blocks accepted with memo Q's vocal fields, `vocal_structure` and `hooks`: they round-trip, are listed in
// `features_present`, are checked, and a crate without them (every crate written before them) reads as it did and
// keeps its bytes.

/// A vocal structure and hooks for a 40-bar track: the vocal-structure test track's reading.
func vocalBlocks() -> (CrateTrack.VocalStructure, CrateTrack.Hooks) {
    let rule = CrateTrack.VocalStructure.Rule(
        threshold: 0.0118, scoreP95: 0.0471, thresholdFraction: 0.25, thresholdFloor: 0.01, bridgeBeats: 8,
        minSpanBeats: 2, pickupBeats: 1, minGapBars: 8, kindBars: 16, beatDensityRatio: 0.5, brightMarginDb: 6,
        exposedLowDropDb: 6, exposedDensityRatio: 0.5, exposedMinBars: 2)
    let vs = CrateTrack.VocalStructure(
        source: "yamnet", frameHopS: 0.48, latticePhaseBar: 1, rule: rule,
        spans: [.init(startBar: 8, startBeat: 4, startS: 15.5545, endBar: 17, endBeat: 1, endS: 31.4012,
                      startOffsetBeats: -1, endOffsetBeats: 0),
                .init(startBar: 25, startBeat: 1, startS: 46.9921, endBar: 41, endBeat: 1, endS: 78.1012,
                      startOffsetBeats: 0, endOffsetBeats: 0)],
        first: .init(bar: 8, beat: 4, timeS: 15.5545, pickup: true), last: .init(bar: 40, beat: 4, timeS: 78.1012),
        introFreeBars: 7, introKind: "beat_only", outroFreeBars: 0, outroKind: "vocal",
        freeGaps: [.init(startBar: 17, endBar: 25)], exposedProxy: [.init(startBar: 29, endBar: 31)])
    let hooks = CrateTrack.Hooks(
        source: "deckie-core", latticePhaseBar: 1,
        rule: .init(lengthsBars: [8, 4], stepBars: 4, weightRepetition: 0.5, weightLoudness: 0.25, weightVocal: 0.25,
                    minRepetition: 0.5, shortMargin: 0.05, sungShare: 0.5, maxHooks: 3),
        candidates: [.init(startBar: 9, endBar: 17, strength: 0.97, sung: true, repetition: 0.962, loudnessScore: 0.988,
                           vocalDensity: 0.969, repeatStartBar: 25),
                     .init(startBar: 1, endBar: 5, strength: 0.525, sung: false, repetition: 0.998, loudnessScore: 0.073,
                           vocalDensity: 0.031, repeatStartBar: 33)])
    return (vs, hooks)
}

/// The sample crate with the blocks on its 40-bar track, b2.
func sampleCrateWithVocalBlocks() -> Crate {
    var crate = sampleCrate()
    let i = crate.tracks.firstIndex { $0.id == "b2" }!
    (crate.tracks[i].vocalStructure, crate.tracks[i].hooks) = vocalBlocks()
    return crate
}

@Suite struct VocalBlocksTests {
    @Test func roundTripAndFeaturesPresent() throws {
        let crate = sampleCrateWithVocalBlocks()
        #expect(crate.problems().isEmpty, "\(crate.problems())")
        let b2 = crate.tracks.first { $0.id == "b2" }!
        #expect(b2.featuresPresent.contains("vocal_structure") && b2.featuresPresent.contains("hooks"))
        let files = try CrateWriter.encode(crate)
        let back = try CrateReader.decode(withSignatureFiles(files, crate))
        #expect(back == crate)
        #expect(try CrateWriter.encode(back) == files)
        // Canonical: the blocks' keys sorted, numbers with their documented decimals; the record without them has
        // no such key.
        let lines = String(decoding: files["crate.json"]!, as: UTF8.self).split(separator: "\n")
        let a1 = String(lines[1]), b2Line = String(lines[2])
        #expect(!a1.contains("vocal_structure") && !a1.contains("hooks"))
        #expect(b2Line.contains(#""hooks":{"candidates":[{"end_bar":17,"loudness_score":0.988,"repeat_start_bar":25,"repetition":0.962,"start_bar":9,"strength":0.97,"sung":true,"vocal_density":0.969}"#))
        #expect(b2Line.contains(#""rule":{"beat_density_ratio":0.5,"bridge_beats":8,"bright_margin_db":6.0,"#))
        #expect(b2Line.hasSuffix(#""vocal_structure":{"exposed_proxy":[{"end_bar":31,"start_bar":29}],"first":{"bar":8,"beat":4,"pickup":true,"time_s":15.5545},"frame_hop_s":0.48,"free_gaps":[{"bars":8,"end_bar":25,"start_bar":17}],"intro_free_bars":7,"intro_kind":"beat_only","last":{"bar":40,"beat":4,"time_s":78.1012},"lattice_phase_bar":1,"outro_free_bars":0,"outro_kind":"vocal","rule":{"beat_density_ratio":0.5,"bridge_beats":8,"bright_margin_db":6.0,"exposed_density_ratio":0.5,"exposed_low_drop_db":6.0,"exposed_min_bars":2,"kind_bars":16,"min_gap_bars":8,"min_span_beats":2,"pickup_beats":1,"score_p95":0.0471,"threshold":0.0118,"threshold_floor":0.01,"threshold_fraction":0.25},"source":"yamnet","spans":[{"end_bar":17,"end_beat":1,"end_offset_beats":0,"end_s":31.4012,"start_bar":8,"start_beat":4,"start_offset_beats":-1,"start_s":15.5545},{"end_bar":41,"end_beat":1,"end_offset_beats":0,"end_s":78.1012,"start_bar":25,"start_beat":1,"start_offset_beats":0,"start_s":46.9921}]}}"#))
        print("vocal blocks: crate.json \(files["crate.json"]!.count) bytes with them on one 40-bar record")
    }

    /// A crate without the blocks reads with neither, and its bytes are what they were: the writer leaves them out
    /// rather than writing null. One that writes them as null reads the same.
    @Test func aCrateWithoutThemIsUnaffected() throws {
        let crate = sampleCrate()
        let files = withSignatureFiles(try CrateWriter.encode(crate), crate)
        let text = String(decoding: files["crate.json"]!, as: UTF8.self)
        #expect(!text.contains("vocal_structure") && !text.contains("hooks"))
        let back = try CrateReader.decode(files)
        #expect(back.tracks.allSatisfy { $0.vocalStructure == nil && $0.hooks == nil } && back == crate)
        let nulls = try editTracks(files) { obj in
            set(&obj, ["tracks", 0, "vocal_structure"], NSNull())
            set(&obj, ["tracks", 0, "hooks"], NSNull())
        }
        #expect(try CrateReader.decode(nulls) == crate)
        // The example crate, written before the blocks existed, reads with neither.
        let example = try CrateReader.read(from: Paths.example)
        #expect(example.tracks.allSatisfy { $0.vocalStructure == nil && $0.hooks == nil })
        #expect(example.tracks.allSatisfy { !$0.featuresPresent.contains("vocal_structure") })
    }

    /// `features_present` must list the blocks exactly when the record has them.
    @Test func featuresPresentMatchesTheBlocks() throws {
        let crate = sampleCrateWithVocalBlocks()
        let files = withSignatureFiles(try CrateWriter.encode(crate), crate)
        let unlisted = try editTracks(files) { obj in
            let list = ((obj["tracks"] as! [Any])[1] as! [String: Any])["features_present"] as! [String]
            set(&obj, ["tracks", 1, "features_present"], list.filter { $0 != "hooks" })
        }
        #expect(readProblems(unlisted).map(\.message) == ["does not list hooks, but the record has it"])
        let missing = try editTracks(files) { obj in set(&obj, ["tracks", 1, "vocal_structure"], nil) }
        #expect(readProblems(missing).map(\.message) == ["lists vocal_structure, but the record has no vocal_structure"])
    }

    /// Bars, beats, order, kinds and scores are checked, each problem naming its field.
    @Test func badValuesAreReported() {
        var crate = sampleCrateWithVocalBlocks()
        let i = crate.tracks.firstIndex { $0.id == "b2" }!
        var vs = crate.tracks[i].vocalStructure!, hooks = crate.tracks[i].hooks!
        vs.spans[0].startBeat = 5
        vs.spans[1].endBar = 41
        vs.spans[1].endBeat = 2
        vs.spans.append(vs.spans[0])
        vs.introKind = "loud"
        vs.freeGaps[0].bars = 9
        vs.exposedProxy[0].endBar = 42
        vs.latticePhaseBar = 9
        hooks.candidates[1].strength = 1.2
        hooks.candidates[0].endBar = 9
        crate.tracks[i].vocalStructure = vs
        crate.tracks[i].hooks = hooks
        let paths = crate.problems().map(\.path)
        let base = "tracks[1]."
        for want in ["vocal_structure.spans[0].start_beat", "vocal_structure.spans[1].end_beat",
                     "vocal_structure.spans[2].start_bar", "vocal_structure.intro_kind",
                     "vocal_structure.free_gaps[0].bars", "vocal_structure.exposed_proxy[0].end_bar",
                     "vocal_structure.lattice_phase_bar", "hooks.candidates[1].strength", "hooks.candidates[0].end_bar"] {
            #expect(paths.contains(base + want), "\(want) not in \(paths)")
        }
        #expect(throws: CrateError.self) { try CrateWriter.encode(crate) }

        // Spans with no first or last, and a first with no spans.
        var noFirst = sampleCrateWithVocalBlocks()
        noFirst.tracks[i].vocalStructure!.first = nil
        #expect(noFirst.problems().map(\.message) == ["is null, but there are spans"])
        var noSpans = sampleCrateWithVocalBlocks()
        noSpans.tracks[i].vocalStructure!.spans = []
        #expect(Set(noSpans.problems().map(\.path)) == [base + "vocal_structure.first", base + "vocal_structure.last"])
        // The blocks need the grid.
        var noGrid = sampleCrateWithVocalBlocks()
        noGrid.tracks[i].grid = nil
        noGrid.tracks[i].bars = nil
        noGrid.tracks[i].tempoSegments = nil
        noGrid.tracks[i].key?.changes = nil
        noGrid.tracks[i].phrase = nil
        noGrid.tracks[i].sections = nil
        noGrid.tracks[i].mixIn = nil
        noGrid.tracks[i].mixOut = nil
        noGrid.tracks[i].ends?.steadyInBar = nil
        noGrid.tracks[i].ends?.steadyOutBar = nil
        #expect(Set(noGrid.problems().map(\.path)) == [base + "vocal_structure", base + "hooks"])
    }
}
