import Testing
import Foundation
import DeckieCore
import DeckieLab

/// Field-by-field comparison of the port's block with the lab's, each number within a tolerance taken from how the
/// lab rounds that field: half a unit of its last decimal plus a fifth (2 decimals: 0.006; 1 decimal: 0.06; 3
/// decimals: 0.0006; 4 decimals: 0.00006). Counts, bar numbers, rules, booleans and flags must be identical.
/// The port rounds as the lab rounds, so a value within tolerance is in practice identical; `inexact` counts the
/// ones that are not. Two roundings of nearly the same number can still land a whole unit apart when the number
/// sits on a tie, and that happens with the window residual (`residual`, below).
private struct BlockComparison {
    var mismatches: [String] = []
    var inexact = 0
    var ties: [String] = []

    mutating func number(_ name: String, _ got: Double?, _ want: Double?, _ tol: Double) {
        switch (got, want) {
        case (nil, nil): return
        case let (g?, w?):
            if g == w { return }
            if abs(g - w) <= tol { inexact += 1 } else { mismatches.append("\(name) \(g) vs \(w)") }
        default:
            mismatches.append("\(name) \(got.map { "\($0)" } ?? "nil") vs \(want.map { "\($0)" } ?? "nil")")
        }
    }

    mutating func same<T: Equatable>(_ name: String, _ got: T?, _ want: T?) {
        if got != want { mismatches.append("\(name) \(got.map { "\($0)" } ?? "nil") vs \(want.map { "\($0)" } ?? "nil")") }
    }

    /// A window's residual. The beats are on a millisecond grid, so the median distance from the fitted line can be
    /// an exact tie for the rounding to 0.1 ms (x.x5 ms) in decimal arithmetic; which way it rounds is then decided
    /// by the last bits of the least squares solve, and numpy's (LAPACK's dgelsd: QR, then the SVD of R) and the
    /// port's (the 2x2 normal equations, as in the grid fit) differ there by a few units in the last place; no
    /// simple solve matches numpy's bits, and the lab's numpy (Accelerate, on the Mac) is not the one here
    /// (OpenBLAS) either. So a residual 0.1 ms from the lab's is accepted when the port's unrounded value is the
    /// midpoint of the two within 1e-9 ms, a millionth of the tolerance (a value off the tie lands that close by
    /// chance about once in 50 million), and listed.
    mutating func residual(_ name: String, _ got: Double, _ want: Double, unrounded: Double?) {
        if got != want, abs(abs(got - want) - 0.1) < 1e-9, let u = unrounded, abs(u - (got + want) / 2) < 1e-9 {
            ties.append("\(name) \(got) vs \(want), unrounded \(u) ms")
            return
        }
        number(name, got, want, 0.06)
    }

    mutating func window(_ name: String, _ got: LocalTempo.Window?, _ want: FeatureFile.LocalTempo.Window?,
                         unroundedResidMs: Double? = nil) {
        guard let g = got, let w = want else {
            if (got == nil) != (want == nil) {
                mismatches.append("\(name) \(got == nil ? "nil" : "a window") vs \(want == nil ? "nil" : "a window")")
            }
            return
        }
        number("\(name).bpm", g.bpm, w.bpm, 0.006)
        number("\(name).bpm_raw", g.bpmRaw, w.bpmRaw, 0.006)
        number("\(name).mult", g.mult, w.mult, 0.00006)
        same("\(name).n_beats", g.nBeats, w.nBeats)
        residual("\(name).resid_ms", g.residMs, w.residMs, unrounded: unroundedResidMs)
        number("\(name).t0", g.t0, w.t0, 0.006)
        number("\(name).t1", g.t1, w.t1, 0.006)
    }

