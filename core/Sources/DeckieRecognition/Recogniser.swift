import Foundation

// TRIAL: see Landmarks.swift.

/// The deck speeds a query is tried at.
///
/// A deck playing a song at speed v (1.08 is the fader at +8 %) moves every point of the song's constellation: its
/// time is divided by v and, when the deck does not hold the key (a turntable, or a player with "master tempo" off),
/// its frequency is multiplied by v. Letter H's remedy was to match several resampled and several time-stretched
/// copies of the microphone. Here the same thing is done to the query's points instead of to its audio: for each
/// candidate speed the points' times are multiplied by v (and, for the vinyl candidates, their frequencies divided by
/// v) before hashing. That is exact for a resampled copy and for an ideal time-stretch, costs a few thousand
/// multiplications a candidate, and needs no stretcher in the booth, so candidates can be 1 % apart rather than 5 or 8.
public struct SpeedGrid: Sendable, Equatable {
    /// The widest fader setting tried, in percent either way (a point beyond the widest common fader range, 16).
    public var maxPercent = 17.0
    /// The step between candidates, in percent. Half a step is the most a deck can be from the nearest candidate: at
    /// 0.5 %, a frequency moves a quarter of a hash's pitch step and two seconds move 10 ms of a 32 ms time step.
    public var stepPercent = 1.0
    public var vinyl = true
    public var tempoOnly = true

    public init() {}

    /// (speed, whether the frequencies move with it), the unchanged candidate first.
    var candidates: [(speed: Double, vinyl: Bool)] {
        var out: [(Double, Bool)] = [(1, false)]
        let n = Int((maxPercent / stepPercent).rounded(.down))
        guard n >= 1 else { return out }
        for k in 1...n {
            for sign in [1.0, -1.0] {
                let v = 1 + sign * Double(k) * stepPercent / 100
                if tempoOnly { out.append((v, false)) }
                if vinyl { out.append((v, true)) }
            }
        }
        return out
    }
}

/// One song found in a query.
public struct RecognitionMatch: Sendable, Equatable {
    public var songIndex: Int
    public var id: String
    /// Where in the song the query's first sample is, in seconds.
    public var offsetSeconds: Double
    /// Song seconds per query second: the deck's speed (1.08 at +8 %), read from the times of the matched points.
    public var tempoRatio: Double
    /// Query frequency over song frequency, read from the matched points: equal to `tempoRatio` on a turntable, 1 when
    /// the deck holds the key.
    public var pitchRatio: Double
    /// The query's points that have a point of the song where the fit puts them, of `queryPoints`.
    public var matched: Int
    public var queryPoints: Int
    /// How far `matched` is above what an unrelated song would give by chance, in standard deviations of that chance
    /// count. This is the number to threshold.
    public var score: Double

    /// The fader reading, in percent.
    public var speedPercent: Double { (tempoRatio - 1) * 100 }
    /// Whether the frequencies moved with the speed (nil within 1 % of zero, where the two cannot be told apart).
    public var isVinyl: Bool? {
        guard abs(tempoRatio - 1) >= 0.01 else { return nil }
        return abs(log(pitchRatio) - log(tempoRatio)) < abs(log(pitchRatio))
    }
}

/// Matches queries against an index. Not thread-safe (it keeps working memory): one per thread, sharing the index.
public final class Recogniser {
    public let index: RecognitionIndex
    public var grid: SpeedGrid
    /// How many of the best (candidate speed, offset) votes are checked against the song's points.
    public var verified = 12
    /// A fitted point counts when the song has a point within these distances: frames, and 1/4096 octaves (0.85 %).
    public var timeTolerance = 2.0
    public var pitchTolerance = 50.0

    /// Frames to a vote bin (64 ms): half a candidate step of speed moves a 12 s query's offsets by 60 ms.
    static let binFrames = 4
    private var votes: [UInt16]
    private var touched: [Int32] = []

    public init(index: RecognitionIndex, grid: SpeedGrid = SpeedGrid()) {
        self.index = index; self.grid = grid
        votes = [UInt16](repeating: 0, count: index.timelineFrames / Self.binFrames + 2)
    }

