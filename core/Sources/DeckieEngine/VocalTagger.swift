import Foundation
import DeckieInference

/// Vocal activity over a track, as a vocal tagger reports it: what the lab's Discogs-EffNet voice head gives
/// (mixer/analyze.py, "vocal probability + embedding"), in the lab's shape (one 0-to-1 value per bar, the lab's
/// patch-to-bar averaging), with the tagger's own extras beside it. The lab's EffNet embedding is non-commercial and
/// never enters a record; a tagger's own style vector (YAMNet's) may.
public struct VocalActivity: Sendable, Equatable {
    /// A second model's per-bar opinion.
    public struct SecondOpinion: Sendable, Equatable {
        public var model: String
        public var perBar: [Double]
        public var meanProbability: Double
        public init(model: String, perBar: [Double], meanProbability: Double) {
            self.model = model; self.perBar = perBar; self.meanProbability = meanProbability
        }
    }

    /// A step of the tagger and its wall-clock seconds.
    public struct Stage: Sendable, Equatable {
        public var name: String
        public var seconds: Double
        public init(_ name: String, _ seconds: Double) { self.name = name; self.seconds = seconds }
    }

    /// One probability per bar of the grid, 0 to 1 (the lab's `per_bar.vocal_prob`): the mean of the tagger's frames
    /// centred in the bar, or the value interpolated at the bar's middle when none is.
    public var perBar: [Double]
    /// The mean over all the tagger's frames (the lab's `vocal.mean_prob`; above 0.75 the track is `vocal_heavy`).
    public var meanProbability: Double
    /// Seconds between the tagger's frames (the lab's `vocal.patch_hop_s`, 0.992 for EffNet, 0.48 for YAMNet).
    public var frameHopSeconds: Double
    /// How many frames the tagger produced (the lab's `vocal.n_patches`).
    public var frameCount: Int
    /// Seconds from the start of the audio to the middle of frame 0 (1.024 for EffNet, 0.4875 for YAMNet); nil when
    /// the tagger does not say.
    public var frameCentreSeconds: Double?
    /// How a frame's vocal score is made, in words; nil when the tagger does not say.
    public var rule: String?
    /// The vocal score of each frame, in order (frame k centred at `frameCentreSeconds + k frameHopSeconds`), finer
    /// than a bar: where a sung stretch starts and ends is read from it to the beat (`VocalStructure`). Nil when the
    /// tagger gives bars only; the vocal structure then works from `perBar`, at bar resolution.
    public var perFrame: [Double]?
    /// Other per-bar series the tagger gives, averaged into bars as `perBar` is, by name (YAMNet: `singing`,
    /// `rapping`, `choir`, `speech`, `music`); the lab JSON writes them in its `deckie.vocal` block as `<name>_prob`.
    public var seriesPerBar: [String: [Double]]
    /// The track's style vector (unit length) and the model that made it: the crate's `style` block.
    public var style: [Double]?
    public var styleModel: String?
    public var secondOpinion: SecondOpinion?
    /// The tagger's steps, in order.
    public var stages: [Stage]

    public init(perBar: [Double], meanProbability: Double, frameHopSeconds: Double, frameCount: Int,
                frameCentreSeconds: Double? = nil, rule: String? = nil, perFrame: [Double]? = nil,
                seriesPerBar: [String: [Double]] = [:], style: [Double]? = nil, styleModel: String? = nil,
                secondOpinion: SecondOpinion? = nil, stages: [Stage] = []) {
        self.perBar = perBar
        self.meanProbability = meanProbability
        self.frameHopSeconds = frameHopSeconds
        self.frameCount = frameCount
        self.frameCentreSeconds = frameCentreSeconds
        self.rule = rule
        self.perFrame = perFrame
        self.seriesPerBar = seriesPerBar
        self.style = style
        self.styleModel = styleModel
        self.secondOpinion = secondOpinion
        self.stages = stages
    }
}

/// A vocal tagger: mono audio in, the probability of singing per bar out. Deckie's is `DeckieVocalTagger`
/// (DeckieInference: YAMNet), which `Analyser`'s default construction loads when its model is where
/// core/Tools/fetch-vocal-models.sh puts it. Without one the engine runs on, writes no vocal block, and places the
/// mix windows treating every bar as vocal-free, flagging the record `vocal_unknown` so the windows are recomputed
/// when a tagger runs. Given a tagger, the `Analyser` feeds its per-bar values to the sections, the mix windows and the
/// flags exactly as the lab feeds its EffNet values.
public protocol VocalTagger: Sendable {
    /// The model's name, as the crate's `engine.models` and the vocal block's `source` give it.
    var modelName: String { get }
    /// The vocal activity of `mono` (the channels' mean, at `sampleRate`) over the bars whose lines are `barTimes`
    /// (seconds, one more than there are bars; bar k spans `barTimes[k]..<barTimes[k + 1]`).
    func vocalActivity(mono: [Float], sampleRate: Int, barTimes: [Double]) throws -> VocalActivity
}

extension DeckieVocalTagger: VocalTagger {
    /// YAMNet's vocal score per bar and per patch, its singing, rapping, choir, speech and music scores per bar, and
    /// its mean embedding as the style vector (`DeckieVocalTagger.tag`).
    public func vocalActivity(mono: [Float], sampleRate: Int, barTimes: [Double]) throws -> VocalActivity {
        let t = try tag(mono: mono, sampleRate: sampleRate, barTimes: barTimes)
        return VocalActivity(
            perBar: t.perBar, meanProbability: t.meanProbability, frameHopSeconds: t.patchHopSeconds,
            frameCount: t.patchCount, frameCentreSeconds: t.patchCentreSeconds, rule: t.rule, perFrame: t.perPatch,
            seriesPerBar: t.seriesPerBar, style: t.style, styleModel: t.styleModel,
            secondOpinion: t.secondOpinion.map { .init(model: $0.model, perBar: $0.perBar, meanProbability: $0.meanProbability) },
            stages: t.timing.map { .init($0.name, $0.seconds) })
    }
}
