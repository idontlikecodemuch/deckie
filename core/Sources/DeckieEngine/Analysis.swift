import Foundation
import DeckieCore
import DeckieCrate
import DeckieDecode

/// One track analysed by the engine: everything mixer/analyze.py writes to a feature file that the engine can measure,
/// kept unrounded (the lab rounds when it writes; `labJSON()` rounds the same way), plus what only the engine knows.
/// `labJSON()` gives the lab's feature JSON, `crateTrack(options:)` the crate record. Times are seconds from the start
/// of the decoded audio; bar numbers are 1-based where they cross the API, as in the lab's files.
public struct Analysis: Sendable {
    /// The engine family written to the crate (`engine.family`): `deckie`, the name of the engine, not of a licence.
    public static let engineFamily = CrateFormat.EngineFamily.deckie
    /// The engine's version (`engine.version`; `analysis.engine` is `deckie-<version>`). It goes up whenever the
    /// record gains or changes fields, so the builder's work folders made by an older version are analysed again
    /// rather than reused. 0.2.0: the vocal structure and hook blocks, and `file.tag_bpm`. 0.3.0: the key decided by
    /// three votes (`KeyVote`): `key.source` `votes` with three entries in `key.votes`, the lab's B.9 confidence, and
    /// `votes`, `vote` and `vote_rule` in the lab JSON's `deckie.key`. 0.3.1: the decoder conceals damaged MP3 frames,
    /// listed as `file.damaged_frames` (`deckie.damaged_frames` in the lab JSON). 0.4.0: the key decided by research
    /// R's whitened HPCP (`HPCPKey`), which changes keys: `key.source` `hpcp-whitened`, its three profiles' keys and
    /// the STFT estimate in `key.votes`, research R's sure rule as the confidence (`KeyConfidence`), and the method's
    /// detail in `deckie.key`.
    public static let engineVersion = "0.4.0"
    /// The lab's feature-file schema the JSON follows (`schema`).
    public static let labSchema = 1
    /// The rate everything is analysed at: the lab decodes at 44.1 kHz and resamples other files to it first (`sr`).
    public static let sampleRate = 44100
    /// The grid's source: the Beat This! checkpoint, the only grid source (the lab's madmom fallback is
    /// non-commercial and not ported). Written as the JSON's `grid.source` and the crate's `grid.source`.
    public static let gridSource = "beat-this-final0"
    /// The lab's `beatthis_device`: ONNX Runtime's CPU provider.
    public static let beatTrackerDevice = "cpu"

    /// The audio file.
    public struct Source: Sendable, Equatable {
        /// The path as given.
        public var path: String
        /// The file's name.
        public var name: String
        /// Its size in bytes.
        public var bytes: Int
        /// SHA-256 of its bytes, 64 hex characters.
        public var sha256: String
        /// What the decoder read it as (`WAV`, `MP3`, `FLAC`, `AIFF`).
        public var format: String
        /// Its own sample rate and channel count, before any resampling (more than two channels are cut to two).
        public var sampleRate: Int
        public var channels: Int

        public init(path: String, name: String, bytes: Int, sha256: String, format: String, sampleRate: Int,
                    channels: Int) {
            self.path = path; self.name = name; self.bytes = bytes; self.sha256 = sha256; self.format = format
            self.sampleRate = sampleRate; self.channels = channels
        }
    }

    /// Integrated loudness (LUFS; nil when the audio is shorter than one 400 ms block; minus infinity for silence),
    /// loudness range (LU; nil when it cannot be measured, as the lab writes null) and true peak (dBTP).
    public struct Loudness: Sendable, Equatable {
        public var integratedLufs: Double?
        public var lra: Double?
        public var truePeakDb: Double
        public init(integratedLufs: Double?, lra: Double?, truePeakDb: Double) {
            self.integratedLufs = integratedLufs; self.lra = lra; self.truePeakDb = truePeakDb
        }
    }

    /// The per-bar series, one value per bar of `bars` (the lab's `per_bar`).
    public struct PerBar: Sendable, Equatable {
        /// K-weighted loudness of the bar, LUFS (`lufs_st`).
        public var lufsSt: [Double]
        /// Level below 150 Hz and above 4 kHz, dB (`low_db`, `high_db`).
        public var lowDb: [Double]
        public var highDb: [Double]
        /// Onsets per beat (`onset_density`).
        public var onsetDensity: [Double]
        /// Vocal probability (`vocal_prob`); nil without a vocal tagger.
        public var vocalProb: [Double]?
        public init(lufsSt: [Double], lowDb: [Double], highDb: [Double], onsetDensity: [Double], vocalProb: [Double]?) {
            self.lufsSt = lufsSt; self.lowDb = lowDb; self.highDb = highDb; self.onsetDensity = onsetDensity
            self.vocalProb = vocalProb
        }
    }

    /// One stage's wall-clock time, in the order the stages ran (the lab's `timing_s`).
    public struct Timing: Sendable, Equatable {
        public var stage: String
        public var seconds: Double
        public init(stage: String, seconds: Double) { self.stage = stage; self.seconds = seconds }
    }

