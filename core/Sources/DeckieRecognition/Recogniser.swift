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

    /// (speed, whether the frequencies move with it): the key-held candidates from slowest to fastest, then the
    /// vinyl ones. Neighbours in speed make mostly the same hashes, so in this order the table's memory touched for
    /// one candidate is still at hand for the next.
    var candidates: [(speed: Double, vinyl: Bool)] {
        let n = Int((maxPercent / stepPercent).rounded(.down))
        var out: [(Double, Bool)] = []
        if tempoOnly || n < 1 { for k in -n...n { out.append((1 + Double(k) * stepPercent / 100, false)) } } else { out.append((1, false)) }
        if vinyl && n >= 1 { for k in -n...n where k != 0 { out.append((1 + Double(k) * stepPercent / 100, true)) } }
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
    /// count.
    public var score: Double
    /// `score` over the score of the third-best song in the same query. Unrelated songs of one style share enough
    /// (a kick drum on every beat puts points in the same places) that `score` alone is high for them; what marks a
    /// true match is standing clear of the other songs. This is the number to threshold.
    public var confidence: Double
    /// Other songs of the index that matched as well and hold the same sound (other files of this recording, or a
    /// long file that contains it): the same answer under other names.
    public var copies: [Int] = []

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
    /// The wide check: when above 0, the songs checked are the first this many the votes propose (two votes each),
    /// in place of the `verified` fullest votes whatever their songs.
    public var checkSongs = 0
    /// Whether songs the index says hold the same sound count as one when a match is judged (off only while the
    /// index itself is looking for them).
    public var judgeCopies = true
    /// For measuring whether forgiving a time difference that moved one step pays (letter AB's item 5): every
    /// hash of the query is also looked up with each of its time differences a step to either side (three ways
    /// for a pair, five for a triple). Off unless the size study's row says it earns its place.
    public var fuzzyGaps = false
    /// Points taken per slice of the query (nil: the index's own setting).
    public var queryPerSlice: Int?
    /// A fitted point counts when the song has a point within these distances: frames, and 1/4096 octaves (0.85 %).
    public var timeTolerance = 2.0
    public var pitchTolerance = 50.0

    /// A second index of the same songs to turn to when the first finds nothing sure (in the trial: pairs, slower and
    /// better in noise, behind triples), and the confidence under which it is turned to.
    /// The two-step way (see `match`): how many songs the index in memory proposes (0: one step), how a proposed
    /// song's constellation is fetched, and how the fetched songs are hashed.
    public var shortlistSize = 0
    public var detail: ((Int) -> Landmarks)?
    public var detailPairing = PairingConfig()
    public var fallback: RecognitionIndex?
    public var fallbackBelow = 3.0

    /// Frames to a vote bin (128 ms: half a candidate step of speed moves a 12 s query's offsets by 60 ms). Wide bins
    /// and one byte a bin keep the table small enough to stay in the processor's cache.
    static let binFrames = 8
    /// The least the third-best song's score is taken to be, when there are fewer than three or it is tiny.
    static let leastYardstick = 5.0
    var votes: [UInt8]
    var touched: [Int32] = []

    public init(index: RecognitionIndex, grid: SpeedGrid = SpeedGrid()) {
        self.index = index; self.grid = grid
        votes = [UInt8](repeating: 0, count: index.timelineFrames / Self.binFrames + 2)
    }

    struct Vote { var count: Int; var bin: Int; var speed: Double; var vinyl: Bool }

    /// The songs found in `query`, best first, one entry a song. Empty when nothing lined up at all; whether the best
    /// is a true match is for the caller to decide from its `score`.
    public func match(_ query: Landmarks) -> [RecognitionMatch] {
        if shortlistSize > 0, let detail {
            // Two steps. The index held in memory only proposes songs: the `shortlistSize` whose votes pile highest.
            // Those songs' constellations are then fetched (from storage, in a booth), hashed in full here and now,
            // and the query is matched against that small index alone.
            let songs = run(index, query, shortlist: shortlistSize).1
            guard !songs.isEmpty else { return [] }
            let small = RecognitionIndex(songs: songs.map { (index.ids[$0], detail($0)) }, landmark: index.landmark, pairing: detailPairing)
            var found = run(small, query).0
            for i in found.indices { found[i].songIndex = songs[found[i].songIndex] }
            return found
        }
        let first = run(index, query).0
        guard let fallback, (first.first?.confidence ?? 0) < fallbackBelow else { return first }
        let second = run(fallback, query).0
        return (second.first?.confidence ?? 0) > (first.first?.confidence ?? 0) ? second : first
    }

    /// Checks one song at one place and speed against a query, with no search: where a song already named should be
    /// now. `offsetSeconds` is where in the song the query's first sample is expected; the fit moves it, the speed
    /// and the pitch to where the points agree, as in a full match. `score` is how far the count of agreeing points
    /// stands above chance; `confidence` is left at 0 (there are no other songs to compare with).
    public func check(_ query: Landmarks, song: Int, offsetSeconds: Double, tempoRatio: Double, pitchRatio: Double) -> RecognitionMatch? {
        let n = min(query.count, query.frames.firstIndex { $0 >= UInt32(RecognitionIndex.maxQueryFrames) } ?? query.count)
        guard n >= 4, song >= 0, song < index.songCount else { return nil }
        let qt = (0..<n).map { Double(query.frames[$0]) }, qp = (0..<n).map { Double(query.pitch($0)) }
        return verify(in: index, qt: qt, qp: qp, song: song, offset: offsetSeconds / index.landmark.frameSeconds,
                      speed: tempoRatio, shift: log2(pitchRatio) * Landmarks.pitchUnitsPerOctave)
    }

    /// The songs the index in memory proposes for a query, best first: those whose votes pile highest, before any
    /// check (for measuring how often the right song is among the first so many).
    public func proposals(_ query: Landmarks, count: Int) -> [Int] { run(index, query, shortlist: count).1 }

    private func run(_ ix: RecognitionIndex, _ query: Landmarks, shortlist: Int? = nil) -> ([RecognitionMatch], [Int]) {
        let p = ix.pairing
        let unit = Double(p.pitchBinUnits)
        let n = min(query.count, query.frames.firstIndex { $0 >= UInt32(RecognitionIndex.maxQueryFrames) } ?? query.count)
        guard n >= 4 else { return ([], []) }
        let qt = (0..<n).map { Double(query.frames[$0]) }, qp = (0..<n).map { Double(query.pitch($0)) }
        // Strength for choosing a slice's points: as measured when the query was made from audio, else its level.
        let qs: [Float] = p.byStrength ? (0..<n).map { query.strengths.count == query.count ? query.strengths[$0] : Float(query.level($0)) }
                                       : [Float](repeating: 0, count: n)
        let bins = p.pitchBins(octaves: ix.landmark.octaves)

        var best: [Vote] = []
        // The fullest bins kept from each candidate speed: three for a direct answer, more when a list is wanted.
        let keep = shortlist == nil && checkSongs == 0 ? 3 : 8
        var qbin = [Int](repeating: -1, count: n)
        let per = queryPerSlice ?? p.queryPerSlice
        // Per slice of the current anchor: how many targets it has, and each one's pitch bin and gap.
        var taken = [Int](repeating: 0, count: p.fanOut)
        var slotBin = [Int](repeating: 0, count: p.fanOut * per), slotGap = [Int](repeating: 0, count: p.fanOut * per)
        var slotStrength = [Float](repeating: 0, count: p.fanOut * per)
        // The candidate's lookups, gathered first so that the table reads (each a cache miss) run back to back.
        var hashes: [Int] = [], shifts: [Double] = [], spans: [(Int, Int)] = []
        if p.ratio { best = ratioVotes(ix, qt: qt, qp: qp, qs: qs, keep: 40) }
        for cand in (p.ratio ? [] : grid.candidates) {
            let v = cand.speed
            let shift = cand.vinyl ? log2(v) * Landmarks.pitchUnitsPerOctave : 0
            for i in 0..<n {
                let b = Int(((qp[i] - shift) / unit).rounded(.down))
                qbin[i] = qp[i] - shift >= 0 && b < bins ? b : -1
            }
            hashes.removeAll(keepingCapacity: true); shifts.removeAll(keepingCapacity: true)
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
                        // Keep the slice's `per` strongest (the earliest of equals), strongest first.
                        var at = taken[k]
                        while at > 0 && qs[j] > slotStrength[k * per + at - 1] { at -= 1 }
                        if at < per {
                            var m = min(taken[k], per - 1)
                            while m > at {
                                slotBin[k * per + m] = slotBin[k * per + m - 1]; slotGap[k * per + m] = slotGap[k * per + m - 1]
                                slotStrength[k * per + m] = slotStrength[k * per + m - 1]
                                m -= 1
                            }
                            slotBin[k * per + at] = b; slotGap[k * per + at] = gap; slotStrength[k * per + at] = qs[j]
                            if taken[k] < per { taken[k] += 1 }
                        }
                    }
                    j += 1
                }
                if !p.triples {
                    for k in 0..<p.fanOut {
                        for x in 0..<taken[k] {
                            let h = p.hash(anchorBin: a, targetBin: slotBin[k * per + x], gap: slotGap[k * per + x])
                            if p.keptPair(h) { hashes.append(h); shifts.append(shiftT) }
                            if fuzzyGaps {
                                // Also the two hashes with the time difference a step to either side.
                                for d in [-p.gapStep, p.gapStep] where slotGap[k * per + x] + d >= 0 {
                                    let hf = p.hash(anchorBin: a, targetBin: slotBin[k * per + x], gap: slotGap[k * per + x] + d)
                                    if p.keptPair(hf) { hashes.append(hf); shifts.append(shiftT) }
                                }
                            }
                        }
                    }
                } else if p.points == 4 {
                    for k in 0..<p.quadCount {
                        let (k1, k2, k3) = p.sliceTriple(k)
                        for x in 0..<taken[k1] {
                            for y in 0..<taken[k2] {
                                for z in 0..<taken[k3] {
                                    let h = p.hash(anchorBin: a, bin1: slotBin[k1 * per + x], gap1: slotGap[k1 * per + x],
                                                   bin2: slotBin[k2 * per + y], gap2: slotGap[k2 * per + y],
                                                   bin3: slotBin[k3 * per + z], gap3: slotGap[k3 * per + z])
                                    if !p.kept(h) { continue }
                                    hashes.append(h)
                                    shifts.append(shiftT)
                                }
                            }
                        }
                    }
                } else {
                    for k in 0..<p.tripleCount {
                        let (k1, k2) = p.slicePair(k)
                        for x in 0..<taken[k1] {
                            for y in 0..<taken[k2] {
                                let h = p.hash(anchorBin: a, bin1: slotBin[k1 * per + x], gap1: slotGap[k1 * per + x],
                                               bin2: slotBin[k2 * per + y], gap2: slotGap[k2 * per + y])
                                if p.kept(h) { hashes.append(h); shifts.append(shiftT) }
                                if fuzzyGaps {
                                    // Also the four hashes with one of the two time differences a step to either side.
                                    for (d1, d2) in [(-p.gapStep, 0), (p.gapStep, 0), (0, -p.gapStep), (0, p.gapStep)] {
                                        let g1 = slotGap[k1 * per + x] + d1, g2 = slotGap[k2 * per + y] + d2
                                        if g1 < 0 || g2 < 0 { continue }
                                        let hf = p.hash(anchorBin: a, bin1: slotBin[k1 * per + x], gap1: g1, bin2: slotBin[k2 * per + y], gap2: g2)
                                        if p.kept(hf) { hashes.append(hf); shifts.append(shiftT) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            ix.offsets.withUnsafeBufferPointer { offsets in
                ix.entries.withUnsafeBufferPointer { entries in
                    do {
                        votes.withUnsafeMutableBufferPointer { votes in
                            spans.removeAll(keepingCapacity: true)
                            for h in hashes { let slot = p.slot(h); spans.append((Int(offsets[slot]), Int(offsets[slot + 1]))) }
                            ix.tags.withUnsafeBufferPointer { tags in
                                let tagged = p.triples, packed = p.triples && p.compact
                                for (x, span) in spans.enumerated() where span.1 > span.0 {
                                    let shiftT = shifts[x]
                                    let tag = p.tag(hashes[x])
                                    var e = span.0
                                    while e < span.1 {
                                        let entry = entries[e]
                                        if packed ? UInt8(entry & 0x7f) == tag : (!tagged || tags[e] == tag) {
                                            let frame = packed ? Double((entry >> 7) * 8 + 4) : Double(entry)
                                            let bin = Int(frame - shiftT) / Self.binFrames
                                            if bin >= 0 {
                                                if votes[bin] == 0 { touched.append(Int32(bin)) }
                                                if votes[bin] < .max { votes[bin] += 1 }
                                            }
                                        }
                                        e += 1
                                    }
                                }
                            }
                            // The three fullest pairs of neighbouring bins for this candidate, then clear.
                            var top: [(Int, Int)] = []
                            for t in touched {
                                let b = Int(t)
                                let c = Int(votes[b]) + Int(votes[b + 1])
                                if top.count < keep || c > top[top.count - 1].0 {
                                    top.append((c, b))
                                    top.sort { $0.0 > $1.0 }
                                    if top.count > keep { top.removeLast() }
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
        if let shortlist {
            var songs: [Int] = []
            for vote in best {
                let s = ix.song(atTimelineFrame: (vote.bin + 1) * Self.binFrames)
                if !songs.contains(s) { songs.append(s); if songs.count == shortlist { break } }
            }
            return ([], songs)
        }
        var bySong: [Int: RecognitionMatch] = [:]
        var checked = 0
        var perSong: [Int: Int] = [:]
        for vote in best {
            let frame = (vote.bin + 1) * Self.binFrames
            let s = ix.song(atTimelineFrame: frame)
            if checkSongs > 0 {
                // The wide check: the two fullest votes of each of the first `checkSongs` songs proposed.
                if perSong.count >= checkSongs && perSong[s] == nil { continue }
                if perSong[s, default: 0] >= 2 { continue }
                perSong[s, default: 0] += 1
            } else {
                // At least `verified` votes, and on until four songs have been seen (the third is the yardstick below).
                if checked >= 5 * verified || (checked >= verified && bySong.count >= 4) { break }
            }
            checked += 1
            guard let m = verify(in: ix, qt: qt, qp: qp, song: s, offset: Double(frame - ix.songStart[s]), speed: vote.speed,
                                 shift: vote.vinyl ? log2(vote.speed) * Landmarks.pitchUnitsPerOctave : 0) else { continue }
            if let old = bySong[s], old.score >= m.score { continue }
            bySong[s] = m
        }
        var found = bySong.values.sorted { $0.score != $1.score ? $0.score > $1.score : $0.songIndex < $1.songIndex }
        // Songs that hold the same sound as a better-scoring one (another file of the recording, or a file that
        // contains it) are not other songs: they are taken out of the list and noted on the one they repeat.
        if judgeCopies && !ix.related.isEmpty {
            var kept: [RecognitionMatch] = []
            for m in found {
                if let at = kept.firstIndex(where: { ix.isRelated($0.songIndex, m.songIndex) }) { kept[at].copies.append(m.songIndex) } else { kept.append(m) }
            }
            found = kept
        }
        // Each song's score over the third-best song's: two songs may truly be playing, the third never is.
        let yardstick = max(Self.leastYardstick, found.count >= 3 ? found[2].score : 0)
        for i in found.indices { found[i].confidence = found[i].score / yardstick }
        return (found, [])
    }

    /// A song's points for the check: from the index when it holds them, else through its `pointSource` (the crate
    /// file's own fingerprint), kept for the last few hundred songs read. The frames are on the index's timeline;
    /// `lo` and `hi` bound the song's points in the buffers handed over.
    func withPoints<R>(_ ix: RecognitionIndex, _ s: Int,
                       _ body: (UnsafeBufferPointer<Int32>, UnsafeBufferPointer<UInt16>, _ lo: Int, _ hi: Int) -> R) -> R? {
        if ix.holdsPoints {
            return ix.pointFrame.withUnsafeBufferPointer { pf in
                ix.pointPitch.withUnsafeBufferPointer { pp in body(pf, pp, ix.pointStart[s], ix.pointStart[s + 1]) }
            }
        }
        if readPoints[s] == nil {
            guard let m = ix.pointSource?(s) else { return nil }
            if readOrder.count >= 256 { readPoints[readOrder.removeFirst()] = nil }
            let start = Int32(ix.songStart[s])
            readPoints[s] = (m.frames.map { start + Int32($0) }, (0..<m.count).map { m.pitch($0) })
            readOrder.append(s)
        }
        guard let kept = readPoints[s] else { return nil }
        return kept.frames.withUnsafeBufferPointer { pf in kept.pitches.withUnsafeBufferPointer { pp in body(pf, pp, 0, pf.count) } }
    }
    private var readPoints: [Int: (frames: [Int32], pitches: [UInt16])] = [:]
    private var readOrder: [Int] = []

    /// Lines the query's points up with one song's from a starting offset, speed and pitch shift; refits the three
    /// from the points that pair up (a straight line through their times, the median of their pitch differences) with
    /// the tolerances narrowing; and counts the pairs at the final tolerances.
    private func verify(in ix: RecognitionIndex, qt: [Double], qp: [Double], song s: Int, offset: Double, speed: Double, shift: Double) -> RecognitionMatch? {
        guard ix.pointStart[s + 1] > ix.pointStart[s] else { return nil }
        let pointCount = ix.pointStart[s + 1] - ix.pointStart[s]
        let start = Double(ix.songStart[s])
        var o = offset, v = speed, sh = shift
        var matched = 0
        let rounds: [(Double, Double)] = [(5, 120), (3, 80), (timeTolerance, pitchTolerance), (timeTolerance, pitchTolerance)]
        var pairs: [(tq: Double, tr: Double, dp: Double)] = []
        for (round, (tt, pt)) in rounds.enumerated() {
            pairs.removeAll(keepingCapacity: true)
            let read: Void? = withPoints(ix, s) { pf, pp, lo, hi in
                do {
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
            if read == nil { return nil }        // the song's points could not be read
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
        let frames = Double(ix.songStart[s + 1] - RecognitionIndex.padding - ix.songStart[s])
        let density = Double(pointCount) / (max(1, frames) * ix.landmark.octaves * Landmarks.pitchUnitsPerOctave)
        let chance = min(0.5, density * (2 * timeTolerance + 1) * (2 * pitchTolerance + 1))
        let nq = Double(qt.count)
        let score = (Double(matched) - nq * chance) / (nq * chance * (1 - chance) + 1).squareRoot()
        return RecognitionMatch(songIndex: s, id: ix.ids[s], offsetSeconds: o * ix.landmark.frameSeconds,
                                tempoRatio: v, pitchRatio: pow(2, sh / Landmarks.pitchUnitsPerOctave), matched: matched,
                                queryPoints: qt.count, score: score, confidence: 0)
    }
}
