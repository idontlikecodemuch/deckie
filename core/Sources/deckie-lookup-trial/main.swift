// deckie-lookup-trial: "Look up songs via MusicBrainz" (D36) measured on a folder of music, with the files' own tags
// hidden from the lookup. A development tool, run only on the owner's say-so, on his own computer: the results file
// stays where he puts it, and the only thing sent anywhere is what Desk's own lookup sends for a song with no tags
// (the words of its file name, never its path), at MusicBrainz's one request a second.
//
//   deckie-lookup-trial <music folder> --out <results.json> [--limit N] [--use-tags] [--labels]
//
// For each audio file below the folder: its tags (title, artist) and its length are read here; the lookup is given
// only the file name, as if the file had no tags (with --use-tags, the tags as Desk would send them instead); the
// candidate Desk would choose (or, when it chooses none, the first shown) is compared with the tags. With --labels, the
// label of the chosen candidate's release is asked for too (one more request a chosen song), as Desk itself does.
// Each row also keeps what the file's tags say of release, year and label (FileFacts) beside the candidate's, so
// what a lookup would fill can be compared with what the file already has. Counts:
//   songs             audio files read
//   noTags            files with no title tag (they cannot be judged; still looked up)
//   nothingToSend     files whose name says nothing ("Track 04"): not looked up
//   found             songs with at least one candidate
//   chosen            songs where Desk would fill in a candidate by itself (one fits by length and agrees)
//   agree             chosen candidates whose title and artist agree with the tags
//   wrongVersion      chosen candidates that agree on title and artist but whose version differs from the tags'
//   wrong             chosen candidates whose title or artist disagrees with the tags
//   requests          requests sent, and every one of them is in the results file (`sent`)
// Nothing is written but the results file (through DeckieFiles). DECKIE_LOOKUP_RECORDED answers from recorded files.
import Foundation
import DeckieCrate
import DeckieBuild
import DeckieDecode
import DeckieDesk
import DeckieLookup

func fail(_ s: String) -> Never { FileHandle.standardError.write(Data(("deckie-lookup-trial: " + s + "\n").utf8)); exit(2) }

var args = Array(CommandLine.arguments.dropFirst())
var out: String? = nil, limit = Int.max, useTags = false, labels = false
var folder: String? = nil
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--out": out = args.isEmpty ? nil : args.removeFirst()
    case "--limit": limit = args.isEmpty ? limit : (Int(args.removeFirst()) ?? limit)
    case "--use-tags": useTags = true
    case "--labels": labels = true
    default: folder = a
    }
}
guard let folder, let out else { fail("usage: deckie-lookup-trial <music folder> --out <results.json> [--limit N] [--use-tags] [--labels]") }
let root = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
let files = (try? AudioFiles.find(in: root)) ?? []
guard !files.isEmpty else { fail("no audio files below \(root.path)") }
let chosenFiles = Array(files.prefix(limit))

struct Row: Encodable {
    var file: String
    var seconds: Double
    var tagTitle: String?
    var tagArtist: String?
    var sent: [[String]]
    var outcome: String
    var candidate: String?
    var candidateArtist: String?
    var candidateVersion: String?
    var candidateSeconds: Double?
    var fit: String?
    var chosen: Bool
    var verdict: String?
    var askKind: String
    var failure: String?
    var several: Bool
    var candidates: Int
    var candidateRelease: String?
    var candidateYear: String?
    var candidateLabel: String?
    var candidateNotes: [String]
    var otherVersion: Bool?
    /// What the file's own tags say (FileFacts): release, year, date, original year, label, compilation.
    var tagFacts: [String: [String]]
}

FileHandle.standardError.write(Data("deckie-lookup-trial: \(chosenFiles.count) songs; about \(chosenFiles.count) seconds of lookups at one request a second, plus reading each file's length\n".utf8))

// The songs as Desk would have them with no tags: no title (so the file name is what is sent), the length read here.
var tracks: [CrateTrack] = []
var tags: [String: FileTags] = [:]
var fileFacts: [String: [String: [String]]] = [:]
let factNames = [SongFacts.release, SongFacts.year, SongFacts.date, SongFacts.originalYear, SongFacts.label, SongFacts.compilation]
for (i, f) in chosenFiles.enumerated() {
    let t = FileTags.read(f.url)
    let seconds = (try? AudioDecoder.decode(f.url)).map { Double($0.frames) / Double(max(1, $0.sampleRate)) } ?? 0
    let id = String(format: "%06d", i)
    var track = CrateTrack(id: id, file: .init(name: f.url.lastPathComponent, rel: nil, bytes: f.size, sha1Head: nil, durationS: seconds),
                           ident: .init(title: "", source: "filename"),
                           analysis: .init(engine: "trial", analysedAt: "", device: "", secs: 0, level: 0),
                           engine: .init(family: "trial", version: "0", platform: "", fidelity: 0, models: [], decoder: .init(name: "", version: "")))
    if useTags {
        track.ident.title = t.title ?? ""
        track.ident.artist = t.artist
    }
    tracks.append(track)
    tags[id] = t
    let ff = FileFacts.read(f.url).facts
    fileFacts[id] = ff.filter { factNames.contains($0.key) }
}

