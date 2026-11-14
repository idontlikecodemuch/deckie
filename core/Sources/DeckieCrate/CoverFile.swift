import Foundation

extension CrateReader {
    /// A song's cover (D36) as a reader app shows it: the bytes of `covers/<hash>.jpg` in a crate file's package, or
    /// nil when there is none to show. `hash` is the record's own `file.cover`, checked to be 64 lower-case
    /// hexadecimal characters before it names a file, so nothing else in the package or outside it is reached. Only
    /// an ordinary file is read (a link in a crate file brought in from elsewhere could point anywhere), and its size
    /// is asked first, so a file put there by mistake is never loaded whole; it must be at most
    /// `CrateFormat.coverMaxBytes` and start as a JPEG does. A cover that cannot be read is no cover, never an error:
    /// a missing picture must not stop anything. The picture itself is not decoded here.
    public static func coverData(in package: URL, hash: String) -> Data? {
        guard CrateIDs.isSHA256(hash) else { return nil }
        let file = package.appendingPathComponent(CrateFormat.coverPath(hash))
        guard let facts = try? FileManager.default.attributesOfItem(atPath: file.path),
              facts[.type] as? FileAttributeType == .typeRegular,
              let size = facts[.size] as? NSNumber, size.intValue <= CrateFormat.coverMaxBytes,
              let data = try? Data(contentsOf: file), data.count <= CrateFormat.coverMaxBytes,
              data.starts(with: [0xFF, 0xD8, 0xFF]) else { return nil }
        return data
    }
}
