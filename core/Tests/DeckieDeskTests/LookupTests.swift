import Foundation
import Testing
import DeckieCrate
import DeckieLookup
@testable import DeckieDesk

/// The lookup through MusicBrainz (D36) on answers recorded once from the real service (LookupSongs): what each song
/// sends, how candidates are ranked, the review, applying it, the sent list, the engine's messages. No test reaches
/// the network: the recorded transport answers only what it has, and "no connection" to anything else.
@Suite struct LookupTests {
    func review(_ tracks: [CrateTrack], isrcs: [String: String] = [:]) -> DeskLookup.Review {
        let t = RecordedTransport(folder: LookupSongs.fixtures)
        let run = DeskLookupRun(plan: DeskLookup.plan(LookupSongs.songs(tracks), isrcs: isrcs), client: LookupSongs.client(t),
                                sent: { _ in })
        return run.run()
    }

    func discReview(_ table: DiscTable, prefix: String, name: String? = nil, transport: LookupTransport? = nil) -> DeskLookup.Review {
        let (tracks, numbers) = LookupSongs.discSongs(table, prefix: prefix)
        let plan = DeskLookup.discPlan(source: "Disc", table: table, songs: LookupSongs.songs(tracks), numbers: numbers, name: name)
        return DeskLookupRun(plan: plan, client: LookupSongs.client(transport ?? RecordedTransport(folder: LookupSongs.fixtures)),
                             sent: { _ in }).run()
    }

    // MARK: what is sent

    @Test func eachSongSendsOnlyWhatItsSentenceSays() {
        let asks = LookupSongs.songs(LookupSongs.all).map { DeskLookup.ask($0) }
        #expect(asks[0] == .init(kind: "words", isrc: nil, query: RecordingQuery(title: "Around the World", artist: "Daft Punk")))
        #expect(asks[2].kind == "none")                                    // "Track 03" with a file name that says nothing
        #expect(asks[4].kind == "isrc" && asks[4].isrc == "GBDUW0600009" && asks[4].query == nil)
        #expect(asks[5] == .init(kind: "fileName", isrc: nil, query: RecordingQuery(title: "da funk", artist: "daft punk")))
        // D39: the version is kept and shown, never sent: the bare title and the first credited artist go.
        #expect(asks[6].query == RecordingQuery(title: "Around the World", artist: "Daft Punk"))
        // A release the song's tags gave goes too; nothing else of the song does (no path, no folder, no length).
        var t = LookupSongs.around
        t.ident.facts[SongFacts.release] = .init("Homework", from: "tag")
        t.file.rel = "Stick 9/Secret Folder/01 Around the World.wav"
        let q = DeskLookup.ask(LookupSongs.songs([t])[0]).query
        #expect(q == RecordingQuery(title: "Around the World", artist: "Daft Punk", release: "Homework"))
        let url = MusicBrainz.address("recording", [("query", MusicBrainz.lucene(q!)!)]).absoluteString
        #expect(!url.contains("Secret") && !url.contains("429") && !url.contains("Stick"))
    }

    @Test func theSentenceSaysWhatGoesToWhomAndHowLong() {
        let one = DeskLookup.plan(LookupSongs.songs([LookupSongs.around]))
        #expect(one.summary.scope == "song")
        #expect(one.summary.sentence.first == DeskWords.text("lookupSendOne"))
        #expect(one.summary.sentence.contains { $0.contains("The songs themselves are not sent") })
        #expect(one.summary.what == [["title", "Around the World"], ["artist", "Daft Punk"]])
        let many = DeskLookup.plan(LookupSongs.songs(LookupSongs.all))
        #expect(many.summary.songs == 7 && many.summary.byIsrc == 1 && many.summary.byFileName == 1 && many.summary.nothingToSend == 1)
        #expect(many.summary.requests == 12 && many.summary.seconds == 12)
        #expect(many.summary.sentence[0] == "Desk will send the titles, artists and releases of 6 songs to MusicBrainz, a public music encyclopedia, one request a second, so this takes about 12 seconds.")
        #expect(many.summary.sentence.contains("1 of them has an ISRC, the recording's serial number: that is sent first."))
        #expect(many.summary.sentence.contains("1 has nothing to look it up by and is left out."))
        let disc = DeskLookup.discPlan(source: "Friday", table: LookupSongs.exampleDisc, songs: [], numbers: [:], name: "Friday late")
        #expect(disc.summary.sentence[0].hasPrefix("Desk will send the lengths of this disc's 6 songs to MusicBrainz"))
        #expect(disc.summary.sentence[0].contains("“Friday late”"))
        for line in many.summary.sentence + disc.summary.sentence {
            #expect(!line.contains("{"), "\(line)")
            #expect(!line.lowercased().contains("track") && !line.contains("AI"), "\(line)")
        }
    }

