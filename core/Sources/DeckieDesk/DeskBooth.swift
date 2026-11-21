import Foundation
import DeckieCrate
import DeckieRecognition
import DeckieCapture
import DeckieBooth

/// Listening inside Desk (research booth-in-desk, step 1: hearing): the crate's recognition index built or opened,
/// sound from an input (`SoundSource`: the microphone, another input, or a stand-in in tests) fed to the shared
/// listener (`BoothRecogniser`, with the default `ListenSettings`, the products' listener, D41), and what it hears said as events. The
/// Windows and Linux engine sends these as `booth.*` messages (DeskProtocol, docs/architecture/desk-protocol.md); the
/// Mac's Desk shows them in SwiftUI. Both use this one class.
///
/// **The song shown is the iPad's** (step 2, D42): every reading goes through the shared switching rule
/// (DeckieBooth's `BoothRule`, the code the iPad app runs), once a second the rule's clock is ticked, and what the rule
/// puts on screen is said as `playing`; the picks for that song (DeckieBooth's `BoothPicks`, the iPad's ranking, tags
/// and words) as `picks`. The listener's raw reading is still said as `heard`, for what came before step 2.
public final class DeskBooth: @unchecked Sendable {
    /// Where a crate's index is kept, in its own folder of Desk's storage (never in the crate file that leaves).
    public static let indexFile = "booth-index.dkx"

    /// Below this loudest-sample level, in dB below full scale, the input is taken to be giving no sound at all. It
    /// sits well above the floor of 16-bit sound and its dither (about -90 to -96 dB), where an input that is switched
    /// off, refused or not connected rests (the Windows pass, Nov 21, 2026: a virtual machine's microphone), and well
    /// under the noise any working microphone picks up in a room. Not fitted to any recording.
    public static let noSoundFloorDB = -70.0
    /// Seconds the input stays under that floor, or gives nothing at all, before the mode says no sound is coming:
    /// longer than the gaps inside music and between songs, short enough that a DJ is told while still looking.
    public static let noSoundAfter = 5.0

    /// What the mode is doing: `starting`, `index` (getting the crate's index ready: `percent`), `listening` (the
    /// input is on and the latest reading named a song, or none has come yet), `nothingHeard` (the input is on and the
    /// latest reading named nothing, and no song has been named since listening started), `nothingNow` (added Nov 21,
    /// 2026: as `nothingHeard`, after a song was named earlier in this listening), `noSound` (added Nov 21, 2026: the
    /// input is on but has given no sound, or only
    /// sound under `noSoundFloorDB`, for `noSoundAfter` seconds; back to `listening` by itself when sound comes),
    /// `error` (`error` says why; the input is off), `stopped`.
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

    /// What the shared switching rule puts on screen (added Nov 21, 2026, step 2): the song the iPad would show, or none.
    public struct Playing: Sendable, Equatable {
        /// The song on screen, as the crate has it (`place` and `heardAt` are the rule's); nil when none is.
        public var song: Heard?
        /// The deck's pitch as the rule shows it (a tenth of a percent), how it reads (`vinyl`, `master tempo` or ""),
        /// and the rate the place moves at.
        public var pitch: Double
        public var pitchKind: String
        public var rate: Double
        /// Not heard for a few seconds (the song stays), and paused (the room quiet as well, its place frozen).
        public var notHeard: Bool
        public var paused: Bool
        /// Another song heard while this one is kept, as shown (its title); nil when none.
        public var alsoHearing: String?
        /// 0...1, how consistent the last readings are.
        public var confidence: Double
        /// The song changed with this event.
        public var newSong: Bool
    }

    /// One pick, with the iPad's words for it.
    public struct Pick: Sendable, Equatable {
        public var id: String
        /// The title as shown, the artist, the tempo and the key as the song shows them.
        public var title: String
        public var artist: String?
        public var bpm: Double?
        public var key: String
        /// `pick`, or `pinned` (not yet: nothing pins on a computer).
        public var kind: String
        /// What is unexpected about it ("half time", "to CD2", "deep cut", ...).
        public var tags: [String]
        /// "128 BPM · pitch +3.2%", "blend · key clash", "8A → 9A".
        public var bpmLine: String
        public var moveLine: String
        public var keys: String
        public var score: Double?
    }

    /// The picks for the song on screen (added Nov 21, 2026, step 2): the shortlist's size, how many more songs follow
    /// it in the whole list, the Shuffle dial they were rolled with, and the picks the iPad shows in Full (up to 10).
    public struct Picks: Sendable, Equatable {
        public var forId: String
        public var shortlist: Int
        public var more: Int
        public var shuffle: Double
        public var picks: [Pick]
    }

