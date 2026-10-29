// deckie-memprobe: measures the analyser's memory. It runs `Analyser.analyse` on audio files, as deckie-build does
// (one analyser shared by the jobs, each job taking the next file), while a thread samples the process's resident
// memory, and reports the peak: the kernel's own high-water mark (VmHWM on Linux, ru_maxrss on macOS), what the
// models took when they loaded, and, with one job, the stage each peak fell in. It writes each record as the lab's
// feature JSON with the timings taken out, so two builds or two settings can be compared byte for byte.
//
//   deckie-memprobe synth <out.wav> [--seconds 240] [--bpm 124] [--seed 1]
//   deckie-memprobe <file>... [--jobs N] [--repeat R] [--arena on|off] [--pattern on|off] [--shrink on|off]
//                   [--threads T] [--no-vocal] [--records DIR] [--sample-ms MS] [--logits]
//                   [--model-runs M]
//
// --model-runs M lets at most M runs of each model happen at once (OnnxRuntime.SessionOptions.concurrentRuns); the
// intra-op threads then default to the processor count over M instead of over the jobs.
//
// --logits also runs the beat model alone on each file's 22,050 Hz mono mix and prints a hash of its raw outputs
// (every bit of every beat and downbeat logit), so settings that should change nothing can be shown to.
//
// The engine needs ONNX Runtime and the Beat This! model, as deckie-build does (core/README.md).

import Foundation
import DeckieAudio
import DeckieCore
import DeckieDecode
import DeckieEngine
import DeckieInference
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("deckie-memprobe: \(message)\n".utf8))
    exit(code)
}

func say(_ line: String) { FileHandle.standardOutput.write(Data((line + "\n").utf8)) }

// MARK: - Memory

enum Memory {
    /// Resident memory now, in bytes.
    static func resident() -> Int {
        #if os(Linux)
        return status("VmRSS")
        #else
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kr == KERN_SUCCESS ? Int(info.resident_size) : 0
        #endif
    }

    /// The kernel's high-water mark of resident memory for this process, in bytes.
    static func peak() -> Int {
        #if os(Linux)
        return status("VmHWM")
        #else
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Int(usage.ru_maxrss)  // bytes on macOS
        #endif
    }

    /// Resets the high-water mark to the resident memory now where the kernel allows it (Linux); returns whether it did.
    static func resetPeak() -> Bool {
        #if os(Linux)
        guard let h = FileHandle(forWritingAtPath: "/proc/self/clear_refs") else { return false }
        defer { try? h.close() }
        h.write(Data("5".utf8))
        return true
        #else
        return false
        #endif
    }

    #if os(Linux)
    static func status(_ key: String) -> Int {
        guard let text = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) else { return 0 }
        for line in text.split(separator: "\n") where line.hasPrefix(key + ":") {
            let kb = line.split(separator: " ", omittingEmptySubsequences: true).dropFirst().first.flatMap { Int($0) }
            return (kb ?? 0) * 1024
        }
        return 0
    }
    #endif

    static func mb(_ bytes: Int) -> String { String(format: "%.0f MB", Double(bytes) / 1_000_000) }
}

/// Samples resident memory every few milliseconds on a thread of its own.
final class Sampler: @unchecked Sendable {
    let lock = NSLock()
    var samples: [(t: Date, rss: Int)] = []
    var running = true
    let interval: Double

    init(intervalMS: Double) { interval = intervalMS / 1000 }

    func start() {
        let t = Thread { [self] in
            while true {
                let rss = Memory.resident()
                lock.lock()
                samples.append((Date(), rss))
                let go = running
                lock.unlock()
                if !go { break }
                Thread.sleep(forTimeInterval: interval)
            }
        }
        t.start()
    }

    func stop() {
        lock.lock(); running = false; lock.unlock()
        Thread.sleep(forTimeInterval: interval * 3)
    }

    func maximum(from a: Date, to b: Date) -> Int {
        lock.lock(); defer { lock.unlock() }
        return samples.filter { $0.t >= a && $0.t <= b }.map(\.rss).max() ?? 0
    }
}

// MARK: - Records

/// The lab JSON without its timings (`timing_s`, at any depth), canonical bytes.
func comparable(_ analysis: Analysis) -> Data {
    func strip(_ v: JSONValue) -> JSONValue {
        switch v {
        case .object(let members):
            return .object(members.filter { $0.key != "timing_s" }.map { JSONValue.Member($0.key, strip($0.value)) })
        case .array(let items): return .array(items.map(strip))
        default: return v
        }
    }
    return strip(analysis.labJSON()).data
}

