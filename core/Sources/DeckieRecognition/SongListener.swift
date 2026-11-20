import Foundation

// The booth-facing recogniser: fed the microphone for a whole set, it says what is playing.
//
//   let index = try RecognitionIndex(contentsOf: indexFile)          // made once per crate file, opened in place
//   let booth = BoothRecogniser(index: index) { reading in ... }      // called about once a second, off the caller's thread
//   booth.feed(samples, sampleRate: 48000)                            // from the audio callback; returns at once
//
// `SongListener` is the same thing without threads, for tests and for playing a recording through it.

/// What the listener says after each second of sound.
public struct ListenReading: Sendable, Equatable {
    public enum State: String, Sendable {
        /// No song can be named from what has been heard.
        case nothingYet
        /// A song has just been named by searching the whole crate.
        case named
        /// The song named earlier is still where it should be.
        case held
    }
    /// Seconds of sound heard since the listener started, at the end of this reading's window.
    public var time: Double
    public var state: State
    /// The song: its number in the index and its id in the crate file (nil with `nothingYet`).
    public var songIndex: Int?
    public var id: String?
    /// Where in the song the sound is now, in seconds.
    public var positionSeconds: Double?
    /// The deck's speed as the fader would show it, in percent.
    public var speedPercent: Double?
    /// Whether the deck seems to hold the key: true when the pitch has not moved with the speed, false when it has
    /// (a turntable, or key lock off), nil within 1 % of zero where the two cannot be told apart.
    public var keyLock: Bool?
    /// How sure: for `named`, the song's standing against the other songs (3 or more is a sure name); for `held`,
    /// how far the count of agreeing points stands above chance.
    public var confidence: Double
    /// Milliseconds this reading took to work out.
    public var milliseconds: Double
    /// For measuring: what this reading's search of the whole crate found, whether or not it was taken as a name
    /// (nil when no search ran, or it found nothing): the song's id, its confidence, and whether it lies on the
    /// same line as the search before.
    public var searched: Searched?
    public struct Searched: Sendable, Equatable {
        public var id: String
        public var confidence: Double
        public var agrees: Bool
    }
}

/// The numbers the listener runs on. Each is from the benchmark's dev half or a first principle named beside it
/// (docs/research/w4-recognition-complete.md).
public struct ListenSettings: Sendable, Equatable {
    /// Seconds between readings.
    public var step = 1.0
    /// The most sound a search looks at, and the least it will try.
    public var window = 8.0
    public var leastWindow = 3.0
    /// When a search of the last `window` seconds names nothing and more has been heard, the last `longWindow`
    /// seconds are searched as well: more sound is worth more in noise (12 s names about ten in a hundred more than
    /// 8 s at equal-level crowd noise), and it costs time only while nothing is named.
    public var longWindow = 12.0
    /// A search's answer is taken at once at this confidence.
    public var sure = 3.0
    /// Two searches in a row that put the same song on the same line (place and speed agreeing to `agreeSeconds`)
    /// are taken together when each reaches this.
    public var fair = 2.6
    public var agreeSeconds = 0.5
    /// A song being followed is still there when its points agree this far above chance...
    public var holdScore = 6.0
    /// ...over the last this many seconds of sound only, so that a song that has ended stops being shown soon...
    public var holdWindow = 5.0
    /// ...and is given up after this many readings in a row without that.
    public var lostAfter = 2
    /// While following, the whole crate is searched again every this many readings, to notice a new song early.
    public var searchEvery = 2
    /// Songs whose first proposals are checked point by point in a search.
    public var checkSongs = 50
    /// Whether the microphone's constellation is made denser than a song's (a point need only be the loudest within
    /// 64 ms and 8 %, not 96 ms and 12 %) and three points are taken per slice, not two. It helped a thin index of
    /// three-point hashes; with the booth's two-point index it gained nothing and tripled the time, so it is off.
    public var denseQuery = false
    /// Whether a named song is followed (false, for measuring only: every reading is a fresh search and nothing is named).
    public var follow = true

