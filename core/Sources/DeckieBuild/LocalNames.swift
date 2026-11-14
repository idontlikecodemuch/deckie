import Foundation
import DeckieCrate

/// The free, local ways to a song's name (D30; research W section 6.2) that read text: whether a title or an artist is
/// usable, a file name read by pattern, a folder read as the artist, the key Mixed In Key writes into a comment or a
/// title, and the tracklist files kept beside the music. Nothing here leaves the computer.
public enum LocalNames {
    // MARK: usable names

    /// A title that names the song: not empty, not only a number, and not a placeholder such as "Track 01",
    /// "Audio Track 3", "Untitled" or "Unknown". The rule is the crate file's own (`SongName`), so the booth agrees.
    public static func isUsableTitle(_ s: String?) -> Bool { SongName.isUsableTitle(s) }

    /// An artist that names someone: not empty, and not "Unknown Artist", "Various Artists" or the like.
    public static func isUsableArtist(_ s: String?) -> Bool { SongName.isUsableArtist(s) }

    // MARK: file names

    /// What a file name says, read by pattern. `number` is the song's place number (on a source, the number a player
    /// shows) or its track number tag: a leading number in the name is taken off only when it is that number ("02
    /// Song A" at place 2 is "Song A"; at place 5 it stays "02 Song A", which is then not split further). Underscores
    /// stand for spaces in a name with none. A Camelot or Open Key code at the front, and a tempo after it, as Mixed
    /// In Key may rename files ("8A - 128 - Artist - Title"), are taken off. Then "Artist - Title" is split at its first
    /// " - " when both sides are usable.
    public static func fromFileName(_ stem: String, number: Int?) -> (title: String, artist: String?) {
        var s = stem
        if !s.contains(" ") && s.contains("_") { s = s.replacingOccurrences(of: "_", with: " ") }
        s = collapse(s.replacingOccurrences(of: " – ", with: " - ").replacingOccurrences(of: " — ", with: " - "))
        // Mixed In Key's renaming: a key, and maybe a tempo, in front.
        var parts = s.components(separatedBy: " - ")
        if parts.count >= 2, KeyNotation.wheelOnly(parts[0]) != nil {
            parts.removeFirst()
            if parts.count >= 2, Double(parts[0].trimmingCharacters(in: .whitespaces)) != nil { parts.removeFirst() }
            s = parts.joined(separator: " - ")
        }
        // A leading track number.
        let digits = s.prefix { $0.isASCII && $0.isNumber }
        if !digits.isEmpty, digits.count <= 3 {
            var rest = s.dropFirst(digits.count)
            let separated = rest.first.map { " .-_)".contains($0) } ?? false
            if separated {
                rest = rest.drop { " .-_)".contains($0) }
                if let n = Int(digits), n == number, !rest.isEmpty {
                    s = String(rest)
                } else {
                    return (s, nil)
                }
            }
        }
        let split = s.components(separatedBy: " - ")
        if split.count >= 2 {
            let artist = split[0].trimmingCharacters(in: .whitespaces)
            let title = split.dropFirst().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            if isUsableArtist(artist) && isUsableTitle(title) { return (title, artist) }
        }
        return (s.trimmingCharacters(in: .whitespaces), nil)
    }

    /// The artist a folder's name gives, when the pattern is clear: the folder is named "Artist - Album" and the file
    /// in it is numbered, as an album's files are. Nil otherwise (a folder named "House" or "Friday" names no one).
    public static func artist(fromFolder folder: String, fileName stem: String) -> String? {
        guard let first = stem.first, first.isASCII, first.isNumber else { return nil }
        let parts = collapse(folder.replacingOccurrences(of: " – ", with: " - ")).components(separatedBy: " - ")
        guard parts.count >= 2 else { return nil }
        let artist = parts[0].trimmingCharacters(in: .whitespaces)
        return isUsableArtist(artist) && !artist.allSatisfy({ $0.isNumber }) ? artist : nil
    }