// MARK: - A synthesised track

/// A four-minute stereo track at 44.1 kHz for the measurement: drums (kick on every beat, snare on 2 and 4, hats on
/// the off-beats), a bass line and chords that change every bar, a breakdown without drums and a sung-like voice in
/// some stretches, written as 16-bit WAV. Not music, but it exercises every stage as a real track does.
func synthesise(to path: String, seconds: Double, bpm: Double, seed: UInt64) throws {
    let sr = 44100, n = Int(seconds * Double(sr))
    var rng = seed &* 6364136223846793005 &+ 1442695040888963407
    func noise() -> Double {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return Double(Int64(bitPattern: rng >> 11) % 1_000_000) / 1_000_000
    }
    let beat = 60.0 / bpm, bar = 4 * beat
    let roots = [57.0, 53.0, 48.0, 55.0, 57.0, 52.0, 53.0, 55.0]  // A F C G A E F G (MIDI)
    func hz(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }
    var left = [Float](repeating: 0, count: n), right = [Float](repeating: 0, count: n)
    let fadeStart = seconds - 12
    for i in 0..<n {
        let t = Double(i) / Double(sr)
        let barIndex = Int(t / bar), inBar = t - Double(barIndex) * bar
        let beatIndex = Int(inBar / beat), inBeat = inBar - Double(beatIndex) * beat
        let section = (barIndex / 16) % 4  // 0 intro-like, 1 full, 2 breakdown, 3 full with voice
        let drums = section != 2 && t > 8
        var x = 0.0, side = 0.0
        if drums {
            let kick = sin(2 * .pi * (50 + 90 * exp(-inBeat * 30)) * inBeat) * exp(-inBeat * 9)
            x += 0.55 * kick
            if beatIndex % 2 == 1 { x += 0.22 * (noise() * 2 - 1) * exp(-inBeat * 18) }
            let off = inBeat - beat / 2
            if off >= 0 { side += 0.06 * (noise() * 2 - 1) * exp(-off * 60) }
        }
        let root = roots[barIndex % roots.count]
        let minor = barIndex % 2 == 0
        let chord = [root, root + (minor ? 3 : 4), root + 7]
        var pad = 0.0
        for (k, m) in chord.enumerated() { pad += sin(2 * .pi * hz(m) * t + Double(k)) }
        x += 0.07 * pad
        x += 0.18 * sin(2 * .pi * hz(root - 24) * t) * (beatIndex % 2 == 0 ? 1 : 0.6)
        if section == 3 || (section == 1 && barIndex % 16 >= 8) {
            let vibrato = 5 * sin(2 * .pi * 5.5 * t)
            let note = root + 12 + Double([0, 3, 7, 5][beatIndex])
            var voice = 0.0
            for h in 1...6 { voice += sin(2 * .pi * Double(h) * (hz(note) + vibrato) * t) / Double(h * h) }
            x += 0.12 * voice * (0.6 + 0.4 * sin(2 * .pi * 1.5 * t))
        }
        var gain = 1.0
        if t > fadeStart { gain = max(0, (seconds - t) / 12) }
        if t < 4 { gain *= t / 4 }
        left[i] = Float(gain * (x + side))
        right[i] = Float(gain * (x - side))
    }
    // 16-bit PCM WAV.
    var d = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    d.append(contentsOf: Array("RIFF".utf8)); u32(UInt32(36 + n * 4)); d.append(contentsOf: Array("WAVE".utf8))
    d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(2); u32(UInt32(sr)); u32(UInt32(sr * 4)); u16(4); u16(16)
    d.append(contentsOf: Array("data".utf8)); u32(UInt32(n * 4))
    var pcm = [Int16](repeating: 0, count: 2 * n)
    for i in 0..<n {
        pcm[2 * i] = Int16(max(-32767, min(32767, (Double(left[i]) * 32767).rounded())))
        pcm[2 * i + 1] = Int16(max(-32767, min(32767, (Double(right[i]) * 32767).rounded())))
    }
    pcm.withUnsafeBytes { d.append(contentsOf: $0) }
    try d.write(to: URL(fileURLWithPath: path))
}

// MARK: - Arguments

