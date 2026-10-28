import Foundation
import Testing
import DeckieCrate
import DeckieLab

// The lab's committed feature files as crate records (FeatureFile+Crate.swift), and the example crate made from five
// of them (core/fixtures/example.deckiecrate, written by core/Tools/make_crate_fixture.sh).

/// A lab feature file as plain JSON, read apart from the converter, to compare against.
struct RawFeatures {
    let d: [String: Any]
    init(_ id: String) throws {
        d = try JSONSerialization.jsonObject(with: Data(contentsOf: Paths.features.appendingPathComponent("\(id).json")))
            as! [String: Any]
    }
    func any(_ path: String) -> Any? {
        var node: Any? = d
        for k in path.split(separator: ".") { node = (node as? [String: Any])?[String(k)] }
        return node is NSNull ? nil : node
    }
    func num(_ path: String) -> Double { (any(path) as! NSNumber).doubleValue }
    func int(_ path: String) -> Int { (any(path) as! NSNumber).intValue }
    func nums(_ path: String) -> [Double] { (any(path) as! [Any]).map { ($0 as! NSNumber).doubleValue } }
    func ints(_ path: String) -> [Int] { (any(path) as! [Any]).map { ($0 as! NSNumber).intValue } }
    func bool(_ path: String) -> Bool { any(path) as! Bool }
    func text(_ path: String) -> String { any(path) as! String }
}

@Suite struct LabCrateTests {
    static let options = FeatureFile.CrateOptions(analysedAt: "2026-10-26T00:00:00Z")

    @Test func everyCommittedFeatureFileConvertsAndRoundTrips() throws {
        let manifest = CrateManifest(crateId: "all", name: "All", createdAt: "2026-10-26T00:00:00Z", devicesSeen: ["lab-mac"])
        let crate = try FeatureFile.crate(featuresDir: Paths.features, candidatesFile: Paths.candidates,
                                          manifest: manifest, options: Self.options)
        #expect(crate.tracks.count == 373)
        #expect(crate.problems().isEmpty, "\(crate.problems().prefix(10))")
        let files = try CrateWriter.encode(crate)
        let back = try CrateReader.decode(files)
        #expect(back == crate)
        #expect(try CrateWriter.encode(back) == files)
        for (a, b) in zip(back.tracks, crate.tracks) where a != b { Issue.record("track \(a.id) reads back different") }

        // Each record against its feature file read as plain JSON.
        var clamped: [String] = []
        var largest = 0.0
        for t in back.tracks {
            let raw = try RawFeatures(t.id)
            let n = raw.int("grid.n_bars")
            #expect(t.grid?.nBars == n && t.grid?.bpm == raw.num("grid.bpm"), "\(t.id)")
            #expect(t.key?.camelot == raw.text("key.camelot") && t.mixIn?.endBar == raw.int("mix_in.end_bar"), "\(t.id)")
            #expect(t.mixOut?.startBar == raw.int("mix_out.start_bar") && t.flags == (raw.any("flags") as! [String]), "\(t.id)")
            #expect(t.ends?.steadyInBar == raw.int("local_tempo.steady_in_bar"), "\(t.id)")
            let steadyOut = raw.int("local_tempo.steady_out_bar")
            #expect(t.ends?.steadyOutBar == min(steadyOut, n + 1), "\(t.id)")
            if steadyOut > n + 1 { clamped.append(t.id) }
            for (name, lab) in [("lufs", "lufs_st"), ("low_db", "low_db"), ("high_db", "high_db"),
                                ("onset_density", "onset_density"), ("vocal", "vocal_prob")] {
                let want = raw.nums("per_bar.\(lab)")
                let got = try #require(t.bars?[name], "\(t.id) \(name)")
                #expect(got == want.map(Half.rounded), "\(t.id) \(name)")
                for (g, w) in zip(got, want) { largest = max(largest, abs(g - w)) }
            }
        }
        #expect(clamped.count == 21)
        #expect(largest <= 0.0313)
        print("lab to crate: 373 records, \(files.count) files, \(files.values.reduce(0) { $0 + $1.count }) bytes " +
              "(crate.json \(files["crate.json"]!.count)); steady_out_bar clamped on \(clamped.count); per-bar values " +
              "within \(largest) of the lab's")
    }

