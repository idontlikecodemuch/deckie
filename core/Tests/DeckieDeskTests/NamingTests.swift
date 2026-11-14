import Foundation
import Testing
import DeckieAudio
import DeckieCrate
import DeckieBuild
import DeckieDisc
import DeckieTestSupport
@testable import DeckieDesk

/// A song as the tools see it, named as given and read from `from` (an `ident.source`).
func named(_ id: String, _ title: String, artist: String? = nil, version: String? = nil, from: String = "tag",
           file: String? = nil, seconds: Double = 200, number: Int = 1) -> CrateTrack {
    var t = entry(id, title, disc: "Friday night", folder: nil, track: number, rel: file ?? "Track \(number).wav")
    t.ident.artist = artist; t.ident.version = version; t.ident.source = from
    t.file.durationS = seconds
    if let file { t.file.name = file }
    return t
}

func songs(_ tracks: [CrateTrack], book: NameBook = NameBook(), fixes: NameCorrections = NameCorrections()) -> [DeskNaming.Song] {
    tracks.map { DeskNaming.Song(track: $0, facts: DeskNaming.facts($0, book: book, corrections: fixes)) }
}

@Suite struct DeskNamingTests {
    @Test func splittingTypedNames() {
        let s = DeskNaming.split("Artist A - Night drive (Extended mix)")
        #expect(s?.artist == "Artist A" && s?.title == "Night drive" && s?.version == "Extended mix")
        #expect(DeskNaming.split("Night drive [Dub]")?.version == "Dub")
        #expect(DeskNaming.split("Night drive") == nil)
        #expect(DeskNaming.split("Unknown - Night drive") == nil)     // "Unknown" names no one
        #expect(DeskNaming.readLine("07. Artist B - Low tide").artist == "Artist B")
        #expect(DeskNaming.readLine("3) Low tide").title == "Low tide")
    }

    @Test func whereEachFactCameFromAndWhatIsAGuess() {
        let t = named("a", "Night drive", artist: "Artist A", from: "filename+folder")
        let f = DeskNaming.facts(t, book: NameBook(), corrections: NameCorrections())
        #expect(f.title.from == "filename" && f.title.guess)
        #expect(f.artist.from == "folder" && f.artist.guess)
        #expect(DeskNaming.reason(t, f) == "guess")
        let tagged = named("b", "Sunrise", artist: "X")
        #expect(DeskNaming.reason(tagged, DeskNaming.facts(tagged, book: NameBook(), corrections: NameCorrections())) == nil)
        let blank = named("c", "Track 03", from: "filename")
        let bf = DeskNaming.facts(blank, book: NameBook(), corrections: NameCorrections())
        #expect(DeskNaming.reason(blank, bf) == "noTitle")
        #expect(bf.title.value == nil)
        #expect(DeskNaming.reason(named("d", "Sunrise"), DeskNaming.facts(named("d", "Sunrise"), book: NameBook(), corrections: NameCorrections())) == "noArtist")
    }

    @Test func aCheckedGuessKeepsItsOriginAndLeavesTheList() {
        var t = named("a", "Night drive", artist: "Artist A", from: "cdtext")
        var c = Crate(manifest: crate([]).manifest, tracks: [t])
        var fixes = NameCorrections()
        var book = NameBook()
        book.record(c, releases: [:])
        let p = DeskNaming.looksRight(songs: songs([t], book: book))
        #expect(p.changes.count == 2)
        #expect(DeskNaming.apply(p, to: &c, corrections: &fixes) == 1)
        t = c.tracks[0]
        let f = DeskNaming.facts(t, book: book, corrections: fixes)
        #expect(f.title.checked && f.title.from == "cdtext" && !f.title.guess)
        #expect(DeskNaming.reason(t, f) == nil)
        #expect(fixes.byId["a"]?.from?["title"] == "checked")
    }

