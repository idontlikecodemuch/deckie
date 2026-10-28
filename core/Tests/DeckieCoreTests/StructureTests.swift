import Testing
import Foundation
import DeckieCore
import DeckieLab

// Parity of the structure port (Sources/DeckieCore/Structure) with the lab: every port runs on the inputs a committed
// feature file holds and is compared with the outputs the same file holds, for all 373 tracks.
//
// The files are rounded (times to 3 or 4 decimals, the grid period to 5, loudness to 2, probabilities to 3 or 4,
// novelty to 3), so each tolerance below is the one that rounding allows, worked out per value. Where the lab compared
// a value with a threshold and the written value sits within its rounding of that threshold, the comparison may have
// gone the other way in the lab; such a disagreement counts as explained only when the port, run again with that input
// moved within its rounding, gives the lab's result. Every disagreement is printed with both values; fewer than 1
// percent of tracks per field may disagree, and only when explained.

// Helpers, nested in the suite so their names stay out of the test target's namespace.
extension StructureTests {
    typealias LabStructure = FeatureFile.Structure

    /// A disagreement between the port and a feature file.
    struct Finding {
        var field: String
        var id: String
        var detail: String
        /// How rounding of an input explains it, or nil.
        var explanation: String?
    }

    /// Per-field counts and findings over the tracks.
    struct Tally {
        var order: [String] = []
        var checked: [String: Int] = [:]
        var findings: [Finding] = []
        var largest: [String: (Double, String)] = [:]
        var notes: [String: [String]] = [:]

        /// Records one comparison; on a disagreement asks `explain` whether rounding of an input accounts for it.
        mutating func check(_ field: String, _ id: String, _ ok: Bool, _ detail: @autoclosure () -> String,
                            explain: () -> String? = { nil }) {
            if checked[field] == nil { order.append(field) }
            checked[field, default: 0] += 1
            if !ok { findings.append(Finding(field: field, id: id, detail: detail(), explanation: explain())) }
        }

        /// Keeps the largest difference seen for a value field.
        mutating func difference(_ field: String, _ id: String, _ d: Double) {
            if d > (largest[field]?.0 ?? -1) { largest[field] = (d, id) }
        }

        /// Lists a value that is within its rounding bound but beyond a flat 0.0015.
        mutating func note(_ field: String, _ text: String) { notes[field, default: []].append(text) }

        /// Prints every field's result and every disagreement, and fails on any unexplained one or on 1 percent or more
        /// of the tracks disagreeing in a field.
        func report() {
            for field in order {
                let n = checked[field] ?? 0
                let fs = findings.filter { $0.field == field }
                var line = "\(field): \(n - fs.count) of \(n) match"
                if let (d, id) = largest[field] { line += "; largest difference \(Py.fixed(d, 6)) (\(id))" }
                print(line)
                if let ns = notes[field] {
                    print("    \(ns.count) beyond a flat 0.0015, each within what its inputs' rounding allows:")
                    for text in ns { print("      \(text)") }
                }
                for f in fs {
                    if let why = f.explanation {
                        print("    \(f.id): \(f.detail). Explained: \(why)")
                    } else {
                        print("    \(f.id): \(f.detail). NOT EXPLAINED by rounding")
                    }
                }
                let unexplained = fs.filter { $0.explanation == nil }
                #expect(unexplained.isEmpty, "\(field): \(unexplained.count) disagreements not explained by rounding")
                #expect(fs.count * 100 < max(n, 1), "\(field): \(fs.count) of \(n) tracks disagree (1 percent or more)")
            }
        }
    }

    /// Inputs worked out from a feature file.
    enum Lab {
        /// The grid period as closely as the file pins it: the overlap of what `grid.beat_s` (5 decimals), `grid.bar_s`
        /// (5 decimals, four beats) and `grid.bpm` (3 decimals) allow. Returns its middle and half its width.
        static func period(_ g: LabStructure.Grid) -> (p: Double, halfWidth: Double) {
            var lo = g.beatS - 5e-6, hi = g.beatS + 5e-6
            lo = max(lo, (g.barS - 5e-6) / 4)
            hi = min(hi, (g.barS + 5e-6) / 4)
            lo = max(lo, 60 / (g.bpm + 5e-4))
            hi = min(hi, 60 / (g.bpm - 5e-4))
            precondition(lo <= hi, "grid fields disagree on the period")
            return ((lo + hi) / 2, (hi - lo) / 2)
        }

        /// The lab's bar grid rebuilt from the written bar 1, period and bar count.
        static func grid(_ d: LabStructure) -> BarGrid {
            BarGrid(firstDownbeatS: d.grid.firstDownbeatS, beatS: period(d.grid).p, nBars: d.grid.nBars)
        }

        /// How far a rebuilt grid time `beats` beats from bar 1 may sit from the written one: half a millisecond of
        /// rounding in the written time, 0.05 ms in the written bar 1, and the period's uncertainty over that many beats.
        static func timeTolerance(_ d: LabStructure, beats: Int) -> Double {
            0.0005 + 0.00005 + Double(abs(beats)) * period(d.grid).halfWidth + 1e-9
        }

        /// Bars whose written vocal probability is exactly 0.5: the lab's value lies within 0.0005 of the 0.5 threshold,
        /// on either side.
        static func vocalAtThreshold(_ d: LabStructure) -> [Int] {
            d.perBar.vocalProb.indices.filter { d.perBar.vocalProb[$0] == 0.5 }
        }
    }
}

@Suite struct StructureTests {
    static let tracks: [LabStructure] = {
        let files = try! FileManager.default.contentsOfDirectory(atPath: RepoPaths.features.path)
            .filter { $0.hasSuffix(".json") }.sorted()
        return files.map { try! LabStructure.load(RepoPaths.features.appendingPathComponent($0)) }
    }()

