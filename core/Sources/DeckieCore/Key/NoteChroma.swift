import Foundation

// Row B of research R ("Overtones taken out of the chroma", Part B) and research X2: a twelve-note profile from an
// approximate note transcription, after Mauch and Dixon, "Approximate note transcription for the improved
// identification of difficult chords", ISMIR 2010. Deckie's own code from the paper; reference
// mixer/keytrial/kt_three.py (`notes_b`), which is mixer/key_overtones.py's `nnls_notes` with one dictionary and the
// core's resampler. Plain arithmetic, no model, nothing fitted:
//
//   audio      mono 44.1 kHz resampled to 11,025 Hz (`Resampler`, soxr's HQ design), ceil(n / 4) samples, with 1,536
//              zeros in front so that frame t is centred where the HPCP's frame t is
//   frames     4,096 samples (0.37 s), hop 1,024 (93 ms), as many as the HPCP has, each times a Hamming window
//              (0.54 - 0.46 cos(2 pi n / 4095), float32); X = |FFT|
//   log bins   256 bins a third of a semitone apart, bin j at MIDI 20 + j / 3 (semitone n, MIDI 21 + n, at bin
//              3 + 3 n): each DFT bin spread over frequency by a raised cosine one DFT bin wide either side, sampled
//              80 times a bin, each sample given to its two nearest log bins by a raised cosine
//   tuning     one value per song: the phase of the summed energy of the lowest 157 bins by position in the
//              semitone (j mod 3); the log spectrum is shifted by it with linear interpolation
//   whitening  per frame, from each bin the Hamming-weighted mean of the 37 bins around it is taken off, the rest
//              divided by the Hamming-weighted standard deviation of the same bins (edges use the nearest bin whose
//              37 bins all exist); negatives become zero
//   notes      84 note templates, A0 (MIDI 21) to G#7: harmonic h of note n at bin 3 + 3 n + 36 log2(h) with
//              amplitude 0.7^(h-1), 20 harmonics, each a raised cosine 1.5 bins either side, the template scaled to
//              sum 1. Per frame, the non-negative combination of the templates of the notes whose own three bins
//              hold any energy that is closest to the whitened frame in the least-squares sense
//   profile    the activations summed over the song and folded to 12 pitch classes (C = 0)
//
// The least-squares problem has one answer (the templates in play are independent), so any exact solver gives it. This
// one is Lawson and Hanson's active-set method ("Solving Least Squares Problems", 1974, ch. 23) on the normal
// equations: the templates' inner products are computed once, and each step solves a small symmetric system by
// Cholesky factorisation. No LAPACK, no dependency.

/// The note-transcription chroma (see above).
public enum NoteChroma {
    public static let sampleRate = 11025
    public static let frameSize = 4096, hop = 1024, leadingZeros = 1536
    public static let binsPerSemitone = 3, bins = 256, firstMIDI = 20
    public static let notes = 84, harmonics = 20
    public static let slope = 0.7
    /// Bins the tuning is read from: round(84 * 0.62) semitones and one bin.
    static let tuningBins = 157
    /// Half the width of the running mean and deviation, in bins.
    static let runningHalf = 18
    /// The gradient a template needs to enter the fit (10 * 256 * the spacing of doubles at 1, as scipy's solver).
    static let tolerance = 10 * 256 * Double.ulpOfOne

    static let resampler = Resampler(from: HPCPKey.sampleRate, to: sampleRate)

    /// `np.hamming(4096)` in float32.
    static let window: [Float] = (0..<frameSize).map {
        Float(0.54 - 0.46 * cos(2 * Double.pi * Double($0) / Double(frameSize - 1)))
    }

    @inline(__always) static func raisedCosine(_ d: Double) -> Double { abs(d) < 1 ? 0.5 + 0.5 * cos(Double.pi * d) : 0 }

