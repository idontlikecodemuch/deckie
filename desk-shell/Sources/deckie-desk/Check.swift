import Foundation

/// `deckie-desk --check`: the window, the engine and the pages together, with no one at the keyboard. It passes when
/// the page loaded, drew a screen in the engine's words, and a request sent from the page (the list of drives) came
/// back through the shell and the engine. It says what the page showed, and how long after the program started the
/// page showed the engine's words (the start-up time).
///
/// With `--music <folder> --export-to <folder>` it then carries on as a DJ would, through the page's own buttons:
/// Add music (the folder chooser answers with the music folder), the run to its end, Export crate file (the chooser
/// answers with the second folder). It passes when the engine says where it wrote the crate file and the file is
/// there. Nothing is done behind the page's back: every step is a click in the page.
enum Check {
    static func arm(_ desk: Desk, seconds: Double, music: String?, exportTo: String?) {
        let started = Notice.started
        @Sendable func say(_ s: String) {
            Notice.say(String(format: "[check %.2fs] ", Date().timeIntervalSince(started)) + s)
        }
        func end(_ code: Int32) -> Never {
            desk.engine?.stop()
            exit(code)
        }
        func eval(_ js: String) { desk.window.eval("try { \(js) } catch (e) { deckieShell.send(JSON.stringify({ type: 'shell.checkError', detail: String(e) })); }") }
        /// Runs `js` in the page once `ready` (a JavaScript expression) is true there, looking every 25 ms.
        func evalWhen(_ ready: String, _ js: String) {
            desk.window.eval("""
                (function look() {
                  try { if (!(\(ready))) { setTimeout(look, 25); return; } \(js) }
                  catch (e) { deckieShell.send(JSON.stringify({ type: 'shell.checkError', detail: String(e) })); }
                })();
                """)
        }
        let fullRun = music != nil && exportTo != nil
        // What has happened so far. Written on the window's thread; the time limit's thread only reads it to say
        // how far the check got.
        final class Seen: @unchecked Sendable { var hello = false, drawn = false, exportAsked = false, finished = false }
        let seen = Seen()

        say("window made with \(Window.engineName); its own icon on the window: \(desk.window.hasIcon ? "yes" : "no")")
        desk.watchers.append { line in
            guard let m = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
            switch m["event"] as? String {
            case "hello":
                seen.hello = true
                say("engine said hello: protocol \(m["protocol"] ?? "?"), platform \(m["platform"] ?? "?"), analysis \(m["analysis"] ?? "?")")
            case "run.started":
                say("run started: reading \"\(m["read"] ?? "?")\" into crate \"\(m["crateName"] ?? "?")\"")
            case "run.failed":
                say("FAILED: the run stopped: \(m["detail"] ?? "?")")
                end(3)
            case "run.finished":
                guard fullRun, !seen.finished else { return }
                seen.finished = true
                let report = m["report"] as? [String: Any] ?? [:]
                say("run finished: \(report["went_in"] ?? "?") of \(report["songs_seen"] ?? "?") files went in, \(report["songs_in_crate"] ?? "?") songs in the crate, in \(report["seconds"] ?? "?") s")
                // The finished screen, then its Export button, as soon as the page shows it.
                evalWhen("!document.getElementById('finished').hidden && document.getElementById('finished-summary').textContent", """
                    deckieShell.send(JSON.stringify({ type: 'shell.checkFinished',
                      summary: document.getElementById('finished-summary').innerText }));
                    document.getElementById('finished-export').click();
                    """)
                seen.exportAsked = true
            default:
                // The reply to the page's crate.export: where the crate file was written.
                guard seen.exportAsked, m["re"] != nil else { return }
                if m["ok"] as? Bool == false {
                    say("FAILED: a request was refused: \(m["error"] ?? "?")")
                    end(3)
                }
                guard let path = m["path"] as? String, path.hasSuffix(".deckiecrate") else { return }
                var isFolder: ObjCBool = false
                let there = FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
                let size = ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.intValue ?? -1
                say("crate file exported: \(path) (\(there ? (isFolder.boolValue ? "a folder" : "one file, \(size) bytes") : "NOT THERE"))")
                say(there ? "PASSED: music added through the page, the run finished, and the crate file was exported"
                          : "FAILED: the engine named a crate file that is not there")
                end(there ? 0 : 3)
            }
        }
        desk.pageWatchers.append { m in
            switch m["type"] as? String {
            case "shell.ready":
                // The page has loaded and listens. As soon as it has drawn a screen in the engine's words (they
                // arrive in the engine's first message), it says what it shows.
                say("page loaded")
                evalWhen("""
                    (function () { var s = document.querySelector('main > section:not([hidden])'); var h = s && s.querySelector('h1');
                      return h && h.textContent && document.getElementById('add-label').textContent; })()
                    """, """
                    var shown = document.querySelector('main > section:not([hidden])');
                    deckieShell.send(JSON.stringify({ type: 'shell.drawn', screen: shown.id,
                      heading: shown.querySelector('h1').textContent, button: document.getElementById('add-label').textContent,
                      engine: deckieShell.engine }));
                    desk.request('drives.list', {}, { quiet: true }).then(function (r) {
                      deckieShell.send(JSON.stringify({ type: 'shell.checked', drives: r.ok ? r.drives.length : -1 }));
                    });
                    """)
            case "shell.drawn":
                seen.drawn = true
                let now = Date()
                say("page shows: screen \(m["screen"] ?? "?"), heading \"\(m["heading"] ?? "")\", button \"\(m["button"] ?? "")\", in \(m["engine"] ?? "?")")
                say(String(format: "start-up: the page showed the engine's words %.2f s after the program started (at unix ms %.0f)",
                           now.timeIntervalSince(started), now.timeIntervalSince1970 * 1000))
            case "shell.checked":
                let drives = (m["drives"] as? NSNumber)?.intValue ?? -1
                say("a request from the page came back from the engine: \(drives) drives listed")
                let ok = seen.drawn && seen.hello && drives >= 0
                guard ok, fullRun else {
                    say(ok ? "PASSED: the window started the engine, showed the pages and passed messages both ways" : "FAILED")
                    end(ok ? 0 : 3)
                }
                say("the window started the engine, showed the pages and passed messages both ways; now Add music, as a DJ would")
                // Add music: the bar's button opens a menu whose last item is "Choose a folder…".
                eval("document.getElementById('add-button').click();")
                evalWhen("!document.getElementById('add-menu').hidden && document.querySelector('#add-menu [role=menuitem]')", """
                    var items = document.querySelectorAll('#add-menu [role=menuitem]');
                    items[items.length - 1].click();
                    """)
            case "shell.checkFinished":
                let summary = (m["summary"] as? String ?? "").split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }.joined(separator: " | ")
                say("the finished screen says: \(summary)")
            case "shell.checkError":
                say("FAILED: a step in the page threw: \(m["detail"] ?? "?")")
                end(3)
            default: break
            }
        }
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: seconds)
            say("FAILED: not done within \(Int(seconds)) s (hello seen: \(seen.hello), page drawn: \(seen.drawn), run finished: \(seen.finished))")
            exit(2)
        }
    }
}
