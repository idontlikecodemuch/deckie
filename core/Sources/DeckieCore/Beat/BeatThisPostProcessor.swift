/// Beats and downbeats from Beat This!'s logits: frame positions (50 a second) and times in seconds.
public struct BeatThisBeats: Sendable, Equatable {
    /// Beat positions in frames; a whole number, or a half or third between frames where neighbouring frames tied.
    public var beatFrames: [Double]
    /// Downbeat positions in frames, each one of `beatFrames`.
    public var downbeatFrames: [Double]
    /// `beatFrames` / framesPerSecond.
    public var beats: [Double]
    /// `downbeatFrames` / framesPerSecond.
    public var downbeats: [Double]

    public init(beatFrames: [Double], downbeatFrames: [Double], beats: [Double], downbeats: [Double]) {
        self.beatFrames = beatFrames
        self.downbeatFrames = downbeatFrames
        self.beats = beats
        self.downbeats = downbeats
    }
}

/// Beat This!'s "minimal" postprocessor (beat_this 1.1.0, `model/postprocessor.py`, `Postprocessor(type="minimal")`),
/// which the authors use instead of a dynamic Bayesian network ("without DBN postprocessing" is the paper's point):
///
/// 1. Peaks: frame t is a peak if its logit equals the largest within frames t - 3 ... t + 3 (70 ms each way; the
///    window stops at the piece's ends) and is above 0 (a probability above one half). Compared in float32, as
///    the package compares.
/// 2. Neighbouring peaks: going through the peaks in order, a peak at most one frame after the running mean of the
///    current group joins it (the mean moves); otherwise it starts a new group. Each group becomes its mean, so two
///    tied neighbours give a half-frame position. (Note the comparison is with the mean, not the previous peak: peaks
///    at 10, 11 and 12 give 10.5 and 12.)
/// 3. Seconds: position / 50.
/// 4. Each downbeat moves to the nearest beat by time (the earlier of two equally near), then repeated downbeats
///    are dropped and the rest sorted. With no beats at all, downbeats stay where they are.
///
/// Every step follows the package's arithmetic (float32 comparisons, double-precision means and divisions), so the
/// frames are identical, not merely close (Tests: BeatThisTests, on the package's own output).
public enum BeatThisPostProcessor {
    public static func minimal(_ logits: BeatThisLogits, framesPerSecond fps: Int = BeatThisFrontEnd.framesPerSecond)
        -> BeatThisBeats {
        let beatFrames = deduplicate(peaks(logits.beat))
        let downFrames = deduplicate(peaks(logits.downbeat))
        let rate = Double(fps)
        let beatTimes = beatFrames.map { $0 / rate }
        var downTimes = downFrames.map { $0 / rate }
        var downIndex: [Int?] = downTimes.map { _ in nil }
        if !beatTimes.isEmpty {
            for (i, d) in downTimes.enumerated() {
                var best = 0, bestDistance = abs(beatTimes[0] - d)
                for (j, b) in beatTimes.enumerated().dropFirst() where abs(b - d) < bestDistance {
                    best = j
                    bestDistance = abs(b - d)
                }
                downTimes[i] = beatTimes[best]
                downIndex[i] = best
            }
        }
        // np.unique: sorted, without repeats.
        var order = Array(downTimes.indices)
        order.sort { downTimes[$0] < downTimes[$1] }
        var downbeats: [Double] = [], downbeatFrames: [Double] = []
        for i in order where downbeats.last != downTimes[i] {
            downbeats.append(downTimes[i])
            downbeatFrames.append(downIndex[i].map { beatFrames[$0] } ?? downFrames[i])
        }
        return BeatThisBeats(beatFrames: beatFrames, downbeatFrames: downbeatFrames, beats: beatTimes, downbeats: downbeats)
    }

    /// The frames whose logit is the largest within +-`radius` frames and above 0, in order.
    public static func peaks(_ x: [Float], radius: Int = 3) -> [Int] {
        let n = x.count
        var out: [Int] = []
        for t in 0..<n where x[t] > 0 {
            var isMax = true
            for u in max(0, t - radius)...min(n - 1, t + radius) where x[u] > x[t] {
                isMax = false
                break
            }
            if isMax { out.append(t) }
        }
        return out
    }

    /// Groups of peaks each at most `width` frames after the running mean of their group, replaced by that mean
    /// (`deduplicate_peaks`).
    public static func deduplicate(_ peaks: [Int], width: Int = 1) -> [Double] {
        guard let firstPeak = peaks.first else { return [] }
        var out: [Double] = []
        var p = Double(firstPeak), c = 1.0
        for q in peaks.dropFirst() {
            let p2 = Double(q)
            if p2 - p <= Double(width) {
                c += 1
                p += (p2 - p) / c
            } else {
                out.append(p)
                p = p2
                c = 1
            }
        }
        out.append(p)
        return out
    }
}