    // The settings below are all off by default; with them off the listener is the one described above, reading for
    // reading (docs/research/faster-listening-proposals.md).

    /// While a song is followed, the whole-crate search looks at the last this many seconds only (the fast setting:
    /// 4; at 8, the window, nothing changes).
    public var followSearchWindow = 8.0
    /// After the followed song first fails its check, the searches look at the sound since then and this many seconds
    /// before it, not the whole window, which still holds the song that has gone (nil: off).
    public var searchSinceMiss: Double? = nil
    /// Proposal A. While a song is followed and passes its check, the newest `challengeWindow` seconds are also
    /// searched every reading. Another song found there is a challenger: it is fitted against the followed song on
    /// the same sound, and replaces it only when it is sure and its score is more than `challengeMargin` times the
    /// followed song's.
    public var challenger = false
    public var challengeWindow = 4.0
    public var challengeMargin = 2.0          // chosen on the dev half from 1.5, 2 and 3 (3 a second slower; 1.5 and 2 alike)
    /// Proposal B. The followed song's own points are watched for the moment they stop pairing (a CUSUM test, Page
    /// 1954): point by point, "still here" (paired at the rate this song has shown) against "gone" (paired at chance).
    /// Its bar is set so that a false alarm comes on average no more often than once in `cutFalseAlarmSeconds` of
    /// points whose pairing follows the model (Lorden 1971: the mean run to a false alarm is at least e^bar points).
    /// After an alarm the crate is searched every reading in the sound since that moment only.
    public var cutWatch = false
    public var cutFalseAlarmSeconds = 3600.0
    /// After an alarm, the least sound since its moment that is searched (nil: `leastWindow`, 3 s). B and A+B use 2,
    /// chosen on the dev half against 3 (half a second sooner, no more wrong names or jumps than the default).
    public var cutSearchFrom: Double? = nil
    public init() {}

    /// The listeners compared in docs/research/faster-listening-proposals.md, by the names the tools use.
    public enum Listener: String, CaseIterable, Sendable { case main, fast, a, b, ab }
    public init(_ listener: Listener) {
        self.init()
        switch listener {
        case .main: break
        case .fast: self = .fast
        case .a: challenger = true; searchSinceMiss = challengeWindow
        case .b: cutWatch = true; cutSearchFrom = 2
        case .ab: challenger = true; searchSinceMiss = challengeWindow; cutWatch = true; cutSearchFrom = 2
        }
    }

    /// The fast setting of docs/research/w5-recognition-by-five-seconds.md (branch recog/fast): while a song is
    /// followed the whole crate is searched every second in the newest 4 s, the first search is made after 2 s, and
    /// after a failed check the search looks only at the sound since then.
    public static var fast: ListenSettings {
        var s = ListenSettings()
        s.searchEvery = 1
        s.followSearchWindow = 4
        s.leastWindow = 2
        s.searchSinceMiss = 4
        return s
    }
}

/// Listens to a stream of sound and names the song. Not thread-safe: one caller at a time (see `BoothRecogniser`).
public final class SongListener {
    public let index: RecognitionIndex
    public var settings: ListenSettings
    private let recogniser: Recogniser
    private let queryConfig: LandmarkConfig
    /// The last `settings.window` seconds of sound, mono, at the rate it arrives.
    private var sound: [Float] = []
    private var rate = 0
    private var heard = 0          // samples heard in all, at `rate`
    private var nextReading = 0    // the sample count at which the next reading is due
    /// The song being followed: its number, the line it is on (song seconds = intercept + tempo x listening seconds)
    /// and its pitch ratio.
    private var following: (song: Int, intercept: Double, tempo: Double, pitch: Double)?
    private var misses = 0
    private var missedSince: Double?      // when the followed song first failed its check, until a name is taken again
    /// A and B: after a switch made early (a challenger, or a name found after an alarm), the moment before which the
    /// sound is not searched again, for one window's length: it holds the song just left, which would otherwise be
    /// found there and named back.
    private var floor: Double?
    private var sinceSearch = 0
    /// B: the watch on the followed song's points. `sum` is the CUSUM, `lastZero` the time it last stood at 0 (the
    /// change's estimated moment), `seenTo` the newest point fed in, `rates` the song's pairing rate on its last
    /// readings, `points` and `seconds` for the rate of points an hour. `cut` is the moment of an alarm, until a
    /// name is taken, the alarm is withdrawn, or a window's length of sound has followed it.
    private var watch = Watch()
    private struct Watch {
        var sum = 0.0, lastZero = 0.0, seenTo = -Double.infinity
        var rates: [Double] = [], chance = 0.0
        var points = 0, seconds = 0.0
        var cut: Double?
        mutating func restart() { let p = points, s = seconds; self = Watch(); points = p; seconds = s }
    }
    /// The last search's answer that was fair but not sure, waiting for a second to agree with it.
    private var pending: (song: Int, intercept: Double, tempo: Double)?
    public private(set) var latest: ListenReading?

