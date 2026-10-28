import Foundation

// The crate in memory (docs/architecture/crate-format.md). Swift names are the format's names in camel case; the
// coding keys carry the format's own. Every optional is written as null, never left out (CrateWriter); a reader
// takes a missing optional as null. A block that is optional in a record is there exactly when its feature is in
// `features_present`, which is worked out from the blocks (`CrateTrack.featuresPresent`), never stored apart.

/// A whole crate: the manifest and the track records, each with its sidecar values.
public struct Crate: Equatable, Sendable {
    public var manifest: CrateManifest
    /// Written sorted by id; a crate read back has them in that order.
    public var tracks: [CrateTrack]

    public init(manifest: CrateManifest, tracks: [CrateTrack]) {
        self.manifest = manifest
        self.tracks = tracks
    }

    /// The manifest's `engines_used`: the tracks' `analysis.engine` labels, distinct and sorted.
    public var enginesUsed: [String] { Set(tracks.map(\.analysis.engine)).sorted(by: byteOrder) }
}

/// `manifest.json`: the crate as a whole. `engines_used` is written from the tracks and not stored here.
public struct CrateManifest: Codable, Equatable, Sendable {
    /// The format version the crate was written with.
    public var schema: Int
    /// The oldest reader version that may open the crate.
    public var minReader: Int
    /// Made once when the crate is created; never changes.
    public var crateId: String
    public var name: String
    /// UTC, to the second: `2026-10-26T00:00:00Z`.
    public var createdAt: String
    /// The device labels that have written to the crate.
    public var devicesSeen: [String]

    public init(crateId: String, name: String, createdAt: String, devicesSeen: [String],
                schema: Int = CrateFormat.schema, minReader: Int = 1) {
        self.schema = schema
        self.minReader = minReader
        self.crateId = crateId
        self.name = name
        self.createdAt = createdAt
        self.devicesSeen = devicesSeen
    }

    enum CodingKeys: String, CodingKey {
        case schema, name, minReader = "min_reader", crateId = "crate_id", createdAt = "created_at"
        case devicesSeen = "devices_seen"
    }
}

/// One track's record in `crate.json`, with its per-bar series (`bars/<id>.bin`) and style values (`style/<id>.bin`).
public struct CrateTrack: Codable, Equatable, Sendable {
    /// Where the audio was: enough to find it again, never the audio and never an absolute path.
    public struct File: Codable, Equatable, Sendable {
        public var name: String
        /// The path below the folder the crate was built from.
        public var rel: String?
        public var bytes: Int?
        /// Track A's head hash: a SHA-1 of the start of the file, kept for a quick identity check. The documents fix
        /// neither how much of the file it covers nor how it is written, so nothing here checks it.
        public var sha1Head: String?
        /// The SHA-256 hash of the whole file, 64 lower-case hexadecimal characters; the record's id is its first 16
        /// (`CrateIDs`). Nil in lab records, which keep the lab's ids.
        public var sha256: String?
        public var durationS: Double
        public init(name: String, rel: String?, bytes: Int?, sha1Head: String?, sha256: String? = nil,
                    durationS: Double) {
            self.name = name; self.rel = rel; self.bytes = bytes; self.sha1Head = sha1Head; self.sha256 = sha256
            self.durationS = durationS
        }
        enum CodingKeys: String, CodingKey {
            case name, rel, bytes, sha256, sha1Head = "sha1_head", durationS = "duration_s"
        }
    }

    /// The track's name and its place in the DJ's collection.
    public struct Ident: Codable, Equatable, Sendable {
        public var title: String
        public var artist: String?
        public var version: String?
        /// Where the name came from: `tag`, `filename`, `user`, `lab`, ...
        public var source: String?
        public var mbid: String?
        public var disc: String?
        public var folder: String?
        public var track: Int?
        public var cutKey: String?
        public var isLongest: Bool?
        public var era: String?
        public var kind: String?
        public var tags: [String]
        public init(title: String, artist: String? = nil, version: String? = nil, source: String? = nil,
                    mbid: String? = nil, disc: String? = nil, folder: String? = nil, track: Int? = nil,
                    cutKey: String? = nil, isLongest: Bool? = nil, era: String? = nil, kind: String? = nil,
                    tags: [String] = []) {
            self.title = title; self.artist = artist; self.version = version; self.source = source
            self.mbid = mbid; self.disc = disc; self.folder = folder; self.track = track; self.cutKey = cutKey
            self.isLongest = isLongest; self.era = era; self.kind = kind; self.tags = tags
        }
        enum CodingKeys: String, CodingKey {
            case title, artist, version, source, mbid, disc, folder, track, era, kind, tags
            case cutKey = "cut_key", isLongest = "is_longest"
        }
    }

