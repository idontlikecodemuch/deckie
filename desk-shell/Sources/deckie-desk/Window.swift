import Foundation
import CDeskShell
#if os(macOS)
import AppKit
#endif

/// Desk's window: the system's web view through CDeskShell, with one message channel each way. Everything except
/// `post` and `onWindowThread` must be called on the window's thread (the main thread, which runs `run`).
final class Window: @unchecked Sendable {
    private let handle: deskshell_t
    /// Each message the page sends, as its text, on the window's thread.
    var onMessage: (String) -> Void = { _ in }

    /// Nil when the system's web view is missing (WebView2 not installed, WebKitGTK not found).
    init?(title: String, width: Int, height: Int, debug: Bool) {
        guard let h = deskshell_create(debug ? 1 : 0, title, Int32(width), Int32(height)) else { return nil }
        handle = h
        deskshell_on_message(h, { args, context in
            guard let args, let context else { return }
            let window = Unmanaged<Window>.fromOpaque(context).takeUnretainedValue()
            // The page's arguments arrive as a JSON array holding the one string it sent.
            let data = Data(String(cString: args).utf8)
            guard let list = try? JSONSerialization.jsonObject(with: data) as? [Any], let text = list.first as? String else { return }
            window.onMessage(text)
        }, Unmanaged.passUnretained(self).toOpaque())
        #if os(macOS)
        Window.installMacMenu()
        fitToScreen()
        #endif
    }

    #if os(macOS)
    /// The first window fits the screen it opens on, as on Windows and Linux (deskshell.cc fit_to_screen): no larger
    /// than the screen's visible part less a margin each side, centred on it; a larger screen keeps the size asked for.
    private func fitToScreen() {
        guard let p = deskshell_native_view(handle) else { return }
        let view = Unmanaged<NSView>.fromOpaque(p).takeUnretainedValue()
        guard let window = view.window, let screen = window.screen ?? NSScreen.main else { return }
        let room = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        var frame = window.frame
        frame.size.width = min(frame.width, room.width); frame.size.height = min(frame.height, room.height)
        frame.origin = CGPoint(x: room.midX - frame.width / 2, y: room.midY - frame.height / 2)
        window.setFrame(frame, display: false)
    }
    #endif

    #if os(macOS)
    /// The Mac's menu bar. Run from the command line the program has no app bundle, and the web view library makes it
    /// an ordinary app (activation policy "regular") but gives it no menu, so Cmd+Q had nothing to answer it (the
    /// system's beep, and the menu bar stayed Finder's). Quit closes the window, the way its close button does, so
    /// the shell ends the engine as it always does.
    static func installMacMenu() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let bar = NSMenu()
        let appItem = NSMenuItem()
        bar.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: Notice.macHide, action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: Notice.macClose, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: Notice.macQuit, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem()
        bar.addItem(editItem)
        let edit = NSMenu(title: Notice.macEdit)
        edit.addItem(withTitle: Notice.macCut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: Notice.macCopy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: Notice.macPaste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: Notice.macSelectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        app.mainMenu = bar
        app.activate(ignoringOtherApps: true)
    }
    #endif

    deinit { deskshell_destroy(handle) }

    static var engineName: String { String(cString: deskshell_engine_name()) }

    /// False on Windows when the program was started with no standard error (a double click): nothing may be
    /// written to it then (deskshell.h).
    static var hasStandardError: Bool { deskshell_has_standard_error() != 0 }

    /// Windows: the version of Microsoft's WebView2 Runtime on this PC, by the registry values Microsoft documents;
    /// nil when it is not installed, and always nil on the other systems.
    static var webView2Version: String? {
        guard let c = deskshell_webview2_version() else { return nil }
        defer { deskshell_free(c) }
        return String(cString: c)
    }

    /// Windows: a message box; true when the DJ chose Yes (or OK). False at once on the other systems.
    static func notice(title: String, text: String, ask: Bool) -> Bool { deskshell_notice(title, text, ask ? 1 : 0) != 0 }

    /// Windows: opens a web address in the DJ's own browser.
    static func openAddress(_ address: String) { deskshell_open_address(address) }

