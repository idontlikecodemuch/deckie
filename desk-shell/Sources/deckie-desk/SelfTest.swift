import Foundation

/// `deckie-desk --self-test`: proves the window on this computer with no engine and no pages on disk. It opens the
/// window, shows a small page, and passes one message each way: the page says "hello", the shell answers "pong", the
/// page answers "got pong". Then it closes the window and exits 0, printing what it saw; it exits 1 when the web view
/// is missing and 2 when the exchange did not finish within the time allowed.
enum SelfTest {
    static let page = """
    <!doctype html><html><head><meta charset="utf-8"><title>Deckie Desk self-test</title></head>
    <body style="background:#121214;color:#f2f2f5;font:16px system-ui;padding:24px">
    <h1>Deckie Desk window self-test</h1><p id="state">Waiting for the shell…</p>
    <script>
      deckieShell.onmessage = function (text) {
        var m = JSON.parse(text);
        if (m.type === "pong") {
          document.getElementById("state").textContent = "The shell answered: " + m.text;
          deckieShell.send(JSON.stringify({ type: "got pong", engine: deckieShell.engine, agent: navigator.userAgent }));
        }
      };
      deckieShell.send(JSON.stringify({ type: "hello" }));
    </script></body></html>
    """

    static func run(seconds: Double) -> Never {
        let started = Date()
        @Sendable func say(_ s: String) {
            Notice.say(String(format: "[self-test %.2fs] ", Date().timeIntervalSince(started)) + s)
        }
        guard let window = Window(title: "Deckie Desk self-test", width: 640, height: 360, debug: false) else {
            say("FAILED: no window; the system's web view (\(Window.engineName)) could not be started")
            exit(1)
        }
        say("window created with \(Window.engineName)")
        var passed = false
        window.onMessage = { text in
            say("page sent: \(text)")
            guard let data = text.data(using: .utf8),
                  let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let type = m["type"] as? String else { return }
            switch type {
            case "hello":
                window.post(#"{"type":"pong","text":"hello from Swift, ünïcødé ok"}"#)
            case "got pong":
                passed = true
                // Leave the page on screen for a moment, so a screenshot can catch it.
                let hold = Double(ProcessInfo.processInfo.environment["DECKIE_SELF_TEST_HOLD"] ?? "") ?? 0.5
                Thread.detachNewThread {
                    Thread.sleep(forTimeInterval: hold)
                    window.onWindowThread { window.close() }
                }
            default: break
            }
        }
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: seconds)
            say("FAILED: no exchange with the page within \(Int(seconds)) s")
            exit(2)
        }
        window.setHTML(page)
        window.run()
        say(passed ? "PASSED: window made, one message each way, closed cleanly" : "FAILED: the window closed before the exchange")
        exit(passed ? 0 : 3)
    }
}
