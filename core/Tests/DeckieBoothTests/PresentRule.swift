import Foundation
import DeckieCrate
import DeckieRecognition

// THE iPAD APP'S SWITCHING RULE AS IT WAS BEFORE THE MOVE (Nov 21, 2026, origin/pc/round-nov21 cc6d933), kept as the
// golden reference for the shared one in DeckieBooth. Do not change this file to follow the shared code: it is the
// record of what the iPad did.
//
// Copied from deck-app/Deck/Sources/Recognizer.swift (the rule: `deckieReading`, `deckieWait` and its numbers, `take`,
// `switchTo`, `updatePitch`, `median`, `tick`, `confidence`, `position(at:)`, `setManual`, `forgetSongs`),
// Listening.swift (`Reading`, `speedFromPlaces`) and Model.swift (the crate's places: `sameSong`, `places(of:)`,
// `leadingCopy`, `placed`, `Track.at`, `oneLine`, `placeText`), with only these changes, so it runs outside the app:
// - `Library.shared` is `lib`, a `PresentLibrary` made from a crate file as CrateLibrary.load makes the app's;
// - every `Date()` the rule read is `clock()`, a clock the test sets (in the app, the moment the main thread ran it);
// - the app's state that is not the rule's (the status line's words, the set recorder, the comparison of two
//   recognisers, the console trace) is left out or kept as plain values the test reads;
// - `@MainActor @Observable` and `private` are gone; the class is the rule's state only.

/// One recogniser's word on what is playing (Listening.swift, `Reading`).
struct PresentReading {
    enum From: String { case deckie, apple }
    var from: From
    var date: Date
    var audioTime: Double
    var id: String?
    var position: Double?
    var speedPercent: Double?
    var keyLock: Bool?
    var pitchRatio = 1.0
    var speedHint: Double?
    var speedFrom = ""
    var confidence = 1.0
    var vouched = false
    var fresh = true
    var milliseconds: Double?
    var wait: Int?
    var incoming: Incoming?
    struct Incoming: Equatable {
        var id: String
        var position: Double?
        var speedPercent: Double?
        var keyLock: Bool?
        var confidence: Double
    }
}

/// The app's `Track`, the parts the rule reads.
struct PresentTrack {
    let id: String
    let title: String
    let artist: String
    let song: String
    let deck: String
    var on: Bool
    var disc: String?
    var folder: String
    let cut: String
    var num: Int?
    var others: [PresentPlace]? = nil
    var named: Bool? = nil
    var place: PresentPlace { PresentPlace(disc: disc, folder: folder, num: num) }
    var places: [PresentPlace] { [PresentPlace(disc: disc, folder: folder, num: num)] + (others ?? []) }
    func at(_ p: PresentPlace) -> PresentTrack {
        guard p != place else { return self }
        var c = self
        c.disc = p.disc; c.folder = p.folder; c.num = p.num; c.on = p.disc != nil
        return c
    }
    var hasName: Bool { named ?? true }
    var sourceName: String? { disc }
    var placeText: String {
        guard let s = sourceName else { return folder }
        return s + (folder.isEmpty ? "" : " / " + folder) + (num.map { String(format: " / %02d", $0) } ?? "")
    }
    var oneLine: String {
        if hasName { return song }
        return placeText.isEmpty ? "No name yet" : placeText + " · " + "no name yet"
    }
}

struct PresentPlace: Hashable { let disc: String?; let folder: String; let num: Int? }

