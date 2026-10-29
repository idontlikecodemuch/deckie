import Foundation
import Testing
import DeckieAudio
import DeckieCore
import DeckieCrate
import DeckieEngine
import DeckieInference
import DeckieLab
import DeckieTestSupport

extension Available {
    /// The engine's models and YAMNet's.
    static let yamnet: Bool = {
        guard engine else { return false }
        let missing = DeckieVocalTagger.missingModels()
        if !missing.isEmpty { print("\(missing.map(\.description).joined(separator: "; ")): the engine's vocal tests are skipped") }
        return missing.isEmpty
    }()
}

/// Where the YAMNet model is missing (and ONNX Runtime and Beat This! are there), the default analyser runs without
/// a vocal tagger and says why; its records are the "wav" run's of `EngineTests`, without a vocal block.
@Suite(.enabled(if: Available.engine && !DeckieVocalTagger.missingModels().isEmpty, "runs only where the YAMNet model is missing"))
struct NoVocalModelTests {
    @Test func defaultAnalyserRunsWithoutTheTagger() throws {
        let analyser = try Analyser()
        let note = try #require(analyser.vocalTaggerNote)
        print("default analyser without the model: \(note)")
        #expect(analyser.vocalTagger == nil && note.contains(YAMNet.modelEnvironmentVariable))
    }
}

/// The engine with Deckie's vocal tagger, on the vocal test track (`VocalTrack`: alternate 8-bar stretches of drums
/// and chords, and the same with a sung-like line, stereo at 44.1 kHz, 63 s).
@Suite(.enabled(if: Available.yamnet, "needs ONNX Runtime, the Beat This! model and the YAMNet model (core/Tools/fetch-vocal-models.sh)"))
struct VocalEngineTests {
    /// The default analyser loads YAMNet, and the record carries the vocal block, the per-bar vocal probability, the
    /// tagger's detail, and no `vocal_unknown`; the vocal bars score above the instrumental bars.
    @Test func defaultAnalyserTagsVocals() async throws {
        let analyser = try Analyser()
        #expect(analyser.vocalTagger?.modelName == "yamnet" && analyser.vocalTaggerNote == nil)
        let run = try await Shared.shared.run("yamnet")
        let a = run.analysis
        print(describe(a))
        let v = try #require(a.vocal)
        let n = a.bars.nBars
        #expect(abs(a.bpm - VocalTrack.bpm) < 0.5 && abs(a.bars.firstDownbeatS - VocalTrack.firstBeat) < 0.03)
        #expect(a.perBar.vocalProb?.count == n && v.perBar.count == n && !a.flags.contains("vocal_unknown"))
        #expect(a.vocalModel == "yamnet" && a.timings.contains { $0.stage == "vocal" })
        #expect(v.frameHopSeconds == 0.48 && v.frameCentreSeconds == 0.4875)
        #expect(v.seriesPerBar["singing"]?.count == n && v.style?.count == 1024)
        // The bars of the grid are the track's bars (bar 1 at the first beat): the voice's bars against the others.
        let bars = Array(0..<min(n, VocalTrack.bars))
        let vocalBars = bars.filter { VocalTrack.isVocal(bar: $0) }.map { v.perBar[$0] }
        let otherBars = bars.filter { !VocalTrack.isVocal(bar: $0) }.map { v.perBar[$0] }
        let vm = vocalBars.reduce(0, +) / Double(vocalBars.count), om = otherBars.reduce(0, +) / Double(otherBars.count)
        let stage = a.timings.first { $0.stage == "vocal" }?.seconds ?? 0
        print("""
            engine with YAMNet: vocal bars \(Py.fixed(vm, 4)), instrumental bars \(Py.fixed(om, 4)); mean_prob \
            \(Py.fixed(v.meanProbability, 4)), \(v.frameCount) patches; the vocal stage \(Py.fixed(stage, 2)) s \
            (\(v.stages.map { "\($0.name) \(Py.fixed($0.seconds, 2))" }.joined(separator: ", "))); analyse took \
            \(Py.fixed(run.seconds, 2)) s
            """)
        #expect(vm > 5 * om && vm - om > 0.005)
    }

