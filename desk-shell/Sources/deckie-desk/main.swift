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
//                                       with `--record`, a picture every half second while it runs
// Options: --engine <path to deckie-desk-engine>, --pages <folder of desk-web>, --debug (the web inspector). By
// default both are looked for beside this program (deckie-desk-engine, desk-web/), then in the checkout.
import Foundation

var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
let env = ProcessInfo.processInfo.environment

if args.contains("--self-test") {
    SelfTest.run(seconds: Double(env["DECKIE_SELF_TEST_SECONDS"] ?? "") ?? 60)
}

let here = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
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
    FileHandle.standardError.write(Data("deckie-desk: the engine program (\(engineName)) was not found; give it with --engine\n".utf8))
    exit(1)
}
guard let pages, FileManager.default.fileExists(atPath: pages.appendingPathComponent("index.html").path) else {
    FileHandle.standardError.write(Data("deckie-desk: the pages (desk-web) were not found; give them with --pages\n".utf8))
    exit(1)
}

var options = Desk.Options(engine: engine, pages: pages.standardizedFileURL, debug: args.contains("--debug"))
options.addMusicAnswer = option("--music")
options.exportAnswer = option("--export-to")
options.playlistAnswer = option("--playlist")

guard let desk = Desk(options: options) else {
    FileHandle.standardError.write(Data("deckie-desk: no window; the system's web view (\(Window.engineName)) could not be started\n".utf8))
    exit(1)
}

if args.contains("--check") { Check.arm(desk, seconds: Double(env["DECKIE_CHECK_SECONDS"] ?? "") ?? 90) }
if let out = option("--tour") { Tour.arm(desk, out: URL(fileURLWithPath: out, isDirectory: true)) }

exit(desk.run())
