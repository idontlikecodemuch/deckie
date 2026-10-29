import Foundation

/// A tagger's class scores, patch by patch: `patches` rows of `names.count` values each (row after row), every value a
/// sigmoid output between 0 and 1, and the name of each column as the model's class list spells it (AudioSet's
/// display names, for YAMNet and for PANNs). A model may leave a column's name empty when Deckie does not name that
/// class: YAMNet names only the classes its rule and the readings use, since its full class list is AudioSet's
/// ontology, which is not copied here.
public struct ClassScoreMatrix: Sendable, Equatable {
    public let patches: Int
    public let names: [String]
    /// `patches` x `names.count`, patch by patch.
    public let scores: [Float]

    public init(patches: Int, names: [String], scores: [Float]) {
        precondition(scores.count == patches * names.count, "\(scores.count) scores for \(patches) x \(names.count)")
        self.patches = patches
        self.names = names
        self.scores = scores
    }

    /// Patch `k`'s score for column `c`.
    @inline(__always)
    public func score(_ k: Int, _ c: Int) -> Float { scores[k * names.count + c] }
}

/// Four readings of the same per-patch class scores, side by side, for the yardstick to compare with the lab's vocal
/// probability. Nothing is fitted: each is a fixed formula over classes named in advance, and a class the model's list
/// does not have is left out and reported (`Classes`). They are research series: the lab JSON writes them in
/// `deckie.vocal` (`readings`, `readings_classes`, `readings_note`) and nothing else reads them.
///
/// Per patch k, with p(c) the patch's score for class c:
/// - `max11`: the largest p(c) over `maxClassNames` (the vocal rule's eleven singing classes); for YAMNet the patch's
///   vocal score exactly, so its bars are `per_bar.vocal_prob`'s.
/// - `voice_sum`: the sum of p(c) over `voiceClassNames`.
/// - `voice_logit_sum`: the sum over the same classes of ln(p / (1 - p)), p first kept within [1e-7, 1 - 1e-7]: the
///   network's output before its sigmoid, recovered.
/// - `voice_vs_music`: `voice_sum` / (`voice_sum` + the sum of p(c) over `musicClassNames`), 0 when both sums are 0.
///
/// `averaged(hop:centreOffset:barTimes:)` turns each per-patch series into bars exactly as `PatchBars.average` turns
/// the vocal score into bars (`voice_vs_music` is a ratio per patch, then averaged).
public struct VocalReadings: Sendable, Equatable {
    /// The readings' names, in the order the record writes them.
    public static let names = ["max11", "voice_sum", "voice_logit_sum", "voice_vs_music"]

    /// The vocal rule's eleven singing classes (YAMNet's `vocalClasses`), as AudioSet spells them.
    public static let maxClassNames = ["Singing", "Choir", "Yodeling", "Chant", "Mantra", "Child singing",
                                       "Synthetic singing", "Rapping", "Humming", "Vocal music", "A capella"]
    /// Every class a voice can score as: the eleven, speech, and male and female singing (which YAMNet's 521 do not
    /// have; AudioSet's 527, PANNs' list, do).
    public static let voiceClassNames = ["Singing", "Choir", "Rapping", "Vocal music", "Speech", "Male singing",
                                         "Female singing", "Child singing", "Chant", "Yodeling", "Humming", "Mantra",
                                         "Synthetic singing", "A capella"]
    /// The two classes a full mix scores as: music itself and the parent of every instrument. Considered and left out:
    /// the instrument families below Musical instrument (Plucked string instrument, Percussion, Keyboard (musical),
    /// Orchestra and the rest: their parent stands for them), Song (a song has a voice, so it would count against
    /// one), and the genres (pop, hip hop, electronic, dance and the rest: vocal music is one of them, and a genre is a
    /// style, not a sign of instruments rather than a voice). AudioSet's grouping parents (Music genre, Musical
    /// concepts, Music role, Music mood) are not in YAMNet's list.
    public static let musicClassNames = ["Music", "Musical instrument"]
    /// How close to 0 and 1 a score is kept before its logit.
    public static let logitClamp = 1e-7

    /// One sentence per reading, in plain words, as the record's `readings_note` gives them.
    public static let notes: [(name: String, note: String)] = [
        ("max11", "The default reading, per_bar.vocal_prob's own series written to 5 decimals instead of 3: the "
            + "largest of the eleven singing-class scores in each patch, kept as the baseline, which sits near zero on "
            + "a full mix because the model hears the whole patch as music."),
        ("voice_sum", "The sum of the scores of every voice class the model has (singing, choir, rapping, vocal "
            + "music, speech and the rest listed in readings_classes), which adds up the small amounts several "
            + "classes each give a voice the model only half hears, so it may rise further off the floor than any one "
            + "class does."),
        ("voice_logit_sum", "The same classes' scores turned back into the network's raw outputs before its sigmoid "
            + "(the logit, ln(p / (1 - p)), with p kept within 1e-7 of 0 and 1) and summed, which pulls apart the "
            + "scores squeezed against zero (0.001 and 0.0001 become about -6.9 and -9.2), so differences at the "
            + "floor show."),
        ("voice_vs_music", "The voice sum divided by itself plus the Music and Musical instrument scores, patch by "
            + "patch and then averaged per bar: the share of the model's belief that goes to a voice rather than to "
            + "music, so a track the model calls all music can still show where the voice's share rises."),
    ]

