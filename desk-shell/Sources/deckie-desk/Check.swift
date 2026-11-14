import Foundation

/// `deckie-desk --check`: the window, the engine and the pages together, with no one at the keyboard. It passes when
/// the engine's first message reached the page, the page drew a screen from it in the engine's words, and a request
/// sent from the page (the list of drives) came back through the shell and the engine. It prints what the page showed.
enum Check {
    static func arm(_ desk: Desk, seconds: Double) {
        let started = Date()
        @Sendable func say(_ s: String) {
            FileHandle.standardError.write(Data((String(format: "[check %.2fs] ", Date().timeIntervalSince(started)) + s + "\n").utf8))
        }
        var sawHello = false, asked = false
        desk.watchers.append { line in
            guard let m = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return }
            if m["event"] as? String == "hello" {
                sawHello = true
                say("engine said hello: protocol \(m["protocol"] ?? "?"), platform \(m["platform"] ?? "?"), analysis \(m["analysis"] ?? "?")")
            }
            if m["event"] as? String == "state", sawHello, !asked {
                asked = true
                // Give the page a moment to draw, then ask it what it shows and have it ask the engine something.
                Thread.detachNewThread {
                    Thread.sleep(forTimeInterval: 1.5)
                    desk.window.onWindowThread {
                        desk.window.eval("""
                        (function () {
                          var shown = document.querySelector('main > section:not([hidden])');
                          var h1 = shown && shown.querySelector('h1');
                          desk.request('drives.list', {}, { quiet: true }).then(function (r) {
                            deckieShell.send(JSON.stringify({ type: 'shell.checked', screen: shown ? shown.id : null,
                              heading: h1 ? h1.textContent : null, button: document.getElementById('add-label').textContent,
                              drives: r.ok ? r.drives.length : -1, engine: deckieShell.engine }));
                          });
                        })();
                        """)
                    }
                }
            }
        }
        desk.pageWatchers.append { m in
            guard m["type"] as? String == "shell.checked" else { return }
            say("page shows: screen \(m["screen"] ?? "?"), heading \"\(m["heading"] ?? "")\", button \"\(m["button"] ?? "")\", in \(m["engine"] ?? "?")")
            say("a request from the page came back from the engine: \(m["drives"] ?? "?") drives listed")
            let ok = (m["heading"] as? String).map { !$0.isEmpty } == true && ((m["drives"] as? NSNumber)?.intValue ?? -1) >= 0
            say(ok ? "PASSED: the window started the engine, showed the pages and passed messages both ways" : "FAILED")
            desk.engine?.stop()
            exit(ok ? 0 : 3)
        }
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: seconds)
            say("FAILED: the page did not answer within \(Int(seconds)) s (hello seen: \(sawHello))")
            exit(2)
        }
    }
}