    mutating func block(_ got: LocalTempo, _ want: FeatureFile.LocalTempo, unroundedResidMs: [String: Double]) {
        number("ref_bpm", got.refBpm, want.refBpm, 0)  // copied from the feature file's bpm, not rounded here
        window("first30", got.first30, want.first30, unroundedResidMs: unroundedResidMs["first30"])
        window("last30", got.last30, want.last30, unroundedResidMs: unroundedResidMs["last30"])
        window("mix_in", got.mixIn, want.mixIn, unroundedResidMs: unroundedResidMs["mix_in"])
        window("mix_out", got.mixOut, want.mixOut, unroundedResidMs: unroundedResidMs["mix_out"])
        number("grid_dev_in_ms", got.gridDevInMs, want.gridDevInMs, 0.06)
        number("grid_dev_out_ms", got.gridDevOutMs, want.gridDevOutMs, 0.06)
        // bpm_in and bpm_out are the global tempo (copied) or a window's tempo (2 decimals).
        number("bpm_in", got.bpmIn, want.bpmIn, 0.006)
        same("in_trusted", got.inTrusted, want.inTrusted)
        same("in_rule", got.inRule.rawValue, want.inRule)
        number("bpm_out", got.bpmOut, want.bpmOut, 0.006)
        same("out_trusted", got.outTrusted, want.outTrusted)
        same("out_rule", got.outRule.rawValue, want.outRule)
        number("drift_pct", got.driftPct, want.driftPct, 0.006)
        let wantProfile = want.profile ?? []
        if got.profile.count != wantProfile.count {
            mismatches.append("profile has \(got.profile.count) segments vs \(wantProfile.count)")
        } else {
            for (i, (g, w)) in zip(got.profile, wantProfile).enumerated() {
                number("profile[\(i)].start", g.start, w.start, 0.06)
                number("profile[\(i)].bpm", g.bpm, w.bpm, 0.006)
                same("profile[\(i)].trusted", g.trusted, w.trusted)
            }
        }
        number("range_pct", got.rangePct, want.rangePct, 0.006)
        same("untrusted_segments", got.untrustedSegments, want.untrustedSegments)
        number("steady_in_s", got.steadyInS, want.steadyInS, 0.0006)
        same("steady_in_bar", got.steadyInBar, want.steadyInBar)
        number("steady_out_s", got.steadyOutS, want.steadyOutS, 0.0006)
        same("steady_out_bar", got.steadyOutBar, want.steadyOutBar)
        number("first_downbeat_in_s", got.firstDownbeatInS, want.firstDownbeatInS, 0.0006)
        number("first_downbeat_out_s", got.firstDownbeatOutS, want.firstDownbeatOutS, 0.0006)
        same("tempo_change", got.tempoChange, want.tempoChange)
        same("transition_track", got.transitionTrack, want.transitionTrack)
        same("in_half_time", got.inHalfTime, want.inHalfTime)
        same("out_half_time", got.outHalfTime, want.outHalfTime)
        same("intro_no_steady_beat", got.introNoSteadyBeat, want.introNoSteadyBeat)
        same("outro_no_steady_beat", got.outroNoSteadyBeat, want.outroNoSteadyBeat)
    }
}

@Suite struct LocalTempoTests {
    /// Every key `compute` writes, by the lab's names.
    static let labKeys: Set<String> = [
        "ref_bpm", "first30", "last30", "mix_in", "mix_out", "grid_dev_in_ms", "grid_dev_out_ms",
        "bpm_in", "in_trusted", "in_rule", "bpm_out", "out_trusted", "out_rule", "drift_pct", "profile",
        "range_pct", "untrusted_segments", "steady_in_s", "steady_in_bar", "steady_out_s", "steady_out_bar",
        "first_downbeat_in_s", "first_downbeat_out_s", "tempo_change", "transition_track", "in_half_time",
        "out_half_time", "intro_no_steady_beat", "outro_no_steady_beat",
    ]

    /// The port's residuals before rounding for the four named windows, from the window bounds `compute` uses.
    static func unroundedResidMs(_ input: LocalTempoInput) -> [String: Double] {
        let det = input.detectedBeats.isEmpty ? input.gridBeats : input.detectedBeats
        let fs = input.firstSound ?? 0, ls = input.lastSound ?? input.duration, win = LocalTempo.windowSeconds
        var bounds = ["first30": (fs, min(fs + win, ls)), "last30": (max(ls - win, fs), ls)]
        if let m = input.mixIn { bounds["mix_in"] = (m.start ?? fs, m.end ?? fs + win) }
        if let m = input.mixOut { bounds["mix_out"] = (m.start ?? ls - win, m.end ?? ls) }
        return bounds.compactMapValues { t0, t1 in BeatGrid.windowFit(det.filter { $0 >= t0 && $0 <= t1 })?.madMs }
    }

