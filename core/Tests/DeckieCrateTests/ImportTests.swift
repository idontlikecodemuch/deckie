import Foundation
import Testing
import DeckieCrate

// Taking a crate file into an app's own storage (CrateImport), as the iPad app does with a crate file from Files,
// AirDrop or a share sheet: both forms arrive as the same package, damage is refused before anything is replaced,
// and the file the DJ gave is never changed. And the one rule for whether a song has a name (SongName).

@Suite struct ImportTests {
    static let single = Paths.core.appendingPathComponent("fixtures/example-single.deckiecrate")

    /// Every file below `folder`, by its path inside it, with its bytes.
    func contents(_ folder: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let base = folder.standardizedFileURL.path
        let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey])!
        for case let u as URL in walker where !((try? u.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false) {
            out[String(u.standardizedFileURL.path.dropFirst(base.count + 1))] = try Data(contentsOf: u)
        }
        return out
    }

    @Test func aPackageAndASingleFileArriveAsTheSamePackage() throws {
        let store = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: store) }
        let fromPackage = try CrateImport.copy(Paths.example, into: store.appendingPathComponent("a"))
        let fromSingle = try CrateImport.copy(Self.single, into: store.appendingPathComponent("b"))
        #expect(!fromPackage.wasSingleFile)
        #expect(fromSingle.wasSingleFile)
        #expect(fromPackage.crate == fromSingle.crate)
        #expect(fromSingle.crate == (try CrateReader.read(from: Paths.example)))
        #expect(fromPackage.package.lastPathComponent == "example.deckie")
        // The same files with the same bytes, whichever form came in.
        #expect(try contents(fromPackage.package) == (try contents(fromSingle.package)))
        // The stored copy is a package folder the reader takes as before.
        var isFolder: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: fromSingle.package.path, isDirectory: &isFolder) && isFolder.boolValue)
    }

    @Test func theFileTheDJGaveIsNotChanged() throws {
        let store = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: store) }
        let given = store.appendingPathComponent("Friday night.deckie")
        try FileManager.default.copyItem(at: Self.single, to: given)
        let before = try Data(contentsOf: given)
        let attributes = try FileManager.default.attributesOfItem(atPath: given.path)
        _ = try CrateImport.copy(given, into: store.appendingPathComponent("storage"))
        #expect(try Data(contentsOf: given) == before)
        #expect(FileManager.default.fileExists(atPath: given.path))
        let after = try FileManager.default.attributesOfItem(atPath: given.path)
        #expect(after[.modificationDate] as? Date == attributes[.modificationDate] as? Date)

        let package = store.appendingPathComponent("Mac.deckie")
        try FileManager.default.copyItem(at: Paths.example, to: package)
        let packageBefore = try contents(package)
        _ = try CrateImport.copy(package, into: store.appendingPathComponent("storage"))
        #expect(try contents(package) == packageBefore)
    }

    @Test func sentAgainItReplacesItself() throws {
        let store = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: store) }
        let first = try CrateImport.copy(Paths.example, into: store)
        let second = try CrateImport.copy(Self.single, into: store)
        #expect(first.package == second.package)
        let names = try FileManager.default.contentsOfDirectory(atPath: store.path)
        #expect(names == ["example.deckie"])
    }

    @Test func damageIsRefusedAndLeavesTheStorageAsItWas() throws {
        let store = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: store) }
        let storage = store.appendingPathComponent("storage")
        let good = try CrateImport.copy(Paths.example, into: storage)
        let goodBytes = try contents(good.package)

        var bytes = [UInt8](try Data(contentsOf: Self.single))
        // A changed byte in the middle of the archive: a file's contents or a header, refused either way.
        bytes[bytes.count / 2] ^= 0xFF
        let damaged = store.appendingPathComponent("damaged.deckie")
        try Data(bytes).write(to: damaged)
        #expect(throws: CrateError.self) { try CrateImport.copy(damaged, into: storage) }

        let cut = store.appendingPathComponent("cut.deckie")
        try Data(try Data(contentsOf: Self.single).prefix(5000)).write(to: cut)
        do {
            _ = try CrateImport.copy(cut, into: storage)
            Issue.record("a cut-short file was taken")
        } catch let e as CrateError {
            #expect(e.description.contains("cut short"))
            #expect(e.problems.first?.file.hasPrefix("cut.deckie") == true)
        }

        let notCrate = store.appendingPathComponent("notes.deckie")
        try Data("just some text".utf8).write(to: notCrate)
        #expect(throws: CrateError.self) { try CrateImport.copy(notCrate, into: storage) }

        let emptyFolder = store.appendingPathComponent("Empty.deckie")
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)
        do {
            _ = try CrateImport.copy(emptyFolder, into: storage)
            Issue.record("an empty folder was taken")
        } catch let e as CrateError {
            #expect(e.description.contains("manifest.json"))
        }

        #expect(throws: CrateError.self) { try CrateImport.copy(store.appendingPathComponent("gone.deckie"), into: storage) }

        // Nothing was left behind and the crate already there is untouched.
        #expect(try FileManager.default.contentsOfDirectory(atPath: storage.path) == ["example.deckie"])
        #expect(try contents(good.package) == goodBytes)
    }

    @Test func storedNamesAreSafe() {
        #expect(CrateImport.storedName("example") == "example.deckie")
        #expect(CrateImport.storedName("2f9c-AB_01") == "2f9c-AB_01.deckie")
        #expect(CrateImport.storedName("../etc/x") == "___etc_x.deckie")
        #expect(CrateImport.storedName("") == "crate.deckie")
        #expect(CrateImport.storedName("caf\u{e9}") == "caf_.deckie")
        #expect(CrateImport.earlierStoredNames("example") == ["example.deckiecrate"])
    }

    /// The extension a crate file is written with, `.deckie`, and the earlier one, `.deckiecrate`, read for good.
    @Test func theExtensionWrittenAndTheOnesRead() {
        #expect(CrateFormat.packageExtension == "deckie")
        #expect(CrateFormat.readExtensions == ["deckie", "deckiecrate"])
        for e in ["deckie", "DECKIE", ".deckie", "deckiecrate", ".DeckieCrate"] { #expect(CrateFormat.isCrateExtension(e), "\(e)") }
        for e in ["", "deckiebuild", "zip", "crate", "deck", "deckiecrates"] { #expect(!CrateFormat.isCrateExtension(e), "\(e)") }
        #expect(CrateFormat.hasCrateExtension("Friday night.deckie"))
        #expect(CrateFormat.hasCrateExtension("Friday night.deckiecrate"))
        #expect(CrateFormat.hasCrateExtension("v1.2 set.DECKIE"))
        #expect(!CrateFormat.hasCrateExtension("deckie"))
        #expect(!CrateFormat.hasCrateExtension(".deckie"))
        #expect(!CrateFormat.hasCrateExtension("Friday night.deckiebuild"))
        #expect(!CrateFormat.hasCrateExtension("notes.txt"))
    }

    /// A crate file made before the extension changed (`.deckiecrate`), in either form, opens unchanged: the same
    /// crate as under the new name, and the file is only read.
    @Test func anEarlierCrateFileOpensUnchanged() throws {
        let store = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: store) }
        // The fixtures themselves carry the earlier extension.
        #expect(Paths.example.pathExtension == "deckiecrate" && Self.single.pathExtension == "deckiecrate")
        let oldPackage = store.appendingPathComponent("Friday night.deckiecrate")
        let oldSingle = store.appendingPathComponent("Saturday.deckiecrate")
        let newSingle = store.appendingPathComponent("Saturday.deckie")
        try FileManager.default.copyItem(at: Paths.example, to: oldPackage)
        try FileManager.default.copyItem(at: Self.single, to: oldSingle)
        try FileManager.default.copyItem(at: Self.single, to: newSingle)
        let packageBefore = try contents(oldPackage)
        let singleBefore = try Data(contentsOf: oldSingle)

        #expect(try CrateReader.read(from: oldPackage) == CrateReader.read(from: newSingle))
        #expect(try CrateReader.read(from: oldSingle) == CrateReader.read(from: newSingle))
        let a = try CrateImport.copy(oldPackage, into: store.appendingPathComponent("a"))
        let b = try CrateImport.copy(oldSingle, into: store.appendingPathComponent("b"))
        #expect(a.crate == b.crate)
        #expect(a.package.lastPathComponent == "example.deckie" && b.package.lastPathComponent == "example.deckie")
        #expect(try contents(oldPackage) == packageBefore)
        #expect(try Data(contentsOf: oldSingle) == singleBefore)
    }

    /// The app's own storage from before the change holds the crate as `<id>.deckiecrate`; the same crate sent again
    /// takes its place as `<id>.deckie`, so it is never kept twice. Other crates are left alone.
    @Test func anEarlierStoredCopyIsReplacedByTheSameCrate() throws {
        let store = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: store) }
        let fm = FileManager.default
        try fm.createDirectory(at: store, withIntermediateDirectories: true)
        try fm.copyItem(at: Paths.example, to: store.appendingPathComponent("example.deckiecrate"))
        try fm.copyItem(at: Paths.example, to: store.appendingPathComponent("other.deckiecrate"))
        let r = try CrateImport.copy(Self.single, into: store)
        #expect(r.package.lastPathComponent == "example.deckie")
        #expect(try fm.contentsOfDirectory(atPath: store.path).sorted() == ["example.deckie", "other.deckiecrate"])
    }
}

@Suite struct SongNameTests {
    @Test func usableTitles() {
        for t in ["Song A", "1999 (Remix)", "99 Problems", "\u{dc}", "Night drive"] { #expect(SongName.isUsableTitle(t), "\(t)") }
        for t in [nil, "", " ", "Track 01", "Track01", "track 1", "Audio Track 3", "Untitled", "Unknown", "07", "Piste 4",
                  "01 - ", "No title"] {
            #expect(!SongName.isUsableTitle(t), "\(t ?? "nil")")
        }
    }

    @Test func usableArtists() {
        #expect(SongName.isUsableArtist("DJ Test"))
        for a in [nil, "", "Unknown Artist", "Various Artists", "VA", "various"] { #expect(!SongName.isUsableArtist(a)) }
    }

    @Test func aTrackKnowsWhetherItHasAName() {
        var t = sampleCrate().tracks[0]
        #expect(t.hasUsableTitle)
        t.ident.title = "Track 07"
        #expect(!t.hasUsableTitle)
    }
}
