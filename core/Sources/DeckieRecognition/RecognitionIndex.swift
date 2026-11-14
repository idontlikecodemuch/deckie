import Foundation

// TRIAL: see Landmarks.swift.

/// How points are paired into hashes (Wang 2003, section 2.2: each point is an "anchor" paired with points in a "target
/// zone" after it; a hash is the two frequencies and the time between them).
public struct PairingConfig: Sendable, Equatable, Codable {
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

    // What the index holds in memory (three-point hashes only). These are the knobs of the size study
    // (docs/research/ac-recognition-size.md).
    /// Whether an entry is one 32-bit word: the anchor's place on the timeline in steps of 8 frames (128 ms, the
    /// width of a vote bin, which is all the vote uses) in 25 bits, and a 7-bit tag. Otherwise, as in the first
    /// trial, a 32-bit frame and a separate 8-bit tag: five bytes.
    public var compact = true
    /// Entries per table slot the table is sized for. A slot's entries are read in a row and told apart by their
    /// tags, so a long slot costs a little time and no accuracy; a short one costs memory (4 bytes a slot).
    public var entriesPerSlot = 32
    /// Keep one hash in this many (a power of two), chosen by the hash's own low bits, so a song and a query drop
    /// the same ones.
    public var keepOneIn = 1
    /// Only a song's points of this strength level or more (0 to 3) are anchors in the index; every point can still
    /// be a target, and every point of a query is tried as an anchor. Level 2 keeps the stronger half.
    public var minAnchorLevel = 0

    public init() {}

    /// The settings the booth's index is built with (chosen in the size study; docs/research/w4-recognition-complete.md).
    public static var booth: PairingConfig { PairingConfig() }

