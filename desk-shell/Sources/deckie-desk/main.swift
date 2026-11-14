// deckie-desk: Deckie Desk's window on Windows and Linux (D32), built on the Mac too so the pages can be seen here.
//
//   deckie-desk                         the window: starts the engine beside it and shows the pages
//   deckie-desk --self-test             proves the window alone: one message each way with a small page (SelfTest)
//   deckie-desk --check                 the window, the engine and the pages together: the page draws the engine's
//                                       first screen and asks it one thing through the page; exits 0 when it did
//   deckie-desk --tour <folder> --music <folder> --export-to <folder>
//                                       the Mac only: walks every screen with the music given and writes a picture
//                                       of each into <folder> (Tour.swift); `--naming` walks the naming screens
//                                       instead (a music CD from DECKIE_DESK_MUSIC_CD, `--playlist <file.m3u>`);
//                                       `--run-screen` the run screen (D37) at a few song counts and finished, and
//                                       with `--record`, a picture every half second while it runs; `--add-music`
//                                       the ways in, a big drive, the count and question, Stop and Carry on
//                                       (research AE; Tour.addMusicSteps says what it needs)
//   deckie-desk --check --music <folder> --export-to <folder>
//                                       the check carried on as a DJ would: Add music with that folder (the page's
//                                       own button; the folder chooser answers with it), the run to its end, Export
//                                       crate file into the second folder; exits 0 when the crate file is there
// Options: --engine <path to deckie-desk-engine>, --pages <folder of desk-web>, --debug (the web inspector),
// --check-log <file> (what a check says, written to a file as well as to standard error: a program of the "windows"
// kind started as a double click starts it has no standard error). By default the engine and the pages are looked
// for beside this program (deckie-desk-engine, desk-web/), then in the checkout.
//
// How it ends: 0 the window was closed (or the check passed); 1 a part of Desk is missing or the engine did not
// start; 2 and 3 a check failed; 4 this PC has no WebView2 Runtime (Windows); 5 the runtime is there and the window
// still could not be made. Before 1, 4 and 5 the DJ is told why in a message box on Windows (Notice.swift).
//
// For checks: DECKIE_NO_BOXES (any value) says those things on standard error only; DECKIE_DESK_NO_WEBVIEW2 (any
// value) makes the program behave as on a PC without the WebView2 Runtime, to try that path where the runtime
// cannot be taken away.
import Foundation

_ = Notice.started

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
let env = ProcessInfo.processInfo.environment
if let log = option("--check-log") { Notice.keepLog(at: log) }
Notice.quiet = args.contains("--check") || args.contains("--self-test") || args.contains("--tour") || env["DECKIE_NO_BOXES"] != nil

// A check never waits for ever: its time limit starts now, before the window is made.
if args.contains("--check") {
    Check.limit(seconds: Double(env["DECKIE_CHECK_SECONDS"] ?? "") ?? (option("--music") == nil ? 90 : 900))
    Notice.say("[check] started; looking for the engine and the pages beside \(CommandLine.arguments[0])")
}

#if canImport(Darwin)
// A check sends nothing over the internet. On the Mac the engine can look songs up (on Windows and Linux it says it
// cannot yet), so unless recorded answers are given, the engine it starts answers from an empty set of them: every
// lookup it is asked for gets "no connection", and nothing leaves this computer.
if args.contains("--check"), (env["DECKIE_LOOKUP_RECORDED"] ?? "").isEmpty {
    let none = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-check-no-lookups-\(getpid())", isDirectory: true)
    try? FileManager.default.createDirectory(at: none, withIntermediateDirectories: true)
    setenv("DECKIE_LOOKUP_RECORDED", none.path, 1)
}
#endif

if args.contains("--self-test") {
    SelfTest.run(seconds: Double(env["DECKIE_SELF_TEST_SECONDS"] ?? "") ?? 60)
}

let here = (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])).deletingLastPathComponent()
#if os(Windows)
let engineName = "deckie-desk-engine.exe"
#else
let engineName = "deckie-desk-engine"
#endif
/// The checkout this was built in (desk-shell/.build/<config>/deckie-desk), for running from a build folder.
let checkout = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
func firstThere(_ candidates: [URL]) -> URL? { candidates.first { FileManager.default.fileExists(atPath: $0.path) } }

let engine = option("--engine").map { URL(fileURLWithPath: $0) } ?? env["DECKIE_DESK_ENGINE"].map { URL(fileURLWithPath: $0) }
    ?? firstThere([here.appendingPathComponent(engineName),
                   checkout.appendingPathComponent("core/.build/release").appendingPathComponent(engineName),
                   checkout.appendingPathComponent("core/.build/debug").appendingPathComponent(engineName)])
let pages = option("--pages").map { URL(fileURLWithPath: $0, isDirectory: true) }
    ?? firstThere([here.appendingPathComponent("desk-web", isDirectory: true), checkout.appendingPathComponent("desk-web", isDirectory: true)])

guard let engine, FileManager.default.fileExists(atPath: engine.path) else {
    Notice.say("deckie-desk: the engine program (\(engineName)) was not found; give it with --engine")
    Notice.tell(Notice.partMissing.replacingOccurrences(of: "{part}", with: engineName))
    exit(1)
}
guard let pages, FileManager.default.fileExists(atPath: pages.appendingPathComponent("index.html").path) else {
    Notice.say("deckie-desk: the pages (desk-web) were not found; give them with --pages")
    Notice.tell(Notice.partMissing.replacingOccurrences(of: "{part}", with: "desk-web"))
    exit(1)
}

var options = Desk.Options(engine: engine, pages: pages.standardizedFileURL, debug: args.contains("--debug"))
options.addMusicAnswer = option("--music")
options.exportAnswer = option("--export-to")
options.playlistAnswer = option("--playlist")

let pretendNoWebView = Window.engineName == "WebView2" && env["DECKIE_DESK_NO_WEBVIEW2"] != nil
if args.contains("--check") { Notice.say("[check] making the window (\(Window.engineName)); engine \(engine.path); pages \(pages.path)") }
guard !pretendNoWebView, let desk = Desk(options: options) else {
    Notice.say("deckie-desk: no window; the system's web view (\(Window.engineName)) could not be started")
    guard Window.engineName == "WebView2" else { exit(1) }
    // Windows. The window is made by the same loader that looks for the runtime, so its "no" is the test; the
    // registry values Microsoft documents say which of the two reasons to give.
    let version = pretendNoWebView ? nil : Window.webView2Version
    Notice.say("deckie-desk: WebView2 Runtime by the registry: \(version ?? "not installed")"
               + (pretendNoWebView ? " (DECKIE_DESK_NO_WEBVIEW2 is set: behaving as on a PC without it)" : ""))
    let words = version.map { Notice.windowFailed.replacingOccurrences(of: "{version}", with: $0) } ?? Notice.noWebView2
    if Notice.ask(words) { Window.openAddress(Notice.webView2Page) }
    exit(version == nil ? 4 : 5)
}

if args.contains("--check") {
    let music = option("--music"), exportTo = option("--export-to")
    Check.arm(desk, music: music, exportTo: exportTo)
}
if let out = option("--tour") { Tour.arm(desk, out: URL(fileURLWithPath: out, isDirectory: true)) }

exit(desk.run())
