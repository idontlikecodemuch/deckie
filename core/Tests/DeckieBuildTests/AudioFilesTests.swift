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
}
