import Foundation
import DeckieAudio

// The loudness module (Biquad.swift, KWeighting.swift, Loudness.swift, TruePeak.swift) reproduces what the lab measures
// in mixer/analyze.py, for any sample rate and with no dependency: K-weighting, integrated loudness and loudness range
// as pyloudnorm 0.2.0 computes them, per-bar and short-term loudness as analyze.py computes them, and true peak as
// scipy.signal.resample_poly's 4x oversampling gives it. The algorithms follow pyloudnorm (MIT licence, Christian
// Steinmetz; its source was read as the reference) and scipy's resample_poly and firwin by description; no code is
// copied. The standards behind them: ITU-R BS.1770-4 (K-weighting, gating, true peak), EBU Tech 3341 (loudness
// metering) and EBU Tech 3342 (loudness range).

/// Loudness measured as the lab measures it (mixer/analyze.py): integrated loudness and loudness range as pyloudnorm
/// 0.2.0 computes them, and the short-term loudness of `st_lufs`. Results are in LUFS (loudness units relative to full
/// scale) and LU (loudness units, for differences). Every sample rate works; filters are computed for the buffer's.
public enum Loudness {
    /// Integrated loudness in LUFS, gated per ITU-R BS.1770-4 as pyloudnorm computes it: the K-weighted power of 400 ms
    /// blocks every 100 ms; blocks below -70 LUFS dropped (the absolute gate); then blocks not above both -70 LUFS and
    /// the loudness of the remaining blocks' mean power minus 10 LU dropped (the relative gate); the loudness of the
    /// mean power of what is left. Minus infinity when nothing passes the gates (silence); nil when the audio is
    /// shorter than one block (pyloudnorm raises an error there).
    public static func integrated(_ buffer: AudioBuffer, design: KWeighting.Design = .pyloudnorm) -> Double? {
        integrated(KWeighted(buffer, design: design))
    }

    /// Integrated loudness of audio already K-weighted, so one filtering serves every measurement.
    public static func integrated(_ k: KWeighted) -> Double? {
        guard let z = blockPowers(k, blockSeconds: 0.4, overlap: 0.75, silence: 0) else { return nil }
        let l = z.map { -0.691 + 10.0 * log10($0) }
        // pyloudnorm's comparisons, kept exactly: >= for the absolute gate, then > for both in the second pass.
        // A NaN threshold (no block passed the first gate) lets nothing through, as in numpy.
        let gammaR = -0.691 + 10.0 * log10(mean(z, where: l.map { $0 >= -70.0 })) - 10.0
        let passed = mean(z, where: l.map { $0 > gammaR && $0 > -70.0 })
        return -0.691 + 10.0 * log10(passed.isNaN ? 0 : passed)
    }

    /// Loudness range in LU per EBU Tech 3342 as pyloudnorm computes it: 1.5 s of silence appended (pyloudnorm's
    /// reading of "followed by at least 1.5 s of silence"), the loudness of 3 s blocks at pyloudnorm's overlap of 0.97
    /// (one every 90 ms), blocks below -70 LUFS dropped, then blocks below the loudness of the remaining blocks' mean
    /// power minus 20 LU dropped, and the spread between the 10th and 95th percentiles (numpy's linear interpolation)
    /// of what is left. Nil when the audio with its silence is shorter than 3 s (pyloudnorm raises an error; the lab
    /// stores no value) or when nothing passes the gates (pyloudnorm gives NaN).
    public static func range(_ buffer: AudioBuffer, design: KWeighting.Design = .pyloudnorm) -> Double? {
        range(KWeighted(buffer, design: design))
    }

    /// Loudness range of audio already K-weighted.
    public static func range(_ k: KWeighted) -> Double? {
        let silence = Int(1.5 * Double(k.sampleRate))
        guard let z = blockPowers(k, blockSeconds: 3.0, overlap: 0.97, silence: silence) else { return nil }
        let absGated = z.map { -0.691 + 10.0 * log10($0) }.filter { $0 >= -70 }
        if absGated.isEmpty { return nil }
        let power = absGated.reduce(0.0) { $0 + pow(10, $1 / 10) } / Double(absGated.count)
        let threshold = 10 * log10(power) + -20
        let relGated = absGated.filter { $0 >= threshold }
        if relGated.isEmpty { return nil }
        return Py.percentile(relGated, 95) - Py.percentile(relGated, 10)
    }

    /// The loudness of the `window` seconds ending at `seconds`, the lab's `st_lufs` (mixer/analyze.py, fade-out
    /// detection): frames from `int(max(0, t - window) * rate)` to `int(max(t, 0.1) * rate)`, cut at the end of the
    /// buffer, K-weighted on their own from rest, -0.691 + db(mean power, floor -120). A span shorter than a quarter
    /// of a second gives -120.
    public static func shortTerm(_ buffer: AudioBuffer, endingAt seconds: Double, window: Double = 3.0,
                                 design: KWeighting.Design = .pyloudnorm) -> Double {
        let rate = buffer.sampleRate
        let a = Int(max(0, seconds - window) * Double(rate)), b = Int(max(seconds, 0.1) * Double(rate))
        let lo = min(max(a, 0), buffer.frames), hi = min(max(b, lo), buffer.frames)
        if hi - lo < rate / 4 { return -120.0 }
        let ch = buffer.channelCount
        let segment = AudioBuffer(sampleRate: rate, channelCount: ch, samples: Array(buffer.samples[(lo * ch)..<(hi * ch)]))
        let k = KWeighted(segment, design: design)
        return -0.691 + LoudnessMath.db(k.powerOver(frames: 0..<k.frames))
    }

    /// The channel-summed mean K-weighted power of each gating block, laid out as pyloudnorm lays them out: block j
    /// covers frames `int(T_g * (j * step) * rate)` to `int(T_g * (j * step + 1) * rate)` (cut at the end), with
    /// step = 1 - overlap, and its energy is divided by the nominal block length `T_g * rate`. There are
    /// `round((T - T_g) / (T_g * step)) + 1` blocks for T seconds. `silence` frames of silence are appended first.
    /// Nil when the audio is shorter than one block.
    static func blockPowers(_ k: KWeighted, blockSeconds tg: Double, overlap: Double, silence: Int) -> [Double]? {
        let rate = Double(k.sampleRate)
        let n = k.frames + silence
        if Double(n) < tg * rate { return nil }
        let tail = silence > 0 ? k.silenceTail(silence) : []
        func cumulative(_ i: Int) -> Double { i <= k.frames ? k.prefixSum[i] : tail[i - k.frames] }
        let step = 1.0 - overlap
        let t = Double(n) / rate
        let count = Int(Py.roundEven((t - tg) / (tg * step)) + 1)
        let scale = 1.0 / (tg * rate)
        return (0..<max(count, 0)).map { j in
            let l = Int(tg * (Double(j) * step) * rate), u = Int(tg * (Double(j) * step + 1) * rate)
            let lo = min(l, n), hi = min(max(u, lo), n)
            return scale * (cumulative(hi) - cumulative(lo))
        }
    }

    /// numpy's mean of the values whose flag is set; NaN when none is.
    static func mean(_ values: [Double], where keep: [Bool]) -> Double {
        var sum = 0.0, count = 0
        for (v, k) in zip(values, keep) where k { sum += v; count += 1 }
        return count > 0 ? sum / Double(count) : .nan
    }
}
