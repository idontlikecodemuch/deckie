import Foundation

// Building an index in a fixed amount of memory, whatever the crate's size.
//
// The first builder (`RecognitionIndex.init(songs:)`) holds every song's points, the whole table and then a copy of
// it all as a file's bytes: for a library of 2,327 songs that was a peak of 0.88 GB on a Mac
// (docs/research/w3-recognition-real-room.md, section 13), which on an iPad would get the booth closed the first
// time it met a large crate. This builder holds one song at a time, the table's 2 million counters, and a buffer
// of entries of a size the caller sets (32 MB by default); the index is written to its file as it is made.
//
// How: songs are asked for one at a time through `song`, as often as needed. A first pass counts each song's hashes
// per table slot and writes its points (when they are kept in the file). The entries are then written in runs of
// table slots, each run small enough for the buffer: for each run every song is hashed again and the hashes that
// fall in the run are placed. So a larger crate takes more passes, not more memory. The file is the same, byte for
// byte, as the first builder's.

extension RecognitionIndex {
    /// The (hash, frame within the song) of each two-point hash of one song, in the order the index keeps them.
    static func pairHashes(of m: Landmarks, pairing p: PairingConfig, _ body: (_ hash: Int, _ frame: Int) -> Void) {
        let n = m.count
        guard n > 0 else { return }
        let unit = p.pitchBinUnits
        let frames = m.frames.map { Int32($0) }, pitches = (0..<n).map { m.pitch($0) }, levels = (0..<n).map { Int8(m.level($0)) }
        let isAnchor = anchors(share: p.anchorShare, songCount: 1, pointStart: [0, n], pointFrame: frames, pointPitch: pitches, pointLevel: levels)
        var slotBin = [Int](repeating: 0, count: p.fanOut), slotGap = [Int](repeating: 0, count: p.fanOut)
        var slotLevel = [Int8](repeating: 0, count: p.fanOut)
        frames.withUnsafeBufferPointer { frames in
            pitches.withUnsafeBufferPointer { pitches in
                levels.withUnsafeBufferPointer { levels in
                    var i = 0
                    while i < n {
                        defer { i += 1 }
                        if Int(levels[i]) < p.minAnchorLevel || !isAnchor[i] { continue }
                        let a = Int(pitches[i]) / unit, ta = Int(frames[i])
                        var filled = 0
                        var j = i + 1
                        while j < n {
                            let gap = Int(frames[j]) - ta
                            if gap > p.maxGap { break }
                            let b = Int(pitches[j]) / unit
                            if gap >= p.minGap && abs(b - a) <= p.maxPitchBins {
                                let k = p.slice(gap: gap)
                                let level = p.byStrength ? levels[j] : 0
                                if filled & (1 << k) == 0 || level > slotLevel[k] {
                                    filled |= 1 << k
                                    slotBin[k] = b; slotGap[k] = gap; slotLevel[k] = level
                                }
                            }
                            j += 1
                        }
                        for k in 0..<p.fanOut where filled & (1 << k) != 0 {
                            let h = p.hash(anchorBin: a, targetBin: slotBin[k], gap: slotGap[k])
                            if p.keptPair(h) { body(h, ta) }
                        }
                    }
                }
            }
        }
    }