    // MARK: per-stage checks (each port fed the file's own inputs)

    static func checkBars(_ d: LabStructure, _ t: inout Tally) {
        let (P, _) = Lab.period(d.grid)
        let fd0 = d.grid.firstDownbeatS
        // Bar 1 from any downbeat of the grid: the written bar 1 itself, and moved 5 bars later and 3 bars earlier.
        var firsts: [Double] = []
        for shift in [0, 5, -3] {
            let downbeat = fd0 + Double(shift) * 4 * P
            firsts.append(BarGrid.firstBar(gridDownbeat: downbeat, beatS: P, firstSound: d.firstSoundS))
        }
        let worst = firsts.map { abs($0 - fd0) }.max()!
        t.difference("bar 1 time", d.id, worst)
        t.check("bar 1 time", d.id, worst <= 1e-4, "bar 1 at \(firsts) s, lab \(fd0) s")
        let g = BarGrid(gridDownbeat: fd0, beatS: P, firstSound: d.firstSoundS, duration: d.durationS)
        t.check("n_bars", d.id, g?.nBars == d.grid.nBars, "\(g?.nBars ?? -1) bars, lab \(d.grid.nBars)") {
            // The duration is written to 3 decimals.
            for dur in [d.durationS - 0.0005, d.durationS + 0.0005]
            where BarGrid.barCount(firstBar: fd0, beatS: P, duration: dur) == d.grid.nBars {
                return "a duration of \(dur) s, within the rounding of the written \(d.durationS), gives the lab's count"
            }
            return nil
        }
        guard let g else { return }
        // Bar lines (downbeats_s) and grid beats (beats_s), rounded to 1 ms in the file.
        var barsOK = g.barTimes.count == d.downbeatsS.count
        var worstBar = 0.0
        if barsOK {
            for k in g.barTimes.indices {
                let dev = abs(g.barTimes[k] - d.downbeatsS[k])
                worstBar = max(worstBar, dev)
                if dev > Lab.timeTolerance(d, beats: 4 * k) { barsOK = false }
            }
        }
        t.difference("downbeats_s", d.id, worstBar)
        t.check("downbeats_s", d.id, barsOK,
                "\(g.barTimes.count) bar lines, lab \(d.downbeatsS.count); largest gap \(worstBar) s")
        let pre = g.beatTimes.count - g.gridBeats.count
        var beatsOK = g.beatTimes.count == d.beatsS.count
        var worstBeat = 0.0
        if beatsOK {
            for i in g.beatTimes.indices {
                let dev = abs(g.beatTimes[i] - d.beatsS[i])
                worstBeat = max(worstBeat, dev)
                if dev > Lab.timeTolerance(d, beats: i - pre) { beatsOK = false }
            }
        }
        t.difference("beats_s", d.id, worstBeat)
        t.check("beats_s", d.id, beatsOK,
                "\(g.beatTimes.count) beats (\(pre) before bar 1), lab \(d.beatsS.count); largest gap \(worstBeat) s")
    }

    /// Half the rounding of each phase's summed novelty: 0.0005 for every written peak value in it.
    static func phaseHalfWidths(_ peaks: [NoveltyPeak]) -> [Double] {
        var w = [Double](repeating: 0, count: 8)
        for p in peaks { w[Py.mod(p.bar - 1, 8)] += 0.0005 }
        return w
    }

    /// The lowest and highest phrase confidence the port gives at a set of points inside the box of phase sums
    /// `sums[i] +- halfWidths[i]` (kept at or above 0): the corners that favour or penalise each phase, and the
    /// points where two phases tie. The confidence is continuous, so every value between the two is reached by some
    /// sums inside the box.
    static func confidenceRange(sums: [Double], halfWidths w: [Double]) -> (lo: Double, hi: Double) {
        let a = sums.indices.map { max(0, sums[$0] - w[$0]) }, b = sums.indices.map { sums[$0] + w[$0] }
        var points: [[Double]] = [sums]
        for p in 0..<8 {
            points.append(sums.indices.map { $0 == p ? b[$0] : a[$0] })
            points.append(sums.indices.map { $0 == p ? a[$0] : b[$0] })
            for q in (p + 1)..<8 {
                let lo = max(a[p], a[q]), hi = min(b[p], b[q])
                if lo > hi { continue }
                for x in [lo, hi] {
                    points.append(sums.indices.map { $0 == p || $0 == q ? x : min(max(x, a[$0]), b[$0]) })
                }
            }
        }
        let c = points.map { Phrase(phaseNovelty: $0).confidence }
        return (c.min()!, c.max()!)
    }

