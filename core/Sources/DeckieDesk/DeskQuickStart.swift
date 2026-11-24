import Foundation
import DeckieCrate

/// Desk's quick start (D46): a silent film of about a minute, bundled with the app (nothing is fetched), offered on the
/// first screen as a card the DJ starts, and played again from the Help menu (the Mac) or the "…" menu (Windows and
/// Linux). The film is made from Desk's own pages (`desk-quickstart/`); the 720p file and its poster live in
/// `desk-web/quick-start/`, which the Windows and Linux pages show from beside themselves and the Mac app copies into
/// its resources.
///
/// What Desk remembers about it is one small file in Desk's storage, beside `libraries.json` (`DeskHome`):
///
///     quick-start.json     {"dismissed": true, "played": true}
///
/// `dismissed`: the DJ closed the card, so the first screen no longer offers the film (the menu still does).
/// `played`: the film has been started once, by the DJ or by itself. Both start false: a Desk that has never been
/// opened offers the card.
public struct DeskQuickStart: Codable, Equatable, Sendable {
    public var dismissed: Bool
    public var played: Bool

    public init(dismissed: Bool = false, played: Bool = false) { self.dismissed = dismissed; self.played = played }

    /// Whether the film plays by itself the very first time Desk opens (it never does again). Off by the owner's
    /// brief of Nov 21, 2026: the DJ starts it. One switch for both windows; flip it here only.
    public static let playsItselfOnFirstOpen = false

    /// The folder the film and its poster are in, beside the pages (and in the Mac app's resources), and their names.
    public static let folder = "quick-start"
    public static let filmFile = "deckie-desk-quick-start.mp4"
    public static let posterFile = "poster.jpg"
    /// The card's own picture (Nov 24, 2026): the poster is the film's title frame, whose words cannot be read at card
    /// size and sat under the play button, so the card shows a picture with nothing to read behind the button
    /// (`desk-quickstart/card-poster.sh`). The player, and the card when the film cannot play, keep the poster.
    public static let cardFile = "card.jpg"
    /// The film's length in whole seconds, for the words that say how long it is ("1 minute").
    public static let filmSeconds = 58

    public static let file = "quick-start.json"

    /// What was kept, or a fresh start when nothing was (or the file does not read: the card is offered again, which
    /// is the harmless way to be wrong).
    public static func load(_ home: DeskHome) -> DeskQuickStart {
        JSONFile.read(Self.self, from: home.root.appendingPathComponent(file)) ?? DeskQuickStart()
    }

    public func save(_ home: DeskHome) throws {
        try DeckieFiles.createDirectory(home.root)
        try JSONFile.write(self, to: home.root.appendingPathComponent(Self.file))
    }

    /// Whether the first screen shows the card.
    public var offers: Bool { !dismissed }

    /// Whether the film should start by itself now: only with the switch on, and only before it has ever played or the
    /// card was closed.
    public func playsItself(switchOn: Bool = DeskQuickStart.playsItselfOnFirstOpen) -> Bool {
        switchOn && !played && !dismissed
    }

    /// The card closed: remembered, so the first screen stops offering it.
    public static func dismiss(_ home: DeskHome) throws {
        var q = load(home)
        guard !q.dismissed else { return }
        q.dismissed = true
        try q.save(home)
    }

    /// The film started: remembered, so it never plays by itself again.
    public static func markPlayed(_ home: DeskHome) throws {
        var q = load(home)
        guard !q.played else { return }
        q.played = true
        try q.save(home)
    }

    /// The film's facts as the engine's first message carries them to the pages (`hello.quickStart`, an addition to
    /// protocol 2): where the film and its poster are, relative to the pages, its length, whether to offer the card and
    /// whether to start the film by itself. `cardPicture` (added Nov 24, 2026, by addition only) is the card's own
    /// picture; a page that does not know it, or cannot load it, shows `poster` on the card as before.
    public static func hello(_ home: DeskHome) -> [String: Any] {
        let q = load(home)
        return ["film": folder + "/" + filmFile, "poster": folder + "/" + posterFile, "cardPicture": folder + "/" + cardFile,
                "seconds": filmSeconds, "offer": q.offers, "playsItself": q.playsItself()]
    }
}
