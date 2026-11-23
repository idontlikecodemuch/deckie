import Foundation
import Testing
@testable import DeckieDesk

/// The quick start (D46): the card on the first screen until the DJ hides it, remembered in Desk's storage (a scratch
/// folder here, never the real one); the film never starting by itself while the switch is off; the engine's hello
/// and its two requests; the film and poster bundled beside the pages, within the budget; and the words both windows
/// share, including the steps shown when the film cannot play.
@Suite struct QuickStartTests {
    static func home(_ name: String) throws -> DeskHome { DeskHome(root: try scratch(name).appendingPathComponent("desk")) }

    @Test func aDeskNeverOpenedOffersTheCardAndDoesNotStartTheFilm() throws {
        let home = try Self.home("qs-fresh")
        let q = DeskQuickStart.load(home)
        #expect(q == DeskQuickStart(dismissed: false, played: false))
        #expect(q.offers)
        #expect(!q.playsItself())
        // The owner's switch: off. With it on, only the very first open starts the film.
        #expect(DeskQuickStart.playsItselfOnFirstOpen == false)
        #expect(q.playsItself(switchOn: true))
    }

    @Test func hidingTheCardIsRememberedAcrossOpens() throws {
        let home = try Self.home("qs-hide")
        try DeskQuickStart.dismiss(home)
        #expect(FileManager.default.fileExists(atPath: home.root.appendingPathComponent(DeskQuickStart.file).path))
        let again = DeskQuickStart.load(home)
        #expect(!again.offers)
        #expect(!again.playsItself(switchOn: true))
        // Twice is harmless.
        try DeskQuickStart.dismiss(home)
        #expect(!DeskQuickStart.load(home).offers)
    }

    @Test func aFilmPlayedOnceNeverStartsByItselfAgainButTheCardStays() throws {
        let home = try Self.home("qs-played")
        try DeskQuickStart.markPlayed(home)
        let q = DeskQuickStart.load(home)
        #expect(q.played && q.offers)
        #expect(!q.playsItself(switchOn: true))
    }

    @Test func aKeptFileThatDoesNotReadOffersTheCardAgain() throws {
        let home = try Self.home("qs-garbled")
        try FileManager.default.createDirectory(at: home.root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: home.root.appendingPathComponent(DeskQuickStart.file))
        #expect(DeskQuickStart.load(home).offers)
    }

