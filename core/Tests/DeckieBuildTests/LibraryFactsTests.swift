import Foundation
import Testing
import DeckieCrate
@testable import DeckieBuild

/// The facts the DJ programs' libraries hold beyond name and key (D34), and gathering them with the files' own.
@Suite struct LibraryFactsTests {
    typealias F = SongFacts

    @Test func rekordboxTraktorVirtualDJAndSerato() throws {
        let rb = """
        <DJ_PLAYLISTS Version="1.0.0"><COLLECTION Entries="1">
        <TRACK TrackID="1" Name="Song R" Artist="Artist R" Album="R Album" Genre="House; Garage" Label="R Label" Year="0"
         Comments="warm up" Remixer="R Remixer" Grouping="" Location="file://localhost/Users/dj/Music/r.mp3"/>
        </COLLECTION></DJ_PLAYLISTS>
        """
        let r = try DJLibrary.parse(.rekordbox, Data(rb.utf8), at: DJLibraryTests.here)
        #expect(r[0].facts == [F.release: ["R Album"], F.genre: ["House", "Garage"], F.label: ["R Label"],
                               F.comment: ["warm up"], F.remixer: ["R Remixer"]])

        let nml = """
        <NML VERSION="19"><COLLECTION ENTRIES="1">
        <ENTRY TITLE="Song T" ARTIST="Artist T"><LOCATION DIR="/:Music/:" FILE="t.mp3" VOLUME="C:"></LOCATION>
        <ALBUM TRACK="4" TITLE="T Album"></ALBUM>
        <INFO GENRE="Techno" LABEL="T Label" COMMENT="peak" RELEASE_DATE="1998/1/1" CATALOG_NO="TL001" KEY="1m"></INFO>
        </ENTRY></COLLECTION></NML>
        """
        let t = try DJLibrary.parse(.traktor, Data(nml.utf8), at: DJLibraryTests.here)
        #expect(t[0].facts == [F.release: ["T Album"], F.trackNumber: ["4"], F.genre: ["Techno"], F.label: ["T Label"],
                               F.comment: ["peak"], F.catalogNumber: ["TL001"], F.year: ["1998"]])
        let dated = try DJLibrary.parse(.traktor, Data(nml.replacingOccurrences(of: "1998/1/1", with: "1998/5/17").utf8), at: DJLibraryTests.here)
        #expect(dated[0].facts[F.date] == ["1998-05-17"])

        let vdj = """
        <VirtualDJ_Database Version="8.1"><Song FilePath="C:\\Music\\v.mp3">
        <Tags Author="A" Title="V" Album="V Album" Genre="Disco" Year="1979" Label="V Label" TrackNumber="2" />
        </Song></VirtualDJ_Database>
        """
        let v = try DJLibrary.parse(.virtualDJ, Data(vdj.utf8), at: URL(fileURLWithPath: "/x/VirtualDJ/database.xml"))
        #expect(v[0].facts == [F.release: ["V Album"], F.genre: ["Disco"], F.year: ["1979"], F.label: ["V Label"], F.trackNumber: ["2"]])

        let u16 = DJLibraryTests.u16
        let track = DJLibraryTests.serato([("pfil", u16("Music/s.mp3")), ("tsng", u16("S")), ("talb", u16("S Album")),
                                           ("tgen", u16("Funk")), ("tlbl", u16("S Label")), ("ttyr", u16("1975"))])
        let s = try DJLibrary.parse(.serato, Data(DJLibraryTests.serato([("vrsn", u16("2.0")), ("otrk", track)])),
                                    at: URL(fileURLWithPath: "/Volumes/USB/_Serato_/database V2"))
        #expect(s[0].facts == [F.release: ["S Album"], F.genre: ["Funk"], F.label: ["S Label"], F.year: ["1975"]])
    }

    @Test func gatheringTheFilesAndTheLibrariesTogether() throws {
        let top = try temporaryFolder("stick-facts")
        try FileManager.default.createDirectory(at: top.appendingPathComponent("House"), withIntermediateDirectories: true)
        let tag = FileFactsTests.tag([FileFactsTests.text("TALB", "Tag Album"), FileFactsTests.text("TSSE", "LAME")])
        try Data(tag + FileTagsTests.mpegFrame).write(to: top.appendingPathComponent("House/a.mp3"))
        var c = Crate(manifest: .init(crateId: "c", name: "N", createdAt: "2026-11-14T00:00:00Z", devicesSeen: []), tracks: [
            LocalFactsApplyTests.track("a", title: "A", rel: "House/a.mp3"),
            LocalFactsApplyTests.track("gone", title: "G", rel: "House/gone.mp3"),
        ])
        c.tracks[0].ident.facts[F.mood] = .init("Mine", from: F.Origin.user)
        c.tracks[0].ident.facts[F.label] = .init("Stale", from: "traktor")
        c.tracks[1].ident.facts[F.release] = .init("Read Last Time", from: F.Origin.tag)
        c.tracks[1].file.otherTags = .init(formats: ["id3v1"], tags: [:], leftOut: [:])
        var files: [String: [LocalFacts.FileRef]] = [:]
        for t in c.tracks { files[t.id] = [.init(url: top.appendingPathComponent(t.file.rel!), rel: t.file.rel!, place: t.ident.ownPlace)] }
        let path = PathKey.slashes(top.appendingPathComponent("House/a.mp3").path)
        let traktor = DJLibraryMatcherTests.lib(.traktor, [DJLibraryEntry(paths: [path], facts: [F.release: ["T Album"], F.genre: ["Techno"]])], written: 2000)
        let serato = DJLibraryMatcherTests.lib(.serato, [DJLibraryEntry(paths: [path], facts: [F.genre: ["Funk"], F.year: ["1990"]])], written: 1000)
        let from = LocalFacts.gatherFacts(&c, files: files, libraries: [serato, traktor])
        let a = c.tracks[0].ident.facts
        #expect(a[F.release] == .init("Tag Album", from: "tag"))       // the file's tag over the libraries
        #expect(a[F.genre] == .init("Techno", from: "traktor"))        // the library written last
        #expect(a[F.year] == .init("1990", from: "serato"))
        #expect(a[F.mood] == .init("Mine", from: "user"))              // the DJ's own stays
        #expect(a[F.label] == nil)                                       // what Traktor gave before and no longer does
        #expect(c.tracks[0].file.otherTags?.tags == ["TSSE": ["LAME"]])
        // A file not here keeps what its tags gave last time.
        #expect(c.tracks[1].ident.facts[F.release]?.values == ["Read Last Time"] && c.tracks[1].file.otherTags?.formats == ["id3v1"])
        #expect(from == ["tag": 2, "traktor": 1, "serato": 1, "user": 1])
        #expect(c.problems().isEmpty)
    }
}