    /// Builds an index of `count` songs straight into the file at `url`, in a fixed working memory (see this file's
    /// notes). `song(i)` gives song i's id and fingerprint and is called several times for each song, so it should
    /// read the fingerprint from storage each time, not keep them all. `embedPoints: false` leaves the songs' points
    /// out of the file (half its size): the index then reads them where the crate file keeps them, through
    /// `pointSource`, which the caller must set on the opened index. Two-point hashes only (the booth's kinds).
    public static func build(to url: URL, count: Int, pairing: PairingConfig = .booth, landmark: LandmarkConfig = LandmarkConfig(),
                             stamp: String = "", embedPoints: Bool = true, workingBytes: Int = 32 << 20,
                             song: (Int) -> (id: String, landmarks: Landmarks)) throws {
        precondition(!pairing.triples, "the bounded builder makes two-point indexes")
        var p = pairing
        p.tableBits = PairingConfig.hashBits
        let slots = 1 << p.tableBits
        let fm = FileManager.default
        let framesURL = url.appendingPathExtension("frames"), pitchesURL = url.appendingPathExtension("pitches")
        defer { try? fm.removeItem(at: framesURL); try? fm.removeItem(at: pitchesURL) }
        _ = fm.createFile(atPath: framesURL.path, contents: nil); _ = fm.createFile(atPath: pitchesURL.path, contents: nil)
        let framesOut = try FileHandle(forWritingTo: framesURL), pitchesOut = try FileHandle(forWritingTo: pitchesURL)

        // Pass 1: where each song sits, its points, and how many hashes fall in each table slot.
        var ids: [String] = [], songStart: [Int64] = [], pointStart: [Int64] = []
        var counts = [UInt32](repeating: 0, count: slots + 1)
        var at = 0, points = 0
        for i in 0..<count {
            try pooled {
                let s = song(i)
                ids.append(s.id)
                at += Self.padding
                songStart.append(Int64(at)); pointStart.append(Int64(points))
                let m = s.landmarks
                if embedPoints {
                    try framesOut.write(contentsOf: m.frames.map { Int32(at) + Int32($0) }.withUnsafeBufferPointer { Data(buffer: $0) })
                    try pitchesOut.write(contentsOf: (0..<m.count).map { m.pitch($0) }.withUnsafeBufferPointer { Data(buffer: $0) })
                }
                points += m.count
                pairHashes(of: m, pairing: p) { h, _ in counts[h + 1] += 1 }
                at += max(m.frameCount, Int(m.frames.last ?? 0) + 1)
            }
        }
        songStart.append(Int64(at + Self.padding)); pointStart.append(Int64(points))
        let timelineFrames = at + Self.padding
        guard timelineFrames < Int(Int32.max) else { throw IndexFileError(description: "the crate is too long for one index") }
        try framesOut.close(); try pitchesOut.close()
        for h in 0..<slots { counts[h + 1] += counts[h] }
        let entryCount = Int(counts[slots])

        // The file: header (filled in at the end), then each part on an 8-byte boundary, in `fileData()`'s order.
        let settings = FileSettings(landmark: landmark, pairing: p, stamp: stamp).encoded()
        let headerSize = 24 + 16 * 11
        _ = fm.createFile(atPath: url.path, contents: nil)
        let out = try FileHandle(forWritingTo: url)
        var places: [(Int, Int)] = []
        var position = headerSize
        try out.write(contentsOf: Data(count: headerSize))
        func begin(_ length: Int) throws {
            let aligned = (position + 7) & ~7
            if aligned > position { try out.write(contentsOf: Data(count: aligned - position)) }
            position = aligned
            places.append((position, length)); position += length
        }
        try begin(settings.count); try out.write(contentsOf: settings)
        let names = Data(ids.joined(separator: "\n").utf8)
        try begin(names.count); try out.write(contentsOf: names)
        try begin(songStart.count * 8); try out.write(contentsOf: songStart.withUnsafeBufferPointer { Data(buffer: $0) })
        try begin(pointStart.count * 8); try out.write(contentsOf: pointStart.withUnsafeBufferPointer { Data(buffer: $0) })
        for (source, width) in [(framesURL, 4), (pitchesURL, 2)] {
            try begin(embedPoints ? points * width : 0)
            if embedPoints {
                let input = try FileHandle(forReadingFrom: source)
                while let chunk = try input.read(upToCount: 4 << 20), !chunk.isEmpty { try out.write(contentsOf: chunk) }
                try input.close()
            }
        }
        try begin(counts.count * 4); try out.write(contentsOf: counts.withUnsafeBufferPointer { Data(buffer: $0) })

        // The entries, a run of table slots at a time.
        try begin(entryCount * 4)
        let room = max(1024, workingBytes / 4)
        var buffer = [UInt32](repeating: 0, count: min(room, max(1, entryCount)))
        var next = counts
        var firstSlot = 0
        while firstSlot < slots {
            // The longest run of slots from `firstSlot` whose entries fit the buffer (one slot at least).
            var lastSlot = firstSlot + 1
            let base = Int(counts[firstSlot])
            while lastSlot < slots && Int(counts[lastSlot + 1]) - base <= buffer.count { lastSlot += 1 }
            let run = Int(counts[lastSlot]) - base
            if run > buffer.count { buffer = [UInt32](repeating: 0, count: run) }      // one slot larger than the buffer
            if run > 0 {
                for i in 0..<count {
                    pooled {
                        let m = song(i).landmarks
                        let start = Int(songStart[i])
                        pairHashes(of: m, pairing: p) { h, frame in
                            if h >= firstSlot && h < lastSlot {
                                buffer[Int(next[h]) - base] = UInt32(start + frame)
                                next[h] += 1
                            }
                        }
                    }
                }
                // Written from the buffer itself, in pieces, with no second copy of the run.
                try buffer.withUnsafeMutableBytes { raw in
                    var done = 0
                    while done < run * 4 {
                        let piece = min(4 << 20, run * 4 - done)
                        try out.write(contentsOf: Data(bytesNoCopy: raw.baseAddress! + done, count: piece, deallocator: .none))
                        done += piece
                    }
                }
            }
            firstSlot = lastSlot
        }
        try begin(0); try begin(0); try begin(0)        // no extra words, no tags, and no related songs yet

        var header = Data(Self.fileMark)
        func put<V: FixedWidthInteger>(_ v: V) { withUnsafeBytes(of: v.littleEndian) { header.append(contentsOf: $0) } }
        put(Self.fileVersion); put(UInt64(timelineFrames)); put(UInt64(11))
        for (place, length) in places { put(UInt64(place)); put(UInt64(length)) }
        try out.seek(toOffset: 0); try out.write(contentsOf: header)
        try out.close()
    }

