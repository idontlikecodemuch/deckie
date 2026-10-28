import Foundation
import Testing
import DeckieAudio
import DeckieCore
import DeckieInference
import DeckieTestSupport

@Suite struct BeatTrackerInputTests {
    /// 22,050 Hz passes, 44,100 Hz is halved, anything else is refused until a resampler exists.
    @Test func sampleRates() throws {
        let y = (0..<1000).map { Float($0 % 7) / 7 }
        #expect(try BeatTracker.modelRateSignal(y, sampleRate: 22050) == y)
        #expect(try BeatTracker.modelRateSignal(y, sampleRate: 44100) == Decimator.halve(y))
        #expect(throws: BeatTrackerError.resampleFirst(sampleRate: 48000)) { try BeatTracker.modelRateSignal(y, sampleRate: 48000) }
    }
}

/// The tracker end to end against the Beat This! package (torch, final0) on the same synthesised drums
/// (Fixtures/beat_this.json from Tools/make_beat_fixtures.py): the 30 s pattern at 120 BPM at 44.1 and 22.05 kHz and
/// the 90 s one turning from 128 to 100 BPM at 45 s.
@Suite(.enabled(if: Available.beatTracker, "needs ONNX Runtime (core/Tools/fetch-onnxruntime.sh) and the Beat This! model (core/Tools/export_beat_this.py)"))
struct BeatTrackerTests {
    static let tracker: BeatTracker? = try? BeatTracker()
    let fx = BeatThisFixture.shared
    static let frame = 1.0 / Double(BeatThisFrontEnd.framesPerSecond)

