import AVFoundation
import Foundation

/// Records the set while the app listens: the same audio buffers that feed recognition (one engine, one tap)
/// are encoded to AAC (128 kbps) in Documents/Sets/"Deckie set <start>.aac" ("Deck set" before Nov 21, 2026; nothing reads the name back), plus a running log of what was
/// recognised: "<name> log.json" (rewritten atomically after every change, always valid) and
/// "<name> tracklist.txt" (one line appended per song). ADTS .aac is used instead of .m4a because an .m4a is
/// unreadable until it is closed properly; an ADTS stream keeps everything up to the last buffer if the app quits.
///
/// The file keeps the channels Deckie keeps of the input when the recording begins (mono or stereo, `ChannelMap`) and
/// its sample rate. If the input changes during the set (an interface plugged in or out), the sound is mixed and
/// converted to fit, and the recording carries on in the same file. A stretch with no sound (a call, Siri, an input
/// that will not start) is a gap: the file simply has nothing for it, and the log says where it was and how long.
/// Every buffer is counted (`RecordingTally`); a problem writing is said while it lasts, and a recording that ends
/// with nothing in it says so.
final class SetRecorder: @unchecked Sendable {
    struct Entry: Codable {
        var time: String          // wall clock, ISO 8601
        var at: Double            // seconds into the recording
        var id: String
        var title: String
        var artist: String
        var location: String      // "CD1 Singalongs / 6 - 125-129 / 08", or "in House" for a song with no source
        var pitch: Double         // detected deck pitch %
        var pitchKind: String     // "", "vinyl", "master tempo"
        var confidence: Double
        // new (D35), left out when not known; a reader that does not know them ignores them
        var keyLock: Bool? = nil      // whether the deck seemed to hold the key (Deckie's reading)
        var heardBy: String? = nil    // "deckie" or "apple": the recogniser whose reading this is
    }
    struct Log: Codable {
        var started: String; var audioFile: String; var entries: [Entry]
        // new (D35): the recogniser in use ("deckie", "apple", "both"), and in "both" the two compared song by song
        var hearing: String? = nil
        var compare: Comparison.Log? = nil
        // new: the recording's own notes (gaps, problems, inputs left out) and, once it ends, how it went
        var notes: [Note]? = nil
        var summary: Summary? = nil
    }
    /// A line in the set's log about the recording itself.
    struct Note: Codable { var time: String; var at: Double; var text: String }
    /// How the recording went, written into the log when it ends.
    struct Summary: Codable {
        var seconds: Double; var buffersWritten: Int; var buffersSkipped: Int; var buffersFailed: Int; var buffersPaused: Int
        var gaps: Int; var gapSeconds: Double; var nothingRecorded: Bool
    }

    private let q = DispatchQueue(label: "deck.recorder")
    private var file: AVAudioFile?
    private var tally = RecordingTally(sampleRate: 44100)
    private var _paused = false
    private var log: Log?
    private var notes: [Note] = []
    private var converter: AVAudioConverter?
    private(set) var baseName: String?
    /// A line for the app's log (a problem writing starts or ends, the recording ends), called on the recorder's queue.
    var report: (@Sendable (String) -> Void)?

    static var folder: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Sets", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    var isActive: Bool { q.sync { file != nil } }
    var paused: Bool {
        get { q.sync { _paused } }
        set { q.sync { _paused = newValue } }
    }
    /// recorded seconds (pauses and gaps excluded)
    var elapsed: Double { q.sync { tally.seconds } }
    /// The recording's counts so far.
    var counts: RecordingTally { q.sync { tally } }
    /// What is wrong with the recording now (it cannot write), nil while it writes or when nothing is recording.
    var trouble: String? { q.sync { file == nil ? nil : tally.trouble } }
    /// Waits until every buffer handed over so far is written (tests).
    func settle() { q.sync {} }