    /// When, where and at which level the track was analysed.
    public struct Analysis: Codable, Equatable, Sendable {
        /// A short label for the engine, such as `lab-1`; `CrateTrack.Engine` has the detail.
        public var engine: String
        public var analysedAt: String
        /// A model label (`Mac15,6`, `linux-x86_64`), never a name the user gave the device.
        public var device: String
        public var secs: Double?
        /// 1 full, 2 fallback, 3 none (spec 5.1).
        public var level: Int
        public init(engine: String, analysedAt: String, device: String, secs: Double?, level: Int) {
            self.engine = engine; self.analysedAt = analysedAt; self.device = device; self.secs = secs
            self.level = level
        }
        enum CodingKeys: String, CodingKey { case engine, device, secs, level, analysedAt = "analysed_at" }
    }

    /// What produced the record (track L): the engine family and build, the models and the decoder.
    public struct Engine: Codable, Equatable, Sendable {
        public struct Model: Codable, Equatable, Sendable {
            public var name: String
            public var version: String?
            public var weightsSha256: String?
            public init(name: String, version: String? = nil, weightsSha256: String? = nil) {
                self.name = name; self.version = version; self.weightsSha256 = weightsSha256
            }
            enum CodingKeys: String, CodingKey { case name, version, weightsSha256 = "weights_sha256" }
        }
        public struct DecoderInfo: Codable, Equatable, Sendable {
            public var name: String
            public var version: String?
            public init(name: String, version: String? = nil) { self.name = name; self.version = version }
        }
        /// `apple-mu`, `deckie` or `lab` (`CrateFormat.EngineFamily`).
        public var family: String
        public var version: String
        /// `macos-arm64`, `linux-x86_64`, `windows-x86_64`.
        public var platform: String
        /// 0: not benchmarked; n: the build passed benchmark tier n (tier 1 is the stage 1 pass marks).
        public var fidelity: Int
        public var models: [Model]
        public var decoder: DecoderInfo?
        public init(family: String, version: String, platform: String, fidelity: Int, models: [Model],
                    decoder: DecoderInfo?) {
            self.family = family; self.version = version; self.platform = platform; self.fidelity = fidelity
            self.models = models; self.decoder = decoder
        }
    }

    /// The whole-track beat grid: bar 1 starts at `firstDownbeatS`; `nBars` whole bars follow.
    public struct Grid: Codable, Equatable, Sendable {
        public var source: String
        public var confidence: Double
        public var bpm: Double
        public var firstDownbeatS: Double
        public var nBars: Int
        public var fitMadMs: Double?
        /// Tempo at the start and the end, and whether each is a steady beat (the lab's local tempo).
        public var bpmIn: Double
        public var bpmOut: Double
        public var inTrusted: Bool
        public var outTrusted: Bool
        public init(source: String, confidence: Double, bpm: Double, firstDownbeatS: Double, nBars: Int,
                    fitMadMs: Double?, bpmIn: Double, bpmOut: Double, inTrusted: Bool, outTrusted: Bool) {
            self.source = source; self.confidence = confidence; self.bpm = bpm; self.firstDownbeatS = firstDownbeatS
            self.nBars = nBars; self.fitMadMs = fitMadMs; self.bpmIn = bpmIn; self.bpmOut = bpmOut
            self.inTrusted = inTrusted; self.outTrusted = outTrusted
        }
        enum CodingKeys: String, CodingKey {
            case source, confidence, bpm, firstDownbeatS = "first_downbeat_s", nBars = "n_bars",
                 fitMadMs = "fit_mad_ms", bpmIn = "bpm_in", bpmOut = "bpm_out", inTrusted = "in_trusted",
                 outTrusted = "out_trusted"
        }
    }

