import Foundation
import Testing
import DeckieCrate

// A song's facts (D34, `ident.facts` and `file.other_tags`): the addition after D27's places. Proved here: a crate
// file without them reads as before and keeps its bytes; both round-trip, left out when empty; a reader that does not
// know them (the previous reader's shape) still opens a file that has them; which source wins; validation.

@Suite struct SongFactsTests {
    typealias Fact = CrateTrack.Fact

    func withFacts() -> Crate {
        var c = sampleCrate()
        c.tracks[0].ident.facts = [
            SongFacts.release: Fact("Friday Night", from: "tag"),
            SongFacts.genre: Fact(["House", "Deep House"], from: "tag"),
            SongFacts.label: Fact("Nervous", from: "user"),
            SongFacts.year: Fact("1999", from: "lookup:musicbrainz"),
        ]
        c.tracks[0].file.otherTags = .init(formats: ["id3v2.4"], tags: ["TSSE": ["LAME 3.100"], "TXXX:Crowd": ["peak"]],
                                           leftOut: ["picture": 1])
        return c
    }

    @Test func aCrateFileWithoutThemReadsAsBeforeAndKeepsItsBytes() throws {
        let c = sampleCrate()
        let files = try CrateWriter.encode(c)
        let json = String(decoding: files["crate.json"]!, as: UTF8.self)
        #expect(!json.contains("\"facts\"") && !json.contains("other_tags"))
        let back = try CrateReader.decode(withSignatureFiles(files, c))
        #expect(back == c)
        #expect(back.tracks.allSatisfy { $0.ident.facts.isEmpty && $0.file.otherTags == nil })
        // The committed example crate, written before D34, reads with no facts and writes back byte for byte.
        let example = try CrateReader.read(from: Paths.example)
        #expect(example.tracks.allSatisfy { $0.ident.facts.isEmpty && $0.file.otherTags == nil })
        let again = try CrateWriter.encode(example)
        #expect(again["crate.json"] == (try Data(contentsOf: Paths.example.appendingPathComponent("crate.json"))))
        #expect(again["manifest.json"] == (try Data(contentsOf: Paths.example.appendingPathComponent("manifest.json"))))
    }

    @Test func theyAreWrittenAndReadBack() throws {
        let c = withFacts()
        let files = try CrateWriter.encode(c)
        let json = String(decoding: files["crate.json"]!, as: UTF8.self)
        #expect(json.contains(#""facts":{"genre":{"from":"tag","values":["House","Deep House"]},"label":{"from":"user","values":["Nervous"]},"release":{"from":"tag","values":["Friday Night"]},"year":{"from":"lookup:musicbrainz","values":["1999"]}}"#))
        #expect(json.contains(#""other_tags":{"formats":["id3v2.4"],"left_out":{"picture":1},"tags":{"TSSE":["LAME 3.100"],"TXXX:Crowd":["peak"]}}"#))
        // Only the record that has them carries the keys.
        #expect(json.components(separatedBy: "\"facts\"").count == 2)
        #expect(json.components(separatedBy: "other_tags").count == 2)
        let back = try CrateReader.decode(withSignatureFiles(files, c))
        #expect(back == c)
        #expect(back.problems().isEmpty)
        let manifest = try JSONSerialization.jsonObject(with: files["manifest.json"]!) as! [String: Any]
        #expect(manifest["schema"] as? Int == 1 && manifest["min_reader"] as? Int == 1)
        // The single-file form carries them as it carries everything.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("facts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        var unsigned = c
        for i in unsigned.tracks.indices { unsigned.tracks[i].signatures = [:] }
        try CrateWriter.write(unsigned, to: folder.appendingPathComponent("F.deckiecrate"))
        try CrateArchive.pack(package: folder.appendingPathComponent("F.deckiecrate"), to: folder.appendingPathComponent("one.deckiecrate"))
        #expect(try CrateReader.read(from: folder.appendingPathComponent("one.deckiecrate")).tracks == unsigned.tracks)
    }

    /// The reader as it was before D34: `ident` and `file` with the fields it knew and nothing else (Swift's decoding
    /// ignores keys it does not know, as the format asks of every reader).
    struct PreD34Ident: Decodable {
        var title: String
        var artist: String?, version: String?, source: String?
        var disc: String?, folder: String?, track: Int?
        var tags: [String]
        var other_places: [CrateTrack.Place]?
    }
    struct PreD34File: Decodable { var name: String; var rel: String?; var duration_s: Double; var tag_bpm: Double? }
    struct PreD34Track: Decodable { var id: String; var ident: PreD34Ident; var file: PreD34File }
    struct PreD34Tracks: Decodable { var tracks: [PreD34Track] }

