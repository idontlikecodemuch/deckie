// deckie-lookup-trial: "Look up songs via MusicBrainz" (D36, D39) measured on a folder of music. A development tool,
// run only on the owner's say-so, on his own computer: the results file stays where he puts it, and the only thing
// sent anywhere is what Desk's own lookup sends for each song (its title, artist and release words, or the words of
// its file name; never its path), at MusicBrainz's one request a second, with Desk's own User-Agent.
//
//   deckie-lookup-trial <music folder> --out <results.json> [--limit N] [--use-tags] [--labels] [--cache <folder>]
//                       [--no-second-ask]
//   deckie-lookup-trial --rescore <old results.json> --out <results.json>
//
// With tags hidden (the default) each song is named as Desk names a file with no tags: from its file name and its
// folder (`LocalFacts.nameFromFile`). With --use-tags, from its title and artist tags, with the facts its file's tags
// carry (release, year, the compilation mark and the rest, as Desk reads them). Either way the candidate Desk would
// choose is compared with the file's own tags, the way a DJ would judge it (D39; research AC, 5.3 suggestion 8):
//
//   agree          the same song: the title by whole words, the credit by whole names, the version by kind
//   originalFound  the original of the DJ's version (an intro, a short edit, a DJ's edit), as Desk said it was
//   wrongVersion   the same title and credit, another version by kind
//   wrong          another title or another credit
//
// and the old strict compare is kept beside it (`oldVerdict`). Each automatic fill records the rules that let it
// through (`rules`), so a wrong fill can be traced to one. The default choices are applied to a copy of the songs and
// any name that changed is counted (`namesChanged`, which must be 0). Clean or dirty, as Desk reads it, is counted by
// where it came from. --cache keeps every answer by its address (and each file's length), so a run again asks only
// what it has not asked; the answers stay in that folder. A song MusicBrainz says is busy for is waited for and asked
// again; a refusal ends the run, with what was found kept. --rescore applies the new compare to an older results file.
// Nothing is written but the results file and the cache (through DeckieFiles). DECKIE_LOOKUP_RECORDED answers from
// recorded files.
import Foundation
import DeckieCrate
import DeckieBuild
import DeckieDecode
import DeckieDesk
import DeckieLookup

func fail(_ s: String) -> Never { FileHandle.standardError.write(Data(("deckie-lookup-trial: " + s + "\n").utf8)); exit(2) }
func say(_ s: String) { FileHandle.standardError.write(Data((s + "\n").utf8)) }

var args = Array(CommandLine.arguments.dropFirst())
var out: String? = nil, limit = Int.max, useTags = false, labels = false, cachePath: String? = nil, rescore: String? = nil
var secondAsk = true
var folder: String? = nil
while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "--out": out = args.isEmpty ? nil : args.removeFirst()
    case "--limit": limit = args.isEmpty ? limit : (Int(args.removeFirst()) ?? limit)
    case "--use-tags": useTags = true
    case "--labels": labels = true
    case "--cache": cachePath = args.isEmpty ? nil : args.removeFirst()
    case "--rescore": rescore = args.isEmpty ? nil : args.removeFirst()
    case "--no-second-ask": secondAsk = false
    default: folder = a
    }
}
guard let out else { fail("usage: deckie-lookup-trial <music folder> --out <results.json> [--limit N] [--use-tags] [--labels] [--cache <folder>] | --rescore <old.json> --out <results.json>") }

// MARK: the compare a DJ would make (D39)