    @Test func pastingAListLinesItUpAndWaitsWhenTheCountsDiffer() {
        let tracks = [named("1", "Track 01", from: "filename", number: 1), named("2", "Track 02", from: "filename", number: 2),
                      named("3", "Own name", artist: "Me", from: "user", number: 3)]
        var fixes = NameCorrections()
        fixes.give("3", field: "title", value: "Own name", how: "user")
        fixes.give("3", field: "artist", value: "Me", how: "user")
        let bad = DeskNaming.pasteList("A - One\nB - Two", songs: songs(tracks, fixes: fixes))
        #expect(bad.problem == "counts" && bad.changes.isEmpty && bad.songs == 3 && bad.lines == 2)
        var c = Crate(manifest: crate([]).manifest, tracks: tracks)
        var f2 = fixes
        #expect(DeskNaming.apply(bad, to: &c, corrections: &f2) == 0)

        let p = DeskNaming.pasteList("01. A - One (Club mix)\n02. B - Two\n03. C - Three", songs: songs(tracks, fixes: fixes))
        #expect(p.problem == nil)
        let one = p.changes.filter { $0.song == "1" }
        #expect(one.map(\.field).sorted() == ["artist", "title", "version"])
        #expect(one.allSatisfy { $0.tick })
        // The DJ's own names are shown locked and never applied.
        let three = p.changes.filter { $0.song == "3" }
        #expect(three.allSatisfy { $0.locked && !$0.tick && $0.note == "yours" })
        #expect(DeskNaming.apply(p, ticks: Set(p.changes.indices), to: &c, corrections: &f2) == 2)
        #expect(c.tracks[0].ident.title == "One" && c.tracks[0].ident.version == "Club mix" && c.tracks[0].ident.artist == "A")
        #expect(c.tracks[2].ident.title == "Own name")
        #expect(f2.byId["1"]?.from?["title"] == "pasted")
        #expect(DeskNaming.facts(c.tracks[0], book: NameBook(), corrections: f2).title.from == "pasted")
    }

    @Test func fillingOnlyWhatIsEmptyAndNeverTakingAVersion() {
        let t = named("1", "Night drive", artist: "Artist A", version: "Extended mix", from: "tag")
        let p = DeskNaming.pasteList("Other - Night drive", songs: songs([t]))
        // The title is the same; the artist has a name from the tags, so it is offered unticked; the version stays.
        #expect(p.changes.count == 1)
        #expect(p.changes[0].field == "artist" && !p.changes[0].tick && p.changes[0].note == "filled")
        let all = DeskNaming.pasteList("Other - Night drive", songs: songs([t]), onlyEmpty: false)
        #expect(all.changes[0].tick)
        #expect(!all.changes.contains { $0.field == "version" })
    }

    @Test func namesFromTheFileNamesByAPattern() {
        let m = DeskNaming.match("07 Artist B - Low tide (Dub)", pattern: "{number} {artist} - {title}")
        #expect(m?.artist == "Artist B" && m?.title == "Low tide" && m?.version == "Dub")
        #expect(DeskNaming.match("Low tide", pattern: "{artist} - {title}") == nil)
        #expect(DeskNaming.match("Low tide - Artist B", pattern: "{title} - {artist}")?.artist == "Artist B")
        let tracks = [named("1", "07 Artist B - Low tide", from: "filename", file: "07 Artist B - Low tide.wav"),
                      named("2", "x", from: "filename", file: "nothing like it.wav")]
        let p = DeskNaming.fromFileNames(pattern: "{number} {artist} - {title}", songs: songs(tracks))
        #expect(p.lines == 1 && p.problem == nil)
        #expect(p.changes.contains { $0.song == "1" && $0.field == "title" && $0.after == "Low tide" && $0.tick })
        #expect(DeskNaming.fromFileNames(pattern: "{artist} = {title}", songs: songs(tracks)).problem == "noMatch")
    }

    @Test func aPlaylistsLengthsAreChecked() {
        let text = """
            #EXTM3U
            #EXTINF:200,Artist A - One
            C:\\Music\\One.mp3
            #EXTINF:340,Artist B - Two
            /home/dj/Music/Two.flac
            """
        let entries = DeskNaming.readPlaylist(text)
        #expect(entries == [.init(seconds: 200, line: "Artist A - One"), .init(seconds: 340, line: "Artist B - Two")])
        let tracks = [named("1", "Track 01", from: "filename", seconds: 201.2, number: 1),
                      named("2", "Track 02", from: "filename", seconds: 230, number: 2)]
        let p = DeskNaming.fromPlaylist(entries, songs: songs(tracks))
        #expect(p.lengthsDiffer == 1)
        #expect(p.changes.filter { $0.song == "1" }.allSatisfy { $0.tick })
        #expect(p.changes.filter { $0.song == "2" }.allSatisfy { !$0.tick && $0.note == "lengthDiffers" })
        let plain = DeskNaming.readPlaylist("One.mp3\nTwo.mp3\n")
        #expect(DeskNaming.fromPlaylist(plain, songs: songs(tracks)).lengthsDiffer == nil)
    }
}

