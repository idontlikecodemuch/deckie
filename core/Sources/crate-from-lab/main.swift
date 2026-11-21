// crate-from-lab: writes a crate (docs/architecture/crate-format.md) from the lab's feature files.
//
//   swift run crate-from-lab --out <folder>.deckie [--ids id,id,...] [--name N] [--crate-id X]
//                            [--created-at T] [--analysed-at T] [--lab <folder>] [--music-root <folder>]
//                            [--single <file>]
//
// --lab is the lab's data folder (features/ and candidates.json): by default DECKIE_LAB_DATA, else the public sample
// of invented songs, core/fixtures/lab-sample, found from the current folder upwards. Without --ids it takes every
// feature file there. --music-root is the folder the candidates' paths start with (default /path/to/music/, the
// sample's), stripped to give each record's file.rel. Times are UTC, as 2026-10-26T00:00:00Z; --created-at defaults
// to now and --analysed-at to 2026-10-26, as the feature files carry no date of their own.
// --single also writes the crate file's single-file form (CrateArchive: the same files in one uncompressed zip).
// core/Tools/make_crate_fixture.sh uses it to rebuild core/fixtures/example.deckiecrate.

import Foundation
import DeckieCrate
import DeckieLab

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("crate-from-lab: \(message)\n".utf8))
    exit(1)
}

var options: [String: String] = [:]
var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    guard arg.hasPrefix("--"), let value = args.popFirst() else { fail("expected --option value, got \(arg)") }
    options[String(arg.dropFirst(2))] = value
}
let known: Set = ["out", "ids", "name", "crate-id", "created-at", "analysed-at", "lab", "music-root", "single"]
if let unknown = options.keys.first(where: { !known.contains($0) }) { fail("unknown option --\(unknown)") }
guard let out = options["out"] else { fail("--out <folder>.deckie is required") }

func labFolder(_ lab: String?) -> URL {
    if let lab { return URL(fileURLWithPath: lab) }
    if let env = ProcessInfo.processInfo.environment["DECKIE_LAB_DATA"], !env.isEmpty { return URL(fileURLWithPath: env) }
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while dir.path != "/" {
        let sample = dir.appendingPathComponent("core/fixtures/lab-sample")
        if FileManager.default.fileExists(atPath: sample.appendingPathComponent("features").path) { return sample }
        dir.deleteLastPathComponent()
    }
    fail("no lab data: give --lab or set DECKIE_LAB_DATA")
}

func now() -> String {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: Date())
}

let lab = labFolder(options["lab"])
let outURL = URL(fileURLWithPath: out)
let name = options["name"] ?? outURL.deletingPathExtension().lastPathComponent
let manifest = CrateManifest(crateId: options["crate-id"] ?? UUID().uuidString.lowercased(), name: name,
                             createdAt: options["created-at"] ?? now(), devicesSeen: ["lab-mac"])
do {
    let crate = try FeatureFile.crate(
        featuresDir: lab.appendingPathComponent("features"),
        ids: options["ids"].map { $0.split(separator: ",").map(String.init) },
        candidatesFile: lab.appendingPathComponent("candidates.json"),
        manifest: manifest,
        options: .init(analysedAt: options["analysed-at"] ?? "2026-10-26T00:00:00Z",
                       musicRoot: options["music-root"] ?? FeatureFile.labMusicRoot))
    try CrateWriter.write(crate, to: outURL)
    let files = try CrateWriter.encode(crate)
    let total = files.values.reduce(0) { $0 + $1.count }
    print("wrote \(crate.tracks.count) tracks to \(out): \(files.count) files, \(total) bytes " +
          "(crate.json \(files["crate.json"]!.count), manifest.json \(files["manifest.json"]!.count))")
    if let single = options["single"] {
        try CrateArchive.pack(package: outURL, to: URL(fileURLWithPath: single))
        print("wrote the single-file form to \(single)")
    }
} catch {
    fail("\(error)")
}
