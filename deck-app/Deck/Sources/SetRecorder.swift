import AVFoundation
import Foundation

/// Records the set while the app listens: the same audio buffers that feed recognition (one engine, one tap)
/// are encoded to AAC (128 kbps) in Documents/Sets/"Deck set <start>.aac", plus a running log of what was
/// recognised: "<name> log.json" (rewritten atomically after every change, always valid) and
/// "<name> tracklist.txt" (one line appended per song). ADTS .aac is used instead of .m4a because an .m4a is
/// unreadable until it is closed properly; an ADTS stream keeps everything up to the last buffer if the app quits.
final class SetRecorder: @unchecked Sendable {
    struct Entry: Codable {
        var time: String          // wall clock, ISO 8601
        var at: Double            // seconds into the recording
        var id: String
        var title: String
        var artist: String
        var location: String      // "CD1 / 6 - 125-129 / 08"
        var pitch: Double         // detected deck pitch %
        var pitchKind: String     // "", "vinyl", "master tempo"
        var confidence: Double
    }
    struct Log: Codable { var started: String; var audioFile: String; var entries: [Entry] }

    private let q = DispatchQueue(label: "deck.recorder")
    private var file: AVAudioFile?
    private var frames: AVAudioFramePosition = 0
    private var sampleRate = 44100.0
    private var _paused = false
    private var log: Log?
    private(set) var baseName: String?

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
    /// recorded seconds (pauses excluded)
    var elapsed: Double { q.sync { Double(frames) / sampleRate } }

    func begin(format: AVAudioFormat) throws {
        finish()
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let name = "Deck set \(f.string(from: Date()))"
        let url = SetRecorder.folder.appendingPathComponent(name + ".aac")
        let ch = min(2, Int(format.channelCount))
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: format.sampleRate,
                                       AVNumberOfChannelsKey: ch, AVEncoderBitRateKey: 128_000]
        let af = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let iso = ISO8601DateFormatter()
        q.sync {
            file = af; frames = 0; sampleRate = format.sampleRate; _paused = false; baseName = name
            log = Log(started: iso.string(from: Date()), audioFile: name + ".aac", entries: [])
        }
        writeLog()
        let header = "Deck set recorded \(iso.string(from: Date()))\naudio: \(name).aac\n\n"
        try? header.write(to: SetRecorder.folder.appendingPathComponent(name + " tracklist.txt"), atomically: true, encoding: .utf8)
    }

    /// Called from the audio tap thread with the same buffer that goes to ShazamKit.
    func append(_ buf: AVAudioPCMBuffer) {
        guard let copy = SetRecorder.copy(buf) else { return }
        q.async { [self] in
            guard let file, !_paused else { return }
            do {
                if copy.format.channelCount == file.processingFormat.channelCount && copy.format.sampleRate == file.processingFormat.sampleRate {
                    try file.write(from: copy)
                    frames += AVAudioFramePosition(copy.frameLength)
                }
            } catch { }
        }
    }

    /// A new song: add an entry and a tracklist line. Same song again: refresh its pitch and confidence.
    func record(track: Track, pitch: Double, pitchKind: String, confidence: Double, newSong: Bool) {
        let loc = track.cd.map { "CD\($0) / \(track.folder) / " + String(format: "%02d", track.num ?? 0) } ?? "not on the CDs"
        q.async { [self] in
            guard var lg = log, let base = baseName else { return }
            let at = Double(frames) / sampleRate
            let e = Entry(time: ISO8601DateFormatter().string(from: Date()), at: (at * 10).rounded() / 10, id: track.id, title: track.song,
                          artist: track.artist, location: loc, pitch: (pitch * 10).rounded() / 10, pitchKind: pitchKind,
                          confidence: (confidence * 100).rounded() / 100)
            if !newSong, let last = lg.entries.last, last.id == track.id {
                var u = last; u.pitch = e.pitch; u.pitchKind = e.pitchKind; u.confidence = max(last.confidence, e.confidence)
                lg.entries[lg.entries.count - 1] = u
            } else {
                lg.entries.append(e)
                let t = Int(at), clock = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
                let p = abs(pitch) < 0.25 ? "pitch ±0" : String(format: "pitch %+.1f%%", pitch) + (pitchKind.isEmpty ? "" : " " + pitchKind)
                let line = String(format: "%02d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) + "  \(clock)  \(loc) · \(track.song) – \(track.artist)  (\(p))\n"
                if let h = try? FileHandle(forWritingTo: SetRecorder.folder.appendingPathComponent(base + " tracklist.txt")) {
                    h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close()
                }
            }
            log = lg
            writeLogLocked()
        }
    }

    func finish() {
        q.sync { file = nil; log = nil; baseName = nil }      // AVAudioFile closes on release
    }

    private func writeLog() { q.async { [self] in writeLogLocked() } }
    private func writeLogLocked() {
        guard let log, let base = baseName else { return }
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let d = try? enc.encode(log) { try? d.write(to: SetRecorder.folder.appendingPathComponent(base + " log.json"), options: .atomic) }
    }

    static func copy(_ b: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let c = AVAudioPCMBuffer(pcmFormat: b.format, frameCapacity: b.frameLength), let src = b.floatChannelData, let dst = c.floatChannelData else { return nil }
        c.frameLength = b.frameLength
        for ch in 0..<Int(b.format.channelCount) { memcpy(dst[ch], src[ch], Int(b.frameLength) * MemoryLayout<Float>.size) }
        return c
    }
}

/// Test source that behaves like the microphone: plays a file (optionally pitched) in real time through an
/// offline engine and hands each 0.1 s buffer to the same sink as the mic tap (recognition + recorder).
final class StreamFeeder: @unchecked Sendable {
    private var cancelled = false
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
            let ahead = Double(done) / 44100 - Date().timeIntervalSince(t0)    // keep real time
            if ahead > 0 { try? await Task.sleep(for: .seconds(ahead)) }
        }
        player.stop(); engine.stop()
    }
}
