import Foundation

/// The lab's structure novelty (mixer/analyze.py, "structure (Foote novelty)"; mixer/README.md, "Structure"): the
/// MFCC and RMS features averaged over half-beat frames from bar 1, a self-similarity matrix for each, Foote's
/// checkerboard novelty along both diagonals, their geometric mean, the peaks at least 8 frames (a bar) apart, the 20
/// strongest, each snapped to the nearest bar line if within 0.4 bar. The peaks feed `Phrase`.
///
/// Everything here is double precision. The lab's MFCC and RMS are float32 (librosa's, from float32 audio), so its
/// frame means, unit vectors and similarity matrices are float32 and only the kernel sums are float64; its novelty
/// agrees with this one to 4e-7 on the test track (SpectralTests prints the figures; given float64 features, the lab's
/// code agrees to 6e-16). That matters only where two candidate
/// peaks are within that of each other (which one `find_peaks` keeps, or which is 20th) or where a peak's left
/// neighbour is that close to it; neither happens on the test track.
public struct FooteNovelty: Sendable, Equatable {
    /// The kernel's side, in half-beat frames: 64, eight bars.
    public static let kernelSize = 64
    /// `find_peaks(distance=8)`: one bar of half-beat frames.
    public static let peakDistance = 8
    /// The strongest 20 peaks are kept.
    public static let maxPeaks = 20
    /// A peak snaps to the nearest bar line when within 0.4 bar of it.
    public static let snapTolerance = 0.4
    /// Half-beat frames per bar (4 beats).
    public static let framesPerBar = 8

    /// The lab's `hb_fr`: the STFT frame of each half-beat edge from bar 1, nBars * 8 + 1 of them.
    public var frameEdges: [Int]
    /// `foote_novelty(S_mfcc)` and `foote_novelty(S_rms)`, one value per half-beat frame, each scaled to a maximum
    /// of 1.
    public var mfccNovelty: [Double]
    public var rmsNovelty: [Double]
    /// Their geometric mean, the lab's `nov`.
    public var novelty: [Double]
    /// The lab's `pk_idx`: the peaks of `novelty` at least 8 frames apart, strongest first, at most 20.
    public var peakFrames: [Int]
    /// Those that snap to a bar line between bar 2 and bar nBars, strongest first (the order the lab sums them in).
    public var peaks: [NoveltyPeak]

    /// The whole chain from the frame-wise MFCC (13 coefficients) and RMS of `SpectralFeatures`, on the bar grid.
    public init(mfcc: FrameMatrix, rms: [Double], grid: BarGrid,
                framesPerSecond: Double = SpectralFeatures.framesPerSecond) {
        precondition(rms.count == mfcc.frames, "\(rms.count) RMS values for \(mfcc.frames) MFCC frames")
        precondition(mfcc.frames > 0 && grid.nBars > 0, "novelty needs frames and bars")
        let edges = FooteNovelty.frameEdges(grid: grid, framesPerSecond: framesPerSecond, frameCount: mfcc.frames)
        let n = edges.count - 1
        let sMfcc = FooteNovelty.mfccSimilarity(FooteNovelty.segmentMeans(mfcc, edges: edges))
        let sRms = FooteNovelty.rmsSimilarity(FooteNovelty.segmentMeans(rms, edges: edges))
        let a = FooteNovelty.novelty(similarity: sMfcc, size: n)
        let b = FooteNovelty.novelty(similarity: sRms, size: n)
        let nov = zip(a, b).map { ($0 * $1).squareRoot() }
        let picked = FooteNovelty.strongestPeaks(nov)
        frameEdges = edges
        mfccNovelty = a
        rmsNovelty = b
        novelty = nov
        peakFrames = picked
        peaks = FooteNovelty.snap(peakFrames: picked, novelty: nov, nBars: grid.nBars)
    }

    /// The half-beat frame edges: t_i = fd + i (beat / 2) for i = 0 ... nBars * 8, as STFT frames
    /// (round(t_i framesPerSecond), ties to even, as numpy rounds), clipped to the frames there are.
    public static func frameEdges(grid: BarGrid, framesPerSecond fps: Double, frameCount: Int) -> [Int] {
        let half = grid.beatS / 2
        return (0...(grid.nBars * framesPerBar)).map { i in
            let t = grid.firstDownbeatS + Double(i) * half
            return min(max(Int(Py.roundEven(t * fps)), 0), frameCount - 1)
        }
    }