/// A chosen candidate against the file's own tags: the title by whole words, the credit by whole names, the version
/// by kind. `mode` is the lookup's (`original` when Desk said this is the original of the song's version).
func verdict(tagTitle: String, tagArtist: String?, title: String, version: String?, artist: String?, credited: [String]?,
             featuring: [Bool]?, mode: String?) -> String {
    let tag = NameReading.readTags(title: tagTitle, artist: tagArtist)
    let cand = NameReading.readTitle(title)
    let sameTitle = NameReading.compareWords(tag.title) == NameReading.compareWords(cand.title)
    let dj = NameReading.compareWords([tag.artist, tag.featured].compactMap { $0 }.joined(separator: " "))
    let names = credited?.isEmpty == false ? credited! : (artist.map { NameReading.credit($0).map(\.name) } ?? [])
    var sameArtist = dj.isEmpty
    if !dj.isEmpty, let first = names.first, NameReading.containsWhole(NameReading.compareWords(first), in: dj) {
        let flags = featuring ?? NameReading.credit(artist ?? "").map(\.featuring)
        sameArtist = names.enumerated().dropFirst().allSatisfy { i, n in
            (i < flags.count && flags[i]) || NameReading.containsWhole(NameReading.compareWords(n), in: dj)
        } && NameReading.containsWhole(NameReading.compareWords(tag.firstArtist ?? tag.artist), in: NameReading.compareWords(artist ?? names.joined(separator: " ")))
    }
    guard sameTitle && sameArtist else { return "wrong" }
    if mode == "original" { return "originalFound" }
    let cv = (version.map(NameReading.readVersion)).map { $0.merged(cand.version) } ?? cand.version
    let m = VersionCompare.compare(song: tag.version, candidate: cv, fits: true)
    return m.chooses ? "agree" : (m == .original ? "originalFound" : "wrongVersion")
}

/// The old strict compare (letter AA2): the title after its last bracket, the artist by "contains", the version by
/// the old markers.
func oldVerdict(tagTitle: String, tagArtist: String?, title: String, version: String?, artist: String?) -> String {
    let tagSplit = DeskNaming.splitVersion(tagTitle)
    let sameTitle = DeskLookup.norm(tagSplit.title) == DeskLookup.norm(title)
    let ta = DeskLookup.norm(tagArtist), ca = DeskLookup.norm(artist)
    let sameArtist = ta.isEmpty || (!ca.isEmpty && (ta.contains(ca) || ca.contains(ta)))
    guard sameTitle && sameArtist else { return "wrong" }
    return DeskLookup.markers(tagSplit.version) == DeskLookup.markers(version) ? "agree" : "wrongVersion"
}

// MARK: --rescore

if let rescore {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: (rescore as NSString).expandingTildeInPath)),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let rows = obj["songs"] as? [[String: Any]] else {
        fail("could not read \(rescore)")
    }
    var counts: [String: Int] = ["songs": rows.count, "chosen": 0, "found": 0, "agree": 0, "originalFound": 0, "wrongVersion": 0, "wrong": 0, "noTags": 0]
    var outRows: [[String: Any]] = []
    for r in rows {
        if (r["outcome"] as? String) == "found" { counts["found", default: 0] += 1 }
        guard r["chosen"] as? Bool == true else { continue }
        counts["chosen", default: 0] += 1
        guard let tt = r["tagTitle"] as? String, SongName.isUsableTitle(tt) else { counts["noTags", default: 0] += 1; continue }
        // The old tool split the candidate's last bracket off as its version: put it back and read it again.
        let t0 = r["candidate"] as? String ?? "", v0 = r["candidateVersion"] as? String
        let whole = v0.map { "\(t0) (\($0))" } ?? t0
        let v = verdict(tagTitle: tt, tagArtist: r["tagArtist"] as? String, title: whole,
                        version: nil, artist: r["candidateArtist"] as? String, credited: nil,
                        featuring: nil, mode: nil)
        counts[v, default: 0] += 1
        var row = r; row["newVerdict"] = v
        outRows.append(row)
    }
    let result: [String: Any] = ["rescored": rescore, "counts": counts, "chosenRows": outRows]
    guard let d = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) else { fail("could not encode") }
    do { try DeckieFiles.write(d, to: URL(fileURLWithPath: (out as NSString).expandingTildeInPath)) } catch { fail("could not write \(out)") }
    print(["songs", "found", "chosen", "noTags", "agree", "originalFound", "wrongVersion", "wrong"].map { "\($0): \(counts[$0] ?? 0)" }.joined(separator: ", "))
    exit(0)
}