    /// Starts a set's recording. `format` is the sound as it comes in; the file keeps the channels Deckie keeps of it
    /// (`ChannelMap.kept`: mono or stereo) and its sample rate for the whole set, whatever the input does later.
    func begin(format: AVAudioFormat, hearing: String? = nil) throws {
        finish()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let name = "Deckie set \(f.string(from: Date()))"
        let url = SetRecorder.folder.appendingPathComponent(name + ".aac")
        let ch = ChannelMap.kept(Int(format.channelCount))
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
                                       AVNumberOfChannelsKey: ch, AVEncoderBitRateKey: 128_000]
        let af = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let iso = ISO8601DateFormatter()
        q.sync {
            file = af; tally = RecordingTally(sampleRate: af.processingFormat.sampleRate); _paused = false; baseName = name
            notes = []; converter = nil
            log = Log(started: iso.string(from: Date()), audioFile: name + ".aac", entries: [], hearing: hearing)
        }
        writeLog()
        let header = "Deckie set recorded \(iso.string(from: Date()))\naudio: \(name).aac\n\n"
        try? header.write(to: SetRecorder.folder.appendingPathComponent(name + " tracklist.txt"), atomically: true, encoding: .utf8)
    }

    /// Called from the audio thread with a buffer of its own (the sink's mixed copy, `CaptureSink`, or a test file's
    /// fresh buffer), which nothing changes after. It is made to fit the file (its channels, and its sample rate if
    /// the input changed since the recording began) and written; every buffer is counted as written, skipped (could
    /// not be made to fit) or failed (the file would not take it), and a problem is said once when it starts and once
    /// when it ends.
    func append(_ buf: AVAudioPCMBuffer) {
        q.async { [self] in
            guard let file else { return }
            if _paused { tally.paused += 1; return }
            guard let fitted = fit(buf, to: file.processingFormat) else {
                problem(tally.skip("the sound could not be made to fit the recording")); return
            }
            guard fitted.frameLength > 0 else { return }      // the converter holds these samples for the next buffer
            do {
                try file.write(from: fitted)
                if tally.wrote(Int(fitted.frameLength)) { say("recording writes again") }
            } catch {
                problem(tally.fail(error.localizedDescription))
            }
        }
    }

    /// A buffer that never reached the recording (the sink could not read it).
    func skip(_ why: String) { q.async { [self] in guard file != nil else { return }; problem(tally.skip(why)) } }

    /// A line about the recording itself in the set's log ("gap of 12 s with no sound: ...").
    func note(_ text: String) {
        q.async { [self] in
            guard log != nil else { return }
            addNote(text)
            writeLogLocked()
        }
    }

    /// The end of a gap in the sound: counted, and noted in the log. The recording waited, and carries on in the same
    /// file.
    func gap(seconds: Double, why: String) {
        q.async { [self] in
            guard file != nil else { return }
            tally.gaps += 1; tally.gapSeconds += seconds
            addNote(String(format: "gap of %.0f s with no sound: %@; the recording carries on", seconds, why))
            writeLogLocked()
        }
    }

    private func addNote(_ text: String) {
        notes.append(Note(time: ISO8601DateFormatter().string(from: Date()), at: (tally.seconds * 10).rounded() / 10, text: text))
        log?.notes = notes
    }
    private func problem(_ began: String?) {
        guard let began else { return }
        let line = "recording problem: " + began
        say(line)
        addNote(line)
        writeLogLocked()
    }
    private func say(_ s: String) { report?(s) }

    /// The buffer in the file's format: its channels mixed to the file's (`ChannelMap`), then, if the sample rate is
    /// another, converted (one AVAudioConverter kept from buffer to buffer, so the joins are seamless).
    private func fit(_ b: AVAudioPCMBuffer, to f: AVAudioFormat) -> AVAudioPCMBuffer? {
        let fc = Int(f.channelCount)
        let mixed: AVAudioPCMBuffer
        if Int(b.format.channelCount) == fc && !b.format.isInterleaved && b.format.commonFormat == .pcmFormatFloat32 { mixed = b }
        else { guard let m = ChannelMap.apply(b, channels: fc) else { return nil }; mixed = m }
        if mixed.format.sampleRate == f.sampleRate { return mixed }
        if converter == nil || converter!.inputFormat != mixed.format { converter = AVAudioConverter(from: mixed.format, to: f) }
        guard let conv = converter else { return nil }
        let cap = AVAudioFrameCount((Double(mixed.frameLength) * f.sampleRate / mixed.format.sampleRate).rounded(.up)) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: cap) else { return nil }
        var given = false
        var err: NSError?
        let st = conv.convert(to: out, error: &err) { _, status in
            if given { status.pointee = .noDataNow; return nil }
            given = true; status.pointee = .haveData; return mixed
        }
        return st == .error ? nil : out
    }

    /// A new song: add an entry and a tracklist line. Same song again: refresh its pitch and confidence.
    func record(track: Track, pitch: Double, pitchKind: String, confidence: Double, newSong: Bool, keyLock: Bool? = nil, heardBy: String? = nil) {
        let loc = track.disc == nil ? "in " + (track.folder.isEmpty ? "the crate" : track.folder) : track.placeText
        q.async { [self] in
            guard var lg = log, let base = baseName else { return }
            let at = tally.seconds
            let e = Entry(time: ISO8601DateFormatter().string(from: Date()), at: (at * 10).rounded() / 10, id: track.id, title: track.song,
                          artist: track.artist, location: loc, pitch: (pitch * 10).rounded() / 10, pitchKind: pitchKind,
                          confidence: (confidence * 100).rounded() / 100, keyLock: keyLock, heardBy: heardBy)
            if !newSong, let last = lg.entries.last, last.id == track.id {
                var u = last; u.pitch = e.pitch; u.pitchKind = e.pitchKind; u.confidence = max(last.confidence, e.confidence)
                if keyLock != nil { u.keyLock = keyLock }
                lg.entries[lg.entries.count - 1] = u
            } else {
                lg.entries.append(e)
                let t = Int(at), clock = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
                let p = abs(pitch) < 0.25 ? "pitch ±0" : String(format: "pitch %+.1f%%", pitch) + (pitchKind.isEmpty ? "" : " " + pitchKind)
                let line = String(format: "%02d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) + "  \(clock)  \(loc) · \(track.hasName ? track.song + (track.artist.isEmpty ? "" : " – " + track.artist) : Words.noNameYetInRow + (track.deck.isEmpty ? "" : " (" + Words.fileLine(track.deck) + ")"))  (\(p))\n"
                if let h = try? FileHandle(forWritingTo: SetRecorder.folder.appendingPathComponent(base + " tracklist.txt")) {
                    h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
                }
            }
            log = lg
            writeLogLocked()
        }
    }

    /// Compare mode: the two recognisers' record of the set so far, written into the log.
    func compare(_ c: Comparison.Log) {
        q.async { [self] in
            guard log != nil else { return }
            log?.compare = c
            writeLogLocked()
        }
    }

    /// Ends the recording: its summary goes into the log and a last line into the tracklist, and the file is closed
    /// (every buffer handed over before is written first: they are ahead of this on the recorder's queue). Returns how
    /// it went, nil when nothing was recording. A recording with no sound in it says so: in the log
    /// (`summary.nothingRecorded`), the tracklist's last line, and to the caller (`RecordingTally.nothingRecorded`).
    @discardableResult
    func finish() -> RecordingTally? {
        q.sync {
            guard let f = file else { log = nil; baseName = nil; return nil }
            let t = tally
            if let base = baseName, log != nil {
                log?.notes = notes
                log?.summary = Summary(seconds: (t.seconds * 10).rounded() / 10, buffersWritten: t.written, buffersSkipped: t.skipped,
                                       buffersFailed: t.failed, buffersPaused: t.paused, gaps: t.gaps,
                                       gapSeconds: t.gapSeconds.rounded(), nothingRecorded: t.nothingRecorded)
                writeLogLocked()
                let line = "\n" + (t.nothingRecorded ? "ended: nothing was recorded (the audio file is empty)"
                                                     : "ended: \(SetRecorder.clock(t.seconds)) recorded") + "\n"
                if let h = try? FileHandle(forWritingTo: SetRecorder.folder.appendingPathComponent(base + " tracklist.txt")) {
                    h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
                }
            }
            if #available(iOS 18.0, *) { f.close() }      // before iPadOS 18 the file closes when it is let go, just below
            say(t.nothingRecorded ? "recording ended: nothing was recorded"
                : "recording ended: \(SetRecorder.clock(t.seconds)) recorded; buffers \(t.written) written, \(t.skipped) skipped, \(t.failed) failed")
            file = nil; log = nil; baseName = nil; converter = nil
            return t
        }
    }

    static func clock(_ s: Double) -> String { let t = Int(s); return String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) }

    private func writeLog() { q.async { [self] in writeLogLocked() } }
    private func writeLogLocked() {
        guard let log, let base = baseName else { return }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(log) { try? d.write(to: SetRecorder.folder.appendingPathComponent(base + " log.json"), options: .atomic) }
    }
}

