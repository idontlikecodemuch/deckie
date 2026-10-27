// catalogtool: builds the Deck app's ShazamKit custom catalog from our MP3s, and tests matching on the Mac.
//
//   catalogtool sign     --manifest M.json --sigdir DIR --variants o,r-4,r+4,t-4,t+4 [--shard k/n] [--force]
//   catalogtool assemble --manifest M.json --sigdir DIR --variants ... --out Deck.shazamcatalog
//   catalogtool match    --catalog C --file F --start S --dur D [--render r+4|t-4|o]
//   catalogtool bench    --catalog C --manifest M.json --n N --dur D --render o,r+4,t+4 [--seed X] [--offset S]
//
// Variants: "o" = original; "rP" = resampled (vinyl: tempo and key move together, AVAudioUnitVarispeed);
// "tP" = tempo only (time-stretched, key kept, AVAudioUnitTimePitch). P is the pitch-fader percent, e.g. r+4, t-8.
// Variant audio is rendered offline in memory and streamed straight into SHSignatureGenerator: nothing is
// written to disk except the signatures (sigdir, a few hundred KB per track) and the catalog.
// Build: swiftc -O -parse-as-library main.swift -o catalogtool

import AVFoundation
import Foundation
import ShazamKit

// MARK: - args / manifest

struct Track: Codable { let id: String; let path: String; let title: String; let artist: String; let song: String }

func arg(_ name: String, _ def: String? = nil) -> String? {
    let a = CommandLine.arguments
    if let i = a.firstIndex(of: "--" + name), i + 1 < a.count { return a[i + 1] }
    return def
}
func flag(_ name: String) -> Bool { CommandLine.arguments.contains("--" + name) }
func die(_ s: String) -> Never { FileHandle.standardError.write((s + "\n").data(using: .utf8)!); exit(1) }

struct Variant: CustomStringConvertible {
    let flavour: String  // "o", "r", "t"
    let pct: Int
    init(_ s: String) {
        if s == "o" || s == "0" { flavour = "o"; pct = 0; return }
        flavour = String(s.prefix(1)); pct = Int(s.dropFirst()) ?? 0
        if !["r", "t"].contains(flavour) { die("bad variant \(s)") }
    }
    var rate: Double { 1 + Double(pct) / 100 }
    var description: String { flavour == "o" ? "o" : "\(flavour)\(pct >= 0 ? "+" : "")\(pct)" }
}

func loadManifest() -> [Track] {
    guard let p = arg("manifest") else { die("--manifest needed") }
    do { return try JSONDecoder().decode([Track].self, from: Data(contentsOf: URL(fileURLWithPath: p))) } catch { die("manifest: \(error)") }
}

// MARK: - offline rendering (mono 44.1 kHz float) through Varispeed / TimePitch

let outFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44100, channels: 1, interleaved: false)!

/// Renders [start, start+dur) of the file (seconds of the original; dur nil = to the end) through the variant
/// and hands each mono buffer to `sink`. Returns the rendered duration in seconds.
@discardableResult
func render(_ url: URL, start: Double = 0, dur: Double? = nil, variant: Variant, sink: (AVAudioPCMBuffer) throws -> Void) throws -> Double {
    let file = try AVAudioFile(forReading: url)
    let sr = file.processingFormat.sampleRate
    let startF = AVAudioFramePosition(max(0, start) * sr)
    guard startF < file.length else { return 0 }
    let count = AVAudioFrameCount(min(Double(file.length - startF), (dur ?? .infinity) * sr))
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    try engine.enableManualRenderingMode(.offline, format: outFormat, maximumFrameCount: 8192)
    var unit: AVAudioNode? = nil
    switch variant.flavour {
    case "r": let v = AVAudioUnitVarispeed(); v.rate = Float(variant.rate); unit = v
    case "t": let t = AVAudioUnitTimePitch(); t.rate = Float(variant.rate); t.pitch = 0; t.overlap = 8; unit = t
    default: break
    }
    if let u = unit {
        engine.attach(u)
        engine.connect(player, to: u, format: file.processingFormat)
        engine.connect(u, to: engine.mainMixerNode, format: file.processingFormat)
    } else {
        engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
    }
    player.scheduleSegment(file, startingFrame: startF, frameCount: count, at: nil)
    try engine.start()
    player.play()
    let total = AVAudioFramePosition(Double(count) / sr / variant.rate * 44100)
    let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount)!
    var done: AVAudioFramePosition = 0
    while done < total {
        let n = AVAudioFrameCount(min(AVAudioFramePosition(buf.frameCapacity), total - done))
        let st = try engine.renderOffline(n, to: buf)
        guard st == .success else { break }
        try sink(buf)
        done += AVAudioFramePosition(buf.frameLength)
    }
    player.stop(); engine.stop()
    return Double(done) / 44100
}

