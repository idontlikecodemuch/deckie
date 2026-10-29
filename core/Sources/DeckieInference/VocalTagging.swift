import Foundation
import DeckieAudio
import DeckieCore

/// A vocal model's opinion patch by patch: the vocal score of each patch (0 to 1, the model's rule already applied),
/// other per-patch series it can give, and a style embedding if it has one.
public struct VocalPatches: Sendable, Equatable {
    /// The patches' vocal scores.
    public var vocal: [Double]
    /// Other per-patch series by name (YAMNet: `singing`, `rapping`, `choir`, `speech`, `music`), each as long as
    /// `vocal`.
    public var series: [String: [Double]]
    /// The style embedding of the whole piece (unit length), if the model gives one.
    public var style: [Double]?
    /// Seconds between patches, and from the start of the audio to the middle of patch 0.
    public var hopSeconds: Double
    public var centreSeconds: Double
    /// Where the time went, in order.
    public var timing: [VocalTagging.Stage]

    public init(vocal: [Double], series: [String: [Double]], style: [Double]?, hopSeconds: Double, centreSeconds: Double,
                timing: [VocalTagging.Stage]) {
        self.vocal = vocal; self.series = series; self.style = style; self.hopSeconds = hopSeconds
        self.centreSeconds = centreSeconds; self.timing = timing
    }
}

/// A model that scores vocal activity patch by patch. YAMNet is the one Deckie runs; the seam is here so a second
/// model can be added beside it as a second opinion (PANNs' MobileNetV2, MIT code and CC BY 4.0 weights, if the
/// yardstick on the Mac shows YAMNet alone reads badly) without touching the averaging or the engine.
public protocol VocalPatchModel: Sendable {
    /// The model's name, as records give it.
    var name: String { get }
    /// The vocal scores and the rest for mono audio at `sampleRate`.
    func vocalPatches(mono: [Float], sampleRate: Int) throws -> VocalPatches
}

extension YAMNet: VocalPatchModel {
    public var name: String { Self.modelName }

    /// The classes whose scores make the vocal score: every kind of singing YAMNet knows (singing, choir, yodelling,
    /// chant, mantra, child singing, synthetic singing), rapping, humming, and the two vocal-music genres (vocal music,
    /// a cappella). Speech is left out: the lab's vocal is the voice that sings or raps over the music, the kind that
    /// clashes in a mix; YAMNet's speech score is recorded beside it for the yardstick to judge (`speech`).
    public static let vocalClasses: [YAMNetClass] = [.singing, .choir, .yodelling, .chant, .mantra, .childSinging,
                                                     .syntheticSinging, .rapping, .humming, .vocalMusic, .aCappella]

    /// The rule, in words, as records give it.
    public static let vocalRule = "max of the yamnet scores for " + vocalClasses.map(\.name).joined(separator: ", ")

    /// A patch's vocal score: the largest of its `vocalClasses` scores. The scores are sigmoids of a multi-label
    /// classifier and the classes fire together on one voice (a sung line scores as singing and as vocal music), so a
    /// sum would count one voice several times; the largest is already between 0 and 1. Not calibrated: the
    /// thresholds the lab applies (0.5 for a vocal bar, 0.75 for a vocal-heavy track) were tuned on its EffNet head,
    /// and track J's listening test on the Mac sets this one's.
    public static func vocalScore(_ p: YAMNetPatches, patch k: Int) -> Double {
        vocalClasses.reduce(0.0) { max($0, Double(p.score(k, $1))) }
    }

    public func vocalPatches(mono: [Float], sampleRate: Int) throws -> VocalPatches {
        let r = try analyse(mono: mono, sampleRate: sampleRate)
        let t0 = Date()
        let p = r.patches
        let vocal = (0..<p.count).map { Self.vocalScore(p, patch: $0) }
        // Sung, rapped, choral and spoken apart (research O: rap over rap is the worst clash), and music.
        let series = ["singing": p.scores(.singing), "rapping": p.scores(.rapping), "choir": p.scores(.choir),
                      "speech": p.scores(.speech), "music": p.scores(.music)]
        let style = p.meanEmbedding()
        let rules = Date().timeIntervalSince(t0)
        return VocalPatches(vocal: vocal, series: series, style: style, hopSeconds: YAMNetFrontEnd.patchHopSeconds,
                            centreSeconds: YAMNetFrontEnd.patchCentreSeconds,
                            timing: [.init("resample", r.timing.resampling), .init("front_end", r.timing.frontEnd),
                                     .init("model", r.timing.model), .init("scores", rules)])
    }
}

/// A track's vocal activity, bar by bar, as the vocal tagger reports it.
public struct VocalTagging: Sendable, Equatable {
    /// A step and its wall-clock seconds.
    public struct Stage: Sendable, Equatable {
        public var name: String
        public var seconds: Double
        public init(_ name: String, _ seconds: Double) { self.name = name; self.seconds = seconds }
    }

    /// A second model's opinion, averaged into the same bars.
    public struct Opinion: Sendable, Equatable {
        public var model: String
        public var perBar: [Double]
        public var meanProbability: Double
    }

