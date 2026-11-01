import Foundation
import Testing
import DeckieCrate

// The disc and folder operations: what each does, that folders are always numbered 1..n, and that the labels
// survive the writer and the reader.

@Suite struct DiscsTests {
    /// A crate of `n` tracks t0..t(n-1) on no disc.
    func crate(_ n: Int) -> Crate {
        var c = sampleCrate()
        let base = c.tracks[1]
        c.tracks = (0..<n).map { i in
            var t = base
            t.id = "t\(i)"; t.ident.title = "Song \(i)"
            t.ident.disc = nil; t.ident.folder = nil; t.ident.track = nil
            return t
        }
        return c
    }

    func ids(_ c: Crate, _ d: String, _ f: String) -> [String] { c.trackIds(disc: d, folder: f) }

    /// Every folder numbered 1..n in the plan's order, and no track with a number or folder but no disc.
    func numberedWell(_ c: Crate) -> Bool {
        let byId = Dictionary(uniqueKeysWithValues: c.tracks.map { ($0.id, $0) })
        for d in c.discPlan { for f in d.folders {
            if f.trackIds.map({ byId[$0]!.ident.track }) != (0..<f.trackIds.count).map({ Optional($0 + 1) }) { return false }
        } }
        return c.tracks.allSatisfy { $0.ident.disc != nil || ($0.ident.folder == nil && $0.ident.track == nil) }
    }

    @Test func placeAppendsAndInserts() {
        var c = crate(6)
        c.place(["t0", "t1"], disc: "Singalongs", folder: "Peak")
        #expect(ids(c, "Singalongs", "Peak") == ["t0", "t1"])
        c.place(["t2"], disc: "Singalongs", folder: "Peak", at: 0)
        #expect(ids(c, "Singalongs", "Peak") == ["t2", "t0", "t1"])
        c.place(["t3"], disc: "Singalongs", folder: "Peak", at: 99)
        #expect(ids(c, "Singalongs", "Peak") == ["t2", "t0", "t1", "t3"])
        #expect(c.tracks.first { $0.id == "t2" }!.ident.track == 1)
        #expect(c.tracks.first { $0.id == "t3" }!.ident.track == 4)
        #expect(numberedWell(c))
    }

    @Test func placingATrackAlreadyInAFolderMovesIt() {
        var c = crate(5)
        c.place(["t0", "t1", "t2"], disc: "Singalongs", folder: "Opening")
        c.place(["t1"], disc: "Mix-ins", folder: "Late")
        #expect(ids(c, "Singalongs", "Opening") == ["t0", "t2"])
        #expect(ids(c, "Mix-ins", "Late") == ["t1"])
        // within the same folder: placing again moves it to the new place
        c.place(["t0"], disc: "Singalongs", folder: "Opening")
        #expect(ids(c, "Singalongs", "Opening") == ["t2", "t0"])
        #expect(c.tracks.filter { $0.id == "t1" }.count == 1)
        #expect(numberedWell(c))
    }

    @Test func removeClearsAllThreeLabels() {
        var c = crate(4)
        c.place(["t0", "t1", "t2"], disc: "Singalongs", folder: "Peak")
        c.remove(["t1"])
        let t1 = c.tracks.first { $0.id == "t1" }!
        #expect(t1.ident.disc == nil && t1.ident.folder == nil && t1.ident.track == nil)
        #expect(ids(c, "Singalongs", "Peak") == ["t0", "t2"])
        #expect(numberedWell(c))
    }

    @Test func moveWithinItsFolder() {
        var c = crate(4)
        c.place(["t0", "t1", "t2", "t3"], disc: "D", folder: "F")
        c.move("t3", to: 0)
        #expect(ids(c, "D", "F") == ["t3", "t0", "t1", "t2"])
        c.move("t3", to: 2)
        #expect(ids(c, "D", "F") == ["t0", "t1", "t3", "t2"])
        c.move("t0", to: -5)
        #expect(ids(c, "D", "F") == ["t0", "t1", "t3", "t2"])
        let before = c
        c.move("nope", to: 0)
        #expect(c == before)
        #expect(numberedWell(c))
    }

    @Test func renameDiscAndFolder() {
        var c = crate(6)
        c.place(["t0", "t1"], disc: "A", folder: "One")
        c.place(["t2"], disc: "A", folder: "Two")
        c.renameDisc("A", to: "B")
        #expect(c.discPlan.map(\.name) == ["B"])
        #expect(ids(c, "B", "One") == ["t0", "t1"])
        c.renameFolder("One", inDisc: "B", to: "First")
        #expect(c.discPlan[0].folders.map(\.name) == ["First", "Two"])
        // onto an existing folder: that folder's songs first
        c.renameFolder("Two", inDisc: "B", to: "First")
        #expect(ids(c, "B", "First") == ["t0", "t1", "t2"])
        // onto an existing disc: folders of the same name join, the other disc's songs first
        c.place(["t3"], disc: "C", folder: "First")
        c.renameDisc("C", to: "B")
        #expect(ids(c, "B", "First") == ["t0", "t1", "t2", "t3"])
        #expect(numberedWell(c))
    }

