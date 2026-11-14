import Foundation
import DeckieRecognition

// What the booth's index needs from a crate, in one place (D35): the songs that carry a fingerprint, which of them
// are the same recording (D24), and the mark that says which songs an index file was made from.

extension Crate {
    /// The crate's songs as the booth's index takes them.
    public struct RecognitionSongs: Sendable {
        /// The songs that carry a fingerprint, in the crate's order; a song without one is left out.
        public var songs: [(id: String, landmarks: Landmarks)]
        /// For each of `songs`, the key its copies share (`ident.cut_key`, D24: entries with the same key are one
        /// recording), or nil for a song on its own.
        public var sameRecording: [String?]
        /// `RecognitionIndex.stamp(of:)` for `songs`: an index file with another stamp is made again.
        public var stamp: String
    }

    /// The songs with fingerprints, their same-recording keys and the stamp.
    public func recognitionSongs() -> RecognitionSongs {
        var songs: [(id: String, landmarks: Landmarks)] = [], keys: [String?] = []
        for t in tracks {
            guard let landmarks = t.fingerprint?.landmarks else { continue }
            songs.append((t.id, landmarks))
            keys.append(t.ident.cutKey.flatMap { $0.isEmpty ? nil : $0 })
        }
        let stamp = RecognitionIndex.stamp(of: songs.map { ($0.id, $0.landmarks.count, $0.landmarks.frameCount) })
        return RecognitionSongs(songs: songs, sameRecording: keys, stamp: stamp)
    }

    /// The booth's index for this crate, kept at `url`: opened in place when the file there was made from these
    /// songs, else built from the fingerprints, written there and opened (`RecognitionIndex.cached`).
    public func recognitionIndex(cachedAt url: URL) throws -> RecognitionIndex {
        let r = recognitionSongs()
        return try RecognitionIndex.cached(at: url, stamp: r.stamp, sameRecording: r.sameRecording) { r.songs }
    }
}