/// A set recording's counts, and what they say: how long was recorded, whether anything was, and the problem now if
/// there is one. Plain numbers, so it is tested without a file (DeckTests/AudioInputTests).
struct RecordingTally: Equatable, Sendable {
    var sampleRate: Double
    /// Samples written to the file (one channel's count).
    private(set) var frames: Int64 = 0
    private(set) var written = 0, skipped = 0, failed = 0
    /// Buffers left out while the DJ paused the recording (not a problem).
    var paused = 0
    /// Stretches with no sound (a call, an input changing), and their length.
    var gaps = 0, gapSeconds = 0.0
    /// The problem now: set by a buffer skipped or failed, cleared by the next one written.
    private(set) var trouble: String?

    init(sampleRate: Double) { self.sampleRate = sampleRate }

    /// Seconds recorded (pauses and gaps excluded).
    var seconds: Double { sampleRate > 0 ? Double(frames) / sampleRate : 0 }
    /// Nothing at all reached the file.
    var nothingRecorded: Bool { frames == 0 }

    /// A buffer written; true when this ends a problem.
    mutating func wrote(_ n: Int) -> Bool {
        written += 1; frames += Int64(n)
        defer { trouble = nil }
        return trouble != nil
    }
    /// A buffer that could not be made to fit; the problem's words when this starts one (nil if one is going on).
    mutating func skip(_ why: String) -> String? { skipped += 1; return begin(why) }
    /// A buffer the file would not take; the same.
    mutating func fail(_ why: String) -> String? { failed += 1; return begin(why) }
    private mutating func begin(_ why: String) -> String? {
        guard trouble == nil else { return nil }
        trouble = why
        return why
    }
}

