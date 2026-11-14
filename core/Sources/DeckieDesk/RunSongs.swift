import Foundation
import DeckieCore
import DeckieCrate
import DeckieBuild

// The run screen's data (D37): what Desk has really found, song by song, as it reads. Both windows draw it: the Mac's
// from `DeskRun` directly, the Windows and Linux pages from the engine's `run.songs` events
// (docs/architecture/desk-protocol.md). Nothing here is decoration: every number is counted from songs Desk read, and
// every sentence a note stands for is true when it is made.

/// A song as the run screen shows it the moment Desk has it: its names as Desk has them then, what Desk found, where
/// it sits, and a small picture of its loudness bar by bar.
public struct RunSong: Codable, Equatable, Sendable {
    /// What Desk decided about the key, exactly as the crate file will say it before the DJ's programs are read: a
    /// key, the home note with major or minor left open, or nothing (not sure). D33, D36.
    public enum KeyKind: String, Codable, Sendable { case key, home, none }
    public struct Key: Codable, Equatable, Sendable {
        public var kind: KeyKind
        /// A key's Camelot code ("8A"); nil for a home note or nothing.
        public var camelot: String?
        /// The home note (a key's tonic, or the home note alone), 0 = C ... 11 = B, and its name ("A", "F#").
        public var note: Int?
        public var name: String?
        /// A key's mode; nil for a home note or nothing.
        public var minor: Bool?
        /// A key from a reader before the three-answer one, under its sure line (shown with "not sure", as the table does).
        public var uncertain: Bool

        public init(kind: KeyKind, camelot: String? = nil, note: Int? = nil, minor: Bool? = nil, uncertain: Bool = false) {
            self.kind = kind; self.camelot = camelot; self.note = note
            self.name = note.map { RunSong.noteNames[$0] }; self.minor = minor; self.uncertain = uncertain
        }
    }

    public var id: String
    /// Joined the screen as this song, from 1: the wall's order.
    public var number: Int
    public var title: String
    public var artist: String?
    /// Tempo in beats per minute and bars, from the beat grid; nil when the song has none.
    public var bpm: Double?
    public var key: Key
    public var bars: Int?
    public var seconds: Double
    /// Where it sits, as the booth shows a place ("Stick 3 / House 4"); nil in the music folder, where `folder` says
    /// which folder ("" its top).
    public var place: String?
    public var folder: String?
    /// The loudness of each stretch of the song's bars, `waveLength` values from 0 (`waveFloorLufs` or quieter) to 99
    /// (`waveCeilLufs` or louder); empty when the song has no beat grid.
    public var wave: [Int]
    /// The bars of its first section, which the engine labels the intro; nil when it labelled none.
    public var introBars: Int?
    /// Worked out before (unchanged since the last run, or read for another crate): not read again now.
    public var before: Bool

    /// 64 values a song: enough to show a song's shape (an intro, a break, a drop, the outro) at the width the stage
    /// draws it, two bars a value for a typical 128-bar song, and small enough that 5,000 songs are about 1 MB of
    /// messages in all. The loudest bar in each stretch is kept, so a short drop is not averaged away.
    public static let waveLength = 64
    /// The loudness scale, the same for every song so the waves compare: per-bar loudness (LUFS, the analysis's `lufs`
    /// series) from -30, near silence for music, to -4, louder than almost any master.
    public static let waveFloorLufs = -30.0, waveCeilLufs = -4.0
    /// The twelve home notes as the run screen names them, C first: DeskWords' `noteName.1` to `noteName.12`.
    public static let noteNames = DeskWords.list("noteName")

    public init(id: String, number: Int = 0, title: String, artist: String?, bpm: Double?, key: Key, bars: Int?,
                seconds: Double, place: String?, folder: String?, wave: [Int], introBars: Int?, before: Bool) {
        self.id = id; self.number = number; self.title = title; self.artist = artist; self.bpm = bpm; self.key = key
        self.bars = bars; self.seconds = seconds; self.place = place; self.folder = folder; self.wave = wave
        self.introBars = introBars; self.before = before
    }

