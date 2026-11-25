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

    /// The top of this computer's own disk, as each part of the way writes it: a folder, and listed. On Windows that
    /// is the system drive (`C:` on the CI runner) in the forms the drive list, a request and a file URL give; this
    /// failed there before (Foundation said "not a folder" for `C:/`). Nothing is walked below the top.
    @Test func theTopOfThisComputersDiskIsAFolderAndIsListed() throws {
        #if os(Windows)
        let drive = (ProcessInfo.processInfo.environment["SystemDrive"] ?? "C:").uppercased()
        var forms = [drive, drive + "\\", drive + "/"]
        forms += forms.map { URL(fileURLWithPath: $0, isDirectory: true).path }
        forms += forms.map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path }
        #else
        let forms = ["/", URL(fileURLWithPath: "/", isDirectory: true).standardizedFileURL.path]
        #endif
        for path in forms {
            #expect(Folders.isFolder(path), "\(path) is a folder")
            let names = try Folders.names(in: path)
            #expect(!names.isEmpty && !names.contains(".") && !names.contains(".."), "\(path): \(names.count) names")
            // The walk's own first step: the check that said "is not a folder".
            #expect(throws: Never.self, "\(path)") { _ = try AudioFiles.checkedRoot(URL(fileURLWithPath: path, isDirectory: true)) }
        }
        #if os(Windows)
        // A name in the top is a path below it that Foundation reads as before.
        let first = try #require(try Folders.names(in: drive + "\\").sorted().first)
        let below = URL(fileURLWithPath: drive + "\\", isDirectory: true).standardizedFileURL.appendingPathComponent(first)
        #expect(FileManager.default.fileExists(atPath: below.path), "\(below.path)")
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
