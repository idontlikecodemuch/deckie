import AppKit
import CoreGraphics
import DeckieDesk

/// Whether macOS lets Deckie Desk record the screen, which decides how its pictures of its own window are made
/// (Snapshot.capture): with it, the window server's image of the window, which shows everything a DJ sees; without it,
/// the window drawn by the app itself (Snapshot.layerImage), with no toolbar buttons, playing film, blurs or share sheet.
///
/// macOS asks about the app it holds responsible for a process. Launched by LaunchServices (`open`, the Finder, the
/// Dock), that is Deckie Desk itself; its binary run from a shell, it is the app that owns the shell (a terminal), so a
/// grant to Deckie Desk does not count there. The grant is tied to the app's signature: an ad hoc signed build loses it
/// at every rebuild, a build signed with a certificate (desk-app/tools/build-signed.sh) keeps it.
///
/// Words printed here are for the person at the terminal, not the DJ's screen, so they are not in Words.swift.
enum ScreenRecording {
    static var allowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Started by LaunchServices: its parent is launchd. Run from a shell, its parent is the shell.
    static var launchedByLaunchServices: Bool { getppid() == 1 }

    static var launchedBy: String {
        launchedByLaunchServices ? "launched through LaunchServices (open), so macOS asks about Deckie Desk itself"
            : "run directly (parent process \(getppid())), so macOS asks about the app that owns the shell, not Deckie Desk"
    }

    /// "Deckie Desk" --screen-recording: says whether Desk may record the screen and, when it may not, asks macOS once
    /// (`CGRequestScreenCaptureAccess`), which shows macOS's own prompt and lists Deckie Desk under System Settings >
    /// Privacy & Security > Screen Recording; then says the answer and quits. It opens no crate and touches no storage
    /// (it only says which storage folder the environment names, so a launch through `open` can be checked).
    /// Exit status 0 when Desk may record the screen, 1 when not.
    static func runIfAsked() {
        let a = CommandLine.arguments
        guard a.count >= 2, a[1] == "--screen-recording" else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        print("screen recording: process \(getpid()), \(launchedBy)")
        print("screen recording: storage this environment names (not opened): \(DeskHome.standard().root.path)")
        if allowed {
            print("screen recording: allowed; pictures of the window come from the window server")
            exit(0)
        }
        print("screen recording: not allowed; asking macOS once")
        let now = CGRequestScreenCaptureAccess()
        if now {
            print("screen recording: allowed now")
        } else {
            print("screen recording: not allowed yet. Turn on Deckie Desk in System Settings > Privacy & Security >"
                  + " Screen Recording; it counts from Desk's next launch")
        }
        exit(now ? 0 : 1)
    }

    /// The picture modes (--snapshot, --quick-start-walk, --film-walk, DECKIE_SNAP_ON_SIGNAL) work in the window with a
    /// crate, so each runs only on scratch storage: it prints the storage folder it would use and quits, before the
    /// window or any storage is opened, when that is the real one (DECKIE_DESK_HOME not set, or set to the real folder).
    /// A launch through `open` passes the environment with `--env`; this line is the proof that it arrived.
    @MainActor
    static func refuseRealStorageForPictures() {
        let env = ProcessInfo.processInfo.environment
        let picture = Snapshot.request != nil || QuickStartWalk.request != nil || FilmWalk.request != nil
            || env["DECKIE_SNAP_ON_SIGNAL"] != nil
        guard picture else { return }
        setvbuf(stdout, nil, _IOLBF, 0)
        let home = DeskHome.standard(environment: env).root
        let real = DeskHome.standard(environment: [:]).root
        print("pictures: process \(getpid()), storage \(home.path)")
        if home.resolvingSymlinksInPath() == real.resolvingSymlinksInPath() {
            print("pictures: refused: that is Desk's real storage. Set DECKIE_DESK_HOME to a scratch folder"
                  + " (with open, pass it as --env DECKIE_DESK_HOME=<folder>)")
            exit(2)
        }
    }

    /// The one line a picture run starts with: which way its pictures are made, and why.
    static var pictureLine: String {
        if allowed {
            return "pictures: through the window server (Deckie Desk may record the screen; \(launchedBy))"
        }
        let why = launchedByLaunchServices
            ? "allow Deckie Desk in System Settings > Privacy & Security > Screen Recording (ask with --screen-recording)"
            : "launch it with open (desk-app/tools/open-desk.sh) for the window server's pictures"
        return "pictures: drawn by the app itself, without toolbar buttons, playing film, blurs or the share sheet"
            + " (Deckie Desk may not record the screen; \(launchedBy); \(why))"
    }
}