    /// The DFT-to-log-bin map, by DFT bin: for bin k, the log bins it feeds and their weights.
    static let logMap: [[(bin: Int, weight: Double)]] = {
        let df = Double(sampleRate) / Double(frameSize)
        let fmax = 440 * pow(2, (Double(firstMIDI) + Double(bins + 1) / Double(binsPerSemitone) - 69) / 12)
        let kmax = Int((fmax / df).rounded(.up)) + 2
        let over = 80
        let count = kmax * over
        var position = [Double](repeating: -1e9, count: count)
        for i in 1..<count {
            let f = Double(i) * (df / Double(over))
            position[i] = (12 * log2(f / 440) + 69 - Double(firstMIDI)) * Double(binsPerSemitone)
        }
        var map = [[(bin: Int, weight: Double)]](repeating: [], count: frameSize / 2 + 1)
        for k in 1..<kmax {
            var column = [Double](repeating: 0, count: bins)
            let lo = max(0, (k - 1) * over), hi = min(count, (k + 1) * over + 1)
            for i in lo..<hi {
                let f = Double(i) * (df / Double(over))
                let a = raisedCosine((f - Double(k) * df) / df)
                let p = position[i]
                let base = p.rounded(.down)
                for off in 0...1 {
                    let jd = base + Double(off)
                    guard jd >= 0, jd < Double(bins) else { continue }
                    let w = raisedCosine(p - jd) * a
                    if w > 0 { column[Int(jd)] += w }
                }
            }
            map[k] = column.enumerated().compactMap { $1 != 0 ? (bin: $0, weight: $1) : nil }
        }
        return map
    }()

    /// The note templates: `dictionary[n]` is note n's 256 values.
    static let dictionary: [[Double]] = (0..<notes).map { n in
        var e = [Double](repeating: 0, count: bins)
        for h in 1...harmonics {
            let c = 3 + 3 * Double(n) + 36 * log2(Double(h))
            if c > Double(bins + 1) { break }
            let amp = pow(slope, Double(h - 1))
            for b in 0..<bins { e[b] += raisedCosine((Double(b) - c) / 1.5) * amp }
        }
        let sum = e.reduce(0, +)
        return e.map { $0 / sum }
    }
    /// Each template's bins that are not zero.
    static let dictionarySupport: [[Int]] = dictionary.map { e in e.indices.filter { e[$0] != 0 } }
    /// The templates' inner products, 84 x 84, row-major.
    static let gram: [Double] = {
        var g = [Double](repeating: 0, count: notes * notes)
        for a in 0..<notes {
            for b in a..<notes {
                var s = 0.0
                for i in dictionarySupport[a] { s += dictionary[a][i] * dictionary[b][i] }
                g[a * notes + b] = s
                g[b * notes + a] = s
            }
        }
        return g
    }()
    /// `np.hamming(37)` over its sum.
    static let runningWeights: [Double] = {
        let n = 2 * runningHalf + 1
        let w = (0..<n).map { 0.54 - 0.46 * cos(2 * Double.pi * Double($0) / Double(n - 1)) }
        let s = w.reduce(0, +)
        return w.map { $0 / s }
    }()

    /// What the transcription gives for a song.
    public struct Result: Sendable, Equatable {
        /// The activations of the 84 notes (A0 first), summed over the frames.
        public var notes: [Double]
        /// The same folded to pitch classes, C first.
        public var pcp: [Double]
        /// The tuning found, in semitones (-0.5 to 0.5).
        public var tuning: Double
        public var frames: Int
    }

