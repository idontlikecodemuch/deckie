import Foundation

/// What the shell itself says, to a developer and to a DJ.
///
/// Lines for a developer or a check (`say`) go to standard error, when there is one, and, with `--check-log
/// <file>`, to that file as well: a program of the "windows" kind started the way a double click starts it has no
/// standard error at all, and nothing is written to it then.
///
/// The few things a DJ must be told before there is a window to tell them in (`tell`, `ask`) are said in a message
/// box on Windows. These are the only words the shell holds; every word in the window is the engine's
/// (DeskWords). They follow docs/product/voice.md: plain, short, sentence case. Each is a named value here, to be
/// changed in one place (D36).
enum Notice {
    static let title = "Deckie Desk"

    /// Microsoft's own page for people who need the WebView2 Runtime (the one Microsoft's documentation says to send
    /// them to: "Distribute your app and the WebView2 Runtime", read Nov 14, 2026). It is named in the message and
    /// opened only when the DJ says yes. Nothing is downloaded by Deckie.
    static let webView2Page = "https://developer.microsoft.com/microsoft-edge/webview2/consumer/"

    /// This PC has no WebView2 Runtime. Asked as a question: Yes opens Microsoft's page in the DJ's browser.
    static let noWebView2 = """
        Deckie Desk needs a free part of Windows that this PC does not have yet: Microsoft's WebView2 Runtime. \
        It is what shows Deckie Desk's window.

        Get it from Microsoft's own page, install it, then start Deckie Desk again:
        \(webView2Page)
        On that page, choose "Download WebView2".

        Or make your crate file now with "Make Crate File" in this folder. It needs nothing else: drag your \
        music folder onto it.

        Open Microsoft's page now?
        """

    /// The runtime is installed (its version is `{version}`) and the window still could not be made.
    static let windowFailed = """
        Deckie Desk could not open its window on this PC.

        The part of Windows that shows it (Microsoft's WebView2 Runtime, version {version}) is here but did not \
        start. Restarting the PC often fixes that. If it does not, install the runtime again from Microsoft's own \
        page:
        \(webView2Page)

        You can still make your crate file with "Make Crate File" in this folder: drag your music folder onto it.

        Open Microsoft's page now?
        """

    /// A part of Deckie's own folder is not where it should be (`{part}`).
    static let partMissing = """
        Deckie Desk cannot start: a part of it is missing ({part}).

        Unzip the Deckie zip again into a new folder, and start "Deckie Desk" from there.
        """

    /// The engine program could not be started.
    static let engineDidNotStart = """
        Deckie Desk cannot start: the part of it that reads music did not start.

        Unzip the Deckie zip again into a new folder, and start "Deckie Desk" from there. If it happens again, \
        tell the person who gave you Deckie.
        """

    // MARK: saying

    static let started = Date()
    /// Asked once, before anything is written: a program started by a double click on Windows has no standard error.
    private static let standardError: FileHandle? = Window.hasStandardError ? FileHandle.standardError : nil
    private static let lock = NSLock()
    nonisolated(unsafe) private static var log: FileHandle?
    /// No message boxes: a check with no one at the keyboard must not wait for a click (`--check`, `--self-test`,
    /// or DECKIE_NO_BOXES in the environment, which the starter reads too).
    nonisolated(unsafe) static var quiet = false

    /// Also writes every line said from now on to `path` (made new).
    static func keepLog(at path: String) {
        _ = FileManager.default.createFile(atPath: path, contents: nil)
        lock.lock(); log = FileHandle(forWritingAtPath: path); lock.unlock()
    }

    /// One line for a developer or a check.
    static func say(_ line: String) {
        let data = Data((line + "\n").utf8)
        lock.lock()
        standardError?.write(data)
        log?.write(data)
        lock.unlock()
    }

    /// The engine's own lines for a developer (its standard error), passed on as they come.
    static func pass(_ data: Data) {
        lock.lock()
        standardError?.write(data)
        log?.write(data)
        lock.unlock()
    }

    /// Tells the DJ something that stops Desk from starting: a message box on Windows, and always a line.
    static func tell(_ words: String) {
        say("deckie-desk: " + words)
        if !quiet { _ = Window.notice(title: title, text: words, ask: false) }
    }

    /// Asks the DJ a yes-or-no question; false where there is no one to ask.
    static func ask(_ words: String) -> Bool {
        say("deckie-desk: " + words)
        return quiet ? false : Window.notice(title: title, text: words, ask: true)
    }
}
