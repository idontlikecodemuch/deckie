import Foundation

// TRIAL: see Landmarks.swift.

/// How points are paired into hashes (Wang 2003, section 2.2: each point is an "anchor" paired with points in a "target
/// zone" after it; a hash is the two frequencies and the time between them).
public struct PairingConfig: Sendable, Equatable {
    /// Frequency steps to the octave in a hash (2.2 % a step). The step sets how far the deck's speed may be from a
    /// candidate speed before a pair's hash changes; the candidates (`SpeedGrid`) are spaced to fit inside it.
    public var pitchBinsPerOctave = 32
    /// The target zone: a later point from `minGap` to `maxGap` frames on (64 ms to 2 s), within an octave either way.
    public var minGap = 4
    public var maxGap = 128
    public var maxPitchBins = 32
    /// Frames to one step of the time difference in a hash (32 ms).
    public var gapStep = 2
    /// The target zone is cut into this many equal slices of time, and an anchor is paired with the first point in
    /// each (the paper's fan-out: it multiplies the index's size). Taking the nearest points instead would put nearly
    /// every pair at the shortest gaps (there are some 30 points a second), so the time difference would tell songs
    /// apart far less than its 7 bits allow and every lookup would return hundreds of unrelated anchors.
    public var fanOut = 6
    /// Points taken per slice in a query: more than one, so that a pair survives an extra point (noise, a second
    /// song) landing in the slice before the song's own.
    public var queryPerSlice = 2

    /// Whether a hash is made of three points (the anchor and the points of two slices) rather than two. A pair's
    /// hash has some 470,000 possible values and a thousand songs make some 40 million pairs, so every lookup
    /// returns about a hundred unrelated anchors and nearly all the matcher's time goes on them; a triple's has
    /// thousands of times more values, so a lookup returns almost nothing but the song. The price: all three points
    /// must survive the room, not two.
    public var triples = true
    /// Whether a slice's point is its strongest (by the constellation's strength levels; the earliest of equals)
    /// rather than its first in time.
    public var byStrength = true

    public init() {}

    /// The slices whose points join the anchor in triple k: each slice with the next, the last with the first.
    @inline(__always) func slicePair(_ k: Int) -> (Int, Int) { k + 1 < fanOut ? (k, k + 1) : (0, k) }
    var tableBits: Int { triples ? 24 : Self.hashBits }
    /// A triple's 35 bits (anchor pitch, two pitch differences, two time differences) folded to the table's 24 by a
    /// multiplicative hash (Knuth's golden-ratio constant); two different triples sharing a slot only add stray votes.
    @inline(__always) func hash(anchorBin a: Int, bin1: Int, gap1: Int, bin2: Int, gap2: Int) -> Int {
        let raw = UInt64(a) | UInt64(bin1 - a + maxPitchBins) << 7 | UInt64(bin2 - a + maxPitchBins) << 14
            | UInt64(gap1 / gapStep) << 21 | UInt64(gap2 / gapStep) << 28
        return Int((raw &* 0x9E37_79B9_7F4A_7C15) >> 40)
    }

    var pitchBinUnits: Int { Int(Landmarks.pitchUnitsPerOctave) / pitchBinsPerOctave }
    func pitchBins(octaves: Double) -> Int { Int((octaves * Double(pitchBinsPerOctave)).rounded(.up)) }
    /// 7 bits of anchor pitch, 7 of pitch difference, 7 of time difference.
    static let hashBits = 21
    @inline(__always) func slice(gap: Int) -> Int { (gap - minGap) * fanOut / (maxGap - minGap + 1) }
    @inline(__always) func hash(anchorBin a: Int, targetBin b: Int, gap: Int) -> Int {
        (a << 14) | ((b - a + maxPitchBins) << 7) | (gap / gapStep)
    }
}

/// The songs a query is matched against, with their hashes: built in memory from the songs' constellations.
public struct RecognitionIndex: Sendable {
    public let landmark: LandmarkConfig
    public let pairing: PairingConfig
    public let ids: [String]

    /// Frames of padding before each song on the one long timeline all songs are laid on, and the longest query (in
    /// frames) that padding allows at the fastest candidate speed.
    static let padding = 1200
    public static let maxQueryFrames = 1000

    /// Where each song starts on the timeline (frames), and one past the last.
    let songStart: [Int]
    let timelineFrames: Int
    /// Each song's first point in the arrays below, and one past the last.
    let pointStart: [Int]
    /// Every song's points: frame on the timeline, and pitch.
    let pointFrame: [Int32]
    let pointPitch: [UInt16]
    /// The hash table: the anchors (their frames on the timeline) of hash h are entries[offsets[h]..<offsets[h + 1]].
    let offsets: [UInt32]
    let entries: [UInt32]

