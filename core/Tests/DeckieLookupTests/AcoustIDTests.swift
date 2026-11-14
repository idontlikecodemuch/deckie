import Foundation
import Testing
@testable import DeckieLookup

/// A transport that answers forms from a list and keeps what it was sent.
final class FormTransport: LookupPostTransport, @unchecked Sendable {
    var answers: [LookupResponse]
    var posts: [LookupPost] = []
    var gets: [LookupRequest] = []
    init(_ answers: [LookupResponse]) { self.answers = answers }
    var available: Bool { true }
    func send(_ request: LookupRequest) throws -> LookupResponse { gets.append(request); throw LookupFailure.noConnection }
    func post(_ request: LookupPost) throws -> LookupResponse {
        posts.append(request)
        guard !answers.isEmpty else { throw LookupFailure.noConnection }
        return answers.removeFirst()
    }
}

/// A transport that only speaks GET, as a stand-in for one that cannot send a form.
struct GetOnly: LookupTransport {
    var available: Bool { true }
    func send(_ request: LookupRequest) throws -> LookupResponse { throw LookupFailure.noConnection }
}

@Suite struct AcoustIDTests {
    static let key = "test-key-not-real-0123"
    static let answer = Data("""
    {"status": "ok", "results": [
      {"id": "9ff43b6a-4f16-427c-93c2-92307ca505e0", "score": 0.62, "recordings": []},
      {"id": "4e0d8649-1f89-44f3-91af-4c0dbee81f28", "score": 0.987, "recordings": [
        {"id": "cd2e7c47-16f5-46c6-a37c-a1eb7bf599ff", "title": "Night Drive", "duration": 284,
         "artists": [{"id": "b7ffd2af-418f-4be2-bdd1-22f8b48613da", "name": "Example Band"}],
         "releasegroups": [{"id": "6a4d7a43-7a1d-3d4f-9a36-f6b7d9e1c3a1", "title": "Example Album", "type": "Album"}]},
        {"id": "0a1b2c3d-0000-4000-8000-000000000001", "title": "Duet",
         "artists": [{"name": "A", "joinphrase": " feat. "}, {"name": "B"}]}
      ]}
    ]}
    """.utf8)

    func client(_ t: LookupTransport, sent: @escaping @Sendable (SentRequest) -> Void = { _ in }) -> AcoustID {
        var c = AcoustID(key: Self.key, version: "1.0", transport: t, gate: MusicBrainzGate(interval: 0, sleep: { _ in }))
        c.sent = sent
        return c
    }

    @Test func asksByPostWithEverythingInTheBody() throws {
        let t = FormTransport([LookupResponse(status: 200, body: Self.answer)])
        let log = SentLog()
        let matches = try client(t, sent: { log.add($0) }).lookup(fingerprint: "AQAAT0mUaEkSZSqO", duration: 284)
        let post = try #require(t.posts.first)
        #expect(post.url.absoluteString == "https://api.acoustid.org/v2/lookup")
        #expect(post.url.query == nil)
        let body = String(decoding: post.body, as: UTF8.self)
        #expect(body == "client=\(Self.key)&duration=284&fingerprint=AQAAT0mUaEkSZSqO&meta=recordings+releasegroups+compress&format=json")
        #expect(post.headers["User-Agent"] == "DeckieDesk/1.0 ( https://deckie.io )")
        #expect(post.headers["Content-Type"] == "application/x-www-form-urlencoded")
        #expect(t.gets.isEmpty)
        // The key is never in what Desk lists as sent, nor in the recorded name, nor in the client's own words.
        let sent = log.items
        #expect(sent.count == 1 && sent[0].service == "acoustid" && sent[0].answer == "ok")
        #expect(!"\(sent)".contains(Self.key))
        #expect(!post.recordingKey.contains(Self.key))
        let c = client(t)
        #expect(!"\(c)".contains(Self.key) && !String(reflecting: c).contains(Self.key))
        var dumped = ""
        dump(c, to: &dumped)
        #expect(!dumped.contains(Self.key))
        // Best first; the artists joined as credited.
        #expect(matches.map(\.score) == [0.987, 0.62])
        let r = try #require(matches.first?.recordings.first)
        #expect(r.id == "cd2e7c47-16f5-46c6-a37c-a1eb7bf599ff" && r.title == "Night Drive" && r.artist == "Example Band")
        #expect(r.seconds == 284 && r.releaseGroups.first?.title == "Example Album")
        #expect(matches[0].recordings[1].artist == "A feat. B")
        #expect(matches[1].recordings.isEmpty)
    }

