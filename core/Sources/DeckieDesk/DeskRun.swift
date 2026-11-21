import Foundation
import DeckieCore
import DeckieCrate
import DeckieBuild
import DeckieEngine
import DeckieDecode
import DeckieDisc

/// What a run reads: a source (a CD, a drive, or a folder read as one) or the ordinary music folder (`source` nil),
/// with a rekordbox collection for the rekordbox route. Kept as `pending.json` while the run goes, so a run that was
/// stopped (Desk quit, the Mac slept for good) can be carried on: the builder's work folder and the file store keep
/// everything finished, so carrying on does only what is left.
public struct RunRequest: Codable, Equatable, Sendable {
    public var folder: String
    public var source: String?
    public var rekordbox: String?
    /// A music CD (research AA): where the disc is (`MusicCDs.Found.location`, also `folder`) and its id. Its songs
    /// are read off the disc one at a time and none is kept (`DiscSongs.swift`); a run that stopped carries on when
    /// the same disc is in a drive again.
    public var musicCD: String?
    public var discId: String?
    public init(folder: URL, source: String?, rekordbox: URL? = nil, musicCD: String? = nil, discId: String? = nil) {
        self.folder = folder.path; self.source = source; self.rekordbox = rekordbox?.path
        self.musicCD = musicCD; self.discId = discId
    }
    public var folderURL: URL { URL(fileURLWithPath: folder) }
    /// What the run reads, by its own name: the source's, or the folder's.
    public var name: String { source ?? URL(fileURLWithPath: folder).lastPathComponent }
}

/// The stage a run is in. One count goes through all of them: a song is done when it is read, its signature made and
/// its print made.
public enum RunStage: String, Codable, Sendable { case reading, finishing, saving }

/// A run's progress: songs done of the songs found, and an estimate of the seconds left (nil until there is
/// something to estimate from).
public struct RunProgress: Sendable {
    public var stage: RunStage
    public var done: Int
    public var total: Int
    public var remaining: Double?
    /// What just happened, for the run's list, or nil.
    public var line: RunLine?
    /// The run screen (D37): a song that just joined it, what is true of it now (and any moment), and the running
    /// totals of every song on it so far.
    public var song: RunSong? = nil
    public var notes: [RunNote] = []
    public var figures = RunFigures()
    /// The song being worked on now and the step it is on, when songs are read one at a time (a music CD's songs, or
    /// a folder read with one job): the run screen's song card names it and says its step. Nil between songs, and
    /// when several songs are read at once (`working` says those).
    public var now: RunNow? = nil
    /// Every song being worked on now, in the order they were taken, each with its step: the one song `now` names,
    /// or the several a folder's jobs read at once. Empty between songs.
    public var working: [RunNow] = []
    /// The next song of a music CD while it is read ahead (its sound coming off the disc while `now` is analysed),
    /// with the share read; nil when nothing is read ahead. Never the song `now` names.
    public var ahead: RunNow? = nil
    /// The file (its `rel`, as the run's lines and `working` name it) whose song has just joined the screen, or whose
    /// second place was just noted, or that turned out to have nothing to show: the song card may let it go now.
    /// Nil on any other call.
    public var landed: String? = nil
}

/// Puts a run's progress calls in the order the run screen shows them, so its two cards agree with each other and
/// with every other line on it: a song leaves the songs worked on (`working`) only in the same call as, or after, the
/// call that brings it onto the screen (`song`, `landed`), and no line about it (the run's list) goes out before then.
/// A call that lets go of a song not yet on the screen is held, with every call after it, in order; when the song
/// joins, its own call goes first (the songs worked on as last let out), then the held ones. A song read that never
/// joins (a read that went wrong) is let go by its line. A stage other than reading lets everything out.
/// One per run, called one call at a time (DeskRun's delivery lock).
public struct RunOrder: Sendable {
    /// The songs worked on in the last call taken, and in the last call let out.
    private var latest: [String] = []
    private var released: RunProgress?
    private var held: [RunProgress] = []
    /// Songs that left the songs worked on and have not yet joined the screen.
    private(set) var waiting: Set<String> = []

    public init() {}

    /// The calls to let out now, in order, for one call taken.
    public mutating func take(_ p: RunProgress) -> [RunProgress] {
        if p.stage != .reading {
            let out = held + [p]
            held = []; waiting = []; latest = []; released = p
            return out
        }
        let rels = p.working.map(\.rel)
        for r in latest where !rels.contains(r) { waiting.insert(r) }
        latest = rels
        if let r = p.landed { waiting.remove(r) }
        if case let .file(rel, outcome)? = p.line, case .failed = outcome { waiting.remove(rel) }
        if held.isEmpty && waiting.isEmpty { released = p; return [p] }
        var out: [RunProgress] = []
        var rest = p
        if p.song != nil || p.landed != nil {
            // The song first, beside the songs worked on as they were last let out.
            var first = released ?? RunProgress(stage: .reading, done: 0, total: p.total)
            first.line = nil
            first.song = p.song; first.notes = p.notes; first.figures = p.figures; first.landed = p.landed
            out.append(first); released = first
            rest.song = nil; rest.notes = []; rest.landed = nil
        }
        held.append(rest)
        if waiting.isEmpty {
            out += held
            released = held.last
            held = []
        }
        return out
    }
}

/// A song a run is working on now, and what is happening to it: taken (`started`), its sound coming off the disc
/// (`reading`, with the share read), or an analysis stage starting (`Analysis.timings`' names: "hash", "decode",
/// "resample", "beatthis", "key", "spectral", "structure", "loudness", "vocal", "windows").
public struct RunNow: Sendable, Equatable {
    /// The song's path as the run's lines name it (the source's name first).
    public var rel: String
    /// Its number on a music CD ("Track 02" is 2), or nil.
    public var number: Int?
    public var step: String
    /// The share of the song read off the disc so far, 0 to 1, while it is read; nil otherwise.
    public var read: Double?
    /// How far through its analysis step it is, 0 to 1, from the work that step has done (the beat model's chunks
    /// done of the song's chunks, for now: the beat step is most of a song's time); nil when the step does not say.
    /// A new step starts at nil.
    public var within: Double?
    /// The name Desk has for it so far: a music CD's CD-Text name, then rekordbox's or its tags' once they are read;
    /// nil until there is one (`name` is then its file name).
    public var title: String?
    public var artist: String?
    /// What Desk has worked out of it so far, each part as soon as it is final and as the finished record (and the
    /// song's `RunSong`) will hold it; nil until then (the owner's note, Nov 20, 2026: the card is the song being worked
    /// on, its parts filling in). Where it is, from the start; its length when decoded; its tempo when the beat is
    /// found; its bars when the bar grid is laid; its key when read (`kind` none: read and not sure); its wave when
    /// the loudness of its bars is measured.
    public var place: String?
    public var folder: String?
    public var seconds: Double?
    public var bpm: Double?
    public var bars: Int?
    public var key: RunSong.Key?
    public var wave: [Int]?
    public init(rel: String, number: Int?, step: String, read: Double? = nil, title: String? = nil, artist: String? = nil) {
        self.rel = rel; self.number = number; self.step = step; self.read = read; self.title = title; self.artist = artist
    }