    /// One stretch of steady tempo, in the shape of the industry's grid marker (P12).
    public struct TempoSegment: Codable, Equatable, Sendable {
        public var startBar: Int
        public var startS: Double
        public var bpm: Double
        public var beatsPerBar: Int
        /// Which beat of its bar the segment starts on; 1 is the downbeat.
        public var beatInBar: Int
        public var confidence: Double?
        public init(startBar: Int, startS: Double, bpm: Double, beatsPerBar: Int, beatInBar: Int,
                    confidence: Double?) {
            self.startBar = startBar; self.startS = startS; self.bpm = bpm; self.beatsPerBar = beatsPerBar
            self.beatInBar = beatInBar; self.confidence = confidence
        }
        enum CodingKeys: String, CodingKey {
            case bpm, confidence, startBar = "start_bar", startS = "start_s", beatsPerBar = "beats_per_bar",
                 beatInBar = "beat_in_bar"
        }
    }

    public struct Key: Codable, Equatable, Sendable {
        public struct Change: Codable, Equatable, Sendable {
            public var startBar: Int
            public var endBar: Int
            public var camelot: String
            public init(startBar: Int, endBar: Int, camelot: String) {
                self.startBar = startBar; self.endBar = endBar; self.camelot = camelot
            }
            enum CodingKeys: String, CodingKey { case camelot, startBar = "start_bar", endBar = "end_bar" }
        }
        public var source: String
        public var confidence: Double
        public var camelot: String
        public var key: String?
        /// `major` or `minor`.
        public var scale: String?
        /// Each vote's source and its Camelot code.
        public var votes: [String: String]
        /// Key segments (feature `key_changes`); nil when the engine did not look for them.
        public var changes: [Change]?
        public init(source: String, confidence: Double, camelot: String, key: String?, scale: String?,
                    votes: [String: String], changes: [Change]?) {
            self.source = source; self.confidence = confidence; self.camelot = camelot; self.key = key
            self.scale = scale; self.votes = votes; self.changes = changes
        }
    }

    public struct Phrase: Codable, Equatable, Sendable {
        public var source: String
        public var confidence: Double
        /// Where the 8-bar phrases start: 1 to 8.
        public var latticePhaseBar: Int
        public var boundariesBars: [Int]
        public init(source: String, confidence: Double, latticePhaseBar: Int, boundariesBars: [Int]) {
            self.source = source; self.confidence = confidence; self.latticePhaseBar = latticePhaseBar
            self.boundariesBars = boundariesBars
        }
        enum CodingKeys: String, CodingKey {
            case source, confidence, latticePhaseBar = "lattice_phase_bar", boundariesBars = "boundaries_bars"
        }
    }

    public struct Section: Codable, Equatable, Sendable {
        public var startBar: Int
        public var endBar: Int
        /// `intro`, `main`, `break`, `outro`.
        public var label: String
        /// `high` or `low`.
        public var energy: String
        public init(startBar: Int, endBar: Int, label: String, energy: String) {
            self.startBar = startBar; self.endBar = endBar; self.label = label; self.energy = energy
        }
        enum CodingKeys: String, CodingKey { case label, energy, startBar = "start_bar", endBar = "end_bar" }
    }

    public struct MixWindow: Codable, Equatable, Sendable {
        public var startBar: Int
        public var endBar: Int
        public var vocalFreeBars: Int?
        public init(startBar: Int, endBar: Int, vocalFreeBars: Int?) {
            self.startBar = startBar; self.endBar = endBar; self.vocalFreeBars = vocalFreeBars
        }
        enum CodingKeys: String, CodingKey {
            case startBar = "start_bar", endBar = "end_bar", vocalFreeBars = "vocal_free_bars"
        }
    }

