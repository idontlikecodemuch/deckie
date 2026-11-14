import Foundation
#if os(macOS)
import AppKit
import WebKit
#endif

/// `deckie-desk --tour <folder> --music <folder> --export-to <folder>`: walks every screen of the window with the
/// music given (generated songs; never a DJ's own), as a DJ would click through it, and writes a picture of each into
/// <folder>. The pictures come from the web view itself (WKWebView's snapshot), so they work with no screen recording
/// permission. The Mac only: the other systems have no snapshot here and run `--check` instead.
enum Tour {
    struct Step {
        var name: String?
        var js: String?
        /// Waits for an engine event of this name (after the step's script ran), else just `delay`.
        var event: String?
        var eventTest: (([String: Any]) -> Bool)?
        var delay: Double = 0.8
    }

    static func arm(_ desk: Desk, out: URL) {
        #if os(macOS)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let click = { (selector: String) in "document.querySelector(\(js(selector))).click();" }
        let steps: [Step] = [
            Step(name: "01-first-screen", delay: 2.0),
            Step(name: "02-add-music-menu", js: click("#add-button"), delay: 1.0),
            Step(name: "03-run", js: "[...document.querySelectorAll('#add-menu [role=menuitem]')].pop().click();",
                 event: "run.progress", eventTest: { (($0["done"] as? NSNumber)?.intValue ?? 0) >= 2 }, delay: 0.3),
            Step(name: "04-finished", event: "run.finished", delay: 1.2),
            Step(name: "05-exported", js: click("#finished-export"), delay: 2.0),
            Step(name: "06-songs", js: click("#finished-songs"), delay: 1.0),
            Step(name: "07-needs-a-name", js: click("#status-needname"), delay: 0.8),
            Step(name: nil, js: click("#status-needname"), delay: 0.5),
            Step(name: "08-name-fix-in-place", js: """
                var td = [...document.querySelectorAll('#songs-body td[data-col=title]')].find(function (c) { return c.textContent === 'Night Drive'; });
                td.dispatchEvent(new MouseEvent('dblclick', { bubbles: true }));
                td.querySelector('input').value = 'Night Drive (Club Mix)';
                """, delay: 0.6),
            Step(name: "09-name-fixed", js: """
                document.querySelector('#songs-body td input').dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', bubbles: true }));
                """, event: "songs", delay: 0.8),
            Step(name: "10-sources-panel", js: click("#sources-button"), delay: 1.0),
            Step(name: "11-remove-source", js: click(".tree .src .danger"), delay: 1.0),
            Step(name: nil, js: "document.getElementById('confirm').close('cancel');", delay: 0.4),
            Step(name: "12-crate-menu", js: click("#crate-button"), delay: 0.8),
            Step(name: "13-rename-crate", js: "[...document.querySelectorAll('#crate-menu [role=menuitem]')].find(function (b) { return b.textContent.indexOf('Rename') === 0; }).click();", delay: 0.8),
            Step(name: nil, js: "document.getElementById('ask').close('cancel');", delay: 0.4),
            Step(name: "14-what-didnt-go-in", js: click("#log-button"), delay: 0.8),
            Step(name: nil, js: "document.getElementById('log').close('ok');", delay: 0.4),
            Step(name: "15-more-menu", js: click("#more-button"), delay: 0.8),
            Step(name: nil, js: click("#more-button"), delay: 0.3),
            Step(name: "16-undo-named", js: click("#side-close"), delay: 0.6),
            Step(name: "17-new-crate", js: "desk.request('crate.new');", event: "state", delay: 1.0),
        ]
        var events: [[String: Any]] = []
        let lock = NSLock()
        desk.watchers.append { line in
            guard let m = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
            lock.lock(); events.append(m); lock.unlock()
        }
        func say(_ s: String) { FileHandle.standardError.write(Data(("[tour] " + s + "\n").utf8)) }

        func run(_ i: Int) {
            guard i < steps.count else {
                say("done: \(steps.compactMap(\.name).count) pictures in \(out.path)")
                desk.engine?.stop()
                exit(0)
            }
            let step = steps[i]
            lock.lock(); let mark = events.count; lock.unlock()
            if let js = step.js { desk.window.eval("try { \(js) } catch (e) { console.error(e); }") }
            Thread.detachNewThread {
                if let event = step.event {
                    let end = Date().addingTimeInterval(600)
                    while Date() < end {
                        lock.lock(); let seen = events[mark...].contains { $0["event"] as? String == event && (step.eventTest?($0) ?? true) }; lock.unlock()
                        if seen { break }
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                }
                Thread.sleep(forTimeInterval: step.delay)
                desk.window.onWindowThread {
                    guard let name = step.name else { run(i + 1); return }
                    snapshot(desk, to: out.appendingPathComponent(name + ".png")) { ok in
                        say((ok ? "wrote " : "could not write ") + name)
                        run(i + 1)
                    }
                }
            }
        }
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 1.0)
            desk.window.onWindowThread { run(0) }
        }
        #else
        FileHandle.standardError.write(Data("deckie-desk: --tour takes pictures on the Mac only\n".utf8))
        exit(1)
        #endif
    }

    static func js(_ s: String) -> String {
        let d = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        return String(String(decoding: d, as: UTF8.self).dropFirst().dropLast())
    }

    #if os(macOS)
    static func snapshot(_ desk: Desk, to url: URL, done: @escaping (Bool) -> Void) {
        guard let p = desk.window.nativeView else { done(false); return }
        let view = Unmanaged<WKWebView>.fromOpaque(p).takeUnretainedValue()
        view.takeSnapshot(with: nil) { image, _ in
            guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { done(false); return }
            done((try? png.write(to: url)) != nil)
        }
    }
    #endif
}
