import Foundation
import DeckieCrate
import DeckieRecognition
import DeckieCapture

/// Listening inside Desk (research booth-in-desk, step 1: hearing): the crate's recognition index built or opened,
/// sound from an input (`SoundSource`: the microphone, another input, or a stand-in in tests) fed to the shared
/// listener (`BoothRecogniser`, with the default `ListenSettings` on main), and what it hears said as events. The
/// Windows and Linux engine sends these as `booth.*` messages (DeskProtocol, docs/architecture/desk-protocol.md); the
/// Mac's Desk shows them in SwiftUI. Both use this one class.
///
/// **The song shown is simply the listener's current named song.** This is NOT yet the iPad's switching rule (its
/// waits, the careful wait, dominance, place jumps and pause: `deck-app/Deck/Sources/Recognizer.swift`, `take`).
/// Step 2 of the order of work moves that rule into the core; it plugs in at `take(_:)` below, which turns each
/// reading into what is shown, and nothing else here changes.
public final class DeskBooth: @unchecked Sendable {
    /// Where a crate's index is kept, in its own folder of Desk's storage (never in the crate file that leaves).
    public static let indexFile = "booth-index.dkx"

    /// What the mode is doing: `starting`, `index` (getting the crate's index ready: `percent`), `listening` (the
    /// input is on and the latest reading named a song, or none has come yet), `nothingHeard` (the input is on and the
    /// latest reading named nothing), `error` (`error` says why; the input is off), `stopped`.
    public struct Status: Sendable, Equatable {
        public var state: String
        public var percent: Int?
        /// Songs in the index (those with a fingerprint), once known.
        public var songs: Int?
        /// The input as the system names it, and the format it gives, once open.
        public var input: String?
        public var rate: Int?
        public var channels: Int?
        /// Whether the index was opened as kept (true) or made now (false), once ready.
        public var indexKept: Bool?
        public var error: CaptureError?
        public init(state: String, percent: Int? = nil, songs: Int? = nil, input: String? = nil, rate: Int? = nil,
                    channels: Int? = nil, indexKept: Bool? = nil, error: CaptureError? = nil) {
            self.state = state; self.percent = percent; self.songs = songs; self.input = input; self.rate = rate
            self.channels = channels; self.indexKept = indexKept; self.error = error
        }
    }

    /// One reading that names a song: the song as the crate has it, where in it the sound is, and how sure.
    public struct Heard: Sendable, Equatable, Codable {
        public var id: String
        /// The title as shown (with its version, as DJs write it), and the artist.
        public var title: String
        public var artist: String?
        /// Its tempo and key from the crate (nil when the crate has none).
        public var bpm: Double?
        public var camelot: String?
        public var key: String?
        public var scale: String?
        /// The song's length, in seconds.
        public var seconds: Double
        /// Where in the song the sound is now, in seconds.
        public var place: Double
        /// The listener's confidence (3 or more is a sure name from a search), and its state: `named` (just named by a
        /// search of the whole crate) or `held` (the song named before, still where it should be).
        public var confidence: Double
        public var reading: String
        /// The deck's speed as the fader would show it, in percent, and whether it seems to hold the key.
        public var speedPercent: Double?
        public var keyLock: Bool?
        /// Seconds heard since listening started, at the end of this reading.
        public var heardAt: Double
        /// Milliseconds the reading took to work out (a reading falls behind when this nears a second).
        public var milliseconds: Double
    }

    public enum Event: Sendable {
        case status(Status)
        case level(SoundLevel)
        case heard(Heard)
    }

    private let fingerprints: Crate.Fingerprints
    private let rows: [String: DeskSongRow]
    private let indexURL: URL
    private let source: SoundSource
    private let settings: ListenSettings
    private let out: @Sendable (Event) -> Void
    private let lock = NSLock()
    private var stopped = false
    private var capture: LiveCapture?
    private var listener: BoothRecogniser?
    private var status = Status(state: "starting")
    private var thread: Thread?
    private let finished = DispatchSemaphore(value: 0)

    /// `indexAt`: where the crate's index is kept (`CrateShelf.file(DeskBooth.indexFile, of: id)`).
    public init(crate: Crate, indexAt: URL, source: SoundSource, settings: ListenSettings = ListenSettings(),
                out: @escaping @Sendable (Event) -> Void) {
        fingerprints = crate.fingerprints()
        var r: [String: DeskSongRow] = [:]
        for t in crate.tracks { r[t.id] = DeskSongRow(t) }
        rows = r
        indexURL = indexAt
        self.source = source
        self.settings = settings
        self.out = out
    }

    /// Songs the crate has that the listener can name (those with a fingerprint).
    public var songCount: Int { fingerprints.count }

    /// The latest status.
    public var current: Status { lock.lock(); defer { lock.unlock() }; return status }

    private func say(_ s: Status) {
        lock.lock()
        if stopped && s.state != "stopped" { lock.unlock(); return }
        status = s
        lock.unlock()
        out(.status(s))
    }

    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    /// Starts, on a thread of its own: the index first (its progress said as `index` with a percent), then the input.
    public func start() {
        say(Status(state: "starting"))
        let t = Thread { [self] in
            run()
            finished.signal()
        }
        t.stackSize = 8 << 20
        thread = t
        t.start()
    }

