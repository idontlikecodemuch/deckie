import Foundation
import DeckieCrate
import DeckieBuild

/// Naming a song (research AA, route A: nothing leaves the computer), as both windows show it: where each of a song's
/// names came from, field by field; whether it still needs a name and why; the DJ's own names kept apart from Desk's
/// guesses; and the batch tools (a pasted list, a pattern over the file names, a playlist, "Looks right"), each a
/// preview with a tick per field, applied as one step of undo.
///
/// The crate file is not changed: it keeps a song's title, artist and version, and one `ident.source` for the name as
/// before. Where each field came from, and a song's release, live in Desk's own storage (`names.json` beside the
/// crate, `NameBook`), and the DJ's own names in `corrections.json` (`NameCorrections`), each field with how the DJ
/// gave it.
public enum DeskNaming {
    /// The fields a DJ names.
    public static let fields = ["title", "artist", "version"]

    /// Origins that are Desk's guess (letter AA, 3.3: "named from a file name, a folder, a list or the disc; worth a
    /// glance"): shown lighter, marked "Desk's guess", in the list until the DJ has looked once.
    public static let guessOrigins: Set<String> = ["filename", "folder", "cue", "m3u", "tracklist", "cdtext"]

    /// Origins of names the DJ gave (never changed by Desk): typed, a pasted list, a pattern the DJ set, a playlist
    /// the DJ chose, or a guess the DJ checked.
    public static let djOrigins: Set<String> = ["user", "pasted", "pattern", "playlist", "checked"]

    // MARK: where each field came from

    /// One fact about a song as the panel shows it: its value, where it came from (a code: `tag`, `filename`,
    /// `cdtext`, `user`, ...; words `factFrom.<code>`), whether it is Desk's guess, and whether the DJ checked a guess.
    public struct Fact: Codable, Equatable, Sendable {
        public var value: String?
        public var from: String?
        public var guess: Bool
        public var checked: Bool
        public init(value: String?, from: String?, guess: Bool = false, checked: Bool = false) {
            self.value = value; self.from = from; self.guess = guess; self.checked = checked
        }
    }

    /// A song's names as the panel shows them.
    public struct Facts: Codable, Equatable, Sendable {
        public var title: Fact
        public var artist: Fact
        public var version: Fact
        public var release: Fact
        public func fact(_ field: String) -> Fact {
            switch field { case "artist": return artist; case "version": return version; case "release": return release; default: return title }
        }
    }

    /// Why a song is in the "Needs a name" list (letter AA, 3.3): `noTitle` (nothing usable, or a placeholder such as
    /// "Track 01"), `noArtist` (a title and nothing else), `guess` (named by Desk from a file name, a folder, a list
    /// or the disc, not yet checked); nil when it is not in the list. Words `nameReason.<code>`.
    public static func reason(_ t: CrateTrack, _ f: Facts) -> String? {
        if !LocalNames.isUsableTitle(t.ident.title) { return "noTitle" }
        if !LocalNames.isUsableArtist(t.ident.artist) { return "noArtist" }
        if [f.title, f.artist, f.version].contains(where: { $0.guess && $0.value != nil }) { return "guess" }
        return nil
    }

    public static func facts(_ t: CrateTrack, book: NameBook, corrections: NameCorrections) -> Facts {
        let read = book.byId[t.id]
        let fix = corrections.byId[t.id]
        func fact(_ field: String, _ value: String?) -> Fact {
            let fixed: Bool
            switch field {
            case "title": fixed = fix?.title != nil
            case "artist": fixed = fix?.artist != nil
            default: fixed = fix?.version != nil
            }
            let readFrom = read?.from(field) ?? derived(t, field)
            if fixed {
                let how = fix?.from?[field] ?? "user"
                if how == "checked" { return Fact(value: value, from: readFrom, checked: true) }
                return Fact(value: value, from: how)
            }
            guard value != nil else { return Fact(value: nil, from: nil) }
            return Fact(value: value, from: readFrom, guess: readFrom.map(guessOrigins.contains) ?? false)
        }
        let title = fact("title", LocalNames.isUsableTitle(t.ident.title) ? t.ident.title : nil)
        return Facts(title: title, artist: fact("artist", t.ident.artist), version: fact("version", t.ident.version),
                     release: Fact(value: read?.release, from: read?.releaseFrom))
    }

