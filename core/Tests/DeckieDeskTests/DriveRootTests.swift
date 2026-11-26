import Foundation
import Testing
import DeckieCrate
#if os(Windows)
import WinSDK
#endif
@testable import DeckieBuild
@testable import DeckieDesk

/// The top of a drive is a folder like any other (the Windows hand pass of Nov 25, 2026: "Read this drive" on a
/// stick at E: stopped at once with "E:/ is not a folder"), and a stick's system folders are never read as music
/// (a test on Mac disk images the same day: a song in `$RECYCLE.BIN` was read, and became its song's place).
@Suite struct DriveRootTests {
    @Test func theTopOfAWindowsDriveInEveryWayItIsWritten() {
        for path in ["E:", "E:\\", "E:/", "/E:/", "/E:", "e:\\", "E:\\\\", "E://"] {
            #expect(Folders.driveRoot(path) == "E:\\", "\(path)")
        }
        for path in ["E:\\House", "E:/House/", "/", "/Volumes/Stick", "\\\\server\\share", "", "EE:", "1:\\", "E"] {
            #expect(Folders.driveRoot(path) == nil, "\(path)")
        }
    }

    /// The top of this computer's own disk, as each part of the way writes it: a folder, and listed, as text and as a
    /// URL. On Windows that is the system drive (`C:` on the CI runner): as text `C:`, `C:\` and `C:/`; as a URL made
    /// the way Desk makes one from a request (`Folders.folderURL`, which never makes a bare `C:` into a folder named
    /// "C:" in the working folder) and from `C:\` and `C:/` directly. Each form's values at every step are printed
    /// (`drive-root:` lines), so the log says what Windows gave, pass or fail. Nothing is walked below the top.
    ///
    /// Established on the runner (core-windows runs 45698235586 and 45712545553, Nov 25, 2026): Foundation's
    /// `standardizedFileURL` of a drive's top gives a path in the working folder (`<cwd>/C:`), from which the drive
    /// cannot be found again; that is why the walk said "C:/ is not a folder.", and why Desk never standardises a URL
    /// that can be a drive's top except through `Folders.standardized`, which keeps it. The test checks that this is
    /// still what Foundation does (so the reason stays known) and that `Folders.standardized` keeps the drive.
    @Test func theTopOfThisComputersDiskIsAFolderAndIsListed() throws {
        #if os(Windows)
        let drive = (ProcessInfo.processInfo.environment["SystemDrive"] ?? "C:").uppercased()
        let texts = [drive, drive + "\\", drive + "/"]
        var urls = texts.map { ("folderURL(\($0))", Folders.folderURL($0)) }
        urls += [drive + "\\", drive + "/"].map { ("URL(\($0))", URL(fileURLWithPath: $0, isDirectory: true)) }
        // Why a bare drive letter is never made into a URL: it is a path in the working folder.
        print("drive-root: URL(fileURLWithPath: \"\(drive)\").path = \(URL(fileURLWithPath: drive, isDirectory: true).path)")
        #else
        let texts = ["/"]
        let urls = [("URL(/)", URL(fileURLWithPath: "/", isDirectory: true)),
                    ("URL(/).standardized", URL(fileURLWithPath: "/", isDirectory: true).standardizedFileURL)]
        #endif
        func exists(_ path: String) -> String {
            var folder: ObjCBool = false
            let there = FileManager.default.fileExists(atPath: path, isDirectory: &folder)
            return "fileExists \(there) isDirectory \(folder.boolValue)"
        }
        func count(_ list: () throws -> [String]) -> String {
            do { return "\(try list().count) names" } catch { return "cannot list: \(error)" }
        }
        func describe(_ made: String, _ url: URL) -> String {
            let native = url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? "nil"
            var line = "\(made): path \"\(url.path)\", native \"\(native)\", standardized \"\(url.standardizedFileURL.path)\", "
                + "Folders.standardized \"\(Folders.standardized(url).path)\", "
                + "driveRoot(path) \(Folders.driveRoot(url.path) ?? "nil"), driveRoot(of:) \(Folders.driveRoot(of: url) ?? "nil"), "
                + "isFolder \(Folders.isFolder(url)), \(exists(url.path)), \(count { try Folders.names(in: url) })"
            do {
                let root = try AudioFiles.checkedRoot(url)
                line += ", checkedRoot \"\(root.path)\""
            } catch {
                line += ", checkedRoot threw \"\(error)\""
            }
            print("drive-root: " + line)
            return line
        }
        for path in texts {
            let line = "text \"\(path)\": driveRoot \(Folders.driveRoot(path) ?? "nil"), isFolder \(Folders.isFolder(path)), "
                + "\(exists(path)), \(count { try Folders.names(in: path) })"
            print("drive-root: " + line)
            #expect(Folders.isFolder(path), "\(line)")
            let names = (try? Folders.names(in: path)) ?? []
            #expect(!names.isEmpty && !names.contains(".") && !names.contains(".."), "\(line)")
        }
        for (made, url) in urls {
            let line = describe(made, url)
            #expect(Folders.isFolder(url), "\(line)")
            #expect(((try? Folders.names(in: url)) ?? []).isEmpty == false, "\(line)")
            #expect(throws: Never.self, "\(line)") { _ = try AudioFiles.checkedRoot(url) }
            // Desk's own standardising keeps it a folder that lists.
            let kept = Folders.standardized(url)
            #expect(Folders.isFolder(kept) && ((try? Folders.names(in: kept)) ?? []).isEmpty == false, "\(line)")
            #expect(Folders.same(url, kept), "\(line)")
            #if os(Windows)
            #expect(Folders.driveRoot(of: kept) == drive + "\\", "\(line)")
            // Foundation's own: the drive is lost (see above). If this ever changes, the reason above is out of date.
            let lost = url.standardizedFileURL
            let lostLine = describe(made + ".standardized", lost)
            #expect(Folders.driveRoot(lost.path) == nil && Folders.driveRoot(of: lost) == nil, "\(lostLine)")
            #expect(!Folders.isFolder(lost), "\(lostLine)")
            #endif
        }
        #if os(Windows)
        try placesBelowTheTop(of: Folders.folderURL(drive), source: "Stick")
        #expect(DeskDrives.isTopOfDrive(Folders.folderURL(drive)) && DeskDrives.readsADrive(Folders.folderURL(drive), environment: [:]))
        // A source read from the drive's top keeps its name when read from there again, by any form of the top, as
        // the system's own reader sees it (SourceIdentity.read): the system drive is the computer's own disk, with
        // its volume serial number as its identity, the same for every form of its top.
        let top = Folders.folderURL(drive)
        let atTop = SourceIdentity.read(top)
        #expect(atTop.ownDisk && atTop.identity != nil && atTop.identity?.inside == "", "\(atTop)")
        let kept = [SourceNaming.Recorded(name: "Stick", root: top, identity: atTop.identity, files: [])]
        // Recorded before identities were kept: only the same path on the computer's own disk can make it the same.
        let before = [SourceNaming.Recorded(name: "Stick", root: top, identity: nil, files: [])]
        let other = SourceIdentity.Found(identity: SourceIdentity(volume: "0000-0001", inside: ""), ownDisk: false)
        for form in texts {
            let url = Folders.folderURL(form)
            let found = SourceIdentity.read(url)
            #expect(found == atTop, "\(form): \(found)")
            #expect(SourceNaming.choose("Stick", root: url, found: found, recorded: kept) == "Stick", "\(form)")
            #expect(SourceNaming.choose("Stick", root: url, found: found, recorded: before) == "Stick", "\(form)")
            // Not by default: another drive at that path is another source, and so is another folder on this disk.
            #expect(SourceNaming.choose("Stick", root: url, found: other, recorded: kept) == "Stick 2", "\(form)")
        }
        let windows = URL(fileURLWithPath: drive + "\\Windows", isDirectory: true)
        #expect(SourceNaming.choose("Stick", root: windows, found: SourceIdentity.read(windows), recorded: before) == "Stick 2")
        #endif
    }

