import Foundation
import DeckieCore
import DeckieEngine

/// The bench's numbers over all compared tracks, and the pass marks.
public struct BenchSummary: Sendable {
    /// Count, median and mean of a measure, and for an F-measure the share below 0.8, as stage 1 reports them.
    public struct Stat: Sendable, Equatable {
        public var n: Int
        public var median: Double?
        public var mean: Double?
        public var below08: Double?
        public var medianAbs: Double?
        public var maxAbs: Double?

        init(_ values: [Double], fMeasure: Bool = false, signed: Bool = false) {
            n = values.count
            median = DeckieBuild.median(values)
            mean = DeckieBuild.mean(values)
            below08 = fMeasure && n > 0 ? Double(values.filter { $0 < 0.8 }.count) / Double(n) : nil
            medianAbs = signed ? DeckieBuild.median(values.map(abs)) : nil
            maxAbs = signed ? values.map(abs).max() : nil
        }
    }

    /// One pass mark: the measured value, the target and whether it is met (nil when there is nothing to measure).
    /// `charter` marks the charter's own pass marks; the others are Apple's stage 1 figures, for reference.
    public struct Mark: Sendable, Equatable {
        public var name: String
        public var value: Double?
        public var target: Double
        /// `>=` or `<=`.
        public var rule: String
        /// Decimals the value is rounded to before it is compared, as the target is written.
        public var decimals: Int
        public var charter: Bool
        public var source: String
        public var pass: Bool? {
            guard let value else { return nil }
            let v = Py.round(value, decimals)
            return rule == ">=" ? v >= target : v <= target
        }
    }

    public var tracks: Int
    public var beatFDetected, beatFGrid, beatFBestOctave, downbeatFDetected, downbeatFGrid: Stat
    /// Shares of tracks.
    public var tempoWithin2, tempoWithin2Octave, octaveApart: Double?
    /// Key relation shares over all tracks, and over the tracks whose lab key is confident (0.65 or more, as stage 1
    /// splits them).
    public var keyAll: [String: Double]
    public var keyConfident: [String: Double]
    public var keyConfidentCount: Int
    /// The key against mixer/key_parity_keys.tsv (research R's key method as key_parity.py decided it): the tracks
    /// with both sides, how many are the same by the parity rule (`TrackScore.keyParity`), the others with their
    /// differences, and on how many the engine's own key (decided with the literature's profile numbers) equals the
    /// sheet's key.
    public var keyParityTracks: Int
    public var keyParitySame: Int
    public var keyParityDiffering: [(id: String, text: String)]
    public var keyDecidedAsParity: Int
    public var lufsDelta, truePeakDelta: Stat
    /// Share of tracks more than 1 LU from the lab.
    public var lufsOver1: Double?
    public var sectionRecall, sectionPrecision, vocalR, bar1OffsetMs: Stat
    public var nBarsMatch: Double?
    /// The engine's seconds per track (fresh analyses only): median, 90th percentile, max.
    public var seconds: Stat
    public var secondsP90: Double?
    /// Beat and downbeat F against the lab's grid where the lab's grid came from Beat This! and where from madmom.
    public var gridByLabSource: [String: (beat: Stat, downbeat: Stat)]
    public var marks: [Mark]

    /// Whether every charter mark is met: nil when one cannot be measured (no tracks, or no confident key).
    public var charterPass: Bool? {
        let charter = marks.filter(\.charter)
        if charter.contains(where: { $0.pass == false }) { return false }
        return charter.allSatisfy { $0.pass == true } ? true : nil
    }