    /// The mean of each feature row over each half-beat frame: frames a ..< max(a + 1, b) for consecutive edges a, b
    /// (at least one frame), added in numpy's pairwise order. Returns one column per half-beat frame, `rows` values
    /// each, frame-major like the input.
    public static func segmentMeans(_ m: FrameMatrix, edges: [Int]) -> FrameMatrix {
        let n = edges.count - 1, rows = m.rows
        var out = [Double](repeating: 0, count: max(n, 0) * rows)
        var buf: [Double] = []
        for s in 0..<max(n, 0) {
            let a = edges[s], b = max(a + 1, edges[s + 1])
            for r in 0..<rows {
                buf.removeAll(keepingCapacity: true)
                for t in a..<b { buf.append(m.values[t * rows + r]) }
                out[s * rows + r] = Py.pairwiseSum(buf) / Double(b - a)
            }
        }
        return FrameMatrix(frames: max(n, 0), rows: rows, values: out)
    }

    /// The same for one curve (the RMS).
    public static func segmentMeans(_ x: [Double], edges: [Int]) -> [Double] {
        (0..<max(edges.count - 1, 0)).map { s in
            let a = edges[s], b = max(a + 1, edges[s + 1])
            return Py.pairwiseSum(Array(x[a..<b])) / Double(b - a)
        }
    }

    /// The MFCC self-similarity: each frame's mean MFCC vector divided by its length (plus 1e-9; the squares added in
    /// coefficient order, as numpy.linalg.norm does along the first axis), then every pair's dot product (the cosine
    /// of the angle between them). Row-major n x n, symmetric.
    public static func mfccSimilarity(_ means: FrameMatrix) -> [Double] {
        let n = means.frames, k = means.rows
        var unit = means.values
        for s in 0..<n {
            var sq = 0.0
            for c in 0..<k { sq += unit[s * k + c] * unit[s * k + c] }
            let d = sq.squareRoot() + 1e-9
            for c in 0..<k { unit[s * k + c] = unit[s * k + c] / d }
        }
        var out = [Double](repeating: 0, count: n * n)
        unit.withUnsafeBufferPointer { u in
            out.withUnsafeMutableBufferPointer { o in
                var i = 0
                while i < n {
                    let ui = u.baseAddress! + i * k
                    var j = i
                    while j < n {
                        let uj = u.baseAddress! + j * k
                        var s = 0.0, c = 0
                        while c < k { s += ui[c] * uj[c]; c += 1 }
                        o[i * n + j] = s
                        o[j * n + i] = s
                        j += 1
                    }
                    i += 1
                }
            }
        }
        return out
    }

    /// The loudness self-similarity: each frame's mean RMS in decibels, 20 log10(rms + 1e-6), then minus the absolute
    /// difference for every pair, divided by the largest absolute value (plus 1e-9): 0 on the diagonal, down to -1 for
    /// the loudest and quietest frames. Row-major n x n, symmetric.
    public static func rmsSimilarity(_ means: [Double]) -> [Double] {
        let n = means.count
        let db = means.map { 20 * log10($0 + 1e-6) }
        var out = [Double](repeating: 0, count: n * n)
        var top = 0.0
        for i in 0..<n {
            for j in 0..<n {
                let v = -abs(db[i] - db[j])
                out[i * n + j] = v
                if abs(v) > top { top = abs(v) }
            }
        }
        let d = top + 1e-9
        for i in out.indices { out[i] = out[i] / d }
        return out
    }

    /// The lab's checkerboard kernel, `size` x `size` row-major (size even, h = size / 2):
    /// g_a = exp(-0.5 ((a - h + 0.5) / (h / 2))^2) for a = 0 ..< size, a Gaussian over the window with its centre
    /// between the two middle frames; kernel(a, b) = g_a g_b, negated where one of a, b is in the first half and the
    /// other in the second (the cross-similarity quadrants). Its quadrants cancel, so a uniform matrix scores 0.
    public static func kernel(size: Int = kernelSize) -> [Double] {
        precondition(size >= 2 && size % 2 == 0)
        let h = size / 2
        let g = (0..<size).map { a -> Double in
            let x = (Double(a - h) + 0.5) / (Double(h) / 2.0)
            return exp(-0.5 * (x * x))
        }
        var ker = [Double](repeating: 0, count: size * size)
        for a in 0..<size {
            for b in 0..<size {
                let v = g[a] * g[b]
                ker[a * size + b] = (a < h) != (b < h) ? -v : v
            }
        }
        return ker
    }

