import Foundation
import Testing
import DeckieCore
import DeckieTestSupport

/// Fixtures/yamnet.json, from Tools/make_yamnet_fixtures.py: TensorFlow's mel matrix with YAMNet's settings, and the
/// log-mel spectrogram YAMNet's own feature code (features.py) computes for two synthesised signals.
struct YAMNetFixture: Decodable {
    struct Signal: Decodable {
        var name: String
        var samples: Int
        var sampleSum: Double
        var firstSamples: [Double]
        var padded: Int
        var frames: Int
        var patches: Int
        var logMel: [Double]
        enum CodingKeys: String, CodingKey {
            case name, samples, padded, frames, patches
            case sampleSum = "sample_sum", firstSamples = "first_samples", logMel = "log_mel"
        }
    }
    var versions: [String: String]
    var mel: [[Double]]
    var signals: [Signal]

    static let shared: YAMNetFixture = try! RepoPaths.fixture("yamnet.json", as: YAMNetFixture.self)

    /// The fixture script's signal, operation for operation: drums at 124 BPM from 0.1 s (`DrumPattern`), an A minor
    /// chord (`ChordSynth`, exact sines) at a quarter level, and a harmonic tone at 262 Hz with a 3 % vibrato at
    /// 5.5 Hz whose phase is in closed form; float32 at 16 kHz.
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

@Suite struct YAMNetFrontEndTests {
    let fx = YAMNetFixture.shared

    /// Patch counts and padding as features.py's pad_waveform gives them.
    @Test func patchCounting() {
        #expect(YAMNetFrontEnd.patchCount(samples: 0) == 1)
        #expect(YAMNetFrontEnd.patchCount(samples: 15600) == 1)
        #expect(YAMNetFrontEnd.patchCount(samples: 15601) == 2)
        #expect(YAMNetFrontEnd.patchCount(samples: 15600 + 7680) == 2)
        #expect(YAMNetFrontEnd.patchCount(samples: 15600 + 7681) == 3)
        #expect(YAMNetFrontEnd.paddedCount(samples: 32000) == 38640)
        #expect(YAMNetFrontEnd.frameCount(samples: 32000) == 240)
        #expect(YAMNetFrontEnd.patchCentre(0) == 0.4875 && abs(YAMNetFrontEnd.patchCentre(10) - 5.2875) < 1e-12)
        for s in fx.signals {
            #expect(YAMNetFrontEnd.patchCount(samples: s.samples) == s.patches, "\(s.name)")
            #expect(YAMNetFrontEnd.paddedCount(samples: s.samples) == s.padded, "\(s.name)")
            #expect(YAMNetFrontEnd.frameCount(samples: s.samples) == s.frames, "\(s.name)")
        }
    }

    /// The mel filter bank against TensorFlow's `linear_to_mel_weight_matrix`: the same nonzero weights, each within
    /// 2e-5. TensorFlow computes the mels in float32, where one unit in the last place at 2,800 mels is 2.4e-4 mels,
    /// about 6e-6 of a band's 40-mel slope; measured, 8.2e-6 at most.
    @Test func melBankMatchesTensorFlow() {
        let bank = YAMNetFrontEnd().filterBank
        var worst = 0.0
        for e in fx.mel {
            let k = Int(e[0]), m = Int(e[1])
            worst = max(worst, abs(bank.weight(band: m, bin: k) - e[2]))
        }
        let ours = bank.weights.reduce(0) { $0 + $1.count }
        print("YAMNet mel bank: \(ours) nonzero weights (TensorFlow \(fx.mel.count)), largest difference \(worst)")
        #expect(ours == fx.mel.count)
        #expect(worst < 2e-5)
    }

    /// The log-mel spectrogram against features.py, after its padding: every value within 1e-3; measured, 1.8e-4 at
    /// most and 5e-6 on average, TensorFlow's float32 STFT and mel weights against this double precision (the
    /// largest differences are in quiet bands, where float32 rounding is a larger part of the value).
    @Test func logMelMatchesYAMNetFeatureCode() {
        let fe = YAMNetFrontEnd()
        for s in fx.signals {
            let y = YAMNetFixture.signal(samples: s.samples)
            let sum = y.reduce(0.0) { $0 + Double($1) }
            #expect(abs(sum - s.sampleSum) < 1e-6 * max(1, abs(s.sampleSum)), "\(s.name): sample sum \(sum) vs \(s.sampleSum)")
            // The same float32 samples, but where another C library's sin rounds a double differently in its last bit.
            #expect(zip(y, s.firstSamples).allSatisfy { abs(Double($0) - $1) <= 1e-7 }, "\(s.name): first samples differ")
            let spec = fe.logMel(y)
            #expect(spec.frames == s.frames)
            guard spec.values.count == s.logMel.count else { Issue.record("\(s.name): size"); continue }
            let d = zip(spec.values, s.logMel).map { abs(Double($0) - $1) }
            let worst = d.max() ?? 0, mean = d.reduce(0, +) / Double(d.count)
            print("YAMNet front end, \(s.name): \(spec.frames) frames x 64 bands, largest difference from features.py "
                  + "\(worst), mean \(mean) (values rounded to 1e-6 in the fixture)")
            #expect(worst <= 1e-3)
            let p = fe.patches(y)
            #expect(p.count == s.patches && p.values.count == s.patches * 96 * 64)
        }
    }

    /// Silence: every value is log(0.001).
    @Test func silence() {
        let spec = YAMNetFrontEnd().logMel([Float](repeating: 0, count: 16000))
        #expect(spec.frames == 144)
        #expect(spec.values.allSatisfy { abs(Double($0) - log(0.001)) < 1e-6 })
    }
}

@Suite struct PatchBarsTests {
    /// The lab's rule: the mean of the patches centred in the bar (start included, end not), else the values
    /// interpolated at the bar's middle, held flat beyond the first and last centres.
    @Test func averagesAsTheLab() {
        // Centres at 0.5, 1.0, 1.5, ... (hop 0.5, offset 0.5), values 0, 1, 2, ...
        let values = (0..<8).map(Double.init)
        let bars = [0.0, 1.0, 2.0, 2.2, 2.4, 4.6, 10.0]
        let got = PatchBars.average(values, hop: 0.5, centreOffset: 0.5, barTimes: bars)
        // Bar 0 holds the centre 0.5 (value 0); bar 1 holds 1.0 and 1.5 (1, 2); bar 2 (2.0 to 2.2) holds 2.0 (3);
        // bar 3 (2.2 to 2.4) holds none: interpolated at 2.3 between 2.0 (3) and 2.5 (4): 3.6; bar 4 holds 2.5 ... 4.5
        // (4 ... 8 less those past 7: 4, 5, 6, 7, mean 5.5); bar 5 (4.6 to 10) holds none: past the last centre, 7.
        let want = [0.0, 1.5, 3.0, 3.6, 5.5, 7.0]
        #expect(got.count == want.count)
        for (g, w) in zip(got, want) { #expect(abs(g - w) < 1e-12, "\(got)") }
        // Before the first centre: the first value.
        #expect(PatchBars.average(values, hop: 0.5, centreOffset: 0.5, barTimes: [0.0, 0.2]) == [0])
        // No patches: zeros.
        #expect(PatchBars.average([], hop: 0.5, centreOffset: 0.5, barTimes: [0, 1, 2]) == [0, 0])
        #expect(PatchBars.interpolate(0.75, [0.5, 1.0], [0, 1]) == 0.5)
    }
}
