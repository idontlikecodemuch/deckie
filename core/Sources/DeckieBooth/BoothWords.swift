import Foundation

/// The words Booth says about what it hears and what it picks, in one table (D28, D36, D42): the iPad app's `Words` reads
/// them from here, and Desk sends them to its pages with its own (`DeskWords.table`), so both products say the same
/// things. `{name}` is filled in by `t`, numbers already written out. The values are the iPad's words as they were, letter
/// for letter (the copy audit changes this table only). Sentence case, "songs" not "tracks", no "AI".
///
/// Not here: the codes a key verdict is made of ("same key", "neighbour", "relative", "boost", "clash", "key not read"),
/// which `BoothJoin` returns and the iPad compares; they show through the iPad's `Words.verdictPhrase`.
public enum BoothWords {
    public static let table: [String: String] = [
        // A pick's join (`BoothJoin.pitchText`): the incoming deck's pitch fader.
        "pick.pitch.cutIn": "cut in, no beat-match",
        "pick.pitch.caps": "PITCH {pitch}%",
        "pick.pitch.multiple": " · x{m}",
        "pick.pitch.na": "PITCH n/a",
        "pick.pitch.aside": " · {pitch}%",
        // The key verdicts that are words, not codes (a home-note pair that fits; a key Deckie was not sure of).
        "pick.verdict.homeNote": "fits on the home note, major or minor open",
        "pick.verdict.keyNotSure": "key not sure",
        // The two songs' keys: "8A → 9A", "Home note A → 9A".
        "pick.keys": "{a} → {b}",
        // A song's key where it shows (D33, D36): its home note in place of the code; "not sure"; "?" when never read.
        "song.homeNote": "Home note {note}",
        "song.keyNotSure": "not sure",
        "song.keyUnknown": "?",
        // A pitch's sign, then the number to one place: "+3.2", "−1.0", "±0.0".
        "pick.sign.plus": "+",
        "pick.sign.minus": "−",
        "pick.sign.none": "±",
        "pick.signed": "{sign}{value}",
        // A pick's BPM line: "128 BPM · pitch +3.2%", "120→126 BPM", " (x1/2)" after a half- or double-time join.
        "pick.bpm": "{bpm} BPM",
        "pick.bpmChange": "{from}→{to} BPM",
        "pick.pitchAfterBPM": "{bpm} · pitch {pitch}%",
        "pick.tempoMultiple": " (x{m})",
        // A pick's move line: "blend", "echo out · keys may clash", "no beat-match · brake".
        "pick.noBeatMatch": "no beat-match",
        "pick.keyClash": "keys may clash",
        "pick.brake": "brake",
        "pick.movesJoin": " / ",
        "pick.moveLineJoin": " · ",
        "pick.moveHomeNote": "home note",
        // What is unexpected about a pick, as its corner chip says it.
        "pick.tag.halfTime": "half time",
        "pick.tag.doubleTime": "double time",
        "pick.tag.tempoMultiple": "x{m} tempo",
        "pick.tag.tempoChange": "tempo change",
        "pick.tag.halloween": "Halloween",
        "pick.tag.to": "to {source}",
        "pick.tag.inCrate": "in the crate",
        "pick.tag.in": "in {folder}",
        "pick.tag.deepCut": "deep cut",
        // The moves, by the crate file's code.
        "pick.move.bass_swap_8": "short blend",
        "pick.move.bass_swap_16": "blend",
        "pick.move.bass_swap_32": "long blend",
        "pick.move.ramped_blend": "ramp blend",
        "pick.move.filter_sweep": "filter out",
        "pick.move.quick_blend_echo": "echo out",
        "pick.move.brake_cut": "brake/cut",
        // The disc filter as a sentence says it ("CD1+CD2", "Singalongs+all"), and a disc's name cut short.
        "pick.filterAll": "all",
        "pick.filterJoin": "+",
        "pick.cutShort": "…",
        // How the pitch shown was found, from Deckie's listener.
        "heard.speedFromDeckie": "Deckie's reading",
    ]

    /// The words for `key` with each `{name}` filled in.
    public static func t(_ key: String, _ values: [String: String] = [:]) -> String {
        var s = table[key] ?? key
        for (k, v) in values { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }

    /// The moves' words by the crate file's code (`bass_swap_16` -> "blend").
    public static let moveLabels: [String: String] = {
        var m: [String: String] = [:]
        for (k, v) in table where k.hasPrefix("pick.move.") { m[String(k.dropFirst("pick.move.".count))] = v }
        return m
    }()

    /// "+3.2", "−1.0", "±0.0": the sign, then the number to one place.
    public static func signed1(_ p: Double) -> String {
        t("pick.signed", ["sign": t(p > 0.05 ? "pick.sign.plus" : p < -0.05 ? "pick.sign.minus" : "pick.sign.none"),
                          "value": String(format: "%.1f", abs(p))])
    }
    /// "128 BPM".
    public static func bpm(_ value: Double) -> String { t("pick.bpm", ["bpm": String(format: "%.0f", value)]) }
    /// "120→126 BPM".
    public static func bpmChange(_ from: Double, _ to: Double) -> String {
        t("pick.bpmChange", ["from": String(format: "%.0f", from), "to": String(format: "%.0f", to)])
    }
}