func signature(_ url: URL, start: Double = 0, dur: Double? = nil, variant: Variant) throws -> SHSignature {
    let gen = SHSignatureGenerator()
    try render(url, start: start, dur: dur, variant: variant) { try gen.append($0, at: nil) }
    return try gen.signature()
}

/// Query rendering for tests: either an in-memory variant, or a pre-rendered file (pedalboard) at the same offsets.
func querySignature(_ url: URL, start: Double, dur: Double, variant: Variant) throws -> SHSignature {
    // `start` is in the ORIGINAL track's seconds; render enough source to give `dur` seconds of output
    try signature(url, start: start, dur: dur * variant.rate, variant: variant)
}

// MARK: - commands

func sigURL(_ dir: String, _ id: String, _ v: Variant) -> URL {
    URL(fileURLWithPath: dir).appendingPathComponent("\(id)_\(v).shazamsignature")
}

func cmdSign() throws {
    let tracks = loadManifest()
    guard let dir = arg("sigdir") else { die("--sigdir needed") }
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let variants = (arg("variants", "o,r-4,r+4,t-4,t+4")!).split(separator: ",").map { Variant(String($0)) }
    var k = 0, n = 1
    if let s = arg("shard") { let p = s.split(separator: "/"); k = Int(p[0])!; n = Int(p[1])! }
    let mine = tracks.enumerated().filter { $0.offset % n == k }.map { $0.element }
    let t0 = Date()
    var made = 0
    for (i, t) in mine.enumerated() {
        for v in variants {
            let out = sigURL(dir, t.id, v)
            if !flag("force") && FileManager.default.fileExists(atPath: out.path) { continue }
            let ts = Date()
            do {
                let sig = try signature(URL(fileURLWithPath: t.path), variant: v)
                try sig.dataRepresentation.write(to: out, options: .atomic)
                made += 1
                print(String(format: "[%d/%d] %@ %@ %.0fs audio -> %d KB in %.1fs", i + 1, mine.count, t.id, v.description, sig.duration, sig.dataRepresentation.count / 1024, Date().timeIntervalSince(ts)))
            } catch { print("ERROR \(t.id) \(v): \(error)") }
        }
    }
    print(String(format: "shard %d/%d: %d signatures in %.0fs", k, n, made, Date().timeIntervalSince(t0)))
}

let kID = SHMediaItemProperty("deck_id"), kFlav = SHMediaItemProperty("deck_flavour"), kPct = SHMediaItemProperty("deck_pct")

