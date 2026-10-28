import Foundation

/// Onset strength as the lab computes it: `librosa.onset.onset_strength(S=logmel, sr=22050, hop_length=512)`
/// (librosa 1.0.0, mixer/analyze.py), the spectral flux of the log-mel spectrogram. Given S, librosa uses it as it is
/// (no mel slice: all 64 bands, `channels=None`, one aggregate over `slice(None)`), with its defaults lag 1,
/// max_size 1 (so the reference is S itself, no maximum filter), detrend off, center on, aggregate `numpy.mean`, and
/// n_fft 2048 (librosa's default, not inferred from S). In librosa's order:
///
///   d_(t, m)  = max(0, S_(t + lag, m) - S_(t, m))          t = 0 ... frames - 1 - lag: the rise in each band
///   o_t       = (d_(t,0) + d_(t,1) + ... ) / bands          the mean over the bands, added in band order (numpy's
///                                                          mean over the first axis of a C-ordered array)
///   then lag + n_fft / (2 hop) zeros in front (1 + 2 = 3 here: the lag, and the centring shift that puts each rise
///   at the frame whose window it fills), and the result cut back to the input's frame count, so the last two rises
///   are dropped.
///
/// So value t (t >= 3) is the mean rise from frame t - 3 to frame t - 2, and values 0, 1 and 2 are zero.
public enum OnsetStrength {
    public static func compute(logMel s: FrameMatrix, lag: Int = 1, fftSize: Int = 2048, hop: Int = 512) -> [Double] {
        precondition(lag >= 1, "lag=\(lag) must be a positive integer")
        let frames = s.frames, bands = s.rows
        var out = [Double](repeating: 0, count: frames)
        let pad = lag + fftSize / (2 * hop)
        if frames <= lag || bands == 0 { return out }
        s.values.withUnsafeBufferPointer { v in
            var t = pad
            while t < frames {
                let j = t - pad  // the rise from frame j to frame j + lag
                if j + lag >= frames { break }
                let a = v.baseAddress! + j * bands, b = v.baseAddress! + (j + lag) * bands
                var sum = 0.0, m = 0
                while m < bands {
                    let d = b[m] - a[m]
                    sum += d > 0 ? d : 0
                    m += 1
                }
                out[t] = sum / Double(bands)
                t += 1
            }
        }
        return out
    }
}

/// Onset detection as the lab calls it for the per-bar onset density: `librosa.onset.onset_detect(
/// onset_envelope=onset_env, sr=22050, hop_length=512, units="time")` (librosa 1.0.0, mixer/analyze.py). librosa
/// normalises the envelope to 0 ... 1 (minus its minimum, divided by its maximum plus the smallest normal number) and
/// picks peaks greedily (`librosa.util.peak_pick`, method "greedy") with the parameters onset_detect sets from the
/// sample rate and hop: pre_max 30 ms, post_max 0 ms + 1 frame, pre_avg 100 ms, post_avg 100 ms + 1 frame, wait 30 ms
/// (each `seconds * sr // hop`, then rounded up), delta 0.07. At 22,050 Hz and hop 512 that is pre_max 1,
/// post_max 1, pre_avg 4, post_avg 5, wait 1.
public enum OnsetDetect {
    /// The greedy peak picker's parameters, in frames (delta in envelope units).
    public struct PeakPick: Sendable, Equatable {
        public var preMax: Int, postMax: Int, preAvg: Int, postAvg: Int, wait: Int
        public var delta: Double
        public init(preMax: Int, postMax: Int, preAvg: Int, postAvg: Int, wait: Int, delta: Double) {
            precondition(preMax >= 0 && preAvg >= 0 && wait >= 0 && delta >= 0 && postMax > 0 && postAvg > 0)
            (self.preMax, self.postMax, self.preAvg, self.postAvg, self.wait, self.delta) =
                (preMax, postMax, preAvg, postAvg, wait, delta)
        }