    @Test func theExampleCrateReadsAndMatchesItsSources() throws {
        let crate = try CrateReader.read(from: Paths.example)
        #expect(crate.manifest.name == "Example" && crate.enginesUsed == ["lab-1"])
        #expect(crate.tracks.map(\.id) == ["0327cf1c94", "04c326848f", "0692b134c9", "08e45fb8ca", "334614c3a0"])
        for t in crate.tracks {
            let raw = try RawFeatures(t.id)
            let n = raw.int("grid.n_bars")
            let grid = try #require(t.grid)
            #expect(grid.bpm == raw.num("grid.bpm") && grid.firstDownbeatS == raw.num("grid.first_downbeat_s"))
            #expect(grid.nBars == n && grid.confidence == raw.num("grid.confidence"))
            #expect(grid.bpmIn == raw.num("local_tempo.bpm_in") && grid.bpmOut == raw.num("local_tempo.bpm_out"))
            #expect(grid.source == (raw.text("grid.source") == "madmom" ? "madmom-rnn-dbn" : "beat-this-final0"))
            #expect(t.tempoSegments?.count == 1 && t.tempoSegments?[0].bpm == grid.bpm)
            #expect(t.key?.camelot == raw.text("key.camelot") && t.key?.confidence == raw.num("key.confidence"))
            #expect(t.phrase?.latticePhaseBar == raw.int("phrase.lattice_phase_bar"))
            #expect(t.phrase?.boundariesBars == raw.ints("boundaries_bars"))
            let sections = raw.any("sections") as! [[String: Any]]
            #expect(t.sections?.map(\.label) == sections.map { $0["label"] as! String })
            #expect(t.mixIn == .init(startBar: raw.int("mix_in.start_bar"), endBar: raw.int("mix_in.end_bar"),
                                     vocalFreeBars: raw.int("mix_in.vocal_free_bars")))
            #expect(t.mixOut == .init(startBar: raw.int("mix_out.start_bar"), endBar: raw.int("mix_out.end_bar"),
                                      vocalFreeBars: raw.int("mix_out.vocal_free_bars")))
            #expect(t.ends?.fadeOut == raw.bool("fade_out") && t.ends?.lastSoundS == raw.num("last_sound_s"))
            #expect(t.loudness?.integratedLufs == raw.num("loudness.integrated_lufs"))
            #expect(t.loudness?.lra == raw.num("loudness.lra") && t.loudness?.truePeakDb == raw.num("loudness.true_peak_db"))
            #expect(t.vocal?.mean == raw.num("vocal.mean_prob") && t.vocal?.heavy == raw.bool("vocal.vocal_heavy"))
            #expect(t.onsetPattern16 == raw.nums("onset_pattern_16") && t.flags == (raw.any("flags") as! [String]))
            #expect(t.bars?[BarSeries.lufs] == raw.nums("per_bar.lufs_st").map(Half.rounded))
            #expect(t.bars?[BarSeries.vocal]?.count == n && t.style == nil && t.signatures.isEmpty)
        }
        // What each was chosen for.
        let byId = Dictionary(uniqueKeysWithValues: crate.tracks.map { ($0.id, $0) })
        #expect(byId["0327cf1c94"]?.grid?.source == "madmom-rnn-dbn")
        #expect(try RawFeatures("0692b134c9").any("octave_fix") != nil)
        #expect(byId["04c326848f"]?.ends?.fadeOut == true && byId["04c326848f"]?.ends?.steadyOutBar == 151)
        #expect(byId["334614c3a0"]?.flags.contains("tempo_change") == true)
        #expect(byId["08e45fb8ca"]?.grid?.nBars == 44)
    }

    @Test func theExampleCrateIsWhatTheConverterMakesToday() throws {
        let committed = try CrateReader.read(from: Paths.example)
        let rebuilt = try FeatureFile.crate(featuresDir: Paths.features, ids: committed.tracks.map(\.id),
                                            candidatesFile: Paths.candidates, manifest: committed.manifest,
                                            options: Self.options)
        let files = try CrateWriter.encode(rebuilt)
        var total = 0
        for (path, data) in files {
            let onDisk = try Data(contentsOf: Paths.example.appendingPathComponent(path))
            #expect(onDisk == data, "\(path) differs from what the converter makes; run core/Tools/make_crate_fixture.sh")
            total += onDisk.count
        }
        #expect(total < 300_000)
        print("example crate: \(files.count) files, \(total) bytes")
    }
}
