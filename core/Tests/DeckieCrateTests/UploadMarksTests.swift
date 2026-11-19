import Testing
@testable import DeckieCrate

/// What a first run over test folders found in names (Nov 18, 2026), as general rules: an upload's or a download's
/// marks kept out of the title (and kept as notes), a leading track number with any of the usual separators, the part
/// after a second dash read by the version vocabulary (a version, a part of the title, or else a note), a name with a
/// single dash before an upload's mark or after a version word run together, and an artist repeated at the head of its
/// own title. Every name here is invented.
@Suite struct UploadMarksTests {
    @Test func marksAreKnownByKindNotBySong() {
        for mark in ["Official Video", "Official Audio", "Official Music Video", "Official Lyric Video", "Lyric Video", "Lyrics",
                     "Visualizer", "HD", "HQ", "Official HD Video", "Lyrics Video HQ", "320kbps", "320 kbps", "256k", "192 kbit/s",
                     "siteName.pm", "tunes.example.ru", "www.siteName.com", "Free Download", "Audio"] {
            #expect(NameReading.isUploadMark(mark), "\(mark)")
        }
        // A year, a key, a tempo, a version, a part of the title, a featured guest or a phrase: not a mark.
        for text in ["2019", "8A", "128 BPM", "Extended Mix", "Ostro Remix", "Part 2", "feat. Kaya Venn", "Forget the Road",
                     "Official Secrets", "Lyrical Mix", "Video Killed the Radio", "Dirty", "Clean", "Live at Harbour Hall"] {
            #expect(!NameReading.isUploadMark(text), "\(text)")
        }
    }

    @Test func aMarkIsTheWholeTextNotAPartOfIt() {
        // Marks together are still a mark.
        for mark in ["Official Video 320kbps", "Free Download www.siteName.com", "320 kbps siteName.pm", "HQ - 256 kbps"] {
            #expect(NameReading.isUploadMark(mark), "\(mark)")
        }
        // A name with a mark in it, or beside it, is not a mark: the name is still there.
        for text in ["Night Drive [320kbps]", "Night Drive 320kbps", "Night Drive (320 kbps)", "Night Drive www.siteName.com",
                     "Night Drive (siteName.pm)", "Night Drive (Official Video)", "Lights Down 192 kbit/s"] {
            #expect(!NameReading.isUploadMark(text), "\(text)")
        }
    }

    @Test func aBitrateBareAtTheEndIsAMark() {
        let cases: [(String, String, [String])] = [
            ("Night Drive 320kbps", "Night Drive", ["320kbps"]),
            ("Night Drive (Ostro Remix) - 320 kbps", "Night Drive (Ostro Remix)", ["320 kbps"]),
            ("Night Drive [HD] 256kbps", "Night Drive", ["[HD]", "256kbps"]),
            // A number that is no bitrate, or nothing left: as written.
            ("Night Drive 320", "Night Drive 320", []),
            ("320kbps", "320kbps", []),
        ]
        for (written, kept, marks) in cases {
            let r = NameReading.withoutMarks(written)
            #expect(r.text == kept, "\(written): \(r.text)")
            #expect(r.marks == marks, "\(written): \(r.marks)")
        }
        let t = NameReading.readTitle("Night Drive (Ostro Remix) 320kbps")
        #expect(t.title == "Night Drive" && t.version?.kinds == [.remix] && t.notes == ["320kbps"])
    }

    @Test func anArtistAndATitleWithAMarkAfterOneDash() {
        // (stem, artist, title as kept, marks): the one-dash guard for a name run together does not take a title with a
        // mark in it for a mark.
        let cases: [(String, String?, String, [String])] = [
            ("Marlo Dune - Night Drive [320kbps]", "Marlo Dune", "Night Drive", ["[320kbps]"]),
            ("Marlo Dune - Night Drive (320 kbps)", "Marlo Dune", "Night Drive", ["(320 kbps)"]),
            ("Marlo Dune - Night Drive 320kbps", "Marlo Dune", "Night Drive", ["320kbps"]),
            ("Marlo Dune - Night Drive (Ostro Remix) [siteName.pm]", "Marlo Dune", "Night Drive (Ostro Remix)", ["[siteName.pm]"]),
            ("Marlo Dune - Night Drive (Official Video) [320kbps]", "Marlo Dune", "Night Drive", ["(Official Video)", "[320kbps]"]),
            // The run-together guard still holds: only marks after the one dash.
            ("Marlo Dune Night Drive - 320kbps", nil, "Marlo Dune Night Drive", ["320kbps"]),
            ("Marlo Dune Night Drive - Official Video [320kbps]", nil, "Marlo Dune Night Drive", ["Official Video [320kbps]"]),
        ]
        for (stem, artist, title, marks) in cases {
            let r = NameReading.readFileName(stem)
            #expect(r.artist == artist, "\(stem): artist \(String(describing: r.artist))")
            #expect(r.titleWritten == title, "\(stem): title \(r.titleWritten)")
            #expect(r.marks == marks, "\(stem): marks \(r.marks)")
        }
    }

