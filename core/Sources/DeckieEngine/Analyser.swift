import Foundation
import DeckieAudio
import DeckieCore
import DeckieCrate
import DeckieDecode
import DeckieInference

/// What the engine cannot read from the audio file.
public struct AnalysisOptions: Sendable {
    /// The tag tempo (the discs' folder convention in the lab): steers the octave alignment and the tag comparisons
    /// (`bpm_tag`, `multiplier_vs_tag`, `bpm_agree`). Nil or 0: none.
    public var bpmTag: Double?
    /// The track's name; nil uses the file name without its extension.
    public var title: String?
    /// The cut's name, the lab's `ver`.
    public var version: String?

    public init(bpmTag: Double? = nil, title: String? = nil, version: String? = nil) {
        self.bpmTag = bpmTag
        self.title = title
        self.version = version
    }
}

/// Why a track could not be analysed (the decoder's own errors are `AudioDecodeError`, ONNX Runtime's
/// `OnnxRuntimeError`).
public enum AnalyserError: Error, Equatable, CustomStringConvertible {
    /// Fewer than 16 beats were detected, so no grid could be fitted (the lab's "no beat grid could be fitted").
    case noGrid
    /// Fewer than 8 whole bars fit on the grid (the lab's "only n bars on grid").
    case tooFewBars(Int)
    /// The vocal tagger gave a number of bars other than the grid's.
    case vocalBars(got: Int, bars: Int)

    public var description: String {
        switch self {
        case .noGrid: return "no beat grid could be fitted (too few beats)"
        case .tooFewBars(let n): return "only \(n) bars on grid"
        case .vocalBars(let got, let bars): return "the vocal tagger gave \(got) bar values for \(bars) bars"
        }
    }
}

/// The Windows and Linux analyser: mixer/analyze.py's `analyse()` in the lab's order, on the ported pieces.
///
///   hash       SHA-256 of the file's bytes (`CrateIDs`), whose first 16 hex characters are the record's id
///   decode     `AudioDecoder` (WAV, AIFF, MP3, FLAC), damaged MP3 frames silenced and listed (`damagedFrames`); not
///              44.1 kHz: `Resampler` to 44.1 kHz, as the lab resamples with soxr; mono is the channels' mean
///              (`AudioBuffer.mono`)
///   resample   the mono mix to 22,050 Hz (`Decimator.halve`, soxr's filter): what Beat This!, the STFT key estimator
///              and the spectral features all read (the lab resamples it once for the spectral features and Beat This!
///              again inside its package; the samples are the same)
///   beatthis   first and last sound (`SoundBounds`, on the stereo audio as the lab does); beats and downbeats from
///              `BeatTracker`, the only grid source (the lab's madmom fallback is non-commercial and not ported);
///              `BeatGrid.fit`; the octave alignment when a tag tempo is given (`OctaveAlign`)
///   key        the track's key by research R's whitened HPCP on the 44.1 kHz mono mix (`HPCPKey`), and the STFT
///              chroma (`KeyEstimator.chroma`) for the mix windows and segments; the lab runs its key detectors here
///   spectral   `SpectralFeatures` (mel, MFCC, RMS, onset strength) at 22,050 Hz; before it, the grid choice (one
///              candidate) and the bar grid (`BarGrid`), and the tag comparisons
///   structure  `FooteNovelty` and its peaks, `Phrase`, the boundaries
///   loudness   per-bar `lufs_st` (`KWeighted`), `low_db` and `high_db` (`BandSplit`), onset density, integrated
///              loudness, loudness range, true peak
///   vocal      only with a `VocalTagger` (by default `DeckieVocalTagger`, YAMNet, when its model is there): the
///              per-bar vocal probability on the mono mix at 44.1 kHz; the onset pattern is computed just before it
///   windows    sections, fade-out (`Loudness.shortTerm`, `FadeOut`), mix windows (`MixWindows`), with a tagger the
///              vocal structure (`VocalStructure`, from its frame-by-frame scores) and the hook candidates (`Hooks`),
///              the key's confidence (`KeyConfidence`, research R's sure rule), the key of both mix windows judged
///              against the key, local tempo, flags
///
/// The stage names are the lab's `timing_s` keys where a stage matches one (`decode`, `beatthis`, `key`, `spectral`,
/// `structure`, `loudness`); every step is inside one stage, so the times add up to the whole run.
public final class Analyser: Sendable {
    public let beatTracker: BeatTracker
    public let vocalTagger: (any VocalTagger)?
    /// Why there is no vocal tagger, when the default construction found none (the models that are missing and what
    /// to do); nil otherwise.
    public let vocalTaggerNote: String?