    /// A field's origin as `ident.source` says it: its first part for the title (and version), its second, when it
    /// has two ("filename+folder"), for the artist.
    static func derived(_ t: CrateTrack, _ field: String) -> String? {
        guard let s = t.ident.source, s != "user" else { return nil }
        let parts = s.split(separator: "+").map(String.init)
        if field == "artist" { return t.ident.artist == nil ? nil : (parts.count > 1 ? parts[1] : parts[0]) }
        return parts[0]
    }

    // MARK: typed names

    /// "Artist - Title (Version)" typed into the title, split as the file-name grammar does (letter B; AA 3.5): the
    /// artist before the first " - " when both sides are usable, a version in round or square brackets at the end.
    /// Nil when there is nothing to split.
    public static func split(_ text: String) -> (artist: String?, title: String, version: String?)? {
        let s = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " – ", with: " - ").replacingOccurrences(of: " — ", with: " - ")
        var artist: String? = nil
        var rest = s
        let parts = s.components(separatedBy: " - ")
        if parts.count >= 2 {
            let a = parts[0].trimmingCharacters(in: .whitespaces)
            let r = parts.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            if LocalNames.isUsableArtist(a) && LocalNames.isUsableTitle(r) { artist = a; rest = r }
        }
        let (title, version) = splitVersion(rest)
        guard artist != nil || version != nil else { return nil }
        return (artist, title, version)
    }

    /// A version in brackets at the end of a title: "Night drive (Extended mix)" is "Night drive" and "Extended mix".
    public static func splitVersion(_ s: String) -> (title: String, version: String?) {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let last = t.last, last == ")" || last == "]" else { return (t, nil) }
        let open: Character = last == ")" ? "(" : "["
        guard let i = t.lastIndex(of: open), i > t.startIndex else { return (t, nil) }
        let title = t[..<i].trimmingCharacters(in: .whitespaces)
        let version = t[t.index(after: i)..<t.index(before: t.endIndex)].trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, !version.isEmpty else { return (t, nil) }
        return (title, version)
    }

    // MARK: the batch tools

    /// One change a batch tool proposes: a field of a song, what it holds now and what it would hold.
    public struct Change: Codable, Equatable, Sendable {
        public var song: String
        public var field: String
        public var before: String?
        public var after: String?
        /// Ticked to be applied. By default only where the field is empty (or a placeholder title) or holds Desk's
        /// own guess; a DJ's own name is never offered (`locked`).
        public var tick: Bool
        public var locked: Bool
        /// Why it is not ticked, as a code: `filled` (it has a name), `yours` (the DJ's own), `lengthDiffers`.
        public var note: String?
    }

    /// What a tool would do, shown before anything changes. `problem` (a code) stops it being applied: `counts` (the
    /// list and the songs differ in number), `noMatch` (the pattern fits no file name), `empty`.
    public struct Preview: Codable, Equatable, Sendable {
        public var tool: String
        public var songs: Int
        public var lines: Int
        public var changes: [Change]
        public var problem: String?
        /// For a playlist: songs whose length differs from their line's by more than the allowance; nil when the
        /// playlist gave no lengths.
        public var lengthsDiffer: Int?
        /// Each song in order, with the line the tool paired it with, for the preview's table.
        public var pairs: [Pair]
        public struct Pair: Codable, Equatable, Sendable {
            public var song: String
            public var line: String?
            public var seconds: Double?
            public var listSeconds: Double?
        }
    }

    /// A song as a tool sees it: its names now and what the DJ gave.
    public struct Song {
        public var track: CrateTrack
        public var facts: Facts
        public init(track: CrateTrack, facts: Facts) { self.track = track; self.facts = facts }
    }

    /// A line of a list, read: an optional leading number ("01.", "1)", "02 -") taken off, then the file-name grammar.
    public static func readLine(_ raw: String) -> (artist: String?, title: String, version: String?) {
        var line = raw.trimmingCharacters(in: .whitespaces)
        let digits = line.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 3 {
            let after = line.dropFirst(digits.count)
            if let sep = after.first, " .-):\t".contains(sep) {
                let rest = String(after.drop { " .-):\t".contains($0) })
                if !rest.isEmpty { line = rest }
            }
        }
        if let s = split(line) { return s }
        return (nil, line, nil)
    }

    /// The changes that would give `song` these names. A field is not offered when the name would not change it; a
    /// DJ's own field is shown locked; a field that already has a name is shown unticked unless `onlyEmpty` is off;
    /// a version is never taken away (a new name with no version keeps the song's own, D24's "versions are separate
    /// songs").
    static func changes(for song: Song, artist: String?, title: String?, version: String?, onlyEmpty: Bool) -> [Change] {
        var out: [Change] = []
        let t = song.track
        let current: [String: String?] = ["title": t.ident.title, "artist": t.ident.artist, "version": t.ident.version]
        let wanted: [String: String?] = ["title": title, "artist": artist, "version": version]
        for field in fields {
            guard let new = wanted[field] ?? nil, !new.isEmpty else { continue }
            let before = current[field] ?? nil
            guard new != before else { continue }
            let fact = song.facts.fact(field)
            let empty = field == "title" ? !LocalNames.isUsableTitle(before) : (before ?? "").isEmpty
            let yours = fact.from.map(djOrigins.contains) == true || fact.checked
            let guess = fact.guess
            var c = Change(song: t.id, field: field, before: before, after: new, tick: false, locked: yours, note: nil)
            if yours { c.note = "yours" }
            else if empty || guess || !onlyEmpty { c.tick = true }
            else { c.note = "filled" }
            out.append(c)
        }
        return out
    }

    /// "Paste a list…" (letter AA, 3.6): one line a song, in order, lined up with the songs by place. If the counts
    /// differ nothing can be applied until the DJ fixes the list.
    public static func pasteList(_ text: String, songs: [Song], onlyEmpty: Bool = true) -> Preview {
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var p = Preview(tool: "paste", songs: songs.count, lines: lines.count, changes: [], problem: nil, lengthsDiffer: nil, pairs: [])
        for (i, s) in songs.enumerated() {
            p.pairs.append(.init(song: s.track.id, line: i < lines.count ? lines[i] : nil, seconds: s.track.file.durationS, listSeconds: nil))
        }
        if lines.isEmpty { p.problem = "empty"; return p }
        if lines.count != songs.count { p.problem = "counts"; return p }
        for (s, line) in zip(songs, lines) {
            let r = readLine(line)
            p.changes += changes(for: s, artist: r.artist, title: r.title, version: r.version, onlyEmpty: onlyEmpty)
        }
        return p
    }

    /// The patterns offered for "Names from the file names…", most common first. `{artist}`, `{title}`, `{version}`
    /// and `{number}` are the parts; anything else must match the file name as written.
    public static let patterns = ["{number} {artist} - {title}", "{artist} - {title}", "{number} {title}", "{title}",
                                  "{number} - {artist} - {title}", "{title} - {artist}"]

    /// A file name's stem read by a pattern, or nil when it does not fit. Each part runs up to the first place the
    /// text after it appears; `{number}` is digits; a title's version in brackets is split off.
    public static func match(_ stem: String, pattern: String) -> (artist: String?, title: String?, version: String?)? {
        enum Piece { case text(String), part(String) }
        var pieces: [Piece] = []
        var rest = Substring(pattern)
        while !rest.isEmpty {
            if rest.first == "{", let close = rest.firstIndex(of: "}") {
                pieces.append(.part(String(rest[rest.index(after: rest.startIndex)..<close])))
                rest = rest[rest.index(after: close)...]
            } else {
                let next = rest.dropFirst().firstIndex(of: "{") ?? rest.endIndex
                pieces.append(.text(String(rest[..<next])))
                rest = rest[next...]
            }
        }
        var s = Substring(stem.replacingOccurrences(of: "_", with: stem.contains(" ") ? "_" : " "))
        var got: [String: String] = [:]
        for (i, piece) in pieces.enumerated() {
            switch piece {
            case let .text(lit):
                guard s.hasPrefix(lit) else { return nil }
                s = s.dropFirst(lit.count)
            case let .part(name):
                let value: Substring
                if name == "number" {
                    value = s.prefix { $0.isASCII && $0.isNumber }
                    guard !value.isEmpty else { return nil }
                } else if i + 1 < pieces.count, case let .text(lit) = pieces[i + 1] {
                    guard let r = s.range(of: lit) else { return nil }
                    value = s[..<r.lowerBound]
                } else {
                    value = s
                }
                got[name] = value.trimmingCharacters(in: .whitespaces)
                s = s.dropFirst(value.count)
            }
        }
        guard s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        var title = got["title"].flatMap { $0.isEmpty ? nil : $0 }
        var version = got["version"].flatMap { $0.isEmpty ? nil : $0 }
        if let t = title, version == nil { let v = splitVersion(t); title = v.title; version = v.version }
        let artist = got["artist"].flatMap { $0.isEmpty ? nil : $0 }
        guard title != nil || artist != nil else { return nil }
        return (artist, title, version)
    }

    /// "Names from the file names…": each song's file name read by the pattern; before and after for every song.
    public static func fromFileNames(pattern: String, songs: [Song], onlyEmpty: Bool = true) -> Preview {
        var p = Preview(tool: "pattern", songs: songs.count, lines: 0, changes: [], problem: nil, lengthsDiffer: nil, pairs: [])
        var fitted = 0
        for s in songs {
            let stem = (s.track.file.name as NSString).deletingPathExtension
            p.pairs.append(.init(song: s.track.id, line: stem, seconds: s.track.file.durationS, listSeconds: nil))
            guard let m = match(stem, pattern: pattern) else { continue }
            fitted += 1
            p.changes += changes(for: s, artist: m.artist, title: m.title, version: m.version, onlyEmpty: onlyEmpty)
        }
        p.lines = fitted
        if fitted == 0 { p.problem = "noMatch" }
        return p
    }

    /// An entry of a playlist file: its length when the playlist gives one, and its name.
    public struct ListedSong: Equatable, Sendable {
        public var seconds: Double?
        public var line: String
    }

    /// An extended M3U playlist's entries, in order (`#EXTINF:<seconds>,<Artist - Title>` before each path; an entry
    /// with no EXTINF line is named by its file's name).
    public static func readPlaylist(_ text: String) -> [ListedSong] {
        var out: [ListedSong] = []
        var pending: (Double?, String)? = nil
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.uppercased().hasPrefix("#EXTINF:") {
                let body = line.dropFirst(8)
                let comma = body.firstIndex(of: ",")
                let secs = Double((comma.map { body[..<$0] } ?? body).trimmingCharacters(in: .whitespaces))
                let name = comma.map { String(body[body.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
                pending = (secs.flatMap { $0 > 0 ? $0 : nil }, name)
            } else if line.hasPrefix("#") || line.isEmpty {
                continue
            } else {
                let file = (PathKey.lastName(line.hasPrefix("file://") ? (URL(string: line)?.path ?? line) : line) as NSString).deletingPathExtension
                if let (secs, name) = pending, !name.isEmpty { out.append(ListedSong(seconds: secs, line: name)) }
                else { out.append(ListedSong(seconds: pending?.0, line: file)) }
                pending = nil
            }
        }
        return out
    }

    /// Two lengths count as the same recording's when they are within this many seconds (letter AA, 6.4: about three
    /// seconds for a version; a playlist's lengths are whole seconds).
    public static let lengthAllowance = 3.0

    /// "Names from a playlist…" (letter AA, 1.2: a burned disc was almost always made from a playlist): the playlist's
    /// entries lined up with the songs in order, and each length checked. A song whose length is off is shown
    /// unticked.
    public static func fromPlaylist(_ entries: [ListedSong], songs: [Song], onlyEmpty: Bool = true) -> Preview {
        var p = Preview(tool: "playlist", songs: songs.count, lines: entries.count, changes: [], problem: nil, lengthsDiffer: nil, pairs: [])
        for (i, s) in songs.enumerated() {
            let e = i < entries.count ? entries[i] : nil
            p.pairs.append(.init(song: s.track.id, line: e?.line, seconds: s.track.file.durationS, listSeconds: e?.seconds))
        }
        if entries.isEmpty { p.problem = "empty"; return p }
        if entries.count != songs.count { p.problem = "counts"; return p }
        var differ = 0
        let haveLengths = entries.contains { $0.seconds != nil }
        for (s, e) in zip(songs, entries) {
            let r = readLine(e.line)
            var cs = changes(for: s, artist: r.artist, title: r.title, version: r.version, onlyEmpty: onlyEmpty)
            if let secs = e.seconds, abs(secs - s.track.file.durationS) > lengthAllowance {
                differ += 1
                for i in cs.indices where !cs[i].locked { cs[i].tick = false; cs[i].note = "lengthDiffers" }
            }
            p.changes += cs
        }
        p.lengthsDiffer = haveLengths ? differ : nil
        return p
    }

    /// "Looks right" on a selection (letter AA, 3.3): every guess among those songs, checked as it is.
    public static func looksRight(songs: [Song]) -> Preview {
        var p = Preview(tool: "check", songs: songs.count, lines: 0, changes: [], problem: nil, lengthsDiffer: nil, pairs: [])
        for s in songs {
            for field in fields {
                let f = s.facts.fact(field)
                guard f.guess, let v = f.value else { continue }
                p.changes.append(Change(song: s.track.id, field: field, before: v, after: v, tick: true, locked: false, note: nil))
            }
        }
        return p
    }

    /// Applies the ticked changes of a preview to `crate` and `corrections` (one step of undo for the caller): each
    /// field becomes the DJ's, marked with how it was given (`pasted`, `pattern`, `playlist`, `checked`). Locked
    /// changes are never applied. Returns how many songs changed.
    @discardableResult
    public static func apply(_ preview: Preview, ticks: Set<Int>? = nil, to crate: inout Crate,
                             corrections: inout NameCorrections) -> Int {
        guard preview.problem == nil else { return 0 }
        let how = preview.tool == "check" ? "checked" : (preview.tool == "paste" ? "pasted" : preview.tool)
        var songs = Set<String>()
        for (i, c) in preview.changes.enumerated() {
            let on = ticks.map { $0.contains(i) } ?? c.tick
            guard on, !c.locked, let value = c.after,
                  let ti = crate.tracks.firstIndex(where: { $0.id == c.song }) else { continue }
            var t = crate.tracks[ti]
            switch c.field {
            case "title": t.ident.title = value
            case "artist": t.ident.artist = value
            case "version": t.ident.version = value
            default: continue
            }
            t.ident.source = "user"
            crate.tracks[ti] = t
            corrections.give(c.song, field: c.field, value: value, how: how)
            songs.insert(c.song)
        }
        return songs.count
    }
}

/// Where each of a song's names was read from, field by field, and its release (`names.json` in the crate's folder).
/// Written after every run and every "Look again", from what the reading found, before the DJ's own names are put
/// back. Names the DJ gave are in `corrections.json`.
public struct NameBook: Codable, Equatable, Sendable {
    public struct Read: Codable, Equatable, Sendable {
        public var title: String?
        public var artist: String?
        public var version: String?
        public var release: String?
        public var releaseFrom: String?
        func from(_ field: String) -> String? {
            switch field { case "artist": return artist; case "version": return version; default: return title }
        }
        enum CodingKeys: String, CodingKey { case title, artist, version, release, releaseFrom = "release_from" }
    }
    public var byId: [String: Read]
    public init(byId: [String: Read] = [:]) { self.byId = byId }
    enum CodingKeys: String, CodingKey { case byId = "by_id" }

    public static let file = "names.json"
    public static func load(from url: URL) -> NameBook { JSONFile.read(Self.self, from: url) ?? NameBook() }
    public func save(to url: URL) throws { try JSONFile.write(self, to: url) }

    /// Notes where a song's names came from before the DJ changes one, when nothing was noted yet (a crate read before
    /// the book was kept), so the fields the DJ does not touch keep their small lines.
    public mutating func keep(_ t: CrateTrack) {
        guard byId[t.id] == nil, t.ident.source != "user" else { return }
        var r = Read()
        r.title = DeskNaming.derived(t, "title")
        r.artist = DeskNaming.derived(t, "artist")
        r.version = t.ident.version == nil ? nil : r.title
        byId[t.id] = r
    }

    /// Notes where each song's names came from as the reading left them (`ident.source`, before the DJ's names are
    /// put back), and its release (`releases`, by id: the value and where from). A song whose names are the DJ's
    /// already keeps what was noted before.
    public mutating func record(_ crate: Crate, releases: [String: (String, String)]) {
        var next: [String: Read] = [:]
        for t in crate.tracks {
            if t.ident.source == "user" { if let old = byId[t.id] { next[t.id] = old }; continue }
            var r = Read()
            r.title = DeskNaming.derived(t, "title")
            r.artist = DeskNaming.derived(t, "artist")
            r.version = t.ident.version == nil ? nil : r.title
            if let rel = releases[t.id] { r.release = rel.0; r.releaseFrom = rel.1 }
            next[t.id] = r
        }
        byId = next
    }
}

extension NameCorrections {
    /// Records a field the DJ gave, and how (`user`, `pasted`, `pattern`, `playlist`, `checked`).
    public mutating func give(_ id: String, field: String, value: String?, how: String) {
        var c = byId[id] ?? NameCorrection()
        switch field {
        case "title": c.title = value
        case "artist": c.artist = .init(value)
        case "version": c.version = .init(value)
        default: return
        }
        var f = c.from ?? [:]
        f[field] = how
        c.from = f
        byId[id] = c
    }
}

/// Listening to name a song (D33; letter AA, 3.7): the rules both windows follow; the playing is each window's own
/// (the Mac's system player, the web view's on Windows and Linux).
public enum DeskListen {
    /// Where listening starts: a third of the way in, as the first half minute of a dance record is often drums alone.
    public static func start(_ seconds: Double) -> Double { seconds > 0 ? (seconds / 3).rounded(.down) : 0 }
    /// The step of the back and forward buttons.
    public static let step = 30.0
}
