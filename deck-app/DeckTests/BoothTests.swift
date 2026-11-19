import Foundation
import Testing
@testable import Deck
import DeckieCrate

/// The booth's own tests, run in the simulator with the app as their host:
///   nice -n 19 xcodebuild test -project Deck.xcodeproj -scheme Deck -destination 'platform=iOS Simulator,name=<an iPad>'
/// What the first-run screen depends on, and that a crate file still opens in both forms under both extensions.
@Suite(.serialized) struct BoothTests {
    /// The repository's two example crate files (core/fixtures): the package a Mac writes and the single file a PC
    /// writes, both under the earlier extension. The simulator reads the Mac's files, so they are read in place.
    static let fixtures: URL = {
        var u = URL(fileURLWithPath: #filePath)
        for _ in 0..<3 { u.deleteLastPathComponent() }   // DeckTests/<file> -> deck-app -> repo
        return u.appendingPathComponent("core/fixtures")
    }()

    // MARK: the first-run screen

    @Test func noCrateFileShowsTheFirstRunScreen() {
        #expect(BoothScreen.now(crateOpen: false, demoBundled: false) == .firstRun(demo: false))
    }

    @Test func theDemoButtonShowsOnlyWhenADemoComesWithTheApp() {
        #expect(BoothScreen.now(crateOpen: false, demoBundled: true) == .firstRun(demo: true))
        #expect(BoothScreen.now(crateOpen: true, demoBundled: true) == .crate)
    }

    @Test func aCrateFileOpenShowsTheTabs() {
        #expect(BoothScreen.now(crateOpen: true, demoBundled: false) == .crate)
    }

    @Test func theDemoShipsAndNoPartyDataDoes() {
        #expect(DemoCrate.url() != nil)
        #expect(BoothScreen.now(crateOpen: false, demoBundled: DemoCrate.url() != nil) == .firstRun(demo: true))
        for (name, ext) in [("deck_data", "json"), ("overview", "json"), ("mixmap", "html"), ("Deck", "shazamcatalog")] {
            #expect(Bundle.main.url(forResource: name, withExtension: ext) == nil, "\(name).\(ext) is in the app")
        }
        #expect(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") != nil)
    }

    // MARK: the demo

    /// The bundled demo is a crate file like any other: facts and fingerprints of every song, no audio, and Booth can
    /// name its songs. It opens as a crate file opens, Booth knows it is the demo, and leaving it shows the first-run
    /// screen again.
    @Test func theDemoOpensAsACrateFileAndLeavesAgain() throws {
        let demo = try #require(DemoCrate.url())
        let fm = FileManager.default
        let files = try #require(fm.enumerator(at: demo, includingPropertiesForKeys: nil)?.allObjects as? [URL])
        for f in files where !f.hasDirectoryPath {
            #expect(["json", "bin", "dkl"].contains(f.pathExtension), "\(f.lastPathComponent) is in the demo")
        }
        let work = fm.temporaryDirectory.appendingPathComponent("booth-demo-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fm.removeItem(at: work)
            Library.shared.close()
        }
        let r = try Library.shared.open(crateFile: demo, into: work)
        #expect(DemoCrate.crateId() != nil)
        // Its name, as the Crate tab shows it, and its id, kept since it was first built (Nov 19, 2026): the name was
        // changed in the manifest by hand, so the package must still be exactly what the writer would write.
        #expect(r.crate.manifest.name == "Demo crate")
        #expect(r.crate.manifest.crateId == "1a365511-96d6-4840-a9f3-e9b7a772179c")
        let written = try CrateWriter.encode(r.crate)
        for file in ["manifest.json", "crate.json"] {
            #expect(written[file] == (try Data(contentsOf: demo.appendingPathComponent(file))), "\(file) is not as the writer writes it")
        }
        #expect(DemoCrate.isOpen)
        #expect(Library.shared.songCount == Credits.demoSongs.count)
        #expect(Library.shared.canRecognise)
        #expect(Library.shared.crate?.deckieSongs == Credits.demoSongs.count)
        // Every song in the crate is credited, by title and artist.
        let named = Set(Library.shared.data.tracks.map { "\($0.song)|\($0.artist)" })
        #expect(named == Set(Credits.demoSongs.map { "\($0.title)|\($0.artist)" }), "\(named.sorted())")
        Library.shared.close()
        #expect(!DemoCrate.isOpen)
        #expect(BoothScreen.current == .firstRun(demo: true))
    }

    @Test func theDemoSongsAreCreditedWithAnOpenLicence() {
        #expect(Credits.demoSongs.count >= 6)
        for s in Credits.demoSongs {
            #expect(!s.title.isEmpty && !s.artist.isEmpty)
            #expect(s.licenceURL == "https://creativecommons.org/publicdomain/zero/1.0/")
            #expect(URL(string: s.source)?.host == "freemusicarchive.org")
        }
        #expect(CreditsView().demoSongs == Credits.demoSongs)
    }

    // MARK: set recording

    /// Set recording is on until the DJ turns it off (the REC chip's menu), and the choice outlasts a relaunch.
    @MainActor @Test func setRecordingIsOnByDefaultAndRemembered() {
        let d = UserDefaults.standard, key = Recognizer.recordingKey
        let before = d.object(forKey: key)
        defer { if let before { d.set(before, forKey: key) } else { d.removeObject(forKey: key) } }
        d.removeObject(forKey: key)
        #expect(Recognizer().recordingOn)
        let r = Recognizer()
        r.setRecording(false)
        #expect(!r.recordingOn && !r.recActive)
        #expect(!Recognizer().recordingOn)
        r.setRecording(true)
        #expect(Recognizer().recordingOn)
    }

    // MARK: the words

    @Test func phrasesKeepTheirLastTwoWordsTogether() {
        let s = Words.phrases("Booth listens to the room,", "and how to mix it in.")
        #expect(s == "Booth listens to the\u{00A0}room,\nand how to mix it\u{00A0}in.")
        #expect(Words.keepLastTwo("Single") == "Single")
        for line in (Words.firstRunWhat + "\n" + Words.tryTheDemoNote + "\n" + Words.demoHow + "\n" + Words.creditsDemoNote + "\n" + Words.recWhere + "\n" + Words.firstRunSteps.map { $0.title + "\n" + $0.note }.joined(separator: "\n"))
                .split(separator: "\n") where line.contains(" ") || line.contains("\u{00A0}") {
            #expect(line.contains("\u{00A0}"), "\(line) can end on one word")
        }
    }

    @Test func theFirstRunWordsKeepToTheVocabulary() {
        let all = ([Words.firstRunWaiting, Words.firstRunWhat, Words.openACrateFile, Words.tryTheDemo, Words.firstRunPrivacy,
                    Words.creditsNoneYet, Words.creditsPrivacy, Words.tryTheDemoNote, Words.demoHow, Words.leaveTheDemo,
                    Words.demoOpened(songs: 7), Words.creditsDemoSection, Words.creditsDemoNote,
                    Words.recOn, Words.recOff, Words.recPaused, Words.recordSets, Words.recWhere, Words.pauseRecording, Words.resumeRecording] + Words.firstRunSteps.flatMap { [$0.title, $0.note] })
            .joined(separator: " ").lowercased()
        #expect(!all.contains("track"))
        #expect(!all.contains(" ai ") && !all.contains("ai."))
        #expect(Words.siteURL.host == "deckie.io")
    }

    // MARK: opening a crate file

    /// Each form (package, single file) under each extension (.deckie, the earlier .deckiecrate) opens: copied or
    /// unpacked into a store of its own, read whole, and then the booth shows the tabs.
    @Test(arguments: [("example.deckiecrate", "deckie"), ("example.deckiecrate", "deckiecrate"),
                      ("example-single.deckiecrate", "deckie"), ("example-single.deckiecrate", "deckiecrate")])
    func aCrateFileOpensInEitherFormUnderEitherExtension(fixture: String, ext: String) throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("booth-tests-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: work)
            UserDefaults.standard.removeObject(forKey: "cratePath")
        }
        let given = work.appendingPathComponent("Example.\(ext)")
        try fm.copyItem(at: Self.fixtures.appendingPathComponent(fixture), to: given)
        let store = work.appendingPathComponent("Crates", isDirectory: true)

        let r = try Library.shared.open(crateFile: given, into: store)
        #expect(r.wasSingleFile == fixture.contains("single"))
        #expect(r.package.path.hasPrefix(store.path))
        #expect(Library.shared.crate != nil)
        #expect(Library.shared.data.tracks.count == 5)
        #expect(BoothScreen.now(crateOpen: Library.shared.crate != nil, demoBundled: false) == .crate)
        // The fixtures carry no fingerprints: the booth opens them and sets songs by hand.
        #expect(!Library.shared.canRecognise)
        // The file the DJ gave is only read.
        #expect(fm.fileExists(atPath: given.path))
    }
}
