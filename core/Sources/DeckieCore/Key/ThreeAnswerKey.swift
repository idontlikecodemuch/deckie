import Foundation

// The key reader that ships on computers without Apple's framework (D33; research X2, section 5.1): two readings of
// the song that share no arithmetic after the audio, and three possible answers. Nothing is trained and nothing is
// fitted; reference mixer/keytrial/kt_three.py, whose answers on the three outside sets are in
// mixer/keytrial/three_answer_expected.tsv.
//
//   row A    the HPCP of `HPCPKey`, frame by frame, with the overtones' share taken off each frame (research R,
//            "Overtones taken out of the chroma", Part A): each pitch class loses 0.6^2 of the class a fifth below it
//            (the third harmonic of that note lands here) and 0.6^4 of the class a major third below it (the fifth
//            harmonic), from the frame's own values, floored at zero; the frames summed
//   row B    the note-transcription profile (`NoteChroma`)
//   scores   for each row, the mean over the edma, bgate and braw profiles of the Pearson correlation with each of
//            the 24 keys (`HPCPKey.decide`'s `meanCorrelations`)
//   answer   the home note is row B's best key's. A KEY when row A's best key has the same home note and the two rows
//            name the same mode on it (minor when the minor key on that home note scores higher than the major):
//            that home note and mode. The HOME NOTE WITH THE MODE OPEN when the home notes agree and the modes do
//            not. NOT SURE otherwise, and for audio shorter than one frame or with no pitch in it.
//
// On music it had not seen (research X2, section 4.4) it gives a key on 70 to 76 percent of dance clips, right on 65
// to 85 percent of those by set; the home note alone on 5 to 12 percent; not sure on about 20.

/// The three-answer key reader (see above).
public enum ThreeAnswerKey {
    /// What the reader says about a song.
    public enum Answer: Sendable, Equatable {
        /// The key: its home note (0 = C) and mode.
        case key(pitchClass: Int, minor: Bool)
        /// The home note, with the mode left open.
        case home(pitchClass: Int)
        case notSure

        /// "key", "home" or "none", as the reference's table spells them.
        public var name: String {
            switch self {
            case .key: return "key"
            case .home: return "home"
            case .notSure: return "none"
            }
        }
        /// The home note, when there is one.
        public var pitchClass: Int? {
            switch self {
            case .key(let pc, _), .home(let pc): return pc
            case .notSure: return nil
            }
        }
        /// The Camelot code of a key answer.
        public var camelot: String? {
            if case .key(let pc, let minor) = self { return Camelot.code(pitchClass: pc, major: !minor) }
            return nil
        }
    }

    /// The share of a note's energy its third and fifth harmonics put on the classes a fifth and a major third above
    /// it: the HPCP's own harmonic slope, 0.6 per harmonic (Gomez 2006).
    public static let thirdHarmonicShare = pow(HPCPKey.harmonicDecay, 2), fifthHarmonicShare = pow(HPCPKey.harmonicDecay, 4)

    public struct Result: Sendable, Equatable {
        public var answer: Answer
        /// Each row's own best key as a Camelot code (nil when the row has no pitch in it).
        public var camelotA: String?
        public var camelotB: String?
        /// Row B's home note with row A's mode on it: the reader's single best guess, whatever the answer (nil when
        /// either row has no pitch in it). Not for showing unless the answer is a key, when it is that key.
        public var guess: String?
        /// The 24 scores of each row (major C..B, then minor C..B), and the profiles they came from.
        public var scoresA: [Double]
        public var scoresB: [Double]
        public var pcpA: [Double]
        public var pcpB: [Double]
        public var tuning: Double
        /// The plain HPCP reading of the same frames (research R's row 3f), which the engine keeps beside it.
        public var hpcp: HPCPKey.Result
    }

    /// One frame's HPCP with the overtones' share taken off.
    static func discounted(_ p: [Double]) -> [Double] {
        (0..<12).map { k in
            max(0, p[k] - (0 + thirdHarmonicShare * p[(k + 5) % 12] + fifthHarmonicShare * p[(k + 8) % 12]))
        }
    }

    /// The answer from the two rows' scores.
    public static func decide(scoresA a: [Double], scoresB b: [Double]) -> Answer {
        guard let ka = best(a), let kb = best(b) else { return .notSure }
        let home = kb % 12
        guard ka % 12 == home else { return .notSure }
        let minorA = a[12 + home] > a[home], minorB = b[12 + home] > b[home]
        return minorA == minorB ? .key(pitchClass: home, minor: minorA) : .home(pitchClass: home)
    }

    /// The first largest score's index, or nil when every score is zero (no pitch).
    static func best(_ v: [Double]) -> Int? {
        guard v.contains(where: { $0 != 0 }) else { return nil }
        var top = 0
        for i in v.indices where v[i] > v[top] { top = i }
        return top
    }

    /// The reader on mono audio at 44.1 kHz (any other rate throws `HPCPKey.EstimateError.resampleFirst`).
    public static func read(_ mono: [Float], sampleRate rate: Int) throws -> Result {
        guard rate == HPCPKey.sampleRate else { throw HPCPKey.EstimateError.resampleFirst(sampleRate: rate) }
        var plain = [Double](repeating: 0, count: 12), a = [Double](repeating: 0, count: 12)
        let n = HPCPKey.frameCount(samples: mono.count)
        HPCPKey.forEachFrame(mono) { _, peaks in
            var frame = [Double](repeating: 0, count: 12)
            HPCPKey.addHPCP(peaks, to: &frame)
            let d = discounted(frame)
            for c in 0..<12 { plain[c] += frame[c]; a[c] += d[c] }
        }
        let pcp = n == 0 ? plain : plain.map { $0 / Double(n) }
        let hpcp = HPCPKey.Result(pcp: pcp, frames: n, decision: HPCPKey.decide(pcp, table: .literature))
        let b = NoteChroma.transcribe(mono, frames: n)
        let sa = HPCPKey.decide(a, table: .literature).meanCorrelations
        let sb = HPCPKey.decide(b.pcp, table: .literature).meanCorrelations
        let ka = best(sa), kb = best(sb)
        var guess: String? = nil
        if ka != nil, let kb {
            let home = kb % 12
            guess = Camelot.code(pitchClass: home, major: !(sa[12 + home] > sa[home]))
        }
        return Result(answer: decide(scoresA: sa, scoresB: sb), camelotA: ka.map(HPCPKey.camelot(index:)),
                      camelotB: kb.map(HPCPKey.camelot(index:)), guess: guess, scoresA: sa, scoresB: sb, pcpA: a,
                      pcpB: b.pcp, tuning: b.tuning, hpcp: hpcp)
    }
}
