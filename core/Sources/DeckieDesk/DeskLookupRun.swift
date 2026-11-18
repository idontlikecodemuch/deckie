import Foundation
import DeckieCrate
import DeckieLookup

/// One lookup, going: the plan's songs one after another (or the disc), at the gate's pace of one request a second,
/// with a count as it goes, stoppable at any moment; what was found before a stop is kept. Both windows run it on a
/// thread of their own. Every request it makes is handed to `sent` as it is made ("What Desk has sent").
public final class DeskLookupRun: @unchecked Sendable {
    public let plan: DeskLookup.Plan
    private var client: MusicBrainz
    private let lock = NSLock()
    private var stopFlag = false
    private var requests = 0
    /// Whether the label of the release that fits is asked for (a second request a song). The trial leaves it out.
    public var fetchLabels = true
    /// Whether a song whose title and artist found nothing is asked once more with free words (D39). The trial turns
    /// it off to measure the lookup without it.
    public var secondAsk = true

    /// Progress: songs done, songs in all, songs with a candidate so far.
    public struct Progress: Sendable, Equatable {
        public var done: Int
        public var total: Int
        public var found: Int
    }

    public init(plan: DeskLookup.Plan, client: MusicBrainz, sent: @escaping @Sendable (SentRequest) -> Void) {
        self.plan = plan
        self.client = client
        self.client.stopped = { [weak self] in self?.isStopped ?? true }
        self.client.sent = { [weak self] r in self?.count(); sent(r) }
    }

