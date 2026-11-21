import Foundation
import DeckieRecognition

/// One recogniser's word on what is playing, as the switching rule takes it (the iPad app's `Reading`): from Deckie's
/// listener (`init(deckie:heard:)`) or from Apple's recogniser (made by the iPad app).
public struct BoothReading: Sendable {
    public enum From: String, Sendable { case deckie, apple }
    public var from: From
    /// When the sound it is about was heard, and how many seconds of sound had been heard by then.
    public var date: Date
    public var audioTime: Double
    /// The song (a crate entry's id); nil when nothing is named.
    public var id: String?
    /// Seconds into the song as recorded, at `date`.
    public var position: Double?
    /// The deck's speed read from this listen, in percent (nil: this recogniser reads it only over time, from how fast
    /// the place moves).
    public var speedPercent: Double?
    /// Whether the key held while the speed moved (true), moved with it (false), or cannot be told (nil).
    public var keyLock: Bool?
    /// How far the key has moved, as a ratio (1: not at all).
    public var pitchRatio = 1.0
    /// Apple's tempo-only catalogue variant: a speed in percent that stands in until it is measured.
    public var speedHint: Double?
    /// How the speed was found, for the details sheet.
    public var speedFrom = ""
    /// The recogniser's own confidence (Deckie: its standing, 3 and more sure; Apple: 1 for a match).
    public var confidence = 1.0
    /// Whether the recogniser checked this place against the song itself (Deckie follows a song on its line), so a jump
    /// to another place in the song is taken at once rather than after the wait a repeated chorus needs.
    public var vouched = false
    /// Named by a search of the crate (not a song only followed).
    public var fresh = true
    /// How long the reading took to work out.
    public var milliseconds: Double?
    /// Deckie's: how many more readings naming this song the rule waits for before it replaces the song on screen (0: at
    /// once). Nil for Apple's, whose readings keep the hold written for them.
    public var wait: Int?
    /// The song heard coming in under the one playing, when the recogniser reports one.
    public var incoming: Incoming?

    /// A second song heard under the playing one: the song (a crate entry's id), its place, its speed, how sure.
    public struct Incoming: Equatable, Sendable {
        public var id: String
        public var position: Double?
        public var speedPercent: Double?
        public var keyLock: Bool?
        public var confidence: Double
        public init(id: String, position: Double?, speedPercent: Double?, keyLock: Bool?, confidence: Double) {
            self.id = id; self.position = position; self.speedPercent = speedPercent; self.keyLock = keyLock; self.confidence = confidence
        }
    }

    public init(from: From, date: Date, audioTime: Double, id: String?, position: Double? = nil, speedPercent: Double? = nil,
                keyLock: Bool? = nil, pitchRatio: Double = 1.0, speedHint: Double? = nil, speedFrom: String = "",
                confidence: Double = 1.0, vouched: Bool = false, fresh: Bool = true, milliseconds: Double? = nil, wait: Int? = nil,
                incoming: Incoming? = nil) {
        self.from = from; self.date = date; self.audioTime = audioTime; self.id = id; self.position = position
        self.speedPercent = speedPercent; self.keyLock = keyLock; self.pitchRatio = pitchRatio; self.speedHint = speedHint
        self.speedFrom = speedFrom; self.confidence = confidence; self.vouched = vouched; self.fresh = fresh
        self.milliseconds = milliseconds; self.wait = wait; self.incoming = incoming
    }

    /// One of Deckie's readings (a second of sound) as the rule takes it; nil for a song carried over a gap (followed,
    /// but not heard in this second), which is no new evidence and changes nothing. `heard`: when the sound it is about
    /// ended (in the products: the moment the reading arrived, less its milliseconds).
    public init?(deckie r: ListenReading, heard: Date) {
        if r.state == .held && r.confidence == 0 { return nil }
        let speed = r.speedPercent
        self.init(from: .deckie, date: heard, audioTime: r.time, id: r.id, position: r.positionSeconds, speedPercent: speed,
                  keyLock: r.keyLock, pitchRatio: r.keyLock == false ? 1 + (speed ?? 0) / 100 : 1,
                  speedFrom: BoothWords.t("heard.speedFromDeckie"), confidence: r.confidence, vouched: true,
                  fresh: r.state == .named, milliseconds: r.milliseconds, wait: BoothRule.deckieWait(r))
    }
}

