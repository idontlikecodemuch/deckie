/// The fixed facts of the crate format: version numbers, file names, feature names and the decimals each number is
/// written with. docs/architecture/crate-format.md describes the format in words.
public enum CrateFormat {
    /// The format version this build writes, and the highest `min_reader` it can read.
    public static let schema = 1

    /// The package folder's extension (track A: `<name>.deckiecrate`).
    public static let packageExtension = "deckiecrate"
    public static let manifestFile = "manifest.json"
    public static let tracksFile = "crate.json"
    public static let barsFolder = "bars"
    public static let styleFolder = "style"
    public static let signaturesFolder = "signatures"

    static func barsPath(_ id: String) -> String { "\(barsFolder)/\(id).bin" }
    static func stylePath(_ id: String) -> String { "\(styleFolder)/\(id).bin" }
    static func signaturePath(_ id: String, _ variant: String) -> String {
        "\(signaturesFolder)/\(id)_\(variant).shazamsignature"
    }

    /// Names that `features_present` uses for the optional blocks of a record. A per-bar series is listed as
    /// `bars.<series>` (`Feature.bars(_:)`).
    public enum Feature {
        public static let grid = "grid"
        public static let tempoSegments = "tempo_segments"
        public static let key = "key"
        public static let keyChanges = "key_changes"
        public static let phrase = "phrase"
        public static let sections = "sections"
        public static let mixWindows = "mix_windows"
        public static let ends = "ends"
        public static let loudness = "loudness"
        public static let vocal = "vocal"
        public static let onsetPattern = "onset_pattern"
        public static let style = "style"
        /// Where the track is sung, to the beat, and the hook candidates (**proposed** with memo O's vocal fields).
        public static let vocalStructure = "vocal_structure"
        public static let hooks = "hooks"
        public static let barsPrefix = "bars."
        public static func bars(_ series: String) -> String { barsPrefix + series }

        /// Every block name above (not the per-bar series).
        public static let blocks = [grid, tempoSegments, key, keyChanges, phrase, sections, mixWindows, ends, loudness,
                                    vocal, onsetPattern, style, vocalStructure, hooks]
    }

    /// The engine families (`engine.family`). A family names an engine, never a licence: the Windows and Linux
    /// engine runs open-source models, but the engine itself is not open source.
    public enum EngineFamily {
        /// The Apple apps' engine, on Apple's Music Understanding.
        public static let appleMU = "apple-mu"
        /// The Windows and Linux engine.
        public static let deckie = "deckie"
        /// The Python lab (`mixer/`), whose feature files convert to records.
        public static let lab = "lab"
        public static let all = [appleMU, deckie, lab]
    }

    /// The decimals a number is written with, by its field name: the lab's own rounding (mixer/analyze.py and
    /// mixer/local_tempo.py). A field name has one precision wherever it appears; the writer refuses a fractional
    /// number under a name that is not listed here, so every number in the format is documented.
    public static let decimals: [String: Int] = [
        "bpm": 3, "bpm_in": 3, "bpm_out": 3, "confidence": 3, "duration_s": 3, "first_sound_s": 3,
        "last_sound_s": 3, "lra": 3, "tag_bpm": 3,
        "first_downbeat_s": 4, "start_s": 4, "end_s": 4, "mean": 4, "onset_pattern_16": 4,
        "fit_mad_ms": 2, "integrated_lufs": 2, "true_peak_db": 2, "secs": 2,
        // The vocal structure and the hooks (proposed with memo O's vocal fields): times as the other times, scores
        // and shares as `confidence`, the rules' thresholds as their inputs are written.
        "time_s": 4, "frame_hop_s": 4, "threshold": 4, "score_p95": 4, "threshold_floor": 4, "threshold_fraction": 3,
        "beat_density_ratio": 3, "bright_margin_db": 2, "exposed_low_drop_db": 2, "exposed_density_ratio": 3,
        "strength": 3, "repetition": 3, "loudness_score": 3, "vocal_density": 3, "weight_repetition": 3,
        "weight_loudness": 3, "weight_vocal": 3, "min_repetition": 3, "short_margin": 3, "sung_share": 3,
    ]

    /// The four-byte tags that open the sidecar files.
    static let barsMagic: [UInt8] = Array("DKB1".utf8)
    static let styleMagic: [UInt8] = Array("DKS1".utf8)
    static let sidecarHeaderBytes = 16
}