    /// The transcription of mono audio at 44.1 kHz over `frames` frames (the HPCP's count for the same audio).
    public static func transcribe(_ mono: [Float], frames n: Int) -> Result {
        guard n > 0 else { return Result(notes: [Double](repeating: 0, count: notes), pcp: [Double](repeating: 0, count: 12), tuning: 0, frames: 0) }
        let y = resampler.process(mono, count: resampler.librosaCount(for: mono.count))
        // The log spectrum of every frame.
        var Y = [Double](repeating: 0, count: n * bins)
        let fft = RealFFT(size: frameSize)
        var input = [Double](repeating: 0, count: frameSize)
        var re = [Double](repeating: 0, count: fft.bins), im = [Double](repeating: 0, count: fft.bins)
        let used = logMap.indices.filter { !logMap[$0].isEmpty }
        let lastUsed = used.last ?? 0
        y.withUnsafeBufferPointer { yb in
            for t in 0..<n {
                let start = t * hop - leadingZeros
                for i in 0..<frameSize {
                    let s = start + i
                    input[i] = s >= 0 && s < yb.count ? Double(yb[s] * window[i]) : 0
                }
                input.withUnsafeBufferPointer { inp in
                    re.withUnsafeMutableBufferPointer { r in
                        im.withUnsafeMutableBufferPointer { m in
                            fft.forward(inp.baseAddress!, real: r.baseAddress!, imag: m.baseAddress!)
                        }
                    }
                }
                let row = t * bins
                var k = 1
                while k <= lastUsed {
                    let x = Double(Float((re[k] * re[k] + im[k] * im[k]).squareRoot()))
                    for (b, w) in logMap[k] { Y[row + b] += x * w }
                    k += 1
                }
            }
        }
        // One tuning for the song.
        var cs = 0.0, sn = 0.0
        for j in 0..<tuningBins {
            var e = 0.0
            for t in 0..<n { e += Y[t * bins + j] }
            let a = 2 * Double.pi * Double(j) / Double(binsPerSemitone)
            cs += e * cos(a)
            sn += e * sin(a)
        }
        let tuning = atan2(sn, cs) / (2 * Double.pi)
        let shift = tuning * Double(binsPerSemitone)
        let i0 = Int(shift.rounded(.down))
        let fs = shift - Double(i0)
        let ia = (0..<bins).map { min(max($0 + i0, 0), bins - 1) }
        let ib = (0..<bins).map { min(max($0 + i0 + 1, 0), bins - 1) }

        var total = [Double](repeating: 0, count: notes)
        var yt = [Double](repeating: 0, count: bins), ys = [Double](repeating: 0, count: bins)
        var mean = [Double](repeating: 0, count: bins), dev = [Double](repeating: 0, count: bins)
        var solver = Solver()
        let w = runningWeights, half = runningHalf
        for t in 0..<n {
            let row = t * bins
            for j in 0..<bins { yt[j] = Y[row + ia[j]] * (1 - fs) + Y[row + ib[j]] * fs }
            // Running mean and deviation over 37 bins, the edges taking the nearest full neighbourhood's.
            for c in half..<(bins - half) {
                var m1 = 0.0, m2 = 0.0
                // np.convolve(row, w, "valid")[c - half] = sum_i row[c - half + i] w[36 - i]; w is symmetric.
                for i in 0...(2 * half) {
                    let v = yt[c - half + i], wi = w[2 * half - i]
                    m1 += v * wi
                    m2 += v * v * wi
                }
                mean[c] = m1
                dev[c] = max(m2 - m1 * m1, 0).squareRoot()
            }
            for c in 0..<half { mean[c] = mean[half]; dev[c] = dev[half] }
            for c in (bins - half)..<bins { mean[c] = mean[bins - half - 1]; dev[c] = dev[bins - half - 1] }
            var any = false
            for j in 0..<bins {
                let d = yt[j] - mean[j]
                ys[j] = d > 0 && dev[j] > 0 ? d / dev[j] : 0
                if ys[j] != 0 { any = true }
            }
            guard any else { continue }
            // The notes in play: those whose own three bins hold energy.
            var inPlay: [Int] = []
            for note in 0..<notes {
                let c = 3 + 3 * note
                if ys[c - 1] + ys[c] + ys[c + 1] > 0 { inPlay.append(note) }
            }
            guard !inPlay.isEmpty else { continue }
            solver.solve(ys, inPlay: inPlay)
            for note in inPlay { total[note] += solver.x[note] }
        }
        var pcp = [Double](repeating: 0, count: 12)
        for note in 0..<notes { pcp[(note + 21) % 12] += total[note] }
        return Result(notes: total, pcp: pcp, tuning: tuning, frames: n)
    }

