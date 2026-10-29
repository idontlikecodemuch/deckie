import Foundation
import Testing
import DeckieBuild
import DeckieEngine
import DeckieTestSupport

/// The bench on the engine's own output, as no music is here: the synthesised test track is analysed, its lab JSON
/// written as a fake lab feature file with a fake candidates row, and the bench, which analyses the track again,
/// must score it perfectly against itself; then against a copy with every beat 100 ms late and the tempo doubled.
@Suite(.enabled(if: Available.engine, "needs ONNX Runtime (core/Tools/fetch-onnxruntime.sh) and the Beat This! model (core/Tools/export_beat_this.py)"))
struct BenchTests {
    static let labID = "fake000001"

    /// Edits a lab-shaped JSON file as a dictionary.
    static func edit(_ data: Data, _ change: (inout [String: Any]) -> Void) throws -> Data {
        var obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        change(&obj)
        return try JSONSerialization.data(withJSONObject: obj)
    }

    @Test func scoresTheEngineAgainstItself() async throws {
        let music = try await Fixture.shared.music()
        let analyser = try await Fixture.shared.analyser()
        let root = try temporaryFolder("bench")
        try? FileManager.default.removeItem(at: root)
        let features = root.appendingPathComponent("features"), shifted = root.appendingPathComponent("features-shifted")
        for d in [features, shifted] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }

        // The fake lab record: the engine's own JSON, its key marked confident so the key pass mark can be read.
        let track = music.appendingPathComponent(Fixture.firstTrack)
        let analysis = try await CPUTurns.exclusive { try analyser.analyse(url: track) }
        let labJSON = try Self.edit(analysis.labJSONData()) { obj in
            var key = obj["key"] as! [String: Any]
            key["confidence"] = 0.9
            obj["key"] = key
        }
        try labJSON.write(to: features.appendingPathComponent("\(Self.labID).json"))
        // The fake candidates: the track as it was on "the lab's machine", and a track whose audio is not here.
        let candidates = root.appendingPathComponent("candidates.json")
        let rows: [[String: Any]] = [
            ["id": Self.labID, "title": "Test track", "path": "/Lab/Music/\(Fixture.firstTrack)", "bpm_tag": NSNull()],
            ["id": "fake000002", "title": "Missing", "path": "/Lab/Music/CD9/missing.mp3", "bpm_tag": 128],
        ]
        try JSONSerialization.data(withJSONObject: rows).write(to: candidates)
        try Data("{}".utf8).write(to: features.appendingPathComponent("fake000002.json"))
        // research R's per-track keys beside the features folder, as mixer/key_parity_keys.tsv sits beside
        // mixer/features: the track's row holds the engine's own decision, so the column reads "same".
        let p = analysis.hpcpKey.decision
        try Data(("id\tkey_3f\tmargin\tagree\tsure\tlab\tlab_confident\tapple\n"
                  + "\(Self.labID)\t\(p.camelot)\t\(String(format: "%.4f", p.margin))\t\(p.agree)\t\(p.sure ? 1 : 0)\t8A\t1\t\n"
                  + "fake000002\t8A\t0.1000\t3\t1\t8A\t1\t8A\n").utf8)
            .write(to: root.appendingPathComponent("key_parity_keys.tsv"))

