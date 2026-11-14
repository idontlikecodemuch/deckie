import Foundation

// TRIAL: four-point hashes in the ratio form, for the size study (docs/research/ac-recognition-size.md).
//
// After Sonnleitner and Widmer, "Robust quad-based audio fingerprinting" (IEEE/ACM TASLP 2016), from the paper's
// description; no code of theirs or of anyone else's was read or copied. Their idea: of four points, the first (A)
// and the last (B) set a frame, and the two between (C, D) are described by where they sit inside it, as fractions.
// Fractions do not change when the deck's speed changes, so the hash is the same at any speed and the speed is read
// off afterwards from how long the frame is in the query against the song.
//
// Here, on this module's logarithmic pitch axis:
//   - time is described by two fractions: (C - A) / (B - A) and (D - A) / (B - A);
//   - pitch by three differences from A (of B, C and D), in steps of 1/32 octave. On a logarithmic axis a
//     vinyl-style speed change moves every pitch by the same amount, so differences are unchanged by it, and key-held
//     playback does not move pitch at all. (The paper works on a linear frequency axis and so needs pitch fractions too.)
// A matching entry gives the song's frame length; over the query's, that is the deck's speed. Its anchor pitch
// against the query's says which way the deck is playing: unchanged (key held) or moved by exactly the speed
// (vinyl-style). An entry that is neither is thrown away before it can vote, which is this form's own filter.
//
// The paper finds its matches by a range search over unrounded values. Here the values are rounded into steps and a
// value close to a step's edge is also looked up one step over (one part at a time).

enum RatioQuads {
    /// The frame's length, in frames: from 0.77 s (so that a fraction is fine enough: a point's time is known to a
    /// frame, 1/48 of the shortest frame) to 2 s, the target zone's end.
    static let spanMin = 48
    static let spanMax = 128
    /// Steps a fraction is rounded to.
    static let ratioSteps = 32

    struct Built { var offsets: [UInt32]; var entries: [UInt32]; var extra: [UInt16] }

    /// The folded hash of a quad: two fraction steps, three pitch-difference steps.
    @inline(__always) static func hash(_ rc: Int, _ rd: Int, _ db: Int, _ dc: Int, _ dd: Int) -> Int {
        let raw = UInt64(rc) | UInt64(rd) << 5 | UInt64(db) << 10 | UInt64(dc) << 17 | UInt64(dd) << 24
        return Int((raw &* 0x9E37_79B9_7F4A_7C15) >> 24)
    }
    @inline(__always) static func slot(_ h: Int, _ bits: Int) -> Int { h >> (40 - bits) }
    @inline(__always) static func tag(_ h: Int, _ bits: Int) -> UInt16 { UInt16((h >> (31 - bits)) & 0x1ff) }

    /// A song's quads: for each anchor (of the wanted strength), the `ratioFar` strongest points one frame length
    /// on (the earliest of equals), and for each of those the two strongest points between, in time order.
    static func build(_ p: PairingConfig, songCount: Int, pointStart: [Int], pointFrame: [Int32], pointPitch: [UInt16],
                      pointLevel: [Int8]) -> Built {
        let unit = p.pitchBinUnits, reach = p.maxPitchBins * unit
        let bits = p.tableBits
        var counts = [UInt32](repeating: 0, count: (1 << bits) + 1)
        func each(_ body: (_ hash: Int, _ frame: Int, _ span: Int, _ pitchBin: Int) -> Void) {
            var far: [Int] = []
            for s in 0..<songCount {
                let lo = pointStart[s], hi = pointStart[s + 1]
                for i in lo..<hi where Int(pointLevel[i]) >= p.minAnchorLevel {
                    let ta = Int(pointFrame[i]), pa = Int(pointPitch[i])
                    // The far points: strongest first.
                    far.removeAll(keepingCapacity: true)
                    var j = i + 1
                    while j < hi {
                        let gap = Int(pointFrame[j]) - ta
                        if gap > spanMax { break }
                        if gap >= spanMin && abs(Int(pointPitch[j]) - pa) <= reach {
                            var at = far.count
                            while at > 0 && pointLevel[j] > pointLevel[far[at - 1]] { at -= 1 }
                            if at < p.ratioFar { far.insert(j, at: at); if far.count > p.ratioFar { far.removeLast() } }
                        }
                        j += 1
                    }
                    for b in far {
                        let span = Int(pointFrame[b]) - ta
                        // The two strongest points between (the earliest of equals).
                        var c = -1, d = -1
                        var k = i + 1
                        while k < b {
                            let gap = Int(pointFrame[k]) - ta
                            if gap >= p.minGap && gap <= span - p.minGap && abs(Int(pointPitch[k]) - pa) <= reach {
                                if c < 0 || pointLevel[k] > pointLevel[c] { d = c; c = k } else if d < 0 || pointLevel[k] > pointLevel[d] { d = k }
                            }
                            k += 1
                        }
                        guard c >= 0, d >= 0 else { continue }
                        let (first, second) = c < d ? (c, d) : (d, c)
                        let h = hash((Int(pointFrame[first]) - ta) * ratioSteps / span, (Int(pointFrame[second]) - ta) * ratioSteps / span,
                                     (Int(pointPitch[b]) - pa + reach) / unit, (Int(pointPitch[first]) - pa + reach) / unit,
                                     (Int(pointPitch[second]) - pa + reach) / unit)
                        if p.kept(h) { body(h, ta, span, pa / unit) }
                    }
                }
            }
        }
        each { h, _, _, _ in counts[slot(h, bits) + 1] += 1 }
        for i in 0..<(1 << bits) { counts[i + 1] += counts[i] }
        var entries = [UInt32](repeating: 0, count: Int(counts[1 << bits]))
        var extra = [UInt16](repeating: 0, count: entries.count)
        var next = counts
        each { h, frame, span, pitchBin in
            let at = Int(next[slot(h, bits)])
            entries[at] = UInt32(frame / 8) << 7 | UInt32(span - 1)
            extra[at] = UInt16(pitchBin) << 9 | tag(h, bits)
            next[slot(h, bits)] += 1
        }
        return Built(offsets: counts, entries: entries, extra: extra)
    }
}

