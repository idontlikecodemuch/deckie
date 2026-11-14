import Foundation
#if os(Windows)
import WinSDK
#endif

/// The one file a DJ sends back when something goes wrong: `Deckie Desk log.txt` in Desk's own storage folder
/// (`%LOCALAPPDATA%\Deckie Desk` on Windows). It is started afresh each time Desk starts; the one before is kept
/// beside it as `Deckie Desk log (last time).txt`, so a start that failed is still there after the next one.
///
/// What goes in: when Desk started, which Windows or Linux and which web view, where its parts are, that the window
/// was made, what the engine said about itself, each run's start and end with its counts, anything the engine
/// refused or failed at with its reason, anything the page threw, and how Desk ended. A reason can name a file or a
/// folder (that is the point of it), and paths carry the account's name. What never goes in: any audio, the songs
/// of a crate, their names, artists or keys, or what a lookup sent.
enum DeskLog {
    static let name = "Deckie Desk log.txt"
    static let lastName = "Deckie Desk log (last time).txt"

    /// Desk's storage folder, as the engine finds it (DeskHome.standard in the core): DECKIE_DESK_HOME, else the
    /// account's application-support folder.
    static var folder: URL {
        if let p = ProcessInfo.processInfo.environment["DECKIE_DESK_HOME"], !p.isEmpty {
            return URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true)
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return support.appendingPathComponent("Deckie Desk", isDirectory: true)
    }

    /// Starts the log and returns where it is, or nil when the folder cannot be written (Desk still runs).
    @discardableResult
    static func start() -> URL? {
        let fm = FileManager.default
        let dir = folder
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name), last = dir.appendingPathComponent(lastName)
        if fm.fileExists(atPath: file.path) {
            try? fm.removeItem(at: last)
            try? fm.moveItem(at: file, to: last)
        }
        Notice.keepLog(at: file.path)
        guard fm.fileExists(atPath: file.path) else { return nil }
        let stamp = ISO8601DateFormatter().string(from: Date())
        Notice.say("Deckie Desk log, started \(stamp). To report a problem, send this one file. It holds no music and no song names.")
        Notice.say("system: \(ProcessInfo.processInfo.operatingSystemVersionString); processor kind: \(machine); "
                   + "web view: \(Window.engineName) \(Window.webView2Version ?? "")")
        return file
    }

    /// The processor this program was built for, and the one it runs on when Windows says they differ (an x64
    /// program on a Windows for Arm PC runs through Windows' own emulation).
    static var machine: String {
        #if arch(x86_64)
        let built = "x64"
        #elseif arch(arm64)
        let built = "arm64"
        #else
        let built = "other"
        #endif
        let env = ProcessInfo.processInfo.environment
        let real = env["PROCESSOR_ARCHITEW6432"] ?? env["PROCESSOR_ARCHITECTURE"] ?? ""
        var native = ""
        #if os(Windows)
        var processKind: USHORT = 0, nativeKind: USHORT = 0
        if IsWow64Process2(GetCurrentProcess(), &processKind, &nativeKind) {
            native = nativeKind == 0xAA64 ? "arm64" : nativeKind == 0x8664 ? "x64" : String(format: "0x%04X", nativeKind)
        }
        #endif
        return "built for \(built)" + (native.isEmpty ? "" : ", this computer is \(native)") + (real.isEmpty ? "" : " (Windows says \(real))")
    }

    /// One line for a message from the engine that is worth keeping, or nil. Never a song's name.
    static func line(forEngine text: String) -> String? {
        guard let data = text.data(using: .utf8), let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        func short(_ v: Any?) -> String { String(String(describing: v ?? "?").prefix(400)) }
        switch m["event"] as? String {
        case "hello":
            let analysis = m["analysis"] as? [String: Any]
            let lookup = m["lookup"] as? [String: Any]
            return "engine: protocol \(short(m["protocol"])), \(short(m["platform"])), analysis ready: \(short(analysis?["ready"]))"
                + ((analysis?["detail"] as? String).map { " (\($0))" } ?? "") + ", lookup available: \(short(lookup?["available"]))"
        case "run.started": return "run started"
        case "run.finished":
            let r = m["report"] as? [String: Any] ?? [:]
            return "run finished: \(short(r["went_in"])) of \(short(r["songs_seen"])) files went in, \(short(r["songs_in_crate"])) songs in the crate, \(short(r["seconds"])) s"
        case "run.failed": return "run failed: \(short(m["detail"]))"
        case "lookup.finished":
            let r = m["review"] as? [String: Any]
            return "lookup finished" + ((r?["failure"] as? String).map { ": \($0)" } ?? "")
        default: break
        }
        if m["re"] != nil, m["ok"] as? Bool == false {
            let e = m["error"] as? [String: Any]
            return "refused: \(short(e?["code"])): \(short(e?["detail"]))"
        }
        return nil
    }
}
