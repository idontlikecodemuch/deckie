import Foundation
import DeckieDecode
import DeckieRecognition

// Plays a recording through the booth's recogniser as the booth would hear it, and prints what it would have shown
// second by second.
//
//   deckie-listen --index crate.dkx --audio set.wav [--chunk 0.1]
//   deckie-listen --prints DIR [--save-index crate.dkx] --audio set.wav
//       --index: an index file made earlier (opened in place). --prints: a folder of fingerprints (<id>.dkl, as a
//       crate file's prints/ folder holds), from which the index is built now and, with --save-index, kept.
//       --audio: any file the core decodes (WAV, AIFF, MP3, FLAC), or raw 16-bit little-endian mono with --raw RATE.
//       The sound is fed in pieces of --chunk seconds (0.1), as a microphone delivers it.
//   deckie-listen --index crate.dkx --list clips.tsv --out readings.tsv [--jobs N]
//       many recordings: clips.tsv has a name, a raw file (16-bit mono), its first sample, its sample count and its
//       rate on each line; every reading of every clip goes to readings.tsv with the clip's name in front.
//
// A reading: seconds heard, state (nothingYet, named, held), the song's id, the place in it (s), the deck's speed
// (percent), key lock (yes, no, ?), confidence, milliseconds taken. At the end: the time readings took and the
// most memory the process held.

func fail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(2) }

var values: [String: String] = [:]
var flags: Set<String> = []
do {
    let args = Array(CommandLine.arguments.dropFirst())
    var i = 0
    while i < args.count {
        guard args[i].hasPrefix("--") else { fail("unexpected argument \(args[i])") }
        if i + 1 < args.count, !args[i + 1].hasPrefix("--") { values[args[i]] = args[i + 1]; i += 2 } else { flags.insert(args[i]); i += 1 }
    }
}

/// The most memory this process has held, in bytes (Linux: the kernel's own figure; elsewhere unknown here).
func peakMemory() -> Int? {
    guard let status = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) else { return nil }
    for line in status.split(separator: "\n") where line.hasPrefix("VmHWM:") {
        return (Int(line.split(separator: " ", omittingEmptySubsequences: true).dropFirst().first ?? "") ?? 0) * 1024
    }
    return nil
}

func rawSamples(_ path: String, first: Int = 0, count: Int? = nil) -> [Float] {
    guard let handle = FileHandle(forReadingAtPath: path) else { fail("cannot read \(path)") }
    defer { try? handle.close() }
    try? handle.seek(toOffset: UInt64(first * 2))
    let data = (count.map { try? handle.read(upToCount: $0 * 2) } ?? (try? handle.readToEnd())) ?? Data()
    var out = [Float](repeating: 0, count: data.count / 2)
    data.withUnsafeBytes { raw in
        for k in 0..<out.count { out[k] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: 2 * k, as: Int16.self))) / 32768 }
    }
    return out
}

func line(_ r: ListenReading) -> String {
    String(format: "%.1f\t%@\t%@\t%@\t%@\t%@\t%.2f\t%.1f", r.time, r.state.rawValue, r.id ?? "-",
           r.positionSeconds.map { String(format: "%.2f", $0) } ?? "-", r.speedPercent.map { String(format: "%+.2f", $0) } ?? "-",
           r.keyLock.map { $0 ? "yes" : "no" } ?? "?", r.confidence, r.milliseconds)
}

// The index: opened in place, or built from fingerprints.
let index: RecognitionIndex
let t0 = DispatchTime.now().uptimeNanoseconds
if let path = values["--index"] {
    do { index = try RecognitionIndex(contentsOf: URL(fileURLWithPath: path), mapped: !flags.contains("--in-memory")) } catch { fail("\(error)") }
} else if let dir = values["--prints"] {
    var songs: [(id: String, landmarks: Landmarks)] = []
    for name in ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter({ $0.hasSuffix(".dkl") }).sorted() {
        guard let d = FileManager.default.contents(atPath: dir + "/" + name), let m = Landmarks(encoded: d) else { fail("bad fingerprint \(name)") }
        songs.append((String(name.dropLast(4)), m))
    }
    index = RecognitionIndex(songs: songs, pairing: PairingConfig.booth)
    if let save = values["--save-index"] { do { try index.write(to: URL(fileURLWithPath: save)) } catch { fail("\(error)") } }
} else { fail("give --index FILE or --prints DIR") }
FileHandle.standardError.write(Data(String(format: "index: %d songs, %.1f MB (%.1f KB a song), ready in %.0f ms\n", index.songCount,
                                            Double(index.fileBytes) / 1e6, Double(index.fileBytes) / 1e3 / Double(max(1, index.songCount)),
                                            Double(DispatchTime.now().uptimeNanoseconds - t0) / 1e6).utf8))
