import Foundation
import Testing
import DeckieCore

/// Fixtures/spectral.json, written by Tools/make_spectral_fixtures.py: librosa's mel filter bank, mel spectrogram,
/// log-mel, MFCC, RMS and onset strength exactly as mixer/analyze.py calls them; scipy's find_peaks; the lab's own
/// structure code (copied from analyze.py and checked against its text) on a synthesised track. Each signal is given
/// twice: the lab's float32 path and the same calls on float64 audio (rms in float64 too), which a double-precision
/// port should match to rounding.
struct SpectralFixture: Decodable {
    /// [kind, first sample, length, three parameters]: see `SpectralSynth`.
    struct Event: Decodable {
        var kind: String, start: Int, length: Int, p: [Double]
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            kind = try c.decode(String.self); start = try c.decode(Int.self); length = try c.decode(Int.self)
            p = []
            while !c.isAtEnd { p.append(try c.decode(Double.self)) }
        }
    }
    struct Check: Decodable { var index: [Int]; var values: [Double]; var sum: Double; var sumSq: Double }
    struct SpectralPath: Decodable {
        var frames: Int, index: [Int]
        var mel: [[Double]], logmel: [[Double]], mfcc: [[Double]]
        var melFrameSums: [Double], melBandSums: [Double], logmelFrameSums: [Double], logmelBandSums: [Double]
        var mfccFrameSums: [Double], mfccCoefSums: [Double]
        var rms: [Double], onset: [Double]
    }
    struct Signal: Decodable {
        var name: String, samples: Int, events: [Event], floor: Double, seed: UInt64, check: Check
        var paths: [String: SpectralPath]
    }
    struct Band: Decodable {
        var first: Int, weights: [Double]
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            first = try c.decode(Int.self); weights = try c.decode([Double].self)
        }
    }
    struct MelBank: Decodable { var nFft: Int, nMels: Int, melFrequencies: [Double], bands: [Band], nonzero: Int }
    struct PeakCase: Decodable {
        var name: String, x: [Double], distance: Double, peaks: [Int], maxima: [Int], tiedHeights: Bool
    }
    struct FooteMatrix: Decodable { var n: Int, seed: UInt64, novelty: [Double] }
    struct Foote: Decodable { var matrices: [FooteMatrix], gaussian: [Double] }
    struct TrackPath: Decodable {
        var frames: Int, frameEdges: [Int]
        var noveltyMfcc: [Double], noveltyRms: [Double], novelty: [Double]
        var peakFrames: [Int], peaks: [[Double]], phaseNovelty: [Double], latticePhaseBar: Int, confidence: Double
        var onsetFrames: [Int], onsetDensity: [Double], cells: [Double], keepPairs: [Int], pattern: [Double]
    }
    struct Track: Decodable {
        var events: [Event], floor: Double, seed: UInt64, check: Check, samples: Int
        var firstDownbeatS: Double, beatS: Double, nBars: Int, barLoudness: [Double]
        var paths: [String: TrackPath]
    }
    var versions: [String: String]
    var melbank: MelBank
    var signals: [Signal]
    var findpeaks: [PeakCase]
    var foote: Foote
    var track: Track

    static let shared: SpectralFixture = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try! d.decode(SpectralFixture.self,
                             from: Data(contentsOf: RepoPaths.fixtures.appendingPathComponent("spectral.json")))
    }()

    /// The track's bar grid, laid out as the lab lays it out from bar 1.
    var grid: BarGrid { BarGrid(firstDownbeatS: track.firstDownbeatS, beatS: track.beatS, nBars: track.nBars) }
}

/// The recipe of `render` in Tools/make_spectral_fixtures.py, operation for operation, so the signals are the
/// script's to the bit. With j the sample within an event of length L, e = 1 - j / L, i the absolute sample index and
/// w(f) = 2 pi f / 22050:
///   kick   [a, L, f0, f1, amp]     amp e^2 sin(w(f1) j + (w(f0) - w(f1)) (L / 3) (1 - e^3))
///   noise  [a, L, amp, p, seed]    amp env (2u - 1), env e^2 (p = 2), (e^2)^2 (p = 4) or 1 (p = 0)
///   tone   [a, L, midi, amp, h]    sum over harmonics k <= h below 11,025 Hz of (amp / k) env sin(w(f) k i), env the
///                                  10 ms ramp in and out of `ChordSynth`
/// then the floor, floor (2u - 1); u from SplitMix64.
enum SpectralSynth {
    static let rate = 22050