    /// The default analyser: `beatTracker` (nil loads the Beat This! model from where `BeatTracker` looks for it)
    /// and Deckie's vocal tagger (`DeckieVocalTagger.loadDefault()`, YAMNet) when its model is there. When it is not,
    /// the analyser runs without one (no vocal block in its records, the flag `vocal_unknown`) and
    /// `vocalTaggerNote` says what is missing. A model that is there but does not load is an error.
    public convenience init(beatTracker: BeatTracker? = nil) throws {
        let tracker = try beatTracker ?? BeatTracker()
        let tagger = try DeckieVocalTagger.loadDefault(runtime: tracker.session.runtime)
        let note = tagger == nil
            ? "no vocal tagger: " + DeckieVocalTagger.missingModels().map(\.description).joined(separator: "; ") : nil
        self.init(beatTracker: tracker, vocalTagger: tagger, note: note)
    }

    /// An analyser with `beatTracker` (nil loads the Beat This! model from where `BeatTracker` looks for it) and the
    /// given vocal tagger, or none.
    public convenience init(beatTracker: BeatTracker?, vocalTagger: (any VocalTagger)?) throws {
        self.init(beatTracker: try beatTracker ?? BeatTracker(), vocalTagger: vocalTagger, note: nil)
    }

    init(beatTracker: BeatTracker, vocalTagger: (any VocalTagger)?, note: String?) {
        self.beatTracker = beatTracker
        self.vocalTagger = vocalTagger
        self.vocalTaggerNote = note
    }

    /// Analyses the audio file at `url`.
    public func analyse(url: URL, options: AnalysisOptions = AnalysisOptions()) throws -> Analysis {
        let SR = Analysis.sampleRate
        var timings: [Analysis.Timing] = []
        var started = Date()
        func lap(_ stage: String) {
            let now = Date()
            timings.append(Analysis.Timing(stage: stage, seconds: now.timeIntervalSince(started)))
            started = now
        }

        // ------------------------------------------------------------------ hash
        // The file's bytes are let go as soon as they are hashed (the decoder reads the file itself), so they are not
        // held through the whole analysis: for a WAV that is as much memory again as the decoded audio.
        let sha: String, format: AudioFormat, bytes: Int
        do {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                let missing = !FileManager.default.fileExists(atPath: url.path)
                throw AudioDecodeError(kind: .cannotRead, file: url.path, format: .unknown,
                                       message: missing ? "no such file" : "could not be read (\(error))")
            }
            sha = CrateIDs.sha256(of: data)
            format = AudioFormat.sniff(data)
            bytes = data.count
        }
        lap("hash")

        // ------------------------------------------------------------------ decode (44.1 kHz, mono = channel mean)
        // A damaged MP3 frame comes out silent, and is listed (`damagedFrames`): everything below, the true peak
        // included, is measured on the audio as it plays, without the frame's burst.
        var buffer: AudioBuffer, damagedFrames: [DamagedFrame]
        do {
            // In a block of its own, so the decoded samples are not held beyond `buffer` once it is resampled.
            let decoded = try AudioDecoder.decodeReporting(url)
            buffer = decoded.buffer
            damagedFrames = decoded.damagedFrames
        }
        let sourceRate = buffer.sampleRate, sourceChannels = buffer.channelCount
        if buffer.sampleRate != SR { buffer = Resampler(from: buffer.sampleRate, to: SR).process(buffer) }
        let mono = buffer.mono()
        let duration = Double(mono.count) / Double(SR)
        lap("decode")