    static func checkPhrase(_ d: LabStructure, _ t: inout Tally) {
        let peaks = d.peaks
        let ph = Phrase(peaks: peaks)
        let lab = d.phrase
        let w = phaseHalfWidths(peaks)
        let sums = ph.phaseNovelty
        t.check("lattice_phase_bar", d.id, ph.latticePhaseBar == lab.latticePhaseBar,
                "bar \(ph.latticePhaseBar), lab bar \(lab.latticePhaseBar)") {
            let l = lab.latticePhaseBar - 1
            let reachable = sums.indices.allSatisfy { $0 == l || sums[l] + w[l] >= sums[$0] - w[$0] }
            return reachable ? "phase \(lab.latticePhaseBar) can lead within the rounding of the peaks" : nil
        }
        // Each phase sum within its peaks' rounding plus the rounding of the written sum.
        var pnOK = true, worst = 0.0
        for i in 0..<8 {
            let dev = abs(sums[i] - lab.phaseNovelty[i])
            worst = max(worst, dev)
            if dev > w[i] + 0.0005 + 1e-9 { pnOK = false }
        }
        t.difference("phase_novelty", d.id, worst)
        t.check("phase_novelty", d.id, pnOK, "\(sums.map { Py.fixed($0, 4) }), lab \(lab.phaseNovelty)")
        if worst > 0.0015 {
            let i = (0..<8).max { abs(sums[$0] - lab.phaseNovelty[$0]) < abs(sums[$1] - lab.phaseNovelty[$1]) }!
            let n = Int((w[i] / 0.0005).rounded())
            t.note("phase_novelty", "\(d.id): phase \(i + 1) differs by \(Py.fixed(worst, 4)); it adds \(n) rounded "
                   + "peaks, so rounding allows \(Py.fixed(w[i] + 0.0005, 4))")
        }
        // Confidence: the written value within its own rounding of a value the port reaches inside the box.
        let r = confidenceRange(sums: sums, halfWidths: w)
        let dev = abs(ph.confidence - lab.confidence)
        t.difference("phrase confidence", d.id, dev)
        t.check("phrase confidence", d.id,
                lab.confidence >= r.lo - 0.0005 - 1e-9 && lab.confidence <= r.hi + 0.0005 + 1e-9,
                "\(Py.fixed(ph.confidence, 5)), lab \(lab.confidence); reachable \(Py.fixed(r.lo, 5))...\(Py.fixed(r.hi, 5))")
        if dev > 0.0015 {
            t.note("phrase confidence", "\(d.id): \(Py.fixed(ph.confidence, 5)) from the rounded peaks, lab "
                   + "\(lab.confidence); the \(peaks.count) peaks' rounding (0.0005 each) reaches "
                   + "\(Py.fixed(r.lo, 5)) to \(Py.fixed(r.hi, 5))")
        }
        // The confidence formula alone, from the written phase sums (each rounded to 3 decimals).
        let fromSums = Phrase(phaseNovelty: lab.phaseNovelty)
        let r2 = confidenceRange(sums: lab.phaseNovelty, halfWidths: [Double](repeating: 0.0005, count: 8))
        t.difference("phrase confidence from phase_novelty", d.id, abs(fromSums.confidence - lab.confidence))
        if abs(fromSums.confidence - lab.confidence) > 0.0015 {
            t.note("phrase confidence from phase_novelty", "\(d.id): \(Py.fixed(fromSums.confidence, 5)), lab "
                   + "\(lab.confidence); the sums' rounding reaches \(Py.fixed(r2.lo, 5)) to \(Py.fixed(r2.hi, 5))")
        }
        t.check("phrase confidence from phase_novelty", d.id,
                lab.confidence >= r2.lo - 0.0005 - 1e-9 && lab.confidence <= r2.hi + 0.0005 + 1e-9,
                "\(Py.fixed(fromSums.confidence, 5)), lab \(lab.confidence); reachable \(Py.fixed(r2.lo, 5))...\(Py.fixed(r2.hi, 5))")
        t.check("snap_phase_bar", d.id, ph.snapPhaseBar == lab.snapPhaseBar,
                "bar \(ph.snapPhaseBar) (confidence \(ph.confidence)), lab bar \(lab.snapPhaseBar)") {
            (r.lo < Phrase.snapConfidence && r.hi >= Phrase.snapConfidence)
                ? "the confidence reachable within the peaks' rounding, \(r.lo)...\(r.hi), spans 0.35" : nil
        }
        let b = Phrase.boundaries(peaks: peaks, latticePhaseBar: ph.latticePhaseBar, nBars: d.grid.nBars)
        t.check("boundaries_bars", d.id, b == d.boundariesBars, "\(b), lab \(d.boundariesBars)") {
            Phrase.boundaries(peaks: peaks, latticePhaseBar: lab.latticePhaseBar, nBars: d.grid.nBars) == d.boundariesBars
                ? "follows from the lattice phase above" : nil
        }
    }

    static func checkSections(_ d: LabStructure, _ t: inout Tally) {
        let lufs = d.perBar.lufsSt
        let s = Section.sections(boundariesBars: d.boundariesBars, lufsSt: lufs, vocalProb: d.perBar.vocalProb)
        let lab = d.sections
        let same = s.count == lab.count && zip(s, lab).allSatisfy {
            ($0.startBar, $0.endBar, $0.label, $0.energy) == ($1.startBar, $1.endBar, $1.label, $1.energy)
        }
        let mine = s.map { "\($0.startBar)-\($0.endBar) \($0.label)/\($0.energy)" }
        let theirs = lab.map { "\($0.startBar)-\($0.endBar) \($0.label)/\($0.energy)" }
        t.check("sections", d.id, same, "\(mine), lab \(theirs)") {
            // Energy compares a mean of bar loudness (2 decimals) with the median less 1.5 LU: 0.01 LU of rounding.
            guard s.count == lab.count else { return nil }
            let body = Py.median(lufs)
            var why: [String] = []
            for (x, y) in zip(s, lab) where x.energy != y.energy || x.label != y.label {
                let margin = x.lufs - (body - Section.highEnergyMargin)
                if abs(margin) > 0.01 || x.startBar != y.startBar || x.endBar != y.endBar { return nil }
                why.append("bars \(x.startBar)-\(x.endBar) sit \(Py.fixed(margin, 4)) LU from the high-energy line")
            }
            return why.isEmpty ? nil : why.joined(separator: "; ")
        }
        guard same else { return }
        // Means of values rounded to 2 (loudness) or 3 (vocal) decimals, then rounded again when written.
        let dl = zip(s, lab).map { abs($0.lufs - $1.lufs) }.max() ?? 0
        let dv = zip(s, lab).map { abs($0.vocal - $1.vocal) }.max() ?? 0
        t.difference("sections lufs", d.id, dl)
        t.check("sections lufs", d.id, dl <= 0.01 + 1e-9, "largest difference \(dl) LU")
        t.difference("sections vocal", d.id, dv)
        t.check("sections vocal", d.id, dv <= 0.001 + 1e-9, "largest difference \(dv)")
    }

