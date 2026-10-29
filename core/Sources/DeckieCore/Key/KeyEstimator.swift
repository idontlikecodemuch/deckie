import Foundation
import DeckieAudio

// The lab's lightweight key estimator (mixer/key_light.py), the variant the charter names: chroma from a plain STFT
// (`Chroma.stft`), the edma profile, Pearson correlation against the 24 keys, for the whole track, for the two mix
// windows judged against the song key, and as key segments over the track with the hysteresis rule. Ported line for
// line; the Python semantics that change numbers (numpy's summation order, its dot product, Python's rounding, slicing
// and sort order) are kept through `Py` (PythonCompat.swift). The lab measured this variant at 75 percent exact
// against its confident keys, where Apple's framework reaches 83 (docs/architecture/stage1-results.md, 1e).

/// The key profiles key_light.py carries (Essentia's key.cpp, verbatim): twelve weights per mode, tonic first.
/// The lab's estimator uses `edma`; the others are kept because they cost nothing (the lab compared all six).
/// Kept as the lab has them for parity with its scripts; the engine's key method takes edma, bgate and braw from the
/// literature instead (`HPCPKey.literatureProfiles`), where edma's major minor sixth is 0.32, not 0.31.
public enum KeyProfile: String, CaseIterable, Sendable {
    case krumhansl, temperley, shaath, edma, bgate, braw

    public var major: [Double] { Self.table[self]!.major }
    public var minor: [Double] { Self.table[self]!.minor }

    static let table: [KeyProfile: (major: [Double], minor: [Double])] = [
        .krumhansl: ([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88],
                     [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]),
        .temperley: ([5.0, 2.0, 3.5, 2.0, 4.5, 4.0, 2.0, 4.5, 2.0, 3.5, 1.5, 4.0],
                     [5.0, 2.0, 3.5, 4.5, 2.0, 4.0, 2.0, 4.5, 3.5, 2.0, 1.5, 4.0]),
        .shaath: ([6.6, 2.0, 3.5, 2.3, 4.6, 4.0, 2.5, 5.2, 2.4, 3.7, 2.3, 3.4],
                  [6.5, 2.7, 3.5, 5.4, 2.6, 3.5, 2.5, 5.2, 4.0, 2.7, 4.3, 3.2]),
        .edma: ([1.00, 0.29, 0.50, 0.40, 0.60, 0.56, 0.32, 0.80, 0.31, 0.45, 0.42, 0.39],
                [1.00, 0.31, 0.44, 0.58, 0.33, 0.49, 0.29, 0.78, 0.43, 0.29, 0.53, 0.32]),
        .bgate: ([1.00, 0.00, 0.42, 0.00, 0.53, 0.37, 0.00, 0.77, 0.00, 0.38, 0.21, 0.30],
                 [1.00, 0.00, 0.36, 0.39, 0.00, 0.38, 0.00, 0.74, 0.27, 0.00, 0.42, 0.23]),
        .braw: ([1.0000, 0.1573, 0.4200, 0.1570, 0.5296, 0.3669, 0.1632, 0.7711, 0.1676, 0.3827, 0.2113, 0.2965],
                [1.0000, 0.2330, 0.3615, 0.3905, 0.2925, 0.3777, 0.1961, 0.7425, 0.2701, 0.2161, 0.4228, 0.2272]),
    ]
}

/// One key decision, the lab's `best_key` result `(pc, mode, r, margin)`.
public struct KeyEstimate: Sendable, Equatable {
    /// The tonic's pitch class, 0 = C ... 11 = B (the lab's `pc`).
    public var pitchClass: Int
    /// "major" or "minor" (the lab's `mode`).
    public var mode: String
    /// The Pearson correlation of the chroma with the winning key's profile (the lab's `r`).
    public var r: Double
    /// The winner's correlation minus the runner-up's (the lab's `margin`).
    public var margin: Double

    public init(pitchClass: Int, mode: String, r: Double, margin: Double) {
        self.pitchClass = pitchClass
        self.mode = mode
        self.r = r
        self.margin = margin
    }