    /// The lab's `foote_novelty(S, K)`, line for line: S (n x n, row-major) padded by h = K / 2 on every side with
    /// its edge values (numpy's pad mode "edge": row and column indices clamped to 0 ... n - 1); for each i, the sum of
    /// kernel times the K x K block of the padded matrix starting at (i, i), which is centred on S's diagonal at i,
    /// the products added in numpy's pairwise order over the flattened block; negative values set to 0; the curve
    /// divided by its largest value when that is positive.
    public static func novelty(similarity s: [Double], size n: Int, kernelSize k: Int = kernelSize) -> [Double] {
        precondition(s.count == n * n, "\(s.count) values for a \(n) x \(n) matrix")
        if n == 0 { return [] }
        let h = k / 2, w = n + 2 * h
        let ker = kernel(size: k)
        var padded = [Double](repeating: 0, count: w * w)
        for r in 0..<w {
            let sr = min(max(r - h, 0), n - 1)
            for c in 0..<w { padded[r * w + c] = s[sr * n + min(max(c - h, 0), n - 1)] }
        }
        var nov = [Double](repeating: 0, count: n)
        let prod = UnsafeMutablePointer<Double>.allocate(capacity: k * k)
        defer { prod.deallocate() }
        ker.withUnsafeBufferPointer { kb in
            padded.withUnsafeBufferPointer { pb in
                var i = 0
                while i < n {
                    var a = 0
                    while a < k {
                        let krow = kb.baseAddress! + a * k, prow = pb.baseAddress! + (i + a) * w + i
                        let out = prod + a * k
                        var b = 0
                        while b < k { out[b] = krow[b] * prow[b]; b += 1 }
                        a += 1
                    }
                    nov[i] = Py.pairwiseSum(UnsafeBufferPointer(start: prod, count: k * k))
                    i += 1
                }
            }
        }
        for i in 0..<n where nov[i] < 0 { nov[i] = 0 }
        let top = nov.max()!
        if top > 0 { for i in 0..<n { nov[i] = nov[i] / top } }
        return nov
    }

    /// `find_peaks(nov, distance=8)`, then the peaks ordered by height, strongest first, and cut to 20 (the lab's
    /// `pk_idx[np.argsort(nov[pk_idx])[::-1][:20]]`; equal heights, which numpy's unstable sort orders as it will, are
    /// taken later frame first).
    public static func strongestPeaks(_ nov: [Double], distance: Int = peakDistance, count: Int = maxPeaks) -> [Int] {
        let pk = FindPeaks.find(nov, distance: Double(distance))
        let ascending = pk.indices.sorted { nov[pk[$0]] < nov[pk[$1]] || (nov[pk[$0]] == nov[pk[$1]] && $0 < $1) }
        return ascending.reversed().prefix(count).map { pk[$0] }
    }

    /// The snap to bar lines: frame p is p / 8 bars after bar 1; it becomes the bar line `round(p / 8)` (Python's
    /// round, ties to even, though a tie is half a bar away and fails the test anyway) when within 0.4 bar of it, and
    /// is kept when that line is strictly inside the grid (not bar 1's start, not the end line). Bars come out
    /// 1-based, so a peak at the line 0-based b starts bar b + 1; the value is the novelty at the peak. Order is kept.
    public static func snap(peakFrames: [Int], novelty nov: [Double], nBars: Int) -> [NoveltyPeak] {
        var out: [NoveltyPeak] = []
        for p in peakFrames {
            let pos = Double(p) / Double(framesPerBar)
            let bar = Int(Py.roundEven(pos))
            if abs(pos - Double(bar)) <= snapTolerance && 0 < bar && bar < nBars {
                out.append(NoveltyPeak(bar: bar + 1, value: nov[p]))
            }
        }
        return out
    }

    /// The peaks from a novelty curve already computed (for instance the lab's): `strongestPeaks`, then `snap`.
    public static func peaks(novelty nov: [Double], nBars: Int) -> [NoveltyPeak] {
        snap(peakFrames: strongestPeaks(nov), novelty: nov, nBars: nBars)
    }
}
