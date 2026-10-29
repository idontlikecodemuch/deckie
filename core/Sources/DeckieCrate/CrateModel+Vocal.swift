import Foundation

// The two blocks accepted with memo Q's vocal fields (docs/research/q-vocal-uses.md, sections 3 and 4;
// docs/architecture/crate-format.md, "Additions proposed with the vocal fields"): `vocal_structure` and `hooks`. Both
// are additive: a record without them reads as before, and a writer leaves them out rather than writing null, so the
// records of engines that do not make them (the lab's, the Apple apps' until they add them) keep their bytes.

extension CrateTrack {
    /// Where the track is sung, to the beat (accepted Oct 29, 2026): memo Q's items A1 to A6, from the vocal tagger's
    /// frame-by-frame scores, the grid and the lattice. Bars are 1-based and beats 1 to 4 within a bar; a span's end is
    /// the beat line it stops at (exclusive), so it can be beat 1 of bar `n_bars + 1`.
    public struct VocalStructure: Codable, Equatable, Sendable {
        /// The intro and outro kinds.
        public static let kinds = ["beat_only", "ambient", "vocal", "fade"]

        /// A sung stretch: the beat it starts on and the beat line it stops at, with the times they were read from,
        /// and each end's signed distance in beats from the nearest 8-bar lattice point (memo Q's `span_end_offset`;
        /// near zero, on a phrase boundary).
        public struct Span: Codable, Equatable, Sendable {
            public var startBar: Int
            public var startBeat: Int
            public var startS: Double
            public var endBar: Int
            public var endBeat: Int
            public var endS: Double
            public var startOffsetBeats: Int
            public var endOffsetBeats: Int

            public init(startBar: Int, startBeat: Int, startS: Double, endBar: Int, endBeat: Int, endS: Double,
                        startOffsetBeats: Int, endOffsetBeats: Int) {
                self.startBar = startBar; self.startBeat = startBeat; self.startS = startS; self.endBar = endBar
                self.endBeat = endBeat; self.endS = endS; self.startOffsetBeats = startOffsetBeats
                self.endOffsetBeats = endOffsetBeats
            }
            enum CodingKeys: String, CodingKey {
                case startBar = "start_bar", startBeat = "start_beat", startS = "start_s", endBar = "end_bar"
                case endBeat = "end_beat", endS = "end_s", startOffsetBeats = "start_offset_beats"
                case endOffsetBeats = "end_offset_beats"
            }
        }

        /// The first sung beat, the time singing starts, and whether it is a pickup (within `rule.pickup_beats` before
        /// a downbeat).
        public struct First: Codable, Equatable, Sendable {
            public var bar: Int
            public var beat: Int
            public var timeS: Double
            public var pickup: Bool
            public init(bar: Int, beat: Int, timeS: Double, pickup: Bool) {
                self.bar = bar; self.beat = beat; self.timeS = timeS; self.pickup = pickup
            }
            enum CodingKeys: String, CodingKey { case bar, beat, pickup, timeS = "time_s" }
        }

        /// The last sung beat and the time singing stops.
        public struct Last: Codable, Equatable, Sendable {
            public var bar: Int
            public var beat: Int
            public var timeS: Double
            public init(bar: Int, beat: Int, timeS: Double) { self.bar = bar; self.beat = beat; self.timeS = timeS }
            enum CodingKeys: String, CodingKey { case bar, beat, timeS = "time_s" }
        }

        /// Bars `start_bar ..< end_bar`, `bars` long.
        public struct Gap: Codable, Equatable, Sendable {
            public var startBar: Int
            public var endBar: Int
            public var bars: Int
            public init(startBar: Int, endBar: Int) {
                self.startBar = startBar; self.endBar = endBar; self.bars = endBar - startBar
            }
            enum CodingKeys: String, CodingKey { case bars, startBar = "start_bar", endBar = "end_bar" }
        }

        /// Bars `start_bar ..< end_bar`.
        public struct Stretch: Codable, Equatable, Sendable {
            public var startBar: Int
            public var endBar: Int
            public init(startBar: Int, endBar: Int) { self.startBar = startBar; self.endBar = endBar }
            enum CodingKeys: String, CodingKey { case startBar = "start_bar", endBar = "end_bar" }
        }

