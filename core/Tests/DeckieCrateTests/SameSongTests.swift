import Foundation
import Testing
import DeckieCore
import DeckieCrate

// "The same song" (D24): entries are one song only when they share a recording key (cut_key, else the id); the
// places of a song's copies in the order the booth shows them; and cut keys set from prints. Synthetic crates only.

@Suite struct SameSongTests {
    /// A crate of entries named by id, each with a title, a cut key and a place.
    func crate(_ rows: [(id: String, title: String, cut: String?, disc: String?, folder: String?, track: Int?)]) -> Crate {
        var c = sampleCrate()
        let base = c.tracks[1]
        c.tracks = rows.map { r in
            var t = base
            t.id = r.id; t.ident.title = r.title; t.ident.cutKey = r.cut
            t.ident.disc = r.disc; t.ident.folder = r.folder; t.ident.track = r.track
            return t
        }
        return c
    }

    @Test func theKeyIsTheCutKeyElseTheId() {
        #expect(SameSong.key(id: "a1", cutKey: nil) == "a1")
        #expect(SameSong.key(id: "a1", cutKey: "") == "a1")
        #expect(SameSong.key(id: "a1", cutKey: "k") == "k")
    }

    /// Nothing folds by title: two versions with brackets in the name stay two songs; two copies with one cut key
    /// are one, whatever their names.
    @Test func nothingFoldsByTitle() {
        let c = crate([
            ("a", "Song (Extended Mix)", nil, nil, nil, nil),
            ("b", "Song (Club Remix)", nil, nil, nil, nil),
            ("c", "Song", "k1", nil, nil, nil),
            ("d", "Song (copy)", "k1", nil, nil, nil),
            ("e", "Other", "", nil, nil, nil),
        ])
        #expect(c.sameSongGroups == [["a"], ["b"], ["c", "d"], ["e"]])
        #expect(c.tracks.map(\.recordingKey) == ["a", "b", "k1", "k1", "e"])
    }

    /// The scoring sees copies as one recording (it never pairs a song with its own copy), through the same key.
    @Test func scoringUsesTheSameKey() {
        var c = crate([("a", "One", "k", nil, nil, nil), ("b", "Two", "k", nil, nil, nil), ("x", "Three", nil, nil, nil, nil)])
        #expect(c.tracks.compactMap { $0.scoringTrack()?.cutKey } == ["k", "k", "x"])
        c.tracks[2].ident.cutKey = ""
        #expect(c.tracks[2].scoringTrack()?.cutKey == "x")
    }

    func place(_ id: String, _ disc: String?, _ folder: String? = nil, _ track: Int? = nil) -> SameSong.Place {
        SameSong.Place(id: id, disc: disc, folder: folder, track: track)
    }

    @Test func thePlayingDiscLeads() {
        let places = [place("a", "CD1", "Warm", 3), place("b", "CD2", "Peak", 1), place("c", "CD3", "Late", 2)]
        let order = ["CD1", "CD2", "CD3"]
        #expect(SameSong.ordered(places, playingDisc: "CD2", discOrder: order).map(\.id) == ["b", "a", "c"])
        #expect(SameSong.ordered(places, playingDisc: "CD3", discOrder: order).map(\.id) == ["c", "a", "b"])
    }

    @Test func failingThatTheFirstDiscInTheDJsOrder() {
        let places = [place("a", "Peak", "x", 1), place("b", "Warm up", "y", 4), place("c", nil)]
        // the playing song is on a disc that holds no copy, or on none
        #expect(SameSong.ordered(places, playingDisc: "Late", discOrder: ["Warm up", "Peak", "Late"]).map(\.id) == ["b", "a", "c"])
        #expect(SameSong.ordered(places, playingDisc: nil, discOrder: ["Peak", "Warm up"]).map(\.id) == ["a", "b", "c"])
        // a disc missing from the order comes after the ordered ones, by name; copies on no disc come last
        #expect(SameSong.ordered(places, playingDisc: nil, discOrder: ["Warm up"]).map(\.id) == ["b", "a", "c"])
    }

    @Test func twoCopiesOnOneDiscByFolderThenTrack() {
        let places = [place("a", "CD1", "B", 1), place("b", "CD1", "A", 9), place("c", "CD1", "A", 2)]
        #expect(SameSong.ordered(places, playingDisc: "CD1", discOrder: ["CD1"]).map(\.id) == ["c", "b", "a"])
    }

    /// Prints made from numbers rather than audio: the rule only sees words and which frames have sound.
    func print(_ seed: UInt64, frames: Int) -> RecordingPrint {
        var x = seed
        let words = (0..<frames).map { _ -> UInt32 in
            x = x &* 6364136223846793005 &+ 1442695040888963407
            return UInt32(truncatingIfNeeded: x >> 32)
        }
        return RecordingPrint(words: words, sounding: [Bool](repeating: true, count: frames))
    }

    @Test func copiesAreGroupedThroughChains() {
        let a = print(1, frames: 3000)
        let b = RecordingPrint(words: a.words, sounding: a.sounding)
        var cWords = a.words
        for i in stride(from: 0, to: cWords.count, by: 3) { cWords[i] ^= 0xFF }   // a quarter of the bits of a third of the frames
        let c = RecordingPrint(words: cWords, sounding: a.sounding)
        let other = print(2, frames: 3000)
        let longer = print(1, frames: 3000 + Int(5 / RecordingPrint.frameStepS))
        let keys = SameSong.copies(["z9": a, "b1": b, "c3": c, "o": other, "l": longer])
        #expect(keys == ["z9": "b1", "b1": "b1", "c3": "b1"])
    }

    @Test func setCutKeysKeepsEntriesNotPrinted() {
        var cr = crate([("a", "One", nil, "CD1", "F", 1), ("b", "One copy", "old", "CD2", "F", 1),
                        ("c", "Two", "stale", nil, nil, nil), ("d", "Lab", "lab-key", nil, nil, nil)])
        let p = print(1, frames: 2000), q = print(3, frames: 2000)
        let n = cr.setCutKeys(prints: ["a": p, "b": p, "c": q])
        #expect(n == 2)
        #expect(cr.tracks.map(\.ident.cutKey) == ["a", "a", nil, "lab-key"])
        #expect(cr.sameSongGroups == [["a", "b"], ["c"], ["d"]])
        // every copy keeps its own place
        #expect(cr.tracks.map(\.ident.disc) == ["CD1", "CD2", nil, nil])
    }

    /// The keys survive the writer and the reader (crate v1, no new field).
    @Test func cutKeysRoundTrip() throws {
        var cr = crate([("a", "One", nil, "CD1", "F", 1), ("b", "One copy", nil, "CD2", "F", 1)])
        let p = print(1, frames: 2000)
        cr.setCutKeys(prints: ["a": p, "b": p])
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("samesong-\(UUID().uuidString).deckiecrate")
        defer { try? FileManager.default.removeItem(at: dir) }
        try CrateWriter.write(cr, to: dir)
        let back = try CrateReader.read(from: dir)
        #expect(back.sameSongGroups == [["a", "b"]])
    }
}