    public struct Ends: Codable, Equatable, Sendable {
        public var firstSoundS: Double
        public var lastSoundS: Double
        public var fadeOut: Bool
        public var fadeStartBar: Int?
        public var steadyInBar: Int?
        public var steadyOutBar: Int?
        public init(firstSoundS: Double, lastSoundS: Double, fadeOut: Bool, fadeStartBar: Int?, steadyInBar: Int?,
                    steadyOutBar: Int?) {
            self.firstSoundS = firstSoundS; self.lastSoundS = lastSoundS; self.fadeOut = fadeOut
            self.fadeStartBar = fadeStartBar; self.steadyInBar = steadyInBar; self.steadyOutBar = steadyOutBar
        }
        enum CodingKeys: String, CodingKey {
            case firstSoundS = "first_sound_s", lastSoundS = "last_sound_s", fadeOut = "fade_out",
                 fadeStartBar = "fade_start_bar", steadyInBar = "steady_in_bar", steadyOutBar = "steady_out_bar"
        }
    }

    public struct Loudness: Codable, Equatable, Sendable {
        public var source: String
        public var confidence: Double?
        public var integratedLufs: Double
        /// Loudness range, LU.
        public var lra: Double
        public var truePeakDb: Double
        public init(source: String, confidence: Double?, integratedLufs: Double, lra: Double, truePeakDb: Double) {
            self.source = source; self.confidence = confidence; self.integratedLufs = integratedLufs; self.lra = lra
            self.truePeakDb = truePeakDb
        }
        enum CodingKeys: String, CodingKey {
            case source, confidence, lra, integratedLufs = "integrated_lufs", truePeakDb = "true_peak_db"
        }
    }

    public struct Vocal: Codable, Equatable, Sendable {
        public var source: String
        public var confidence: Double?
        /// Mean vocal activity, 0 to 1, on the source's scale.
        public var mean: Double
        public var heavy: Bool
        public init(source: String, confidence: Double?, mean: Double, heavy: Bool) {
            self.source = source; self.confidence = confidence; self.mean = mean; self.heavy = heavy
        }
    }

    /// The style vector: `model` and `dims` in crate.json, the values in `style/<id>.bin` (float16).
    public struct Style: Codable, Equatable, Sendable {
        public var model: String
        public var dims: Int
        /// Rounded to float16, as the sidecar holds them.
        public internal(set) var values: [Double] = []
        public init(model: String, values: [Double]) {
            self.model = model
            self.dims = values.count
            self.values = values.map(Half.rounded)
        }
        enum CodingKeys: String, CodingKey { case model, dims }
    }

    /// A recognition signature made on an Apple device; the file is `signatures/<id>_<variant>.shazamsignature`.
    public struct Signature: Codable, Equatable, Sendable {
        public var madeBy: String
        public var madeAt: String
        public init(madeBy: String, madeAt: String) { self.madeBy = madeBy; self.madeAt = madeAt }
        enum CodingKeys: String, CodingKey { case madeBy = "made_by", madeAt = "made_at" }
    }

    public var id: String
    public var schema: Int
    public var file: File
    public var ident: Ident
    public var analysis: Analysis
    public var engine: Engine
    public var grid: Grid?
    public var tempoSegments: [TempoSegment]?
    public var key: Key?
    public var phrase: Phrase?
    public var sections: [Section]?
    public var mixIn: MixWindow?
    public var mixOut: MixWindow?
    public var ends: Ends?
    public var loudness: Loudness?
    public var vocal: Vocal?
    public var onsetPattern16: [Double]?
    public var flags: [String]
    public var style: Style?
    /// By variant (`o`, `r-4`, `r+4`, ...). Empty until an Apple device adds signatures.
    public var signatures: [String: Signature]
    /// The per-bar series (`bars/<id>.bin`), not part of crate.json.
    public var bars: BarSeries? = nil

    public init(id: String, schema: Int = CrateFormat.schema, file: File, ident: Ident, analysis: Analysis,
                engine: Engine, grid: Grid? = nil, tempoSegments: [TempoSegment]? = nil, key: Key? = nil,
                phrase: Phrase? = nil, sections: [Section]? = nil, mixIn: MixWindow? = nil, mixOut: MixWindow? = nil,
                ends: Ends? = nil, loudness: Loudness? = nil, vocal: Vocal? = nil, onsetPattern16: [Double]? = nil,
                flags: [String] = [], style: Style? = nil, signatures: [String: Signature] = [:],
                bars: BarSeries? = nil) {
        self.id = id; self.schema = schema; self.file = file; self.ident = ident; self.analysis = analysis
        self.engine = engine; self.grid = grid; self.tempoSegments = tempoSegments; self.key = key
        self.phrase = phrase; self.sections = sections; self.mixIn = mixIn; self.mixOut = mixOut; self.ends = ends
        self.loudness = loudness; self.vocal = vocal; self.onsetPattern16 = onsetPattern16; self.flags = flags
        self.style = style; self.signatures = signatures; self.bars = bars
    }

