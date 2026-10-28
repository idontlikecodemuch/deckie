import Foundation
import DeckieCore
import DeckieCrate

// The lab's feature files as crate records (docs/architecture/crate-format.md, "From the lab's feature files").
// Every committed mixer/features/<id>.json converts; the numbers keep the lab's rounding, the per-bar series are
// rounded to float16 as the bars sidecar holds them, and nothing is analysed again.

extension FeatureFile {
    /// The folder the lab's `path`s start with (mixer/candidates.json); a record's `file.rel` is the path below it.
    public static let labMusicRoot = "/Users/christophershannon/personal/90s2000 playlist/"

    /// What a lab record cannot take from its feature file.
    public struct CrateOptions: Sendable {
        /// When the analysis ran: the files carry no date.
        public var analysedAt: String
        /// The device label written to `analysis.device`.
        public var device: String
        /// Stripped from the lab's absolute paths to give `file.rel`; a path outside it gets no `rel`.
        public var musicRoot: String

        public init(analysedAt: String, device: String = "lab-mac", musicRoot: String = FeatureFile.labMusicRoot) {
            self.analysedAt = analysedAt
            self.device = device
            self.musicRoot = musicRoot
        }
    }

    /// The crate record for the feature file at `url`, with its candidates.json row (for the artist, the song and
    /// the pool's bookkeeping) when there is one.
    public static func crateTrack(contentsOf url: URL, candidate: CandidateRecord?,
                                  options: CrateOptions) throws -> CrateTrack {
        try JSONDecoder().decode(CrateSource.self, from: Data(contentsOf: url)).crateTrack(candidate: candidate,
                                                                                            options: options)
    }

    /// A crate of the feature files in `featuresDir` (all of them, or the ones in `ids`), joined with their
    /// candidates.json rows, under `manifest`.
    public static func crate(featuresDir: URL, ids: [String]? = nil, candidatesFile: URL?, manifest: CrateManifest,
                             options: CrateOptions) throws -> Crate {
        var cands: [String: CandidateRecord] = [:]
        if let candidatesFile {
            cands = Dictionary(try CandidateRecord.loadAll(candidatesFile).map { ($0.id, $0) },
                               uniquingKeysWith: { a, _ in a })
        }
        let names = try ids.map { $0.map { "\($0).json" } }
            ?? FileManager.default.contentsOfDirectory(atPath: featuresDir.path).filter { $0.hasSuffix(".json") }
        let tracks = try names.sorted().map { name in
            try crateTrack(contentsOf: featuresDir.appendingPathComponent(name),
                           candidate: cands[String(name.dropLast(".json".count))], options: options)
        }
        return Crate(manifest: manifest, tracks: tracks.sorted { $0.id.utf8.lexicographicallyPrecedes($1.id.utf8) })
    }

    /// The fields of a feature file that a crate record takes, decoded on their own (as `FeatureFile.Structure` is).
    public struct CrateSource: Decodable, Sendable {
        /// One key detector's answer, written by the lab as `[key, scale, strength]`.
        public struct Vote: Decodable, Sendable {
            public var key: String
            public var scale: String
            public init(from decoder: Decoder) throws {
                var c = try decoder.unkeyedContainer()
                key = try c.decode(String.self)
                scale = try c.decode(String.self)
            }
        }
        public struct Key: Decodable, Sendable {
            public var essentiaEdma: Vote?
            public var essentiaBgate: Vote?
            public var madmomCnn: Vote?
            public var camelotEdma: String?
            public var camelotBgate: String?
            public var camelotMadmom: String?
            public var camelot: String
            public var confidence: Double
            enum CodingKeys: String, CodingKey {
                case camelot, confidence, essentiaEdma = "essentia_edma", essentiaBgate = "essentia_bgate",
                     madmomCnn = "madmom_cnn", camelotEdma = "camelot_edma", camelotBgate = "camelot_bgate",
                     camelotMadmom = "camelot_madmom"
            }
        }
        public struct Loudness: Decodable, Sendable {
            public var integratedLufs: Double
            public var lra: Double
            public var truePeakDb: Double
            enum CodingKeys: String, CodingKey {
                case lra, integratedLufs = "integrated_lufs", truePeakDb = "true_peak_db"
            }
        }
        public struct PerBar: Decodable, Sendable {
            public var lufsSt: [Double]
            public var lowDb: [Double]
            public var highDb: [Double]
            public var onsetDensity: [Double]
            public var vocalProb: [Double]
            enum CodingKeys: String, CodingKey {
                case lufsSt = "lufs_st", lowDb = "low_db", highDb = "high_db", onsetDensity = "onset_density",
                     vocalProb = "vocal_prob"
            }
        }
        public struct Meta: Decodable, Sendable {
            public var disc: String?
            public var folder: String?
            public var hal: Bool?
            public var kind: String?
            public var era: String?
            public var cutKey: String?
            public var isLongest: Bool?
            enum CodingKeys: String, CodingKey {
                case disc, folder, hal, kind, era, cutKey = "cut_key", isLongest = "is_longest"
            }
        }

