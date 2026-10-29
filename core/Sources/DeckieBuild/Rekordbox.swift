import Foundation
import DeckieCore
import DeckieCrate

/// A rekordbox collection export: the XML file rekordbox writes from File, Export Collection in xml format, with the
/// element and attribute names of its documented format (pyrekordbox documents it): `DJ_PLAYLISTS` holding
/// `PRODUCT`, `COLLECTION` (one `TRACK` per track, with `TEMPO` grid markers and `POSITION_MARK` cues inside) and
/// `PLAYLISTS` (a tree of `NODE`s: folders, `Type` 0, and playlists, `Type` 1, whose `TRACK`s name a track by `Key`,
/// its TrackID when the playlist's `KeyType` is 0 and its Location when it is 1). Attributes the builder does not use
/// are not kept.
public struct RekordboxCollection: Sendable {
    /// One `TRACK` of the collection.
    public struct Track: Sendable, Equatable {
        public var trackID: String
        public var name: String?
        public var artist: String?
        /// The mix name (`Mix`), such as "Extended Mix": the crate's `ident.version`.
        public var mix: String?
        /// `Location` as written: a file URL, percent-encoded.
        public var location: String
        /// The file's path, from `Location` (`RekordboxCollection.path(fromLocation:)`).
        public var path: String?
        /// File size in bytes (`Size`).
        public var size: Int?
        /// Seconds (`TotalTime`).
        public var totalTime: Double?
        /// `AverageBpm`; nil when absent or zero.
        public var averageBpm: Double?
        /// `Tonality` as written.
        public var tonality: String?
        public var tempos: [Tempo]
        public var marks: [PositionMark]
    }

    /// A `TEMPO` element: from `inizio` seconds the grid runs at `bpm` in `metro`, the beat there being beat
    /// `battito` of its bar.
    public struct Tempo: Sendable, Equatable {
        public var inizio: Double
        public var bpm: Double
        public var metro: String?
        public var battito: Int
        public init(inizio: Double, bpm: Double, metro: String?, battito: Int) {
            self.inizio = inizio; self.bpm = bpm; self.metro = metro; self.battito = battito
        }
    }

    /// A `POSITION_MARK`: `type` 0 cue, 1 fade-in, 2 fade-out, 3 load, 4 loop; `num` 0 to 7 for hot cues A to H, -1
    /// for a memory cue; `end` for a loop.
    public struct PositionMark: Sendable, Equatable {
        public var name: String
        public var type: Int
        public var start: Double
        public var end: Double?
        public var num: Int
        public init(name: String, type: Int, start: Double, end: Double?, num: Int) {
            self.name = name; self.type = type; self.start = start; self.end = end; self.num = num
        }
    }

    /// A playlist (`NODE Type="1"`): its path of folder names from the top (the root node left out), its own name last,
    /// and the TrackIDs it holds, in order.
    public struct Playlist: Sendable, Equatable {
        public var path: [String]
        public var trackIDs: [String]
        public init(path: [String], trackIDs: [String]) { self.path = path; self.trackIDs = trackIDs }
    }

    public struct ReadError: Error, CustomStringConvertible {
        public var file: String
        public var message: String
        public var description: String { "\(file): \(message)" }
    }

    /// The `PRODUCT`'s name and version, as written (`rekordbox 6.8.5`).
    public var product: String?
    public var tracks: [Track]
    public var playlists: [Playlist]