    static func render(samples n: Int, events: [SpectralFixture.Event], floor: Double, seed: UInt64) -> [Double] {
        var y = [Double](repeating: 0, count: n)
        let sr = Double(rate)
        let ramp = Double(Int(0.01 * sr))
        y.withUnsafeMutableBufferPointer { yb in
            let out = yb.baseAddress!
            for ev in events {
                let a = ev.start, length = ev.length, L = Double(length)
                precondition(a >= 0 && a + length <= n)
                switch ev.kind {
                case "kick":
                    let (f0, f1, amp) = (ev.p[0], ev.p[1], ev.p[2])
                    let w0 = 2.0 * Double.pi * f0 / sr, w1 = 2.0 * Double.pi * f1 / sr
                    var j = 0
                    while j < length {
                        let e = 1.0 - Double(j) / L
                        let env = e * e
                        let phase = w1 * Double(j) + (w0 - w1) * (L / 3.0) * (1.0 - e * e * e)
                        out[a + j] += amp * env * sin(phase)
                        j += 1
                    }
                case "noise":
                    let (amp, p) = (ev.p[0], Int(ev.p[1]))
                    var g = SplitMix64(UInt64(ev.p[2]))
                    var j = 0
                    while j < length {
                        let e = 1.0 - Double(j) / L
                        let env = p == 2 ? e * e : p == 4 ? (e * e) * (e * e) : 1.0
                        out[a + j] += amp * env * (2.0 * g.uniform() - 1.0)
                        j += 1
                    }
                case "tone":
                    let (m, amp, h) = (ev.p[0], ev.p[1], Int(ev.p[2]))
                    let f = 440.0 * pow(2.0, (m - 69) / 12.0)
                    for k in 1...h {
                        if f * Double(k) >= sr / 2 { break }
                        let w = 2.0 * Double.pi * f * Double(k) / sr
                        let ak = amp / Double(k)
                        var j = 0
                        while j < length {
                            let env = min(1.0, min((Double(j) + 1) / ramp, (L - Double(j)) / ramp))
                            out[a + j] += ak * env * sin(w * Double(a + j))
                            j += 1
                        }
                    }
                default:
                    fatalError("unknown event \(ev.kind)")
                }
            }
            if floor != 0 {
                var g = SplitMix64(seed)
                var i = 0
                while i < n { out[i] += floor * (2.0 * g.uniform() - 1.0); i += 1 }
            }
        }
        return y
    }

    static func render(_ s: SpectralFixture.Signal) -> [Float] {
        render(samples: s.samples, events: s.events, floor: s.floor, seed: s.seed).map { Float($0) }
    }

    /// The structure track (2,065,203 samples, 93.7 s), rendered once for the tests that need it.
    static let track: [Float] = {
        let t = SpectralFixture.shared.track
        return render(samples: t.samples, events: t.events, floor: t.floor, seed: t.seed).map { Float($0) }
    }()

    /// Its features, computed once.
    static let trackFeatures = SpectralFeatures(track)
}

/// Largest |a - b| / |b| over pairs with b != 0; a pair with b == 0 counts as infinite unless a is 0 too.
private func relErr(_ a: [Double], _ b: [Double]) -> Double {
    precondition(a.count == b.count, "\(a.count) values against \(b.count)")
    var worst = 0.0
    for (x, y) in zip(a, b) {
        if y == 0 { if x != 0 { worst = .infinity }; continue }
        worst = max(worst, abs(x - y) / abs(y))
    }
    return worst
}

/// Largest |a - b| divided by the largest |b|.
private func scaledErr(_ a: [Double], _ b: [Double]) -> Double {
    precondition(a.count == b.count, "\(a.count) values against \(b.count)")
    let scale = b.map(abs).max() ?? 0
    let d = zip(a, b).map { abs($0 - $1) }.max() ?? 0
    return scale == 0 ? (d == 0 ? 0 : .infinity) : d / scale
}

