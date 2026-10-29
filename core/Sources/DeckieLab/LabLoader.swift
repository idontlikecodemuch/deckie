import Foundation
import DeckieCore

/// Reads the lab's feature files and candidates into `Track`s, exactly as `load()` in mixer/score.py does.
public enum LabLoader {
    /// Feature files in name order (the lab's `sorted(glob(...))`), joined with their candidates rows.
    public static func loadTracks(featuresDir: URL, candidatesFile: URL) throws -> [Track] {
        let cands = Dictionary(try CandidateRecord.loadAll(candidatesFile).map { ($0.id, $0) },
                               uniquingKeysWith: { a, _ in a })
        let files = try FileManager.default.contentsOfDirectory(atPath: featuresDir.path)
            .filter { $0.hasSuffix(".json") }.sorted()
        return try files.map { try track(from: FeatureFile.load(featuresDir.appendingPathComponent($0)), cands) }
    }

    /// Power mean in dB of the finite values, -70 when there are none (the lab's `pmean`).
    static func pmean(_ a: ArraySlice<Double>) -> Double {
        let finite = a.filter { $0.isFinite }
        if finite.isEmpty { return -70.0 }
        var sum = 0.0
        for v in finite { sum += pow(10, v / 10) }
        return 10 * log10(sum / Double(finite.count))
    }

    static func slice(_ a: [Double], _ lo: Int, _ hi: Int) -> [Double] {
        // Python slicing: clamp, and an empty result when lo >= hi.
        let l = min(max(lo, 0), a.count), h = min(max(hi, 0), a.count)
        return l < h ? Array(a[l..<h]) : []
    }

    public static func track(from d: FeatureFile, _ cands: [String: CandidateRecord]) -> Track {
        let c = cands[d.id]
        let lufs = d.perBar.lufsSt, voc = d.perBar.vocalProb
        let i0 = d.mixIn.startBar - 1, i1 = d.mixIn.endBar - 1
        let o0 = d.mixOut.startBar - 1, o1 = d.mixOut.endBar - 1
        let integ = d.loudness.integratedLufs
        let emb = d.embeddingEffnet
        var norm = 0.0
        for v in emb { norm += v * v }
        norm = norm.squareRoot() + 1e-9
        let lt = d.localTempo
        let secs = c?.secs ?? 0
        return Track(
            id: d.id, title: c?.title ?? d.title ?? "", ver: (c?.ver ?? d.ver) ?? "",
            secs: secs != 0 ? secs : d.durationS, cutKey: (c?.cutKey).flatMap { $0.isEmpty ? nil : $0 } ?? d.id,
            isLongest: c?.isLongest ?? true, onDisc: c?.onDisc ?? false, disc: c?.disc,
            folder: c?.folder ?? "", hal: c?.hal ?? false, bpm: d.bpm, bpmTag: d.bpmTag,
            gridConf: d.grid.confidence,
            bpmIn: (lt?.bpmIn).flatMap { $0 != 0 ? $0 : nil } ?? d.bpm,
            bpmOut: (lt?.bpmOut).flatMap { $0 != 0 ? $0 : nil } ?? d.bpm,
            tempoChange: lt?.tempoChange ?? false, driftPct: lt?.driftPct ?? 0.0,
            inTrusted: lt?.inTrusted ?? true, outTrusted: lt?.outTrusted ?? true,
            steadyInBar: lt?.steadyInBar, steadyOutBar: lt?.steadyOutBar, nBars: d.grid.nBars,
            camelot: d.key.camelot, keyConf: d.key.confidence, inBars: d.mixIn.bars, outBars: d.mixOut.bars,
            inRel: pmean(lufs[min(i0, lufs.count)..<min(max(i0, i1), lufs.count)]) - integ,
            outRel: pmean(lufs[min(o0, lufs.count)..<min(max(o0, o1), lufs.count)]) - integ,
            vocIn: slice(voc, i0, i1), vocOut: slice(voc, o0, o1), vocFirst16: slice(voc, i0, i0 + 16),
            pattern: d.onsetPattern16, embedding: emb.map { $0 / norm },
            fadeOut: d.fadeOut ?? false, flags: d.flags ?? [],
            kind: (c?.kind).flatMap { $0.isEmpty ? nil : $0 } ?? d.meta?.kind ?? "",
            era: (c?.era).flatMap { $0.isEmpty ? nil : $0 } ?? d.meta?.era ?? "")
    }
}
