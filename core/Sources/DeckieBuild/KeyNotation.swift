import Foundation
import DeckieCore

/// A key as a DJ's program or a file's tag writes it, turned into the crate file's form, a Camelot code ("8A").
///
/// The notations read:
/// - **musical names**: a note A to G, a sharp or a flat (`#`, `b`, `♯`, `♭`, or the words "sharp" and "flat"), then
///   the mode: minor as `m`, `min`, `minor` or `-`; major as nothing, `M`, `maj` or `major` (any case but `m`, and
///   with or without a space): `Am`, `F#m`, `Ebmin`, `Db`, `A minor`, `F♯ maj`, `B flat minor`;
/// - **Camelot**: 1 to 12 then `A` (minor) or `B` (major), with or without a leading zero: `8A`, `08A`, `12b`;
/// - **Open Key** (Traktor's, and rekordbox's "1m" option): 1 to 12 then `m` (minor) or `d` (major): `1m` is A minor,
///   8A in Camelot; `1d` is C major, 8B.
/// Anything else gives nil: an empty tag, "Off", a key change written as two keys, a mode Camelot cannot write.
public enum KeyNotation {
    /// The Camelot code of `text`, in any of the notations above; nil for anything else.
    public static func camelot(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first else { return nil }
        if first.isASCII && first.isNumber { return wheel(t) }
        return musical(t)
    }

    /// Only the wheel notations (Camelot and Open Key), not musical names: for a key found inside a title, where "A"
    /// or "Am" could be words of the title itself.
    public static func wheelOnly(_ text: String) -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = t.first, first.isASCII, first.isNumber else { return nil }
        return wheel(t)
    }

    /// Camelot (`8A`) and Open Key (`1m`).
    static func wheel(_ t: String) -> String? {
        let digits = t.prefix { $0.isASCII && $0.isNumber }
        let rest = t.dropFirst(digits.count).trimmingCharacters(in: .whitespaces).lowercased()
        guard digits.count <= 2, let n = Int(digits), (1...12).contains(n) else { return nil }
        switch rest {
        case "a": return "\(n)A"
        case "b": return "\(n)B"
        // Open Key: 1m is A minor (8A), 1d C major (8B); each step is the same step on the wheel.
        case "m": return "\((n + 6) % 12 + 1)A"
        case "d": return "\((n + 6) % 12 + 1)B"
        default: return nil
        }
    }

    /// Musical names.
    static func musical(_ t: String) -> String? {
        var s = Substring(t.replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b"))
        guard let letter = s.first, "ABCDEFGabcdefg".contains(letter) else { return nil }
        s.removeFirst()
        var note = String(letter).uppercased()
        // The accidental: a sign, or the word (with an optional space or hyphen before it).
        let lower = s.lowercased()
        for (word, sign) in [(" sharp", "#"), ("-sharp", "#"), ("sharp", "#"), (" flat", "b"), ("-flat", "b"), ("flat", "b")]
        where lower.hasPrefix(word) {
            note += sign; s = s.dropFirst(word.count); break
        }
        if note.count == 1, let a = s.first, a == "#" || a == "b" {
            // "Bb" is B flat; "Bbm" B flat minor. A "b" before "m" or the end is the flat, never a mode.
            note.append(a); s.removeFirst()
        }
        let mode = s.trimmingCharacters(in: .whitespaces)
        let minor: Bool
        switch mode {
        case "m", "-": minor = true
        // A lone lower-case letter ("a") is minor in some notations and major in others: not read.
        case "": guard letter.isUppercase else { return nil }; minor = false
        case "M": minor = false
        default:
            switch mode.lowercased() {
            case "min", "minor", "moll": minor = true
            case "maj", "major", "dur": minor = false
            default: return nil
            }
        }
        return Camelot.code(key: note, scale: minor ? "minor" : "major")
    }
}