// MARK: the answers kept, so a run again asks only what it has not asked

/// MusicBrainz's answers kept by their address in `folder`; a request not kept yet waits its turn at the shared gate
/// (one a second) and goes out through the system's own transport. Only answers that say something are kept (200 and
/// 404); a busy answer is never kept.
final class KeptAnswers: LookupTransport, @unchecked Sendable {
    let folder: URL
    let inner: LookupTransport
    private let lock = NSLock()
    private var index: [String: String]
    var asked = 0, kept = 0

    init(folder: URL, inner: LookupTransport) {
        self.folder = folder; self.inner = inner
        index = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: folder.appendingPathComponent("index.json")))) ?? [:]
    }
    var available: Bool { inner.available }

    func send(_ request: LookupRequest) throws -> LookupResponse {
        let key = request.url.absoluteString
        lock.lock(); let file = index[key]; lock.unlock()
        if let file, let body = try? Data(contentsOf: folder.appendingPathComponent(file)) {
            lock.lock(); kept += 1; lock.unlock()
            return LookupResponse(status: file.hasPrefix("404-") ? 404 : 200, body: body)
        }
        try MusicBrainzGate.shared.wait()
        let r = try inner.send(request)
        lock.lock(); asked += 1; lock.unlock()
        if r.status == 200 || r.status == 404 {
            lock.lock()
            let name = (r.status == 404 ? "404-" : "") + String(format: "%06d.json", index.count + 1)
            index[key] = name
            let snapshot = index
            lock.unlock()
            try? DeckieFiles.write(r.body, to: folder.appendingPathComponent(name))
            if let d = try? JSONEncoder().encode(snapshot) { try? DeckieFiles.write(d, to: folder.appendingPathComponent("index.json")) }
        }
        return r
    }
}

// MARK: the songs

guard let folder else { fail("no music folder given") }
let root = URL(fileURLWithPath: (folder as NSString).expandingTildeInPath, isDirectory: true)
let files = (try? AudioFiles.find(in: root)) ?? []
guard !files.isEmpty else { fail("no audio files below \(root.path)") }
let chosenFiles = Array(files.prefix(limit))
let cacheURL = cachePath.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true) }

struct Row: Encodable {
    var file: String
    var seconds: Double
    var tagTitle: String?
    var tagArtist: String?
    /// What Desk had before the lookup (tags hidden: read from the file name and the folder).
    var title: String
    var artist: String?
    var version: String?
    var nameFrom: String?
    var folderKind: String?
    var sent: [[String]]
    var outcome: String
    var candidate: String?
    var candidateArtist: String?
    var candidateVersion: String?
    var candidateSeconds: Double?
    var fit: String?
    var chosen: Bool
    var mode: String?
    var rules: [String]?
    var askedAgain: Int
    var verdict: String?
    var oldVerdict: String?
    var askKind: String
    var failure: String?
    var several: Bool
    var candidates: Int
    var candidateRelease: String?
    var candidateYear: String?
    var candidateLabel: String?
    var candidateNotes: [String]
    var otherVersion: Bool?
    /// The fields Desk would fill by itself, and the names it would change (must be none).
    var filled: [String]
    var namesChanged: [String]
    var lyrics: String?
    var lyricsFrom: String?
    var tagFacts: [String: [String]]
}

say("deckie-lookup-trial: \(chosenFiles.count) songs; about \(chosenFiles.count) seconds of lookups at one request a second, plus reading each file's length")

// Each file's length (kept in the cache, as it takes a full decode).
var lengths: [String: Double] = [:]
let lengthsURL = cacheURL?.appendingPathComponent("lengths.json")
if let u = lengthsURL, let d = try? Data(contentsOf: u), let l = try? JSONDecoder().decode([String: Double].self, from: d) { lengths = l }

