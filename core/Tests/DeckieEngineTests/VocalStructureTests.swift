import Foundation
import Testing
import DeckieCore
import DeckieTestSupport

// The vocal structure (memo O's items A1 to A6) and the hook candidates (item B7) from constructed inputs, so every
// field can be checked exactly against the construction; they need neither ONNX Runtime nor a model. The engine's
// run on synthesised audio is in VocalStructureEngineTests.

/// The grid of the vocal-structure test track (`VocalStructureTrack`): 40 bars at 124 BPM from 0.5 s.
private let grid = BarGrid(firstDownbeatS: 0.5, beatS: 60.0 / 124, nBars: 40)

/// Frames as a YAMNet-like tagger gives them for a voice over `voiced` (beat indices from bar 1's downbeat, 0-based, the
/// ends exclusive): frame k centred at 0.4875 + 0.48 k with a 0.96 s window, scoring 0.002 plus `peak` times the
/// square of the share of its window that is voiced (the late rise YAMNet showed on the synthesised voice), up to 1 s
/// after the grid's end line.
private func frames(_ voiced: [Range<Double>], peak: Double = 0.6) -> VocalStructure.Frames {
    let end = grid.barTimes.last! + 1
    var scores: [Double] = []
    var k = 0
    while 0.4875 + 0.48 * Double(k) + 0.48 <= end {
        let c = 0.4875 + 0.48 * Double(k)
        var voicedSeconds = 0.0
        for r in voiced {
            let a = grid.firstDownbeatS + r.lowerBound * grid.beatS, b = grid.firstDownbeatS + r.upperBound * grid.beatS
            voicedSeconds += max(0, min(c + 0.48, b) - max(c - 0.48, a))
        }
        let share = voicedSeconds / 0.96
        scores.append(0.002 + peak * share * share)
        k += 1
    }
    return VocalStructure.Frames(scores: scores, hopSeconds: 0.48, centreSeconds: 0.4875)
}

/// The per-bar series: by default the same in every bar, a steady beat (2 onsets a beat) at the test track's levels.
private struct Series {
    var low = [Double](repeating: -27.7, count: 40)
    var high = [Double](repeating: -41.0, count: 40)
    var onsets = [Double](repeating: 2.0, count: 40)
}

private func structure(_ voiced: [Range<Double>], _ series: Series = Series(), lattice: Int = 1, fade: Int? = nil,
                       frames given: VocalStructure.Frames? = nil) -> VocalStructure {
    VocalStructure(frames: given ?? frames(voiced), grid: grid, latticePhaseBar: lattice, lowDb: series.low,
                   highDb: series.high, onsetDensity: series.onsets, fadeStartBar: fade)
}

/// Spans as [start bar, start beat, end bar, end beat].
private func spans(_ s: VocalStructure) -> [[Int]] {
    s.spans.map { [$0.start.bar, $0.start.beat, $0.end.bar, $0.end.beat] }
}
private func barBeat(_ p: VocalStructure.Point?) -> [Int] { p.map { [$0.bar, $0.beat] } ?? [] }
private func stretches(_ list: [VocalStructure.Stretch]) -> [[Int]] { list.map { [$0.startBar, $0.endBar] } }

@Suite struct VocalStructureTests {
    /// The test track's construction: sung from beat 4 of bar 8 (a pickup) to the end of bar 16 and over bars 25 to
    /// 32, of 40.
    @Test func readsTheConstruction() {
        let f = frames([31..<64, 96..<128])
        let s = structure([], frames: f)
        #expect(spans(s) == [[8, 4, 17, 1], [25, 1, 33, 1]])
        // The times are read between frame centres, within a fifth of a beat of the construction's.
        let t = { (beat: Double) in grid.firstDownbeatS + beat * grid.beatS }
        for (got, want) in zip(s.spans.flatMap { [$0.start.seconds, $0.end.seconds] }, [t(31), t(64), t(96), t(128)]) {
            #expect(abs(got - want) < 0.1, "\(got) against \(want)")
        }
        #expect(barBeat(s.first) == [8, 4] && s.pickup && barBeat(s.last) == [32, 4])
        #expect(s.introFreeBars == 7 && s.outroFreeBars == 8)
        #expect(s.introKind == .beatOnly && s.outroKind == .beatOnly)
        // Bar 8 holds the pickup, so the intro's 7 free bars are no gap; bars 17 to 24 and 33 to 40 are.
        #expect(stretches(s.freeGaps) == [[17, 25], [33, 41]] && s.freeGaps.map(\.bars) == [8, 8])
        // The pickup starts a beat before the lattice point at bar 9; the rest are on it.
        #expect(s.spans.map(\.startOffsetBeats) == [-1, 0] && s.spans.map(\.endOffsetBeats) == [0, 0])
        #expect(s.exposedProxy.isEmpty)
        #expect(s.barCoverage[7] == 0.25 && s.barCoverage[8..<16].allSatisfy { $0 == 1 } && s.barCoverage[16] == 0)
        #expect(s.threshold == max(0.01, 0.25 * Py.percentile(f.scores, 95)) && abs(s.scoreP95 - 0.602) < 1e-9)
        #expect(s.frameHopSeconds == 0.48 && s.latticePhaseBar == 1 && s.parameters == .standard)
        print("vocal structure of the construction: spans \(spans(s)), first \(barBeat(s.first)) pickup \(s.pickup), "
              + "last \(barBeat(s.last)), free \(s.introFreeBars)/\(s.outroFreeBars), gaps \(stretches(s.freeGaps)), "
              + "threshold \(Py.fixed(s.threshold, 4))")
    }

