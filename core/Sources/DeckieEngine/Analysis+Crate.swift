import Foundation
import DeckieCore
import DeckieCrate

extension Analysis {
    /// What a crate record needs beyond the analysis.
    public struct CrateOptions: Sendable {
        /// When the analysis ran, UTC to the second (`2026-10-28T12:00:00Z`).
        public var analysedAt: String
        /// The device label (`analysis.device`): a model label, never a name the user gave the machine.
        public var device: String
        /// The folder the crate is built from: `file.rel` is the path below it; nil, or a file outside it, gives no
        /// `rel`.
        public var musicRoot: String?

        public init(analysedAt: String, device: String = Analysis.platform, musicRoot: String? = nil) {
            self.analysedAt = analysedAt
            self.device = device
            self.musicRoot = musicRoot
        }
    }

    /// The platform label of the machine running this (`engine.platform`): `linux-x86_64`, `macos-arm64`,
    /// `windows-x86_64`, ...
    public static var platform: String {
        #if os(Linux)
        let system = "linux"
        #elseif os(macOS)
        let system = "macos"
        #elseif os(Windows)
        let system = "windows"
        #else
        let system = "unknown"
        #endif
        #if arch(x86_64)
        let cpu = "x86_64"
        #elseif arch(arm64)
        let cpu = "arm64"
        #else
        let cpu = "unknown"
        #endif
        return "\(system)-\(cpu)"
    }

    /// The decoder that read the file, by format: the vendored dr_mp3 and dr_flac (versions as DEPENDENCIES.md pins
    /// them), DeckieDecode's own readers for WAV and AIFF.
    var decoderInfo: CrateTrack.Engine.DecoderInfo {
        switch source.format {
        case "MP3": return .init(name: "dr_mp3", version: "0.7.4")
        case "FLAC": return .init(name: "dr_flac", version: "0.13.4")
        default: return .init(name: "deckie-decode", version: nil)
        }
    }