    // MARK: ranking

    @Test func theOneThatFitsByLengthIsChosenAndItsReleaseYearAndLabelCome() throws {
        let r = review([LookupSongs.around])
        let s = try #require(r.songs.first)
        #expect(s.outcome == "found" && s.chosen == 0 && !s.several)
        let c = s.candidates[0]
        #expect(c.title == "Around the World" && c.artist == "Daft Punk" && c.fit == "fits" && !c.otherVersion)
        #expect(abs((c.seconds ?? 0) - 429.506) < 0.001)
        #expect(c.year == "1996" && c.label == "Virgin" && c.release == "Around the World")
        // Shown, not preferred: other versions (a remix, live, another length) come after it, each saying why.
        #expect(s.candidates.dropFirst().allSatisfy { $0.otherVersion || $0.fit == "unknown" })
        #expect(s.candidates.contains { $0.notes.contains("live") && $0.otherVersion })
        #expect(s.candidates.contains { $0.notes.contains("remix") && $0.otherVersion })
        // Only empty fields are ticked; the names the song already has are not offered.
        #expect(Set(c.changes.map(\.field)) == ["release", "year", "label"] && c.changes.allSatisfy(\.tick))
    }

    @Test func aVersionInTheDJsTitleIsNeverReplacedAndTheOriginalIsNotPreferred() throws {
        let s = try #require(review([LookupSongs.radio]).songs.first)
        let c = s.candidates[try #require(s.chosen)]
        #expect(norm(c.version) == "radio edit" && c.fit == "fits")
        #expect(!c.changes.contains { $0.field == "version" || $0.field == "title" })
        // The original (no version) at a similar length is shown as the original, unticked.
        let original = try #require(s.candidates.first { $0.version == nil && $0.fit == "fits" })
        #expect(original.otherVersion && original.notes.contains("original"))
        #expect(original.changes.filter { ["release", "year", "label"].contains($0.field) }.allSatisfy { !$0.tick && $0.note == "original" })
        // A candidate with another version beside a song that has one: the version change is locked.
        var song = LookupSongs.radio
        song.ident.version = "Club Mix"
        let other = DeskLookup.changes(c, song: LookupSongs.songs([song])[0])
        let v = try #require(other.first { $0.field == "version" })
        #expect(v.locked && v.note == "yourVersion" && !v.tick)
    }

    func norm(_ s: String?) -> String { DeskLookup.norm(s) }

    @Test func noneFitsAndNothingFoundAndNothingToSend() throws {
        var slow = LookupSongs.blue
        slow.file.durationS = 333.3                                  // no Blue Monday of 5:33 among the answers
        let r = review([slow, LookupSongs.unknown, LookupSongs.blank])
        #expect(r.songs[0].outcome == "found" && r.songs[0].chosen == nil)
        #expect(r.songs[0].candidates.allSatisfy { $0.fit != "fits" })
        #expect(r.songs[1].outcome == "nothing" && r.songs[1].candidates.isEmpty)
        #expect(r.songs[2].outcome == "nothingToSend")
        // The song MusicBrainz knows nothing of was asked once more with free words (D39), and the line says so.
        #expect(DeskLookup.summaryLine(r) == "1 of 2 found. 1 not found: edits and bootlegs often aren't. 1 was asked again with free words.")
        let single = review([LookupSongs.unknown])
        #expect(DeskLookup.summaryLine(single) == "MusicBrainz doesn't know this one. That's usual for edits and bootlegs. The name is yours to give.")
    }

    @Test func anISRCNamesASongWithNoTitleAndAFileNameNamesAnother() throws {
        let r = review([LookupSongs.byIsrc, LookupSongs.byFileName])
        let a = r.songs[0].candidates[try #require(r.songs[0].chosen)]
        #expect(a.title == "Around the World" && a.agree >= 3)
        #expect(a.changes.first { $0.field == "title" }?.tick == true && a.changes.first { $0.field == "artist" }?.after == "Daft Punk")
        let b = r.songs[1].candidates[try #require(r.songs[1].chosen)]
        #expect(b.title == "Da Funk" && b.fit == "fits" && b.label == "Soma Records")
    }

    @Test func aDJsOwnNameIsLockedAndATagIsNotTickedOver() throws {
        var t = LookupSongs.around
        t.ident.facts[SongFacts.year] = .init("1990", from: "tag")
        t.ident.facts[SongFacts.label] = .init("My label", from: SongFacts.Origin.user)
        let c = try #require(review([t]).songs.first?.candidates.first { $0.year == "1996" && $0.fit == "fits" && !$0.otherVersion })
        let year = try #require(c.changes.first { $0.field == "year" })
        #expect(!year.tick && !year.locked && year.note == "filled" && year.before == "1990")
        let label = try #require(c.changes.first { $0.field == "label" })
        #expect(label.locked && label.note == "yours")
    }

    @Test func aTitleWithNoArtistGivesAListToChooseFromNotAnAnswer() throws {
        // The answer to the Around the World search, served for the file-name words of a file with no tags.
        let index = try JSONDecoder().decode([String: RecordedTransport.Entry].self,
                                             from: Data(contentsOf: LookupSongs.fixtures.appendingPathComponent("index.json")))
        let file = try #require(index.first { $0.key.contains("Around%20the%20World%22%20%2Bartist") && !$0.key.contains("Radio") }?.value.file)
        struct Same: LookupTransport { let body: Data; var available: Bool { true }; func send(_ r: LookupRequest) throws -> LookupResponse { LookupResponse(status: 200, body: body) } }
        let body = try Data(contentsOf: LookupSongs.fixtures.appendingPathComponent(file))
        let untagged = LookupSongs.song("u1", "", seconds: 429.4, file: "01 Around the World.wav", source: "filename")
        let radio = LookupSongs.song("u2", "", seconds: 239.0, file: "Around the World (Radio Edit).wav", source: "filename")
        let plan = DeskLookup.plan(LookupSongs.songs([untagged, radio]))
        #expect(plan.asks.map(\.kind) == ["fileName", "fileName"])
        #expect(plan.asks[0].query == RecordingQuery(words: "Around the World"))
        let r = DeskLookupRun(plan: plan, client: LookupSongs.client(Same(body: body)), sent: { _ in }).run()
        #expect(r.songs[0].outcome == "found" && r.songs[0].chosen == nil)
        #expect(r.songs[0].candidates.first?.fit == "fits")
        // The file name's version counts: an answer with no version is the original, not this edit.
        #expect(r.songs[1].chosen == nil)
        let originals = r.songs[1].candidates.filter { $0.version == nil }
        #expect(originals.allSatisfy { $0.otherVersion })
    }

    // MARK: discs

    @Test func aKnownDiscNamesEverySong() throws {
        let r = discReview(LookupSongs.exampleDisc, prefix: "x")
        #expect(r.discMatch == "exact" && r.found == 6)
        #expect(r.songs.map { $0.candidates[$0.chosen ?? 0].title } == ["Rysperdal Gstp", "Nicotine", "Genius", "Twilight", "Dunkelheit", "Smog"])
        let first = r.songs[0].candidates[0]
        #expect(first.artist == "Ettella Diamant" && first.release == "Ettella Diamant" && first.label == "Deadred Records" && first.year == "2004")
        #expect(first.notes.contains("disc"))
        #expect(first.changes.first { $0.field == "title" }?.tick == true)  // "Track 01" is no name
    }

    @Test func aFuzzyMatchCountsOnlyWhenEverySongIsTheSameLength() {
        // The fuzzy search answers discs that are near; none has these four lengths.
        let r = discReview(LookupSongs.strangeDisc, prefix: "s")
        #expect(r.discMatch == nil && r.found == 0 && r.failure == nil)
        #expect(r.songs.allSatisfy { $0.outcome == "nothing" })
    }

    @Test func aDiscFoundByItsNameIsCheckedSongBySongAndNeverChosenByItself() throws {
        // A scripted service: the disc is unknown, its name finds the example disc's release, read for its songs.
        let fixtures = LookupSongs.fixtures
        let index = try JSONDecoder().decode([String: RecordedTransport.Entry].self, from: Data(contentsOf: fixtures.appendingPathComponent("index.json")))
        let discFile = try #require(index.first { $0.key.contains("49HHV7Eb8UKF3aQiNmu1GR8vKTY-") }?.value.file)
        let disc = try JSONSerialization.jsonObject(with: Data(contentsOf: fixtures.appendingPathComponent(discFile))) as! [String: Any]
        let release = (disc["releases"] as! [[String: Any]])[0]
        final class Scripted: LookupTransport, @unchecked Sendable {
            let release: Data
            var asked: [String] = []
            init(_ r: Data) { release = r }
            var available: Bool { true }
            func send(_ r: LookupRequest) throws -> LookupResponse {
                let u = r.url.absoluteString
                asked.append(u)
                if u.contains("/discid/") { return LookupResponse(status: 200, body: Data(#"{"release-count":0,"releases":[]}"#.utf8)) }
                if u.contains("/release?") { return LookupResponse(status: 200, body: Data(#"{"count":1,"releases":[{"id":"d3dc4be9-9749-4959-99e5-133d0cb467fe","title":"Ettella Diamant"}]}"#.utf8)) }
                return LookupResponse(status: 200, body: release)
            }
        }
        let s = Scripted(try JSONSerialization.data(withJSONObject: release))
        let r = discReview(LookupSongs.exampleDisc, prefix: "y", name: "Ettella Diamant", transport: s)
        #expect(s.asked.count == 3)
        #expect(s.asked[1].contains("release?query=release%3A%22Ettella%20Diamant%22%20AND%20tracksmedium%3A6"))
        #expect(r.discMatch == "byName" && r.found == 6)
        #expect(r.songs.allSatisfy { $0.chosen == nil && $0.candidates.first?.notes.contains("byName") == true })
    }

    // MARK: stopping, failing, applying

    @Test func aStopKeepsWhatWasFound() {
        let plan = DeskLookup.plan(LookupSongs.songs(LookupSongs.all))
        let run = DeskLookupRun(plan: plan, client: LookupSongs.client(RecordedTransport(folder: LookupSongs.fixtures)), sent: { _ in })
        let r = run.run { p in if p.done == 2 { run.stop() } }
        #expect(r.stopped)
        #expect(r.songs.count == 7 && r.songs[0].outcome == "found" && r.songs[1].outcome == "found")
        #expect(r.songs.dropFirst(2).allSatisfy { $0.outcome == "notAsked" })
        #expect(DeskLookup.summaryLine(r).hasSuffix("Stopped before the end; what was found is here."))
    }

    @Test func noConnectionEndsTheBatchInPlainWords() {
        struct Offline: LookupTransport { var available: Bool { true }; func send(_ r: LookupRequest) throws -> LookupResponse { throw LookupFailure.noConnection } }
        let plan = DeskLookup.plan(LookupSongs.songs([LookupSongs.around, LookupSongs.blue]))
        let r = DeskLookupRun(plan: plan, client: LookupSongs.client(Offline()), sent: { _ in }).run()
        #expect(r.failure == "noConnection" && r.songs[0].outcome == "failed" && r.songs[1].outcome == "notAsked")
        #expect(DeskLookup.summaryLine(r) == "Looking up needs a connection to the internet. Everything else works without one.")
    }

    @Test func applyingFillsTheSameFieldsMarkedAsTheLookupsAndKeepsThemOnARead() throws {
        let tracks = [LookupSongs.around, LookupSongs.byIsrc]
        var c = crate(tracks)
        var corrections = NameCorrections()
        var book = NameBook()
        let r = review(tracks)
        let n = DeskLookup.apply(r, DeskLookup.defaultChoices(r), to: &c, corrections: &corrections, book: &book)
        #expect(n == 2)
        let a = c.tracks[0], b = c.tracks[1]
        #expect(a.ident.facts[SongFacts.label] == .init("Virgin", from: "lookup:musicbrainz"))
        #expect(a.ident.facts[SongFacts.year]?.from == "lookup:musicbrainz" && a.ident.title == "Around the World")
        #expect(b.ident.title == "Around the World" && b.ident.artist == "Daft Punk")
        #expect(corrections.byId[b.id]?.from?["title"] == "lookup:musicbrainz")
        // The panel says where each came from, and the song no longer needs a name.
        let f = DeskNaming.facts(b, book: book, corrections: corrections)
        #expect(f.title.from == "lookup:musicbrainz" && !f.title.guess)
        #expect(DeskNaming.reason(b, f) == nil)
        #expect(DeskWords.coded("factFrom", "lookup:musicbrainz") == "from MusicBrainz, when you looked it up")
        // Read again: the file's names come back, then the corrections put the lookup's back with their origin.
        var reread = crate([LookupSongs.around, LookupSongs.byIsrc])
        corrections.apply(to: &reread)
        #expect(reread.tracks[1].ident.title == "Around the World")
        // A fact filled where nothing was is in the crate file, not the corrections: a tag read later wins over it.
        #expect(corrections.byId[a.id]?.facts?[SongFacts.label] == nil)
        // Nothing the DJ did not tick is applied, and the DJ's own entry never is.
        var c2 = crate([LookupSongs.byIsrc])
        var corr2 = NameCorrections()
        corr2.give("eeee", field: "title", value: "My name", how: "user")
        corr2.apply(to: &c2)
        let r2 = review([LookupSongs.byIsrc])
        let i = try #require(r2.songs[0].chosen)
        DeskLookup.apply(r2, [.init(song: "eeee", candidate: i, fields: ["title", "year"])], to: &c2, corrections: &corr2, book: &book)
        #expect(c2.tracks[0].ident.title == "My name" && c2.tracks[0].ident.artist == nil)
        #expect(c2.tracks[0].ident.facts[SongFacts.year]?.values == ["1996"])
    }

    @Test func aFactTickedOverATagStaysTheLookupsAfterARead() throws {
        var t = LookupSongs.around
        t.ident.facts[SongFacts.year] = .init("1990", from: "tag")
        var c = crate([t])
        var corrections = NameCorrections()
        var book = NameBook()
        let r = review([t])
        let i = try #require(r.songs[0].candidates.firstIndex { $0.year == "1996" && $0.fit == "fits" && !$0.otherVersion })
        DeskLookup.apply(r, [.init(song: t.id, candidate: i, fields: ["year"])], to: &c, corrections: &corrections, book: &book)
        #expect(c.tracks[0].ident.facts[SongFacts.year] == .init("1996", from: "lookup:musicbrainz"))
        var reread = crate([t])
        corrections.apply(to: &reread)
        #expect(reread.tracks[0].ident.facts[SongFacts.year] == .init("1996", from: "lookup:musicbrainz"))
    }

    // MARK: the session and the engine

    func session(_ name: String, tracks: [CrateTrack]) throws -> DeskSession {
        let home = DeskHome(root: try scratch(name))
        try home.prepare()
        var info = try home.shelf.make(name: "Friday")
        info.sourceRoots["Stick 9"] = "/nowhere/Stick 9"
        try home.shelf.save(info)
        try CrateWriter.write(crate(tracks, name: "Friday"), to: home.shelf.package(info.id))
        return DeskSession(home: home)
    }

    @Test func theSessionAppliesALookupAsOneStepOfUndoAndKeepsWhatWasSent() throws {
        let s = try session("lookup-session", tracks: [LookupSongs.around, LookupSongs.byIsrc, LookupSongs.blank])
        let plan = try s.lookupPlan(scope: "songs")                   // the songs that need a name
        #expect(Set(plan.songs.map(\.track.id)) == ["eeee", "cccc"])
        let lock = s.sentLock, home = s.home
        let run = DeskLookupRun(plan: plan, client: LookupSongs.client(RecordedTransport(folder: LookupSongs.fixtures)),
                                sent: { LookupLog.record($0, home: home, lock: lock) })
        s.setReview(run.run())
        #expect(try s.applyLookup(nil) == 1)
        #expect(s.undoName == "undoLookup")
        #expect(s.crate?.tracks.first { $0.id == "eeee" }?.ident.title == "Around the World")
        try s.undo()
        #expect(s.crate?.tracks.first { $0.id == "eeee" }?.ident.title == "Track 05")
        let log = s.lookupLog
        #expect(log.sent.map(\.kind) == ["isrcSearch", "release"])
        #expect(log.sent[0].fields == [["isrc", "GBDUW0600009"]] && log.sent[0].address.hasPrefix("https://musicbrainz.org/ws/2/recording?query=isrc:"))
        // Kept in Desk's storage, readable back, and clearable.
        #expect(FileManager.default.fileExists(atPath: s.home.root.appendingPathComponent("lookups.json").path))
        try s.clearSent()
        #expect(s.lookupLog.sent.isEmpty)
    }

    @Test func theEngineLooksUpWithRecordedAnswersAndThePagesSeeEveryStep() throws {
        let s = try session("lookup-engine", tracks: [LookupSongs.around, LookupSongs.unknown])
        let lines = Lines()
        let engine = DeskProtocol(home: s.home, output: { lines.add($0) }, makeRun: { _, _, _ in fatalError() },
                                  analysisCheck: {}, environment: [RecordedTransport.environmentVariable: LookupSongs.fixtures.path])
        engine.start()
        #expect((lines.events("hello").first?["lookup"] as? [String: Any])?["available"] as? Bool == true)
        engine.handle(line: #"{"id":1,"type":"lookup.plan","scope":"songs","songs":["aaaa","dddd"]}"#)
        let plan = try #require(lines.reply(1)?["plan"] as? [String: Any])
        #expect((plan["sentence"] as? [String])?.first?.contains("2 songs") == true)
        #expect(lines.reply(1)?["explained"] as? Bool == false)
        engine.handle(line: #"{"id":2,"type":"lookup.start"}"#)
        engine.handle(line: #"{"id":3,"type":"song.fix","song":"aaaa","title":"x"}"#)   // busy while it looks up, unless it has ended
        engine.waitForLookup()
        #expect(lines.events("lookup.progress").count >= 2)
        let finished = try #require(lines.events("lookup.finished").first)
        #expect(finished["summary"] as? String == "1 of 2 found. 1 not found: edits and bootlegs often aren't. 1 was asked again with free words.")
        engine.handle(line: #"{"id":4,"type":"lookup.apply","choices":[{"song":"aaaa","candidate":0,"fields":["label"]}]}"#)
        #expect(lines.reply(4)?["songs"] as? Int == 1)
        engine.handle(line: #"{"id":5,"type":"lookup.sent"}"#)
        let sent = try #require(lines.reply(5)?["sent"] as? [[String: Any]])
        #expect(sent.count == 4 && (sent[0]["at"] as? String)?.hasSuffix("Z") == true)   // the second ask is the fourth
        engine.handle(line: #"{"id":6,"type":"lookup.plan","scope":"song","song":"aaaa"}"#)
        engine.handle(line: #"{"id":7,"type":"lookup.start"}"#)
        engine.waitForLookup()
        engine.handle(line: #"{"id":8,"type":"lookup.plan","scope":"song","song":"aaaa"}"#)
        #expect(lines.reply(8)?["explained"] as? Bool == true)          // shown once; from now on under the button
    }

    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [[String: Any]] = []
        func add(_ d: Data) {
            guard let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
            lock.lock(); all.append(o); lock.unlock()
        }
        func events(_ name: String) -> [[String: Any]] { lock.lock(); defer { lock.unlock() }; return all.filter { $0["event"] as? String == name } }
        func reply(_ id: Int) -> [String: Any]? { lock.lock(); defer { lock.unlock() }; return all.first { ($0["re"] as? Int) == id } }
    }
}
