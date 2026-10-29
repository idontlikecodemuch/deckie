import Foundation
import DeckieCore
import DeckieInference

/// A second vocal model's opinion in full, beside the vocal tagger's (`Analyser.secondOpinion`; PANNs when its model
/// file is there): its vocal score averaged into the same bars as the tagger's, the four readings of its class scores
/// (`VocalReadings`, as the tagger's are read) and its other per-patch series (PANNs: singing, speech, music) averaged
/// the same way, and where its patches sit. A research record: the lab JSON writes it in `deckie.vocal.second_opinion`, the vocal block's
/// `SecondOpinion` carries its summary (model, bars, mean), and nothing else reads it. It changes nothing else in the
/// record, and nothing of it goes into the crate.
public struct VocalSecondOpinion: Sendable, Equatable {
    /// The model's name (`panns-mobilenetv2`).
    public var model: String
    /// How a patch's vocal score is made, in words, when the model says (`VocalRuleDescribing`).
    public var rule: String?
    /// One vocal probability per bar, as the tagger's are made from its patches (`PatchBars.average`).
    public var perBar: [Double]
    /// The mean of all patches' vocal scores.
    public var meanProbability: Double
    public var patchHopSeconds: Double
    public var patchCentreSeconds: Double
    public var patchCount: Int
    /// The four readings of the model's class scores, one value per bar each, with the classes each read; nil when
    /// the model gives no class scores.
    public var readings: VocalReadings?
    /// The model's other per-patch series averaged into bars, by name.
    public var seriesPerBar: [String: [Double]]
    /// The model's steps and their seconds, in order.
    public var stages: [VocalActivity.Stage]

    /// The time it took, all steps.
    public var seconds: Double { stages.reduce(0) { $0 + $1.seconds } }

    /// The summary the vocal block carries.
    public var summary: VocalActivity.SecondOpinion {
        .init(model: model, perBar: perBar, meanProbability: meanProbability)
    }

    public init(model: String, rule: String?, perBar: [Double], meanProbability: Double, patchHopSeconds: Double,
                patchCentreSeconds: Double, patchCount: Int, readings: VocalReadings?, seriesPerBar: [String: [Double]],
                stages: [VocalActivity.Stage]) {
        self.model = model; self.rule = rule; self.perBar = perBar; self.meanProbability = meanProbability
        self.patchHopSeconds = patchHopSeconds; self.patchCentreSeconds = patchCentreSeconds
        self.patchCount = patchCount; self.readings = readings; self.seriesPerBar = seriesPerBar; self.stages = stages
    }

    /// `model` on `mono` (at `sampleRate`), its patches averaged into the bars whose lines are `barTimes`.
    public static func run(_ model: any VocalPatchModel, mono: [Float], sampleRate: Int,
                           barTimes: [Double]) throws -> VocalSecondOpinion {
        let p = try model.vocalPatches(mono: mono, sampleRate: sampleRate)
        func bars(_ values: [Double]) -> [Double] {
            PatchBars.average(values, hop: p.hopSeconds, centreOffset: p.centreSeconds, barTimes: barTimes)
        }
        return VocalSecondOpinion(
            model: model.name, rule: (model as? any VocalRuleDescribing)?.vocalRuleText, perBar: bars(p.vocal),
            meanProbability: p.vocal.isEmpty ? 0 : p.vocal.reduce(0, +) / Double(p.vocal.count),
            patchHopSeconds: p.hopSeconds, patchCentreSeconds: p.centreSeconds, patchCount: p.vocal.count,
            readings: p.readings(barTimes: barTimes), seriesPerBar: p.series.mapValues(bars),
            stages: p.timing.map { .init($0.name, $0.seconds) })
    }
}

extension Analysis {
    /// `deckie.vocal.second_opinion`: null without a second opinion; the model, its mean and its bars when only the
    /// vocal block's summary is there (a tagger that gives one itself); and with the analyser's second model
    /// (`vocalSecondOpinion`), also its rule, its patch timing, the four readings each as a per-bar list of its own
    /// (`max11`, `voice_sum`, `voice_logit_sum`, `voice_vs_music`, `Analysis.readingsDecimals` decimals, as
    /// `deckie.vocal.readings`; flat beside `per_bar`, so a reader that scores every per-bar list of the block, as
    /// mixer/vocal3way.py does, scores them too) with `readings_classes` as `deckie.vocal` has it (the note is
    /// `deckie.vocal`'s), its other series as `<name>_prob` (3 decimals, as the bars) and its own step times.
    func secondOpinionBlock(_ v: VocalActivity) -> JSONValue {
        typealias J = JSONValue
        func m(_ k: String, _ value: J) -> J.Member { J.Member(k, value) }
        guard let s = vocalSecondOpinion else {
            return v.secondOpinion.map {
                .object([m("model", .string($0.model)), m("mean_prob", J.round($0.meanProbability, 4)),
                         m("per_bar", J.roundList($0.perBar, 3))])
            } ?? .null
        }
        var members = [m("model", .string(s.model)), m("rule", J.text(s.rule)), m("mean_prob", J.round(s.meanProbability, 4)),
                       m("per_bar", J.roundList(s.perBar, 3)), m("patch_hop_s", J.round(s.patchHopSeconds, 4)),
                       m("patch_centre_s", J.round(s.patchCentreSeconds, 4)), m("n_patches", .int(s.patchCount))]
        if s.readings != nil {
            for member in readingsMembers(s.readings) {
                switch member.key {
                case "readings": if case .object(let series) = member.value { members += series }
                case "readings_classes": members.append(member)
                default: break
                }
            }
        }
        for name in s.seriesPerBar.keys.sorted() {
            members.append(m("\(name)_prob", J.roundList(s.seriesPerBar[name]!, 3)))
        }
        members.append(m("timing_s", .object(s.stages.map { m($0.name, J.round($0.seconds, 3)) })))
        return .object(members)
    }
}