/// The app's `Library`, the parts the rule reads.
final class PresentLibrary {
    private(set) var byId: [String: PresentTrack] = [:]
    private(set) var copiesByCut: [String: [String]] = [:]
    private(set) var discOrder: [String] = []
    init(_ crate: Crate) {
        discOrder = Array(Set(crate.tracks.flatMap { $0.ident.allPlaces.compactMap(\.disc) })).sorted()
        var tracks: [PresentTrack] = []
        for t in crate.tracks {
            let folder = t.ident.folder ?? ((t.file.rel ?? "") as NSString).deletingLastPathComponent.components(separatedBy: "/").last ?? ""
            let artist = t.ident.artist ?? ""
            tracks.append(PresentTrack(
                id: t.id, title: artist.isEmpty ? t.ident.title : "\(artist) - \(t.ident.title)", artist: artist, song: t.ident.title,
                deck: (t.file.name as NSString).deletingPathExtension, on: t.ident.disc != nil, disc: t.ident.disc, folder: folder,
                cut: t.recordingKey, num: t.ident.track,
                others: t.ident.otherPlaces.isEmpty ? nil : t.ident.otherPlaces.map { p in
                    PresentPlace(disc: p.disc, folder: p.disc != nil ? p.folder ?? "" : (p.folder ?? "").components(separatedBy: "/").last ?? "", num: p.track)
                },
                named: t.hasUsableTitle ? nil : false))
        }
        byId = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })
        for t in tracks { copiesByCut[t.cut, default: []].append(t.id) }
    }
    func track(_ id: String?) -> PresentTrack? { id.flatMap { byId[$0] } }
    func sameSong(_ a: String?, _ b: String?) -> Bool {
        guard let a, let b, let x = byId[a], let y = byId[b] else { return false }
        return x.cut == y.cut
    }
    func places(of id: String, playingDisc: String?, among: ((PresentTrack) -> Bool)? = nil) -> [PresentTrack] {
        guard let t = byId[id] else { return [] }
        let all = (copiesByCut[t.cut] ?? [id]).compactMap { byId[$0] }.flatMap { c in c.places.map { c.at($0) } }
            .filter { among?($0) ?? true }
        let places = all.enumerated().map { SameSong.Place(id: String($0.offset), disc: $0.element.disc, folder: $0.element.folder, track: $0.element.num) }
        return SameSong.ordered(places, playingDisc: playingDisc, discOrder: discOrder).map { all[Int($0.id)!] }
    }
    func leadingCopy(of id: String, playingDisc: String?) -> String {
        places(of: id, playingDisc: playingDisc).first?.id ?? id
    }
    func placed(_ id: String, playingDisc: String?, among: ((PresentTrack) -> Bool)? = nil) -> PresentTrack? {
        let mine = { (ts: [PresentTrack]) in ts.first { $0.id == id } }
        return mine(places(of: id, playingDisc: playingDisc, among: among)) ?? mine(places(of: id, playingDisc: playingDisc)) ?? byId[id]
    }
}

