import Foundation
import DeckieCore

/// What the octave alignment did, the lab's `octave_fix` (`{"mode": ..., "from_bpm": ..., "parity": ...}`).
public struct OctaveFix: Sendable, Equatable {
    public enum Mode: String, Sendable {
        /// The tracker sat at double the tag tempo: every other beat was kept.
        case halved
        /// The tracker sat at half the tag tempo: a beat was added halfway between each pair.
        case doubled
    }

    public var mode: Mode
    /// The grid tempo before the fix, rounded to 3 decimals as the lab writes it (`from_bpm`).
    public var fromBpm: Double
    /// Which beats were kept when halving: 0 for the even ones counted from the first detected beat, 1 for the odd
    /// ones (`parity`); nil when doubling, where the lab writes no parity.
    public var parity: Int?

    public init(mode: Mode, fromBpm: Double, parity: Int?) {
        self.mode = mode
        self.fromBpm = fromBpm
        self.parity = parity
    }
}

/// The lab's octave alignment (mixer/analyze.py, `octave_align` and `_rms_at`), ported line for line: when the tag
/// tempo is known and the tracker's grid sits at exactly double it (within 0.08 of the ratio 2) or half it (within
/// 0.04 of 1/2), the detected pulse is brought to the tag's octave, the discs' folder convention, and the grid fitted
/// again. Without a tag tempo nothing changes. Times are seconds.
public enum OctaveAlign {
    /// The lab's `_rms_at(mono, times, win=0.05)`: for each time, the RMS of the `window` seconds of mono audio from
    /// `int(t * rate)` (Python's int, toward zero; the slice `mono[max(0, i) : i + int(win * rate)]` as Python cuts
    /// it), skipping empty slices; then the median of those values, 0 when there are none. The audio is float32 and
    /// numpy keeps the squares, their mean (pairwise sums in float32) and the square root in float32; so does this.
    /// It picks which of two alternating downbeat sets has the stronger hit.
    public static func rms(at times: [Double], in mono: [Float], sampleRate: Int, window: Double = 0.05) -> Double {
        let n = mono.count
        let w = Int(window * Double(sampleRate))
        var vals: [Double] = []
        mono.withUnsafeBufferPointer { m in
            var squares: [Float] = []
            for t in times {
                let i = Int(t * Double(sampleRate))
                let start = min(max(0, i), n)
                var stop = i + w
                if stop < 0 { stop = max(0, stop + n) }  // a negative end counts from the end, as in Python
                stop = min(stop, n)
                guard stop > start else { continue }
                squares.removeAll(keepingCapacity: true)
                for j in start..<stop { squares.append(m[j] * m[j]) }
                let mean = floatPairwiseSum(squares) / Float(stop - start)
                vals.append(Double(mean.squareRoot()))
            }
        }
        return vals.isEmpty ? 0 : Py.median(vals)
    }

    /// The octave alignment. `beats` and `downbeats` are the tracker's detections, `grid` the grid fitted to them,
    /// `bpmTag` the tag tempo (nil or 0: no change), `mono` the audio the lab measures `_rms_at` on (the channels'
    /// float32 mean at `sampleRate`). Returns the beats, downbeats and grid to use, and what was done (nil when
    /// nothing was).
    public static func align(beats: [Double], downbeats: [Double], grid: GridFit, bpmTag: Double?, mono: [Float],
                             sampleRate: Int) -> (beats: [Double], downbeats: [Double], grid: GridFit, fix: OctaveFix?) {
        guard let tag = bpmTag, tag != 0 else { return (beats, downbeats, grid, nil) }
        let r = grid.bpm / tag
        let b = beats, d = downbeats
        let P = 60.0 / grid.bpm
        if abs(r - 2.0) < 0.08 && b.count >= 8 {
            let k = b.map { Int(Py.roundEven(($0 - b[0]) / P)) }
            let kd = d.map { Int(Py.roundEven(($0 - b[0]) / P)) }
            // numpy.bincount(kd % 2).argmax(): the parity most downbeats fall on, even on a tie.
            var par = 0
            if !kd.isEmpty {
                let odd = kd.filter { Py.mod($0, 2) == 1 }.count
                par = odd > kd.count - odd ? 1 : 0
            }
            let nb = zip(b, k).filter { Py.mod($0.1, 2) == par }.map(\.0)
            var nd = d
            if d.count >= 2 {
                let gaps = (0..<(d.count - 1)).map { d[$0 + 1] - d[$0] }
                if Py.median(gaps) / (2 * P) < 3 {
                    // The downbeats were half-bars: keep the alternate set with the stronger low-end hit.
                    let c0 = stride(from: 0, to: d.count, by: 2).map { d[$0] }
                    let c1 = stride(from: 1, to: d.count, by: 2).map { d[$0] }
                    nd = rms(at: c0, in: mono, sampleRate: sampleRate) >= rms(at: c1, in: mono, sampleRate: sampleRate)
                        ? c0 : c1
                }
            }
            if let g = BeatGrid.fit(beats: nb, downbeats: nd) {
                return (nb, nd, g, OctaveFix(mode: .halved, fromBpm: Py.round(grid.bpm, 3), parity: par))
            }
        } else if abs(r - 0.5) < 0.04 && b.count >= 8 {
            let nb = (b + (0..<(b.count - 1)).map { (b[$0] + b[$0 + 1]) / 2 }).sorted()
            let nd = d.count >= 2 ? (d + (0..<(d.count - 1)).map { (d[$0] + d[$0 + 1]) / 2 }).sorted() : d
            if let g = BeatGrid.fit(beats: nb, downbeats: nd) {
                return (nb, nd, g, OctaveFix(mode: .doubled, fromBpm: Py.round(grid.bpm, 3), parity: nil))
            }
        }
        return (beats, downbeats, grid, nil)
    }

    /// numpy's pairwise sum of a contiguous float32 array, accumulated in float32: `Py.pairwiseSum`'s blocks and order
    /// with Float in place of Double.
    static func floatPairwiseSum(_ a: [Float]) -> Float {
        a.withUnsafeBufferPointer { floatPairwiseSum($0) }
    }

    static func floatPairwiseSum(_ a: UnsafeBufferPointer<Float>) -> Float {
        let n = a.count
        if n < 8 {
            var s: Float = 0
            for v in a { s += v }
            return s
        }
        if n <= 128 {
            var r0 = a[0], r1 = a[1], r2 = a[2], r3 = a[3], r4 = a[4], r5 = a[5], r6 = a[6], r7 = a[7]
            var i = 8
            while i < n - n % 8 {
                r0 += a[i]; r1 += a[i + 1]; r2 += a[i + 2]; r3 += a[i + 3]
                r4 += a[i + 4]; r5 += a[i + 5]; r6 += a[i + 6]; r7 += a[i + 7]
                i += 8
            }
            var s = ((r0 + r1) + (r2 + r3)) + ((r4 + r5) + (r6 + r7))
            while i < n { s += a[i]; i += 1 }
            return s
        }
        var half = n / 2
        half -= half % 8
        return floatPairwiseSum(UnsafeBufferPointer(rebasing: a[0..<half]))
            + floatPairwiseSum(UnsafeBufferPointer(rebasing: a[half..<n]))
    }
}
