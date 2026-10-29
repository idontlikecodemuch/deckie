import Foundation

/// Where a track is sung, to the beat: research O's section 3, items A1 to A6 (docs/research/o-vocal-uses.md). Memo O
/// found that DJs use vocals six ways (keep two apart, hand off, acapella, tease, echo out, singalong) and that a
/// per-bar probability serves few of them: a hand-off needs the beat of the last word, a "drop on the four" the
/// pickup, an acapella a vocal-free stretch in the middle of the track. This reads all of that from what the engine
/// already has: a vocal tagger's frame-by-frame scores (finer than a bar: YAMNet's are 0.48 s apart), the bar grid, the
/// 8-bar lattice, the per-bar `low_db`, `high_db` and onset density, and the fade-out.
///
/// Every rule is a first cut on uncalibrated scores, so each is relative to the track (the threshold is a fraction of
/// the track's own 95th-percentile score, with a floor), and the parameters and the threshold used are kept beside the
/// result: the Mac's listening test tunes them, and a reader can tell which rule made a record.
///
/// Conventions are the crate's: bars 1-based, beats 1 to 4 within a bar; a stretch starts on a beat and ends at a beat
/// line, exclusive, so an end can be beat 1 of bar `nBars + 1`, the grid's end line.
public struct VocalStructure: Sendable, Equatable {
    /// A vocal tagger's scores, frame by frame: frame k is centred at `centreSeconds + k hopSeconds` (YAMNet: 0.48 s
    /// apart, frame 0 at 0.4875 s). A tagger that gives only bars is read as one frame per bar (`perBar(_:grid:)`).
    public struct Frames: Sendable, Equatable {
        public var scores: [Double]
        public var hopSeconds: Double
        public var centreSeconds: Double
        /// True when the time a score crosses the threshold is read between two frame centres by straight-line
        /// interpolation (a tagger's own frames, whose windows overlap the change); false when the change is taken to
        /// be halfway between the two frames (bars: a bar's mean says nothing about where in the bar the voice began).
        public var interpolated: Bool

        public init(scores: [Double], hopSeconds: Double, centreSeconds: Double, interpolated: Bool = true) {
            precondition(hopSeconds > 0, "frames need a positive hop")
            self.scores = scores
            self.hopSeconds = hopSeconds
            self.centreSeconds = centreSeconds
            self.interpolated = interpolated
        }

        /// One frame per bar, centred in it: bar resolution, for a tagger without a finer series. A change is placed
        /// on the bar line.
        public static func perBar(_ values: [Double], grid: BarGrid) -> Frames {
            Frames(scores: values, hopSeconds: grid.barS, centreSeconds: grid.firstDownbeatS + grid.barS / 2,
                   interpolated: false)
        }

        /// The centre of frame `k`, in seconds.
        public func time(_ k: Int) -> Double { centreSeconds + Double(k) * hopSeconds }
    }

    /// The rules' parameters. The defaults are a first cut, chosen on the synthesised test tracks and memo O's
    /// reading of how DJs work; none is tuned on real music yet.
    public struct Parameters: Sendable, Equatable {
        /// A frame is sung when its score is at least `max(thresholdFloor, thresholdFraction x the 95th percentile of
        /// the track's frame scores)`. Relative to the track because the scores are not calibrated (YAMNet gives the
        /// synthesised voice a few hundredths and a real voice far more); the floor keeps a track with no voice from
        /// having its own background read as singing (the synthesised track's instrumental frames stay under 0.004).
        /// A quarter: YAMNet's score rose late as the voice filled a frame's 0.96 s window (on the synthesised voice,
        /// 4 percent of its peak with the window 35 percent voiced, 10 percent at 58, about half at 85), roughly with
        /// the square of the voiced share, so a quarter of the peak is crossed when the window is about half voiced,
        /// which puts the crossing near the time the voice starts or stops; and sung frames dip far below their peak,
        /// so half the peak split verses apart. It also errs toward hearing a voice: a missed vocal makes a clash, a
        /// false one only an unused bar.
        public var thresholdFraction = 0.25
        public var thresholdFloor = 0.01
        /// Dips shorter than this many beats between sung stretches are bridged, so a span is a verse or a chorus
        /// rather than a line (memo O, section 4: Apple's `ranges` bridges dips the same way). Two bars: longer than a
        /// breath or a fill between lines, shorter than the 4-bar breaks DJs mix in.
        public var bridgeBeats = 8
        /// After bridging, a sung stretch shorter than this many beats is dropped as a blip (one YAMNet frame is about a
        /// beat at 124 BPM). Bridging comes first, so a line of short syllables is joined before this test.
        public var minSpanBeats = 2
        /// The first sung point is a pickup when it is within this many beats before a downbeat (1: it is beat 4).
        public var pickupBeats = 1
        /// A free gap is at least this many bars long, counted from its start snapped to the lattice.
        public var minGapBars = 8
        /// The intro and outro kinds are read from at most this many free bars next to the track's edge, the part a DJ
        /// mixes over.
        public var kindBars = 16
        /// A free intro or outro is `beat_only` when its median onset density is at least this share of the track's
        /// median (a beat goes on) and its median `high_db` is at most `brightMarginDb` above the track's median (not a
        /// riser or a noise sweep, whose onsets are not a beat); otherwise it is `ambient`.
        public var beatDensityRatio = 0.5
        public var brightMarginDb = 6.0
        /// A bar's vocal is exposed (proxy) when at least half its beats are sung, its `low_db` is at least
        /// `exposedLowDropDb` under the track's median and its onset density at most `exposedDensityRatio` of the
        /// track's median: the bass and the drums have dropped while the voice goes on. Runs of `exposedMinBars` bars
        /// or more are kept.
        public var exposedLowDropDb = 6.0
        public var exposedDensityRatio = 0.5
        public var exposedMinBars = 2