    /// The tonic's name as the lab spells it ("C#", not "Db").
    public var key: String { KeyEstimator.pitchNames[pitchClass] }
    /// The Camelot code (the lab's `camelot(pc, mode)`).
    public var camelot: String { Camelot.code(pitchClass: pitchClass, major: mode == "major") }
}

/// A stretch of the track in one key, from the lab's `segments`: `(round(start, 1), camelot, round(mean r, 3))`.
public struct KeySegment: Sendable, Equatable {
    /// Where the segment starts, in seconds: the start of the first window of the run that opened it, rounded to
    /// 0.1 s (the first segment starts at 0.0).
    public var start: Double
    public var camelot: String
    /// The mean correlation of the windows counted in the segment, rounded to 0.001.
    public var meanR: Double

    public init(start: Double, camelot: String, meanR: Double) {
        self.start = start
        self.camelot = camelot
        self.meanR = meanR
    }
}

/// Which end of the track a mix window is at; it decides the lab's fallback window.
public enum MixEnd: Sendable {
    /// The mix-in window; falls back to the first 30 s.
    case mixIn
    /// The mix-out window; falls back to the last 30 s.
    case mixOut
}

/// The key of one mix window, judged against the song key as key_light.py's `--ends` mode does.
public struct WindowKey: Sendable, Equatable {
    /// The chroma frames the key was read from: the window given, or the lab's fallback when that is shorter than
    /// 8 s (the first 30 s for mix-in, the last 30 s for mix-out), cut to the track as a Python slice is.
    public var frames: Range<Int>
    /// The window's own key (the lab's `mix_in` / `mix_out` column is its Camelot code).
    public var estimate: KeyEstimate
    /// How well the song key's profile fits this window (the lab's `r_whole_here`).
    public var songKeyR: Double
    /// `estimate.r - songKeyR`, unrounded (the lab writes it rounded to 2 places as `mix_in_gain`).
    public var gain: Double
    /// The lab's `mix_in_flag` / `mix_out_flag`: the window's key is far from the song key (wheel cost 2 or more) and
    /// fits the window better than the song key by at least the gap (0.08).
    public var flag: Bool

    /// The window's own key as a Camelot code (the lab's `mix_in` / `mix_out`).
    public var camelot: String { estimate.camelot }
}

/// The key results the lab records for a track: the whole-track key with its correlation and margin, the key of
/// each mix window seeded with the song key, and the key segments.
public struct KeyResult: Sendable, Equatable {
    /// The whole-track key (the lab's `whole`, `whole_r`, and its margin).
    public var whole: KeyEstimate
    /// The song key the mix windows are judged against (the lab's `ref`): the one given (Apple's, in the lab and in
    /// the product) or else the whole-track estimate.
    public var songKey: String
    /// The mix-in window's key; nil when the window holds no chroma frames (it starts past the end).
    public var mixIn: WindowKey?
    /// The mix-out window's key; nil when the window holds no chroma frames.
    public var mixOut: WindowKey?
    /// Key segments over the whole track (20 s windows every 5 s, with the hysteresis rule).
    public var segments: [KeySegment]
}

public enum KeyEstimatorError: Error, Equatable, CustomStringConvertible {
    /// The estimator reads 22,050 Hz; 44,100 Hz is halved (`Decimator`); other rates go through `Resampler` first.
    case resampleFirst(sampleRate: Int)

    public var description: String {
        switch self {
        case .resampleFirst(let rate):
            return "the key estimator reads 22050 Hz audio and can halve 44100 Hz; resample \(rate) Hz audio first"
        }
    }
}

public enum KeyEstimator {
    /// The lab's analysis settings (key_light.py): 22,050 Hz, an 8192-point FFT (2.7 Hz bins), a hop of 2048 samples.
    public static let sampleRate = 22050, fftSize = 8192, hop = 2048
    /// Chroma frames per second, the lab's `fps = SR / HOP` (10.7666015625, exact in binary).
    public static let framesPerSecond = Double(sampleRate) / Double(hop)
    /// Pitch-class names as the lab spells them (`PC`).
    public static let pitchNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    // MARK: - The whole pipeline

