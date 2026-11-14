import Foundation
import Testing
import DeckieCrate
@testable import DeckieDesk

/// The words both windows use (DeskWords) and the window-free session the Windows and Linux engine drives
/// (DeskSession): edits, undo and redo, saving, export.
@Suite struct DeskWordsTests {
    @Test func countsCodesAndBlanksFillAsTheMacHadThem() {
        #expect(DeskWords.count("wentIn", 1) == "1 song went in.")
        #expect(DeskWords.count("wentIn", 12) == "12 songs went in.")
        #expect(DeskWords.count("removeBody", 0) == "No songs go: every song on it is somewhere else in the crate too.")
        #expect(DeskWords.count("removeBody", 3) == "3 songs go from the crate. Songs that are somewhere else too stay.")
        #expect(DeskWords.count("songsOf", 40, ["done": "12", "total": "40"]) == "12 of 40 songs")
        #expect(DeskWords.count("sourceLine", 1, ["name": "Stick 3"]) == "Stick 3  ·  1 song")
        #expect(DeskWords.text("finishedTitle", ["read": "Stick 3", "crate": "Friday"]) == "Stick 3 is in Friday")
        #expect(DeskWords.coded("keyFrom", "traktor") == "from Traktor")
        #expect(DeskWords.coded("keyFrom", "mixedinkey") == "from mixedinkey")
        #expect(DeskWords.coded("programName", "hpcp-whitened") == "Deckie")
        // A missing value leaves its blank as it is, and a missing word shows its own name.
        #expect(DeskWords.text("addMusicTo") == "Add music to {crate}")
        #expect(DeskWords.text("noSuchWord") == "noSuchWord")
    }

    @Test func everyBlankIsANameAndTheTableTravelsAsJSON() throws {
        for (key, words) in DeskWords.table {
            var depth = 0
            for c in words { if c == "{" { depth += 1 } else if c == "}" { depth -= 1 }; #expect(depth >= 0 && depth <= 1, "\(key)") }
            #expect(depth == 0, "\(key) has an unclosed blank")
        }
        let back = try JSONDecoder().decode([String: String].self, from: DeskWords.json)
        #expect(back == DeskWords.table)
        // D31: a folder is a source too, and Desk says so where sources are chosen and listed.
        #expect(DeskWords.text("chooseSourceMessage").contains("source"))
        #expect(DeskWords.text("nothingReadYet").contains("folder"))
    }
}

@Suite struct DeskSessionTests {
    /// A crate kept by a desk: two songs on Stick 3 (House), one of them also on Friday (Set 1).
    func make(_ name: String) throws -> (DeskSession, CrateInfo) {
        let home = DeskHome(root: try scratch(name))
        try home.prepare()
        var info = try home.shelf.make(name: "Friday")
        info.sourceRoots["Stick 3"] = "/nowhere/Stick 3"
        info.sourceRoots["Friday"] = "/nowhere/Friday"
        try home.shelf.save(info)
        let a = entry("aaaa", "Song A", disc: "Stick 3", folder: "House", track: 1, rel: "House/01 Song A.mp3",
                      others: [.init(disc: "Friday", folder: "Set 1", track: 1)])
        let b = entry("bbbb", "Song B", disc: "Stick 3", folder: "House", track: 2, rel: "House/02 Song B.mp3")
        try CrateWriter.write(crate([a, b], name: "Friday"), to: home.shelf.package(info.id))
        return (DeskSession(home: home), info)
    }

    @Test func opensTheMostRecentCrateAndKeepsEveryEditAsOneStep() throws {
        let (s, info) = try make("session-edits")
        #expect(s.current?.id == info.id && s.crate?.tracks.count == 2)
        #expect(s.undoName == nil)

        try s.fixName("aaaa", title: "Café 東京", artist: "")
        #expect(s.crate?.tracks.first { $0.id == "aaaa" }?.ident.title == "Café 東京")
        #expect(s.crate?.tracks.first { $0.id == "aaaa" }?.ident.source == "user")
        #expect(s.undoName == "undoNameFix")
        // Saved at once, with the fix kept as a correction.
        let saved = try CrateReader.read(from: s.shelf.package(info.id))
        #expect(saved.tracks.first { $0.id == "aaaa" }?.ident.title == "Café 東京")
        #expect(NameCorrections.load(from: s.shelf.file(DeskRun.correctionsFile, of: info.id)).byId["aaaa"]?.title == "Café 東京")

        try s.renameSource("Stick 3", to: "Stick Three")
        #expect(s.crate?.discPlan.map(\.name).sorted() == ["Friday", "Stick Three"])
        #expect(s.current?.sourceRoots["Stick Three"] == "/nowhere/Stick 3")
        #expect(s.undoName == "undoRename")

        try s.move("bbbb", inSource: "Stick Three", folder: "House", by: -1)
        #expect(s.crate?.trackIds(disc: "Stick Three", folder: "House") == ["bbbb", "aaaa"])

        try s.undo()   // the move
        try s.undo()   // the rename
        #expect(s.crate?.discPlan.map(\.name).sorted() == ["Friday", "Stick 3"])
        #expect(s.redoName == "undoRename")
        try s.redo()
        #expect(s.crate?.discPlan.map(\.name).sorted() == ["Friday", "Stick Three"])
        // A new edit clears what Redo would have put back.
        try s.fixName("bbbb", version: "Extended")
        #expect(s.redoName == nil)
        // Nothing changed, nothing recorded.
        try s.fixName("bbbb", version: "Extended")
        #expect(s.undoName == "undoNameFix")
    }

    @Test func removingASourceSaysHowManyGoAndUndoPutsThemBack() throws {
        let (s, _) = try make("session-remove")
        #expect(s.songsOnlyOn("Friday") == 0)
        #expect(s.songsOnlyOn("Stick 3") == 1)
        try s.removeSource("Stick 3")
        #expect(s.crate?.tracks.map(\.id) == ["aaaa"])
        #expect(s.crate?.tracks.first?.ident.disc == "Friday")
        #expect(s.current?.sourceRoots["Stick 3"] == nil)
        try s.undo()
        #expect(s.crate?.tracks.count == 2)
        #expect(s.current?.sourceRoots["Stick 3"] != nil)
    }

    @Test func exportWritesTheCrateFileUnderItsNameAndDeleteMovesOn() throws {
        let (s, info) = try make("session-export")
        let out = try scratch("session-export-out")
        try s.rename(info.id, to: "Fri: late/early")
        let path = try s.export(into: out)
        #expect(path.lastPathComponent == "Fri- late-early.deckiecrate")
        let c = try CrateReader.read(from: path)
        #expect(c.manifest.name == "Fri: late/early" && c.tracks.count == 2)

        let other = try s.shelf.make(name: "Saturday")
        #expect(s.show(other.id) && s.crate == nil)
        #expect(throws: (any Error).self) { _ = try s.export(into: out) }
        try s.delete(other.id)
        #expect(s.current?.id == info.id)
        try s.delete(info.id)
        #expect(s.current == nil && s.crates.isEmpty)
    }

    @Test func aFolderAddedIsASourceNamedAfterItself() throws {
        let (s, _) = try make("session-add")
        let root = try scratch("session-add-music")
        let mix = root.appendingPathComponent("Mix Tapes")
        try FileManager.default.createDirectory(at: mix, withIntermediateDirectories: true)
        let r = s.addRequest(mix)
        #expect(r.source == "Mix Tapes" && r.name == "Mix Tapes")
        // A second folder of the same name elsewhere is another source.
        s.newCrate()
        #expect(s.addRequest(mix).source == "Mix Tapes")
    }
}
