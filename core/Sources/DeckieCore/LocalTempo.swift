import Foundation

/// What `LocalTempo.compute` reads from a track: the fields of a lab feature file (mixer/features/<id>.json) that
/// `compute(feat)` in mixer/local_tempo.py uses. Times are seconds from the start of the decoded audio; the lab's
/// field names are in brackets.
public struct LocalTempoInput: Sendable, Equatable {
    /// A mix window of the track, by its start and end. A missing end takes the lab's default for that end of the
    /// track (see `LocalTempo.compute`).
    public struct MixWindow: Sendable, Equatable {
        /// Where the window starts (`start_s`), or nil for the default.
        public var start: Double?
        /// Where the window ends (`end_s`), or nil for the default.
        public var end: Double?
        public init(start: Double?, end: Double?) {
            self.start = start
            self.end = end
        }
    }

    /// The track's global tempo in BPM (`bpm`): the reference every local tempo is octave-normalised against, and the
    /// tempo that stands in wherever a window has no steady beat of its own. Must be positive.
    public var bpm: Double
    /// Length of the track (`duration_s`); read only when `lastSound` is nil.
    public var duration: Double
    /// Beat times as the beat tracker detected them, in order (`detected_beats_s`); when empty, the grid's beats are
    /// used in their place, as the lab does.
    public var detectedBeats: [Double]
    /// Downbeat times as the beat tracker detected them, in order (`detected_downbeats_s`); when empty, the grid's
    /// downbeats are used in their place.
    public var detectedDownbeats: [Double]
    /// Beats of the fitted constant grid, sorted (`beats_s`): the detected beats' distance to them is the grid
    /// deviation that decides whether the global tempo already holds in a window.
    public var gridBeats: [Double]
    /// Downbeats of the fitted grid (`downbeats_s`); read only when `detectedDownbeats` is empty.
    public var gridDownbeats: [Double]
    /// The grid's first downbeat (`grid.first_downbeat_s`), the start of bar 1 for the bar numbers; nil means
    /// `firstSound`.
    public var firstDownbeat: Double?
    /// Where the music starts (`first_sound_s`); nil means 0.
    public var firstSound: Double?
    /// Where the music ends (`last_sound_s`); nil means `duration`.
    public var lastSound: Double?
    /// The mix-in window (`mix_in`); nil when the track has none, and then the result's `mixIn` is nil too.
    public var mixIn: MixWindow?
    /// The mix-out window (`mix_out`); nil when the track has none.
    public var mixOut: MixWindow?

    public init(bpm: Double, duration: Double, detectedBeats: [Double], detectedDownbeats: [Double] = [],
                gridBeats: [Double] = [], gridDownbeats: [Double] = [], firstDownbeat: Double? = nil,
                firstSound: Double? = nil, lastSound: Double? = nil, mixIn: MixWindow? = nil,
                mixOut: MixWindow? = nil) {
        self.bpm = bpm
        self.duration = duration
        self.detectedBeats = detectedBeats
        self.detectedDownbeats = detectedDownbeats
        self.gridBeats = gridBeats
        self.gridDownbeats = gridDownbeats
        self.firstDownbeat = firstDownbeat
        self.firstSound = firstSound
        self.lastSound = lastSound
        self.mixIn = mixIn
        self.mixOut = mixOut
    }
}

