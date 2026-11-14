import Foundation

// An index is built once from a crate file's fingerprints and then kept as one file, which the booth opens in place
// ("mapped": the system reads the parts that are touched straight from storage and may drop them again when memory
// is short). Nothing of the tables is copied into the app's own memory; what stays there is a few numbers a song.

/// A run of fixed-size values, held in memory (an index just built) or inside a mapped file (an index opened).
struct Block<T>: @unchecked Sendable {
    private let array: [T]
    private let data: Data?
    private let offset: Int
    let count: Int

    init(_ array: [T]) { self.array = array; data = nil; offset = 0; count = array.count }
    init(data: Data, offset: Int, count: Int) { array = []; self.data = data; self.offset = offset; self.count = count }

    @inline(__always) func withUnsafeBufferPointer<R>(_ body: (UnsafeBufferPointer<T>) throws -> R) rethrows -> R {
        guard let data else { return try array.withUnsafeBufferPointer(body) }
        return try data.withUnsafeBytes { raw in
            try body(UnsafeBufferPointer(start: count == 0 ? nil : (raw.baseAddress! + offset).assumingMemoryBound(to: T.self), count: count))
        }
    }
    var bytes: Int { count * MemoryLayout<T>.stride }
}

struct FileSettings: Codable {
    var landmark: LandmarkConfig; var pairing: PairingConfig; var stamp: String
    /// As JSON with its keys in order, so that two builders write the same bytes.
    func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}

public struct IndexFileError: Error, CustomStringConvertible {
    public var description: String
}

extension RecognitionIndex {
    /// The size of this index as a file: what the booth maps from storage.
    public var fileBytes: Int {
        pointFrame.bytes + pointPitch.bytes + offsets.bytes + entries.bytes + extra.bytes + tags.bytes + 16 * (ids.count + 1) + ids.reduce(0) { $0 + $1.utf8.count + 1 }
    }
    static let fileMark: [UInt8] = Array("DKX1".utf8)
    /// Bumped when the file's layout or the meaning of an entry changes: an index file is a cache, made again from
    /// the fingerprints whenever its version or its settings are not the ones wanted.
    public static let fileVersion: UInt32 = 2
    private static let sections = 11

    /// The index as one file's bytes: a header (the mark `DKX1`, a version, the timeline's length, then the place and
    /// length of each part), and the parts, each starting on an 8-byte boundary: the settings (JSON), the songs'
    /// ids, where each song starts on the timeline and among the points, the points (frame, pitch), the table, the
    /// entries, their tags, and the pairs of songs that hold the same sound. Numbers are little-endian, as on every system Deckie runs on.
    public func fileData() -> Data {
        precondition(1.littleEndian == 1)
        let settings = FileSettings(landmark: landmark, pairing: pairing, stamp: stamp).encoded()
        var parts: [Data] = [settings, Data(ids.joined(separator: "\n").utf8),
                             songStart.map(Int64.init).withUnsafeBufferPointer { Data(buffer: $0) },
                             pointStart.map(Int64.init).withUnsafeBufferPointer { Data(buffer: $0) }]
        parts.append(pointFrame.withUnsafeBufferPointer { Data(buffer: $0) })
        parts.append(pointPitch.withUnsafeBufferPointer { Data(buffer: $0) })
        parts.append(offsets.withUnsafeBufferPointer { Data(buffer: $0) })
        parts.append(entries.withUnsafeBufferPointer { Data(buffer: $0) })
        parts.append(extra.withUnsafeBufferPointer { Data(buffer: $0) })
        parts.append(tags.withUnsafeBufferPointer { Data(buffer: $0) })
        // The related songs, as pairs of song numbers (each pair once).
        var pairs: [Int32] = []
        for (a, others) in related.enumerated() { for b in others where Int(b) > a { pairs.append(Int32(a)); pairs.append(b) } }
        parts.append(pairs.withUnsafeBufferPointer { Data(buffer: $0) })
        let headerSize = 24 + 16 * Self.sections
        var header = Data(Self.fileMark)
        func put<V: FixedWidthInteger>(_ v: V, into d: inout Data) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        put(Self.fileVersion, into: &header); put(UInt64(timelineFrames), into: &header); put(UInt64(Self.sections), into: &header)
        var at = headerSize
        var places: [(Int, Int)] = []
        for part in parts {
            at = (at + 7) & ~7
            places.append((at, part.count)); at += part.count
        }
        for (place, length) in places { put(UInt64(place), into: &header); put(UInt64(length), into: &header) }
        var out = header
        for (i, part) in parts.enumerated() {
            out.append(Data(count: places[i].0 - out.count))
            out.append(part)
        }
        return out
    }

