import AVFoundation
import Foundation
import ShazamKit
import SwiftUI

/// Listens (SHManagedSession on the microphone) or tests a file (rendered segments matched with SHSession),
/// against the bundled custom catalog, and keeps the "now playing" estimate: song, position, pitch, confidence.
@MainActor @Observable final class Recognizer {
    enum Source: Equatable { case idle, mic, file(String), manual }
    enum PitchKind: String { case none = "", vinyl = "vinyl", masterTempo = "master tempo" }

    struct Event { let date: Date; let id: String; let offset: Double; let freqRatio: Double; let flavour: String; let pct: Int; let audioTime: Double }

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
    private let mic = MicCapture()
    let recorder = SetRecorder()
    var recordingOn = true          // record every listening session
    var recActive = false
    var recPaused = false
    private var feeder: StreamFeeder?
    private var justSwitched = false
    var inputLevel: Float = 0     // dBFS-ish RMS of the microphone, for the level meter
    private var startedAt = Date()
    private var songStartedAt = Date()

    static let kID = SHMediaItemProperty("deck_id"), kFlav = SHMediaItemProperty("deck_flavour"), kPct = SHMediaItemProperty("deck_pct")

    init() { rebuildCatalog() }

    /// The recognition catalogue: from the crate's signatures when a crate is in use (one plain signature per
    /// track, made on the Mac), else the bundled catalog with its pitch variants.
    func rebuildCatalog() {
        let c = SHCustomCatalog()
        let sigs = Library.shared.crate?.signatures ?? []
        if !sigs.isEmpty {
            var n = 0
            for s in sigs {
                guard let d = try? Data(contentsOf: s.url), let sig = try? SHSignature(dataRepresentation: d) else { continue }
                let item = SHMediaItem(properties: [.title: s.title, .artist: s.artist, Self.kID: s.id, Self.kFlav: "o", Self.kPct: 0])
                do { try c.addReferenceSignature(sig, representing: [item]); n += 1 }
                catch { note("signature \(s.id): \(error.localizedDescription)") }
            }
            catalog = c
            note("catalog from the crate: \(n) of \(sigs.count) signatures")
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

    var current: Track? { Library.shared.track(currentId) }

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
            currentId = nil; paused = false; frozenAt = nil; positionKnown = false; alsoHearing = nil
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

    // MARK: microphone

    func startMic() {
        stop()
        guard let catalog else { status = "no catalog"; return }
        source = .mic; status = "listening…"; startedAt = Date()
        task = Task { [weak self] in
            let granted = await AVAudioApplication.requestRecordPermission()
            guard let self else { return }
            if !granted { self.micDenied = true; self.status = "microphone access is off (Settings > Deck)"; self.note("mic denied"); return }
            // own capture pipeline (instead of SHManagedSession) so the input level can be shown and checked
            let session = SHSession(catalog: catalog)
            let rec = self.recorder
            do {
                try self.mic.start(session: session, sink: { rec.append($0) }) { [weak self] level in Task { @MainActor in self?.inputLevel = level } }
            }
            catch { self.note("mic start failed: \(error.localizedDescription)"); self.status = "microphone unavailable"; return }
            self.note("mic session started (\(self.mic.formatText))")
            self.startHeartbeat()
            if let f = self.mic.format { self.beginRecording(f) }
            for await r in session.results {
                if Task.isCancelled { break }
                self.handle(r, receivedAt: Date(), latencyMs: nil, fileEnd: nil, audioTime: self.mic.audioSeconds)
            }
            self.note("mic session ended")
        }
    }

    /// Test source that goes through the same streaming path as the microphone (recognition + recording).
    func startStream(_ url: URL, start: Double, render: String) {
        stop()
        guard let catalog else { status = "no catalog"; return }
        let v = TestVariant(render)
        source = .file(url.lastPathComponent + " (stream" + (render == "o" ? "" : " @\(render)") + ")")
        status = "streaming test file"; startedAt = Date()
        note("stream \(url.lastPathComponent) from \(Int(start))s render \(render)")
        let session = SHSession(catalog: catalog)
        let fd = StreamFeeder(); feeder = fd
        startHeartbeat()
        beginRecording(fd.format)
        let rec = recorder
        Task.detached {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            var lastLevel = Date.distantPast
            do { try await fd.run(url, start: start, variant: v) { buf in
                session.matchStreamingBuffer(buf, at: nil); rec.append(buf)
                if Date().timeIntervalSince(lastLevel) > 0.25, let ch = buf.floatChannelData?[0] {
                    lastLevel = Date()
                    var sum: Float = 0; let n = Int(buf.frameLength)
                    for i in 0..<n { sum += ch[i] * ch[i] }
                    let db = 10 * log10(max(1e-9, sum / Float(max(1, n))))
                    Task { @MainActor in self.inputLevel = db }
                }
            } }
            catch { await MainActor.run { self.note("stream failed: \(error.localizedDescription)") } }
        }
        task = Task { [weak self] in
            for await r in session.results {
                if Task.isCancelled { break }
                self?.handle(r, receivedAt: Date(), latencyMs: nil, fileEnd: nil, audioTime: fd.audioSeconds)
            }
        }
    }

    // MARK: set recording

    func beginRecording(_ format: AVAudioFormat) {
        guard recordingOn else { return }
        do { try recorder.begin(format: format); recActive = true; recPaused = false; note("recording to \(recorder.baseName ?? "?").aac") }
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
        mic.stop()
        if recActive { recorder.finish(); recActive = false; note("recording closed") }
        if source != .manual { source = .idle }
        status = "stopped"
    }

    func setManual(_ id: String) {
        stop()
        switchTo(id)
        source = .manual; positionKnown = false; status = "set by hand"
        events.removeAll()
    }

    // MARK: file test (debug): matches rendered segments of a file, optionally simulating continuous play

    /// render: "o", "r+4" (vinyl), "t-4" (tempo only). loop: keep matching the next segment every 4 s as if playing.
    func testFile(_ url: URL, start: Double, render: String, loop: Bool) {
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
                self.handle(r, receivedAt: t0.addingTimeInterval(elapsed), latencyMs: ms, fileEnd: 0, audioTime: elapsed)   // offsets at the segment start, timed on the simulated playback clock
                if !loop { break }
                try? await Task.sleep(for: .seconds(4))
            } while !Task.isCancelled
        }
    }

