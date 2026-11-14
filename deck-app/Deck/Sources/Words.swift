import Foundation
import DeckieCrate

/// The booth's words for opening crate files and for songs with no name, in one list by name (D28: placeholders until
/// the copy audit, which changes this file). Sentence case, "songs", a crate is the songs and a crate file is the file.
enum Words {
    // MARK: a song with no name (research AA, 3.13)

    /// The quiet line under a song's place when the crate file gives it no name.
    static let noNameYet = "No name yet"
    /// The same, inside a row or a pick ("Friday night / Peak / 07 · no name yet").
    static let noNameYetInRow = "no name yet"
    /// The file a song with no name was read from, shown as a file name so it never looks like a title.
    static func fileLine(_ stem: String) -> String { "file: \(stem)" }

    // MARK: a crate file with no fingerprints

    static let setByHandTitle = "Set the song by hand"
    static let noFingerprints = "The booth cannot name what is playing from this crate file yet: it has no song fingerprints."
    static let setByHandHow = "Tap a song in the Crate tab to set it as playing."
    static let chooseSong = "Choose a song"
    /// The status corner when nothing can be recognised.
    static let notListening = "not listening"

    // MARK: opening a crate file

    static let openCrateFile = "Open crate file"
    static func opened(_ name: String, songs: Int) -> String {
        "\(name) is open: \(songs) song\(songs == 1 ? "" : "s")."
    }
    static func couldNotOpen(_ fileName: String) -> String { "Could not open \(fileName)" }

    /// What went wrong, in plain words, from the reader's problem. The reader's own words follow as a detail.
    static func whyNotOpened(_ error: Error) -> String {
        let said = (error as? CrateError)?.description ?? error.localizedDescription
        if said.contains("cut short") {
            return "This crate file is not complete. It may not have finished copying or downloading. Send it again."
        }
        if said.contains("compressed") {
            return "Another program has changed this crate file, so it cannot be opened. Make it again with Deckie and send that one."
        }
        if said.contains("min_reader") {
            return "This crate file was made by a newer Deckie. Update the booth to open it."
        }
        if said.contains("is not a crate file") || said.hasPrefix("manifest.json: is missing") {
            return "This is not a crate file. A crate file is the .deckiecrate that Deckie makes."
        }
        if said.contains("is not there") || said.contains("could not be read") || error is CocoaError {
            return "This crate file could not be read. If it is in iCloud Drive, check that the iPad is online, then try again."
        }
        return "This crate file is damaged, so it cannot be opened. Make it again with Deckie and send it again."
    }
    /// The reader's own description, for the detail line.
    static func detail(_ error: Error) -> String {
        (error as? CrateError)?.description ?? error.localizedDescription
    }
}