    private struct Vote { var count: Int; var bin: Int; var speed: Double; var vinyl: Bool }

    /// The songs found in `query`, best first, one entry a song. Empty when nothing lined up at all; whether the best
    /// is a true match is for the caller to decide from its `score`.
    public func match(_ query: Landmarks) -> [RecognitionMatch] {
        let p = index.pairing
        let unit = Double(p.pitchBinUnits)
        let n = min(query.count, query.frames.firstIndex { $0 >= UInt32(RecognitionIndex.maxQueryFrames) } ?? query.count)
        guard n >= 4 else { return [] }
        let qt = (0..<n).map { Double(query.frames[$0]) }, qp = (0..<n).map { Double(query.pitches[$0]) }
        let bins = p.pitchBins(octaves: index.landmark.octaves)

        var best: [Vote] = []
        var qbin = [Int](repeating: -1, count: n)
        var taken = [Int](repeating: 0, count: p.fanOut)
        for cand in grid.candidates {
            let v = cand.speed
            let shift = cand.vinyl ? log2(v) * Landmarks.pitchUnitsPerOctave : 0
            for i in 0..<n {
                let b = Int(((qp[i] - shift) / unit).rounded(.down))
                qbin[i] = qp[i] - shift >= 0 && b < bins ? b : -1
            }
            index.offsets.withUnsafeBufferPointer { offsets in
                index.entries.withUnsafeBufferPointer { entries in
                    do {
                        votes.withUnsafeMutableBufferPointer { votes in
                            for i in 0..<n where qbin[i] >= 0 {
                                let a = qbin[i]
                                var j = i + 1
                                for k in 0..<p.fanOut { taken[k] = 0 }
                                let shiftT = v * qt[i]
                                while j < n {
                                    let gap = Int((qt[j] - qt[i]) * v + 0.5)
                                    if gap > p.maxGap { break }
                                    let b = qbin[j]
                                    if gap >= p.minGap && b >= 0 && abs(b - a) <= p.maxPitchBins {
                                        let k = p.slice(gap: gap)
                                        if taken[k] < p.queryPerSlice {
                                            taken[k] += 1
                                            let h = p.hash(anchorBin: a, targetBin: b, gap: gap)
                                            var e = Int(offsets[h])
                                            let end = Int(offsets[h + 1])
                                            while e < end {
                                                let bin = Int(Double(entries[e]) - shiftT) / Self.binFrames
                                                if bin >= 0 {
                                                    if votes[bin] == 0 { touched.append(Int32(bin)) }
                                                    if votes[bin] < .max { votes[bin] += 1 }
                                                }
                                                e += 1
                                            }
                                        }
                                    }
                                    j += 1
                                }
                            }
                            // The three fullest pairs of neighbouring bins for this candidate, then clear.
                            var top: [(Int, Int)] = []
                            for t in touched {
                                let b = Int(t)
                                let c = Int(votes[b]) + Int(votes[b + 1])
                                if top.count < 3 || c > top[top.count - 1].0 {
                                    top.append((c, b))
                                    top.sort { $0.0 > $1.0 }
                                    if top.count > 3 { top.removeLast() }
                                }
                            }
                            for t in touched { votes[Int(t)] = 0 }
                            touched.removeAll(keepingCapacity: true)
                            for (c, b) in top { best.append(Vote(count: c, bin: b, speed: v, vinyl: cand.vinyl)) }
                        }
                    }
                }
            }
        }

        best.sort { $0.count > $1.count }
        var bySong: [Int: RecognitionMatch] = [:]
        for vote in best.prefix(verified) {
            let frame = (vote.bin + 1) * Self.binFrames
            let s = index.song(atTimelineFrame: frame)
            guard let m = verify(qt: qt, qp: qp, song: s, offset: Double(frame - index.songStart[s]), speed: vote.speed,
                                 shift: vote.vinyl ? log2(vote.speed) * Landmarks.pitchUnitsPerOctave : 0) else { continue }
            if let old = bySong[s], old.score >= m.score { continue }
            bySong[s] = m
        }
        return bySong.values.sorted { $0.score != $1.score ? $0.score > $1.score : $0.songIndex < $1.songIndex }
    }

