import Foundation
import Testing
import DeckieAudio
import DeckieCore
import DeckieInference
import DeckieTestSupport

/// Whether ONNX Runtime and the YAMNet model are here; the reason is printed once when not.
enum VocalAvailable {
    static let yamnet: Bool = {
        guard Available.runtime else { return false }  // Available.library has printed why
        let missing = DeckieVocalTagger.missingModels()
        if !missing.isEmpty { print("\(missing.map(\.description).joined(separator: "; ")): the YAMNet tests are skipped") }
        return missing.isEmpty
    }()

    /// Tools/make_yamnet_fixtures.py's output (kept with DeckieCore's fixtures, beside the front end's).
    static let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("DeckieCoreTests/Fixtures/yamnet.json")
}

/// The parts of the fixture these tests read.
struct YAMNetModelFixture: Decodable {
    struct Signal: Decodable {
        var name: String
        var samples: Int
        var frames: Int
        var logMel: [Float]
        enum CodingKeys: String, CodingKey { case name, samples, frames, logMel = "log_mel" }
    }
    struct Model: Decodable {
        var sha256: String
        var signal: String
        var patches: Int
        var scores: [Float]
        var embeddings: [Float]
    }
    var signals: [Signal]
    var model: Model

    static let shared: YAMNetModelFixture = try! JSONDecoder().decode(
        YAMNetModelFixture.self, from: Data(contentsOf: VocalAvailable.fixtureURL))
}

@Suite struct YAMNetClassTests {
    /// The vocal rule takes the largest of the vocal classes' scores, and leaves speech and music out.
    @Test func vocalRuleIsTheLargestVocalClass() {
        var scores = [Float](repeating: 0, count: 2 * YAMNetPatches.classes)
        scores[YAMNetClass.singing.index] = 0.2
        scores[YAMNetClass.rapping.index] = 0.6
        scores[YAMNetClass.speech.index] = 0.9
        scores[YAMNetPatches.classes + YAMNetClass.music.index] = 0.99
        let p = YAMNetPatches(count: 2, scores: scores, embeddings: [Float](repeating: 0, count: 2 * YAMNetPatches.embeddingSize))
        #expect(YAMNet.vocalScore(p, patch: 0) == Double(Float(0.6)))
        #expect(YAMNet.vocalScore(p, patch: 1) == 0)
        #expect(!YAMNet.vocalClasses.contains(.speech) && !YAMNet.vocalClasses.contains(.music))
        #expect(Set(YAMNet.vocalClasses.map(\.index)).count == YAMNet.vocalClasses.count)
        #expect(YAMNet.vocalClasses.allSatisfy { $0.index >= 0 && $0.index < YAMNetPatches.classes })
    }

    /// The style vector is the mean embedding scaled to length 1.
    @Test func meanEmbeddingIsUnitLength() {
        var e = [Float](repeating: 0, count: 2 * YAMNetPatches.embeddingSize)
        e[0] = 6; e[YAMNetPatches.embeddingSize + 1] = 8  // the mean is (3, 4, 0, ...)
        let p = YAMNetPatches(count: 2, scores: [Float](repeating: 0, count: 2 * YAMNetPatches.classes), embeddings: e)
        let m = p.meanEmbedding()
        #expect(abs(m[0] - 0.6) < 1e-12 && abs(m[1] - 0.8) < 1e-12 && m.count == 1024)
    }
}

