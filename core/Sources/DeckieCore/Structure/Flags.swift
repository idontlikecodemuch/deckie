import Foundation

/// The lab's per-track flags (mixer/analyze.py, "flags"), in the lab's order, followed by the local-tempo flags.
public enum TrackFlags {
    /// The flags of a track:
    /// - `half_time_candidate`: the grid tempo `bpm` is under 100, or its nearest relation to the tag tempo `bpmTag`
    ///   among 1/2, 2/3, 3/4, 1, 4/3, 3/2 and 2 is not 1 (no tag, or a tag of 0, counts as 1);
    /// - `vocal_heavy`: the track's mean vocal probability (over all patches, `vocal.mean_prob`) is above 0.75;
    /// - `fade_out`: the fade-out decision;
    /// - `low_grid_confidence`: the chosen grid's confidence is under 0.5;
    /// - `key_uncertain`: the key confidence is under 0.5;
    /// - `short_intro` / `short_outro`: the window is under 16 bars or has under 8 vocal-free bars.
    /// `localTempoFlags`, the names mixer/local_tempo.py's `flags` gives, follow in their order, each once.
    public static func flags(bpm: Double, bpmTag: Double?, vocalMeanProb: Double, fadeOut: Bool, gridConfidence: Double,
                             keyConfidence: Double, mixIn: MixIn, mixOut: MixOut, localTempoFlags: [String] = [])
        -> [String] {
        var f: [String] = []
        var multTag = 1.0
        if let tag = bpmTag, tag != 0 { multTag = Tempo.closest(bpm: bpm, reference: tag).multiplier }
        if bpm < 100 || abs(multTag - 1.0) > 1e-6 { f.append("half_time_candidate") }
        if vocalMeanProb > 0.75 { f.append("vocal_heavy") }
        if fadeOut { f.append("fade_out") }
        if gridConfidence < 0.5 { f.append("low_grid_confidence") }
        if keyConfidence < 0.5 { f.append("key_uncertain") }
        if mixIn.bars < 16 || mixIn.vocalFreeBars < 8 { f.append("short_intro") }
        if mixOut.bars < 16 || mixOut.vocalFreeBars < 8 { f.append("short_outro") }
        for name in localTempoFlags where !f.contains(name) { f.append(name) }
        return f
    }
}