/// Start, end and windowed tempo measured from a track's raw detected beats: the lab's `local_tempo` block
/// (mixer/local_tempo.py, `compute`), field for field, rounded as the lab rounds. The global grid is one constant
/// tempo per track, which is wrong for tempo-change transition edits, slow intros, rideouts and drifting live
/// recordings; this measures tempo by window instead. A window's tempo is trusted only when its beats fit one steady
/// period within 15 ms over at least 16 beats (or already sit on the global grid within 15 ms); otherwise the global
/// tempo stands in and that end of the track is flagged as having no steady beat. Times are seconds, tempos BPM.
/// Where a Swift name differs from the lab's, the lab's is in brackets.
public struct LocalTempo: Sendable, Equatable {
    /// One window's tempo by robust linear regression of beat time on beat index (the lab's `_local`).
    public struct Window: Sendable, Equatable {
        /// The window's tempo times `mult`, so it reads in the global tempo's octave; 2 decimals.
        public var bpm: Double
        /// The regression's own tempo, 60 / period; 2 decimals (`bpm_raw`).
        public var bpmRaw: Double
        /// The multiplier, of 1/2, 2/3, 3/4, 1, 4/3, 3/2 and 2, that brings `bpmRaw` closest to the global tempo
        /// (smallest absolute log ratio, the first one on a tie); 4 decimals.
        public var mult: Double
        /// Beats within a quarter period of the fitted line after the last pass (`n_beats`).
        public var nBeats: Int
        /// Median distance of those beats from the line, in milliseconds; 1 decimal (`resid_ms`).
        public var residMs: Double
        /// Start of the window; 2 decimals.
        public var t0: Double
        /// End of the window; 2 decimals.
        public var t1: Double

        public init(bpm: Double, bpmRaw: Double, mult: Double, nBeats: Int, residMs: Double, t0: Double, t1: Double) {
            self.bpm = bpm
            self.bpmRaw = bpmRaw
            self.mult = mult
            self.nBeats = nBeats
            self.residMs = residMs
            self.t0 = t0
            self.t1 = t1
        }
    }

    /// Why a window got its tempo (`_decide`); the raw values are the lab's strings.
    public enum Rule: String, Sendable {
        /// The window's detected beats sit on the global grid within 15 ms: the global tempo, trusted.
        case onGlobalGrid = "on_global_grid"
        /// The window has its own steady beat and its tempo differs from the global one by more than 1.5 percent:
        /// the window's tempo, trusted.
        case localDiffers = "local_differs"
        /// The window has its own steady beat within 1.5 percent of the global tempo: the global tempo, trusted.
        case localMatches = "local_matches"
        /// Neither: the global tempo stands in, untrusted.
        case noSteadyBeat = "no_steady_beat"
    }

    /// One 15 s segment of the tempo profile; the lab writes it as `[start, bpm, trusted]`.
    public struct Segment: Sendable, Equatable {
        /// Start of the segment; 1 decimal.
        public var start: Double
        /// The segment's tempo as `decide` gives it.
        public var bpm: Double
        /// Whether `decide` trusted it.
        public var trusted: Bool

        public init(start: Double, bpm: Double, trusted: Bool) {
            self.start = start
            self.bpm = bpm
            self.trusted = trusted
        }
    }