private func sci(_ x: Double) -> String { String(format: "%.1e", x) }

@Suite struct LibrosaMelTests {
    /// librosa.filters.mel(sr=22050, n_fft=2048, n_mels=64): the 66 mel frequencies and every non-zero float32 weight.
    @Test func filterBankMatchesLibrosa() {
        let fx = SpectralFixture.shared.melbank
        let bank = LibrosaMelFilterBank.lab
        #expect(bank.bands == fx.nMels && bank.bins == fx.nFft / 2 + 1)
        let freqErr = relErr(bank.melFrequencies, fx.melFrequencies)
        #expect(freqErr < 1e-15, "mel frequencies differ by \(freqErr) relative")
        var exact = 0, total = 0, worstUlps = 0
        for m in 0..<bank.bands {
            let want = fx.bands[m]
            #expect(bank.firstBin[m] == want.first && bank.weights[m].count == want.weights.count, "band \(m) run")
            for (j, w) in want.weights.enumerated() {
                let got = Float(bank.weight(band: m, bin: want.first + j)), ref = Float(w)
                total += 1
                if got == ref { exact += 1; continue }
                let ulps = abs(Int(got.bitPattern) - Int(ref.bitPattern))
                worstUlps = max(worstUlps, ulps)
                #expect(ulps <= 1, "band \(m) bin \(want.first + j): \(got), librosa \(ref)")
            }
        }
        #expect(total == fx.nonzero)
        print("mel filter bank against librosa \(SpectralFixture.shared.versions["librosa"] ?? "?"): mel frequencies "
              + "within \(sci(freqErr)) relative; \(exact) of \(total) non-zero float32 weights identical"
              + (exact < total ? ", the rest within \(worstUlps) unit(s) in the last place" : ""))
    }

    /// The Slaney scale's fixed points and its inverse; the HTK scale's formula.
    @Test func melScale() {
        #expect(LibrosaMelFilterBank.hzToMel(0) == 0)
        #expect(abs(LibrosaMelFilterBank.hzToMel(1000) - 15) < 1e-12)
        #expect(abs(LibrosaMelFilterBank.hzToMel(6400) - 42) < 1e-12)  // 15 + 27: ln(6.4) per 27 mel
        #expect(abs(LibrosaMelFilterBank.hzToMel(500) - 7.5) < 1e-12)
        for f in [0.0, 60, 440, 999, 1000, 1001, 4000, 11025] {
            #expect(abs(LibrosaMelFilterBank.melToHz(LibrosaMelFilterBank.hzToMel(f)) - f) < 1e-9 * max(f, 1))
            let m = LibrosaMelFilterBank.hzToMel(f, htk: true)
            #expect(abs(m - 2595 * log10(1 + f / 700)) < 1e-12)
            #expect(abs(LibrosaMelFilterBank.melToHz(m, htk: true) - f) < 1e-9 * max(f, 1))
        }
        let c = LibrosaMelFilterBank.melFrequencies(count: 66, fmin: 0, fmax: 11025)
        #expect(c.first == 0 && c.last == 11025)
    }

    /// power_to_db's two floors: amin (digital silence reads -100 dB) and top_db (nothing more than 80 dB below the
    /// loudest value of the whole matrix).
    @Test func powerToDbClamps() {
        let s = FrameMatrix(frames: 2, rows: 3, values: [1, 0.1, 0, 1e-12, 100, 1e-5])
        let db = LibrosaMel.powerToDb(s)
        #expect(db.values == [0, -10, -100, -120, 20, -50].map { max($0, 20 - 80) })
        let raw = LibrosaMel.powerToDb(s, topDb: nil)
        #expect(raw[0, 2] == -100 && raw[1, 0] == -100)
        let ref = LibrosaMel.powerToDb(s, ref: 100, topDb: nil)
        #expect(ref[1, 1] == 0 && ref[0, 0] == -20)
    }
}

