import Foundation
import Testing
import DeckieCrate
import DeckieBuild
@testable import DeckieDesk

/// Keys and names gathered for a crate the desk keeps (D30): where libraries are looked for, the ones chosen by hand,
/// and "Look again for keys and names" on a crate already read.
@Suite struct DeskLocalFactsTests {
    @Test func aTestDeskNeverLooksInTheRealHomeFolder() throws {
        let home = DeskHome(root: try scratch("dj-home"))
        #expect(DeskLocalFacts.djHome(for: home, environment: [:]) == nil)
        #expect(DeskLocalFacts.djHome(for: home, environment: [DeskLocalFacts.djHomeVariable: "/tmp/dj"])?.path == "/tmp/dj")
        let standard = DeskHome.standard(environment: [:])
        #expect(DeskLocalFacts.djHome(for: standard, environment: [:]) == FileManager.default.homeDirectoryForCurrentUser)
    }

    @Test func lookAgainTakesKeysAndNamesFromTheStickAndAChosenLibrary() throws {
        let root = try scratch("look-again")
        let fm = FileManager.default
        let stick = root.appendingPathComponent("Stick")
        try fm.createDirectory(at: stick.appendingPathComponent("Set"), withIntermediateDirectories: true)
        try Data([0xFF, 0xFB, 0x90, 0x64] + [UInt8](repeating: 0, count: 60)).write(to: stick.appendingPathComponent("Set/01 Song A.mp3"))
        try Data([0xFF, 0xFB, 0x90, 0x64] + [UInt8](repeating: 1, count: 60)).write(to: stick.appendingPathComponent("Set/02 Song B.mp3"))
        // Serato's library on the stick names B's artist and key; a Traktor collection chosen by hand gives A's key.
        func u16(_ s: String) -> [UInt8] { s.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] } }
        func field(_ tag: String, _ v: [UInt8]) -> [UInt8] {
            Array(tag.utf8) + [UInt8(v.count >> 24 & 0xFF), UInt8(v.count >> 16 & 0xFF), UInt8(v.count >> 8 & 0xFF), UInt8(v.count & 0xFF)] + v
        }
        let otrk = field("pfil", u16("Set/02 Song B.mp3")) + field("tart", u16("Artist B")) + field("tkey", u16("Gm"))
        try fm.createDirectory(at: stick.appendingPathComponent("_Serato_"), withIntermediateDirectories: true)
        try Data(field("vrsn", u16("2.0/Serato Scratch LIVE Database")) + field("otrk", otrk))
            .write(to: stick.appendingPathComponent("_Serato_/database V2"))
        let nml = root.appendingPathComponent("collection.nml")
        let dir = PathKey.slashes(stick.appendingPathComponent("Set").path).replacingOccurrences(of: "/", with: "/:") + "/:"
        try Data("<NML><COLLECTION><ENTRY TITLE=\"A\"><LOCATION DIR=\"\(dir)\" FILE=\"01 Song A.mp3\" VOLUME=\"\"/><INFO KEY=\"1d\"/></ENTRY></COLLECTION></NML>".utf8)
            .write(to: nml)

        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        var choices = DJLibraryChoices()
        #expect(try choices.add(nml) == .traktor)
        #expect(throws: (any Error).self) { _ = try choices.add(root.appendingPathComponent("Stick/Set/01 Song A.mp3")) }
        try choices.save(home)

        var info = try home.shelf.make(name: "Night")
        info.sourceRoots["Stick"] = stick.path
        try home.shelf.save(info)
        let a = entry("aaaa", "x", disc: "Stick", folder: "Set", track: 1, rel: "Set/01 Song A.mp3")
        let b = entry("bbbb", "x", disc: "Stick", folder: "Set", track: 2, rel: "Set/02 Song B.mp3")
        try CrateWriter.write(crate([a, b]), to: home.shelf.package(info.id))
        var paths = PlacePaths()
        paths.record(["aaaa": [ReadPlace(place: a.ident.ownPlace, rel: "Set/01 Song A.mp3")],
                      "bbbb": [ReadPlace(place: b.ident.ownPlace, rel: "Set/02 Song B.mp3")]], source: "Stick")
        try paths.save(to: home.shelf.file(DeskRun.placesFile, of: info.id))
        // The DJ fixed B's title before: the fix stays.
        var fixes = NameCorrections()
        var fixedB = b; fixedB.ident.title = "B (mine)"
        fixes.note(before: b, after: fixedB)
        try fixes.save(to: home.shelf.file(DeskRun.correctionsFile, of: info.id))

        let found = DeskLocalFacts.find(home: home, info: info, environment: [:])
        #expect(Set(found.found.map(\.program)) == [.serato, .traktor])
        let (c, summary) = try DeskLocalFacts.lookAgain(home: home, crateId: info.id, environment: [:])
        let ra = try #require(c.tracks.first { $0.id == "aaaa" }), rb = try #require(c.tracks.first { $0.id == "bbbb" })
        #expect(ra.key?.camelot == "8B" && ra.key?.source == "traktor")
        #expect(ra.ident.title == "Song A" && ra.ident.source == "filename")
        #expect(rb.key?.camelot == "6A" && rb.key?.source == "serato")
        #expect(rb.ident.title == "B (mine)" && rb.ident.source == "user")
        #expect(summary.report.keysFrom == ["traktor": 1, "serato": 1])
        #expect(summary.libraries.count == 2 && summary.failed.isEmpty)
        // Saved: the crate file read back says the same.
        let back = try CrateReader.read(from: home.shelf.package(info.id))
        #expect(back.tracks.first { $0.id == "aaaa" }?.key?.source == "traktor")
    }
}