/// Test source that behaves like the microphone: plays a file (optionally pitched) in real time through an
/// offline engine and hands each 0.1 s buffer to the same sink as the mic tap (recognition + recorder).
final class StreamFeeder: @unchecked Sendable {
    private var cancelled = false
    /// seconds of audio fed so far (sample time), the clock the recogniser's drift fit uses
    private(set) var audioSeconds: Double = 0
    let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!

    func cancel() { cancelled = true }

    func run(_ url: URL, start: Double, variant: TestVariant, sink: @escaping (AVAudioPCMBuffer) -> Void) async throws {
        let file = try AVAudioFile(forReading: url)
        let sr = file.processingFormat.sampleRate
        let startF = AVAudioFramePosition(max(0, start) * sr)
        guard startF < file.length else { return }
        let engine = AVAudioEngine(), player = AVAudioPlayerNode()
        engine.attach(player)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4410)
        var unit: AVAudioNode?
        if variant.flavour == "r" { let v = AVAudioUnitVarispeed(); v.rate = Float(variant.tempo); unit = v }
        if variant.flavour == "t" { let t = AVAudioUnitTimePitch(); t.rate = Float(variant.tempo); unit = t }
        if let u = unit {
            engine.attach(u)
            engine.connect(player, to: u, format: file.processingFormat)
            engine.connect(u, to: engine.mainMixerNode, format: file.processingFormat)
        } else { engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat) }
        player.scheduleSegment(file, startingFrame: startF, frameCount: AVAudioFrameCount(file.length - startF), at: nil, completionHandler: nil)
        try engine.start(); player.play()
        let total = AVAudioFramePosition(Double(file.length - startF) / sr / variant.tempo * 44100)
        var done: AVAudioFramePosition = 0
        let t0 = Date()
        while done < total && !cancelled {
            let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4410)!
            guard try engine.renderOffline(4410, to: buf) == .success else { break }
            sink(buf)
            done += AVAudioFramePosition(buf.frameLength)
            audioSeconds = Double(done) / 44100
            let ahead = Double(done) / 44100 - Date().timeIntervalSince(t0)    // keep real time
            if ahead > 0 { try? await Task.sleep(for: .seconds(ahead)) }
        }
        player.stop(); engine.stop()
    }
}