@Suite struct SpectralParityTests {
    /// The Swift synthesis gives the script's signals to the bit: sampled values and numpy's pairwise sums agree
    /// exactly.
    @Test func synthesisMatchesScript() {
        let fx = SpectralFixture.shared
        var checks: [(String, [Float], SpectralFixture.Check)] =
            fx.signals.map { ($0.name, SpectralSynth.render($0), $0.check) }
        checks.append(("track", SpectralSynth.track, fx.track.check))
        for (name, y, c) in checks {
            for (i, v) in zip(c.index, c.values) {
                #expect(y[i] == Float(v), "\(name) sample \(i): \(y[i]), script \(v)")
            }
            let d = y.map(Double.init)
            #expect(Py.pairwiseSum(d) == c.sum, "\(name): sum \(Py.pairwiseSum(d)), script \(c.sum)")
            #expect(Py.pairwiseSum(d.map { $0 * $0 }) == c.sumSq, "\(name): sum of squares")
        }
    }

    /// The spectral block against librosa on the three test signals: every value of the sampled frames, every frame's
    /// and every band's sum, the RMS and onset-strength curves whole. Against the lab's float32 path within 1e-4
    /// relative (mel, RMS: per value; log-mel, MFCC: relative to the frame's largest magnitude; onset strength:
    /// relative to its maximum); against the float64 path to rounding.
    @Test(arguments: 0..<3) func matchesLibrosa(signal k: Int) {
        let s = SpectralFixture.shared.signals[k]
        let f = SpectralFeatures(SpectralSynth.render(s))
        var lines: [String] = []
        for (path, bound, sumBound) in [("float32", 1e-4, 1e-4), ("float64", 1e-11, 1e-8)] {
            let ref = s.paths[path]!
            #expect(f.frames == ref.frames)
            var mel = 0.0, logmel = 0.0, logmelDb = 0.0, mfcc = 0.0
            for (t, (m, (l, c))) in zip(ref.index, zip(ref.mel, zip(ref.logmel, ref.mfcc))) {
                mel = max(mel, relErr(f.mel.frame(t), m))
                logmel = max(logmel, scaledErr(f.logMel.frame(t), l))
                logmelDb = max(logmelDb, zip(f.logMel.frame(t), l).map { abs($0 - $1) }.max()!)
                mfcc = max(mfcc, scaledErr(f.mfcc.frame(t), c))
            }
            // the sums: every frame over the bands, every band over the frames (written to 9 significant digits)
            func frameSums(_ x: FrameMatrix) -> [Double] { (0..<x.frames).map { x.frame($0).reduce(0, +) } }
            func rowSums(_ x: FrameMatrix) -> [Double] { (0..<x.rows).map { x.row($0).reduce(0, +) } }
            let sums = [
                relErr(frameSums(f.mel), ref.melFrameSums), relErr(rowSums(f.mel), ref.melBandSums),
                relErr(frameSums(f.logMel), ref.logmelFrameSums), relErr(rowSums(f.logMel), ref.logmelBandSums),
                // MFCC sums can cancel to near 0: measured against the sum of magnitudes
                zip(frameSums(f.mfcc), zip(ref.mfccFrameSums, 0..<f.frames)).map { abs($0 - $1.0)
                    / f.mfcc.frame($1.1).map(abs).reduce(0, +) }.max()!,
                zip(rowSums(f.mfcc), zip(ref.mfccCoefSums, 0..<f.mfcc.rows)).map { abs($0 - $1.0)
                    / f.mfcc.row($1.1).map(abs).reduce(0, +) }.max()!,
            ]
            let rms = relErr(f.rms, ref.rms), onset = scaledErr(f.onsetEnvelope, ref.onset)
            #expect(mel <= bound && logmel <= bound && mfcc <= bound && rms <= bound && onset <= bound,
                    "\(s.name) \(path): mel \(mel), log-mel \(logmel), MFCC \(mfcc), RMS \(rms), onset \(onset)")
            #expect(sums.allSatisfy { $0 <= sumBound }, "\(s.name) \(path): sums \(sums)")
            lines.append("\(path): mel \(sci(mel)), log-mel \(sci(logmel)) (\(sci(logmelDb)) dB), MFCC \(sci(mfcc)), "
                         + "RMS \(sci(rms)), onset strength \(sci(onset)); frame and band sums \(sci(sums.max()!))")
        }
        print("spectral features of \(s.name) (\(f.frames) frames) against librosa: " + lines.joined(separator: "; "))
    }

    /// Frame layout and the silent stretch: digital silence gives exactly 0 power, RMS 0, the log-mel floor (80 dB
    /// below the loudest value) and no rise.
    @Test func silenceAndFrames() {
        let s = SpectralFixture.shared.signals[2]  // noise with a gap from 3 s to 5 s
        let f = SpectralFeatures(SpectralSynth.render(s))
        #expect(f.frames == 1 + s.samples / 512)
        let top = f.logMel.values.max()!
        for t in 135...210 {  // frames whose 2048 samples lie inside the gap
            #expect(f.mel.frame(t).allSatisfy { $0 == 0 } && f.rms[t] == 0)
            #expect(f.logMel.frame(t).allSatisfy { $0 == top - 80 })
            if t >= 138 { #expect(f.onsetEnvelope[t] == 0) }
        }
        #expect(f.onsetEnvelope[0] == 0 && f.onsetEnvelope[1] == 0 && f.onsetEnvelope[2] == 0)
    }
}