        public init() {}

        /// The engine's parameters.
        public static let standard = Parameters()
    }

    /// A place on the grid: the 1-based bar, the beat in it (1 to 4), and the time in seconds it was read from.
    public struct Point: Sendable, Equatable {
        public var bar: Int
        public var beat: Int
        public var seconds: Double
        public init(bar: Int, beat: Int, seconds: Double) { self.bar = bar; self.beat = beat; self.seconds = seconds }
    }

    /// A sung stretch.
    public struct Span: Sendable, Equatable {
        /// The beat the singing starts on (the grid beat nearest the time the score rises through the threshold), and
        /// that time.
        public var start: Point
        /// The beat line the singing stops at (the grid beat nearest the time the score falls through the threshold:
        /// an exclusive end, so the last sung beat is the one before), and that time.
        public var end: Point
        /// Beats from bar 1's downbeat to `start` and to `end` (0-based), the form the other fields are worked out on.
        public var startBeatIndex: Int
        public var endBeatIndex: Int
        /// Beats from the nearest 8-bar lattice point to `start` and to `end`, signed (-15 to 16; negative is before
        /// the lattice point): near zero, the stretch starts or stops on a phrase boundary, where a hand-off or an echo
        /// out sounds intended and anywhere else reads as a mistake (memo O, item A6).
        public var startOffsetBeats: Int
        public var endOffsetBeats: Int

        public init(start: Point, end: Point, startBeatIndex: Int, endBeatIndex: Int, startOffsetBeats: Int,
                    endOffsetBeats: Int) {
            self.start = start; self.end = end; self.startBeatIndex = startBeatIndex; self.endBeatIndex = endBeatIndex
            self.startOffsetBeats = startOffsetBeats; self.endOffsetBeats = endOffsetBeats
        }
    }

    /// Bars `startBar ..< endBar` (1-based, the end a bar line).
    public struct Stretch: Sendable, Equatable {
        public var startBar: Int
        public var endBar: Int
        public var bars: Int { endBar - startBar }
        public init(startBar: Int, endBar: Int) { self.startBar = startBar; self.endBar = endBar }
    }

    /// What the vocal-free intro or outro holds.
    public enum EdgeKind: String, Sendable, Equatable, CaseIterable {
        /// A beat goes on and nothing bright washes over it: it can be looped or mixed over.
        case beatOnly = "beat_only"
        /// Little rhythm (pads, a riser, a spoken or ambient opening): a blend, not a beat-matched loop.
        case ambient
        /// No free bar: the voice is there from bar 1, or still there in the last bar.
        case vocal
        /// The outro's free bars are all inside the fade-out (never the intro: the engine detects no fade-in).
        case fade
    }