/// The deck's speed from how fast a song's place moves against the sound heard: the median of the slopes between every
/// two readings at least 3 s apart (Theil-Sen, so one stray reading cannot pull it), from 12 s and three readings on
/// (track H measured two matches 8 s apart to a few hundredths; in the app the first 10 s read rough). Nil before that,
/// or when the slope is not a deck's.
public func speedFromPlaces(_ points: [(audioTime: Double, offset: Double)]) -> (ratio: Double, span: Double)? {
    guard let f = points.first, let l = points.last, points.count >= 3, l.audioTime - f.audioTime >= 12 else { return nil }
    var slopes: [Double] = []
    for i in 0..<points.count { for j in (i + 1)..<points.count {
        let dt = points[j].audioTime - points[i].audioTime
        if dt >= 3 { slopes.append((points[j].offset - points[i].offset) / dt) }
    } }
    slopes.sort()
    guard !slopes.isEmpty else { return nil }
    let slope = slopes[slopes.count / 2]
    return slope > 0.8 && slope < 1.2 ? (slope, l.audioTime - f.audioTime) : nil
}

/// The switching rule (D35 and the notes after it; moved from the iPad app into the core on Nov 21, 2026, D42): the one
/// place a reading, from either recogniser, becomes the song on screen, its place, the pitch shown, whether it is heard
/// just now or paused, and what else is heard. The iPad app and Desk's Booth run this same code.
///
/// It reads no clock of its own: each call is given `now`, the moment it runs (in the products, `Date()`), apart from the
/// reading's own `date`. No screen, no platform: plain values in, plain values out, and log lines (`notes`) for whoever
/// keeps a log.
public struct BoothRule: Sendable {
    public enum PitchKind: String, Sendable { case none = "", vinyl = "vinyl", masterTempo = "master tempo" }
    /// Where the sound comes from, as far as the rule cares: a microphone (or another input), a test file, nothing (not
    /// listening), or nothing heard because the song was set by hand.
    public enum Source: Sendable, Equatable { case listening, file, idle, manual }

    /// What one reading did.
    public enum Outcome: Sendable, Equatable {
        /// It named nothing.
        case nothing
        /// It changed nothing on screen yet: a song being waited for, a repeated section, buffered sound from before a
        /// pause.
        case kept
        /// It was taken: the song on screen (`newSong`: a new one just now) at the place it gave.
        case shown(newSong: Bool)
    }

    struct Event: Sendable { let date: Date; let id: String; let offset: Double; let freqRatio: Double; let speed: Double?; let audioTime: Double }

    // MARK: what the screen shows

    public private(set) var currentId: String?
    /// The place the playing song is at (D27): set when the song is set, the place that leads given the place playing
    /// before, or the place it was chosen from.
    public private(set) var currentPlace: BoothPlace?
    public private(set) var positionKnown = false
    public private(set) var anchorDate = Date(timeIntervalSince1970: 0)
    /// Seconds into the original song at `anchorDate`.
    public private(set) var anchorOffset = 0.0
    /// Playback tempo relative to the original.
    public private(set) var rate = 1.0
    /// The pitch fader estimate, how it reads, and how it was found.
    public private(set) var pitchPct = 0.0
    public private(set) var pitchKind: PitchKind = .none
    public private(set) var pitchFrom = ""
    public private(set) var lastMatch: Date?
    public private(set) var lastNoMatch: Date?
    public private(set) var matchCount = 0
    public private(set) var lastLatencyMs = 0.0
    /// Time from the start of listening (or of the wait) to the match that put the current song up.
    public private(set) var firstMatchSeconds: Double?
    /// Songs played before the current one, most recent last.
    public private(set) var history: [String] = []
    public private(set) var noMatchCount = 0
    /// Another song heard while the current one is kept (its id; the products say it in their words).
    public private(set) var alsoHearingId: String?
    /// Deckie's: no reading has named the playing song for `notHeardAfter` seconds (talk, silence, the music stopped).
    /// The song stays on screen, marked as not heard just now.
    public private(set) var notHeard = false
    /// The current song is not heard and the room is quiet: its place frozen, "paused".
    public private(set) var paused = false
    /// The song heard coming in under the playing one, when the recogniser reports one: the leading copy of it, never
    /// the playing song.
    public private(set) var incoming: BoothReading.Incoming?