@Suite struct FindPeaksTests {
    /// scipy.signal.find_peaks on 41 curves (smooth ones, quantised ones full of plateaus, and hand-made edge cases):
    /// the local maxima always identical; with distance, identical wherever no two maxima share a height, and where
    /// some do (numpy's unstable sort then decides), a valid selection.
    @Test func matchesScipy() {
        var exact = 0, tied = 0, tiedExact = 0
        for c in SpectralFixture.shared.findpeaks {
            #expect(FindPeaks.find(c.x) == c.maxima, "\(c.name): local maxima")
            let got = FindPeaks.find(c.x, distance: c.distance)
            if !c.tiedHeights {
                #expect(got == c.peaks, "\(c.name): \(got), scipy \(c.peaks)")
                if got == c.peaks { exact += 1 }
                continue
            }
            tied += 1
            if got == c.peaks { tiedExact += 1 }
            // valid: kept peaks are maxima at least `distance` apart, and every dropped maximum is closer than that to
            // a kept one at least as high
            let d = Int(c.distance.rounded(.up))
            #expect(Set(got).isSubset(of: Set(c.maxima)))
            #expect(zip(got, got.dropFirst()).allSatisfy { $1 - $0 >= d }, "\(c.name): spacing")
            for p in c.maxima where !got.contains(p) {
                #expect(got.contains { abs($0 - p) < d && c.x[$0] >= c.x[p] }, "\(c.name): \(p) dropped")
            }
        }
        print("find_peaks against scipy \(SpectralFixture.shared.versions["scipy"] ?? "?"): \(exact) curves without "
              + "tied heights, all identical; \(tied) with tied heights, \(tiedExact) identical, the rest valid")
    }

    /// Plateaus: the middle sample (rounded down); none at either end; a plateau that rises again is no peak.
    @Test func plateaus() {
        #expect(FindPeaks.find([0, 1, 5, 5, 5, 5, 1, 0]) == [3])
        #expect(FindPeaks.find([3, 3, 3, 1, 0, 2, 0]) == [5])
        #expect(FindPeaks.find([0, 1, 0, 2, 2, 2]) == [1])
        #expect(FindPeaks.find([0, 2, 2, 3, 0]) == [3])
        #expect(FindPeaks.find([]) == [] && FindPeaks.find([1]) == [] && FindPeaks.find([0, 1]) == [])
        #expect(FindPeaks.find([0, 3, 0, 2, 0, 4, 0], distance: 3) == [1, 5])
        #expect(FindPeaks.find([0, 3, 0, 0, 2, 0, 4, 0], distance: 3) == [1, 6])
    }
}