func cmdAssemble() throws {
    let tracks = loadManifest()
    guard let dir = arg("sigdir"), let out = arg("out") else { die("--sigdir and --out needed") }
    let variants = (arg("variants", "o,r-4,r+4,t-4,t+4")!).split(separator: ",").map { Variant(String($0)) }
    let cat = SHCustomCatalog()
    var n = 0, missing = 0
    for t in tracks {
        for v in variants {
            let u = sigURL(dir, t.id, v)
            guard let d = try? Data(contentsOf: u) else { missing += 1; continue }
            let sig = try SHSignature(dataRepresentation: d)
            let item = SHMediaItem(properties: [
                .title: t.song, .artist: t.artist, kID: t.id, kFlav: v.flavour, kPct: v.pct,
            ])
            try cat.addReferenceSignature(sig, representing: [item])
            n += 1
        }
    }
    let url = URL(fileURLWithPath: out)
    try? FileManager.default.removeItem(at: url)
    try cat.write(to: url)
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
    print("catalog: \(n) reference signatures (\(missing) missing) -> \(url.lastPathComponent) \(size / 1024 / 1024) MB; query duration \(cat.minimumQuerySignatureDuration)-\(cat.maximumQuerySignatureDuration) s")
}

func loadCatalog() throws -> SHCustomCatalog {
    guard let c = arg("catalog") else { die("--catalog needed") }
    let cat = SHCustomCatalog()
    try cat.add(from: URL(fileURLWithPath: c))
    return cat
}

struct MatchOut: Codable { var id: String?; var flavour: String?; var pct: Int?; var offset: Double?; var skew: Double?; var ms: Double; var others: [String] }

func describe(_ r: SHSession.Result, ms: Double) -> MatchOut {
    switch r {
    case .match(let m):
        let items = m.mediaItems
        let f = items.first!
        return MatchOut(id: f[kID] as? String, flavour: f[kFlav] as? String, pct: f[kPct] as? Int, offset: f.matchOffset, skew: Double(f.frequencySkew), ms: ms,
                        others: items.dropFirst().map { "\($0[kID] as? String ?? "?") \($0[kFlav] as? String ?? "?")\($0[kPct] as? Int ?? 0) off \(String(format: "%.1f", $0.matchOffset)) skew \(String(format: "%.4f", $0.frequencySkew))" })
    case .noMatch: return MatchOut(ms: ms, others: ["no match"])
    case .error(let e, _): return MatchOut(ms: ms, others: ["error \(e)"])
    @unknown default: return MatchOut(ms: ms, others: [])
    }
}

func cmdMatch() async throws {
    let cat = try loadCatalog()
    guard let f = arg("file") else { die("--file needed") }
    let start = Double(arg("start", "60")!)!, dur = Double(arg("dur", "8")!)!
    let v = Variant(arg("render", "o")!)
    let sig = try querySignature(URL(fileURLWithPath: f), start: start, dur: dur, variant: v)
    let session = SHSession(catalog: cat)
    let t = Date()
    let r = await session.result(from: sig)
    let out = describe(r, ms: Date().timeIntervalSince(t) * 1000)
    print(String(data: try JSONEncoder().encode(out), encoding: .utf8)!)
}

