import Foundation
import DeckieAudio

/// The K-weighting of ITU-R BS.1770: a high shelf (about +4 dB above 1.5 kHz, the acoustic effect of the head)
/// followed by a high pass (about 38 Hz), applied to each channel before its power is measured.
public struct KWeighting: Sendable, Equatable {
    /// Which coefficients to use.
    public enum Design: Sendable, Equatable {
        /// pyloudnorm's "K-weighting" class, which the lab measures with: the Audio EQ Cookbook high shelf
        /// (G = 4 dB, Q = 1/sqrt(2), fc = 1500 Hz) and high pass (Q = 0.5, fc = 38 Hz), computed for the signal's
        /// rate. Close to the standard but not equal to it: at 48 kHz the shelf is within 1.1e-4 of the published
        /// coefficients, and the high pass is close to the published one scaled by 0.995 (its numerator is
        /// 0.995 (1, -2, 1) where BS.1770's is 1, -2, 1), so loudness reads about 0.04 LU lower than with `.bs1770`
        /// (0.041 dB at 1 kHz). The default, so Deckie's numbers match the lab's.
        case pyloudnorm
        /// The coefficients ITU-R BS.1770-4 publishes for 48 kHz, moved to the signal's rate through the analogue
        /// filters they come from (see `KWeighting.init`), as libebur128 does.
        case bs1770
    }

    public var shelf: Biquad
    public var highPass: Biquad

    /// The two filters for a sample rate in Hz.
    public init(sampleRate: Int, design: Design = .pyloudnorm) {
        let rate = Double(sampleRate)
        switch design {
        case .pyloudnorm:
            shelf = .highShelf(gain: 4.0, q: 1 / 2.0.squareRoot(), frequency: 1500.0, sampleRate: rate)
            highPass = .highPass(q: 0.5, frequency: 38.0, sampleRate: rate)
        case .bs1770:
            // BS.1770 gives the filters only as 48 kHz coefficients. Each is the bilinear transform of an analogue
            // filter with K = tan(pi f0 / 48000):
            //   shelf:     a0 = 1 + K/Q + K^2, a1 = 2 (K^2 - 1) / a0, a2 = (1 - K/Q + K^2) / a0,
            //              b0 = (Vh + Vb K/Q + K^2) / a0, b1 = 2 (K^2 - Vh) / a0, b2 = (Vh - Vb K/Q + K^2) / a0
            //   high pass: the same a, and b = 1, -2, 1.
            // Inverting: K^2 = (1 + a1 + a2) / (1 - a1 + a2), a0 = 4 / (1 - a1 + a2), K/Q = a0 (1 - a2) / 2,
            // Vh = a0 (b0 - b1 + b2) / 4, Vb = a0 (b0 - b2) / (2 K/Q). The analogue filter does not depend on the
            // rate, so at another rate only K changes: K' = tan(atan(K) * 48000 / rate). (This gives a shelf at
            // f0 = 1681.9745 Hz, 3.99984 dB, Q = 0.70718, and a high pass at 38.1355 Hz, Q = 0.50033: the values
            // libebur128 uses, to 1e-10.)
            func analogue(_ a1: Double, _ a2: Double) -> (k: Double, kq: Double, a0: Double) {
                let a0 = 4 / (1 - a1 + a2)
                return (((1 + a1 + a2) / (1 - a1 + a2)).squareRoot(), a0 * (1 - a2) / 2, a0)
            }
            func atRate(_ k48: Double, _ q: Double) -> (k: Double, kq: Double, a0: Double) {
                let k = tan(atan(k48) * 48000 / rate)
                return (k, k / q, 1 + k / q + k * k)
            }
            let s = analogue(-1.69065929318241, 0.73248077421585)
            let vh = s.a0 * (1.53512485958697 + 2.69169618940638 + 1.19839281085285) / 4
            let vb = s.a0 * (1.53512485958697 - 1.19839281085285) / (2 * s.kq)
            let sr = atRate(s.k, s.k / s.kq)
            shelf = Biquad(b0: vh + vb * sr.kq + sr.k * sr.k, b1: 2 * (sr.k * sr.k - vh),
                           b2: vh - vb * sr.kq + sr.k * sr.k,
                           a0: sr.a0, a1: 2 * (sr.k * sr.k - 1), a2: 1 - sr.kq + sr.k * sr.k)
            let h = analogue(-1.99004745483398, 0.99007225036621)
            let hr = atRate(h.k, h.k / h.kq)
            highPass = Biquad(b0: 1, b1: -2, b2: 1, a1: 2 * (hr.k * hr.k - 1) / hr.a0,
                              a2: (1 - hr.kq + hr.k * hr.k) / hr.a0)
        }
    }

    /// Each channel of `buffer` K-weighted from rest, in double precision (the lab's `k_weight`).
    public func filtered(_ buffer: AudioBuffer) -> [[Double]] {
        (0..<buffer.channelCount).map { c in
            highPass.filter(shelf.filter(buffer.channel(c).map(Double.init)))
        }
    }
}

/// An audio buffer after K-weighting, kept as a running sum of power so that the power of any span of frames is one
/// subtraction: the lab's per-bar loudness, and the blocks the integrated loudness and loudness range are gated on.
///
/// Channels are summed with weight 1, BS.1770's weight for left, right and centre (an `AudioBuffer` holds one or two).
/// The running sum costs 8 bytes a frame: 85 MB for four minutes at 44.1 kHz.
public struct KWeighted: Sendable {
    public let sampleRate: Int
    public let channelCount: Int
    public let frames: Int
    public let weighting: KWeighting
    /// `prefixSum[i]` is the sum over frames `0..<i` of the K-weighted square summed over channels; `frames + 1`
    /// values, the first 0. Accumulated with compensated (Neumaier) summation, so a span's power keeps its precision
    /// however far into the track it starts.
    public let prefixSum: [Double]
    /// Each channel's filter memory after the last frame, to continue the K-weighted signal into silence.
    let endStates: [(shelf: Biquad.State, highPass: Biquad.State)]