@Suite struct FooteNoveltyTests {
    /// The kernel's Gaussian against numpy's, and foote_novelty itself (the lab's function) on SplitMix64 similarity
    /// matrices of 100, 20 (smaller than the kernel: the edge padding fills most of it), 1, 64 and 150 frames.
    @Test func matchesLab() {
        let fx = SpectralFixture.shared.foote
        let ker = FooteNovelty.kernel()
        let g = (0..<64).map { ker[$0 * 64 + $0].squareRoot() }  // the diagonal holds g_a^2
        let gErr = relErr(g, fx.gaussian)
        #expect(gErr < 1e-15)
        #expect(abs(ker.reduce(0, +)) < 1e-13)  // the quadrants cancel
        var worst = 0.0
        for c in fx.matrices {
            var r = SplitMix64(c.seed)
            let u = (0..<(c.n * c.n)).map { _ in r.uniform() }
            var s = [Double](repeating: 0, count: c.n * c.n)
            for i in 0..<c.n { for j in 0..<c.n { s[i * c.n + j] = (u[i * c.n + j] + u[j * c.n + i]) / 2.0 } }
            let nov = FooteNovelty.novelty(similarity: s, size: c.n)
            let err = zip(nov, c.novelty).map { abs($0 - $1) }.max()!
            worst = max(worst, err)
            #expect(nov.count == c.n && err < 1e-14, "n = \(c.n): \(err)")
        }
        print("Foote novelty against the lab's foote_novelty: kernel Gaussian within \(sci(gErr)) relative, novelty "
              + "within \(sci(worst)) on \(fx.matrices.count) matrices")
    }

    /// The snap: frames 8 apart per bar; within 0.4 bar of a line (3 frames) it snaps, half a bar (4) does not; bar 1's
    /// line and the end line are not kept.
    @Test func snapRule() {
        let nov = (0..<100).map { Double($0) / 100 }
        let peaks = FooteNovelty.snap(peakFrames: [16, 19, 21, 20, 3, 0, 4, 11, 88, 85, 80], novelty: nov, nBars: 11)
        #expect(peaks.map(\.bar) == [3, 3, 4, 2, 11])
        #expect(peaks[0].value == 0.16)
    }
}