    public init(index: RecognitionIndex, settings: ListenSettings = ListenSettings()) {
        self.index = index; self.settings = settings
        recogniser = Recogniser(index: index)
        recogniser.checkSongs = settings.checkSongs
        if settings.denseQuery { recogniser.queryPerSlice = 3 }
        var c = index.landmark
        if settings.denseQuery { c.timeReach = 4; c.frequencyReach = 0.08 }
        queryConfig = c
    }

    /// Bytes this listener holds in the app's own memory: its vote table (a byte for every 128 ms of every song) and
    /// its window of sound. The index itself is counted by `RecognitionIndex`.
    public var workingBytes: Int { index.timelineFrames / 8 + 2 + sound.capacity * 4 }

    /// Forgets everything heard (a new set, or the sound's rate changed).
    public func reset() {
        sound.removeAll(keepingCapacity: true); heard = 0; nextReading = 0
        following = nil; pending = nil; misses = 0; sinceSearch = 0; latest = nil
        missedSince = nil; watch = Watch(); floor = nil
    }

    /// Takes more sound (interleaved if more than one channel) and returns a reading for each second completed.
    public func hear(_ samples: [Float], channels: Int = 1, sampleRate: Int) -> [ListenReading] {
        if sampleRate != rate { reset(); rate = sampleRate }
        let keep = Int(max(settings.window, settings.longWindow) * Double(rate))
        var out: [ListenReading] = []
        let ch = max(1, channels)
        var i = 0
        let frames = samples.count / ch
        while i < frames {
            if nextReading <= heard { nextReading = heard + Int(settings.step * Double(rate)) }
            let take = min(frames - i, nextReading - heard)
            if ch == 1 {
                sound.append(contentsOf: samples[i..<(i + take)])
            } else {
                for f in i..<(i + take) {
                    var sum: Float = 0
                    for c in 0..<ch { sum += samples[f * ch + c] }
                    sound.append(sum / Float(ch))
                }
            }
            i += take; heard += take
            if sound.count > 2 * keep { sound.removeFirst(sound.count - keep) }
            if heard == nextReading, let reading = pooled({ read() }) { out.append(reading); latest = reading }
        }
        return out
    }