    /// A part of the song's record (the analyser's `AnalysisPart`), in the run screen's own form: the same rounding
    /// and the same key rule as `RunSong` makes from the finished record, so the card's values never change when the
    /// song is done.
    public mutating func take(_ part: AnalysisPart) {
        switch part {
        case let .length(s): seconds = (s * 10).rounded() / 10
        case let .tempo(b): bpm = (b * 10).rounded() / 10
        case let .bars(n): bars = n
        case let .key(k): key = RunSong.key(k)
        case let .loudness(lufs): wave = RunSong.wave(lufs)
        }
    }

    /// Where it is, as `RunSong` says it from the same place.
    public mutating func take(_ p: CrateTrack.Place) {
        place = Crate.placeLine(p)
        folder = p.disc == nil ? (p.folder ?? SourceReading.group(of: rel)) : nil
    }

    /// Whether any part of it has been worked out (a song taken from what was worked out before has none).
    public var hasParts: Bool { seconds != nil || bpm != nil || bars != nil || key != nil || wave != nil }

    /// The analysis stages in the order they start (run.js's NOW_STEPS must say the same). The key is read before the
    /// beat since Nov 21, 2026 (its chromagram, timed with it, is still made after).
    public static let analysisSteps = ["hash", "decode", "resample", "key", "beatthis", "spectral", "structure", "loudness",
                                       "vocal", "windows"]

    /// Whether the song's sound is still coming off the source.
    public var isReading: Bool { step == "started" || step == "reading" }

    /// The song's name on the screen: the name Desk has for it, else its file name without the ending ("Track 02").
    public var name: String {
        if let t = title, !t.isEmpty { return t }
        return (CratePath.lastName(rel) as NSString).deletingPathExtension
    }

    /// The beat step's share of the song's bar (run.js's NOW_BEAT_SHARE must say the same). Finding the beat is most of
    /// a song's time (about 70% on the Windows pass), so with one tenth of the bar the bar sat still for most of each
    /// song; with a wider share the bar's place is closer to how much of the wait is behind. Not all of it: the quick
    /// steps still move the bar in small jumps, which the owner likes (his choice, Nov 21, 2026: a wider share, but not all of the bar). A display proportion only, the same on every machine and for every song; nothing measured.
    public static let beatShare = 0.3

    /// Each step's share of the song's bar, in `analysisSteps`' order: a step named in `ownShares` has its own; the
    /// rest share what is left equally.
    static let ownShares: [String: Double] = ["beatthis": beatShare]
    public static let stepShares: [Double] = {
        let others = analysisSteps.filter { ownShares[$0] == nil }.count
        let left = 1 - ownShares.values.reduce(0, +)
        return analysisSteps.map { ownShares[$0] ?? left / Double(others) }
    }()

    /// The steps that say how far through them the song is (`within`): only the beat step, for now.
    public static let stepsThatSayHowFar: Set<String> = ["beatthis"]

    /// How far through the song, 0 to 1: the share read while it is read, then its analysis steps, each its share of
    /// the bar (`stepShares`). A step that says how far it is (`stepsThatSayHowFar`) moves the bar across its own share
    /// in proportion to the work done: at its start until it says, at its end only when all its work is done. Any
    /// other step shows its share as done from the moment it starts, as every step did before (when the shares were
    /// tenths, step n of ten showed n tenths). run.js `nowShare` does the same.
    public var share: Double {
        if isReading { return max(0, min(1, read ?? 0)) }
        guard let i = Self.analysisSteps.firstIndex(of: step) else { return 1 }
        let start = Self.stepShares[..<i].reduce(0, +)
        let inStep = Self.stepsThatSayHowFar.contains(step) ? max(0, min(1, within ?? 0)) : 1
        return min(1, start + inStep * Self.stepShares[i])
    }

    /// The step line on the song card, in Desk's words: "Reading song 2 of 6 from the disc", "Song 2 of 6: finding
    /// the beat", or for a song not on a disc, "Reading this song", "This song: finding the beat". `total` is the
    /// songs of the run.
    public func line(total: Int) -> String {
        if isReading {
            return number.map { DeskWords.text("nowReadingDisc", ["number": DeskWords.number($0), "total": DeskWords.number(total)]) }
                ?? DeskWords.text("nowReading")
        }
        return number.map { DeskWords.text("nowStageOf", ["number": DeskWords.number($0), "total": DeskWords.number(total), "stage": stage]) }
            ?? DeskWords.text("nowStageAlone", ["stage": stage])
    }

    /// The step alone, as a part of a sentence ("finding the beat"): a row of the songs worked on at once.
    public var stage: String {
        if isReading { return DeskWords.text("nowOpening") }
        return DeskWords.table["nowStage." + step] != nil ? DeskWords.text("nowStage." + step) : DeskWords.text("nowStage.other")
    }

    /// The quiet line under the song card while the next song is read ahead.
    public static var aheadLine: String { DeskWords.text("nowAheadDisc") }

    /// The heading of the rows under the song card when several songs are worked on at once: "Also working on 3 songs".
    public static func alsoLine(_ n: Int) -> String { DeskWords.count("alsoWorkingOn", n) }

    /// The song the card shows (the owner's note, Nov 20, 2026: the card is the song being worked on): the one it
    /// shows already while it is still worked on; else, of the songs worked on, the furthest along (the one that will
    /// finish next): by its bar, and where two bars are level, the later step (a song starting the beat stands where a
    /// song on its key stands, and is further on); the first taken when two are as far. run.js `cardSong` does the same.
    public static func cardSong(_ working: [RunNow], keeping current: String?) -> RunNow? {
        if let current, let kept = working.first(where: { $0.rel == current }) { return kept }
        var best: RunNow?
        for n in working where best == nil || n.isFurther(than: best!) { best = n }
        return best
    }

