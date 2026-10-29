/// The Camelot wheel: the DJ notation for musical keys where neighbouring numbers mix well.
/// Port of the key tables in mixer/analyze.py (camelot, camelot_neighbour) and mixer/score.py (cshift, key_raw).
public enum Camelot {
    /// Pitch class (0 = C ... 11 = B) for every key spelling the lab accepts.
    public static let pitchClass: [String: Int] = [
        "C": 0, "B#": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "Fb": 4,
        "F": 5, "E#": 5, "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10,
        "Bb": 10, "B": 11, "Cb": 11,
    ]

    /// Camelot code ("8A", "12B") from a key name and "major"/"minor". Nil for an unknown key name.
    public static func code(key: String, scale: String) -> String? {
        guard let pc = pitchClass[key] else { return nil }
        return code(pitchClass: pc, major: scale.lowercased().hasPrefix("maj"))
    }

    /// Camelot code from a pitch class (0 = C ... 11 = B) and the mode: the lab's `CAM_MAJ[pc]` or `CAM_MIN[pc]`
    /// (mixer/key_light.py). Each semitone up is 7 steps round the wheel; C major is 8B and C minor 5A.
    public static func code(pitchClass pc: Int, major: Bool) -> String {
        let n = Py.mod(pc * 7 + (major ? 8 : 5), 12)
        return "\(n == 0 ? 12 : n)\(major ? "B" : "A")"
    }

    /// The tonic's pitch class and the mode of a Camelot code, the inverse of `code(pitchClass:major:)` (the lab's
    /// `(CAM_MAJ + CAM_MIN).index(cam) % 12` and `cam.endswith("B")`). Nil for anything but 1A ... 12A, 1B ... 12B.
    public static func tonic(_ code: String) -> (pitchClass: Int, major: Bool)? {
        let (n, letter) = parse(code)
        guard (1...12).contains(n), letter == "A" || letter == "B", code == "\(n)\(letter)" else { return nil }
        let major = letter == "B"
        return (Py.mod((n - (major ? 8 : 5)) * 7, 12), major)
    }

    /// Splits "11A" into (11, "A"). Codes are kept as strings, as the lab does.
    public static func parse(_ code: String) -> (number: Int, letter: Character) {
        (Int(code.dropLast()) ?? 0, code.last ?? "?")
    }

    /// True when `b` is the same code as `a`, one step either way on the same letter, or the relative key.
    public static func isNeighbour(_ a: String, _ b: String) -> Bool {
        let (na, la) = parse(a)
        let (nb, lb) = parse(b)
        if la == lb {
            let d = Py.mod(nb - na, 12)
            return d == 0 || d == 1 || d == 11
        }
        return na == nb
    }

    /// The code a track lands on after a pitch shift of `semitones` (each semitone moves 7 steps round the wheel).
    public static func shifted(_ code: String, semitones: Int) -> String {
        let (n, l) = parse(code)
        let m = Py.mod(n - 1 + 7 * semitones, 12) + 1
        return "\(m)\(l)"
    }

    /// Key compatibility from the research B.9 table, with the lab's wording of the reason.
    public static func rawCompatibility(_ a: String, _ b: String) -> (score: Double, why: String) {
        let (na, la) = parse(a)
        let (nb, lb) = parse(b)
        if a == b { return (1.0, "same key") }
        if la == lb {
            switch Py.mod(nb - na, 12) {
            case 1: return (0.90, "+1 (fifth)")
            case 11: return (0.90, "-1 (fifth)")
            case 2: return (0.65, "+2 energy boost")
            case 7: return (0.50, "+1 semitone")
            case 5: return (0.50, "-1 semitone")
            case 10: return (0.45, "-2")
            default: return (0.15, "clash")
            }
        }
        if na == nb { return (0.85, "relative major/minor") }
        return (0.15, "clash")
    }
}