@Suite(.enabled(if: VocalAvailable.yamnet, "needs ONNX Runtime (core/Tools/fetch-onnxruntime.sh) and the YAMNet model (core/Tools/fetch-vocal-models.sh)"))
struct YAMNetTests {
    static let model: YAMNet? = try? YAMNet()
    func model() throws -> YAMNet { try #require(Self.model, "YAMNet did not load") }
    let fx = YAMNetModelFixture.shared

    /// The network from Swift against Python's ONNX Runtime on the same patches (the fixture's, cut from the
    /// spectrogram features.py computed): every score and embedding value within 1e-4.
    @Test func matchesPythonOnnxRuntime() throws {
        let yamnet = try model()
        let s = try #require(fx.signals.first { $0.name == fx.model.signal })
        let p = YAMNetFrontEnd.patches(s.logMel, frames: s.frames)
        #expect(p.count == fx.model.patches)
        let out = try yamnet.run(patches: p.values, count: p.count)
        let ds = zip(out.scores, fx.model.scores).map { abs($0 - $1) }.max() ?? 0
        let de = zip(out.embeddings, fx.model.embeddings).map { abs($0 - $1) }.max() ?? 0
        print("YAMNet from Swift against Python's ONNX Runtime, \(p.count) patches: largest difference in a score \(ds), "
              + "in an embedding value \(de) (largest value \(fx.model.embeddings.max() ?? 0)); fixture model \(fx.model.sha256.prefix(16))")
        #expect(ds <= 1e-4 && de <= 1e-4)
        // Batches of one give the same numbers as one batch.
        let one = try YAMNet(modelPath: yamnet.session.modelPath, batchSize: 1).run(patches: p.values, count: p.count)
        #expect(zip(one.scores, out.scores).allSatisfy { abs($0 - $1) <= 1e-5 })
    }

    /// End to end on the fixture's signal: Swift's front end and the network against features.py and Python's ONNX
    /// Runtime. The front end's 1.8e-4 moves the scores by about as much.
    @Test func endToEndMatchesThePythonPipeline() throws {
        let yamnet = try model()
        let s = try #require(fx.signals.first { $0.name == fx.model.signal })
        let y = YAMNetFixture16k.signal(samples: s.samples)
        let r = try yamnet.analyse(mono: y, sampleRate: YAMNetFrontEnd.sampleRate)
        let ds = zip(r.patches.scores, fx.model.scores).map { abs($0 - $1) }.max() ?? 0
        let de = zip(r.patches.embeddings, fx.model.embeddings).map { abs($0 - $1) }.max() ?? 0
        print("YAMNet end to end against features.py and Python's ONNX Runtime: largest difference in a score \(ds), in an embedding value \(de)")
        #expect(r.patches.count == fx.model.patches)
        #expect(ds <= 1e-3 && de <= 1e-2)
    }

    /// The vocal test track (alternate 8-bar stretches of drums and chords, and the same with the sung-like line):
    /// the vocal bars score clearly above the instrumental bars, on the vocal score and on YAMNet's singing score;
    /// and drums alone score near 0.
    @Test func vocalBarsScoreAboveInstrumentalBars() async throws { try await CPUTurns.exclusive {
        let tagger = DeckieVocalTagger(yamnet: try model())
        let rate = 44100
        let (instruments, voice) = VocalTrack.parts(rate: rate)
        let mono = zip(instruments, voice).map { Float($0 + $1) }
        let barTimes = (0...VocalTrack.bars).map { VocalTrack.firstBeat + Double($0) * VocalTrack.barS }
        let t = try tagger.tag(mono: mono, sampleRate: rate, barTimes: barTimes)
        #expect(t.perBar.count == VocalTrack.bars)
        #expect(t.patchCount == YAMNetFrontEnd.patchCount(samples: Resampler(from: rate, to: 16000).outputCount(for: mono.count)))
        let singing = try #require(t.seriesPerBar["singing"])
        func means(_ v: [Double]) -> (vocal: Double, instrumental: Double, lowestVocal: Double, highestInstrumental: Double) {
            let vb = (0..<VocalTrack.bars).filter { VocalTrack.isVocal(bar: $0) }.map { v[$0] }
            let ib = (0..<VocalTrack.bars).filter { !VocalTrack.isVocal(bar: $0) }.map { v[$0] }
            return (vb.reduce(0, +) / Double(vb.count), ib.reduce(0, +) / Double(ib.count), vb.min()!, ib.max()!)
        }
        let v = means(t.perBar), s = means(singing)
        print("""
            vocal test track, per-bar means: vocal score \(Py.fixed(v.vocal, 4)) on the vocal bars against \(Py.fixed(v.instrumental, 4)) \
            on the instrumental bars (lowest vocal bar \(Py.fixed(v.lowestVocal, 4)), highest instrumental bar \(Py.fixed(v.highestInstrumental, 4))); \
            singing score \(Py.fixed(s.vocal, 4)) against \(Py.fixed(s.instrumental, 4)); \(t.patchCount) patches; per bar \(t.perBar.map { Py.fixed($0, 3) })
            """)
        #expect(v.vocal > 5 * v.instrumental && v.vocal - v.instrumental > 0.005)
        #expect(s.vocal > 5 * s.instrumental && s.vocal - s.instrumental > 0.005)
        // Every bar of the voice's stretches above the busiest instrumental bar, but for the first bar of a stretch,
        // whose first patches straddle the change.
        let inner = (0..<VocalTrack.bars).filter { VocalTrack.isVocal(bar: $0) && $0 % VocalTrack.stretch != 0 }
        #expect(inner.allSatisfy { t.perBar[$0] > v.highestInstrumental }, "\(t.perBar)")
        // The style vector: 1,024 values, unit length.
        let style = try #require(t.style)
        #expect(style.count == 1024 && abs(style.reduce(0) { $0 + $1 * $1 } - 1) < 1e-9)

        // Drums alone: near 0.
        let beats = DrumPattern.steadyBeats(first: 0.5, bpm: 124, end: 30)
        let drums = DrumPattern.render(rate: rate, samples: 30 * rate, beats: beats, seed: 3)
        let d = try tagger.tag(mono: drums, sampleRate: rate, barTimes: stride(from: 0.5, through: 29.5, by: VocalTrack.barS).map { $0 })
        let worst = d.perBar.max() ?? 0
        print("drums alone: vocal score per bar at most \(Py.fixed(worst, 5)), mean \(Py.fixed(d.meanProbability, 5)); music \(Py.fixed(d.seriesPerBar["music"]!.reduce(0, +) / Double(d.perBar.count), 3))")
        #expect(worst < 0.01)
    } }

    /// Four minutes of stereo at 44.1 kHz through the tagger, timed step by step (the channels averaged first).
    @Test func fourMinutes() async throws { try await CPUTurns.exclusive {
        let tagger = DeckieVocalTagger(yamnet: try model())
        let rate = 44100, n = 240 * rate
        let beats = DrumPattern.steadyBeats(first: 0.5, bpm: 128, end: 239.75)
        let drums = DrumPattern.render(rate: rate, samples: n, beats: beats, seed: 13)
        let chords = ChordSynth.render(rate: rate, samples: n,
                                       chords: ChordSynth.progression(rate: rate, samples: n, chordSeconds: 1.875,
                                                                      [ChordSynth.Am, ChordSynth.F, ChordSynth.C, ChordSynth.G]),
                                       harmonics: 4, noise: 0, seed: 5, exact: false)
        var stereo = [Float](repeating: 0, count: 2 * n)
        for i in 0..<n { stereo[2 * i] = drums[i] + Float(0.2 * chords[i]); stereo[2 * i + 1] = 0.9 * drums[i] + Float(0.25 * chords[i]) }
        let audio = AudioBuffer(sampleRate: rate, channelCount: 2, samples: stereo)
        let barTimes = stride(from: 0.5, through: 239.0, by: 1.875).map { $0 }
        let t0 = Date()
        let mono = audio.mono()
        let t1 = Date()
        let t = try tagger.tag(mono: mono, sampleRate: rate, barTimes: barTimes)
        let total = Date().timeIntervalSince(t0)
        let stages = t.timing.map { "\($0.name) \(String(format: "%.2f", $0.seconds)) s" }.joined(separator: ", ")
        print("""
            vocal tagger, four minutes of stereo at 44.1 kHz: \(String(format: "%.2f", total)) s in all: mono \
            \(String(format: "%.2f", t1.timeIntervalSince(t0))) s, \(stages); \(t.patchCount) patches, \(t.perBar.count) bars
            """)
        #expect(t.patchCount == 499 && t.perBar.count == barTimes.count - 1)
    } }
}

/// The fixture's signal (YAMNetFrontEndTests builds the same in DeckieCore's tests).
enum YAMNetFixture16k {
    static func signal(samples n: Int) -> [Float] {
        let rate = YAMNetFrontEnd.sampleRate, r = Double(rate)
        let drums = DrumPattern.render(rate: rate, samples: n,
                                       beats: DrumPattern.steadyBeats(first: 0.1, bpm: 124, end: Double(n) / r), seed: 7)
        let chord = ChordSynth.render(rate: rate, samples: n, chords: [(0, n, ChordSynth.Am)], harmonics: 5,
                                      noise: 0.002, seed: 11, exact: true)
        let f0 = 262.0, depth = 0.03, vib = 5.5
        return (0..<n).map { i in
            let t = Double(i) / r
            let phi = 2.0 * Double.pi * f0 * t - (f0 * depth / vib) * cos(2.0 * Double.pi * vib * t)
            var tone = 0.0
            for h in 1...6 { tone += (0.1 / Double(h)) * sin(Double(h) * phi) }
            return Float((Double(drums[i]) + 0.25 * chord[i]) + tone)
        }
    }
}
