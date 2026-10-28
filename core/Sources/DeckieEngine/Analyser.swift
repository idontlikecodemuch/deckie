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
///   decode     `AudioDecoder` (WAV, AIFF, MP3, FLAC); not 44.1 kHz: `Resampler` to 44.1 kHz, as the lab resamples
///              with soxr; mono is the channels' mean (`AudioBuffer.mono`)
///   resample   the mono mix to 22,050 Hz (`Decimator.halve`, soxr's filter): what Beat This!, the key estimator and
///              the spectral features all read (the lab resamples it once for the spectral features and Beat This!
///              again inside its package; the samples are the same)
///   beatthis   first and last sound (`SoundBounds`, on the stereo audio as the lab does); beats and downbeats from
///              `BeatTracker`, the only grid source (the lab's madmom fallback is non-commercial and not ported);
///              `BeatGrid.fit`; the octave alignment when a tag tempo is given (`OctaveAlign`)
///   key        chroma for the key estimator (`KeyEstimator.chroma`); the lab runs its key detectors here
///   spectral   `SpectralFeatures` (mel, MFCC, RMS, onset strength) at 22,050 Hz; before it, the grid choice (one
///              candidate) and the bar grid (`BarGrid`), and the tag comparisons
///   structure  `FooteNovelty` and its peaks, `Phrase`, the boundaries
///   loudness   per-bar `lufs_st` (`KWeighted`), `low_db` and `high_db` (`BandSplit`), onset density, integrated
///              loudness, loudness range, true peak
///   vocal      only with a `VocalTagger`; the onset pattern is computed just before it
///   windows    sections, fade-out (`Loudness.shortTerm`, `FadeOut`), mix windows (`MixWindows`), the key of the whole
///              track and of both mix windows with its confidence (`KeyConfidence`), local tempo, flags
///
/// The stage names are the lab's `timing_s` keys where a stage matches one (`decode`, `beatthis`, `key`, `spectral`,
/// `structure`, `loudness`); every step is inside one stage, so the times add up to the whole run.
public final class Analyser: Sendable {
    public let beatTracker: BeatTracker
    public let vocalTagger: (any VocalTagger)?

    /// An analyser with `beatTracker` (nil loads the Beat This! model from where `BeatTracker` looks for it) and an
    /// optional vocal tagger (none ships yet).
    public init(beatTracker: BeatTracker? = nil, vocalTagger: (any VocalTagger)? = nil) throws {
        self.beatTracker = try beatTracker ?? BeatTracker()
        self.vocalTagger = vocalTagger
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
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let missing = !FileManager.default.fileExists(atPath: url.path)
            throw AudioDecodeError(kind: .cannotRead, file: url.path, format: .unknown,
                                   message: missing ? "no such file" : "could not be read (\(error))")
        }
        let sha = CrateIDs.sha256(of: data)
        let format = AudioFormat.sniff(data)
        lap("hash")

        // ------------------------------------------------------------------ decode (44.1 kHz, mono = channel mean)
        var buffer = try AudioDecoder.decode(url)
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

        // ------------------------------------------------------------------ key (chroma; decided after the windows)
        let chroma = try KeyEstimator.chroma(m22, sampleRate: KeyEstimator.sampleRate)
        lap("key")

        // ------------------------------------------------------------------ grid choice and bars
        func tagDev(_ g: GridFit) -> Double {
            guard let tag else { return 999.0 }
            return Tempo.closest(bpm: g.bpm, reference: tag, among: Tempo.octaveMultipliers).deviationPct
        }
        // The lab's madmom --auto rule, recorded so the Mac comparison knows where the lab's grid may differ.
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
        let kw = KWeighted(buffer)
        let barFrames = bars.barTimes.map { kw.frame(at: $0) }
        let lufs = (0..<bars.nBars).map { kw.loudness(from: barFrames[$0], to: barFrames[$0 + 1]) }
        let levels = BandSplit(sampleRate: SR).levels(mono, barFrames: barFrames)
        let onsetDensity = spectral.onsetDensity(grid: bars)
        let loudness = Analysis.Loudness(integratedLufs: Loudness.integrated(kw), lra: Loudness.range(kw),
                                         truePeakDb: TruePeak.decibels(buffer))
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

        // ------------------------------------------------------------------ key: whole track and the two windows
        // mixer/key_light.py reads the windows from the feature file, where they are rounded to 3 decimals.
        let key = KeyEstimator.estimate(chroma, mixIn: (Py.round(mixIn.startS, 3), Py.round(mixIn.endS, 3)),
                                        mixOut: (Py.round(mixOut.startS, 3), Py.round(mixOut.endS, 3)))
        let keyConfidence = KeyConfidence.oneEstimator(key.whole)

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
            source: .init(path: path, name: url.lastPathComponent, bytes: data.count, sha256: sha,
                          format: format.rawValue, sampleRate: sourceRate, channels: sourceChannels),
            duration: duration, bpmTag: tag, detectedBeats: beats, detectedDownbeats: downbeats, octaveFix: octaveFix,
            grid: G, bars: bars, multiplierVsTag: multTag, tagDevPct: devTag, bpmAgree: bpmAgree,
            madmomWouldRun: madmomWouldRun, noveltyPeaks: novelty.peaks, phrase: phrase, boundariesBars: boundaries,
            sections: sections, firstSound: sound.firstSound, lastSound: ls, endLoudness: end, fade: fade,
            mixIn: mixIn, mixOut: mixOut, key: key, keyConfidence: keyConfidence, loudness: loudness,
            perBar: .init(lufsSt: lufs, lowDb: levels.lowDB, highDb: levels.highDB, onsetDensity: onsetDensity,
                          vocalProb: vocal?.perBar),
            onsetPattern16: pattern, vocal: vocal, vocalModel: vocal == nil ? nil : vocalTagger?.modelName,
            flags: flags, localTempo: localTempo, timings: timings)
    }
}
