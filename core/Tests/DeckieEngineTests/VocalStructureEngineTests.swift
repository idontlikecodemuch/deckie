import Foundation
import Testing
import DeckieAudio
import DeckieCore
import DeckieCrate
import DeckieEngine
import DeckieInference
import DeckieLab
import DeckieTestSupport

/// The engine's vocal structure and hooks on the vocal-structure test track (`VocalStructureTrack`: 40 bars, the
/// synthesised voice from beat 4 of bar 8 to the end of bar 16 and over bars 25 to 32), with YAMNet. The synthesised
/// voice's frame scores dip far below their peak inside a sung stretch, so a span's ends are checked within two beats of
/// the construction (the rules themselves are checked exactly in VocalStructureTests); the bars, the free stretches,
/// the kinds and the pickup are checked exactly.
@Suite(.enabled(if: Available.yamnet, "needs ONNX Runtime, the Beat This! model and the YAMNet model (core/Tools/fetch-vocal-models.sh)"))
struct VocalStructureEngineTests {
    @Test func readsTheTestTrack() async throws {
        let a = try await Shared.shared.run("structure").analysis
        let v = try #require(a.vocal), s = try #require(a.vocalStructure)
        // The tagger's frames are kept, and the structure was read from them.
        #expect(v.perFrame?.count == v.frameCount && s.frameHopSeconds == 0.48)
        #expect(a.bars.nBars == VocalStructureTrack.bars && abs(a.bars.firstDownbeatS - VocalStructureTrack.firstBeat) < 0.03)
        #expect(s.latticePhaseBar == 1)
        // Two spans, each end within two beats of the construction's.
        try #require(s.spans.count == 2)
        let want = VocalStructureTrack.voiced.flatMap { [$0.lowerBound, $0.upperBound] }
        let got = s.spans.flatMap { [$0.startBeatIndex, $0.endBeatIndex] }
        for (g, w) in zip(got, want) { #expect(abs(g - w) <= 2, "beat \(g) against \(w)") }
        // The first sung beat is the pickup, beat 4 of bar 8; the last is beat 4 of bar 32.
        #expect(s.first?.bar == 8 && s.first?.beat == 4 && s.pickup)
        #expect(s.last?.bar == 32 && s.last?.beat == 4)
        #expect(s.introFreeBars == 7 && s.outroFreeBars == 8 && s.introKind == .beatOnly && s.outroKind == .beatOnly)
        #expect(s.freeGaps.map { [$0.startBar, $0.endBar] } == [[17, 25], [33, 41]] && s.exposedProxy.isEmpty)
        #expect(s.spans.allSatisfy { abs($0.startOffsetBeats) <= 2 && abs($0.endOffsetBeats) <= 2 })
        // The hooks: a sung stretch first, 8 bars, repeating at the other; well ahead of the rest.
        let h = try #require(a.hooks)
        let top = try #require(h.candidates.first)
        #expect([9, 25].contains(top.startBar) && top.bars == 8 && top.sung)
        #expect(top.repeatStartBar == (top.startBar == 9 ? 25 : 9))
        #expect(h.candidates.count <= 3 && h.candidates.dropFirst().allSatisfy { !$0.sung && $0.strength < top.strength - 0.2 })
        let t = { (beat: Int) in Py.fixed(a.bars.firstDownbeatS + Double(beat) * a.bars.beatS, 2) }
        print("""
            vocal structure of the test track (threshold \(Py.fixed(s.threshold, 4)), p95 \(Py.fixed(s.scoreP95, 4))): \
            spans \(s.spans.map { "\($0.start.bar).\($0.start.beat) (\(Py.fixed($0.start.seconds, 2)) s) to \($0.end.bar).\($0.end.beat) (\(Py.fixed($0.end.seconds, 2)) s), offsets \($0.startOffsetBeats)/\($0.endOffsetBeats)" }); \
            built \(VocalStructureTrack.voiced.map { "\(t($0.lowerBound)) to \(t($0.upperBound)) s" }); \
            first \(s.first.map { "\($0.bar).\($0.beat)" } ?? "-") pickup \(s.pickup), last \(s.last.map { "\($0.bar).\($0.beat)" } ?? "-"); \
            free intro \(s.introFreeBars) \(s.introKind.rawValue), outro \(s.outroFreeBars) \(s.outroKind.rawValue); \
            gaps \(s.freeGaps.map { "\($0.startBar)-\($0.endBar)" }); hooks \(h.candidates.map { "\($0.startBar)-\($0.endBar) \(Py.fixed($0.strength, 3)) (rep \(Py.fixed($0.repetition, 3)), loud \(Py.fixed($0.loudness, 3)), vocal \(Py.fixed($0.vocalDensity, 3)))\($0.sung ? " sung" : "")" })
            """)
    }

    /// The lab JSON carries both under `deckie`, as the crate blocks' fields; the lab's readers still read the file.
    @Test func labJSONCarriesThem() async throws {
        let a = try await Shared.shared.run("structure").analysis
        let json = a.labJSON()
        let deckie = try #require(json["deckie"])
        let vs = try #require(deckie["vocal_structure"]), hooks = try #require(deckie["hooks"])
        #expect(vs.keys == ["source", "frame_hop_s", "lattice_phase_bar", "spans", "first", "last", "intro_free_bars",
                            "intro_kind", "outro_free_bars", "outro_kind", "free_gaps", "exposed_proxy", "rule"])
        #expect(vs["first"]?["pickup"] == .bool(true) && vs["intro_kind"] == .string("beat_only"))
        #expect(vs["rule"]?["threshold_fraction"] == .number(0.25) && vs["rule"]?["bridge_beats"] == .int(8))
        #expect(hooks.keys == ["source", "lattice_phase_bar", "candidates", "rule"])
        let f = try JSONDecoder().decode(FeatureFile.self, from: json.data)
        #expect(f.perBar.vocalProb?.count == a.bars.nBars)
        _ = try JSONDecoder().decode(FeatureFile.Structure.self, from: json.data)
        print("lab JSON deckie.vocal_structure: \(vs.text)\nlab JSON deckie.hooks: \(hooks.text)")
    }

    /// The crate record lists both in `features_present`; the crate validates, writes and reads back the same.
    @Test func crateCarriesThem() async throws {
        let a = try await Shared.shared.run("structure").analysis
        let t = a.crateTrack(options: .init(analysedAt: "2026-10-29T12:00:00Z"))
        #expect(t.featuresPresent.contains("vocal_structure") && t.featuresPresent.contains("hooks"))
        let vs = try #require(t.vocalStructure), h = try #require(t.hooks)
        #expect(vs.source == "yamnet" && vs.first?.pickup == true && vs.introFreeBars == 7 && h.source == "deckie-core")
        #expect(vs.rule.threshold == Py.round(a.vocalStructure!.threshold, 4) && h.candidates.count == a.hooks!.candidates.count)
        let crate = Crate(manifest: CrateManifest(crateId: "engine-vocal-structure", name: "engine vocal structure",
                                                  createdAt: "2026-10-29T12:00:00Z", devicesSeen: [Analysis.platform]),
                          tracks: [t])
        #expect(crate.problems().isEmpty, "\(crate.problems())")
        let folder = try temporaryFolder("crate").appendingPathComponent("vocal-structure.deckiecrate")
        try? FileManager.default.removeItem(at: folder)
        try CrateWriter.write(crate, to: folder)
        let back = try CrateReader.read(from: folder)
        #expect(back == crate)
        let text = try String(contentsOf: folder.appendingPathComponent("crate.json"), encoding: .utf8)
        #expect(text.contains(#""vocal_structure":{"#) && text.contains(#""hooks":{"#))
        print("crate record with the vocal structure: features \(t.featuresPresent); "
              + "\(text.utf8.count) bytes of crate.json")
    }
}