    static func checkFade(_ d: LabStructure, _ t: inout Tally) {
        let g = Lab.grid(d)
        let f = FadeOut(endLoudness: d.endLoudness, lufsSt: d.perBar.lufsSt, grid: g, firstSound: d.firstSoundS,
                        lastSound: d.lastSoundS)
        // The drop is the difference of two values written to 2 decimals, then written to 2 decimals itself.
        t.difference("fade_drop_lu", d.id, abs(f.fadeDropLu - d.fadeDropLu))
        t.check("fade_drop_lu", d.id, abs(f.fadeDropLu - d.fadeDropLu) <= 0.015 + 1e-9,
                "\(f.fadeDropLu), lab \(d.fadeDropLu)")
        // The tail is written to 2 decimals; the bar line it starts from is known to 0.05 ms plus the period's
        // uncertainty over the beats before it, and the bar length to four times the period's.
        let h = Lab.period(d.grid).halfWidth
        let tailTol = 0.005 + (0.00005 + Double(4 * f.lastBodyBar) * h) / g.barS + abs(f.tailBars) * 4 * h / g.barS
            + 1e-9
        t.difference("tail_bars", d.id, abs(f.tailBars - d.tailBars))
        t.check("tail_bars", d.id, abs(f.tailBars - d.tailBars) <= tailTol, "\(f.tailBars), lab \(d.tailBars)") {
            Self.bodyBarNearLine(d).map { "the last body-level bar may differ: \($0)" }
        }
        t.check("fade_out", d.id, f.fadeOut == d.fadeOut,
                "\(f.fadeOut) (drop \(f.fadeDropLu), tail \(f.tailBars)), lab \(d.fadeOut)") {
            if abs(f.fadeDropLu - FadeOut.minDrop) <= 0.01 {
                return "the drop, \(f.fadeDropLu) LU, is within 0.01 LU of 6"
            }
            if abs(f.tailBars - FadeOut.minTailBars) <= tailTol {
                return "the tail, \(f.tailBars) bars, is within its rounding of 3"
            }
            return Self.bodyBarNearLine(d).map { "the last body-level bar may differ: \($0)" }
        }
        t.check("fade_start_bar", d.id, f.fadeStartBar == d.fadeStartBar,
                "\(f.fadeStartBar.map(String.init) ?? "none"), lab \(d.fadeStartBar.map(String.init) ?? "none")") {
            if f.fadeOut != d.fadeOut { return "follows from fade_out" }
            return Self.bodyBarNearLine(d).map { "the last body-level bar may differ: \($0)" }
        }
    }

    /// A bar whose loudness (2 decimals) lies within 0.01 LU of the body-level line (median - 2 LU), which can move
    /// the last body-level bar.
    static func bodyBarNearLine(_ d: LabStructure) -> String? {
        let lufs = d.perBar.lufsSt
        let line = Py.median(lufs) - FadeOut.bodyMargin
        guard let i = lufs.indices.last(where: { abs(lufs[$0] - line) <= 0.01 }) else { return nil }
        return "bar \(i + 1) is \(Py.fixed(lufs[i] - line, 4)) LU from the line"
    }

    static func mixWindows(_ d: LabStructure, vocal: [Double]) -> (mixIn: MixIn, mixOut: MixOut) {
        MixWindows.windows(grid: Lab.grid(d), vocalProb: vocal, boundariesBars: d.boundariesBars,
                           snapPhaseBar: d.phrase.snapPhaseBar, lastSound: d.lastSoundS, fadeOut: d.fadeOut,
                           fadeStartBar: d.fadeStartBar)
    }

    /// Runs the windows again with every bar written as exactly 0.5 moved just below the threshold (0.4996, inside the
    /// rounding of 0.5); when `same` then holds, rounding of those bars explains the difference.
    static func vocalExplanation(_ d: LabStructure, _ same: ((mixIn: MixIn, mixOut: MixOut)) -> Bool) -> String? {
        let at = Lab.vocalAtThreshold(d)
        guard !at.isEmpty else { return nil }
        var v = d.perBar.vocalProb
        for i in at { v[i] = 0.4996 }
        guard same(mixWindows(d, vocal: v)) else { return nil }
        return "bar \(at.map { String($0 + 1) }.joined(separator: ", ")) is written as 0.5; the lab's value was below 0.5 "
            + "(by less than 0.0005), and with it below 0.5 the port gives the lab's result"
    }

