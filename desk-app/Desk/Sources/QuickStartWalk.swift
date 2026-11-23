import AppKit
import AVKit
import SwiftUI
import DeckieDesk

/// "Deckie Desk" --quick-start-walk <out folder>: the quick start where a DJ meets it on the Mac (D46), walked through
/// with no one at the keyboard, saying what it finds and writing a PNG of the window at each step (Snapshot.capture):
/// the first screen with the card, at the usual size and at the window's smallest; the film in its sheet, started as
/// the card's play button starts it, with what the player reports (the item's status, the film's size, the time going
/// on); Help > Watch the quick start, found in the menu bar and pressed; then Hide, and the first screen after it, and
/// what `quick-start.json` says. Run it with DECKIE_DESK_HOME set to a fresh scratch folder (it hides the card there).
/// A window drawn by the app itself shows no video and none of the toolbar's glass (Snapshot.layerImage); the
/// player's own report says whether the film plays.
@MainActor
enum QuickStartWalk {
    static var request: String? {
        let a = CommandLine.arguments
        return a.count >= 3 && a[1] == "--quick-start-walk" ? a[2] : nil
    }

    private static weak var model: DeskModel?

    static func run(model: DeskModel, out: String) {
        Self.model = model
        Snapshot.prepare(out: out)
        func say(_ s: String) { print("walk: " + s) }
        var t = 1.5
        func step(_ d: Double, _ f: @escaping () -> Void) {
            t += d
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { MainActor.assumeIsolated { f() } }
        }
        var window: NSWindow? { NSApp.windows.first { $0.isVisible && $0.contentView != nil && !$0.isSheet } }

        step(0) {
            Snapshot.sizeWindow()
            say("film file: \(QuickStartFiles.film?.lastPathComponent ?? "missing"); poster: \(QuickStartFiles.poster?.lastPathComponent ?? "missing")")
            say("card offered: \(model.quickStart.offers); film plays (before the check): \(model.filmPlays)")
        }
        step(1.5) {
            say("film plays (after the check): \(model.filmPlays)")
            Snapshot.capture("card", hold: 1)
            report(window, say)
        }
        // The smallest window the app allows: does the card push the ways in off the screen?
        step(0.5) { window?.setContentSize(NSSize(width: Look.Size.windowMinWidth, height: Look.Size.windowMinHeight)) }
        step(1.0) { Snapshot.capture("card-smallest", hold: 1); report(window, say) }
        step(0.5) { Snapshot.sizeWindow() }
        // The film, as the play button starts it.
        step(1.0) { model.showFilm = true }
        step(2.5) { Snapshot.capture("player", hold: 1, withSheet: true); player(window, say) }
        step(3.0) { player(window, say) }
        step(0.2) { model.showFilm = false }
        // Help > Watch the quick start, from the menu bar.
        step(1.0) {
            let help = NSApp.helpMenu ?? NSApp.mainMenu?.items.first { $0.title == "Help" }?.submenu
            let titles = help?.items.map { $0.isSeparatorItem ? "—" : $0.title } ?? []
            say("Help menu: \(titles)")
            if let m = help, let i = m.items.firstIndex(where: { $0.title == Words.t("quickStartMenu") }) {
                m.performActionForItem(at: i)
                say("pressed Help > \(m.items[i].title)")
            } else { say("no \(Words.t("quickStartMenu")) in the Help menu") }
        }
        step(2.5) { Snapshot.capture("player-from-help", hold: 1, withSheet: true); player(window, say) }
        step(0.2) { model.showFilm = false }
        // Hide.
        step(1.0) {
            model.hideQuickStart()
            say("hidden; card offered: \(model.quickStart.offers)")
            let f = model.home.root.appendingPathComponent("quick-start.json")
            say("quick-start.json: \((try? String(contentsOf: f, encoding: .utf8))?.replacingOccurrences(of: "\n", with: " ") ?? "none")")
        }
        step(1.0) { Snapshot.capture("after-hide", hold: 1); report(window, say) }
        step(0.5) { Snapshot.finish() }
    }

    /// Where the first screen's last line sits against the window's content: anything below the bottom is cut off.
    static func report(_ w: NSWindow?, _ say: (String) -> Void) {
        guard let w, let v = w.contentView, let m = model else { return }
        let first = NSHostingView(rootView: FirstScreen().environmentObject(m).frame(width: v.bounds.width))
        let need = first.fittingSize.height, room = v.bounds.height - (w.contentLayoutRect.minY == 0 ? v.bounds.height - w.contentLayoutRect.height : 0)
        say("window content \(Int(v.bounds.width))x\(Int(w.contentLayoutRect.height)) pt below the toolbar; the first screen needs \(Int(need)) pt"
            + (need > w.contentLayoutRect.height ? ": it scrolls" : ": it fits") + " (room \(Int(room)))")
    }

    /// What the sheet's player says: its item's status, the film's size and where it is.
    static func player(_ w: NSWindow?, _ say: (String) -> Void) {
        guard let sheet = w?.attachedSheet else { say("no sheet showing"); return }
        func find(_ v: NSView) -> AVPlayerView? {
            if let p = v as? AVPlayerView { return p }
            for s in v.subviews { if let p = find(s) { return p } }
            return nil
        }
        say("sheet \(Int(sheet.frame.width))x\(Int(sheet.frame.height)) pt")
        guard let root = sheet.contentView, let pv = find(root), let p = pv.player, let item = p.currentItem else {
            say("no player in the sheet (the steps in words instead)"); return
        }
        let status = ["unknown", "readyToPlay", "failed"][item.status.rawValue]
        say("player: item \(status), film \(Int(item.presentationSize.width))x\(Int(item.presentationSize.height)), at \(String(format: "%.2f", item.currentTime().seconds)) s, rate \(p.rate)\(item.error.map { ", error \($0.localizedDescription)" } ?? "")")
    }
}
