import Foundation

// DeckieLookup: the only code in Deckie that uses the network (D36). It speaks MusicBrainz's public web service and
// nothing else, and only when the DJ asks (the note on D30). Nothing else in the package depends on it but
// DeckieDesk, and a test (`NetworkIsolationTests`) fails if any other source file names a networking API.
//
// The one way out to the network is `LookupTransports.system`, used by `MusicBrainz` and by nothing else:
//
// - **On the Mac** it is Foundation's URL loading (`URLSession`, part of the system), with an ephemeral session: no
//   cookies, no cache on disk, no stored credentials.
// - **On Linux and Windows** it is not built. Swift's Foundation keeps URL loading in a separate library,
//   FoundationNetworking, which is a layer over libcurl: on Linux it links the system's `libcurl.so.4` (and through
//   it the TLS library and the rest curl was built with), on Windows the toolchain's `FoundationNetworking.dll`
//   carries its own build of curl. curl's licence is not on the dependency allowlist (DEPENDENCIES.md; the note on
//   D3 of Oct 28 left it off on purpose), so this module does not import FoundationNetworking and the lookup there
//   says, in plain words, that it is not on this computer yet. The owner decides the way (the report of Nov 14).
//
// Tests and the window tours never use the network: `RecordedTransport` answers from files recorded once.

/// One request as it goes out: the address and the headers. Nothing else is ever sent: no body, no cookies.
public struct LookupRequest: Sendable, Equatable {
    public let url: URL
    public let headers: [String: String]
    public init(url: URL, headers: [String: String]) { self.url = url; self.headers = headers }
}

/// The service's answer: its status, its headers (names in lower case) and its body.
public struct LookupResponse: Sendable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
    public init(status: Int, headers: [String: String] = [:], body: Data) {
        self.status = status; self.body = body
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
    }
}

/// Why a lookup did not get an answer, as codes the windows have words for (`lookupFailure.<code>`).
public enum LookupFailure: Error, Equatable, Sendable, CustomStringConvertible {
    /// No connection to the internet, or the service could not be reached.
    case noConnection
    /// The service said it is busy or that we asked too often (HTTP 503), even after waiting and asking again.
    case busy
    /// The service refused the request (another HTTP status).
    case refused(Int)
    /// The answer was not what the service documents.
    case badAnswer
    /// This computer has no way to look up yet (Linux and Windows, see above).
    case notOnThisComputer
    /// The DJ stopped it.
    case stopped

    public var code: String {
        switch self {
        case .noConnection: return "noConnection"
        case .busy: return "busy"
        case .refused: return "refused"
        case .badAnswer: return "badAnswer"
        case .notOnThisComputer: return "notOnThisComputer"
        case .stopped: return "stopped"
        }
    }
    public var description: String {
        if case let .refused(s) = self { return "refused (HTTP \(s))" }
        return code
    }
}

/// How a request leaves the computer. `MusicBrainz` is given one; only `LookupTransports` makes the real one.
public protocol LookupTransport: Sendable {
    /// Sends one request and waits for its answer. Throws `LookupFailure.noConnection` when there is none.
    func send(_ request: LookupRequest) throws -> LookupResponse
    /// Whether this transport can reach the service at all on this computer.
    var available: Bool { get }
}

public enum LookupTransports {
    /// The system's own way out (the Mac's URL loading), or, on Linux and Windows, one that says it is not built.
    public static var system: LookupTransport {
        #if canImport(Darwin)
        return SystemTransport.shared
        #else
        return Unavailable()
        #endif
    }

    /// `DECKIE_LOOKUP_RECORDED=<folder>` answers from recorded files instead (tests and the window tours); otherwise
    /// the system's.
    public static func forEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> LookupTransport {
        if let folder = environment[RecordedTransport.environmentVariable], !folder.isEmpty {
            return RecordedTransport(folder: URL(fileURLWithPath: folder, isDirectory: true))
        }
        return system
    }

    struct Unavailable: LookupTransport {
        var available: Bool { false }
        func send(_ request: LookupRequest) throws -> LookupResponse { throw LookupFailure.notOnThisComputer }
    }
}

#if canImport(Darwin)
/// Foundation's URL loading on the Mac: an ephemeral session (no cookies, no cache on disk, no credentials kept), a
/// 20-second wait for an answer, the headers given and no others of ours.
final class SystemTransport: LookupTransport, @unchecked Sendable {
    static let shared = SystemTransport()
    let session: URLSession

    init() {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieAcceptPolicy = .never
        c.httpShouldSetCookies = false
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.urlCredentialStorage = nil
        c.timeoutIntervalForRequest = 20
        c.timeoutIntervalForResource = 40
        c.waitsForConnectivity = false
        session = URLSession(configuration: c)
    }

    var available: Bool { true }

    final class Box: @unchecked Sendable { var result: Result<LookupResponse, Error> = .failure(LookupFailure.noConnection) }

    func send(_ request: LookupRequest) throws -> LookupResponse {
        var r = URLRequest(url: request.url)
        r.httpMethod = "GET"
        r.httpShouldHandleCookies = false
        for (k, v) in request.headers { r.setValue(v, forHTTPHeaderField: k) }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: r) { data, response, error in
            if let http = response as? HTTPURLResponse {
                var headers: [String: String] = [:]
                for (k, v) in http.allHeaderFields { headers["\(k)"] = "\(v)" }
                box.result = .success(LookupResponse(status: http.statusCode, headers: headers, body: data ?? Data()))
            } else {
                box.result = .failure(error.map { _ in LookupFailure.noConnection } ?? LookupFailure.noConnection)
            }
            done.signal()
        }
        task.resume()
        done.wait()
        return try box.result.get()
    }
}
#endif

/// Answers recorded once from the real service, kept as files: `index.json` maps each request's address to the file
/// holding its body and the status it came with. A request not in the index gets "no connection", so a test never
/// reaches the network by accident. Used by the tests and the window tours (`DECKIE_LOOKUP_RECORDED`).
public struct RecordedTransport: LookupTransport {
    public static let environmentVariable = "DECKIE_LOOKUP_RECORDED"
    public struct Entry: Codable, Sendable {
        public var file: String
        public var status: Int
        public init(file: String, status: Int) { self.file = file; self.status = status }
    }
    public let folder: URL
    public let index: [String: Entry]
    /// Every request this transport was asked for, in order (tests read it).
    public let log = Log()

    public final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [LookupRequest] = []
        func add(_ r: LookupRequest) { lock.lock(); items.append(r); lock.unlock() }
        public var requests: [LookupRequest] { lock.lock(); defer { lock.unlock() }; return items }
    }

    public init(folder: URL) {
        self.folder = folder
        let data = (try? Data(contentsOf: folder.appendingPathComponent("index.json"))) ?? Data("{}".utf8)
        index = (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    public var available: Bool { true }

    public func send(_ request: LookupRequest) throws -> LookupResponse {
        log.add(request)
        guard let e = index[request.url.absoluteString],
              let body = try? Data(contentsOf: folder.appendingPathComponent(e.file)) else { throw LookupFailure.noConnection }
        return LookupResponse(status: e.status, body: body)
    }
}