    public var parameters: Parameters
    /// The frame score a frame needed to count as sung, and the track's 95th-percentile score it came from.
    public var threshold: Double
    public var scoreP95: Double
    /// Seconds between the frames read: the tagger's hop, or the bar length when it gave bars only.
    public var frameHopSeconds: Double
    /// The 8-bar lattice the free gaps are snapped to and the offsets measured from (`Phrase.latticePhaseBar`).
    public var latticePhaseBar: Int
    /// The sung stretches, in order, none overlapping (A1).
    public var spans: [Span]
    /// The first sung beat, and whether it is a pickup (A2); nil and false without a sung stretch.
    public var first: Point?
    public var pickup: Bool
    /// The last sung beat (the beat before the last span's end line), with the time the singing stops (A2).
    public var last: Point?
    /// Whole bars before the first sung beat and after the last; the track's bar count when nothing is sung (A3).
    public var introFreeBars: Int
    public var outroFreeBars: Int
    public var introKind: EdgeKind
    public var outroKind: EdgeKind
    /// Vocal-free stretches of `minGapBars` or more, anywhere, each starting on the lattice (A4).
    public var freeGaps: [Stretch]
    /// Stretches where the voice goes on over little bass and few onsets: a stand-in for memo O's `exposed` (vocal
    /// high, drums and bass low, A5), which needs drum and bass activity this engine does not measure.
    public var exposedProxy: [Stretch]
    /// For each bar, the share of its four beats inside a span (0, 0.25, ..., 1).
    public var barCoverage: [Double]