    public func write(to url: URL) throws { try fileData().write(to: url, options: .atomic) }

    /// Opens an index file in place. `mapped: false` reads it into memory instead (for a system or a volume where
    /// mapping is not to be had).
    public init(contentsOf url: URL, mapped: Bool = true) throws {
        let data = try Data(contentsOf: url, options: mapped ? .alwaysMapped : [])
        try self.init(file: data)
    }

    public init(file data: Data) throws {
        func fail(_ why: String) -> IndexFileError { IndexFileError(description: "not a usable index file: \(why)") }
        let headerSize = 24 + 16 * Self.sections
        guard data.count >= headerSize, Array(data.prefix(4)) == Self.fileMark else { throw fail("no DKX1 mark") }
        func u64(_ at: Int) -> Int { Int(data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: at, as: UInt64.self) }.littleEndian) }
        let version = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }.littleEndian
        guard version == Self.fileVersion else { throw fail("version \(version), wanted \(Self.fileVersion)") }
        guard u64(16) == Self.sections else { throw fail("parts") }
        var places: [(Int, Int)] = []
        for i in 0..<Self.sections {
            let place = u64(24 + 16 * i), length = u64(32 + 16 * i)
            guard place >= headerSize, place % 8 == 0, length >= 0, place + length <= data.count else { throw fail("a part lies outside the file") }
            places.append((place, length))
        }
        guard let settings = try? JSONDecoder().decode(FileSettings.self, from: data.subdata(in: places[0].0..<(places[0].0 + places[0].1))) else { throw fail("settings") }
        landmark = settings.landmark; pairing = settings.pairing; stamp = settings.stamp
        let names = String(decoding: data.subdata(in: places[1].0..<(places[1].0 + places[1].1)), as: UTF8.self)
        ids = names.isEmpty ? [] : names.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        func ints(_ i: Int) -> [Int] {
            let n = places[i].1 / 8
            return data.withUnsafeBytes { raw in (0..<n).map { Int(raw.loadUnaligned(fromByteOffset: places[i].0 + 8 * $0, as: Int64.self)) } }
        }
        songStart = ints(2); pointStart = ints(3)
        guard songStart.count == ids.count + 1, pointStart.count == ids.count + 1 else { throw fail("song count") }
        timelineFrames = u64(8)
        pointFrame = Block(data: data, offset: places[4].0, count: places[4].1 / 4)
        pointPitch = Block(data: data, offset: places[5].0, count: places[5].1 / 2)
        offsets = Block(data: data, offset: places[6].0, count: places[6].1 / 4)
        entries = Block(data: data, offset: places[7].0, count: places[7].1 / 4)
        extra = Block(data: data, offset: places[8].0, count: places[8].1 / 2)
        tags = Block(data: data, offset: places[9].0, count: places[9].1)
        var sets = [[Int32]](repeating: [], count: ids.count)
        let pairCount = places[10].1 / 8
        data.withUnsafeBytes { raw in
            for k in 0..<pairCount {
                let a = Int(raw.loadUnaligned(fromByteOffset: places[10].0 + 8 * k, as: Int32.self)), b = Int(raw.loadUnaligned(fromByteOffset: places[10].0 + 8 * k + 4, as: Int32.self))
                if a >= 0, b >= 0, a < sets.count, b < sets.count { sets[a].append(Int32(b)); sets[b].append(Int32(a)) }
            }
        }
        related = sets
        guard pointFrame.count == pointPitch.count, pointFrame.count == (pointStart.last ?? 0) || pointFrame.count == 0,
              offsets.count == (1 << pairing.tableBits) + 1 else {
            throw fail("the parts do not fit together")
        }
    }
}

