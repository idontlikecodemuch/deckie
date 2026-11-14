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
    public var fair = 2.3
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
    /// 64 ms and 8 %, not 96 ms and 12 %) and three points are taken per slice, not two: the index is thin, so
    /// the listening side carries more (letter AB; the size study's rows).
    public var denseQuery = true
    /// Whether a named song is followed (false, for measuring only: every reading is a fresh search and nothing is named).
    public var follow = true
    public init() {}
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
    private var sinceSearch = 0
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
        var state = ListenReading.State.nothingYet
        var confidence = 0.0
        var searched: ListenReading.Searched?

        // Follow the song already named: one check, at the place and speed it should be at.
        if let f = following {
            // The check looks at the newest sound only: the points of the window's last `holdWindow` seconds.
            let recent = have > settings.holdWindow ? marks.suffix(fromSeconds: have - settings.holdWindow, frameSeconds: queryConfig.frameSeconds) : marks
            let from = now - min(have, settings.holdWindow)
            if let m = recogniser.check(recent, song: f.song, offsetSeconds: f.intercept + f.tempo * from, tempoRatio: f.tempo, pitchRatio: f.pitch),
               m.score >= settings.holdScore {
                following = (f.song, m.offsetSeconds - m.tempoRatio * from, m.tempoRatio, m.pitchRatio)
                misses = 0; state = .held; confidence = m.score
            } else {
                misses += 1
                if misses >= settings.lostAfter { following = nil }
                else { state = .held; confidence = 0 }       // carried over a gap: still shown, on its last line
            }
        }
        // Search the whole crate: always when nothing is followed, and every few readings when something is. Then,
        // if nothing is named and there is more sound to go on, once more over the longer window.
        sinceSearch += 1
        var tries: [(Landmarks, Double)] = []
        if following == nil || misses > 0 || sinceSearch >= settings.searchEvery {
            sinceSearch = 0
            tries.append((marks, start))
        }
        var tried = 0
        while tried < tries.count {
            let (marks, start) = tries[tried]
            tried += 1
            if tried == 1, following == nil, settings.longWindow > settings.window {
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
                    misses = 0; state = .named; confidence = best.confidence
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