        /// The rule that made the block, with its parameters and the threshold it used: the scores are uncalibrated,
        /// so a reader comparing records checks the rule, and the Mac's listening test tunes it.
        public struct Rule: Codable, Equatable, Sendable {
            /// The frame score a frame needed to count as sung: `max(threshold_floor, threshold_fraction x score_p95)`,
            /// `score_p95` being the track's 95th-percentile frame score.
            public var threshold: Double
            public var scoreP95: Double
            public var thresholdFraction: Double
            public var thresholdFloor: Double
            /// Dips shorter than this many beats are bridged; stretches shorter than `min_span_beats` then dropped.
            public var bridgeBeats: Int
            public var minSpanBeats: Int
            public var pickupBeats: Int
            public var minGapBars: Int
            /// The intro and outro kinds read at most `kind_bars` free bars at the edge: `beat_only` when their median
            /// onset density is at least `beat_density_ratio` of the track's median and their median `high_db` at most
            /// `bright_margin_db` above the track's, `ambient` otherwise.
            public var kindBars: Int
            public var beatDensityRatio: Double
            public var brightMarginDb: Double
            /// A bar is exposed (proxy) when at least half its beats are sung, its `low_db` is `exposed_low_drop_db`
            /// under the track's median and its onset density at most `exposed_density_ratio` of the track's median,
            /// in runs of `exposed_min_bars` or more.
            public var exposedLowDropDb: Double
            public var exposedDensityRatio: Double
            public var exposedMinBars: Int

            public init(threshold: Double, scoreP95: Double, thresholdFraction: Double, thresholdFloor: Double,
                        bridgeBeats: Int, minSpanBeats: Int, pickupBeats: Int, minGapBars: Int, kindBars: Int,
                        beatDensityRatio: Double, brightMarginDb: Double, exposedLowDropDb: Double,
                        exposedDensityRatio: Double, exposedMinBars: Int) {
                self.threshold = threshold; self.scoreP95 = scoreP95; self.thresholdFraction = thresholdFraction
                self.thresholdFloor = thresholdFloor; self.bridgeBeats = bridgeBeats; self.minSpanBeats = minSpanBeats
                self.pickupBeats = pickupBeats; self.minGapBars = minGapBars; self.kindBars = kindBars
                self.beatDensityRatio = beatDensityRatio; self.brightMarginDb = brightMarginDb
                self.exposedLowDropDb = exposedLowDropDb; self.exposedDensityRatio = exposedDensityRatio
                self.exposedMinBars = exposedMinBars
            }
            enum CodingKeys: String, CodingKey {
                case threshold, scoreP95 = "score_p95", thresholdFraction = "threshold_fraction"
                case thresholdFloor = "threshold_floor", bridgeBeats = "bridge_beats", minSpanBeats = "min_span_beats"
                case pickupBeats = "pickup_beats", minGapBars = "min_gap_bars", kindBars = "kind_bars"
                case beatDensityRatio = "beat_density_ratio", brightMarginDb = "bright_margin_db"
                case exposedLowDropDb = "exposed_low_drop_db", exposedDensityRatio = "exposed_density_ratio"
                case exposedMinBars = "exposed_min_bars"
            }
        }

        /// The tagger whose scores were read (a model from `engine.models`), as the `vocal` block's `source`.
        public var source: String
        /// Seconds between the frames read: the tagger's hop, or the bar length when it gave bars only.
        public var frameHopS: Double
        /// The lattice the gaps are snapped to and the offsets measured from (`phrase.lattice_phase_bar`).
        public var latticePhaseBar: Int
        public var rule: Rule
        public var spans: [Span]
        public var first: First?
        public var last: Last?
        /// Whole bars before the first sung beat and after the last (`n_bars` when nothing is sung), and what they hold.
        public var introFreeBars: Int
        public var introKind: String
        public var outroFreeBars: Int
        public var outroKind: String
        /// Vocal-free stretches of `rule.min_gap_bars` or more, each starting on the lattice.
        public var freeGaps: [Gap]
        /// Stretches where the voice goes on over little bass and few onsets: a stand-in, from `low_db` and the onset
        /// density, for memo Q's `exposed` (vocal high, drums and bass low), which the Apple apps' records can carry
        /// from real drum and bass activity; a reader prefers that when present.
        public var exposedProxy: [Stretch]

