import Foundation

/// The parts of a lab feature file (mixer/features/<id>.json) that DeckieCore's tests and scoring read.
/// Field names follow the file; see mixer/README.md for what each one means.
public struct FeatureFile: Decodable, Sendable {
    public struct Grid: Decodable, Sendable {
        public var source: String
        public var bpm: Double
        public var firstDownbeatS: Double
        public var fitMadMs: Double
        public var inlierFrac: Double
        public var downbeatAgree: Double
        public var confidence: Double
        public var nBars: Int
        enum CodingKeys: String, CodingKey {
            case source, bpm, confidence
            case firstDownbeatS = "first_downbeat_s", fitMadMs = "fit_mad_ms", inlierFrac = "inlier_frac"
            case downbeatAgree = "downbeat_agree", nBars = "n_bars"
        }
    }
    public struct GridCandidate: Decodable, Sendable {
        public var bpm: Double
        public var fitMadMs: Double
        public var confidence: Double
        public var tagDevPct: Double
        enum CodingKeys: String, CodingKey {
            case bpm, confidence, fitMadMs = "fit_mad_ms", tagDevPct = "tag_dev_pct"
        }
    }
    // `LocalTempo`, the lab's local_tempo block, is in FeatureFile+LocalTempo.swift.
    public struct Key: Decodable, Sendable {
        public var camelot: String
        public var confidence: Double
    }
    public struct MixWindow: Decodable, Sendable {
        public var startBar: Int
        public var endBar: Int
        public var bars: Int
        // Read by the local tempo port (FeatureFile+LocalTempo.swift).
        public var startS: Double?
        public var endS: Double?
        enum CodingKeys: String, CodingKey {
            case bars, startBar = "start_bar", endBar = "end_bar"
            case startS = "start_s", endS = "end_s"
        }
    }
    public struct Loudness: Decodable, Sendable {
        public var integratedLufs: Double
        enum CodingKeys: String, CodingKey { case integratedLufs = "integrated_lufs" }
    }
    public struct PerBar: Decodable, Sendable {
        public var lufsSt: [Double]
        public var vocalProb: [Double]
        enum CodingKeys: String, CodingKey { case lufsSt = "lufs_st", vocalProb = "vocal_prob" }
    }
    public struct Meta: Decodable, Sendable {
        public var kind: String?
        public var era: String?
    }

    public var id: String
    public var title: String?
    public var ver: String?
    public var durationS: Double
    public var bpm: Double
    public var bpmTag: Double?
    public var grid: Grid
    public var gridCandidates: [String: GridCandidate?]?
    public var detectedBeatsS: [Double]
    public var detectedDownbeatsS: [Double]?
    public var localTempo: LocalTempo?
    public var key: Key
    public var mixIn: MixWindow
    public var mixOut: MixWindow
    public var loudness: Loudness
    public var perBar: PerBar
    public var onsetPattern16: [Double]
    public var embeddingEffnet: [Double]
    public var fadeOut: Bool?
    public var flags: [String]?
    public var meta: Meta?
    // Read by the local tempo port (FeatureFile+LocalTempo.swift).
    public var beatsS: [Double]?
    public var downbeatsS: [Double]?
    public var firstSoundS: Double?
    public var lastSoundS: Double?

    enum CodingKeys: String, CodingKey {
        case id, title, ver, bpm, grid, key, loudness, meta, flags
        case durationS = "duration_s", bpmTag = "bpm_tag", gridCandidates = "grid_candidates"
        case detectedBeatsS = "detected_beats_s", detectedDownbeatsS = "detected_downbeats_s"
        case localTempo = "local_tempo", mixIn = "mix_in", mixOut = "mix_out", perBar = "per_bar"
        case onsetPattern16 = "onset_pattern_16", embeddingEffnet = "embedding_effnet", fadeOut = "fade_out"
        // Local tempo port.
        case beatsS = "beats_s", downbeatsS = "downbeats_s", firstSoundS = "first_sound_s", lastSoundS = "last_sound_s"
    }

    public static func load(_ url: URL) throws -> FeatureFile {
        try JSONDecoder().decode(FeatureFile.self, from: Data(contentsOf: url))
    }
}

/// One row of mixer/candidates.json: the pool's bookkeeping for a track.
public struct CandidateRecord: Decodable, Sendable {
    public var id: String
    public var title: String?
    public var ver: String?
    public var secs: Double?
    public var cutKey: String?
    public var isLongest: Bool?
    public var onDisc: Bool?
    public var disc: String?
    public var folder: String?
    public var hal: Bool?
    public var kind: String?
    public var era: String?
    enum CodingKeys: String, CodingKey {
        case id, title, ver, secs, disc, folder, hal, kind, era
        case cutKey = "cut_key", isLongest = "is_longest", onDisc = "on_disc"
    }

    public static func loadAll(_ url: URL) throws -> [CandidateRecord] {
        try JSONDecoder().decode([CandidateRecord].self, from: Data(contentsOf: url))
    }
}
