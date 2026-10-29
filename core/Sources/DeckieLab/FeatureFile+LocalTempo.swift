import Foundation
import DeckieCore

// The local tempo port's view of a feature file: the lab's `local_tempo` block as written, and the input
// `DeckieCore.LocalTempo.compute` takes, built from the fields mixer/local_tempo.py's `compute(feat)` reads.
// The stored fields it needs beyond the rest of FeatureFile (`beats_s`, `downbeats_s`, `first_sound_s`,
// `last_sound_s` and each mix window's `start_s` and `end_s`) are declared in FeatureFile.swift, marked there.

extension FeatureFile {
    /// The lab's `local_tempo` block (mixer/local_tempo.py, `compute`): every key, as the lab wrote it, for comparing
    /// with `DeckieCore.LocalTempo`, which has the same fields under Swift names (the lab's names are on the
    /// coding keys). Every field is optional so that a block from an older version of the script, with fewer keys,
    /// still decodes, as the scorer only reads a few of them; the current script writes them all, and the ones that
    /// can be null are the ones `DeckieCore.LocalTempo` has as optionals.
    public struct LocalTempo: Decodable, Sendable {
        /// One window's regression (the lab's `_local`).
        public struct Window: Decodable, Sendable {
            public var bpm: Double
            public var bpmRaw: Double
            public var mult: Double
            public var nBeats: Int
            public var residMs: Double
            public var t0: Double
            public var t1: Double
            enum CodingKeys: String, CodingKey {
                case bpm, mult, t0, t1
                case bpmRaw = "bpm_raw", nBeats = "n_beats", residMs = "resid_ms"
            }
        }

        /// One profile segment, written by the lab as the array `[start, bpm, trusted]`.
        public struct Segment: Decodable, Sendable {
            public var start: Double
            public var bpm: Double
            public var trusted: Bool

            public init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                start = try c.decode(Double.self)
                bpm = try c.decode(Double.self)
                trusted = try c.decode(Bool.self)
                if !c.isAtEnd {
                    throw DecodingError.dataCorruptedError(in: c, debugDescription: "a profile segment has three values")
                }
            }
        }

        public var refBpm: Double?
        public var first30: Window?
        public var last30: Window?
        public var mixIn: Window?
        public var mixOut: Window?
        public var gridDevInMs: Double?
        public var gridDevOutMs: Double?
        public var bpmIn: Double?
        public var inTrusted: Bool?
        /// The lab's rule name, one of `DeckieCore.LocalTempo.Rule`'s raw values.
        public var inRule: String?
        public var bpmOut: Double?
        public var outTrusted: Bool?
        public var outRule: String?
        public var driftPct: Double?
        public var profile: [Segment]?
        public var rangePct: Double?
        public var untrustedSegments: Int?
        public var steadyInS: Double?
        public var steadyInBar: Int?
        public var steadyOutS: Double?
        public var steadyOutBar: Int?
        public var firstDownbeatInS: Double?
        public var firstDownbeatOutS: Double?
        public var tempoChange: Bool?
        public var transitionTrack: Bool?
        public var inHalfTime: Bool?
        public var outHalfTime: Bool?
        public var introNoSteadyBeat: Bool?
        public var outroNoSteadyBeat: Bool?

        enum CodingKeys: String, CodingKey {
            case first30, last30, profile
            case refBpm = "ref_bpm", mixIn = "mix_in", mixOut = "mix_out"
            case gridDevInMs = "grid_dev_in_ms", gridDevOutMs = "grid_dev_out_ms"
            case bpmIn = "bpm_in", inTrusted = "in_trusted", inRule = "in_rule"
            case bpmOut = "bpm_out", outTrusted = "out_trusted", outRule = "out_rule"
            case driftPct = "drift_pct", rangePct = "range_pct", untrustedSegments = "untrusted_segments"
            case steadyInS = "steady_in_s", steadyInBar = "steady_in_bar"
            case steadyOutS = "steady_out_s", steadyOutBar = "steady_out_bar"
            case firstDownbeatInS = "first_downbeat_in_s", firstDownbeatOutS = "first_downbeat_out_s"
            case tempoChange = "tempo_change", transitionTrack = "transition_track"
            case inHalfTime = "in_half_time", outHalfTime = "out_half_time"
            case introNoSteadyBeat = "intro_no_steady_beat", outroNoSteadyBeat = "outro_no_steady_beat"
        }
    }

    /// What `DeckieCore.LocalTempo.compute` reads, taken from this file as mixer/local_tempo.py's `compute(feat)`
    /// takes it: the global `bpm`, `duration_s`, the detected beats and downbeats with the grid's `beats_s` and
    /// `downbeats_s` behind them, `grid.first_downbeat_s`, `first_sound_s`, `last_sound_s`, and the mix windows'
    /// `start_s` and `end_s`.
    public var localTempoInput: LocalTempoInput {
        LocalTempoInput(
            bpm: bpm, duration: durationS, detectedBeats: detectedBeatsS,
            detectedDownbeats: detectedDownbeatsS ?? [], gridBeats: beatsS ?? [], gridDownbeats: downbeatsS ?? [],
            firstDownbeat: grid.firstDownbeatS, firstSound: firstSoundS, lastSound: lastSoundS,
            mixIn: .init(start: mixIn.startS, end: mixIn.endS), mixOut: .init(start: mixOut.startS, end: mixOut.endS))
    }
}