    /// The global tempo everything is measured against (`ref_bpm`).
    public var refBpm: Double
    /// The first 30 s of sound (`first30`).
    public var first30: Window?
    /// The last 30 s of sound (`last30`).
    public var last30: Window?
    /// The mix-in window (`mix_in`).
    public var mixIn: Window?
    /// The mix-out window (`mix_out`).
    public var mixOut: Window?
    /// Median distance in ms from each detected beat in the 30 s after the first sound to the nearest grid beat;
    /// 1 decimal; nil with fewer than 4 detected beats there or fewer than 2 grid beats (`grid_dev_in_ms`).
    public var gridDevInMs: Double?
    /// The same for the 30 s before the last sound (`grid_dev_out_ms`).
    public var gridDevOutMs: Double?
    /// Start tempo: the first 30 s's own tempo when `inRule` is `.localDiffers`, else the global tempo (`bpm_in`).
    public var bpmIn: Double
    /// Whether the start has a steady beat (`in_trusted`).
    public var inTrusted: Bool
    /// Why (`in_rule`).
    public var inRule: Rule
    /// End tempo, from the last 30 s the same way (`bpm_out`).
    public var bpmOut: Double
    /// Whether the end has a steady beat (`out_trusted`).
    public var outTrusted: Bool
    /// Why (`out_rule`).
    public var outRule: Rule
    /// (bpmOut - bpmIn) / bpmIn in percent; 2 decimals (`drift_pct`).
    public var driftPct: Double
    /// Tempo of every 15 s segment from the first sound on.
    public var profile: [Segment]
    /// (fastest - slowest trusted segment) / global tempo in percent; 2 decimals; nil when no segment is trusted
    /// (`range_pct`).
    public var rangePct: Double?
    /// How many profile segments are untrusted (`untrusted_segments`).
    public var untrustedSegments: Int
    /// Where the steady beat starts: the first downbeat from half a second before the first trusted segment on, or
    /// that segment's start when no downbeat follows; 3 decimals; nil when no segment is trusted (`steady_in_s`).
    public var steadyInS: Double?
    /// Its bar number on the global grid, at least 1 (`steady_in_bar`).
    public var steadyInBar: Int?
    /// Where the steady beat ends: the end of the last trusted segment; 3 decimals (`steady_out_s`).
    public var steadyOutS: Double?
    /// Its bar number on the global grid, at least 1 (`steady_out_bar`).
    public var steadyOutBar: Int?
    /// The first downbeat in the 30 s after the first sound; 3 decimals (`first_downbeat_in_s`).
    public var firstDownbeatInS: Double?
    /// The first downbeat in the 30 s before the last sound; 3 decimals (`first_downbeat_out_s`).
    public var firstDownbeatOutS: Double?
    /// Both ends trusted and drifting by more than 2 percent, or trusted segments spread over more than 3 percent
    /// (`tempo_change`).
    public var tempoChange: Bool
    /// Both ends trusted and drifting by more than 5 percent (`transition_track`).
    public var transitionTrack: Bool
    /// The start runs at its own tempo in another relation than 1 to the global tempo, such as half time
    /// (`in_half_time`; the flag is `intro_half_time`).
    public var inHalfTime: Bool
    /// The same for the end (`out_half_time`; the flag is `outro_half_time`).
    public var outHalfTime: Bool
    /// The start has no steady beat (`intro_no_steady_beat`).
    public var introNoSteadyBeat: Bool
    /// The end has no steady beat (`outro_no_steady_beat`).
    public var outroNoSteadyBeat: Bool

    /// The track flags this block sets, in the lab's order (`flags(lt)`).
    public var flags: [String] {
        var f: [String] = []
        if tempoChange { f.append("tempo_change") }
        if transitionTrack { f.append("transition_track") }
        if inHalfTime { f.append("intro_half_time") }
        if outHalfTime { f.append("outro_half_time") }
        if introNoSteadyBeat { f.append("intro_no_steady_beat") }
        if outroNoSteadyBeat { f.append("outro_no_steady_beat") }
        return f
    }

    /// Every flag `flags` can set; the lab removes these from a track's flags before adding the current ones.
    public static let flagNames = ["tempo_change", "transition_track", "intro_half_time", "outro_half_time",
                                   "intro_no_steady_beat", "outro_no_steady_beat"]

    /// Length of the start and end windows (`WIN_S`).
    public static let windowSeconds = 30.0
    /// Length of a profile segment (`SEG_S`).
    public static let segmentSeconds = 15.0
    /// A window is trusted when its median residual is at most this many milliseconds (`TRUST_RESID_MS`); the same
    /// limit on the grid deviation means the window already sits on the global grid.
    public static let trustResidMs = 15.0
    /// ... and it keeps at least this many beats (`TRUST_MIN_BEATS`).
    public static let trustMinBeats = 16
    /// A trusted window's tempo replaces the global one only when they differ by more than this percentage
    /// (`DIFF_PCT`).
    public static let differPct = 1.5