    /// Every committed `local_tempo` block, recomputed from the same feature file's committed inputs. The current
    /// mixer/local_tempo.py, run in Python on the committed (millisecond-rounded) data, reproduces all 373 committed
    /// blocks exactly, so the files are the reference and no fixture is needed. The track's local tempo flags,
    /// in the lab's order, are the ones the port's `flags` gives. Every field of 372 tracks is identical; on
    /// 90b24bf89e the mix-in residual is a rounding tie (5.25 ms to within 1e-11 ms), which numpy rounds to 5.3
    /// and the port to 5.2; nothing else in that block differs. Of the 7,538 windows the 373 blocks fit
    /// (profile segments included), three more sit on such a tie, all profile segments, where only the trust
    /// decision is kept and the residual is far from 15 ms.
    @Test func reproducesTheCommittedBlockOnEveryTrack() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: RepoPaths.features.path)
            .filter { $0.hasSuffix(".json") }.sorted()
        #expect(files.count == 373)
        var identical = 0, withinRounding = 0, failing: [String] = [], ties: [String] = []
        for name in files {
            let data = try Data(contentsOf: RepoPaths.features.appendingPathComponent(name))
            let d = try JSONDecoder().decode(FeatureFile.self, from: data)
            let raw = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let rawBlock = try #require(raw["local_tempo"] as? [String: Any], "\(d.id) has no local_tempo block")
            #expect(Set(rawBlock.keys) == Self.labKeys, "\(d.id) local_tempo keys \(rawBlock.keys.sorted())")
            let want = try #require(d.localTempo)

            let input = d.localTempoInput
            let got = LocalTempo.compute(input)
            var c = BlockComparison()
            c.block(got, want, unroundedResidMs: Self.unroundedResidMs(input))
            let labFlags = (d.flags ?? []).filter { LocalTempo.flagNames.contains($0) }
            if got.flags != labFlags { c.mismatches.append("flags \(got.flags) vs \(labFlags)") }

            #expect(c.mismatches.isEmpty, "\(d.id): \(c.mismatches.joined(separator: "; "))")
            ties += c.ties.map { "\(d.id) \($0)" }
            if !c.mismatches.isEmpty {
                failing.append(d.id)
            } else if c.inexact == 0 && c.ties.isEmpty {
                identical += 1
            } else {
                withinRounding += 1
            }
        }
        print("local tempo: \(files.count) tracks; identical on every field: \(identical); within rounding or on a "
              + "rounding tie: \(withinRounding) \(ties); disagreeing: \(failing.count) \(failing)")
    }

    // MARK: synthetic beat lists (each case also run through mixer/local_tempo.py, which gives the numbers checked)

    /// 120 BPM, a beat every 0.5 s from 0.25 s to 180.25 s, a downbeat every fourth beat.
    static func steadyInput(onGrid: Bool) -> LocalTempoInput {
        let beats = (0...360).map { 0.25 + 0.5 * Double($0) }
        let downs = stride(from: 0, to: beats.count, by: 4).map { beats[$0] }
        return LocalTempoInput(bpm: 120, duration: 181, detectedBeats: beats, detectedDownbeats: downs,
                               gridBeats: onGrid ? beats : [], firstDownbeat: 0.25, firstSound: 0.25,
                               lastSound: 180.25, mixIn: .init(start: 0.25, end: 16.25),
                               mixOut: .init(start: 148.25, end: 180.25))
    }

    @Test func aSteadyBeatGivesTheReferenceTempoAndTrustedWindows() throws {
        let lt = LocalTempo.compute(Self.steadyInput(onGrid: false))
        let first = try #require(lt.first30)
        #expect(first == LocalTempo.Window(bpm: 120, bpmRaw: 120, mult: 1, nBeats: 61, residMs: 0, t0: 0.25, t1: 30.25))
        #expect(lt.last30 == LocalTempo.Window(bpm: 120, bpmRaw: 120, mult: 1, nBeats: 61, residMs: 0, t0: 150.25,
                                                t1: 180.25))
        #expect(lt.mixIn?.nBeats == 33 && lt.mixOut?.nBeats == 65)
        #expect(LocalTempo.isTrusted(lt.first30) && LocalTempo.isTrusted(lt.last30))
        #expect(lt.gridDevInMs == nil && lt.gridDevOutMs == nil)  // no grid given
        #expect(lt.bpmIn == 120 && lt.inTrusted && lt.inRule == .localMatches)
        #expect(lt.bpmOut == 120 && lt.outTrusted && lt.outRule == .localMatches)
        #expect(lt.driftPct == 0 && lt.rangePct == 0 && lt.untrustedSegments == 0)
        #expect(lt.profile.count == 12 && lt.profile.allSatisfy { $0.trusted && $0.bpm == 120 })
        #expect(lt.profile.first?.start == 0.2 && lt.profile.last?.start == 165.2)  // round(0.25, 1) is 0.2, ties to even
        #expect(lt.steadyInS == 0.25 && lt.steadyInBar == 1 && lt.steadyOutS == 180.2 && lt.steadyOutBar == 91)
        #expect(lt.firstDownbeatInS == 0.25 && lt.firstDownbeatOutS == 150.25)
        #expect(lt.flags.isEmpty)

        // The same beats with the grid on them: the windows already sit on the global grid.
        let onGrid = LocalTempo.compute(Self.steadyInput(onGrid: true))
        #expect(onGrid.gridDevInMs == 0 && onGrid.gridDevOutMs == 0)
        #expect(onGrid.inRule == .onGlobalGrid && onGrid.outRule == .onGlobalGrid && onGrid.inTrusted)

        // No detected beats at all: the grid's beats stand in for them, as in the lab.
        var gridOnly = Self.steadyInput(onGrid: true)
        gridOnly.detectedBeats = []
        #expect(LocalTempo.compute(gridOnly) == onGrid)
    }

    @Test func aDriftingBeatIsUntrusted() throws {
        // The tempo ramps from 100 to 140 BPM over three minutes; beat times rounded to the millisecond.
        var beats: [Double] = []
        var t = 1.0
        while t < 181 {
            beats.append(Py.round(t, 3))
            t += 60 / (100 + 40 * (t - 1) / 180)
        }
        let lt = LocalTempo.compute(LocalTempoInput(bpm: 120, duration: 182, detectedBeats: beats, firstDownbeat: 1,
                                                    firstSound: 1, lastSound: beats.last!))
        // Thirty seconds of a changing tempo do not fit one period: the windows exist but miss by tens of ms.
        let first = try #require(lt.first30), last = try #require(lt.last30)
        #expect(first.residMs == 60.3 && first.nBeats == 50)
        #expect(last.residMs == 43.0 && last.nBeats == 65)
        #expect(!LocalTempo.isTrusted(first) && !LocalTempo.isTrusted(last))
        #expect(lt.inRule == .noSteadyBeat && lt.outRule == .noSteadyBeat && !lt.inTrusted && !lt.outTrusted)
        #expect(lt.bpmIn == 120 && lt.bpmOut == 120 && lt.driftPct == 0)  // the global tempo stands in
        // Fifteen seconds are short enough to fit: the trusted segments climb, and the range flags a tempo change.
        #expect(lt.profile[1].bpm == 104.94 && lt.profile[11].bpm == 138.29 && lt.rangePct == 27.79)
        #expect(lt.flags == ["tempo_change", "intro_no_steady_beat", "outro_no_steady_beat"])
    }

    @Test func anEmptyWindowFallsBackToTheGrid() throws {
        // The grid runs from 0 s; the tracker found nothing before 40 s.
        let grid = (0...360).map { 0.5 * Double($0) }
        let det = grid.filter { $0 >= 40 }
        let downs = stride(from: 0, to: det.count, by: 4).map { det[$0] }
        let lt = LocalTempo.compute(LocalTempoInput(
            bpm: 120, duration: 180, detectedBeats: det, detectedDownbeats: downs, gridBeats: grid,
            gridDownbeats: stride(from: 0, to: grid.count, by: 4).map { grid[$0] }, firstDownbeat: 0,
            firstSound: 0, lastSound: 180))
        #expect(lt.first30 == nil && lt.gridDevInMs == nil)
        #expect(lt.bpmIn == 120 && !lt.inTrusted && lt.inRule == .noSteadyBeat)
        #expect(lt.outRule == .onGlobalGrid && lt.outTrusted && lt.gridDevOutMs == 0)
        #expect(lt.profile.map(\.trusted) == [false, false] + Array(repeating: true, count: 10))
        #expect(lt.untrustedSegments == 2)
        // The steady beat starts at the first detected downbeat after the first trusted segment (30 s): bar 21.
        #expect(lt.steadyInS == 40 && lt.steadyInBar == 21)
        #expect(lt.firstDownbeatInS == nil && lt.firstDownbeatOutS == 150)
        #expect(lt.flags == ["intro_no_steady_beat"])

        #expect(LocalTempo.window(det, from: 0, to: 30, reference: 120) == nil)
        #expect(LocalTempo.window(Array(grid[0..<7]), from: 0, to: 30, reference: 120) == nil)  // 7 beats: too few
        #expect(LocalTempo.gridDeviationMs(Array(grid[0..<3]), grid: grid, from: 0, to: 30) == nil)
    }

    @Test func aHalfTimeIntroIsItsOwnTempo() {
        // 60 BPM for 30 s (half of 120), then 124 BPM; the global tempo is 124.
        let beats = (0...30).map { Double($0) } + (1..<300).map { 30 + 60.0 / 124 * Double($0) }
        let lt = LocalTempo.compute(LocalTempoInput(bpm: 124, duration: beats.last! + 1, detectedBeats: beats,
                                                    firstDownbeat: 0, firstSound: 0, lastSound: beats.last!))
        #expect(lt.first30?.bpmRaw == 60 && lt.first30?.mult == 2 && lt.first30?.bpm == 120)
        #expect(lt.bpmIn == 120 && lt.inRule == .localDiffers && lt.inHalfTime)
        #expect(lt.bpmOut == 124 && lt.outRule == .localMatches && !lt.outHalfTime)
        #expect(lt.driftPct == 3.33 && lt.rangePct == 3.23 && lt.tempoChange && !lt.transitionTrack)
        #expect(lt.flags == ["tempo_change", "intro_half_time"])
    }
}
