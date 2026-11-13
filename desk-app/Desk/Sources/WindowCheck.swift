import AppKit
import SwiftUI
import DeckieCrate
import DeckieDesk

/// "Deckie Desk" --window-check <out folder> <folder or drive to add>: a scripted pass through the window, for when
/// nobody is at the Mac. It adds the music to the crate showing (or a new one) through the window's own model, waits
/// for the finished screen, then makes a name fix, a source rename and a source removal and undoes and redoes each with
/// the window's own undo manager, saying what it saw at each step and writing a PNG of the window at the main ones
/// (whole-window frames only when the Mac is unlocked; see Snapshot). Then it quits. It changes the crate showing, so it
/// is run with DECKIE_DESK_HOME set to a scratch folder.
@MainActor
enum WindowCheck {
    static var request: (out: String, add: String)? {
        let a = CommandLine.arguments
        return a.count >= 4 && a[1] == "--window-check" ? (a[2], a[3]) : nil
    }

    static func run(model: DeskModel, out: String, add: String) {
        Snapshot.prepare(out: out)
        func say(_ s: String) { print("check: " + s) }
        func later(_ d: Double, _ f: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: .now() + d) { MainActor.assumeIsolated { f() } }
        }
        func waitRun(_ then: @escaping () -> Void) {
            if model.running { later(0.5) { waitRun(then) } } else { then() }
        }
        later(1.5) {
            Snapshot.sizeWindow()
            say("showing \(model.current?.name ?? "the first screen"), \(model.crates.count) crates, undo manager \(model.undoManager == nil ? "missing" : "there")")
            Snapshot.capture("start", hold: 1.5)
            let url = URL(fileURLWithPath: add)
            model.addSource(url, name: MountedSource.name(of: url))
            later(0.8) { Snapshot.capture("running", hold: 1.5) }
            later(1.0) { waitRun(afterRun) }
        }
        func afterRun() {
            guard let r = model.finished else { say("no finished screen: \(model.errorText ?? "?")"); Snapshot.finish(); return }
            say("finished screen: \(Words.finishedTitle(r.read, r.crate)); \(Words.wentIn(r.wentIn)) \(r.notInCount) didn't; \(Words.took(r.seconds, perMinute: r.songsPerMinute))")
            say("crate menu: \(model.crates.map(\.name)), showing \(model.current?.name ?? "-")")
            later(0.6) { Snapshot.capture("finished", hold: 2.5) }
            later(1.2) { model.finished = nil }
            later(1.8) { Snapshot.capture("crate", hold: 2) }
            later(2.0) { edits() }
        }
        func edits() {
            guard let c = model.crate, let t = c.tracks.first else { say("no songs"); Snapshot.finish(); return }
            let id = t.id, was = t.ident.title
            model.selection = [id]
            model.update(id) { $0.ident.title = was + " (fixed in the window)" }
            say("name fix: \(model.binding(for: id)?.ident.title ?? "?")")
            model.undoManager?.undo()
            say("after undo: \(model.binding(for: id)?.ident.title ?? "?") (undo menu: \(model.undoManager?.redoMenuItemTitle ?? "-"))")
            model.undoManager?.redo()
            say("after redo: \(model.binding(for: id)?.ident.title ?? "?")")
            later(0.8) {
                Snapshot.capture("fixed", hold: 2)
                let fixes = NameCorrections.load(from: model.shelf.file(DeskRun.correctionsFile, of: model.current!.id))
                say("saved fix: \(fixes.byId[id]?.title ?? "none")")
                let onDisk = try? CrateReader.read(from: model.shelf.package(model.current!.id))
                say("crate file on disk: \(onDisk?.tracks.first { $0.id == id }?.ident.title ?? "?")")
                sources()
            }
        }
        func sources() {
            guard let s = model.crate?.discPlan.first?.name else { say("no source"); Snapshot.finish(); return }
            model.showSources = true
            model.renameSource(s, to: s + " renamed")
            say("rename: sources \(model.crate?.discPlan.map(\.name) ?? [])")
            model.undoManager?.undo()
            say("after undo: sources \(model.crate?.discPlan.map(\.name) ?? [])")
            let before = model.crate?.tracks.count ?? 0
            let going = model.crate?.entriesOnlyOn(source: s).count ?? 0
            say("remove confirmation: \(Words.removeTitle(s, model.current?.name ?? "")) \(Words.removeBody(going))")
            model.removeSource(s)
            say("removed: \(before) songs, now \(model.crate?.tracks.count ?? 0)")
            later(0.6) { Snapshot.capture("removed", hold: 2) }
            later(1.0) {
                model.undoManager?.undo()
                say("after undo: \(model.crate?.tracks.count ?? 0) songs")
                model.undoManager?.redo()
                say("after redo: \(model.crate?.tracks.count ?? 0) songs")
                model.undoManager?.undo()
                say("after undo again: \(model.crate?.tracks.count ?? 0) songs")
                model.sendToIPad()
                let box = model.home.outbox.appendingPathComponent((model.current?.name ?? "") + ".deckiecrate")
                say("send to iPad: \(FileManager.default.fileExists(atPath: box.path) ? "outbox has " + box.lastPathComponent : "no outbox copy")")
                later(1.0) { Snapshot.capture("share", hold: 2) }
                later(1.6) { model.saveNow(); Snapshot.finish() }
            }
        }
    }
}
