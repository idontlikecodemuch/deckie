import Foundation
import Testing
@testable import Deck

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

    @Test func noDemoAndNoPartyDataShipInTheApp() {
        #expect(DemoCrate.url() == nil)
        for (name, ext) in [("deck_data", "json"), ("overview", "json"), ("mixmap", "html"), ("Deck", "shazamcatalog")] {
            #expect(Bundle.main.url(forResource: name, withExtension: ext) == nil, "\(name).\(ext) is in the app")
        }
        #expect(Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") != nil)
    }

    // MARK: the words

    @Test func phrasesKeepTheirLastTwoWordsTogether() {
        let s = Words.phrases("Booth listens to the room,", "and how to mix it in.")
        #expect(s == "Booth listens to the\u{00A0}room,\nand how to mix it\u{00A0}in.")
        #expect(Words.keepLastTwo("Single") == "Single")
        for line in (Words.firstRunWhat + "\n" + Words.firstRunSteps.map { $0.title + "\n" + $0.note }.joined(separator: "\n"))
                .split(separator: "\n") where line.contains(" ") || line.contains("\u{00A0}") {
            #expect(line.contains("\u{00A0}"), "\(line) can end on one word")
        }
    }

    @Test func theFirstRunWordsKeepToTheVocabulary() {
        let all = ([Words.firstRunWaiting, Words.firstRunWhat, Words.openACrateFile, Words.tryTheDemo, Words.firstRunPrivacy,
                    Words.creditsNoneYet, Words.creditsPrivacy] + Words.firstRunSteps.flatMap { [$0.title, $0.note] })
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