        // ------------------------------------------------------------------ the 22,050 Hz mono mix
        let m22 = Decimator.halve(mono)
        lap("resample")

        // ------------------------------------------------------------------ first / last sound, beats, grid
        let sound = SoundBounds(buffer)
        let tracked = try beatTracker.track(AudioBuffer(sampleRate: SpectralFeatures.sampleRate, channelCount: 1,
                                                        samples: m22))
        var beats = tracked.beats.beats, downbeats = tracked.beats.downbeats
        guard var gridBT = BeatGrid.fit(beats: beats, downbeats: downbeats) else { throw AnalyserError.noGrid }
        let tag = options.bpmTag.flatMap { $0 != 0 ? $0 : nil }
        var octaveFix: OctaveFix? = nil
        if tag != nil {
            let aligned = OctaveAlign.align(beats: beats, downbeats: downbeats, grid: gridBT, bpmTag: tag, mono: mono,
                                            sampleRate: SR)
            beats = aligned.beats
            downbeats = aligned.downbeats
            gridBT = aligned.grid
            octaveFix = aligned.fix
        }
        lap("beatthis")

        // ------------------------------------------------------------------ key (the windows' keys come later)
        let hpcpKey = try HPCPKey.estimate(mono, sampleRate: SR)
        let chroma = try KeyEstimator.chroma(m22, sampleRate: KeyEstimator.sampleRate)
        lap("key")

        // ------------------------------------------------------------------ grid choice and bars
        func tagDev(_ g: GridFit) -> Double {
            guard let tag else { return 999.0 }
            return Tempo.closest(bpm: g.bpm, reference: tag, among: Tempo.octaveMultipliers).deviationPct
        }
        // The lab's madmom --auto rule, recorded so the Mac comparison knows where the lab's grid may differ. It
        // changes nothing else in the record, on purpose (decided after the first Mac bench, Oct 28, 2026, where it
        // fired on 55 of 373 tracks). "poor grid fit" is the very test that sets `low_grid_confidence`: the kept
        // grid's own confidence under 0.5, so a reader already sees a weak grid. "Beat This vs tag > 2%" fires on a
        // grid that fits (the engine's matched the lab's final grid to the beat on all 4 such tracks): the doubt is
        // the tag's, whose tempo the record carries beside the grid's, and capping `grid.confidence` for it would
        // give the fit's confidence a second meaning, which the crate format rules out.
        var madmomWouldRun: String? = nil
        if gridBT.confidence < 0.5 {
            madmomWouldRun = "poor grid fit"
        } else if tagDev(gridBT) > 2.0 {
            madmomWouldRun = "Beat This vs tag > 2%"
        }
        let G = gridBT  // the only candidate
        let P = G.period
        guard let bars = BarGrid(gridDownbeat: G.firstDownbeat, beatS: P, firstSound: sound.firstSound,
                                 duration: duration) else {
            let fd = BarGrid.firstBar(gridDownbeat: G.firstDownbeat, beatS: P, firstSound: sound.firstSound)
            throw AnalyserError.tooFewBars(BarGrid.barCount(firstBar: fd, beatS: P, duration: duration))
        }
        let bpm = 60.0 / P
        var multTag = 1.0, devTag = 0.0, bpmAgree = false
        if let tag {
            (multTag, devTag) = Tempo.closest(bpm: bpm, reference: tag)
            bpmAgree = Tempo.closest(bpm: bpm, reference: tag, among: Tempo.octaveMultipliers).deviationPct < 1.0
        }

        // ------------------------------------------------------------------ spectral features (22.05 kHz)
        let spectral = SpectralFeatures(m22)
        lap("spectral")