    private func read() -> ListenReading? {
        let t0 = DispatchTime.now().uptimeNanoseconds
        let now = Double(heard) / Double(rate)
        let have = min(Double(sound.count) / Double(rate), settings.window)
        guard have >= settings.leastWindow else { return nil }
        let window = Array(sound.suffix(Int(have * Double(rate))))
        let marks = Landmarks(mono: window, sampleRate: rate, config: queryConfig)
        let start = now - have          // listening time of the window's first sample
        let fs = queryConfig.frameSeconds
        /// The window's points from listening time `t` on, and the listening time their frames count from.
        func since(_ t: Double) -> (Landmarks, Double) {
            guard t > start else { return (marks, start) }
            let skip = ((t - start) / fs).rounded()
            return (marks.suffix(fromSeconds: t - start, frameSeconds: fs), start + skip * fs)
        }
        var state = ListenReading.State.nothingYet
        var confidence = 0.0
        var searched: ListenReading.Searched?
        var named = false

        // B: an alarm lasts until a window's length of sound has followed it.
        if let c = watch.cut, now - c >= settings.window { watch.restart() }
        if let fl = floor, now - fl >= settings.window { floor = nil }

        // Follow the song already named: one check, at the place and speed it should be at.
        if let f = following {
            // The check looks at the newest sound only: the points of the window's last `holdWindow` seconds.
            let recent = have > settings.holdWindow ? marks.suffix(fromSeconds: have - settings.holdWindow, frameSeconds: fs) : marks
            let from = now - min(have, settings.holdWindow)
            let m = recogniser.check(recent, song: f.song, offsetSeconds: f.intercept + f.tempo * from, tempoRatio: f.tempo, pitchRatio: f.pitch)
            if settings.cutWatch, watch.cut == nil, misses == 0 { watchPoints(recent, from: from, match: m, now: now) }
            if let m, m.score >= settings.holdScore {
                following = (f.song, m.offsetSeconds - m.tempoRatio * from, m.tempoRatio, m.pitchRatio)
                misses = 0; state = .held; confidence = m.score; missedSince = nil
            } else {
                misses += 1
                if missedSince == nil { missedSince = now }
                if misses >= settings.lostAfter { following = nil }
                else { state = .held; confidence = 0 }       // carried over a gap: still shown, on its last line
            }
        }
        // B: if the followed song fits the sound since the alarm after all, the alarm was false.
        if settings.cutWatch, let c = watch.cut, let f = following, now - c >= settings.leastWindow {
            let (after, at) = since(c)
            if let m = recogniser.check(after, song: f.song, offsetSeconds: f.intercept + f.tempo * at, tempoRatio: f.tempo, pitchRatio: f.pitch),
               m.score >= settings.holdScore { watch.restart() }
        }
        // A: a challenger in the newest sound, judged against the followed song on that same sound.
        if settings.challenger, let f = following, misses == 0, state == .held {
            let (short, at) = have > settings.challengeWindow ? since(now - settings.challengeWindow) : (marks, start)
            let found = recogniser.match(short)
            if let other = found.first(where: { $0.songIndex != f.song && !index.isRelated($0.songIndex, f.song) }), other.confidence >= settings.sure {
                let line = (song: other.songIndex, intercept: other.offsetSeconds - other.tempoRatio * at, tempo: other.tempoRatio)
                let held = recogniser.check(short, song: f.song, offsetSeconds: f.intercept + f.tempo * at, tempoRatio: f.tempo, pitchRatio: f.pitch)?.score ?? 0
                searched = ListenReading.Searched(id: index.ids[other.songIndex], confidence: other.confidence, agrees: false)
                // Only a clear lead counts. Being ahead by a hair on two readings in a row (the blend rule first
                // proposed) is a coin toss where both songs hold the same passage, and it named the other song in
                // a test of exactly that; a song fading in gets clearly ahead after the middle of the blend.
                if other.score > settings.challengeMargin * max(held, 0) {
                    following = (other.songIndex, line.intercept, other.tempoRatio, other.pitchRatio)
                    state = .named; confidence = other.confidence; named = true
                    pending = nil; missedSince = nil; watch.restart()
                    floor = at
                }
            }
        }
        // Search the whole crate: always when nothing is followed, and every few readings when something is. Then,
        // if nothing is named and there is more sound to go on, once more over the longer window.
        sinceSearch += 1
        var tries: [(Landmarks, Double)] = []
        let followed = misses == 0 ? following?.song : nil      // the song held at this reading, if any
        let alarm = settings.cutWatch ? watch.cut : nil
        if named {
        } else if let c = alarm {
            // B: every reading, in the sound since the song went only, once there is enough of it.
            sinceSearch = 0
            if now - c >= (settings.cutSearchFrom ?? settings.leastWindow) { tries.append(since(c)) }
        } else if following == nil || misses > 0 || sinceSearch >= settings.searchEvery {
            sinceSearch = 0
            if followed != nil, have > settings.followSearchWindow {
                tries.append((marks.suffix(fromSeconds: have - settings.followSearchWindow, frameSeconds: fs), now - settings.followSearchWindow))
            } else if let lead = settings.searchSinceMiss, let since = missedSince, now - since < settings.window, have > lead + (now - since) {
                // The song that was followed has just stopped fitting: what replaced it is in the newest sound, and
                // the older part of the window still holds the song that has gone.
                let span = lead + (now - since)
                tries.append((marks.suffix(fromSeconds: have - span, frameSeconds: fs), now - span))
            } else {
                if let since = missedSince, now - since >= settings.window { missedSince = nil }
                tries.append((marks, start))
            }
        }
        if let fl = floor {
            tries = tries.map { $0.1 >= fl ? $0 : since(fl) }
        }
        var tried = 0
        while tried < tries.count {
            let (marks, start) = tries[tried]
            tried += 1
            if tried == 1, following == nil, alarm == nil, floor == nil, settings.longWindow > settings.window {
                let longer = min(Double(sound.count) / Double(rate), settings.longWindow)
                if longer >= have + 1 {
                    tries.append((Landmarks(mono: Array(sound.suffix(Int(longer * Double(rate)))), sampleRate: rate, config: queryConfig), now - longer))
                }
            }
            if tried == 2, state == .named { break }
            if let best = recogniser.match(marks).first {
                let line = (song: best.songIndex, intercept: best.offsetSeconds - best.tempoRatio * start, tempo: best.tempoRatio)
                let agrees = pending.map { $0.song == line.song && abs(($0.intercept + $0.tempo * now) - (line.intercept + line.tempo * now)) <= settings.agreeSeconds } ?? false
                searched = ListenReading.Searched(id: index.ids[best.songIndex], confidence: best.confidence, agrees: agrees)
                let take = settings.follow && (best.confidence >= settings.sure || (best.confidence >= settings.fair && agrees))
                pending = best.confidence >= settings.fair || !settings.follow ? line : nil
                if take, following?.song != best.songIndex || misses > 0 {
                    following = (best.songIndex, line.intercept, best.tempoRatio, best.pitchRatio)
                    misses = 0; state = .named; confidence = best.confidence; missedSince = nil
                    if let c = alarm { floor = c }          // B: named from the sound since the alarm
                    watch.restart()
                } else if take, alarm != nil, following?.song == best.songIndex {
                    watch.restart()          // B: the same song again in the sound since the alarm: it was false
                }
            } else { pending = nil }
        }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6
        guard let f = following, state != .nothingYet else {
            return ListenReading(time: now, state: .nothingYet, songIndex: nil, id: nil, positionSeconds: nil, speedPercent: nil,
                                 keyLock: nil, confidence: 0, milliseconds: ms, searched: searched)
        }
        let lock: Bool? = abs(f.tempo - 1) < 0.01 ? nil : !(abs(log(f.pitch) - log(f.tempo)) < abs(log(f.pitch)))
        return ListenReading(time: now, state: state, songIndex: f.song, id: index.ids[f.song], positionSeconds: f.intercept + f.tempo * now,
                             speedPercent: (f.tempo - 1) * 100, keyLock: lock, confidence: confidence, milliseconds: ms, searched: searched)
    }

