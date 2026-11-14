import Foundation
import Testing
@testable import DeckieLookup

#if !canImport(Darwin)
/// The way out on Windows (WinHTTP) and Linux (libsoup 3), against a small server on this computer
/// (Tools/lookup_test_server.py). Nothing here reaches MusicBrainz or any other computer, except one question to
/// the name service about a name that by rule never exists.
///
/// The tests need Python to run the server and, on Linux, libsoup 3. Where either is missing they say so and pass,
/// unless DECKIE_REQUIRE_LOOKUP_NET is set, as every workflow sets it: there a missing piece is a failure.
@Suite(.serialized) struct PortableTransportTests {
    final class Server: @unchecked Sendable {
        let process = Process()
        let input = Pipe(), output = Pipe()
        var port = 0, tls = 0

        init?() {
            let tool = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent().appendingPathComponent("Tools/lookup_test_server.py")
            let names = ["python3", "python", "python3.exe", "python.exe"]
            let folders = (ProcessInfo.processInfo.environment["PATH"] ?? ProcessInfo.processInfo.environment["Path"] ?? "")
                .split(separator: Character(Self.pathSeparator)).map(String.init)
            guard let python = folders.lazy.flatMap({ f in names.map { URL(fileURLWithPath: f).appendingPathComponent($0) } })
                .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else { return nil }
            process.executableURL = python
            process.arguments = [tool.path]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return nil }
            var text = ""
            let end = Date().addingTimeInterval(60)
            while Date() < end, text.split(separator: "\n").count < 2 {
                let d = output.fileHandleForReading.availableData
                if d.isEmpty { break }
                text += String(decoding: d, as: UTF8.self)
            }
            for line in text.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: " ")
                if parts.count == 2, parts[0] == "PORT" { port = Int(parts[1]) ?? 0 }
                if parts.count == 2, parts[0] == "TLS" { tls = Int(parts[1]) ?? 0 }
            }
            if port == 0 { process.terminate(); return nil }
        }

        static var pathSeparator: String {
            #if os(Windows)
            return ";"
            #else
            return ":"
            #endif
        }

        func stop() { try? input.fileHandleForWriting.close(); process.terminate() }
        func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }
    }

    static let required = ProcessInfo.processInfo.environment["DECKIE_REQUIRE_LOOKUP_NET"] != nil
    static let server = Server()
    let transport = PortableTransport(timeout: 3)
    let headers = ["User-Agent": "DeckieDesk/0.1 ( https://deckie.io )", "Accept": "application/json"]

    /// The server, or nil with the reason said (a failure where the workflow requires these tests).
    func ready() -> Server? {
        guard PortableTransport.shared.available else {
            if Self.required { Issue.record("this computer's networking library could not be opened") }
            else { print("PortableTransportTests: not run, this computer's networking library could not be opened") }
            return nil
        }
        guard let s = Self.server else {
            if Self.required { Issue.record("the test server did not start (is Python here?)") }
            else { print("PortableTransportTests: not run, the test server did not start (is Python here?)") }
            return nil
        }
        return s
    }

    func get(_ s: Server, _ path: String) throws -> LookupResponse {
        try transport.send(LookupRequest(url: s.url(path), headers: headers))
    }

    @Test func anAnswerComesBackWithItsStatusHeadersAndBody() throws {
        guard let s = ready() else { return }
        let r = try get(s, "/json")
        #expect(r.status == 200)
        #expect(String(decoding: r.body, as: UTF8.self) == #"{"ok":true,"name":"Café"}"#)
        #expect(r.headers["x-deckie-test"] == "yes" && r.headers["content-type"] == "application/json")
        let big = try get(s, "/big")
        #expect(big.body.count == 1024 * 1024 && big.body.allSatisfy { $0 == UInt8(ascii: "a") })
    }

    @Test func theHeadersGivenGoOutAndNoCookieEverDoes() throws {
        guard let s = ready() else { return }
        func seen(_ path: String) throws -> (path: String, headers: [String: String]) {
            let r = try get(s, path)
            let o = try #require(try JSONSerialization.jsonObject(with: r.body) as? [String: Any])
            return (o["path"] as? String ?? "", o["headers"] as? [String: String] ?? [:])
        }
        let first = try seen("/echo?query=%2Brecording%3A%22Blue%20Monday%22&fmt=json")
        // The address arrives as written, percent signs and all.
        #expect(first.path == "/echo?query=%2Brecording%3A%22Blue%20Monday%22&fmt=json")
        #expect(first.headers["user-agent"] == "DeckieDesk/0.1 ( https://deckie.io )")
        #expect(first.headers["accept"] == "application/json")
        #expect(first.headers["cookie"] == nil && first.headers["authorization"] == nil && first.headers["referer"] == nil)
        // Nothing of ours beyond those two: what else is there is the library's own plumbing.
        let plumbing: Set<String> = ["host", "connection", "accept-encoding", "user-agent", "accept"]
        #expect(Set(first.headers.keys).subtracting(plumbing).isEmpty, "\(first.headers)")
        // The server hands out a cookie; the next request does not carry it.
        #expect(try get(s, "/cookie").status == 200)
        #expect(try seen("/echo").headers["cookie"] == nil)
    }

    @Test func anyStatusIsAnAnswerAndARedirectIsFollowed() throws {
        guard let s = ready() else { return }
        #expect(try get(s, "/status/404").status == 404)
        let busy = try get(s, "/status/503")
        #expect(busy.status == 503 && busy.headers["retry-after"] == "1")
        #expect(try get(s, "/redirect").status == 200)
    }

    @Test func noAnswerIsNoConnectionInEveryWayItCanHappen() throws {
        guard let s = ready() else { return }
        // Nothing listens there (a port just closed).
        let closed = URL(string: "http://127.0.0.1:1/json")!
        #expect(throws: LookupFailure.noConnection) { _ = try transport.send(LookupRequest(url: closed, headers: headers)) }
        // A name that never exists (".invalid" is reserved for that).
        let nowhere = URL(string: "https://deckie-lookup-test.invalid/ws/2/recording")!
        do {
            // Behind a proxy (the computer's own settings are followed) it is the proxy that answers, with a refusal.
            let r = try transport.send(LookupRequest(url: nowhere, headers: headers))
            #expect(r.status >= 400, "a name that does not exist gave status \(r.status)")
        } catch { #expect(error as? LookupFailure == .noConnection) }
        // The time limit: the server waits 8 seconds, the transport 3.
        let started = Date()
        #expect(throws: LookupFailure.noConnection) { _ = try get(s, "/slow") }
        #expect(Date().timeIntervalSince(started) < 7.5)
        // HTTPS with a certificate no system trusts is refused, not read.
        if s.tls != 0 {
            let untrusted = URL(string: "https://127.0.0.1:\(s.tls)/json")!
            #expect(throws: LookupFailure.noConnection) { _ = try transport.send(LookupRequest(url: untrusted, headers: headers)) }
            let named = URL(string: "https://localhost:\(s.tls)/json")!
            #expect(throws: LookupFailure.noConnection) { _ = try transport.send(LookupRequest(url: named, headers: headers)) }
            print("PortableTransportTests: HTTPS with an untrusted certificate was refused, as it should be")
        } else {
            print("PortableTransportTests: no certificate could be made (no openssl program here), so the HTTPS check did not run")
        }
        // Not an address the lookup uses.
        #expect(throws: LookupFailure.badAnswer) {
            _ = try transport.send(LookupRequest(url: URL(string: "ftp://127.0.0.1/x")!, headers: headers))
        }
    }

    @Test func theSwitchTurnsTheWayOutOff() {
        let off = LookupTransports.forEnvironment([LookupTransports.offVariable: "1"])
        #expect(!off.available)
        #expect(throws: LookupFailure.notOnThisComputer) {
            _ = try off.send(LookupRequest(url: URL(string: "https://musicbrainz.org/")!, headers: [:]))
        }
        // Without it, the system's way out is there wherever its library is.
        #expect(LookupTransports.forEnvironment([:]).available == PortableTransport.shared.available)
    }

    @Test func theServerIsStoppedAtTheEnd() {
        // Runs last in this serialized suite (tests run in the order written).
        Self.server?.stop()
    }
}
#endif