/// The naming flow through a desk's session: each tool one step of undo, saved, and kept across a re-read.
@Suite struct DeskSessionNamingTests {
    func make(_ name: String) throws -> (DeskSession, CrateInfo) {
        let home = DeskHome(root: try scratch(name))
        try home.prepare()
        var info = try home.shelf.make(name: "Friday")
        info.sourceRoots["Friday night"] = "/nowhere/Friday night"
        try home.shelf.save(info)
        let tracks = [named("aaaa", "Track 01", from: "filename", number: 1),
                      named("bbbb", "Night drive", artist: "Artist A", from: "cdtext", number: 2),
                      named("cccc", "Low tide", artist: "Artist C", from: "tag", number: 3)]
        try CrateWriter.write(crate(tracks, name: "Friday"), to: home.shelf.package(info.id))
        return (DeskSession(home: home), info)
    }

    @Test func pasteApplyUndoAndTheListShrinks() throws {
        let (s, info) = try make("naming-session")
        #expect(s.rows.filter { $0.needsName }.map(\.nameReason) == ["noTitle", "guess"])
        let p = try s.makePreview(tool: "paste", source: "Friday night", ids: nil, text: "Zed - Sunrise\nArtist A - Night drive\nArtist C - Low tide")
        #expect(p.problem == nil)
        #expect(try s.applyPreview(ticks: nil) == 1)
        #expect(s.undoName == "undoNames")
        let a = try #require(s.rows.first { $0.id == "aaaa" })
        #expect(a.title == "Sunrise" && a.artist == "Zed" && a.names?.title.from == "pasted")
        #expect(!a.needsName)
        // Saved at once: a new session sees it.
        let again = DeskSession(home: s.home)
        #expect(again.rows.first { $0.id == "aaaa" }?.title == "Sunrise")
        try s.undo()
        #expect(s.rows.first { $0.id == "aaaa" }?.title == "Track 01")
        try s.redo()
        // Looks right on the guess.
        #expect(try s.check(["bbbb"]) == 1)
        #expect(s.undoName == "undoCheck")
        #expect(s.rows.filter { $0.needsName }.isEmpty)
        // Typing over a guess makes it the DJ's.
        try s.undo()
        try s.fixName("bbbb", title: "Night drive (Club mix)")
        let b = try #require(s.rows.first { $0.id == "bbbb" })
        #expect(b.names?.title.from == "user" && b.names?.artist.from == "cdtext" && b.names?.artist.guess == true)
        _ = info
    }
}

/// A music CD through the one run, with the stand-in drive: copied off, named from its CD-Text, its source named after
/// the disc, the songs placed by number; a disc with no names; the copy kept once and removed with the source.
@Suite(.enabled(if: Engine.available, "needs ONNX Runtime and the Beat This! model"))
struct MusicCDRunTests {
    static func pcm(_ b: AudioBuffer) -> [Int16] { b.samples.map { Int16(max(-1, min(1, $0)) * 32767) } }

    static func makeDisc(_ folder: URL, names: Bool) throws {
        let b = TestTrack.render()
        let quiet = AudioBuffer(sampleRate: b.sampleRate, channelCount: b.channelCount, samples: b.samples.map { $0 * 0.5 })
        let text = names ? DiscFixture.response(DiscFixture.packs([
            (0x80, ["Friday night", "Night drive", "Café Ünder"].map(DiscFixture.latin1)),
            (0x81, ["DJ Vera", "Artist A", ""].map(DiscFixture.latin1)),
        ], lastSong: 2)) : nil
        try DiscFixture.writeStandIn(folder, songs: [pcm(b), pcm(quiet)], cdText: text, gap: 75)
    }