func cmdBench() async throws {
    let cat = try loadCatalog()
    let tracks = loadManifest()
    let n = Int(arg("n", "30")!)!, dur = Double(arg("dur", "8")!)!
    let renders = arg("render", "o,r+4,t+4")!.split(separator: ",").map { Variant(String($0)) }
    var rng = SystemRandomNumberGenerator()
    var seed = UInt64(arg("seed", "7")!)!
    func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
    _ = rng
    let session = SHSession(catalog: cat)
    struct Stat { var n = 0, ok = 0, flav = 0, pct = 0, none = 0, wrong = 0; var ms: [Double] = []; var offErr: [Double] = [] }
    var stats: [String: Stat] = [:]
    for i in 0..<n {
        let t = tracks[Int(rnd() * Double(tracks.count))]
        let url = URL(fileURLWithPath: t.path)
        let len = (try? AVAudioFile(forReading: url)).map { Double($0.length) / $0.processingFormat.sampleRate } ?? 200
        let start = arg("offset").map { Double($0)! } ?? (10 + rnd() * max(1, len - 30))
        for v in renders {
            var s = stats[v.description] ?? Stat()
            s.n += 1
            do {
                let sig = try querySignature(url, start: start, dur: dur, variant: v)
                let tt = Date()
                let r = await session.result(from: sig)
                let ms = Date().timeIntervalSince(tt) * 1000
                let o = describe(r, ms: ms)
                s.ms.append(ms)
                if o.id == nil { s.none += 1 }
                else if o.id == t.id {
                    s.ok += 1
                    if o.flavour == v.flavour || (v.flavour == "o" && o.pct == 0) { s.flav += 1 }
                    if o.pct == v.pct { s.pct += 1 }
                    // offset of the matched item is in the matched variant's time; convert to original seconds
                    let rate = 1 + Double(o.pct ?? 0) / 100
                    s.offErr.append(abs((o.offset ?? 0) * rate - start))
                } else { s.wrong += 1 }
                print(String(format: "%3d %@ %-6@ @%5.1fs -> %@ %@%@ off %.1f skew %.4f %.0f ms %@", i, t.id, v.description, start, o.id ?? "none", o.flavour ?? "", o.pct.map { String($0) } ?? "", o.offset ?? -1, o.skew ?? 0, ms, o.id == t.id ? "OK" : (o.id == nil ? "-" : "WRONG " + o.others.joined(separator: "; "))))
            } catch { print("err \(error)") }
            stats[v.description] = s
        }
    }
    for v in renders {
        let s = stats[v.description]!
        let ms = s.ms.sorted(), oe = s.offErr.sorted()
        print(String(format: "SUMMARY %-6@ n=%d match=%d none=%d wrong=%d flavour-right=%d pct-right=%d median %.0f ms (max %.0f) offset err median %.2fs", v.description, s.n, s.ok, s.none, s.wrong, s.flav, s.pct, ms.isEmpty ? 0 : ms[ms.count / 2], ms.last ?? 0, oe.isEmpty ? 0 : oe[oe.count / 2]))
    }
}

/// Live test on the Mac: microphone -> SHSession streaming, the same path the iPad app uses.
/// catalogtool listen --catalog C --secs 40
func cmdListen() async throws {
    let cat = try loadCatalog()
    let secs = Double(arg("secs", "40")!)!
    let session = SHSession(catalog: cat)
    let engine = AVAudioEngine()
    let input = engine.inputNode
    let fmt = input.outputFormat(forBus: 0)
    print("input \(fmt.sampleRate) Hz \(fmt.channelCount) ch")
    guard fmt.sampleRate > 0 else { die("no input") }
    let t0 = Date()
    var peak: Float = 0
    input.installTap(onBus: 0, bufferSize: 4096, format: fmt) { buf, when in
        session.matchStreamingBuffer(buf, at: when)
        if let ch = buf.floatChannelData?[0] { for i in 0..<Int(buf.frameLength) { peak = max(peak, abs(ch[i])) } }
    }
    try engine.start()
    let listener = Task {
        for await r in session.results {
            let o = describe(r, ms: 0)
            print(String(format: "%6.1fs %@ %@%@ off %.1f skew %.4f peak %.3f %@", Date().timeIntervalSince(t0), o.id ?? "none", o.flavour ?? "", o.pct.map { String($0) } ?? "", o.offset ?? -1, o.skew ?? 0, peak, o.id == nil ? o.others.joined() : ""))
            fflush(stdout)
        }
    }
    try await Task.sleep(for: .seconds(secs))
    listener.cancel(); engine.stop()
}

@main struct Main {
    static func main() async {
        let cmd = CommandLine.arguments.dropFirst().first ?? ""
        do {
            switch cmd {
            case "sign": try cmdSign()
            case "assemble": try cmdAssemble()
            case "match": try await cmdMatch()
            case "bench": try await cmdBench()
            case "listen": try await cmdListen()
            default: die("usage: catalogtool sign|assemble|match|bench ...")
            }
        } catch { die("error: \(error)") }
    }
}