    /// The song from its record (with its per-bar series), the names Desk has for it now and the place it was read.
    public init(_ t: CrateTrack, title: String? = nil, artist: String? = nil, place p: CrateTrack.Place?, before: Bool) {
        let p = p ?? t.ident.ownPlace
        self.init(id: t.id, title: title ?? t.ident.title, artist: title == nil ? t.ident.artist : artist,
                  bpm: t.grid.map { ($0.bpm * 10).rounded() / 10 }, key: Self.key(t.key), bars: t.grid?.nBars,
                  seconds: (t.file.durationS * 10).rounded() / 10,
                  place: Crate.placeLine(p), folder: p.disc == nil ? (p.folder ?? SourceReading.group(of: t.file.rel ?? "")) : nil,
                  wave: Self.wave(t.bars?[BarSeries.lufs]), introBars: Self.introBars(t.sections), before: before)
    }

    /// The key as Desk shows it (LocalFacts' "when sure" rule, D33): the three-answer reader's key when it is sure,
    /// its home note when only that agreed, else nothing; a reading of an earlier reader as it is.
    public static func key(_ k: CrateTrack.Key?) -> Key {
        guard let k, let tonic = Camelot.tonic(k.camelot) else { return Key(kind: .none) }
        if k.source == LocalFacts.threeAnswerSource && k.confidence < 0.5 {
            return k.confidence >= LocalFacts.modeOpenConfidence ? Key(kind: .home, note: tonic.pitchClass) : Key(kind: .none)
        }
        return Key(kind: .key, camelot: k.camelot, note: tonic.pitchClass, minor: !tonic.major, uncertain: k.confidence < 0.5)
    }

    /// `waveLength` values from a per-bar loudness series: the loudest bar of each stretch, on the fixed scale.
    public static func wave(_ lufs: [Double]?) -> [Int] {
        guard let v = lufs?.filter({ $0.isFinite || $0 == -.infinity }), !v.isEmpty else { return [] }
        let n = waveLength
        return (0..<n).map { i in
            let a = i * v.count / n, b = max(a + 1, (i + 1) * v.count / n)
            let loudest = v[a..<min(b, v.count)].max() ?? waveFloorLufs
            let x = (loudest - waveFloorLufs) / (waveCeilLufs - waveFloorLufs)
            return Int((max(0, min(1, x.isFinite ? x : 0)) * 99).rounded())
        }
    }

    static func introBars(_ sections: [CrateTrack.Section]?) -> Int? {
        guard let s = sections?.first, s.label == "intro" else { return nil }
        return s.endBar - s.startBar
    }
}

/// The running totals the run screen's figures draw, each a true count of the songs on the screen so far.
public struct RunFigures: Codable, Equatable, Sendable {
    /// Songs on the screen, and the minutes and seconds of music in them.
    public var songs = 0
    public var seconds = 0.0
    /// Tempos as a histogram: `tempos[i]` counts the songs from `tempoLow + i * tempoStep` up to the next bin; the end
    /// bins also hold anything beyond them. Songs with no beat grid are `noTempo`.
    public var tempoLow = RunFigures.tempoFloor
    public var tempoStep = RunFigures.tempoBin
    public var tempos = [Int](repeating: 0, count: RunFigures.tempoBins)
    public var noTempo = 0
    public var slowest: Double?
    public var fastest: Double?
    /// Keys by home note (0 = C): major, minor, and the home note alone (mode left open); `noKey` not sure.
    public var major = [Int](repeating: 0, count: 12)
    public var minor = [Int](repeating: 0, count: 12)
    public var home = [Int](repeating: 0, count: 12)
    public var noKey = 0
    /// Keys on the wheel found so far, of 24.
    public var keysFound = 0
    /// Songs with no usable title or no artist yet, as Desk has them.
    public var needName = 0
    /// Songs found in more than one place in what is read (the same file's bytes twice).
    public var sameFile = 0
    /// Songs in a group of copies of one recording (D24), known once Desk links them while saving; nil before.
    public var copies: Int?
    /// Files that did not go in.
    public var notIn = 0

    public static let tempoFloor = 50.0, tempoBin = 2.0, tempoBins = 100

    public init() {}
}