    /// The slices whose points join the anchor in triple k: each slice with the next, the last with the first.
    @inline(__always) func slicePair(_ k: Int) -> (Int, Int) { k + 1 < fanOut ? (k, k + 1) : (0, k) }
    // Four points (the owner's question, Nov 14: "Can we use 4 points?"), in two forms; both keep `triples` true,
    // which only means "not pairs": a folded hash with a tag.
    /// Points in a hash made the way pairs and triples are: 3, or 4 (the anchor with the points of three
    /// neighbouring slices: three pitch differences and three time differences, tried at every candidate speed).
    public var points = 3
    /// The ratio form, after Sonnleitner and Widmer's quad fingerprint (written from the paper's description, on
    /// this module's logarithmic pitch axis): see RatioQuads.swift. No speed search.
    public var ratio = false
    /// Ratio form: the far points tried per anchor in a song, and in a query; the inner points tried per far point
    /// in a query (a song uses its two strongest).
    public var ratioFar = 1
    public var queryRatioFar = 3
    public var queryRatioInner = 5
    /// Quads per anchor in the plain form: one for every slice from four slices up (each with the next two).
    var quadCount: Int { fanOut >= 4 ? fanOut : (fanOut == 3 ? 1 : 0) }
    @inline(__always) func sliceTriple(_ k: Int) -> (Int, Int, Int) {
        let a = k, b = (k + 1) % fanOut, c = (k + 2) % fanOut
        return (min(a, b, c), a + b + c - min(a, b, c) - max(a, b, c), max(a, b, c))
    }
    /// A quad's 49 bits folded like a triple's.
    @inline(__always) func hash(anchorBin a: Int, bin1: Int, gap1: Int, bin2: Int, gap2: Int, bin3: Int, gap3: Int) -> Int {
        let raw = UInt64(a) | UInt64(bin1 - a + maxPitchBins) << 7 | UInt64(bin2 - a + maxPitchBins) << 14
            | UInt64(bin3 - a + maxPitchBins) << 21 | UInt64(gap1 / gapStep) << 28 | UInt64(gap2 / gapStep) << 35
            | UInt64(gap3 / gapStep) << 42
        return Int((raw &* 0x9E37_79B9_7F4A_7C15) >> 24)
    }
    /// Triples per anchor: one for every slice from three slices up (each with the next, the last with the first);
    /// with two slices there is only the one pairing.
    var tripleCount: Int { fanOut >= 3 ? fanOut : (fanOut == 2 ? 1 : 0) }
    @inline(__always) func kept(_ h: Int) -> Bool { keepOneIn <= 1 || h & (keepOneIn - 1) == 0 }
    /// The table's size as a power of two: for pairs the hash's own 21 bits; for triples set by the index to the
    /// catalogue (about one slot for every four entries, from 2^20 to 2^26 slots), so that a slot stays a few entries long.
    public internal(set) var tableBits = 24
    /// A triple's 35 bits (anchor pitch, two pitch differences, two time differences) folded by a multiplicative
    /// hash (Knuth's golden-ratio constant): the top bits are its slot in the table, the next 8 a tag kept with
    /// each entry. As a catalogue grows, different triples come to share slots; the tag lets the matcher pass over
    /// the entries of other triples in a slot (all but one in 256) without casting a vote for them.
    @inline(__always) func hash(anchorBin a: Int, bin1: Int, gap1: Int, bin2: Int, gap2: Int) -> Int {
        let raw = UInt64(a) | UInt64(bin1 - a + maxPitchBins) << 7 | UInt64(bin2 - a + maxPitchBins) << 14
            | UInt64(gap1 / gapStep) << 21 | UInt64(gap2 / gapStep) << 28
        return Int((raw &* 0x9E37_79B9_7F4A_7C15) >> 24)
    }
    /// The table slot and the tag of a hash value (a pair's hash is its own slot, with no tag).
    @inline(__always) func slot(_ h: Int) -> Int { triples ? h >> (40 - tableBits) : h }
    @inline(__always) func tag(_ h: Int) -> UInt8 {
        triples ? (compact ? UInt8((h >> (33 - tableBits)) & 0x7f) : UInt8((h >> (32 - tableBits)) & 0xff)) : 0
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
    /// A mark of which songs the index was made from (see `stamp(of:)`); empty when the maker gave none.
    public let stamp: String

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
    let pointFrame: Block<Int32>
    let pointPitch: Block<UInt16>
    /// The hash table: the anchors (their frames on the timeline) of hash h are entries[offsets[h]..<offsets[h + 1]].
    let offsets: Block<UInt32>
    let entries: Block<UInt32>
    /// Ratio quads only: each entry's anchor pitch step (7 bits) and tag (9 bits).
    let extra: Block<UInt16>
    /// Each entry's tag (three-point hashes only; empty otherwise).
    let tags: Block<UInt8>

    public var songCount: Int { ids.count }
    public var hashCount: Int { entries.count }
    /// Bytes the matcher must hold in memory to propose songs: the entries, their tags when kept apart, the table,
    /// and 16 bytes a song (where it starts on the timeline and among the points).
    public var memoryBytes: Int { entries.count * 4 + tags.count + extra.count * 2 + offsets.count * 4 + ids.count * 16 }
    /// Bytes of the songs' points, which only the final check of a dozen or so songs reads: they can stay on storage.
    public var pointBytes: Int { pointFrame.count * 6 }
    public var pointCount: Int { pointFrame.count }

    public init(songs: [(id: String, landmarks: Landmarks)], landmark: LandmarkConfig = LandmarkConfig(),
                pairing: PairingConfig = PairingConfig(), stamp: String = "") {
        self.stamp = stamp
        var pairing = pairing
        if pairing.triples {
            let share = [1.0, 0.75, 0.5, 0.25][max(0, min(3, pairing.minAnchorLevel))]   // the levels are quartiles
            let perAnchor = pairing.ratio ? pairing.ratioFar : (pairing.points == 4 ? pairing.quadCount : pairing.tripleCount)
            let entries = Int(Double(songs.reduce(0) { $0 + $1.landmarks.count } * perAnchor) * share) / max(1, pairing.keepOneIn)
            var bits = 12
            while bits < 26 && (1 << bits) * pairing.entriesPerSlot < entries { bits += 1 }
            pairing.tableBits = bits
        } else {
            pairing.tableBits = PairingConfig.hashBits
        }
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
                    if Int(pointLevel[i]) < p.minAnchorLevel { continue }
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
                    if p.triples && p.points == 4 {
                        for k in 0..<p.quadCount {
                            let (k1, k2, k3) = p.sliceTriple(k)
                            if filled & (1 << k1) != 0 && filled & (1 << k2) != 0 && filled & (1 << k3) != 0 {
                                let h = p.hash(anchorBin: a, bin1: slotBin[k1], gap1: slotGap[k1], bin2: slotBin[k2], gap2: slotGap[k2],
                                               bin3: slotBin[k3], gap3: slotGap[k3])
                                if p.kept(h) { body(h, ta) }
                            }
                        }
                    } else if p.triples {
                        for k in 0..<p.tripleCount {
                            let (k1, k2) = p.slicePair(k)
                            if filled & (1 << k1) != 0 && filled & (1 << k2) != 0 {
                                let h = p.hash(anchorBin: a, bin1: slotBin[k1], gap1: slotGap[k1], bin2: slotBin[k2], gap2: slotGap[k2])
                                if p.kept(h) { body(h, ta) }
                            }
                        }
                    }
                }
            }
        }
        if p.ratio {
            let built = RatioQuads.build(p, songCount: songs.count, pointStart: pointStart, pointFrame: pointFrame,
                                         pointPitch: pointPitch, pointLevel: pointLevel)
            self.songStart = songStart; self.pointStart = pointStart
            self.pointFrame = Block(pointFrame); self.pointPitch = Block(pointPitch)
            offsets = Block(built.offsets); entries = Block(built.entries); extra = Block(built.extra); tags = Block([])
            return
        }
        forEachPair { h, _ in counts[p.slot(h) + 1] += 1 }
        for h in 0..<size { counts[h + 1] += counts[h] }
        var entries = [UInt32](repeating: 0, count: Int(counts[size]))
        var next = counts
        let packed = p.triples && p.compact
        precondition(!packed || timelineFrames / 8 < 1 << 25, "too long a timeline for 25-bit entries")
        var tags = [UInt8](repeating: 0, count: p.triples && !packed ? entries.count : 0)
        forEachPair { h, frame in
            let at = Int(next[p.slot(h)])
            if packed {
                entries[at] = UInt32(frame / 8) << 7 | UInt32(p.tag(h))
            } else {
                entries[at] = UInt32(frame)
                if p.triples { tags[at] = p.tag(h) }
            }
            next[p.slot(h)] += 1
        }
        self.tags = Block(tags); extra = Block([])
        self.songStart = songStart; self.pointStart = pointStart
        self.pointFrame = Block(pointFrame); self.pointPitch = Block(pointPitch)
        offsets = Block(counts); self.entries = Block(entries)
    }

    /// The share of all hashes that sit in buckets (one bucket per hash value) larger than `size`: how lopsided the
    /// table is.
    public func shareInBuckets(largerThan size: Int) -> Double {
        offsets.withUnsafeBufferPointer { offsets in
            var n = 0
            for h in 0..<(offsets.count - 1) where Int(offsets[h + 1] - offsets[h]) > size { n += Int(offsets[h + 1] - offsets[h]) }
            return Double(n) / Double(max(1, entries.count))
        }
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