    public init(_ scores: [TrackScore]) {
        func share(_ pred: (TrackScore) -> Bool, _ among: [TrackScore]) -> Double? {
            among.isEmpty ? nil : Double(among.filter(pred).count) / Double(among.count)
        }
        func relations(_ s: [TrackScore]) -> [String: Double] {
            guard !s.isEmpty else { return [:] }
            var r: [String: Double] = [:]
            for k in ["exact", "neighbour", "other"] { r[k] = Double(s.filter { $0.keyRelation == k }.count) / Double(s.count) }
            return r
        }
        tracks = scores.count
        beatFDetected = Stat(scores.compactMap(\.beatFDetected), fMeasure: true)
        beatFGrid = Stat(scores.compactMap(\.beatFGrid), fMeasure: true)
        beatFBestOctave = Stat(scores.compactMap(\.beatFBestOctave), fMeasure: true)
        downbeatFDetected = Stat(scores.compactMap(\.downbeatFDetected), fMeasure: true)
        downbeatFGrid = Stat(scores.compactMap(\.downbeatFGrid), fMeasure: true)
        tempoWithin2 = share({ $0.tempoWithin2 }, scores)
        tempoWithin2Octave = share({ $0.tempoWithin2Octave }, scores)
        octaveApart = share({ $0.octaveApart }, scores)
        keyAll = relations(scores)
        let confident = scores.filter { ($0.keyConfidenceLab ?? 0) >= 0.65 }
        keyConfident = relations(confident)
        keyConfidentCount = confident.count
        let parity = scores.filter { $0.keyParity != nil }
        keyParityTracks = parity.count
        keyParitySame = parity.filter { $0.keyParity == "same" }.count
        keyParityDiffering = parity.compactMap { $0.keyParity == "same" ? nil : ($0.id, $0.keyParity!) }
        keyDecidedAsParity = parity.filter { $0.keyEngine == $0.keyParityReference?.key }.count
        let lufs = scores.compactMap(\.lufsDelta)
        lufsDelta = Stat(lufs, signed: true)
        lufsOver1 = lufs.isEmpty ? nil : Double(lufs.filter { abs($0) > 1 }.count) / Double(lufs.count)
        truePeakDelta = Stat(scores.compactMap(\.truePeakDelta), signed: true)
        sectionRecall = Stat(scores.compactMap(\.sectionRecall))
        sectionPrecision = Stat(scores.compactMap(\.sectionPrecision))
        vocalR = Stat(scores.compactMap(\.vocalR))
        bar1OffsetMs = Stat(scores.map(\.bar1OffsetMs), signed: true)
        nBarsMatch = share({ $0.nBarsMatch }, scores)
        let secs = scores.compactMap(\.seconds)
        seconds = Stat(secs, signed: true)
        secondsP90 = secs.isEmpty ? nil : secs.sorted()[min(secs.count - 1, Int((0.9 * Double(secs.count - 1)).rounded()))]
        var bySource: [String: (beat: Stat, downbeat: Stat)] = [:]
        for source in Set(scores.compactMap(\.labGridSource)) {
            let s = scores.filter { $0.labGridSource == source }
            bySource[source] = (Stat(s.compactMap(\.beatFGrid), fMeasure: true), Stat(s.compactMap(\.downbeatFGrid), fMeasure: true))
        }
        gridByLabSource = bySource

        // The charter's pass marks: at least Apple's framework on beats and loudness (stage 1, 1a, mixer/mu_bench.tsv
        // over 373 tracks) and the key estimator's measured 75 percent exact. Apple's other figures for reference.
        let apple = "Apple's framework, stage 1 (1a)"
        marks = [
            Mark(name: "beat F@70ms, detected vs detected, median", value: beatFDetected.median, target: 0.987,
                 rule: ">=", decimals: 3, charter: true, source: apple),
            Mark(name: "beat F@70ms, detected vs detected, share below 0.8", value: beatFDetected.below08, target: 0.078,
                 rule: "<=", decimals: 3, charter: true, source: apple),
            Mark(name: "beat F@70ms, grid vs grid, median", value: beatFGrid.median, target: 0.997, rule: ">=", decimals: 3,
                 charter: true, source: apple),
            Mark(name: "beat F@70ms, grid vs grid, share below 0.8", value: beatFGrid.below08, target: 0.145, rule: "<=",
                 decimals: 3, charter: true, source: apple),
            Mark(name: "downbeat F@70ms, detected vs detected, median", value: downbeatFDetected.median, target: 0.968,
                 rule: ">=", decimals: 3, charter: true, source: apple),
            Mark(name: "downbeat F@70ms, detected vs detected, share below 0.8", value: downbeatFDetected.below08,
                 target: 0.185, rule: "<=", decimals: 3, charter: true, source: apple),
            Mark(name: "downbeat F@70ms, grid vs grid, median", value: downbeatFGrid.median, target: 1.0, rule: ">=",
                 decimals: 3, charter: true, source: apple),
            Mark(name: "downbeat F@70ms, grid vs grid, share below 0.8", value: downbeatFGrid.below08, target: 0.225,
                 rule: "<=", decimals: 3, charter: true, source: apple),
            Mark(name: "integrated loudness, median |delta| (LU)", value: lufsDelta.medianAbs, target: 0.04, rule: "<=",
                 decimals: 2, charter: true, source: apple),
            Mark(name: "integrated loudness, share more than 1 LU off", value: lufsOver1, target: 0, rule: "<=",
                 decimals: 3, charter: true, source: apple),
            Mark(name: "key exact where the lab is confident", value: keyConfident["exact"], target: 0.75, rule: ">=",
                 decimals: 3, charter: true, source: "the key estimator's measured 75 percent (mixer/key_light.py)"),
            Mark(name: "tempo within 2 percent (no octave normalisation)", value: tempoWithin2, target: 0.914, rule: ">=",
                 decimals: 3, charter: false, source: apple),
            Mark(name: "key exact where the lab is confident, against Apple", value: keyConfident["exact"], target: 0.833,
                 rule: ">=", decimals: 3, charter: false, source: apple),
            Mark(name: "per-bar vocal correlation, median", value: vocalR.median, target: 0.645, rule: ">=", decimals: 3,
                 charter: false, source: apple),
            Mark(name: "section boundary recall within one bar, median", value: sectionRecall.median, target: 1.0,
                 rule: ">=", decimals: 3, charter: false, source: apple),
        ]
    }
}

