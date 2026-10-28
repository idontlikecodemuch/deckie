import Foundation
import Testing
import DeckieCore
import DeckieTestSupport

// The beat tracker's pure Swift pieces against the Beat This! package itself (Fixtures/beat_this.json, written by
// Tools/make_beat_fixtures.py). None of these need ONNX Runtime or the model; they run on every platform.

@Suite struct BeatThisFrontEndTests {
    let fx = BeatThisFixture.shared

    /// The 128 mel filters against torchaudio's `melscale_fbanks` (float32): the same bins, and the same float32
    /// weights but for the 42 that touch one mel point, at 8,909.8 Hz, which torch's vectorised expf (Sleef) puts one
    /// float32 step from the C library's expf (glibc on Linux); those move by up to 4e-6.
    @Test func melFilterBankMatchesTorchaudio() {
        let bank = BeatThisFrontEnd().filterBank
        #expect(bank.melCount == fx.filterbank.count)
        var worst = 0.0, identical = 0, total = 0
        for (m, f) in fx.filterbank.enumerated() {
            #expect(bank.firstBin[m] == f.first, "mel \(m): first bin \(bank.firstBin[m]), torchaudio's \(f.first)")
            #expect(bank.weights[m].count == f.weights.count, "mel \(m): \(bank.weights[m].count) bins, torchaudio's \(f.weights.count)")
            for (a, b) in zip(bank.weights[m], f.weights.map(Double.init)) {
                worst = max(worst, abs(a - b))
                total += 1
                if a == b { identical += 1 }
            }
        }
        print("mel filter bank: \(identical) of \(total) weights identical to torchaudio's, largest difference \(worst)")
        #expect(worst <= 1e-5)
        #if os(Linux)
        // With glibc's expf only that one point differs; other C libraries may round other points differently.
        #expect(identical >= total - 3 * 16, "more than the three filters around one mel point differ")
        #endif
    }

    /// Reflect padding: the STFT of a signal with `.reflect` equals the zero-padded STFT of the signal mirrored by
    /// hand (numpy.pad(..., mode="reflect")) where the frames line up (hop 256, so 512 samples is two frames). At 300
    /// samples the 512-sample mirror folds more than once, which torch refuses and numpy does.
    @Test func reflectPaddingMirrorsAboutTheEnds() {
        var g = SplitMix64Generator(99)
        for n in [300, 600, 1000, 1500] {
            let y = (0..<n).map { _ in 2 * g.uniform() - 1 }
            let period = 2 * (n - 1)
            func mirrored(_ i: Int) -> Double {
                var k = i % period
                if k < 0 { k += period }
                return y[k < n ? k : period - k]
            }
            let z = (-512..<(n + 512)).map(mirrored)
            let a = STFT(fftSize: 1024, hop: 256, padding: .reflect).powerSpectrogram(y)
            let b = STFT(fftSize: 1024, hop: 256, padding: .zeros).powerSpectrogram(z)
            for t in a.indices {
                let worst = zip(a[t], b[t + 2]).map { abs($0 - $1) / max(1, abs($1)) }.max()!
                #expect(worst <= 1e-12, "n \(n), frame \(t): \(worst)")
            }
        }
    }

    /// The log-mel spectrogram of synthesised drums against the package's `LogMelSpect` (float32 torch): whole frames
    /// at the start, middle and end, and every frame's sum, within 1e-4 relative (values under 0.01, nearly silent
    /// bands, count absolutely). Against the package's steps run in float64 the frames agree to 1e-5, the mark of
    /// the one mel point above; the rest of the difference from float32 is the package's own float32 rounding.
    @Test func spectrogramMatchesThePackage() {
        let frontEnd = BeatThisFrontEnd()
        var worstAbs = 0.0, worstRel = 0.0, worstSum = 0.0, worst64 = 0.0, compared = 0
        for s in fx.frontend {
            let y = DrumPattern.render(rate: BeatThisFrontEnd.sampleRate, samples: s.samples, beats: s.beats, seed: s.seed)
            #expect(BeatThisFixture.matches(y, s.synth), "\(s.name): the synthesised signal is not the fixture's")
            let spect = frontEnd.spectrogram(y)
            #expect(spect.frames == s.frames, "\(s.name): \(spect.frames) frames, the package's \(s.frames)")
            guard spect.frames == s.frames else { continue }
            for ((t, want), want64) in zip(zip(s.index, s.values), s.values64) {
                for b in 0..<BeatThisSpectrogram.bands {
                    let got = Double(spect[t, b]), w = Double(want[b])
                    let d = abs(got - w)
                    worstAbs = max(worstAbs, d)
                    // Relative to the value; values below 0.01 (bands nearly silent in that frame) count absolutely.
                    worstRel = max(worstRel, d / max(abs(w), 0.01))
                    worst64 = max(worst64, abs(got - want64[b]) / max(abs(want64[b]), 0.01))
                    compared += 1
                }
            }
            for t in 0..<spect.frames {
                let sum = spect.frame(t).reduce(0.0) { $0 + Double($1) }
                worstSum = max(worstSum, abs(sum - s.frameSums[t]) / max(abs(s.frameSums[t]), 1))
            }
        }
        print("Beat This! front end against the package: \(compared) values, largest difference \(worstAbs) (relative \(worstRel)); frame sums within \(worstSum) relative; against the package's steps in float64 within \(worst64) relative")
        #expect(worstRel <= 1e-4)
        #expect(worstSum <= 1e-4)
        #expect(worst64 <= 1e-5)
    }
}