        let records = root.appendingPathComponent("records")
        let output = root.appendingPathComponent("bench.json")
        let report = try await CPUTurns.exclusive {
            try Bench.run(BenchOptions(folder: music, features: features, candidates: candidates, output: output,
                                       records: records, jobs: 1), analyser: analyser, progress: { print($0) })
        }
        print(report.table)
        #expect(report.musicRoot == "/Lab/Music" && report.candidates == 2 && report.reused == 0)
        #expect(report.notFound.map(\.id) == ["fake000002"] && report.notFound.map(\.rel) == ["CD9/missing.mp3"])
        let s = try #require(report.scores.first)
        #expect(report.scores.count == 1 && s.id == Self.labID && s.rel == Fixture.firstTrack && s.seconds != nil)
        #expect(s.beatFDetected == 1 && s.beatFGrid == 1 && s.beatFBestOctave == 1)
        #expect(s.downbeatFDetected == 1 && s.downbeatFGrid == 1)
        #expect(s.bpmRatio == 1 && s.tempoWithin2 && s.tempoWithin2Octave && !s.octaveApart)
        #expect(s.keyRelation == "exact" && s.keyConfidenceLab == 0.9)
        #expect(s.keyParity == "same" && report.summary.keyParityTracks == 1 && report.summary.keyParitySame == 1)
        #expect(report.table.contains("key vs key_parity.py") && report.table.contains("1 of 1 the same"))
        #expect(s.lufsDelta == 0 && s.truePeakDelta == 0)
        #expect(s.sectionRecall == nil || s.sectionRecall == 1)
        if analysis.vocal == nil {
            #expect(s.vocalR == nil && s.vocalNote == "absent on both sides" && report.vocalModel == nil)
        } else {  // with the vocal tagger's model installed: the same series on both sides
            #expect(s.vocalR.map { abs($0 - 1) < 1e-9 } ?? true, "\(s.vocalNote)")
        }
        #expect(s.bar1OffsetMs == 0 && s.nBarsMatch)
        #expect(report.summary.charterPass == true, "\(report.summary.marks.filter { $0.charter && $0.pass != true })")
        #expect(report.table.contains("charter pass marks: all met"))
        // The JSON and the engine's record for the lab's tools.
        let json = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: output)) as? [String: Any])
        #expect(json["compared"] as? Int == 1 && (json["tracks"] as? [Any])?.count == 1)
        let summary = try #require(json["summary"] as? [String: Any])
        #expect(summary["charter_pass"] as? Bool == true && (summary["pass_marks"] as? [Any])?.count == report.summary.marks.count)
        #expect(FileManager.default.fileExists(atPath: records.appendingPathComponent("\(Self.labID).json").path))

        // Against a copy with every beat and bar 100 ms late and the tempo doubled: no beat within 70 ms, the
        // tempo an octave apart (right after octave normalisation), bar 1 100 ms early. The engine's record is
        // taken from the records folder, so nothing is analysed again.
        let moved = try Self.edit(labJSON) { obj in
            for k in ["beats_s", "downbeats_s", "detected_beats_s", "detected_downbeats_s"] {
                obj[k] = (obj[k] as! [Double]).map { $0 + 0.1 }
            }
            var grid = obj["grid"] as! [String: Any]
            grid["first_downbeat_s"] = (grid["first_downbeat_s"] as! Double) + 0.1
            grid["bpm"] = (grid["bpm"] as! Double) * 2
            obj["grid"] = grid
            obj["bpm"] = (obj["bpm"] as! Double) * 2
        }
        try moved.write(to: shifted.appendingPathComponent("\(Self.labID).json"))
        let report2 = try Bench.run(BenchOptions(folder: music, features: shifted, candidates: candidates,
                                                 records: records, jobs: 1), analyser: analyser)
        print(report2.table)
        let m = try #require(report2.scores.first)
        #expect(report2.reused == 1 && m.seconds == nil)
        #expect(m.beatFDetected == 0 && m.beatFGrid == 0 && m.downbeatFDetected == 0 && m.downbeatFGrid == 0)
        #expect(m.beatFBestOctave == 0)
        #expect(abs(m.bpmRatio - 0.5) < 1e-9 && !m.tempoWithin2 && m.octaveApart && m.tempoWithin2Octave)
        #expect(abs(m.bar1OffsetMs + 100) < 1e-6 && m.keyRelation == "exact" && m.lufsDelta == 0)
        #expect(report2.summary.charterPass == false)
        #expect(report2.summary.marks.first { $0.name.hasPrefix("beat F@70ms, detected") }?.pass == false)
        #expect(report2.summary.marks.first { $0.name.hasPrefix("integrated loudness, median") }?.pass == true)
    }
}