    public var songCount: Int { ids.count }
    public var hashCount: Int { entries.count }
    public var pointCount: Int { pointFrame.count }

    public init(songs: [(id: String, landmarks: Landmarks)], landmark: LandmarkConfig = LandmarkConfig(),
                pairing: PairingConfig = PairingConfig()) {
        self.landmark = landmark; self.pairing = pairing
        ids = songs.map(\.id)
        var songStart: [Int] = [], pointStart: [Int] = []
        var pointFrame: [Int32] = [], pointPitch: [UInt16] = [], pointLevel: [Int8] = []
        var at = 0
        for s in songs {
            at += Self.padding
            songStart.append(at); pointStart.append(pointFrame.count)
            for i in 0..<s.landmarks.count {
                pointFrame.append(Int32(at + Int(s.landmarks.frames[i])))
                pointPitch.append(s.landmarks.pitch(i))
                pointLevel.append(Int8(s.landmarks.level(i)))
            }
            at += max(s.landmarks.frameCount, Int(s.landmarks.frames.last ?? 0) + 1)
        }
        songStart.append(at + Self.padding); pointStart.append(pointFrame.count)
        timelineFrames = at + Self.padding
        precondition(timelineFrames < Int(Int32.max))

        // Two passes over every pair: count each hash, then place the anchors.
        let size = 1 << pairing.tableBits
        var counts = [UInt32](repeating: 0, count: size + 1)
        let p = pairing
        let unit = p.pitchBinUnits
        var slotBin = [Int](repeating: 0, count: p.fanOut), slotGap = [Int](repeating: 0, count: p.fanOut)
        var slotLevel = [Int8](repeating: 0, count: p.fanOut)
        func forEachPair(_ body: (_ hash: Int, _ anchor: Int) -> Void) {
            for s in 0..<songs.count {
                let lo = pointStart[s], hi = pointStart[s + 1]
                for i in lo..<hi {
                    let a = Int(pointPitch[i]) / unit, ta = Int(pointFrame[i])
                    var filled = 0   // bit k set once slice k has its point
                    var j = i + 1
                    while j < hi {
                        let gap = Int(pointFrame[j]) - ta
                        if gap > p.maxGap { break }
                        let b = Int(pointPitch[j]) / unit
                        if gap >= p.minGap && abs(b - a) <= p.maxPitchBins {
                            let k = p.slice(gap: gap)
                            let level = p.byStrength ? pointLevel[j] : 0
                            if filled & (1 << k) == 0 || level > slotLevel[k] {
                                filled |= 1 << k
                                slotBin[k] = b; slotGap[k] = gap; slotLevel[k] = level
                            }
                        }
                        j += 1
                    }
                    if !p.triples {
                        for k in 0..<p.fanOut where filled & (1 << k) != 0 {
                            body(p.hash(anchorBin: a, targetBin: slotBin[k], gap: slotGap[k]), ta)
                        }
                    }
                    if p.triples {
                        for k in 0..<p.fanOut {
                            let (k1, k2) = p.slicePair(k)
                            if filled & (1 << k1) != 0 && filled & (1 << k2) != 0 {
                                body(p.hash(anchorBin: a, bin1: slotBin[k1], gap1: slotGap[k1], bin2: slotBin[k2], gap2: slotGap[k2]), ta)
                            }
                        }
                    }
                }
            }
        }
        forEachPair { h, _ in counts[h + 1] += 1 }
        for h in 0..<size { counts[h + 1] += counts[h] }
        var entries = [UInt32](repeating: 0, count: Int(counts[size]))
        var next = counts
        forEachPair { h, frame in entries[Int(next[h])] = UInt32(frame); next[h] += 1 }
        self.songStart = songStart; self.pointStart = pointStart
        self.pointFrame = pointFrame; self.pointPitch = pointPitch
        offsets = counts; self.entries = entries
    }

    /// The share of all hashes that sit in buckets (one bucket per hash value) larger than `size`: how lopsided the
    /// table is.
    public func shareInBuckets(largerThan size: Int) -> Double {
        var n = 0
        for h in 0..<(offsets.count - 1) where Int(offsets[h + 1] - offsets[h]) > size { n += Int(offsets[h + 1] - offsets[h]) }
        return Double(n) / Double(max(1, entries.count))
    }

    /// The song whose stretch of the timeline (its padding, then its frames) holds `frame`.
    func song(atTimelineFrame frame: Int) -> Int {
        var lo = 0, hi = ids.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if songStart[mid] - Self.padding <= frame { lo = mid } else { hi = mid - 1 }
        }
        return lo
    }
}