    /// A class a reading uses: its name and its column in the model's class list.
    public struct Class: Sendable, Equatable {
        public var name: String
        public var index: Int
        public init(_ name: String, _ index: Int) { self.name = name; self.index = index }
    }

    /// The classes asked for, resolved against one model's class list: those it has, in the order asked, and the
    /// names it does not have.
    public struct Classes: Sendable, Equatable {
        public var max: [Class]
        public var voice: [Class]
        public var music: [Class]
        public var missingMax: [String]
        public var missingVoice: [String]
        public var missingMusic: [String]
    }

    public var classes: Classes
    /// One value per patch (from `read`) or per bar (from `averaged`), each.
    public var max11: [Double]
    public var voiceSum: [Double]
    public var voiceLogitSum: [Double]
    public var voiceVsMusic: [Double]

    /// The four series by name, in `names`' order.
    public var series: [(name: String, values: [Double])] {
        [("max11", max11), ("voice_sum", voiceSum), ("voice_logit_sum", voiceLogitSum), ("voice_vs_music", voiceVsMusic)]
    }

    /// The names of `wanted` found in `names` (exact spelling; the first column of that name), in `wanted`'s order,
    /// and those not found.
    public static func resolve(_ wanted: [String], in names: [String]) -> (found: [Class], missing: [String]) {
        var column: [String: Int] = [:]
        for (i, n) in names.enumerated() where !n.isEmpty && column[n] == nil { column[n] = i }
        var found: [Class] = [], missing: [String] = []
        for w in wanted {
            if let i = column[w] { found.append(Class(w, i)) } else { missing.append(w) }
        }
        return (found, missing)
    }

    /// ln(p / (1 - p)) with p kept within [`logitClamp`, 1 - `logitClamp`]. Above one half the clamp is applied to
    /// 1 - p, which is exact there, rather than to p, whose distance from 1 would carry the rounding of 1 - 1e-7: so
    /// a score of 1 gives minus what a score of 0 gives, to the last digits.
    @inline(__always)
    public static func logit(_ p: Double) -> Double {
        if p <= 0.5 {
            let q = Swift.max(p, logitClamp)
            return log(q / (1 - q))
        }
        let r = Swift.max(1 - p, logitClamp)
        return log((1 - r) / r)
    }

    /// The four readings of `m`, patch by patch, over the classes named (by default the lists above).
    public static func read(_ m: ClassScoreMatrix, maxNames: [String] = maxClassNames,
                            voiceNames: [String] = voiceClassNames, musicNames: [String] = musicClassNames) -> VocalReadings {
        let mx = resolve(maxNames, in: m.names), vo = resolve(voiceNames, in: m.names), mu = resolve(musicNames, in: m.names)
        let n = m.patches
        var max11 = [Double](repeating: 0, count: n), voiceSum = max11, logitSum = max11, share = max11
        for k in 0..<n {
            var top = 0.0
            for c in mx.found { top = Swift.max(top, Double(m.score(k, c.index))) }
            var sum = 0.0, logits = 0.0
            for c in vo.found {
                let p = Double(m.score(k, c.index))
                sum += p
                logits += logit(p)
            }
            var music = 0.0
            for c in mu.found { music += Double(m.score(k, c.index)) }
            max11[k] = top
            voiceSum[k] = sum
            logitSum[k] = logits
            share[k] = sum + music > 0 ? sum / (sum + music) : 0
        }
        return VocalReadings(classes: Classes(max: mx.found, voice: vo.found, music: mu.found, missingMax: mx.missing,
                                              missingVoice: vo.missing, missingMusic: mu.missing),
                             max11: max11, voiceSum: voiceSum, voiceLogitSum: logitSum, voiceVsMusic: share)
    }

    /// The per-patch readings averaged into the bars whose lines are `barTimes`, as `PatchBars.average` does
    /// (patch k centred at `centreOffset + k hop` seconds).
    public func averaged(hop: Double, centreOffset: Double, barTimes: [Double]) -> VocalReadings {
        func bars(_ v: [Double]) -> [Double] { PatchBars.average(v, hop: hop, centreOffset: centreOffset, barTimes: barTimes) }
        return VocalReadings(classes: classes, max11: bars(max11), voiceSum: bars(voiceSum),
                             voiceLogitSum: bars(voiceLogitSum), voiceVsMusic: bars(voiceVsMusic))
    }
}
