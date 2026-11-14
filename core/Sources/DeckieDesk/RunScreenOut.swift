import Foundation

/// The run screen's part of the engine's messages (D37; docs/architecture/desk-protocol.md, "The run screen"): the
/// songs that joined the screen, what is true of them, and the running totals, as `run.songs` events. A run calls in
/// from several threads, often several songs at once; they go out together at most `every` seconds apart, so 5,000
/// songs read before (which join in a burst) are a handful of lines, and a song that arrives alone waits at most that
/// long. The totals, the larger part of a line, go at most every `figuresEvery` seconds, and always with the last
/// line. Lines go out in the order the songs joined.
final class RunScreenOut: @unchecked Sendable {
    /// The shortest time between two `run.songs` events, and between two that carry the totals.
    static let every = 0.25
    static let figuresEvery = 1.0
    /// The most songs one line carries (about 240 KB), so a burst is a few lines a page takes in its stride.
    static let maxSongs = 500

    private let lock = NSLock()
    private var songs: [RunSong] = []
    private var notes: [RunNote] = []
    private var figures = RunFigures()
    private var sent: RunFigures?
    private var lastSent = Date.distantPast
    private var lastFigures = Date.distantPast
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
        if wait <= 0 { sendHeld(force: false) } else { later(wait) }
    }

    /// Sends whatever is waiting, the totals too (before the run's last event).
    func flush() {
        lock.lock(); defer { lock.unlock() }
        sendHeld(force: true)
    }

    /// Called with the lock held.
    private func later(_ wait: Double) {
        guard !scheduled else { return }
        scheduled = true
        queue.asyncAfter(deadline: .now() + max(0, wait)) { [self] in
            lock.lock(); defer { lock.unlock() }
            scheduled = false
            sendHeld(force: false)
        }
    }

    /// Called with the lock held, so two batches never cross.
    private func sendHeld(force: Bool) {
        let now = Date()
        let figuresDue = figures != sent && (force || now.timeIntervalSince(lastFigures) >= Self.figuresEvery)
        if songs.isEmpty && notes.isEmpty && !figuresDue {
            if figures != sent { later(Self.figuresEvery - now.timeIntervalSince(lastFigures)) }
            return
        }
        // A long burst goes as several lines of at most `maxSongs`, the totals (when due) with the last.
        while songs.count > Self.maxSongs {
            send(Self.message(songs: Array(songs.prefix(Self.maxSongs)), notes: [], figures: nil))
            songs.removeFirst(Self.maxSongs)
        }
        send(Self.message(songs: songs, notes: notes, figures: figuresDue ? figures : nil))
        songs = []; notes = []; lastSent = now
        if figuresDue { sent = figures; lastFigures = now }
        else if figures != sent { later(Self.figuresEvery - now.timeIntervalSince(lastFigures)) }
    }

    static func message(songs: [RunSong], notes: [RunNote], figures: RunFigures?) -> [String: Any] {
        var m: [String: Any] = ["event": "run.songs", "songs": DeskProtocol.plain(songs), "notes": DeskProtocol.plain(notes)]
        if let figures { m["figures"] = DeskProtocol.plain(figures) }
        return m
    }
}