    /// The gaps start on the lattice, and the offsets are measured from it, signed.
    @Test func gapsAndOffsetsFollowTheLattice() {
        // Sung over bars 1 to 16 and from 2 beats before bar 31 to the end; lattice points at bars 5, 13, 21, 29, 37.
        let s = structure([0..<64, 118..<160], lattice: 5)
        #expect(spans(s) == [[1, 1, 17, 1], [30, 3, 41, 1]])
        // Free bars 17 to 29 (bar 30 is sung from its third beat), moved to start at bar 21: 9 bars.
        #expect(stretches(s.freeGaps) == [[21, 30]] && s.freeGaps[0].bars == 9)
        // Bar 1 is 16 beats from bar -3 and from bar 5, bar 17 from bars 13 and 21 (a tie, taken as after the earlier
        // point); bar 30 beat 3 is 6 beats after bar 29; the end line, bar 41, is 16 beats after bar 37.
        #expect(s.spans.map(\.startOffsetBeats) == [16, 6] && s.spans.map(\.endOffsetBeats) == [16, 16])
        // A stretch starting 2 beats before a lattice point reads -2.
        let early = structure([126..<160], lattice: 1)
        #expect(spans(early) == [[32, 3, 41, 1]] && early.spans[0].startOffsetBeats == -2)
    }

    /// No vocals at all: no span, no first or last, the whole track free.
    @Test func noVocals() {
        let s = structure([])
        #expect(s.spans.isEmpty && s.first == nil && s.last == nil && !s.pickup)
        #expect(s.introFreeBars == 40 && s.outroFreeBars == 40 && s.introKind == .beatOnly && s.outroKind == .beatOnly)
        #expect(stretches(s.freeGaps) == [[1, 41]] && s.barCoverage.allSatisfy { $0 == 0 })
        // The track's own background stays under the floor, which is the threshold.
        #expect(s.threshold == 0.01)
        #expect(stretches(structure([], lattice: 3).freeGaps) == [[3, 41]])
        // A voice that never reaches the floor is not heard.
        #expect(structure([], frames: frames([32..<64], peak: 0.006)).spans.isEmpty)
    }

    /// Sung from bar 1 to the end: one span over the grid, no free bar, both edges `vocal`.
    @Test func vocalsThroughout() {
        let s = structure([0..<160])
        #expect(spans(s) == [[1, 1, 41, 1]] && barBeat(s.first) == [1, 1] && !s.pickup && barBeat(s.last) == [40, 4])
        #expect(s.introFreeBars == 0 && s.outroFreeBars == 0 && s.introKind == .vocal && s.outroKind == .vocal)
        #expect(s.freeGaps.isEmpty && s.barCoverage.allSatisfy { $0 == 1 })
        #expect(s.spans[0].startOffsetBeats == 0 && s.spans[0].endOffsetBeats == 0)
        // A voice from the very start of the audio, before bar 1's downbeat, still starts at bar 1.
        let early = structure([-1..<64])
        #expect(spans(early) == [[1, 1, 17, 1]] && early.introKind == .vocal)
    }