// MARK: - Writing it out

extension BenchSummary.Stat {
    func json() -> JSONValue {
        var m: [JSONValue.Member] = [.init("n", .int(n)), .init("median", num(median)), .init("mean", num(mean))]
        if below08 != nil { m.append(.init("below_0_8", num(below08))) }
        if medianAbs != nil || n == 0 { m.append(.init("median_abs", num(medianAbs))) }
        if maxAbs != nil { m.append(.init("max_abs", num(maxAbs))) }
        return .object(m)
    }
}

func num(_ x: Double?, _ places: Int = 4) -> JSONValue {
    guard let x, x.isFinite else { return .null }
    return .number(Py.round(x, places))
}

extension BenchSummary {
    func json() -> JSONValue {
        func shares(_ d: [String: Double]) -> JSONValue { .object(["exact", "neighbour", "other"].map { .init($0, num(d[$0])) }) }
        return .object([
            .init("tracks", .int(tracks)),
            .init("beat_f_detected", beatFDetected.json()), .init("beat_f_grid", beatFGrid.json()),
            .init("beat_f_best_octave", beatFBestOctave.json()),
            .init("downbeat_f_detected", downbeatFDetected.json()), .init("downbeat_f_grid", downbeatFGrid.json()),
            .init("grid_by_lab_source", .object(gridByLabSource.keys.sorted().map { k in
                .init(k, .object([.init("beat_f_grid", gridByLabSource[k]!.beat.json()),
                                  .init("downbeat_f_grid", gridByLabSource[k]!.downbeat.json())]))
            })),
            .init("tempo", .object([.init("within_2pct_octave_normalised", num(tempoWithin2Octave)),
                                    .init("within_2pct", num(tempoWithin2)), .init("octave_apart", num(octaveApart))])),
            .init("key", .object([.init("all", shares(keyAll)),
                                  .init("lab_confident", shares(keyConfident)),
                                  .init("lab_confident_tracks", .int(keyConfidentCount))])),
            .init("key_parity", .object([
                .init("tracks", .int(keyParityTracks)), .init("same", .int(keyParitySame)),
                .init("decided_as_key_parity_py", .int(keyDecidedAsParity)),
                .init("differing", .array(keyParityDiffering.map {
                    .object([.init("id", .string($0.id)), .init("differences", .string($0.text))])
                })),
            ])),
            .init("integrated_lufs_delta", lufsDelta.json()), .init("integrated_lufs_over_1_lu", num(lufsOver1)),
            .init("true_peak_delta_db", truePeakDelta.json()),
            .init("section_recall", sectionRecall.json()), .init("section_precision", sectionPrecision.json()),
            .init("vocal_r", vocalR.json()),
            .init("bar1_offset_ms", bar1OffsetMs.json()), .init("n_bars_match", num(nBarsMatch)),
            .init("seconds_per_track", .object([.init("n", .int(seconds.n)), .init("median", num(seconds.median, 2)),
                                                .init("p90", num(secondsP90, 2)), .init("max", num(seconds.maxAbs, 2))])),
            .init("pass_marks", .array(marks.map { k in
                .object([.init("name", .string(k.name)), .init("value", num(k.value)), .init("target", .number(k.target)),
                         .init("rule", .string(k.rule)), .init("pass", k.pass.map(JSONValue.bool) ?? .null),
                         .init("charter", .bool(k.charter)), .init("source", .string(k.source))])
            })),
            .init("charter_pass", charterPass.map(JSONValue.bool) ?? .null),
        ])
    }
}

