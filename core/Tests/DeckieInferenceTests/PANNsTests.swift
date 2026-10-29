import Foundation
import Testing
import DeckieAudio
import DeckieCore
import DeckieInference
import DeckieTestSupport

/// Whether ONNX Runtime and the PANNs model are here; the reason is printed once when not.
enum PANNsAvailable {
    static let model: Bool = {
        guard Available.runtime else { return false }  // Available.library has printed why
        if PANNs.locateModel() == nil {
            print("\(PANNsError.modelNotFound(searched: PANNs.modelCandidates())): the PANNs tests are skipped")
            return false
        }
        return true
    }()

    /// Tools/make_panns_fixtures.py's output.
    static let fixtureURL = Available.fixtures.appendingPathComponent("panns.json")
}

/// The fixture: the class list's rows Deckie names, and Python's ONNX Runtime on the fixture signal's windows.
struct PANNsFixture: Decodable {
    struct Row: Decodable {
        var index: Int
        var name: String
        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            index = try c.decode(Int.self)
            name = try c.decode(String.self)
        }
    }
    struct Model: Decodable {
        var sha256: String
        var samples: Int
        var windows: Int
        var signalSum: Double
        var scores: [Float]
        var embeddings: [Float]
        enum CodingKeys: String, CodingKey { case sha256, samples, windows, scores, embeddings, signalSum = "signal_sum" }
    }
    var sourceCommit: String
    var classes: [Row]
    var model: Model?
    enum CodingKeys: String, CodingKey { case classes, model, sourceCommit = "source_commit" }

    static let shared: PANNsFixture = try! JSONDecoder().decode(
        PANNsFixture.self, from: Data(contentsOf: PANNsAvailable.fixtureURL))
}

/// The fixture's signal (make_panns_fixtures.py's `signal`), at 32 kHz: a chord, a sung-like tone with vibrato, a click
/// every half second.
enum PANNsFixtureSignal {
    static func samples(_ n: Int) -> [Float] {
        let r = Double(PANNs.sampleRate)
        let chord = [220.0, 261.6255653005986, 329.6275569128699]
        let f0 = 262.0, depth = 0.03, vib = 5.5
        return (0..<n).map { i in
            let t = Double(i) / r
            var y = 0.0
            for f in chord {
                for h in 1...4 { y += 0.08 / Double(h) * sin(2.0 * Double.pi * f * Double(h) * t) }
            }
            let phi = 2.0 * Double.pi * f0 * t - (f0 * depth / vib) * cos(2.0 * Double.pi * vib * t)
            for h in 1...8 { y += 0.12 / Double(h) * sin(Double(h) * phi) }
            if t >= 0.25 {
                let d = (t - 0.25).truncatingRemainder(dividingBy: 0.5)
                y += 0.5 * exp(-d / 0.01) * sin(2.0 * Double.pi * 1500.0 * d)
            }
            return Float(y)
        }
    }
}

@Suite struct PANNsClassTests {
    let fx = PANNsFixture.shared

    /// The classes PANNs names sit where the class list at the pinned commit has them, spelt as it spells them.
    @Test func namedClassesMatchTheClassList() {
        #expect(fx.sourceCommit == "d2f4b8c18eab44737fcc0de1248ae21eb43f6aa4")
        #expect(PANNsClass.named.map(\.index) == fx.classes.map(\.index))
        #expect(PANNsClass.named.map(\.name) == fx.classes.map(\.name))
        #expect(Set(PANNsClass.named.map(\.index)).count == PANNsClass.named.count)
        #expect(PANNsClass.named.allSatisfy { $0.index >= 0 && $0.index < PANNsPatches.classes })
    }

    /// Every class the four readings ask for is in PANNs' list (AudioSet's 527 have them all, male and female singing
    /// among them), and the readings are what their formulas give.
    @Test func readingsFindEveryClass() {
        var scores = [Float](repeating: 0, count: 2 * PANNsPatches.classes)
        scores[PANNsClass.singing.index] = 0.2
        scores[PANNsClass.femaleSinging.index] = 0.5
        scores[PANNsClass.speech.index] = 0.1
        scores[PANNsClass.music.index] = 0.8
        scores[PANNsPatches.classes + PANNsClass.music.index] = 0.9
        let p = PANNsPatches(count: 2, scores: scores, embeddings: [Float](repeating: 0, count: 2 * PANNsPatches.embeddingSize))
        let r = VocalReadings.read(p.classScores)
        #expect(r.classes.missingMax.isEmpty && r.classes.missingVoice.isEmpty && r.classes.missingMusic.isEmpty)
        #expect(r.series.map(\.name) == VocalReadings.names)
        // max11 leaves female singing out (it is not one of the eleven); the voice sum takes it, and speech.
        #expect(abs(r.max11[0] - 0.2) < 1e-7 && abs(r.voiceSum[0] - 0.8) < 1e-6)
        #expect(abs(r.voiceVsMusic[0] - 0.8 / 1.6) < 1e-6 && r.voiceVsMusic[1] == 0 && r.voiceSum[1] == 0)
        // Eleven classes at the clamp's floor and three above it.
        let floor = log(1e-7 / (1 - 1e-7))
        let want = 11 * floor + log(0.2 / 0.8) + log(0.5 / 0.5) + log(0.1 / 0.9)
        #expect(abs(r.voiceLogitSum[0] - want) < 1e-5, "\(r.voiceLogitSum[0]) against \(want)")
        // PANNs' own rule takes female singing.
        #expect(PANNs.vocalScore(p, patch: 0) == Double(Float(0.5)) && PANNs.vocalScore(p, patch: 1) == 0)
        #expect(!PANNs.vocalClasses.contains(.speech) && !PANNs.vocalClasses.contains(.music))
    }

