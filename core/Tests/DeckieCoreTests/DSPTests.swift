import Foundation
import Testing
import DeckieCore

/// Fixtures/dsp.json, written by Tools/make_dsp_fixtures.py (numpy.fft, scipy's Hann window, librosa's chroma filter
/// bank and chroma, soxr through librosa.resample).
struct DSPFixture: Decodable {
    struct FFTCase: Decodable {
        var n: Int
        var seed: UInt64
        var rfftBins: [Int]
        var rfft: [[Double]]
        var imagSeed: UInt64?
        var fft: [[Double]]?
        enum CodingKeys: String, CodingKey { case n, seed, rfft, fft, rfftBins = "rfft_bins", imagSeed = "imag_seed" }
    }
    struct Hann: Decodable { var n: Int; var index: [Int]; var values: [Double] }
    struct FilterBank: Decodable { var bins: [Int]; var values: [[Double]] }
    struct Frames: Decodable { var index: [Int]; var values: [[Double]] }
    /// [first sample, end sample, [MIDI notes]]
    struct ChordSpec: Decodable {
        var start: Int, end: Int, notes: [Double]
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            start = try c.decode(Int.self); end = try c.decode(Int.self); notes = try c.decode([Double].self)
        }
        var chord: ChordSynth.Chord { (start, end, notes) }
    }
    struct Signal: Decodable {
        var name: String
        var samples: Int, harmonics: Int, noise: Double, seed: UInt64
        var chords: [ChordSpec]
        var frames: Int
        var float32: Frames, float64: Frames
    }
    struct Decimate: Decodable {
        var samples: Int, harmonics: Int, noise: Double, seed: UInt64
        var chords: [ChordSpec]
        var outSamples: Int, stretchStart: Int
        var stretch: [Double]
        var chroma: Frames
        enum CodingKeys: String, CodingKey {
            case samples, harmonics, noise, seed, chords, stretch, chroma
            case outSamples = "out_samples", stretchStart = "stretch_start"
        }
    }
    var versions: [String: String]
    var fft: [FFTCase]
    var hann: Hann
    var filterbank: FilterBank
    var chroma: [Signal]
    var decimate: Decimate

    static let shared = try! RepoPaths.fixture("dsp.json", as: DSPFixture.self)
}

/// 2u - 1 from SplitMix64(seed), the script's FFT inputs.
func noiseInput(_ seed: UInt64, _ n: Int) -> [Double] {
    var g = SplitMix64(seed)
    return (0..<n).map { _ in 2.0 * g.uniform() - 1.0 }
}

@Suite struct FFTTests {
    let fx = DSPFixture.shared

    /// The real FFT against numpy.fft.rfft, sizes 1 to 8192; the complex FFT against numpy.fft.fft up to 256.
    @Test func matchesNumpy() {
        var worstReal = 0.0, worstComplex = 0.0
        for c in fx.fft {
            let x = noiseInput(c.seed, c.n)
            let (re, im) = RealFFT(size: c.n).forward(x)
            #expect(re.count == c.n / 2 + 1)
            let scale = c.rfft.map { hypot($0[0], $0[1]) }.max()!
            var err = 0.0
            for (bin, want) in zip(c.rfftBins, c.rfft) { err = max(err, hypot(re[bin] - want[0], im[bin] - want[1])) }
            worstReal = max(worstReal, err / scale)
            #expect(err <= 1e-13 * scale, "rfft \(c.n): largest difference \(err), largest bin \(scale)")
            if let fft = c.fft, let imagSeed = c.imagSeed {
                var zr = x, zi = noiseInput(imagSeed, c.n)
                FFT(size: c.n).forward(real: &zr, imag: &zi)
                let scale = fft.map { hypot($0[0], $0[1]) }.max()!
                let err = zip(fft.indices, fft).map { hypot(zr[$0] - $1[0], zi[$0] - $1[1]) }.max()!
                worstComplex = max(worstComplex, err / scale)
                #expect(err <= 1e-13 * scale, "fft \(c.n): largest difference \(err), largest bin \(scale)")
            }
        }
        print("FFT against numpy \(fx.versions["numpy"] ?? "?"): largest difference relative to the largest bin, "
              + "real \(worstReal), complex \(worstComplex)")
    }

    /// Small cases by hand: an impulse, a constant, and a cosine on a bin.
    @Test func knownTransforms() {
        let (re1, im1) = RealFFT(size: 8).forward([1, 0, 0, 0, 0, 0, 0, 0])
        #expect(re1 == [1, 1, 1, 1, 1] && im1 == [0, 0, 0, 0, 0])
        let (re2, _) = RealFFT(size: 4).forward([2, 2, 2, 2])
        #expect(re2 == [8, 0, 0])
        let n = 64
        let x = (0..<n).map { cos(2 * Double.pi * 5 * Double($0) / Double(n)) }
        let (re3, im3) = RealFFT(size: n).forward(x)
        for k in 0...(n / 2) {
            #expect(abs(re3[k] - (k == 5 ? 32 : 0)) < 1e-12 && abs(im3[k]) < 1e-12, "bin \(k)")
        }
    }

