import Foundation

/// Deckie's learned key reader (research X4, `docs/research/x4-key-complete.md`): a small convolutional model over a
/// log-frequency spectrogram, in plain Swift, with nothing to link and nothing to download. Its numbers
/// (`LearnedKeyWeights`) were fitted by `mixer/keytrial/kt_x4.py` only on recordings whose own licence allows a shipped
/// model (CC BY, CC0, public domain); `DEPENDENCIES.md` lists them. The Python reference is `kt_x4.py` (`reference`),
/// and Fixtures/learned_key.json holds its values on generated clips.
///
/// The steps, each the reference's:
/// 1. **Spectrogram.** Mono audio at 44,100 Hz; frames of 16,384 samples (a periodic Hann window) every 8,820 samples
///    (five a second), the audio padded by half a frame of silence at each end; the magnitude of each frame's FFT;
///    126 triangular bands, 24 to the octave from 55 Hz, each band's weights summing to 1 (a band narrower than one
///    FFT bin takes the two bins around its centre); log(1 + x).
/// 2. **Model.** Four blocks of two convolutions (12, 24, 48, 96 maps; the first 5 by 5, the rest 3 by 3) with the
///    ELU nonlinearity, halving time and frequency after each of the first three; a convolution over the whole
///    frequency axis to 48 maps; a last one to 24 key scores; the mean over time. Batch normalisation is folded into
///    the convolutions when the numbers are written, so none is computed here.
/// 3. **A long song** is read in stretches of 600 frames (two minutes) and the stretches' scores are averaged by
///    their length; a last stretch shorter than 16 frames is left out unless it is the only one.
/// 4. **Confidence.** The scores become probabilities (softmax); the minor keys' are raised by `minorLean` and the
///    whole divided by `temperature`, both fixed where the numbers were made (the lean from openly licensed
///    electronic music, the temperature on labelled recordings the model did not learn from).
/// 5. **Three answers** (D33, D36): a key when its probability is at least one half; otherwise the home note when the
///    two keys on one note together reach one half; otherwise not sure.
public enum LearnedKey {
    public static let sampleRate = 44_100
    public static let frameLength = 16_384
    public static let hop = 8_820
    public static let bands = 126
    public static let bandsPerOctave = 24
    public static let lowestHz = 55.0
    public static let stretchFrames = 600
    public static let shortestStretch = 16
    /// A key is shown when its probability reaches this; a home note when its two keys' together do.
    public static let keyThreshold = 0.5, homeThreshold = 0.5

    public struct Result: Sendable, Equatable {
        public var answer: ThreeAnswerKey.Answer
        /// The probability of each of the 24 keys (index = home note, C = 0, plus 12 if minor); empty when the audio
        /// is shorter than one frame.
        public var probabilities: [Double]
        /// The likeliest key (0 to 23), nil when there is none.
        public var best: Int?
        /// The likeliest key's probability; the confidence of a shown key.
        public var keyProbability: Double
        /// The likeliest home note (0 to 11) and the probability that it is the home note, in either mode.
        public var home: Int?
        public var homeProbability: Double
        public var frames: Int
        public init(answer: ThreeAnswerKey.Answer, probabilities: [Double], best: Int?, keyProbability: Double, home: Int?,
                    homeProbability: Double, frames: Int) {
            self.answer = answer; self.probabilities = probabilities; self.best = best; self.keyProbability = keyProbability
            self.home = home; self.homeProbability = homeProbability; self.frames = frames
        }
        /// The likeliest key as a Camelot code.
        public var camelot: String? { best.map { Camelot.code(pitchClass: $0 % 12, major: $0 < 12) } }
    }

    // MARK: Spectrogram

    struct Band { var first: Int; var weights: [Float] }