    func tracker() throws -> BeatTracker { try #require(Self.tracker, "the tracker did not load") }

    /// Pairs up two sorted lists of times: equal counts and every pair within one frame (20 ms).
    func compare(_ got: [Double], _ want: [Double]) -> (sameCount: Bool, withinFrame: Bool, identical: Int, worst: Double) {
        guard got.count == want.count else { return (false, false, 0, .infinity) }
        let d = zip(got, want).map { abs($0 - $1) }
        return (true, d.allSatisfy { $0 <= Self.frame + 1e-9 }, d.filter { $0 == 0 }.count, d.max() ?? 0)
    }

    /// The times of `a` with no time of `b` within one frame.
    func unpaired(_ a: [Double], _ b: [Double]) -> [Double] {
        a.filter { t in !b.contains { abs($0 - t) <= Self.frame + 1e-9 } }
    }

    /// At 22.05 kHz the tracker reads what the package reads, so its beats and downbeats must be the package's within
    /// one frame, every one. At 44.1 kHz the package resamples with soxr and the tracker with the stopgap
    /// `Decimator.halve`, which moves logits by up to about 0.6: there a beat may be found by one side only where
    /// its logit is within 0.1 of the threshold (0) on both sides, a decision on a knife edge, and each such beat may
    /// move a downbeat on either side; everything else must pair within one frame.
    @Test func piecesMatchThePackage() async throws { try await CPUTurns.exclusive {
        let tracker = try tracker()
        for p in fx.pieces {
            let y = p.render()
            #expect(BeatThisFixture.matches(y, p.synth), "\(p.name): the synthesised signal is not the fixture's")
            let r = try tracker.track(AudioBuffer(sampleRate: p.rate, channelCount: 1, samples: y))
            #expect(r.logits.frames == p.frames)
            let logitDiff = zip(r.logits.beat + r.logits.downbeat, p.beatLogits + p.downbeatLogits).map { abs(Double($0) - Double($1)) }.max() ?? 0
            let b = compare(r.beats.beats, p.beats), d = compare(r.beats.downbeats, p.downbeats)
            let onlyHere = unpaired(r.beats.beats, p.beats), onlyThere = unpaired(p.beats, r.beats.beats)
            let downHere = unpaired(r.beats.downbeats, p.downbeats), downThere = unpaired(p.downbeats, r.beats.downbeats)
            print("""
                \(p.name): \(r.beats.beats.count) beats (package \(p.beats.count)), \(b.identical) identical\(b.sameCount ? ", worst \(b.worst) s" : ""), \
                only here \(onlyHere), only in the package \(onlyThere); \(r.beats.downbeats.count) downbeats (package \(p.downbeats.count)), \
                \(d.identical) identical\(d.sameCount ? ", worst \(d.worst) s" : ""), only here \(downHere), only in the package \(downThere); \
                largest logit difference \(logitDiff); time: resampling \(r.timing.resampling) s, spectrogram \(r.timing.spectrogram) s, \
                model \(r.timing.model) s, postprocessing \(r.timing.postprocessing) s
                """)
            if p.rate == BeatThisFrontEnd.sampleRate {
                #expect(b.sameCount && b.withinFrame, "\(p.name): beats differ from the package's by more than one frame")
                #expect(d.sameCount && d.withinFrame, "\(p.name): downbeats differ from the package's by more than one frame")
            } else {
                for t in onlyHere + onlyThere {
                    let f = Int((t * Double(BeatThisFrontEnd.framesPerSecond)).rounded())
                    let here = r.logits.beat[f], there = p.beatLogits[f]
                    #expect(abs(here) <= 0.1 && abs(there) <= 0.1,
                            "\(p.name): a beat at \(t) s on one side only, with logits \(here) here and \(there) in the package")
                }
                let marginal = onlyHere.count + onlyThere.count
                #expect(downHere.count <= marginal && downThere.count <= marginal,
                        "\(p.name): downbeats differ beyond what the marginal beats explain")
            }
        }
    } }

    /// On the 120 BPM pattern at 44.1 kHz the beats sit on the clicks and the downbeats on every fourth beat, the
    /// accented ones.
    @Test func firstPieceSitsOnTheClicks() async throws { try await CPUTurns.exclusive {
        let p = try #require(fx.pieces.first { $0.name == "drums_120_30s_44k" })
        let r = try tracker().track(AudioBuffer(sampleRate: p.rate, channelCount: 1, samples: p.render()))
        let clicks = p.trueBeats.map(\.time), accents = p.trueBeats.filter(\.accent).map(\.time)
        let beats = r.beats.beats, period = 60.0 / 120
        func nearest(_ t: Double, _ list: [Double]) -> Double { list.map { abs($0 - t) }.min() ?? .infinity }
        // Every click has a beat within 20 ms.
        let missed = clicks.filter { nearest($0, beats) > 0.02 + 1e-9 }
        #expect(missed.isEmpty, "clicks without a beat: \(missed)")
        // Every beat within the clicks' span is within 20 ms of a click; outside it the model may continue the grid
        // by one period into the lead-in or tail, and nothing else.
        let inside = beats.filter { $0 >= clicks.first! - 0.02 && $0 <= clicks.last! + 0.02 }
        let outside = beats.filter { $0 < clicks.first! - 0.02 || $0 > clicks.last! + 0.02 }
        let worst = inside.map { nearest($0, clicks) }.max() ?? 0
        #expect(worst <= 0.02 + 1e-9, "a beat \(worst) s from the nearest click")
        for t in outside {
            let gap = min(abs(clicks.first! - t), abs(t - clicks.last!))
            #expect(abs(gap - period) <= 0.02 + 1e-9, "a beat at \(t) s, outside the clicks and not one period from them")
        }
        #expect(outside.count <= 2)
        // Downbeats: on accented clicks, four beats apart.
        let downbeats = r.beats.downbeats
        let offAccent = downbeats.filter { nearest($0, accents) > 0.02 + 1e-9 }
        #expect(offAccent.isEmpty, "downbeats away from the accents: \(offAccent)")
        let positions = downbeats.compactMap { d in beats.firstIndex(of: d) }
        #expect(positions.count == downbeats.count, "every downbeat is one of the beats")
        let steps = zip(positions.dropFirst(), positions).map { $0 - $1 }
        #expect(steps.allSatisfy { $0 == 4 }, "beats between downbeats: \(steps)")
        print("""
            120 BPM clicks: \(clicks.count) clicks, \(beats.count) beats (\(outside.count) outside the clicks, at \(outside) s); \
            largest distance from a click \(worst) s; \(downbeats.count) downbeats of \(accents.count) accents, \
            steps between them \(Set(steps))
            """)
    } }

    /// Four minutes at 44.1 kHz (the 128 BPM pattern), timed step by step.
    @Test func fourMinutes() async throws { try await CPUTurns.exclusive {
        let tracker = try tracker()
        let beats = DrumPattern.steadyBeats(first: 0.5, bpm: 128, end: 239.75)
        let y = DrumPattern.render(rate: 44100, samples: 240 * 44100, beats: beats, seed: 13)
        let t0 = Date()
        let r = try tracker.track(AudioBuffer(sampleRate: 44100, channelCount: 1, samples: y))
        let total = Date().timeIntervalSince(t0)
        let found = beats.filter { b in r.beats.beats.contains { abs($0 - b.time) <= 0.02 + 1e-9 } }.count
        print("""
            four minutes at 44.1 kHz: \(String(format: "%.2f", total)) s in all: resampling \(String(format: "%.2f", r.timing.resampling)) s, \
            spectrogram \(String(format: "%.2f", r.timing.spectrogram)) s, model \(String(format: "%.2f", r.timing.model)) s \
            (\(BeatThisChunking.split(frames: r.logits.frames).count) chunks), postprocessing \(String(format: "%.3f", r.timing.postprocessing)) s; \
            \(found) of \(beats.count) clicks found within 20 ms
            """)
        #expect(r.logits.frames == 1 + 240 * 22050 / 441)
        #expect(found >= beats.count - 2)
    } }
}
