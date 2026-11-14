import AVFoundation
import Foundation
import ShazamKit
import SwiftUI
import DeckieRecognition

/// Listens (the microphone) or tests a file (streamed as the microphone would hear it, or rendered segments for
/// Apple's), through Deckie's recogniser, Apple's, or both (Listening.swift), and keeps the "now playing" estimate:
/// song, position, pitch, confidence. Every recogniser's word arrives as a `Reading`; `take` is the one place a
/// reading becomes the playing song, the pitch shown and the set's log.
@MainActor @Observable final class Recognizer {
    enum Source: Equatable { case idle, mic, file(String), manual }
    enum PitchKind: String { case none = "", vinyl = "vinyl", masterTempo = "master tempo" }

    struct Event { let date: Date; let id: String; let offset: Double; let freqRatio: Double; let speed: Double?; let audioTime: Double }

    // public state
    var source: Source = .idle
    var currentId: String?
    var positionKnown = false
    var anchorDate = Date()
    var anchorOffset = 0.0          // seconds into the ORIGINAL track at anchorDate
    var rate = 1.0                  // playback tempo relative to the original
    var pitchPct = 0.0              // pitch fader estimate
    var pitchKind: PitchKind = .none
    var pitchFrom = ""              // how the pitch was found
    var lastMatch: Date?
    var lastNoMatch: Date?
    var matchCount = 0
    var lastLatencyMs = 0.0
    var firstMatchSeconds: Double?  // time from start of listening/test to the first match of the current song
    var status = "starting…"
    var log: [String] = []
    var history: [String] = []      // songs played before the current one (most recent last)
    var micDenied = false
    var noMatchCount = 0

    // which recogniser (D35)
    /// Deckie's index for the open crate file.
    let deckie = DeckieIndex()
    /// The recognisers listening now (empty when none is), and the comparison of the two in "both".
    private(set) var listening: Hearing?
    let comparison = Comparison()
    /// The DJ's choice (the details sheet; test hook deck://hearing?with=deckie|apple|both), remembered.
    var chosen: Hearing = Hearing.chosen {
        didSet {
            Hearing.chosen = chosen
            guard chosen != oldValue else { return }
            note("recognise with: \(chosen.rawValue) (in use: \(hearing?.rawValue ?? "none"))")
            if source == .mic { startMic() }
        }
    }
    /// Whether the open crate file (or the bundled data) carries each kind of fingerprint.
    var hasDeckie: Bool { (Library.shared.crate?.deckieSongs ?? 0) > 0 }
    var hasApple: Bool { catalog != nil }
    /// The recogniser that will listen: the DJ's choice where the crate file allows it; Deckie's when it has only
    /// Deckie's fingerprints; Apple's when it has only Apple's (a crate file made before D35) or for the bundled data;
    /// nil when it has neither.
    var hearing: Hearing? {
        switch (hasDeckie, hasApple) {
        case (true, true): return chosen
        case (true, false): return .deckie
        case (false, true): return .apple
        default: return nil
        }
    }

    // private
    private var events: [Event] = []
    private var pendingId: String?
    private var pendingCount = 0
    private var lastOnTrack = Date.distantPast
    private var lastRaw: [String: Double] = [:]      // last raw match offset per song (stale-repeat filter)
    private var staleCount = 0
    private var hits: [(Date, String)] = []          // every match of the last 40 s: (time, track id)
    private var challengerId: String?
    private var challengerSince = Date.distantPast
    private var challengerLast = Date.distantPast
    static let hold: TimeInterval = 10
    var alsoHearing: String?                          // another song heard while the current one is kept
    private var pendingJump: Event?   // a same-song match at an unexpected offset (repeated chorus?) waiting for confirmation
    private var catalog: SHCustomCatalog?
    private var task: Task<Void, Never>?
    private var ears: [Ear] = []
    private let mic = MicCapture()
    let recorder = SetRecorder()
    var recordingOn = true          // record every listening session
    var recActive = false
    var recPaused = false
    private var feeder: StreamFeeder?
    private var justSwitched = false
    private var lastRecorded = Date.distantPast
    var inputLevel: Float = 0     // dBFS-ish RMS of the microphone, for the level meter
    private var startedAt = Date()
    private var songStartedAt = Date()
    /// The clock of the sound being heard now (the microphone's or the test file's), in seconds.
    private var audioClock: () -> Double = { 0 }

