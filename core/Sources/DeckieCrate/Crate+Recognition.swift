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

        /// The booth's index for these songs, kept at `url`: opened in place when the file there was made from these
        /// songs with `pairing`, else built, written there and opened (`RecognitionIndex.cached`).
        public func index(cachedAt url: URL, pairing: PairingConfig = .booth) throws -> RecognitionIndex {
            try RecognitionIndex.cached(at: url, stamp: stamp, sameRecording: sameRecording, pairing: pairing) { songs }
        }
    }

    /// What an app keeps of a crate until its index is ready: each fingerprinted song's id, its fingerprint as kept
    /// (the compact bytes, not the points) and its same-recording key. Lighter than the crate, so an app that reads
    /// a crate on one thread can build or open the index on another without holding the whole crate.
    public struct Fingerprints: Sendable {
        public var items: [(id: String, fingerprint: CrateTrack.Fingerprint, cutKey: String?)]
        public var count: Int { items.count }
        /// The songs as the index takes them: each fingerprint read into its points (one that cannot be read is left
        /// out), the keys (an empty key is none) and the stamp.
        public func songs() -> RecognitionSongs {
            var songs: [(id: String, landmarks: Landmarks)] = [], keys: [String?] = []
            for item in items {
                guard let landmarks = item.fingerprint.landmarks else { continue }
                songs.append((item.id, landmarks))
                keys.append(item.cutKey.flatMap { $0.isEmpty ? nil : $0 })
            }
            let stamp = RecognitionIndex.stamp(of: songs.map { ($0.id, $0.landmarks.count, $0.landmarks.frameCount) })
            return RecognitionSongs(songs: songs, sameRecording: keys, stamp: stamp)
        }
    }

    /// The crate's fingerprints, in the crate's order, with each song's key.
    public func fingerprints() -> Fingerprints {
        Fingerprints(items: tracks.compactMap { t in t.fingerprint.map { (t.id, $0, t.ident.cutKey) } })
    }

    /// The songs with fingerprints, their same-recording keys and the stamp.
    public func recognitionSongs() -> RecognitionSongs { fingerprints().songs() }

    /// The booth's index for this crate, kept at `url`: opened in place when the file there was made from these
    /// songs, else built from the fingerprints, written there and opened (`RecognitionIndex.cached`). `pairing` is
    /// the index's setting: `.booth`, or `.boothSmall` for half the size.
    public func recognitionIndex(cachedAt url: URL, pairing: PairingConfig = .booth) throws -> RecognitionIndex {
        try recognitionSongs().index(cachedAt: url, pairing: pairing)
    }
}
