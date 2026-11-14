import Foundation

/// Deckie Desk's window (D32): starts the engine program, shows the pages, and passes messages between them
/// (docs/architecture/desk-protocol.md). Requests from the page whose type starts with "shell." are answered here:
/// the system's folder and file choosers, the file manager, and folders dropped on the window. Everything else goes to
/// the engine unchanged, and every line from the engine goes to the page unchanged.
///
/// All of this runs on the window's thread; the engine's lines arrive on a thread of their own and are moved over.
final class Desk: @unchecked Sendable {
    struct Options {
        var engine: URL
        var pages: URL
        var debug = false
        /// Answers for the choosers, so a check or a tour runs with no one at the keyboard: a folder for Add music,
        /// a folder for export.
        var addMusicAnswer: String?
        var exportAnswer: String?
        /// An answer for the file chooser when it asks for a playlist (the naming tool's "Choose a playlist…").
        var playlistAnswer: String?
    }

    let window: Window
    let options: Options
    private(set) var engine: EngineProcess?
    private var pageReady = false
    private var waiting: [String] = []
    private var closing = false
    /// Every line from the engine as it is passed on, for a check or a tour (window's thread).
    var watchers: [(String) -> Void] = []
    /// Messages the page sends to the shell that are not requests, and its `shell.ready` (the page has loaded and
    /// listens), for a check or a tour (window's thread).
    var pageWatchers: [([String: Any]) -> Void] = []

    init?(options: Options) {
        guard let w = Window(title: "Deckie Desk", width: 1180, height: 760, debug: options.debug) else { return nil }
        window = w
        self.options = options
        window.onMessage = { [unowned self] text in self.fromPage(text) }
    }

    /// Starts the engine, shows the pages, and runs until the window closes. Returns the window's exit code.
    func run() -> Int32 {
        do {
            engine = try EngineProcess(executable: options.engine, onLine: { [weak self] line in
                guard let self else { return }
                self.window.onWindowThread { self.fromEngine(line) }
            }, onExit: { [weak self] status in
                guard let self else { return }
                self.window.onWindowThread {
                    if !self.closing {
                        Notice.say("deckie-desk: the engine ended (\(status))")
                        self.toPage(#"{"event":"shell.engineGone"}"#)
                    }
                }
            })
        } catch {
            Notice.say("deckie-desk: could not start the engine at \(options.engine.path): \(error)")
            Notice.tell(Notice.engineDidNotStart)
            return 1
        }
        window.load(options.pages.appendingPathComponent("index.html"))
        let code = window.run()
        closing = true
        engine?.stop()
        return code
    }

    func close() {
        closing = true
        window.close()
    }

    // MARK: messages

    private func fromEngine(_ line: String) {
        for w in watchers { w(line) }
        toPage(line)
    }

    /// Hands a line to the page, or keeps it until the page is ready (a message sent before the page has loaded
    /// would be lost).
    func toPage(_ line: String) {
        if pageReady { window.post(line) } else { waiting.append(line) }
    }

    private func reply(_ id: Any?, _ fields: [String: Any]) {
        var m = fields
        m["re"] = id ?? NSNull()
        if m["ok"] == nil { m["ok"] = true }
        toPage(Self.json(m))
    }

    static func json(_ m: [String: Any]) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: m, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: d, as: UTF8.self)
    }

    private func fromPage(_ text: String) {
        guard let m = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let type = m["type"] as? String else { return }
        guard type.hasPrefix("shell.") else { engine?.send(text); return }
        let id = m["id"]
        switch type {
        case "shell.ready":
            pageReady = true
            let lines = waiting
            waiting = []
            for l in lines { window.post(l) }
            for w in pageWatchers { w(m) }
        case "shell.chooseFolder":
            let purpose = m["purpose"] as? String
            let preset = purpose == "export" ? options.exportAnswer : options.addMusicAnswer
            let path = preset ?? window.chooseFolder(message: m["message"] as? String ?? "")
            reply(id, path.map { ["path": $0] } ?? ["cancelled": true])
        case "shell.chooseFile":
            let preset = m["purpose"] as? String == "playlist" ? options.playlistAnswer : nil
            let path = preset ?? window.chooseFile(message: m["message"] as? String ?? "")
            reply(id, path.map { ["path": $0] } ?? ["cancelled": true])
        case "shell.openFolder":
            if let p = m["path"] as? String { Window.openFolder(p) }
            reply(id, [:])
        case "shell.droppedUris":
            // WebKitGTK hands the page dropped files as file URIs; they become paths here.
            let paths = (m["uris"] as? [String] ?? []).compactMap { URL(string: $0) }.filter(\.isFileURL)
                .map { $0.withUnsafeFileSystemRepresentation { $0.map { String(cString: $0) } } ?? $0.path }
            reply(id, [:])
            if !paths.isEmpty { toPage(Self.json(["event": "shell.dropped", "paths": paths])) }
        case "shell.droppedPaths":
            // WebView2 hands the dropped items to the shell (deskshell.cc), which reads their paths.
            let paths = m["paths"] as? [String] ?? []
            if !paths.isEmpty { toPage(Self.json(["event": "shell.dropped", "paths": paths])) }
        default:
            for w in pageWatchers { w(m) }
            if id != nil { reply(id, ["ok": false, "error": ["code": "unknown_type", "detail": type]]) }
        }
    }
}