/// Something true Desk just found (`fact`) or a real event worth a brief mark (`moment`, D37), as a code with its
/// values; a window says it with the words `fact.<code>` or `moment.<code>` (forms by `n` where there is one).
public struct RunNote: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case fact, moment }
    public var kind: Kind
    public var code: String
    /// The song it is about, if any.
    public var song: String?
    public var n: Int?
    /// The words' blanks, as text: `title`, `bpm`, `bars`, `key`, `note`, `length`, `place`, `songs`, `mode` (the code `major` or `minor`), `seconds` (a length of music in whole seconds, for the window to say in its words).
    public var values: [String: String]

    public init(_ kind: Kind, _ code: String, song: String? = nil, n: Int? = nil, _ values: [String: String] = [:]) {
        self.kind = kind; self.code = code; self.song = song; self.n = n; self.values = values
    }
}

/// Keeps the figures and makes the notes as songs join the screen. One per run; not shared between threads (DeskRun
/// holds it under its lock).
public struct RunTally: Sendable {
    public private(set) var figures = RunFigures()
    private var seen = Set<String>()
    private var longest: Double?, shortest: Double?, longestIntro = 0
    private var rounded: [Int: Int] = [:]
    private var lastTempo: Int?, tempoRun = 0, tempoRunSaid = 0
    private var keysSeen = Set<String>()
    private var hours = 0
    private var wheelSaid = false

    /// Round numbers of songs that are a moment: these, then every thousand.
    public static let milestones = [10, 50, 100, 500, 1000]
    /// Songs on the screen before "so far" facts are made (slowest, fastest, longest, shortest, a new key): fewer is
    /// every song.
    public static let factsFrom = 5, newKeyFrom = 8
    /// An intro this long or longer is worth saying; tempo runs from this many in a row.
    public static let introWorthSaying = 16, tempoRunFrom = 3
    /// Every this many songs, the tempo most of them share, when at least this share of them do.
    public static let commonTempoEvery = 25, commonTempoShare = 0.2
    /// Keys found so far worth a line (24 is the wheel's moment).
    public static let keysWorthSaying = [6, 12, 18]

    public init() {}

    /// Whether a song of this id is on the screen already.
    public func has(_ id: String) -> Bool { seen.contains(id) }