    static func checkMixWindows(_ d: LabStructure, _ t: inout Tally) {
        let (mi, mo) = mixWindows(d, vocal: d.perBar.vocalProb)
        let li = d.mixIn, lo = d.mixOut
        func inBars(_ m: MixIn) -> Bool { (m.startBar, m.endBar, m.bars) == (li.startBar, li.endBar, li.bars) }
        func outBars(_ m: MixOut) -> Bool { (m.startBar, m.endBar, m.bars) == (lo.startBar, lo.endBar, lo.bars) }
        t.check("mix_in bars", d.id, inBars(mi),
                "\(mi.startBar)-\(mi.endBar) (\(mi.bars)), lab \(li.startBar)-\(li.endBar) (\(li.bars))") {
            vocalExplanation(d) { inBars($0.mixIn) }
        }
        t.check("mix_in vocal_free_bars", d.id, mi.vocalFreeBars == li.vocalFreeBars,
                "\(mi.vocalFreeBars), lab \(li.vocalFreeBars)") {
            vocalExplanation(d) { $0.mixIn.vocalFreeBars == li.vocalFreeBars }
        }
        t.check("mix_in first_vocal_bar", d.id, mi.firstVocalBar == li.firstVocalBar,
                "\(mi.firstVocalBar.map(String.init) ?? "none"), lab \(li.firstVocalBar.map(String.init) ?? "none")") {
            vocalExplanation(d) { $0.mixIn.firstVocalBar == li.firstVocalBar }
        }
        t.check("mix_out bars", d.id, outBars(mo),
                "\(mo.startBar)-\(mo.endBar) (\(mo.bars)), lab \(lo.startBar)-\(lo.endBar) (\(lo.bars))") {
            vocalExplanation(d) { outBars($0.mixOut) }
        }
        t.check("mix_out vocal_free_bars", d.id, mo.vocalFreeBars == lo.vocalFreeBars,
                "\(mo.vocalFreeBars), lab \(lo.vocalFreeBars)") {
            vocalExplanation(d) { $0.mixOut.vocalFreeBars == lo.vocalFreeBars }
        }
        t.check("mix_out last_vocal_bar", d.id, mo.lastVocalBar == lo.lastVocalBar,
                "\(mo.lastVocalBar.map(String.init) ?? "none"), lab \(lo.lastVocalBar.map(String.init) ?? "none")") {
            vocalExplanation(d) { $0.mixOut.lastVocalBar == lo.lastVocalBar }
        }
        t.check("mix_out fade_out", d.id, mo.fadeOut == lo.fadeOut, "\(mo.fadeOut), lab \(lo.fadeOut)")
        // Seconds: bar line times, written to 3 decimals. Checked where the bars agree.
        if inBars(mi) {
            let dev = max(abs(mi.startS - li.startS), abs(mi.endS - li.endS))
            t.difference("mix_in seconds", d.id, dev)
            t.check("mix_in seconds", d.id, abs(mi.startS - li.startS) <= Lab.timeTolerance(d, beats: 4 * (mi.startBar - 1))
                    && abs(mi.endS - li.endS) <= Lab.timeTolerance(d, beats: 4 * (mi.endBar - 1)),
                    "\(mi.startS)-\(mi.endS) s, lab \(li.startS)-\(li.endS) s")
        }
        if outBars(mo) {
            let dev = max(abs(mo.startS - lo.startS), abs(mo.endS - lo.endS))
            t.difference("mix_out seconds", d.id, dev)
            t.check("mix_out seconds", d.id, abs(mo.startS - lo.startS) <= Lab.timeTolerance(d, beats: 4 * (mo.startBar - 1))
                    && abs(mo.endS - lo.endS) <= Lab.timeTolerance(d, beats: 4 * (mo.endBar - 1)),
                    "\(mo.startS)-\(mo.endS) s, lab \(lo.startS)-\(lo.endS) s")
        }
    }

    static func flags(_ d: LabStructure, bpm: Double? = nil, meanProb: Double? = nil, gridConf: Double? = nil)
        -> [String] {
        TrackFlags.flags(bpm: bpm ?? d.bpm, bpmTag: d.bpmTag, vocalMeanProb: meanProb ?? d.vocal.meanProb,
                         fadeOut: d.fadeOut, gridConfidence: gridConf ?? d.grid.confidence,
                         keyConfidence: d.key.confidence, mixIn: d.mixInValue, mixOut: d.mixOutValue,
                         localTempoFlags: d.localTempo?.names ?? [])
    }

    static func checkFlags(_ d: LabStructure, _ t: inout Tally) {
        let f = flags(d)
        t.check("flags", d.id, f == d.flags, "\(f), lab \(d.flags)") {
            // Inputs compared with a threshold and written rounded: bpm (3 decimals) with 100, the mean vocal
            // probability (4) with 0.75, the grid confidence (3) with 0.5. Each is moved within its rounding.
            var tries: [(String, [String])] = []
            if abs(d.bpm - 100) <= 0.0005 {
                for b in [d.bpm - 0.0004, d.bpm + 0.0004] { tries.append(("bpm \(b) (written \(d.bpm))", flags(d, bpm: b))) }
            }
            if abs(d.vocal.meanProb - 0.75) <= 0.00005 {
                for m in [d.vocal.meanProb - 0.00004, d.vocal.meanProb + 0.00004] {
                    tries.append(("mean vocal probability \(m) (written \(d.vocal.meanProb))", flags(d, meanProb: m)))
                }
            }
            if abs(d.grid.confidence - 0.5) <= 0.0005 {
                for c in [d.grid.confidence - 0.0004, d.grid.confidence + 0.0004] {
                    tries.append(("grid confidence \(c) (written \(d.grid.confidence))", flags(d, gridConf: c)))
                }
            }
            guard let hit = tries.first(where: { $0.1 == d.flags }) else { return nil }
            var why = "with \(hit.0), within its rounding, the port gives the lab's flags"
            let url = RepoPaths.features.appendingPathComponent("\(d.id).json")
            if hit.0.hasPrefix("bpm"), let full = try? FeatureFile.load(url),
               let g = BeatGrid.fit(beats: full.detectedBeatsS, downbeats: full.detectedDownbeatsS ?? []) {
                why += "; the ported grid fit on this track's detected beats gives \(String(format: "%.17g", g.bpm)) BPM"
            }
            return why
        }
        if let tag = d.bpmTag, tag != 0 {
            let m = Tempo.closest(bpm: d.bpm, reference: tag).multiplier
            t.check("multiplier_vs_tag", d.id, abs(m - d.multiplierVsTagValue) <= 0.00005,
                    "\(m), lab \(d.multiplierVsTagValue)")
        } else {
            t.check("multiplier_vs_tag", d.id, d.multiplierVsTagValue == 1, "no tag, lab \(d.multiplierVsTagValue)")
        }
    }