    /// The chroma the estimator reads, from a mono signal: at 22,050 Hz as it is, at 44,100 Hz halved first with
    /// `Decimator.halve` (`Resampler` with soxr's HQ filter, as the lab resamples); any other rate throws `resampleFirst`.
    public static func chroma(_ signal: [Float], sampleRate rate: Int) throws -> Chromagram {
        switch rate {
        case sampleRate: return Chroma.stft(signal, sampleRate: sampleRate, fftSize: fftSize, hop: hop)
        case 2 * sampleRate: return Chroma.stft(Decimator.halve(signal), sampleRate: sampleRate, fftSize: fftSize, hop: hop)
        default: throw KeyEstimatorError.resampleFirst(sampleRate: rate)
        }
    }

    /// The key results for decoded audio: its channels averaged to mono (the lab's `y.mean(axis=1)`), then
    /// `chroma(_:sampleRate:)` and `estimate(_:mixIn:mixOut:songKey:profile:gap:)`.
    public static func estimate(_ buffer: AudioBuffer, mixIn: (start: Double, end: Double)? = nil,
                                mixOut: (start: Double, end: Double)? = nil, songKey: String? = nil,
                                profile: KeyProfile = .edma) throws -> KeyResult {
        estimate(try chroma(buffer.mono(), sampleRate: buffer.sampleRate), mixIn: mixIn, mixOut: mixOut,
                 songKey: songKey, profile: profile)
    }

    /// The key results from chroma, as key_light.py records them. `mixIn` and `mixOut` are the mix windows in seconds
    /// (the lab reads them from features/<id>.json); nil, or one shorter than 8 s, means the lab's fallback (the first
    /// or last 30 s). `songKey` is the Camelot code the windows are judged against, Apple's key in the lab; nil uses
    /// the whole-track estimate, as the lab does when Apple's is missing.
    public static func estimate(_ chroma: Chromagram, mixIn: (start: Double, end: Double)? = nil,
                                mixOut: (start: Double, end: Double)? = nil, songKey: String? = nil,
                                profile: KeyProfile = .edma, gap: Double = 0.08) -> KeyResult {
        let whole = bestKey(meanChroma(chroma, frames: 0..<chroma.frames), profile: profile)
        let ref = songKey ?? whole.camelot
        return KeyResult(
            whole: whole, songKey: ref,
            mixIn: windowKey(chroma, start: mixIn?.start ?? 0, end: mixIn?.end ?? 0, side: .mixIn, songKey: ref,
                             profile: profile, gap: gap),
            mixOut: windowKey(chroma, start: mixOut?.start ?? 0, end: mixOut?.end ?? 0, side: .mixOut, songKey: ref,
                              profile: profile, gap: gap),
            segments: segments(chroma, profile: profile))
    }

    // MARK: - The lab's functions

    /// The mean of each pitch class over `frames`, as numpy's `C[:, a:b].mean(axis=1)` gives it for the lab's chroma
    /// (librosa returns it in column order, so numpy adds frame after frame); empty frames give zeros.
    public static func meanChroma(_ chroma: Chromagram, frames: Range<Int>) -> [Double] {
        var sum = [Double](repeating: 0, count: 12)
        if frames.isEmpty { return sum }
        chroma.values.withUnsafeBufferPointer { v in
            for t in frames {
                for c in 0..<12 { sum[c] += v[t * 12 + c] }
            }
        }
        let n = Double(frames.count)
        return sum.map { $0 / n }
    }