    /// Writes which songs hold the same sound into an index file that is already built: the pairs go at the file's
    /// end and the header is pointed at them.
    public static func setRelated(_ pairs: [(Int, Int)], inFileAt url: URL) throws {
        var seen: Set<Int64> = []
        for (a, b) in pairs { seen.insert(Int64(min(a, b)) << 32 | Int64(max(a, b))) }
        var words: [Int32] = []
        for key in seen.sorted() { words.append(Int32(key >> 32)); words.append(Int32(key & 0xffff_ffff)) }
        let out = try FileHandle(forUpdating: url)
        var end = Int(try out.seekToEnd())
        let aligned = (end + 7) & ~7
        if aligned > end { try out.write(contentsOf: Data(count: aligned - end)); end = aligned }
        try out.write(contentsOf: words.withUnsafeBufferPointer { Data(buffer: $0) })
        var place = Data()
        withUnsafeBytes(of: UInt64(end).littleEndian) { place.append(contentsOf: $0) }
        withUnsafeBytes(of: UInt64(words.count * 4).littleEndian) { place.append(contentsOf: $0) }
        try out.seek(toOffset: UInt64(24 + 16 * 10)); try out.write(contentsOf: place)
        try out.close()
    }

    /// Reads a song's points from where a crate file keeps them: `<folder>/<id>.dkl` (its `prints/` folder).
    public static func pointSource(printsFolder: URL, ids: [String]) -> @Sendable (Int) -> Landmarks? {
        { i in
            guard i >= 0, i < ids.count, let data = try? Data(contentsOf: printsFolder.appendingPathComponent(ids[i] + ".dkl")) else { return nil }
            return Landmarks(encoded: data)
        }
    }
}