    static let kID = SHMediaItemProperty("deck_id"), kFlav = SHMediaItemProperty("deck_flavour"), kPct = SHMediaItemProperty("deck_pct")

    init() { rebuildCatalog() }

    /// The recognition catalogues for the crate in use: Deckie's index from the crate file's fingerprints (made
    /// ready off the main thread), and Apple's from its signatures (one plain signature per track, made on the Mac),
    /// else, with no crate, the bundled catalog with its pitch variants.
    func rebuildCatalog() {
        let c = SHCustomCatalog()
        let sigs = Library.shared.crate?.signatures ?? []
        let deckieSongs = Library.shared.crate?.deckieSongs ?? 0
        deckie.prepare(Library.shared.takeFingerprints(), package: Library.shared.crate?.url) { [weak self] in self?.note($0) }
        if let crate = Library.shared.crate, sigs.isEmpty {
            // No Apple signatures: Apple's has nothing to listen for (the bundled catalogue would name songs that are
            // not in this crate). With no Deckie fingerprints either, songs are set by hand.
            catalog = nil
            note(deckieSongs > 0 ? "crate \(crate.name): Deckie's fingerprints for \(deckieSongs) songs, no Apple signatures"
                                 : "crate \(crate.name) has no fingerprints: songs are set by hand")
        } else if !sigs.isEmpty {
            var n = 0
            for s in sigs {
                guard let d = try? Data(contentsOf: s.url), let sig = try? SHSignature(dataRepresentation: d) else { continue }
                let item = SHMediaItem(properties: [.title: s.title, .artist: s.artist, Self.kID: s.id, Self.kFlav: "o", Self.kPct: 0])
                do { try c.addReferenceSignature(sig, representing: [item]); n += 1 }
                catch { note("signature \(s.id): \(error.localizedDescription)") }
            }
            catalog = c
            note("catalog from the crate: \(n) of \(sigs.count) signatures; Deckie's fingerprints for \(deckieSongs) songs")
        } else if let url = Bundle.main.url(forResource: "Deck", withExtension: "shazamcatalog") {
            do { try c.add(from: url); catalog = c; note("catalog loaded (query \(c.minimumQuerySignatureDuration)-\(c.maximumQuerySignatureDuration) s)") }
            catch { note("catalog error: \(error.localizedDescription)") }
        } else { note("no crate and no bundled catalog") }
    }

    func note(_ s: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        log.append("\(f.string(from: Date())) \(s)"); FileHandle.standardError.write("DECK \(f.string(from: Date())) \(s)\n".data(using: .utf8)!)
        if log.count > 60 { log.removeFirst(log.count - 60) }
    }

    /// The place the playing song is at (D27): set when the song is set, the place that leads given the place playing
    /// before, or the place it was chosen from in the Crate tab.
    private(set) var currentPlace: TrackPlace?
    /// The playing song, shown at the place it is playing from.
    var current: Track? {
        guard let t = Library.shared.track(currentId) else { return nil }
        if let p = currentPlace, t.places.contains(p) { return t.at(p) }
        return t
    }

    /// position frozen while the deck is paused (no matches of the song and a quiet input)
    func position(at d: Date) -> Double { anchorOffset + max(0, min(frozenAt ?? d, d).timeIntervalSince(anchorDate)) * rate }

    // pause / silence handling
    var paused = false                  // current song not heard and the room is quiet: position frozen, "paused" hint
    private var frozenAt: Date?
    private var lastCurrentMatch = Date.distantPast
    private var lastAnyMatch = Date.distantPast
    private var heartbeat: Task<Void, Never>?
    static let quietDB: Float = -45     // below this the input counts as silence
    static let silenceClear: TimeInterval = 120