    /// Stretches shorter than the bridging gap: kept on their own when far from other singing, joined to a verse they
    /// are close to, dropped when they are only a blip.
    @Test func shortStretches() {
        // A one-bar line in bar 3, far from the verse over bars 17 to 32: a span of its own.
        let alone = structure([8..<12, 64..<128])
        #expect(spans(alone) == [[3, 1, 4, 1], [17, 1, 33, 1]] && alone.introFreeBars == 2)
        // The same line 6 beats before the verse (under the 8-beat bridge): one span.
        let close = structure([54..<58, 64..<128])
        #expect(spans(close) == [[14, 3, 33, 1]])
        // 12 beats before it (over the bridge): two.
        #expect(spans(structure([48..<52, 64..<128])) == [[13, 1, 14, 1], [17, 1, 33, 1]])
        // A one-frame blip in the intro, above the threshold but shorter than 2 beats, is dropped.
        var f = frames([64..<128])
        f.scores[10] = 0.6
        let blip = structure([], frames: f)
        #expect(spans(blip) == [[17, 1, 33, 1]] && blip.introFreeBars == 16)
    }

    /// Sung in the last bar: the span ends at the grid's end line and the outro is `vocal`.
    @Test func vocalsInTheLastBar() {
        let s = structure([64..<96, 156..<160])
        #expect(spans(s) == [[17, 1, 25, 1], [40, 1, 41, 1]] && barBeat(s.last) == [40, 4])
        #expect(s.outroFreeBars == 0 && s.outroKind == .vocal && s.introFreeBars == 16)
        #expect(stretches(s.freeGaps) == [[1, 17], [25, 40]])
        // A voice running on past the last whole bar ends at the end line too.
        let past = structure([128..<162])
        #expect(spans(past) == [[33, 1, 41, 1]] && past.outroKind == .vocal)
    }

    /// The intro and outro kinds: beat-only, ambient (few onsets, or a bright wash), fade.
    @Test func edgeKinds() {
        let voiced: [Range<Double>] = [32..<64, 96..<128]
        var quiet = Series()
        for b in 0..<8 { quiet.onsets[b] = 0.3 }
        #expect(structure(voiced, quiet).introKind == .ambient && structure(voiced, quiet).outroKind == .beatOnly)
        var bright = Series()
        for b in 0..<8 { bright.high[b] = -30 }
        #expect(structure(voiced, bright).introKind == .ambient)
        // The fade covers the free outro (bars 33 to 40): fade; it starts at bar 37: the bars before it decide.
        #expect(structure(voiced, fade: 33).outroKind == .fade && structure(voiced, fade: 30).outroKind == .fade)
        #expect(structure(voiced, fade: 37).outroKind == .beatOnly)
        var fadingAmbient = Series()
        for b in 32..<36 { fadingAmbient.onsets[b] = 0.2 }
        #expect(structure(voiced, fadingAmbient, fade: 37).outroKind == .ambient)
        // Singing into the last bar is `vocal` even over a fade.
        #expect(structure([32..<160], fade: 33).outroKind == .vocal)
    }

    /// The exposed-vocal proxy: sung bars over little bass and few onsets, two bars or more.
    @Test func exposedProxy() {
        var series = Series()
        for b in [9] + Array(24..<28) {
            series.low[b] = -40
            series.onsets[b] = 0.5
        }
        let s = structure([0..<160], series)
        #expect(stretches(s.exposedProxy) == [[25, 29]])
        // Not where nothing is sung.
        #expect(structure([0..<64], series).exposedProxy.isEmpty)
    }

    /// A tagger with bars only: one frame per bar, changes on bar lines, no pickup read from a bar's mean.
    @Test func barResolution() {
        let perBar = (0..<40).map { (8..<24).contains($0) ? 0.9 : 0.1 }
        let s = structure([], frames: .perBar(perBar, grid: grid))
        #expect(spans(s) == [[9, 1, 25, 1]] && !s.pickup && s.introFreeBars == 8 && s.outroFreeBars == 16)
        #expect(abs(s.threshold - 0.225) < 1e-12 && s.frameHopSeconds == grid.barS)
        #expect(stretches(s.freeGaps) == [[1, 9], [25, 41]])
    }

    /// The threshold follows the track's own scores: the same voice ten times quieter reads the same.
    @Test func thresholdIsRelative() {
        let loud = structure([], frames: frames([31..<64, 96..<128]))
        let quiet = structure([], frames: frames([31..<64, 96..<128], peak: 0.06))
        #expect(spans(quiet) == spans(loud) && quiet.pickup && abs(quiet.threshold - 0.25 * 0.062) < 1e-9)
    }
}