    public func stop() { lock.lock(); stopFlag = true; lock.unlock() }
    public var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopFlag }
    private func count() { lock.lock(); requests += 1; lock.unlock() }
    private var made: Int { lock.lock(); defer { lock.unlock() }; return requests }

    /// Runs the lookup to its end or until stopped; never throws: failures are in the review, in plain codes.
    public func run(progress: (Progress) -> Void = { _ in }) -> DeskLookup.Review {
        if plan.scope == "disc", let disc = plan.disc { return runDisc(disc, progress: progress) }
        var results: [DeskLookup.SongResult] = []
        var failure: String? = nil
        var stopped = false
        let total = plan.songs.count
        progress(Progress(done: 0, total: total, found: 0))
        for (i, song) in plan.songs.enumerated() {
            let ask = plan.asks[i]
            var r = DeskLookup.SongResult(song: song.track.id, title: song.track.ident.title, seconds: song.track.file.durationS,
                                          ask: ask, outcome: "notAsked", failure: nil, candidates: [], chosen: nil, several: false)
            if stopped || failure != nil || isStopped {
                stopped = stopped || isStopped; results.append(r); progress(next(results, total)); continue
            }
            if ask.kind == "none" { r.outcome = "nothingToSend"; results.append(r); progress(next(results, total)); continue }
            do {
                var recs: [MBRecording] = []
                if let isrc = ask.isrc { recs = try client.searchRecordings(isrc: isrc) }
                if recs.isEmpty, let q = ask.query { recs = try client.searchRecordings(q) }
                // The second ask, with free words, only when title and artist found nothing (D39).
                var again = 0
                if recs.isEmpty, secondAsk {
                    for q in DeskLookup.secondAsks(song, first: ask) where recs.isEmpty {
                        recs = try client.searchRecordings(q)
                        again += 1
                    }
                }
                let known = DeskLookup.Known(song, ask: ask)
                var cands = recs.map { DeskLookup.candidate($0, known: known) }
                for j in cands.indices {
                    DeskLookup.rate(&cands[j], known: known, isrcs: recs[j].isrcs ?? [])
                    if again > 0 { cands[j].notes.append("askedAgain") }
                    if known.artistFromFolder { cands[j].notes.append("fromFolder") }
                }
                var (ordered, chosen, several, mode, rules) = DeskLookup.order(cands, known: known)
                if chosen != nil, again > 0 { rules.append("askedAgain") }
                // The label of the release that fits (a recording's search answer has none): one more request.
                if fetchLabels, let c = chosen, ordered[c].label == nil, let rid = ordered[c].releaseId {
                    if let rel = try? client.release(rid), let label = rel.labels.first { ordered[c].label = label }
                    if isStopped { throw LookupFailure.stopped }
                }
                for j in ordered.indices { ordered[j].changes = DeskLookup.changes(ordered[j], song: song, mode: j == chosen ? mode : nil) }
                r.candidates = ordered; r.chosen = chosen; r.several = several
                r.mode = mode; r.rules = chosen == nil ? nil : rules; r.askedAgain = again
                r.outcome = ordered.isEmpty ? "nothing" : "found"
            } catch let f as LookupFailure {
                switch f {
                case .stopped: stopped = true
                case .noConnection, .busy, .notOnThisComputer: r.outcome = "failed"; r.failure = f.code; failure = f.code
                case .refused, .badAnswer: r.outcome = "failed"; r.failure = f.code
                }
            } catch {
                r.outcome = "failed"; r.failure = LookupFailure.badAnswer.code
            }
            results.append(r)
            progress(next(results, total))
        }
        return DeskLookup.Review(scope: plan.scope, source: nil, songs: results, stopped: stopped, failure: failure,
                                 requests: made, discMatch: nil)
    }

    private func next(_ results: [DeskLookup.SongResult], _ total: Int) -> Progress {
        Progress(done: results.count, total: total, found: results.filter { $0.outcome == "found" }.count)
    }

    // MARK: a music CD

    /// A disc: its id with its table (MusicBrainz does the fuzzy search itself when it does not know the id); when
    /// that finds nothing and the disc has a name, a release search by the name and the number of songs, and up to
    /// `releasesLookedInto` of those releases read for their songs. Each song's candidates are the song at its number
    /// on each release found.
    func runDisc(_ disc: DeskLookup.DiscPlan, progress: (Progress) -> Void) -> DeskLookup.Review {
        let total = plan.songs.count
        progress(Progress(done: 0, total: total, found: 0))
        var releases: [(MBRelease, String)] = []
        var failure: String? = nil
        var stopped = false
        var match: String? = nil
        // A disc found by its table's likeness or by its name counts only when every song on it is the length of the
        // song at the same number here: otherwise it is another disc that happens to be near.
        func alike(_ rel: MBRelease) -> Bool {
            guard let m = Self.medium(rel, disc: disc) else { return false }
            let lengths = m.songs.map { ($0.length ?? $0.recording?.length).map { Double($0) / 1000 } }
            let ours = disc.table.seconds
            return lengths.count == ours.count
                && zip(lengths, ours).allSatisfy { l, o in l.map { abs($0 - o) <= DeskLookup.allowance } ?? false }
        }
        do {
            let answer = try client.disc(disc.table)
            if answer.exact {
                releases = (answer.releases ?? []).map { ($0, "disc") }
                if !releases.isEmpty { match = "exact" }
            } else {
                releases = (answer.releases ?? []).filter(alike).map { ($0, "fuzzy") }
                if !releases.isEmpty { match = "fuzzy" }
            }
            if releases.isEmpty, let name = disc.name {
                let found = try client.searchReleases(name: name, tracks: disc.table.offsets.count)
                for rel in found.prefix(DeskLookup.releasesLookedInto) {
                    guard let id = rel.id else { continue }
                    let full = try client.release(id, songs: true)
                    if alike(full) { releases.append((full, "byName")) }
                }
                if !releases.isEmpty { match = "byName" }
            }
        } catch let f as LookupFailure {
            if f == .stopped { stopped = true } else { failure = f.code }
        } catch { failure = LookupFailure.badAnswer.code }

        let first = disc.table.first
        var results: [DeskLookup.SongResult] = []
        for song in plan.songs {
            let ask = DeskLookup.Ask(kind: "disc", isrc: nil, query: nil)
            var r = DeskLookup.SongResult(song: song.track.id, title: song.track.ident.title, seconds: song.track.file.durationS,
                                          ask: ask, outcome: failure != nil ? "failed" : (stopped ? "notAsked" : "nothing"),
                                          failure: failure, candidates: [], chosen: nil, several: false)
            if let number = disc.numbers[song.track.id], failure == nil, !stopped {
                let known = DeskLookup.Known(song, ask: ask)
                var cands: [DeskLookup.Candidate] = []
                for (rel, how) in releases {
                    guard let medium = Self.medium(rel, disc: disc) else { continue }
                    let tracks = medium.songs
                    let at = number - first
                    guard let track = tracks.first(where: { $0.position == at + 1 })
                            ?? (at >= 0 && at < tracks.count ? tracks[at] : nil) else { continue }
                    var c = Self.candidate(track, release: rel, known: known)
                    c.notes.append(how)
                    DeskLookup.rate(&c, known: known)
                    cands.append(c)
                }
                var (ordered, chosen, several, mode, _) = DeskLookup.order(cands, known: known)
                // A disc found by its name or a fuzzy match is never filled in by itself: the DJ chooses.
                if match != "exact" { chosen = nil }
                for j in ordered.indices { ordered[j].changes = DeskLookup.changes(ordered[j], song: song, mode: j == chosen ? mode : nil) }
                r.candidates = ordered; r.chosen = chosen; r.several = several
                r.outcome = ordered.isEmpty ? "nothing" : "found"
            }
            results.append(r)
            progress(next(results, total))
        }
        return DeskLookup.Review(scope: "disc", source: disc.source, songs: results, stopped: stopped, failure: failure,
                                 requests: made, discMatch: match)
    }

    /// The medium of a release that is this disc: the one carrying its id, else one with as many songs, else the first.
    static func medium(_ rel: MBRelease, disc: DeskLookup.DiscPlan) -> MBMedium? {
        let media = rel.media ?? []
        let id = disc.table.musicBrainzId
        return media.first { ($0.discs ?? []).contains { $0.id == id } }
            ?? media.first { ($0.trackCount ?? $0.songs.count) == disc.table.offsets.count }
            ?? media.first
    }

    static func candidate(_ track: MBTrack, release rel: MBRelease, known: DeskLookup.Known) -> DeskLookup.Candidate {
        let rec = track.recording
        let title = track.title ?? rec?.title ?? ""
        let v = DeskLookup.candidateVersion(title: title, disambiguation: rec?.disambiguation)
        let year = (rec?.firstReleaseDate ?? rel.date).flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil }
        let length = track.length ?? rec?.length
        let credit = track.artistCredit ?? rec?.artistCredit ?? rel.artistCredit ?? []
        return DeskLookup.Candidate(recording: rec?.id, title: v.title, version: v.version,
                                    artist: credit.line,
                                    release: rel.title, releaseId: rel.id, year: year, label: rel.labels.first,
                                    seconds: length.map { Double($0) / 1000 }, fit: "unknown", difference: nil,
                                    otherVersion: false, notes: [], agree: 0, changes: [], score: 0,
                                    credited: credit.compactMap(\.name), featuring: DeskLookup.featuringFlags(credit),
                                    match: nil, titleAgrees: nil, artistAgrees: nil, lyrics: v.reading?.lyrics?.rawValue, disagree: nil)
    }
}