    /// Where its step stands in the order: before every analysis step while it is read; after them all when unknown.
    var stepRank: Int {
        if isReading { return -1 }
        return Self.analysisSteps.firstIndex(of: step) ?? Self.analysisSteps.count
    }

    /// Further along than `other`: a fuller bar, or as full a bar at a later step.
    func isFurther(than other: RunNow) -> Bool {
        let a = share, b = other.share
        if abs(a - b) > 1e-9 { return a > b }
        return stepRank > other.stepRank
    }

    /// The songs worked on other than the card's, in the order taken: the rows under the card.
    public static func rows(_ working: [RunNow], card: String?) -> [RunNow] { working.filter { $0.rel != card } }
}

/// The songs a run is working on, kept as their steps come (from the builder's jobs and the disc's read ahead, under
/// the run's lock): which are in hand, in the order taken, each with its step and name, and the song read ahead.
/// One rule makes the screen's words match what the drive and the analysis are doing: a read of a song in hand is
/// that song's read; a read of any other song is the read ahead.
struct RunWorking: Sendable, Equatable {
    /// Songs read one at a time (`jobs` 1): `now` is the one song.
    let oneAtATime: Bool
    private(set) var songs: [RunNow] = []
    private(set) var ahead: RunNow?
    init(oneAtATime: Bool) { self.oneAtATime = oneAtATime }

    var now: RunNow? { oneAtATime ? songs.first : nil }

    /// The builder took a song: it is in hand (its read ahead, if it was being read ahead, is now its own read).
    mutating func took(_ song: RunNow) {
        if ahead?.rel == song.rel { ahead = nil }
        songs.removeAll { $0.rel == song.rel }
        songs.append(song)
    }

    /// A step of a song: its own when it is in hand; a read of a song not in hand is the read ahead (ended when it
    /// has all been read). Steps of a song neither in hand nor being read are let go.
    mutating func step(_ rel: String, step: String, read: Double? = nil) {
        if let i = songs.firstIndex(where: { $0.rel == rel }) {
            songs[i].step = step; songs[i].read = read; songs[i].within = nil
            return
        }
        guard step == "reading" else { return }
        if let r = read, r >= 1 { if ahead?.rel == rel { ahead = nil }; return }
        if ahead?.rel == rel { ahead?.read = read } else {
            ahead = RunNow(rel: rel, number: DiscSongFiles.number(of: rel), step: "reading", read: read)
        }
    }

    /// How far a song in hand is through its analysis step: `done` of `total` (the beat model's chunks). Never moves
    /// back within the step, and says nothing of a song being read.
    mutating func within(_ rel: String, done: Int, total: Int) {
        guard total > 0, let i = songs.firstIndex(where: { $0.rel == rel }), !songs[i].isReading else { return }
        let share = max(0, min(1, Double(done) / Double(total)))
        songs[i].within = max(share, songs[i].within ?? 0)
    }

    /// A part of a song in hand, as it is worked out; where it is.
    mutating func part(_ rel: String, _ part: AnalysisPart) {
        guard let i = songs.firstIndex(where: { $0.rel == rel }) else { return }
        songs[i].take(part)
    }
    mutating func placed(_ rel: String, _ p: CrateTrack.Place) {
        guard let i = songs.firstIndex(where: { $0.rel == rel }) else { return }
        songs[i].take(p)
    }

    /// The name Desk has for a song in hand (a name already given, a disc's CD-Text, stays when this gives none).
    mutating func named(_ rel: String, title: String?, artist: String?) {
        guard let i = songs.firstIndex(where: { $0.rel == rel }), let t = title, !t.isEmpty else { return }
        songs[i].title = t; songs[i].artist = artist ?? songs[i].artist
    }

    /// A song is done (read, or not read): it leaves the songs in hand.
    mutating func done(_ rel: String) { songs.removeAll { $0.rel == rel } }

    /// The read ahead of `rel` ended (read whole, cancelled, or failed).
    mutating func aheadEnded(_ rel: String) { if ahead?.rel == rel { ahead = nil } }

    mutating func clear() { songs = []; ahead = nil }
}

/// One line of a run's list, as data; a desk says it in its own words.
public enum RunLine: Sendable, Equatable {
    /// The folder is listed: audio files found, unchanged since the last run, and to read now.
    case started(files: Int, unchanged: Int, queued: Int)
    /// A file was read: its path (the source's name first) and what happened.
    case file(rel: String, outcome: FileProgress.Outcome)
    /// Part of a music CD's song could not be read even on a second try: its number, and the sectors (1/75 s each)
    /// that were read as silence.
    case discDamaged(number: Int, sectors: Int)
}

/// What a run did, measured as it ran (no tuning: these are for collecting real timings). Shown on the finished
/// screen and written as one line of the crate's `runs.jsonl`.
public struct RunReport: Codable, Equatable, Sendable {
    public var crate: String
    /// What was read, by its own name.
    public var read: String
    public var startedAt: String
    /// Wall-clock seconds of the whole run, and of its parts: the builder (with finishing alongside), and the
    /// finishing and saving after it.
    public var seconds: Double
    public var buildSeconds: Double
    public var finishSeconds: Double
    /// Audio files found in what was read, how many went in, and the ones that did not, by the import log's reason.
    public var songsSeen: Int
    public var wentIn: Int
    public var notIn: [String: Int]
    /// Folders left out by the "_" rule (the music folder only), and songs in with damaged frames.
    public var foldersLeftOut: Int
    public var damaged: Int
    /// Files analysed in this run, and taken from what was worked out before (this crate's or another's).
    public var analysed: Int
    public var reused: Int
    public var signaturesMade: Int
    public var signaturesKept: Int
    public var signaturesFailed: Int
    public var printsMade: Int
    public var printsKept: Int
    public var printsFailed: Int
    /// Entries now in a group of copies of one recording, and songs in the crate after the run.
    public var copies: Int
    public var songsInCrate: Int
    /// Songs found per minute of the whole run.
    public var songsPerMinute: Double
    public var jobs: Int
    public var device: String
    public var engine: String
    /// Whether the run carried on one that had stopped.
    public var carriedOn: Bool
    /// The keys and names taken from what is already on the computer (D30): where each key came from, the songs still
    /// with no key or no name, the DJ libraries read. Nil in a line written before it.
    public var local: LocalFactsSummary? = nil
    /// A music CD's part of the run (research AA): what the drive said about names, the songs named from the disc,
    /// and the sound that could not be read. Nil for anything else.
    public var disc: DiscReport? = nil
    /// Covers (D36), as the builder counted them: songs with one, distinct covers and their bytes, pictures that could
    /// not be used. Nil in a line written before covers.
    public var covers: CoverCounts? = nil
    /// Songs fingerprinted for recognition in this run (D35; the builder's count), and the crate's songs that carry
    /// a fingerprint after it. Nil in a line written before it. Not the prints above, which find copies.
    public var fingerprinted: Int? = nil
    public var songsWithFingerprint: Int? = nil
    /// The DJ stopped the run (Stop) before every song was read: the songs read are in the crate, and the run is kept
    /// to carry on (`pending.json` stays). Nil in a line written before Stop.
    public var stopped: Bool? = nil
    /// Songs this run read, each once however many places it is in (the run screen's count, and "That's the lot"),
    /// where `wentIn` counts files: a song in two folders is two files and one song. And the audio files found in what
    /// was read, reached or not: a stopped run read `songsSeen` of them. Nil in a line written before them.
    public var songsRead: Int? = nil
    public var filesFound: Int? = nil
    /// Why `jobs` is what it is (`DeskJobs.Reason`): `cores`, `memory`, `set` (DECKIE_DESK_JOBS), or `disc` (a music
    /// CD, read one song at a time whatever `jobs` says). Nil when the caller did not say, and in a line written before it.
    public var jobsBy: String? = nil
    /// A run carried on after Stop: the seconds of the part or parts before it, which `seconds` (and so
    /// `songsPerMinute`) includes; the pause between is not counted. Nil for a run that did not carry one on, and in a
    /// line written before it.
    public var secondsBefore: Double? = nil

