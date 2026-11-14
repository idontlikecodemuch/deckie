import Foundation

/// The run screen's part of the engine's messages (D37; docs/architecture/desk-protocol.md, "The run screen"): the
/// songs that joined the screen, what is true of them, and the running totals, as `run.songs` events. A run calls in
/// from several threads, often several songs at once; they go out together at most `every` seconds apart, so 5,000
/// songs read before (which join in a burst) are a handful of lines, and a song that arrives alone waits at most that
/// long. Lines go out in the order the songs joined.
final class RunScreenOut: @unchecked Sendable {
    /// The shortest time between two `run.songs` events.
    static let every = 0.25
    /// The most songs one line carries (about 240 KB), so a burst is a few lines a page takes in its stride.
    static let maxSongs = 500

    private let lock = NSLock()
    private var songs: [RunSong] = []
    private var notes: [RunNote] = []
    private var figures = RunFigures()
    private var sent: RunFigures?
    private var lastSent = Date.distantPast
    private var scheduled = false
    private let send: @Sendable ([String: Any]) -> Void
    private let queue = DispatchQueue(label: "deckie.desk.screen-out", qos: .utility)

    init(send: @escaping @Sendable ([String: Any]) -> Void) { self.send = send }

    /// Takes what a progress call carries for the screen; sends now, or soon.
    func offer(_ p: RunProgress) {
        lock.lock(); defer { lock.unlock() }
        if let s = p.song { songs.append(s) }
        notes += p.notes
        figures = p.figures
        guard !songs.isEmpty || !notes.isEmpty || figures != sent else { return }
        let wait = Self.every - Date().timeIntervalSince(lastSent)
        if wait <= 0 { sendHeld(); return }
        if !scheduled {
            scheduled = true
            queue.asyncAfter(deadline: .now() + wait) { [self] in
                lock.lock(); defer { lock.unlock() }
                scheduled = false
                sendHeld()
            }
        }
    }

    /// Sends whatever is waiting (before the run's last event).
    func flush() {
        lock.lock(); defer { lock.unlock() }
        sendHeld()
    }

    /// Called with the lock held, so two batches never cross.
    private func sendHeld() {
        guard !songs.isEmpty || !notes.isEmpty || figures != sent else { return }
        // A long burst goes as several lines of at most `maxSongs`, the totals with the last.
        while songs.count > Self.maxSongs {
            send(Self.message(songs: Array(songs.prefix(Self.maxSongs)), notes: [], figures: nil))
            songs.removeFirst(Self.maxSongs)
        }
        send(Self.message(songs: songs, notes: notes, figures: figures))
        songs = []; notes = []; sent = figures; lastSent = Date()
    }

    static func message(songs: [RunSong], notes: [RunNote], figures: RunFigures?) -> [String: Any] {
        var m: [String: Any] = ["event": "run.songs", "songs": DeskProtocol.plain(songs), "notes": DeskProtocol.plain(notes)]
        if let figures { m["figures"] = DeskProtocol.plain(figures) }
        return m
    }
}
