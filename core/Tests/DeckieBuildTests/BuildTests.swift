import Foundation
import Testing
import DeckieBuild
import DeckieCrate
import DeckieEngine
import DeckieTestSupport

/// A vocal tagger for the tests: singing over the middle half of the bars, and a style vector.
struct StyledStubTagger: VocalTagger {
    var modelName: String { "stub-styled" }
    func vocalActivity(mono: [Float], sampleRate: Int, barTimes: [Double]) throws -> VocalActivity {
        let n = barTimes.count - 1
        let p = (0..<n).map { $0 >= n / 4 && $0 < 3 * n / 4 ? 0.9 : 0.1 }
        let style = (0..<8).map { Double($0 + 1) / 14.2829 }
        return VocalActivity(perBar: p, meanProbability: p.reduce(0, +) / Double(n), frameHopSeconds: 0.48,
                             frameCount: 128, style: style, styleModel: modelName)
    }
}

/// A rekordbox export naming the folder's first track by its full path, percent-encoded as rekordbox writes it.
func rekordboxXML(for track: URL) -> String {
    let location = "file://localhost" + track.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
    return """
        <?xml version="1.0" encoding="UTF-8"?>
        <DJ_PLAYLISTS Version="1.0.0">
          <PRODUCT Name="rekordbox" Version="6.8.5" Company="AlphaTheta"/>
          <COLLECTION Entries="2">
            <TRACK TrackID="7" Name="Track One" Artist="The Synths" Mix="Extended Mix" AverageBpm="124.00" Tonality="Am"
                   Location="\(location)">
              <TEMPO Inizio="0.500" Bpm="124.00" Metro="4/4" Battito="1"/>
              <POSITION_MARK Name="Drop" Type="0" Start="16.629" Num="0"/>
              <POSITION_MARK Name="" Type="4" Start="8.242" End="16.000" Num="-1"/>
            </TRACK>
            <TRACK TrackID="8" Name="Not Here" AverageBpm="90.00" Location="file://localhost/elsewhere/not%20here.mp3"/>
          </COLLECTION>
          <PLAYLISTS>
            <NODE Type="0" Name="ROOT" Count="1">
              <NODE Name="Tonight" Type="1" KeyType="0" Entries="1"><TRACK Key="7"/></NODE>
            </NODE>
          </PLAYLISTS>
        </DJ_PLAYLISTS>
        """
}

