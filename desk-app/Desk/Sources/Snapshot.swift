import AppKit
import SwiftUI

/// "Deckie Desk" --snapshot <crate.deckiecrate> <out folder>: open the crate in the window, step through it the way a
/// DJ would (arrow down the list, look at a track, open the import log) and write a PNG of the window at each step,
/// plus an ffmpeg concat list with how long each frame holds. The app draws its own windows, so no screen-recording
/// permission is involved; then it quits. Made for showing the app when nobody is at the Mac. The Mac must be unlocked
/// for whole-window frames; DECKIE_SNAP_ROWS=<n> changes how many rows the walk goes down (12 by default).
@MainActor
enum Snapshot {
    static var request: (crate: String, out: String)? {
        let a = CommandLine.arguments
        return a.count >= 4 && a[1] == "--snapshot" ? (a[2], a[3]) : nil
    }

    private static var frames: [(name: String, hold: Double)] = []
    private static var outDir = URL(fileURLWithPath: ".")

    static func run(model: DeskModel, out: String) {
        outDir = URL(fileURLWithPath: out)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        var steps: [(delay: Double, action: () -> Void)] = []
        var t = 1.2
        func step(after d: Double, _ f: @escaping () -> Void) { t += d; steps.append((t, f)) }

        step(after: 0) {
            if let w = window { w.setContentSize(NSSize(width: 1280, height: 800)); w.center() }
        }
        step(after: 0.8) { capture("open", hold: 1.6) }
        let n = min(model.crate?.tracks.count ?? 0, ProcessInfo.processInfo.environment["DECKIE_SNAP_ROWS"].flatMap(Int.init) ?? 12)
        for i in 0..<n {
            step(after: 0.45) {
                if let id = model.crate?.tracks[i].id { model.selection = [id] }
            }
            step(after: 0.35) { capture("row\(i)", hold: i == n - 1 ? 2.2 : 0.4) }
        }
        step(after: 0.2) { model.showImportLog = true }
        step(after: 1.0) { capture("log", hold: 2.6, withSheet: true) }
        step(after: 0.2) { model.showImportLog = false }
        step(after: 0.8) { capture("end", hold: 1.6) }
        step(after: 0.3) { finish() }

        for s in steps { let f = s.action; DispatchQueue.main.asyncAfter(deadline: .now() + s.delay) { MainActor.assumeIsolated { f() } } }
    }

    private static var window: NSWindow? { NSApp.windows.first { $0.isVisible && $0.contentView != nil && !$0.isSheet } }

    private static func capture(_ name: String, hold: Double, withSheet: Bool = false) {
        guard let w = window else { print("no window"); return }
        var ids: [CGWindowID] = [CGWindowID(w.windowNumber)]
        if withSheet, let s = w.attachedSheet { ids.append(CGWindowID(s.windowNumber)) }
        // Screen-space rect of the main window, in CG's top-left-origin coordinates.
        let screenH = NSScreen.screens.first?.frame.height ?? 0
        let f = w.frame
        let rect = CGRect(x: f.minX, y: screenH - f.maxY, width: f.width, height: f.height)
        var image = CGImage(windowListFromArrayScreenBounds: rect, windowArray: ids as CFArray, imageOption: [.bestResolution])
        if image == nil, ids.count == 1 {
            image = CGImage(windowListFromArrayScreenBounds: .null, windowArray: ids as CFArray, imageOption: [.boundsIgnoreFraming, .bestResolution])
        }
        let file = "\(String(format: "%02d", frames.count))_\(name).png"
        let url = outDir.appendingPathComponent(file)
        if let image, image.width > 1 {
            let rep = NSBitmapImageRep(cgImage: image)
            if let png = rep.representation(using: .png, properties: [:]) {
                do { try png.write(to: url); frames.append((file, hold)); print("frame \(file) \(image.width)x\(image.height) via window server"); return }
                catch { print("write failed: \(error)") }
            }
        }
        // Fallback while the screen is locked (the window server then gives nothing, even to the window's own app): the
        // frame view draws itself. That picture has the table and the title bar but not the SwiftUI-drawn parts (toolbar
        // items, selection highlight, inspector) nor a sheet, so it is a still of the table, not the window.
        guard let v = w.contentView?.superview ?? w.contentView else { print("no view for \(name)"); return }
        guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { print("no image for \(name)"); return }
        v.cacheDisplay(in: v.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url); frames.append((file, hold)); print("frame \(file) \(rep.pixelsWide)x\(rep.pixelsHigh) via cacheDisplay (table only; unlock the Mac for the whole window)")
        }
    }

    private static func finish() {
        var list = ""
        for f in frames { list += "file '\(f.name)'\nduration \(f.hold)\n" }
        if let last = frames.last { list += "file '\(last.name)'\n" }
        try? list.write(to: outDir.appendingPathComponent("list.txt"), atomically: true, encoding: .utf8)
        print("\(frames.count) frames written to \(outDir.path)")
        exit(0)
    }
}