    @Test func deleteDiscAndFolderClearLabels() {
        var c = crate(6)
        c.place(["t0", "t1"], disc: "A", folder: "One")
        c.place(["t2", "t3"], disc: "A", folder: "Two")
        c.place(["t4"], disc: "B", folder: "Late")
        c.deleteFolder("One", inDisc: "A")
        #expect(c.discPlan.first { $0.name == "A" }!.folders.map(\.name) == ["Two"])
        #expect(c.tracks.first { $0.id == "t0" }!.ident.disc == nil)
        c.deleteDisc("A")
        #expect(c.discPlan.map(\.name) == ["B"])
        #expect(c.tracks.filter { $0.ident.disc != nil }.map(\.id) == ["t4"])
        #expect(c.tracks.count == 6)
        #expect(numberedWell(c))
    }

    @Test func planIsInNameOrder() {
        var c = crate(5)
        c.place(["t0"], disc: "Singalongs", folder: "Peak")
        c.place(["t1"], disc: "Singalongs", folder: "Opening")
        c.place(["t2", "t3"], disc: "Mix-ins", folder: "Late")
        #expect(c.discPlan == [
            DiscPlan(name: "Mix-ins", folders: [FolderPlan(name: "Late", trackIds: ["t2", "t3"])]),
            DiscPlan(name: "Singalongs", folders: [FolderPlan(name: "Opening", trackIds: ["t1"]),
                                                  FolderPlan(name: "Peak", trackIds: ["t0"])]),
        ])
        #expect(Crate.discLine(c.tracks[3]) == "Mix-ins / Late 2")
        #expect(Crate.discLine(c.tracks[4]) == nil)
    }

    @Test func unknownIdsAreIgnored() {
        var c = crate(3)
        let before = c
        c.place(["x", "y"], disc: "A", folder: "F")
        c.remove(["x"])
        c.renameDisc("nope", to: "A"); c.renameFolder("nope", inDisc: "A", to: "B")
        c.deleteDisc("nope"); c.deleteFolder("nope", inDisc: "A")
        #expect(c == before)
        c.place(["x", "t1", "t1", "y"], disc: "A", folder: "F")
        #expect(ids(c, "A", "F") == ["t1"])
    }

    @Test func numberingIsAlways1ToN() {
        // A crate made elsewhere with gaps and repeats gets 1..n from renumber; then a run of operations keeps it.
        var c = crate(10)
        for (i, n) in [7, 3, 3, 12].enumerated() { c.tracks[i].ident.disc = "A"; c.tracks[i].ident.folder = "F"; c.tracks[i].ident.track = n }
        c.renumber()
        #expect(ids(c, "A", "F") == ["t1", "t2", "t0", "t3"])
        #expect(numberedWell(c))
        var rng = SystemRandomNumberGenerator()
        for step in 0..<300 {
            let id = "t\(Int.random(in: 0..<10, using: &rng))"
            switch step % 5 {
            case 0: c.place([id], disc: ["A", "B"].randomElement()!, folder: ["F", "G"].randomElement()!, at: Int.random(in: -1..<5))
            case 1: c.move(id, to: Int.random(in: 0..<6))
            case 2: if Int.random(in: 0..<4) == 0 { c.remove([id]) }
            case 3: if Int.random(in: 0..<8) == 0 { c.renameFolder("G", inDisc: "A", to: "F") }
            default: if Int.random(in: 0..<10) == 0 { c.renameDisc("B", to: "A") }
            }
            #expect(numberedWell(c), "after step \(step)")
        }
    }

    @Test func labelsSurviveTheWriterAndTheReader() throws {
        var c = crate(4)
        c.place(["t2", "t0"], disc: "Singalongs", folder: "Opening")
        c.place(["t3"], disc: "Mix-ins", folder: "Late")
        let back = try CrateReader.decode(withSignatureFiles(try CrateWriter.encode(c), c))
        #expect(back == c)
        #expect(back.discPlan == c.discPlan)
        #expect(back.tracks.first { $0.id == "t0" }!.ident.track == 2)
        #expect(back.problems().isEmpty)

        let dir = try temporaryFolder().appendingPathComponent("Labelled.deckiecrate")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        try CrateWriter.write(c, to: dir)
        #expect(try CrateReader.read(from: dir).discPlan == c.discPlan)
    }
}
