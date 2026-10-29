import Foundation
import Testing
import DeckieAudio
import DeckieCore
import DeckieCrate
import DeckieDecode
import DeckieEngine
import DeckieInference
import DeckieLab
import DeckieTestSupport

/// Whether ONNX Runtime and the Beat This! model are there; the reason is printed once when not.
enum Available {
    static let engine: Bool = {
        guard let lib = OnnxRuntime.locateLibrary() else {
            print("ONNX Runtime not found (looked at: \(OnnxRuntime.libraryCandidates().joined(separator: ", "))): the "
                  + "engine tests are skipped; run core/Tools/fetch-onnxruntime.sh or set "
                  + "\(OnnxRuntime.libraryEnvironmentVariable)")
            return false
        }
        guard BeatTracker.locateModel() != nil else {
            print("Beat This! model not found (looked at: \(BeatTracker.modelCandidates().joined(separator: ", "))): "
                  + "the engine tests are skipped (ONNX Runtime is at \(lib)); run core/Tools/export_beat_this.py or set "
                  + "\(BeatTracker.modelEnvironmentVariable)")
            return false
        }
        return true
    }()

    static let ffmpeg: String? = {
        let found = findFFmpeg()
        if found == nil { print("the ffmpeg program was not found: the MP3 engine test is skipped") }
        return found
    }()
}

/// A vocal tagger for the tests: singing over bars 9 to 24, none elsewhere.
struct StubVocalTagger: VocalTagger {
    var modelName: String { "stub-vocal" }
    func vocalActivity(mono: [Float], sampleRate: Int, barTimes: [Double]) throws -> VocalActivity {
        let n = barTimes.count - 1
        let p = (0..<n).map { (8..<24).contains($0) ? 0.9 : 0.1 }
        return VocalActivity(perBar: p, meanProbability: p.reduce(0, +) / Double(n), frameHopSeconds: 0.992,
                             frameCount: 64)
    }
}