    public enum Event: Sendable {
        case status(Status)
        case level(SoundLevel)
        case heard(Heard)
        /// Added Nov 21, 2026 (step 2).
        case playing(Playing)
        case picks(Picks)
        /// How long the listener's readings took, in one line, once when listening stops or fails
        /// ("listener: a, 142 readings, typical 61 ms, slowest 240 ms"). Also kept in `timesFile`.
        case times(String)
    }

    /// The file beside the index where each listening's times line is kept, one line each, with the date.
    public static let timesFile = "booth-times.log"

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
    /// The no-sound watch: where the quiet began, in seconds heard (the level's own queue alone uses these two), and
    /// the clock for an input that gives no samples at all.
    private var quietFrom: Double?
    /// Whether a song has been named since this listening started (under `lock`).
    private var namedOnce = false
    private var lastLevelAt = 0.0
    private var watch: DispatchSourceTimer?

    // The shared brains (under `lock`): the crate as Booth sees it, the switching rule, its clock, and the picks.
    private let crate: Crate
    private let shuffle: Double
    private var library: BoothLibrary?
    private var rule = BoothRule()
    private var listenedFrom = Date()
    private var levelDB: Float = -20
    private var ticker: DispatchSourceTimer?
    private var picksFor: String?
    private var picksPitch: Double?
    private var ranked: (list: [BoothPick], shortlist: Int)?
    private var timesTold = false