    @Test func marksComeOutOfTheTitleAsWrittenAndAreKept() {
        let cases: [(String, String, [String])] = [
            ("Night Drive (Official Video)", "Night Drive", ["(Official Video)"]),
            ("Night Drive (Lyrics)", "Night Drive", ["(Lyrics)"]),
            ("Night Drive [HD] (Extended Mix)", "Night Drive (Extended Mix)", ["[HD]"]),
            ("Night Drive (Ostro Remix) (320kbps)", "Night Drive (Ostro Remix)", ["(320kbps)"]),
            ("Night Drive Soundtrack Version (siteName.pm)", "Night Drive Soundtrack Version", ["(siteName.pm)"]),
            ("Night Drive (Intro - Dirty) [www.siteName.com]", "Night Drive (Intro - Dirty)", ["[www.siteName.com]"]),
            // Nothing to take out, or nothing left: as written.
            ("Night Drive (Part 2) (2019)", "Night Drive (Part 2) (2019)", []),
            ("(Official Video)", "(Official Video)", []),
        ]
        for (written, kept, marks) in cases {
            let r = NameReading.withoutMarks(written)
            #expect(r.text == kept, "\(written): \(r.text)")
            #expect(r.marks == marks, "\(written): \(r.marks)")
        }
    }

    @Test func fileNamesFromUploadsAndRips() {
        // (stem, artist, title as kept, version after a second dash, marks)
        let cases: [(String, String?, String, String?, [String])] = [
            // A version after a second dash is the song's version, with no brackets and no number in front.
            ("Marlo Dune - Night Drive - Fog Lines Remix", "Marlo Dune", "Night Drive", "Fog Lines Remix", []),
            ("07 Marlo Dune - Night Drive - Ostro Little Bit Edit", "Marlo Dune", "Night Drive", "Ostro Little Bit Edit", []),
            // What is neither a version nor a part of the title after a second dash: an uploader's name, kept as a note.
            ("Marlo Dune - Night Drive (Extended Mix) - Harbour Uploads", "Marlo Dune", "Night Drive (Extended Mix)", nil, ["Harbour Uploads"]),
            ("Marlo Dune x Kaya Venn - Night Drive [Ostro Re-Edit] [Extended] - Tide Channel", "Marlo Dune x Kaya Venn",
             "Night Drive [Ostro Re-Edit] [Extended]", nil, ["Tide Channel"]),
            ("Marlo Dune - Night Drive - Official Video", "Marlo Dune", "Night Drive", nil, ["Official Video"]),
            // Both: an uploader's name after a version.
            ("Marlo Dune - Night Drive - Ostro Remix - Harbour Uploads", "Marlo Dune", "Night Drive", "Ostro Remix", ["Harbour Uploads"]),
            // A part of the title after the dash stays in the title.
            ("Marlo Dune - Night Drive - Part 2", "Marlo Dune", "Night Drive - Part 2", nil, []),
            // Marks in brackets.
            ("Marlo Dune - Night Drive (Official Audio)", "Marlo Dune", "Night Drive", nil, ["(Official Audio)"]),
            ("Marlo Dune, Kaya Venn - Night Drive (Lyrics)", "Marlo Dune, Kaya Venn", "Night Drive", nil, ["(Lyrics)"]),
            ("Marlo_Dune_-_Night_Drive_(siteName.pm)", "Marlo Dune", "Night Drive", nil, ["(siteName.pm)"]),
            // Leading track numbers with the usual separators.
            ("01- Night Drive", nil, "Night Drive", nil, []),
            ("01_Night Drive", nil, "Night Drive", nil, []),
            ("01. Night Drive", nil, "Night Drive", nil, []),
            ("01 - Night Drive", nil, "Night Drive", nil, []),
            // One dash, then an upload's mark, or a version word run on before it: the whole name, no artist.
            ("Marlo Dune Night Drive - Official Video", nil, "Marlo Dune Night Drive", nil, ["Official Video"]),
            ("Marlo Dune Night Drive Ostro 90s Rework - Harbour Uploads", nil, "Marlo Dune Night Drive Ostro 90s Rework", nil,
             ["Harbour Uploads"]),
            // The guards: Bandcamp's album, a number that is an artist, a title in brackets that is no mark.
            ("Tessa Ray - Lights Down EP - 02 Lights Down (Dub)", "Tessa Ray", "Lights Down (Dub)", nil, []),
            ("112 - Night Drive", "112", "Night Drive", nil, []),
            ("Marlo Dune - Night Drive (Forget the Road)", "Marlo Dune", "Night Drive (Forget the Road)", nil, []),
            ("04 - Night Drive (Ostro Remix) - Marlo Dune", "Marlo Dune", "Night Drive (Ostro Remix)", nil, []),
        ]
        for (stem, artist, title, version, marks) in cases {
            let r = NameReading.readFileName(stem)
            #expect(r.artist == artist, "\(stem): artist \(String(describing: r.artist))")
            #expect(r.titleWritten == title, "\(stem): title \(r.titleWritten)")
            #expect(r.dashedVersion == version, "\(stem): version \(String(describing: r.dashedVersion))")
            #expect(r.marks == marks, "\(stem): marks \(r.marks)")
        }
        // A version read from the dash keeps its kinds; the shown title carries it.
        let v = NameReading.readFileName("Marlo Dune - Night Drive - Fog Lines Remix")
        #expect(v.version?.kinds == [.remix] && v.shown == "Night Drive (Fog Lines Remix)")
    }

    @Test func anArtistRepeatedAtTheHeadOfItsOwnTitle() {
        #expect(NameReading.withoutArtistHead("Marlo Dune - Night Drive (Ostro Remix)", artist: "Marlo Dune") == "Night Drive (Ostro Remix)")
        #expect(NameReading.withoutArtistHead("MARLO DUNE - Night Drive", artist: "Marlo Dune ft. Kaya Venn") == "Night Drive")
        // Not the artist, or nothing after it: left alone.
        #expect(NameReading.withoutArtistHead("Night Drive - Extended Mix", artist: "Marlo Dune") == nil)
        #expect(NameReading.withoutArtistHead("Kaya Venn - Night Drive", artist: "Marlo Dune") == nil)
        #expect(NameReading.withoutArtistHead("Night Drive", artist: "Marlo Dune") == nil)
    }
}
