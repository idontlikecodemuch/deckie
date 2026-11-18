import Foundation
import Testing
import DeckieCrate
import DeckieBuild
@testable import DeckieDesk

/// Names from a first run over test folders (Nov 18, 2026), through Desk's whole gathering (`LocalFacts.gather`) on
/// small files made here: a version after a second dash kept and shown; an upload's marks and an uploader's name kept
/// out of the title and kept as the `name_notes` fact; an artist repeated at the head of a title tag; a title tag that
/// names another song than the file name, kept and marked for a look; an artist tag holding the remixer; and a name
/// run together before a channel's name, read with no artist. Every name is invented.
@Suite struct WildNamesTests {
    static let mpegFrame: [UInt8] = [0xFF, 0xFB, 0x90, 0x64] + [UInt8](repeating: 0, count: 60)

    /// An ID3v2.3 tag with a UTF-8 title and artist where given, then one MPEG frame; with neither, no tag at all.
    static func file(title: String? = nil, artist: String? = nil) -> [UInt8] {
        func frame(_ id: String, _ text: String) -> [UInt8] {
            let data = [3] + Array(text.utf8)
            let n = data.count
            return Array(id.utf8) + [UInt8(n >> 24 & 0xFF), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)] + [0, 0] + data
        }
        var frames: [UInt8] = []
        if let title { frames += frame("TIT2", title) }
        if let artist { frames += frame("TPE1", artist) }
        guard !frames.isEmpty else { return mpegFrame }
        let body = frames + [UInt8](repeating: 0, count: 8)
        let n = body.count
        return Array("ID3".utf8) + [3, 0, 0] + [UInt8(n >> 21 & 0x7F), UInt8(n >> 14 & 0x7F), UInt8(n >> 7 & 0x7F), UInt8(n & 0x7F)]
            + body + mpegFrame
    }

    /// Gathers names and facts for the files given (file name to bytes) in one folder, as a run does.
    static func gather(_ files: [(String, [UInt8])]) throws -> Crate {
        let top = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-wild-\(UUID().uuidString)")
        let folder = top.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var crate = Crate(manifest: CrateManifest(crateId: "c", name: "N", createdAt: "2026-11-18T00:00:00Z", devicesSeen: []), tracks: [])
        var refs: [String: [LocalFacts.FileRef]] = [:]
        for (i, (name, bytes)) in files.enumerated() {
            try Data(bytes).write(to: folder.appendingPathComponent(name))
            let rel = "Downloads/" + name
            var t = entry("s\(i)", (name as NSString).deletingPathExtension, disc: nil, folder: "Downloads", track: nil, rel: rel)
            t.ident.source = "filename"
            crate.tracks.append(t)
            refs[t.id] = [.init(url: folder.appendingPathComponent(name), rel: rel, place: t.ident.ownPlace)]
        }
        _ = LocalFacts.gather(&crate, files: refs, djHome: nil, tops: [], records: nil)
        return crate
    }

    @Test func aVersionAfterASecondDashIsKeptAndShown() throws {
        let c = try Self.gather([("Marlo Dune - Night Drive - Fog Lines Remix.mp3", Self.file()),
                                 ("Kaya Venn - Lights Down - Ostro Little Bit Edit.mp3", Self.file(artist: "Kaya Venn")),
                                 ("Tessa Ray - Harbour Song - Dirty.mp3", Self.file(title: "", artist: "Tessa Ray"))])
        let want: [(String, String)] = [("Night Drive", "Fog Lines Remix"), ("Lights Down", "Ostro Little Bit Edit"), ("Harbour Song", "Dirty")]
        for (i, w) in want.enumerated() {
            let t: CrateTrack = c.tracks[i]
            #expect(t.ident.title == w.0 && t.ident.version == w.1, "\(t.ident.title) / \(String(describing: t.ident.version))")
            let shown: String = DeskSongRow(t).shown
            #expect(shown == w.0 + " (" + w.1 + ")")
        }
    }

    @Test func marksAndAnUploaderAreKeptOutOfTheTitleAndKeptAsNotes() throws {
        let c = try Self.gather([
            ("Marlo Dune - Night Drive (Official Video).mp3", Self.file()),
            ("Kaya Venn - Lights Down (Extended Mix) - Harbour Uploads.mp3", Self.file()),
            ("01- Harbour Song.mp3", Self.file()),
            ("tagged.mp3", Self.file(title: "Tessa Ray - Fog Lines (Ostro Remix) (320kbps)", artist: "Tessa Ray")),
        ])
        func t(_ i: Int) -> CrateTrack { c.tracks[i] }
        #expect(t(0).ident.title == "Night Drive" && t(0).ident.artist == "Marlo Dune")
        #expect(t(0).ident.facts[SongFacts.nameNotes] == CrateTrack.Fact(["(Official Video)"], from: "filename"))
        #expect(t(1).ident.title == "Lights Down (Extended Mix)" && t(1).ident.artist == "Kaya Venn" && t(1).ident.version == nil)
        #expect(t(1).ident.facts[SongFacts.nameNotes] == CrateTrack.Fact(["Harbour Uploads"], from: "filename"))
        #expect(t(2).ident.title == "Harbour Song")
        // The title tag: the artist repeated at its head and the bitrate come out; the bitrate is kept as a note.
        #expect(t(3).ident.title == "Fog Lines (Ostro Remix)" && t(3).ident.artist == "Tessa Ray" && t(3).ident.source == "tag")
        #expect(t(3).ident.facts[SongFacts.nameNotes] == CrateTrack.Fact(["(320kbps)"], from: "tag"))
        #expect(!c.tracks.contains { $0.flags.contains(LocalFacts.nameDisagrees) })
    }

    @Test func aTitleTagNamingAnotherSongIsKeptAndMarkedForALook() throws {
        let c = try Self.gather([
            ("Marlo Dune - Night Drive - Ostro Remix.mp3", Self.file(title: "Harbour Lights", artist: "Marlo Dune")),
            ("Marlo Dune - Night Drive (Ostro Remix).mp3", Self.file(title: "Night Drive", artist: "Marlo Dune")),
            ("Track 04.mp3", Self.file(title: "Harbour Lights", artist: "Marlo Dune")),
        ])
        let other = c.tracks[0], same = c.tracks[1], placeholder = c.tracks[2]
        #expect(other.ident.title == "Harbour Lights" && other.ident.source == "tag")       // the tag's reading is kept
        #expect(other.flags.contains(LocalFacts.nameDisagrees) && LocalFacts.needsName(other))
        #expect(DeskSongRow(other).nameReason == "disagree")
        #expect(DeskWords.coded("nameReason", "disagree") != "disagree")
        // A tag and a name that share a word, and a file name that names no song, are not a disagreement.
        #expect(!same.flags.contains(LocalFacts.nameDisagrees) && !LocalFacts.needsName(same))
        #expect(!placeholder.flags.contains(LocalFacts.nameDisagrees))
        // The DJ's own name takes it out of the list; reading again with a matching tag takes the flag off.
        var named = other; named.ident.source = "user"
        #expect(!LocalFacts.needsName(named) && DeskSongRow(named).nameReason == nil)
        // "Looks right" offers the title of a song in the list for this reason.
        let song = DeskNaming.Song(track: other, facts: DeskNaming.facts(other, book: NameBook(), corrections: NameCorrections()))
        #expect(DeskNaming.looksRight(songs: [song]).changes.map(\.field) == ["title"])
    }

    @Test func anArtistTagHoldingTheRemixerGivesWayToTheFileName() throws {
        let c = try Self.gather([
            ("Marlo Dune - Night Drive (Ostro Remix).mp3", Self.file(title: "Marlo Dune - Night Drive (Ostro Remix)", artist: "Ostro the Second")),
            // The artist tag names someone the version does not: it stands.
            ("Marlo Dune - Lights Down (Ostro Remix).mp3", Self.file(title: "Lights Down (Ostro Remix)", artist: "Kaya Venn")),
        ])
        let r = c.tracks[0], kept = c.tracks[1]
        #expect(r.ident.artist == "Marlo Dune" && r.ident.title == "Night Drive (Ostro Remix)" && r.ident.source == "tag+filename")
        #expect(r.ident.facts[SongFacts.remixer] == CrateTrack.Fact(["Ostro the Second"], from: "tag"))
        #expect(kept.ident.artist == "Kaya Venn" && kept.ident.facts[SongFacts.remixer] == nil)
    }

    @Test func aNameRunTogetherBeforeAChannelNeedsALookAndIsNotSwapped() throws {
        let c = try Self.gather([("Marlo Dune  Night Drive Ostro 90s Rework - Harbour Uploads.mp3", Self.file())])
        let t = c.tracks[0]
        #expect(t.ident.title == "Marlo Dune Night Drive Ostro 90s Rework" && t.ident.artist == nil)
        #expect(LocalFacts.needsName(t) && DeskSongRow(t).nameReason == "noArtist")
        #expect(t.ident.facts[SongFacts.nameNotes] == CrateTrack.Fact(["Harbour Uploads"], from: "filename"))
    }
}