extension RecognitionIndex {
    /// A short mark of which songs an index was made from: their ids and the sizes of their fingerprints, folded
    /// into 16 hex digits (FNV-1a). An index file whose stamp is not the crate file's own is made again.
    public static func stamp(of songs: [(id: String, points: Int, frames: Int)]) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ byte: UInt8) { h = (h ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        for s in songs {
            for b in s.id.utf8 { mix(b) }
            mix(0)
            for v in [s.points, s.frames] { for k in 0..<8 { mix(UInt8((v >> (8 * k)) & 0xff)) } }
        }
        return String(h, radix: 16)
    }

    /// The booth's way to its index: opens the file at `url` in place if it is there, readable, made with the
    /// booth's settings and from the same songs (`stamp`); otherwise builds the index from `songs()` (the crate
    /// file's fingerprints), writes it to `url`, and opens that. So the building happens once per crate file, the
    /// first time the booth sees it, and what is used afterwards is always the mapped file.
    public static func cached(at url: URL, stamp: String, sameRecording: [String?] = [], pairing: PairingConfig = .booth,
                              printsFolder: URL? = nil, songs: () -> [(id: String, landmarks: Landmarks)]) throws -> RecognitionIndex {
        if let kept = kept(at: url, stamp: stamp, pairing: pairing, printsFolder: printsFolder) { return kept }
        let all = songs()
        return try cached(at: url, stamp: stamp, count: all.count, sameRecording: sameRecording, pairing: pairing, printsFolder: printsFolder) { all[$0] }
    }

    /// The same, asking for one song at a time, so that neither the songs nor the index are ever all in memory: the
    /// index is built by `build(to:…)` in a fixed working memory. With `printsFolder` (a crate file's `prints/`
    /// folder) the index file leaves the songs' points out and reads them there when it checks a song; without, it
    /// keeps its own copy of them.
    public static func cached(at url: URL, stamp: String, count: Int, sameRecording: [String?] = [], pairing: PairingConfig = .booth,
                              printsFolder: URL? = nil, findCopies: Bool = true,
                              song: (Int) -> (id: String, landmarks: Landmarks)) throws -> RecognitionIndex {
        func open() throws -> RecognitionIndex { try opened(at: url, printsFolder: printsFolder) }
        if let kept = kept(at: url, stamp: stamp, pairing: pairing, printsFolder: printsFolder) { return kept }
        if pairing.triples {
            // The other kinds of hash are for study only and are built whole in memory.
            let built = RecognitionIndex(songs: (0..<count).map { song($0) }, pairing: pairing, stamp: stamp, sameRecording: sameRecording, findCopies: findCopies)
            try built.write(to: url)
            return try open()
        }
        try build(to: url, count: count, pairing: pairing, stamp: stamp, embedPoints: printsFolder == nil, song: song)
        var pairs: [(Int, Int)] = []
        var byKey: [String: [Int]] = [:]
        for (i, key) in sameRecording.enumerated() where i < count { if let key { byKey[key, default: []].append(i) } }
        for group in byKey.values where group.count > 1 { for a in group { for b in group where a < b { pairs.append((a, b)) } } }
        if findCopies { pairs += SameRecording.find(in: try open()) }
        if !pairs.isEmpty { try setRelated(pairs, inFileAt: url) }
        return try open()
    }

    private static func opened(at url: URL, printsFolder: URL?) throws -> RecognitionIndex {
        var index = try RecognitionIndex(contentsOf: url)
        if let printsFolder, !index.holdsPoints { index.pointSource = pointSource(printsFolder: printsFolder, ids: index.ids) }
        return index
    }

    /// The index file at `url` if it is there and is the one wanted: made from these songs, with these settings,
    /// and holding its points or not as asked.
    private static func kept(at url: URL, stamp: String, pairing: PairingConfig, printsFolder: URL?) -> RecognitionIndex? {
        guard let kept = try? opened(at: url, printsFolder: printsFolder), kept.stamp == stamp, kept.settingsMatch(pairing),
              kept.holdsPoints == (printsFolder == nil) else { return nil }
        return kept
    }

    /// Whether this index was built with these settings (the table's size aside, which the index sets itself).
    func settingsMatch(_ wanted: PairingConfig) -> Bool {
        var mine = pairing, theirs = wanted
        mine.tableBits = 0; theirs.tableBits = 0
        return mine == theirs && landmark == LandmarkConfig()
    }
}
