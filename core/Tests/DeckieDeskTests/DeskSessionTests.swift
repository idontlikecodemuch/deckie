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
        #expect(DeskWords.count("removeBody", 0) == "No songs go: every song on it is somewhere else in the crate too. Your music files are not touched.")
        #expect(DeskWords.count("removeBody", 3) == "3 songs go from the crate. Songs that are somewhere else too stay. Your music files are not touched.")
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

    /// A crate named after the folder read into it ("F1 - Names is in F1 - Names", "Adding Stick 1 to Stick 1"): the
    /// name is said once.
    @Test func aNameSharedByTheCrateAndWhatWasAddedIsSaidOnce() {
        #expect(DeskWords.text("finishedTitle", ["read": "F1 - Names", "crate": "F1 - Names"]) == "F1 - Names is in the crate")
        #expect(DeskWords.text("runReading", ["read": "Stick 1", "crate": "Stick 1"]) == "Adding the songs in Stick 1")
        #expect(DeskWords.count("stoppedTitle", 1, ["read": "Stick 1", "crate": "Stick 1"]) == "Stopped: 1 song from Stick 1 is in the crate")
        #expect(DeskWords.count("stoppedTitle", 7, ["read": "Stick 1", "crate": "Stick 1"]) == "Stopped: 7 songs from Stick 1 are in the crate")
        #expect(DeskWords.text("removeTitle", ["source": "Stick 1", "crate": "Stick 1"]) == "Remove Stick 1 from the crate?")
        // Capitals and spaces at the ends aside, it is the same name.
        #expect(DeskWords.text("finishedTitle", ["read": "stick 1 ", "crate": "Stick 1"]) == "stick 1  is in the crate")
        // Different names are both said, as before.
        #expect(DeskWords.text("finishedTitle", ["read": "Stick 3", "crate": "Friday"]) == "Stick 3 is in Friday")
        #expect(DeskWords.text("runReading", ["read": "Stick 1", "crate": "Stick 10"]) == "Adding Stick 1 to Stick 10")
        #expect(DeskWords.count("stoppedTitle", 2, ["read": "Stick 3", "crate": "Friday"]) == "Stopped: 2 songs from Stick 3 are in Friday")
        // Every word that names both has its once-only form, and no form names the crate twice or says "track".
        for key in ["finishedTitle", "runReading", "removeTitle"] { #expect(DeskWords.table[key + ".same"] != nil, "\(key)") }
        for (key, words) in DeskWords.table where key.contains(".same") {
            #expect(!words.contains("{crate}") && !words.lowercased().contains("track"), "\(key)")
        }
        #expect(!DeskWords.sameName(["read": "", "crate": ""]) && !DeskWords.sameName(["crate": "Friday"]))
    }

    @Test func theComputerIsNamedByItsKind() {
        #expect(DeskWords.fill(DeskWords.table["saying.folder.1"]!, DeskWords.withComputer([:], kind: "mac")).contains("stays on this Mac."))
        #expect(DeskWords.fill(DeskWords.table["saying.folder.1"]!, DeskWords.withComputer([:], kind: "other")).contains("stays on this computer."))
        #if os(macOS)
        #expect(DeskWords.text("addFolderHelp").contains("on this Mac or"))
        #else
        #expect(DeskWords.text("addFolderHelp").contains("on this computer or"))
        #endif
        // The question before a large read, too (research AE).
        let ask = DeskWords.table["askReadBody"]!
        #expect(DeskWords.fill(ask, DeskWords.withComputer(["about": "9 hours"], kind: "mac")).hasPrefix("That's about 9 hours of reading on this Mac."))
        #expect(DeskWords.fill(ask, DeskWords.withComputer(["about": "9 hours"], kind: "other")).hasPrefix("That's about 9 hours of reading on this computer."))
        // No other word names the Mac: Windows and Linux say "this computer".
        let mac = DeskWords.table.filter { $0.value.contains("Mac") }.map(\.key)
        #expect(mac == ["thisComputer.mac"], "\(mac)")
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

    /// A run's crate file that cannot be read back the moment it is saved (on Windows a virus scanner or the indexer
    /// can hold a file just written): the crate the run saved is shown, never a crate with no songs.
    @Test func aRunsSavedCrateIsShownWhenItsFileCannotBeReadBackAtOnce() throws {
        let (s, info) = try make("session-run-ended")
        let saved = try #require(s.crate)
        let manifest = s.shelf.package(info.id).appendingPathComponent(CrateFormat.manifestFile)
        let good = try Data(contentsOf: manifest)
        try Data("held by another program".utf8).write(to: manifest)
        s.runEnded(info.id, saved: saved)
        #expect(s.current?.id == info.id && s.crate?.tracks.count == 2)
        // Read back alone, the crate would have had no songs.
        s.runEnded(info.id)
        #expect(s.crate == nil)
        // Once the file can be read, it is what is shown.
        try good.write(to: manifest)
        s.runEnded(info.id)
        #expect(s.crate?.tracks.count == 2)
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
        #expect(path.lastPathComponent == "Fri- late-early.deckie")
        let c = try CrateReader.read(from: path)
        #expect(c.manifest.name == "Fri: late/early" && c.tracks.count == 2)
        // One file on Windows and Linux, the package on the Mac.
        #if os(Windows) || os(Linux)
        #expect(DeskSession.exportsSingleFile && CrateArchive.isArchive(path))
        #else
        #expect(!DeskSession.exportsSingleFile && !CrateArchive.isArchive(path))
        #endif

        let other = try s.shelf.make(name: "Saturday")
        #expect(s.show(other.id) && s.crate == nil)
        #expect(throws: (any Error).self) { _ = try s.export(into: out) }
        try s.delete(other.id)
        #expect(s.current?.id == info.id)
        try s.delete(info.id)
        #expect(s.current == nil && s.crates.isEmpty)
    }

    /// The single-file form on export (the switch DeskSession.export makes on Windows and Linux), tried on every
    /// system: one file that holds exactly the package's files with the same bytes, replaces what an earlier export
    /// left under the name in either form, and leaves nothing behind in Desk's storage.
    @Test func exportAsOneFileHoldsThePackagesFilesAndReplacesAnEarlierExport() throws {
        let (s, _) = try make("session-export-one-file")
        let out = try scratch("session-export-one-file-out")
        let fm = FileManager.default

        let package = try s.export(into: out, singleFile: false)
        var isFolder: ObjCBool = false
        #expect(fm.fileExists(atPath: package.path, isDirectory: &isFolder) && isFolder.boolValue)
        let fromPackage = try CrateReader.read(from: package)

        // The same name, now as one file: the package folder left by the first export is replaced.
        let file = try s.export(into: out, singleFile: true)
        #expect(file.path == package.path)
        #expect(fm.fileExists(atPath: file.path, isDirectory: &isFolder) && !isFolder.boolValue)
        #expect(CrateArchive.isArchive(file))
        let inside = try CrateArchive.read(file)
        for (name, data) in inside {
            #expect(try Data(contentsOf: s.shelf.package(s.current!.id).appendingPathComponent(name)) == data, "\(name)")
        }
        #expect(inside[CrateFormat.manifestFile] != nil && inside[CrateFormat.tracksFile] != nil)
        let fromFile = try CrateReader.read(from: file)
        #expect(fromFile.manifest.name == fromPackage.manifest.name)
        #expect(fromFile.tracks.map(\.id) == fromPackage.tracks.map(\.id) && fromFile.tracks.count == 2)

        // Again over the file: the same bytes (the form is canonical), and no scratch folder is left in storage.
        let bytes = try Data(contentsOf: file)
        #expect(try Data(contentsOf: s.export(into: out, singleFile: true)) == bytes)
        let left = try fm.contentsOfDirectory(atPath: s.home.root.path).filter { $0.hasPrefix("export-") }
        #expect(left.isEmpty)
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
