import Foundation
import DeckieCore

extension FeatureFile {
    /// The parts of a lab feature file that the structure port reads and writes: the grid, first and last sound,
    /// novelty peaks, phrase, boundaries, sections, per-bar loudness and vocal probability, the end loudness and the
    /// fade, the mix windows, and what the flags are made from. Decoded on its own (`FeatureFile.Structure.load`) so
    /// it can grow without touching `FeatureFile`. Field names follow the file; see mixer/README.md.
    public struct Structure: Decodable, Sendable {
        public struct Grid: Decodable, Sendable {
            public var bpm: Double
            public var firstDownbeatS: Double
            public var beatS: Double
            public var barS: Double
            public var confidence: Double
            public var nBars: Int
            enum CodingKeys: String, CodingKey {
                case bpm, confidence
                case firstDownbeatS = "first_downbeat_s", beatS = "beat_s", barS = "bar_s", nBars = "n_bars"
            }
        }
        public struct PhraseRecord: Decodable, Sendable {
            public var latticePhaseBar: Int
            public var phraseLenBars: Int
            public var confidence: Double
            public var phaseNovelty: [Double]
            public var snapPhaseBar: Int
            enum CodingKeys: String, CodingKey {
                case confidence
                case latticePhaseBar = "lattice_phase_bar", phraseLenBars = "phrase_len_bars"
                case phaseNovelty = "phase_novelty", snapPhaseBar = "snap_phase_bar"
            }
        }
        public struct SectionRecord: Decodable, Sendable {
            public var startBar: Int
            public var endBar: Int
            public var label: String
            public var energy: String
            public var lufs: Double
            public var vocal: Double
            enum CodingKeys: String, CodingKey {
                case label, energy, lufs, vocal, startBar = "start_bar", endBar = "end_bar"
            }
        }
        public struct EndLufs: Decodable, Sendable {
            public var t20: Double
            public var t10: Double
            public var t4: Double
            enum CodingKeys: String, CodingKey { case t20 = "t-20", t10 = "t-10", t4 = "t-4" }
        }
        public struct MixInRecord: Decodable, Sendable {
            public var startBar: Int
            public var endBar: Int
            public var bars: Int
            public var startS: Double
            public var endS: Double
            public var vocalFreeBars: Int
            public var firstVocalBar: Int?
            enum CodingKeys: String, CodingKey {
                case bars, startBar = "start_bar", endBar = "end_bar", startS = "start_s", endS = "end_s"
                case vocalFreeBars = "vocal_free_bars", firstVocalBar = "first_vocal_bar"
            }
        }
        public struct MixOutRecord: Decodable, Sendable {
            public var startBar: Int
            public var endBar: Int
            public var bars: Int
            public var startS: Double
            public var endS: Double
            public var vocalFreeBars: Int
            public var lastVocalBar: Int?
            public var fadeOut: Bool
            enum CodingKeys: String, CodingKey {
                case bars, startBar = "start_bar", endBar = "end_bar", startS = "start_s", endS = "end_s"
                case vocalFreeBars = "vocal_free_bars", lastVocalBar = "last_vocal_bar", fadeOut = "fade_out"
            }
        }
        public struct PerBar: Decodable, Sendable {
            public var lufsSt: [Double]
            public var vocalProb: [Double]
            enum CodingKeys: String, CodingKey { case lufsSt = "lufs_st", vocalProb = "vocal_prob" }
        }
        public struct Vocal: Decodable, Sendable {
            public var meanProb: Double
            public var vocalHeavy: Bool
            enum CodingKeys: String, CodingKey { case meanProb = "mean_prob", vocalHeavy = "vocal_heavy" }
        }
        public struct Key: Decodable, Sendable {
            public var confidence: Double
        }
        /// The local-tempo booleans that become flags (mixer/local_tempo.py, `flags`).
        public struct LocalTempoFlags: Decodable, Sendable {
            public var tempoChange: Bool?
            public var transitionTrack: Bool?
            public var inHalfTime: Bool?
            public var outHalfTime: Bool?
            public var introNoSteadyBeat: Bool?
            public var outroNoSteadyBeat: Bool?
            enum CodingKeys: String, CodingKey {
                case tempoChange = "tempo_change", transitionTrack = "transition_track"
                case inHalfTime = "in_half_time", outHalfTime = "out_half_time"
                case introNoSteadyBeat = "intro_no_steady_beat", outroNoSteadyBeat = "outro_no_steady_beat"
            }

