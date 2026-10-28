import Foundation

/// How a shipped engine names a track (docs/architecture/crate-format.md, "The track record"): the record's `id` is
/// the first 16 hexadecimal characters of the SHA-256 hash of the audio file's bytes, all of them as they are on
/// disk, and `file.sha256` holds the whole hash. Two files with the same audio but different bytes are different
/// files with different ids. Lab records keep the lab's ids and have no `sha256`.
public enum CrateIDs {
    /// Hexadecimal characters of the hash an id keeps: 16, so 64 bits. The chance that any two of 100,000 files
    /// share an id is about one in 3.7 billion.
    public static let idLength = 16

    /// The SHA-256 hash of `bytes`, as 64 lower-case hexadecimal characters.
    public static func sha256(of bytes: Data) -> String {
        var hash = SHA256()
        hash.update(bytes)
        let hex: [Character] = Array("0123456789abcdef")
        return String(hash.finalize().flatMap { [hex[Int($0 >> 4)], hex[Int($0 & 15)]] })
    }

    /// The record id of the file whose bytes are `fileBytes`: the start of its SHA-256 hash.
    public static func id(forFileBytes fileBytes: Data) -> String { id(forSHA256: sha256(of: fileBytes)) }

    /// The record id that goes with a `file.sha256` value.
    public static func id(forSHA256 sha256: String) -> String { String(sha256.prefix(idLength)) }

    /// Whether `s` has the form of a `file.sha256` value: 64 lower-case hexadecimal characters.
    public static func isSHA256(_ s: String) -> Bool {
        s.utf8.count == 64 && s.utf8.allSatisfy { (0x30...0x39).contains($0) || (0x61...0x66).contains($0) }
    }
}