extension TrackScore {
    func json() -> JSONValue {
        .object([
            .init("id", .string(id)), .init("title", title.map(JSONValue.string) ?? .null), .init("rel", .string(rel)),
            .init("seconds", num(seconds, 2)),
            .init("beat_f_detected", num(beatFDetected)), .init("beat_f_grid", num(beatFGrid)),
            .init("beat_f_best_octave", num(beatFBestOctave)),
            .init("downbeat_f_detected", num(downbeatFDetected)), .init("downbeat_f_grid", num(downbeatFGrid)),
            .init("bpm_engine", num(bpmEngine, 3)), .init("bpm_lab", num(bpmLab, 3)), .init("bpm_ratio", num(bpmRatio)),
            .init("tempo_within_2pct", .bool(tempoWithin2)), .init("tempo_within_2pct_octave", .bool(tempoWithin2Octave)),
            .init("octave_apart", .bool(octaveApart)),
            .init("key_engine", .string(keyEngine)), .init("key_lab", .string(keyLab)),
            .init("key_confidence_lab", num(keyConfidenceLab, 3)), .init("key_relation", .string(keyRelation)),
            .init("key_parity_py", keyParityReference.map { .string($0.key) } ?? .null),
            .init("key_parity_py_margin", num(keyParityReference?.margin)),
            .init("key_parity_py_sure", keyParityReference.map { .bool($0.sure) } ?? .null),
            .init("key_engine_parity", keyParityEngine.map { .string($0.camelot) } ?? .null),
            .init("key_engine_parity_margin", num(keyParityEngine?.margin)),
            .init("key_engine_parity_sure", keyParityEngine.map { .bool($0.sure) } ?? .null),
            .init("key_parity", keyParity.map(JSONValue.string) ?? .null),
            .init("integrated_lufs_delta", num(lufsDelta)), .init("true_peak_delta_db", num(truePeakDelta)),
            .init("section_recall", num(sectionRecall)), .init("section_precision", num(sectionPrecision)),
            .init("vocal_r", num(vocalR)), .init("vocal", .string(vocalNote)),
            .init("bar1_offset_ms", num(bar1OffsetMs, 1)), .init("n_bars_engine", .int(nBarsEngine)),
            .init("n_bars_lab", .int(nBarsLab)), .init("n_bars_match", .bool(nBarsMatch)),
            .init("lab_grid_source", labGridSource.map(JSONValue.string) ?? .null),
            .init("madmom_would_run", madmomWouldRun.map(JSONValue.string) ?? .null),
        ])
    }
}