    /// The paths and places of the files directly at a folder's top and in one folder below it, built the way the walk
    /// builds them (`AudioFiles.walk`, names from the listing; no file is read): a path below the top with "/" between
    /// names and no drive in it, a URL that is there, and a place whose group is the folder below the top. On Windows
    /// the folder is the drive's top itself.
    func placesBelowTheTop(of top: URL, source: String) throws {
        var entries: [(rel: String, url: URL, folder: Bool)] = []
        AudioFiles.walk(top, below: "") { rel, _, url, type in entries.append((rel, url, type == .typeDirectory)); return false }
        #expect(!entries.isEmpty, "\(top.path) gave no names")
        var below: [(rel: String, url: URL, folder: Bool)] = []
        for dir in entries.filter(\.folder).prefix(5) {
            AudioFiles.walk(dir.url, below: dir.rel) { rel, _, url, type in below.append((rel, url, type == .typeDirectory)); return false }
            if !below.isEmpty { break }
        }
        var checked = 0
        for e in entries.prefix(20) + below.prefix(20) {
            let line = "\(top.path) + \"\(e.rel)\" = \(e.url.path)"
            #expect(!e.rel.contains("\\") && !e.rel.contains(":") && !e.rel.hasPrefix("/"), "\(line)")
            // An entry the system lists but will not answer about (a protected junction, a protected system folder)
            // says nothing about paths: it is named and passed over, and every other entry is checked.
            if let why = Self.refused(name: String(e.rel.split(separator: "/").last ?? ""), url: e.url) {
                print("drive-root: \(line): not checked, \(why)")
                continue
            }
            #expect(FileManager.default.fileExists(atPath: e.url.path), "\(line)")
            // The URL Desk rebuilds from the source's root and the path below it (PlacePaths) is the same file.
            #expect(FileManager.default.fileExists(atPath: top.appendingPathComponent(e.rel).path), "\(line)")
            checked += 1
        }
        // Never vacuous: a top with names has entries the system answers about, and they were checked.
        #expect(checked >= min(3, entries.count), "\(top.path): only \(checked) entries checked")
        let files = (entries + below).filter { !$0.folder }.map(\.rel)
        let places = SourceReading.places(source: source, paths: files)
        for rel in files {
            let place = try #require(places[rel], "\(rel)")
            #expect(place.source == source && place.group == SourceReading.group(of: rel), "\(rel): \(place)")
            #expect(rel.contains("/") ? !place.group.isEmpty : place.group.isEmpty, "\(rel): \(place)")
        }
        print("drive-root: \(top.path): \(entries.count) names at the top, \(below.count) in the first folder below, \(files.count) files placed")
    }