@Suite(.enabled(if: Available.engine, "needs ONNX Runtime (core/Tools/fetch-onnxruntime.sh) and the Beat This! model (core/Tools/export_beat_this.py)"))
struct BuildTests {
    /// Builds the crate, reads it back, runs again (everything unchanged), touches a file (found again by its hash),
    /// and, with an MP3 carrying a tempo tag, builds with `--bpm-tags` (only that file is analysed again).
    @Test func buildsResumesAndLogsWhatItCannotRead() async throws {
        let music = try await Fixture.shared.music()
        let analyser = try await Fixture.shared.analyser()
        let out = try temporaryFolder("build")
        let xml = out.appendingPathComponent("collection.xml")
        try Data(rekordboxXML(for: music.appendingPathComponent(Fixture.firstTrack)).utf8).write(to: xml)
        let crateURL = out.appendingPathComponent("Test.deckiecrate")
        var options = BuildOptions(folder: music, output: crateURL, rekordbox: xml, jobs: 2, fresh: true)

        // First run: two records, two files logged with their reasons.
        let events1 = Events()
        let first = try await CPUTurns.exclusive {
            try Builder(options: options, analyser: analyser).run(progress: { events1.add($0) })
        }
        print(first.summary)
        for e in events1.all { print(ProgressText.line(e)) }
        #expect(first.filesSeen == 4 && first.analysed == 2 && first.reused == 0 && first.crate.tracks.count == 2)
        #expect(events1.started?.queued == 4)

        let crate = try CrateReader.read(from: crateURL)
        #expect(crate.tracks.count == 2)
        let log = try #require(crate.manifest.importLog)
        #expect(log.filesSeen == 4 && log.tracks == 2 && log.builtBy == options.device && log.builtBy == Analysis.platform)
        #expect(log.entries.map(\.rel) == ["CD2/broken.mp3", "locked.m4p"])
        #expect(log.entries.map(\.reason) == ["damaged", "protected"])
        #expect(log.entries.map(\.ext) == ["mp3", "m4p"])
        #expect(log.entries[0].message.contains("no complete MPEG audio frame"), "\(log.entries[0].message)")
        #expect(log.entries[1].message.hasPrefix("protected, cannot be read"), "\(log.entries[1].message)")
        #expect(log.counts == ["damaged": ["mp3": 1], "protected": ["m4p": 1]])
        #expect(log.rekordbox == .init(tracks: 2, matched: 1))
        #expect(!log.entries.contains { $0.message.contains(music.path) })  // no absolute paths
        #expect(first.summary.contains("protected") && first.summary.contains("damaged"))

        // The first track, named and steered by rekordbox.
        let one = try #require(crate.tracks.first { $0.file.rel == Fixture.firstTrack })
        #expect(one.ident.title == "Track One" && one.ident.artist == "The Synths" && one.ident.version == "Extended Mix")
        #expect(one.ident.source == "rekordbox-xml")
        #expect(one.key?.votes["rekordbox-xml"] == "8A" && one.key?.votes["deckie-key-edma"] != nil)
        #expect(one.deckie?.bpmTag == .init(bpm: 124, source: "rekordbox-xml"))
        let rb = try #require(one.deckie?.rekordbox)
        #expect(rb.trackId == "7" && rb.playlists == [["Tonight"]] && rb.grid.count == 1)
        #expect(rb.cues == [.init(name: "Drop", kind: "cue", hotCue: 0, startS: 16.629, endS: nil),
                            .init(name: "", kind: "loop", hotCue: nil, startS: 8.242, endS: 16)])
        #expect(abs((one.grid?.bpm ?? 0) - TestTrack.bpm) < 0.5 && one.engine.family == "deckie")
        #expect(one.file.sha256.map { $0.hasPrefix(one.id) } == true)
        // The second, named by its own tags (or its file name without ffmpeg); no tag tempo without --bpm-tags.
        let two = try #require(crate.tracks.first { $0.file.rel == Fixture.secondTrack })
        if Available.ffmpeg != nil {
            #expect(two.ident.title == "Track Two" && two.ident.artist == "Tagged Artist" && two.ident.source == "tag")
        } else {
            #expect(two.ident.title == "Track Two" && two.ident.source == "filename")
        }
        #expect(two.deckie == nil)

        // Second run: everything unchanged, nothing analysed, the same records.
        options.fresh = false
        let events2 = Events()
        let second = try Builder(options: options, analyser: analyser).run(progress: { events2.add($0) })
        print(second.summary)
        #expect(events2.started.map { [$0.files, $0.unchanged, $0.queued] } == [4, 4, 0])
        #expect(second.analysed == 0 && second.reused == 2)
        #expect(try CrateReader.read(from: crateURL).tracks == crate.tracks)
        #expect(try CrateReader.read(from: crateURL).manifest.crateId == crate.manifest.crateId)

        // A touched file (same bytes, new modification time) is found again by its hash.
        let wav = music.appendingPathComponent(Fixture.firstTrack)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)], ofItemAtPath: wav.path)
        let events3 = Events()
        let third = try Builder(options: options, analyser: analyser).run(progress: { events3.add($0) })
        #expect(events3.started.map { [$0.unchanged, $0.queued] } == [3, 1])
        #expect(events3.outcomes[Fixture.firstTrack] == .reused)
        #expect(third.analysed == 0 && third.reused == 2)

        // With --bpm-tags the MP3's own tempo tag steers its analysis, so it alone is analysed again.
        if Available.ffmpeg != nil {
            options.fileBPMTags = true
            let events4 = Events()
            let fourth = try await CPUTurns.exclusive {
                try Builder(options: options, analyser: analyser).run(progress: { events4.add($0) })
            }
            #expect(fourth.analysed == 1 && fourth.reused == 1)
            if case .analysed? = events4.outcomes[Fixture.secondTrack] {} else {
                Issue.record("the MP3 was not analysed again: \(String(describing: events4.outcomes[Fixture.secondTrack]))")
            }
            let tagged = try #require(try CrateReader.read(from: crateURL).tracks.first { $0.file.rel == Fixture.secondTrack })
            #expect(tagged.deckie?.bpmTag == .init(bpm: 124, source: "file-tag"))
        }
    }

    /// With a vocal tagger (a stand-in here, as YAMNet's model may not be installed), the records carry the vocal
    /// block, the per-bar vocal series and the style vector through the work folder into the crate; a record made
    /// without the tagger is not reused by a build with one.
    @Test func vocalRecordsSurviveTheWorkFolder() async throws {
        let music = try await Fixture.shared.music()
        let base = try await Fixture.shared.analyser()
        let folder = try temporaryFolder("vocal-music")
        try? FileManager.default.removeItem(at: folder.appendingPathComponent("one.wav"))
        try FileManager.default.copyItem(at: music.appendingPathComponent(Fixture.firstTrack),
                                         to: folder.appendingPathComponent("one.wav"))
        let out = try temporaryFolder("vocal-build").appendingPathComponent("Vocal.deckiecrate")
        let tagged = try Analyser(beatTracker: base.beatTracker, vocalTagger: StyledStubTagger())
        let options = BuildOptions(folder: folder, output: out, jobs: 1, fresh: true)
        let first = try await CPUTurns.exclusive { try Builder(options: options, analyser: tagged).run() }
        #expect(first.analysed == 1)
        var again = options
        again.fresh = false
        let second = try Builder(options: again, analyser: tagged).run()
        #expect(second.analysed == 0 && second.reused == 1)
        let t = try #require(try CrateReader.read(from: out).tracks.first)
        #expect(t.vocal?.source == "stub-styled" && t.bars?[BarSeries.vocal]?.count == t.grid?.nBars)
        #expect(t.style?.model == "stub-styled" && t.style?.values.count == 8 && !t.flags.contains("vocal_unknown"))
        // The same file with the plain analyser (no tagger, unless YAMNet's model is installed) is analysed again.
        if base.vocalTagger == nil {
            let third = try await CPUTurns.exclusive { try Builder(options: again, analyser: base).run() }
            #expect(third.analysed == 1)
            #expect(try CrateReader.read(from: out).tracks.first?.vocal == nil)
        }
    }

    /// An output that is not a crate is never overwritten.
    @Test func refusesToOverwriteSomethingElse() throws {
        let out = try temporaryFolder("not-a-crate")
        let target = out.appendingPathComponent("Mine.deckiecrate")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: target.appendingPathComponent("notes.txt"))
        let music = try temporaryFolder("empty-music")
        let builder = try Builder(options: BuildOptions(folder: music, output: target, jobs: 1))
        #expect(throws: BuildError.self) { try builder.run() }
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("notes.txt").path))
    }
}