    /// The model's name (`yamnet`).
    public var model: String
    /// The rule that makes a patch's vocal score, in words.
    public var rule: String
    /// One vocal probability per bar: the patches' vocal scores averaged into bars as the lab averages its EffNet
    /// patches (`PatchBars`).
    public var perBar: [Double]
    /// The mean of all patches' vocal scores (the lab's `vocal.mean_prob`).
    public var meanProbability: Double
    public var patchHopSeconds: Double
    public var patchCentreSeconds: Double
    public var patchCount: Int
    /// The patches' own vocal scores, in order (patch k centred at `patchCentreSeconds + k patchHopSeconds`): finer
    /// than a bar, so the engine can find where a sung stretch starts and ends to the beat (`VocalStructure`).
    public var perPatch: [Double]
    /// The model's other per-patch series averaged into bars the same way (`singing`, `rapping`, `choir`, `speech`,
    /// `music`).
    public var seriesPerBar: [String: [Double]]
    /// The style vector (unit length) and the model that gave it.
    public var style: [Double]?
    public var styleModel: String?
    /// The second opinion, when a second model is set.
    public var secondOpinion: Opinion?
    public var timing: [Stage]
}

/// Deckie's vocal tagger: YAMNet's vocal score per patch (`YAMNet.vocalScore`), averaged into the bars of the grid as
/// the lab averages its EffNet voice probabilities, with YAMNet's singing, rapping, choir, speech and music scores per
/// bar beside it and the mean of its embeddings as the track's style vector. The engine (DeckieEngine) uses it through its `VocalTagger`
/// protocol; `loadDefault()` finds the model where core/Tools/fetch-vocal-models.sh puts it, and says what is missing
/// when it is not there, so the analyser runs without a vocal block.
public final class DeckieVocalTagger: Sendable {
    public let yamnet: YAMNet
    /// A second model whose per-bar opinion is recorded beside YAMNet's (none is built yet; see `VocalPatchModel`).
    public let secondOpinion: (any VocalPatchModel)?

    public init(yamnet: YAMNet, secondOpinion: (any VocalPatchModel)? = nil) {
        self.yamnet = yamnet
        self.secondOpinion = secondOpinion
    }

    /// The models' names: `yamnet`, or `yamnet+<second>` with a second opinion.
    public var modelName: String { secondOpinion.map { "\(YAMNet.modelName)+\($0.name)" } ?? YAMNet.modelName }

    /// A model the tagger needs that is not where it is looked for: its name, where it was looked for, and what to do.
    public struct MissingModel: Sendable, Equatable, CustomStringConvertible {
        public var name: String
        public var searched: [String]
        public var remedy: String
        public var description: String {
            "\(name) model not found (looked at: \(searched.joined(separator: ", "))); \(remedy)"
        }
    }

    /// The models that are not there (empty when the tagger can load).
    public static func missingModels() -> [MissingModel] {
        guard YAMNet.locateModel() == nil else { return [] }
        return [MissingModel(name: "YAMNet", searched: YAMNet.modelCandidates(),
                             remedy: "run core/Tools/fetch-vocal-models.sh or set \(YAMNet.modelEnvironmentVariable)")]
    }

    /// The tagger with the model from where it is looked for, or nil when the model is not there (`missingModels()`
    /// says why). A model that is there but does not load is an error.
    public static func loadDefault(runtime: OnnxRuntime? = nil) throws -> DeckieVocalTagger? {
        guard let path = YAMNet.locateModel() else { return nil }
        return DeckieVocalTagger(yamnet: try YAMNet(modelPath: path, runtime: runtime))
    }

    /// The vocal activity of `mono` (at `sampleRate`) over the bars whose lines are `barTimes` (seconds, one more than
    /// there are bars).
    public func tag(mono: [Float], sampleRate: Int, barTimes: [Double]) throws -> VocalTagging {
        let p = try yamnet.vocalPatches(mono: mono, sampleRate: sampleRate)
        func bars(_ values: [Double], _ q: VocalPatches) -> [Double] {
            PatchBars.average(values, hop: q.hopSeconds, centreOffset: q.centreSeconds, barTimes: barTimes)
        }
        let mean = p.vocal.isEmpty ? 0 : p.vocal.reduce(0, +) / Double(p.vocal.count)
        var timing = p.timing
        var opinion: VocalTagging.Opinion? = nil
        if let second = secondOpinion {
            let t0 = Date()
            let q = try second.vocalPatches(mono: mono, sampleRate: sampleRate)
            opinion = .init(model: second.name, perBar: bars(q.vocal, q),
                            meanProbability: q.vocal.isEmpty ? 0 : q.vocal.reduce(0, +) / Double(q.vocal.count))
            timing.append(.init(second.name, Date().timeIntervalSince(t0)))
        }
        return VocalTagging(model: YAMNet.modelName, rule: YAMNet.vocalRule, perBar: bars(p.vocal, p),
                            meanProbability: mean, patchHopSeconds: p.hopSeconds, patchCentreSeconds: p.centreSeconds,
                            patchCount: p.vocal.count, perPatch: p.vocal, seriesPerBar: p.series.mapValues { bars($0, p) },
                            style: p.style, styleModel: p.style == nil ? nil : YAMNet.modelName,
                            secondOpinion: opinion, timing: timing)
    }
}
