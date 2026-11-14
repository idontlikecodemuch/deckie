// deckie-sound-trial: "Look up songs by sound" (the note on D30) measured on a folder of music: each file fingerprinted
// here by DeckieChroma, and that fingerprint asked of AcoustID. A development tool, run only on recordings that may be
// sent (public ones), never on a DJ's music without the owner's say-so. The only thing sent is the fingerprint and
// the file's length, at AcoustID's three requests a second; the key comes from DECKIE_ACOUSTID_KEY and is never shown.
//
//   deckie-sound-trial print <file> [--raw]
//       The file's length and fingerprint, as `fpcalc` prints them (DURATION=, FINGERPRINT=). Nothing is sent.
//   deckie-sound-trial compare <folder> --fpcalc <path to fpcalc> [--out <file under .scratch/>]
//       For each file, the share of bits that differ between DeckieChroma's raw fingerprint and `fpcalc -raw`'s.
//       Nothing is sent.
//   deckie-sound-trial lookup <folder> --out <file under .scratch/> [--fpcalc <path>] [--limit N]
//       Each file's fingerprint asked of AcoustID; with --fpcalc, fpcalc's fingerprint of the same file is asked too,
//       and the two answers compared. Counts printed:
//         files           files read
//         answered        files AcoustID gave at least one recording for
//         scores          the best match's score, by tenths
//         judged          files whose tags (or, without tags, whose name "Artist - Title") give a title
//         agree           judged files whose best recording agrees with that title and artist (the MusicBrainz
//                         trial's measure: the title without its version the same, one artist inside the other)
//         sameAnswer      with --fpcalc: files where both fingerprints give the same best recording (or both none)
//       Per-file detail goes only to the --out file, which must be under a `.scratch` folder.
import Foundation
import DeckieChroma
import DeckieLookup
import DeckieBuild
import DeckieDecode
import DeckieDesk
import DeckieCrate

func fail(_ s: String) -> Never { FileHandle.standardError.write(Data(("deckie-sound-trial: " + s + "\n").utf8)); exit(2) }
func note(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

var args = Array(CommandLine.arguments.dropFirst())
guard let mode = args.first else {
    fail("usage: deckie-sound-trial print <file> [--raw] | compare <folder> --fpcalc <path> [--out <file>] | lookup <folder> --out <file> [--fpcalc <path>] [--limit N]")
}
args.removeFirst()
var out: String? = nil, fpcalc: String? = nil, limit = Int.max, raw = false, target: String? = nil
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--out": out = args.isEmpty ? nil : args.removeFirst()
    case "--fpcalc": fpcalc = args.isEmpty ? nil : args.removeFirst()
    case "--limit": limit = args.isEmpty ? limit : (Int(args.removeFirst()) ?? limit)
    case "--raw": raw = true
    default: target = a
    }
}
guard let target else { fail("no file or folder given") }
let targetURL = URL(fileURLWithPath: (target as NSString).expandingTildeInPath)
let outURL: URL? = out.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath).standardizedFileURL }
if let outURL, !outURL.path.contains("/.scratch/") { fail("--out must be a file under a .scratch folder") }

/// fpcalc's own fingerprint of a file: its raw frames, its compressed form and its length.
@MainActor func runFpcalc(_ file: URL, raw: Bool) -> (frames: [UInt32], compressed: String, duration: Int)? {
    guard let fpcalc else { return nil }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: (fpcalc as NSString).expandingTildeInPath)
    p.arguments = (raw ? ["-raw"] : []) + [file.path]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    let text = String(decoding: data, as: UTF8.self)
    var duration = 0, fp = ""
    for line in text.split(separator: "\n") {
        if line.hasPrefix("DURATION=") { duration = Int(line.dropFirst(9)) ?? 0 }
        if line.hasPrefix("FINGERPRINT=") { fp = String(line.dropFirst(12)) }
    }
    guard !fp.isEmpty else { return nil }
    if raw { return (fp.split(separator: ",").compactMap { UInt32($0) }, "", duration) }
    return ([], fp, duration)
}