    /// A song joins the screen: its number, the figures, and what is true of it now.
    public mutating func add(_ song: inout RunSong) -> [RunNote] {
        guard seen.insert(song.id).inserted else { return [] }
        var f = figures
        f.songs += 1
        song.number = f.songs
        f.seconds += song.seconds
        var notes: [RunNote] = []
        let title = ["title": song.title]
        func fact(_ code: String, _ v: [String: String] = [:], n: Int? = nil) {
            notes.append(RunNote(.fact, code, song: song.id, n: n, title.merging(v) { _, b in b }))
        }

        // Tempo.
        if let bpm = song.bpm {
            let i = Int(((bpm - f.tempoLow) / f.tempoStep).rounded(.down))
            f.tempos[max(0, min(f.tempos.count - 1, i))] += 1
            let r = Int(bpm.rounded())
            rounded[r, default: 0] += 1
            let enough = f.songs >= Self.factsFrom
            if let s = f.slowest, bpm < s - 0.5, enough { fact("slowest", ["bpm": String(r)]) }
            if let s = f.fastest, bpm > s + 0.5, enough { fact("fastest", ["bpm": String(r)]) }
            f.slowest = min(f.slowest ?? bpm, bpm); f.fastest = max(f.fastest ?? bpm, bpm)
            if r == lastTempo { tempoRun += 1 } else { lastTempo = r; tempoRun = 1; tempoRunSaid = 0 }
            if tempoRun >= Self.tempoRunFrom && tempoRun > tempoRunSaid {
                tempoRunSaid = tempoRun
                fact("tempoRun", ["bpm": String(r)], n: tempoRun)
            }
        } else {
            f.noTempo += 1; lastTempo = nil; tempoRun = 0
        }

        // Key.
        switch song.key.kind {
        case .key:
            if let note = song.key.note, let minor = song.key.minor {
                if minor { f.minor[note] += 1 } else { f.major[note] += 1 }
                let code = song.key.camelot ?? ""
                if keysSeen.insert(code).inserted && f.songs >= Self.newKeyFrom {
                    fact("newKey", ["key": code, "note": song.key.name ?? "", "mode": minor ? "minor" : "major"])
                }
            }
        case .home:
            if let note = song.key.note { f.home[note] += 1 }
            fact("homeNote", ["note": song.key.name ?? ""])
        case .none:
            f.noKey += 1
            fact("notSure")
        }

        // Length and intro.
        let enough = f.songs >= Self.factsFrom
        if let l = longest, song.seconds > l + 1, enough { fact("longest", ["length": Self.clock(song.seconds)]) }
        if let s = shortest, song.seconds < s - 1, enough { fact("shortest", ["length": Self.clock(song.seconds)]) }
        longest = max(longest ?? song.seconds, song.seconds); shortest = min(shortest ?? song.seconds, song.seconds)
        if let intro = song.introBars, intro >= Self.introWorthSaying, intro > longestIntro {
            longestIntro = intro
            if f.songs > 1 { fact("longestIntro", ["bars": String(intro)]) }
        }

        // Names.
        // LocalFacts.needsName's rule, on the names as they are now.
        if !LocalNames.isUsableTitle(song.title) || !LocalNames.isUsableArtist(song.artist) {
            f.needName += 1
            if f.needName == 1 { fact("needName") }
        }

        // The tempo most share, now and then.
        if f.songs % Self.commonTempoEvery == 0, let top = rounded.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }),
           Double(top.value) >= Double(f.songs - f.noTempo) * Self.commonTempoShare, top.value > 1 {
            notes.append(RunNote(.fact, "commonTempo", n: top.value, ["bpm": String(top.key), "songs": String(f.songs)]))
        }

        // Moments.
        if f.songs == 1 { notes.append(RunNote(.moment, "first", song: song.id, title)) }
        if Self.milestones.contains(f.songs) || (f.songs > 1000 && f.songs % 1000 == 0) {
            notes.append(RunNote(.moment, "songs", n: f.songs, ["n": Self.grouped(f.songs)]))
        }
        let h = Int(f.seconds / 3600)
        if h > hours { hours = h; notes.append(RunNote(.moment, "hour", n: h)) }
        f.keysFound = f.major.filter { $0 > 0 }.count + f.minor.filter { $0 > 0 }.count
        if !wheelSaid && f.keysFound == 24 { wheelSaid = true; notes.append(RunNote(.moment, "wheel")) }
        let k = f.keysFound
        if k != figures.keysFound && Self.keysWorthSaying.contains(k) { notes.append(RunNote(.fact, "keysFound", n: k)) }
        figures = f
        return notes
    }

    /// A song already on the screen was found in another place of what is read: the same file twice.
    public mutating func again(_ id: String, title: String, place: String?) -> [RunNote] {
        guard seen.contains(id) else { return [] }
        figures.sameFile += 1
        var v = ["title": title]
        if let place { v["place"] = place }
        return [RunNote(.fact, "twoPlaces", song: id, v)]
    }

    /// A file did not go in.
    public mutating func notIn() { figures.notIn += 1 }

    /// Copies of one recording linked while saving: entries in a group of copies.
    public mutating func copies(_ n: Int) -> [RunNote] {
        figures.copies = n
        return n > 0 ? [RunNote(.fact, "copies", n: n)] : []
    }

    /// The songs still needing a name once Desk has looked for names on the computer (while saving).
    public mutating func needName(_ n: Int) { figures.needName = n }

    /// A music CD read to its end.
    public func discRead() -> RunNote { RunNote(.moment, "disc", n: figures.songs) }

    /// The run finished.
    public func finished() -> RunNote {
        RunNote(.moment, "finished", n: figures.songs, ["seconds": String(Int(figures.seconds.rounded()))])
    }

    /// 4:05, 61:00.
    public static func clock(_ s: Double) -> String {
        let t = Int(s.rounded())
        return "\(t / 60):" + String(format: "%02d", t % 60)
    }

    /// 1,000 and 12,500.
    public static func grouped(_ n: Int) -> String {
        var s = String(n), out = ""
        while s.count > 3 { out = "," + s.suffix(3) + out; s = String(s.dropLast(3)) }
        return s + out
    }
}
