import Foundation

// The crate in memory (docs/architecture/crate-format.md). Swift names are the format's names in camel case; the
// coding keys carry the format's own. Every optional is written as null, never left out (CrateWriter), except the
// two blocks added with memo Q's vocal fields, `vocal_structure` and `hooks` (CrateModel+Vocal.swift), which are left
// out when absent; a reader takes a missing optional as null. A block that is optional in a record is there exactly when its feature is in
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
    /// What the builder saw when it last made the crate from a folder (**proposed**); nil for a crate not built from a
    /// folder, such as one converted from the lab's files.
    public var importLog: ImportLog?

    public init(crateId: String, name: String, createdAt: String, devicesSeen: [String],
                schema: Int = CrateFormat.schema, minReader: Int = 1, importLog: ImportLog? = nil) {
        self.schema = schema
        self.minReader = minReader
        self.crateId = crateId
        self.name = name
        self.createdAt = createdAt
        self.devicesSeen = devicesSeen
        self.importLog = importLog
    }

    enum CodingKeys: String, CodingKey {
        case schema, name, minReader = "min_reader", crateId = "crate_id", createdAt = "created_at"
        case devicesSeen = "devices_seen", importLog = "import_log"
    }

    /// The manifest's `import_log` (**proposed**): every audio file of the folder that has no record of its own, so
    /// no file is left out silently. A file is "audio" by its extension; one that could not be analysed is listed with
    /// its path below the folder (never an absolute path), its extension, a reason and the reason's text. `counts`
    /// (reason, then extension, to the number of files) is written from the entries for a quick look and recomputed
    /// by readers, as `engines_used` is.
    public struct ImportLog: Codable, Equatable, Sendable {
        /// Why a file has no record of its own.
        public enum Reason {
            /// A format, or a variant of one, that this platform's decoder cannot read (AAC on Linux, WMA, Ogg, ...).
            public static let unsupported = "unsupported"
            /// Locked by copy protection (an iTunes Store or Apple Music file): no decoder will ever read it.
            public static let protected = "protected"
            /// The file starts like a format it knows but its contents do not hold together (cut short, corrupted).
            public static let damaged = "damaged"
            /// The file could not be read, or decoding failed in some other way.
            public static let decodeError = "decode_error"
            /// Decoded, but the analysis failed (no beat grid, too few bars, the model failed).
            public static let analysisError = "analysis_error"
            /// The same bytes as another file of the folder, which has the record (the record id is the file's hash).
            public static let duplicate = "duplicate"
            public static let all = [unsupported, protected, damaged, decodeError, analysisError, duplicate]
        }

        /// One file without a record of its own.
        public struct Entry: Codable, Equatable, Sendable {
            /// The path below the folder the crate was built from.
            public var rel: String
            /// The file's extension, lower case, without the dot (`mp3`, `m4p`).
            public var ext: String
            /// One of `Reason`.
            public var reason: String
            /// The reason in words, as the decoder or the analyser gave it.
            public var message: String
            public init(rel: String, ext: String, reason: String, message: String) {
                self.rel = rel; self.ext = ext; self.reason = reason; self.message = message
            }
        }

        /// What the DJ's rekordbox collection export contributed: its track count and how many matched a file.
        public struct Rekordbox: Codable, Equatable, Sendable {
            public var tracks: Int
            public var matched: Int
            public init(tracks: Int, matched: Int) { self.tracks = tracks; self.matched = matched }
        }

        /// The device that built the crate: a model label (`Mac15,6`, `linux-x86_64`), never a name the user gave the
        /// machine, by the same rule and with the same value as the records' `analysis.device`, so a crate names no
        /// person's computer.
        public var builtBy: String
        /// When the build finished, UTC to the second.
        public var builtAt: String
        /// Audio files found in the folder, by extension.
        public var filesSeen: Int
        /// Records the build wrote (files seen less the entries).
        public var tracks: Int
        /// Sorted by `rel`.
        public var entries: [Entry]
        public var rekordbox: Rekordbox?

        public init(builtBy: String, builtAt: String, filesSeen: Int, tracks: Int, entries: [Entry],
                    rekordbox: Rekordbox? = nil) {
            self.builtBy = builtBy; self.builtAt = builtAt; self.filesSeen = filesSeen; self.tracks = tracks
            self.entries = entries; self.rekordbox = rekordbox
        }

        /// Reason, then extension, to the number of entries.
        public var counts: [String: [String: Int]] {
            var c: [String: [String: Int]] = [:]
            for e in entries { c[e.reason, default: [:]][e.ext, default: 0] += 1 }
            return c
        }

        enum CodingKeys: String, CodingKey {
            case entries, rekordbox, tracks, counts, builtBy = "built_by", builtAt = "built_at", filesSeen = "files_seen"
        }

        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            builtBy = try c.decode(String.self, forKey: .builtBy)
            builtAt = try c.decode(String.self, forKey: .builtAt)
            filesSeen = try c.decode(Int.self, forKey: .filesSeen)
            tracks = try c.decode(Int.self, forKey: .tracks)
            entries = try c.decode([Entry].self, forKey: .entries)
            rekordbox = try c.decodeIfPresent(Rekordbox.self, forKey: .rekordbox)
        }

        public func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(builtBy, forKey: .builtBy)
            try c.encode(builtAt, forKey: .builtAt)
            try c.encode(filesSeen, forKey: .filesSeen)
            try c.encode(tracks, forKey: .tracks)
            try c.encode(entries, forKey: .entries)
            try c.encode(counts, forKey: .counts)
            try c.encodeIfPresent(rekordbox, forKey: .rekordbox)
        }
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
        /// The tempo written down for the file before it was analysed (the DJ's rekordbox tempo, or the file's own tag
        /// such as ID3 TBPM), which steered the analysis between double and half tempo; nil when there was none. It is
        /// a fact about the file, not something imported, so it sits here and not in `imported`.
        public var tagBpm: Double?
        public init(name: String, rel: String?, bytes: Int?, sha1Head: String?, sha256: String? = nil,
                    durationS: Double, tagBpm: Double? = nil) {
            self.name = name; self.rel = rel; self.bytes = bytes; self.sha1Head = sha1Head; self.sha256 = sha256
            self.durationS = durationS; self.tagBpm = tagBpm
        }
        enum CodingKeys: String, CodingKey {
            case name, rel, bytes, sha256, sha1Head = "sha1_head", durationS = "duration_s", tagBpm = "tag_bpm"
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

    /// What was imported with the track from the DJ's own software, keyed by source: `rekordbox` now, and a Serato
    /// import would sit beside it under its own name. It holds the DJ's data as their software wrote it, never the
    /// engine's, so the block is named for where it came from. Nil when nothing was imported. A reader that does not
    /// know it ignores it.
    public struct Imported: Codable, Equatable, Sendable {
        /// The track's entry in a rekordbox collection export (rekordbox's XML), as rekordbox wrote it. Times are
        /// seconds from the start of the file as rekordbox decodes it.
        public struct Rekordbox: Codable, Equatable, Sendable {
            /// One of rekordbox's grid markers (a TEMPO element): the beat at `startS` is beat `beatInBar` of its
            /// bar, and the grid runs at `bpm` in `meter` from there to the next marker.
            public struct GridMarker: Codable, Equatable, Sendable {
                public var startS: Double
                public var bpm: Double
                /// As written, `4/4`, or null.
                public var meter: String?
                public var beatInBar: Int
                public init(startS: Double, bpm: Double, meter: String?, beatInBar: Int) {
                    self.startS = startS; self.bpm = bpm; self.meter = meter; self.beatInBar = beatInBar
                }
                enum CodingKeys: String, CodingKey {
                    case bpm, meter, startS = "start_s", beatInBar = "beat_in_bar"
                }
            }

            /// A cue point or another position mark that is not a loop (a POSITION_MARK element of type 0 to 3).
            public struct Cue: Codable, Equatable, Sendable {
                /// The DJ's name for it; empty when unnamed.
                public var name: String
                /// `cue`, `fade-in`, `fade-out` or `load` (rekordbox's types 0 to 3).
                public var kind: String
                /// The hot cue's number, 0 for A to 7 for H; null for a memory cue.
                public var hotCue: Int?
                public var startS: Double
                public init(name: String, kind: String, hotCue: Int?, startS: Double) {
                    self.name = name; self.kind = kind; self.hotCue = hotCue; self.startS = startS
                }
                enum CodingKeys: String, CodingKey { case name, kind, hotCue = "hot_cue", startS = "start_s" }
            }

            /// A loop (a POSITION_MARK element of type 4), from `startS` to `endS`.
            public struct Loop: Codable, Equatable, Sendable {
                /// The DJ's name for it; empty when unnamed.
                public var name: String
                /// The hot cue holding it, 0 for A to 7 for H; null for a memory loop.
                public var hotCue: Int?
                public var startS: Double
                /// Null only when rekordbox wrote no end.
                public var endS: Double?
                public init(name: String, hotCue: Int?, startS: Double, endS: Double?) {
                    self.name = name; self.hotCue = hotCue; self.startS = startS; self.endS = endS
                }
                enum CodingKeys: String, CodingKey { case name, hotCue = "hot_cue", startS = "start_s", endS = "end_s" }
            }

            /// When the entry was taken from the export, UTC to the second. A rebuild that finds the entry unchanged
            /// keeps the first time, so a rebuild from the same export changes no record, and of two devices'
            /// different imports the newer can be told.
            public var importedAt: String
            /// rekordbox's TrackID within that export.
            public var trackId: String
            /// The average tempo rekordbox shows (`AverageBpm`); null when it has none.
            public var bpm: Double?
            /// The key as rekordbox wrote it (`Tonality`: `Am`, `8A` or `1m`, by the DJ's display setting); its
            /// Camelot code is the vote `rekordbox-xml` in `key.votes`.
            public var tonality: String?
            public var gridMarkers: [GridMarker]
            public var cues: [Cue]
            public var loops: [Loop]
            /// The playlists holding the track, each as its path of folder names from the top, the playlist last.
            public var playlists: [[String]]

            public init(importedAt: String, trackId: String, bpm: Double?, tonality: String?, gridMarkers: [GridMarker],
                        cues: [Cue], loops: [Loop], playlists: [[String]]) {
                self.importedAt = importedAt; self.trackId = trackId; self.bpm = bpm; self.tonality = tonality
                self.gridMarkers = gridMarkers; self.cues = cues; self.loops = loops; self.playlists = playlists
            }
            enum CodingKeys: String, CodingKey {
                case bpm, tonality, cues, loops, playlists, importedAt = "imported_at", trackId = "track_id",
                     gridMarkers = "grid_markers"
            }
        }

        public var rekordbox: Rekordbox?

        public init(rekordbox: Rekordbox? = nil) { self.rekordbox = rekordbox }
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
    /// What was imported with the track from the DJ's own software, by source; nil when nothing was.
    public var imported: Imported?
    /// Where the track is sung, to the beat, and the hook candidates (accepted Oct 29, 2026, with memo Q's vocal fields); nil
    /// when the engine made none. Unlike every other field, a nil one is left out of crate.json rather than written as
    /// null, so the records of engines that do not make them keep their bytes.
    public var vocalStructure: VocalStructure?
    public var hooks: Hooks?
    /// The per-bar series (`bars/<id>.bin`), not part of crate.json.
    public var bars: BarSeries? = nil

    public init(id: String, schema: Int = CrateFormat.schema, file: File, ident: Ident, analysis: Analysis,
                engine: Engine, grid: Grid? = nil, tempoSegments: [TempoSegment]? = nil, key: Key? = nil,
                phrase: Phrase? = nil, sections: [Section]? = nil, mixIn: MixWindow? = nil, mixOut: MixWindow? = nil,
                ends: Ends? = nil, loudness: Loudness? = nil, vocal: Vocal? = nil, onsetPattern16: [Double]? = nil,
                flags: [String] = [], style: Style? = nil, signatures: [String: Signature] = [:],
                bars: BarSeries? = nil, imported: Imported? = nil, vocalStructure: VocalStructure? = nil,
                hooks: Hooks? = nil) {
        self.id = id; self.schema = schema; self.file = file; self.ident = ident; self.analysis = analysis
        self.engine = engine; self.grid = grid; self.tempoSegments = tempoSegments; self.key = key
        self.phrase = phrase; self.sections = sections; self.mixIn = mixIn; self.mixOut = mixOut; self.ends = ends
        self.loudness = loudness; self.vocal = vocal; self.onsetPattern16 = onsetPattern16; self.flags = flags
        self.style = style; self.signatures = signatures; self.bars = bars; self.imported = imported
        self.vocalStructure = vocalStructure; self.hooks = hooks
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
        if vocalStructure != nil { f.append(F.vocalStructure) }
        if hooks != nil { f.append(F.hooks) }
        if let bars { f += bars.names.map(F.bars) }
        return f.sorted(by: byteOrder)
    }

    enum CodingKeys: String, CodingKey {
        case id, schema, file, ident, analysis, engine, grid, key, phrase, sections, ends, loudness, vocal, flags
        case style, signatures, imported, hooks
        case tempoSegments = "tempo_segments", mixIn = "mix_in", mixOut = "mix_out", onsetPattern16 = "onset_pattern_16"
        case vocalStructure = "vocal_structure"
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
        try c.encodeIfPresent(imported, forKey: .imported)
        // Left out when nil (crate-format.md, "Additions proposed with the vocal fields").
        if let vocalStructure { try c.encode(vocalStructure, forKey: .vocalStructure) }
        if let hooks { try c.encode(hooks, forKey: .hooks) }
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
