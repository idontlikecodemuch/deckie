import Foundation
import Testing
@testable import DeckieLookup

/// The MusicBrainz disc id, from MusicBrainz's own worked examples ("Disc ID Calculation").
@Suite struct DiscTableTests {
    @Test func sha1MatchesTheStandardsVectors() {
        let hex = { (b: [UInt8]) in b.map { String(format: "%02x", $0) }.joined() }
        #expect(hex(SHA1.hash(Array("abc".utf8))) == "a9993e364706816aba3e25717850c26c9cd0d89d")
        #expect(hex(SHA1.hash([])) == "da39a3ee5e6b4b0d3255bfef95601890afd80709")
        #expect(hex(SHA1.hash(Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)))
                == "84983e441c3bd26ebaae4aa1f95129e5e54670f1")
    }

    @Test func theSingleSessionExampleGivesItsId() {
        // "First track: 1, Last track: 6", LBAs 0, 15213, 32164, 46442, 63264, 80339, lead-out 95312.
        let t = DiscTable(tracks: [(1, 0), (2, 15213), (3, 32164), (4, 46442), (5, 63264), (6, 80339)], audioEnd: 95312)
        #expect(t.offsets == [150, 15363, 32314, 46592, 63414, 80489])
        #expect(t.leadOut == 95462)
        #expect(t.musicBrainzId == "49HHV7Eb8UKF3aQiNmu1GR8vKTY-")
        #expect(t.musicBrainzId.count == 28)
        #expect(t.tocParameter == "1+6+95462+150+15363+32314+46592+63414+80489")
    }

    @Test func anEnhancedCDCountsOnlyItsAudio() {
        // The multi-session example: track 8 is data at 125824; the audio ends 11,400 sectors before it.
        let tracks = [(1, 0), (2, 13959), (3, 33436), (4, 52927), (5, 65631), (6, 77742), (7, 99024)]
        let t = DiscTable(tracks: tracks, audioEnd: 125824 - 11400)
        #expect(t.leadOut == 114574)
        #expect(t.last == 7)
        #expect(t.musicBrainzId == "BPnh1KU.hea1C.KMYWLGZkHJr0w-")
    }

    @Test func lengthsComeFromTheTable() {
        let t = DiscTable(tracks: [(1, 0), (2, 750)], audioEnd: 1500)
        #expect(t.seconds == [10, 10])
    }
}

/// How requests are made: the address, the words, the header, the pace, and what happens when the service is busy
/// or cannot be reached. A scripted transport stands in for the service.
@Suite struct MusicBrainzRequestTests {
    final class Scripted: LookupTransport, @unchecked Sendable {
        var answers: [LookupResponse]
        var asked: [LookupRequest] = []
        var fail: LookupFailure?
        init(_ answers: [LookupResponse], fail: LookupFailure? = nil) { self.answers = answers; self.fail = fail }
        var available: Bool { true }
        func send(_ request: LookupRequest) throws -> LookupResponse {
            asked.append(request)
            if let fail { throw fail }
            return answers.isEmpty ? LookupResponse(status: 500, body: Data()) : answers.removeFirst()
        }
    }

    final class Clock: @unchecked Sendable {
        var t = Date(timeIntervalSince1970: 1_000_000)
        var slept: [Double] = []
    }

    func gate(_ c: Clock) -> MusicBrainzGate {
        MusicBrainzGate(interval: 1, sleep: { c.slept.append($0); c.t = c.t.addingTimeInterval($0) }, now: { c.t })
    }