    /// Log lines since the last `takeNotes()`.
    public private(set) var notes: [String] = []
    public mutating func takeNotes() -> [String] { defer { notes = [] }; return notes }

    // MARK: the rule's own memory

    private var events: [Event] = []
    private var pendingCount = 0
    private var lastOnTrack = Date.distantPast
    private var hits: [(Date, String)] = []            // every match of the last 40 s: (time, song id)
    private var challengerId: String?
    private var challengerSince = Date.distantPast
    private var challengerLast = Date.distantPast
    // Deckie's song change (D35): the song its readings name in a row that is not on screen, how many readings named
    // it, when the first did, how many more are needed (`deckieWait`) and the least in all (`carefulWait`).
    private var deckieRun: (id: String, count: Int, since: Date, left: Int, least: Int)?
    /// The song on screen was set by hand and has not been heard since.
    private var byHand = false
    /// How strongly Deckie's listener last heard the playing song when it followed it (its points above chance), and
    /// when: a song coming in must be heard more strongly than that to take over on one confirmation.
    private var currentHeld: (score: Double, at: Date)?
    /// The song that was on screen before the playing one, and when it gave way.
    private var leftId: String?
    private var leftAt = Date.distantPast
    /// Deckie's pitch readings of the playing song since the last song change or fader move (`updatePitch`).
    private var speeds: (id: String, values: [Double], lone: Double?)?
    private var pendingJump: Event?   // a same-song match at an unexpected offset (repeated chorus?) waiting for confirmation
    private var justSwitched = false
    private var songStartedAt = Date(timeIntervalSince1970: 0)
    private var frozenAt: Date?
    private var lastCurrentMatch = Date.distantPast
    private var lastAnyMatch = Date.distantPast

    public init() {}

    // MARK: the numbers (D35, the note of Nov 14: the booth switches sooner when Deckie's is sure)

