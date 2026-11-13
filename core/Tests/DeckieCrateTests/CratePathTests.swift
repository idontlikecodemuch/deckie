import Foundation
import Testing
import DeckieCrate

/// A crate path has "/" between names on every platform, and only "/" separates (CratePath).
@Suite struct CratePathTests {
    @Test func joinsAndSplitsOnSlashOnly() {
        #expect(CratePath.join(["House", "Peak", "a.mp3"]) == "House/Peak/a.mp3")
        #expect(CratePath.join("", "a.mp3") == "a.mp3")
        #expect(CratePath.join("House", "a.mp3") == "House/a.mp3")
        #expect(CratePath.names("House//Peak/a.mp3") == ["House", "Peak", "a.mp3"])
        #expect(CratePath.lastName("House/Peak/a.mp3") == "a.mp3")
        #expect(CratePath.lastName("a.mp3") == "a.mp3")
        #expect(CratePath.folder(of: "House/Peak/a.mp3") == "House/Peak")
        #expect(CratePath.folder(of: "a.mp3") == "")
    }

    /// A backslash is part of a name (a Mac file may be called `AC\DC - Track.mp3`), never a separator, on any
    /// platform: Foundation's `NSString` path methods may split on it on Windows, and they are not used for crate paths.
    @Test func aBackslashIsPartOfAName() {
        #expect(CratePath.names("Rock/AC\\DC - Track.mp3") == ["Rock", "AC\\DC - Track.mp3"])
        #expect(CratePath.lastName("Rock/AC\\DC - Track.mp3") == "AC\\DC - Track.mp3")
        #expect(CratePath.folder(of: "Rock\\Live/a.mp3") == "Rock\\Live")
        #expect(SourceReading.group(of: "Rock\\Live/a.mp3") == "Rock\\Live")
        let places = SourceReading.places(source: "S", paths: ["Rock/AC\\DC - Track.mp3", "Rock/AB.mp3"])
        #expect(places["Rock/AC\\DC - Track.mp3"]?.group == "Rock")
        #expect(places["Rock/AC\\DC - Track.mp3"]?.number == 2)
    }

    @Test func extensionsAreWhatFollowsTheLastDot() {
        #expect(CratePath.fileExtension(of: "01. Track.MP3") == "MP3")
        #expect(CratePath.fileExtension(of: "Out.deckiecrate") == "deckiecrate")
        #expect(CratePath.fileExtension(of: ".DS_Store") == "")
        #expect(CratePath.fileExtension(of: "README") == "")
        #expect(CratePath.fileExtension(of: "a.") == "")
    }
}