    @Test func aMusicCDIsCopiedNamedAndPlaced() async throws {
        let root = try scratch("music-cd")
        let disc = root.appendingPathComponent("E")
        try Self.makeDisc(disc, names: true)
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        let s = DeskSession(home: home)
        let drive = StandInDrive(folder: disc)
        let open: (String) throws -> MusicCD = { _ in SectorMusicCD(location: disc.path, device: drive) }
        let (request, ask) = try s.addMusicCDRequest(disc.path, open: open)
        #expect(request.source == "Friday night" && ask == nil)
        let info = try s.crateForRun(request)
        let analyser = try Builder.makeAnalyser(jobs: 1)
        func run(_ r: RunRequest) throws -> (crate: Crate, report: RunReport) {
            let run = DeskRun(home: home, crateId: info.id, request: r, jobs: 1, device: "Mac15,6", analyser: analyser,
                              signer: nil, printer: DeskRun.portablePrint)
            run.openMusicCD = open
            return try run.run()
        }
        let (c, report) = try await CPUTurns.exclusive { try run(request) }
        s.runEnded(info.id)
        #expect(report.wentIn == 2)
        #expect(report.disc?.text == "names" && report.disc?.songs == 2 && report.disc?.named == 2)
        #expect(report.disc?.damagedSectors == 0 && report.disc?.titled == true && (report.disc?.bytes ?? 0) > 0)
        let sorted = c.tracks.sorted { ($0.ident.track ?? 0) < ($1.ident.track ?? 0) }
        #expect(sorted.map(\.ident.track) == [1, 2])
        #expect(sorted.allSatisfy { $0.ident.disc == "Friday night" })
        #expect(sorted[0].ident.title == "Night drive" && sorted[0].ident.artist == "Artist A")
        // No performer for song 2: the disc's performer stands in.
        #expect(sorted[1].ident.title == "Café Ünder" && sorted[1].ident.artist == "DJ Vera")
        let row = try #require(s.rows.first { $0.id == sorted[0].id })
        #expect(row.names?.title.from == "cdtext" && row.names?.title.guess == true && row.nameReason == "guess")
        #expect(row.names?.release.value == "Friday night")
        // The copy: in Desk's storage, by the disc's id, the songs cut where the table says.
        let copy = request.folderURL
        #expect(DiscCopies.isCopy(copy, home: home))
        #expect(FileManager.default.fileExists(atPath: copy.appendingPathComponent("Track 01.wav").path))
        #expect(DiscCopies.size(home) > 0)
        // The same disc again: nothing is copied twice.
        let reads = drive.reads
        _ = try await CPUTurns.exclusive { try run(request) }
        #expect(drive.reads == reads)
        // Listen finds the copy.
        #expect(try s.audioFile(sorted[0].id).lastPathComponent == "Track 01.wav")
        // Removing the disc from the crate removes the copy.
        try s.removeSource("Friday night")
        #expect(!FileManager.default.fileExists(atPath: copy.path))
    }

    @Test func aDiscWithNoNamesAsksForItsName() async throws {
        let root = try scratch("music-cd-blank")
        let disc = root.appendingPathComponent("E")
        try Self.makeDisc(disc, names: false)
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        let s = DeskSession(home: home)
        let open: (String) throws -> MusicCD = { _ in SectorMusicCD(location: disc.path, device: StandInDrive(folder: disc)) }
        let (request, ask) = try s.addMusicCDRequest(disc.path, open: open)
        let placeholder = try #require(ask)
        #expect(placeholder.hasPrefix("Music CD, 2 songs, "))
        #expect(request.source == placeholder)
        let info = try s.crateForRun(request)
        // The DJ types the name while it is read; it is applied when the run ends, as one step of undo.
        try s.nameDisc(source: placeholder, to: "Friday night", running: true)
        let run = DeskRun(home: home, crateId: info.id, request: request, jobs: 1, device: "Mac15,6",
                          analyser: try Builder.makeAnalyser(jobs: 1), signer: nil, printer: DeskRun.portablePrint)
        run.openMusicCD = open
        let (_, report) = try await CPUTurns.exclusive { try run.run() }
        #expect(report.disc?.text == "none" && report.disc?.titled == false)
        s.runEnded(info.id)
        #expect(s.crate?.discPlan.map(\.name) == ["Friday night"])
        #expect(s.current?.name == "Friday night")   // the crate made from the disc follows its name
        #expect(s.undoName == "undoRename")
        #expect(s.rows.allSatisfy { $0.nameReason == "noTitle" })
        // Each song's file name is Track NN, its place the source and its number.
        #expect(s.crate?.tracks.compactMap(\.ident.track).sorted() == [1, 2])
    }
}
