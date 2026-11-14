import Foundation
import DeckieCrate

/// Every word the PC program says, in one list (D28: each app keeps its words in one place, so the copy audit changes
/// one file). Plain, short, sentence case; "songs", never "tracks" (docs/product/voice.md).
public enum PCWords {
    public static let title = "Deckie for PC, first test"
    public static func hello(version: String) -> String {
        "\(title) (version \(version))\nMakes a crate file from a folder of music. Your music stays on this PC."
    }

    public static let askForFolder = """
        Which folder is your music in?
        Drag the folder into this window, then press Enter.
        (Or type its path. To stop, close this window.)
        """
    public static let prompt = "> "
    public static func notThere(_ path: String) -> String { "There is no folder at \(path). Check the path and try again." }
    public static func isAFile(_ name: String) -> String {
        "\(name) is a file, not a folder. Drag in the folder your music is in."
    }
    public static let nothingTyped = "Nothing was typed."

    public static func reading(_ name: String) -> String { "Reading the folder \"\(name)\"..." }
    public static func noSongs(_ name: String) -> String {
        "No music files were found in \"\(name)\". Deckie looks for mp3, flac, wav, aiff, m4a, wma, ogg and opus files."
    }
    public static func found(songs: Int, toRead: Int) -> String {
        let s = "Found \(count(songs, "music file"))."
        if toRead == 0 { return s + " Nothing has changed since last time." }
        if toRead == songs { return s + " Reading them now. You can keep using the PC; it will be busy." }
        return s + " \(toRead) \(toRead == 1 ? "is" : "are") new or changed since last time; reading \(toRead == 1 ? "it" : "them") now."
    }
    public static func progress(done: Int, of total: Int, name: String, left: Double?) -> String {
        let width = String(total).count
        let n = String(repeating: " ", count: max(0, width - String(done).count)) + "\(done)"
        return "  \(n) of \(total)  \(timeLeft(left))  \(name)"
    }
    public static func progressNotRead(done: Int, of total: Int, name: String, left: Double?, why: String) -> String {
        progress(done: done, of: total, name: name, left: left) + "\n" + String(repeating: " ", count: 6) + "not added: \(why)"
    }
    /// "about 12 minutes left", padded so the names line up; blank until a first song has been read.
    public static func timeLeft(_ seconds: Double?) -> String {
        guard let seconds else { return String(repeating: " ", count: 22) }
        let text: String
        if seconds < 50 { text = "under a minute left" }
        else if seconds < 3600 * 1.5 { let m = max(1, Int((seconds / 60).rounded())); text = "about \(m) minute\(m == 1 ? "" : "s") left" }
        else { text = "about \(String(format: "%.1f", seconds / 3600)) hours left" }
        return text.padding(toLength: 22, withPad: " ", startingAt: 0)
    }
    public static let writing = "Writing the crate file..."

    public static func done(songs: Int) -> String { "Done. \(count(songs, "song")) \(songs == 1 ? "is" : "are") in the crate file." }
    public static func notAdded(_ n: Int) -> String { "\(count(n, "file")) could not be added:" }
    public static func notAddedLine(_ n: Int, _ why: String, types: String) -> String { "  \(n)  \(why) (\(types))" }
    public static func copies(_ n: Int) -> String {
        "\(count(n, "file")) \(n == 1 ? "is an exact copy" : "are exact copies") of a song already in, in the same folder, and \(n == 1 ? "was" : "were") counted once."
    }
    public static func damagedSpots(_ n: Int) -> String {
        "\(count(n, "song")) in the crate file \(n == 1 ? "has" : "have") a damaged spot. \(n == 1 ? "It still plays" : "They still play"); the log says where."
    }
    public static func startUncertain(_ n: Int) -> String {
        "\(count(n, "song")) in the crate file \(n == 1 ? "comes" : "come") from \(n == 1 ? "a file that does" : "files that do") not say exactly where the music starts. "
            + "\(n == 1 ? "Its" : "Their") beats may sit a touch late (up to 0.05 seconds); the log lists \(n == 1 ? "it" : "them")."
    }
    /// Deckie's own key reader's three answers over the crate file's songs (D33, D36). New words, placeholders.
    public static func keys(read: Int, homeNote: Int, notSure: Int) -> String {
        var parts = ["Key: \(count(read, "song")) with a key"]
        if homeNote > 0 { parts.append("\(homeNote) with a home note in place of a key") }
        if notSure > 0 { parts.append("\(notSure) where Deckie is not sure and shows none") }
        return parts.joined(separator: ", ") + "."
    }
    public static func crateFileIs(_ path: String) -> String { "Your crate file:\n  \(path)" }
    public static func logIs(_ path: String) -> String { "A log of this run, to send if something looks wrong:\n  \(path)" }
    public static let notYet = "Not in a crate file made on a PC yet: song recognition, and the key unless your files carry one."
    public static func took(_ seconds: Double) -> String {
        let m = Int((seconds / 60).rounded())
        return seconds < 90 ? "That took \(Int(seconds.rounded())) seconds." : "That took \(m) minutes."
    }
    public static let pressEnter = "Press Enter to close this window."

    public static func wentWrong(_ what: String) -> String { "Something went wrong, and no crate file was written:\n  \(what)" }
    public static func sendLog(_ path: String) -> String { "Please send this file to the person who gave you Deckie:\n  \(path)" }
    public static func partsMissing(_ what: String) -> String {
        "A part of Deckie is missing: \(what).\nUnzip the whole Deckie folder again and run it from there, not from inside the zip."
    }
    public static func inTheWay(_ name: String) -> String {
        "There is already something called \(name) next to your music folder that is not a crate file Deckie can read. "
            + "Move it somewhere else and try again."
    }
    public static func writtenElsewhere(_ folder: String) -> String {
        "Deckie cannot write next to your music folder, so the crate file is in \(folder) instead."
    }
    public static let interrupted = "Stopped. The songs read so far are kept; run it again to carry on."

    /// Why a file was not added, in plain words, by the import log's reason and the file's type.
    public static func why(reason: String, ext: String) -> String {
        typealias R = CrateManifest.ImportLog.Reason
        switch reason {
        case R.unsupported:
            switch ext {
            case "m4a", "mp4", "aac": return "Windows on this PC could not read these AAC or Apple Lossless files (.\(ext)); the log says why"
            case "wma": return "Windows Media files (.wma) cannot be read by this version yet"
            case "ogg", "opus": return "Ogg and Opus files (.\(ext)) cannot be read by this version yet"
            default: return "this kind of file cannot be read by this version yet"
            }
        case R.protected: return "copy-protected (an old iTunes Store purchase or an Apple Music download); only Apple's own apps can play it"
        case R.damaged: return "the file is damaged"
        case R.decodeError: return "the file could not be opened"
        case R.analysisError: return "no steady beat was found, or it is too short to be a song"
        case R.duplicate: return "an exact copy of another file in the same folder"
        default: return "left out"
        }
    }

    public static func count(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}
