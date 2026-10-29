import Foundation
import Testing
import DeckieBuild
import DeckieLab

/// The stage 1 measures, ported from mixer/bench_mu.py, on hand-made numbers whose answers are worked out here (and
/// match what the Python gives for the same lists).
@Suite struct BenchMetricsTests {
    @Test func fMeasureAt70ms() {
        // Two of three within 70 ms: precision and recall 2/3.
        #expect(BenchMetrics.fMeasure(reference: [1, 2, 3], estimate: [1.05, 2.2, 3.0]) == 2.0 / 3.0)
        // Exactly 70 ms counts (on numbers whose difference is exact in binary).
        #expect(BenchMetrics.fMeasure(reference: [1.0], estimate: [1.0 + 0.0703125], tolerance: 0.0703125) == 1)
        // Each reference is used once: two estimates near one beat give one hit; p = 1/2, r = 1.
        #expect(BenchMetrics.fMeasure(reference: [1], estimate: [0.99, 1.01]) == 2 * 0.5 * 1 / 1.5)
        // An estimate takes the unused reference before it first, then the one after (bench_mu's order); early and
        // late estimates both count, and the lists need not be sorted.
        #expect(BenchMetrics.fMeasure(reference: [2.0, 1.0], estimate: [2.05, 0.95]) == 1)
        let f = BenchMetrics.fMeasure(reference: [1.00, 1.06, 2.0], estimate: [1.05, 1.07, 2.0])
        #expect(f.map { abs($0 - 1) < 1e-12 } == true)
        #expect(BenchMetrics.fMeasure(reference: [], estimate: [1]) == nil)
        #expect(BenchMetrics.fMeasure(reference: [1, 2], estimate: [1.5]) == 0)
    }

    @Test func keyRelations() {
        #expect(BenchMetrics.keyRelation("8A", "8A") == "exact")
        #expect(BenchMetrics.keyRelation("8A", "8B") == "neighbour")
        #expect(BenchMetrics.keyRelation("12A", "1A") == "neighbour")
        #expect(BenchMetrics.keyRelation("8A", "10A") == "other")
        #expect(BenchMetrics.keyRelation("8A", "9B") == "other")
        #expect(BenchMetrics.keyRelation("?", "8A") == "other")
    }

    @Test func boundariesAndCorrelation() {
        let pr = BenchMetrics.boundaries(reference: [10, 20, 30], estimate: [10.5, 25, 31], tolerance: 2)
        #expect(pr?.precision == 2.0 / 3.0 && pr?.recall == 2.0 / 3.0)
        #expect(BenchMetrics.boundaries(reference: [], estimate: [1], tolerance: 2) == nil)
        #expect(BenchMetrics.pearson([1, 2, 3, 4], [2, 4, 6, 8]).map { abs($0 - 1) < 1e-12 } == true)
        #expect(BenchMetrics.pearson([1, 2], [1, 2]) == nil)
        #expect(BenchMetrics.pearson([1, 1, 1], [1, 2, 3]) == nil)
    }

    /// The "key vs key_parity.py" column: the engine's own decision (`deckie.key`) against the sheet's row, by the
    /// main session's rule (same key, margin within 1e-3, same sure flag); absent without either side.
    @Test func keyParityColumn() throws {
        func record(_ deckie: String) throws -> BenchRecord {
            let text = #"{"id":"t1","bpm":120,"grid":{"bpm":120,"first_downbeat_s":0.5,"n_bars":8},"key":{"camelot":"8A"}"#
                + deckie + "}"
            return try JSONDecoder().decode(BenchRecord.self, from: Data(text.utf8))
        }
        func parity(_ camelot: String, _ margin: Double, _ sure: Bool) -> String {
            ",\"deckie\":{\"key\":{\"camelot\":\"\(camelot)\",\"margin\":\(margin),\"agree\":3,\"sure\":\(sure)}}"
        }
        let row = KeyParityRow(id: "t1", key: "8A", margin: 0.1234, agree: 3, sure: true, lab: "8A", labConfident: true,
                               apple: "8A")
        let lab = try record("")
        let same = BenchMetrics.compare(engine: try record(parity("8A", 0.1240, true)), lab: lab, rel: "a", seconds: nil,
                                        parity: row)
        #expect(same.keyParity == "same" && same.keyParityEngine?.margin == 0.124)
        let differ = BenchMetrics.compare(engine: try record(parity("9A", 0.13, false)), lab: lab, rel: "a", seconds: nil,
                                          parity: row)
        #expect(differ.keyParity == "key 9A, key_parity.py 8A; margin 0.1300, key_parity.py 0.1234; sure false, key_parity.py true")
        #expect(BenchMetrics.compare(engine: lab, lab: lab, rel: "a", seconds: nil, parity: row).keyParity == nil)
        let noRow = BenchMetrics.compare(engine: try record(parity("8A", 0.1240, true)), lab: lab, rel: "a", seconds: nil)
        #expect(noRow.keyParity == nil)
        let summary = BenchSummary([same, differ])
        #expect(summary.keyParityTracks == 2 && summary.keyParitySame == 1)
        #expect(summary.keyParityDiffering.map(\.id) == ["t1"])
    }

    @Test func musicRootIsTheSharedFolder() {
        #expect(Bench.commonFolder(["/Users/c/music/CD1/a.mp3", "/Users/c/music/CD2/b.mp3"]) == "/Users/c/music")
        #expect(Bench.commonFolder(["/Users/c/music/CD1/a.mp3"]) == "/Users/c/music/CD1")
        #expect(Bench.commonFolder(["/a/x.mp3", "/b/y.mp3"]) == "/")
    }
}