    /// The record's id: the first 16 hex characters of `source.sha256` (`CrateIDs`).
    public var id: String
    /// The track's name, from the options or the file name (the lab's `title`).
    public var title: String?
    /// The lab's `ver` (the cut's name), from the options.
    public var version: String?
    public var source: Source
    /// Length of the decoded audio at 44.1 kHz (`duration_s`).
    public var duration: Double
    /// The tag tempo given in the options (the lab JSON's `bpm_tag`, the crate record's `file.tag_bpm`); it only steers
    /// the octave alignment and the tag comparisons.
    public var bpmTag: Double?
    /// The frames the decoder found damaged and played as silence (MP3 only; `AudioDecoder.decodeReporting`), in
    /// order; everything else in the record was measured on the audio with them silent (the lab JSON's
    /// `deckie.damaged_frames`, the crate record's `file.damaged_frames`, null when empty).
    public var damagedFrames: [DamagedFrame] = []

    /// The tracker's beats and downbeats, after the octave alignment (`detected_beats_s`, `detected_downbeats_s`).
    public var detectedBeats: [Double]
    public var detectedDownbeats: [Double]
    /// What the octave alignment did (`octave_fix`); nil when it did nothing.
    public var octaveFix: OctaveFix?
    /// The chosen grid (`grid`): the Beat This! grid, the only candidate (`grid_candidates.beatthis`).
    public var grid: GridFit
    /// Bar 1, the bar lines and the grid beats (`grid.first_downbeat_s`, `downbeats_s`, `beats_s`, `grid.n_bars`).
    public var bars: BarGrid
    /// The nearest of 1/2, 2/3, 3/4, 1, 4/3, 3/2 and 2 to bpm / tag and the deviation left, in percent; 1 and 0
    /// without a tag (`multiplier_vs_tag_value`, `tag_dev_pct`).
    public var multiplierVsTag: Double
    public var tagDevPct: Double
    /// Within 1 percent of the tag after x1/2, x1, x2 (`bpm_agree`); false without a tag.
    public var bpmAgree: Bool
    /// Why the lab would have run madmom here (`madmom --auto`: a grid confidence under 0.5, or more than 2 percent
    /// from the tag), or nil when it would not have: where the lab's grid may differ from the engine's.
    public var madmomWouldRun: String?

    /// The novelty peaks snapped to bar lines, strongest first (`novelty_peaks`, written sorted by bar).
    public var noveltyPeaks: [NoveltyPeak]
    public var phrase: Phrase
    /// Bar 1, the on-lattice peaks and the end line, 1-based (`boundaries_bars`).
    public var boundariesBars: [Int]
    /// The sections; their `vocal` is the mean vocal probability, 0 (and written null) without a vocal tagger.
    public var sections: [Section]
    public var firstSound: Double
    public var lastSound: Double
    /// Short-term loudness 20, 10 and 4 s before the last sound (`end_lufs_st`).
    public var endLoudness: EndLoudness
    /// The fade-out decision (`fade_out`, `fade_drop_lu`, `tail_bars`, `fade_start_bar`).
    public var fade: FadeOut
    /// The mix windows (`mix_in`, `mix_out`); without a vocal tagger every bar counts as vocal-free.
    public var mixIn: MixIn
    public var mixOut: MixOut

    /// The STFT key estimator's results with the edma profile (`KeyEstimator`, mixer/key_light.py): its whole-track
    /// key (no longer deciding; recorded as `stft_edma` for comparison), both mix windows judged against the song key
    /// (`songKey`, the HPCP method's key), and the key segments.
    public var key: KeyResult
    /// The track's key: research R's whitened HPCP with the edma, bgate and braw profiles (`HPCPKey`). Its
    /// `decision` (the literature's profile numbers) is the record's key; its `parity` decision (key_light.py's
    /// numbers) is what mixer/key_parity.py decides, for the bench's parity column.
    public var hpcpKey: HPCPKey.Result
    /// The key confidence, research R's sure rule on the decision (`KeyConfidence`).
    public var keyConfidence: KeyConfidence

    public var loudness: Loudness
    public var perBar: PerBar
    /// `onset_pattern_16`.
    public var onsetPattern16: [Double]
    /// The vocal tagger's output and model name; nil when there is no tagger (no `vocal` block, no
    /// `per_bar.vocal_prob`, the flag `vocal_unknown`).
    public var vocal: VocalActivity?
    public var vocalModel: String?
    /// Where the track is sung, to the beat (memo Q's items A1 to A6: spans, first and last sung beat with the pickup,
    /// free intro and outro and their kinds, free gaps, the exposed-vocal proxy, span ends against the lattice); nil
    /// without a vocal tagger.
    public var vocalStructure: VocalStructure?
    /// Up to three hook candidates (memo Q's item B7); nil without a vocal tagger.
    public var hooks: Hooks?
    /// The lab's flags, then the local-tempo flags, then `vocal_unknown` when there is no tagger.
    public var flags: [String]
    /// The lab's `local_tempo` block, computed from the record's rounded values as the lab computes it from its file.
    public var localTempo: LocalTempo
    public var timings: [Timing]

    /// The grid tempo, 60 / period (`bpm`).
    public var bpm: Double { 60.0 / grid.period }
    /// True when no vocal tagger ran: the mix windows were placed without vocal information.
    public var vocalUnknown: Bool { vocal == nil }
    /// The sum of the stage times.
    public var totalSeconds: Double { timings.reduce(0) { $0 + $1.seconds } }
    /// The deviation of the Beat This! grid from the tag after x1/2, x1, x2, in percent; 999 without a tag, as the lab's
    /// `tag_dev` has it.
    public var gridTagDevPct: Double {
        guard let tag = bpmTag, tag != 0 else { return 999.0 }
        return Tempo.closest(bpm: grid.bpm, reference: tag, among: Tempo.octaveMultipliers).deviationPct
    }
}
