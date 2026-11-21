import Foundation
import Testing
@testable import DeckieCrate

// A save that cannot tear (CrateWriter.write; the review of Nov 21, 2026). A stop is injected after every step of a
// save in turn, through the writer's test hook, as a closed window or a kill would stop it there: each time, the
// package reads as the old crate or the new one, never neither, and no save's folder is left once it has been read.
// A completed save leaves the same bytes the writer left before saves were made this way.

private struct Stopped: Error {}

@Suite(.serialized) struct SaveSafetyTests {
    /// The old crate: the sample crate, a fingerprint on its first song, its signature file in the package.
    func old() -> Crate {
        var c = sampleCrate()
        c.tracks[0].fingerprint = .init(PrintTests.landmarks(200), madeBy: "linux-x86_64", madeAt: "2026-11-14T09:00:00Z")
        return c
    }

    /// The new crate: renamed; the first song's style vector changed (a sidecar replaced); the second song taken out
    /// (its sidecars deleted); a new song with every sidecar (new files).
    func new() -> Crate {
        var c = old()
        c.manifest.name = "Sample, later"
        let a = c.tracks[0]
        c.tracks[0].style = .init(model: "style-v1", values: (0..<64).map { cos(Double($0)) })
        c.tracks.removeAll { $0.id == "b2" }
        var added = a
        added.id = "c3"
        added.signatures = [:]
        added.fingerprint = .init(PrintTests.landmarks(150), madeBy: "linux-x86_64", madeAt: "2026-11-21T09:00:00Z")
        c.tracks.append(added)
        return c
    }