    /// The listener's own thresholds (`ListenSettings`): a search at `sure` names a song on its own; one at `fair` names
    /// it only when the search before put the same song on the same line.
    public static let listenSettings = ListenSettings()
    /// Readings the rule waits for before a song Deckie's names replaces the one on screen:
    /// - named, sure (confidence 3 or more) and agreeing with the search a second or two before on place and speed: none,
    ///   the name already rests on two searches seconds apart;
    /// - named and sure, on one search: one, the next reading naming it too (the listener's check of it, its points
    ///   agreeing 6 or more above chance over the last 5 s);
    /// - named and only fair (2.6 to 3, two weak searches agreeing): `fairWait`, so the name rests on about five seconds
    ///   of agreeing sound before it replaces the song a DJ is reading picks from;
    /// - followed (held): one; a held reading that comes after a name of the same song is its confirmation.
    public static let fairWait = 3
    public static func deckieWait(_ r: ListenReading) -> Int {
        switch r.state {
        case .named where r.confidence >= listenSettings.sure: return r.searched?.agrees == true ? 0 : 1
        case .named: return fairWait
        default: return 1
        }
    }
    /// The wait for a song that would undo a recent change or a choice: the song on screen until less than
    /// `returnWindow` seconds ago (no flicker back in a blend), or any song while the one on screen was set by hand and
    /// has not been heard since. That many readings in a row naming it, whatever their confidence.
    public static let carefulWait = 3
    public static let returnWindow: TimeInterval = 30
    /// How recent the playing song's own followed reading must be for the dominance check (two readings).
    public static let dominanceWindow: TimeInterval = 2
    /// The playing song is marked as not heard just now after this many seconds with no reading of it.
    public static let notHeardAfter: TimeInterval = 4
    /// The pitch shown from Deckie's readings: the median of the playing song's last `pitchReadings` speeds, started
    /// afresh on a song change, and when two readings in a row lie more than `faderJump` percent from the median and
    /// within `faderJump` of each other (the fader moved: shown from the second, about a second after the move). One
    /// reading that far off on its own is set aside (measured: +7.6 % once in a song at +6 % as it faded out). The
    /// reading's own wobble in a song is a tenth to three tenths (the generated set); nine readings steady it to a tenth,
    /// and a move of half a percent or more is shown from two readings rather than averaged in.
    public static let pitchReadings = 9
    public static let faderJump = 0.5
    /// Apple's hold: a new song takes over only after it has out-matched the current one for this long.
    public static let hold: TimeInterval = 10
    /// Below this input level (dBFS-ish RMS) the room counts as quiet.
    public static let quietDB: Float = -45
    /// With no match at all for this long, the screen lets the song go.
    public static let silenceClear: TimeInterval = 120

    // MARK: reading the state

    /// The playing song, shown at the place it is playing from.
    public func current(in lib: BoothLibrary) -> BoothSong? {
        guard let t = lib.song(currentId) else { return nil }
        if let p = currentPlace, t.places.contains(p) { return t.at(p) }
        return t
    }

    /// The place in the song at `d`, frozen while the deck is paused.
    public func position(at d: Date) -> Double { anchorOffset + max(0, min(frozenAt ?? d, d).timeIntervalSince(anchorDate)) * rate }

    /// 0...1 from how consistent the last few matches are (same song, offsets that line up) and how recent they are.
    public func confidence(now: Date, source: Source) -> Double {
        guard let cur = currentId else { return 0 }
        if source == .manual { return 0 }
        let recent = events.suffix(6)
        guard !recent.isEmpty else { return 0 }
        let same = recent.filter { $0.id == cur }
        let agree = Double(same.count) / Double(recent.count)
        var good = 0, checked = 0
        let s = Array(same)
        if s.count >= 2 {
            for i in 1..<s.count {
                let pred = s[i - 1].offset + s[i].date.timeIntervalSince(s[i - 1].date) * rate
                checked += 1
                if abs(pred - s[i].offset) < 2.0 { good += 1 }
            }
        }
        let consistency = checked == 0 ? 0.6 : Double(good) / Double(checked)
        let depth = min(1.0, 0.45 + 0.2 * Double(same.count))
        let age = now.timeIntervalSince(lastMatch ?? .distantPast)
        let recency = paused ? 1.0 : age < 20 ? 1.0 : max(0.2, 1 - (age - 20) / 150)   // slow decay in noisy stretches
        return agree * (0.4 + 0.6 * consistency) * depth * recency
    }

    // MARK: the clock

    /// Once a second: pauses, "not heard just now", and after two minutes without any match the song let go (returns
    /// true then: the screen is back to listening). `deckie`: Deckie's listener is listening (Apple's results come too
    /// far apart for "not heard"). `level`: the input's level.
    @discardableResult
    public mutating func tick(now: Date, source: Source, deckie: Bool, level: Float) -> Bool {
        guard currentId != nil, source != .manual else { return false }
        let sinceCur = now.timeIntervalSince(lastCurrentMatch)
        if !notHeard, deckie, sinceCur > Self.notHeardAfter {
            notHeard = true
            note("not heard just now (no reading of it for \(Int(sinceCur)) s)")
        }
        if !paused && sinceCur > 5 && level < Self.quietDB {
            paused = true; frozenAt = lastCurrentMatch.addingTimeInterval(1)
            note("paused (quiet, no match for \(Int(sinceCur)) s)")
        }
        if now.timeIntervalSince(lastAnyMatch) > Self.silenceClear {
            note("nothing recognised for 2 min: back to listening")
            currentId = nil; currentPlace = nil; paused = false; frozenAt = nil; positionKnown = false; alsoHearingId = nil
            events.removeAll(); hits.removeAll()
            notHeard = false; deckieRun = nil; speeds = nil; incoming = nil
            return true
        }
        return false
    }