@Suite struct BeatThisChunkingTests {
    let fx = BeatThisFixture.shared

    /// Chunk starts and padding against the package's `split_piece`, for lengths around every boundary.
    @Test func splitMatchesThePackage() {
        for c in fx.chunking {
            let chunks = BeatThisChunking.split(frames: c.frames)
            #expect(chunks.map(\.start) == c.starts, "\(c.frames) frames")
            #expect(chunks.map { [$0.leftPad, $0.rightPad, $0.length] } == c.pads, "\(c.frames) frames")
        }
    }

    /// Assembly against `split_predict_aggregate` with a stand-in model whose logits say which chunk and row each
    /// frame came from (beat = 2048 x frame + row): every frame from the same chunk as in the package.
    @Test func aggregateMatchesThePackage() {
        let bands = BeatThisSpectrogram.bands
        for c in fx.chunking {
            var values = [Float](repeating: 0, count: c.frames * bands)
            for i in 0..<c.frames { values[i * bands] = Float(i) }
            let logits = BeatThisChunking.run(BeatThisSpectrogram(frames: c.frames, values: values)) { input, rows in
                BeatThisLogits(beat: (0..<rows).map { input[$0 * bands] * 2048 + Float($0) },
                               downbeat: (0..<rows).map { input[$0 * bands] * 2048 - Float($0) })
            }
            #expect(logits.frames == c.frames)
            var wrong = 0
            for seg in c.segments {
                for i in seg[0]..<seg[1] where logits.beat[i] != Float(2049 * i - seg[2]) || logits.downbeat[i] != Float(2047 * i + seg[2]) {
                    wrong += 1
                }
            }
            #expect(wrong == 0, "\(c.frames) frames: \(wrong) frames assembled differently from the package")
        }
    }
}

@Suite struct BeatThisPostProcessorTests {
    let fx = BeatThisFixture.shared

    func check(_ name: String, _ beat: [Float], _ downbeat: [Float], beatFrames: [Double], downbeatFrames: [Double],
               beats: [Double], downbeats: [Double]) {
        let got = BeatThisPostProcessor.minimal(BeatThisLogits(beat: beat, downbeat: downbeat))
        #expect(got.beatFrames == beatFrames, "\(name): beat frames")
        #expect(got.downbeatFrames == downbeatFrames, "\(name): downbeat frames")
        #expect(got.beats == beats, "\(name): beat times")
        #expect(got.downbeats == downbeats, "\(name): downbeat times")
    }

    /// Ties, plateaus, edges, peaks three frames apart, downbeats between beats, nothing above zero, and random
    /// logits: identical frames and times to the package's minimal postprocessor.
    @Test func handMadeLogitsMatchThePackage() {
        for c in fx.postprocessor {
            check(c.name, c.beat, c.downbeat, beatFrames: c.beatFrames, downbeatFrames: c.downbeatFrames, beats: c.beats,
                  downbeats: c.downbeats)
        }
    }

    /// The package's own logits for the synthesised pieces (30 s and 90 s): identical beats and downbeats.
    @Test func modelLogitsMatchThePackage() {
        var beats = 0, downbeats = 0
        for p in fx.pieces {
            check(p.name, p.beatLogits, p.downbeatLogits, beatFrames: p.beatFrames, downbeatFrames: p.downbeatFrames,
                  beats: p.beats, downbeats: p.downbeats)
            beats += p.beats.count
            downbeats += p.downbeats.count
        }
        print("postprocessor on the package's logits: \(beats) beats and \(downbeats) downbeats in \(fx.pieces.count) pieces, compared exactly")
    }
}
