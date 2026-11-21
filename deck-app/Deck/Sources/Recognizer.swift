import AVFoundation
import Foundation
import ShazamKit
import SwiftUI
import DeckieRecognition
import DeckieBooth

/// Listens (the microphone) or tests a file (streamed as the microphone would hear it, or rendered segments for
/// Apple's), through Deckie's recogniser, Apple's, or both (Listening.swift), and keeps the "now playing" estimate:
/// song, position, pitch, confidence. Every recogniser's word arrives as a `Reading`; `take` hands it to the switching
/// rule, which is the core's (`BoothRule`, DeckieBooth, D42: the same code as Desk's Booth), and keeps the set's log and
/// the status line.
@MainActor @Observable final class Recognizer {
    enum Source: Equatable { case idle, mic, file(String), manual }
    typealias PitchKind = BoothRule.PitchKind

    // public state
    var source: Source = .idle
    // the switching rule's (BoothRule), read through
    /// The switching rule: which song is on screen, its place and pitch, and when it changes.
    private(set) var rule = BoothRule()
    var currentId: String? { rule.currentId }
    var positionKnown: Bool { rule.positionKnown }
    var anchorDate: Date { rule.anchorDate }
    var anchorOffset: Double { rule.anchorOffset }    // seconds into the ORIGINAL track at anchorDate
    var rate: Double { rule.rate }                    // playback tempo relative to the original
    var pitchPct: Double { rule.pitchPct }            // pitch fader estimate
    var pitchKind: PitchKind { rule.pitchKind }
    var pitchFrom: String { rule.pitchFrom }          // how the pitch was found
    var lastMatch: Date? { rule.lastMatch }
    var lastNoMatch: Date? { rule.lastNoMatch }
    var matchCount: Int { rule.matchCount }
    var lastLatencyMs: Double { rule.lastLatencyMs }
    var firstMatchSeconds: Double? { rule.firstMatchSeconds }  // time from start of listening/test to the first match of the current song
    var status = "starting…"
    var log: [String] = []
    var history: [String] { rule.history }      // songs played before the current one (most recent last)
    var micDenied = false
    var noMatchCount: Int { rule.noMatchCount }

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
    /// Whether the open crate file carries each kind of fingerprint.
    var hasDeckie: Bool { (Library.shared.crate?.deckieSongs ?? 0) > 0 }
    var hasApple: Bool { catalog != nil }
    /// The recogniser that will listen: the DJ's choice where the crate file allows it; Deckie's when it has only
    /// Deckie's fingerprints; Apple's when it has only Apple's (a crate file made before D35);
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
    private var lastRaw: [String: Double] = [:]      // last raw match offset per song (Apple's stale-repeat filter)
    private var staleCount = 0
    /// Another song heard while the current one is kept.
    var alsoHearing: String? { rule.alsoHearingId.flatMap { Library.shared.track($0)?.oneLine } }
    /// Deckie's: no reading has named the playing song for a few seconds (talk, silence, the music stopped). The song
    /// stays on screen, marked as not heard just now.
    var notHeard: Bool { rule.notHeard }
    /// The song heard coming in under the playing one, when the recogniser reports one (`Reading.incoming`); the
    /// leading copy of it, never the playing song. Not shown yet: its place is the panel's foot, where "also hearing"
    /// sits now, before the switch.
    var incoming: Reading.Incoming? { rule.incoming }
    private var catalog: SHCustomCatalog?
    private var task: Task<Void, Never>?
    private var ears: [Ear] = []
    private let mic = MicCapture()
    let recorder = SetRecorder()
    /// Whether each listening session is recorded as a set (the REC chip's menu on the Listen page, and the details
    /// sheet): on until the DJ turns it off, and remembered between launches.
    var recordingOn: Bool = UserDefaults.standard.object(forKey: Recognizer.recordingKey) as? Bool ?? true {
        didSet { UserDefaults.standard.set(recordingOn, forKey: Recognizer.recordingKey) }
    }
    static let recordingKey = "recordSets"
    var recActive = false
    var recPaused = false
    /// Why the set cannot be recorded, when its recording would not begin (nil when it began, or is not asked for).
    private(set) var recFailed: String?
    /// What is wrong with the recording in progress (it cannot write), read once a second; nil while it writes.
    private(set) var recTrouble: String?
    /// How the recording that Stop last ended went (its length, or that nothing was recorded); nil with `savedSet`.
    private(set) var lastRecording: RecordingTally?
    /// What listening does when iPadOS takes the sound away or the input changes (`ListenGuard`, AudioInput.swift).
    private(set) var listenGuard = ListenGuard()
    /// Where the sound goes (the recognisers and the recorder), while something is listened to.
    private var sink: CaptureSink?
    private var audioObservers: [NSObjectProtocol] = []
    private var feeder: StreamFeeder?
    private var lastRecorded = Date.distantPast
    var inputLevel: Float = 0     // dBFS-ish RMS of the microphone, for the level meter
    private var startedAt = Date()
    /// The clock of the sound being heard now (the microphone's or the test file's), in seconds.
    private var audioClock: () -> Double = { 0 }