        public var schema: Int?
        public var id: String
        public var title: String?
        public var ver: String?
        public var path: String?
        public var durationS: Double
        public var grid: FeatureFile.Grid
        public var localTempo: FeatureFile.LocalTempo?
        public var key: Key
        public var phrase: FeatureFile.Structure.PhraseRecord
        public var boundariesBars: [Int]
        public var sections: [FeatureFile.Structure.SectionRecord]
        public var firstSoundS: Double
        public var lastSoundS: Double
        public var fadeOut: Bool
        public var fadeStartBar: Int?
        public var mixIn: FeatureFile.Structure.MixInRecord
        public var mixOut: FeatureFile.Structure.MixOutRecord
        public var loudness: Loudness
        public var perBar: PerBar
        public var onsetPattern16: [Double]
        public var vocal: FeatureFile.Structure.Vocal
        public var flags: [String]
        public var meta: Meta?
        public var timingS: [String: Double]?

        enum CodingKeys: String, CodingKey {
            case schema, id, title, ver, path, grid, key, phrase, sections, loudness, vocal, flags, meta
            case durationS = "duration_s", localTempo = "local_tempo", boundariesBars = "boundaries_bars"
            case firstSoundS = "first_sound_s", lastSoundS = "last_sound_s", fadeOut = "fade_out"
            case fadeStartBar = "fade_start_bar", mixIn = "mix_in", mixOut = "mix_out", perBar = "per_bar"
            case onsetPattern16 = "onset_pattern_16", timingS = "timing_s"
        }