    private func run() {
        // The index: each fingerprint read from the crate (the first half of the percent), then the index opened as
        // kept if it was made from these songs, else built and kept (the second half; it says nothing until done).
        let items = fingerprints.items
        var songs: [(id: String, landmarks: Landmarks)] = []
        var keys: [String?] = []
        var lastPercent = -1
        func progress(_ p: Int) {
            guard p != lastPercent else { return }
            lastPercent = p
            say(Status(state: "index", percent: p, songs: items.count))
        }
        progress(0)
        for (i, item) in items.enumerated() {
            if isStopped { return }
            if let landmarks = item.fingerprint.landmarks {
                songs.append((item.id, landmarks))
                keys.append(item.cutKey.flatMap { $0.isEmpty ? nil : $0 })
            }
            progress((i + 1) * 50 / max(1, items.count))
        }
        guard !songs.isEmpty else {
            say(Status(state: "error", songs: 0, error: CaptureError("noPrints", "no song in this crate has a fingerprint")))
            return
        }
        let stamp = RecognitionIndex.stamp(of: songs.map { ($0.id, $0.landmarks.count, $0.landmarks.frameCount) })
        let index: RecognitionIndex
        var built = false
        do {
            try FileManager.default.createDirectory(at: indexURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            index = try RecognitionIndex.cached(at: indexURL, stamp: stamp, sameRecording: keys) { built = true; return songs }
        } catch {
            say(Status(state: "error", songs: songs.count, error: CaptureError("index", "\(error)")))
            return
        }
        progress(100)
        if isStopped { return }

        // The listener, then the input.
        let booth = BoothRecogniser(index: index, settings: settings) { [weak self] reading in self?.take(reading) }
        let capture = LiveCapture(source)
        lock.lock(); listener = booth; self.capture = capture; lock.unlock()
        let out = self.out
        do {
            let format = try capture.start(sound: { samples, format in
                booth.feed(samples, channels: format.channels, sampleRate: format.rate)
            }, level: { [weak self] level in
                guard let self, !self.isStopped else { return }
                out(.level(level))
            }, ended: { [weak self] e in self?.fail(e) })
            // Stopped while the input was opening: it is closed again at once.
            if isStopped { capture.stop(); return }
            var s = Status(state: "listening", songs: index.songCount, input: source.name, rate: format.rate,
                           channels: format.channels, indexKept: !built)
            s.error = nil
            say(s)
        } catch let e as CaptureError {
            fail(e)
        } catch {
            fail(CaptureError("failed", "\(error)"))
        }
    }

    private func fail(_ e: CaptureError) {
        lock.lock(); let c = capture; capture = nil; lock.unlock()
        // The input's own thread may be the caller (an unplugged input): stop it from another.
        if let c { DispatchQueue.global().async { c.stop() } }
        var s = current
        s.state = "error"; s.error = e
        say(s)
    }

    /// Each reading becomes what is shown. Step 1: the listener's current named song as it is. Step 2 replaces this
    /// with the iPad's switching rule, moved into the core (research booth-in-desk, section 1).
    private func take(_ r: ListenReading) {
        guard !isStopped else { return }
        guard r.state != .nothingYet, let id = r.id, let row = rows[id] else {
            let s = current
            if s.state == "listening" { var n = s; n.state = "nothingHeard"; say(n) }
            return
        }
        let s = current
        if s.state == "nothingHeard" { var n = s; n.state = "listening"; say(n) }
        out(.heard(Heard(id: id, title: row.shown, artist: row.artist, bpm: row.bpm, camelot: row.key?.camelot,
                         key: row.key?.key, scale: row.key?.scale, seconds: row.seconds, place: r.positionSeconds ?? 0,
                         confidence: r.confidence, reading: r.state.rawValue, speedPercent: r.speedPercent,
                         keyLock: r.keyLock, heardAt: r.time, milliseconds: r.milliseconds)))
    }

    /// Stops the input (nothing more is heard once this returns) and says `stopped`. Does not wait for an index being
    /// built: that finishes on its own thread and is kept for next time.
    public func stop() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        let c = capture
        capture = nil
        lock.unlock()
        c?.stop()
        lock.lock(); status = Status(state: "stopped"); lock.unlock()
        out(.status(Status(state: "stopped")))
    }

    /// Waits until the index is ready and the input started or failed (tests and tools): at most `seconds` (nil: for
    /// as long as it takes). False when the time ran out first.
    @discardableResult
    public func waitUntilStarted(within seconds: Double? = nil) -> Bool {
        if let seconds {
            guard finished.wait(timeout: .now() + seconds) == .success else { return false }
        } else {
            finished.wait()
        }
        finished.signal()
        return true
    }

    /// Waits until everything heard so far has been read (tests and tools).
    public func finishReading() {
        lock.lock(); let b = listener; let c = capture; lock.unlock()
        c?.flushLevels()
        b?.finish()
    }
}
