import Foundation
import Testing
import DeckieCrate

// Reading a source as it is (D25, D26): its name, its groups and the order a player shows, on made-up paths.

@Suite struct SourcePlacesTests {
    typealias P = SourceReading.Place

    @Test func nameIsTheVolumesElseTheFolders() {
        #expect(SourceReading.name(volumeName: "Stick 3", folderName: "Stick 3 1") == "Stick 3")
        #expect(SourceReading.name(volumeName: nil, folderName: "Friday night") == "Friday night")
        #expect(SourceReading.name(volumeName: "  ", folderName: "Friday night") == "Friday night")
    }

    @Test func groupIsTheFolderPathBelowTheTop() {
        #expect(SourceReading.group(of: "a.mp3") == "")
        #expect(SourceReading.group(of: "House/a.mp3") == "House")
        #expect(SourceReading.group(of: "House/Peak/a.mp3") == "House/Peak")
    }

    @Test func eachGroupIsNumberedFromOneInPlayerOrder() {
        let paths = ["House/02 Second.mp3", "House/01 First.mp3", "Top.mp3", "House/Peak/b.mp3", "House/Peak/a.mp3",
                     "House/10 Tenth.mp3"]
        let p = SourceReading.places(source: "Stick 3", paths: paths)
        #expect(p.count == 6)
        #expect(p["Top.mp3"] == P(source: "Stick 3", group: "", number: 1))
        #expect(p["House/01 First.mp3"] == P(source: "Stick 3", group: "House", number: 1))
        #expect(p["House/02 Second.mp3"] == P(source: "Stick 3", group: "House", number: 2))
        #expect(p["House/10 Tenth.mp3"] == P(source: "Stick 3", group: "House", number: 3))
        #expect(p["House/Peak/a.mp3"] == P(source: "Stick 3", group: "House/Peak", number: 1))
        #expect(p["House/Peak/b.mp3"] == P(source: "Stick 3", group: "House/Peak", number: 2))
    }

    /// The disc's own order (ISO 9660's rule): characters by code, the shorter name padded with spaces, the name
    /// before the extension.
    @Test func playerOrderIsTheDiscsOrder() {
        func sorted(_ names: [String]) -> [String] { names.sorted { SourceReading.comesBefore($0, $1, isFile: true) } }
        // numbers are characters: "10" before "2"
        #expect(sorted(["2 b.mp3", "10 a.mp3", "1 c.mp3"]) == ["1 c.mp3", "10 a.mp3", "2 b.mp3"])
        // capitals before small letters
        #expect(sorted(["abc.mp3", "Zed.mp3"]) == ["Zed.mp3", "abc.mp3"])
        // the name part first, padded with spaces: "A" before "A B" (a plain string sort puts "A B.mp3" first,
        // because a space is below a dot)
        #expect(sorted(["A B.mp3", "A.mp3"]) == ["A.mp3", "A B.mp3"])
        // the same name: the extension decides
        #expect(sorted(["Song.wav", "Song.aiff", "Song.mp3"]) == ["Song.aiff", "Song.mp3", "Song.wav"])
        // a composed and a decomposed accent sort the same: by its code, after every plain letter
        let composed = "Caf\u{e9}.mp3", decomposed = "Cafe\u{301}.mp3"
        #expect(sorted([composed, "Cafe.mp3", "Cafz.mp3"]) == ["Cafe.mp3", "Cafz.mp3", composed])
        #expect(sorted([decomposed, "Cafe.mp3", "Cafz.mp3"]) == ["Cafe.mp3", "Cafz.mp3", decomposed])
    }

    @Test func groupsAreWalkedTopFirstThenEachFolderBeforeItsInside() {
        let groups = ["House/Peak", "", "Disco", "House", "House 2", "Disco/Late"]
        #expect(groups.sorted(by: SourceReading.groupComesBefore) == ["", "Disco", "Disco/Late", "House", "House/Peak", "House 2"])
    }

    @Test func labelWritesTheThreeFieldsForThatSourceOnly() throws {
        var c = sampleCrate()
        c.tracks[0].file.rel = "House/01 a.mp3"
        c.tracks[1].file.rel = "elsewhere.mp3"
        let before1 = c.tracks[1].ident
        c.label(with: SourceReading.places(source: "Stick 3", paths: ["House/01 a.mp3"]))
        #expect(c.tracks[0].ident.disc == "Stick 3")
        #expect(c.tracks[0].ident.folder == "House")
        #expect(c.tracks[0].ident.track == 1)
        #expect(c.tracks[1].ident == before1)
        // the labels survive the writer and the reader
        let back = try CrateReader.decode(withSignatureFiles(CrateWriter.encode(c), c))
        let t0 = back.tracks.first { $0.id == c.tracks[0].id }
        #expect(t0?.ident.disc == "Stick 3" && t0?.ident.folder == "House" && t0?.ident.track == 1)
    }

    /// A folder read with a gap (a file on the stick that is not in the crate) keeps the player's numbers until the DJ
    /// changes that folder; changing another folder leaves it alone.
    @Test func readNumbersSurviveChangesElsewhere() {
        var c = sampleCrate()
        let base = c.tracks[1]
        c.tracks = (0..<5).map { i in var t = base; t.id = "t\(i)"; t.ident.title = "Song \(i)"; return t }
        for (i, n) in [1, 3, 4].enumerated() {
            c.tracks[i].ident.disc = "Stick"; c.tracks[i].ident.folder = "House"; c.tracks[i].ident.track = n
        }
        c.tracks[3].ident.disc = "Stick"; c.tracks[3].ident.folder = "Disco"; c.tracks[3].ident.track = 1
        c.tracks[4].ident.disc = "Other"; c.tracks[4].ident.folder = "X"; c.tracks[4].ident.track = 1
        c.renameDisc("Other", to: "Other 2")
        c.renameFolder("Disco", inDisc: "Stick", to: "Disco classics")
        c.move("t3", to: 0)
        c.deleteDisc("Other 2")
        #expect(c.tracks[0..<3].map(\.ident.track) == [1, 3, 4])
        c.renameDisc("Stick", to: "Stick 3")
        #expect(c.tracks[0..<3].map(\.ident.track) == [1, 3, 4])
        c.move("t2", to: 0)
        #expect(c.trackIds(disc: "Stick 3", folder: "House") == ["t2", "t0", "t1"])
        #expect(c.tracks[0..<3].map(\.ident.track) == [2, 3, 1])
    }
}