    /// The 126 bands over the 8,193 FFT bins (`kt_extract.filterbank`, rows 14 to 139 of its 148).
    static let filterBank: [Band] = {
        let n = frameLength / 2 + 1, hzPerBin = Double(sampleRate) / Double(frameLength)
        return (0..<bands).map { j in
            let lo = lowestHz * pow(2, Double(j - 1) / Double(bandsPerOctave))
            let c = lowestHz * pow(2, Double(j) / Double(bandsPerOctave))
            let hi = lowestHz * pow(2, Double(j + 1) / Double(bandsPerOctave))
            var first = max(0, Int((lo / hzPerBin).rounded(.down))), w: [Double] = []
            var k = first
            while k < n, Double(k) * hzPerBin < hi {
                let f = Double(k) * hzPerBin
                w.append(max(0, min((f - lo) / (c - lo), (hi - f) / (hi - c))))
                k += 1
            }
            var sum = w.reduce(0, +)
            if sum < 0.5 {
                let kc = c / hzPerBin, i0 = Int(kc.rounded(.down)), fr = kc - Double(i0)
                first = i0; w = [1 - fr, fr]; sum = 1
            }
            return Band(first: first, weights: w.map { Float($0 / sum) })
        }
    }()

    static let window: [Double] = (0..<frameLength).map { 0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(frameLength)) }

    public static func frameCount(samples: Int) -> Int { samples < 1 ? 0 : 1 + samples / hop }

    /// The spectrogram of mono audio at 44,100 Hz: `frames` rows of 126 values, row after row.
    public static func spectrogram(_ mono: [Float]) -> (frames: Int, values: [Float]) {
        let n = frameCount(samples: mono.count)
        var out = [Float](repeating: 0, count: n * bands)
        let fft = RealFFT(size: frameLength), half = frameLength / 2
        var frame = [Double](repeating: 0, count: frameLength)
        var re = [Double](repeating: 0, count: fft.bins), im = [Double](repeating: 0, count: fft.bins)
        var mag = [Float](repeating: 0, count: fft.bins)
        for i in 0..<n {
            let start = i * hop - half
            for s in 0..<frameLength {
                let p = start + s
                frame[s] = p >= 0 && p < mono.count ? Double(mono[p] * Float(window[s])) : 0
            }
            frame.withUnsafeBufferPointer { fb in
                re.withUnsafeMutableBufferPointer { rb in
                    im.withUnsafeMutableBufferPointer { ib in fft.forward(fb.baseAddress!, real: rb.baseAddress!, imag: ib.baseAddress!) }
                }
            }
            for k in 0..<fft.bins { mag[k] = Float((re[k] * re[k] + im[k] * im[k]).squareRoot()) }
            for (j, band) in filterBank.enumerated() {
                var acc: Float = 0
                for (d, w) in band.weights.enumerated() { acc += mag[band.first + d] * w }
                out[i * bands + j] = Float(log1p(Double(acc)))
            }
        }
        return (n, out)
    }

    // MARK: Model

    /// One convolution: `out` maps from `inp`, a kernel of `kh` frames by `kw` bands, then a bias.
    struct Layer { var out: Int; var inp: Int; var kh: Int; var kw: Int; var weights: [Float]; var bias: [Float] }

    public struct Model: Sendable {
        var inputScale: Float, inputShift: Float
        var convs: [Layer]      // eight, two a block
        var proj: Layer         // 1 frame by 15 bands, no padding
        var last: Layer         // 1 by 1
        public var minorLean: Double
        public var temperature: Double
        public var name: String

        /// The model whose numbers ship in `LearnedKeyWeights`.
        public static let shipped: Model = try! Model(base64: LearnedKeyWeights.base64, minorLean: LearnedKeyWeights.minorLean,
                                                      temperature: LearnedKeyWeights.temperature, name: LearnedKeyWeights.name)

        public struct BadWeights: Error {}

        /// The numbers as 16-bit floats, low byte first, in the order `kt_x4.py export` writes them: the input's scale
        /// and shift; for each convolution its weights (out, in, frames, bands) then its biases.
        public init(base64: String, minorLean: Double, temperature: Double, name: String) throws {
            guard let data = Data(base64Encoded: base64) else { throw BadWeights() }
            let v: [Float] = stride(from: 0, to: data.count - 1, by: 2).map { Model.half(UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8) }
            var at = 0
            func take(_ n: Int) throws -> [Float] {
                guard at + n <= v.count else { throw BadWeights() }
                defer { at += n }
                return Array(v[at..<at + n])
            }
            func layer(_ o: Int, _ i: Int, _ kh: Int, _ kw: Int) throws -> Layer {
                Layer(out: o, inp: i, kh: kh, kw: kw, weights: try take(o * i * kh * kw), bias: try take(o))
            }
            let head = try take(2)
            inputScale = head[0]; inputShift = head[1]
            convs = [try layer(12, 1, 5, 5), try layer(12, 12, 3, 3), try layer(24, 12, 3, 3), try layer(24, 24, 3, 3),
                     try layer(48, 24, 3, 3), try layer(48, 48, 3, 3), try layer(96, 48, 3, 3), try layer(96, 96, 3, 3)]
            proj = try layer(48, 96, 1, bands / 8)
            last = try layer(24, 48, 1, 1)
            guard at == v.count else { throw BadWeights() }
            self.minorLean = minorLean; self.temperature = temperature; self.name = name
        }

        /// A 16-bit float's value.
        static func half(_ h: UInt16) -> Float {
            let sign: Float = h & 0x8000 != 0 ? -1 : 1, e = Int(h >> 10) & 0x1f, m = Float(h & 0x3ff)
            if e == 0 { return sign * m * Float(pow(2.0, -24.0)) }
            if e == 31 { return m == 0 ? sign * .infinity : .nan }
            return sign * (1 + m / 1024) * Float(pow(2.0, Double(e - 15)))
        }
    }

    /// maps x frames x bands, map after map, row after row.
    struct Maps { var c: Int; var t: Int; var f: Int; var v: [Float] }

    static func conv(_ x: Maps, _ l: Layer) -> Maps {
        let t = x.t, f = x.f, ph = l.kh / 2, pw = l.kw / 2
        var out = [Float](repeating: 0, count: l.out * t * f)
        x.v.withUnsafeBufferPointer { xb in
            l.weights.withUnsafeBufferPointer { wb in
                out.withUnsafeMutableBufferPointer { ob in
                    for o in 0..<l.out {
                        let dst = ob.baseAddress! + o * t * f
                        let b = l.bias[o]
                        for i in 0..<(t * f) { dst[i] = b }
                        for i in 0..<l.inp {
                            let src = xb.baseAddress! + i * t * f
                            let w = wb.baseAddress! + (o * l.inp + i) * l.kh * l.kw
                            for dy in 0..<l.kh {
                                let y0 = max(0, ph - dy), y1 = min(t, t + ph - dy)
                                if y0 >= y1 { continue }
                                for dx in 0..<l.kw {
                                    let wv = w[dy * l.kw + dx]
                                    let x0 = max(0, pw - dx), x1 = min(f, f + pw - dx), shift = dx - pw
                                    if x0 >= x1 { continue }
                                    for y in y0..<y1 {
                                        let d = dst + y * f, s = src + (y + dy - ph) * f + shift
                                        for q in x0..<x1 { d[q] += wv * s[q] }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        elu(&out)
        return Maps(c: l.out, t: t, f: f, v: out)
    }

    static func elu(_ v: inout [Float]) {
        for i in v.indices where v[i] < 0 { v[i] = Float(expm1(Double(v[i]))) }
    }

    static func pool(_ x: Maps) -> Maps {
        let t = x.t / 2, f = x.f / 2
        var out = [Float](repeating: 0, count: x.c * t * f)
        for c in 0..<x.c {
            for y in 0..<t {
                let a = c * x.t * x.f + 2 * y * x.f, b = a + x.f, o = c * t * f + y * f
                for q in 0..<f { out[o + q] = max(max(x.v[a + 2 * q], x.v[a + 2 * q + 1]), max(x.v[b + 2 * q], x.v[b + 2 * q + 1])) }
            }
        }
        return Maps(c: x.c, t: t, f: f, v: out)
    }

    /// The 24 key scores of one stretch of spectrogram (`frames` rows of 126), before the softmax.
    static func scores(_ spec: ArraySlice<Float>, frames: Int, model m: Model) -> [Double] {
        var x = Maps(c: 1, t: frames, f: bands, v: spec.map { $0 * m.inputScale + m.inputShift })
        for b in 0..<4 {
            x = conv(conv(x, m.convs[2 * b]), m.convs[2 * b + 1])
            if b < 3 { x = pool(x) }
        }
        // Over the whole frequency axis (15 bands left), no padding: one value per map and frame.
        let t = x.t, kw = m.proj.kw
        var acc = [Double](repeating: 0, count: 24)
        var h = [Float](repeating: 0, count: m.proj.out)
        for y in 0..<t {
            for o in 0..<m.proj.out {
                var s = m.proj.bias[o]
                for i in 0..<m.proj.inp {
                    let w = (o * m.proj.inp + i) * kw, a = i * t * x.f + y * x.f
                    for q in 0..<kw { s += m.proj.weights[w + q] * x.v[a + q] }
                }
                h[o] = s < 0 ? Float(expm1(Double(s))) : s
            }
            for k in 0..<24 {
                var s = m.last.bias[k]
                for o in 0..<m.proj.out { s += m.last.weights[k * m.proj.out + o] * h[o] }
                acc[k] += Double(s)
            }
        }
        return acc.map { $0 / Double(max(1, t)) }
    }

    /// The model's 24 scores for a whole spectrogram: stretch by stretch, averaged by length.
    public static func scores(spectrogram spec: [Float], frames: Int, model: Model = .shipped) -> [Double]? {
        guard frames >= 8 else { return nil }
        var total = [Double](repeating: 0, count: 24), weight = 0.0, at = 0
        while at < frames {
            let n = min(stretchFrames, frames - at)
            if n < shortestStretch && at > 0 { break }
            let s = scores(spec[(at * bands)..<((at + n) * bands)], frames: n, model: model)
            for k in 0..<24 { total[k] += s[k] * Double(n) }
            weight += Double(n); at += n
        }
        return total.map { $0 / weight }
    }

    /// Probabilities from scores: softmax, the minor keys raised by the lean, the whole divided by the temperature.
    public static func probabilities(scores s: [Double], model: Model = .shipped) -> [Double] {
        func logSoftmax(_ v: [Double]) -> [Double] {
            let top = v.max() ?? 0, z = log(v.reduce(0) { $0 + exp($1 - top) }) + top
            return v.map { $0 - z }
        }
        var lp = logSoftmax(s)
        for k in 12..<24 { lp[k] += model.minorLean }
        return logSoftmax(lp.map { $0 / model.temperature }).map { exp($0) }
    }

    /// The three answers from the 24 probabilities.
    public static func decide(_ p: [Double]) -> (answer: ThreeAnswerKey.Answer, best: Int, home: Int, homeProbability: Double) {
        var best = 0, home = 0, hp = 0.0
        for k in 1..<24 where p[k] > p[best] { best = k }
        for h in 0..<12 where p[h] + p[h + 12] > hp { home = h; hp = p[h] + p[h + 12] }
        if p[best] >= keyThreshold { return (.key(pitchClass: best % 12, minor: best >= 12), best, best % 12, p[best % 12] + p[best % 12 + 12]) }
        if hp >= homeThreshold { return (.home(pitchClass: home), best, home, hp) }
        return (.notSure, best, home, hp)
    }

    /// The reader on mono audio at 44,100 Hz (any other rate throws `HPCPKey.EstimateError.resampleFirst`).
    public static func read(_ mono: [Float], sampleRate rate: Int, model: Model = .shipped) throws -> Result {
        guard rate == sampleRate else { throw HPCPKey.EstimateError.resampleFirst(sampleRate: rate) }
        let (n, spec) = spectrogram(mono)
        guard let s = scores(spectrogram: spec, frames: n, model: model) else {
            return Result(answer: .notSure, probabilities: [], best: nil, keyProbability: 0, home: nil, homeProbability: 0, frames: n)
        }
        let p = probabilities(scores: s, model: model), d = decide(p)
        return Result(answer: d.answer, probabilities: p, best: d.best, keyProbability: p[d.best], home: d.home,
                      homeProbability: d.homeProbability, frames: n)
    }
}