// The place number of each file: its position in its folder, in the order a player shows it.
var byFolder: [String: [Int]] = [:]
for (i, f) in chosenFiles.enumerated() { byFolder[CratePath.folder(of: f.rel), default: []].append(i) }
var placeNumber: [Int: Int] = [:]
for (_, ids) in byFolder {
    for (n, i) in ids.sorted(by: { chosenFiles[$0].rel.lowercased() < chosenFiles[$1].rel.lowercased() }).enumerated() { placeNumber[i] = n + 1 }
}

var tracks: [CrateTrack] = []
var tags: [String: FileTags] = [:]
var fileFacts: [String: [String: [String]]] = [:]
var allFacts: [String: [String: [String]]] = [:]
let factNames = [SongFacts.release, SongFacts.year, SongFacts.date, SongFacts.originalYear, SongFacts.label, SongFacts.compilation,
                 SongFacts.releaseArtist, SongFacts.lyrics]
for (i, f) in chosenFiles.enumerated() {
    let t = FileTags.read(f.url)
    let seconds: Double
    if let s = lengths[f.rel] { seconds = s } else {
        seconds = (try? AudioDecoder.decode(f.url)).map { Double($0.frames) / Double(max(1, $0.sampleRate)) } ?? 0
        lengths[f.rel] = seconds
    }
    let id = String(format: "%06d", i)
    let track = CrateTrack(id: id, file: .init(name: f.url.lastPathComponent, rel: f.rel, bytes: f.size, sha1Head: nil, durationS: seconds),
                           ident: .init(title: "", source: "filename", track: placeNumber[i]),
                           analysis: .init(engine: "trial", analysedAt: "", device: "", secs: 0, level: 0),
                           engine: .init(family: "trial", version: "0", platform: "", fidelity: 0, models: [], decoder: .init(name: "", version: "")))
    tracks.append(track)
    tags[id] = t
    let ff = FileFacts.read(f.url).facts
    allFacts[id] = ff
    fileFacts[id] = ff.filter { factNames.contains($0.key) }
}
if let u = lengthsURL, let d = try? JSONEncoder().encode(lengths) { try? DeckieFiles.write(d, to: u) }