    /// Tempo inside [t0, t1] by robust linear regression of beat time on beat index (`_local`). A median interval
    /// is only good to about 4 percent, since the beat tracker places beats on a 20 ms frame grid; a regression
    /// over 30 s of beats is good to about 0.1 percent. The regression (cumulative integer indexing from the median
    /// interval, three passes of least squares, re-indexing and rejecting beats more than a quarter period off) is
    /// the same code as analyze.py's `_win_fit`, so it is `BeatGrid.windowFit`. Nil with fewer than 8 beats in the
    /// window, when their median interval is not positive, or with fewer than 8 kept at the start of a pass.
    public static func window(_ beats: [Double], from t0: Double, to t1: Double, reference: Double) -> Window? {
        guard let fit = BeatGrid.windowFit(beats.filter { $0 >= t0 && $0 <= t1 }) else { return nil }
        let raw = 60.0 / fit.period
        // Python's min(MULTS, key=...): the first multiplier with the smallest key wins.
        var m = Tempo.multipliers[0]
        var best = abs(log(raw * m / reference))
        for x in Tempo.multipliers.dropFirst() {
            let d = abs(log(raw * x / reference))
            if d < best { best = d; m = x }
        }
        return Window(bpm: Py.round(raw * m, 2), bpmRaw: Py.round(raw, 2), mult: Py.round(m, 4), nBeats: fit.kept,
                      residMs: Py.round(fit.madMs, 1), t0: Py.round(t0, 2), t1: Py.round(t1, 2))
    }

    /// Median distance in ms (1 decimal) from each detected beat inside [t0, t1] to the nearest beat of the sorted
    /// grid (`_grid_dev_ms`). Nil with fewer than 4 detected beats there or fewer than 2 grid beats.
    public static func gridDeviationMs(_ detected: [Double], grid: [Double], from t0: Double, to t1: Double) -> Double? {
        let d = detected.filter { $0 >= t0 && $0 <= t1 }
        if d.count < 4 || grid.count < 2 { return nil }
        let near = d.map { x -> Double in
            let i = min(max(Py.countBelow(x, in: grid), 1), grid.count - 1)
            return min(abs(x - grid[i - 1]), abs(x - grid[i]))
        }
        return Py.round(Py.median(near) * 1000, 1)
    }

    /// The trust rule (`_trusted`): a window is trusted when its residual is within 15 ms and it kept at least 16
    /// beats.
    public static func isTrusted(_ w: Window?) -> Bool {
        guard let w else { return false }
        return w.residMs <= trustResidMs && w.nBeats >= trustMinBeats
    }

    /// A window's tempo (`_decide`): the global tempo when the window's beats already sit on the global grid, the
    /// window's own when it has a steady beat that differs by more than 1.5 percent, the global one when its steady
    /// beat agrees, and otherwise the global tempo, untrusted.
    public static func decide(_ w: Window?, gridDeviationMs: Double?, reference ref: Double)
        -> (bpm: Double, trusted: Bool, rule: Rule) {
        if let g = gridDeviationMs, g <= trustResidMs { return (ref, true, .onGlobalGrid) }
        if let w, isTrusted(w) {
            if abs(w.bpm - ref) / ref * 100 > differPct { return (w.bpm, true, .localDiffers) }
            return (ref, true, .localMatches)
        }
        return (ref, false, .noSteadyBeat)
    }