    /// `indexAt`: where the crate's index is kept (`CrateShelf.file(DeskBooth.indexFile, of: id)`).
    /// `shuffle`: the Shuffle dial the picks are rolled with (0: the shortlist in score order; 1: a fair shuffle; the
    /// iPad's own default is 0.5).
    public init(crate: Crate, indexAt: URL, source: SoundSource, settings: ListenSettings = ListenSettings(), shuffle: Double = 0.5,
                out: @escaping @Sendable (Event) -> Void) {
        self.crate = crate
        self.shuffle = shuffle.isFinite ? min(1, max(0, shuffle)) : 0.5
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
        // The crate as Booth sees it, for the switching rule and the picks (the picks' scoring pool is built here once).
        let lib = BoothLibrary(crate)
        lock.lock(); library = lib; rule = BoothRule(); listenedFrom = Date(); lock.unlock()
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
                self.hearLevel(level)
                self.lock.lock(); self.levelDB = Float(level.rmsDB); self.lock.unlock()
            }, ended: { [weak self] e in self?.fail(e) })
            // Stopped while the input was opening: it is closed again at once.
            if isStopped { capture.stop(); return }
            var s = Status(state: "listening", songs: index.songCount, input: source.name, rate: format.rate,
                           channels: format.channels, indexKept: !built)
            s.error = nil
            say(s)
            watchForNoSamples(capture)
            startTicking()
        } catch let e as CaptureError {
            fail(e)
        } catch {
            fail(CaptureError("failed", "\(error)"))
        }
    }

    /// Moves the state from one of `from` to `to`, and says it; nothing when the state is another, or after stop.
    private func move(from: Set<String>, to state: String) {
        lock.lock()
        guard !stopped, from.contains(status.state) else { lock.unlock(); return }
        var n = status
        n.state = state
        status = n
        lock.unlock()
        out(.status(n))
    }

    /// The states in which the input is on and heard.
    private static let hearing: Set<String> = ["listening", "nothingHeard", "nothingNow"]

    /// Each level, on the level's queue: under the floor for `noSoundAfter` seconds of sound is `noSound`; a level over
    /// it, while `noSound`, is `listening` again (the next reading says whether a song is named).
    private func hearLevel(_ l: SoundLevel) {
        let start = lastLevelAt
        lastLevelAt = l.seconds
        if l.peakDB < Self.noSoundFloorDB {
            let from = quietFrom ?? start
            quietFrom = from
            if l.seconds - from >= Self.noSoundAfter { move(from: Self.hearing, to: "noSound") }
        } else {
            quietFrom = nil
            move(from: ["noSound"], to: "listening")
        }
    }

    /// An input that gives no samples at all has no levels to measure: a clock checks, twice a second, and says
    /// `noSound` once `noSoundAfter` seconds have passed with nothing. Only until the first samples come; from then on
    /// the levels say it.
    private func watchForNoSamples(_ capture: LiveCapture) {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "deckie.booth.watch"))
        let began = DispatchTime.now().uptimeNanoseconds
        timer.schedule(deadline: .now() + 0.5, repeating: 0.5)
        // The handler holds the timer (on Linux a timer cannot be held weakly); cancelling it lets both go.
        timer.setEventHandler { [weak self] in
            guard let self else { timer.cancel(); return }
            if capture.framesHeard > 0 || self.isStopped { timer.cancel(); return }
            if Double(DispatchTime.now().uptimeNanoseconds - began) / 1e9 >= Self.noSoundAfter {
                self.move(from: Self.hearing, to: "noSound")
            }
        }
        lock.lock(); watch?.cancel(); watch = timer; lock.unlock()
        timer.resume()
    }

    /// The rule's clock, once a second while listening (pauses, "not heard just now", the two-minute rule).
    private func startTicking() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "deckie.booth.tick"))
        timer.schedule(deadline: .now() + 1, repeating: 1)
        // The handler holds the timer (on Linux a timer cannot be held weakly); cancelling it lets both go.
        timer.setEventHandler { [weak self] in
            guard let self, !self.isStopped else { timer.cancel(); return }
            self.tickRule()
        }
        lock.lock(); ticker?.cancel(); ticker = timer; lock.unlock()
        timer.resume()
    }

    private func tickRule() {
        lock.lock()
        guard let lib = library else { lock.unlock(); return }
        let before = rule.currentId, wasNotHeard = rule.notHeard, wasPaused = rule.paused
        rule.tick(now: Date(), source: .listening, deckie: true, level: levelDB)
        _ = rule.takeNotes()
        let changed = before != rule.currentId || wasNotHeard != rule.notHeard || wasPaused != rule.paused
        let shown = changed ? playing(lib, newSong: false) : nil
        lock.unlock()
        if let shown { out(.playing(shown)) }
    }

    /// What the rule shows now (called with the lock held).
    private func playing(_ lib: BoothLibrary, newSong: Bool) -> Playing {
        let now = Date()
        var song: Heard?
        if let id = rule.currentId {
            let row = rows[id]
            song = Heard(id: id, title: row?.shown ?? lib.song(id)?.song ?? id, artist: row?.artist, bpm: row?.bpm,
                         camelot: row?.key?.camelot, key: row?.key?.key, scale: row?.key?.scale, seconds: row?.seconds ?? 0,
                         place: rule.positionKnown ? rule.position(at: now) : 0, confidence: rule.confidence(now: now, source: .listening),
                         reading: "shown", speedPercent: rule.pitchPct, keyLock: rule.pitchKind == .masterTempo ? true : rule.pitchKind == .vinyl ? false : nil,
                         heardAt: now.timeIntervalSince(listenedFrom), milliseconds: rule.lastLatencyMs)
        }
        let also = rule.alsoHearingId.map { rows[$0]?.shown ?? lib.song($0)?.song ?? $0 }
        return Playing(song: song, pitch: rule.pitchPct, pitchKind: rule.pitchKind.rawValue, rate: rule.rate, notHeard: rule.notHeard,
                       paused: rule.paused, alsoHearing: also, confidence: rule.confidence(now: now, source: .listening), newSong: newSong)
    }

    /// The picks for the song on screen: ranked again when the song changes (the songs played before left out, as on the
    /// iPad), their words again when the pitch shown moves (the join's pitch follows the playing deck's). Nil when
    /// neither changed. Called with the lock held.
    private func picksNow(_ lib: BoothLibrary) -> Picks? {
        guard let cur = rule.current(in: lib) else { picksFor = nil; ranked = nil; return nil }
        let pitch = rule.pitchPct
        if picksFor == cur.id, picksPitch == pitch { return nil }
        if picksFor != cur.id || ranked == nil {
            var rng = SystemRandomNumberGenerator()
            ranked = BoothPicks(lib).ranked(cur: cur, target: BoothFilter(), exclude: Set(rule.history.suffix(12)), pinned: nil,
                                            shuffle: shuffle, rng: &rng)
        }
        picksFor = cur.id; picksPitch = pitch
        guard let ranked else { return nil }
        let split = BoothPicks.split(ranked.list, shortlist: ranked.shortlist, full: true)
        let picks = BoothPicks(lib)
        let shownPicks: [Pick] = split.shown.compactMap { op in
            guard let target = lib.placed(op.id, playingDisc: cur.disc, among: picks.allowsPlace(BoothFilter())) else { return nil }
            let ji = BoothJoin(cur, target, op.pair, deckAPitch: pitch)
            let row = rows[op.id]
            return Pick(id: op.id, title: row?.shown ?? target.song, artist: row?.artist, bpm: target.bpm ?? target.bpmTag, key: target.keyShown,
                        kind: op.kind == .pinned ? "pinned" : "pick", tags: op.tags, bpmLine: BoothJoin.bpmLine(target, op.pair, ji),
                        moveLine: BoothJoin.moveLine(op.pair, ji), keys: ji.keyText, score: op.pair?.s)
        }
        return Picks(forId: cur.id, shortlist: ranked.shortlist, more: split.more.count, shuffle: shuffle, picks: shownPicks)
    }

    /// The listener's times line, said once and kept in `timesFile` beside the index.
    private func tellTimes() {
        lock.lock()
        guard !timesTold, let b = listener else { lock.unlock(); return }
        timesTold = true
        lock.unlock()
        let line = b.timesLine
        let file = indexURL.deletingLastPathComponent().appendingPathComponent(Self.timesFile)
        let stamp = ISO8601DateFormatter().string(from: Date())
        if let data = "\(stamp) \(line)\n".data(using: .utf8) {
            if let h = try? FileHandle(forWritingTo: file) {
                h.seekToEndOfFile(); h.write(data); try? h.close()
            } else {
                try? data.write(to: file)
            }
        }
        out(.times(line))
    }

    private func fail(_ e: CaptureError) {
        lock.lock(); let c = capture; capture = nil; watch?.cancel(); watch = nil; ticker?.cancel(); ticker = nil; lock.unlock()
        // The input's own thread may be the caller (an unplugged input): stop it from another.
        if let c { DispatchQueue.global().async { c.stop() } }
        var s = current
        s.state = "error"; s.error = e
        say(s)
        tellTimes()
    }

    /// Each reading: the listener's raw answer said as `heard` (and the state line), then the reading through the shared
    /// switching rule, as the iPad takes it (`heard`: the moment the sound ended, the reading's milliseconds before now),
    /// and what the rule shows said as `playing`, with the picks for that song when it changed.
    private func take(_ r: ListenReading) {
        guard !isStopped else { return }
        defer { shareReading(r) }
        guard r.state != .nothingYet, let id = r.id, let row = rows[id] else {
            // "Nothing heard yet" only until a song has been named in this listening; after that, "nothing now".
            lock.lock(); let before = namedOnce; lock.unlock()
            move(from: ["listening"], to: before ? "nothingNow" : "nothingHeard")
            return
        }
        lock.lock(); namedOnce = true; lock.unlock()
        // A song named is sound arriving.
        move(from: ["nothingHeard", "nothingNow", "noSound"], to: "listening")
        out(.heard(Heard(id: id, title: row.shown, artist: row.artist, bpm: row.bpm, camelot: row.key?.camelot,
                         key: row.key?.key, scale: row.key?.scale, seconds: row.seconds, place: r.positionSeconds ?? 0,
                         confidence: r.confidence, reading: r.state.rawValue, speedPercent: r.speedPercent,
                         keyLock: r.keyLock, heardAt: r.time, milliseconds: r.milliseconds)))
    }

    /// The reading through the shared rule (called on the listener's thread).
    private func shareReading(_ r: ListenReading) {
        let now = Date()
        lock.lock()
        guard !stopped, let lib = library else { lock.unlock(); return }
        var shown: Playing?, picks: Picks?
        if let reading = BoothReading(deckie: r, heard: now.addingTimeInterval(-r.milliseconds / 1000)) {
            let outcome = rule.take(reading, in: lib, now: now, source: .listening, level: levelDB, startedAt: listenedFrom)
            _ = rule.takeNotes()
            var newSong = false
            if case let .shown(n) = outcome { newSong = n }
            shown = playing(lib, newSong: newSong)
            picks = picksNow(lib)
        }
        lock.unlock()
        if let shown { out(.playing(shown)) }
        if let picks { out(.picks(picks)) }
    }

    /// Stops the input (nothing more is heard once this returns) and says `stopped`. Does not wait for an index being
    /// built: that finishes on its own thread and is kept for next time.
    public func stop() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        stopped = true
        let c = capture
        capture = nil
        watch?.cancel()
        watch = nil
        ticker?.cancel()
        ticker = nil
        lock.unlock()
        c?.stop()
        tellTimes()
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
