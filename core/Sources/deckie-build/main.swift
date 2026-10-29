// deckie-build: builds a crate (docs/architecture/crate-format.md) from a folder of music, and runs the yardstick
// bench against the lab's feature files.
//
//   deckie-build <folder> --out <name>.deckiecrate [--rekordbox export.xml] [--jobs N] [--bpm-tags] [--name N]
//                [--fresh]
//   deckie-build bench <folder> --features mixer/features --candidates mixer/candidates.json [--music-root path]
//                [--out bench.json] [--records dir] [--jobs N] [--ids id,id,...] [--fresh]
//
// The engine needs ONNX Runtime and the Beat This! model: DECKIE_ONNXRUNTIME_LIB and DECKIE_BEAT_THIS_MODEL, or
// core/.deps and core/.models of the checkout it was built from (core/README.md).

import Foundation
import DeckieBuild
import DeckieEngine
import DeckieInference

let usage = """
    usage:
      deckie-build <folder> --out <name>.deckiecrate [--rekordbox export.xml] [--jobs N] [--bpm-tags] [--name N] [--fresh]
      deckie-build bench <folder> --features <dir> --candidates <file> [--music-root path] [--out bench.json]
                   [--records dir] [--jobs N] [--ids id,id,...] [--fresh]

    build: analyses every audio file below <folder> (mp3, flac, wav, aif, aiff, aifc, m4a, mp4, aac, wma, ogg, opus,
      m4p), N at a time (default: the processor count, fewer if memory is short, as a job needs about 1 GB: \(defaultJobs)
      here), and writes the crate. Finished files are kept in <name>.deckiebuild beside the crate, so a second run
      skips files that are unchanged; --fresh starts over.
      Files that cannot be analysed are counted in the summary and listed in the crate's manifest (import_log).
      --rekordbox takes names, the DJ's tempo (which steers the analysis), key, cues and playlists from a rekordbox
      collection export; --bpm-tags takes a file's own tempo tag (ID3 TBPM, FLAC BPM) when rekordbox gives none.
    bench: analyses every lab track found below <folder> (a candidates row's path, less the music root, which
      defaults to the folder the rows' paths share) and compares it with the lab's feature file by the stage 1
      measures; prints a table and writes the JSON. The engine's records go to <out>.records and are taken again on
      a later run while the file and the engine are the same; --fresh analyses everything again.
    """

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("deckie-build: \(message)\n".utf8))
    exit(code)
}

func say(_ line: String) {
    FileHandle.standardOutput.write(Data((line + "\n").utf8))
}

/// The options after the positional folder: `--flag` or `--option value`.
func parse(_ args: [String], flags: Set<String>, values: Set<String>) -> (folder: String, options: [String: String]) {
    var folder: String? = nil
    var options: [String: String] = [:]
    var rest = args[...]
    while let arg = rest.popFirst() {
        if arg == "-h" || arg == "--help" { say(usage); exit(0) }
        if arg.hasPrefix("--") {
            let name = String(arg.dropFirst(2))
            if flags.contains(name) { options[name] = "yes"; continue }
            guard values.contains(name) else { fail("unknown option \(arg)\n\(usage)", code: 2) }
            guard let value = rest.popFirst() else { fail("\(arg) needs a value", code: 2) }
            options[name] = value
        } else if folder == nil {
            folder = arg
        } else {
            fail("unexpected argument \(arg)\n\(usage)", code: 2)
        }
    }
    guard let folder else { fail("no folder given\n\(usage)", code: 2) }
    return (folder, options)
}

func jobs(_ options: [String: String]) -> Int {
    guard let j = options["jobs"] else { return defaultJobs }
    guard let n = Int(j), n >= 1 else { fail("--jobs needs a whole number of 1 or more", code: 2) }
    return n
}

func url(_ path: String) -> URL { URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL }

// An interrupted run keeps every finished file in the work folder; say so.
#if !os(Windows)
signal(SIGINT) { _ in
    let message = "\ndeckie-build: interrupted; finished files are kept, run the same command again to carry on\n"
    _ = message.withCString { write(2, $0, strlen($0)) }
    _exit(130)
}
#endif

var args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty { say(usage); exit(2) }

do {
    if args.first == "bench" {
        args.removeFirst()
        let (folder, o) = parse(args, flags: ["fresh"],
                                values: ["features", "candidates", "music-root", "out", "records", "jobs", "ids"])
        guard let features = o["features"] else { fail("bench needs --features <dir> (mixer/features)", code: 2) }
        guard let candidates = o["candidates"] else { fail("bench needs --candidates <file> (mixer/candidates.json)", code: 2) }
        let options = BenchOptions(folder: url(folder), features: url(features), candidates: url(candidates),
                                   musicRoot: o["music-root"], output: o["out"].map(url), records: o["records"].map(url),
                                   jobs: jobs(o), ids: o["ids"].map { $0.split(separator: ",").map(String.init) },
                                   fresh: o["fresh"] != nil)
        if let note = Builder.vocalTaggerNote { say(note) }
        let report = try Bench.run(options, progress: { say($0) })
        say("")
        say(report.table)
        if let out = options.output { say("wrote \(out.path)" + (options.records.map { "; engine records in \($0.path)" } ?? "")) }
    } else {
        let (folder, o) = parse(args, flags: ["bpm-tags", "fresh"], values: ["out", "rekordbox", "jobs", "name"])
        guard let out = o["out"] else { fail("--out <name>.deckiecrate is required\n\(usage)", code: 2) }
        var output = url(out)
        if output.pathExtension != "deckiecrate" { output = output.appendingPathExtension("deckiecrate") }
        let options = BuildOptions(folder: url(folder), output: output, rekordbox: o["rekordbox"].map(url), jobs: jobs(o),
                                   fileBPMTags: o["bpm-tags"] != nil, fresh: o["fresh"] != nil, name: o["name"])
        let builder = try Builder(options: options)
        say("\(Builder.programLabel), engine \(Builder.engineLabel) on \(Analysis.platform); work folder "
            + options.workFolder.path)
        if let note = Builder.vocalTaggerNote { say(note) }
        let result = try builder.run(progress: { say(ProgressText.line($0)) })
        say("")
        FileHandle.standardOutput.write(Data(result.summary.utf8))
    }
} catch {
    fail("\(error)")
}