    static func collapse(_ s: String) -> String {
        var t = s
        while t.contains("  ") { t = t.replacingOccurrences(of: "  ", with: " ") }
        return t.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Mixed In Key's keys in a comment or a title

    /// The key Mixed In Key writes into the comment: the comment is a key ("8A", "Am"), or a key and the energy ("8A -
    /// Energy 6", "Energy 6 - 8A"), or a key then other words after " - " or "/" ("1A - 128"). Nil when the comment
    /// does not start or end that way.
    public static func key(inComment comment: String) -> String? {
        let c = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if let k = KeyNotation.camelot(c) { return k }
        let parts = c.components(separatedBy: " - ").flatMap { $0.components(separatedBy: "/") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 2 else { return nil }
        if let k = KeyNotation.camelot(parts[0]) { return k }
        if parts[0].lowercased().hasPrefix("energy"), let k = KeyNotation.camelot(parts[parts.count - 1]) { return k }
        return nil
    }

    /// A key written into the title by Mixed In Key, in front ("8A - Title", "8A - 128 - Title") or at the end
    /// ("Title - 8A"): only Camelot and Open Key codes, never a musical name, which could be the title's own word. The
    /// key and the title without it, or nil.
    public static func key(inTitle title: String) -> (camelot: String, title: String)? {
        var parts = title.components(separatedBy: " - ")
        guard parts.count >= 2 else { return nil }
        if let k = KeyNotation.wheelOnly(parts[0]) {
            parts.removeFirst()
            if parts.count >= 2, Double(parts[0].trimmingCharacters(in: .whitespaces)) != nil { parts.removeFirst() }
            let rest = parts.joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : (k, rest)
        }
        if let k = KeyNotation.wheelOnly(parts[parts.count - 1]) {
            let rest = parts.dropLast().joined(separator: " - ").trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : (k, rest)
        }
        return nil
    }

    // MARK: tracklist files beside the music

    /// A name a tracklist file gives a song.
    public struct Listed: Equatable, Sendable {
        public var title: String?
        public var artist: String?
        /// `cue`, `m3u` or `tracklist` (a numbered list in a .txt or .nfo file).
        public var origin: String
        public init(title: String?, artist: String?, origin: String) { self.title = title; self.artist = artist; self.origin = origin }
    }

    /// The names the tracklist files in one folder give: by file name (a `.cue` sheet's `FILE`, an `.m3u` or `.m3u8`
    /// playlist's entries, compared by name without case), and by number (a numbered list in a `.txt` or `.nfo` file).
    public struct Tracklists: Sendable {
        public var byFileName: [String: Listed] = [:]
        public var byNumber: [Int: Listed] = [:]
        public init() {}

        /// The name for the file `fileName` whose number is `number` (its leading number, else its place number).
        public func name(fileName: String, number: Int?) -> Listed? {
            byFileName[fileName.lowercased()] ?? number.flatMap { byNumber[$0] }
        }

        /// Reads every tracklist file in `folder` (files under 1 MB). Nothing is written.
        public static func read(folder: URL) -> Tracklists {
            var t = Tracklists()
            let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names.sorted() {
                let ext = (name as NSString).pathExtension.lowercased()
                guard ["cue", "m3u", "m3u8", "txt", "nfo"].contains(ext) else { continue }
                let u = folder.appendingPathComponent(name)
                guard let size = (try? FileManager.default.attributesOfItem(atPath: u.path))?[.size] as? Int, size < 1 << 20,
                      let data = try? Data(contentsOf: u) else { continue }
                let text = decode(data)
                switch ext {
                case "cue": t.byFileName.merge(cue(text)) { a, _ in a }
                case "m3u", "m3u8": t.byFileName.merge(m3u(text)) { a, _ in a }
                default: t.byNumber.merge(numberedList(text)) { a, _ in a }
                }
            }
            return t
        }
    }

    /// Text as UTF-8, else Latin-1 (old .nfo and .cue files), a byte-order mark taken off.
    static func decode(_ data: Data) -> String {
        var d = data
        if d.starts(with: [0xEF, 0xBB, 0xBF]) { d = d.dropFirst(3) }
        return String(data: d, encoding: .utf8) ?? String(d.map { Character(Unicode.Scalar($0)) })
    }

    /// A cue sheet: each `FILE`'s `TRACK`s with `TITLE` and `PERFORMER`; the sheet's own `TITLE` and `PERFORMER` (before
    /// the first `FILE`) are the album's. A file with one track is named by that track (its performer, else the
    /// album's); a file with several (a continuous mix) is named by the sheet's own title and performer, the songs
    /// inside it being no song of the crate.
    static func cue(_ text: String) -> [String: Listed] {
        var albumTitle: String? = nil, albumPerformer: String? = nil
        var files: [(name: String, tracks: [(title: String?, performer: String?)])] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let upper = line.uppercased()
            func value() -> String? {
                guard let sp = line.firstIndex(of: " ") else { return nil }
                var v = line[line.index(after: sp)...].trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("\""), let end = v.dropFirst().firstIndex(of: "\"") { v = String(v[v.index(after: v.startIndex)..<end]) }
                return nonEmpty(v)
            }
            if upper.hasPrefix("FILE ") {
                guard let v = value() else { continue }
                files.append((PathKey.lastName(v), []))
            } else if upper.hasPrefix("TRACK "), !files.isEmpty {
                files[files.count - 1].tracks.append((nil, nil))
            } else if upper.hasPrefix("TITLE ") {
                if let f = files.indices.last, !files[f].tracks.isEmpty { files[f].tracks[files[f].tracks.count - 1].title = value() }
                else if files.isEmpty { albumTitle = value() }
            } else if upper.hasPrefix("PERFORMER ") {
                if let f = files.indices.last, !files[f].tracks.isEmpty { files[f].tracks[files[f].tracks.count - 1].performer = value() }
                else if files.isEmpty { albumPerformer = value() }
            }
        }
        var out: [String: Listed] = [:]
        for f in files {
            if f.tracks.count == 1 {
                out[f.name.lowercased()] = Listed(title: f.tracks[0].title, artist: f.tracks[0].performer ?? albumPerformer, origin: "cue")
            } else if f.tracks.count > 1, albumTitle != nil {
                out[f.name.lowercased()] = Listed(title: albumTitle, artist: albumPerformer, origin: "cue")
            }
        }
        return out
    }

    /// An extended M3U playlist: `#EXTINF:<seconds>,<Artist - Title>` before each entry's path. Entries are named by
    /// their file's name.
    static func m3u(_ text: String) -> [String: Listed] {
        var out: [String: Listed] = [:]
        var pending: String? = nil
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.uppercased().hasPrefix("#EXTINF:") {
                pending = line.firstIndex(of: ",").map { String(line[line.index(after: $0)...]).trimmingCharacters(in: .whitespaces) }
            } else if line.hasPrefix("#") || line.isEmpty {
                continue
            } else {
                if let p = nonEmpty(pending) {
                    let parts = p.components(separatedBy: " - ")
                    let listed = parts.count >= 2
                        ? Listed(title: parts.dropFirst().joined(separator: " - "), artist: parts[0], origin: "m3u")
                        : Listed(title: p, artist: nil, origin: "m3u")
                    let name = PathKey.lastName(line.hasPrefix("file://") ? (URL(string: line)?.path ?? line) : line)
                    out[name.lowercased()] = listed
                }
                pending = nil
            }
        }
        return out
    }

    /// A numbered list ("01. Artist - Title", "1) Title", "02 - Artist - Title"): number to name, when the numbers
    /// run 1, 2, 3 ... with no gap or repeat and there are at least two (so a list of something else is not read).
    static func numberedList(_ text: String) -> [Int: Listed] {
        var out: [Int: Listed] = [:]
        var order: [Int] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let digits = line.prefix { $0.isASCII && $0.isNumber }
            guard !digits.isEmpty, digits.count <= 3, let n = Int(digits) else { continue }
            let afterNumber = line.dropFirst(digits.count)
            guard let sep = afterNumber.first, " .-):".contains(sep) else { continue }
            let rest = String(afterNumber.drop { " .-):\t".contains($0) })
            guard !rest.isEmpty else { continue }
            let parts = rest.components(separatedBy: " - ")
            out[n] = parts.count >= 2 && isUsableArtist(parts[0])
                ? Listed(title: parts.dropFirst().joined(separator: " - "), artist: parts[0], origin: "tracklist")
                : Listed(title: rest, artist: nil, origin: "tracklist")
            order.append(n)
        }
        guard order.count >= 2, order == Array(1...order.count) else { return [:] }
        return out
    }
}