var args = Array(CommandLine.arguments.dropFirst())
if args.first == "-h" || args.first == "--help" || args.isEmpty {
    say("""
        usage:
          deckie-memprobe synth <out.wav> [--seconds 240] [--bpm 124] [--seed 1]
          deckie-memprobe <file>... [--jobs N] [--repeat R] [--arena on|off] [--pattern on|off] [--shrink on|off]
                          [--threads T] [--no-vocal] [--records DIR] [--sample-ms MS] [--logits]
                          [--model-runs M]
        """)
    exit(0)
}

func options(_ args: [String], flags: Set<String>, values: Set<String>) -> (positional: [String], opts: [String: String]) {
    var pos: [String] = [], opts: [String: String] = [:]
    var rest = args[...]
    while let a = rest.popFirst() {
        if a.hasPrefix("--") {
            let name = String(a.dropFirst(2))
            if flags.contains(name) { opts[name] = "yes"; continue }
            guard values.contains(name) else { fail("unknown option \(a)", code: 2) }
            guard let v = rest.popFirst() else { fail("\(a) needs a value", code: 2) }
            opts[name] = v
        } else {
            pos.append(a)
        }
    }
    return (pos, opts)
}

func onOff(_ v: String?, _ name: String, default d: Bool) -> Bool {
    switch v {
    case nil: return d
    case "on": return true
    case "off": return false
    default: fail("--\(name) takes on or off", code: 2)
    }
}

if args.first == "synth" {
    let (pos, o) = options(Array(args.dropFirst()), flags: [], values: ["seconds", "bpm", "seed"])
    guard pos.count == 1 else { fail("synth needs one output path", code: 2) }
    let seconds = Double(o["seconds"] ?? "240") ?? 240, bpm = Double(o["bpm"] ?? "124") ?? 124
    let seed = UInt64(o["seed"] ?? "1") ?? 1
    do { try synthesise(to: pos[0], seconds: seconds, bpm: bpm, seed: seed) } catch { fail("\(error)") }
    say("wrote \(pos[0]): \(seconds) s, \(bpm) BPM, 44.1 kHz stereo 16-bit")
    exit(0)
}

let (files, o) = options(args, flags: ["no-vocal", "logits"],
                         values: ["jobs", "repeat", "arena", "pattern", "shrink", "threads", "records", "sample-ms",
                                  "model-runs"])
guard !files.isEmpty else { fail("no audio files given", code: 2) }
let jobs = max(1, Int(o["jobs"] ?? "1") ?? 1)
let repeatCount = max(1, Int(o["repeat"] ?? "1") ?? 1)
let defaults = OnnxRuntime.SessionOptions()
let cores = max(1, ProcessInfo.processInfo.activeProcessorCount)
let modelRuns = max(0, Int(o["model-runs"] ?? "0") ?? 0)
let sharing = modelRuns > 0 ? min(modelRuns, jobs) : jobs  // model runs that can happen at once
let threads = Int(o["threads"] ?? "") ?? (sharing <= 1 ? 0 : max(1, cores / sharing))
let sessionOptions = OnnxRuntime.SessionOptions(
    intraOpThreads: threads,
    cpuMemoryArena: onOff(o["arena"], "arena", default: defaults.cpuMemoryArena),
    memoryPattern: onOff(o["pattern"], "pattern", default: defaults.memoryPattern),
    arenaShrinkage: onOff(o["shrink"], "shrink", default: defaults.arenaShrinkage),
    concurrentRuns: modelRuns)
let recordsDir = o["records"]
if let recordsDir { try? FileManager.default.createDirectory(atPath: recordsDir, withIntermediateDirectories: true) }

// MARK: - Run

let start = Memory.resident()
let sampler = Sampler(intervalMS: Double(o["sample-ms"] ?? "5") ?? 5)
sampler.start()
let analyser: Analyser
do {
    let tracker = try BeatTracker(options: sessionOptions)
    var tagger: (any VocalTagger)? = nil
    if o["no-vocal"] == nil, let path = YAMNet.locateModel() {
        tagger = DeckieVocalTagger(yamnet: try YAMNet(modelPath: path, runtime: tracker.session.runtime,
                                                       options: sessionOptions))
    }
    analyser = try Analyser(beatTracker: tracker, vocalTagger: tagger)
} catch {
    fail("\(error)")
}
let loaded = Memory.resident()
let peakAtLoad = Memory.peak()
let reset = Memory.resetPeak()