    /// The record's `features_present`: the optional blocks it holds and its per-bar series, sorted.
    public var featuresPresent: [String] {
        typealias F = CrateFormat.Feature
        var f: [String] = []
        if grid != nil { f.append(F.grid) }
        if tempoSegments != nil { f.append(F.tempoSegments) }
        if key != nil { f.append(F.key) }
        if key?.changes != nil { f.append(F.keyChanges) }
        if phrase != nil { f.append(F.phrase) }
        if sections != nil { f.append(F.sections) }
        if mixIn != nil || mixOut != nil { f.append(F.mixWindows) }
        if ends != nil { f.append(F.ends) }
        if loudness != nil { f.append(F.loudness) }
        if vocal != nil { f.append(F.vocal) }
        if onsetPattern16 != nil { f.append(F.onsetPattern) }
        if style != nil { f.append(F.style) }
        if let bars { f += bars.names.map(F.bars) }
        return f.sorted(by: byteOrder)
    }

    enum CodingKeys: String, CodingKey {
        case id, schema, file, ident, analysis, engine, grid, key, phrase, sections, ends, loudness, vocal, flags
        case style, signatures
        case tempoSegments = "tempo_segments", mixIn = "mix_in", mixOut = "mix_out", onsetPattern16 = "onset_pattern_16"
    }
    enum ListKeys: String, CodingKey { case featuresPresent = "features_present" }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(schema, forKey: .schema)
        try c.encode(file, forKey: .file)
        try c.encode(ident, forKey: .ident)
        try c.encode(analysis, forKey: .analysis)
        try c.encode(engine, forKey: .engine)
        try c.encodeIfPresent(grid, forKey: .grid)
        try c.encodeIfPresent(tempoSegments, forKey: .tempoSegments)
        try c.encodeIfPresent(key, forKey: .key)
        try c.encodeIfPresent(phrase, forKey: .phrase)
        try c.encodeIfPresent(sections, forKey: .sections)
        try c.encodeIfPresent(mixIn, forKey: .mixIn)
        try c.encodeIfPresent(mixOut, forKey: .mixOut)
        try c.encodeIfPresent(ends, forKey: .ends)
        try c.encodeIfPresent(loudness, forKey: .loudness)
        try c.encodeIfPresent(vocal, forKey: .vocal)
        try c.encodeIfPresent(onsetPattern16, forKey: .onsetPattern16)
        try c.encode(flags, forKey: .flags)
        try c.encodeIfPresent(style, forKey: .style)
        try c.encode(signatures, forKey: .signatures)
        var l = encoder.container(keyedBy: ListKeys.self)
        try l.encode(featuresPresent, forKey: .featuresPresent)
    }
}

/// A track's per-bar series by name (`lufs`, `low_db`, `high_db`, `onset_density`, `vocal`, `drum`, `bass`,
/// `other`), each with one value per bar of the grid. Values are kept rounded to float16, as the sidecar holds them,
/// so a crate read back equals the one written.
public struct BarSeries: Equatable, Sendable {
    public static let lufs = "lufs", lowDb = "low_db", highDb = "high_db", onsetDensity = "onset_density"
    public static let vocal = "vocal", drum = "drum", bass = "bass", other = "other"

    public private(set) var series: [String: [Double]]

    public init(_ series: [String: [Double]]) { self.series = series.mapValues { $0.map(Half.rounded) } }

    public subscript(name: String) -> [Double]? {
        get { series[name] }
        set { series[name] = newValue?.map(Half.rounded) }
    }

    /// The series names in the sidecar's order (sorted by byte, as `features_present` lists them).
    public var names: [String] { series.keys.sorted(by: byteOrder) }
}

/// Byte order of UTF-8 text: the crate's one sort order.
func byteOrder(_ a: String, _ b: String) -> Bool { a.utf8.lexicographicallyPrecedes(b.utf8) }