    /// Why the system will not answer about an entry it listed, or nil when it will: the read leaves it out anyway
    /// (`AudioFiles.isLeftOut`: "System Volume Information", a recycle bin, a hidden name), or on Windows it is a
    /// reparse point (`FILE_ATTRIBUTE_REPARSE_POINT` from `GetFileAttributesW` on the entry itself: a junction such as
    /// "Documents and Settings", whose target is refused), or Windows refuses to say (`GetFileAttributesW` fails with
    /// `ERROR_ACCESS_DENIED`, which is not "not there": a missing entry still fails the check).
    static func refused(name: String, url: URL) -> String? {
        if AudioFiles.isLeftOut(name: name, url: url) { return "left out by the read" }
        #if os(Windows)
        let path = url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? url.path
        var error: DWORD = 0
        let attributes = path.withCString(encodedAs: UTF16.self) { p -> DWORD in
            let a = GetFileAttributesW(p)
            if a == DWORD.max { error = GetLastError() }
            return a
        }
        if attributes == DWORD.max { return error == DWORD(ERROR_ACCESS_DENIED) ? "access denied" : nil }
        if attributes & DWORD(FILE_ATTRIBUTE_REPARSE_POINT) != 0 { return "a junction or link (reparse point)" }
        #endif
        return nil
    }

    /// The same paths and places for a folder of known files (every system).
    @Test func pathsAndPlacesBelowAFoldersTop() throws {
        let top = try scratch("top")
        try FileManager.default.createDirectory(at: top.appendingPathComponent("House"), withIntermediateDirectories: true)
        for rel in ["01 Song.mp3", "House/02 Song.mp3"] { try Data("x".utf8).write(to: top.appendingPathComponent(rel)) }
        try placesBelowTheTop(of: top, source: "Stick")
        #expect(Folders.same(top, Folders.standardized(top)) && Folders.standardized(top) == top.standardizedFileURL)
    }

    @Test func aFolderAndNotAFolder() throws {
        let root = try scratch("is-folder")
        let file = root.appendingPathComponent("a.mp3")
        try Data("x".utf8).write(to: file)
        #expect(Folders.isFolder(root.path) && Folders.isFolder(root))
        #expect(!Folders.isFolder(file.path) && !Folders.isFolder(root.appendingPathComponent("none").path))
        #expect(try Folders.names(in: root) == ["a.mp3"])
        #expect(throws: (any Error).self) { try Folders.names(in: root.appendingPathComponent("none")) }
        #expect(throws: (any Error).self) { try AudioFiles.checkedRoot(file) }
    }

    /// A stick's system folders, at its top and deeper, in any case: left out of the read and of the count before it,
    /// which agree. `_` folders, `PIONEER` and `_Serato_` are not decided here and stay as they were.
    @Test func aSticksSystemFoldersAreNotMusic() throws {
        let fm = FileManager.default
        let stick = try scratch("junk")
        func touch(_ rel: String) throws {
            let url = stick.appendingPathComponent(rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0x49, 0x44, 0x33]).write(to: url)
        }
        let music = ["House/01 Song.mp3", "House/Gigs/02 Song.mp3", "PIONEER/x.mp3", "_Serato_/y.mp3"]
        for rel in music { try touch(rel) }
        for junk in ["$RECYCLE.BIN/S-1-5-21-1/$RABC123.mp3", "$Recycle.Bin/a.mp3", "System Volume Information/b.mp3",
                     "RECYCLER/c.mp3", "RECYCLED/d.mp3", "lost+found/e.mp3", "House/$RECYCLE.BIN/f.mp3",
                     "House/system volume information/g.mp3", ".Trashes/501/h.mp3", ".Spotlight-V100/i.mp3",
                     ".fseventsd/j.mp3", "House/.Trashes/k.mp3"] {
            try touch(junk)
        }
        let found = try AudioFiles.find(in: stick).map(\.rel)
        #expect(found == music.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) })
        // A source's read (no folder left out by its name) finds the same.
        #expect(try AudioFiles.find(in: stick, skippingFolderPrefixes: []).files.map(\.rel) == found)
        #expect(DeskAddMusic.count(stick).songs == found.count)
        for name in ["$RECYCLE.BIN", "system volume information", "Lost+Found", "RECYCLER"] {
            #expect(AudioFiles.isLeftOut(name: name, url: stick.appendingPathComponent(name)), "\(name)")
        }
        for name in ["PIONEER", "_Serato_", "Engine Library", "_old", "House"] {
            #expect(!AudioFiles.isLeftOut(name: name, url: stick.appendingPathComponent(name)), "\(name)")
        }
    }
}
