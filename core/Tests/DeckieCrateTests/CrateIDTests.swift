import Foundation
import Testing
@testable import DeckieCrate

// SHA-256 written in Swift, against known digests, and record ids made from it.

@Suite struct SHA256Tests {
    /// Digests from Python's hashlib (`hashlib.sha256(...).hexdigest()`); the first three are FIPS 180-2's examples.
    @Test func knownDigests() {
        #expect(CrateIDs.sha256(of: Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(CrateIDs.sha256(of: Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(CrateIDs.sha256(of: Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)) ==
            "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        // The lengths around the padding's edge: 55 bytes still fit one block with the length, 56 do not.
        let a: [(Int, String)] = [
            (55, "9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318"),
            (56, "b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a"),
            (63, "7d3e74a05d7db15bce4ad9ec0658ea98e3f06eeecf16b4c6fff2da457ddc2f34"),
            (64, "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"),
            (65, "635361c48bb9eab14198e76ea8ab7f1a41685d6ad62aa9146d301d4f17eb0ae0"),
        ]
        for (n, digest) in a { #expect(CrateIDs.sha256(of: Data(repeating: 0x61, count: n)) == digest, "\(n) a's") }
    }

    /// 1 MiB, byte i being i mod 251: `hashlib.sha256(bytes(i % 251 for i in range(1048576))).hexdigest()`.
    static let megabyte = Data((0..<1_048_576).map { UInt8($0 % 251) })
    static let megabyteDigest = "631b84027d6b9e52b539c4e8373622d23032dfadc64d60af87339c9037e4f769"

    @Test func aMegabyte() {
        #expect(CrateIDs.sha256(of: Self.megabyte) == Self.megabyteDigest)
    }

    @Test func piecesGiveTheSameDigestAsTheWhole() {
        var hash = SHA256()
        var start = 0
        for size in [0, 1, 63, 64, 65, 1000, 4096, 100_000] {
            hash.update(Self.megabyte[start..<(start + size)])
            start += size
        }
        hash.update(Self.megabyte[start...])
        let hex = hash.finalize().map { String(format: "%02x", $0) }.joined()
        #expect(hex == Self.megabyteDigest)
    }
}

@Suite struct CrateIDTests {
    @Test func theIdIsTheStartOfTheHash() {
        let bytes = SHA256Tests.megabyte
        let id = CrateIDs.id(forFileBytes: bytes)
        #expect(id == "631b84027d6b9e52")
        #expect(id == String(CrateIDs.sha256(of: bytes).prefix(16)))
        #expect(id.count == CrateIDs.idLength && CrateIDs.id(forSHA256: SHA256Tests.megabyteDigest) == id)
        #expect(CrateIDs.id(forFileBytes: Data()) == "e3b0c44298fc1c14")
    }

    @Test func oneByteMoreIsAnotherFile() {
        // The same audio with different bytes (here, one more byte, as a changed tag would add) is a different file.
        var other = SHA256Tests.megabyte
        other.append(0)
        #expect(CrateIDs.id(forFileBytes: other) != CrateIDs.id(forFileBytes: SHA256Tests.megabyte))
    }

    /// The sample crate with its first track named as a shipped engine names it, from stand-in file bytes.
    static func hashedCrate() -> (Crate, String) {
        var crate = sampleCrate()
        let hash = CrateIDs.sha256(of: SHA256Tests.megabyte)
        crate.tracks[0].id = CrateIDs.id(forSHA256: hash)
        crate.tracks[0].file.sha256 = hash
        crate.tracks[0].signatures = [:]
        return (crate, hash)
    }

    @Test func aRecordWithItsHashRoundTrips() throws {
        let (crate, hash) = Self.hashedCrate()
        #expect(crate.problems().isEmpty, "\(crate.problems())")
        let files = try CrateWriter.encode(crate)
        let text = String(decoding: files["crate.json"]!, as: UTF8.self)
        let lines = text.split(separator: "\n")
        #expect(lines[1].contains(#""sha1_head":"f00d","sha256":"\#(hash)"}"#) && lines[1].contains(#""id":"631b84027d6b9e52""#))
        #expect(lines[2].contains(#""sha1_head":"f00d","sha256":null}"#) && lines[2].contains(#""id":"b2""#))
        let back = try CrateReader.decode(files)
        #expect(back == crate && back.tracks.first { $0.id == "631b84027d6b9e52" }?.file.sha256 == hash)

        // A crate written before the field existed reads, the hash as null.
        let older = try editTracks(files) { set(&$0, ["tracks", 1, "file", "sha256"], nil) }
        #expect(try CrateReader.decode(older) == crate)
    }

    @Test func aHashOfTheWrongFormOrAnIdThatIsNotItsStartIsRefused() throws {
        let (crate, hash) = Self.hashedCrate()
        let files = try CrateWriter.encode(crate)
        // The tracks sort by id, so the hashed one is tracks[0]; b2 follows.
        let f = try editTracks(files) { set(&$0, ["tracks", 0, "file", "sha256"], hash.uppercased()) }
        #expect(readProblems(f).map(\.description) == [
            "crate.json: tracks[0].file.sha256 (track 631b84027d6b9e52): \"\(hash.uppercased())\" must be 64 " +
            "lower-case hexadecimal characters (a SHA-256 hash)"])
        let g = try editTracks(files) { set(&$0, ["tracks", 1, "file", "sha256"], hash) }
        #expect(readProblems(g).map(\.description) == [
            "crate.json: tracks[1].id (track b2): \"b2\" must be the first 16 characters of file.sha256, 631b84027d6b9e52"])
        var c = crate
        c.tracks[1].file.sha256 = String(hash.dropLast())
        let error = try #require(throws: CrateError.self) { try CrateWriter.encode(c) }
        #expect(error.problems.map(\.path) == ["tracks[1].file.sha256"])
    }

    @Test func theFormOfAHash() {
        #expect(CrateIDs.isSHA256(SHA256Tests.megabyteDigest))
        #expect(!CrateIDs.isSHA256(SHA256Tests.megabyteDigest.uppercased()))
        #expect(!CrateIDs.isSHA256(String(SHA256Tests.megabyteDigest.dropLast())))
        #expect(!CrateIDs.isSHA256(String(SHA256Tests.megabyteDigest.dropLast()) + "g"))
        #expect(!CrateIDs.isSHA256(""))
    }
}
