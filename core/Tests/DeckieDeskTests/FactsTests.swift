import Foundation
import Testing
import DeckieCrate
import DeckieBuild
import DeckieDisc
import DeckieTestSupport
@testable import DeckieDesk

/// A song's facts in Desk (D34): read from the file, shown with where each came from, the DJ's own kept in the same
/// store as name fixes and put back after a re-read, a music CD's CD-Text facts, and one step of undo each.
@Suite struct DeskFactsTests {
    /// An ID3v2.3 tag with the given text frames, then a few bytes of MPEG audio.
    static func tagged(_ frames: [(String, String)]) -> Data {
        var body: [UInt8] = []
        for (id, text) in frames {
            let d = [3] + Array(text.utf8)
            body += Array(id.utf8) + [UInt8(d.count >> 24 & 0xFF), UInt8(d.count >> 16 & 0xFF), UInt8(d.count >> 8 & 0xFF), UInt8(d.count & 0xFF), 0, 0] + d
        }
        body += [UInt8](repeating: 0, count: 8)
        let n = body.count
        let size: [UInt8] = [UInt8(n >> 21 & 0x7F), UInt8(n >> 14 & 0x7F), UInt8(n >> 7 & 0x7F), UInt8(n & 0x7F)]
        return Data(Array("ID3".utf8) + [3, 0, 0] + size + body + [0xFF, 0xFB, 0x90, 0x64] + [UInt8](repeating: 0, count: 60))
    }

    @Test func theDJsFactsSurviveAReadAgain() throws {
        let root = try scratch("facts-session")
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        let stick = root.appendingPathComponent("Stick 3")
        try FileManager.default.createDirectory(at: stick, withIntermediateDirectories: true)
        try Self.tagged([("TIT2", "Night drive"), ("TPE1", "Artist A"), ("TALB", "Friday Night"), ("TCON", "House"),
                         ("TPUB", "Tag Label"), ("TSSE", "LAME")]).write(to: stick.appendingPathComponent("01 Night drive.mp3"))
        var info = try home.shelf.make(name: "Friday")
        info.sourceRoots["Stick 3"] = stick.path
        try home.shelf.save(info)
        var a = entry("aaaa", "Night drive", disc: "Stick 3", folder: "", track: 1, rel: "01 Night drive.mp3")
        a.ident.artist = "Artist A"
        try CrateWriter.write(crate([a], name: "Friday"), to: home.shelf.package(info.id))
        let s = DeskSession(home: home)
        // Look again reads the file's facts into the crate.
        _ = try s.lookAgain(environment: [:])
        var row = try #require(s.rows.first)
        #expect(row.names?.release.value == "Friday Night" && row.names?.release.from == "tag")
        #expect(row.names?.genre.value == "House" && row.names?.label.value == "Tag Label")
        #expect(row.names?.fileTags.map(\.name) == ["TSSE"])

        try s.fixFacts("aaaa", ["label": "My Label", "genre": "House, Deep House", "year": "1999", "release": ""])
        #expect(s.undoName == "undoNameFix")
        row = try #require(s.rows.first)
        #expect(row.names?.label.value == "My Label" && row.names?.label.from == "user")
        #expect(row.names?.genre.value == "House, Deep House" && row.names?.year.value == "1999")
        #expect(row.names?.release.value == nil)
        // A name fix is unchanged by it: the name is still the tag's.
        #expect(row.nameFrom == "tag" || row.nameFrom == nil)
        // Kept where the name fixes are, and in the crate file as the DJ's.
        let fixes = NameCorrections.load(from: home.shelf.file(DeskRun.correctionsFile, of: info.id))
        #expect(fixes.byId["aaaa"]?.facts == ["label": ["My Label"], "genre": ["House", "Deep House"], "year": ["1999"], "release": []])
        let saved = try CrateReader.read(from: home.shelf.package(info.id)).tracks[0].ident.facts
        #expect(saved["genre"] == .init(["House", "Deep House"], from: "user") && saved["release"] == nil)

        // Read again: the file's tags come back for the rest, and the DJ's facts go back over them.
        _ = try s.lookAgain(environment: [:])
        let again = try CrateReader.read(from: home.shelf.package(info.id)).tracks[0]
        #expect(again.ident.facts["label"] == .init("My Label", from: "user"))
        #expect(again.ident.facts["release"] == nil)
        #expect(again.file.otherTags?.tags == ["TSSE": ["LAME"]])
        #expect(again.ident.source == "tag")
        // Undo takes the DJ's facts back in one step (reading again changed nothing, so it is no step).
        try s.undo()
        #expect(s.rows.first?.names?.release.value == "Friday Night")
    }