            /// The flag names in the order mixer/local_tempo.py's `flags` gives them.
            public var names: [String] {
                var f: [String] = []
                if tempoChange == true { f.append("tempo_change") }
                if transitionTrack == true { f.append("transition_track") }
                if inHalfTime == true { f.append("intro_half_time") }
                if outHalfTime == true { f.append("outro_half_time") }
                if introNoSteadyBeat == true { f.append("intro_no_steady_beat") }
                if outroNoSteadyBeat == true { f.append("outro_no_steady_beat") }
                return f
            }
        }

        public var id: String
        public var durationS: Double
        public var bpm: Double
        public var bpmTag: Double?
        public var multiplierVsTagValue: Double
        public var grid: Grid
        public var downbeatsS: [Double]
        public var beatsS: [Double]
        public var firstSoundS: Double
        public var lastSoundS: Double
        /// `[bar, value]` pairs, 1-based bars, sorted by bar; values to 3 decimals.
        public var noveltyPeaks: [[Double]]
        public var phrase: PhraseRecord
        public var boundariesBars: [Int]
        public var sections: [SectionRecord]
        public var perBar: PerBar
        public var endLufsSt: EndLufs
        public var fadeOut: Bool
        public var fadeDropLu: Double
        public var tailBars: Double
        public var fadeStartBar: Int?
        public var mixIn: MixInRecord
        public var mixOut: MixOutRecord
        public var vocal: Vocal
        public var key: Key
        public var flags: [String]
        public var localTempo: LocalTempoFlags?

        enum CodingKeys: String, CodingKey {
            case id, bpm, grid, phrase, sections, vocal, key, flags
            case durationS = "duration_s", bpmTag = "bpm_tag", multiplierVsTagValue = "multiplier_vs_tag_value"
            case downbeatsS = "downbeats_s", beatsS = "beats_s", firstSoundS = "first_sound_s"
            case lastSoundS = "last_sound_s", noveltyPeaks = "novelty_peaks", boundariesBars = "boundaries_bars"
            case perBar = "per_bar", endLufsSt = "end_lufs_st", fadeOut = "fade_out", fadeDropLu = "fade_drop_lu"
            case tailBars = "tail_bars", fadeStartBar = "fade_start_bar", mixIn = "mix_in", mixOut = "mix_out"
            case localTempo = "local_tempo"
        }

        public static func load(_ url: URL) throws -> Structure {
            try JSONDecoder().decode(Structure.self, from: Data(contentsOf: url))
        }

        /// The novelty peaks as DeckieCore values.
        public var peaks: [NoveltyPeak] { noveltyPeaks.map { NoveltyPeak(bar: Int($0[0]), value: $0[1]) } }
        /// The end loudness as a DeckieCore value.
        public var endLoudness: EndLoudness { EndLoudness(t20: endLufsSt.t20, t10: endLufsSt.t10, t4: endLufsSt.t4) }
        /// The written phrase as a DeckieCore value.
        public var phraseValue: Phrase {
            Phrase(latticePhaseBar: phrase.latticePhaseBar, phraseLenBars: phrase.phraseLenBars,
                   confidence: phrase.confidence, phaseNovelty: phrase.phaseNovelty, snapPhaseBar: phrase.snapPhaseBar)
        }
        /// The written sections as DeckieCore values.
        public var sectionValues: [Section] {
            sections.map { Section(startBar: $0.startBar, endBar: $0.endBar, label: $0.label, energy: $0.energy,
                                   lufs: $0.lufs, vocal: $0.vocal) }
        }
        /// The written mix-in window as a DeckieCore value.
        public var mixInValue: MixIn {
            MixIn(startBar: mixIn.startBar, endBar: mixIn.endBar, bars: mixIn.bars, startS: mixIn.startS,
                  endS: mixIn.endS, vocalFreeBars: mixIn.vocalFreeBars, firstVocalBar: mixIn.firstVocalBar)
        }
        /// The written mix-out window as a DeckieCore value.
        public var mixOutValue: MixOut {
            MixOut(startBar: mixOut.startBar, endBar: mixOut.endBar, bars: mixOut.bars, startS: mixOut.startS,
                   endS: mixOut.endS, vocalFreeBars: mixOut.vocalFreeBars, lastVocalBar: mixOut.lastVocalBar,
                   fadeOut: mixOut.fadeOut)
        }
    }
}