        // ------------------------------------------------------------------ structure (Foote novelty)
        let novelty = spectral.novelty(grid: bars)
        let phrase = Phrase(peaks: novelty.peaks)
        let boundaries = Phrase.boundaries(peaks: novelty.peaks, latticePhaseBar: phrase.latticePhaseBar,
                                           nBars: bars.nBars)
        lap("structure")

        // ------------------------------------------------------------------ per-bar loudness, bands, onsets; loudness
        // The K-weighted running sum (8 bytes a sample) is needed only here, so it lives only in this block.
        let lufs: [Double], levels: BandSplit.Levels, loudness: Analysis.Loudness
        do {
            let kw = KWeighted(buffer)
            let barFrames = bars.barTimes.map { kw.frame(at: $0) }
            lufs = (0..<bars.nBars).map { kw.loudness(from: barFrames[$0], to: barFrames[$0 + 1]) }
            levels = BandSplit(sampleRate: SR).levels(mono, barFrames: barFrames)
            loudness = Analysis.Loudness(integratedLufs: Loudness.integrated(kw), lra: Loudness.range(kw),
                                         truePeakDb: TruePeak.decibels(buffer))
        }
        let onsetDensity = spectral.onsetDensity(grid: bars)
        lap("loudness")
        let pattern = spectral.onsetPattern(grid: bars, barLoudness: lufs)

        // ------------------------------------------------------------------ vocal probability (optional)
        var vocal: VocalActivity? = nil
        if let tagger = vocalTagger {
            let v = try tagger.vocalActivity(mono: mono, sampleRate: SR, barTimes: bars.barTimes)
            guard v.perBar.count == bars.nBars else { throw AnalyserError.vocalBars(got: v.perBar.count, bars: bars.nBars) }
            vocal = v
            lap("vocal")
        }
        // Without a tagger the lab has no path; every bar counts as vocal-free and the record is flagged vocal_unknown.
        let voc = vocal?.perBar ?? [Double](repeating: 0, count: bars.nBars)

        // ------------------------------------------------------------------ sections, fade-out, mix windows
        let sections = Section.sections(boundariesBars: boundaries, lufsSt: lufs, vocalProb: voc)
        let ls = sound.lastSound
        let end = EndLoudness(t20: Loudness.shortTerm(buffer, endingAt: ls - 17.0),
                              t10: Loudness.shortTerm(buffer, endingAt: ls - 7.0),
                              t4: Loudness.shortTerm(buffer, endingAt: ls - 1.0))
        let fade = FadeOut(endLoudness: end, lufsSt: lufs, grid: bars, firstSound: sound.firstSound, lastSound: ls)
        let (mixIn, mixOut) = MixWindows.windows(grid: bars, vocalProb: voc, boundariesBars: boundaries,
                                                 snapPhaseBar: phrase.snapPhaseBar, lastSound: ls,
                                                 fadeOut: fade.fadeOut, fadeStartBar: fade.fadeStartBar)

        // ------------------------------------------------------------------ vocal structure and hooks (with a tagger)
        // The tagger's frames when it gives them (YAMNet's patches, 0.48 s apart), otherwise its bars; the hooks
        // compare bars by the MFCC the novelty already averaged, on the novelty's own frame edges.
        var vocalStructure: VocalStructure? = nil
        var hooks: Hooks? = nil
        if let v = vocal {
            let frames = v.perFrame.map {
                VocalStructure.Frames(scores: $0, hopSeconds: v.frameHopSeconds,
                                      centreSeconds: v.frameCentreSeconds ?? v.frameHopSeconds / 2)
            } ?? .perBar(v.perBar, grid: bars)
            let structure = VocalStructure(frames: frames, grid: bars, latticePhaseBar: phrase.latticePhaseBar,
                                           lowDb: levels.lowDB, highDb: levels.highDB, onsetDensity: onsetDensity,
                                           fadeStartBar: fade.fadeOut ? fade.fadeStartBar : nil)
            let features = Hooks.barFeatures(mfcc: spectral.mfcc, halfBeatEdges: novelty.frameEdges)
            vocalStructure = structure
            hooks = Hooks(barSimilarity: Hooks.barSimilarity(features), lufs: lufs, vocalCoverage: structure.barCoverage,
                          latticePhaseBar: phrase.latticePhaseBar)
        }