    /// Reads the export at `url`.
    public static func read(_ url: URL) throws -> RekordboxCollection {
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            throw ReadError(file: url.lastPathComponent, message: "could not be read (\(error.localizedDescription))")
        }
        do { return try parse(data) } catch let e as XMLScanner.Failure {
            throw ReadError(file: url.lastPathComponent, message: "not a readable XML file: \(e)")
        } catch let e as ReadError {
            throw ReadError(file: url.lastPathComponent, message: e.message)
        }
    }

    /// Parses an export's bytes.
    public static func parse(_ data: Data) throws -> RekordboxCollection {
        var product: String? = nil
        var tracks: [Track] = []
        var current: Track? = nil
        var sawRoot = false
        var inCollection = false, inPlaylists = false
        // The open NODEs: (name, is a playlist, key type); the outermost is the root.
        var nodes: [(name: String, playlist: Bool, keyType: Int)] = []
        var rawPlaylists: [(path: [String], keyType: Int, keys: [String])] = []

        try XMLScanner.scan(data) { event in
            switch event {
            case .start(let name, let a):
                switch name {
                case "DJ_PLAYLISTS": sawRoot = true
                case "PRODUCT":
                    product = [a["Name"], a["Version"]].compactMap { $0 }.joined(separator: " ")
                case "COLLECTION": inCollection = true
                case "PLAYLISTS": inPlaylists = true
                case "TRACK" where inCollection:
                    current = Track(trackID: a["TrackID"] ?? "", name: nonEmpty(a["Name"]), artist: nonEmpty(a["Artist"]),
                                    mix: nonEmpty(a["Mix"]), location: a["Location"] ?? "",
                                    path: a["Location"].flatMap(path(fromLocation:)), size: a["Size"].flatMap { Int($0) },
                                    totalTime: number(a["TotalTime"]),
                                    averageBpm: number(a["AverageBpm"]).flatMap { $0 > 0 ? $0 : nil },
                                    tonality: nonEmpty(a["Tonality"]), tempos: [], marks: [])
                case "TEMPO" where current != nil:
                    if let start = number(a["Inizio"]), let bpm = number(a["Bpm"]), bpm > 0 {
                        current?.tempos.append(Tempo(inizio: start, bpm: bpm, metro: nonEmpty(a["Metro"]),
                                                     battito: a["Battito"].flatMap { Int($0) } ?? 1))
                    }
                case "POSITION_MARK" where current != nil:
                    if let start = number(a["Start"]) {
                        current?.marks.append(PositionMark(name: a["Name"] ?? "", type: a["Type"].flatMap { Int($0) } ?? 0,
                                                           start: start, end: number(a["End"]),
                                                           num: a["Num"].flatMap { Int($0) } ?? -1))
                    }
                case "NODE" where inPlaylists:
                    let playlist = a["Type"] == "1"
                    nodes.append((a["Name"] ?? "", playlist, a["KeyType"].flatMap { Int($0) } ?? 0))
                    if playlist { rawPlaylists.append((nodes.dropFirst().map(\.name), nodes.last!.keyType, [])) }
                case "TRACK" where inPlaylists:
                    if let last = nodes.last, last.playlist, let key = a["Key"], !rawPlaylists.isEmpty {
                        rawPlaylists[rawPlaylists.count - 1].keys.append(key)
                    }
                default: break
                }
            case .end(let name):
                switch name {
                case "COLLECTION": inCollection = false
                case "PLAYLISTS": inPlaylists = false
                case "TRACK" where inCollection:
                    if let t = current, !t.location.isEmpty { tracks.append(t) }
                    current = nil
                case "NODE" where inPlaylists: _ = nodes.popLast()
                default: break
                }
            }
        }
        guard sawRoot else { throw ReadError(file: "", message: "has no DJ_PLAYLISTS element: not a rekordbox export") }
        var byLocation: [String: String] = [:]
        for t in tracks where byLocation[t.location] == nil { byLocation[t.location] = t.trackID }
        let playlists = rawPlaylists.map { p in
            Playlist(path: p.path, trackIDs: p.keys.compactMap { p.keyType == 1 ? byLocation[$0] : $0 })
        }
        return RekordboxCollection(product: product, tracks: tracks, playlists: playlists)
    }

    /// The playlists holding the track `trackID`, each as its path, in the export's order.
    public func playlists(holding trackID: String) -> [[String]] {
        playlists.filter { $0.trackIDs.contains(trackID) }.map(\.path)
    }

    /// The file path in a `Location`: `file://localhost/Users/dj/Music/My%20Track.mp3` gives
    /// `/Users/dj/Music/My Track.mp3`; `file://localhost/C:/Music/x.mp3` gives `C:/Music/x.mp3`. Percent escapes are
    /// decoded as UTF-8; nil when the location is not a file URL.
    public static func path(fromLocation location: String) -> String? {
        var s = Substring(location)
        if s.hasPrefix("file://localhost") { s = s.dropFirst("file://localhost".count) }
        else if s.hasPrefix("file://") { s = s.dropFirst("file://".count) }
        else { return nil }
        let decoded = String(s).removingPercentEncoding ?? String(s)
        let c = Array(decoded)
        if c.count >= 3 && c[0] == "/" && c[1].isLetter && c[2] == ":" { return String(decoded.dropFirst()) }
        return decoded
    }

    /// The Camelot code of a `Tonality`, written in whichever notation the DJ's rekordbox shows: classic (`Am`,
    /// `F#m`, `Db`, `Ebmin`), Camelot (`8A`, `08A`) or Open Key (`1m`, `1d`); nil for anything else.
    public static func camelot(fromTonality tonality: String) -> String? {
        let t = tonality.trimmingCharacters(in: .whitespaces)
        guard let first = t.first else { return nil }
        if first.isNumber {
            let digits = t.prefix { $0.isNumber }, rest = t.dropFirst(digits.count).lowercased()
            guard let n = Int(digits), (1...12).contains(n) else { return nil }
            switch rest {
            case "a": return "\(n)A"
            case "b": return "\(n)B"
            case "m", "d": return "\((n + 6) % 12 + 1)\(rest == "m" ? "A" : "B")"
            default: return nil
            }
        }
        var rest = Substring(t.replacingOccurrences(of: "♯", with: "#").replacingOccurrences(of: "♭", with: "b"))
        var note = String(rest.removeFirst()).uppercased()
        if let a = rest.first, a == "#" || a == "b" { note.append(a); rest.removeFirst() }
        let mode = rest.trimmingCharacters(in: .whitespaces)
        let minor: Bool
        switch mode {
        case "m", "min", "minor", "Min", "Minor", "-": minor = true
        case "", "M", "maj", "major", "Maj", "Major": minor = false
        default: return nil
        }
        return Camelot.code(key: note, scale: minor ? "minor" : "major")
    }

    static func number(_ s: String?) -> Double? {
        guard let s, let v = Double(s.trimmingCharacters(in: .whitespaces)), v.isFinite else { return nil }
        return v
    }

    /// What the track's entry contributes to its crate record's `deckie.rekordbox` block.
    public func crateBlock(for track: Track) -> CrateTrack.Deckie.Rekordbox {
        let kinds = ["cue", "fade-in", "fade-out", "load", "loop"]
        return .init(
            trackId: track.trackID, bpm: track.averageBpm, tonality: track.tonality,
            grid: track.tempos.map { .init(startS: $0.inizio, bpm: $0.bpm, meter: $0.metro, beatInBar: max($0.battito, 1)) },
            cues: track.marks.map { m in
                .init(name: m.name, kind: (0..<kinds.count).contains(m.type) ? kinds[m.type] : "type-\(m.type)",
                      hotCue: m.num >= 0 ? m.num : nil, startS: max(m.start, 0),
                      endS: m.type == 4 ? m.end.map { max($0, max(m.start, 0)) } : nil)
            },
            playlists: playlists(holding: track.trackID))
    }
}