    func package(_ crate: Crate?) throws -> URL {
        let dir = try temporaryFolder().appendingPathComponent("crate.deckie")
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("signatures"), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent("signatures/a1_o.shazamsignature"))
        if let crate { try CrateWriter.write(crate, to: dir) }
        return dir
    }

    /// Runs `body` with a stop after the `n`th step of a save to `dir` (1 is the first); whether the stop came.
    func stopping(after n: Int, in dir: URL, _ body: () throws -> Void) rethrows -> Bool {
        nonisolated(unsafe) var steps = 0
        nonisolated(unsafe) var stopped = false
        let target = dir.standardizedFileURL.path
        CrateWriter.stepHook = { pkg, _ in
            guard pkg.standardizedFileURL.path == target else { return }
            steps += 1
            if steps == n { stopped = true; throw Stopped() }
        }
        defer { CrateWriter.stepHook = nil }
        do { try body() } catch is Stopped {}
        return stopped
    }

    @Test func aSaveStoppedAfterAnyStepLeavesTheOldCrateOrTheNew() throws {
        let before = old(), after = new()
        var sawOld = 0, sawNew = 0
        var n = 1
        while true {
            let dir = try package(before)
            defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
            let stopped = try stopping(after: n, in: dir) { try CrateWriter.write(after, to: dir) }
            // What is on disk now, read as the next open reads it: a stopped save finished or undone first.
            let read = try CrateReader.read(from: dir)
            #expect(read == before || read == after, "stopped after step \(n)")
            #expect(!CrateWriter.hasInterruptedSave(dir), "a save's folder left after step \(n)")
            if read == before { sawOld += 1 } else { sawNew += 1 }
            if !stopped {
                #expect(read == after)
                break
            }
            // Before the save is decided the package is the old crate; after, the new one.
            n += 1
            #expect(n < 100)
            if n >= 100 { break }
        }
        // New sidecars, the staged files, the list, each placed and deleted file: many steps, old then new.
        #expect(sawOld >= 4 && sawNew >= 4, "old \(sawOld), new \(sawNew)")
    }

    @Test func aFirstSaveStoppedAnywhereLeavesNoCrateOrTheCrate() throws {
        let crate = old()
        var n = 1
        while n < 100 {
            let dir = try package(nil)
            defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
            let stopped = try stopping(after: n, in: dir) { try CrateWriter.write(crate, to: dir) }
            try CrateWriter.finishInterruptedSave(dir)
            let manifest = FileManager.default.fileExists(atPath: dir.appendingPathComponent("manifest.json").path)
            if manifest {
                #expect(try CrateReader.read(from: dir) == crate, "stopped after step \(n)")
            } else {
                // No crate yet: no list of songs either, only sidecars no record names (the builder reads such a
                // package as empty).
                #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("crate.json").path), "after step \(n)")
            }
            if !stopped { #expect(manifest); break }
            n += 1
        }
    }

    /// A save stopped after its list was written is finished by the next write's own start, and one stopped part-way
    /// through finishing is finished again the same way, also after a second stop.
    @Test func aStoppedSaveIsFinishedAtTheNextOpenEvenAfterASecondStop() throws {
        let before = old(), after = new()
        let dir = try package(before)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        // Find the step at which the save is decided.
        nonisolated(unsafe) var names: [String] = []
        CrateWriter.stepHook = { _, s in names.append(s) }
        let probe = try package(before)
        try CrateWriter.write(after, to: probe)
        CrateWriter.stepHook = nil
        try? FileManager.default.removeItem(at: probe.deletingLastPathComponent())
        let decided = try #require(names.firstIndex(of: "decided")) + 1

        // Stopped just after the first file was put in place, then stopped again while finishing it at the next open.
        #expect(try stopping(after: decided + 1, in: dir) { try CrateWriter.write(after, to: dir) })
        #expect(CrateWriter.hasInterruptedSave(dir))
        #expect(try stopping(after: 2, in: dir) { try CrateWriter.finishInterruptedSave(dir) })
        #expect(CrateWriter.hasInterruptedSave(dir))
        #expect(try CrateReader.read(from: dir) == after)
        #expect(!CrateWriter.hasInterruptedSave(dir))

        // Stopped before the list: undone, the old crate as it was, byte for byte.
        let again = try package(before)
        defer { try? FileManager.default.removeItem(at: again.deletingLastPathComponent()) }
        let was = try snapshot(again)
        #expect(try stopping(after: decided - 1, in: again) { try CrateWriter.write(after, to: again) })
        try CrateWriter.finishInterruptedSave(again)
        var now = try snapshot(again)
        // The new song's sidecars, written straight in, are files no record names; the next save takes them away.
        for k in now.keys where k.contains("c3") { now[k] = nil }
        #expect(now == was)
        #expect(try CrateReader.read(from: again) == before)
    }

    /// A save's folder holding a list that does not read is not trusted: it is deleted and the package left alone.
    @Test func aListThatDoesNotReadIsNotFollowed() throws {
        let before = old()
        let dir = try package(before)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let saving = CrateWriter.savingFolder(for: dir)
        #expect(saving.lastPathComponent == "crate.deckie.saving")
        try FileManager.default.createDirectory(at: saving, withIntermediateDirectories: true)
        try Data(#"{"format":1,"place":["../escape.json"],"remove":["crate.json"]}"#.utf8)
            .write(to: saving.appendingPathComponent("saving.json"))
        #expect(try CrateReader.read(from: dir) == before)
        #expect(!CrateWriter.hasInterruptedSave(dir))
    }

    /// A list whose files are neither in the save's folder nor in the package (two programs at one crate: the folder
    /// undone by one while the other still saved) is not followed: nothing the old list of songs names is deleted.
    @Test func aListWhoseFilesAreGoneDeletesNothing() throws {
        let before = old()
        let dir = try package(before)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let saving = CrateWriter.savingFolder(for: dir)
        try FileManager.default.createDirectory(at: saving, withIntermediateDirectories: true)
        let list = CrateWriter.SaveList(place: ["crate.json"], remove: ["bars/b2.bin"], sha256: ["crate.json": String(repeating: "0", count: 64)])
        try JSONEncoder().encode(list).write(to: saving.appendingPathComponent("saving.json"))
        #expect(try CrateReader.read(from: dir) == before)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("bars/b2.bin").path))
        #expect(!CrateWriter.hasInterruptedSave(dir))
    }

    /// Runs `body` with every delete of a save's tidying (the save's folder, its files, stale sidecars) below `dir`'s
    /// folder failing, as a file held by another program through every retry does on Windows; the notes it logged.
    func held(in dir: URL, _ body: () throws -> Void) rethrows -> [String] {
        let root = dir.deletingLastPathComponent().standardizedFileURL.path
        nonisolated(unsafe) var notes: [String] = []
        let log = CrateWriter.log
        CrateWriter.removeHook = { $0.standardizedFileURL.path.hasPrefix(root) }
        CrateWriter.log = { notes.append($0) }
        defer { CrateWriter.removeHook = nil; CrateWriter.log = log }
        try body()
        return notes
    }

    /// The Windows runner, Nov 21, 2026: the save's folder could not be removed at the end of a save ("another
    /// program kept the file open"), and the save failed. Now the save has succeeded once its files are in place:
    /// the tidying that cannot be done is noted and left, and the next open or save does it.
    @Test func aSaveWhoseTidyingIsHeldStillSucceedsAndIsTidiedNextTime() throws {
        let before = old(), after = new()
        let dir = try package(before)
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
        let notes = try held(in: dir) {
            try CrateWriter.write(after, to: dir)
            // While still held: the crate reads as the new one, and the leftover does not stop that.
            #expect(try CrateReader.read(from: dir) == after)
            // A further save, with the folder still there and still held, succeeds too.
            try CrateWriter.write(before, to: dir)
            #expect(try CrateReader.read(from: dir) == before)
            try CrateWriter.write(after, to: dir)
        }
        #expect(!notes.isEmpty && notes.allSatisfy { $0.contains("left for the next save to tidy") })
        #expect(CrateWriter.hasInterruptedSave(dir))
        // Let go: the next open tidies it, with nothing else to do, and the stale sidecar is gone by the next save.
        #expect(try CrateReader.read(from: dir) == after)
        #expect(!CrateWriter.hasInterruptedSave(dir))
        try CrateWriter.write(after, to: dir)
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("bars/b2.bin").path))
        #expect(try CrateReader.read(from: dir) == after)
    }

    /// A kill in the middle of a save, with a folder an earlier save could not tidy already there (and its deletes
    /// still failing): the package is still the old crate or the new one, after every step.
    @Test func aSaveStoppedAnywhereOverALeftoverFolderLeavesTheOldCrateOrTheNew() throws {
        let mid = old(), after = new()
        var n = 1
        while n < 100 {
            let dir = try package(new())
            defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }
            _ = try held(in: dir) { try CrateWriter.write(mid, to: dir) }
            #expect(CrateWriter.hasInterruptedSave(dir))
            var stopped = false
            _ = try held(in: dir) {
                stopped = try stopping(after: n, in: dir) { try CrateWriter.write(after, to: dir) }
            }
            let read = try CrateReader.read(from: dir)
            #expect(read == mid || read == after, "stopped after step \(n)")
            if !stopped { #expect(read == after); break }
            n += 1
        }
    }

    /// A completed save leaves the same bytes as the writer did before saves were made through a folder (its steps,
    /// kept here as they were): the same three saves into two packages, compared file by file after each.
    @Test func aCompletedSaveIsByteForByteWhatItWas() throws {
        let a = try package(nil), b = try package(nil)
        defer {
            try? FileManager.default.removeItem(at: a.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: b.deletingLastPathComponent())
        }
        try Data("{}".utf8).write(to: a.appendingPathComponent("prefs.json"))
        try Data("{}".utf8).write(to: b.appendingPathComponent("prefs.json"))
        for crate in [old(), new(), old(), new()] {
            try CrateWriter.write(crate, to: a)
            try Self.writeAsBefore(crate, to: b)
            #expect(try snapshot(a) == snapshot(b))
            #expect(!CrateWriter.hasInterruptedSave(a))
        }
    }

    /// CrateWriter.write as it was until Nov 21, 2026 (stale sidecars and covers deleted, then every file written in
    /// path order), for the comparison above.
    static func writeAsBefore(_ crate: Crate, to package: URL) throws {
        let files = try CrateWriter.encode(crate)
        let fm = FileManager.default
        try fm.createDirectory(at: package, withIntermediateDirectories: true)
        for (folder, ext) in [("bars", ".bin"), ("style", ".bin"), ("prints", ".dkl")] {
            let dir = package.appendingPathComponent(folder)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names where name.hasSuffix(ext) && files["\(folder)/\(name)"] == nil {
                try fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
        let covers = Set(crate.tracks.compactMap(\.file.cover))
        let coversDir = package.appendingPathComponent("covers")
        for name in (try? fm.contentsOfDirectory(atPath: coversDir.path)) ?? [] where name.hasSuffix(".jpg") {
            if !covers.contains(String(name.dropLast(4))) { try fm.removeItem(at: coversDir.appendingPathComponent(name)) }
        }
        for path in files.keys.sorted() {
            let url = package.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files[path]!.write(to: url, options: .atomic)
        }
    }

    /// Every file below `dir`, by its path inside it.
    func snapshot(_ dir: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let base = dir.standardizedFileURL.path
        let walker = FileManager.default.enumerator(atPath: base)
        while let rel = walker?.nextObject() as? String {
            var isDir: ObjCBool = false
            let full = base + "/" + rel
            if FileManager.default.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue {
                out[rel.replacingOccurrences(of: "\\", with: "/")] = try Data(contentsOf: URL(fileURLWithPath: full))
            }
        }
        return out
    }
}