    /// Lawson and Hanson's non-negative least squares on the normal equations of the note templates.
    struct Solver {
        /// The answer of the last `solve`: 84 activations, zero for the notes not in play.
        var x = [Double](repeating: 0, count: NoteChroma.notes)
        private var b = [Double](repeating: 0, count: NoteChroma.notes)
        private var w = [Double](repeating: 0, count: NoteChroma.notes)
        private var passive = [Bool](repeating: false, count: NoteChroma.notes)
        private var z = [Double](repeating: 0, count: NoteChroma.notes)

        /// min |D x - y| with x >= 0 and x[n] = 0 for every note not in `inPlay`.
        mutating func solve(_ y: [Double], inPlay: [Int]) {
            let N = NoteChroma.notes, G = NoteChroma.gram
            for n in 0..<N { x[n] = 0; passive[n] = false; b[n] = 0 }
            for n in inPlay {
                var s = 0.0
                let e = NoteChroma.dictionary[n]
                for i in NoteChroma.dictionarySupport[n] { s += e[i] * y[i] }
                b[n] = s
            }
            for n in inPlay { w[n] = b[n] }
            var set: [Int] = []
            var iterations = 0
            let limit = 3 * N
            while iterations < limit {
                // The template whose entry would lower the error fastest.
                var pick = -1
                for n in inPlay where !passive[n] && w[n] > NoteChroma.tolerance && (pick < 0 || w[n] > w[pick]) { pick = n }
                if pick < 0 { break }
                passive[pick] = true
                set.append(pick)
                set.sort()
                while true {
                    iterations += 1
                    guard Self.solveSubset(G, b, set, &z) else {
                        // The subset is not independent to working precision: leave the newcomer out for good.
                        passive[pick] = false
                        set.removeAll { $0 == pick }
                        w[pick] = 0
                        break
                    }
                    var smallest = Double.infinity
                    for n in set { smallest = min(smallest, z[n]) }
                    if smallest > 0 {
                        for n in set { x[n] = z[n] }
                        break
                    }
                    // Step toward z until the first activation reaches zero, and drop what reached it.
                    var alpha = Double.infinity
                    for n in set where z[n] <= 0 { alpha = min(alpha, x[n] / (x[n] - z[n])) }
                    for n in set { x[n] += alpha * (z[n] - x[n]) }
                    let dropped = set.filter { x[$0] <= 0 || (z[$0] <= 0 && x[$0] / (x[$0] - z[$0]) == alpha) }
                    for n in dropped { x[n] = 0; passive[n] = false }
                    set.removeAll { !passive[$0] }
                    if set.isEmpty { break }
                    if iterations >= limit { break }
                }
                // The gradient with the new activations.
                for n in inPlay {
                    var s = b[n]
                    for m in set { s -= G[n * N + m] * x[m] }
                    w[n] = passive[n] ? 0 : s
                }
            }
        }

        /// Solves G[set, set] z[set] = b[set] by Cholesky factorisation; false when the matrix is not positive
        /// definite to working precision.
        private static func solveSubset(_ G: [Double], _ b: [Double], _ set: [Int], _ z: inout [Double]) -> Bool {
            let p = set.count, N = NoteChroma.notes
            var L = [Double](repeating: 0, count: p * p)
            for i in 0..<p {
                for j in 0...i {
                    var s = G[set[i] * N + set[j]]
                    for k in 0..<j { s -= L[i * p + k] * L[j * p + k] }
                    if i == j {
                        if s <= 1e-14 * G[set[i] * N + set[i]] { return false }
                        L[i * p + i] = s.squareRoot()
                    } else {
                        L[i * p + j] = s / L[j * p + j]
                    }
                }
            }
            var v = [Double](repeating: 0, count: p)
            for i in 0..<p {
                var s = b[set[i]]
                for k in 0..<i { s -= L[i * p + k] * v[k] }
                v[i] = s / L[i * p + i]
            }
            for i in stride(from: p - 1, through: 0, by: -1) {
                var s = v[i]
                for k in (i + 1)..<p { s -= L[k * p + i] * v[k] }
                v[i] = s / L[i * p + i]
            }
            for i in 0..<p { z[set[i]] = v[i] }
            return true
        }
    }
}
