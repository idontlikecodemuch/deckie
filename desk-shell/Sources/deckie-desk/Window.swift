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
    }

    deinit { deskshell_destroy(handle) }

    static var engineName: String { String(cString: deskshell_engine_name()) }

    /// Windows: gives a program started by a double click somewhere harmless to write (deskshell.h). Call first.
    static func prepareProcess() { deskshell_prepare_process() }

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
    func chooseFolder(message: String) -> String? {
        #if os(macOS)
        let p = NSOpenPanel()
        p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = false
        p.message = message
        return p.runModal() == .OK ? p.url?.path : nil
        #else
        guard let c = deskshell_choose_folder(handle, message) else { return nil }
        defer { deskshell_free(c) }
        return String(cString: c)
        #endif
    }

    /// The system's file chooser for one file; the path, or nil.
    func chooseFile(message: String) -> String? {
        #if os(macOS)
        let p = NSOpenPanel()
        p.canChooseDirectories = false; p.canChooseFiles = true; p.allowsMultipleSelection = false
        p.treatsFilePackagesAsDirectories = true
        p.message = message
        return p.runModal() == .OK ? p.url?.path : nil
        #else
        guard let c = deskshell_choose_file(handle, message) else { return nil }
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