    /// once a second: detect pauses, and only after 2 minutes without any match fall back to "listening…"
    private func tick() {
        let now = Date()
        guard currentId != nil, source != .manual else { return }
        let sinceCur = now.timeIntervalSince(lastCurrentMatch)
        if !paused && sinceCur > 5 && inputLevel < Self.quietDB {
            paused = true; frozenAt = lastCurrentMatch.addingTimeInterval(1)
            note("paused (quiet, no match for \(Int(sinceCur)) s)")
        }
        if now.timeIntervalSince(lastAnyMatch) > Self.silenceClear {
            note("nothing recognised for 2 min: back to listening")
            currentId = nil; currentPlace = nil; paused = false; frozenAt = nil; positionKnown = false; alsoHearing = nil
            events.removeAll(); hits.removeAll()
            status = "listening…"
        }
    }

    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.tick()
            }
        }
    }

    /// 0...1 from how consistent the last few matches are (same song, offsets that line up) and how recent they are.
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
        let age = Date().timeIntervalSince(lastMatch ?? .distantPast)
        let recency = paused ? 1.0 : age < 20 ? 1.0 : max(0.2, 1 - (age - 20) / 150)   // slow decay in noisy stretches
        return agree * (0.4 + 0.6 * consistency) * depth * recency
    }

    // MARK: the recognisers

    /// The ears for what `hearing` asks: Apple's session and Deckie's listener. Nil when one that is needed is not
    /// ready (Deckie's index still being made).
    private func makeEars(_ h: Hearing, fileEnd: Double? = nil) -> [Ear]? {
        var out: [Ear] = []
        if h != .apple {
            guard let index = deckie.index else { return nil }
            out.append(DeckieEar(index: index) { [weak self] r, heard in self?.deckieReading(r, heard: heard) })
        }
        if h != .deckie, let catalog {
            let apple = AppleEar(catalog: catalog)
            out.append(apple)
            let clock = audioClock
            Task { [weak self] in
                for await r in apple.session.results {
                    guard let self, self.ears.contains(where: { $0 === apple }) else { break }
                    self.appleResult(r, receivedAt: Date(), latencyMs: nil, fileEnd: fileEnd, audioTime: clock())
                }
            }
        }
        return out
    }

    /// Deckie's index is not ready yet: says so, and runs `start` when it is.
    private func waitForDeckie(_ h: Hearing, _ start: @escaping () -> Void) -> Bool {
        guard h != .apple, deckie.index == nil else { return false }
        if case .preparing(let n) = deckie.state {
            status = Words.preparingStatus
            note("waiting for Deckie's index (\(n) songs)")
            deckie.whenReady(start)
        } else { status = Words.notListening; note("Deckie's index is not there: \(deckie.state)") }
        return true
    }

    // MARK: microphone

    func startMic() {
        // Nothing to listen for (a crate file with no fingerprints): the playing panel says so once; a song playing by
        // hand stays.
        guard let h = hearing else { if source != .manual { stop(); status = Words.notListening }; return }
        stop()
        if waitForDeckie(h, { [weak self] in self?.startMic() }) { return }
        source = .mic; status = "listening…"; startedAt = Date()
        comparison.reset()
        task = Task { [weak self] in
            let granted = await AVAudioApplication.requestRecordPermission()
            guard let self, !Task.isCancelled else { return }
            if !granted { self.micDenied = true; self.status = "microphone access is off (Settings > Deck)"; self.note("mic denied"); return }
            // own capture pipeline (instead of SHManagedSession) so the input level can be shown and checked
            let mic = self.mic
            self.audioClock = { mic.audioSeconds }
            guard let ears = self.makeEars(h) else { return }
            self.ears = ears; self.listening = h
            let rec = self.recorder
            do {
                try mic.start(sink: { buf, when in for e in ears { e.hear(buf, at: when) }; rec.append(buf) }) { [weak self] level in Task { @MainActor in self?.inputLevel = level } }
            }
            catch { self.note("mic start failed: \(error.localizedDescription)"); self.status = "microphone unavailable"; return }
            self.note("mic session started (\(mic.formatText)), recognising with \(h.rawValue)")
            self.startHeartbeat()
            if let f = mic.format { self.beginRecording(f) }
        }
    }

    /// Test source that goes through the same streaming path as the microphone (recognition + recording).
    func startStream(_ url: URL, start: Double, render: String) {
        stop()
        guard let h = hearing else { status = "no catalog"; return }
        if waitForDeckie(h, { [weak self] in self?.startStream(url, start: start, render: render) }) { return }
        let v = TestVariant(render)
        source = .file(url.lastPathComponent + " (stream" + (render == "o" ? "" : " @\(render)") + ")")
        status = "streaming test file"; startedAt = Date()
        comparison.reset()
        note("stream \(url.lastPathComponent) from \(Int(start))s render \(render), recognising with \(h.rawValue)")
        let fd = StreamFeeder(); feeder = fd
        audioClock = { fd.audioSeconds }
        guard let ears = makeEars(h) else { return }
        self.ears = ears; listening = h
        startHeartbeat()
        beginRecording(fd.format)
        let rec = recorder
        Task.detached {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var lastLevel = Date.distantPast
            do { try await fd.run(url, start: start, variant: v) { buf in
                for e in ears { e.hear(buf, at: nil) }
                rec.append(buf)
                if Date().timeIntervalSince(lastLevel) > 0.25, let ch = buf.floatChannelData?[0] {
                    lastLevel = Date()
                    var sum: Float = 0; let n = Int(buf.frameLength)
                    for i in 0..<n { sum += ch[i] * ch[i] }
                    let db = 10 * log10(max(1e-9, sum / Float(max(1, n))))
                    Task { @MainActor in self.inputLevel = db }
                }
            } }
            catch { await MainActor.run { self.note("stream failed: \(error.localizedDescription)") } }
            await MainActor.run { self.note("stream ended at \(String(format: "%.1f", fd.audioSeconds)) s") }
        }
    }

    // MARK: set recording

    func beginRecording(_ format: AVAudioFormat) {
        guard recordingOn else { return }
        do { try recorder.begin(format: format, hearing: listening?.rawValue); recActive = true; recPaused = false; note("recording to \(recorder.baseName ?? "?").aac") }
        catch { note("recording failed: \(error.localizedDescription)"); recActive = false }
    }

    func toggleRecPause() {
        guard recActive else { return }
        recorder.paused.toggle(); recPaused = recorder.paused
        note(recPaused ? "recording paused" : "recording resumed")
    }

    func stop() {
        heartbeat?.cancel(); heartbeat = nil
        task?.cancel(); task = nil
        feeder?.cancel(); feeder = nil
        for e in ears { e.stop() }
        ears = []; listening = nil
        mic.stop()
        if recActive { recorder.finish(); recActive = false; note("recording closed") }
        if source != .manual { source = .idle }
        status = "stopped"
    }

    /// Another crate file is open: nothing from the last one is playing or was played.
    func forgetSongs() {
        source = .idle
        stop()
        currentId = nil; currentPlace = nil; history = []; positionKnown = false; paused = false; frozenAt = nil
        alsoHearing = nil; events.removeAll(); hits.removeAll(); pendingId = nil; challengerId = nil
        comparison.reset()
    }

    /// Sets the playing song by hand; `place` is where it was chosen (the Crate tab), else the place that leads.
    func setManual(_ id: String, place: TrackPlace? = nil) {
        stop()
        switchTo(id, place: place)
        source = .manual; positionKnown = false; status = "set by hand"
        events.removeAll()
    }

    // MARK: file test (debug): matches rendered segments of a file, optionally simulating continuous play

    /// render: "o", "r+4" (vinyl), "t-4" (tempo only). loop: keep matching the next segment every 4 s as if playing.
    /// Rendered segments are Apple's way; Deckie's recogniser follows the sound as it goes, so with Deckie's (or both)
    /// the file is streamed as the microphone would hear it instead.
    func testFile(_ url: URL, start: Double, render: String, loop: Bool) {
        if let h = hearing, h != .apple { note("test file: streamed, for Deckie's"); startStream(url, start: start, render: render); return }
        stop()
        guard let catalog else { status = "no catalog"; return }
        let v = TestVariant(render)
        source = .file(url.lastPathComponent + (render == "o" ? "" : " @\(render)"))
        status = "testing \(url.lastPathComponent)…"; startedAt = Date()
        note("test \(url.lastPathComponent) from \(Int(start))s render \(render) loop \(loop)")
        task = Task { [weak self] in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let session = SHSession(catalog: catalog)
            let t0 = Date()
            repeat {
                let elapsed = Date().timeIntervalSince(t0)
                let qStart = start + elapsed * v.tempo              // original-track seconds where this segment starts
                let dur = 8.0
                let tr = Date()
                let sig: SHSignature
                do { sig = try await Task.detached { try FileRenderer.signature(url, start: qStart, dur: dur * v.tempo, variant: v) }.value }
                catch { self?.note("render failed: \(error.localizedDescription)"); self?.status = "could not read the file"; return }
                let renderMs = Date().timeIntervalSince(tr) * 1000
                let tm = Date()
                let r = await session.result(from: sig)
                let ms = Date().timeIntervalSince(tm) * 1000
                guard let self, !Task.isCancelled else { return }
                self.note(String(format: "segment @%.1fs: render %.0f ms, match %.0f ms", qStart, renderMs, ms))
                self.appleResult(r, receivedAt: t0.addingTimeInterval(elapsed), latencyMs: ms, fileEnd: 0, audioTime: elapsed)   // offsets at the segment start, timed on the simulated playback clock
                if !loop { break }
                try? await Task.sleep(for: .seconds(4))
            } while !Task.isCancelled
        }
    }

    // MARK: Apple's results as readings

    private func appleResult(_ r: SHSession.Result, receivedAt now: Date, latencyMs: Double?, fileEnd: Double?, audioTime: Double) {
        switch r {
        case .match(let m):
            guard let reading = appleReading(m, now: now, latencyMs: latencyMs, fileEnd: fileEnd, audioTime: audioTime) else { return }
            if listening == .both {
                compared(comparison.heard(reading, at: recorder.isActive ? recorder.elapsed : audioTime))
            } else { take(reading) }
        case .noMatch:
            if listening == .both { return }
            take(Reading(from: .apple, date: now, audioTime: audioTime, id: nil, milliseconds: latencyMs))
        case .error(let e, _):
            note("error: \(e.localizedDescription)")
            if listening != .both { status = "listening… (\(e.localizedDescription))" }
        @unknown default: break
        }
    }

    /// One of Apple's matches as a reading: the item that is the playing song at its expected place if there is one,
    /// its place in the original (the catalogue's pitch variants undone), the key's skew, and the tempo-only variant's
    /// percent as a stand-in. Nil for a stale repeat: ShazamKit keeps re-reporting the last match while the input is
    /// silent (same raw match offset, only the prediction moves on); those are not new evidence, and skipping them
    /// lets pauses and cuts be seen.
    private func appleReading(_ m: SHMatch, now: Date, latencyMs: Double?, fileEnd: Double?, audioTime: Double) -> Reading? {
        // several items can match (other cuts, repeated sections): prefer the current song at the expected position
        let predicted = positionKnown ? position(at: now) : nil
        func origOffset(_ it: SHMatchedMediaItem) -> Double {
            let f = it[Self.kFlav] as? String ?? "o", p = it[Self.kPct] as? Int ?? 0
            return (fileEnd.map { it.matchOffset + $0 } ?? it.predictedCurrentMatchOffset) * (f == "o" ? 1 : 1 + Double(p) / 100)
        }
        // the playing song is any copy of its recording (D24): the same audio, so the same place in it
        let lib = Library.shared
        let sameSong = m.mediaItems.filter { lib.sameSong($0[Self.kID] as? String, currentId) }
        let preferred = predicted.flatMap { pr in sameSong.min { abs(origOffset($0) - pr) < abs(origOffset($1) - pr) } }
        guard let item = preferred ?? m.mediaItems.first, let matched = item[Self.kID] as? String else { return nil }
        let staleKey = lib.track(matched)?.cut ?? matched
        let raw = item.matchOffset
        if fileEnd == nil, let last = lastRaw[staleKey], abs(last - raw) < 0.15 {
            staleCount += 1
            if staleCount % 10 == 1 { note(String(format: "stale repeat of %@ at %.1fs ignored", Library.shared.track(matched)?.song ?? matched, raw)) }
            return nil
        }
        lastRaw[staleKey] = raw
        let flav = item[Self.kFlav] as? String ?? "o"
        let pct = item[Self.kPct] as? Int ?? 0
        let vr = 1 + Double(pct) / 100
        let refTempo = flav == "o" ? 1.0 : vr
        let refFreq = flav == "r" ? vr : 1.0
        let freqRatio = refFreq * (1 + Double(item.frequencySkew))
        // reference seconds now -> original seconds
        let refNow = fileEnd.map { item.matchOffset + $0 } ?? item.predictedCurrentMatchOffset
        let offset = refNow * refTempo
        let name = Library.shared.track(matched)?.title ?? matched
        note(String(format: "match %@ [%@%@] at %.1fs (raw %.1f) skew %+.4f, heard %.1fs", name, flav, flav == "o" ? "" : String(format: "%+d", pct), offset, raw, item.frequencySkew, audioTime))
        return Reading(from: .apple, date: now, audioTime: audioTime, id: matched, position: offset, speedPercent: nil,
                       keyLock: abs(freqRatio - 1) > 0.008 ? false : nil, pitchRatio: freqRatio,
                       speedHint: flav == "t" ? Double(pct) : nil,
                       speedFrom: flav == "r" ? "vinyl variant \(pct > 0 ? "+" : "")\(pct)% + skew" : "frequency skew",
                       milliseconds: latencyMs)
    }

    // MARK: Deckie's readings

    /// One of Deckie's readings (a second of sound). "Nothing yet" is a no-match; a song carried over a gap
    /// (followed, but not heard in this second) is no new evidence and changes nothing.
    private func deckieReading(_ r: ListenReading, heard: Date) {
        guard listening == .deckie || listening == .both else { return }
        defer { if Self.traceShown { trace(r) } }
        if r.state == .held && r.confidence == 0 { return }
        let speed = r.speedPercent
        let reading = Reading(from: .deckie, date: heard, audioTime: r.time, id: r.id, position: r.positionSeconds, speedPercent: speed,
                              keyLock: r.keyLock, pitchRatio: r.keyLock == false ? 1 + (speed ?? 0) / 100 : 1,
                              speedFrom: Words.speedFromDeckie, confidence: r.confidence, vouched: true,
                              fresh: r.state == .named, milliseconds: r.milliseconds)
        if r.state == .named, let id = r.id {
            note(String(format: "Deckie named %@ at %.1fs, speed %+.2f%%, key lock %@, confidence %.1f (%.0f ms), heard %.1fs", Library.shared.track(id)?.title ?? id,
                        r.positionSeconds ?? 0, speed ?? 0, r.keyLock.map { $0 ? "on" : "off" } ?? "?", r.confidence, r.milliseconds, r.time))
        }
        if listening == .both, r.id != nil { compared(comparison.heard(reading, at: recorder.isActive ? recorder.elapsed : r.time)) }
        take(reading)
    }

    /// For measuring (launch argument `-traceShown YES`): after each of Deckie's readings, one line on the console with
    /// the sound's time, what the reading said and what the screen shows. Not in the log the details sheet shows.
    static let traceShown = UserDefaults.standard.bool(forKey: "traceShown")
    private func trace(_ r: ListenReading) {
        let lib = Library.shared
        let line = String(format: "SHOWN heard %.1f reading %@ %@ conf %.1f agrees %@ | screen %@ pitch %+.1f %@ notHeard %@ paused %@\n",
                          r.time, r.id.flatMap { lib.track($0)?.title } ?? "-", r.state.rawValue, r.confidence,
                          r.searched.map { $0.agrees ? "yes" : "no" } ?? "-", current?.title ?? "-", pitchPct, pitchKind.rawValue.isEmpty ? "none" : pitchKind.rawValue,
                          notHeardFlag ? "yes" : "no", paused ? "yes" : "no")
        FileHandle.standardError.write(line.data(using: .utf8)!)
    }
    /// The trace's view of whether the playing song is marked as not heard just now (false before D35's letting go).
    private var notHeardFlag: Bool { false }

    /// Compare mode: the comparison goes into the set's log when something new is in it (a song named, a
    /// disagreement), and every few seconds besides so its speeds and counts stay current.
    private func compared(_ changed: Bool) {
        guard recActive, changed || Date().timeIntervalSince(lastCompared) >= Self.recordEvery else { return }
        recorder.compare(comparison.log); lastCompared = Date()
    }
    private var lastCompared = Date.distantPast

    // MARK: readings into what the DJ sees

    /// The one place a reading, from either recogniser, becomes the playing song, its place, the pitch shown and the
    /// set's log.
    private func take(_ r: Reading) {
        let now = r.date
        guard let matched = r.id, let offset = r.position else {
            lastNoMatch = now
            noMatchCount += 1
            if noMatchCount % 5 == 1 { note(String(format: "no match (%d so far), input %.0f dB", noMatchCount, inputLevel)) }
            if let ms = r.milliseconds { lastLatencyMs = ms }
            if currentId == nil { status = "listening…" }      // with a song on screen, keep it (2-minute rule in tick)
            return
        }
        let predicted = positionKnown ? position(at: now) : nil
        // Whichever copy was heard, the song is named once: a copy of the playing song is the playing song (never a
        // song change), and another song is the copy whose place leads (on the playing song's disc, else the first
        // disc in order), so every copy of it counts as one challenger.
        let lib = Library.shared
        let id = lib.sameSong(matched, currentId) ? currentId! : lib.leadingCopy(of: matched, playingDisc: current?.disc)
        matchCount += 1
        lastMatch = now
        if let ms = r.milliseconds { lastLatencyMs = ms }
        let ev = Event(date: now, id: id, offset: offset, freqRatio: r.pitchRatio, speed: r.speedPercent, audioTime: r.audioTime)
        hits.append((now, id))
        hits.removeAll { now.timeIntervalSince($0.0) > 40 }
        lastAnyMatch = now
        if id == currentId {
            // a match while the room is still quiet is buffered audio from before the pause, not a resume
            if paused && inputLevel < Self.quietDB { return }
            let resumed = paused || now.timeIntervalSince(lastCurrentMatch) > 5
            lastCurrentMatch = now
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
                    // 2 agreeing matches, and the old place no longer heard for 5 s (repeated choruses
                    // otherwise make ShazamKit alternate between two equally good positions)
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

        // hysteresis: a new song takes over only after it has out-matched the current one for ~10 s
        // (Mike blends for long stretches); while both are heard the current one stays, with a note.
        if id != currentId {
            if currentId == nil {
                lastCurrentMatch = now
                switchTo(id)
                firstMatchSeconds = now.timeIntervalSince(source == .mic ? max(startedAt, songStartedAt) : startedAt)
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
                    note("switch to \(Library.shared.track(id)?.song ?? id) (\(hardCut ? "hard cut" : "blend"): \(c) vs \(k) matches in \(Int(Self.hold)) s)")
                    paused = false; frozenAt = nil; lastCurrentMatch = now
                    switchTo(id)
                    challengerId = nil; alsoHearing = nil
                    firstMatchSeconds = now.timeIntervalSince(challengerSince)
                } else {
                    alsoHearing = Library.shared.track(id)?.oneLine
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
        // The log follows the panel: a new song at once; the same song's pitch and confidence refreshed at most every
        // few seconds (Deckie's readings come every second).
        if recActive, let t = current, justSwitched || now.timeIntervalSince(lastRecorded) >= Self.recordEvery {
            recorder.record(track: t, pitch: pitchPct, pitchKind: pitchKind.rawValue, confidence: confidence, newSong: justSwitched,
                            keyLock: r.keyLock, heardBy: r.from.rawValue)
            lastRecorded = now
        }
        justSwitched = false
        status = source == .mic ? "listening · matched" : "test file · matched"
    }
    static let recordEvery: TimeInterval = 5

    private func switchTo(_ id: String, place: TrackPlace? = nil) {
        justSwitched = true
        if id != currentId || place != nil {
            currentPlace = place ?? Library.shared.placed(id, playingDisc: current?.disc)?.place
        }
        if let c = currentId, c != id {
            history.removeAll { $0 == c }
            history.append(c)
            if history.count > 30 { history.removeFirst() }
        }
        currentId = id
        songStartedAt = Date()
        events.removeAll { $0.id != id }
        pitchPct = 0; pitchKind = .none; rate = 1; pitchFrom = ""
    }

    /// The pitch shown, from the readings of the playing song: the key moved (vinyl-style), the speed read from one
    /// listen (Deckie's), or the speed from how fast the place moves (Apple's with the key held).
    private func updatePitch(_ r: Reading, _ ev: Event) {
        if abs(ev.freqRatio - 1) > 0.008 {
            // vinyl-style (master tempo off): key and tempo moved together; the key's ratio says how much, averaged
            // over the song's last four readings and shown to a tenth
            let same = events.filter { $0.id == ev.id }.suffix(4).map(\.freqRatio)
            let fr = same.reduce(0, +) / Double(same.count)
            pitchPct = ((fr - 1) * 1000).rounded() / 10; pitchKind = .vinyl; rate = fr
            pitchFrom = r.speedFrom
            return
        }
        if r.speedPercent != nil {
            // Deckie's: the deck's speed from each listen, the key held or not to be told; averaged over the song's
            // last four readings and shown to a tenth. With the key held the tempo shown is still the tempo the song
            // plays at (the BPM and the song time follow `rate`).
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

// MARK: - offline rendering of a file segment through a pitch variant (same code path as tools/catalogtool)

struct TestVariant {
    let flavour: String; let pct: Int
    init(_ s: String) {
        if s == "o" || s.isEmpty { flavour = "o"; pct = 0 } else { flavour = String(s.prefix(1)); pct = Int(s.dropFirst()) ?? 0 }
    }
    var tempo: Double { 1 + Double(pct) / 100 }
}

enum FileRenderer {
    static let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!

    static func signature(_ url: URL, start: Double, dur: Double, variant: TestVariant) throws -> SHSignature {
        let file = try AVAudioFile(forReading: url)
        let sr = file.processingFormat.sampleRate
        let startF = AVAudioFramePosition(max(0, start) * sr)
        guard startF < file.length else { throw NSError(domain: "Deck", code: 1, userInfo: [NSLocalizedDescriptionKey: "past the end of the file"]) }
        let count = AVAudioFrameCount(min(Double(file.length - startF), dur * sr))
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        engine.attach(player)
        try engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 8192)
        var unit: AVAudioNode?
        if variant.flavour == "r" { let v = AVAudioUnitVarispeed(); v.rate = Float(variant.tempo); unit = v }
        if variant.flavour == "t" { let t = AVAudioUnitTimePitch(); t.rate = Float(variant.tempo); unit = t }
        if let u = unit {
            engine.attach(u)
            engine.connect(player, to: u, format: file.processingFormat)
            engine.connect(u, to: engine.mainMixerNode, format: file.processingFormat)
        } else { engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat) }
        player.scheduleSegment(file, startingFrame: startF, frameCount: count, at: nil)
        try engine.start(); player.play()
        let total = AVAudioFramePosition(Double(count) / sr / variant.tempo * 44100)
        let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 8192)!
        let gen = SHSignatureGenerator()
        var done: AVAudioFramePosition = 0
        while done < total {
            let st = try engine.renderOffline(AVAudioFrameCount(min(8192, total - done)), to: buf)
            guard st == .success else { break }
            try gen.append(buf, at: nil)
            done += AVAudioFramePosition(buf.frameLength)
        }
        player.stop(); engine.stop()
        return gen.signature()
    }
}

/// The microphone, asked for the least processed input iPadOS gives (measurement mode: no automatic gain on loud
/// music), plus an RMS level for the meter. One engine, one tap: every buffer goes to `sink` (the recognisers and the
/// set recorder).
final class MicCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private(set) var formatText = ""
    private var lastLevel = Date.distantPast

    private(set) var format: AVAudioFormat?
    /// seconds of audio heard so far: the clock the drift fit runs on (sample time, not wall time)
    private(set) var audioSeconds: Double = 0

    func start(sink: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void, level: @escaping (Float) -> Void) throws {
        let av = AVAudioSession.sharedInstance()
        // measurement: no automatic gain on loud music; with UIBackgroundModes=audio, capture continues when the screen locks
        try av.setCategory(.record, mode: .measurement, options: [])
        try av.setActive(true)
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        formatText = "\(Int(fmt.sampleRate)) Hz, \(fmt.channelCount) ch"
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            throw NSError(domain: "Deck", code: 2, userInfo: [NSLocalizedDescriptionKey: "no microphone input available"])
        }
        input.removeTap(onBus: 0)
        format = fmt; audioSeconds = 0
        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, when in
            sink(buf, when)
            self?.audioSeconds += Double(buf.frameLength) / fmt.sampleRate
            guard let self, let ch = buf.floatChannelData?[0], Date().timeIntervalSince(self.lastLevel) > 0.25 else { return }
            self.lastLevel = Date()
            var sum: Float = 0
            let n = Int(buf.frameLength)
            for i in 0..<n { sum += ch[i] * ch[i] }
            level(10 * log10(max(1e-9, sum / Float(max(1, n)))))
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