    /// K-weights every channel of `buffer` from rest, in double precision.
    public init(_ buffer: AudioBuffer, design: KWeighting.Design = .pyloudnorm) {
        precondition(buffer.channelCount <= 3, "K-weighting sums channels with weight 1, so at most 3 channels")
        let w = KWeighting(sampleRate: buffer.sampleRate, design: design)
        let n = buffer.frames, ch = buffer.channelCount
        var ends: [(shelf: Biquad.State, highPass: Biquad.State)] = []
        // First the channel-summed square of each frame into slots 1...n, one channel at a time; then the running sum
        // in place. The loops use raw pointers and local copies of the coefficients because they also have to be
        // quick in a debug build, where Swift calls a function for each array access and inlines almost nothing.
        let prefix = [Double](unsafeUninitializedCapacity: n + 1) { out, count in
            let o = out.baseAddress!
            o.initialize(repeating: 0, count: n + 1)
            buffer.samples.withUnsafeBufferPointer { sb in
                for c in 0..<ch {
                    let sb0 = w.shelf.b0, sb1 = w.shelf.b1, sb2 = w.shelf.b2, sa1 = w.shelf.a1, sa2 = w.shelf.a2
                    let hb0 = w.highPass.b0, hb1 = w.highPass.b1, hb2 = w.highPass.b2
                    let ha1 = w.highPass.a1, ha2 = w.highPass.a2
                    var s1 = 0.0, s2 = 0.0, h1 = 0.0, h2 = 0.0
                    guard n > 0 else { ends.append((Biquad.State(), Biquad.State())); continue }
                    var x = sb.baseAddress! + c
                    var dst = o + 1
                    let end = o + 1 + n
                    while dst < end {
                        let v = Double(x.pointee)
                        let y = s1 + sb0 * v
                        s1 = s2 + v * sb1 - y * sa1
                        s2 = v * sb2 - y * sa2
                        let z = h1 + hb0 * y
                        h1 = h2 + y * hb1 - z * ha1
                        h2 = y * hb2 - z * ha2
                        dst.pointee += z * z
                        dst += 1
                        x += ch
                    }
                    var a = Biquad.State(), b = Biquad.State()
                    a.z1 = s1; a.z2 = s2; b.z1 = h1; b.z2 = h2
                    ends.append((a, b))
                }
            }
            var sum = 0.0, comp = 0.0
            var p = o + 1
            let end = o + 1 + n
            while p < end {
                let v = p.pointee
                let t = sum + v
                // Neumaier: keep the low-order bits each addition loses (the terms are never negative).
                if sum >= v { comp += (sum - t) + v } else { comp += (v - t) + sum }
                sum = t
                p.pointee = sum + comp
                p += 1
            }
            count = n + 1
        }
        self.sampleRate = buffer.sampleRate
        self.channelCount = ch
        self.frames = n
        self.weighting = w
        self.prefixSum = prefix
        self.endStates = ends
    }

    /// The frame at `seconds`, rounded half to even like the lab's `np.round(t * SR)`.
    public func frame(at seconds: Double) -> Int { Int(Py.roundEven(seconds * Double(sampleRate))) }

    /// The K-weighted energy (sum of squares, summed over channels) of a span of frames, clamped to the buffer like a
    /// numpy slice.
    public func energy(frames span: Range<Int>) -> Double {
        let lo = min(max(span.lowerBound, 0), frames), hi = min(max(span.upperBound, lo), frames)
        return prefixSum[hi] - prefixSum[lo]
    }

    /// The mean power over a span of frames: the lab's per-bar `ms`, the sum over channels of the mean K-weighted
    /// square (`np.sum(np.mean(kw[a:b] ** 2, axis=0))`). The span is clamped to the buffer; 0 when nothing is left.
    public func powerOver(frames span: Range<Int>) -> Double {
        let lo = min(max(span.lowerBound, 0), frames), hi = min(max(span.upperBound, lo), frames)
        return hi > lo ? (prefixSum[hi] - prefixSum[lo]) / Double(hi - lo) : 0
    }

    /// The loudness of frames `from..<to` in LUFS: -0.691 + 10 log10(mean power), with the logarithm floored at -120
    /// like the lab's `-0.691 + db(ms, -120)`, so never below -120.691.
    public func loudness(from: Int, to: Int) -> Double {
        -0.691 + LoudnessMath.db(powerOver(frames: from..<max(from, to)))
    }

    /// The running sum carried on through `count` frames of silence after the last frame, while the filters ring
    /// down: `count + 1` values, the first equal to `prefixSum[frames]`.
    func silenceTail(_ count: Int) -> [Double] {
        var tail = [Double](repeating: 0, count: count + 1)
        let w = weighting
        for (shelfState, highPassState) in endStates {
            var s = shelfState, h = highPassState
            for i in 0..<count {
                let z = w.highPass.step(w.shelf.step(0, &s), &h)
                tail[i + 1] += z * z
            }
        }
        tail[0] = prefixSum[frames]
        for i in 0..<count { tail[i + 1] += tail[i] }
        return tail
    }
}

/// Small numeric helpers shared by the loudness files.
enum LoudnessMath {
    /// The lab's `db(x, floor)`: 10 log10(x), never below `floor` (mixer/analyze.py). Like Python's
    /// `max(floor, nan)`, a NaN gives the floor.
    static func db(_ x: Double, floor: Double = -120) -> Double {
        let v = 10 * log10(max(x, 1e-30))
        return v > floor ? v : floor
    }
}