        // ------------------------------------------------------------------ key: confidence, the two windows, segments
        // The song key is the HPCP method's (`HPCPKey`); the windows are judged against it, as the lab judged them
        // against the product's song key. mixer/key_light.py reads the windows from the feature file, rounded to 3
        // decimals.
        let key = KeyEstimator.estimate(chroma, mixIn: (Py.round(mixIn.startS, 3), Py.round(mixIn.endS, 3)),
                                        mixOut: (Py.round(mixOut.startS, 3), Py.round(mixOut.endS, 3)),
                                        songKey: hpcpKey.decision.camelot)
        let keyConfidence = KeyConfidence.hpcp(hpcpKey.decision)

        // ------------------------------------------------------------------ local tempo, from the rounded record
        let r3 = { (x: Double) in Py.round(x, 3) }
        let localTempo = LocalTempo.compute(LocalTempoInput(
            bpm: r3(bpm), duration: r3(duration), detectedBeats: beats.map(r3), detectedDownbeats: downbeats.map(r3),
            gridBeats: bars.beatTimes.map(r3), gridDownbeats: bars.barTimes.map(r3),
            firstDownbeat: Py.round(bars.firstDownbeatS, 4), firstSound: r3(sound.firstSound), lastSound: r3(ls),
            mixIn: .init(start: r3(mixIn.startS), end: r3(mixIn.endS)),
            mixOut: .init(start: r3(mixOut.startS), end: r3(mixOut.endS))))

        // ------------------------------------------------------------------ flags
        var flags = TrackFlags.flags(bpm: bpm, bpmTag: tag, vocalMeanProb: vocal?.meanProbability ?? 0,
                                     fadeOut: fade.fadeOut, gridConfidence: G.confidence,
                                     keyConfidence: keyConfidence.value, mixIn: mixIn, mixOut: mixOut,
                                     localTempoFlags: localTempo.flags)
        if vocal == nil { flags.append("vocal_unknown") }
        lap("windows")

        let path = url.path
        return Analysis(
            id: CrateIDs.id(forSHA256: sha), title: options.title ?? url.deletingPathExtension().lastPathComponent,
            version: options.version,
            source: .init(path: path, name: url.lastPathComponent, bytes: bytes, sha256: sha,
                          format: format.rawValue, sampleRate: sourceRate, channels: sourceChannels),
            duration: duration, bpmTag: tag, damagedFrames: damagedFrames, detectedBeats: beats,
            detectedDownbeats: downbeats, octaveFix: octaveFix,
            grid: G, bars: bars, multiplierVsTag: multTag, tagDevPct: devTag, bpmAgree: bpmAgree,
            madmomWouldRun: madmomWouldRun, noveltyPeaks: novelty.peaks, phrase: phrase, boundariesBars: boundaries,
            sections: sections, firstSound: sound.firstSound, lastSound: ls, endLoudness: end, fade: fade,
            mixIn: mixIn, mixOut: mixOut, key: key, hpcpKey: hpcpKey, keyConfidence: keyConfidence, loudness: loudness,
            perBar: .init(lufsSt: lufs, lowDb: levels.lowDB, highDb: levels.highDB, onsetDensity: onsetDensity,
                          vocalProb: vocal?.perBar),
            onsetPattern16: pattern, vocal: vocal, vocalModel: vocal == nil ? nil : vocalTagger?.modelName,
            vocalStructure: vocalStructure, hooks: hooks, flags: flags, localTempo: localTempo, timings: timings)
    }
}