    // MARK: songs set by hand, another crate

    /// Another crate file is open: nothing from the last one is playing or was played.
    public mutating func forget() {
        currentId = nil; currentPlace = nil; history = []; positionKnown = false; paused = false; frozenAt = nil
        alsoHearingId = nil; events.removeAll(); hits.removeAll(); challengerId = nil
        notHeard = false; deckieRun = nil; byHand = false; leftId = nil; speeds = nil; incoming = nil
    }

    /// Sets the playing song by hand; `place` is where it was chosen, else the place that leads.
    public mutating func setManual(_ id: String, place: BoothPlace? = nil, in lib: BoothLibrary, now: Date) {
        switchTo(id, place: place, lib: lib, now: now)
        positionKnown = false
        events.removeAll()
        byHand = true
        // The clocks of "not heard" and of the 2-minute rule start from the choice: before, the first second of
        // listening after a song was set by hand found no match ever and cleared it.
        lastCurrentMatch = now; lastAnyMatch = now
    }

    // MARK: readings into what the DJ sees

    /// The one place a reading, from either recogniser, becomes the playing song, its place and the pitch shown.
    /// `now`: the moment this runs. `level`: the input's level. `startedAt`: when listening (or the test file) started.
    public mutating func take(_ r: BoothReading, in lib: BoothLibrary, now wall: Date, source: Source, level: Float,
                              startedAt: Date) -> Outcome {
        let now = r.date
        guard let matched = r.id, let offset = r.position else {
            lastNoMatch = now
            noMatchCount += 1
            if noMatchCount % 5 == 1 { note(String(format: "no match (%d so far), input %.0f dB", noMatchCount, level)) }
            if let ms = r.milliseconds { lastLatencyMs = ms }
            if r.wait != nil { deckieRun = nil }               // Deckie's: nothing heard breaks a run of readings
            incoming = nil
            return .nothing
        }
        let predicted = positionKnown ? position(at: now) : nil
        // Whichever copy was heard, the song is named once: a copy of the playing song is the playing song (never a song
        // change), and another song is the copy whose place leads (on the playing song's disc, else the first disc in
        // order), so every copy of it counts as one challenger.
        let playingDisc = current(in: lib)?.disc
        let currentId = self.currentId
        let id = lib.sameSong(matched, currentId) ? currentId! : lib.leadingCopy(of: matched, playingDisc: playingDisc)
        // The song coming in (D35): kept as its leading copy, never the song this reading names.
        incoming = r.incoming.flatMap { inc in
            if lib.sameSong(inc.id, matched) { return nil }
            var c = inc
            c.id = lib.sameSong(inc.id, currentId) ? currentId! : lib.leadingCopy(of: inc.id, playingDisc: playingDisc)
            return c
        }
        matchCount += 1
        lastMatch = now
        if let ms = r.milliseconds { lastLatencyMs = ms }
        let ev = Event(date: now, id: id, offset: offset, freqRatio: r.pitchRatio, speed: r.speedPercent, audioTime: r.audioTime)
        hits.append((now, id))
        hits.removeAll { now.timeIntervalSince($0.0) > 40 }
        lastAnyMatch = now
        if id == currentId {
            // a match while the room is still quiet is buffered audio from before the pause, not a resume
            if paused && level < Self.quietDB { return .kept }
            let resumed = paused || now.timeIntervalSince(lastCurrentMatch) > 5
            lastCurrentMatch = now
            // Heard: no longer marked as not heard, no longer only set by hand, and any run of readings naming another
            // song is broken.
            if notHeard { note("heard again") }
            notHeard = false; byHand = false; deckieRun = nil
            if r.wait != nil { currentHeld = r.fresh ? nil : (r.confidence, now) }
            if resumed {
                // back after a pause / gap: continue from wherever the song is now, no confirmation needed
                if paused { note(String(format: "resumed at %.1fs", offset)) }
                paused = false; frozenAt = nil
                if let pr = predicted, abs(offset - pr) > 2.5 { events.removeAll { $0.id == id } }
                pendingJump = nil; pendingCount = 0; lastOnTrack = now
            } else if let pr = predicted, abs(offset - pr) > 2.5 {
                // same song, different place: cue restart, hot cue, loop, scratch, or a repeated section.
                if r.vouched {
                    // Deckie's listener checked the new place against the song itself: taken at once.
                    note(String(format: "position jump to %.1fs (expected %.1fs)", offset, pr))
                    events.removeAll { $0.id == id }; pendingJump = nil; pendingCount = 0; lastOnTrack = now
                } else if offset < 15 && pr > 30 {
                    note(String(format: "restart from the top (%.1fs)", offset))
                    events.removeAll { $0.id == id }; pendingJump = nil; pendingCount = 0; lastOnTrack = now
                } else {
                    if let pj = pendingJump, abs(pj.offset + now.timeIntervalSince(pj.date) * rate - offset) < 2.5 {
                        pendingCount += 1
                    } else { pendingJump = ev; pendingCount = 1 }
                    // 2 agreeing matches, and the old place no longer heard for 5 s (repeated choruses otherwise make
                    // ShazamKit alternate between two equally good positions)
                    if pendingCount >= 2 && now.timeIntervalSince(lastOnTrack) >= 5 {
                        pendingJump = nil; pendingCount = 0
                        events.removeAll { $0.id == id }
                        lastOnTrack = now
                        note(String(format: "position jump confirmed to %.1fs", offset))
                    } else {
                        note(String(format: "ignored %.1fs (expected %.1fs): repeated section?", offset, pr))
                        return .kept
                    }
                }
            } else { pendingJump = nil; pendingCount = 0; lastOnTrack = now }
        }
        events.append(ev)
        if events.count > 12 { events.removeFirst(events.count - 12) }

        // hysteresis: a new song takes over only after it has out-matched the current one for ~10 s (the first party's DJ
        // blends for long stretches); while both are heard the current one stays, with a note.
        if id != currentId {
            if currentId == nil {
                lastCurrentMatch = now
                switchTo(id, lib: lib, now: wall)
                firstMatchSeconds = now.timeIntervalSince(source == .listening ? max(startedAt, songStartedAt) : startedAt)
            } else if let wait = r.wait {
                // Deckie's (D35): its listener has already gathered the evidence across seconds, so the rule waits only
                // as many readings as the name's standing asks (`deckieWait`), and longer for a song that would undo a
                // recent change or a song set by hand (`carefulWait`).
                if var run = deckieRun, run.id == id {
                    run.count += 1; run.left = min(run.left - 1, wait); deckieRun = run
                } else {
                    let careful = byHand || (id == leftId && now.timeIntervalSince(leftAt) < Self.returnWindow)
                    deckieRun = (id, 1, now, wait, careful ? Self.carefulWait : 1)
                }
                // Dominance, kept from the old hold: a followed reading of the new song no stronger than the playing
                // song's own a moment ago (`dominanceWindow`) does not confirm on its own; the careful wait applies.
                // (On the test set a wrong name once came with a weak check, 17.6 against the playing song's 62; every
                // real change's check stood above the playing song's last.)
                if !r.fresh, let h = currentHeld, now.timeIntervalSince(h.at) <= Self.dominanceWindow, r.confidence <= h.score {
                    let least = max(deckieRun?.least ?? 0, Self.carefulWait)
                    deckieRun?.least = least
                }
                challengerLast = now
                guard let run = deckieRun else { return .kept }
                if run.left <= 0 && run.count >= run.least {
                    note(String(format: "switch to %@ (Deckie's: %d reading%@ in %.1f s%@)", lib.song(id)?.song ?? id, run.count,
                                run.count == 1 ? "" : "s", now.timeIntervalSince(run.since), run.least > 1 ? ", the careful wait" : ""))
                    paused = false; frozenAt = nil; lastCurrentMatch = now
                    switchTo(id, lib: lib, now: wall)
                    challengerId = nil; alsoHearingId = nil
                    firstMatchSeconds = now.timeIntervalSince(run.since)
                } else {
                    // A wait of more than a second shows the other song meanwhile, as Apple's hold does; a one-reading
                    // wait does not, so the foot does not flash just before the title changes.
                    if max(run.left, run.least - run.count) > 1 { alsoHearingId = lib.song(id) != nil ? id : nil }
                    return .kept
                }
            } else {
                if challengerId != id || now.timeIntervalSince(challengerLast) > 12 { challengerId = id; challengerSince = now }
                challengerLast = now
                let recent = hits.filter { now.timeIntervalSince($0.0) <= Self.hold }
                let c = recent.filter { $0.1 == id }.count, k = recent.filter { $0.1 == currentId }.count
                // hard cut: the current song has stopped matching entirely and the new one matches consistently
                let lastCur = hits.last { $0.1 == currentId }?.0 ?? .distantPast
                let cRecent = hits.filter { $0.1 == id && now.timeIntervalSince($0.0) <= 6 }.count
                let hardCut = now.timeIntervalSince(lastCur) > 3.5 && cRecent >= 3
                // blend: both are heard; switch only after ~10 s of dominance
                let dominated = now.timeIntervalSince(challengerSince) >= Self.hold && c > k
                if dominated || hardCut {
                    note("switch to \(lib.song(id)?.song ?? id) (\(hardCut ? "hard cut" : "blend"): \(c) vs \(k) matches in \(Int(Self.hold)) s)")
                    paused = false; frozenAt = nil; lastCurrentMatch = now
                    switchTo(id, lib: lib, now: wall)
                    challengerId = nil; alsoHearingId = nil
                    firstMatchSeconds = now.timeIntervalSince(challengerSince)
                } else {
                    alsoHearingId = lib.song(id) != nil ? id : nil
                    return .kept
                }
            }
        } else if now.timeIntervalSince(challengerLast) > 15 {
            alsoHearingId = nil
        }
        let before = (pitchPct, pitchFrom)
        updatePitch(r, ev)
        if abs(pitchPct - before.0) >= 0.05 || pitchFrom != before.1 { note(String(format: "pitch %+.1f%% %@ (%@)", pitchPct, pitchKind.rawValue, pitchFrom)) }
        anchorDate = now; anchorOffset = offset; positionKnown = true
        let newSong = justSwitched
        justSwitched = false
        return .shown(newSong: newSong)
    }

