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
    /// What has happened so far. Written on the window's thread; the time limit's thread only reads it to say how
    /// far the check got.
    final class Seen: @unchecked Sendable { var window = false, hello = false, drawn = false, exportAsked = false, finished = false }
    static let seen = Seen()

    /// Ends the program with code 2 when the check has not ended it within `seconds`, saying how far it got. Started
    /// before the window is made, so that a web view that never comes up cannot make a check wait for ever.
    static func limit(seconds: Double) {
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: seconds)
            Notice.say("[check] FAILED: not done within \(Int(seconds)) s (window made: \(seen.window), hello seen: \(seen.hello), "
                       + "page drawn: \(seen.drawn), run finished: \(seen.finished))")
            exit(2)
        }
    }

    static func arm(_ desk: Desk, music: String?, exportTo: String?) {
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
        seen.window = true

        say("window made with \(Window.engineName); its own icon on the window: \(desk.window.hasIcon ? "yes" : "no")")
        desk.watchers.append { line in
            guard let m = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
            switch m["event"] as? String {
            case "hello":
                seen.hello = true
                say("engine said hello: protocol \(m["protocol"] ?? "?"), platform \(m["platform"] ?? "?"), analysis \(m["analysis"] ?? "?")")
            case "add.counted":
                // Add folder counts the songs first (research AE); the page goes on to read them, or asks first.
                say("counted before reading: \(m["songs"] ?? "?") songs in \"\(m["path"] ?? "?")\" (ask first: \(m["ask"] ?? "?"))")
            case "run.started":
                say("run started: reading \"\(m["read"] ?? "?")\" into crate \"\(m["crateName"] ?? "?")\"")
            case "run.failed":
                say("FAILED: the run stopped: \(m["detail"] ?? "?")")
                end(3)
            case "run.finished":
                guard fullRun, !seen.finished else { return }
                seen.finished = true
                let report = m["report"] as? [String: Any] ?? [:]
                say("run finished: \(report["went_in"] ?? "?") of \(report["songs_seen"] ?? "?") files went in, \(report["songs_in_crate"] ?? "?") songs in the crate, in \((report["seconds"] as? NSNumber).map { String(format: "%.1f", $0.doubleValue) } ?? "?") s")
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
                guard there else {
                    say("FAILED: the engine named a crate file that is not there")
                    end(3)
                }
                // Last, the lookup, as a DJ would reach it: the crate's songs, the More menu's "Look up songs via
                // MusicBrainz" (the first of its items that use the internet), then the dialog's own button once
                // its sentence is there. On Windows and Linux nothing is sent: the page should say so in words.
                seen.exportAsked = false
                eval("document.getElementById('finished-songs').click();")
                evalWhen("document.getElementById('finished').hidden && !document.getElementById('more-button').disabled",
                         "document.getElementById('more-button').click();")
                evalWhen("!document.getElementById('more-menu').hidden && document.querySelector('#more-menu .net-item')",
                         "document.querySelector('#more-menu .net-item').click();")
                evalWhen("""
                    document.getElementById('lookup').open && !document.getElementById('lookup-ask').hidden
                      && document.getElementById('lookup-sentence').textContent && !document.getElementById('lookup-go').disabled
                    """, """
                    var sentence = document.getElementById('lookup-sentence').innerText;
                    document.getElementById('lookup-go').click();
                    (function look() {
                      var review = document.getElementById('lookup-review'), progress = document.getElementById('lookup-progress');
                      if (review.hidden && progress.hidden) { setTimeout(look, 25); return; }
                      deckieShell.send(JSON.stringify({ type: 'shell.checkLookup', sentence: sentence, sending: !progress.hidden,
                        says: document.getElementById('lookup-summary').innerText }));
                    })();
                    """)
            }
        }
        desk.pageWatchers.append { m in
            switch m["type"] as? String {
            case "shell.ready":
                // The page has loaded and listens. As soon as it has drawn a screen in the engine's words (they
                // arrive in the engine's first message), it says what it shows.
                say("page loaded")
                // From here on, anything the page throws on its own ends the check.
                eval("""
                    window.addEventListener('error', function (e) { deckieShell.send(JSON.stringify({ type: 'shell.checkError', detail: 'the page: ' + (e.message || e) })); });
                    window.addEventListener('unhandledrejection', function (e) { deckieShell.send(JSON.stringify({ type: 'shell.checkError', detail: 'the page (a promise): ' + String(e.reason) })); });
                    """)
                // (The first screen, a run and its end have a heading; a crate's own screen has none.)
                evalWhen("""
                    document.querySelector('main > section:not([hidden])') && document.getElementById('add-label').textContent
                    """, """
                    var shown = document.querySelector('main > section:not([hidden])');
                    var h1 = shown.querySelector('h1');
                    deckieShell.send(JSON.stringify({ type: 'shell.drawn', screen: shown.id,
                      heading: h1 ? h1.textContent : '', button: document.getElementById('add-label').textContent,
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
                // The first screen's name field: the new crate is named as a DJ would name it, after the music
                // folder (a new crate is otherwise "My crate"; research AE). The exported file takes this name.
                let crateName = music.map { String($0.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last ?? "") } ?? ""
                say("names the new crate \"\(crateName)\" in the first screen's field")
                eval("""
                    var f = document.getElementById('first-name'); f.value = \(Tour.js(crateName));
                    f.dispatchEvent(new Event('input')); f.dispatchEvent(new Event('change'));
                    """)
                // Add music: the bar's button opens a menu of the three ways (DeskAddMusic.ways); the last is
                // Add folder, whose chooser answers with the music folder. The songs are counted, then read.
                eval("document.getElementById('add-button').click();")
                evalWhen("!document.getElementById('add-menu').hidden && document.querySelector('#add-menu [role=menuitem]')", """
                    var items = document.querySelectorAll('#add-menu [role=menuitem]');
                    items[items.length - 1].click();
                    """)
            case "shell.checkFinished":
                let summary = (m["summary"] as? String ?? "").split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }.joined(separator: " | ")
                say("the finished screen says: \(summary)")
            case "shell.checkLookup":
                let one = { (v: Any?) in (v as? String ?? "").split(whereSeparator: \.isNewline).joined(separator: " ") }
                say("the lookup's sentence: \(one(m["sentence"]))")
                if m["sending"] as? Bool == true {
                    say("the lookup started sending (this computer can look songs up); stopped here")
                } else {
                    say("the lookup says: \(one(m["says"]))")
                }
                let plain = m["sending"] as? Bool == true || !one(m["says"]).isEmpty
                say(plain ? "PASSED: music added through the page, the run finished, the crate file was exported, and the lookup answered in words"
                          : "FAILED: the lookup said nothing")
                end(plain ? 0 : 3)
            case "shell.checkError":
                say("FAILED: a step in the page threw: \(m["detail"] ?? "?")")
                end(3)
            default: break
            }
        }
    }
}