    @Test func noKeyMeansNothingIsSent() {
        let t = FormTransport([])
        guard case .failure(let f) = AcoustID.fromEnvironment(version: "1", environment: [:], transport: t) else {
            Issue.record("a client without a key"); return
        }
        #expect(f == .noKey)
        #expect(f.description.contains("DECKIE_ACOUSTID_KEY") && f.description.contains("nothing was sent"))
        if case .success = AcoustID.fromEnvironment(version: "1", environment: ["DECKIE_ACOUSTID_KEY": "  "], transport: t) {
            Issue.record("a blank key is no key")
        }
        #expect(t.posts.isEmpty)
        if case .success(let c) = AcoustID.fromEnvironment(version: "1", environment: ["DECKIE_ACOUSTID_KEY": Self.key], transport: t) {
            #expect(!"\(c)".contains(Self.key))
        } else { Issue.record("a key gives a client") }
    }

    @Test func busyIsWaitedOutThenGivenUp() throws {
        let busy = LookupResponse(status: 503, headers: ["Retry-After": "1"], body: Data())
        let t = FormTransport([busy, LookupResponse(status: 429, body: Data()), LookupResponse(status: 200, body: Self.answer)])
        #expect(try client(t).lookup(fingerprint: "AQAA", duration: 10).count == 2)
        #expect(t.posts.count == 3)
        let t2 = FormTransport([busy, busy, busy, busy])
        #expect(throws: LookupFailure.busy) { try client(t2).lookup(fingerprint: "AQAA", duration: 10) }
        #expect(t2.posts.count == 3)
    }

    @Test func theServicesOwnErrorsAreSaidPlainly() throws {
        let bad = Data(#"{"status": "error", "error": {"code": 4, "message": "invalid API key"}}"#.utf8)
        let t = FormTransport([LookupResponse(status: 400, body: bad)])
        #expect(throws: AcoustIDFailure.service(code: 4, message: "invalid API key")) {
            try client(t).lookup(fingerprint: "AQAA", duration: 10)
        }
        let t2 = FormTransport([LookupResponse(status: 200, body: Data("not json".utf8))])
        #expect(throws: LookupFailure.badAnswer) { try client(t2).lookup(fingerprint: "AQAA", duration: 10) }
        let t3 = FormTransport([LookupResponse(status: 200, body: Data(#"{"status": "ok", "results": []}"#.utf8))])
        #expect(try client(t3).lookup(fingerprint: "AQAA", duration: 10).isEmpty)
    }

    @Test func aTransportThatCannotSendAFormSaysSo() {
        #expect(throws: LookupFailure.notOnThisComputer) { try client(GetOnly()).lookup(fingerprint: "AQAA", duration: 10) }
        #expect(!client(GetOnly()).available)
        #expect(throws: LookupFailure.notOnThisComputer) {
            try client(LookupTransports.Unavailable()).lookup(fingerprint: "AQAA", duration: 10)
        }
    }

    @Test func recordedAnswersAreFoundByFingerprintNotKey() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-acoustid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let name = AcoustID.recordingKey(fingerprint: "AQAAT0mU", duration: 284)
        try Self.answer.write(to: dir.appendingPathComponent("a.json"))
        let index = try JSONEncoder().encode([name: RecordedTransport.Entry(file: "a.json", status: 200)])
        try index.write(to: dir.appendingPathComponent("index.json"))
        let recorded = RecordedTransport(folder: dir)
        #expect(try client(recorded).lookup(fingerprint: "AQAAT0mU", duration: 284).first?.score == 0.987)
        #expect(throws: LookupFailure.noConnection) { try client(recorded).lookup(fingerprint: "AQAAother", duration: 284) }
        #expect(!recorded.log.requests.map(\.url.absoluteString).joined().contains(Self.key))
    }
}

final class SentLog: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [SentRequest] = []
    func add(_ r: SentRequest) { lock.lock(); list.append(r); lock.unlock() }
    var items: [SentRequest] { lock.lock(); defer { lock.unlock() }; return list }
}
