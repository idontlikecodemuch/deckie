// crate-from-lab: writes a crate (docs/architecture/crate-format.md) from the lab's committed feature files.
//
//   swift run crate-from-lab --out <folder>.deckiecrate [--ids id,id,...] [--name N] [--crate-id X]
//                            [--created-at T] [--analysed-at T] [--repo <repository root>]
//
// Without --ids it takes every file in mixer/features. The repository root is found from the current folder
// upwards unless --repo gives it. Times are UTC, as 2026-10-26T00:00:00Z; --created-at defaults to now and
// --analysed-at to the day the feature files were committed, as they carry no date of their own.
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
let known: Set = ["out", "ids", "name", "crate-id", "created-at", "analysed-at", "repo"]
if let unknown = options.keys.first(where: { !known.contains($0) }) { fail("unknown option --\(unknown)") }
guard let out = options["out"] else { fail("--out <folder>.deckiecrate is required") }

func repositoryRoot(_ repo: String?) -> URL {
    if let repo { return URL(fileURLWithPath: repo) }
    var dir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    while dir.path != "/" {
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent("mixer/features").path) { return dir }
        dir.deleteLastPathComponent()
    }
    fail("no mixer/features folder here or above; give --repo")
}

func now() -> String {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: Date())
}

let root = repositoryRoot(options["repo"])
let outURL = URL(fileURLWithPath: out)
let name = options["name"] ?? outURL.deletingPathExtension().lastPathComponent
let manifest = CrateManifest(crateId: options["crate-id"] ?? UUID().uuidString.lowercased(), name: name,
                             createdAt: options["created-at"] ?? now(), devicesSeen: ["lab-mac"])
do {
    let crate = try FeatureFile.crate(
        featuresDir: root.appendingPathComponent("mixer/features"),
        ids: options["ids"].map { $0.split(separator: ",").map(String.init) },
        candidatesFile: root.appendingPathComponent("mixer/candidates.json"),
        manifest: manifest,
        options: .init(analysedAt: options["analysed-at"] ?? "2026-10-26T00:00:00Z"))
    try CrateWriter.write(crate, to: outURL)
    let files = try CrateWriter.encode(crate)
    let total = files.values.reduce(0) { $0 + $1.count }
    print("wrote \(crate.tracks.count) tracks to \(out): \(files.count) files, \(total) bytes " +
          "(crate.json \(files["crate.json"]!.count), manifest.json \(files["manifest.json"]!.count))")
} catch {
    fail("\(error)")
}