    static let kID = SHMediaItemProperty("deck_id"), kFlav = SHMediaItemProperty("deck_flavour"), kPct = SHMediaItemProperty("deck_pct")

    init() {
        rebuildCatalog()
        recorder.report = { [weak self] s in Task { @MainActor in self?.note(s) } }
        watchAudio()
    }

    /// The recognition catalogues for the crate in use: Deckie's index from the crate file's fingerprints (made
    /// ready off the main thread), and Apple's from its signatures (one plain signature per track, made on the Mac).
    /// With no crate file open there is nothing to listen for (no catalogue ships inside the app).
    func rebuildCatalog() {
        let c = SHCustomCatalog()
        let sigs = Library.shared.crate?.signatures ?? []
        let deckieSongs = Library.shared.crate?.deckieSongs ?? 0
        deckie.prepare(Library.shared.takeFingerprints(), package: Library.shared.crate?.url) { [weak self] in self?.note($0) }
        if let crate = Library.shared.crate, sigs.isEmpty {
            // No Apple signatures: Apple's has nothing to listen for. With no Deckie fingerprints either, songs are set
            // by hand.
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
        } else { catalog = nil; note("no crate file open: nothing to listen for") }
    }

    func note(_ s: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        log.append("\(f.string(from: Date())) \(s)"); FileHandle.standardError.write("DECK \(f.string(from: Date())) \(s)\n".data(using: .utf8)!)
        if log.count > 60 { log.removeFirst(log.count - 60) }
    }

    /// The place the playing song is at (D27): set when the song is set, the place that leads given the place playing
    /// before, or the place it was chosen from in the Crate tab.
    var currentPlace: TrackPlace? { rule.currentPlace }
    /// The playing song, shown at the place it is playing from.
    var current: Track? {
        guard let t = Library.shared.track(currentId) else { return nil }
        if let p = currentPlace, t.places.contains(p) { return t.at(p) }
        return t
    }

    /// position frozen while the deck is paused
    func position(at d: Date) -> Double { rule.position(at: d) }

    // pause / silence handling
    var paused: Bool { rule.paused }    // current song not heard and the room is quiet: position frozen, "paused" hint
    private var heartbeat: Task<Void, Never>?
    static var quietDB: Float { BoothRule.quietDB }     // below this the input counts as silence

    /// The rule's view of where the sound comes from.
    private var ruleSource: BoothRule.Source {
        switch source { case .mic: return .listening; case .file: return .file; case .idle: return .idle; case .manual: return .manual }
    }
    /// The rule's log lines, into the log.
    private func flushNotes() { for n in rule.takeNotes() { note(n) } }

