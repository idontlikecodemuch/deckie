import Foundation
import Testing
@testable import DeckieBuild

/// The scan finds every audio file whatever else sits in the folder.
@Suite struct AudioFilesTests {
    /// A `.DS_Store` (or any hidden file) next to the music must not hide the files listed after it: the walker's
    /// `skipDescendants()` is only for a folder, and called after a file it skipped the rest of that folder (16 of
    /// 17 tracks of one album were lost in the first library build, Oct 29, 2026).
    @Test func hiddenFilesHideNothingButThemselves() throws {
        let root = try temporaryFolder("audio-files-scan")
        let fm = FileManager.default
        func touch(_ rel: String) throws {
            let url = root.appendingPathComponent(rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0x49, 0x44, 0x33]).write(to: url)
        }
        var expected: [String] = []
        for folder in ["Album", "Album/Disc 2", "Singles"] {
            for i in 1...20 {
                let rel = "\(folder)/\(String(format: "%02d", i)). Track.mp3"
                try touch(rel); expected.append(rel)
            }
            // hidden files among the music, in several spellings, so some land before the music in walk order
            for hidden in [".DS_Store", "._01. Track.mp3", ".hidden.mp3", ".z"] { try touch("\(folder)/\(hidden)") }
        }
        // hidden folders, crate packages and work folders stay out, with everything below them
        try touch(".git/objects/x.mp3")
        try touch("Out.deckiecrate/signatures/a.mp3")
        try touch("Out.deckiebuild/records/b.mp3")
        try touch("Album/.Trash/c.mp3")

        let found = try AudioFiles.find(in: root).map(\.rel)
        #expect(found == expected.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) })
        #expect(found.count == 60)
    }

    /// A folder left out by name is reported with the number of audio files it holds.
    @Test func skippedFoldersAreNamedAndCounted() throws {
        let root = try temporaryFolder("audio-files-skip")
        let fm = FileManager.default
        for rel in ["_pool build/a.mp3", "_pool build/deep/b.mp3", "_pool build/.DS_Store", "Music/c.mp3", "Music/.DS_Store", "Music/d.mp3"] {
            let url = root.appendingPathComponent(rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0x49]).write(to: url)
        }
        let (files, skipped) = try AudioFiles.find(in: root, skippingFolderPrefixes: ["_"])
        #expect(files.map(\.rel) == ["Music/c.mp3", "Music/d.mp3"])
        #expect(skipped == [.init(rel: "_pool build", audioFiles: 2)])
    }

    /// Every path the scan gives is a crate path: the names below the folder joined by "/" on every platform (a crate
    /// made on a PC must read on an iPad), and it leads back to the file. The paths are made by the scan itself, so on
    /// Windows this checks that no backslash gets in; nested folders and dots in folder names are in the same folder.
    @Test func pathsHaveSlashesOnEveryPlatform() throws {
        let root = try temporaryFolder("audio-files-paths")
        let fm = FileManager.default
        let made = [["top.wav"], ["A", "one.flac"], ["A", "B.v2", "two.mp3"], ["A", "B.v2", "C", "three.m4a"],
                    ["Vol. 2", "01. Four.aiff"], ["Vol. 2", "Disc 1", "05 Five.MP3"]]
        for names in made {
            let url = names.reduce(root) { $0.appendingPathComponent($1) }
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data([0x49]).write(to: url)
        }
        let found = try AudioFiles.find(in: root)
        let expected = made.map { $0.joined(separator: "/") }.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
        #expect(found.map(\.rel) == expected)
        for f in found {
            #expect(!f.rel.contains("\\"), "\(f.rel) holds a backslash")
            #expect(fm.fileExists(atPath: f.url.path), "\(f.rel) does not lead to its file")
        }
        #expect(found.first { $0.rel == "Vol. 2/Disc 1/05 Five.MP3" }?.ext == "mp3")
        // a left-out folder deep down is named by its crate path too
        try fm.createDirectory(at: root.appendingPathComponent("A/_old"), withIntermediateDirectories: true)
        try Data([0x49]).write(to: root.appendingPathComponent("A/_old/x.mp3"))
        let (files, skipped) = try AudioFiles.find(in: root, skippingFolderPrefixes: ["_"])
        #expect(files.map(\.rel) == expected)
        #expect(skipped == [.init(rel: "A/_old", audioFiles: 1)])
    }
}