        public init(source: String, frameHopS: Double, latticePhaseBar: Int, rule: Rule, spans: [Span], first: First?,
                    last: Last?, introFreeBars: Int, introKind: String, outroFreeBars: Int, outroKind: String,
                    freeGaps: [Gap], exposedProxy: [Stretch]) {
            self.source = source; self.frameHopS = frameHopS; self.latticePhaseBar = latticePhaseBar; self.rule = rule
            self.spans = spans; self.first = first; self.last = last; self.introFreeBars = introFreeBars
            self.introKind = introKind; self.outroFreeBars = outroFreeBars; self.outroKind = outroKind
            self.freeGaps = freeGaps; self.exposedProxy = exposedProxy
        }
        enum CodingKeys: String, CodingKey {
            case source, rule, spans, first, last
            case frameHopS = "frame_hop_s", latticePhaseBar = "lattice_phase_bar", introFreeBars = "intro_free_bars"
            case introKind = "intro_kind", outroFreeBars = "outro_free_bars", outroKind = "outro_kind"
            case freeGaps = "free_gaps", exposedProxy = "exposed_proxy"
        }
    }

    /// Up to three hook candidates, strongest first (accepted Oct 29, 2026): memo Q's item B7, stretches of 4 to 8 bars that
    /// repeat, are loud for the track and are sung, for the DJ to confirm with one tap.
    public struct Hooks: Codable, Equatable, Sendable {
        /// One candidate: bars `start_bar ..< end_bar`, its `strength` (0 to 1) and the three terms it is made of, whether
        /// it is sung, and where it comes again (`repeat_start_bar`, the same length).
        public struct Candidate: Codable, Equatable, Sendable {
            public var startBar: Int
            public var endBar: Int
            public var strength: Double
            public var sung: Bool
            public var repetition: Double
            public var loudnessScore: Double
            public var vocalDensity: Double
            public var repeatStartBar: Int

            public init(startBar: Int, endBar: Int, strength: Double, sung: Bool, repetition: Double,
                        loudnessScore: Double, vocalDensity: Double, repeatStartBar: Int) {
                self.startBar = startBar; self.endBar = endBar; self.strength = strength; self.sung = sung
                self.repetition = repetition; self.loudnessScore = loudnessScore; self.vocalDensity = vocalDensity
                self.repeatStartBar = repeatStartBar
            }
            enum CodingKeys: String, CodingKey {
                case strength, sung, repetition, startBar = "start_bar", endBar = "end_bar"
                case loudnessScore = "loudness_score", vocalDensity = "vocal_density", repeatStartBar = "repeat_start_bar"
            }
        }

        /// The rule and its parameters: strength = (weight_repetition x repetition + weight_loudness x loudness_score +
        /// weight_vocal x vocal_density) / the weights' sum, over candidates of `lengths_bars` starting every
        /// `step_bars` from the lattice phase that repeat at least `min_repetition`.
        public struct Rule: Codable, Equatable, Sendable {
            public var lengthsBars: [Int]
            public var stepBars: Int
            public var weightRepetition: Double
            public var weightLoudness: Double
            public var weightVocal: Double
            public var minRepetition: Double
            public var shortMargin: Double
            public var sungShare: Double
            public var maxHooks: Int

            public init(lengthsBars: [Int], stepBars: Int, weightRepetition: Double, weightLoudness: Double,
                        weightVocal: Double, minRepetition: Double, shortMargin: Double, sungShare: Double,
                        maxHooks: Int) {
                self.lengthsBars = lengthsBars; self.stepBars = stepBars; self.weightRepetition = weightRepetition
                self.weightLoudness = weightLoudness; self.weightVocal = weightVocal; self.minRepetition = minRepetition
                self.shortMargin = shortMargin; self.sungShare = sungShare; self.maxHooks = maxHooks
            }
            enum CodingKeys: String, CodingKey {
                case lengthsBars = "lengths_bars", stepBars = "step_bars", weightRepetition = "weight_repetition"
                case weightLoudness = "weight_loudness", weightVocal = "weight_vocal", minRepetition = "min_repetition"
                case shortMargin = "short_margin", sungShare = "sung_share", maxHooks = "max_hooks"
            }
        }

        /// The method (`deckie-core` for DeckieCore's `Hooks`).
        public var source: String
        public var latticePhaseBar: Int
        public var rule: Rule
        public var candidates: [Candidate]

        public init(source: String, latticePhaseBar: Int, rule: Rule, candidates: [Candidate]) {
            self.source = source; self.latticePhaseBar = latticePhaseBar; self.rule = rule; self.candidates = candidates
        }
        enum CodingKeys: String, CodingKey { case source, rule, candidates, latticePhaseBar = "lattice_phase_bar" }
    }
}