    enum CodingKeys: String, CodingKey {
        case crate, read, seconds, analysed, reused, copies, jobs, device, engine, damaged
        case startedAt = "started_at", buildSeconds = "build_seconds", finishSeconds = "finish_seconds"
        case songsSeen = "songs_seen", wentIn = "went_in", notIn = "not_in", foldersLeftOut = "folders_left_out"
        case signaturesMade = "signatures_made", signaturesKept = "signatures_kept", signaturesFailed = "signatures_failed"
        case printsMade = "prints_made", printsKept = "prints_kept", printsFailed = "prints_failed"
        case songsInCrate = "songs_in_crate", songsPerMinute = "songs_per_minute", carriedOn = "carried_on"
        case local, disc, covers, fingerprinted, songsWithFingerprint = "songs_with_fingerprint", stopped
        case songsRead = "songs_read", filesFound = "files_found"
        case jobsBy = "jobs_by", secondsBefore = "seconds_before"
    }

    /// Songs that did not go in.
    public var notInCount: Int { notIn.values.reduce(0, +) }

    /// The finished screen's first lines, in Desk's words (desk.js `drawFinished` says the same): the songs that went
    /// in, counted as the crate counts them (a song in two places once, as "That's the lot" and the sources say); for
    /// a stopped run, how many of the songs found it read instead, never "Every song went in"; and, when more files
    /// went in than songs, why.
    public var summaryLines: [String] {
        let songs = songsRead ?? wentIn
        var out: [String] = []
        if stopped == true {
            out.append(filesFound.map { DeskWords.count("stoppedRead", $0, ["done": DeskWords.number(songsSeen), "total": DeskWords.number($0)]) }
                       ?? DeskWords.count("wentIn", songs))
        } else {
            out.append(notInCount == 0 ? DeskWords.text("everySongWentIn") : DeskWords.count("wentIn", songs))
        }
        if wentIn > songs {
            out.append(DeskWords.count("wentInAsSongs", wentIn - songs, ["files": DeskWords.number(wentIn), "songs": DeskWords.count("songs", songs)]))
        }
        return out
    }
}

/// The one run (D28, desk.md section 2): everything a crate needs from what was added, in one go. The builder reads
/// and analyses (keeping its records in the shared file store, each with the song's fingerprint for recognition, D35,
/// made from the audio the analysis decoded); as each song is read, its recognition signature and
/// its print are made, or taken from the store; then copies of one recording are linked, the keys and names already on
/// the computer are gathered (`DeskLocalFacts`, D30), the DJ's name fixes are put back, every place's path is remembered, and the crate file is written. Stopping at any point loses nothing
/// already done; running again carries on.
public final class DeskRun: @unchecked Sendable {
    /// Makes a recognition signature from a song's file (ShazamKit on Apple's systems); nil where there is none.
    public typealias SignatureMaker = @Sendable (URL) throws -> Data
    /// Makes the print that finds copies of one recording from a song's file.
    public typealias PrintMaker = @Sendable (URL) throws -> RecordingPrint
    /// Makes the same print from the song's audio as the analysis decoded it (its file named by the URL), so the
    /// song is not read and decoded again for it; nil when this desk makes it from the file instead (`PrintMaker`).
    /// It must give exactly the print `PrintMaker` would for that file.
    public typealias AudioPrintMaker = @Sendable (URL, AudioBuffer) -> RecordingPrint?

    public let home: DeskHome
    public let crateId: String
    public let request: RunRequest
    public let jobs: Int
    /// Why `jobs` is what it is (`DeskJobs.Reason`), for the run log; nil when the caller did not say.
    public let jobsBy: DeskJobs.Reason?
    public let device: String
    public let fileBPMTags: Bool
    let analyser: Analyser?
    let signer: SignatureMaker?
    let printer: PrintMaker
    let audioPrinter: AudioPrintMaker?
    /// Opens a music CD by its location (`MusicCDs.open`; a test gives a stand-in), and lists the drives holding
    /// one (to find the disc when it is in another drive).
    public var openMusicCD: (String) throws -> MusicCD = { try MusicCDs.open($0) }
    public var findMusicCDs: () -> [MusicCDs.Found] = { MusicCDs.list() }
    /// Stop (the run screen's button): no further song is started, the ones being read finish, and the crate is saved
    /// with every song read so far. The run stays pending, so Carry on reads the rest (quickly: what was read is kept).
    let stopFlag = BuildStop()
    public func stop() { stopFlag.set() }
    public var stopAsked: Bool { stopFlag.isSet }