    /// once a second: detect pauses, and only after 2 minutes without any match fall back to "listening…"
    private func tick() {
        if rule.tick(now: Date(), source: ruleSource, deckie: listening == .deckie || listening == .both, level: inputLevel) {
            status = "listening…"
        }
        flushNotes()
        if source == .mic { perform(listenGuard.handle(.tick, now: Date())) }
        let trouble = recActive ? recorder.trouble : nil
        if trouble != recTrouble { recTrouble = trouble }
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
    var confidence: Double { rule.confidence(now: Date(), source: ruleSource) }

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
        source = .mic; status = "listening…"; startedAt = Date(); savedSet = nil; lastRecording = nil
        comparison.reset()
        task = Task { [weak self] in
            let granted = await AVAudioApplication.requestRecordPermission()
            guard let self, !Task.isCancelled else { return }
            if !granted { self.micDenied = true; self.status = "microphone access is off (Settings > Deckie)"; self.note("mic denied"); return }
            // own capture pipeline (instead of SHManagedSession) so the input level can be shown and checked
            let mic = self.mic
            self.audioClock = { mic.audioSeconds }
            guard let ears = self.makeEars(h) else { return }
            self.ears = ears; self.listening = h
            let sink = self.makeSink(ears)
            self.startHeartbeat()
            do {
                let shape = try mic.start(sink: { buf, when in sink.take(buf, at: when) }) { [weak self] level in Task { @MainActor in self?.inputLevel = level } }
                self.perform(self.listenGuard.handle(.started(shape), now: Date()))
            }
            catch {
                // It cannot start now (another app has the sound, no input): said on screen, and tried again by itself.
                self.note("mic start failed: \(error.localizedDescription)"); self.status = "microphone unavailable"
                self.perform(self.listenGuard.handle(.startFailed(error.localizedDescription), now: Date()))
                return
            }
            self.note("mic session started (\(mic.formatText)), recognising with \(h.rawValue)")
            if let f = mic.format { self.beginRecording(f) }
        }
    }

    /// The sink every buffer goes through, for these ears.
    private func makeSink(_ ears: [Ear]) -> CaptureSink {
        let s = CaptureSink(ears: ears, recorder: recorder) { [weak self] line in Task { @MainActor in self?.note(line) } }
        sink = s
        return s
    }

