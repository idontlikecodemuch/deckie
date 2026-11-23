import AppKit
import SwiftUI

/// "Deckie Desk" --film-walk <out folder> [crate]: the stills of the Mac's window the site's film uses, with no one at
/// the keyboard: the crate's songs as they open; the Sources panel with the first source's first folder selected; then
/// Booth, with the engine's stand-in input when DECKIE_BOOTH_SOUND names one (Booth.swift), a frame a second while it
/// gets ready, listens and names the song. Frames are the window drawn by the app itself (Snapshot.capture); with Screen
/// Recording allowed for Deckie Desk they are the window server's whole window, toolbar included.
@MainActor
enum FilmWalk {
    static var request: (out: String, crate: String?)? {
        let a = CommandLine.arguments
        guard a.count >= 3, a[1] == "--film-walk" else { return nil }
        return (a[2], a.count >= 4 ? a[3] : nil)
    }

    static func run(model: DeskModel, out: String) {
        Snapshot.prepare(out: out)
        var t = 1.5
        func step(_ d: Double, _ f: @escaping () -> Void) {
            t += d
            DispatchQueue.main.asyncAfter(deadline: .now() + t) { MainActor.assumeIsolated { f() } }
        }
        step(0) { Snapshot.sizeWindow(); model.selection = []; model.showSources = false }
        step(1.2) { Snapshot.capture("songs", hold: 1) }
        if let d = model.crate?.discPlan.first, let f = d.folders.first {
            step(0.3) { model.showSources = true; model.sourceSelection = .folder(source: d.name, folder: f.name) }
            step(1.0) { Snapshot.capture("sources", hold: 1) }
        }
        step(0.3) { model.showSources = false; model.sourceSelection = nil; model.boothOn = true; print("walk: Booth on") }
        for i in 0..<24 { step(1.0) { Snapshot.capture("booth\(i)", hold: 1); print("walk: booth at \(i + 1) s") } }
        step(0.3) { model.boothOn = false }
        step(1.0) { Snapshot.finish() }
    }
}