    /// Windows of 2 s every 0.48 s at 32 kHz: one for anything up to a window, then enough for the last to reach the
    /// end.
    @Test func windowCounts() {
        #expect(PANNs.windowSeconds == 2 && PANNs.hopSeconds == 0.48 && PANNs.centreSeconds == 1)
        #expect(PANNs.patchCount(samples: 0) == 1 && PANNs.patchCount(samples: 64000) == 1)
        #expect(PANNs.patchCount(samples: 64001) == 2 && PANNs.patchCount(samples: 79360) == 2)
        #expect(PANNs.patchCount(samples: 79361) == 3 && PANNs.patchCount(samples: 96000) == 4)
        // Four minutes: the last window starts at most one hop before the end.
        let n = 240 * 32000, k = PANNs.patchCount(samples: n)
        #expect((k - 1) * PANNs.hopSamples + PANNs.windowSamples >= n && (k - 2) * PANNs.hopSamples + PANNs.windowSamples < n)
    }
}

@Suite(.enabled(if: PANNsAvailable.model, "needs ONNX Runtime (core/Tools/fetch-onnxruntime.sh) and the PANNs model (core/Tools/fetch-panns.sh)"))
struct PANNsTests {
    static let model: PANNs? = try? PANNs()
    func model() throws -> PANNs { try #require(Self.model, "PANNs did not load") }
    let fx = PANNsFixture.shared

    /// The model from Swift against Python's ONNX Runtime on the fixture signal's windows: the same windows, every
    /// score within 1e-4 and every embedding value within 1e-4 of the largest.
    @Test(.enabled(if: PANNsFixture.shared.model != nil, "the fixture has no model numbers (make_panns_fixtures.py --model)"))
    func matchesPythonOnnxRuntime() throws {
        let panns = try model()
        let ref = try #require(fx.model)
        let y = PANNsFixtureSignal.samples(ref.samples)
        let sum = y.reduce(0.0) { $0 + Double($1) }
        #expect(abs(sum - ref.signalSum) < 1e-3, "the signal differs from Python's: sum \(sum) against \(ref.signalSum)")
        #expect(PANNs.patchCount(samples: y.count) == ref.windows)
        let out = try panns.run(signal: y)
        #expect(out.count == ref.windows)
        let ds = zip(out.scores, ref.scores).map { abs($0 - $1) }.max() ?? 0
        let de = zip(out.embeddings, ref.embeddings).map { abs($0 - $1) }.max() ?? 0
        let top = ref.embeddings.map(abs).max() ?? 1
        print("PANNs from Swift against Python's ONNX Runtime, \(out.count) windows: largest difference in a score \(ds), "
              + "in an embedding value \(de) (largest value \(top)); fixture model \(ref.sha256.prefix(16))")
        #expect(ds <= 1e-4 && de <= 1e-4 * max(1, top))
        // Batches of one give the same numbers as one batch.
        let one = try PANNs(modelPath: panns.session.modelPath, batchSize: 1).run(signal: y)
        #expect(zip(one.scores, out.scores).allSatisfy { abs($0 - $1) <= 1e-5 })
    }

    /// The vocal test track (alternate 8-bar stretches of drums and chords, and the same with the sung-like line), at
    /// 44.1 kHz through the resampler: the vocal bars score above the instrumental bars on the vocal score and on the
    /// voice readings; drums alone score near 0 and as music.
    @Test func vocalBarsScoreAboveInstrumentalBars() async throws { try await CPUTurns.exclusive {
        let panns = try model()
        let rate = 44100
        let (instruments, voice) = VocalTrack.parts(rate: rate)
        let mono = zip(instruments, voice).map { Float($0 + $1) }
        let barTimes = (0...VocalTrack.bars).map { VocalTrack.firstBeat + Double($0) * VocalTrack.barS }
        let p = try panns.vocalPatches(mono: mono, sampleRate: rate)
        #expect(p.vocal.count == PANNs.patchCount(samples: Resampler(from: rate, to: 32000).outputCount(for: mono.count)))
        func bars(_ v: [Double]) -> [Double] {
            PatchBars.average(v, hop: p.hopSeconds, centreOffset: p.centreSeconds, barTimes: barTimes)
        }
        func means(perBar b: [Double]) -> (vocal: Double, instrumental: Double, lowestVocal: Double, highestInstrumental: Double) {
            let vb = (0..<VocalTrack.bars).filter { VocalTrack.isVocal(bar: $0) }.map { b[$0] }
            let ib = (0..<VocalTrack.bars).filter { !VocalTrack.isVocal(bar: $0) }.map { b[$0] }
            return (vb.reduce(0, +) / Double(vb.count), ib.reduce(0, +) / Double(ib.count), vb.min()!, ib.max()!)
        }
        func means(_ v: [Double]) -> (vocal: Double, instrumental: Double, lowestVocal: Double, highestInstrumental: Double) {
            means(perBar: bars(v))
        }
        let v = means(p.vocal)
        let readings = try #require(p.readings(barTimes: barTimes))
        #expect(readings.classes.missingMax.isEmpty && readings.classes.missingVoice.isEmpty && readings.classes.missingMusic.isEmpty)
        let r = Dictionary(uniqueKeysWithValues: readings.series.map { ($0.name, means(perBar: $0.values)) })
        var lines = ["vocal score: \(Py.fixed(v.vocal, 4)) on the vocal bars against \(Py.fixed(v.instrumental, 4)) on the instrumental bars (lowest vocal bar \(Py.fixed(v.lowestVocal, 4)), highest instrumental bar \(Py.fixed(v.highestInstrumental, 4)))"]
        for name in VocalReadings.names {
            let s = try #require(r[name], "\(name)")
            lines.append("\(name): \(Py.fixed(s.vocal, 4)) against \(Py.fixed(s.instrumental, 4))")
        }
        for name in ["singing", "speech", "music"] {
            let s = means(try #require(p.series[name], "\(name)"))
            lines.append("\(name): \(Py.fixed(s.vocal, 4)) against \(Py.fixed(s.instrumental, 4))")
        }
        print("PANNs on the vocal test track, per-bar means (\(p.vocal.count) windows):\n  " + lines.joined(separator: "\n  ")
              + "\n  vocal score per bar \(bars(p.vocal).map { Py.fixed($0, 3) })")
        #expect(v.vocal > 2 * v.instrumental && v.vocal - v.instrumental > 0.02)
        let voiceSum = r["voice_sum"]!, share = r["voice_vs_music"]!, logits = r["voice_logit_sum"]!, max11 = r["max11"]!
        #expect(voiceSum.vocal > voiceSum.instrumental && share.vocal > share.instrumental)
        #expect(logits.vocal > logits.instrumental && max11.vocal > max11.instrumental)
        // The style vector: 1,024 values, unit length.
        let style = try #require(p.style)
        #expect(style.count == 1024 && abs(style.reduce(0) { $0 + $1 * $1 } - 1) < 1e-9)

        // Drums alone.
        let beats = DrumPattern.steadyBeats(first: 0.5, bpm: 124, end: 30)
        let drums = DrumPattern.render(rate: rate, samples: 30 * rate, beats: beats, seed: 3)
        let d = try panns.vocalPatches(mono: drums, sampleRate: rate)
        let worst = d.vocal.max() ?? 0, music = d.series["music"]!.reduce(0, +) / Double(d.vocal.count)
        print("PANNs, drums alone: vocal score at most \(Py.fixed(worst, 5)); music \(Py.fixed(music, 3))")
        #expect(worst < 0.05)
    } }

    /// Four minutes of stereo at 44.1 kHz, timed step by step (the channels averaged first).
    @Test func fourMinutes() async throws { try await CPUTurns.exclusive {
        let panns = try model()
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
        let t0 = Date()
        let p = try panns.vocalPatches(mono: audio.mono(), sampleRate: rate)
        let total = Date().timeIntervalSince(t0)
        let stages = p.timing.map { "\($0.name) \(String(format: "%.2f", $0.seconds)) s" }.joined(separator: ", ")
        print("PANNs, four minutes of stereo at 44.1 kHz: \(String(format: "%.2f", total)) s in all: \(stages); \(p.vocal.count) windows")
        #expect(p.vocal.count == PANNs.patchCount(samples: 240 * 32000) && p.vocal.count == 497)
    } }
}
