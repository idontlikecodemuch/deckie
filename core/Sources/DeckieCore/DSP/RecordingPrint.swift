import Foundation

/// A print of a song's audio, made to answer one question: are two files the same recording? (D24: two crate entries
/// are the same song only when they are the same recording; a remix, an edit or a live version is its own song.)
///
/// The print is the one published by Haitsma and Kalker, "A Highly Robust Audio Fingerprinting System" (ISMIR 2002),
/// with the paper's own numbers: the audio as mono at a low rate, frames of 0.37 s every 1/32 of a frame (11.6 ms),
/// each frame's spectrum cut into 33 bands spaced evenly in pitch (logarithmically) from 300 to 2000 Hz, and one
/// 32-bit word per frame whose bit m is 1 when the energy difference between bands m and m + 1 grew since the frame
/// before: E(n, m) - E(n, m + 1) - (E(n - 1, m) - E(n - 1, m + 1)) > 0. The paper compares blocks of 256 words (about
/// 3 s) and calls two blocks the same audio when fewer than 35 % of their bits differ (the bit error rate, BER); for
/// unrelated audio about half the bits differ, and the paper puts the chance of a false match at that threshold at
/// 3.6e-20 per block. Lossy encoding, level changes, resampling and equalisation leave the BER of the same recording
/// well under that (the paper's table: mostly under 0.2).
///
/// Its rate is 5 kHz rather than the paper's 5.5 kHz (the band stops at 2 kHz, so both keep everything it needs, and 5 kHz
/// is a small ratio from 44.1 and 48 kHz for the resampler); a frame is 1850 samples (0.37 s), Hann-windowed and padded
/// to a 2048-point transform; the hop is 58 samples (1850 / 32, rounded).
///
/// The rule for the same recording (`sameRecording`) asks more than the paper's search, which wanted any 3 s of a song:
/// the whole song has to match, so that an edit, an extended mix or a remix that shares some of its audio is not taken
/// for a copy. Two prints are the same recording when both of these hold:
///
/// 1. **Their sound lasts as long, within 1 s.** The sound is from the first to the last frame above -60 dBFS (the usual
///    digital-silence line), so the silence a rip or an encoder adds at either end does not count; an encoder's own
///    delay and padding are under 0.1 s. Any edit of the music adds or removes at least a bar, and a bar is 1.2 s even
///    at 200 BPM, so 1 s lets every copy through and no edit.
/// 2. **Every block matches.** The two are lined up by the start of their sound, then the best offset within 1 s either
///    way is found on the first two blocks; from there, every block of 256 frames along the whole sound (the last
///    block takes the remainder) must have a BER under the paper's 0.35, counting only frames where at least one of the
///    two has sound. A section that differs anywhere (a remix's new drums, a live take drifting off the record's
///    tempo) fails its block.
///
/// None of these numbers is fitted to any library: 0.37 s, 1/32, 33 bands, 300 to 2000 Hz, 256 frames and 0.35 are the
/// paper's; -60 dBFS is the common silence line; 1 s follows from the shortest edit, as above.
public struct RecordingPrint: Sendable, Equatable {
    public static let sampleRate = 5000
    public static let frameLength = 1850
    public static let fftSize = 2048
    public static let hop = 58
    public static let bandCount = 33
    public static let lowHz = 300.0
    public static let highHz = 2000.0
    public static let blockFrames = 256
    public static let berThreshold = 0.35
    public static let silenceDB = -60.0
    public static let lengthToleranceS = 1.0
    public static let maxShiftS = 1.0

    /// Seconds from one frame to the next.
    public static var frameStepS: Double { Double(hop) / Double(sampleRate) }

    /// One word per frame (the first frame has none, as it has no frame before it, so word i is frame i + 1).
    public let words: [UInt32]
    /// Whether each word's frame has sound (its level above -60 dBFS).
    public let sounding: [Bool]

    public init(words: [UInt32], sounding: [Bool]) {
        precondition(words.count == sounding.count)
        self.words = words; self.sounding = sounding
    }

    /// The print of interleaved samples (any channel count, any rate); the channels are averaged to mono first.
    public init(interleaved samples: [Float], channels: Int, sampleRate rate: Int) {
        let ch = max(1, channels)
        var mono: [Float]
        if ch == 1 { mono = samples } else {
            let n = samples.count / ch
            mono = [Float](repeating: 0, count: n)
            let g = 1 / Float(ch)
            samples.withUnsafeBufferPointer { s in
                for i in 0..<n {
                    var sum: Float = 0
                    for c in 0..<ch { sum += s[i * ch + c] }
                    mono[i] = sum * g
                }
            }
        }
        self.init(mono: mono, sampleRate: rate)
    }