/// The test track, written once, and each analysis of it made once, shared by the tests. Analyses take turns on the
/// processor (`CPUTurns`) so the stage times they print mean something.
actor Shared {
    static let shared = Shared()

    struct Run: Sendable {
        var analysis: Analysis
        /// Wall-clock seconds of `analyse`, the model load excluded.
        var seconds: Double
    }

    private var track: (url: URL, buffer: AudioBuffer)?
    private var analyser: Analyser?
    private var runs: [String: Task<Run, Error>] = [:]

    func testTrack() throws -> (url: URL, buffer: AudioBuffer) {
        if let track { return track }
        let buffer = TestTrack.render()
        let url = try temporaryFolder("track").appendingPathComponent("test-track.wav")
        try TestTrack.wav(buffer).write(to: url)
        track = (url, buffer)
        return (url, buffer)
    }

    /// The analyser without a vocal tagger, whatever is installed: the runs on the test track check the record a
    /// machine without the vocal model writes.
    func engine() throws -> Analyser {
        if let analyser { return analyser }
        let a = try Analyser(beatTracker: nil, vocalTagger: nil)
        analyser = a
        return a
    }

    private var vocalTrackFile: URL?

    /// The vocal test track (`VocalTrack`) as a stereo float WAV: the instruments slightly wider on the left, the voice
    /// in the middle.
    func vocalTrack() throws -> URL {
        if let vocalTrackFile { return vocalTrackFile }
        let (instruments, voice) = VocalTrack.parts(rate: TestTrack.rate)
        var stereo = [Float](repeating: 0, count: 2 * instruments.count)
        for i in 0..<instruments.count {
            stereo[2 * i] = Float(0.5 * (instruments[i] + voice[i]))
            stereo[2 * i + 1] = Float(0.5 * (0.9 * instruments[i] + voice[i]))
        }
        let url = try temporaryFolder("track").appendingPathComponent("vocal-track.wav")
        try TestTrack.wav(AudioBuffer(sampleRate: TestTrack.rate, channelCount: 2, samples: stereo)).write(to: url)
        vocalTrackFile = url
        return url
    }

    private var structureTrackFile: URL?

    /// The vocal-structure test track (`VocalStructureTrack`: 40 bars, sung from a pickup before bar 9 to bar 16 and
    /// over bars 25 to 32) as a stereo float WAV.
    func structureTrack() throws -> URL {
        if let structureTrackFile { return structureTrackFile }
        let url = try temporaryFolder("track").appendingPathComponent("vocal-structure-track.wav")
        try TestTrack.wav(VocalStructureTrack.render(rate: TestTrack.rate)).write(to: url)
        structureTrackFile = url
        return url
    }

    /// The test track as a 192 kbps MP3, made with the ffmpeg program.
    func mp3() throws -> URL {
        let (wav, _) = try testTrack()
        let url = wav.deletingPathExtension().appendingPathExtension("mp3")
        if !FileManager.default.fileExists(atPath: url.path) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: Available.ffmpeg!)
            p.arguments = ["-y", "-hide_banner", "-loglevel", "error", "-i", wav.path, "-codec:a", "libmp3lame",
                           "-b:a", "192k", url.path]
            try p.run()
            p.waitUntilExit()
            if p.terminationStatus != 0 { throw CocoaError(.fileWriteUnknown) }
        }
        return url
    }

    private var damaged: (url: URL, frame: DamagedFrame)?

    /// That MP3 with one frame near 30 s damaged so its big values run past the granule's end (`MP3Damage`), and the
    /// frame as the decoder reports it.
    func damagedMP3() throws -> (url: URL, frame: DamagedFrame) {
        if let damaged { return damaged }
        let url = try mp3().deletingLastPathComponent().appendingPathComponent("test-track-damaged.mp3")
        guard let frame = try MP3Damage.damagedCopy(of: try mp3(), nearSeconds: 30, to: url) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSLocalizedDescriptionKey: "no damage the decoder flags"])
        }
        damaged = (url, frame)
        return (url, frame)
    }

    /// The analysis of the WAV ("wav"), of its MP3 ("mp3"), of that MP3 with a damaged frame ("damaged"), of the WAV
    /// with the stub vocal tagger ("vocal"), of the vocal test track by the default analyser, which loads YAMNet
    /// ("yamnet"), or of the vocal-structure test track by the default analyser ("structure").
    func run(_ name: String) async throws -> Run {
        if let task = runs[name] { return try await task.value }
        let (wav, _) = try testTrack()
        let base = try engine()
        let url: URL
        switch name {
        case "yamnet":
            url = try vocalTrack()
        case "structure":
            url = try structureTrack()
        case "mp3":
            url = try mp3()
        case "damaged":
            url = try damagedMP3().url
        default:
            url = wav
        }
        let analyser: Analyser
        switch name {
        case "vocal": analyser = try Analyser(beatTracker: base.beatTracker, vocalTagger: StubVocalTagger())
        case "yamnet", "structure": analyser = try Analyser(beatTracker: base.beatTracker)
        default: analyser = base
        }
        let task = Task.detached {
            try await CPUTurns.exclusive {
                let t0 = Date()
                let title = name == "yamnet" ? "Vocal test track" : name == "structure" ? "Vocal structure test track" : "Test track"
                let a = try analyser.analyse(url: url, options: AnalysisOptions(title: title))
                return Run(analysis: a, seconds: Date().timeIntervalSince(t0))
            }
        }
        runs[name] = task
        return try await task.value
    }
}