@Suite struct StructureChainTests {
    /// The lab's own novelty curve (float32 path) through `strongestPeaks` and `snap`: the same frames in the same
    /// order, the same bars and values, and through `Phrase` the same lattice phase, phase sums and confidence, to the
    /// bit.
    @Test func peaksFromLabCurve() {
        let fx = SpectralFixture.shared.track
        for (path, ref) in fx.paths.sorted(by: { $0.key < $1.key }) {
            #expect(FooteNovelty.strongestPeaks(ref.novelty) == ref.peakFrames, "\(path)")
            let peaks = FooteNovelty.peaks(novelty: ref.novelty, nBars: fx.nBars)
            #expect(peaks.map(\.bar) == ref.peaks.map { Int($0[0]) } && peaks.map(\.value) == ref.peaks.map { $0[1] })
            let phrase = Phrase(peaks: peaks)
            #expect(phrase.latticePhaseBar == ref.latticePhaseBar && phrase.phaseNovelty == ref.phaseNovelty
                    && phrase.confidence == ref.confidence, "\(path): \(phrase)")
        }
    }

    /// The whole chain from audio: the synthesised 48-bar track through `SpectralFeatures` and `FooteNovelty`, against
    /// the lab's spectral and structure blocks on both paths: the frame edges exactly, the novelty curves, the same
    /// peak frames and bars, and the same lattice phase through `Phrase`.
    @Test func fullChainFromAudio() {
        let fx = SpectralFixture.shared.track
        let f = SpectralSynth.trackFeatures
        let nov = f.novelty(grid: SpectralFixture.shared.grid)
        let phrase = Phrase(peaks: nov.peaks)
        var lines: [String] = []
        for (path, ref) in fx.paths.sorted(by: { $0.key < $1.key }) {
            #expect(f.frames == ref.frames && nov.frameEdges == ref.frameEdges, "\(path)")
            let em = zip(nov.mfccNovelty, ref.noveltyMfcc).map { abs($0 - $1) }.max()!
            let er = zip(nov.rmsNovelty, ref.noveltyRms).map { abs($0 - $1) }.max()!
            let en = zip(nov.novelty, ref.novelty).map { abs($0 - $1) }.max()!
            let ev = zip(nov.peaks.map(\.value), ref.peaks.map { $0[1] }).map { abs($0 - $1) }.max() ?? 0
            #expect(nov.peakFrames == ref.peakFrames, "\(path): peak frames \(nov.peakFrames), lab \(ref.peakFrames)")
            #expect(nov.peaks.map(\.bar) == ref.peaks.map { Int($0[0]) }, "\(path): bars")
            #expect(phrase.latticePhaseBar == ref.latticePhaseBar, "\(path): phase \(phrase.latticePhaseBar)")
            let ec = abs(phrase.confidence - ref.confidence)
            let bound = path == "float64" ? 1e-12 : 1e-5
            #expect(en <= bound && em <= bound && er <= bound && ev <= bound && ec <= bound, "\(path)")
            lines.append("\(path): novelty within \(sci(en)) (MFCC \(sci(em)), RMS \(sci(er))), "
                         + "peak values \(sci(ev)), confidence \(sci(ec))")
        }
        print("structure chain on the synthesised track: \(nov.peaks.count) peaks at bars "
              + "\(nov.peaks.map(\.bar).sorted()), lattice phase bar \(phrase.latticePhaseBar), confidence "
              + "\(Py.fixed(phrase.confidence, 3)), the same peak frames and bars as the lab on both paths; "
              + lines.joined(separator: "; "))
    }

    /// Onset density and onset pattern on the same track against the lab's numpy: the same onset frames and densities,
    /// the same bar pairs kept, the cells and the 16 values within 1e-6 (float64 path: to rounding).
    @Test func onsetDensityAndPattern() {
        let fx = SpectralFixture.shared.track
        let f = SpectralSynth.trackFeatures
        let grid = SpectralFixture.shared.grid
        let frames = OnsetDetect.frames(envelope: f.onsetEnvelope)
        let density = f.onsetDensity(grid: grid)
        let cells = OnsetPattern.cellValues(onsetEnvelope: f.onsetEnvelope, grid: grid)
        let pattern = f.onsetPattern(grid: grid, barLoudness: fx.barLoudness)
        let body = Py.median(fx.barLoudness)
        let kept = (0..<(fx.nBars / 2)).filter { min(fx.barLoudness[2 * $0], fx.barLoudness[2 * $0 + 1]) > body - 10 }
        var lines: [String] = []
        for (path, ref) in fx.paths.sorted(by: { $0.key < $1.key }) {
            #expect(frames == ref.onsetFrames, "\(path): onset frames")
            #expect(density == ref.onsetDensity, "\(path): onset density")
            #expect(kept == ref.keepPairs, "\(path): bar pairs")
            let ec = scaledErr(cells, ref.cells), ep = zip(pattern, ref.pattern).map { abs($0 - $1) }.max()!
            let bound = path == "float64" ? 1e-13 : 1e-6
            #expect(ec <= bound && ep <= bound, "\(path): cells \(ec), pattern \(ep)")
            lines.append("\(path): cells within \(sci(ec)) of the largest, pattern within \(sci(ep))")
        }
        print("onsets on the synthesised track: \(frames.count) onsets, density "
              + "\(Py.fixed(Py.mean(density), 3)) a beat on average, identical per bar; "
              + "\(kept.count) of \(fx.nBars / 2) bar pairs kept; " + lines.joined(separator: "; "))
    }
}

@Suite struct OnsetTests {
    /// onset_strength's shift: three leading zeros (the lag and the centring), value t the mean rise from frame t - 3
    /// to t - 2 over the bands, falls ignored, the last two rises dropped.
    @Test func onsetStrengthByHand() {
        let s = FrameMatrix(frames: 6, rows: 2, values: [0, 0, 1, -1, 3, 0, 2, 4, 2, 2, 9, 9])
        let o = OnsetStrength.compute(logMel: s)
        #expect(o == [0, 0, 0, 0.5, 1.5, 2])
    }

