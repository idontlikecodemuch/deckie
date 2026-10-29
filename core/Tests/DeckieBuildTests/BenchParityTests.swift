import Foundation
import Testing
import DeckieBuild

/// The bench's measures against mixer/bench_mu.py's own functions, run by core/Tools/make_bench_fixtures.py on pairs
/// of series from every committed lab feature file (Fixtures/bench_parity.json); and every committed lab file read as
/// a bench record and scored against itself.
@Suite struct BenchParityTests {
    static let features = repositoryRoot.appendingPathComponent("mixer/features")

    struct Expected: Decodable {
        var beat_f: Double?
        var downbeat_f: Double?
        var half_f: Double?
        var key_rel: String?
        var section_p: Double?
        var section_r: Double?
        var pearson: Double?
    }

    static func lab(_ id: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: features.appendingPathComponent("\(id).json")))
                     as? [String: Any])
    }

    @Test func measuresMatchTheLabsOwnFunctions() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/bench_parity.json")
        let expected = try JSONDecoder().decode([String: Expected].self, from: Data(contentsOf: url))
        #expect(expected.count == 373)
        var compared = 0
        for (id, want) in expected.sorted(by: { $0.key < $1.key }) {
            let f = try Self.lab(id)
            let grid = f["grid"] as! [String: Any]
            let barS = grid["bar_s"] as! Double, fd = grid["first_downbeat_s"] as! Double, n = grid["n_bars"] as! Int
            let beats = f["beats_s"] as! [Double], detected = f["detected_beats_s"] as! [Double]
            #expect(BenchMetrics.fMeasure(reference: beats, estimate: detected) == want.beat_f, "\(id) beat_f")
            #expect(BenchMetrics.fMeasure(reference: f["downbeats_s"] as! [Double],
                                          estimate: f["detected_downbeats_s"] as? [Double] ?? []) == want.downbeat_f,
                    "\(id) downbeat_f")
            let half = stride(from: 0, to: detected.count, by: 2).map { detected[$0] }
            #expect(BenchMetrics.fMeasure(reference: detected, estimate: half) == want.half_f, "\(id) half_f")
            let key = f["key"] as! [String: Any]
            if let madmom = key["camelot_madmom"] as? String {
                #expect(BenchMetrics.keyRelation(madmom, key["camelot"] as! String) == want.key_rel, "\(id) key")
            } else {
                #expect(want.key_rel == nil)
            }
            let inner = (f["boundaries_bars"] as! [Int]).filter { $0 > 1 && $0 < n }.map { fd + Double($0 - 1) * barS }
            let peaks = (f["novelty_peaks"] as! [[Double]]).map { fd + ($0[0] - 1) * barS }
            let pr = BenchMetrics.boundaries(reference: inner, estimate: peaks, tolerance: barS)
            #expect(pr?.precision == want.section_p && pr?.recall == want.section_r, "\(id) sections")
            let perBar = f["per_bar"] as! [String: Any]
            #expect(BenchMetrics.pearson(perBar["lufs_st"] as! [Double], perBar["vocal_prob"] as! [Double]) == want.pearson,
                    "\(id) pearson")
            compared += 1
        }
        #expect(compared == 373)
    }

    /// Every committed lab file reads as a bench record and scores perfectly against itself.
    @Test func everyLabFileScoresPerfectlyAgainstItself() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Self.features.path).filter { $0.hasSuffix(".json") }
        #expect(names.count == 373)
        var scores: [TrackScore] = []
        for name in names.sorted() {
            let r = try JSONDecoder().decode(BenchRecord.self, from: Data(contentsOf: Self.features.appendingPathComponent(name)))
            let s = BenchMetrics.compare(engine: r, lab: r, rel: name, seconds: nil)
            #expect(s.beatFDetected == 1 && s.beatFGrid == 1 && s.downbeatFDetected == 1 && s.downbeatFGrid == 1, "\(name)")
            #expect(s.bpmRatio == 1 && s.keyRelation == "exact" && s.lufsDelta == 0 && s.bar1OffsetMs == 0, "\(name)")
            #expect(s.sectionRecall == nil || s.sectionRecall == 1, "\(name)")
            #expect(s.vocalR.map { abs($0 - 1) < 1e-9 } ?? true, "\(name): \(s.vocalNote)")
            scores.append(s)
        }
        let summary = BenchSummary(scores)
        #expect(summary.tracks == 373 && summary.charterPass == true)
        // The lab's 311 confident keys, as stage 1 counts them.
        #expect(summary.keyConfidentCount == 311)
        print("lab against itself: \(summary.vocalR.n) tracks with a vocal correlation, sections on "
              + "\(summary.sectionRecall.n), lab grids \(summary.gridByLabSource.mapValues { $0.beat.n })")
    }
}
