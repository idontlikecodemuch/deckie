import Foundation
import Testing
import DeckieCrate
import DeckieLookup
@testable import DeckieDesk

/// The songs the lookup's tests (and the recorded answers) are about: well-known public recordings chosen for the
/// test, never a DJ's own music, with lengths set so that some fit and some do not.
enum LookupSongs {
    static let fixtures: URL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("DeckieLookupTests/Fixtures/musicbrainz", isDirectory: true)

    static func song(_ id: String, _ title: String, artist: String? = nil, version: String? = nil, seconds: Double,
                     file: String? = nil, facts: [String: CrateTrack.Fact] = [:], source: String = "tag") -> CrateTrack {
        var t = entry(id, title, disc: "Stick 9", folder: "", track: 1, rel: file ?? "\(title).wav")
        t.file.durationS = seconds
        t.file.name = file ?? "\(title).wav"
        t.ident.artist = artist
        t.ident.version = version
        t.ident.facts = facts
        t.ident.source = source
        return t
    }

    /// Around the World, the album version (7:09.5): fits MusicBrainz's album recording.
    static let around = song("aaaa", "Around the World", artist: "Daft Punk", seconds: 429.4)
    /// Blue Monday at 5:00: none of the first answers is this length.
    static let blue = song("bbbb", "Blue Monday", artist: "New Order", seconds: 300)
    /// No title and a file name that says nothing: nothing to send.
    static let blank = song("cccc", "Track 03", seconds: 200, file: "Track 03.wav", source: "filename")
    /// Words no catalogue knows.
    static let unknown = song("dddd", "Qzxv Plorbeth Wunk", artist: "Nobody Zzyx", seconds: 250)
    /// No title, but its file carries an ISRC.
    static let byIsrc = song("eeee", "Track 05", seconds: 429.6, file: "Track 05.wav",
                             facts: [SongFacts.isrc: .init("GBDUW0600009", from: "tag")], source: "filename")
    /// No title; the file name names it.
    static let byFileName = song("ffff", "Track 06", seconds: 328.0, file: "daft punk - da funk.mp3", source: "filename")
    /// The radio edit, as the DJ's tags say: a version in the DJ's title that no answer may replace.
    static let radio = song("gggg", "Around the World", artist: "Daft Punk", version: "Radio Edit", seconds: 238.6)

    static let all = [around, blue, blank, unknown, byIsrc, byFileName, radio]

    /// The example disc of MusicBrainz's own "Disc ID Calculation" page (six songs), known by its id.
    static let exampleDisc = DiscTable(tracks: [(1, 0), (2, 15213), (3, 32164), (4, 46442), (5, 63264), (6, 80339)],
                                       audioEnd: 95312)
    /// A disc no one has: its fuzzy search.
    static let strangeDisc = DiscTable(tracks: [(1, 0), (2, 17000), (3, 31000), (4, 52000)], audioEnd: 70000)
    /// A disc of 14 songs no one has, named "Discovery": found by its name.
    static let namedDisc = DiscTable(tracks: (1...14).map { ($0, ($0 - 1) * 15000) }, audioEnd: 14 * 15000)

    static func songs(_ tracks: [CrateTrack]) -> [DeskNaming.Song] {
        tracks.map { DeskNaming.Song(track: $0, facts: DeskNaming.facts($0, book: NameBook(), corrections: NameCorrections())) }
    }

    /// The disc's songs as Desk would have them, with no names: "Track 01" and so on, each its length from the table.
    static func discSongs(_ table: DiscTable, prefix: String) -> ([CrateTrack], [String: Int]) {
        var tracks: [CrateTrack] = [], numbers: [String: Int] = [:]
        for (i, s) in table.seconds.enumerated() {
            let n = table.first + i
            let id = prefix + String(format: "%02d", n)
            tracks.append(song(id, String(format: "Track %02d", n), seconds: s, file: String(format: "Track %02d.wav", n),
                               source: "filename"))
            numbers[id] = n
        }
        return (tracks, numbers)
    }

    /// A gate that never waits (the recorded answers need no pace).
    static let instant = MusicBrainzGate(interval: 0, sleep: { _ in })

    static func client(_ transport: LookupTransport, gate: MusicBrainzGate = instant) -> MusicBrainz {
        MusicBrainz(version: DeskLookup.appVersion, transport: transport, gate: gate)
    }
}

/// Records the answers above from MusicBrainz itself, once, at its pace: only when DECKIE_LOOKUP_LIVE_RECORD names a
/// folder (run by hand, never in CI). Writes each answer and an index the recorded transport reads.
@Suite struct LookupLiveRecording {
    final class Recorder: LookupTransport, @unchecked Sendable {
        let folder: URL
        let inner = LookupTransports.system
        var index: [String: RecordedTransport.Entry] = [:]
        var n = 0
        init(folder: URL) {
            self.folder = folder
            if let d = try? Data(contentsOf: folder.appendingPathComponent("index.json")),
               let i = try? JSONDecoder().decode([String: RecordedTransport.Entry].self, from: d) { index = i; n = i.count }
        }
        var available: Bool { true }
        func send(_ request: LookupRequest) throws -> LookupResponse {
            let r = try inner.send(request)
            // A busy answer is not kept: the gate asks again and the next answer is the one recorded.
            if r.status == 503 { return r }
            n += 1
            let name = String(format: "%02d.json", n)
            try r.body.write(to: folder.appendingPathComponent(name))
            index[request.url.absoluteString] = .init(file: name, status: r.status)
            let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try e.encode(index).write(to: folder.appendingPathComponent("index.json"))
            return r
        }
    }

    @Test func recordOnce() throws {
        guard let out = ProcessInfo.processInfo.environment["DECKIE_LOOKUP_LIVE_RECORD"], !out.isEmpty else { return }
        let folder = URL(fileURLWithPath: out, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let rec = Recorder(folder: folder)
        let gate = MusicBrainzGate(interval: 1.5)
        let log = NSLock()
        nonisolated(unsafe) var sent: [SentRequest] = []
        func run(_ plan: DeskLookup.Plan) -> DeskLookup.Review {
            DeskLookupRun(plan: plan, client: LookupSongs.client(rec, gate: gate), sent: { r in log.lock(); sent.append(r); log.unlock() }).run()
        }
        _ = run(DeskLookup.plan(LookupSongs.songs(LookupSongs.all)))
        for (table, name, prefix) in [(LookupSongs.exampleDisc, nil as String?, "x"), (LookupSongs.strangeDisc, nil, "s"),
                                      (LookupSongs.namedDisc, "Discovery", "n")] {
            let (tracks, numbers) = LookupSongs.discSongs(table, prefix: prefix)
            _ = run(DeskLookup.discPlan(source: "Disc", table: table, songs: LookupSongs.songs(tracks), numbers: numbers, name: name))
        }
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]; e.dateEncodingStrategy = .iso8601
        try e.encode(sent).write(to: folder.appendingPathComponent("sent.json"))
        print("recorded \(rec.index.count) answers; \(sent.count) requests made")
    }
}
