import Foundation
import Testing
import DeckieAudio
import DeckieTestSupport
@testable import DeckieCore

/// Fixtures/three_answer.json, written by mixer/keytrial/kt_three.py (`fixture`): eight generated clips and the
/// values of the Python reference of the three-answer key reader on them. The clips are made here again from the
/// fixture's recipe in whole-number arithmetic (no audio file, nothing downloaded), so both sides read the very same
/// samples; the fixture's checksum says so. The full parity, on the 2,090 recordings of the three outside key sets, is
/// run by hand with `kt_three.py parity` against mixer/keytrial/three_answer_expected.tsv.
struct ThreeAnswerFixture: Decodable {
    struct Note: Decodable { var inc: UInt32; var amp: Int }
    struct Case: Decodable {
        var name: String
        var seed: UInt32
        var seconds: Int
        var samples: Int
        var chords: [[Note]]
        var checksum: Int
        var frames: Int
        var answer: String
        var key: Int
        var home: Int
        var tuning: Double
        var pcpA: [Double]
        var pcpB: [Double]
        var scoresA: [Double]
        var scoresB: [Double]
        var decimated: [Double]
        var decimatedCount: Int
        enum CodingKeys: String, CodingKey {
            case name, seed, seconds, samples, chords, checksum, frames, answer, key, home, tuning, decimated
            case pcpA = "pcp_a", pcpB = "pcp_b", scoresA = "scores_a", scoresB = "scores_b", decimatedCount = "decimated_count"
        }
    }
    var cases: [Case]

    /// kt_three.py's `synth`: sawtooth notes from 32-bit phase counters, a falling envelope per two-second chord and
    /// noise from a linear congruential generator, all in integers; 16-bit samples over 32768.
    static func render(_ c: Case) -> (samples: [Float], checksum: Int) {
        guard c.seconds > 0 else { return ([Float](repeating: 0, count: c.samples), 0) }
        let n = c.seconds * 44100
        var out = [Float](repeating: 0, count: n)
        var state = c.seed
        var sum = 0
        let hasNotes = c.chords.contains { !$0.isEmpty }
        for i in 0..<n {
            let l = i % 88200
            let env = 65536 - (l * 43690) / 88200
            var acc = 0
            if !c.chords.isEmpty {
                for note in c.chords[(i / 88200) % c.chords.count] {
                    let phase = UInt32(truncatingIfNeeded: UInt64(note.inc) &* UInt64(i))
                    acc += note.amp * (Int(phase >> 16) - 32768)
                }
            }
            let v = ((acc * env) >> 16) >> 5
            state = state &* 1664525 &+ 1013904223
            let nz = Int(state >> 20) - 2048
            let s = min(max(v + (hasNotes ? nz >> 2 : nz), -32768), 32767)
            sum += s
            out[i] = Float(Double(s) / 32768.0)
        }
        return (out, sum)
    }
}

@Suite struct ThreeAnswerKeyTests {
    static let fx = try! RepoPaths.fixture("three_answer.json", as: ThreeAnswerFixture.self)