/// Finds a file's entry in a rekordbox collection by its location: the same path; else, where the export was made on
/// another machine or the music has moved, the one entry whose path ends with the file's path below the folder;
/// else the one entry with the file's name and size. Names are compared in Unicode's composed form, as macOS and
/// rekordbox may write accents either way.
public struct RekordboxMatcher: Sendable {
    let collection: RekordboxCollection
    private var byPath: [String: Int] = [:]
    private var byName: [String: [Int]] = [:]

    public init(_ collection: RekordboxCollection) {
        self.collection = collection
        for (i, t) in collection.tracks.enumerated() {
            guard let p = t.path else { continue }
            let n = Self.normal(p)
            if byPath[n] == nil { byPath[n] = i }
            byName[Self.normal(Self.lastComponent(n)), default: []].append(i)
        }
    }

    static func normal(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }
    static func lastComponent(_ p: String) -> String { String(p.split(separator: "/").last ?? Substring(p)) }

    /// The entry for the file at `absolutePath`, `rel` below the folder, `size` bytes.
    public func match(absolutePath: String, rel: String, size: Int?) -> RekordboxCollection.Track? {
        if let i = byPath[Self.normal(absolutePath)] { return collection.tracks[i] }
        let r = Self.normal(rel)
        guard let candidates = byName[Self.normal(Self.lastComponent(r))] else { return nil }
        let suffix = candidates.filter { Self.normal(collection.tracks[$0].path ?? "").hasSuffix("/" + r) }
        if suffix.count == 1 { return collection.tracks[suffix[0]] }
        if suffix.count > 1 { return nil }
        let sized = candidates.filter { i in collection.tracks[i].size.map { $0 == size } ?? false }
        return sized.count == 1 ? collection.tracks[sized[0]] : nil
    }
}