    /// scipy.signal.get_window("hann", 8192): the same operations, so the same bits.
    @Test func hannWindowMatchesScipy() {
        let w = Window.hann(fx.hann.n)
        for (i, want) in zip(fx.hann.index, fx.hann.values) { #expect(w[i] == want, "w[\(i)] = \(w[i]), scipy \(want)") }
    }
}

@Suite struct ChromaFilterBankTests {
    /// librosa.filters.chroma(sr=22050, n_fft=8192, tuning=0.0), float32, at 14 bins from 0 Hz to Nyquist.
    @Test func matchesLibrosa() {
        let fx = DSPFixture.shared.filterbank
        let bank = ChromaFilterBank.keyEstimator
        #expect(bank.bins == 4097 && bank.weights.count == 4097 * 12)
        var exact = 0, total = 0, worstUlps = 0
        for (bin, want) in zip(fx.bins, fx.values) {
            for pc in 0..<12 {
                let got = Float(bank.weights[bin * 12 + pc]), ref = Float(want[pc])
                total += 1
                if got == ref { exact += 1; continue }
                let ulps = abs(Int(got.bitPattern) - Int(ref.bitPattern))
                worstUlps = max(worstUlps, ulps)
                #expect(ulps <= 1, "bin \(bin) class \(pc): \(got), librosa \(ref)")
            }
        }
        print("chroma filter bank against librosa \(DSPFixture.shared.versions["librosa"] ?? "?"): \(exact) of \(total) "
              + "float32 weights identical" + (exact < total ? ", the rest within \(worstUlps) unit(s) in the last place" : ""))
    }
}

@Suite struct DecimatorTests {
    /// The filter's response (now `Resampler`'s, soxr's HQ design): 1 at 0 Hz, flat to 10 kHz, -6 dB at 10,549.5 Hz,
    /// and at least 120 dB down from the new Nyquist frequency (11,025 Hz) on. (The stopgap it replaced had 65 taps,
    /// -6 dB at 11,025 Hz and 55 dB from 12.5 kHz.)
    @Test func frequencyResponse() {
        let h = Decimator.taps, centre = Decimator.center
        #expect(h.count == 389 && centre == 194)
        #expect(abs(h.reduce(0, +) - 1) < 1e-6)  // float32 taps
        func gain(_ hz: Double) -> Double {
            let w = 2 * Double.pi * hz / 44100
            var re = 0.0, im = 0.0
            for (k, v) in h.enumerated() { re += v * cos(w * Double(k - centre)); im -= v * sin(w * Double(k - centre)) }
            return 20 * log10(hypot(re, im))
        }
        let at = [100.0, 1000, 5000, 9000, 9900, 10000, 10549.5, 11025, 12100, 13000, 16000, 20000].map { ($0, gain($0)) }
        print("decimator response: " + at.map { "\($0.0) Hz \(Py.fixed($0.1, 4)) dB" }.joined(separator: ", "))
        #expect([100.0, 1000, 5000, 9000, 9900, 10000].allSatisfy { abs(gain($0)) < 1e-4 })
        #expect(abs(gain(10549.5) - 20 * log10(0.5)) < 0.01)
        #expect(stride(from: 11025.0, through: 22050, by: 25).allSatisfy { gain($0) < -120 })
    }

    /// Length and placement: (n + 1) / 2 samples, output k centred on input 2k (a slow sine passes unchanged but for
    /// float32 rounding); the samples are the 44.1 to 22.05 kHz resampler's.
    @Test func lengthAndAlignment() {
        #expect(Decimator.halve([]).isEmpty)
        #expect(Decimator.halve([1]).count == 1 && Decimator.halve([1, 2, 3]).count == 2)
        let noise = noiseInput(9, 9999).map { Float($0) }
        #expect(Decimator.halve(noise) == Resampler(from: 44100, to: 22050).process(noise))
        let x = (0..<4411).map { Float(sin(2 * Double.pi * 200 * Double($0) / 44100)) }
        let y = Decimator.halve(x)
        #expect(y.count == 2206)
        let err = (100..<2100).map { abs(Double(y[$0]) - Double(x[2 * $0])) }.max()!
        #expect(err < 1e-6, "200 Hz through the decimator: largest difference \(err)")
    }

    /// Against soxr "hq" (the lab's resampler) on a synthesised 44.1 kHz signal with harmonics up to 22 kHz: the samples
    /// and the chroma of the result. The filter is soxr's, so they agree to soxr's single-precision noise.
    @Test func againstSoxr() {
        let fx = DSPFixture.shared.decimate
        let y = ChordSynth.render(rate: 44100, samples: fx.samples, chords: fx.chords.map(\.chord),
                                  harmonics: fx.harmonics, noise: fx.noise, seed: fx.seed).map { Float($0) }
        let half = Decimator.halve(y)
        #expect(half.count == fx.outSamples)
        let ours = half[fx.stretchStart..<(fx.stretchStart + fx.stretch.count)].map(Double.init)
        let diff = zip(ours, fx.stretch).map { abs($0 - $1) }
        let rms = (zip(ours, fx.stretch).map { ($0 - $1) * ($0 - $1) }.reduce(0, +) / Double(ours.count)).squareRoot()
        let level = (fx.stretch.map { $0 * $0 }.reduce(0, +) / Double(ours.count)).squareRoot()
        let c = Chroma.stft(half)
        var chromaErr = 0.0
        for (t, want) in zip(fx.chroma.index, fx.chroma.values) {
            for pc in 0..<12 { chromaErr = max(chromaErr, abs(c[t, pc] - want[pc])) }
        }
        print("decimator against soxr hq: samples differ by at most \(String(format: "%.1e", diff.max()!)) (RMS "
              + "difference \(Py.fixed(20 * log10(rms / level), 1)) dB below the signal); chroma differs by at most "
              + "\(String(format: "%.1e", chromaErr)) over \(fx.chroma.index.count) frames")
        #expect(rms < 1e-5 * level)
        #expect(chromaErr < 1e-5)
    }
}
