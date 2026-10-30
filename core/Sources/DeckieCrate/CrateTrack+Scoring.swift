import Foundation
import DeckieCore

extension CrateTrack {
    /// The track as the pair scoring sees it (the row mixer/score.py's `load()` makes from a feature file and its
    /// candidates entry), from the crate's own fields: the grid and mix windows, the per-bar loudness and vocal
    /// series, the style vector, the DJ's names. Nil when the record has no grid, mix windows or loudness (an engine
    /// below level 1 wrote it). This is what lets an app score picks from any crate, on the device, without the lab.
    public func scoringTrack() -> DeckieCore.Track? {
        guard let grid, let mixIn, let mixOut, let loudness else { return nil }
        let lufs = bars?[BarSeries.lufs] ?? []
        // No vocal series (an engine that does not hear vocals): every bar counts as vocal-free, as the lab does.
        let voc = bars?[BarSeries.vocal] ?? [Double](repeating: 0, count: grid.nBars)
        let i0 = mixIn.startBar - 1, i1 = mixIn.endBar - 1
        let o0 = mixOut.startBar - 1, o1 = mixOut.endBar - 1
        let emb = style?.values ?? []
        var norm = 0.0
        for v in emb { norm += v * v }
        norm = norm.squareRoot() + 1e-9
        let title = ident.artist.map { "\($0) - \(ident.title)" } ?? ident.title
        return DeckieCore.Track(
            id: id, title: title, ver: ident.version ?? "", secs: file.durationS,
            cutKey: ident.cutKey.flatMap { $0.isEmpty ? nil : $0 } ?? id,
            isLongest: ident.isLongest ?? true, onDisc: ident.disc != nil, disc: ident.disc,
            folder: ident.folder ?? "", hal: ident.tags.contains("halloween"), bpm: grid.bpm, bpmTag: file.tagBpm,
            gridConf: grid.confidence, bpmIn: grid.bpmIn, bpmOut: grid.bpmOut,
            tempoChange: (tempoSegments?.count ?? 1) > 1, driftPct: 0.0,
            inTrusted: grid.inTrusted, outTrusted: grid.outTrusted,
            steadyInBar: ends?.steadyInBar, steadyOutBar: ends?.steadyOutBar, nBars: grid.nBars,
            camelot: key?.camelot ?? "", keyConf: key?.confidence ?? 0,
            inBars: mixIn.endBar - mixIn.startBar, outBars: mixOut.endBar - mixOut.startBar,
            inRel: Self.powerMean(lufs, i0, i1) - loudness.integratedLufs,
            outRel: Self.powerMean(lufs, o0, o1) - loudness.integratedLufs,
            vocIn: Self.slice(voc, i0, i1), vocOut: Self.slice(voc, o0, o1), vocFirst16: Self.slice(voc, i0, i0 + 16),
            pattern: onsetPattern16 ?? [], embedding: emb.map { $0 / norm },
            fadeOut: ends?.fadeOut ?? false, flags: flags, kind: ident.kind ?? "", era: ident.era ?? "")
    }

    /// Power mean in dB of the finite values of `a[lo..<hi]` (clamped), -70 when there are none: the lab's `pmean`.
    static func powerMean(_ a: [Double], _ lo: Int, _ hi: Int) -> Double {
        let finite = slice(a, lo, hi).filter { $0.isFinite }
        if finite.isEmpty { return -70.0 }
        var sum = 0.0
        for v in finite { sum += pow(10, v / 10) }
        return 10 * log10(sum / Double(finite.count))
    }

    /// Python slicing: clamped, empty when lo >= hi.
    static func slice(_ a: [Double], _ lo: Int, _ hi: Int) -> [Double] {
        let l = min(max(lo, 0), a.count), h = min(max(hi, 0), a.count)
        return l < h ? Array(a[l..<h]) : []
    }
}