let chunkSeconds = Double(values["--chunk"] ?? "") ?? 0.1
let settings: ListenSettings = {
    var s = ListenSettings()
    if let v = values["--window"].flatMap(Double.init) { s.window = v }
    if let v = values["--sure"].flatMap(Double.init) { s.sure = v }
    if let v = values["--fair"].flatMap(Double.init) { s.fair = v }
    if let v = values["--hold-score"].flatMap(Double.init) { s.holdScore = v }
    if let v = values["--check-songs"].flatMap(Int.init) { s.checkSongs = v }
    if let v = values["--search-every"].flatMap(Int.init) { s.searchEvery = v }
    if let v = values["--lost-after"].flatMap(Int.init) { s.lostAfter = v }
    return s
}()

func play(_ samples: [Float], rate: Int, into listener: SongListener, _ each: (ListenReading) -> Void) {
    let chunk = max(1, Int(chunkSeconds * Double(rate)))
    var at = 0
    while at < samples.count {
        let end = min(samples.count, at + chunk)
        for r in listener.hear(Array(samples[at..<end]), sampleRate: rate) { each(r) }
        at = end
    }
}

if let list = values["--list"] {
    guard let text = try? String(contentsOfFile: list, encoding: .utf8), let out = values["--out"] else { fail("cannot read the list, or no --out") }
    let clips = text.split(separator: "\n").map { $0.split(separator: "\t").map(String.init) }
    let jobs = Int(values["--jobs"] ?? "") ?? ProcessInfo.processInfo.activeProcessorCount
    let lock = NSLock()
    nonisolated(unsafe) var next = 0
    nonisolated(unsafe) var rows = [String](repeating: "", count: clips.count)
    let group = DispatchGroup()
    for _ in 0..<max(1, jobs) {
        group.enter()
        let thread = Thread {
            let listener = SongListener(index: index, settings: settings)
            while true {
                lock.lock(); let i = next; next += 1; lock.unlock()
                if i >= clips.count { break }
                let c = clips[i]
                guard c.count >= 5, let first = Int(c[2]), let count = Int(c[3]), let rate = Int(c[4]) else { continue }
                listener.reset()
                var mine = ""
                play(rawSamples(c[1], first: first, count: count), rate: rate, into: listener) { mine += c[0] + "\t" + line($0) + "\n" }
                lock.lock(); rows[i] = mine; lock.unlock()
            }
            group.leave()
        }
        thread.stackSize = 16 << 20
        thread.start()
    }
    group.wait()
    guard (try? rows.joined().write(toFile: out, atomically: true, encoding: .utf8)) != nil else { fail("cannot write \(out)") }
} else if let audio = values["--audio"] {
    var samples: [Float]
    var rate: Int
    if let raw = values["--raw"].flatMap(Int.init) { samples = rawSamples(audio); rate = raw } else {
        guard let buffer = try? AudioDecoder.decode(URL(fileURLWithPath: audio)) else { fail("cannot decode \(audio)") }
        samples = buffer.mono(); rate = buffer.sampleRate
    }
    let listener = SongListener(index: index, settings: settings)
    var times: [Double] = []
    print("seconds\tstate\tsong\tplace\tspeed\tkey lock\tconfidence\tms")
    play(samples, rate: rate, into: listener) { print(line($0)); times.append($0.milliseconds) }
    times.sort()
    let summary = String(format: "%d readings over %.0f s of sound; a reading took %.0f ms at the median, %.0f at the 95th percentile, %.0f at most; the listener's own memory %.1f MB",
                         times.count, Double(samples.count) / Double(rate), times.isEmpty ? 0 : times[times.count / 2],
                         times.isEmpty ? 0 : times[min(times.count - 1, times.count * 95 / 100)], times.last ?? 0, Double(listener.workingBytes) / 1e6)
    FileHandle.standardError.write(Data((summary + (peakMemory().map { String(format: "; the process's peak memory %.0f MB (mapped index pages included)", Double($0) / 1e6) } ?? "") + "\n").utf8))
} else { fail("give --audio FILE or --list clips.tsv") }