    /// The vocal structure of a track from its tagger's `frames` and its grid: `latticePhaseBar` is the phrase
    /// lattice, `lowDb`, `highDb` and `onsetDensity` the per-bar series (one value per bar), `fadeStartBar` the first
    /// bar of the fade-out, nil when the track does not fade.
    public init(frames: Frames, grid: BarGrid, latticePhaseBar: Int, lowDb: [Double], highDb: [Double],
                onsetDensity: [Double], fadeStartBar: Int?, parameters: Parameters = .standard) {
        let n = grid.nBars, beatS = grid.beatS
        precondition(n >= 1, "the vocal structure needs bars")
        precondition(lowDb.count == n && highDb.count == n && onsetDensity.count == n,
                     "per-bar series of \(lowDb.count), \(highDb.count), \(onsetDensity.count) values for \(n) bars")
        let s = frames.scores
        let p95 = s.isEmpty ? 0 : Py.percentile(s, 95)
        let thr = max(parameters.thresholdFloor, parameters.thresholdFraction * p95)

        // Runs of sung frames, each as the times its score rises and falls through the threshold, read between frame
        // centres by straight-line interpolation (finer than the hop, which is about a beat) or, for bars, halfway. A
        // run at either end of the frames starts or stops half a hop beyond its outer frame.
        func crossing(_ a: Int, _ b: Int) -> Double {
            let f = frames.interpolated && s[b] != s[a] ? min(max((thr - s[a]) / (s[b] - s[a]), 0), 1) : 0.5
            return frames.time(a) + f * (frames.time(b) - frames.time(a))
        }
        var runs: [(start: Double, end: Double)] = []
        var k = 0
        while k < s.count {
            guard s[k] >= thr else { k += 1; continue }
            var j = k
            while j + 1 < s.count && s[j + 1] >= thr { j += 1 }
            let start = k > 0 ? crossing(k - 1, k) : max(0, frames.time(k) - frames.hopSeconds / 2)
            let end = j + 1 < s.count ? crossing(j, j + 1) : frames.time(j) + frames.hopSeconds / 2
            runs.append((start, end))
            k = j + 1
        }
        // Bridge the short dips, then drop what is still a blip.
        var bridged: [(start: Double, end: Double)] = []
        for r in runs {
            if let last = bridged.last, r.start - last.end < Double(parameters.bridgeBeats) * beatS {
                bridged[bridged.count - 1].end = r.end
            } else {
                bridged.append(r)
            }
        }
        let kept = bridged.filter { $0.end - $0.start >= Double(parameters.minSpanBeats) * beatS }

        // On the grid: beat index 0 is bar 1's downbeat, 4 n the end line.
        let endLine = 4 * n
        func nearestBeat(_ t: Double) -> Int { Int(((t - grid.firstDownbeatS) / beatS + 0.5).rounded(.down)) }
        func point(_ index: Int, _ t: Double) -> Point { Point(bar: index / 4 + 1, beat: index % 4 + 1, seconds: t) }
        let phase0 = 4 * (latticePhaseBar - 1)
        func offset(_ index: Int) -> Int {
            let d = Py.mod(index - phase0, 32)
            return d > 16 ? d - 32 : d
        }
        var spans: [Span] = []
        for r in kept {
            let a = min(max(nearestBeat(r.start), 0), endLine - 1)
            var b = min(max(nearestBeat(r.end), 1), endLine)
            if b <= a { b = a + 1 }
            // Stretches the clamp to the grid pushed together (singing before bar 1 or after the end line) are one.
            if let prev = spans.last, a < prev.endBeatIndex {
                let end = max(b, prev.endBeatIndex)
                spans[spans.count - 1].end = point(end, r.end)
                spans[spans.count - 1].endBeatIndex = end
                spans[spans.count - 1].endOffsetBeats = offset(end)
                continue
            }
            spans.append(Span(start: point(a, r.start), end: point(b, r.end), startBeatIndex: a, endBeatIndex: b,
                              startOffsetBeats: offset(a), endOffsetBeats: offset(b)))
        }

        let first = spans.first.map { point($0.startBeatIndex, $0.start.seconds) }
        let last = spans.last.map { point($0.endBeatIndex - 1, $0.end.seconds) }
        var coverage = [Double](repeating: 0, count: n)
        for sp in spans { for i in sp.startBeatIndex..<sp.endBeatIndex { coverage[i / 4] += 0.25 } }
        let introFree = first.map { $0.bar - 1 } ?? n
        let outroFree = last.map { n - $0.bar } ?? n

        // Free gaps: whole bars with no sung beat, the start moved forward to the next lattice bar.
        var gaps: [Stretch] = []
        var b0 = 0
        while b0 < n {
            guard coverage[b0] == 0 else { b0 += 1; continue }
            var e0 = b0
            while e0 < n && coverage[e0] == 0 { e0 += 1 }
            var start = b0 + 1
            while Py.mod(start - latticePhaseBar, Phrase.length) != 0 { start += 1 }
            if e0 + 1 - start >= parameters.minGapBars { gaps.append(Stretch(startBar: start, endBar: e0 + 1)) }
            b0 = e0
        }

        // The intro and outro kinds.
        let medianDensity = Py.median(onsetDensity), medianHigh = Py.median(highDb), medianLow = Py.median(lowDb)
        func kind(_ bars: Range<Int>) -> EdgeKind {
            let d = Py.median(Array(onsetDensity[bars])), h = Py.median(Array(highDb[bars]))
            let busy = medianDensity > 0 ? d >= parameters.beatDensityRatio * medianDensity : d > 0
            return busy && h - medianHigh <= parameters.brightMarginDb ? .beatOnly : .ambient
        }
        let introKind: EdgeKind = introFree == 0 ? .vocal : kind(0..<min(introFree, parameters.kindBars))
        let outroKind: EdgeKind
        if outroFree == 0 {
            outroKind = .vocal
        } else {
            let from = max(n - outroFree, n - parameters.kindBars)  // 0-based first bar read
            if let fade = fadeStartBar, fade - 1 <= from {
                outroKind = .fade
            } else {
                outroKind = kind(from..<(fadeStartBar.map { min(n, $0 - 1) } ?? n))
            }
        }

        // The exposed-vocal proxy.
        var exposed: [Stretch] = []
        var e = 0
        while e < n {
            func isExposed(_ i: Int) -> Bool {
                coverage[i] >= 0.5 && lowDb[i] <= medianLow - parameters.exposedLowDropDb
                    && onsetDensity[i] <= parameters.exposedDensityRatio * medianDensity
            }
            guard isExposed(e) else { e += 1; continue }
            var f = e
            while f < n && isExposed(f) { f += 1 }
            if f - e >= parameters.exposedMinBars { exposed.append(Stretch(startBar: e + 1, endBar: f + 1)) }
            e = f
        }

        self.parameters = parameters
        threshold = thr
        scoreP95 = p95
        frameHopSeconds = frames.hopSeconds
        self.latticePhaseBar = latticePhaseBar
        self.spans = spans
        self.first = first
        pickup = first.map { $0.beat > 4 - parameters.pickupBeats } ?? false
        self.last = last
        introFreeBars = introFree
        outroFreeBars = outroFree
        self.introKind = introKind
        self.outroKind = outroKind
        freeGaps = gaps
        exposedProxy = exposed
        barCoverage = coverage
    }
}