        /// onset_detect's defaults: Python's `0.03 * sr // hop_length` and so on, rounded up to whole frames.
        public static func onsetDefaults(sampleRate: Int, hop: Int) -> PeakPick {
            let sr = Double(sampleRate), h = Double(hop)
            func frames(_ x: Double) -> Int { Int(x.rounded(.up)) }
            return PeakPick(preMax: frames(floorDiv(0.03 * sr, h)), postMax: frames(floorDiv(0.00 * sr, h) + 1),
                            preAvg: frames(floorDiv(0.10 * sr, h)), postAvg: frames(floorDiv(0.10 * sr, h) + 1),
                            wait: frames(floorDiv(0.03 * sr, h)), delta: 0.07)
        }
    }

    /// librosa's greedy peak picker (`librosa.util.peak_pick`, the numba function `__peak_pick_greedy`): frame 0 is a
    /// peak when it is the largest of the first post_max values and at least delta above the mean of the first post_avg;
    /// then from frame 1 (or wait + 1 after a peak at 0), frame n is a peak when it equals the largest value in
    /// n - pre_max ..< n + post_max and is at least delta above the mean of n - pre_avg ..< n + post_avg (both windows
    /// cut at the ends); after a peak the next `wait` frames are skipped. Means are added in turn, as numba does.
    public static func peakPick(_ x: [Double], _ p: PeakPick) -> [Int] {
        let n = x.count
        guard n > 0 else { return [] }
        var peaks: [Int] = []
        x.withUnsafeBufferPointer { b in
            func maxOf(_ lo: Int, _ hi: Int) -> Double {
                var m = b[lo], i = lo + 1
                while i < hi { if b[i] > m { m = b[i] }; i += 1 }
                return m
            }
            func meanOf(_ lo: Int, _ hi: Int) -> Double {
                var s = 0.0, i = lo
                while i < hi { s += b[i]; i += 1 }
                return s / Double(hi - lo)
            }
            var i = 1
            if b[0] >= maxOf(0, min(p.postMax, n)) && b[0] >= meanOf(0, min(p.postAvg, n)) + p.delta {
                peaks.append(0)
                i = p.wait + 1
            }
            while i < n {
                if b[i] != maxOf(max(0, i - p.preMax), min(i + p.postMax, n)) { i += 1; continue }
                if !(b[i] >= meanOf(max(0, i - p.preAvg), min(i + p.postAvg, n)) + p.delta) { i += 1; continue }
                peaks.append(i)
                i += p.wait + 1
            }
        }
        return peaks
    }

    /// `librosa.onset.onset_detect(onset_envelope=envelope, sr=sampleRate, hop_length=hop)` in frames: the envelope
    /// normalised to 0 ... 1, then `peakPick` with onset_detect's defaults. None when the normalised envelope is all
    /// zero or not finite.
    public static func frames(envelope: [Double], sampleRate: Int = 22050, hop: Int = 512) -> [Int] {
        guard let lo = envelope.min() else { return [] }
        var x = envelope.map { $0 - lo }
        let scale = x.max()! + Double.leastNormalMagnitude  // util.tiny: the smallest normal float64
        for i in x.indices { x[i] /= scale }
        if !x.contains(where: { $0 != 0 }) || !x.allSatisfy({ $0.isFinite }) { return [] }
        return peakPick(x, .onsetDefaults(sampleRate: sampleRate, hop: hop))
    }

    /// The same with units="time": frame times hop, divided by the sample rate (librosa's frames_to_time).
    public static func times(envelope: [Double], sampleRate: Int = 22050, hop: Int = 512) -> [Double] {
        frames(envelope: envelope, sampleRate: sampleRate, hop: hop).map { Double($0 * hop) / Double(sampleRate) }
    }

    /// Python's `a // b` for floats (CPython's float_floor_div): the quotient of fmod's exact remainder, floored.
    static func floorDiv(_ a: Double, _ b: Double) -> Double {
        var mod = fmod(a, b)
        var div = (a - mod) / b
        if mod != 0 {
            if (b < 0) != (mod < 0) { mod += b; div -= 1.0 }
        }
        if div != 0 {
            var fl = div.rounded(.down)
            if div - fl > 0.5 { fl += 1.0 }
            return fl
        }
        return Double(signOf: a / b, magnitudeOf: 0.0)
    }
}