    // MARK: the 373 tracks

    @Test func barGridMatchesTheLab() {
        var t = Tally()
        for d in Self.tracks { Self.checkBars(d, &t) }
        t.report()
        #expect(Self.tracks.count == 373)
    }

    @Test func phraseLatticeMatchesTheLab() {
        var t = Tally()
        for d in Self.tracks { Self.checkPhrase(d, &t) }
        t.report()
    }

    @Test func sectionsMatchTheLab() {
        var t = Tally()
        for d in Self.tracks { Self.checkSections(d, &t) }
        t.report()
    }

    @Test func fadeOutMatchesTheLab() {
        var t = Tally()
        for d in Self.tracks { Self.checkFade(d, &t) }
        t.report()
    }

    @Test func mixWindowsMatchTheLab() {
        var t = Tally()
        for d in Self.tracks { Self.checkMixWindows(d, &t) }
        t.report()
    }

    @Test func flagsMatchTheLab() {
        var t = Tally()
        for d in Self.tracks { Self.checkFlags(d, &t) }
        t.report()
    }

    /// The ports chained as the lab chains them, from the raw inputs only (grid, first and last sound, duration,
    /// novelty peaks, per-bar loudness and vocal probability, end loudness, and the flag inputs), compared on bar
    /// numbers, labels and decisions. Every track whose chained result differs from the file must be one where the
    /// per-stage checks found disagreements, all explained by rounding.
    @Test func chainedPortsMatchTheLab() throws {
        var allMatch = 0
        var differing: [String] = []
        for d in Self.tracks {
            let (P, _) = Lab.period(d.grid)
            let g = try #require(BarGrid(gridDownbeat: d.grid.firstDownbeatS, beatS: P, firstSound: d.firstSoundS,
                                         duration: d.durationS))
            let ph = Phrase(peaks: d.peaks)
            let b = Phrase.boundaries(peaks: d.peaks, latticePhaseBar: ph.latticePhaseBar, nBars: g.nBars)
            let secs = Section.sections(boundariesBars: b, lufsSt: d.perBar.lufsSt, vocalProb: d.perBar.vocalProb)
            let fade = FadeOut(endLoudness: d.endLoudness, lufsSt: d.perBar.lufsSt, grid: g, firstSound: d.firstSoundS,
                               lastSound: d.lastSoundS)
            let (mi, mo) = MixWindows.windows(grid: g, vocalProb: d.perBar.vocalProb, boundariesBars: b,
                                              snapPhaseBar: ph.snapPhaseBar, lastSound: d.lastSoundS,
                                              fadeOut: fade.fadeOut, fadeStartBar: fade.fadeStartBar)
            let flags = TrackFlags.flags(bpm: d.bpm, bpmTag: d.bpmTag, vocalMeanProb: d.vocal.meanProb,
                                         fadeOut: fade.fadeOut, gridConfidence: d.grid.confidence,
                                         keyConfidence: d.key.confidence, mixIn: mi, mixOut: mo,
                                         localTempoFlags: d.localTempo?.names ?? [])
            let li = d.mixIn, lo = d.mixOut
            let same = g.nBars == d.grid.nBars && abs(g.firstDownbeatS - d.grid.firstDownbeatS) <= 1e-4
                && ph.latticePhaseBar == d.phrase.latticePhaseBar && ph.snapPhaseBar == d.phrase.snapPhaseBar
                && b == d.boundariesBars
                && secs.map { "\($0.startBar) \($0.endBar) \($0.label) \($0.energy)" }
                    == d.sections.map { "\($0.startBar) \($0.endBar) \($0.label) \($0.energy)" }
                && fade.fadeOut == d.fadeOut && fade.fadeStartBar == d.fadeStartBar
                && (mi.startBar, mi.endBar, mi.bars, mi.vocalFreeBars) == (li.startBar, li.endBar, li.bars, li.vocalFreeBars)
                && mi.firstVocalBar == li.firstVocalBar
                && (mo.startBar, mo.endBar, mo.bars, mo.vocalFreeBars) == (lo.startBar, lo.endBar, lo.bars, lo.vocalFreeBars)
                && mo.lastVocalBar == lo.lastVocalBar && flags == d.flags
            if same { allMatch += 1; continue }
            differing.append(d.id)
            var t = Tally()
            Self.checkBars(d, &t); Self.checkPhrase(d, &t); Self.checkSections(d, &t)
            Self.checkFade(d, &t); Self.checkMixWindows(d, &t); Self.checkFlags(d, &t)
            #expect(!t.findings.isEmpty && t.findings.allSatisfy { $0.explanation != nil },
                    "\(d.id): the chained ports differ from the file and no stage explains it")
        }
        print("chained ports: \(allMatch) of \(Self.tracks.count) tracks match the file on every bar number, label and "
              + "decision; the rest (\(differing.joined(separator: ", "))) are rounding cases explained above")
    }

    // MARK: small functions, by hand

    @Test func pickLenFollowsTheLabsRule() {
        #expect(MixWindows.pickLen(available: 40, vocalFree: 20) == 32)
        #expect(MixWindows.pickLen(available: 32, vocalFree: 16) == 32)
        #expect(MixWindows.pickLen(available: 40, vocalFree: 15) == 16)   // too few vocal-free bars for 32
        #expect(MixWindows.pickLen(available: 31, vocalFree: 31) == 16)   // 32 do not fit
        #expect(MixWindows.pickLen(available: 16, vocalFree: 0) == 16)
        #expect(MixWindows.pickLen(available: 15, vocalFree: 15) == 8)
        #expect(MixWindows.pickLen(available: 8, vocalFree: 8) == 8)
    }

    @Test func latticeAndSnapping() {
        // Phrases from bar 3: bars 3, 11, 19; the end line of 18 bars is bar 19.
        #expect(MixWindows.lattice(snapPhaseBar: 3, nBars: 18) == [3, 11, 19])
        #expect(MixWindows.lattice(snapPhaseBar: 3, nBars: 17) == [3, 11])
        #expect(MixWindows.lattice(snapPhaseBar: 1, nBars: 16) == [1, 9, 17])
        #expect(MixWindows.isOnLattice(11, snapPhaseBar: 3))
        #expect(!MixWindows.isOnLattice(1, snapPhaseBar: 3))
        // Mix-in from bar 1. On the lattice: kept (16 bars end at bar 17 with phrases from bar 1).
        #expect(MixWindows.snapMixInEnd(length: 16, available: 16, snapPhaseBar: 1, nBars: 100) == 17)
        // Phrases from bar 5 (lines 4, 12, 20, ...): 16 bars would end on line 16; within lines 8...16 the nearest
        // is 12, so the window ends at bar 13.
        #expect(MixWindows.snapMixInEnd(length: 16, available: 16, snapPhaseBar: 5, nBars: 100) == 13)
        // With 20 available, lines 12 and 20 are both 4 away: the earlier wins.
        #expect(MixWindows.snapMixInEnd(length: 16, available: 20, snapPhaseBar: 5, nBars: 100) == 13)
        // Phrases from bar 7 (lines 6, 14, 22): 16 bars, 24 available: line 14 (2 away) beats 22 (6 away).
        #expect(MixWindows.snapMixInEnd(length: 16, available: 24, snapPhaseBar: 7, nBars: 100) == 15)
        // 32 bars of 40 available, phrases from bar 3 (lines 2, 10, ..., 34): line 34 is nearer than 26.
        #expect(MixWindows.snapMixInEnd(length: 32, available: 40, snapPhaseBar: 3, nBars: 100) == 35)
        // 8 bars of 8 with phrases from bar 4 (lines 3, 11): no line within 8...8, so line 8 stays.
        #expect(MixWindows.snapMixInEnd(length: 8, available: 8, snapPhaseBar: 4, nBars: 100) == 9)
        // Mix-out, no fade: 98 full bars of 100, phrases from bar 1: line 96 is within 4 bars, so the end is bar 97.
        #expect(MixWindows.mixOutEnd(fullBars: 98, nBars: 100, snapPhaseBar: 1, fadeStartBar: nil) == 97)
        // Phrases from bar 3 put a line at 98 itself.
        #expect(MixWindows.mixOutEnd(fullBars: 98, nBars: 100, snapPhaseBar: 3, fadeStartBar: nil) == 99)
        // 93 full bars: lines 88 and 96 are both out of 89...93, so the end stays at line 93.
        #expect(MixWindows.mixOutEnd(fullBars: 93, nBars: 100, snapPhaseBar: 1, fadeStartBar: nil) == 94)
        // More full bars than bars (a last sound past the grid): the usable end is the last bar.
        #expect(MixWindows.mixOutEnd(fullBars: 101, nBars: 100, snapPhaseBar: 1, fadeStartBar: nil) == 97)
        // Never before line 8.
        #expect(MixWindows.mixOutEnd(fullBars: 5, nBars: 30, snapPhaseBar: 1, fadeStartBar: nil) == 9)
        // A fade starting at bar 90 (line 89): the last lattice line from 16 up to it is 88.
        #expect(MixWindows.mixOutEnd(fullBars: 98, nBars: 100, snapPhaseBar: 1, fadeStartBar: 90) == 89)
        // A fade starting at bar 15 (line 14): no lattice line in 16...14, so max(16, min(14, 98)) = line 16.
        #expect(MixWindows.mixOutEnd(fullBars: 98, nBars: 100, snapPhaseBar: 1, fadeStartBar: 15) == 17)
    }

    @Test func phraseFromHandMadePeaks() {
        // Peaks at bars 11 and 19 (phase 3) and bar 6 (phase 6): sums 1.0 and 0.5 of 1.5; share 2/3, margin 0.5,
        // confidence 0.6 * 2/3 + 0.4 * 0.5 = 0.6.
        let peaks = [NoveltyPeak(bar: 11, value: 0.6), NoveltyPeak(bar: 19, value: 0.4), NoveltyPeak(bar: 6, value: 0.5)]
        let p = Phrase(peaks: peaks)
        #expect(p.latticePhaseBar == 3 && p.snapPhaseBar == 3 && p.phraseLenBars == 8)
        #expect(near(p.phaseNovelty[2], 1.0, 1e-12) && near(p.phaseNovelty[5], 0.5, 1e-12))
        #expect(near(p.confidence, 0.6, 1e-8))
        #expect(Phrase.onLatticeBars(peaks: peaks, latticePhaseBar: 3) == [11, 19])
        #expect(Phrase.boundaries(peaks: peaks, latticePhaseBar: 3, nBars: 24) == [1, 11, 19, 25])
        // Two phases tied: the first wins, the margin is 0, the confidence 0.6 * 0.5 = 0.3, so snapping uses bar 1.
        let tie = Phrase(peaks: [NoveltyPeak(bar: 4, value: 0.5), NoveltyPeak(bar: 3, value: 0.5)])
        #expect(tie.latticePhaseBar == 3 && near(tie.confidence, 0.3, 1e-8) && tie.snapPhaseBar == 1)
        // No peaks: bar 1, confidence 0, boundaries only the start and the end.
        let none = Phrase(peaks: [])
        #expect(none.latticePhaseBar == 1 && none.confidence == 0 && none.snapPhaseBar == 1)
        #expect(Phrase.boundaries(peaks: [], latticePhaseBar: 1, nBars: 40) == [1, 41])
    }

    @Test func barGridByHand() throws {
        // Grid downbeats every 2 s through 10 s; first sound at 1.3 s, so bar 1 is the downbeat at or after
        // 1.3 - 0.125 = 1.175 s, which is 2 s.
        #expect(BarGrid.firstBar(gridDownbeat: 10, beatS: 0.5, firstSound: 1.3) == 2)
        // The same grid seen from a downbeat before 0: downbeats at ..., 1, 3, ...: bar 1 is at 3 s.
        #expect(BarGrid.firstBar(gridDownbeat: -7, beatS: 0.5, firstSound: 1.3) == 3)
        // A first sound at 0 allows a bar 1 at 0.3 s.
        #expect(near(BarGrid.firstBar(gridDownbeat: 4.3, beatS: 0.5, firstSound: 0), 0.3, 1e-12))
        let g = try #require(BarGrid(gridDownbeat: 10, beatS: 0.5, firstSound: 1.3, duration: 100))
        #expect(g.nBars == 49)                     // floor((100 - 2) / 2)
        #expect(g.barTimes.count == 50 && g.barTimes.first == 2 && g.barTimes.last == 100)
        #expect(g.gridBeats.count == 197)
        #expect(g.beatTimes.prefix(5) == [0, 0.5, 1, 1.5, 2])   // four grid beats before bar 1, back to 0 s
        #expect(g.beatTimes.count == 201)
        // Fewer than 8 bars: no grid (the lab stops there).
        #expect(BarGrid(gridDownbeat: 10, beatS: 0.5, firstSound: 1.3, duration: 15) == nil)
    }

    @Test func sectionsByHand() {
        // Four bars each at -20, -10 and -14 LUFS: the median is -14, so high energy is -15.5 and up.
        let lufs = [Double](repeating: -20, count: 4) + [Double](repeating: -10, count: 4) + [Double](repeating: -14, count: 4)
        let voc = [0, 0, 0, 0.4, 1, 1, 1, 1, 0.2, 0.2, 0.2, 0.2]
        let s = Section.sections(boundariesBars: [1, 5, 9, 13], lufsSt: lufs, vocalProb: voc)
        #expect(s.map(\.label) == ["intro", "main", "outro"])
        #expect(s.map(\.energy) == ["low", "high", "high"])
        #expect(s.map(\.startBar) == [1, 5, 9] && s.map(\.endBar) == [5, 9, 13])
        #expect(near(s[0].vocal, 0.1, 1e-12) && s[1].lufs == -10)
    }

    @Test func fadeOutByHand() {
        // 100 bars of 2 s from 0 s; bars 1-90 at -10 LUFS, 91-100 at -20 (median -10, body level from -12).
        let g = BarGrid(firstDownbeatS: 0, beatS: 0.5, nBars: 100)
        let lufs = [Double](repeating: -10, count: 90) + [Double](repeating: -20, count: 10)
        let f = FadeOut(endLoudness: EndLoudness(t20: -10, t10: -15, t4: -25), lufsSt: lufs, grid: g, firstSound: 0.5,
                        lastSound: 199)
        #expect(f.fadeOut && f.fadeDropLu == 15 && f.lastBodyBar == 90 && f.fadeStartBar == 91)
        #expect(near(f.tailBars, 9.5, 1e-12))   // (199 - 180) / 2
        // A hard stop: only 1.75 bars after the last body-level bar, so no fade even with a large drop.
        let hard = FadeOut(endLoudness: EndLoudness(t20: -10, t10: -15, t4: -25),
                           lufsSt: [Double](repeating: -10, count: 98) + [-20, -20], grid: g, firstSound: 0.5,
                           lastSound: 199.5)
        #expect(!hard.fadeOut && near(hard.tailBars, 1.75, 1e-12) && hard.fadeStartBar == nil)
        // With the fade, the mix-out window ends at the last lattice line before bar 91: line 88, bar 89.
        let (_, mo) = MixWindows.windows(grid: g, vocalProb: [Double](repeating: 0, count: 100), boundariesBars: [1, 101],
                                         snapPhaseBar: 1, lastSound: 199, fadeOut: true, fadeStartBar: 91)
        #expect(mo.endBar == 89 && mo.bars == 32 && mo.startBar == 57 && mo.vocalFreeBars == 32 && mo.lastVocalBar == nil)
    }

    @Test func flagsByHand() {
        let wide = MixIn(startBar: 1, endBar: 33, bars: 32, startS: 0, endS: 64, vocalFreeBars: 32, firstVocalBar: nil)
        let out = MixOut(startBar: 60, endBar: 92, bars: 32, startS: 0, endS: 64, vocalFreeBars: 32, lastVocalBar: nil,
                         fadeOut: false)
        func f(_ bpm: Double, _ tag: Double?, mixIn: MixIn = wide, lt: [String] = []) -> [String] {
            TrackFlags.flags(bpm: bpm, bpmTag: tag, vocalMeanProb: 0.5, fadeOut: false, gridConfidence: 0.9,
                             keyConfidence: 0.65, mixIn: mixIn, mixOut: out, localTempoFlags: lt)
        }
        #expect(f(128, 120) == [])                          // nearest relation to the tag is 1
        #expect(f(128, 64) == ["half_time_candidate"])      // double the tag
        #expect(f(99.9, nil) == ["half_time_candidate"])    // under 100 BPM
        var short = wide
        short.vocalFreeBars = 7
        #expect(f(128, nil, mixIn: short, lt: ["tempo_change", "tempo_change"]) == ["short_intro", "tempo_change"])
    }
}
