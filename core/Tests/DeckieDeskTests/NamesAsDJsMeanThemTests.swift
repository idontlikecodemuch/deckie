import Foundation
import Testing
import DeckieCrate
import DeckieBuild
import DeckieLookup
@testable import DeckieDesk

/// D39: Desk reads a song's name the way a DJ means it (research AC, section 5). Kept, shown and sent kept apart; clean
/// or dirty a fact of its own; the artist from a folder only for an artist's album; and the lookup's rules (folding,
/// versions by kind, whole names, compilations, a DJ's edit). Every name is invented; nothing reaches the network.
@Suite struct NamesAsDJsMeanThemTests {
    func song(_ title: String, artist: String?, version: String? = nil, seconds: Double = 240, file: String? = nil,
              facts: [String: CrateTrack.Fact] = [:], source: String = "tag") -> DeskNaming.Song {
        var t = entry("s" + String(abs(title.hashValue) % 100000), title, disc: "Stick 1", folder: "", track: 1, rel: file ?? "\(title).mp3")
        t.file.durationS = seconds
        t.file.name = file ?? "\(title).mp3"
        t.ident.artist = artist; t.ident.version = version; t.ident.facts = facts; t.ident.source = source
        return DeskNaming.Song(track: t, facts: DeskNaming.facts(t, book: NameBook(), corrections: NameCorrections()))
    }

    func cand(_ title: String, _ artist: String, credited: [String]? = nil, featuring: [Bool]? = nil, seconds: Double = 240,
              year: String? = "1999", release: String? = "First Light", label: String? = nil) -> DeskLookup.Candidate {
        let v = DeskLookup.candidateVersion(title: title, disambiguation: nil)
        return DeskLookup.Candidate(recording: nil, title: v.title, version: v.version, artist: artist, release: release, releaseId: nil,
                                    year: year, label: label, seconds: seconds, fit: "unknown", difference: nil, otherVersion: false,
                                    notes: [], agree: 0, changes: [], score: 0, credited: credited ?? NameReading.credit(artist).map(\.name),
                                    featuring: featuring ?? NameReading.credit(artist).map(\.featuring), match: nil, titleAgrees: nil,
                                    artistAgrees: nil, lyrics: v.reading?.lyrics?.rawValue, disagree: nil)
    }

    func decide(_ s: DeskNaming.Song, _ cs: [DeskLookup.Candidate]) -> (candidates: [DeskLookup.Candidate], chosen: Int?, several: Bool, mode: String?, rules: [String]) {
        let ask = DeskLookup.ask(s)
        let known = DeskLookup.Known(s, ask: ask)
        var all = cs
        for i in all.indices { DeskLookup.rate(&all[i], known: known) }
        return DeskLookup.order(all, known: known)
    }

    // MARK: kept, shown, sent (AC 5.1)

    @Test func whatIsSentLeavesTheVersionMarksAndNumbersOutAndSendsTheFirstArtist() {
        let s = song("Night Drive (DJ Ostro Intro - Dirty)", artist: "Marlo Dune ft. Kaya Venn")
        #expect(DeskLookup.ask(s).query == RecordingQuery(title: "Night Drive", artist: "Marlo Dune"))
        let f = song("", artist: nil, file: "07. X Marlo Dune - Night Drive - Ostro Remix [siteName.com].mp3", source: "filename")
        #expect(DeskLookup.ask(f).query?.title == "Night Drive")
        let p = song("Night Drive (Part 2) (Clean)", artist: "Marlo Dune")
        #expect(DeskLookup.ask(p).query?.title == "Night Drive (Part 2)")      // a part of the title is the title
        // Shown: with its version, as DJs write it.
        #expect(DeskSongRow(s.track).shown == "Night Drive (DJ Ostro Intro - Dirty)")
        var v = s.track; v.ident.title = "Night Drive"; v.ident.version = "DJ Ostro Remix"
        #expect(DeskSongRow(v).shown == "Night Drive (DJ Ostro Remix)")
    }

