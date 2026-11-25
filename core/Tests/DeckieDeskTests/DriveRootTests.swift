import Foundation
import Testing
import DeckieCrate
import DeckieBuild
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
    /// "C:" in the working folder), and from `C:\` and `C:/` directly, each also standardised. The walk's first step
    /// said "C:/ is not a folder." for a URL until Nov 25, 2026 (core-windows run 45698235586). Each form's values at
    /// every step are printed, so the log says what Windows gave, pass or fail. Nothing is walked below the top.
    @Test func theTopOfThisComputersDiskIsAFolderAndIsListed() throws {
        #if os(Windows)
        let drive = (ProcessInfo.processInfo.environment["SystemDrive"] ?? "C:").uppercased()
        let texts = [drive, drive + "\\", drive + "/"]
        var urls = texts.map { ("folderURL(\($0))", Folders.folderURL($0)) }
        urls += [drive + "\\", drive + "/"].map { ("URL(\($0))", URL(fileURLWithPath: $0, isDirectory: true)) }
        urls += urls.map { ("\($0.0).standardized", $0.1.standardizedFileURL) }
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
        for path in texts {
            let line = "text \"\(path)\": driveRoot \(Folders.driveRoot(path) ?? "nil"), isFolder \(Folders.isFolder(path)), "
                + "\(exists(path)), \(count { try Folders.names(in: path) })"
            print("drive-root: " + line)
            #expect(Folders.isFolder(path), "\(line)")
            let names = (try? Folders.names(in: path)) ?? []
            #expect(!names.isEmpty && !names.contains(".") && !names.contains(".."), "\(line)")
        }
        for (made, url) in urls {
            let native = url.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? "nil"
            var line = "\(made): path \"\(url.path)\", native \"\(native)\", standardized \"\(url.standardizedFileURL.path)\", "
                + "driveRoot(path) \(Folders.driveRoot(url.path) ?? "nil"), driveRoot(of:) \(Folders.driveRoot(of: url) ?? "nil"), "
                + "isFolder \(Folders.isFolder(url)), \(exists(url.path)), \(count { try Folders.names(in: url) })"
            do {
                let root = try AudioFiles.checkedRoot(url)
                line += ", checkedRoot \"\(root.path)\""
            } catch {
                line += ", checkedRoot threw \"\(error)\""
            }
            print("drive-root: " + line)
            #expect(Folders.isFolder(url), "\(line)")
            #expect(((try? Folders.names(in: url)) ?? []).isEmpty == false, "\(line)")
            #expect(throws: Never.self, "\(line)") { _ = try AudioFiles.checkedRoot(url) }
        }
        #if os(Windows)
        // A name in the top is a path below it that Foundation reads as before, and the drive's top is a drive.
        let first = try #require(try Folders.names(in: drive + "\\").sorted().first)
        let below = Folders.folderURL(drive).appendingPathComponent(first)
        #expect(FileManager.default.fileExists(atPath: below.path), "\(below.path)")
        #expect(DeskDrives.isTopOfDrive(Folders.folderURL(drive)))
        #endif
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