    /// The lab JSON has the lab's vocal fields (`vocal`, `per_bar.vocal_prob`) and the tagger's detail under `deckie`,
    /// never `embedding_effnet`; it decodes as the lab's feature file, and loads as the lab's scorer loads a track.
    @Test func labJSONCarriesTheVocalBlock() async throws {
        let a = try await Shared.shared.run("yamnet").analysis
        let json = a.labJSON()
        let labURL = repositoryRoot.appendingPathComponent("mixer/features/0327cf1c94.json")
        let lab = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: labURL)) as? [String: Any])
        let ours = try #require(try JSONSerialization.jsonObject(with: json.data) as? [String: Any])
        #expect(Set(ours.keys) == Set(lab.keys).subtracting(["embedding_effnet"]).union(["deckie"]))
        let vocal = try #require(ours["vocal"] as? [String: Any]), labVocal = try #require(lab["vocal"] as? [String: Any])
        #expect(Set(vocal.keys) == Set(labVocal.keys))
        let perBar = try #require(ours["per_bar"] as? [String: Any]), labPerBar = try #require(lab["per_bar"] as? [String: Any])
        #expect(Set(perBar.keys) == Set(labPerBar.keys))
        #expect(json["vocal"]?["n_patches"] == .int(a.vocal!.frameCount) && json["vocal"]?["patch_hop_s"] == .number(0.48))
        #expect(json["vocal"]?["vocal_heavy"] == .bool(false))
        let deckie = try #require((ours["deckie"] as? [String: Any])?["vocal"] as? [String: Any])
        #expect((deckie["singing_prob"] as? [Any])?.count == a.bars.nBars && (deckie["style"] as? [Any])?.count == 1024)
        #expect(deckie["model"] as? String == "yamnet" && (deckie["rule"] as? String)?.hasPrefix("max of") == true)
        #expect(json["deckie"]?["vocal_unknown"] == .bool(false))
        // The lab's readers: the feature file, its structure fields, and the scorer's track.
        let f = try JSONDecoder().decode(FeatureFile.self, from: json.data)
        #expect(f.perBar.vocalProb?.count == a.bars.nBars && f.embeddingEffnet == nil)
        _ = try JSONDecoder().decode(FeatureFile.Structure.self, from: json.data)
        let t = LabLoader.track(from: f, [:])
        #expect(t.vocIn.count == a.mixIn.endBar - a.mixIn.startBar && t.vocOut.count == a.mixOut.endBar - a.mixOut.startBar)
        #expect(t.embedding.isEmpty && t.nBars == a.bars.nBars)
        print("lab-shaped record with the vocal block: \(json.data.count) bytes; vocal \(json["vocal"]!.text); "
              + "scorer's track: voc_in \(t.vocIn.map { Py.fixed($0, 3) }), voc_out \(t.vocOut.map { Py.fixed($0, 3) })")
    }

    /// The crate record: the vocal block, the vocal series and the style vector, listed in `features_present`; the
    /// crate validates, writes and reads back.
    @Test func crateCarriesVocalAndStyle() async throws {
        let a = try await Shared.shared.run("yamnet").analysis
        let t = a.crateTrack(options: .init(analysedAt: "2026-10-29T12:00:00Z"))
        #expect(t.featuresPresent.contains("vocal") && t.featuresPresent.contains("bars.vocal") && t.featuresPresent.contains("style"))
        #expect(t.vocal?.source == "yamnet" && t.style?.model == "yamnet" && t.style?.dims == 1024)
        #expect(t.engine.models.map(\.name) == [Analysis.gridSource, "yamnet"])
        #expect(t.mixIn?.vocalFreeBars != nil && !t.flags.contains("vocal_unknown"))
        let crate = Crate(manifest: CrateManifest(crateId: "engine-vocal-test", name: "engine vocal test",
                                                  createdAt: "2026-10-29T12:00:00Z", devicesSeen: [Analysis.platform]),
                          tracks: [t])
        #expect(crate.problems().isEmpty, "\(crate.problems())")
        let folder = try temporaryFolder("crate").appendingPathComponent("vocal.deckiecrate")
        try? FileManager.default.removeItem(at: folder)
        try CrateWriter.write(crate, to: folder)
        let back = try CrateReader.read(from: folder)
        #expect(back == crate)
        print("crate record with YAMNet: features \(t.featuresPresent)")
    }
}