        /// The crate record.
        public func crateTrack(candidate c: CandidateRecord?, options: CrateOptions) -> CrateTrack {
            /// Empty text in the lab's files means "none", in the candidates row as in the feature file.
            func text(_ s: String?) -> String? { s.flatMap { $0.isEmpty ? nil : $0 } }
            let n = grid.nBars
            let lt = localTempo
            let gridModel = grid.source == "madmom" ? "madmom-rnn-dbn" : "beat-this-final0"
            // Beat This's detections feed the local tempo even when madmom's grid won, so it is always listed.
            var models = [CrateTrack.Engine.Model(name: "beat-this-final0")]
            if gridModel != "beat-this-final0" { models.append(.init(name: gridModel)) }
            var votes: [String: String] = [:]
            var spelled: Vote? = nil
            for (name, vote, code) in [("essentia-key-edma", key.essentiaEdma, key.camelotEdma),
                                       ("essentia-key-bgate", key.essentiaBgate, key.camelotBgate),
                                       ("madmom-key-cnn", key.madmomCnn, key.camelotMadmom)] {
                guard let code else { continue }
                votes[name] = code
                models.append(.init(name: name))
                if spelled == nil && code == key.camelot { spelled = vote }
            }
            models.append(.init(name: "discogs-effnet"))
            let path = text(self.path)
            let rel = path.flatMap { $0.hasPrefix(options.musicRoot) ? String($0.dropFirst(options.musicRoot.count)) : nil }
            /// A bar line, clamped to the grid's end: the lab rounds the end of a steady stretch to the nearest bar
            /// line, which past the last full bar can be the line after the partial last bar (n_bars + 2).
            func line(_ b: Int?) -> Int? { b.map { min($0, n + 1) } }

            return CrateTrack(
                id: id,
                file: .init(name: path.map { String($0.split(separator: "/").last ?? "") } ?? id, rel: rel, bytes: nil,
                            sha1Head: nil, durationS: durationS),
                ident: .init(title: text(c?.song) ?? text(title) ?? id, artist: text(c?.artist),
                             version: text(c?.ver) ?? text(ver), source: "lab", disc: text(c?.disc) ?? text(meta?.disc),
                             folder: text(c?.folder) ?? text(meta?.folder),
                             cutKey: text(c?.cutKey) ?? text(meta?.cutKey), isLongest: c?.isLongest ?? meta?.isLongest,
                             era: text(c?.era) ?? text(meta?.era), kind: text(c?.kind) ?? text(meta?.kind),
                             tags: (c?.hal ?? meta?.hal) == true ? ["halloween"] : []),
                analysis: .init(engine: "lab-\(schema ?? 1)", analysedAt: options.analysedAt, device: options.device,
                                secs: timingS.map { Py.round($0.values.sorted().reduce(0, +), 2) }, level: 1),
                engine: .init(family: "lab", version: "\(schema ?? 1)", platform: "macos-arm64", fidelity: 0,
                              models: models, decoder: .init(name: "soundfile")),
                grid: .init(source: gridModel, confidence: grid.confidence, bpm: grid.bpm,
                            firstDownbeatS: grid.firstDownbeatS, nBars: n, fitMadMs: grid.fitMadMs,
                            bpmIn: (lt?.bpmIn).flatMap { $0 != 0 ? $0 : nil } ?? grid.bpm,
                            bpmOut: (lt?.bpmOut).flatMap { $0 != 0 ? $0 : nil } ?? grid.bpm,
                            inTrusted: lt?.inTrusted ?? true, outTrusted: lt?.outTrusted ?? true),
                tempoSegments: [.init(startBar: 1, startS: grid.firstDownbeatS, bpm: grid.bpm, beatsPerBar: 4,
                                      beatInBar: 1, confidence: grid.confidence)],
                key: .init(source: "votes", confidence: key.confidence, camelot: key.camelot, key: spelled?.key,
                           scale: spelled?.scale, votes: votes, changes: nil),
                phrase: .init(source: "foote-novelty", confidence: phrase.confidence,
                              latticePhaseBar: phrase.latticePhaseBar, boundariesBars: boundariesBars),
                sections: sections.map {
                    .init(startBar: $0.startBar, endBar: $0.endBar, label: $0.label, energy: $0.energy)
                },
                mixIn: .init(startBar: mixIn.startBar, endBar: mixIn.endBar, vocalFreeBars: mixIn.vocalFreeBars),
                mixOut: .init(startBar: mixOut.startBar, endBar: mixOut.endBar, vocalFreeBars: mixOut.vocalFreeBars),
                ends: .init(firstSoundS: firstSoundS, lastSoundS: lastSoundS, fadeOut: fadeOut,
                            fadeStartBar: fadeStartBar, steadyInBar: line(lt?.steadyInBar),
                            steadyOutBar: line(lt?.steadyOutBar)),
                loudness: .init(source: "pyloudnorm", confidence: nil, integratedLufs: loudness.integratedLufs,
                                lra: loudness.lra, truePeakDb: loudness.truePeakDb),
                vocal: .init(source: "discogs-effnet", confidence: nil, mean: vocal.meanProb, heavy: vocal.vocalHeavy),
                onsetPattern16: onsetPattern16,
                flags: flags,
                bars: BarSeries([BarSeries.lufs: perBar.lufsSt, BarSeries.lowDb: perBar.lowDb,
                                 BarSeries.highDb: perBar.highDb, BarSeries.onsetDensity: perBar.onsetDensity,
                                 BarSeries.vocal: perBar.vocalProb]))
        }
    }
}
