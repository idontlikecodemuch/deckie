import Foundation
import DeckieCore
import DeckieDecode
import DeckieRecognition

// TRIAL (docs/research/w2-own-recognition-trial.md): the measuring tool for Deckie's own recognition. It is driven by
// core/Tools/recognition-bench/run.sh and is not part of any product.
//
//   deckie-recog-bench print --list songs.tsv --out DIR [--jobs N] [--time-reach 6] [--frequency-reach 0.12]
//       songs.tsv: id <tab> audio file. Writes DIR/<id>.dkl (the constellation) and prints, per song:
//       id, seconds of audio, points, bytes, milliseconds to decode, milliseconds to fingerprint.
//   deckie-recog-bench match --prints DIR --queries queries.tsv --out results.tsv [--jobs N] [--leave-out ids.txt]
//                            [--step 1] [--no-speed] [--fan-out 6] [--query-per-slice 2] [--time-reach 6] [--frequency-reach 0.12]
//       --audio-copies S: instead of moving the query's points, resample the query's audio at every S percent from
//       -17 to +17 and match each copy as it is (the comparison the research letter W asks for; vinyl-style only).
//       queries.tsv: query id <tab> raw file (16-bit little-endian mono) <tab> first sample <tab> samples <tab> rate.
//       Writes per query: id, points, milliseconds to fingerprint the query, milliseconds to match, then for the best
//       and the second-best song: id, score, matched points, offset in seconds, tempo ratio, pitch ratio.

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

struct Options {
    var values: [String: String] = [:]
    var flags: Set<String> = []
    init(_ args: [String]) {
        var i = 0
        while i < args.count {
            let a = args[i]
            guard a.hasPrefix("--") else { fail("unexpected argument \(a)") }
            if i + 1 < args.count, !args[i + 1].hasPrefix("--") { values[a] = args[i + 1]; i += 2 } else { flags.insert(a); i += 1 }
        }
    }
    func string(_ k: String) -> String { if let v = values[k] { return v }; fail("missing \(k)") }
    func int(_ k: String, _ d: Int) -> Int { values[k].flatMap(Int.init) ?? d }
    func double(_ k: String, _ d: Double) -> Double { values[k].flatMap(Double.init) ?? d }
}

func lines(_ path: String) -> [[String]] {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("cannot read \(path)") }
    return text.split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
}

func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [Int: String] = [:]
    func set(_ i: Int, _ row: String) { lock.lock(); rows[i] = row; lock.unlock() }
    func joined(_ n: Int) -> String { (0..<n).compactMap { rows[$0] }.joined(separator: "\n") + "\n" }
}

func parallel(_ count: Int, jobs: Int, _ body: @escaping @Sendable (Int, Int) -> Void) {
    let lock = NSLock()
    nonisolated(unsafe) var next = 0
    let group = DispatchGroup()
    for w in 0..<max(1, jobs) {
        group.enter()
        let thread = Thread {
            while true {
                lock.lock(); let i = next; next += 1; lock.unlock()
                if i >= count { break }
                body(i, w)
            }
            group.leave()
        }
        thread.stackSize = 16 << 20
        thread.start()
    }
    group.wait()
}

func landmarkConfig(_ o: Options) -> LandmarkConfig {
    var c = LandmarkConfig()
    c.timeReach = o.int("--time-reach", c.timeReach)
    c.frequencyReach = o.double("--frequency-reach", c.frequencyReach)
    return c
}

let args = Array(CommandLine.arguments.dropFirst())
guard let command = args.first else { fail("usage: deckie-recog-bench print|match ...") }
let o = Options(Array(args.dropFirst()))
let jobs = o.int("--jobs", ProcessInfo.processInfo.activeProcessorCount)

switch command {
case "print":
    let songs = lines(o.string("--list"))
    let out = o.string("--out")
    try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)
    let config = landmarkConfig(o)
    let rows = Collector()
    parallel(songs.count, jobs: jobs) { i, _ in
        let id = songs[i][0], path = songs[i][1]
        let t0 = now()
        guard let buffer = try? AudioDecoder.decode(URL(fileURLWithPath: path)) else {
            rows.set(i, "\(id)\tFAILED"); return
        }
        let mono = buffer.mono()
        let t1 = now()
        let marks = Landmarks(mono: mono, sampleRate: buffer.sampleRate, config: config)
        let t2 = now()
        let data = marks.encoded()
        try? data.write(to: URL(fileURLWithPath: out + "/" + id + ".dkl"))
        rows.set(i, String(format: "%@\t%.2f\t%d\t%d\t%.1f\t%.1f", id, buffer.duration, marks.count, data.count, t1 - t0, t2 - t1))
    }
    print(rows.joined(songs.count), terminator: "")