    /// The crate record (docs/architecture/crate-format.md), engine family `deckie`. It takes the values the lab
    /// JSON writes, rounded the same way, so a record made here equals one made from the JSON. Without a vocal tagger
    /// the record has no `vocal` block and no `bars.vocal` series, so `features_present` lists neither, and the mix
    /// windows' `vocal_free_bars` are null; the flags carry `vocal_unknown`. With one, the `vocal` block (source: the
    /// tagger's model), the `bars.vocal` series and, when the tagger gives one, the `style` block (YAMNet's mean
    /// embedding, 1,024 values, unit length) are written. The key's changes are the estimator's segments placed on
    /// bars. The lab's EffNet embedding is never written. With a tagger the record also carries the proposed
    /// `vocal_structure` and `hooks` blocks (`crateVocalStructure()`, `crateHooks()`); without one it has neither.
    public func crateTrack(options: CrateOptions) -> CrateTrack {
        let n = bars.nBars
        let r3 = { (x: Double) in Py.round(x, 3) }
        let lt = localTempo
        var models = [CrateTrack.Engine.Model(name: Analysis.gridSource)]
        if let vocalModel { models.append(.init(name: vocalModel)) }
        var rel: String? = nil
        if let root = options.musicRoot {
            let prefix = root.hasSuffix("/") ? root : root + "/"
            if source.path.hasPrefix(prefix) { rel = String(source.path.dropFirst(prefix.count)) }
        }
        /// A bar line clamped to the grid's end, as the lab converter clamps the steady-beat bars.
        func line(_ b: Int?) -> Int? { b.map { min(max($0, 1), n + 1) } }
        let fromFileName = title == URL(fileURLWithPath: source.name).deletingPathExtension().lastPathComponent

        var series: [String: [Double]] = [
            BarSeries.lufs: perBar.lufsSt.map { Py.round($0, 2) }, BarSeries.lowDb: perBar.lowDb.map { Py.round($0, 2) },
            BarSeries.highDb: perBar.highDb.map { Py.round($0, 2) },
            BarSeries.onsetDensity: perBar.onsetDensity.map { Py.round($0, 3) },
        ]
        if let v = perBar.vocalProb { series[BarSeries.vocal] = v.map { Py.round($0, 3) } }

        var crateLoudness: CrateTrack.Loudness? = nil
        if let i = loudness.integratedLufs, i.isFinite, let lra = loudness.lra, lra.isFinite {
            crateLoudness = .init(source: "deckie-core", confidence: nil, integratedLufs: Py.round(i, 2),
                                 lra: Py.round(lra, 3), truePeakDb: Py.round(loudness.truePeakDb, 2))
        }

        return CrateTrack(
            id: id,
            file: .init(name: source.name, rel: rel, bytes: source.bytes, sha1Head: nil, sha256: source.sha256,
                        durationS: r3(duration)),
            ident: .init(title: title ?? source.name, version: version,
                         source: fromFileName ? "filename" : "user"),
            analysis: .init(engine: "\(Analysis.engineFamily)-\(Analysis.engineVersion)", analysedAt: options.analysedAt,
                            device: options.device, secs: Py.round(totalSeconds, 2), level: 1),
            engine: .init(family: Analysis.engineFamily, version: Analysis.engineVersion, platform: Analysis.platform,
                          fidelity: 0, models: models, decoder: decoderInfo),
            grid: .init(source: Analysis.gridSource, confidence: r3(grid.confidence), bpm: r3(bpm),
                        firstDownbeatS: Py.round(bars.firstDownbeatS, 4), nBars: n, fitMadMs: Py.round(grid.fitMadMs, 2),
                        bpmIn: lt.bpmIn != 0 ? lt.bpmIn : r3(bpm), bpmOut: lt.bpmOut != 0 ? lt.bpmOut : r3(bpm),
                        inTrusted: lt.inTrusted, outTrusted: lt.outTrusted),
            tempoSegments: [.init(startBar: 1, startS: Py.round(bars.firstDownbeatS, 4), bpm: r3(bpm), beatsPerBar: 4,
                                  beatInBar: 1, confidence: r3(grid.confidence))],
            key: .init(source: "deckie-core", confidence: keyConfidence.value, camelot: key.whole.camelot,
                       key: key.whole.key, scale: key.whole.mode, votes: ["deckie-key-edma": key.whole.camelot],
                       changes: keyChanges()),
            phrase: .init(source: "foote-novelty", confidence: r3(phrase.confidence),
                          latticePhaseBar: phrase.latticePhaseBar, boundariesBars: boundariesBars),
            sections: sections.map { .init(startBar: $0.startBar, endBar: $0.endBar, label: $0.label, energy: $0.energy) },
            mixIn: .init(startBar: mixIn.startBar, endBar: mixIn.endBar, vocalFreeBars: vocal == nil ? nil : mixIn.vocalFreeBars),
            mixOut: .init(startBar: mixOut.startBar, endBar: mixOut.endBar,
                          vocalFreeBars: vocal == nil ? nil : mixOut.vocalFreeBars),
            ends: .init(firstSoundS: r3(firstSound), lastSoundS: r3(lastSound), fadeOut: fade.fadeOut,
                        fadeStartBar: fade.fadeStartBar, steadyInBar: line(lt.steadyInBar), steadyOutBar: line(lt.steadyOutBar)),
            loudness: crateLoudness,
            vocal: vocal.map { .init(source: vocalModel ?? "vocal-tagger", confidence: nil,
                                     mean: Py.round($0.meanProbability, 4), heavy: $0.meanProbability > 0.75) },
            onsetPattern16: onsetPattern16.map { Py.round($0, 4) },
            flags: flags,
            style: vocal.flatMap { v in v.style.map { CrateTrack.Style(model: v.styleModel ?? vocalModel ?? "vocal-tagger", values: $0) } },
            bars: BarSeries(series), vocalStructure: crateVocalStructure(), hooks: crateHooks())
    }

    /// `x` rounded to the decimals the crate writes the field `name` with (`CrateFormat.decimals`), so the record read
    /// back equals the one written.
    private static func rounded(_ x: Double, _ name: String) -> Double { Py.round(x, CrateFormat.decimals[name]!) }