    public init(home: DeskHome, crateId: String, request: RunRequest, jobs: Int, device: String,
                fileBPMTags: Bool = true, analyser: Analyser? = nil, signer: SignatureMaker?, printer: @escaping PrintMaker,
                audioPrinter: AudioPrintMaker? = nil, jobsBy: DeskJobs.Reason? = nil) {
        self.home = home; self.crateId = crateId; self.request = request; self.jobs = max(1, jobs); self.device = device
        self.jobsBy = jobsBy
        self.fileBPMTags = fileBPMTags; self.analyser = analyser; self.signer = signer; self.printer = printer
        self.audioPrinter = audioPrinter
    }

    public static let pendingFile = "pending.json"
    public static let runsFile = "runs.jsonl"
    public static let correctionsFile = "corrections.json"
    public static let placesFile = "places.json"
    public static let namesFile = NameBook.file

    /// Whether a run that stopped can carry on now: its folder is here, or for a music CD, the same disc is in a
    /// drive.
    public static func canCarryOn(_ r: RunRequest, home: DeskHome,
                                  open: (String) throws -> MusicCD = { try MusicCDs.open($0) },
                                  musicCDs: () -> [MusicCDs.Found] = { MusicCDs.list() }) -> Bool {
        guard let id = r.discId, r.musicCD != nil else { return FileManager.default.fileExists(atPath: r.folder) }
        return DiscRecords.find(id, near: r.musicCD, open: open, musicCDs: musicCDs) != nil
    }

    /// The run a crate has left unfinished, if any.
    public static func pending(home: DeskHome, crateId: String) -> RunRequest? {
        JSONFile.read(RunRequest.self, from: home.shelf.file(pendingFile, of: crateId))
    }

    /// The crate's finished runs, oldest first.
    public static func runs(home: DeskHome, crateId: String) -> [RunReport] {
        guard let text = try? String(contentsOf: home.shelf.file(runsFile, of: crateId), encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? JSONDecoder().decode(RunReport.self, from: Data($0.utf8)) }
    }