    /// The test the brief asks for: no path in Desk rewrites a name the DJ gave or that came from the file. Reading a
    /// file name keeps its title part as written; a lookup's every candidate, with every field forced on, leaves a song's
    /// title, artist, version, genre and clean-or-dirty as they were.
    @Test func noPathRewritesANameTheDJGaveOrThatCameFromTheFile() throws {
        for stem in ["Marlo Dune ft. Kaya Venn - Night Drive (Intro - Dirty)", "07 - Marlo Dune - Night Drive - DJ Ostro Remix",
                     "(307) [Marlo Dune & Kaya Venn] Night Drive (Ostro '07 Remix)", "04 - Night Drive (Ostro Remix) - Marlo Dune",
                     "Marlo Dune - Night Drive (Official Video) [siteName.com]", "1.04 Marlo Dune, Kaya Venn - Night Drive"] {
            let n = LocalFacts.nameFromFile(rel: "Folder/" + stem + ".mp3", number: nil, siblings: [])
            #expect(stem.contains(n.title), "\(stem): \(n.title)")
            if let a = n.artist { #expect(stem.contains(a), "\(stem): \(a)") }
            if let v = n.version { #expect(stem.contains(v), "\(stem): \(v)") }
        }
        let songs = [song("Night Drive (Extended Mix) (Clean)", artist: "Marlo Dune ft. Kaya Venn",
                          facts: [SongFacts.genre: .init("Wedding", from: "user"), SongFacts.lyrics: .init("clean", from: "tag")]),
                     song("Night Drive", artist: "Marlo Dune", version: "Ostro Remix", source: "user"),
                     song("night drive", artist: "marlo dune", source: "filename")]
        let candidates = [cand("Night Drive (radio edit) [explicit]", "Marlo Dune feat. Kaya Venn"),
                          cand("Night Drive (Extended Mix)", "Marlo Dune & Kaya Venn", seconds: 400),
                          cand("Night Drive", "Marlo Dune")]
        for s in songs {
            var cs = decide(s, candidates).candidates
            for i in cs.indices { cs[i].changes = DeskLookup.changes(cs[i], song: s, mode: i == 0 ? "original" : nil) }
            #expect(cs.allSatisfy { $0.changes.allSatisfy { !(["title", "artist"].contains($0.field)) } })
            #expect(cs.allSatisfy { $0.changes.allSatisfy { $0.field != SongFacts.genre && $0.field != SongFacts.lyrics } })
            let r = DeskLookup.Review(scope: "songs", source: nil, songs: [DeskLookup.SongResult(song: s.track.id, title: s.track.ident.title,
                seconds: 240, ask: DeskLookup.ask(s), outcome: "found", failure: nil, candidates: cs, chosen: 0, several: false)],
                stopped: false, failure: nil, requests: 0, discMatch: nil)
            for i in cs.indices {
                var c = Crate(manifest: CrateManifest(crateId: "c", name: "c", createdAt: "", devicesSeen: []), tracks: [s.track])
                var corrections = NameCorrections(), book = NameBook()
                let every = ["title", "artist", "version", SongFacts.genre, SongFacts.lyrics] + cs[i].changes.map(\.field)
                DeskLookup.apply(r, [DeskLookup.Choice(song: s.track.id, candidate: i, fields: every)], to: &c, corrections: &corrections, book: &book)
                let after = c.tracks[0].ident
                #expect(after.title == s.track.ident.title && after.artist == s.track.ident.artist)
                // A version the song has stays; one it lacks is only ever the DJ's tick, never Desk's.
                if s.track.ident.version != nil { #expect(after.version == s.track.ident.version) }
                #expect(!cs[i].changes.contains { $0.field == "version" && $0.tick })
                #expect(after.facts[SongFacts.genre] == s.track.ident.facts[SongFacts.genre])
                #expect(after.facts[SongFacts.lyrics] == s.track.ident.facts[SongFacts.lyrics])
            }
        }
    }

    // MARK: clean or dirty (AC 5.2)

    @Test func cleanOrDirtyIsReadFromTheNameAndTagsAndSetOnlyByTheDJ() throws {
        #expect(LocalFacts.lyrics(title: "Night Drive (Intro - Dirty)", version: nil, grouping: nil, comment: nil) == .dirty)
        #expect(LocalFacts.lyrics(title: "Night Drive", version: "Clean Edit", grouping: nil, comment: nil) == .clean)
        #expect(LocalFacts.lyrics(title: "Night Drive", version: nil, grouping: ["Clean"], comment: nil) == .clean)
        #expect(LocalFacts.lyrics(title: "Night Drive", version: nil, grouping: nil, comment: ["#Explicit MWW Lights Down"]) == .dirty)
        #expect(LocalFacts.lyrics(title: "Night Drive (Clean Harbour Remix)", version: nil, grouping: nil, comment: nil) == nil)
        #expect(LocalFacts.lyrics(title: "Night Drive (Clean)", version: "Dirty", grouping: nil, comment: nil) == nil)  // they disagree
        // "Radio" is a hint, never an answer; a song that says nothing is not said, never clean.
        #expect(LocalFacts.lyrics(title: "Night Drive (Radio Edit)", version: nil, grouping: nil, comment: nil) == nil)
        // Set by the DJ: one of two words, or not said.
        var t = song("Night Drive", artist: "Marlo Dune").track
        var corrections = NameCorrections()
        #expect(DeskNaming.fixFacts(&t, [SongFacts.lyrics: "dirty"], corrections: &corrections))
        #expect(t.ident.facts[SongFacts.lyrics] == .init("dirty", from: "user"))
        DeskNaming.fixFacts(&t, [SongFacts.lyrics: "rude"], corrections: &corrections)
        #expect(t.ident.facts[SongFacts.lyrics] == nil)
        let f = DeskNaming.facts(t, book: NameBook(), corrections: corrections)
        #expect(f.lyrics.value == nil && !f.others.contains { $0.name == SongFacts.lyrics })
        #expect(DeskWords.text("lyrics.none") == "Not said")
    }

    // MARK: the artist from a folder (AC 3.1)

    @Test func theArtistComesFromAFolderOnlyWhenItIsPlainlyOneArtistsAlbum() {
        let album = ["01 Night Drive", "02 Lights Down", "03 First Light"].map { LocalNames.Sibling(stem: $0) }
        let a = LocalNames.readFolder(["Marlo Dune - First Light (2019)"], siblings: album)
        #expect(a.kind == .artistAlbum && a.artist == "Marlo Dune" && a.release == "First Light")
        #expect(LocalNames.readFolder(["Marlo Dune - First Light", "CD1"], siblings: album).artist == "Marlo Dune")
        // A compilation names the release, never the artist; nor do dated folders or the DJ's own categories.
        for name in ["VA - Club Summer 2004", "Various Artists - Club Summer 2004", "VA-Club.Summer-2CD-MP3"] {
            let c = LocalNames.readFolder([name], siblings: album)
            #expect(c.kind == .compilation && c.artist == nil, "\(name)")
        }
        #expect(LocalNames.readFolder(["Compilations", "Club Summer 2004"], siblings: album).kind == .compilation)
        #expect(LocalNames.readFolder(["VA - Club Summer 2004", "Disc 2"], siblings: album).kind == .compilation)
        #expect(LocalNames.readFolder(["2026-09"], siblings: album).artist == nil)
        #expect(LocalNames.readFolder(["Wedding"], siblings: album).artist == nil)
        // Files with artists of their own, or files that are not numbered, keep the folder from naming anyone.
        let named = ["01 Marlo Dune - Night Drive", "02 Tessa Ray - Lights Down"].map { LocalNames.Sibling(stem: $0) }
        let mixed = LocalNames.readFolder(["Kaya Venn - Summer Set"], siblings: named)
        #expect(mixed.artist == nil && mixed.severalArtists && mixed.kind == .category)
        #expect(LocalNames.readFolder(["Marlo Dune - First Light"], siblings: [LocalNames.Sibling(stem: "Night Drive")]).artist == nil)
        let marked = album.map { var s = $0; s.compilationMark = true; return s }
        #expect(LocalNames.readFolder(["Marlo Dune - First Light"], siblings: marked).kind == .compilation)
        let tagged = album.enumerated().map { i, s in var s = s; s.tagArtist = i == 0 ? "Marlo Dune" : "Tessa Ray"; return s }
        #expect(LocalNames.readFolder(["Marlo Dune - First Light"], siblings: tagged).artist == nil)
    }

    // MARK: versions by kind (AC 5.5)

    @Test func versionsAreComparedByKindNameAndLengthNotSpelling() {
        func m(_ a: String?, _ b: String?, fits: Bool = true) -> VersionMatch {
            VersionCompare.compare(song: a.map(NameReading.readVersion), candidate: b.map(NameReading.readVersion), fits: fits)
        }
        #expect(m("Extended", "Extended Mix") == .same && m("12\" Mix", "extended version") == .same)
        #expect(m(nil, "Original Mix") == .same && m(nil, "2011 Remaster") == .same)
        #expect(m(nil, "Radio Edit") == .catalogueWord && m(nil, "Radio Edit", fits: false) == .other)
        #expect(m("Ostro Remix", "Ostro Rmx") == .same && m("Ostro Remix", "Venn Remix") == .other && m("Ostro Remix", "Remix") == .other)
        #expect(m("Clean", nil) == .sameTake && m("Extended Mix (Dirty)", "Extended Mix") == .sameTake)
        #expect(m("Intro - Dirty", nil, fits: false) == .original && m("Quick Hit", nil) == .original && m("Ostro Edit", nil) == .original)
        #expect(m("Transition 100-128", nil) == .notInCatalogue && m("Mashup", "Mashup") == .notInCatalogue)
        #expect(m("Live at Harbour Hall", nil) == .other && m("Radio Edit", nil) == .other)
        #expect(m("Extended", "Club Mix") == .other)                       // probably the same: to be checked on real rows
    }

    // MARK: the lookup's rules (AC 5.4)

    @Test func candidatesThatDifferOnlyInSpellingFoldAndFillOnlyWhatTheyAgreeOn() throws {
        let s = song("Night Drive", artist: "Marlo Dune")
        let r = decide(s, [cand("Night Drive", "Marlo Dune", release: "First Light"),
                           cand("Night Drive", "Marlo Dune feat. Kaya Venn", credited: ["Marlo Dune", "Kaya Venn"], featuring: [false, true],
                                year: "2000", release: "Club Summer 2004")])
        let i = try #require(r.chosen)
        #expect(!r.several && r.rules.contains("fold"))
        #expect(Set(r.candidates[i].disagree ?? []) == [SongFacts.release, SongFacts.label, SongFacts.year])
        let ch = DeskLookup.changes(r.candidates[i], song: s)
        #expect(ch.allSatisfy { !$0.tick && $0.note == "disagree" })
        // Years more than one apart are two records: several, a list.
        let apart = decide(s, [cand("Night Drive", "Marlo Dune", year: "1999"),
                               cand("Night Drive", "Marlo Dune feat. Kaya Venn", featuring: [false, true], year: "2012")])
        #expect(apart.chosen == nil && apart.several)
        // Clean against explicit never folds.
        let twins = decide(s, [cand("Night Drive (clean)", "Marlo Dune"), cand("Night Drive (explicit)", "Marlo Dune")])
        #expect(twins.chosen == nil && twins.several)
    }

    @Test func agreementIsByWholeWordsAndWholeNames() {
        let s = song("Drive", artist: "Marlo Dune")
        #expect(decide(s, [cand("Night Drive", "Marlo Dune")]).chosen == nil)            // a one-word title inside a longer one
        #expect(decide(s, [cand("Drive", "Marlo Dunes")]).chosen == nil)                  // a name inside another name
        #expect(decide(s, [cand("Drive", "Marlo Dune & Tessa Ray")]).chosen == nil)       // a co-artist the DJ's credit lacks
        #expect(decide(s, [cand("Drive", "Marlo Dune feat. Tessa Ray", featuring: [false, true])]).chosen == 0)  // a guest it may
        let duo = song("Drive", artist: "Marlo & Dune")
        #expect(decide(duo, [cand("Drive", "Marlo & Dune", credited: ["Marlo & Dune"], featuring: [false])]).chosen == 0)
    }

    @Test func aCompilationSongKeepsItsCopysReleaseAndGetsWhenItFirstCameOut() throws {
        var s = song("Night Drive", artist: "Marlo Dune", facts: [SongFacts.compilation: .init("1", from: "tag"),
                                                                  SongFacts.release: .init("Club Summer 2004", from: "tag")])
        let r = decide(s, [cand("Night Drive", "Marlo Dune", year: "1999", release: "First Light", label: "Harbour")])
        let c = r.candidates[try #require(r.chosen)]
        let ch = DeskLookup.changes(c, song: s)
        #expect(ch.first { $0.field == SongFacts.originalYear }?.tick == true && ch.first { $0.field == SongFacts.originalLabel }?.tick == true)
        #expect(ch.first { $0.field == SongFacts.release }.map { !$0.tick && $0.note == "firstRelease" } ?? true)
        #expect(!ch.contains { $0.field == SongFacts.year || $0.field == SongFacts.label })
        // Its folder can say so too.
        s.facts = DeskNaming.facts(s.track, book: NameBook(), corrections: NameCorrections())
        s.track.ident.facts = [:]
        s.folder = LocalNames.FolderReading(kind: .compilation, artist: nil, release: "Club Summer 2004")
        #expect(DeskLookup.changes(c, song: s).contains { $0.field == SongFacts.originalYear })
    }

    @Test func aDJsEditTakesTheOriginalsYearAndLabelMarkedAsTheOriginals() throws {
        let s = song("Night Drive (Intro - Dirty)", artist: "Marlo Dune", seconds: 262)
        let r = decide(s, [cand("Night Drive", "Marlo Dune", seconds: 230, year: "1999", label: "Harbour")])
        let i = try #require(r.chosen)
        #expect(r.mode == "original" && r.rules.contains("original"))
        let ch = DeskLookup.changes(r.candidates[i], song: s, mode: r.mode)
        #expect(Set(ch.filter(\.tick).map(\.field)) == [SongFacts.originalYear, SongFacts.originalLabel])
        #expect(ch.allSatisfy { $0.note == "original" || $0.field == "version" })
        // Applied, the origin says it is the original's; the song's name, version and clean-or-dirty stay.
        let review = DeskLookup.Review(scope: "song", source: nil, songs: [{
            var x = DeskLookup.SongResult(song: s.track.id, title: s.track.ident.title, seconds: 262, ask: DeskLookup.ask(s), outcome: "found",
                                          failure: nil, candidates: r.candidates.enumerated().map { j, c in var c = c; c.changes = j == i ? ch : []; return c },
                                          chosen: i, several: false)
            x.mode = r.mode; return x }()], stopped: false, failure: nil, requests: 0, discMatch: nil)
        var c = Crate(manifest: CrateManifest(crateId: "c", name: "c", createdAt: "", devicesSeen: []), tracks: [s.track])
        var corrections = NameCorrections(), book = NameBook()
        DeskLookup.apply(review, DeskLookup.defaultChoices(review), to: &c, corrections: &corrections, book: &book)
        #expect(c.tracks[0].ident.facts[SongFacts.originalYear] == .init("1999", from: "lookup:musicbrainz:original"))
        #expect(c.tracks[0].ident.title == s.track.ident.title)
        #expect(DeskWords.coded("factFrom", "lookup:musicbrainz:original") == "from MusicBrainz: the original's")
        // A mashup or a transition is in no catalogue: never chosen.
        #expect(decide(song("Night Drive (Transition 100-128)", artist: "Marlo Dune"), [cand("Night Drive", "Marlo Dune")]).chosen == nil)
    }

    @Test func aSecondAskSendsFreeWordsThenTheNameInTheVersion() {
        let s = song("Night Drive (DJ Ostro Bootleg)", artist: "Marlo Dune")
        let qs = DeskLookup.secondAsks(s, first: DeskLookup.ask(s))
        #expect(qs == [RecordingQuery(words: "Night Drive Marlo Dune"), RecordingQuery(words: "Night Drive dj ostro")])
    }
}
