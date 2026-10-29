import Foundation
import Testing
import DeckieAudio
import DeckieCore
import DeckieCrate
import DeckieEngine
import DeckieInference
import DeckieTestSupport

extension Available {
    /// The engine's models, YAMNet's and PANNs'.
    static let panns: Bool = {
        guard yamnet else { return false }  // Available.yamnet has printed why
        if PANNs.locateModel() == nil {
            print("\(PANNsError.modelNotFound(searched: PANNs.modelCandidates())): the engine's second-opinion test with PANNs is skipped")
            return false
        }
        return true
    }()
}

/// A second vocal model for the tests: patches every 0.5 s centred from 0.25 s, singing from 20 to 40 s, with two
/// named classes (Singing at the vocal score, Music at 0.5) and a singing series.
struct StubPatchModel: VocalPatchModel, VocalRuleDescribing {
    var name: String { "stub-second" }
    var vocalRuleText: String { "0.7 from 20 to 40 s, else 0.05" }
    func vocalPatches(mono: [Float], sampleRate: Int) throws -> VocalPatches {
        let n = Int(Double(mono.count) / Double(sampleRate) / 0.5)
        let vocal = (0..<n).map { k -> Double in let t = 0.25 + 0.5 * Double(k); return t >= 20 && t < 40 ? 0.7 : 0.05 }
        let scores = vocal.flatMap { v -> [Float] in [Float(v), 0.5, 0.25] }
        return VocalPatches(vocal: vocal, series: ["singing": vocal.map { $0 / 2 }], style: nil, hopSeconds: 0.5,
                            centreSeconds: 0.25, timing: [.init("model", 0.01)],
                            classScores: ClassScoreMatrix(patches: n, names: ["Singing", "Music", ""], scores: scores))
    }
}

/// The analyser's second vocal opinion: recorded in the lab JSON's `deckie.vocal.second_opinion`, summarised in the
/// vocal block, and nowhere else: not the tagger's model name, not the stages, not the crate.
@Suite(.enabled(if: Available.engine, "needs ONNX Runtime and the Beat This! model"))
struct SecondOpinionTests {
    /// The test track with the stub tagger and the stub second model.
    @Test func recordedBesideTheTaggerAndNowhereElse() async throws {
        let base = try await Shared.shared.run("vocal").analysis  // the same track with the stub tagger alone
        let (wav, _) = try await Shared.shared.testTrack()
        let analyser = try Analyser(beatTracker: try await Shared.shared.engine().beatTracker,
                                    vocalTagger: StubVocalTagger(), secondOpinion: StubPatchModel())
        #expect(analyser.secondOpinion?.name == "stub-second")
        #expect(try Analyser(beatTracker: analyser.beatTracker, vocalTagger: nil, secondOpinion: StubPatchModel()).secondOpinion == nil)
        let a = try await CPUTurns.exclusive { try analyser.analyse(url: wav, options: AnalysisOptions(title: "Test track")) }
        let n = a.bars.nBars
        let s = try #require(a.vocalSecondOpinion)
        let v = try #require(a.vocal)
        #expect(a.vocalModel == "stub-vocal" && a.timings.map(\.stage) == base.timings.map(\.stage))
        #expect(s.model == "stub-second" && s.perBar.count == n && s.patchHopSeconds == 0.5 && s.patchCentreSeconds == 0.25)
        #expect(v.secondOpinion == s.summary && v.stages.last?.name == "stub-second")
        #expect(Set(s.seriesPerBar.keys) == ["singing"])
        let r = try #require(s.readings)
        #expect(r.max11.count == n && r.classes.max.map(\.name) == ["Singing"] && r.classes.music.map(\.name) == ["Music"])
        // The bars inside 20 to 40 s read 0.7, those wholly outside 0.05; the readings follow (Singing is the only
        // voice class, Music the only music class).
        for b in 0..<n {
            let start = a.bars.barTimes[b], end = a.bars.barTimes[b + 1]
            for (want, inside) in [(0.7, start >= 20.25 && end <= 39.75), (0.05, end <= 19.75 || start >= 40.25)] where inside {
                #expect(abs(s.perBar[b] - want) < 1e-12 && abs(r.max11[b] - want) < 1e-6 && abs(r.voiceSum[b] - want) < 1e-6,
                        "bar \(b)")
                #expect(abs(r.voiceVsMusic[b] - want / (want + 0.5)) < 1e-6, "bar \(b)")
            }
        }