    /// The lab's `best_key`: the Pearson correlation of 12 pitch-class energies (C first) with each of the 24 keys'
    /// profiles (the profile rolled to each tonic), and the best. Ties go as Python's reverse sort of (r, tonic, mode)
    /// sends them: the higher tonic, then minor before major. A flat chroma gives (C, major, 0, 0).
    public static func bestKey(_ chroma: [Double], profile: KeyProfile = .edma) -> KeyEstimate {
        precondition(chroma.count == 12, "\(chroma.count) pitch classes")
        let mean = Py.pairwiseSum(chroma) / 12
        let c = chroma.map { $0 - mean }
        if Py.norm(c) == 0 { return KeyEstimate(pitchClass: 0, mode: "major", r: 0, margin: 0) }
        var scores: [(r: Double, s: Int, mode: String)] = []
        for (mode, weights) in [("major", profile.major), ("minor", profile.minor)] {
            let pm = Py.pairwiseSum(weights) / 12
            let p = weights.map { $0 - pm }
            for s in 0..<12 {
                let q = roll(p, s)
                scores.append((Py.dot(c, q) / (Py.norm(c) * Py.norm(q)), s, mode))
            }
        }
        scores.sort { ($0.r, $0.s, $0.mode) > ($1.r, $1.s, $1.mode) }
        return KeyEstimate(pitchClass: scores[0].s, mode: scores[0].mode, r: scores[0].r,
                           margin: scores[0].r - scores[1].r)
    }

    /// The lab's `corr_for`: the correlation of a chroma mean with one given key's profile. It differs from
    /// `bestKey`'s in two details the lab has: the profile is rolled before its mean is taken, and 1e-12 is added to
    /// the denominator.
    public static func correlation(_ chroma: [Double], camelot: String, profile: KeyProfile = .edma) -> Double {
        guard let key = Camelot.tonic(camelot) else { preconditionFailure("not a Camelot code: \(camelot)") }
        let mean = Py.pairwiseSum(chroma) / Double(chroma.count)
        let c = chroma.map { $0 - mean }
        var q = roll(key.major ? profile.major : profile.minor, key.pitchClass)
        let qm = Py.pairwiseSum(q) / Double(q.count)
        q = q.map { $0 - qm }
        return Py.dot(c, q) / (Py.norm(c) * Py.norm(q) + 1e-12)
    }

    /// The lab's `segments`: windowed keys with hysteresis. Windows of `windowSeconds` every `hopSeconds` (in whole
    /// frames, rounded down: 215 frames, 19.97 s, every 53 frames, 4.92 s), each with its best key. A new key opens a
    /// segment only when it is outside the running key's tonal area (wheel cost above 0), wins windows in a row with a
    /// margin of at least `minMargin`, and persists: `persist` windows for a far move (wheel cost 3 or more), twice
    /// that for a near one (cost 1 or 2). A window inside the running key's area, or below the margin, ends any run
    /// and counts towards the running segment. Empty for chroma with no frames.
    public static func segments(_ chroma: Chromagram, profile: KeyProfile = .edma, windowSeconds: Double = 20.0,
                                hopSeconds: Double = 5.0, persist: Int = 2, minMargin: Double = 0.04) -> [KeySegment] {
        let fps = framesPerSecond
        let w = Int(windowSeconds * fps), h = Int(hopSeconds * fps), n = chroma.frames
        precondition(h > 0, "hop of \(hopSeconds) s is less than one frame")
        if n == 0 { return [] }
        var keys: [(t: Double, k: String, r: Double, m: Double)] = []
        var a = 0
        while a < max(1, n - w + 1) {
            let e = bestKey(meanChroma(chroma, frames: a..<min(a + w, n)), profile: profile)
            keys.append((Double(a) / fps, e.camelot, e.r, e.margin))
            a += h
        }
        var segs: [(start: Double, k: String, rs: [Double])] = [(0.0, keys[0].k, [keys[0].r])]
        var run: [(t: Double, k: String, r: Double)] = []
        for (t, k, r, m) in keys.dropFirst() {
            let cur = segs[segs.count - 1].k
            let cost = Camelot.wheelCost(k, cur)
            if cost == 0 || m < minMargin {
                segs[segs.count - 1].rs.append(r)
                run = []
                continue
            }
            if let last = run.last, last.k != k { run = [] }
            run.append((t, k, r))
            let need = cost >= 3 ? persist : 2 * persist
            if run.count >= need {
                segs.append((run[0].t, k, run.map(\.r)))
                run = []
            }
        }
        return segs.map { KeySegment(start: Py.round($0.start, 1), camelot: $0.k, meanR: Py.round(Py.pairwiseMean($0.rs), 3)) }
    }