    /// B: feeds the points of the follow check heard since the last reading to the watch, in time order. A point that
    /// paired with the song adds log(chance / rate), one that did not adds log((1 - chance) / (1 - rate)); the sum is
    /// kept at 0 or above, and an alarm is raised when it passes log(points in `cutFalseAlarmSeconds`), at the moment
    /// it last stood at 0. Silent until the song's own rate is known from two readings and stands clear of chance.
    private func watchPoints(_ recent: Landmarks, from: Double, match m: RecognitionMatch?, now: Double) {
        let fs = queryConfig.frameSeconds
        let n = recogniser.usablePoints(recent)
        var paired = [Bool](repeating: false, count: n)
        if m != nil { for i in recogniser.lastPaired where i < n { paired[i] = true } }
        if let m { watch.chance = m.chance }
        let fresh = (0..<n).filter { from + Double(recent.frames[$0]) * fs > watch.seenTo }
        if watch.seenTo.isFinite { watch.points += fresh.count; watch.seconds += settings.step }
        let perSecond = watch.seconds >= 3 ? Double(watch.points) / watch.seconds : 50
        let bar = log(settings.cutFalseAlarmSeconds * max(1, perSecond))
        let p0 = watch.chance
        let p1 = watch.rates.count >= 2 ? watch.rates.reduce(0, +) / Double(watch.rates.count) : 0
        if p0 > 0, p1 > 1.5 * p0, p1 < 1 {
            let hit = log(p0 / p1), miss = log((1 - p0) / (1 - p1))
            for i in fresh {
                let t = from + Double(recent.frames[i]) * fs
                watch.sum = max(0, watch.sum + (paired[i] ? hit : miss))
                if watch.sum == 0 { watch.lastZero = t }
                if watch.sum > bar { watch.cut = watch.lastZero; break }
            }
        }
        watch.seenTo = fresh.last.map { from + Double(recent.frames[$0]) * fs } ?? now
        // The song's own rate, from readings it passes while the watch does not doubt it.
        if let m, m.score >= settings.holdScore, watch.cut == nil, watch.sum < 0.25 * bar, m.queryPoints > 0 {
            watch.rates.append(Double(m.matched) / Double(m.queryPoints))
            if watch.rates.count > 5 { watch.rates.removeFirst() }
        }
    }
}

