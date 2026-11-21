import Foundation
import Testing
import DeckieCrate
@testable import DeckieBuild
@testable import DeckieDesk

/// A crate whose crate file is there and does not read (the review of Nov 21, 2026: a save stopped by an earlier Desk
/// between writing the list of songs and a new song's style vector): said in plain words, never shown as an empty
/// crate; Add music refused in those words, not the reader's; Rebuild this crate puts it right from Desk's store.
@Suite struct UnreadableCrateTests {
    /// A crate of two songs, each with a style vector (a sidecar), kept as Desk keeps it; the second song's analysis
    /// is in the store, the first's is not. Then the second song's sidecar is taken away, as the old save left it.
    func torn(_ name: String) throws -> (home: DeskHome, info: CrateInfo, whole: Crate) {
        let home = DeskHome(root: try scratch(name))
        let info = try home.shelf.make(name: "Friday")
        var a = entry("aaaa000000000001", "Song A", disc: "Stick", folder: "House", track: 1, rel: "House/a.mp3")
        var b = entry("bbbb000000000002", "Song B", disc: "Stick", folder: "House", track: 2, rel: "House/b.mp3")
        a.style = .init(model: "style-v1", values: (0..<64).map { sin(Double($0)) })
        b.style = .init(model: "style-v1", values: (0..<64).map { cos(Double($0)) })
        var c = crate([a, b], name: "Friday")
        try CrateWriter.write(c, to: home.shelf.package(info.id))
        c = try CrateReader.read(from: home.shelf.package(info.id))
        let record = WorkStore.Record(engine: "deckie-0.4.0", bpmTag: nil, track: b, bars: nil, style: b.style?.values)
        try DeckieFiles.write(try JSONEncoder().encode(record), to: home.store.records.appendingPathComponent("\(b.id).json"))
        try FileManager.default.removeItem(at: home.shelf.package(info.id).appendingPathComponent("style/\(b.id).bin"))
        return (home, info, c)
    }

    @Test func theCrateSaysItCouldNotBeReadAndAddMusicIsRefusedInPlainWords() throws {
        let (home, info, _) = try torn("unreadable-session")
        let s = DeskSession(home: home)
        #expect(s.current?.id == info.id)
        #expect(s.crate == nil)
        let u = try #require(s.unreadable)
        #expect(u.description == "This crate's file could not be read.")
        #expect(u.detail.contains("style/bbbb000000000002.bin"))
        #expect(s.canRebuild)
        // Add music: the plain line, and nothing is read into it.
        #expect(throws: CrateUnreadable.self) { _ = try s.crateForRun(s.addRequest(URL(fileURLWithPath: "/tmp/x"))) }

        // Through the engine's messages: the state carries the line and the rebuild; run.add is refused with it.
        let out = Lines()
        let p = DeskProtocol(home: home, output: out.add, makeRun: AddMusicTests.noRun, analysisCheck: {})
        p.start()
        let state = try #require(out.wait { ($0["event"] as? String) == "state" })
        let current = try #require(state["current"] as? [String: Any])
        #expect(current["hasSongs"] as? Bool == false)
        let line = try #require(current["unreadable"] as? [String: Any])
        #expect(line["line"] as? String == "This crate's file could not be read.")
        #expect(line["canRebuild"] as? Bool == true)
        #expect((line["detail"] as? String)?.contains("style/") == true)
        let music = try scratch("unreadable-music")
        p.handle(line: #"{"id":7,"type":"run.add","path":"\#(music.path)"}"#)
        let refused = try #require(out.wait { ($0["re"] as? Int) == 7 })
        let error = try #require(refused["error"] as? [String: Any])
        #expect(error["code"] as? String == "crate_unreadable")
        #expect(error["detail"] as? String == "This crate's file could not be read.")
        #expect(!out.all.contains { ($0["event"] as? String) == "run.started" })
    }

    @Test func rebuildPutsTheSongRightFromTheStore() throws {
        let (home, info, whole) = try torn("unreadable-rebuild")
        let out = Lines()
        let p = DeskProtocol(home: home, output: out.add, makeRun: AddMusicTests.noRun, analysisCheck: {})
        p.start()
        p.handle(line: #"{"id":3,"type":"crate.rebuild"}"#)
        let r = try #require(out.wait { ($0["re"] as? Int) == 3 })
        #expect(r["ok"] as? Bool == true, "\(r)")
        #expect((r["putRight"] as? Int) == 1 && (r["kept"] as? Int) == 1 && (r["leftOut"] as? Int) == 0)
        #expect((r["lines"] as? [String])?.first == "Crate rebuilt: 2 songs.")
        // The crate file reads again, the same crate as before the tear; the file as it was is kept aside.
        #expect(try CrateReader.read(from: home.shelf.package(info.id)) == whole)
        let names = try FileManager.default.contentsOfDirectory(atPath: home.shelf.folder(info.id).path)
        #expect(names.contains { $0.hasPrefix("unreadable-") })
        let s = DeskSession(home: home)
        #expect(s.unreadable == nil && s.crate?.tracks.count == 2)
    }

    @Test func aSongTheStoreDoesNotHaveIsPutRightWithoutItsMissingPartOrLeftOut() throws {
        let (home, info, whole) = try torn("unreadable-no-record")
        try FileManager.default.removeItem(at: home.store.records.appendingPathComponent("bbbb000000000002.json"))
        let r = try CrateRebuild.rebuild(home: home, crateId: info.id)
        #expect(r == .init(kept: 1, putRight: 1, leftOut: 0))
        let back = try CrateReader.read(from: home.shelf.package(info.id))
        #expect(back.tracks.count == 2)
        #expect(back.tracks.first { $0.id == "bbbb000000000002" }?.style == nil)
        #expect(back.tracks.first { $0.id == "aaaa000000000001" } == whole.tracks.first { $0.id == "aaaa000000000001" })
    }

    @Test func aListThatDoesNotReadCannotBeRebuilt() throws {
        let (home, info, _) = try torn("unreadable-list")
        try Data("{\"tracks\":[".utf8).write(to: home.shelf.package(info.id).appendingPathComponent("crate.json"))
        let s = DeskSession(home: home)
        #expect(s.unreadable != nil && !s.canRebuild)
        #expect(throws: CrateRebuild.CannotRebuild.self) { try s.rebuild() }
    }

    /// The export replaces the DJ's earlier one only once the new copy is whole: a copy that cannot be made leaves
    /// the earlier export as it was.
    @Test func aFailedExportLeavesTheEarlierOne() throws {
        let (home, info, _) = try torn("export-replace")
        let out = try scratch("export-replace-out")
        let dest = out.appendingPathComponent("Friday.deckie", isDirectory: true)
        try DeckieFiles.createDirectory(dest)
        try Data("earlier".utf8).write(to: dest.appendingPathComponent("manifest.json"))
        // The crate file does not read, so the copy fails its check: the earlier export stays.
        #expect(throws: (any Error).self) { try home.shelf.exportCopy(info.id, to: dest) }
        #expect(try Data(contentsOf: dest.appendingPathComponent("manifest.json")) == Data("earlier".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path) == ["Friday.deckie"])
        // Rebuilt, it replaces the earlier one.
        try CrateRebuild.rebuild(home: home, crateId: info.id)
        try home.shelf.exportCopy(info.id, to: dest)
        #expect(try CrateReader.read(from: dest).tracks.count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: out.path) == ["Friday.deckie"])
    }
}
