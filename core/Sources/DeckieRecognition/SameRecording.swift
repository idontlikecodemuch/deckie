import Foundation

// Songs that hold the same sound.
//
// A DJ's library often has the same recording twice (an album's copy and a compilation's), and sometimes a long file
// that contains many songs (a continuous mix kept as one track). The recogniser judges a match by how far the best
// song stands above the others, so a second file of the same recording, scoring as high as the first, used to make
// every match look unsure: on the owner's library the right song was named in 42 % of 8 s listens where it was 81 %
// against the party's discs alone (docs/research/w3-recognition-real-room.md).
//
// So an index knows, for each song, which other songs hold its sound, and the recogniser never counts those against
// it. They are found two ways: a crate file's own keys for copies (`sameRecording` in the index's initialiser), and,
// here, from the fingerprints, so that a crate file without keys is covered and a containing file is found at all.

enum SameRecording {
    /// Pairs of songs in `index` that hold the same sound. From each song three stretches of 8 s are taken (a fifth,
    /// a half and four fifths of the way through) and matched against the index at the song's own speed; another
    /// song is related when it answers two of the three with most of the stretch's points in place, at one and the
    /// same shift between the two songs. A copy answers with no shift; a file that contains the song answers at the
    /// song's place in it. A remix or a different song answers at most by chance, far below the bar.
    static func find(in index: RecognitionIndex) -> [(Int, Int)] {
        var grid = SpeedGrid()
        grid.maxPercent = 1                     // the same recording is at the same speed: 0.99, 1 and 1.01 only
        let recogniser = Recogniser(index: index, grid: grid)
        recogniser.checkSongs = 12
        recogniser.judgeCopies = false
        let stretch = 500                       // frames: 8 s
        var pairs: Set<[Int]> = []
        index.pointFrame.withUnsafeBufferPointer { frames in
            index.pointPitch.withUnsafeBufferPointer { pitches in
                for s in 0..<index.songCount {
                    let lo = index.pointStart[s], hi = index.pointStart[s + 1]
                    let length = index.songStart[s + 1] - RecognitionIndex.padding - index.songStart[s]
                    guard length >= 3 * stretch, hi - lo >= 60 else { continue }
                    var seen: [Int: [Double]] = [:]     // other song -> the shifts it answered at (frames)
                    for share in [0.2, 0.5, 0.8] {
                        let from = index.songStart[s] + Int(Double(length - stretch) * share)
                        var f: [UInt32] = [], p: [UInt16] = []
                        var i = lo
                        while i < hi && Int(frames[i]) < from { i += 1 }
                        while i < hi && Int(frames[i]) < from + stretch { f.append(UInt32(Int(frames[i]) - from)); p.append(pitches[i]); i += 1 }
                        guard f.count >= 20 else { continue }
                        let probe = Landmarks(frames: f, pitches: p, frameCount: stretch)
                        for m in recogniser.match(probe) where m.songIndex != s && abs(m.tempoRatio - 1) < 0.005 && m.matched * 2 >= m.queryPoints {
                            seen[m.songIndex, default: []].append(m.offsetSeconds / index.landmark.frameSeconds - Double(from - index.songStart[s]))
                        }
                    }
                    for (other, shifts) in seen where shifts.count >= 2 {
                        let sorted = shifts.sorted()
                        if sorted[sorted.count - 1] - sorted[0] <= 30 || (sorted.count == 3 && min(sorted[1] - sorted[0], sorted[2] - sorted[1]) <= 30) {
                            pairs.insert([min(s, other), max(s, other)])
                        }
                    }
                }
            }
        }
        return pairs.map { ($0[0], $0[1]) }
    }
}