extension Recogniser {
    /// The ratio form's votes for a query: no candidate speeds. Every anchor of the query is framed with its
    /// strongest far points and, for each, every two of its strongest points between; each quad is looked up
    /// (and once more for each part that sits near a step's edge); an entry that passes the speed and pitch
    /// test votes for its place in its song. Returns the fullest bins with the speed their entries agree on.
    func ratioVotes(_ ix: RecognitionIndex, qt: [Double], qp: [Double], qs: [Float], keep: Int) -> [Vote] {
        let p = ix.pairing
        let n = qt.count
        let unit = Double(p.pitchBinUnits), reach = Double(p.maxPitchBins * p.pitchBinUnits)
        let bits = p.tableBits
        let steps = Double(RatioQuads.ratioSteps)
        let maxSpeed = 1 + grid.maxPercent / 100, minSpeed = 1 - grid.maxPercent / 100
        let spanLo = Double(RatioQuads.spanMin) / maxSpeed, spanHi = Double(RatioQuads.spanMax) / minSpeed
        var hits: [(bin: Int32, speed: Float, vinyl: Bool)] = []
        var far: [Int] = [], inner: [Int] = []
        // A part's step, and the step next door when the value is within `edge` of the border (else -1).
        @inline(__always) func stepped(_ value: Double, _ edge: Double) -> (Int, Int) {
            let s = value.rounded(.down), f = value - s
            return (Int(s), f < edge ? Int(s) - 1 : (f > 1 - edge ? Int(s) + 1 : -1))
        }
        ix.offsets.withUnsafeBufferPointer { offsets in
            ix.entries.withUnsafeBufferPointer { entries in
                ix.extra.withUnsafeBufferPointer { extra in
                    votes.withUnsafeMutableBufferPointer { votes in
                        func look(_ rc: Int, _ rd: Int, _ db: Int, _ dc: Int, _ dd: Int, anchorBin: Int, span: Double, ta: Double) {
                            guard rc >= 0, rd >= 0, rc < RatioQuads.ratioSteps, rd < RatioQuads.ratioSteps, db >= 0, dc >= 0, dd >= 0 else { return }
                            let h = RatioQuads.hash(rc, rd, db, dc, dd)
                            if !p.kept(h) { return }
                            let slot = RatioQuads.slot(h, bits), tag = RatioQuads.tag(h, bits)
                            var e = Int(offsets[slot])
                            let end = Int(offsets[slot + 1])
                            while e < end {
                                let x = extra[e]
                                if x & 0x1ff == tag {
                                    let entry = entries[e]
                                    let v = Double(entry & 0x7f + 1) / span
                                    if v >= minSpeed && v <= maxSpeed {
                                        // Key held: the anchor's pitch step unchanged (to a step). Vinyl-style: moved by the speed.
                                        let moved = Double(anchorBin - Int(x >> 9))
                                        let held = abs(moved) <= 1
                                        let vinyl = abs(moved - log2(v) * Double(p.pitchBinsPerOctave)) <= 1.5
                                        if held || vinyl {
                                            let bin = Int(Double((entry >> 7) * 8 + 4) - v * ta) / Self.binFrames
                                            if bin >= 0 {
                                                if votes[bin] == 0 { touched.append(Int32(bin)) }
                                                if votes[bin] < .max { votes[bin] += 1 }
                                                hits.append((Int32(bin), Float(v), vinyl && !(held && abs(v - 1) < 0.01)))
                                            }
                                        }
                                    }
                                }
                                e += 1
                            }
                        }
                        for i in 0..<n {
                            let ta = qt[i], pa = qp[i]
                            // The query's far points for this anchor: its strongest, a frame length on at any speed tried.
                            far.removeAll(keepingCapacity: true)
                            var j = i + 1
                            var last = i
                            while j < n {
                                let gap = qt[j] - ta
                                if gap > spanHi { break }
                                last = j
                                if gap >= spanLo && abs(qp[j] - pa) <= reach {
                                    var at = far.count
                                    while at > 0 && qs[j] > qs[far[at - 1]] { at -= 1 }
                                    if at < p.queryRatioFar { far.insert(j, at: at); if far.count > p.queryRatioFar { far.removeLast() } }
                                }
                                j += 1
                            }
                            guard last > i else { continue }
                            let anchorBin = Int(pa / unit)
                            for b in far {
                                let span = qt[b] - ta
                                // Its strongest points between.
                                inner.removeAll(keepingCapacity: true)
                                var k = i + 1
                                while k < b {
                                    let gap = qt[k] - ta
                                    if gap >= Double(p.minGap) - 1 && gap <= span - Double(p.minGap) + 1 && abs(qp[k] - pa) <= reach {
                                        var at = inner.count
                                        while at > 0 && qs[k] > qs[inner[at - 1]] { at -= 1 }
                                        if at < p.queryRatioInner { inner.insert(k, at: at); if inner.count > p.queryRatioInner { inner.removeLast() } }
                                    }
                                    k += 1
                                }
                                guard inner.count >= 2 else { continue }
                                let (db, db2) = stepped((qp[b] - pa + reach) / unit, 0.1)
                                for x in 0..<inner.count {
                                    for y in 0..<inner.count where inner[x] < inner[y] {
                                        let c = inner[x], d = inner[y]
                                        let (rc, rc2) = stepped((qt[c] - ta) * steps / span, 0.3)
                                        let (rd, rd2) = stepped((qt[d] - ta) * steps / span, 0.3)
                                        let (dc, dc2) = stepped((qp[c] - pa + reach) / unit, 0.1)
                                        let (dd, dd2) = stepped((qp[d] - pa + reach) / unit, 0.1)
                                        look(rc, rd, db, dc, dd, anchorBin: anchorBin, span: span, ta: ta)
                                        if rc2 >= 0 { look(rc2, rd, db, dc, dd, anchorBin: anchorBin, span: span, ta: ta) }
                                        if rd2 >= 0 { look(rc, rd2, db, dc, dd, anchorBin: anchorBin, span: span, ta: ta) }
                                        if db2 >= 0 { look(rc, rd, db2, dc, dd, anchorBin: anchorBin, span: span, ta: ta) }
                                        if dc2 >= 0 { look(rc, rd, db, dc2, dd, anchorBin: anchorBin, span: span, ta: ta) }
                                        if dd2 >= 0 { look(rc, rd, db, dc, dd2, anchorBin: anchorBin, span: span, ta: ta) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        // The fullest pairs of neighbouring bins, each with the middle speed of its votes and the commoner way.
        var top: [(Int, Int)] = []
        for t in touched {
            let b = Int(t)
            let c = Int(votes[b]) + Int(votes[b + 1])
            if top.count < keep || c > top[top.count - 1].0 {
                top.append((c, b))
                top.sort { $0.0 > $1.0 }
                if top.count > keep { top.removeLast() }
            }
        }
        for t in touched { votes[Int(t)] = 0 }
        touched.removeAll(keepingCapacity: true)
        var out: [Vote] = []
        for (count, bin) in top {
            let mine = hits.filter { Int($0.bin) == bin || Int($0.bin) == bin + 1 }
            guard !mine.isEmpty else { continue }
            let speeds = mine.map(\.speed).sorted()
            let vinyl = mine.filter(\.vinyl).count * 2 > mine.count
            out.append(Vote(count: count, bin: bin, speed: Double(speeds[speeds.count / 2]), vinyl: vinyl))
        }
        return out
    }
}