    /// The key of one mix window, judged against the song key, as key_light.py's `--ends` mode computes it. `start`
    /// and `end` are seconds (0 and 0 for a window the lab has no record of); they become frames as
    /// `int(seconds * fps)`. A window shorter than 8 s (86 frames) is replaced by the first 30 s for mix-in and the
    /// last 30 s for mix-out. The key is flagged when it is far from the song key (wheel cost 2 or more) and fits the
    /// window better than the song key does by at least `gap`. Nil when the window holds no frames (the lab would
    /// compute with an empty mean, which is NaN).
    public static func windowKey(_ chroma: Chromagram, start: Double, end: Double, side: MixEnd, songKey: String,
                                 profile: KeyProfile = .edma, gap: Double = 0.08) -> WindowKey? {
        let fps = framesPerSecond, n = chroma.frames
        var a = Int(start * fps), b = Int(end * fps)
        if b - a < Int(8 * fps) {
            switch side {
            case .mixIn: (a, b) = (0, Int(30 * fps))
            case .mixOut: (a, b) = (max(0, n - Int(30 * fps)), n)
            }
        }
        let frames = pythonSlice(a, b, count: n)
        if frames.isEmpty { return nil }
        let cm = meanChroma(chroma, frames: frames)
        let e = bestKey(cm, profile: profile)
        let here = correlation(cm, camelot: songKey, profile: profile)
        let far = Camelot.wheelCost(e.camelot, songKey) >= 2
        return WindowKey(frames: frames, estimate: e, songKeyR: here, gain: e.r - here, flag: far && (e.r - here) >= gap)
    }

    // MARK: - Helpers

    /// `numpy.roll(p, s)`: element i moves to (i + s) mod n.
    static func roll(_ p: [Double], _ s: Int) -> [Double] {
        let n = p.count
        return (0..<n).map { p[Py.mod($0 - s, n)] }
    }

    /// The frames Python's `x[a:b]` selects from `count` frames: negative bounds count from the end, both are clipped
    /// to 0...count, and b <= a is empty.
    static func pythonSlice(_ a: Int, _ b: Int, count n: Int) -> Range<Int> {
        func clip(_ i: Int) -> Int { i < 0 ? max(0, i + n) : min(i, n) }
        let lo = clip(a), hi = clip(b)
        return lo < hi ? lo..<hi : lo..<lo
    }
}

extension Camelot {
    /// How two Camelot codes relate, the lab's `relation` (mixer/key_light.py).
    public enum Relation: String, Sendable {
        /// The same code.
        case exact
        /// Same number, other letter: the relative major or minor (8B C major, 8A A minor).
        case relative
        /// Same letter, one step round the wheel (a fifth apart).
        case neighbour
        /// Other letter, three steps round: the same tonic in the other mode (12A C# minor, 3B C# major).
        case parallel
        case other
    }

    /// The lab's `relation(a, b)`.
    public static func relation(_ a: String, _ b: String) -> Relation {
        if a == b { return .exact }
        let (na, la) = parse(a), (nb, lb) = parse(b)
        if na == nb { return .relative }
        let d = Py.mod(na - nb, 12)
        if la == lb && (d == 1 || d == 11) { return .neighbour }
        if la != lb && (d == 3 || d == 9) { return .parallel }
        return .other
    }

    /// The lab's `wheel_cost(a, b)`: 0 inside the same tonal area (exact, relative, neighbour, parallel); otherwise
    /// the steps round the wheel the short way, plus one when the letter differs.
    public static func wheelCost(_ a: String, _ b: String) -> Int {
        switch relation(a, b) {
        case .exact, .relative, .neighbour, .parallel: return 0
        case .other:
            let (na, la) = parse(a), (nb, lb) = parse(b)
            return min(Py.mod(na - nb, 12), Py.mod(nb - na, 12)) + (la != lb ? 1 : 0)
        }
    }
}