    /// Windows: whether the window carries Desk's own icon (the program was built with it).
    var hasIcon: Bool { deskshell_window_has_icon(handle) != 0 }

    /// Runs `js` at the start of every page, before the page's own scripts. Before `load`.
    func addScript(_ js: String) { deskshell_init_script(handle, js) }

    func load(_ url: URL) { deskshell_load(handle, url.absoluteString) }
    func setHTML(_ html: String) { deskshell_set_html(handle, html) }

    /// Hands one message to the page. Any thread.
    func post(_ text: String) { deskshell_post(handle, text) }

    /// Runs JavaScript in the page. Window's thread.
    func eval(_ js: String) { deskshell_eval(handle, js) }

    var nativeView: UnsafeMutableRawPointer? { deskshell_native_view(handle) }

    /// Runs `work` on the window's thread. Any thread.
    func onWindowThread(_ work: @escaping @Sendable () -> Void) {
        let box = Unmanaged.passRetained(WorkBox(work)).toOpaque()
        deskshell_dispatch(handle, { context in
            guard let context else { return }
            Unmanaged<WorkBox>.fromOpaque(context).takeRetainedValue().work()
        }, box)
    }

    /// Runs until the window closes or `close` is called.
    @discardableResult
    func run() -> Int32 { deskshell_run(handle) }

    func close() { deskshell_terminate(handle) }

    /// The system's folder chooser; the path, or nil when the DJ cancelled.
    /// `start`: the folder it opens at (a big drive's top, research AE), or nil.
    func chooseFolder(message: String, accept: String, cancel: String, start: String? = nil) -> String? {
        if case .chosen(let path) = chooseFolder(message: message, accept: accept, cancel: cancel, start: start, purpose: nil) { return path }
        return nil
    }

    /// What a folder chooser ended with: a folder, the DJ's cancel, or nothing for a reason (said in `failed`).
    enum Chosen: Equatable {
        case chosen(String)
        case cancelled
        case failed(String)
    }

    /// The system's folder chooser for one purpose ("export", "addMusic"): on Windows Export keeps its own memory of
    /// where it was last. Tells a cancel apart from a chooser that gave nothing back, so the page never ends in silence.
    func chooseFolder(message: String, accept: String, cancel: String, start: String?, purpose: String?) -> Chosen {
        #if os(macOS)
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.message = message
        if let start { p.directoryURL = URL(fileURLWithPath: start, isDirectory: true) }
        guard p.runModal() == .OK else { return .cancelled }
        guard let path = p.url?.path, !path.isEmpty else { return .failed("the chooser gave back nothing") }
        return .chosen(path)
        #else
        var problem: UnsafeMutablePointer<CChar>?
        let c = deskshell_choose_folder_for(handle, message, accept, cancel, start ?? "", purpose ?? "", &problem)
        defer { if let c { deskshell_free(c) }; if let problem { deskshell_free(problem) } }
        if let c {
            let path = String(cString: c)
            return path.isEmpty ? .failed("the chooser gave back an empty path") : .chosen(path)
        }
        if let problem { return .failed(String(cString: problem)) }
        return .cancelled
        #endif
    }

    /// The system's file chooser for one file; the path, or nil.
    func chooseFile(message: String, accept: String, cancel: String) -> String? {
        #if os(macOS)
        let p = NSOpenPanel()
        p.canChooseDirectories = false; p.canChooseFiles = true; p.allowsMultipleSelection = false
        p.treatsFilePackagesAsDirectories = true
        p.message = message
        return p.runModal() == .OK ? p.url?.path : nil
        #else
        guard let c = deskshell_choose_file(handle, message, accept, cancel) else { return nil }
        defer { deskshell_free(c) }
        return String(cString: c)
        #endif
    }

    /// Opens a folder in the system's file manager.
    static func openFolder(_ path: String) {
        #if os(macOS)
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
        #else
        deskshell_open_folder(path)
        #endif
    }
}

private final class WorkBox {
    let work: @Sendable () -> Void
    init(_ work: @escaping @Sendable () -> Void) { self.work = work }
}