// Named as Desk would name them: from the tags (with the file's facts), or from the file name and the folder alone.
var siblingsByFolder: [String: [LocalNames.Sibling]] = [:]
for (i, f) in chosenFiles.enumerated() {
    let id = tracks[i].id
    let stem = (f.url.lastPathComponent as NSString).deletingPathExtension
    let s = useTags
        ? LocalNames.Sibling(stem: stem, tagArtist: tags[id]?.artist, compilationMark: allFacts[id]?[SongFacts.compilation]?.first == "1",
                             releaseArtist: allFacts[id]?[SongFacts.releaseArtist]?.first)
        : LocalNames.Sibling(stem: stem)
    siblingsByFolder[CratePath.folder(of: f.rel), default: []].append(s)
}
var lyricsFrom: [String: (String, String)] = [:]
var folderKinds: [String: LocalNames.FolderReading] = [:]
for (i, f) in chosenFiles.enumerated() {
    let id = tracks[i].id
    let sib = siblingsByFolder[CratePath.folder(of: f.rel)] ?? []
    let fr = LocalNames.readFolder(CratePath.folder(of: f.rel).split(separator: "/").map(String.init), siblings: sib)
    folderKinds[id] = fr
    let stem = (f.url.lastPathComponent as NSString).deletingPathExtension
    if useTags {
        let t = tags[id] ?? FileTags()
        tracks[i].ident.title = t.title ?? ""
        tracks[i].ident.artist = t.artist
        tracks[i].ident.source = "tag"
        for (name, values) in allFacts[id] ?? [:] { tracks[i].ident.offer(name, .init(values, from: SongFacts.Origin.tag)) }
        // Clean or dirty as Desk reads it: the tags' advisory, the title and the grouping and comment, then the file name.
        if let l = allFacts[id]?[SongFacts.lyrics]?.first { lyricsFrom[id] = (l, "tagAdvisory") }
        else if let l = LocalFacts.lyrics(title: t.title, version: nil, grouping: allFacts[id]?[SongFacts.grouping],
                                          comment: allFacts[id]?[SongFacts.comment]) { lyricsFrom[id] = (l.rawValue, "tagWords") }
        else if let l = NameReading.readFileName(stem).lyrics { lyricsFrom[id] = (l.rawValue, "fileName") }
        if !LocalNames.isUsableTitle(tracks[i].ident.title) {
            let n = LocalFacts.nameFromFile(rel: f.rel, number: placeNumber[i], siblings: sib)
            tracks[i].ident.title = n.title; tracks[i].ident.version = n.version; tracks[i].ident.source = n.source
            if !LocalNames.isUsableArtist(tracks[i].ident.artist) { tracks[i].ident.artist = n.artist }
        }
    } else {
        let n = LocalFacts.nameFromFile(rel: f.rel, number: placeNumber[i], siblings: sib)
        tracks[i].ident.title = n.title
        tracks[i].ident.artist = n.artist
        tracks[i].ident.version = n.version
        tracks[i].ident.source = n.source
        if let l = NameReading.readFileName(stem, number: placeNumber[i]).lyrics { lyricsFrom[id] = (l.rawValue, "fileName") }
    }
}

// MARK: the lookup, one song at a time

let base = LookupTransports.forEnvironment()
let kept = cacheURL.map { KeptAnswers(folder: $0, inner: base) }
let client = kept.map { MusicBrainz(version: DeskLookup.appVersion, transport: $0, gate: MusicBrainzGate(interval: 0)) } ?? DeskLookup.client()
let songs = tracks.map { DeskNaming.Song(track: $0, facts: DeskNaming.facts($0, book: NameBook(), corrections: NameCorrections()),
                                         folder: folderKinds[$0.id]) }
let sentLock = NSLock()
nonisolated(unsafe) var sent: [SentRequest] = []
let started = Date()
var results: [DeskLookup.SongResult] = []
var asks: [DeskLookup.Ask] = []
var refused = false
var busyWaits = 0
for (i, song) in songs.enumerated() {
    let plan = DeskLookup.plan([song])
    asks.append(plan.asks[0])
    var result: DeskLookup.SongResult? = nil
    if !refused {
        for attempt in 0..<6 {
            let run = DeskLookupRun(plan: plan, client: client, sent: { r in sentLock.lock(); sent.append(r); sentLock.unlock() })
            run.fetchLabels = labels
            run.secondAsk = secondAsk
            let review = run.run()
            let r = review.songs[0]
            if r.failure == "busy" || r.failure == "noConnection" {
                busyWaits += 1
                say("  busy at song \(i + 1) (attempt \(attempt + 1)); waiting a minute")
                Thread.sleep(forTimeInterval: 60)
                result = r
                continue
            }
            if r.failure == "refused" { refused = true; say("  MusicBrainz refused a request: stopping") }
            result = r
            break
        }
    }
    results.append(result ?? DeskLookup.SongResult(song: song.track.id, title: song.track.ident.title, seconds: song.track.file.durationS,
                                                   ask: plan.asks[0], outcome: "notAsked", failure: nil, candidates: [], chosen: nil, several: false))
    if (i + 1) % 10 == 0 || i + 1 == songs.count {
        say("  \(i + 1) of \(songs.count), \(results.filter { $0.outcome == "found" }.count) found, \(results.filter { $0.chosen != nil }.count) chosen")
    }
}

// MARK: scoring