    @Test func theRestAreListedInTheirOrder() {
        var t = entry("a", "Song", disc: nil, folder: nil, track: nil, rel: "a.mp3")
        t.ident.facts = ["isrc": .init("X", from: "tag"), "composer": .init(["One", "Two"], from: "serato"),
                         "genre": .init("Funk", from: "tag"), "zzz_later": .init("kept", from: "lookup:musicbrainz")]
        t.file.otherTags = .init(formats: ["vorbis"], tags: ["B": ["2"], "A": ["1", "3"]], leftOut: ["private": 2])
        let f = DeskNaming.facts(t, book: NameBook(), corrections: NameCorrections())
        #expect(f.genre.value == "Funk" && f.others.map(\.name) == ["composer", "isrc", "zzz_later"])
        #expect(f.others[0].value == "One, Two" && f.others[0].from == "serato")
        #expect(f.fileTags.map(\.value) == ["1, 3", "2"] && f.leftOut == ["private": 2])
        #expect(DeskNaming.factValues("genre", " House ;Disco,, ") == ["House", "Disco"])
        #expect(DeskNaming.factValues("composer", "Earth, Wind & Fire") == ["Earth, Wind & Fire"])
    }

    @Test func aMusicCDsCDTextFacts() throws {
        let root = try scratch("facts-disc")
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        var info = try home.shelf.make(name: "Friday")
        let copy = DiscCopies.folder(home, disc: "cd-1")
        try DeckieFiles.createDirectory(copy)
        let text = CDText.decode(DiscFixture.response(DiscFixture.packs([
            (0x80, ["Friday night", "Night drive"].map(DiscFixture.latin1)),
            (0x81, ["DJ Vera", "Artist A"].map(DiscFixture.latin1)),
            (0x83, ["", "A Writer"].map(DiscFixture.latin1)),
            (0x8E, ["0123456789012", "GBXYZ0000001"].map { Array($0.utf8) }),
        ], lastSong: 1)))
        let toc = DiscTOC(tracks: [.init(number: 1, start: 0, audio: true)], leadOut: 1000)
        try JSONFile.write(DiscCopies.Record(toc: toc, reading: .names(text), fileExtension: "wav"),
                           to: copy.appendingPathComponent(DiscCopies.recordFile))
        info.sourceRoots["Friday night"] = copy.path
        var c = crate([entry("aaaa", "Night drive", disc: "Friday night", folder: "", track: 1, rel: "Track 01.wav")])
        c.tracks[0].ident.artist = "Artist A"
        c.tracks[0].ident.facts["release"] = .init("From A Library", from: "traktor")
        #expect(DeskLocalFacts.discFacts(&c, home: home, info: info) == 1)
        let f = c.tracks[0].ident.facts
        #expect(f["release"] == .init("From A Library", from: "traktor"))   // a library ranks above the disc
        #expect(f["release_artist"] == .init("DJ Vera", from: "cdtext"))
        #expect(f["isrc"] == .init("GBXYZ0000001", from: "cdtext") && f["composer"] == .init("A Writer", from: "cdtext"))
        #expect(f["barcode"] == .init("0123456789012", from: "cdtext"))
        #expect(c.problems().isEmpty)
    }
}