say("settings: jobs \(jobs), intra-op threads \(threads == 0 ? "auto" : String(threads)), arena "
    + "\(sessionOptions.cpuMemoryArena ? "on" : "off"), memory pattern \(sessionOptions.memoryPattern ? "on" : "off"), "
    + "shrinkage \(sessionOptions.arenaShrinkage ? "on" : "off"), model runs at once "
    + "\(modelRuns == 0 ? "unlimited" : String(modelRuns)), vocal tagger \(analyser.vocalTagger == nil ? "none" : analyser.vocalTagger!.modelName)")
say("resident: \(Memory.mb(start)) at start, \(Memory.mb(loaded)) with the models loaded (peak \(Memory.mb(peakAtLoad)) while loading)")

final class Log: @unchecked Sendable {
    let lock = NSLock()
    var lines: [String] = []
    var failures = 0
    func add(_ s: String) { lock.lock(); lines.append(s); lock.unlock() }
}
let log = Log()
let work = (0..<repeatCount).flatMap { _ in files }
final class Next: @unchecked Sendable {
    let lock = NSLock()
    var i = 0
    func take(_ n: Int) -> Int? { lock.lock(); defer { lock.unlock() }; guard i < n else { return nil }; defer { i += 1 }; return i }
}
let next = Next()
let wallStart = Date()
let group = DispatchGroup()
for _ in 0..<min(jobs, work.count) {
    group.enter()
    let t = Thread {
        while let k = next.take(work.count) {
            let path = work[k]
            let t0 = Date()
            do {
                let a = try analyser.analyse(url: URL(fileURLWithPath: path))
                let t1 = Date()
                var line = String(format: "%@: %.1f s", (path as NSString).lastPathComponent, t1.timeIntervalSince(t0))
                if jobs == 1 {
                    // The stages' peaks from the samples: the analysis's own stage times laid end to end.
                    var from = t0
                    var parts: [String] = []
                    for s in a.timings {
                        let to = from.addingTimeInterval(s.seconds)
                        parts.append("\(s.stage) \(Memory.mb(sampler.maximum(from: from, to: to)))")
                        from = to
                    }
                    line += "\n  sampled resident peak by stage: " + parts.joined(separator: ", ")
                }
                if let recordsDir {
                    let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension + ".json"
                    try comparable(a).write(to: URL(fileURLWithPath: recordsDir).appendingPathComponent(name))
                }
                log.add(line)
            } catch {
                log.add("\(path): \(error)")
                log.lock.lock(); log.failures += 1; log.lock.unlock()
            }
        }
        group.leave()
    }
    t.stackSize = 16 << 20
    t.start()
}
group.wait()
let wall = Date().timeIntervalSince(wallStart)
sampler.stop()
for l in log.lines { say(l) }
if o["logits"] != nil {
    // FNV-1a over the logits' bit patterns, beat then downbeat.
    func fnv(_ values: [Float], _ h: inout UInt64) {
        for v in values {
            var b = v.bitPattern
            for _ in 0..<4 { h ^= UInt64(b & 0xff); h = h &* 0x100000001b3; b >>= 8 }
        }
    }
    for path in files {
        do {
            var buffer = try AudioDecoder.decode(URL(fileURLWithPath: path))
            if buffer.sampleRate != 44100 { buffer = Resampler(from: buffer.sampleRate, to: 44100).process(buffer) }
            let m22 = Decimator.halve(buffer.mono())
            let r = try analyser.beatTracker.track(AudioBuffer(sampleRate: 22050, channelCount: 1, samples: m22))
            var h: UInt64 = 0xcbf29ce484222325
            fnv(r.logits.beat, &h)
            fnv(r.logits.downbeat, &h)
            say("\((path as NSString).lastPathComponent): beat model logits \(r.logits.frames) frames, hash "
                + String(h, radix: 16))
        } catch {
            say("\(path): logits: \(error)")
        }
    }
}
let peak = Memory.peak()
say(String(format: "wall time %.1f s for %d analyses", wall, work.count))
say("peak resident (kernel high-water mark\(reset ? ", reset after loading" : ", since start")): \(Memory.mb(peak)); "
    + "sampled peak during the analyses \(Memory.mb(sampler.maximum(from: wallStart, to: Date()))); "
    + "resident at the end \(Memory.mb(Memory.resident()))")
exit(log.failures == 0 ? 0 : 1)