        // The lab JSON's block.
        let json = try #require(try JSONSerialization.jsonObject(with: a.labJSONData()) as? [String: Any])
        let vocal = try #require((json["deckie"] as? [String: Any])?["vocal"] as? [String: Any])
        let block = try #require(vocal["second_opinion"] as? [String: Any])
        #expect(Set(block.keys) == Set(["model", "rule", "mean_prob", "per_bar", "patch_hop_s", "patch_centre_s", "n_patches",
                                        "readings_classes", "singing_prob", "timing_s"] + VocalReadings.names))
        #expect(block["model"] as? String == "stub-second" && block["rule"] as? String == "0.7 from 20 to 40 s, else 0.05")
        #expect((block["per_bar"] as? [Any])?.count == n && (block["singing_prob"] as? [Any])?.count == n)
        // The readings flat beside per_bar, each a per-bar list, as mixer/vocal3way.py scores every list of the block.
        #expect(VocalReadings.names.allSatisfy { (block[$0] as? [Any])?.count == n })
        let classes = try #require(block["readings_classes"] as? [String: Any])
        #expect(Set(classes.keys) == Set(VocalReadings.names))
        #expect((block["timing_s"] as? [String: Any])?.keys.sorted() == ["model"])
        print("second opinion in the lab JSON: \(block.keys.sorted()); per_bar \((block["per_bar"] as? [Double] ?? []).prefix(12))")

        // Nothing of it in the crate: the record is the one made without it.
        var without = a
        without.vocalSecondOpinion = nil
        without.vocal?.secondOpinion = nil
        let options = Analysis.CrateOptions(analysedAt: "2026-10-29T12:00:00Z")
        #expect(a.crateTrack(options: options) == without.crateTrack(options: options))
        // And without the analyser's second opinion the block is the vocal block's summary, or null.
        var summaryOnly = a
        summaryOnly.vocalSecondOpinion = nil
        let summary = summaryOnly.labJSON()["deckie"]?["vocal"]?["second_opinion"]
        #expect(summary?["model"] == .string("stub-second") && summary?["mean_prob"] != nil && summary?["max11"] == nil)
        #expect(without.labJSON()["deckie"]?["vocal"]?["second_opinion"] == .null)
    }
}

/// The default analyser with YAMNet and PANNs on the vocal test track: PANNs' opinion is recorded, the vocal bars above
/// the instrumental bars, and the crate record is the one YAMNet alone makes.
@Suite(.enabled(if: Available.panns, "needs ONNX Runtime, the Beat This! and YAMNet models, and the PANNs model (core/Tools/fetch-panns.sh)"))
struct PANNsSecondOpinionTests {
    @Test func defaultAnalyserRecordsPANNs() async throws {
        let analyser = try Analyser()
        #expect(analyser.vocalTagger?.modelName == "yamnet" && analyser.secondOpinion?.name == PANNs.modelName)
        let a = try await Shared.shared.run("yamnet").analysis
        let s = try #require(a.vocalSecondOpinion)
        let n = a.bars.nBars
        #expect(a.vocalModel == "yamnet" && s.model == PANNs.modelName && s.perBar.count == n)
        #expect(s.rule == PANNs.vocalRule && s.patchHopSeconds == 0.48 && s.patchCentreSeconds == 1)
        let bars = Array(0..<min(n, VocalTrack.bars))
        func means(_ v: [Double]) -> (vocal: Double, other: Double) {
            let vb = bars.filter { VocalTrack.isVocal(bar: $0) }.map { v[$0] }
            let ob = bars.filter { !VocalTrack.isVocal(bar: $0) }.map { v[$0] }
            return (vb.reduce(0, +) / Double(vb.count), ob.reduce(0, +) / Double(ob.count))
        }
        let m = means(s.perBar)
        let readings = (s.readings?.series ?? []).map { ($0.name, means($0.values)) }
        print("engine with PANNs as the second opinion: vocal bars \(Py.fixed(m.vocal, 4)), instrumental bars "
              + "\(Py.fixed(m.other, 4)); " + readings.map { "\($0.0) \(Py.fixed($0.1.vocal, 4)) against \(Py.fixed($0.1.other, 4))" }
                .joined(separator: ", ")
              + "; \(s.patchCount) windows, \(Py.fixed(s.seconds, 2)) s (\(s.stages.map { "\($0.name) \(Py.fixed($0.seconds, 2))" }.joined(separator: ", ")))")
        #expect(m.vocal > 2 * m.other)
        let block = a.labJSON()["deckie"]?["vocal"]?["second_opinion"]
        #expect(block?["model"] == .string(PANNs.modelName) && block?["n_patches"] == .int(s.patchCount))
        for name in VocalReadings.names { #expect(block?[name] != nil, "\(name)") }
        let r = try #require(s.readings)
        #expect(r.classes.missingMax.isEmpty && r.classes.missingVoice.isEmpty && r.classes.missingMusic.isEmpty)
        var without = a
        without.vocalSecondOpinion = nil
        without.vocal?.secondOpinion = nil
        let options = Analysis.CrateOptions(analysedAt: "2026-10-29T12:00:00Z")
        #expect(a.crateTrack(options: options) == without.crateTrack(options: options))
    }
}