    /// The whole block for one track (`compute`). The start window is the first 30 s of sound and the end window
    /// the last 30 s (each cut to the sound); a mix window without a start or an end takes the first sound and 30 s
    /// after it (mix-in) or 30 s before the last sound and the last sound (mix-out), uncut; the grid deviations always
    /// look at the full 30 s after the first sound and before the last; the profile steps 15 s at a time from the
    /// first sound while more than 9 s of sound remain.
    public static func compute(_ input: LocalTempoInput) -> LocalTempo {
        let ref = input.bpm
        precondition(ref > 0, "local tempo needs a positive global tempo (the lab divides by it)")
        let det = input.detectedBeats.isEmpty ? input.gridBeats : input.detectedBeats
        let grid = input.gridBeats
        let downs = input.detectedDownbeats.isEmpty ? input.gridDownbeats : input.detectedDownbeats
        let fs = input.firstSound ?? 0.0, ls = input.lastSound ?? input.duration
        let win = windowSeconds, seg = segmentSeconds

        let first30 = window(det, from: fs, to: min(fs + win, ls), reference: ref)
        let last30 = window(det, from: max(ls - win, fs), to: ls, reference: ref)
        let mixIn = input.mixIn.flatMap { window(det, from: $0.start ?? fs, to: $0.end ?? fs + win, reference: ref) }
        let mixOut = input.mixOut.flatMap {
            window(det, from: $0.start ?? ls - win, to: $0.end ?? ls, reference: ref)
        }
        let devIn = gridDeviationMs(det, grid: grid, from: fs, to: fs + win)
        let devOut = gridDeviationMs(det, grid: grid, from: ls - win, to: ls)
        let (bi, ti, ri) = decide(first30, gridDeviationMs: devIn, reference: ref)
        let (bo, to, ro) = decide(last30, gridDeviationMs: devOut, reference: ref)
        let drift = Py.round((bo - bi) / bi * 100, 2)

        var profile: [Segment] = []
        var t = fs
        while t + seg * 0.6 < ls {
            let end = min(t + seg, ls)
            let (b, tr, _) = decide(window(det, from: t, to: end, reference: ref),
                                    gridDeviationMs: gridDeviationMs(det, grid: grid, from: t, to: end),
                                    reference: ref)
            profile.append(Segment(start: Py.round(t, 1), bpm: b, trusted: tr))
            t += seg
        }
        let trusted = profile.filter { $0.trusted }
        let vals = trusted.map { $0.bpm }
        let range: Double? = vals.isEmpty ? nil : Py.round((vals.max()! - vals.min()!) / ref * 100, 2)

        let barS = 240.0 / ref
        let fd0 = input.firstDownbeat ?? fs
        func barOf(_ t: Double) -> Int { Int(Py.roundEven((t - fd0) / barS)) + 1 }
        var steadyInS: Double?, steadyInBar: Int?, steadyOutS: Double?, steadyOutBar: Int?
        if let firstTrusted = trusted.first, let lastTrusted = trusted.last {
            // From the first trusted segment's start as the lab rounds it, to the first downbeat after it.
            var tIn = firstTrusted.start
            if let d = downs.first(where: { $0 >= tIn - 0.5 }) { tIn = d }
            let tOut = min(lastTrusted.start + seg, ls)
            steadyInS = Py.round(tIn, 3)
            steadyInBar = max(1, barOf(tIn))
            steadyOutS = Py.round(tOut, 3)
            steadyOutBar = max(1, barOf(tOut))
        }
        let firstDownIn = downs.first { $0 >= fs && $0 <= fs + win }
        let firstDownOut = downs.first { $0 >= ls - win && $0 <= ls }

        return LocalTempo(
            refBpm: ref, first30: first30, last30: last30, mixIn: mixIn, mixOut: mixOut,
            gridDevInMs: devIn, gridDevOutMs: devOut,
            bpmIn: bi, inTrusted: ti, inRule: ri, bpmOut: bo, outTrusted: to, outRule: ro, driftPct: drift,
            profile: profile, rangePct: range, untrustedSegments: profile.count - trusted.count,
            steadyInS: steadyInS, steadyInBar: steadyInBar, steadyOutS: steadyOutS, steadyOutBar: steadyOutBar,
            firstDownbeatInS: firstDownIn.map { Py.round($0, 3) },
            firstDownbeatOutS: firstDownOut.map { Py.round($0, 3) },
            tempoChange: (ti && to && abs(drift) > 2.0) || (range ?? 0) > 3.0,
            transitionTrack: ti && to && abs(drift) > 5.0,
            inHalfTime: ti && ri == .localDiffers && (first30?.mult ?? 1.0) != 1.0,
            outHalfTime: to && ro == .localDiffers && (last30?.mult ?? 1.0) != 1.0,
            introNoSteadyBeat: !ti, outroNoSteadyBeat: !to)
    }
}