let songs = tracks.map { DeskNaming.Song(track: $0, facts: DeskNaming.facts($0, book: NameBook(), corrections: NameCorrections())) }
let plan = DeskLookup.plan(songs)
let sentLock = NSLock()
nonisolated(unsafe) var sent: [SentRequest] = []
let run = DeskLookupRun(plan: plan, client: DeskLookup.client(), sent: { r in sentLock.lock(); sent.append(r); sentLock.unlock() })
run.fetchLabels = labels
let started = Date()
let review = run.run { p in
    if p.done % 10 == 0 || p.done == p.total {
        FileHandle.standardError.write(Data("  \(p.done) of \(p.total), \(p.found) found\n".utf8))
    }
}

var rows: [Row] = []
var counts: [String: Int] = ["songs": tracks.count, "noTags": 0, "nothingToSend": 0, "found": 0, "chosen": 0, "agree": 0,
                             "wrongVersion": 0, "wrong": 0, "failed": 0]
for (i, s) in review.songs.enumerated() {
    let t = tags[s.song] ?? FileTags()
    let tagTitle = t.title.flatMap { SongName.isUsableTitle($0) ? $0 : nil }
    if tagTitle == nil { counts["noTags", default: 0] += 1 }
    if s.outcome == "nothingToSend" { counts["nothingToSend", default: 0] += 1 }
    if s.outcome == "failed" { counts["failed", default: 0] += 1 }
    if s.outcome == "found" { counts["found", default: 0] += 1 }
    let pick = s.chosen.map { s.candidates[$0] } ?? s.candidates.first
    var verdict: String? = nil
    if let c = pick, s.chosen != nil {
        counts["chosen", default: 0] += 1
        if let title = tagTitle {
            let tagSplit = DeskNaming.splitVersion(title)
            let sameTitle = DeskLookup.norm(tagSplit.title) == DeskLookup.norm(c.title)
            let ta = DeskLookup.norm(t.artist), ca = DeskLookup.norm(c.artist)
            let sameArtist = ta.isEmpty || (!ca.isEmpty && (ta.contains(ca) || ca.contains(ta)))
            if sameTitle && sameArtist {
                let sameVersion = DeskLookup.markers(tagSplit.version) == DeskLookup.markers(c.version)
                verdict = sameVersion ? "agree" : "wrongVersion"
            } else {
                verdict = "wrong"
            }
            counts[verdict!, default: 0] += 1
        }
    }
    let ask = plan.asks[i]
    rows.append(Row(file: chosenFiles[i].rel, seconds: s.seconds, tagTitle: t.title, tagArtist: t.artist,
                    sent: (ask.isrc.map { [["isrc", $0]] } ?? []) + (ask.query?.fields ?? []), outcome: s.outcome,
                    candidate: pick?.title, candidateArtist: pick?.artist, candidateVersion: pick?.version,
                    candidateSeconds: pick?.seconds, fit: pick?.fit, chosen: s.chosen != nil, verdict: verdict,
                    askKind: ask.kind, failure: s.failure, several: s.several, candidates: s.candidates.count,
                    candidateRelease: pick?.release, candidateYear: pick?.year, candidateLabel: pick?.label,
                    candidateNotes: pick?.notes ?? [], otherVersion: pick?.otherVersion, tagFacts: fileFacts[s.song] ?? [:]))
}
counts["requests"] = sent.count

struct Results: Encodable {
    var folder: String
    var when: Date
    var minutes: Double
    var tagsHidden: Bool
    var labels: Bool
    var allowanceSeconds: Double
    var counts: [String: Int]
    var songs: [Row]
    var sent: [SentRequest]
}
let results = Results(folder: root.path, when: started, minutes: Date().timeIntervalSince(started) / 60, tagsHidden: !useTags, labels: labels,
                      allowanceSeconds: DeskLookup.allowance, counts: counts, songs: rows, sent: sent)
let e = JSONEncoder()
e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
e.dateEncodingStrategy = .iso8601
do {
    try DeckieFiles.write(try e.encode(results), to: URL(fileURLWithPath: (out as NSString).expandingTildeInPath))
} catch { fail("could not write \(out): \(error)") }
let order = ["songs", "noTags", "nothingToSend", "found", "chosen", "agree", "wrongVersion", "wrong", "failed", "requests"]
print(order.map { "\($0): \(counts[$0] ?? 0)" }.joined(separator: ", "))
print("results in \(out)")