@Suite struct HookTests {
    /// 40 bars, each with its own random features, except a chorus (bars 9 to 16 and 25 to 32: the same eight bars
    /// twice, 4 dB louder and sung) and a riff (bars 1 to 4 and 17 to 20: the same four bars, quiet, not sung); bars 33
    /// to 40 are the loudest of all but do not repeat. The chorus comes first, at its first place, as 8 bars; then the
    /// riff; the loud stretch that does not repeat is no hook, and neither is the chorus's second place.
    @Test func aRepeatedLoudSungSectionComesFirst() {
        var g = SplitMix64Generator(5)
        var bars = (0..<40).map { _ in (0..<64).map { _ in 2 * g.uniform() - 1 } }
        for i in 0..<8 { bars[24 + i] = bars[8 + i] }
        for i in 0..<4 { bars[16 + i] = bars[i] }
        let features = FrameMatrix(frames: 40, rows: 64, values: bars.flatMap { $0 })
        var lufs = [Double](repeating: -20, count: 40), coverage = [Double](repeating: 0, count: 40)
        for b in Array(8..<16) + Array(24..<32) { lufs[b] = -16; coverage[b] = 1 }
        for b in 32..<40 { lufs[b] = -14 }
        let h = Hooks(barSimilarity: Hooks.barSimilarity(features), lufs: lufs, vocalCoverage: coverage, latticePhaseBar: 1)
        let c = h.candidates
        #expect(c.map { [$0.startBar, $0.endBar, $0.repeatStartBar] } == [[9, 17, 25], [1, 5, 17]])
        #expect(c.map(\.sung) == [true, false])
        // strength = (0.5 repetition + 0.25 loudness + 0.25 vocal) / 1: the chorus's loudness is 4 dB over the 10th
        // percentile in a 6 dB range.
        #expect(abs(c[0].repetition - 1) < 1e-9 && abs(c[0].loudness - 4.0 / 6) < 1e-9 && c[0].vocalDensity == 1)
        #expect(abs(c[0].strength - (0.5 + 0.25 * 4 / 6 + 0.25)) < 1e-9 && abs(c[1].strength - 0.5) < 1e-9)
        #expect(h.latticePhaseBar == 1 && h.parameters == .standard)
        print("hooks of the construction: \(c.map { "\($0.startBar)-\($0.endBar) \(Py.fixed($0.strength, 3)) sung \($0.sung)" })")
    }

    /// Candidates start on the lattice and at most three are given, none overlapping another or its repeat.
    @Test func atMostThreeOnTheLattice() {
        // The same 4-bar pattern all through: everything repeats; louder towards the end.
        var g = SplitMix64Generator(9)
        let pattern = (0..<4).map { _ in (0..<16).map { _ in 2 * g.uniform() - 1 } }
        let features = FrameMatrix(frames: 40, rows: 16, values: (0..<40).flatMap { pattern[$0 % 4] })
        let lufs = (0..<40).map { -20 + Double($0) / 10 }
        let h = Hooks(barSimilarity: Hooks.barSimilarity(features), lufs: lufs,
                      vocalCoverage: [Double](repeating: 0, count: 40), latticePhaseBar: 3)
        #expect(h.candidates.count == 3)
        #expect(h.candidates.allSatisfy { ($0.startBar - 3) % 4 == 0 && [4, 8].contains($0.bars) })
        #expect(zip(h.candidates, h.candidates.dropFirst()).allSatisfy { $0.strength >= $1.strength })
        for (i, a) in h.candidates.enumerated() {
            for b in h.candidates[(i + 1)...] {
                #expect(b.endBar <= a.startBar || b.startBar >= a.endBar)
                #expect(b.endBar <= a.repeatStartBar || b.startBar >= a.repeatStartBar + a.bars)
            }
        }
    }

    /// The bar features: the MFCC averaged over each bar on every eighth half-beat edge, the first coefficient left
    /// out, the rest centred; and their similarity.
    @Test func barFeaturesFromTheNoveltyFrames() {
        // 13 coefficients over 33 frames; two bars of 8 half-beats of 2 frames each.
        let values = (0..<33).flatMap { t in (0..<13).map { r in Double(10 * r) + (t < 16 ? 1 : 3) } }
        let mfcc = FrameMatrix(frames: 33, rows: 13, values: values)
        let f = Hooks.barFeatures(mfcc: mfcc, halfBeatEdges: Array(stride(from: 0, through: 32, by: 2)))
        #expect(f.frames == 2 && f.rows == 12)
        #expect(f.values == [Double](repeating: -1, count: 12) + [Double](repeating: 1, count: 12))
        let s = Hooks.barSimilarity(f)
        #expect(s.count == 4 && abs(s[0] - 1) < 1e-9 && abs(s[1] + 1) < 1e-9)
    }
}