    // MARK: result handling

    private func handle(_ r: SHSession.Result, receivedAt now: Date, latencyMs: Double?, fileEnd: Double?, audioTime: Double? = nil) {
        switch r {
        case .match(let m):
            // several items can match (other cuts, repeated sections): prefer the current song at the expected position
            let predicted = positionKnown ? position(at: now) : nil
            func origOffset(_ it: SHMatchedMediaItem) -> Double {
                let f = it[Self.kFlav] as? String ?? "o", p = it[Self.kPct] as? Int ?? 0
                return (fileEnd.map { it.matchOffset + $0 } ?? it.predictedCurrentMatchOffset) * (f == "o" ? 1 : 1 + Double(p) / 100)
            }
            let sameSong = m.mediaItems.filter { ($0[Self.kID] as? String) == currentId }
            let preferred = predicted.flatMap { pr in sameSong.min { abs(origOffset($0) - pr) < abs(origOffset($1) - pr) } }
            guard let item = preferred ?? m.mediaItems.first, let id = item[Self.kID] as? String else { return }
            // ShazamKit keeps re-reporting the last match while the input is silent (same raw match offset, only the
            // prediction moves on). Those repeats are not new evidence: skip them, so pauses and cuts are seen.
            let raw = item.matchOffset
            if fileEnd == nil, let last = lastRaw[id], abs(last - raw) < 0.15 {
                staleCount += 1
                if staleCount % 10 == 1 { note(String(format: "stale repeat of %@ at %.1fs ignored", Library.shared.track(id)?.song ?? id, raw)) }
                return
            }
            lastRaw[id] = raw
            // another cut of the song now playing (an alternate version in the catalogue): same song, not a challenger
            if let c = current, id != c.id, let t = Library.shared.track(id), t.songKey == c.songKey {
                hits.append((now, c.id)); lastMatch = now; lastAnyMatch = now; lastCurrentMatch = now
                if paused { paused = false; frozenAt = nil }
                return
            }
            let flav = item[Self.kFlav] as? String ?? "o"
            let pct = item[Self.kPct] as? Int ?? 0
            let vr = 1 + Double(pct) / 100
            let refTempo = flav == "o" ? 1.0 : vr
            let refFreq = flav == "r" ? vr : 1.0
            let freqRatio = refFreq * (1 + Double(item.frequencySkew))
            // reference seconds now -> original seconds
            let refNow = fileEnd.map { item.matchOffset + $0 } ?? item.predictedCurrentMatchOffset
            let offset = refNow * refTempo
            matchCount += 1
            lastMatch = now
            if let latencyMs { lastLatencyMs = latencyMs }
            let ev = Event(date: now, id: id, offset: offset, freqRatio: freqRatio, flavour: flav, pct: pct, audioTime: audioTime ?? now.timeIntervalSince(startedAt))
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
                    if offset < 15 && pr > 30 {
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
            let name = Library.shared.track(id)?.title ?? id
            note(String(format: "match %@ [%@%@] at %.1fs (raw %.1f) skew %+.4f", name, flav, flav == "o" ? "" : String(format: "%+d", pct), offset, raw, item.frequencySkew))

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
                        alsoHearing = Library.shared.track(id)?.song
                        return
                    }
                }
            } else if now.timeIntervalSince(challengerLast) > 15 {
                alsoHearing = nil
            }
            pendingId = nil
            let before = (pitchPct, pitchFrom)
            updatePitch(ev, flavour: flav, pct: pct, vr: vr)
            if abs(pitchPct - before.0) >= 0.05 || pitchFrom != before.1 { note(String(format: "pitch %+.1f%% %@ (%@)", pitchPct, pitchKind.rawValue, pitchFrom)) }
            anchorDate = now; anchorOffset = offset; positionKnown = true
            if recActive, let t = current {
                recorder.record(track: t, pitch: pitchPct, pitchKind: pitchKind.rawValue, confidence: confidence, newSong: justSwitched)
            }
            justSwitched = false
            status = source == .mic ? "listening · matched" : "test file · matched"
        case .noMatch:
            lastNoMatch = now
            noMatchCount += 1
            if noMatchCount % 5 == 1 { note(String(format: "no match (%d so far), input %.0f dB", noMatchCount, inputLevel)) }
            if let latencyMs { lastLatencyMs = latencyMs }
            if currentId == nil { status = "listening…" }      // with a song on screen, keep it (2-minute rule in tick)
        case .error(let e, _):
            note("error: \(e.localizedDescription)")
            status = "listening… (\(e.localizedDescription))"
        @unknown default: break
        }
    }

    private func switchTo(_ id: String) {
        justSwitched = true
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

    private func updatePitch(_ ev: Event, flavour: String, pct: Int, vr: Double) {
        if abs(ev.freqRatio - 1) > 0.008 {
            // vinyl-style (master tempo off): key and tempo moved together; ShazamKit's frequency skew says how much
            let same = events.filter { $0.id == ev.id }.suffix(4).map(\.freqRatio)
            let fr = same.reduce(0, +) / Double(same.count)
            pitchPct = ((fr - 1) * 1000).rounded() / 10; pitchKind = .vinyl; rate = fr
            pitchFrom = flavour == "r" ? "vinyl variant \(pct > 0 ? "+" : "")\(pct)% + skew" : "frequency skew"
            return
        }
        // key unchanged (master tempo on, or no pitch): the tempo is how fast the matched position runs against the
        // audio clock. Track H measured two matches 8 s apart to a few hundredths; in the app the first 10 s read
        // rough, so the fit is shown from 12 s and three matches on, and refined on every match after that.
        let same = Array(events.filter { $0.id == ev.id }.suffix(12))
        if let f = same.first, let l = same.last, same.count >= 3, l.audioTime - f.audioTime >= 12 {
            // median of the pairwise slopes (Theil-Sen): one stray match cannot pull the reading, unlike least squares
            var slopes: [Double] = []
            for i in 0..<same.count { for j in (i + 1)..<same.count {
                let dt = same[j].audioTime - same[i].audioTime
                if dt >= 3 { slopes.append((same[j].offset - same[i].offset) / dt) }
            } }
            slopes.sort()
            let slope = slopes.isEmpty ? 1 : slopes[slopes.count / 2]
            if slope > 0.8 && slope < 1.2 {
                let p = ((slope - 1) * 1000).rounded() / 10
                if abs(p) >= 0.3 { pitchPct = p; pitchKind = .masterTempo; rate = slope; pitchFrom = "position drift over \(Int(l.audioTime - f.audioTime)) s" }
                else { pitchPct = 0; pitchKind = .none; rate = 1; pitchFrom = "position drift" }
                return
            }
        }
        if flavour == "t" {
            // a tempo-only variant matched: its percent stands in until the drift fit has 8 s of matches
            pitchPct = Double(pct); pitchKind = .masterTempo; rate = vr; pitchFrom = "tempo-only variant, measuring"
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

/// Microphone -> SHSession streaming matcher, plus an RMS level for the meter.
final class MicCapture {
    private let engine = AVAudioEngine()
    private(set) var formatText = ""
    private var lastLevel = Date.distantPast

    private(set) var format: AVAudioFormat?
    /// seconds of audio appended so far: the clock the drift fit runs on (sample time, not wall time)
    private(set) var audioSeconds: Double = 0

    /// One engine, one tap: every buffer goes to ShazamKit and to `sink` (the set recorder).
    func start(session: SHSession, sink: @escaping (AVAudioPCMBuffer) -> Void, level: @escaping (Float) -> Void) throws {
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
            session.matchStreamingBuffer(buf, at: when)
            sink(buf)
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