var rows: [Row] = []
var counts: [String: Int] = ["songs": tracks.count, "noTags": 0, "nothingToSend": 0, "found": 0, "chosen": 0, "agree": 0,
                             "originalFound": 0, "wrongVersion": 0, "wrong": 0, "failed": 0, "notAsked": 0, "namesChanged": 0,
                             "oldAgree": 0, "oldWrongVersion": 0, "oldWrong": 0, "askedAgain": 0, "foundOnSecondAsk": 0]
var byRule: [String: [String: Int]] = [:]
var lyricsCounts: [String: Int] = [:]
var folderCounts: [String: Int] = [:]
var fieldCounts: [String: Int] = [:]
for (i, s) in results.enumerated() {
    let id = s.song
    let t = tags[id] ?? FileTags()
    let tagTitle = t.title.flatMap { SongName.isUsableTitle($0) ? $0 : nil }
    if tagTitle == nil { counts["noTags", default: 0] += 1 }
    switch s.outcome {
    case "nothingToSend": counts["nothingToSend", default: 0] += 1
    case "failed": counts["failed", default: 0] += 1
    case "notAsked": counts["notAsked", default: 0] += 1
    case "found": counts["found", default: 0] += 1
    default: break
    }
    if (s.askedAgain ?? 0) > 0 { counts["askedAgain", default: 0] += 1; if s.outcome == "found" { counts["foundOnSecondAsk", default: 0] += 1 } }
    let pick = s.chosen.map { s.candidates[$0] } ?? s.candidates.first
    var v: String? = nil, ov: String? = nil
    if let c = pick, s.chosen != nil {
        counts["chosen", default: 0] += 1
        if let title = tagTitle {
            v = verdict(tagTitle: title, tagArtist: t.artist, title: c.title, version: c.version, artist: c.artist, credited: c.credited,
                        featuring: c.featuring, mode: s.mode)
            ov = oldVerdict(tagTitle: title, tagArtist: t.artist, title: c.title, version: c.version, artist: c.artist)
            counts[v!, default: 0] += 1
            counts["old" + ov!.prefix(1).uppercased() + ov!.dropFirst(), default: 0] += 1
            for rule in s.rules ?? [] { byRule[rule, default: [:]][v!, default: 0] += 1 }
        }
    }
    // The default choices applied to a copy: which fields fill, and whether any name changed.
    var filled: [String] = [], changedNames: [String] = []
    if s.chosen != nil {
        let review = DeskLookup.Review(scope: "song", source: nil, songs: [s], stopped: false, failure: nil, requests: 0, discMatch: nil)
        var c = Crate(manifest: CrateManifest(crateId: "trial", name: "trial", createdAt: "", devicesSeen: []), tracks: [tracks[i]])
        var corrections = NameCorrections(), book = NameBook()
        let choices = DeskLookup.defaultChoices(review)
        filled = choices.first?.fields ?? []
        DeskLookup.apply(review, choices, to: &c, corrections: &corrections, book: &book)
        let before = tracks[i].ident, after = c.tracks[0].ident
        if LocalNames.isUsableTitle(before.title) && before.title != after.title { changedNames.append("title") }
        if LocalNames.isUsableArtist(before.artist) && before.artist != after.artist { changedNames.append("artist") }
        if !(before.version ?? "").isEmpty && before.version != after.version { changedNames.append("version") }
        if before.facts[SongFacts.genre] != after.facts[SongFacts.genre] || before.facts[SongFacts.lyrics] != after.facts[SongFacts.lyrics] {
            changedNames.append("genreOrLyrics")
        }
        for f in filled { fieldCounts[f, default: 0] += 1 }
    }
    if !changedNames.isEmpty { counts["namesChanged", default: 0] += 1 }
    if let l = lyricsFrom[id] { lyricsCounts[l.1 + ":" + l.0, default: 0] += 1 }
    let fk = folderKinds[id]
    folderCounts[(fk?.kind.rawValue ?? "none") + (fk?.severalArtists == true ? "+several" : ""), default: 0] += 1
    if tracks[i].ident.source == "filename+folder" { folderCounts["artistFromFolder:" + (fk?.kind.rawValue ?? "none"), default: 0] += 1 }
    let ask = asks[i]
    rows.append(Row(file: chosenFiles[i].rel, seconds: s.seconds, tagTitle: t.title, tagArtist: t.artist,
                    title: tracks[i].ident.title, artist: tracks[i].ident.artist, version: tracks[i].ident.version,
                    nameFrom: tracks[i].ident.source, folderKind: fk?.kind.rawValue,
                    sent: (ask.isrc.map { [["isrc", $0]] } ?? []) + (ask.query?.fields ?? []), outcome: s.outcome,
                    candidate: pick?.title, candidateArtist: pick?.artist, candidateVersion: pick?.version,
                    candidateSeconds: pick?.seconds, fit: pick?.fit, chosen: s.chosen != nil, mode: s.mode, rules: s.rules,
                    askedAgain: s.askedAgain ?? 0, verdict: v, oldVerdict: ov,
                    askKind: ask.kind, failure: s.failure, several: s.several, candidates: s.candidates.count,
                    candidateRelease: pick?.release, candidateYear: pick?.year, candidateLabel: pick?.label,
                    candidateNotes: pick?.notes ?? [], otherVersion: pick?.otherVersion, filled: filled, namesChanged: changedNames,
                    lyrics: lyricsFrom[id]?.0, lyricsFrom: lyricsFrom[id]?.1, tagFacts: fileFacts[id] ?? [:]))
}
counts["requests"] = sent.count
counts["sentToMusicBrainz"] = kept?.asked ?? sent.count
counts["answeredFromCache"] = kept?.kept ?? 0
counts["busyWaits"] = busyWaits
counts["busyAnswers"] = sent.filter { $0.answer == "busy" }.count