@MainActor func write<T: Encodable>(_ value: T) {
    guard let outURL else { return }
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    e.dateEncodingStrategy = .iso8601
    do { try DeckieFiles.write(try e.encode(value), to: outURL) } catch { fail("could not write \(outURL.path): \(error)") }
    print("detail in \(outURL.path)")
}

@MainActor func audioFiles(_ folder: URL) -> [SourceFile] {
    let files = (try? AudioFiles.find(in: folder)) ?? []
    guard !files.isEmpty else { fail("no audio files below \(folder.path)") }
    return Array(files.prefix(limit))
}

switch mode {
case "print":
    do {
        let f = try Chromaprint.fingerprint(file: targetURL)
        print("DURATION=\(f.duration)")
        print("FINGERPRINT=" + (raw ? f.frames.map(String.init).joined(separator: ",") : f.compressed))
    } catch { fail("could not read \(targetURL.path): \(error)") }

case "compare":
    guard fpcalc != nil else { fail("compare needs --fpcalc") }
    struct Row: Encodable { var file: String; var frames: Int; var fpcalcFrames: Int; var bitsDiffering: Double; var duration: Int; var fpcalcDuration: Int }
    var rows: [Row] = []
    var bits = 0, total = 0
    for f in audioFiles(targetURL) {
        guard let mine = try? Chromaprint.fingerprint(file: f.url) else { note("  could not decode \(f.rel)"); continue }
        guard let theirs = runFpcalc(f.url, raw: true) else { note("  fpcalc could not read \(f.rel)"); continue }
        let n = min(mine.frames.count, theirs.frames.count)
        var d = 0
        for i in 0..<n { d += (mine.frames[i] ^ theirs.frames[i]).nonzeroBitCount }
        bits += d; total += n * 32
        let share = n > 0 ? Double(d) / Double(n * 32) : 1
        rows.append(Row(file: f.rel, frames: mine.frames.count, fpcalcFrames: theirs.frames.count, bitsDiffering: share,
                        duration: mine.duration, fpcalcDuration: theirs.duration))
        print(String(format: "%6.3f%%  %4d / %4d frames  ", share * 100, mine.frames.count, theirs.frames.count) + f.rel)
    }
    print(String(format: "files: %d, bits differing over all: %.3f%%", rows.count, total > 0 ? Double(bits) / Double(total) * 100 : 0))
    write(rows)

case "lookup":
    guard outURL != nil else { fail("lookup needs --out <file under .scratch/>") }
    let client: AcoustID
    switch AcoustID.fromEnvironment(version: "trial") {
    case .success(let c): client = c
    case .failure(let f): fail(f.description)
    }
    struct Best: Encodable, Equatable { var recording: String?; var title: String?; var artist: String?; var score: Double }
    struct Row: Encodable {
        var file: String
        var duration: Int
        var judgedTitle: String?
        var judgedArtist: String?
        var judgedFrom: String?
        var matches: [AcoustIDMatch]
        var best: Best?
        var agree: Bool?
        var failure: String?
        var fpcalcBest: Best?
        var fpcalcFailure: String?
        var sameAnswer: Bool?
        var bitsDiffering: Double?
    }
    func best(_ m: [AcoustIDMatch]) -> Best? {
        guard let top = m.first(where: { !$0.recordings.isEmpty }) else { return nil }
        let r = top.recordings[0]
        return Best(recording: r.id, title: r.title, artist: r.artist, score: top.score)
    }
    func agrees(_ b: Best, title: String, artist: String?) -> Bool {
        let split = DeskNaming.splitVersion(title)
        let sameTitle = DeskLookup.norm(split.title) == DeskLookup.norm(DeskNaming.splitVersion(b.title ?? "").title)
        let ta = DeskLookup.norm(artist), ca = DeskLookup.norm(b.artist)
        let sameArtist = ta.isEmpty || (!ca.isEmpty && (ta.contains(ca) || ca.contains(ta)))
        return sameTitle && sameArtist
    }
    let files = audioFiles(targetURL)
    note("deckie-sound-trial: \(files.count) files; at most three lookups a second\(fpcalc != nil ? ", twice each (ours and fpcalc's)" : "")")
    var rows: [Row] = []
    var counts: [String: Int] = ["files": 0, "answered": 0, "judged": 0, "agree": 0, "sameAnswer": 0, "fpcalcAnswered": 0,
                                 "fpcalcAgree": 0, "failed": 0]
    var scores = [Int](repeating: 0, count: 11)
    for (i, f) in files.enumerated() {
        guard let mine = try? Chromaprint.fingerprint(file: f.url) else { note("  could not decode \(f.rel)"); continue }
        counts["files", default: 0] += 1
        let tags = FileTags.read(f.url)
        var title = tags.title.flatMap { SongName.isUsableTitle($0) ? $0 : nil }
        var artist = tags.artist
        var from: String? = title != nil ? "tags" : nil
        if title == nil {
            let stem = f.url.deletingPathExtension().lastPathComponent
            let parts = stem.components(separatedBy: " - ")
            if parts.count >= 2 { artist = parts[parts.count - 2]; title = parts[parts.count - 1]; from = "name" }
        }
        var row = Row(file: f.rel, duration: mine.duration, judgedTitle: title, judgedArtist: artist, judgedFrom: from, matches: [])
        do {
            row.matches = try client.lookup(fingerprint: mine.compressed, duration: mine.duration)
            row.best = best(row.matches)
        } catch {
            row.failure = "\(error)"
            counts["failed", default: 0] += 1
        }
        if let b = row.best {
            counts["answered", default: 0] += 1
            scores[min(10, Int(b.score * 10))] += 1
        }
        if let t = title {
            counts["judged", default: 0] += 1
            if let b = row.best {
                row.agree = agrees(b, title: t, artist: artist)
                if row.agree == true { counts["agree", default: 0] += 1 }
            } else {
                row.agree = false
            }
        }
        if fpcalc != nil, let theirs = runFpcalc(f.url, raw: false) {
            if let d = Chromaprint.decompress(theirs.compressed) {
                row.bitsDiffering = Chromaprint.bitDifference(mine.frames, d.frames)
            }
            do {
                let m = try client.lookup(fingerprint: theirs.compressed, duration: theirs.duration)
                row.fpcalcBest = best(m)
            } catch { row.fpcalcFailure = "\(error)" }
            if row.fpcalcBest != nil { counts["fpcalcAnswered", default: 0] += 1 }
            if let t = title, let b = row.fpcalcBest, agrees(b, title: t, artist: artist) { counts["fpcalcAgree", default: 0] += 1 }
            row.sameAnswer = row.best?.recording == row.fpcalcBest?.recording
            if row.sameAnswer == true { counts["sameAnswer", default: 0] += 1 }
        }
        rows.append(row)
        if (i + 1) % 5 == 0 || i + 1 == files.count { note("  \(i + 1) of \(files.count), \(counts["answered"] ?? 0) answered") }
    }
    struct Results: Encodable { var when: Date; var counts: [String: Int]; var bestScoreByTenths: [Int]; var files: [Row] }
    let order = ["files", "answered", "judged", "agree", "failed"] + (fpcalc != nil ? ["fpcalcAnswered", "fpcalcAgree", "sameAnswer"] : [])
    print(order.map { "\($0): \(counts[$0] ?? 0)" }.joined(separator: ", "))
    print("best score by tenths (0.0-0.1 ... 1.0): " + scores.map(String.init).joined(separator: " "))
    write(Results(when: Date(), counts: counts, bestScoreByTenths: scores, files: rows))

default:
    fail("unknown mode \(mode): print, compare or lookup")
}