    @Test func theGeneratedClipsMatchTheReference() throws {
        var answers: [String: Int] = [:]
        for c in Self.fx.cases {
            let (y, checksum) = ThreeAnswerFixture.render(c)
            #expect(y.count == c.samples && checksum == c.checksum, "\(c.name): the clip is not the reference's")
            let r = try ThreeAnswerKey.read(y, sampleRate: 44100)
            #expect(r.hpcp.frames == c.frames, "\(c.name)")
            #expect(r.answer.name == c.answer, "\(c.name): \(r.answer) against \(c.answer)")
            answers[r.answer.name, default: 0] += 1
            switch r.answer {
            case .key(let pc, let minor): #expect(pc + (minor ? 12 : 0) == c.key && pc == c.home, "\(c.name)")
            case .home(let pc): #expect(pc == c.home && c.key == -1, "\(c.name)")
            case .notSure: #expect(c.home == -1 && c.key == -1, "\(c.name)")
            }
            #expect(near(r.tuning, c.tuning, 1e-6), "\(c.name): tuning \(r.tuning) against \(c.tuning)")
            for i in 0..<24 {
                #expect(near(r.scoresA[i], c.scoresA[i], 1e-5), "\(c.name): row A score \(i)")
                #expect(near(r.scoresB[i], c.scoresB[i], 1e-5), "\(c.name): row B score \(i)")
            }
            let scaleA = c.pcpA.max() ?? 0, scaleB = c.pcpB.max() ?? 0
            for i in 0..<12 {
                #expect(near(r.pcpA[i], c.pcpA[i], 1e-5 * max(scaleA, 1e-12)), "\(c.name): row A profile \(i)")
                #expect(near(r.pcpB[i], c.pcpB[i], 1e-6 * max(scaleB, 1e-12)), "\(c.name): row B profile \(i)")
            }
            // The 11,025 Hz audio the transcription reads.
            let y11 = NoteChroma.resampler.process(y, count: NoteChroma.resampler.librosaCount(for: y.count))
            #expect(y11.count == c.decimatedCount, "\(c.name)")
            for (i, v) in c.decimated.enumerated() { #expect(near(Double(y11[1000 + i]), v, 2e-6), "\(c.name): sample \(1000 + i)") }
        }
        // The fixture holds all three answers.
        #expect(answers["key", default: 0] >= 2 && answers["home", default: 0] >= 1 && answers["none", default: 0] >= 2)
    }

    /// The engine's own test track (A minor: Am, Dm, E, Am with drums) is given its key by both readings, so the
    /// engine's record of it carries a key (EngineTests, which need the beat model, rely on this).
    @Test func theEnginesTestTrackGetsItsKey() throws {
        let buffer = TestTrack.render()
        let mono: [Float] = buffer.channelCount == 1 ? buffer.samples : (0..<buffer.frames).map { f in
            (0..<buffer.channelCount).reduce(Float(0)) { $0 + buffer.samples[f * buffer.channelCount + $1] } / Float(buffer.channelCount)
        }
        let r = try ThreeAnswerKey.read(mono, sampleRate: buffer.sampleRate)
        #expect(r.answer == .key(pitchClass: 9, minor: true) && r.answer.camelot == TestTrack.camelot, "\(r.answer), rows \(r.camelotA ?? "-") / \(r.camelotB ?? "-")")
        #expect(r.guess == TestTrack.camelot && r.hpcp.decision.camelot == TestTrack.camelot)
    }

    @Test func theRule() {
        func scores(_ best: Int, _ others: [Int: Double] = [:]) -> [Double] {
            var s = [Double](repeating: 0.1, count: 24)
            for (k, v) in others { s[k] = v }
            s[best] = 0.9
            return s
        }
        // Same home note, same mode: a key (A minor is index 12 + 9).
        #expect(ThreeAnswerKey.decide(scoresA: scores(21), scoresB: scores(21)) == .key(pitchClass: 9, minor: true))
        #expect(ThreeAnswerKey.decide(scoresA: scores(9), scoresB: scores(9)) == .key(pitchClass: 9, minor: false))
        // Same home note, the rows differ on the mode: the home note, mode open.
        #expect(ThreeAnswerKey.decide(scoresA: scores(21), scoresB: scores(9)) == .home(pitchClass: 9))
        // Row A's best key is elsewhere, but on row B's home note it names the same mode: still not sure, since the
        // home notes differ.
        #expect(ThreeAnswerKey.decide(scoresA: scores(16, [21: 0.5]), scoresB: scores(21)) == .notSure)
        // The relative key (C major against A minor) is a different home note.
        #expect(ThreeAnswerKey.decide(scoresA: scores(0), scoresB: scores(21)) == .notSure)
        // No pitch in one row.
        #expect(ThreeAnswerKey.decide(scoresA: [Double](repeating: 0, count: 24), scoresB: scores(21)) == .notSure)
        #expect(ThreeAnswerKey.Answer.key(pitchClass: 9, minor: true).camelot == "8A")
        #expect(ThreeAnswerKey.Answer.home(pitchClass: 9).camelot == nil)
    }

    @Test func theOvertonesShare() {
        // A lone C: its fifth (G) and major third (E) carry only overtone energy and are taken off; C stays.
        var p = [Double](repeating: 0, count: 12)
        p[0] = 1; p[7] = 0.36; p[4] = 0.1296
        let d = ThreeAnswerKey.discounted(p)
        #expect(d[0] == 1 && near(d[7], 0, 1e-15) && near(d[4], 0, 1e-15))
        // A played third above what the overtones explain stays in part; nothing goes below zero.
        p[4] = 0.5
        #expect(near(ThreeAnswerKey.discounted(p)[4], 0.5 - 0.1296, 1e-12))
        #expect(ThreeAnswerKey.discounted(p).allSatisfy { $0 >= 0 })
    }

    @Test func theSolverFindsTheNotesThatWerePlayed() {
        // A frame made of three templates is given back as those three, and nothing else in play gets weight.
        var y = [Double](repeating: 0, count: NoteChroma.bins)
        let played: [Int: Double] = [24: 2.0, 28: 0.5, 31: 1.25]
        for (n, a) in played { for i in 0..<NoteChroma.bins { y[i] += a * NoteChroma.dictionary[n][i] } }
        var solver = NoteChroma.Solver()
        solver.solve(y, inPlay: Array(12..<60))
        for n in 0..<NoteChroma.notes { #expect(near(solver.x[n], played[n] ?? 0, 1e-8), "note \(n): \(solver.x[n])") }
        // A note left out of play stays at zero whatever the frame holds, and no activation is negative.
        solver.solve(y, inPlay: Array(12..<60).filter { $0 != 28 })
        #expect(solver.x[28] == 0 && solver.x.allSatisfy { $0 >= 0 })
        // Each template sums to one, and a note's own bin is 3 + 3 n.
        for n in [0, 40, 83] {
            #expect(near(NoteChroma.dictionary[n].reduce(0, +), 1, 1e-12))
            #expect(NoteChroma.dictionary[n][3 + 3 * n] > 0)
        }
    }
}