func describe(_ a: Analysis) -> String {
    let t = a.timings.map { "\($0.stage) \(Py.fixed($0.seconds, 2))" }.joined(separator: ", ")
    return "\(a.source.name): bpm \(Py.fixed(a.bpm, 3)), bar 1 at \(Py.fixed(a.bars.firstDownbeatS, 4)) s, "
        + "\(a.bars.nBars) bars, key \(a.hpcpKey.decision.camelot) (margin \(Py.fixed(a.hpcpKey.decision.margin, 4)), "
        + a.hpcpKey.decision.profileKeys.map { "\($0.name) \($0.camelot) r \(Py.fixed($0.r, 3))" }.joined(separator: ", ")
        + ", stft edma \(a.key.whole.camelot); confidence \(a.keyConfidence.value)), sound \(Py.fixed(a.firstSound, 2))"
        + " to \(Py.fixed(a.lastSound, 2)) s, fade \(a.fade.fadeOut) from bar \(a.fade.fadeStartBar.map(String.init) ?? "-"), "
        + "mix in \(a.mixIn.startBar)-\(a.mixIn.endBar), mix out \(a.mixOut.startBar)-\(a.mixOut.endBar), "
        + "integrated \(a.loudness.integratedLufs.map { Py.fixed($0, 2) } ?? "-") LUFS, flags \(a.flags)\n  stages: \(t)"
}

