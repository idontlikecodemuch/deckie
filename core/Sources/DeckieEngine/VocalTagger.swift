import Foundation

/// Vocal activity over a track, as a vocal tagger reports it: what the lab's Discogs-EffNet voice head gives
/// (mixer/analyze.py, "vocal probability + embedding"), without the embedding, which is non-commercial and never
/// enters a crate.
public struct VocalActivity: Sendable, Equatable {
    /// One probability per bar of the grid, 0 to 1 (the lab's `per_bar.vocal_prob`): the mean of the tagger's frames
    /// centred in the bar, or the value interpolated at the bar's middle when none is.
    public var perBar: [Double]
    /// The mean over all the tagger's frames (the lab's `vocal.mean_prob`; above 0.75 the track is `vocal_heavy`).
    public var meanProbability: Double
    /// Seconds between the tagger's frames (the lab's `vocal.patch_hop_s`, 0.992 for EffNet).
    public var frameHopSeconds: Double
    /// How many frames the tagger produced (the lab's `vocal.n_patches`).
    public var frameCount: Int

    public init(perBar: [Double], meanProbability: Double, frameHopSeconds: Double, frameCount: Int) {
        self.perBar = perBar
        self.meanProbability = meanProbability
        self.frameHopSeconds = frameHopSeconds
        self.frameCount = frameCount
    }
}

/// A vocal tagger: mono audio in, the probability of singing per bar out. None ships yet: the permissive model is
/// waiting for approval, so the engine runs without one, writes no vocal block, and places the mix windows treating
/// every bar as vocal-free, flagging the record `vocal_unknown` so the windows are recomputed when a tagger lands.
/// Given a tagger, the `Analyser` feeds its per-bar values to the sections, the mix windows and the flags exactly as the
/// lab feeds its EffNet values.
public protocol VocalTagger: Sendable {
    /// The model's name, as the crate's `engine.models` and the vocal block's `source` give it.
    var modelName: String { get }
    /// The vocal activity of `mono` (the channels' mean, at `sampleRate`) over the bars whose lines are `barTimes`
    /// (seconds, one more than there are bars; bar k spans `barTimes[k]..<barTimes[k + 1]`).
    func vocalActivity(mono: [Float], sampleRate: Int, barTimes: [Double]) throws -> VocalActivity
}