    /// The middle value (the mean of the middle two for an even count).
    public static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted(), n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    private mutating func note(_ s: String) { notes.append(s) }

    private mutating func switchTo(_ id: String, place: BoothPlace? = nil, lib: BoothLibrary, now: Date) {
        justSwitched = true
        if let c = currentId, c != id { leftId = c; leftAt = now }
        notHeard = false; byHand = false; deckieRun = nil; speeds = nil; currentHeld = nil
        if incoming?.id == id { incoming = nil }
        if id != currentId || place != nil {
            currentPlace = place ?? lib.placed(id, playingDisc: current(in: lib)?.disc)?.place
        }
        if let c = currentId, c != id {
            history.removeAll { $0 == c }
            history.append(c)
            if history.count > 30 { history.removeFirst() }
        }
        currentId = id
        songStartedAt = now
        events.removeAll { $0.id != id }
        pitchPct = 0; pitchKind = .none; rate = 1; pitchFrom = ""
    }

    /// The pitch shown, from the readings of the playing song: the key moved (vinyl-style), the speed read from one
    /// listen (Deckie's), or the speed from how fast the place moves (Apple's with the key held).
    private mutating func updatePitch(_ r: BoothReading, _ ev: Event) {
        if r.from == .deckie, let s = r.speedPercent {
            // Deckie's (D35): the deck's speed from each second's listen wobbles by a tenth or two; the pitch shown is
            // the median of the playing song's last `pitchReadings`, started afresh on a song change and when two
            // readings in a row move more than `faderJump` from it (the fader moved: not averaged in). The key held or
            // not to be told, the tempo shown is still the tempo the song plays at (the BPM and the song time follow
            // `rate`).
            if var run = speeds, run.id == ev.id {
                if abs(s - Self.median(run.values)) <= Self.faderJump {
                    run.values.append(s); run.values = Array(run.values.suffix(Self.pitchReadings)); run.lone = nil
                } else if let lone = run.lone, abs(s - lone) <= Self.faderJump {
                    // Two readings in a row away from the median and agreeing: the fader moved. Start from them.
                    note(String(format: "fader moved: %+.2f%%, %+.2f%% after %+.2f%%", lone, s, Self.median(run.values)))
                    run.values = [lone, s]; run.lone = nil
                } else {
                    run.lone = s           // one reading away from the rest: set aside until the next agrees
                }
                speeds = run
            } else {
                speeds = (ev.id, [s], nil)
            }
            let m = Self.median(speeds?.values ?? [s])
            pitchPct = (m * 10).rounded() / 10; rate = 1 + m / 100
            pitchKind = r.keyLock == true ? .masterTempo : r.keyLock == false ? .vinyl : .none
            pitchFrom = r.speedFrom
            return
        }
        if abs(ev.freqRatio - 1) > 0.008 {
            // vinyl-style (master tempo off): key and tempo moved together; the key's ratio says how much, averaged over
            // the song's last four readings and shown to a tenth
            let same = events.filter { $0.id == ev.id }.suffix(4).map(\.freqRatio)
            let fr = same.reduce(0, +) / Double(same.count)
            pitchPct = ((fr - 1) * 1000).rounded() / 10; pitchKind = .vinyl; rate = fr
            pitchFrom = r.speedFrom
            return
        }
        if r.speedPercent != nil {
            // Deckie's: the deck's speed from each listen, the key held or not to be told; averaged over the song's last
            // four readings and shown to a tenth.
            let same = events.filter { $0.id == ev.id }.compactMap(\.speed).suffix(4)
            let s = same.reduce(0, +) / Double(same.count)
            pitchPct = (s * 10).rounded() / 10; rate = 1 + s / 100
            pitchKind = r.keyLock == true ? .masterTempo : .none
            pitchFrom = r.speedFrom
            return
        }
        // key unchanged (master tempo on, or no pitch): the tempo is how fast the matched position runs against the
        // audio clock, shown from 12 s and three matches on (`speedFromPlaces`), and refined on every match after that.
        let same = Array(events.filter { $0.id == ev.id }.suffix(12))
        if let fit = speedFromPlaces(same.map { ($0.audioTime, $0.offset) }) {
            let p = ((fit.ratio - 1) * 1000).rounded() / 10
            if abs(p) >= 0.3 { pitchPct = p; pitchKind = .masterTempo; rate = fit.ratio; pitchFrom = "position drift over \(Int(fit.span)) s" }
            else { pitchPct = 0; pitchKind = .none; rate = 1; pitchFrom = "position drift" }
            return
        }
        if let hint = r.speedHint {
            // a tempo-only variant matched: its percent stands in until the drift fit has 12 s of matches
            pitchPct = hint; pitchKind = .masterTempo; rate = 1 + hint / 100; pitchFrom = "tempo-only variant, measuring"
        } else if pitchKind == .vinyl {
            pitchPct = 0; pitchKind = .none; rate = 1
        }
    }
}