/// The listener for an app: `feed` may be called from the audio thread and returns at once; the work is done on a
/// thread of the recogniser's own, one reading at a time, and each reading is handed to `onReading` there. If sound
/// arrives faster than it can be read (it should not: a reading takes a small part of a second), the oldest waiting
/// sound is still heard in order; nothing is dropped and the caller is never held up.
public final class BoothRecogniser: @unchecked Sendable {
    private let listener: SongListener
    private let queue = DispatchQueue(label: "deckie.recognition")
    private let lock = NSLock()
    private var waiting: [(samples: [Float], channels: Int, rate: Int)] = []
    private var working = false
    private var last: ListenReading?
    private let onReading: @Sendable (ListenReading) -> Void

    public init(index: RecognitionIndex, settings: ListenSettings = ListenSettings(), onReading: @escaping @Sendable (ListenReading) -> Void) {
        listener = SongListener(index: index, settings: settings)
        self.onReading = onReading
    }

    /// The most recent reading (nil until three seconds have been heard).
    public var latest: ListenReading? { lock.lock(); defer { lock.unlock() }; return last }

    /// Hands over more sound: copies it and returns.
    public func feed(_ samples: [Float], channels: Int = 1, sampleRate: Int) {
        lock.lock()
        waiting.append((samples, channels, sampleRate))
        let start = !working
        working = true
        lock.unlock()
        if start { queue.async { [self] in drain() } }
    }

    private func drain() {
        while true {
            lock.lock()
            guard !waiting.isEmpty else { working = false; lock.unlock(); return }
            let batch = waiting; waiting.removeAll()
            lock.unlock()
            for b in batch {
                for reading in listener.hear(b.samples, channels: b.channels, sampleRate: b.rate) {
                    lock.lock(); last = reading; lock.unlock()
                    onReading(reading)
                }
            }
        }
    }

    /// Waits until everything fed so far has been read (for tests and tools; an app has no need of it).
    public func finish() { queue.sync {} ; while true { lock.lock(); let busy = working; lock.unlock(); if !busy { break }; queue.sync {} } }
}

/// Runs `body` so that whatever Foundation set aside for later release while it ran is released when it ends. On
/// Apple's systems such memory otherwise waits for the thread's own pool, which a long-lived thread may never empty:
/// measured on a Mac, a tool's memory grew with every query (docs/research/w3-recognition-real-room.md). Elsewhere
/// there is no such pool and this only runs `body`.
@inline(__always) public func pooled<T>(_ body: () -> T) -> T {
    #if canImport(ObjectiveC)
    return autoreleasepool(invoking: body)
    #else
    return body()
    #endif
}
