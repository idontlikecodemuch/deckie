// MUBench: runs Apple's Music Understanding framework over audio files and writes the raw SessionResult as JSON.
// Stage 1 benchmark harness (docs/architecture/analysis-port-plan.md). Launch arguments:
//   -in <file> -out <json>                    one file
//   -manifest <json> -outdir <dir> [-limit n] [-force]   batch: [{"id":..., "path":...}, ...] -> <dir>/<id>.mu.json + run.json
// In the simulator, host paths are readable directly. Run with: xcrun simctl launch --console <udid> io.christophershannon.mubench <args>
import SwiftUI
import AVFoundation
import MusicUnderstanding

@main
struct MUBenchApp: App {
    var body: some Scene {
        WindowGroup { Text("MUBench running; see the console").padding().task { await Bench.run() } }
    }
}

enum Bench {
    static func arg(_ name: String) -> String? {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: name), i + 1 < a.count else { return nil }
        return a[i + 1]
    }
    static func flag(_ name: String) -> Bool { ProcessInfo.processInfo.arguments.contains(name) }

    static func run() async {
        var jobs: [(id: String, path: String)] = []
        if let p = arg("-in") { jobs = [(id: (p as NSString).deletingPathExtension.components(separatedBy: "/").last ?? "track", path: p)] }
        if let m = arg("-manifest"), let d = FileManager.default.contents(atPath: m),
           let arr = (try? JSONSerialization.jsonObject(with: d)) as? [[String: Any]] {
            jobs = arr.compactMap { r in
                guard let id = r["id"] as? String, let path = r["path"] as? String else { return nil }
                return (id: id, path: path)
            }
        }
        let outDir = arg("-outdir")
        let limit = Int(arg("-limit") ?? "") ?? Int.max
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        enc.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")  // silence measures -inf LUFS
        var runLog: [[String: Any]] = []
        let started = Date()
        print("MUBench on \(await UIDevice.current.model) \(ProcessInfo.processInfo.operatingSystemVersionString); \(jobs.count) job(s)")
        for (n, job) in jobs.prefix(limit).enumerated() {
            let outPath = arg("-out") ?? ((outDir ?? NSTemporaryDirectory()) + "/" + job.id + ".mu.json")
            if !flag("-force"), FileManager.default.fileExists(atPath: outPath) { continue }
            let t0 = Date()
            do {
                let asset = AVURLAsset(url: URL(fileURLWithPath: job.path))
                let session = try await MusicUnderstandingSession(asset: asset)
                let result = try await session.analyze()
                let secs = Date().timeIntervalSince(t0)
                let data = try enc.encode(result)
                try data.write(to: URL(fileURLWithPath: outPath))
                let bpm = result.rhythm?.beatsPerMinute.map { String(format: "%.2f", $0) } ?? "-"
                let key = result.key?.ranges.first.map { "\($0.value.tonic.rawValue) \($0.value.mode.rawValue)" } ?? "-"
                let lufs = result.loudness.map { String(format: "%.1f", $0.integrated.value) } ?? "-"
                let thermal = ProcessInfo.processInfo.thermalState.rawValue
                print("[\(n + 1)/\(jobs.count)] \(job.id) \(String(format: "%.1f", secs))s bpm \(bpm) beats \(result.rhythm?.beats.count ?? 0) bars \(result.rhythm?.bars.count ?? 0) key \(key) keyRanges \(result.key?.ranges.count ?? 0) sections \(result.structure?.sections.count ?? 0) segments \(result.structure?.segments.count ?? 0) phrases \(result.structure?.phrases.count ?? 0) lufs \(lufs) instruments \(result.instrumentActivity?.activity.keys.map { $0.rawValue }.sorted().joined(separator: ",") ?? "-") bytes \(data.count) thermal \(thermal)")
                runLog.append(["id": job.id, "secs": secs, "ok": true, "bytes": data.count, "thermal": thermal])
            } catch {
                print("[\(n + 1)/\(jobs.count)] \(job.id) FAILED \(error)")
                runLog.append(["id": job.id, "ok": false, "error": "\(error)"])
            }
        }
        if let outDir {
            let run: [String: Any] = ["device": await UIDevice.current.model, "os": ProcessInfo.processInfo.operatingSystemVersionString,
                                      "started": ISO8601DateFormatter().string(from: started), "secs_total": Date().timeIntervalSince(started), "jobs": runLog]
            if let rd = try? JSONSerialization.data(withJSONObject: run, options: [.prettyPrinted, .sortedKeys]) {
                try? rd.write(to: URL(fileURLWithPath: outDir + "/run.json"))
            }
        }
        print("DONE \(runLog.filter { ($0["ok"] as? Bool) == true }.count) ok, \(runLog.filter { ($0["ok"] as? Bool) == false }.count) failed, \(String(format: "%.0f", Date().timeIntervalSince(started)))s")
        exit(0)
    }
}
