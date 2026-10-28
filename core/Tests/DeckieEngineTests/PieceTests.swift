import Foundation
import Testing
import DeckieCore
import DeckieEngine

// The engine's own pieces, which need neither ONNX Runtime nor the model. (The file hash is DeckieCrate's
// `CrateIDs`, tested there.)

@Suite struct JSONValueTests {
    /// Python's json.dumps(..., separators=(",", ":")): keys in order, floats in their shortest form with .0 on whole
    /// numbers, ASCII only.
    @Test func writesAsPythonDoes() {
        let v = JSONValue.object([
            .init("b", .number(1.0)), .init("a", .array([.number(0.1), .number(1e-05), .number(118.497), .int(3),
                                                          .number(-0.0), .number(1e16)])),
            .init("s", .string("é \"q\" \\ \n 😀")), .init("n", .null), .init("t", .bool(true)),
            .init("inf", .number(-.infinity)),
        ])
        // Built from parts so that no editor turns the escapes back into the characters: u is a backslash and a "u".
        let u = String(UnicodeScalar(92)) + "u"
        let s = u + "00e9 " + #"\"q\" \\ \n "# + u + "d83d" + u + "de00"
        #expect(v.text == #"{"b":1.0,"a":[0.1,1e-05,118.497,3,-0.0,1e+16],"s":""# + s + #"","n":null,"t":true,"inf":null}"#)
        #expect(v.keys == ["b", "a", "s", "n", "t", "inf"])
        #expect(v["t"] == .bool(true))
        // And Foundation reads it back.
        #expect((try? JSONSerialization.jsonObject(with: v.data)) != nil)
    }
}

@Suite struct KeyConfidenceTests {
    /// The one-estimator steps: r under 0.6 gives 0.3 whatever the margin; then margin 0.10 and up 0.65, 0.04 to 0.10
    /// 0.45, under 0.04 0.3.
    @Test func steps() {
        func c(_ r: Double, _ margin: Double) -> Double {
            KeyConfidence.oneEstimator(KeyEstimate(pitchClass: 9, mode: "minor", r: r, margin: margin)).value
        }
        #expect(c(0.59, 0.3) == 0.3)
        #expect(c(0.8, 0.10) == 0.65)
        #expect(c(0.8, 0.25) == 0.65)
        #expect(c(0.8, 0.0999) == 0.45)
        #expect(c(0.6, 0.04) == 0.45)
        #expect(c(0.8, 0.0399) == 0.3)
        #expect(c(.nan, 0.2) == 0.3)
        let rule = KeyConfidence.oneEstimator(KeyEstimate(pitchClass: 0, mode: "major", r: 0.8, margin: 0.2)).rule
        #expect(rule.contains("one estimator"))
    }
}

@Suite struct OctaveAlignTests {
    static let rate = 44100

    /// Mono audio with a 50 ms burst of `level` at each time.
    static func clicks(_ times: [(Double, Float)], seconds: Double) -> [Float] {
        var y = [Float](repeating: 0, count: Int(seconds * Double(rate)))
        for (t, level) in times {
            let i = Int(t * Double(rate))
            for j in i..<min(i + rate / 20, y.count) { y[j] = (j - i) % 2 == 0 ? level : -level }
        }
        return y
    }

    /// The tracker at double the tag: every other beat is kept (the parity most downbeats fall on), and when the
    /// downbeats are half-bars the alternate set with the stronger hit is kept.
    @Test func halvesADoubledPulse() throws {
        let beats = (0..<240).map { 0.1 + Double($0) * 0.25 }  // 240 BPM
        let downs = stride(from: 0, to: 240, by: 4).map { beats[$0] }  // every second: half-bars at 120 BPM
        let grid = try #require(BeatGrid.fit(beats: beats, downbeats: downs))
        // The downbeats at even seconds hit harder.
        let mono = Self.clicks(downs.enumerated().map { ($0.element, $0.offset % 2 == 0 ? 0.8 : 0.2) }, seconds: 61)
        let r = OctaveAlign.align(beats: beats, downbeats: downs, grid: grid, bpmTag: 120, mono: mono,
                                  sampleRate: Self.rate)
        #expect(r.fix == OctaveFix(mode: .halved, fromBpm: 240, parity: 0))
        #expect(abs(r.grid.bpm - 120) < 1e-6)
        #expect(r.beats == stride(from: 0, to: 240, by: 2).map { beats[$0] })
        #expect(r.downbeats == stride(from: 0, to: downs.count, by: 2).map { downs[$0] })
        // With the odd ones harder, the odd set is kept.
        let mono2 = Self.clicks(downs.enumerated().map { ($0.element, $0.offset % 2 == 1 ? 0.8 : 0.2) }, seconds: 61)
        let r2 = OctaveAlign.align(beats: beats, downbeats: downs, grid: grid, bpmTag: 120, mono: mono2,
                                   sampleRate: Self.rate)
        #expect(r2.downbeats == stride(from: 1, to: downs.count, by: 2).map { downs[$0] })
    }

    /// The tracker at half the tag: a beat is added halfway between each pair, and so is a downbeat.
    @Test func doublesAHalvedPulse() throws {
        let beats = (0..<60).map { 0.3 + Double($0) }  // 60 BPM
        let downs = stride(from: 0, to: 60, by: 4).map { beats[$0] }
        let grid = try #require(BeatGrid.fit(beats: beats, downbeats: downs))
        let r = OctaveAlign.align(beats: beats, downbeats: downs, grid: grid, bpmTag: 120, mono: [], sampleRate: Self.rate)
        #expect(r.fix == OctaveFix(mode: .doubled, fromBpm: 60, parity: nil))
        #expect(r.beats.count == 119 && abs(r.grid.bpm - 120) < 1e-6)
        #expect(r.downbeats.count == 2 * downs.count - 1)
    }

    /// No tag, or a tag the grid already agrees with: nothing changes.
    @Test func leavesTheRestAlone() throws {
        let beats = (0..<120).map { 0.2 + Double($0) * 0.5 }
        let downs = stride(from: 0, to: 120, by: 4).map { beats[$0] }
        let grid = try #require(BeatGrid.fit(beats: beats, downbeats: downs))
        for tag in [nil, 0, 120, 100] as [Double?] {
            let r = OctaveAlign.align(beats: beats, downbeats: downs, grid: grid, bpmTag: tag, mono: [],
                                      sampleRate: Self.rate)
            #expect(r.fix == nil && r.beats == beats && r.grid == grid)
        }
    }

    /// `_rms_at`: the median over the times of the RMS of the 50 ms from each; times past the end count for nothing.
    @Test func rmsAtTimes() {
        let y = [Float](repeating: 0.5, count: Self.rate)
        #expect(OctaveAlign.rms(at: [0, 0.5], in: y, sampleRate: Self.rate) == 0.5)
        #expect(OctaveAlign.rms(at: [2.0], in: y, sampleRate: Self.rate) == 0)
        #expect(OctaveAlign.rms(at: [], in: y, sampleRate: Self.rate) == 0)
    }
}