    /// Counts shared between the builder's jobs and the finishing queue.
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var total = 0
        var done = 0
        var finishedIds = Set<String>()
        var finishSeconds: [Double] = []
        var waiting = 0
        var builderRemaining: Double?
        var builderStamp = Date()
        var sigMade = 0, sigKept = 0, sigFailed = 0, printMade = 0, printKept = 0, printFailed = 0
        /// The run screen's songs and totals (D37).
        var tally = RunTally()
        /// The songs being worked on now and the song read ahead (`RunProgress.now`, `working`, `ahead`).
        var working = RunWorking(oneAtATime: true)
        /// The order the calls go out in (RunOrder); used under the delivery lock.
        var order = RunOrder()
        /// Songs whose print was made from the analysis's audio in this run (counted as made, not kept).
        var printedInHand = Set<String>()
    }

    public func run(progress: @escaping @Sendable (RunProgress) -> Void = { _ in }) throws -> (crate: Crate, report: RunReport) {
        let t0 = Date()
        try home.prepare()
        let shelf = home.shelf, store = home.store
        guard var info = shelf.info(crateId) else { throw DeskError(DeskWords.text("error.noCrate", ["id": crateId])) }
        let pkg = shelf.package(crateId)
        let pendingURL = shelf.file(Self.pendingFile, of: crateId)
        let carriedOn = FileManager.default.fileExists(atPath: pendingURL.path)
        try JSONFile.write(request, to: pendingURL)

        let fm = FileManager.default
        // 0. A music CD: the disc in a drive (the one asked for; a stopped run carries on only with it), what Desk
        // knows of it, and its songs for the builder, read one at a time and none kept.
        DiscReading.clearLeftovers(home)
        let disc = try request.discId.flatMap { id -> DiscSongFiles? in
            guard request.musicCD != nil else { return nil }
            guard let cd = DiscRecords.find(id, near: request.musicCD, open: openMusicCD, musicCDs: findMusicCDs) else {
                throw DeskError(DeskWords.text("error.notInADrive", ["name": request.name]))
            }
            return DiscSongFiles(cd: cd, record: try DiscRecords.prepare(cd, home: home), home: home, store: store,
                                 needsSignature: signer != nil, stop: stopFlag)
        }
        let folder = disc.map { URL(fileURLWithPath: $0.cd.location) } ?? request.folderURL
        defer { disc?.clear() }
        let before = fm.fileExists(atPath: pkg.appendingPathComponent(CrateFormat.manifestFile).path)
            ? try CrateReader.read(from: pkg) : nil
        let keep: Set<String> = request.source == nil
            ? Set(info.sourceRoots.keys).union(before?.tracks.flatMap { $0.ident.allPlaces.compactMap(\.disc) } ?? [])
            : []
        var options = BuildOptions(folder: folder, output: pkg, rekordbox: request.rekordbox.map { URL(fileURLWithPath: $0) },
                                   jobs: jobs, fileBPMTags: fileBPMTags, fresh: false, name: info.name, device: device,
                                   source: request.source, keepSources: keep, sharedRecords: store.records,
                                   files: disc)
        options.stop = stopFlag
        let prefix = request.source.map { $0 + "/" } ?? ""
        let state = State()
        let queue = DispatchQueue(label: "deckie.desk.finish", qos: .userInitiated)
        let signer = self.signer, printer = self.printer, device = self.device

        @Sendable func estimate() -> Double? {
            // Called with the lock held.
            let mean = state.finishSeconds.isEmpty ? nil : state.finishSeconds.reduce(0, +) / Double(state.finishSeconds.count)
            let finishing = mean.map { Double(state.waiting) * $0 }
            let reading = state.builderRemaining.map { max(0, $0 - Date().timeIntervalSince(state.builderStamp)) }
            switch (reading, finishing) {
            case let (r?, f?): return max(r, f)
            case let (r?, nil): return r
            case let (nil, f?): return f
            default: return nil
            }
        }
        // Progress goes out one call at a time, in the order the state changed: the snapshot and the call are made
        // under one lock, so a step reported on the analysing thread is never overtaken by a later snapshot from
        // another thread (the disc's read ahead, the finishing queue, the screen's queue), nor folded into it.
        let deliver = NSRecursiveLock()
        @Sendable func emit(_ stage: RunStage, _ line: RunLine?, song: RunSong? = nil, notes: [RunNote] = [], landed: String? = nil) {
            deliver.lock(); defer { deliver.unlock() }
            state.lock.lock()
            var p = RunProgress(stage: stage, done: min(state.done, state.total), total: state.total, remaining: estimate(),
                                line: line)
            p.song = song; p.notes = notes + state.tally.done(p.done); p.figures = state.tally.figures
            if stage == .reading {
                p.now = state.working.now; p.working = state.working.songs; p.ahead = state.working.ahead
            }
            p.landed = landed
            state.lock.unlock()
            // Out in the order the screen shows them (RunOrder): a song leaves the songs worked on only as it joins.
            for q in state.order.take(p) { progress(q) }
        }
        // The run screen (D37): a song joins it when it is read, from its record in the store (on a queue of its own,
        // so the reading never waits for it); a second place of a song on it already is noted, not shown twice.
        let screen = DispatchQueue(label: "deckie.desk.screen", qos: .utility)
        // `rel`: the file read, which the song card lets go of as the song joins (RunProgress.landed).
        @Sendable func show(_ id: String, title: String?, artist: String?, place: CrateTrack.Place?, before: Bool,
                            stage: RunStage, track: CrateTrack? = nil, rel: String? = nil) {
            state.lock.lock()
            if state.tally.has(id) {
                let notes = state.tally.again(id, title: title ?? "", place: place.flatMap(Crate.placeLine))
                state.lock.unlock()
                emit(stage, nil, notes: notes, landed: rel)
                return
            }
            state.lock.unlock()
            guard let t = track ?? Builder.finishedRecord(id, records: store.records) else {
                if rel != nil { emit(stage, nil, landed: rel) }
                return
            }
            var song = RunSong(t, title: title, artist: artist, place: place, before: before)
            song.rel = rel
            state.lock.lock()
            let notes = state.tally.add(&song)
            state.lock.unlock()
            emit(stage, nil, song: song, notes: notes, landed: rel)
        }
        /// Makes (or takes from the store) the signature and the print of one file. Called on the finishing queue.
        @Sendable func finish(_ id: String, _ url: URL) {
            let t = Date()
            var made = false
            if let signer {
                if store.signature(id) != nil {
                    state.lock.lock(); state.sigKept += 1; state.lock.unlock()
                } else {
                    do {
                        let data = try signer(url)
                        try store.saveSignature(data, made: .init(madeBy: device, madeAt: Self.utcNow()), id: id)
                        made = true
                        state.lock.lock(); state.sigMade += 1; state.lock.unlock()
                    } catch { state.lock.lock(); state.sigFailed += 1; state.lock.unlock() }
                }
            }
            if store.print(id) != nil {
                state.lock.lock()
                // Made from the analysis's own audio a moment ago (`audioPrinter`): made in this run, not kept.
                if state.printedInHand.remove(id) != nil { state.printMade += 1; made = true } else { state.printKept += 1 }
                state.lock.unlock()
            } else {
                do {
                    try store.savePrint(try printer(url), id: id)
                    made = true
                    state.lock.lock(); state.printMade += 1; state.lock.unlock()
                } catch { state.lock.lock(); state.printFailed += 1; state.lock.unlock() }
            }
            state.lock.lock()
            state.finishedIds.insert(id)
            if made { state.finishSeconds.append(Date().timeIntervalSince(t)) }
            state.lock.unlock()
        }

        // The songs now, step by step, for the song card: taken, named, coming off the disc, each analysis stage; and
        // the next song of a disc while it is read ahead (RunWorking tells the two apart).
        state.working = RunWorking(oneAtATime: options.jobs == 1)
        @Sendable func change(_ f: (inout RunWorking) -> Void) {
            // The change and its progress together: every step of the song now is sent, in order.
            deliver.lock(); defer { deliver.unlock() }
            state.lock.lock()
            let was = state.working
            f(&state.working)
            let changed = state.working != was
            state.lock.unlock()
            if changed { emit(.reading, nil) }
        }
        let base = disc?.base
        /// A music CD's song by the name its CD-Text gives, where the builder has only its file name.
        @Sendable func discName(_ rel: String, _ title: String?, _ artist: String?) -> (String?, String?) {
            guard let base else { return (title, artist) }
            return DiscSongFiles.shownName(rel: rel, title: title, artist: artist, record: base)
        }
        options.onStep = { rel, s in
            let number = base != nil ? DiscSongFiles.number(of: rel) : nil
            switch s {
            case .started:
                let (title, artist) = discName(rel, nil, nil)
                var song = RunNow(rel: rel, number: number, step: "started", title: title, artist: artist)
                // A music CD's song: its length from the disc's table, before its sound is read (the Windows pass,
                // Nov 21, 2026). The same value the decoded sound gives (CD audio is 588 samples a sector at 44.1 kHz,
                // and a sector that cannot be read comes in as silence), which replaces it when it comes.
                if let base, let number, let toc = base.toc.songs.first(where: { $0.number == number }) {
                    song.take(.length(seconds: toc.seconds))
                }
                change { $0.took(song) }
            case let .named(title, artist):
                let (t, a) = discName(rel, title, artist)
                change { $0.named(rel, title: t, artist: a) }
            case let .reading(done, total):
                change { $0.step(rel, step: "reading", read: total > 0 ? Double(done) / Double(total) : nil) }
            case .stage(let name): change { $0.step(rel, step: name) }
            case .place(let p): change { $0.placed(rel, p) }
            case .part(let part): change { $0.part(rel, part) }
            // One a chunk of the beat model (about 30 s of the song each): a few a song, each sent at once.
            case let .within(done, total): change { $0.within(rel, done: done, total: total) }
            }
        }
        disc?.onRead = { rel, done, total in
            change { $0.step(rel, step: "reading", read: total > 0 ? min(1, Double(done) / Double(total)) : nil) }
        }
        disc?.onAheadEnded = { rel in change { $0.aheadEnded(rel) } }
        // The print that finds copies, from the audio the analysis decoded: the song is not read again for it.
        if let audioPrinter {
            options.withAudio = { id, file, audio in
                guard store.print(id) == nil, let p = audioPrinter(file.url, audio),
                      (try? store.savePrint(p, id: id)) != nil else { return }
                state.lock.lock(); state.printedInHand.insert(id); state.lock.unlock()
            }
        }

        // 1. Read: the builder, with each song finished as soon as it is read.
        let builder = try Builder(options: options, analyser: analyser)
        let result: BuildResult
        do { result = try builder.run { event in
            switch event {
            case let .started(files, unchanged, queued, _, _):
                // Files unchanged since a run (one that stopped, carried on now, among them) are done already: the
                // count carries on from them. Their signatures and prints are looked at after the read, as before.
                state.lock.lock(); state.total = files; state.done = unchanged; state.lock.unlock()
                emit(.reading, .started(files: files, unchanged: unchanged, queued: queued))
            case let .file(p):
                state.lock.lock()
                state.working.done(p.rel)
                state.builderRemaining = p.remaining; state.builderStamp = Date()
                if p.id == nil { state.done += 1; state.tally.notIn() } else { state.waiting += 1 }
                state.lock.unlock()
                if let id = p.id {
                    let before: Bool = { if case .analysed = p.outcome { return false }; return true }()
                    // A music CD's song named only by its file name ("Track 02") is shown by its CD-Text name.
                    let (title, artist) = disc.map { DiscSongFiles.shownName(rel: p.rel, title: p.title, artist: p.artist, record: $0.base) } ?? (p.title, p.artist)
                    screen.async { show(id, title: title, artist: artist, place: p.place, before: before, stage: .reading, rel: p.rel) }
                }
                if let id = p.id, let disc {
                    // A music CD's song is finished now, while its file is here; then the builder lets it go.
                    // One worked out before was not read: its signature and print are in the store already.
                    let url = disc.file(rel: p.rel)
                    if url != nil { disc.learned(rel: p.rel, id: id) }
                    finish(id, url ?? folder.appendingPathComponent(String(p.rel.dropFirst(prefix.count))))
                    state.lock.lock(); state.waiting -= 1; state.done += 1; state.lock.unlock()
                    let damaged = disc.damaged(rel: p.rel)
                    if damaged > 0, let n = DiscSongFiles.number(of: p.rel) { emit(.reading, .discDamaged(number: n, sectors: damaged)) }
                } else if let id = p.id {
                    let url = folder.appendingPathComponent(String(p.rel.dropFirst(prefix.count)))
                    queue.async {
                        finish(id, url)
                        state.lock.lock(); state.waiting -= 1; state.done += 1; state.lock.unlock()
                        emit(.reading, nil)
                    }
                }
                emit(.reading, .file(rel: p.rel, outcome: p.outcome))
            case .writing:
                break
            }
        } } catch let e as DiscError where disc != nil {
            disc?.cancelReadAhead()
            // The disc came out, or the drive stopped answering: nothing of this read is written; carry on asks for it.
            throw DeskError(DeskWords.text("error.couldNotRead", ["name": request.name, "detail": e.description]))
        }
        // Nothing more is read off the disc: a song read ahead that the builder did not take (Stop) is let go.
        disc?.cancelReadAhead()
        state.lock.lock(); state.working.clear(); state.lock.unlock()
        queue.sync {}
        screen.sync {}
        if disc != nil { emit(.finishing, nil, notes: [state.tally.discRead()]) }
        let buildSeconds = Date().timeIntervalSince(t0)
        let t1 = Date()

        // 2. Finish: every song of the crate gets its signature and print, from the store when they were made before
        // (songs unchanged since the last run, or read for another crate), else from its file.
        var crate = result.crate
        let paths = PlacePaths.load(from: shelf.file(Self.placesFile, of: crateId))
        var newPaths = paths
        newPaths.record(result.placesRead, source: request.source, keep: keep)
        newPaths.fillMissingPaths(&crate)
        if let s = request.source {
            info.sourceRoots[s] = folder.path
            info.discs[s] = disc?.base.toc.id
        } else { info.musicFolder = folder.path }
        let roots = info.roots, music = info.musicFolderURL
        let todo = crate.tracks.filter { t in
            state.lock.lock(); defer { state.lock.unlock() }
            return !state.finishedIds.contains(t.id)
        }
        state.lock.lock(); state.waiting = todo.count; state.lock.unlock()
        for t in todo {
            let readNow = result.placesRead[t.id]?.first.map { folder.appendingPathComponent($0.rel) }
            let url = readNow.flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil }
                ?? newPaths.locate(t, roots: roots, musicFolder: music)
            if let url { finish(t.id, url) } else {
                state.lock.lock(); state.finishedIds.insert(t.id); state.lock.unlock()
            }
            // A song of what was read that the builder did not have to look at (unchanged since the last run) joins
            // the run screen now, from the crate's own record; its other places in the read are noted.
            for r in result.placesRead[t.id] ?? [] {
                show(t.id, title: t.ident.title, artist: t.ident.artist, place: r.place, before: true, stage: .finishing,
                     track: t)
            }
            state.lock.lock()
            state.waiting -= 1
            state.lock.unlock()
            emit(.finishing, nil)
        }
        state.lock.lock(); state.done = state.total; state.lock.unlock()
        emit(.saving, nil)

        // 3. Save: signatures and fingerprints into the crate file, copies linked, the DJ's fixes put back, the crate's name.
        // The name as it is now: the DJ may have renamed the crate while it was read.
        if let now = shelf.info(crateId) { info.name = now.name }
        let sigFolder = pkg.appendingPathComponent(CrateFormat.signaturesFolder)
        try DeckieFiles.createDirectory(sigFolder)
        var prints: [String: RecordingPrint] = [:]
        for i in crate.tracks.indices {
            let id = crate.tracks[i].id
            if let s = store.signature(id) {
                let dest = sigFolder.appendingPathComponent("\(id)_o.shazamsignature")
                if !fm.fileExists(atPath: dest.path) { try DeckieFiles.write(s.data, to: dest) }
                if crate.tracks[i].signatures["o"] == nil { crate.tracks[i].signatures["o"] = s.made }
            }
            // The fingerprint (D35) comes with the builder's record. An entry kept from an earlier crate file, not
            // read now, takes the one the store has, when its file was since read for another crate.
            if crate.tracks[i].fingerprint == nil { crate.tracks[i].fingerprint = store.fingerprint(id) }
            if let p = store.print(id) { prints[id] = p }
        }
        let copies = crate.setCutKeys(prints: prints)
        let read = Set(result.placesRead.keys)
        state.lock.lock()
        let copyNotes = state.tally.copies(crate.tracks.filter { read.contains($0.id) && $0.ident.cutKey != nil }.count)
        state.lock.unlock()
        emit(.saving, nil, notes: copyNotes)
        // Keys and names already on the computer: the files' tags, the DJ programs' libraries, tracklists, copies.
        var local = DeskLocalFacts.gather(&crate, home: home, info: info, paths: newPaths)
        // A music CD's names from its CD-Text; where every name came from, and each song's release (research AA).
        let namedBefore = Dictionary(crate.tracks.map { ($0.id, $0.ident.source) }, uniquingKeysWith: { a, _ in a })
        let (book, discNamed) = DeskNamesStep.run(&crate, home: home, info: info, paths: newPaths,
                                                  book: NameBook.load(from: shelf.file(Self.namesFile, of: crateId)))
        try book.save(to: shelf.file(Self.namesFile, of: crateId))
        let corrections = NameCorrections.load(from: shelf.file(Self.correctionsFile, of: crateId))
        corrections.apply(to: &crate)
        // The report says where the names the crate now holds came from: a disc's CD-Text named songs after the
        // computer's names were counted, and the DJ's own names went back on (the finished screen and runs.jsonl).
        Self.recount(&local.report, before: namedBefore, crate: crate)
        state.lock.lock()
        state.tally.needName(crate.tracks.filter { read.contains($0.id) && LocalFacts.needsName($0) }.count)
        state.lock.unlock()
        emit(.saving, nil)
        crate.manifest.name = info.name
        try CrateWriter.write(crate, to: pkg)
        newPaths.keepOnly(Set(crate.tracks.map(\.id)))
        try newPaths.save(to: shelf.file(Self.placesFile, of: crateId))
        info.openedAt = max(Date().timeIntervalSince1970, (shelf.list().first?.openedAt ?? 0) + 0.001)
        try shelf.save(info)

        // 4. The report, and the run's line in the crate's log.
        typealias Reason = CrateManifest.ImportLog.Reason
        let mine = result.entries.filter { e in
            if let s = request.source { return e.rel.hasPrefix(s + "/") }
            return !keep.contains { e.rel.hasPrefix($0 + "/") }
        }
        var notIn: [String: Int] = [:]
        for e in mine where e.reason != Reason.damagedFrames && e.reason != Reason.skipped { notIn[e.reason, default: 0] += 1 }
        // The whole reading time: a run carried on after Stop adds the time of the part (or parts) before it, as the
        // stopped run's line says it; the pause between is not counted.
        let partsBefore = carriedOn ? Self.runs(home: home, crateId: crateId).last.flatMap { $0.stopped == true ? $0.seconds : nil } : nil
        let seconds = Date().timeIntervalSince(t0) + (partsBefore ?? 0)
        state.lock.lock()
        var report = RunReport(
            crate: info.name, read: request.name, startedAt: Self.utc(t0), seconds: seconds, buildSeconds: buildSeconds,
            finishSeconds: Date().timeIntervalSince(t1), songsSeen: result.filesSeen,
            wentIn: max(0, result.filesSeen - notIn.values.reduce(0, +)), notIn: notIn,
            foldersLeftOut: mine.filter { $0.reason == Reason.skipped }.count,
            damaged: mine.filter { $0.reason == Reason.damagedFrames }.count,
            analysed: result.analysed, reused: result.reused,
            signaturesMade: state.sigMade, signaturesKept: state.sigKept, signaturesFailed: state.sigFailed,
            printsMade: state.printMade, printsKept: state.printKept, printsFailed: state.printFailed,
            copies: copies, songsInCrate: crate.tracks.count,
            songsPerMinute: seconds > 0 ? Double(result.filesSeen) / seconds * 60 : 0,
            jobs: jobs, device: device, engine: Builder.engineLabel, carriedOn: carriedOn, local: local,
            disc: disc.map(\.current).map { r in
                DiscReport(text: r.text, songs: r.toc.songs.count, named: request.source.flatMap { discNamed[$0] } ?? 0,
                           damagedSectors: r.damagedSectors, titled: r.discTitle != nil, textDetail: r.textDetail)
            }, covers: result.covers,
            fingerprinted: result.fingerprinted, songsWithFingerprint: crate.tracks.filter { $0.fingerprint != nil }.count,
            songsRead: state.tally.figures.songs, filesFound: max(state.total, result.filesSeen))
        state.lock.unlock()
        report.secondsBefore = partsBefore
        report.jobsBy = disc != nil ? DeskJobs.Reason.disc.rawValue : jobsBy?.rawValue
        var line = report
        line.stopped = result.stopped ? true : nil
        try Self.appendRun(line, to: shelf.file(Self.runsFile, of: crateId))
        // A stopped run stays pending, so Carry on reads the rest.
        if !result.stopped { try? DeckieFiles.remove(pendingURL) }
        // "That's the lot" only when it is: a stopped run has more to read.
        if !result.stopped {
            state.lock.lock(); let last = state.tally.finished(); state.lock.unlock()
            emit(.saving, nil, notes: [last])
        }
        return (crate, line)
    }

    static func appendRun(_ r: RunReport, to url: URL) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        var line = try e.encode(r)
        line.append(0x0A)
        try DeckieFiles.append(line, to: url)
    }

    public static func utc(_ d: Date) -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: d)
    }
    public static func utcNow() -> String { utc(Date()) }
}