struct Results: Encodable {
    var folder: String
    var when: Date
    var minutes: Double
    var tagsHidden: Bool
    var labels: Bool
    var secondAsk: Bool
    var refused: Bool
    var allowanceSeconds: Double
    var counts: [String: Int]
    var byRule: [String: [String: Int]]
    var lyrics: [String: Int]
    var folders: [String: Int]
    var filledFields: [String: Int]
    var songs: [Row]
    var sent: [SentRequest]
}
let results_ = Results(folder: root.path, when: started, minutes: Date().timeIntervalSince(started) / 60, tagsHidden: !useTags, labels: labels,
                       secondAsk: secondAsk, refused: refused, allowanceSeconds: DeskLookup.allowance, counts: counts, byRule: byRule,
                       lyrics: lyricsCounts, folders: folderCounts, filledFields: fieldCounts, songs: rows, sent: sent)
let e = JSONEncoder()
e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
e.dateEncodingStrategy = .iso8601
do {
    try DeckieFiles.write(try e.encode(results_), to: URL(fileURLWithPath: (out as NSString).expandingTildeInPath))
} catch { fail("could not write \(out): \(error)") }
let order = ["songs", "noTags", "nothingToSend", "found", "chosen", "agree", "originalFound", "wrongVersion", "wrong", "oldAgree",
             "oldWrongVersion", "oldWrong", "namesChanged", "askedAgain", "foundOnSecondAsk", "failed", "notAsked", "requests",
             "sentToMusicBrainz", "answeredFromCache", "busyAnswers", "busyWaits"]
print(order.map { "\($0): \(counts[$0] ?? 0)" }.joined(separator: ", "))
print("by rule: \(byRule.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))" }.joined(separator: "; "))")
print("lyrics: \(lyricsCounts.sorted { $0.key < $1.key })")
print("folders: \(folderCounts.sorted { $0.key < $1.key })")
print("filled: \(fieldCounts.sorted { $0.key < $1.key })")
print("results in \(out)")