    /// The proposed `vocal_structure` block: the vocal structure with its rule, rounded as the crate writes it; its
    /// source is the vocal tagger's model. Nil without a tagger.
    public func crateVocalStructure() -> CrateTrack.VocalStructure? {
        guard let vs = vocalStructure else { return nil }
        let r = Analysis.rounded, p = vs.parameters
        return CrateTrack.VocalStructure(
            source: vocalModel ?? "vocal-tagger", frameHopS: r(vs.frameHopSeconds, "frame_hop_s"),
            latticePhaseBar: vs.latticePhaseBar,
            rule: .init(threshold: r(vs.threshold, "threshold"), scoreP95: r(vs.scoreP95, "score_p95"),
                        thresholdFraction: r(p.thresholdFraction, "threshold_fraction"),
                        thresholdFloor: r(p.thresholdFloor, "threshold_floor"), bridgeBeats: p.bridgeBeats,
                        minSpanBeats: p.minSpanBeats, pickupBeats: p.pickupBeats, minGapBars: p.minGapBars,
                        kindBars: p.kindBars, beatDensityRatio: r(p.beatDensityRatio, "beat_density_ratio"),
                        brightMarginDb: r(p.brightMarginDb, "bright_margin_db"),
                        exposedLowDropDb: r(p.exposedLowDropDb, "exposed_low_drop_db"),
                        exposedDensityRatio: r(p.exposedDensityRatio, "exposed_density_ratio"),
                        exposedMinBars: p.exposedMinBars),
            spans: vs.spans.map {
                .init(startBar: $0.start.bar, startBeat: $0.start.beat, startS: r($0.start.seconds, "start_s"),
                      endBar: $0.end.bar, endBeat: $0.end.beat, endS: r($0.end.seconds, "end_s"),
                      startOffsetBeats: $0.startOffsetBeats, endOffsetBeats: $0.endOffsetBeats)
            },
            first: vs.first.map { .init(bar: $0.bar, beat: $0.beat, timeS: r($0.seconds, "time_s"), pickup: vs.pickup) },
            last: vs.last.map { .init(bar: $0.bar, beat: $0.beat, timeS: r($0.seconds, "time_s")) },
            introFreeBars: vs.introFreeBars, introKind: vs.introKind.rawValue, outroFreeBars: vs.outroFreeBars,
            outroKind: vs.outroKind.rawValue,
            freeGaps: vs.freeGaps.map { .init(startBar: $0.startBar, endBar: $0.endBar) },
            exposedProxy: vs.exposedProxy.map { .init(startBar: $0.startBar, endBar: $0.endBar) })
    }

    /// The proposed `hooks` block: the hook candidates with their rule, rounded as the crate writes them, source
    /// `deckie-core`. Nil without a tagger.
    public func crateHooks() -> CrateTrack.Hooks? {
        guard let h = hooks else { return nil }
        let r = Analysis.rounded, p = h.parameters
        return CrateTrack.Hooks(
            source: "deckie-core", latticePhaseBar: h.latticePhaseBar,
            rule: .init(lengthsBars: p.lengthsBars, stepBars: p.stepBars,
                        weightRepetition: r(p.weightRepetition, "weight_repetition"),
                        weightLoudness: r(p.weightLoudness, "weight_loudness"),
                        weightVocal: r(p.weightVocal, "weight_vocal"), minRepetition: r(p.minRepetition, "min_repetition"),
                        shortMargin: r(p.shortMargin, "short_margin"), sungShare: r(p.sungShare, "sung_share"),
                        maxHooks: p.maxHooks),
            candidates: h.candidates.map {
                .init(startBar: $0.startBar, endBar: $0.endBar, strength: r($0.strength, "strength"), sung: $0.sung,
                      repetition: r($0.repetition, "repetition"), loudnessScore: r($0.loudness, "loudness_score"),
                      vocalDensity: r($0.vocalDensity, "vocal_density"), repeatStartBar: $0.repeatStartBar)
            })
    }

    /// The key segments as bar spans: each segment starts at the bar line nearest its start time (bar 1 for the
    /// first), runs to the next segment's start or the end line; segments that land on the same bar keep the later
    /// key. Nil when there are no segments.
    func keyChanges() -> [CrateTrack.Key.Change]? {
        let n = bars.nBars
        guard !key.segments.isEmpty else { return nil }
        var starts: [(bar: Int, camelot: String)] = []
        for (i, s) in key.segments.enumerated() {
            let bar = i == 0 ? 1 : min(max(Int(Py.roundEven((s.start - bars.firstDownbeatS) / bars.barS)) + 1, 1), n)
            if let last = starts.last, bar <= last.bar {
                starts[starts.count - 1].camelot = s.camelot
            } else {
                starts.append((bar, s.camelot))
            }
        }
        // Neighbouring spans in the same key are one span.
        var merged: [(bar: Int, camelot: String)] = []
        for s in starts where merged.last?.camelot != s.camelot { merged.append(s) }
        return merged.enumerated().map { i, s in
            CrateTrack.Key.Change(startBar: s.bar, endBar: i + 1 < merged.count ? merged[i + 1].bar : n + 1,
                                  camelot: s.camelot)
        }
    }
}
