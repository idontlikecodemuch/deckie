import Foundation
import DeckieCore
import DeckieCrate
import DeckieBuild

/// What a desk worked out for each file, kept once and used by every crate (`Files/` in `DeskHome`), keyed by the
/// file's id (the SHA-256 of its bytes, as an entry's id is): the analysis (the builder's records, through
/// `BuildOptions.sharedRecords`) with the song's fingerprint beside it (D35), the recognition signatures and the print
/// that finds copies. A song read for one crate is not read again for another: only its bytes are hashed, to know
/// which song it is.
public struct FileStore: Sendable {
    public let folder: URL
    public init(folder: URL) { self.folder = folder }

    /// The builder's finished records, shared by every crate's work folder.
    public var records: URL { folder.appendingPathComponent("records", isDirectory: true) }
    var signatures: URL { folder.appendingPathComponent("signatures", isDirectory: true) }
    var prints: URL { folder.appendingPathComponent("prints", isDirectory: true) }

    func signatureFile(_ id: String, _ variant: String) -> URL {
        signatures.appendingPathComponent("\(id)_\(variant).shazamsignature")
    }
    func signatureNote(_ id: String, _ variant: String) -> URL { signatures.appendingPathComponent("\(id)_\(variant).json") }
    func printFile(_ id: String) -> URL { prints.appendingPathComponent("\(id).print") }

    /// Whether the analysis of `id` is kept.
    public func hasRecord(_ id: String) -> Bool {
        FileManager.default.fileExists(atPath: records.appendingPathComponent("\(id).json").path)
    }

    // MARK: fingerprints

    /// The song's fingerprint, by which a booth names it from its sound (D35; the crate file's `print` and
    /// `prints/<id>.dkl`), or nil. The builder makes it with the analysis, from the same decoded audio, and keeps it
    /// beside the record (`records/<id>.dkl`), so a file is fingerprinted once however many crates it is in. Not the
    /// print below, which finds copies of one recording.
    public func fingerprint(_ id: String) -> CrateTrack.Fingerprint? { WorkRecords.fingerprint(id, in: records) }

    /// Keeps a fingerprint with the file's analysis; false, and nothing kept, when the file has no analysis yet.
    @discardableResult
    public func saveFingerprint(_ f: CrateTrack.Fingerprint, id: String) throws -> Bool {
        try WorkRecords.keep(f, id: id, in: records)
    }

    // MARK: signatures

    /// A kept signature and who made it when.
    public func signature(_ id: String, variant: String = "o") -> (data: Data, made: CrateTrack.Signature)? {
        guard let data = try? Data(contentsOf: signatureFile(id, variant)), !data.isEmpty,
              let made = JSONFile.read(CrateTrack.Signature.self, from: signatureNote(id, variant)) else { return nil }
        return (data, made)
    }

    /// Keeps a signature (the data first, then the note, so a note always has its data).
    public func saveSignature(_ data: Data, made: CrateTrack.Signature, id: String, variant: String = "o") throws {
        try DeckieFiles.write(data, to: signatureFile(id, variant))
        try JSONFile.write(made, to: signatureNote(id, variant))
    }

    // MARK: prints

    static let printMagic: [UInt8] = Array("DKP1".utf8)

    /// A kept print, or nil.
    public func print(_ id: String) -> RecordingPrint? {
        guard let data = try? Data(contentsOf: printFile(id)) else { return nil }
        return Self.decodePrint(data)
    }

    public func savePrint(_ p: RecordingPrint, id: String) throws {
        try DeckieFiles.write(Self.encodePrint(p), to: printFile(id))
    }

    /// "DKP1", the word count (little-endian UInt32), the words (little-endian UInt32), then one byte per word for
    /// whether its frame has sound.
    static func encodePrint(_ p: RecordingPrint) -> Data {
        var d = Data(printMagic)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        u32(UInt32(p.words.count))
        for w in p.words { u32(w) }
        d.append(contentsOf: p.sounding.map { $0 ? 1 : 0 })
        return d
    }

    static func decodePrint(_ d: Data) -> RecordingPrint? {
        let b = [UInt8](d)
        guard b.count >= 8, Array(b[0..<4]) == printMagic else { return nil }
        func u32(_ at: Int) -> UInt32 {
            UInt32(b[at]) | UInt32(b[at + 1]) << 8 | UInt32(b[at + 2]) << 16 | UInt32(b[at + 3]) << 24
        }
        let n = Int(u32(4))
        guard b.count == 8 + n * 5 else { return nil }
        let words = (0..<n).map { u32(8 + $0 * 4) }
        let sounding = (0..<n).map { b[8 + n * 4 + $0] != 0 }
        return RecordingPrint(words: words, sounding: sounding)
    }
}