    @Test func theEnginesHelloCarriesTheFilmAndTheRequestsRememberTheCard() throws {
        let home = try Self.home("qs-protocol")
        let out = Lines()
        let p = DeskProtocol(home: home, output: out.add, makeRun: AddMusicTests.noRun, analysisCheck: {})
        p.start()
        let hello = try #require(out.all.first { $0["event"] as? String == "hello" })
        let q = try #require(hello["quickStart"] as? [String: Any])
        #expect(q["film"] as? String == "quick-start/deckie-desk-quick-start.mp4")
        #expect(q["poster"] as? String == "quick-start/poster.jpg")
        #expect(q["seconds"] as? Int == DeskQuickStart.filmSeconds)
        #expect(q["offer"] as? Bool == true && q["playsItself"] as? Bool == false)

        p.handle(line: #"{"id": 1, "type": "quickStart.played"}"#)
        let played = try #require(out.all.first { ($0["re"] as? Int) == 1 })
        #expect(played["ok"] as? Bool == true)
        #expect((played["quickStart"] as? [String: Any])?["offer"] as? Bool == true)

        p.handle(line: #"{"id": 2, "type": "quickStart.dismiss"}"#)
        let hidden = try #require(out.all.first { ($0["re"] as? Int) == 2 })
        #expect(hidden["ok"] as? Bool == true)
        #expect((hidden["quickStart"] as? [String: Any])?["offer"] as? Bool == false)

        // Desk opened again on the same storage: the card is not offered.
        let out2 = Lines()
        let p2 = DeskProtocol(home: home, output: out2.add, makeRun: AddMusicTests.noRun, analysisCheck: {})
        p2.start()
        let hello2 = try #require(out2.all.first { $0["event"] as? String == "hello" })
        #expect((hello2["quickStart"] as? [String: Any])?["offer"] as? Bool == false)
        #expect(DeskQuickStart.load(home) == DeskQuickStart(dismissed: true, played: true))
    }

    // MARK: what ships

    static let repo: URL = VariablesTests.repo

    @Test func theFilmAndItsPosterAreBundledBesideThePagesWithinTheBudget() throws {
        let folder = Self.repo.appendingPathComponent("desk-web").appendingPathComponent(DeskQuickStart.folder)
        var total = 0
        for name in [DeskQuickStart.filmFile, DeskQuickStart.posterFile] {
            let attrs = try FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)
            let size = (attrs[.size] as? NSNumber)?.intValue ?? 0
            #expect(size > 10_000, "\(name) is there and not empty")
            total += size
        }
        // The brief's budget: 12 MB in all.
        #expect(total <= 12_000_000, "the quick start is \(total) bytes")
        // An MP4 (its 'ftyp' box) and a JPEG (its first two bytes).
        let film = try Data(contentsOf: folder.appendingPathComponent(DeskQuickStart.filmFile)).prefix(12)
        #expect(String(decoding: film.dropFirst(4).prefix(4), as: UTF8.self) == "ftyp")
        let poster = try Data(contentsOf: folder.appendingPathComponent(DeskQuickStart.posterFile)).prefix(2)
        #expect(Array(poster) == [0xFF, 0xD8])
    }

    @Test func thePagesOfferTheCardTheMenuItemAndTheFallBackAndMayPlayTheBundledFilm() {
        let html = VariablesTests.read("desk-web/index.html")
        for id in ["qs-card", "qs-play", "qs-offer", "qs-watch", "qs-hide", "qs-words", "qs-steps", "film", "film-video", "film-words", "film-steps"] {
            #expect(html.contains("id=\"\(id)\""), "index.html has #\(id)")
        }
        #expect(html.contains("<script src=\"quickstart.js\"></script>"))
        // The page may play a film from beside itself, and still fetches nothing.
        #expect(html.contains("media-src 'self' blob:") && html.contains("connect-src 'none'"))
        let js = VariablesTests.read("desk-web/desk.js")
        #expect(js.contains("t(\"quickStartMenu\")"), "the ⋯ menu has the quick start")
        #expect(js.contains("quickStart.firstScreen()"))
        let qs = VariablesTests.read("desk-web/quickstart.js")
        // Each way the film can fail turns to the steps: the web view says no, the film errs, it does not start in time.
        #expect(qs.contains("canPlayType"))
        #expect(qs.contains("video.addEventListener(\"error\", toWords)"))
        #expect(qs.contains("num(\"--qs-start-wait\")"))
        #expect(qs.contains("quickStart.dismiss") && qs.contains("quickStart.played"))
    }

    @Test func theWordsAreSharedAndTheStepsAreFour() {
        for key in ["quickStartOffer", "quickStartWatch", "quickStartPlay", "quickStartMenu", "quickStartTitle", "quickStartClose", "quickStartHide",
                    "quickStartHideHelp", "quickStartAt.menu", "quickStartAt.more", "quickStartInWords", "quickStartNoPlayer",
                    "quickStartStepLine", "stopAnyTime", "thenOpenInDeckie", "sendToIPadHow"] {
            #expect(DeskWords.table[key] != nil, "\(key)")
        }
        let steps = DeskWords.list("quickStartStep")
        #expect(steps.count == 4)
        #expect(steps.last?.contains("Booth") == true, "the last step is Booth in Desk, for a DJ with no iPad")
        #expect(DeskWords.text("quickStartNoPlayer").contains(DeskWords.text("thisComputer.\(DeskWords.computerKind)")))
    }

    /// D43: the iPad app is "Deckie" and Desk's mode is "Booth"; the old name of the iPad app is in none of Desk's words,
    /// its pages or the quick start's storyboard.
    @Test func theOldNameOfTheIPadAppIsNowhereInDeskOrTheQuickStart() {
        let old = "Deckie" + " Booth"
        for (key, value) in DeskWords.table { #expect(!value.contains(old), "\(key)") }
        for path in ["desk-web/index.html", "desk-web/desk.js", "desk-web/quickstart.js", "desk-quickstart/storyboard.md",
                     "desk-quickstart/film.js"] {
            #expect(!VariablesTests.read(path).contains(old), "\(path)")
        }
    }
}