extension DeskRun {
    /// The names part of the report, made true of the crate as saved: a song the names step after the computer's
    /// (a music CD's CD-Text) named is counted under where its name came from now, no longer under its file name; and
    /// the songs that still need a name are counted on the crate itself.
    static func recount(_ report: inout LocalFacts.Report, before: [String: String?], crate: Crate) {
        func steps(_ source: String?) -> [String] {
            Array(Set((source ?? "").split(separator: "+").map(String.init))).filter { !$0.isEmpty && $0 != "tag" }
        }
        for t in crate.tracks {
            guard let was = before[t.id], was != t.ident.source, t.ident.source != "user" else { continue }
            for s in steps(was) {
                if let n = report.namesFrom[s] { report.namesFrom[s] = n > 1 ? n - 1 : nil }
            }
            for s in steps(t.ident.source) { report.namesFrom[s, default: 0] += 1 }
        }
        report.needName = crate.tracks.filter(LocalFacts.needsName).count
    }

    /// The print of a song's audio as the analysis decoded it: what `portablePrint` makes from the file, from the same
    /// samples (`AudioDecoder.decode` is the analysis's decoder), so the song is decoded once.
    public static let portableAudioPrint: AudioPrintMaker = { _, b in
        RecordingPrint(interleaved: b.samples, channels: b.channelCount, sampleRate: b.sampleRate)
    }

    /// The print of a song's file through the shared decoder (WAV, AIFF, MP3, FLAC), for a desk with no system
    /// decoder of its own; the Mac's desk reads with AVFoundation, which also reads AAC and Apple Lossless.
    public static let portablePrint: PrintMaker = { url in
        let b = try AudioDecoder.decode(url)
        return RecordingPrint(interleaved: b.samples, channels: b.channelCount, sampleRate: b.sampleRate)
    }
}