case "match":
    let dir = o.string("--prints")
    let leftOut = Set(o.values["--leave-out"].map { lines($0).map { $0[0] } } ?? [])
    let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".dkl") }.sorted()
    var songs: [(id: String, landmarks: Landmarks)] = []
    for name in names {
        let id = String(name.dropLast(4))
        if leftOut.contains(id) { continue }
        guard let d = FileManager.default.contents(atPath: dir + "/" + name), let m = Landmarks(encoded: d) else { fail("bad print \(name)") }
        songs.append((id, m))
    }
    let config = landmarkConfig(o)
    var pairing = PairingConfig()
    pairing.fanOut = o.int("--fan-out", pairing.fanOut)
    pairing.queryPerSlice = o.int("--query-per-slice", pairing.queryPerSlice)
    let t0 = now()
    let index = RecognitionIndex(songs: songs, landmark: config, pairing: pairing)
    FileHandle.standardError.write(Data(String(format: "index: %d songs, %d points, %d hashes, %.0f ms\n", index.songCount,
                                                index.pointCount, index.hashCount, now() - t0).utf8))
    if o.flags.contains("--stats") {
        for k in [50, 100, 200, 400, 800, 1600] {
            FileHandle.standardError.write(Data(String(format: "hashes in buckets over %d: %.1f %%\n", k, 100 * index.shareInBuckets(largerThan: k)).utf8))
        }
    }
    var grid = SpeedGrid()
    grid.stepPercent = o.double("--step", grid.stepPercent)
    if o.flags.contains("--no-speed") { grid.maxPercent = 0 }
    let audioStep = o.double("--audio-copies", 0)
    if audioStep > 0 { grid.maxPercent = 0 }
    let queries = lines(o.string("--queries"))
    let rows = Collector()
    let recognisers = (0..<jobs).map { _ in Recogniser(index: index, grid: grid) }
    nonisolated(unsafe) let pool = recognisers
    parallel(queries.count, jobs: jobs) { i, w in
        let q = queries[i]
        guard q.count >= 5, let first = Int(q[2]), let count = Int(q[3]), let rate = Int(q[4]),
              let handle = FileHandle(forReadingAtPath: q[1]) else { rows.set(i, "\(q[0])\tFAILED"); return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: UInt64(first * 2))
        let data = (try? handle.read(upToCount: count * 2)) ?? Data()
        var samples = [Float](repeating: 0, count: data.count / 2)
        data.withUnsafeBytes { raw in
            for k in 0..<samples.count {
                let v = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: 2 * k, as: Int16.self))
                samples[k] = Float(v) / 32768
            }
        }
        let t0 = now()
        var marks = Landmarks(mono: samples, sampleRate: rate, config: config)
        var t1 = now()
        var found: [RecognitionMatch] = []
        if audioStep > 0 {
            // The comparison arm: undo each candidate speed on the audio (resample the query, vinyl-style only), make
            // a constellation of each copy and match it with no speed candidates; the best copy answers. Its tempo
            // and pitch ratios are put back in terms of the query as heard.
            var k = -17.0
            while k <= 17.0 {
                let copy = k == 0 ? samples : Resampler.resample(samples, from: 1000, to: Int((1000 + 10 * k).rounded()))
                let m = Landmarks(mono: copy, sampleRate: rate, config: config)
                if k == 0 { marks = m }
                if var best = pool[w].match(m).first, best.score > (found.first?.score ?? -1) {
                    best.tempoRatio *= 1 + k / 100; best.pitchRatio *= 1 + k / 100
                    found = [best]
                }
                k += audioStep
            }
            t1 = t0
        } else {
            found = pool[w].match(marks)
        }
        let t2 = now()
        var row = String(format: "%@\t%d\t%.2f\t%.2f", q[0], marks.count, t1 - t0, t2 - t1)
        for k in 0..<2 {
            if k < found.count {
                let m = found[k]
                row += String(format: "\t%@\t%.3f\t%d\t%.3f\t%.5f\t%.5f", m.id, m.score, m.matched, m.offsetSeconds, m.tempoRatio, m.pitchRatio)
            } else { row += "\t-\t0\t0\t0\t1\t1" }
        }
        rows.set(i, row)
    }
    let text = rows.joined(queries.count)
    guard (try? text.write(toFile: o.string("--out"), atomically: true, encoding: .utf8)) != nil else { fail("cannot write results") }

default:
    fail("unknown command \(command)")
}
