import Foundation

/// Whether a song's title and artist name it (research AA, 3.3 and 3.13): the one rule every reader of a crate file
/// uses, so Desk's "Needs a name" list and the booth's "No name yet" agree on every song. It lives here, beside the
/// crate file's model, because the iPad app reads crate files without the builder; `LocalNames` in DeckieBuild uses
/// the same rule.
public enum SongName {
    /// A title that names the song: not empty, not only a number, and not a placeholder such as "Track 01",
    /// "Audio Track 3", "Untitled" or "Unknown".
    public static func isUsableTitle(_ s: String?) -> Bool {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return false }
        let words = t.lowercased().filter { !$0.isNumber }.trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
        if words.isEmpty { return false }
        let placeholders: Set<String> = ["track", "audio track", "audiotrack", "piste", "pista", "titel", "title", "untitled",
                                         "unknown", "unknown title", "no title", "new recording", "recording", "song"]
        return !placeholders.contains(words)
    }

    /// An artist that names someone: not empty, and not "Unknown Artist", "Various Artists" or the like.
    public static func isUsableArtist(_ s: String?) -> Bool {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return false }
        let bad: Set<String> = ["unknown", "unknown artist", "various", "various artists", "va", "v.a.", "v/a", "artist",
                                "<unknown>", "[unknown]", "none", "no artist"]
        return !bad.contains(t.lowercased())
    }
}

extension CrateTrack {
    /// Whether the entry has a title that names it (`SongName.isUsableTitle`). A song without one is still found
    /// and shown like any other; the booth leads with its place and says "No name yet".
    public var hasUsableTitle: Bool { SongName.isUsableTitle(ident.title) }
}
