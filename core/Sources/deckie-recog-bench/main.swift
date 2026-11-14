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
//       and the second-best song: id, score, matched points, offset in seconds, tempo ratio, pitch ratio; then the
//       two songs' confidences (the number to threshold).
//       --deep: when the first answer's confidence is under --deep-below (3), match again with a denser
//       constellation of the query and three points per slice, and keep the better answer.
//       --pairs: two-point hashes only; --hybrid: three-point hashes, then two-point ones when nothing sure is found.

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
        var mono: [Float] = []
        var rate = 16000
        if path.hasSuffix(".s16") {
            // Already decoded by the benchmark's scripts: 16-bit little-endian mono at 16 kHz.
            guard let data = FileManager.default.contents(atPath: path) else { rows.set(i, "\(id)\tFAILED"); return }
            mono = [Float](repeating: 0, count: data.count / 2)
            data.withUnsafeBytes { raw in
                for k in 0..<mono.count { mono[k] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: 2 * k, as: Int16.self))) / 32768 }
            }
        } else {
            guard let buffer = try? AudioDecoder.decode(URL(fileURLWithPath: path)) else { rows.set(i, "\(id)\tFAILED"); return }
            mono = buffer.mono(); rate = buffer.sampleRate
        }
        let seconds = Double(mono.count) / Double(rate)
        let t1 = now()
        let marks = Landmarks(mono: mono, sampleRate: rate, config: config)
        let t2 = now()
        let data = marks.encoded()
        try? data.write(to: URL(fileURLWithPath: out + "/" + id + ".dkl"))
        rows.set(i, String(format: "%@\t%.2f\t%d\t%d\t%.1f\t%.1f", id, seconds, marks.count, data.count, t1 - t0, t2 - t1))
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
    // --limit N: only the first N songs (ids in order). --pad N: fill the index up to N songs with altered copies
    // of the real constellations (time reversed, every pitch moved round the band by a different amount per copy):
    // they have a real song's density and rhythm of points and match no query, so they load the index as more
    // songs would without being more music.
    if let limit = o.values["--limit"].flatMap(Int.init), limit < songs.count { songs = Array(songs.prefix(limit)) }
    if let pad = o.values["--pad"].flatMap(Int.init), !songs.isEmpty {
        let real = songs.count
        let top = UInt16(LandmarkConfig().octaves * Landmarks.pitchUnitsPerOctave)
        var copy = 0
        while songs.count < pad {
            let source = songs[(songs.count - real) % real].landmarks
            copy = (songs.count - real) / real + 1
            let turn = UInt16((copy * 997 + 311) % Int(top))
            var frames: [UInt32] = [], packed: [UInt16] = []
            for i in stride(from: source.count - 1, through: 0, by: -1) {
                frames.append(UInt32(source.frameCount - 1) - min(UInt32(source.frameCount - 1), source.frames[i]))
                packed.append((source.pitch(i) + turn) % top | UInt16(source.level(i)) << 14)
            }
            // Points of one frame must stay in pitch order within the frame for nothing here; time order is enough.
            songs.append(("pad\(songs.count)", Landmarks(frames: frames, pitches: packed, frameCount: source.frameCount)))
        }
    }
    // The test for copies (docs/research/w3-recognition-real-room.md): --duplicate-all adds a second entry for every
    // song, "<id>~copy", with the same fingerprint; --join N adds long files, each N of the songs end to end
    // ("join~<k>", listed with their songs in --join-map FILE), as a continuous mix kept as one track is. With them an
    // index must score as it does without. --no-copy-finding leaves the index's own search for such songs out.
    if o.flags.contains("--duplicate-all") {
        songs += songs.map { ($0.id + "~copy", $0.landmarks) }
    }
    if let per = o.values["--join"].flatMap(Int.init), per > 1 {
        let real = songs.filter { !$0.id.hasSuffix("~copy") }
        var map = ""
        var k = 0
        while (k + 1) * per * 8 <= real.count {      // one joined file for every 8 x N songs, from songs spread through the list
            let members = (0..<per).map { real[(k * per * 8 + $0 * 8) % real.count] }
            var frames: [UInt32] = [], packed: [UInt16] = []
            var at = 0
            for m in members {
                for i in 0..<m.landmarks.count { frames.append(UInt32(at) + m.landmarks.frames[i]); packed.append(m.landmarks.packed[i]) }
                at += m.landmarks.frameCount
            }
            songs.append(("join~\(k)", Landmarks(frames: frames, pitches: packed, frameCount: at)))
            map += "join~\(k)\t" + members.map(\.id).joined(separator: "\t") + "\n"
            k += 1
        }
        if let path = o.values["--join-map"] { try? map.write(toFile: path, atomically: true, encoding: .utf8) }
    }
    let config = landmarkConfig(o)
    var pairing = PairingConfig()
    pairing.fanOut = o.int("--fan-out", pairing.fanOut)
    if o.flags.contains("--pairs") { pairing.triples = false }
    if o.flags.contains("--first-in-time") { pairing.byStrength = false }
    if o.flags.contains("--wide-entries") { pairing.compact = false }
    pairing.entriesPerSlot = o.int("--entries-per-slot", pairing.entriesPerSlot)
    pairing.keepOneIn = o.int("--keep-one-in", pairing.keepOneIn)
    pairing.minAnchorLevel = o.int("--min-anchor-level", pairing.minAnchorLevel)
    // Four points: --points 4 (hashed like triples, with the speed search), or --ratio-quads (no speed search).
    pairing.points = o.int("--points", pairing.points)
    if o.flags.contains("--ratio-quads") { pairing.ratio = true }
    pairing.ratioFar = o.int("--ratio-far", pairing.ratioFar)
    pairing.queryRatioFar = o.int("--query-ratio-far", pairing.queryRatioFar)
    pairing.queryRatioInner = o.int("--query-ratio-inner", pairing.queryRatioInner)
    pairing.maxGap = o.int("--max-gap", pairing.maxGap)
    let verified = o.int("--verified", 12)
    pairing.queryPerSlice = o.int("--query-per-slice", pairing.queryPerSlice)
    let t0 = now()
    let index = RecognitionIndex(songs: songs, landmark: config, pairing: pairing, findCopies: !o.flags.contains("--no-copy-finding"))
    FileHandle.standardError.write(Data("songs that hold the same sound as another: \(index.related.filter { !$0.isEmpty }.count)\n".utf8))
    FileHandle.standardError.write(Data(String(format: "index: %d songs, %d points, %d hashes, %.0f ms; memory %.1f MB (%.1f KB a song), points on storage %.1f MB\n",
                                                index.songCount, index.pointCount, index.hashCount, now() - t0,
                                                Double(index.memoryBytes) / 1e6, Double(index.memoryBytes) / 1e3 / Double(max(1, index.songCount)),
                                                Double(index.pointBytes) / 1e6).utf8))
    if let path = o.values["--memory-out"] {
        try? String(format: "%d\t%d\t%d\t%d\n", index.songCount, index.memoryBytes, index.pointBytes, index.hashCount).write(toFile: path, atomically: true, encoding: .utf8)
    }
    if o.flags.contains("--stats") {
        for k in [50, 100, 200, 400, 800, 1600] {
            FileHandle.standardError.write(Data(String(format: "hashes in buckets over %d: %.1f %%\n", k, 100 * index.shareInBuckets(largerThan: k)).utf8))
        }
    }
    var grid = SpeedGrid()
    grid.stepPercent = o.double("--step", grid.stepPercent)
    if o.flags.contains("--no-speed") { grid.maxPercent = 0 }
    let proposalCount = o.int("--proposals", 0)
    // --dense-query: the query's constellation is made with the denser neighbourhood (64 ms, 8 %) and three points
    // are taken per slice, on every query (not only as a second pass).
    let denseQuery = o.flags.contains("--dense-query")
    let deep = o.flags.contains("--deep")
    let deepBelow = o.double("--deep-below", 3.0)
    let deepConfig: LandmarkConfig = {
        var c = config
        c.timeReach = o.int("--deep-time-reach", 4); c.frequencyReach = o.double("--deep-frequency-reach", 0.08)
        return c
    }()
    let audioStep = o.double("--audio-copies", 0)
    if audioStep > 0 { grid.maxPercent = 0 }
    let queries = lines(o.string("--queries"))
    let rows = Collector()
    let recognisers = (0..<jobs).map { _ in Recogniser(index: index, grid: grid) }
    let fallback = o.flags.contains("--hybrid") ? { () -> RecognitionIndex in
        var pairs = pairing; pairs.triples = false
        return RecognitionIndex(songs: songs, landmark: config, pairing: pairs) }() : nil
    for r in recognisers { r.verified = verified; r.fallback = fallback; r.fallbackBelow = o.double("--fallback-below", r.fallbackBelow) }
    // --shortlist K [--detail pairs]: the index only proposes K songs; those are hashed in full (three-point hashes,
    // or two-point with --detail pairs) from their constellations, which here stand in for files on storage.
    let checkSongs = o.int("--check-songs", 0)
    for r in recognisers { r.checkSongs = checkSongs; r.fuzzyGaps = o.flags.contains("--fuzzy-gaps") }
    let shortlist = o.int("--shortlist", 0)
    if shortlist > 0 {
        nonisolated(unsafe) let all = songs
        var full = PairingConfig()
        full.entriesPerSlot = 4
        if o.values["--detail"] == "pairs" { full.triples = false }
        for r in recognisers { r.shortlistSize = shortlist; r.detailPairing = full; r.detail = { all[$0].landmarks } }
    }
    nonisolated(unsafe) let pool = recognisers
    parallel(queries.count, jobs: jobs) { i, w in pooled {
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
        var marks = Landmarks(mono: samples, sampleRate: rate, config: denseQuery ? deepConfig : config)
        if denseQuery { pool[w].queryPerSlice = 3 }
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
            if deep, (found.first?.confidence ?? 0) < deepBelow {
                // The deeper second pass: a denser constellation of the query and more of its points per slice.
                let more = Landmarks(mono: samples, sampleRate: rate, config: deepConfig)
                pool[w].queryPerSlice = 3
                let again = pool[w].match(more)
                pool[w].queryPerSlice = denseQuery ? 3 : nil
                if (again.first?.confidence ?? 0) > (found.first?.confidence ?? 0) { found = again }
            }
        }
        let t2 = now()
        var row = String(format: "%@\t%d\t%.2f\t%.2f", q[0], marks.count, t1 - t0, t2 - t1)
        for k in 0..<2 {
            if k < found.count {
                let m = found[k]
                row += String(format: "\t%@\t%.3f\t%d\t%.3f\t%.5f\t%.5f", m.id, m.score, m.matched, m.offsetSeconds, m.tempoRatio, m.pitchRatio)
            } else { row += "\t-\t0\t0\t0\t1\t1" }
        }
        row += String(format: "\t%.3f\t%.3f", found.first?.confidence ?? 0, found.count > 1 ? found[1].confidence : 0)
        if proposalCount > 0 {
            // --proposals K: one more column, the first pass's K proposed songs, best first.
            row += "\t" + pool[w].proposals(marks, count: proposalCount).map { index.ids[$0] }.joined(separator: "\u{1F}")
        }
        rows.set(i, row)
    } }
    let text = rows.joined(queries.count)
    guard (try? text.write(toFile: o.string("--out"), atomically: true, encoding: .utf8)) != nil else { fail("cannot write results") }

case "strengths":
    // The spread of point strengths over some songs (to place the four levels at equal shares).
    let songs = lines(o.string("--list"))
    var all: [Float] = []
    for s in songs {
        guard let buffer = try? AudioDecoder.decode(URL(fileURLWithPath: s[1])) else { continue }
        all += Landmarks(mono: buffer.mono(), sampleRate: buffer.sampleRate, config: landmarkConfig(o)).strengths
    }
    all.sort()
    print(all.count, [0.1, 0.25, 0.5, 0.75, 0.9].map { String(format: "%.0f%%: %.1f dB", $0 * 100, all[Int($0 * Double(all.count - 1))]) }.joined(separator: ", "))

default:
    fail("unknown command \(command)")
}
