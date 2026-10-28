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
        public static let barsPrefix = "bars."
        public static func bars(_ series: String) -> String { barsPrefix + series }

        /// Every block name above (not the per-bar series).
        public static let blocks = [grid, tempoSegments, key, keyChanges, phrase, sections, mixWindows, ends, loudness,
                                    vocal, onsetPattern, style]
    }

    /// The decimals a number is written with, by its field name: the lab's own rounding (mixer/analyze.py and
    /// mixer/local_tempo.py). A field name has one precision wherever it appears; the writer refuses a fractional
    /// number under a name that is not listed here, so every number in the format is documented.
    public static let decimals: [String: Int] = [
        "bpm": 3, "bpm_in": 3, "bpm_out": 3, "confidence": 3, "duration_s": 3, "first_sound_s": 3,
        "last_sound_s": 3, "lra": 3,
        "first_downbeat_s": 4, "start_s": 4, "mean": 4, "onset_pattern_16": 4,
        "fit_mad_ms": 2, "integrated_lufs": 2, "true_peak_db": 2, "secs": 2,
    ]

    /// The four-byte tags that open the sidecar files.
    static let barsMagic: [UInt8] = Array("DKB1".utf8)
    static let styleMagic: [UInt8] = Array("DKS1".utf8)
    static let sidecarHeaderBytes = 16
}