    /// The print of mono samples at any rate.
    public init(mono: [Float], sampleRate rate: Int) {
        let x = rate == Self.sampleRate ? mono : Resampler.resample(mono, from: rate, to: Self.sampleRate)
        let L = Self.frameLength, N = Self.fftSize, H = Self.hop
        let frames = x.count >= L ? (x.count - L) / H + 1 : 0
        guard frames >= 2 else { self.init(words: [], sounding: []); return }

        let fft = RealFFT(size: N)
        let window = (0..<L).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(L)) }
        // Band edges in transform bins: 34 edges spaced evenly in pitch from 300 to 2000 Hz.
        let binHz = Double(Self.sampleRate) / Double(N)
        let edges = (0...Self.bandCount).map { i -> Int in
            let f = Self.lowHz * pow(Self.highHz / Self.lowHz, Double(i) / Double(Self.bandCount))
            return Int((f / binHz).rounded())
        }
        let silence = pow(10, Self.silenceDB / 10)   // mean square at -60 dBFS

        var words: [UInt32] = []; words.reserveCapacity(frames - 1)
        var sounding: [Bool] = []; sounding.reserveCapacity(frames - 1)
        var prev = [Double](repeating: 0, count: Self.bandCount)
        var cur = [Double](repeating: 0, count: Self.bandCount)
        var buf = [Double](repeating: 0, count: N)
        var re = [Double](repeating: 0, count: fft.bins), im = [Double](repeating: 0, count: fft.bins)
        x.withUnsafeBufferPointer { xs in
            for n in 0..<frames {
                let start = n * H
                var ms = 0.0
                for i in 0..<L {
                    let v = Double(xs[start + i])
                    ms += v * v
                    buf[i] = v * window[i]
                }
                ms /= Double(L)
                buf.withUnsafeBufferPointer { b in
                    re.withUnsafeMutableBufferPointer { r in
                        im.withUnsafeMutableBufferPointer { m in fft.forward(b.baseAddress!, real: r.baseAddress!, imag: m.baseAddress!) }
                    }
                }
                for m in 0..<Self.bandCount {
                    var e = 0.0
                    for k in edges[m]..<max(edges[m] + 1, edges[m + 1]) { e += re[k] * re[k] + im[k] * im[k] }
                    cur[m] = e
                }
                if n > 0 {
                    var w: UInt32 = 0
                    for m in 0..<(Self.bandCount - 1) {
                        if cur[m] - cur[m + 1] - (prev[m] - prev[m + 1]) > 0 { w |= 1 << UInt32(m) }
                    }
                    words.append(w)
                    sounding.append(ms > silence)
                }
                swap(&prev, &cur)
            }
        }
        self.init(words: words, sounding: sounding)
    }

    /// The first and last frames with sound, or nil when there is none.
    public var soundSpan: ClosedRange<Int>? {
        guard let a = sounding.firstIndex(of: true), let b = sounding.lastIndex(of: true) else { return nil }
        return a...b
    }

    /// How two prints compare, for the rule and for reports.
    public struct Comparison: Sendable, Equatable {
        /// The difference between the lengths of their sound, in seconds.
        public var lengthDifferenceS: Double
        /// Frames from `a`'s frame to `b`'s matching frame, as lined up (nil when there was nothing to line up).
        public var shift: Int?
        /// Each block's bit error rate along the whole sound, in order (empty when the lengths already differ).
        public var blockBER: [Double]
        public var worstBER: Double? { blockBER.max() }
        /// The rule: lengths within 1 s, and every block under 0.35.
        public var sameRecording: Bool {
            lengthDifferenceS <= RecordingPrint.lengthToleranceS && !blockBER.isEmpty
                && blockBER.allSatisfy { $0 < RecordingPrint.berThreshold }
        }
    }

    /// Whether the two prints are of the same recording (see the type's notes for the rule and its numbers).
    public static func sameRecording(_ a: RecordingPrint, _ b: RecordingPrint) -> Bool { compare(a, b).sameRecording }

    public static func compare(_ a: RecordingPrint, _ b: RecordingPrint) -> Comparison {
        guard let sa = a.soundSpan, let sb = b.soundSpan else {
            return Comparison(lengthDifferenceS: .infinity, shift: nil, blockBER: [])
        }
        let lengthDiff = abs(Double(sa.count - sb.count)) * frameStepS
        guard lengthDiff <= lengthToleranceS else { return Comparison(lengthDifferenceS: lengthDiff, shift: nil, blockBER: []) }

        // Line up by the start of the sound, then find the best offset within 1 s on the first two blocks.
        let base = sb.lowerBound - sa.lowerBound
        let reach = Int((maxShiftS / frameStepS).rounded())
        let probe = sa.lowerBound..<min(sa.upperBound + 1, sa.lowerBound + 2 * blockFrames)
        var best = (shift: base, ber: Double.infinity)
        for s in (base - reach)...(base + reach) {
            if let r = ber(a, b, frames: probe, shift: s), r < best.ber { best = (s, r) }
        }

        // Every block along a's sound, the last one taking the remainder.
        let n = sa.count
        let count = max(1, n / blockFrames)
        var blocks: [Double] = []
        for i in 0..<count {
            let lo = sa.lowerBound + i * blockFrames
            let hi = i == count - 1 ? sa.upperBound + 1 : lo + blockFrames
            // A block with no frame to compare (silent in both, or past b's end) counts as all bits different.
            blocks.append(ber(a, b, frames: lo..<hi, shift: best.shift) ?? 1)
        }
        return Comparison(lengthDifferenceS: lengthDiff, shift: best.shift, blockBER: blocks)
    }

    /// The bit error rate of a's frames `frames` against b's frames `shift` later, over the frames inside both prints
    /// where either has sound; nil when there is no such frame.
    static func ber(_ a: RecordingPrint, _ b: RecordingPrint, frames: Range<Int>, shift: Int) -> Double? {
        var diff = 0, compared = 0
        for i in frames {
            let j = i + shift
            guard i >= 0, i < a.words.count, j >= 0, j < b.words.count else { continue }
            guard a.sounding[i] || b.sounding[j] else { continue }
            diff += (a.words[i] ^ b.words[j]).nonzeroBitCount
            compared += 1
        }
        return compared == 0 ? nil : Double(diff) / Double(32 * compared)
    }
}