    let ok = LookupResponse(status: 200, body: Data(#"{"count":0,"recordings":[]}"#.utf8))

    @Test func everyRequestNamesTheAppItsVersionAndThePublicSiteAndNothingElse() throws {
        let s = Scripted([ok])
        let mb = MusicBrainz(version: "0.1", transport: s, gate: gate(Clock()))
        _ = try mb.searchRecordings(RecordingQuery(title: "Blue Monday", artist: "New Order"))
        let r = try #require(s.asked.first)
        #expect(r.headers == ["User-Agent": "DeckieDesk/0.1 ( https://deckie.io )", "Accept": "application/json"])
        #expect(r.url.absoluteString == "https://musicbrainz.org/ws/2/recording?query=%2Brecording%3A%22Blue%20Monday%22%20%2Bartist%3A%22New%20Order%22&limit=50&fmt=json")
        #expect(r.url.host == "musicbrainz.org" && r.url.scheme == "https")
    }

    @Test func theWordsAreEscapedForTheSearchLanguage() {
        #expect(MusicBrainz.lucene(RecordingQuery(title: "Say \"Hi\" (Extended Mix)", artist: "AC/DC", release: "Live: 1979"))
                == #"+recording:"Say \"Hi\"" recording:"Say \"Hi\" (Extended Mix)" +artist:"AC/DC" release:"Live: 1979""#)
        #expect(MusicBrainz.lucene(RecordingQuery(words: "da funk (live) - 1997")) == #"recording:(da funk \(live\) \- 1997) artist:(da funk \(live\) \- 1997)"#)
        #expect(MusicBrainz.lucene(RecordingQuery()) == nil)
        #expect(MusicBrainz.bareTitle("Night drive (extended mix)") == "Night drive")
        #expect(MusicBrainz.bareTitle("(Untitled)") == "(Untitled)")
    }

    @Test func theDiscRequestCarriesTheIdAndTheTableAsDocumented() throws {
        let s = Scripted([LookupResponse(status: 404, body: Data(#"{"error":"Not Found"}"#.utf8))])
        let mb = MusicBrainz(version: "0.1", transport: s, gate: gate(Clock()))
        let t = DiscTable(tracks: [(1, 0), (2, 15213), (3, 32164), (4, 46442), (5, 63264), (6, 80339)], audioEnd: 95312)
        let a = try mb.disc(t)
        #expect(a.releases == nil)
        #expect(s.asked.first?.url.absoluteString == "https://musicbrainz.org/ws/2/discid/49HHV7Eb8UKF3aQiNmu1GR8vKTY-?toc=1+6+95462+150+15363+32314+46592+63414+80489&cdstubs=no&inc=artist-credits+recordings+labels&fmt=json")
    }

    @Test func requestsKeepToOneASecond() throws {
        let c = Clock()
        let s = Scripted([ok, ok, ok])
        let mb = MusicBrainz(version: "0.1", transport: s, gate: gate(c))
        for _ in 0..<3 { _ = try mb.searchRecordings(RecordingQuery(title: "x")) }
        #expect(s.asked.count == 3)
        #expect(abs(c.slept.reduce(0, +) - 2) < 1e-3, "\(c.slept)")   // three requests: two waits of a second
    }

    @Test func aBusyAnswerIsWaitedOutAndAskedAgainAtMostTwice() throws {
        let busy = LookupResponse(status: 503, headers: ["Retry-After": "0"], body: Data(#"{"error":"busy"}"#.utf8))
        let c = Clock()
        nonisolated(unsafe) var sent: [SentRequest] = []
        var mb = MusicBrainz(version: "0.1", transport: Scripted([busy, ok]), gate: gate(c))
        mb.sent = { sent.append($0) }
        _ = try mb.searchRecordings(RecordingQuery(title: "x"))
        #expect(sent.map(\.answer) == ["busy", "ok"])
        #expect(c.slept.reduce(0, +) >= 2)                                  // the back-off, through the gate
        let s3 = Scripted([busy, busy, busy, ok])
        let mb3 = MusicBrainz(version: "0.1", transport: s3, gate: gate(Clock()))
        #expect(throws: LookupFailure.busy) { _ = try mb3.searchRecordings(RecordingQuery(title: "x")) }
        #expect(s3.asked.count == 3)
    }

    @Test func noConnectionAndOtherAnswersAreSaidPlainly() {
        let mb = MusicBrainz(version: "0.1", transport: Scripted([], fail: .noConnection), gate: gate(Clock()))
        #expect(throws: LookupFailure.noConnection) { _ = try mb.searchRecordings(RecordingQuery(title: "x")) }
        let bad = MusicBrainz(version: "0.1", transport: Scripted([LookupResponse(status: 400, body: Data())]), gate: gate(Clock()))
        #expect(throws: LookupFailure.refused(400)) { _ = try bad.searchRecordings(RecordingQuery(title: "x")) }
        let junk = MusicBrainz(version: "0.1", transport: Scripted([LookupResponse(status: 200, body: Data("<html>".utf8))]), gate: gate(Clock()))
        #expect(throws: LookupFailure.badAnswer) { _ = try junk.searchRecordings(RecordingQuery(title: "x")) }
        #if !canImport(Darwin)
        // Linux and Windows: no way out is built (curl is not on the allowlist), and it says so.
        #expect(!LookupTransports.system.available)
        #expect(throws: LookupFailure.notOnThisComputer) {
            _ = try MusicBrainz(version: "0.1", gate: gate(Clock())).searchRecordings(RecordingQuery(title: "x"))
        }
        #endif
    }

    @Test func aStopEndsTheWait() {
        let c = Clock()
        var mb = MusicBrainz(version: "0.1", transport: Scripted([ok, ok]), gate: gate(c))
        _ = try? mb.searchRecordings(RecordingQuery(title: "x"))
        mb.stopped = { true }
        #expect(throws: LookupFailure.stopped) { _ = try mb.searchRecordings(RecordingQuery(title: "x")) }
    }

    @Test func recordedAnswersNeverReachTheNetwork() throws {
        let t = RecordedTransport(folder: fixtures)
        #expect(t.index.count >= 10)
        let unknown = LookupRequest(url: URL(string: "https://musicbrainz.org/ws/2/recording?query=x&fmt=json")!, headers: [:])
        #expect(throws: LookupFailure.noConnection) { _ = try t.send(unknown) }
    }

    let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/musicbrainz")

    @Test func theRecordedAnswersRead() throws {
        let mb = MusicBrainz(version: "0.1", transport: RecordedTransport(folder: fixtures), gate: MusicBrainzGate(interval: 0, sleep: { _ in }))
        let recs = try mb.searchRecordings(RecordingQuery(title: "Around the World", artist: "Daft Punk"))
        #expect(recs.count >= 25)
        let album = try #require(recs.first { $0.length == 429506 })
        #expect(album.artistCredit?.line == "Daft Punk")
        #expect(album.isrcs?.contains("GBDUW0600009") == true)
        #expect((album.releases ?? []).count > 10)
        let byIsrc = try mb.searchRecordings(isrc: "gb-duw-06-00009")
        #expect(byIsrc.first?.length == 429506)
        let disc = try mb.disc(DiscTable(tracks: [(1, 0), (2, 15213), (3, 32164), (4, 46442), (5, 63264), (6, 80339)], audioEnd: 95312))
        #expect(disc.exact)
        let rel = try #require(disc.releases?.first)
        #expect(rel.title == "Ettella Diamant" && rel.labels == ["Deadred Records"])
        #expect(rel.media?.first?.songs.count == 6 && rel.media?.first?.discs?.first?.id == "49HHV7Eb8UKF3aQiNmu1GR8vKTY-")
        #expect(try mb.searchRecordings(RecordingQuery(title: "Qzxv Plorbeth Wunk", artist: "Nobody Zzyx")).isEmpty)
    }
}

/// The lookup is the only code that uses the network (D36): no other source file in Deckie names a networking API.
@Suite struct NetworkIsolationTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    func files(_ folder: String, endings: Set<String>, skip: [String] = []) -> [URL] {
        let root = Self.repo.appendingPathComponent(folder)
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [] }
        return e.compactMap { $0 as? URL }.filter { u in
            endings.contains(u.pathExtension) && !skip.contains { u.path.contains($0) }
        }
    }

    @Test func noOtherSourceNamesANetworkingAPI() throws {
        let swiftAndC = ["URLSession", "FoundationNetworking", "URLRequest", "NSURLConnection", "CFNetwork", "CFStream",
                         "curl_", "WinHttp", "WinINet", "InternetOpen", "getaddrinfo", "gethostbyname", "Network.framework",
                         "import Network", "NWConnection", "SCNetworkReachability", "socket(", "contentsOf: URL(string"]
        let sources = files("core/Sources", endings: ["swift", "c", "h", "cc"],
                            skip: ["/DeckieLookup/", "/COnnxRuntime/include/", "/CDrMp3/", "/CDrFlac/"])
            + files("desk-app/Desk/Sources", endings: ["swift"])
            + files("desk-shell/Sources", endings: ["swift", "c", "h", "cc"], skip: ["/vendor/"])
        #expect(sources.count > 50)
        var found: [String] = []
        for u in sources {
            let text = try String(contentsOf: u, encoding: .utf8)
            for p in swiftAndC where text.contains(p) { found.append("\(u.lastPathComponent): \(p)") }
        }
        #expect(found.isEmpty, "\(found)")
        // The pages never touch the network: no request APIs, and their content rules allow no connection.
        var pageHits: [String] = []
        for u in files("desk-web", endings: ["js", "html"]) {
            // SVG's namespace is a name, not an address anything is fetched from.
            let text = try String(contentsOf: u, encoding: .utf8).replacingOccurrences(of: "http://www.w3.org/2000/svg", with: "")
            for p in ["fetch(", "XMLHttpRequest", "WebSocket", "EventSource", "sendBeacon", "http://", "https://"] where text.contains(p) {
                pageHits.append("\(u.lastPathComponent): \(p)")
            }
            if u.pathExtension == "html" { #expect(text.contains("connect-src 'none'")) }
        }
        #expect(pageHits.isEmpty, "\(pageHits)")
        // And inside the lookup, the one way out is the system transport.
        let lookup = files("core/Sources/DeckieLookup", endings: ["swift"])
        let users = try lookup.filter { try String(contentsOf: $0, encoding: .utf8).contains("URLSession(") }
        #expect(users.map(\.lastPathComponent) == ["LookupTransport.swift"])
    }
}