    /// Test source that goes through the same streaming path as the microphone (recognition + recording).
    func startStream(_ url: URL, start: Double, render: String) {
        stop()
        guard let h = hearing else { status = "no catalog"; return }
        if waitForDeckie(h, { [weak self] in self?.startStream(url, start: start, render: render) }) { return }
        let v = TestVariant(render)
        source = .file(url.lastPathComponent + " (stream" + (render == "o" ? "" : " @\(render)") + ")")
        status = "streaming test file"; startedAt = Date(); savedSet = nil; lastRecording = nil
        comparison.reset()
        note("stream \(url.lastPathComponent) from \(Int(start))s render \(render), recognising with \(h.rawValue)")
        let fd = StreamFeeder(); feeder = fd
        audioClock = { fd.audioSeconds }
        guard let ears = makeEars(h) else { return }
        self.ears = ears; listening = h
        startHeartbeat()
        beginRecording(fd.format)
        let sink = makeSink(ears)
        Task.detached {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var lastLevel = Date.distantPast
            do { try await fd.run(url, start: start, variant: v) { buf in
                sink.take(buf, at: nil)
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
        do {
            try recorder.begin(format: format, hearing: listening?.rawValue); recActive = true; recPaused = false; recFailed = nil; recTrouble = nil
            note("recording to \(recorder.baseName ?? "?").aac (\(AudioShape(format)) in, \(ChannelMap.kept(Int(format.channelCount))) ch recorded)")
        }
        catch { note("recording failed: \(error.localizedDescription)"); recActive = false; recFailed = error.localizedDescription }
    }

    /// Set recording on or off. Off closes the recording in progress (what was recorded stays in Files); on starts a
    /// new one at once when the microphone is hearing, otherwise with the next listening session (or when the sound
    /// comes back after an interruption).
    func setRecording(_ on: Bool) {
        guard on != recordingOn else { return }
        recordingOn = on
        if !on {
            if recActive { recorder.finish(); recActive = false; recPaused = false }
            recFailed = nil; recTrouble = nil
            note("set recording switched off")
        } else {
            note("set recording switched on")
            if !recActive, source == .mic, listenGuard.hearing, let f = mic.format { beginRecording(f) }
        }
    }

    func toggleRecPause() {
        guard recActive else { return }
        recorder.paused.toggle(); recPaused = recorder.paused
        note(recPaused ? "recording paused" : "recording resumed")
    }

    /// The set recording the DJ's Stop last ended and saved (its name in Files, Deckie > Sets); nil once listening
    /// starts again, and when Stop found nothing recording.
    private(set) var savedSet: String?

    /// Whether a sound is being listened to now: the microphone, or a test file streamed as it would hear it.
    var isListening: Bool {
        switch source { case .mic, .file: return true; case .idle, .manual: return false }
    }

    /// The Listen page's Stop (`ListenControl`): the microphone off, and the set's recording, if one is running, ended
    /// and saved (what was recorded stays in Files). The song on screen stays, so the picks are still there; listening
    /// starts again only when the DJ asks (Start listening), not on the iPad's return from the lock screen.
    func stopListening() {
        let saved = recActive ? recorder.baseName : nil
        stop()
        savedSet = saved
        if saved == nil { lastRecording = nil }
        note(saved.map { "stopped by the DJ: \($0) saved" + (lastRecording?.nothingRecorded == true ? ", with nothing recorded in it" : "") } ?? "stopped by the DJ")
    }

    func stop() {
        heartbeat?.cancel(); heartbeat = nil
        task?.cancel(); task = nil
        feeder?.cancel(); feeder = nil
        // How long Deckie's readings took while it listened, for the log (the details sheet's Log, and the console):
        // "listener: a, 142 readings, typical 61 ms, slowest 240 ms".
        for case let d as DeckieEar in ears { note(d.timesLine) }
        for e in ears { e.stop() }
        ears = []; listening = nil; sink = nil
        mic.stop()
        _ = listenGuard.handle(.stopped, now: Date())
        if recActive { lastRecording = recorder.finish(); recActive = false; note("recording closed") }
        recTrouble = nil
        if source != .manual { source = .idle }
        status = "stopped"
    }

    // MARK: interruptions and changes of input

    /// What listening is up against now, for the screen: nil while it hears (or is not listening).
    enum ListenTrouble: Equatable { case interrupted, restarting, cannotListen }
    var listenTrouble: ListenTrouble? {
        guard source == .mic else { return nil }
        switch listenGuard.state {
        case .interrupted: return .interrupted
        case .restarting: return .restarting
        case .stalled: return .cannotListen
        case .off, .running: return nil
        }
    }

    /// iPadOS's word on the sound (an interruption, a route change, the engine's configuration change, its audio
    /// restarting), turned into the guard's events. Registered once; nothing happens unless the microphone is on.
    private func watchAudio() {
        let nc = NotificationCenter.default
        func on(_ name: Notification.Name, _ object: AnyObject?, _ event: @escaping @MainActor (Notification) -> ListenGuard.Event?) {
            audioObservers.append(nc.addObserver(forName: name, object: object, queue: .main) { [weak self] n in
                MainActor.assumeIsolated { if let self, let e = event(n) { self.audio(e, from: n.object) } }
            })
        }
        on(AVAudioSession.interruptionNotification, nil) { ListenGuard.Event.interruption($0.userInfo) }
        on(AVAudioSession.routeChangeNotification, nil) {
            ListenGuard.Event.routeChange($0.userInfo, hasInput: !AVAudioSession.sharedInstance().currentRoute.inputs.isEmpty)
        }
        on(AVAudioSession.mediaServicesWereResetNotification, nil) { _ in .mediaReset }
        on(.AVAudioEngineConfigurationChange, nil) { _ in .configurationChanged }
    }

    /// The app came to the front: listening that was interrupted, or that stopped with no word from iPadOS, starts
    /// again (iPadOS does not always say an interruption ended). The DJ's Stop is never undone here.
    func appBecameActive() {
        guard source == .mic else { return }
        if listenGuard.state == .running && !mic.isRunning { note("back at the front and the microphone had stopped"); audio(.configurationChanged); return }
        audio(.appActive)
    }

    /// One event about the sound, from iPadOS or a test (`object`: the engine a configuration change is about).
    func audio(_ e: ListenGuard.Event, from object: Any? = nil) {
        guard source == .mic else { return }
        if case .configurationChanged = e, let eng = object as? AVAudioEngine, eng !== mic.engine { return }   // an engine let go before
        // A change that leaves the input as it was and the engine running needs nothing.
        let inputChange: Bool = { switch e { case .configurationChanged, .routeChanged(.deviceAdded), .routeChanged(.deviceRemoved): return true; default: return false } }()
        if inputChange, listenGuard.state == .running, mic.isRunning, mic.inputNow == listenGuard.shape {
            note("audio: \(e), the input is as it was (\(listenGuard.shape.map { "\($0)" } ?? "?")): listening goes on"); return
        }
        note("audio: \(e)")
        perform(listenGuard.handle(e, now: Date()))
    }

    /// Does what the guard says.
    private func perform(_ actions: [ListenGuard.Action]) {
        for a in actions {
            switch a {
            case .pauseCapture:
                mic.halt()
            case .restartCapture:
                do {
                    let s = try mic.restart()
                    note("listening again (\(s))")
                    perform(listenGuard.handle(.restarted(s), now: Date()))
                    // A set that could not begin before the sound came (listening started during a call): begins now.
                    if recordingOn, !recActive, recFailed == nil, let f = mic.format { beginRecording(f) }
                } catch {
                    note("could not start listening again: \(error.localizedDescription)")
                    perform(listenGuard.handle(.restartFailed(error.localizedDescription), now: Date()))
                }
            case .gapBegan(let why):
                note("no sound: \(why)")
                if recActive { recorder.note("no sound from here: \(why); the recording waits") }
            case .gapEnded(let seconds, let why):
                note(String(format: "sound back after %.0f s (%@)", seconds, why))
                if recActive { recorder.gap(seconds: seconds, why: why) }
            case .formatChanged(let from, let to):
                // The recognisers start fresh with the new format; the recording follows it in the same file.
                note("the input is now \(to) (was \(from)): the recognisers start again with it")
                if recActive { recorder.note("the input is now \(to) (was \(from)); the recording carries on in the same file") }
                if let h = listening, let fresh = makeEars(h) {
                    for case let d as DeckieEar in ears { note(d.timesLine) }
                    for e in ears { e.stop() }
                    ears = fresh; sink?.setEars(fresh)
                }
            }
        }
    }

    /// Another crate file is open: nothing from the last one is playing or was played.
    func forgetSongs() {
        source = .idle
        stop()
        rule.forget()
        savedSet = nil
        comparison.reset()
    }

    /// Sets the playing song by hand; `place` is where it was chosen (the Crate tab), else the place that leads.
    func setManual(_ id: String, place: TrackPlace? = nil) {
        stop()
        rule.setManual(id, place: place, in: Library.shared.booth, now: Date())
        flushNotes()
        source = .manual; status = "set by hand"
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
        // A song carried over a gap (followed, but not heard in this second) is no reading at all.
        guard let reading = Reading(deckie: r, heard: heard) else { return }
        let speed = r.speedPercent
        if r.state == .named, let id = r.id {
            note(String(format: "Deckie named %@ at %.1fs, speed %+.2f%%, key lock %@, confidence %.1f (%.0f ms), heard %.1fs", Library.shared.track(id)?.title ?? id,
                        r.positionSeconds ?? 0, speed ?? 0, r.keyLock.map { $0 ? "on" : "off" } ?? "?", r.confidence, r.milliseconds, r.time))
        }
        if listening == .both, r.id != nil { compared(comparison.heard(reading, at: recorder.isActive ? recorder.elapsed : r.time)) }
        take(reading)
    }

    // MARK: the switching rule's numbers (D35, note of Nov 14): the core's (`BoothRule`), named here as before

    static var listenSettings: ListenSettings { BoothRule.listenSettings }
    static var fairWait: Int { BoothRule.fairWait }
    static func deckieWait(_ r: ListenReading) -> Int { BoothRule.deckieWait(r) }
    static var carefulWait: Int { BoothRule.carefulWait }
    static var returnWindow: TimeInterval { BoothRule.returnWindow }
    static var dominanceWindow: TimeInterval { BoothRule.dominanceWindow }
    static var notHeardAfter: TimeInterval { BoothRule.notHeardAfter }
    static var pitchReadings: Int { BoothRule.pitchReadings }
    static var faderJump: Double { BoothRule.faderJump }

    /// For measuring (launch argument `-traceShown YES`): after each of Deckie's readings, one line on the console with
    /// the sound's time, what the reading said and what the screen shows. Not in the log the details sheet shows.
    /// Debug builds only.
    #if DEBUG
    static let traceShown = UserDefaults.standard.bool(forKey: "traceShown")
    #else
    static let traceShown = false
    #endif
    private func trace(_ r: ListenReading) {
        let lib = Library.shared
        let line = String(format: "SHOWN heard %.1f reading %@ %@ conf %.1f agrees %@ raw %+.2f | screen %@ pitch %+.1f %@ notHeard %@ paused %@\n",
                          r.time, r.id.flatMap { lib.track($0)?.title } ?? "-", r.state.rawValue, r.confidence,
                          r.searched.map { $0.agrees ? "yes" : "no" } ?? "-", r.speedPercent ?? .nan, current?.title ?? "-", pitchPct,
                          pitchKind.rawValue.isEmpty ? "none" : pitchKind.rawValue, notHeard ? "yes" : "no", paused ? "yes" : "no")
        FileHandle.standardError.write(line.data(using: .utf8)!)
    }

    /// Compare mode: the comparison goes into the set's log when something new is in it (a song named, a
    /// disagreement), and every few seconds besides so its speeds and counts stay current.
    private func compared(_ changed: Bool) {
        guard recActive, changed || Date().timeIntervalSince(lastCompared) >= Self.recordEvery else { return }
        recorder.compare(comparison.log); lastCompared = Date()
    }
    private var lastCompared = Date.distantPast

    // MARK: readings into what the DJ sees

    /// The one place a reading, from either recogniser, becomes the playing song, its place, the pitch shown (the
    /// shared rule, `BoothRule.take`) and the set's log.
    private func take(_ r: Reading) {
        let outcome = rule.take(r, in: Library.shared.booth, now: Date(), source: ruleSource, level: inputLevel, startedAt: startedAt)
        flushNotes()
        switch outcome {
        case .nothing:
            if currentId == nil { status = "listening…" }      // with a song on screen, keep it (2-minute rule in tick)
        case .kept:
            break
        case .shown(let newSong):
            // The log follows the panel: a new song at once; the same song's pitch and confidence refreshed at most
            // every few seconds (Deckie's readings come every second).
            if recActive, let t = current, newSong || r.date.timeIntervalSince(lastRecorded) >= Self.recordEvery {
                recorder.record(track: t, pitch: pitchPct, pitchKind: pitchKind.rawValue, confidence: confidence, newSong: newSong,
                                keyLock: r.keyLock, heardBy: r.from.rawValue)
                lastRecorded = r.date
            }
            status = source == .mic ? "listening · matched" : "test file · matched"
        }
    }
    static let recordEvery: TimeInterval = 5
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
/// set recorder, `CaptureSink`).
///
/// `restart` starts it again after an interruption or a change of input: a new engine, so whatever the input is now
/// (its sample rate, its channels) is what the tap takes; the sink and the sound's clock (`audioSeconds`) carry on.
final class MicCapture: @unchecked Sendable {
    private(set) var engine = AVAudioEngine()
    private(set) var formatText = ""
    private var lastLevel = Date.distantPast
    private var sink: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    private var level: ((Float) -> Void)?

    private(set) var format: AVAudioFormat?
    /// seconds of audio heard so far: the clock the drift fit runs on (sample time, not wall time); a gap does not
    /// count, so it runs on across a restart as the recognisers' own clocks do
    private(set) var audioSeconds: Double = 0

    /// Whether the engine is running now.
    var isRunning: Bool { engine.isRunning }
    /// The input's shape as iPadOS has it now (nil with no input).
    var inputNow: AudioShape? {
        let f = engine.inputNode.inputFormat(forBus: 0)
        return f.sampleRate > 0 && f.channelCount > 0 ? AudioShape(f) : nil
    }

    /// The session for a set (what each choice is for is said in the README, "The sound input"):
    /// - play and record, so another app's music on this iPad (a DJ app) is not silenced, as the record category would;
    /// - mix with others: starting to listen never stops or ducks that music;
    /// - measurement: no automatic gain or voice processing on loud music;
    /// - Bluetooth A2DP allowed for output only, so music already going to a Bluetooth speaker stays there; no
    ///   Bluetooth hands-free input is allowed, so a Bluetooth headset never becomes the microphone;
    /// - with UIBackgroundModes=audio, capture continues when the screen locks.
    /// The ring and silent switch never silences recording (it silences only playback, and Deckie plays nothing).
    static let category: AVAudioSession.Category = .playAndRecord
    static let mode: AVAudioSession.Mode = .measurement
    static let options: AVAudioSession.CategoryOptions = [.mixWithOthers, .allowBluetoothA2DP]

    /// Starts listening; the input's shape.
    @discardableResult
    func start(sink: @escaping (AVAudioPCMBuffer, AVAudioTime) -> Void, level: @escaping (Float) -> Void) throws -> AudioShape {
        self.sink = sink; self.level = level
        audioSeconds = 0
        return try run()
    }

    /// Starts again with the input as it is now (after an interruption or a change of input); the input's shape.
    @discardableResult
    func restart() throws -> AudioShape {
        halt()
        engine = AVAudioEngine()
        return try run()
    }

    private func run() throws -> AudioShape {
        guard let sink, let level else { throw NSError(domain: "Deck", code: 3, userInfo: [NSLocalizedDescriptionKey: "listening was not started"]) }
        let av = AVAudioSession.sharedInstance()
        try av.setCategory(Self.category, mode: Self.mode, options: Self.options)
        try av.setActive(true)
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        formatText = "\(Int(fmt.sampleRate)) Hz, \(fmt.channelCount) ch"
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
            throw NSError(domain: "Deck", code: 2, userInfo: [NSLocalizedDescriptionKey: "no microphone input available"])
        }
        input.removeTap(onBus: 0)
        format = fmt
        input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { [weak self] buf, when in
            sink(buf, when)
            self?.audioSeconds += Double(buf.frameLength) / fmt.sampleRate
            guard let self, let ch = buf.floatChannelData?[0], Date().timeIntervalSince(self.lastLevel) > 0.25 else { return }
            self.lastLevel = Date()
            var sum: Float = 0
            let n = Int(buf.frameLength), step = buf.format.isInterleaved ? buf.stride : 1
            for i in 0..<n { let x = ch[i * step]; sum += x * x }
            level(10 * log10(max(1e-9, sum / Float(max(1, n)))))
        }
        engine.prepare()
        do { try engine.start() } catch { input.removeTap(onBus: 0); throw error }
        return AudioShape(fmt)
    }

    /// The engine and its tap stopped (an interruption: the session is iPadOS's to deactivate).
    func halt() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    func stop() {
        halt()
        sink = nil; level = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