/// Listening.swift's `speedFromPlaces`.
func presentSpeedFromPlaces(_ points: [(audioTime: Double, offset: Double)]) -> (ratio: Double, span: Double)? {
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

/// Recognizer.swift's rule.
final class PresentRule {
    enum Source: Equatable { case idle, mic, file(String), manual }
    enum PitchKind: String { case none = "", vinyl = "vinyl", masterTempo = "master tempo" }
    struct Event { let date: Date; let id: String; let offset: Double; let freqRatio: Double; let speed: Double?; let audioTime: Double }

    let lib: PresentLibrary
    var clock: () -> Date
    init(lib: PresentLibrary, clock: @escaping () -> Date) { self.lib = lib; self.clock = clock }

    // What the test sets, as the app had it.
    var source: Source = .mic
    var listeningDeckie = true          // `listening == .deckie || listening == .both`
    var inputLevel: Float = -20
    var startedAt = Date(timeIntervalSince1970: 0)
    // What the app did after `take` (the status line and the set's log), as values.
    var status = ""
    var notes: [String] = []
    func note(_ s: String) { notes.append(s) }

    var currentId: String?
    var positionKnown = false
    var anchorDate = Date(timeIntervalSince1970: 0)
    var anchorOffset = 0.0
    var rate = 1.0
    var pitchPct = 0.0
    var pitchKind: PitchKind = .none
    var pitchFrom = ""
    var lastMatch: Date?
    var lastNoMatch: Date?
    var matchCount = 0
    var lastLatencyMs = 0.0
    var firstMatchSeconds: Double?
    var history: [String] = []
    var noMatchCount = 0

    var events: [Event] = []
    var pendingId: String?
    var pendingCount = 0
    var lastOnTrack = Date.distantPast
    var hits: [(Date, String)] = []
    var challengerId: String?
    var challengerSince = Date.distantPast
    var challengerLast = Date.distantPast
    static let hold: TimeInterval = 10
    var alsoHearing: String?
    var deckieRun: (id: String, count: Int, since: Date, left: Int, least: Int)?
    var byHand = false
    var currentHeld: (score: Double, at: Date)?
    var leftId: String?
    var leftAt = Date.distantPast
    var notHeard = false
    var speeds: (id: String, values: [Double], lone: Double?)?
    var incoming: PresentReading.Incoming?
    var pendingJump: Event?
    var justSwitched = false
    var songStartedAt = Date(timeIntervalSince1970: 0)

    var currentPlace: PresentPlace?
    var current: PresentTrack? {
        guard let t = lib.track(currentId) else { return nil }
        if let p = currentPlace, t.places.contains(p) { return t.at(p) }
        return t
    }

    func position(at d: Date) -> Double { anchorOffset + max(0, min(frozenAt ?? d, d).timeIntervalSince(anchorDate)) * rate }

    var paused = false
    var frozenAt: Date?
    var lastCurrentMatch = Date.distantPast
    var lastAnyMatch = Date.distantPast
    static let quietDB: Float = -45
    static let silenceClear: TimeInterval = 120

    func tick() {
        let now = clock()
        guard currentId != nil, source != .manual else { return }
        let sinceCur = now.timeIntervalSince(lastCurrentMatch)
        if !notHeard, listeningDeckie, sinceCur > Self.notHeardAfter {
            notHeard = true
            note("not heard just now (no reading of it for \(Int(sinceCur)) s)")
        }
        if !paused && sinceCur > 5 && inputLevel < Self.quietDB {
            paused = true; frozenAt = lastCurrentMatch.addingTimeInterval(1)
            note("paused (quiet, no match for \(Int(sinceCur)) s)")
        }
        if now.timeIntervalSince(lastAnyMatch) > Self.silenceClear {
            note("nothing recognised for 2 min: back to listening")
            currentId = nil; currentPlace = nil; paused = false; frozenAt = nil; positionKnown = false; alsoHearing = nil
            events.removeAll(); hits.removeAll()
            notHeard = false; deckieRun = nil; speeds = nil; incoming = nil
            status = "listening…"
        }
    }

    var confidence: Double {
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
        let age = clock().timeIntervalSince(lastMatch ?? .distantPast)
        let recency = paused ? 1.0 : age < 20 ? 1.0 : max(0.2, 1 - (age - 20) / 150)
        return agree * (0.4 + 0.6 * consistency) * depth * recency
    }

    func forgetSongs() {
        source = .idle
        currentId = nil; currentPlace = nil; history = []; positionKnown = false; paused = false; frozenAt = nil
        alsoHearing = nil; events.removeAll(); hits.removeAll(); pendingId = nil; challengerId = nil
        notHeard = false; deckieRun = nil; byHand = false; leftId = nil; speeds = nil; incoming = nil
    }

    func setManual(_ id: String, place: PresentPlace? = nil) {
        switchTo(id, place: place)
        source = .manual; positionKnown = false; status = "set by hand"
        events.removeAll()
        byHand = true
        lastCurrentMatch = clock(); lastAnyMatch = clock()
    }

    /// `deckieReading`: one of Deckie's readings as the rule takes it.
    func deckieReading(_ r: ListenReading, heard: Date) {
        guard listeningDeckie else { return }
        if r.state == .held && r.confidence == 0 { return }
        let speed = r.speedPercent
        let reading = PresentReading(from: .deckie, date: heard, audioTime: r.time, id: r.id, position: r.positionSeconds, speedPercent: speed,
                                     keyLock: r.keyLock, pitchRatio: r.keyLock == false ? 1 + (speed ?? 0) / 100 : 1,
                                     speedFrom: "Deckie's reading", confidence: r.confidence, vouched: true,
                                     fresh: r.state == .named, milliseconds: r.milliseconds, wait: Self.deckieWait(r))
        if r.state == .named, let id = r.id {
            note(String(format: "Deckie named %@ at %.1fs, speed %+.2f%%, key lock %@, confidence %.1f (%.0f ms), heard %.1fs", lib.track(id)?.title ?? id,
                        r.positionSeconds ?? 0, speed ?? 0, r.keyLock.map { $0 ? "on" : "off" } ?? "?", r.confidence, r.milliseconds, r.time))
        }
        take(reading)
    }

    static let listenSettings = ListenSettings()
    static let fairWait = 3
    static func deckieWait(_ r: ListenReading) -> Int {
        switch r.state {
        case .named where r.confidence >= listenSettings.sure: return r.searched?.agrees == true ? 0 : 1
        case .named: return fairWait
        default: return 1
        }
    }
    static let carefulWait = 3
    static let returnWindow: TimeInterval = 30
    static let dominanceWindow: TimeInterval = 2
    static let notHeardAfter: TimeInterval = 4
    static let pitchReadings = 9
    static let faderJump = 0.5

    func take(_ r: PresentReading) {
        let now = r.date
        guard let matched = r.id, let offset = r.position else {
            lastNoMatch = now
            noMatchCount += 1
            if noMatchCount % 5 == 1 { note(String(format: "no match (%d so far), input %.0f dB", noMatchCount, inputLevel)) }
            if let ms = r.milliseconds { lastLatencyMs = ms }
            if currentId == nil { status = "listening…" }
            if r.wait != nil { deckieRun = nil }
            incoming = nil
            return
        }
        let predicted = positionKnown ? position(at: now) : nil
        let lib = self.lib
        let id = lib.sameSong(matched, currentId) ? currentId! : lib.leadingCopy(of: matched, playingDisc: current?.disc)
        incoming = r.incoming.flatMap { inc in
            if lib.sameSong(inc.id, matched) { return nil }
            var c = inc
            c.id = lib.sameSong(inc.id, currentId) ? currentId! : lib.leadingCopy(of: inc.id, playingDisc: current?.disc)
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
            if paused && inputLevel < Self.quietDB { return }
            let resumed = paused || now.timeIntervalSince(lastCurrentMatch) > 5
            lastCurrentMatch = now
            if notHeard { note("heard again") }
            notHeard = false; byHand = false; deckieRun = nil
            if r.wait != nil { currentHeld = r.fresh ? nil : (r.confidence, now) }
            if resumed {
                if paused { note(String(format: "resumed at %.1fs", offset)) }
                paused = false; frozenAt = nil
                if let pr = predicted, abs(offset - pr) > 2.5 { events.removeAll { $0.id == id } }
                pendingJump = nil; pendingCount = 0; lastOnTrack = now
            } else if let pr = predicted, abs(offset - pr) > 2.5 {
                if r.vouched {
                    note(String(format: "position jump to %.1fs (expected %.1fs)", offset, pr))
                    events.removeAll { $0.id == id }; pendingJump = nil; pendingCount = 0; lastOnTrack = now
                } else if offset < 15 && pr > 30 {
                    note(String(format: "restart from the top (%.1fs)", offset))
                    events.removeAll { $0.id == id }; pendingJump = nil; pendingCount = 0; lastOnTrack = now
                } else {
                    if let pj = pendingJump, abs(pj.offset + now.timeIntervalSince(pj.date) * rate - offset) < 2.5 {
                        pendingCount += 1
                    } else { pendingJump = ev; pendingCount = 1 }
                    if pendingCount >= 2 && now.timeIntervalSince(lastOnTrack) >= 5 {
                        pendingJump = nil; pendingCount = 0
                        events.removeAll { $0.id == id }
                        lastOnTrack = now
                        note(String(format: "position jump confirmed to %.1fs", offset))
                    } else {
                        note(String(format: "ignored %.1fs (expected %.1fs): repeated section?", offset, pr))
                        return
                    }
                }
            } else { pendingJump = nil; pendingCount = 0; lastOnTrack = now }
        }
        events.append(ev)
        if events.count > 12 { events.removeFirst(events.count - 12) }

        if id != currentId {
            if currentId == nil {
                lastCurrentMatch = now
                switchTo(id)
                firstMatchSeconds = now.timeIntervalSince(source == .mic ? max(startedAt, songStartedAt) : startedAt)
            } else if let wait = r.wait {
                if var run = deckieRun, run.id == id {
                    run.count += 1; run.left = min(run.left - 1, wait); deckieRun = run
                } else {
                    let careful = byHand || (id == leftId && now.timeIntervalSince(leftAt) < Self.returnWindow)
                    deckieRun = (id, 1, now, wait, careful ? Self.carefulWait : 1)
                }
                if !r.fresh, let h = currentHeld, now.timeIntervalSince(h.at) <= Self.dominanceWindow, r.confidence <= h.score {
                    // (The app writes `deckieRun?.least = max(deckieRun?.least ?? 0, Self.carefulWait)`; Swift 6 asks
                    // for the value to be read first. The same value.)
                    let least = max(deckieRun?.least ?? 0, Self.carefulWait)
                    deckieRun?.least = least
                }
                challengerLast = now
                guard let run = deckieRun else { return }
                if run.left <= 0 && run.count >= run.least {
                    note(String(format: "switch to %@ (Deckie's: %d reading%@ in %.1f s%@)", lib.track(id)?.song ?? id, run.count,
                                run.count == 1 ? "" : "s", now.timeIntervalSince(run.since), run.least > 1 ? ", the careful wait" : ""))
                    paused = false; frozenAt = nil; lastCurrentMatch = now
                    switchTo(id)
                    challengerId = nil; alsoHearing = nil
                    firstMatchSeconds = now.timeIntervalSince(run.since)
                } else {
                    if max(run.left, run.least - run.count) > 1 { alsoHearing = lib.track(id)?.oneLine }
                    return
                }
            } else {
                if challengerId != id || now.timeIntervalSince(challengerLast) > 12 { challengerId = id; challengerSince = now }
                challengerLast = now
                let recent = hits.filter { now.timeIntervalSince($0.0) <= Self.hold }
                let c = recent.filter { $0.1 == id }.count, k = recent.filter { $0.1 == currentId }.count
                let lastCur = hits.last { $0.1 == currentId }?.0 ?? .distantPast
                let cRecent = hits.filter { $0.1 == id && now.timeIntervalSince($0.0) <= 6 }.count
                let hardCut = now.timeIntervalSince(lastCur) > 3.5 && cRecent >= 3
                let dominated = now.timeIntervalSince(challengerSince) >= Self.hold && c > k
                if dominated || hardCut {
                    note("switch to \(lib.track(id)?.song ?? id) (\(hardCut ? "hard cut" : "blend"): \(c) vs \(k) matches in \(Int(Self.hold)) s)")
                    paused = false; frozenAt = nil; lastCurrentMatch = now
                    switchTo(id)
                    challengerId = nil; alsoHearing = nil
                    firstMatchSeconds = now.timeIntervalSince(challengerSince)
                } else {
                    alsoHearing = lib.track(id)?.oneLine
                    return
                }
            }
        } else if now.timeIntervalSince(challengerLast) > 15 {
            alsoHearing = nil
        }
        pendingId = nil
        let before = (pitchPct, pitchFrom)
        updatePitch(r, ev)
        if abs(pitchPct - before.0) >= 0.05 || pitchFrom != before.1 { note(String(format: "pitch %+.1f%% %@ (%@)", pitchPct, pitchKind.rawValue, pitchFrom)) }
        anchorDate = now; anchorOffset = offset; positionKnown = true
        // (The set's log was written here: a new song at once, the same song every few seconds.)
        shownNewSong = justSwitched
        justSwitched = false
        status = source == .mic ? "listening · matched" : "test file · matched"
    }
    /// Whether the last `take` that reached the end put a new song up (the set's log's `newSong`).
    var shownNewSong = false

    static func median(_ v: [Double]) -> Double {
        guard !v.isEmpty else { return 0 }
        let s = v.sorted(), n = s.count
        return n % 2 == 1 ? s[n / 2] : (s[n / 2 - 1] + s[n / 2]) / 2
    }

    func switchTo(_ id: String, place: PresentPlace? = nil) {
        justSwitched = true
        if let c = currentId, c != id { leftId = c; leftAt = clock() }
        notHeard = false; byHand = false; deckieRun = nil; speeds = nil; currentHeld = nil
        if incoming?.id == id { incoming = nil }
        if id != currentId || place != nil {
            currentPlace = place ?? lib.placed(id, playingDisc: current?.disc)?.place
        }
        if let c = currentId, c != id {
            history.removeAll { $0 == c }
            history.append(c)
            if history.count > 30 { history.removeFirst() }
        }
        currentId = id
        songStartedAt = clock()
        events.removeAll { $0.id != id }
        pitchPct = 0; pitchKind = .none; rate = 1; pitchFrom = ""
    }

    func updatePitch(_ r: PresentReading, _ ev: Event) {
        if r.from == .deckie, let s = r.speedPercent {
            if var run = speeds, run.id == ev.id {
                if abs(s - Self.median(run.values)) <= Self.faderJump {
                    run.values.append(s); run.values = Array(run.values.suffix(Self.pitchReadings)); run.lone = nil
                } else if let lone = run.lone, abs(s - lone) <= Self.faderJump {
                    note(String(format: "fader moved: %+.2f%%, %+.2f%% after %+.2f%%", lone, s, Self.median(run.values)))
                    run.values = [lone, s]; run.lone = nil
                } else {
                    run.lone = s
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
            let same = events.filter { $0.id == ev.id }.suffix(4).map(\.freqRatio)
            let fr = same.reduce(0, +) / Double(same.count)
            pitchPct = ((fr - 1) * 1000).rounded() / 10; pitchKind = .vinyl; rate = fr
            pitchFrom = r.speedFrom
            return
        }
        if r.speedPercent != nil {
            let same = events.filter { $0.id == ev.id }.compactMap(\.speed).suffix(4)
            let s = same.reduce(0, +) / Double(same.count)
            pitchPct = (s * 10).rounded() / 10; rate = 1 + s / 100
            pitchKind = r.keyLock == true ? .masterTempo : .none
            pitchFrom = r.speedFrom
            return
        }
        let same = Array(events.filter { $0.id == ev.id }.suffix(12))
        if let fit = presentSpeedFromPlaces(same.map { ($0.audioTime, $0.offset) }) {
            let p = ((fit.ratio - 1) * 1000).rounded() / 10
            if abs(p) >= 0.3 { pitchPct = p; pitchKind = .masterTempo; rate = fit.ratio; pitchFrom = "position drift over \(Int(fit.span)) s" }
            else { pitchPct = 0; pitchKind = .none; rate = 1; pitchFrom = "position drift" }
            return
        }
        if let hint = r.speedHint {
            pitchPct = hint; pitchKind = .masterTempo; rate = 1 + hint / 100; pitchFrom = "tempo-only variant, measuring"
        } else if pitchKind == .vinyl {
            pitchPct = 0; pitchKind = .none; rate = 1
        }
    }
}