    /// The greedy picker by hand, with onset_detect's parameters at 22,050 Hz and hop 512.
    @Test func peakPickByHand() {
        let p = OnsetDetect.PeakPick.onsetDefaults(sampleRate: 22050, hop: 512)
        #expect(p == OnsetDetect.PeakPick(preMax: 1, postMax: 1, preAvg: 4, postAvg: 5, wait: 1, delta: 0.07))
        // a peak needs to be >= its left neighbour and 0.07 above the mean of 4 before and 5 from it
        let x: [Double] = [0, 0, 1, 1, 0, 0, 0, 0.3, 0.2, 0, 0, 0, 0.05, 0, 0]
        #expect(OnsetDetect.peakPick(x, p) == [2, 7])  // 3 equals its neighbour but falls in the wait after 2
        #expect(OnsetDetect.frames(envelope: x.map { $0 * 3 + 1 }) == [2, 7])  // normalised first
        #expect(OnsetDetect.frames(envelope: [2, 2, 2]) == [])
        #expect(OnsetDetect.times(envelope: x) == [1024.0 / 22050, 3584.0 / 22050])
    }

    /// numpy.histogram's edges: each bar [start, end), the last [start, end].
    @Test func densityEdges() {
        let d = OnsetDensity.perBar(onsetTimes: [-0.1, 0, 0.5, 1, 1.999, 2, 3.5, 4, 4.01], barTimes: [0, 1, 2, 4])
        #expect(d == [0.5, 0.5, 0.75])
    }

    /// The pattern's bar pairs: only pairs whose quieter bar is within 10 LU of the median count; with none, all do.
    @Test func patternPairs() {
        let cells: [Double] = (0..<64).map { (i: Int) -> Double in i % 16 == 0 ? 2 : Double(i / 16 + 1) }  // 4 pairs
        let p = OnsetPattern.pattern(cellValues: cells, barLoudness: [-30, -8, -9, -8, -8, -8, -25, -8])
        // pairs 1 and 2 kept (rows of 2s and 3s, cell 0 a 2): mean 2.5, cell 0 2, scaled by 2.5 + 1e-9
        #expect(abs(p[1] - 1) < 1e-9 && abs(p[0] - 0.8) < 1e-9)
        let q = OnsetPattern.pattern(cellValues: cells, barLoudness: [0, -30, 0, -30, 0, -30, 0, -30])
        #expect(abs(q[1] - 1) < 1e-9 && abs(q[0] - 2 / 2.5) < 1e-9)  // none kept: all four rows, mean 2.5
    }
}

@Suite struct SpectralSpeedTests {
    /// Four minutes of mono at 22,050 Hz through mel, log-mel, MFCC, RMS, onset strength and the structure novelty in
    /// under 4 s of this thread's processor time, in a debug build (the processor time, not the wall clock, because the
    /// tests run side by side and the machine may be shared).
    @Test func fourMinutes() {
        let n = 240 * 22050
        var g = SplitMix64(42)
        var y = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let j = i % 11025  // a click every 0.5 s, decaying over 0.1 s, over quiet noise
            let e = j < 2205 ? 1 - Double(j) / 2205 : 0
            y[i] = Float(0.5 * e * e * (2 * g.uniform() - 1) + 0.01 * (2 * g.uniform() - 1))
        }
        let grid = BarGrid(firstDownbeatS: 0.25, beatS: 0.5, nBars: 119)
        let clock = ContinuousClock()
        let cpu0 = threadCPUSeconds()
        var f: SpectralFeatures? = nil, nov: FooteNovelty? = nil
        let spectral = seconds(clock.measure { f = SpectralFeatures(y) })
        let structure = seconds(clock.measure { nov = f!.novelty(grid: grid) })
        let cpu = threadCPUSeconds() - cpu0
        print("4 min mono at 22.05 kHz: mel, MFCC, RMS and onset strength \(Py.fixed(spectral, 3)) s "
              + "(\(f!.frames) frames), novelty \(Py.fixed(structure, 3)) s (\(nov!.novelty.count) half-beat frames, "
              + "\(nov!.peaks.count) peaks); \(Py.fixed(spectral + structure, 3)) s wall clock, "
              + "\(Py.fixed(cpu, 3)) s processor time")
        #expect(f!.frames == 1 + n / 512 && nov!.novelty.count == 119 * 8)
        #expect(cpu < 4.0)
    }

    private func threadCPUSeconds() -> Double {
        var ts = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts)
        return Double(ts.tv_sec) + Double(ts.tv_nsec) * 1e-9
    }
}