    @Test func theReaderBeforeD34StillReadsAFileThatHasThem() throws {
        let c = withFacts()
        let files = try CrateWriter.encode(c)
        let old = try JSONDecoder().decode(PreD34Tracks.self, from: files["crate.json"]!)
        #expect(old.tracks.map(\.id) == c.tracks.map(\.id))
        let first = try #require(old.tracks.first { $0.id == c.tracks[0].id })
        #expect(first.ident.title == c.tracks[0].ident.title && first.ident.artist == c.tracks[0].ident.artist)
        #expect(first.file.name == c.tracks[0].file.name && first.file.duration_s == c.tracks[0].file.durationS)
    }

    @Test func whichSourceWins() {
        var id = CrateTrack.Ident(title: "A")
        var took: [Bool] = []
        took.append(id.offer("genre", Fact("Disco", from: "lookup:discogs")))
        took.append(id.offer("genre", Fact("House", from: "serato")))            // a program's library over a lookup
        took.append(id.offer("genre", Fact("Garage", from: "cdtext")))           // the disc ranks below a library
        took.append(id.offer("genre", Fact("Deep House", from: "tag")))          // the file's tags over a library
        took.append(id.offer("genre", Fact("Mine", from: "user")))
        took.append(id.offer("genre", Fact("Lookup", from: "lookup:musicbrainz")))  // never over the DJ's own
        took.append(id.offer("genre", Fact("Tag", from: "tag")))
        took.append(id.offer("year", Fact([], from: "tag")))                     // nothing to offer
        #expect(took == [true, true, false, true, true, false, false, false])
        #expect(id.facts["genre"] == Fact("Mine", from: "user"))
        id.dropFacts { $0 == "user" }
        #expect(id.facts.isEmpty)
        #expect(SongFacts.rank("rekordbox-xml") == SongFacts.rank("traktor"))
    }

    @Test func validationChecksFactsAndOtherTags() {
        var c = sampleCrate()
        c.tracks[0].ident.facts = [
            "Bad Name": Fact("x", from: "tag"),
            "label": Fact("x", from: "has space"),
            "genre": Fact([], from: "tag"),
            "comment": Fact(String(repeating: "a", count: SongFacts.maxValueBytes + 1), from: "tag"),
            "mood": Fact(" padded", from: "tag"),
            "composer": Fact((0...SongFacts.maxValues).map { "c\($0)" }, from: "tag"),
        ]
        c.tracks[0].file.otherTags = .init(formats: [], tags: ["": ["x"], "BIG": [String(repeating: "b", count: 1000)] + (0..<4).map { String(repeating: "\($0)", count: 1000) }],
                                           leftOut: ["picture": 0])
        let p = c.problems().map { "\($0.path): \($0.message)" }
        #expect(p.contains { $0.hasPrefix("tracks[0].ident.facts.Bad Name: ") })
        #expect(p.contains("tracks[0].ident.facts.label.from: \"has space\" is not an origin"))
        #expect(p.contains("tracks[0].ident.facts.genre.values: is empty; a fact or tag with no value is left out"))
        #expect(p.contains { $0.hasPrefix("tracks[0].ident.facts.comment.values[0]: is 1025 bytes") })
        #expect(p.contains("tracks[0].ident.facts.mood.values[0]: must be plain text, trimmed and not empty"))
        #expect(p.contains { $0.hasPrefix("tracks[0].ident.facts.composer.values: has 17 values") })
        #expect(p.contains { $0.hasPrefix("tracks[0].file.other_tags.tags.: the name must be plain text") })
        #expect(p.contains { $0.hasPrefix("tracks[0].file.other_tags.tags: holds ") })
        #expect(p.contains("tracks[0].file.other_tags.left_out.picture: 0 must be 1 or more"))
        #expect(throws: (any Error).self) { try CrateWriter.encode(c) }
        var empty = sampleCrate()
        empty.tracks[0].file.otherTags = .init()
        #expect(empty.problems().map(\.message) == ["is empty; it is left out when there is nothing in it"])
    }
}