/// The engine without a vocal tagger, and with a tagger that gives bars only (`StubVocalTagger`), on the engine's test
/// track; these need ONNX Runtime and the Beat This! model, not YAMNet.
@Suite(.enabled(if: Available.engine, "needs ONNX Runtime and the Beat This! model"))
struct VocalStructureWithoutFramesTests {
    /// Without a tagger there is neither: no blocks, nulls under `deckie`, and `vocal_unknown` stays.
    @Test func noTaggerNoStructure() async throws {
        let a = try await Shared.shared.run("wav").analysis
        #expect(a.vocalStructure == nil && a.hooks == nil && a.flags.contains("vocal_unknown"))
        let json = a.labJSON()
        #expect(json["deckie"]?["vocal_structure"] == .null && json["deckie"]?["hooks"] == .null)
        let t = a.crateTrack(options: .init(analysedAt: "2026-10-29T12:00:00Z"))
        #expect(t.vocalStructure == nil && t.hooks == nil)
        #expect(!t.featuresPresent.contains("vocal_structure") && !t.featuresPresent.contains("hooks"))
        let crate = Crate(manifest: CrateManifest(crateId: "engine-no-tagger", name: "no tagger",
                                                  createdAt: "2026-10-29T12:00:00Z", devicesSeen: []), tracks: [t])
        let text = String(decoding: try CrateWriter.encode(crate)["crate.json"]!, as: UTF8.self)
        #expect(!text.contains("vocal_structure") && !text.contains("hooks"))
    }

    /// A tagger with bars only (the stub: singing over bars 9 to 24) gives a structure at bar resolution.
    @Test func barsOnlyTagger() async throws {
        let a = try await Shared.shared.run("vocal").analysis
        let s = try #require(a.vocalStructure)
        #expect(s.spans.map { [$0.start.bar, $0.start.beat, $0.end.bar, $0.end.beat] } == [[9, 1, 25, 1]])
        #expect(!s.pickup && s.introFreeBars == 8 && s.frameHopSeconds == a.bars.barS)
        // The test track fades over its last 8 bars, after the free outro's first bars.
        #expect(s.outroFreeBars == a.bars.nBars - 24)
        #expect(a.hooks != nil)
    }
}