    /// Lines the query's points up with one song's from a starting offset, speed and pitch shift; refits the three
    /// from the points that pair up (a straight line through their times, the median of their pitch differences) with
    /// the tolerances narrowing; and counts the pairs at the final tolerances.
    private func verify(qt: [Double], qp: [Double], song s: Int, offset: Double, speed: Double, shift: Double) -> RecognitionMatch? {
        let lo = index.pointStart[s], hi = index.pointStart[s + 1]
        guard hi > lo else { return nil }
        let start = Double(index.songStart[s])
        var o = offset, v = speed, sh = shift
        var matched = 0
        let rounds: [(Double, Double)] = [(5, 120), (3, 80), (timeTolerance, pitchTolerance), (timeTolerance, pitchTolerance)]
        var pairs: [(tq: Double, tr: Double, dp: Double)] = []
        for (round, (tt, pt)) in rounds.enumerated() {
            pairs.removeAll(keepingCapacity: true)
            index.pointFrame.withUnsafeBufferPointer { pf in
                index.pointPitch.withUnsafeBufferPointer { pp in
                    for i in 0..<qt.count {
                        let tr = start + o + v * qt[i], pr = qp[i] - sh
                        // The first song point at or after tr - tt.
                        var a = lo, b = hi
                        let from = tr - tt
                        while a < b {
                            let mid = (a + b) / 2
                            if Double(pf[mid]) < from { a = mid + 1 } else { b = mid }
                        }
                        var bestD = Double.infinity, bestJ = -1
                        var j = a
                        while j < hi && Double(pf[j]) <= tr + tt {
                            let dp = Double(pp[j]) - pr
                            if abs(dp) <= pt {
                                let dt = (Double(pf[j]) - tr) / tt, df = dp / pt
                                let d = dt * dt + df * df
                                if d < bestD { bestD = d; bestJ = j }
                            }
                            j += 1
                        }
                        if bestJ >= 0 { pairs.append((qt[i], Double(pf[bestJ]) - start, qp[i] - Double(pp[bestJ]))) }
                    }
                }
            }
            matched = pairs.count
            if round == rounds.count - 1 { break }
            guard pairs.count >= 4 else { return nil }
            // Least squares: tr = o + v tq.
            let k = Double(pairs.count)
            let mq = pairs.reduce(0) { $0 + $1.tq } / k, mr = pairs.reduce(0) { $0 + $1.tr } / k
            var sqq = 0.0, sqr = 0.0
            for pr in pairs { sqq += (pr.tq - mq) * (pr.tq - mq); sqr += (pr.tq - mq) * (pr.tr - mr) }
            guard sqq > 0 else { return nil }
            v = min(1.25, max(0.8, sqr / sqq))
            o = mr - v * mq
            let dps = pairs.map(\.dp).sorted()
            sh = dps.count % 2 == 1 ? dps[dps.count / 2] : 0.5 * (dps[dps.count / 2 - 1] + dps[dps.count / 2])
        }
        // What an unrelated song would give: each query point finds a song point in its window with probability
        // (the song's points per frame and pitch unit) x (the window's area).
        let frames = Double(index.songStart[s + 1] - RecognitionIndex.padding - index.songStart[s])
        let density = Double(hi - lo) / (max(1, frames) * index.landmark.octaves * Landmarks.pitchUnitsPerOctave)
        let chance = min(0.5, density * (2 * timeTolerance + 1) * (2 * pitchTolerance + 1))
        let nq = Double(qt.count)
        let score = (Double(matched) - nq * chance) / (nq * chance * (1 - chance) + 1).squareRoot()
        return RecognitionMatch(songIndex: s, id: index.ids[s], offsetSeconds: o * index.landmark.frameSeconds,
                                tempoRatio: v, pitchRatio: pow(2, sh / Landmarks.pitchUnitsPerOctave), matched: matched,
                                queryPoints: qt.count, score: score)
    }
}