@Suite(.enabled(if: Available.engine, "needs ONNX Runtime (core/Tools/fetch-onnxruntime.sh) and the Beat This! model (core/Tools/export_beat_this.py)"))
struct EngineTests {
    /// The test track end to end: tempo, bar 1, bar count, key, first and last sound, fade, mix windows, loudness,
    /// per-bar series; and the time it takes.
    @Test func analysesTheTestTrack() async throws {
        let run = try await Shared.shared.run("wav")
        let a = run.analysis
        let (_, buffer) = try await Shared.shared.testTrack()
        print(describe(a))
        print("analyse took \(Py.fixed(run.seconds, 2)) s for \(Py.fixed(a.duration, 1)) s of audio "
              + "(stages add up to \(Py.fixed(a.totalSeconds, 2)) s)")

        #expect(abs(a.bpm - TestTrack.bpm) < 0.5, "bpm \(a.bpm)")
        // Bar 1 at the first downbeat, the first accented beat; the bars that fit before the end.
        #expect(abs(a.bars.firstDownbeatS - TestTrack.firstBeat) < 0.03, "bar 1 at \(a.bars.firstDownbeatS)")
        #expect(abs(a.bars.nBars - TestTrack.bars) <= 1, "\(a.bars.nBars) bars")
        #expect(a.key.whole.camelot == TestTrack.camelot)
        // The key by the HPCP method, from the 44.1 kHz mono mix: the record's key and the windows' song key; its
        // parity decision (key_light.py's profile numbers) agrees here; the confidence is the sure rule's.
        #expect(a.hpcpKey.decision.camelot == TestTrack.camelot && a.hpcpKey.parity.camelot == TestTrack.camelot)
        #expect(a.hpcpKey.frames == HPCPKey.frameCount(samples: Int((a.duration * 44100).rounded())))
        #expect(a.hpcpKey.decision.profileKeys.map(\.name) == ["edma", "bgate", "braw"])
        #expect(a.key.songKey == a.hpcpKey.decision.camelot && a.keyConfidence == KeyConfidence.hpcp(a.hpcpKey.decision))
        #expect(a.flags.contains("key_uncertain") == !a.hpcpKey.decision.sure)
        // First and last sound: the 10 ms frames around the first and last sample above -60 dBFS.
        let bounds = TestTrack.soundBounds(buffer)
        #expect(abs(a.firstSound - bounds.first) < 0.0101, "first sound \(a.firstSound), samples say \(bounds.first)")
        #expect(abs(a.lastSound - bounds.last) < 0.0101, "last sound \(a.lastSound), samples say \(bounds.last)")
        // The fade over the last 8 bars starts after the last body-level bar: bar 25 or 26 (the first fade bar is
        // only 3 dB down on average, within the lab's 2 LU of the median bar).
        #expect(a.fade.fadeOut)
        let fadeBar = TestTrack.bars - TestTrack.fadeBars + 1
        #expect((fadeBar...(fadeBar + 2)).contains(a.fade.fadeStartBar ?? 0), "fade from bar \(a.fade.fadeStartBar ?? 0)")
        #expect(a.flags.contains("fade_out") && a.flags.contains("vocal_unknown"))
        // Mix windows inside the track, ending on the snapping lattice, the mix-out before the fade.
        let n = a.bars.nBars
        for (name, start, end) in [("mix_in", a.mixIn.startBar, a.mixIn.endBar), ("mix_out", a.mixOut.startBar, a.mixOut.endBar)] {
            #expect(start >= 1 && end <= n + 1 && end > start, "\(name) \(start)-\(end)")
            #expect(MixWindows.isOnLattice(end, snapPhaseBar: a.phrase.snapPhaseBar), "\(name) ends at \(end)")
            #expect(MixWindows.isOnLattice(start, snapPhaseBar: a.phrase.snapPhaseBar), "\(name) starts at \(start)")
        }
        #expect(a.mixIn.startBar == 1)
        #expect(a.mixOut.endBar <= (a.fade.fadeStartBar ?? n + 1))
        // Loudness: the whole track's integrated loudness within 1 LU of the body's synthesised level (the quiet intro
        // and the deep end of the fade fall below the relative gate); the body's bars, and the intro's 15 dB down.
        let integrated = try #require(a.loudness.integratedLufs)
        #expect(abs(integrated - TestTrack.bodyLufs) < 1, "integrated \(integrated)")
        let bodyBars = a.perBar.lufsSt[10..<22]
        #expect(bodyBars.allSatisfy { abs($0 - TestTrack.bodyLufs) < 1.5 }, "body bars \(Array(bodyBars))")
        let introBars = a.perBar.lufsSt[1..<7]
        #expect(introBars.allSatisfy { abs($0 - (TestTrack.bodyLufs + TestTrack.introDB)) < 1.5 }, "intro \(Array(introBars))")
        #expect(a.loudness.lra != nil && a.loudness.truePeakDb < 0)
        // Every per-bar series has one value per bar; the vocal ones are absent.
        for (name, series) in [("lufs_st", a.perBar.lufsSt), ("low_db", a.perBar.lowDb), ("high_db", a.perBar.highDb),
                               ("onset_density", a.perBar.onsetDensity)] {
            #expect(series.count == n, "\(name): \(series.count) values for \(n) bars")
        }
        #expect(a.perBar.vocalProb == nil && a.vocal == nil)
        #expect(a.onsetPattern16.count == 16)
        // The id is the file's hash.
        #expect(a.id.count == 16 && a.source.sha256.hasPrefix(a.id))
        #expect(a.timings.map(\.stage) == ["hash", "decode", "resample", "beatthis", "key", "spectral", "structure",
                                           "loudness", "windows"])
        // Speed: a 60 s track in under 30 s in a debug build.
        #expect(run.seconds < 30, "took \(run.seconds) s")
    }

    /// The JSON has the lab's keys (checked against a committed lab file), decodes through DeckieLab's FeatureFile,
    /// and its numbers are rounded as the lab rounds them.
    @Test func jsonHasTheLabShape() async throws {
        let a = try await Shared.shared.run("wav").analysis
        let json = a.labJSON()
        let data = json.data
        let f = try JSONDecoder().decode(FeatureFile.self, from: data)
        #expect(f.id == a.id && f.grid.nBars == a.bars.nBars && f.perBar.vocalProb == nil && f.embeddingEffnet == nil)
        #expect(f.grid.source == Analysis.gridSource && f.key.camelot == a.hpcpKey.decision.camelot)
        #expect(f.key.confidence == a.keyConfidence.value && [1.0, 0.45].contains(f.key.confidence))
        #expect(json["key"]?["confidence_rule"] == .string(a.keyConfidence.rule))
        let dk = try #require(json["deckie"]?["key"])
        #expect(dk.keys == ["estimator", "whitening", "frames", "camelot", "key", "scale", "r", "margin", "agree", "sure",
                            "tables", "profiles", "parity", "stft_edma", "song_key", "windows_estimator", "mix_in",
                            "mix_out", "segments"])
        #expect(dk["estimator"] == .string("hpcp-whitened") && dk["whitening"] == .bool(true))
        #expect(dk["margin"] == .number(Py.round(a.hpcpKey.decision.margin, 4)) && dk["sure"] == .bool(a.hpcpKey.decision.sure))
        #expect(dk["profiles"]?.keys == ["edma", "bgate", "braw"] && dk["parity"]?["tables"] == .string("key_light"))
        #expect(dk["stft_edma"]?["camelot"] == .string(a.key.whole.camelot))
        #expect(f.localTempo?.bpmIn != nil)
        // The local tempo block decodes as the lab's and the port's input reads back from the file.
        #expect(f.localTempoInput.bpm == Py.round(a.bpm, 3))

        // Keys against a committed lab feature file: the same, less the vocal block and the embedding, plus the
        // engine's own block.
        let labURL = repositoryRoot.appendingPathComponent("mixer/features/0327cf1c94.json")
        let lab = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: labURL)) as? [String: Any])
        let ours = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let absent: Set<String> = ["vocal", "embedding_effnet"]
        #expect(Set(ours.keys) == Set(lab.keys).subtracting(absent).union(["deckie"]))
        for block in ["grid", "phrase", "mix_in", "mix_out", "key", "loudness", "end_lufs_st", "local_tempo", "meta"] {
            let l = try #require(lab[block] as? [String: Any]), o = try #require(ours[block] as? [String: Any])
            #expect(Set(o.keys) == Set(l.keys), "\(block): \(Set(o.keys).symmetricDifference(l.keys))")
        }
        let perBar = try #require(ours["per_bar"] as? [String: Any]), labPerBar = try #require(lab["per_bar"] as? [String: Any])
        #expect(Set(perBar.keys) == Set(labPerBar.keys).subtracting(["vocal_prob"]))
        let sections = try #require(ours["sections"] as? [[String: Any]]), labSections = try #require(lab["sections"] as? [[String: Any]])
        #expect(Set(sections[0].keys) == Set(labSections[0].keys))
        // Rounding: a few fields, as analyze.py's out dict rounds them.
        #expect(json["grid"]?["first_downbeat_s"] == .number(Py.round(a.bars.firstDownbeatS, 4)))
        #expect(json["grid"]?["beat_s"] == .number(Py.round(a.bars.beatS, 5)))
        #expect(json["bpm"] == .number(Py.round(a.bpm, 3)))
        #expect(json["mix_in"]?["vocal_free_bars"] == .null && json["madmom_ran"] == .bool(false))
        #expect(json["downbeats_s"].map { if case .array(let v) = $0 { return v.count } else { return 0 } } == a.bars.nBars + 1)
        #expect(json["deckie"]?["vocal_unknown"] == .bool(true))
        let written = try temporaryFolder("json").appendingPathComponent("\(a.id).json")
        try data.write(to: written)
        print("lab-shaped record: \(data.count) bytes, written to \(written.path); key block \(json["key"]!.text); deckie.key \(json["deckie"]!["key"]!.text)")
    }

    /// The crate record: engine family `deckie`, no vocal block, and a crate holding it validates, writes and reads back.
    @Test func crateTrackValidates() async throws {
        let a = try await Shared.shared.run("wav").analysis
        let t = a.crateTrack(options: .init(analysedAt: "2026-10-28T12:00:00Z"))
        #expect(t.engine.family == "deckie" && t.analysis.engine == "deckie-\(Analysis.engineVersion)")
        #expect(t.file.sha256 == a.source.sha256 && t.id == CrateIDs.id(forSHA256: a.source.sha256))
        #expect(!t.featuresPresent.contains("vocal") && !t.featuresPresent.contains("bars.vocal"))
        #expect(t.featuresPresent.contains("bars.lufs") && t.featuresPresent.contains("key_changes"))
        #expect(t.mixIn?.vocalFreeBars == nil && t.vocal == nil && t.style == nil && t.flags.contains("vocal_unknown"))
        // The key decided by the HPCP method: its three profiles' keys and the STFT estimate in the votes, none
        // deciding; the sure rule's confidence.
        let d = a.hpcpKey.decision
        #expect(t.key?.source == "hpcp-whitened" && t.key?.camelot == d.camelot && t.key?.confidence == a.keyConfidence.value)
        #expect(t.key?.votes == ["hpcp_edma": d.profileKeys[0].camelot, "hpcp_bgate": d.profileKeys[1].camelot,
                                 "hpcp_braw": d.profileKeys[2].camelot, "stft_edma": a.key.whole.camelot])
        #expect(t.key?.key == d.key && t.key?.scale == d.mode)
        let crate = Crate(manifest: CrateManifest(crateId: "engine-test", name: "engine test",
                                                  createdAt: "2026-10-28T12:00:00Z", devicesSeen: [Analysis.platform]),
                          tracks: [t])
        let problems = crate.problems()
        #expect(problems.isEmpty, "\(problems)")
        let folder = try temporaryFolder("crate").appendingPathComponent("engine.deckiecrate")
        try? FileManager.default.removeItem(at: folder)
        try CrateWriter.write(crate, to: folder)
        let back = try CrateReader.read(from: folder)
        #expect(back == crate)
        print("crate record: features \(t.featuresPresent); key changes \(t.key?.changes ?? [])")
    }

    /// The same audio as an MP3 (made with the ffmpeg program) gives the same bars and tempo.
    @Test(.enabled(if: Available.ffmpeg != nil, "needs the ffmpeg program to make the MP3"))
    func mp3GivesTheSameBarsAndTempo() async throws {
        let wav = try await Shared.shared.run("wav").analysis
        let mp3 = try await Shared.shared.run("mp3").analysis
        print(describe(mp3))
        #expect(mp3.source.format == "MP3" && mp3.id != wav.id)
        #expect(mp3.bars.nBars == wav.bars.nBars)
        #expect(abs(mp3.bpm - wav.bpm) < 0.05, "mp3 \(mp3.bpm), wav \(wav.bpm)")
        #expect(abs(mp3.bars.firstDownbeatS - wav.bars.firstDownbeatS) < 0.02)
        #expect(mp3.key.whole.camelot == wav.key.whole.camelot)
        #expect(mp3.hpcpKey.decision.camelot == wav.hpcpKey.decision.camelot)
        #expect(mp3.damagedFrames.isEmpty && wav.damagedFrames.isEmpty)
    }

    /// The MP3 with a damaged frame near 30 s: the decoder plays the frame as silence and reports it, and the record
    /// carries it, as `deckie.damaged_frames` in the lab JSON and `file.damaged_frames` in the crate (null for the clean
    /// MP3); everything else is measured on the concealed audio (26 ms of silence in 63 s), so the bars, the tempo
    /// and the key are the clean MP3's, and the true peak stays within the concealment's fade of it.
    @Test(.enabled(if: Available.ffmpeg != nil, "needs the ffmpeg program to make the MP3"))
    func damagedMP3FrameReachesTheRecordAndTheCrate() async throws {
        let clean = try await Shared.shared.run("mp3").analysis
        let a = try await Shared.shared.run("damaged").analysis
        let frame = try await Shared.shared.damagedMP3().frame
        print(describe(a))
        #expect(a.damagedFrames == [frame])
        #expect(frame.startSeconds > 29.5 && frame.startSeconds < 30.5 && abs(frame.seconds - 1152.0 / 44100) < 1e-12)
        #expect(a.bars.nBars == clean.bars.nBars && abs(a.bpm - clean.bpm) < 1e-6)
        #expect(a.key.whole.camelot == clean.key.whole.camelot)
        #expect(a.hpcpKey.decision.camelot == clean.hpcpKey.decision.camelot)
        #expect(a.loudness.truePeakDb <= clean.loudness.truePeakDb + 1.7,
                "true peak \(a.loudness.truePeakDb) dBTP, the clean MP3's \(clean.loudness.truePeakDb)")

        let json = a.labJSON()
        let listed: JSONValue = .array([.object([.init("start_s", .number(Py.round(frame.startSeconds, 4))),
                                                 .init("seconds", .number(Py.round(frame.seconds, 4)))])])
        #expect(json["deckie"]?["damaged_frames"] == listed, "\(json["deckie"]?["damaged_frames"]?.text ?? "-")")
        #expect(clean.labJSON()["deckie"]?["damaged_frames"] == .null)

        let t = a.crateTrack(options: .init(analysedAt: "2026-10-29T12:00:00Z"))
        #expect(t.file.damagedFrames == [.init(startS: Py.round(frame.startSeconds, 4), seconds: Py.round(frame.seconds, 4))])
        #expect(clean.crateTrack(options: .init(analysedAt: "2026-10-29T12:00:00Z")).file.damagedFrames == nil)
        let crate = Crate(manifest: CrateManifest(crateId: "engine-test", name: "engine test",
                                                  createdAt: "2026-10-29T12:00:00Z", devicesSeen: [Analysis.platform]),
                          tracks: [t])
        #expect(crate.problems().isEmpty, "\(crate.problems())")
        let line = String(decoding: try CrateWriter.encode(crate)["crate.json"]!, as: UTF8.self)
        #expect(line.contains(#""damaged_frames":[{"seconds":0.0261,"start_s":"#), "\(line.prefix(400))")
        print("damaged MP3: frame at \(Py.fixed(frame.startSeconds, 4)) s; true peak \(Py.fixed(a.loudness.truePeakDb, 2)) "
              + "dBTP (the clean MP3 \(Py.fixed(clean.loudness.truePeakDb, 2))); deckie.damaged_frames "
              + "\(json["deckie"]?["damaged_frames"]?.text ?? "-")")
    }

    /// With a vocal tagger the record has the vocal block, the per-bar vocal probability and vocal-aware windows,
    /// and no `vocal_unknown`.
    @Test func vocalTaggerFeedsTheRecord() async throws {
        let a = try await Shared.shared.run("vocal").analysis
        #expect(a.perBar.vocalProb?.count == a.bars.nBars && !a.flags.contains("vocal_unknown"))
        // Singing from bar 9: the vocal-free intro is 8 bars, so mix-in is bars 1 to 8.
        #expect(a.mixIn.firstVocalBar == 9 && a.mixIn.endBar == 9 && a.mixIn.vocalFreeBars == 8)
        let json = a.labJSON()
        #expect(json["vocal"]?["n_patches"] == .int(64) && json["per_bar"]?["vocal_prob"] != nil)
        let f = try JSONDecoder().decode(FeatureFile.self, from: json.data)
        #expect(f.perBar.vocalProb?.count == a.bars.nBars)
        _ = try JSONDecoder().decode(FeatureFile.Structure.self, from: json.data)
        let t = a.crateTrack(options: .init(analysedAt: "2026-10-28T12:00:00Z"))
        #expect(t.featuresPresent.contains("vocal") && t.featuresPresent.contains("bars.vocal"))
        #expect(t.engine.models.map(\.name) == [Analysis.gridSource, "stub-vocal"])
        let crate = Crate(manifest: CrateManifest(crateId: "engine-test", name: "engine test",
                                                  createdAt: "2026-10-28T12:00:00Z", devicesSeen: []), tracks: [t])
        #expect(crate.problems().isEmpty)
    }
}
