import Foundation

// MusicBrainz's rules, as their documentation stated them when this was written (read Nov 14, 2026):
//
// From "MusicBrainz API / Rate Limiting" (musicbrainz.org/doc/MusicBrainz_API/Rate_Limiting):
//   - "Each request sent to MusicBrainz needs to include a User-Agent header, with enough information in the
//     User-Agent for us (MusicBrainz) to contact the application maintainers."
//   - "We strongly suggest including your application's version number in the User-Agent string too."
//   - The suggested form: "Application name/<version> ( contact-url )".
//   - Source IP address: "Currently that rate is (on average) 1 request per second." "If that rate is too high, all
//     your requests will be declined (http 503) until the rate drops again."
//   - "We may change the blocking/throttling rules at any time in order to protect the overall site health."
// From "MusicBrainz API" (musicbrainz.org/doc/MusicBrainz_API):
//   - "The API root URL is https://musicbrainz.org/ws/2/."; JSON by adding "fmt=json" to the query string.
//   - "Non-commercial use of this web service is free"; commercial use goes through their supporter plans.
//
// What this code does about them:
//   - One gate for the whole program (`MusicBrainzGate.shared`): every request waits its turn, and two requests never
//     start less than `MusicBrainzRules.interval` (one second) apart, from any thread.
//   - Every request carries `MusicBrainzRules.userAgent(version:)`: "DeckieDesk/<version> ( https://deckie.io )", the
//     application, its version and the public site as the contact; no person's name or address.
//   - A 503 is waited out (its Retry-After when it gives one, else 2 then 4 seconds) and asked again at most twice;
//     then the lookup says MusicBrainz is busy. The waits go through the same gate.
//   - Nothing is sent but what the request needs: the words, the ISRC, the disc's id and table, or an id from an
//     answer. No file paths, no machine name, no list of other songs; no cookies, no body.

public enum MusicBrainzRules {
    public static let root = "https://musicbrainz.org/ws/2/"
    /// The least time between the starts of two requests, in seconds: their "1 request per second".
    public static let interval = 1.0
    /// How many times a 503 is asked again before the lookup gives up.
    public static let retries = 2
    /// The waits before asking again when the 503 gives no Retry-After.
    public static let backoff = [2.0, 4.0]
    /// The application's name and the contact in the User-Agent (the public site; never a person).
    public static let application = "DeckieDesk"
    public static let contact = "https://deckie.io"
    public static func userAgent(version: String) -> String { "\(application)/\(version) ( \(contact) )" }
}

/// The one queue every MusicBrainz request goes through: each takes the next free slot, one second after the last.
public final class MusicBrainzGate: @unchecked Sendable {
    public static let shared = MusicBrainzGate()
    private let lock = NSLock()
    private var next = Date.distantPast
    public let interval: Double
    /// How the gate waits (tests make it instant and record the waits).
    let sleep: @Sendable (Double) -> Void
    let now: @Sendable () -> Date

    public init(interval: Double = MusicBrainzRules.interval,
                sleep: @escaping @Sendable (Double) -> Void = { Thread.sleep(forTimeInterval: $0) },
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.interval = interval; self.sleep = sleep; self.now = now
    }

    /// Waits for this request's turn; `stopped` is asked while waiting, and a stop ends the wait with
    /// `LookupFailure.stopped`. `extra` holds the slot back further (a 503's wait).
    public func wait(extra: Double = 0, stopped: () -> Bool = { false }) throws {
        lock.lock()
        let t = now()
        let slot = max(t.addingTimeInterval(extra), next)
        next = slot.addingTimeInterval(interval)
        lock.unlock()
        var left = slot.timeIntervalSince(t)
        while left > 0 {
            if stopped() { throw LookupFailure.stopped }
            let step = min(left, 0.1)
            sleep(step)
            left -= step
        }
        if stopped() { throw LookupFailure.stopped }
    }
}

/// One request Desk made, as "What Desk has sent" lists it: when, to which service, what kind, the words or the id it
/// carried (each a name and the value), the whole address, and what came back (`ok`, `nothing`, or a failure code).
public struct SentRequest: Codable, Equatable, Sendable {
    public var at: Date
    public var service: String
    /// `recordingSearch`, `isrcSearch`, `disc`, `releaseSearch`, `release` (words `sentKind.<kind>`).
    public var kind: String
    /// What it carried, in order: `[["title", "Blue Monday"], ["artist", "New Order"]]` (words `sentField.<name>`).
    public var fields: [[String]]
    public var address: String
    public var answer: String
    public init(at: Date, service: String, kind: String, fields: [[String]], address: String, answer: String) {
        self.at = at; self.service = service; self.kind = kind; self.fields = fields; self.address = address; self.answer = answer
    }
}

/// What a recording search asks: the song's title (with its version, as written, when it has one), its artist, a
/// release it is on; or, for a song with no title, the words of its file name. ISRC searches are `isrc`.
public struct RecordingQuery: Sendable, Equatable, Codable {
    public var title: String?
    public var artist: String?
    public var release: String?
    /// Free words (a file name's), used when there is no title.
    public var words: String?
    public init(title: String? = nil, artist: String? = nil, release: String? = nil, words: String? = nil) {
        self.title = title; self.artist = artist; self.release = release; self.words = words
    }

    /// The fields as the sent list shows them.
    public var fields: [[String]] {
        var f: [[String]] = []
        if let title { f.append(["title", title]) }
        if let artist { f.append(["artist", artist]) }
        if let release { f.append(["release", release]) }
        if let words { f.append(["words", words]) }
        return f
    }
}

/// MusicBrainz's public web service, by its documented requests. Each call waits its turn at the gate, sends one
/// request (again after a 503, at most twice), reports it to `sent`, and returns the answer read from JSON.
public struct MusicBrainz: Sendable {
    public static let service = "musicbrainz"
    public let userAgent: String
    let transport: LookupTransport
    let gate: MusicBrainzGate
    /// Asked between and during waits: true ends the call with `LookupFailure.stopped`.
    public var stopped: @Sendable () -> Bool = { false }
    /// Told of every request made, as it is made (the sent list).
    public var sent: @Sendable (SentRequest) -> Void = { _ in }
    /// How many recordings a search asks for: a song's versions are many (live, DJ mixes, compilations' copies), and
    /// the one that fits by length is often not in the first ten.
    public static let searchLimit = 50

    public init(version: String, transport: LookupTransport = LookupTransports.system, gate: MusicBrainzGate = .shared) {
        self.userAgent = MusicBrainzRules.userAgent(version: version)
        self.transport = transport
        self.gate = gate
    }

    public var available: Bool { transport.available }

    // MARK: the requests

    /// A recording search by words: `+recording:"<title>" +artist:"<artist>"`, with the title without its version
    /// required and the title as written, and the release, as optional clauses that only raise a match's score; or a
    /// file name's words, each matched against the recording's title or its artist.
    public func searchRecordings(_ q: RecordingQuery) throws -> [MBRecording] {
        guard let lucene = Self.lucene(q) else { return [] }
        let r: MBRecordingList = try get("recording", [("query", lucene), ("limit", "\(Self.searchLimit)")],
                                         kind: "recordingSearch", fields: q.fields)
        return r.recordings ?? []
    }

    /// The recordings with this ISRC, through the search (`isrc:<code>`), which, unlike `/isrc/`, gives each
    /// recording's releases in the same answer.
    public func searchRecordings(isrc: String) throws -> [MBRecording] {
        let code = isrc.uppercased().filter { $0.isLetter || $0.isNumber }
        guard code.count == 12 else { return [] }
        let r: MBRecordingList = try get("recording", [("query", "isrc:" + code), ("limit", "\(Self.searchLimit)")],
                                         kind: "isrcSearch", fields: [["isrc", code]])
        return r.recordings ?? []
    }

    /// A music CD by its disc id, with its table of contents so that MusicBrainz does its fuzzy search ("a fuzzy
    /// lookup will be done to find matching MusicBrainz releases") when it does not know the id; with each release's
    /// songs, artists and labels. CD stubs (tracklists anyone typed in, not checked) are left out.
    public func disc(_ table: DiscTable) throws -> MBDiscAnswer {
        try get("discid/" + table.musicBrainzId,
                [("toc", table.tocParameter), ("cdstubs", "no"), ("inc", "artist-credits+recordings+labels")],
                kind: "disc", fields: [["discId", table.musicBrainzId], ["toc", table.tocParameter]],
                notFound: MBDiscAnswer())
    }

    /// A release search for a disc whose songs have no names: its name and how many songs it has.
    public func searchReleases(name: String, tracks: Int) throws -> [MBRelease] {
        let q = "release:\"\(Self.phrase(name))\" AND tracksmedium:\(tracks)"
        let r: MBReleaseList = try get("release", [("query", q), ("limit", "5")], kind: "releaseSearch",
                                       fields: [["release", name], ["tracks", "\(tracks)"]])
        return r.releases ?? []
    }

    /// One release by its id, with its labels, or with its songs and their artists (`songs`).
    public func release(_ id: String, songs: Bool = false) throws -> MBRelease {
        guard id.allSatisfy({ $0.isHexDigit || $0 == "-" }), !id.isEmpty else { throw LookupFailure.badAnswer }
        return try get("release/" + id, [("inc", songs ? "artist-credits+recordings+labels" : "labels")], kind: "release",
                       fields: [["releaseId", id]])
    }

    // MARK: sending

    /// The address of a request: the root, the path, the query (each value percent-encoded), then `fmt=json`.
    public static func address(_ path: String, _ query: [(String, String)]) -> URL {
        let q = (query + [("fmt", "json")]).map { "\($0.0)=\(encode($0.1, keepPlus: $0.0 == "inc" || $0.0 == "toc"))" }
            .joined(separator: "&")
        return URL(string: MusicBrainzRules.root + path + "?" + q)!
    }

    /// Percent-encoding for a query value: everything but letters, digits and `-._~` is encoded, so a search's `+`
    /// (a required clause) travels as `%2B` and a space as `%20`. `inc` and `toc` keep their `+` as the documentation
    /// writes them (`inc=artist-credits+recordings`, `toc=1+6+95462+150+...`).
    static func encode(_ s: String, keepPlus: Bool = false) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
                                   + (keepPlus ? "+" : ""))
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    func get<T: Decodable>(_ path: String, _ query: [(String, String)], kind: String, fields: [[String]],
                           notFound: T? = nil) throws -> T {
        let url = Self.address(path, query)
        let request = LookupRequest(url: url, headers: ["User-Agent": userAgent, "Accept": "application/json"])
        var extra = 0.0
        var attempt = 0
        while true {
            try gate.wait(extra: extra, stopped: stopped)
            let shown = url.absoluteString.removingPercentEncoding ?? url.absoluteString
            let response: LookupResponse
            do { response = try transport.send(request) } catch let f as LookupFailure {
                sent(SentRequest(at: Date(), service: Self.service, kind: kind, fields: fields, address: shown, answer: f.code))
                throw f
            } catch {
                sent(SentRequest(at: Date(), service: Self.service, kind: kind, fields: fields, address: shown, answer: "noConnection"))
                throw LookupFailure.noConnection
            }
            switch response.status {
            case 200:
                guard let value = try? JSONDecoder().decode(T.self, from: response.body) else {
                    sent(SentRequest(at: Date(), service: Self.service, kind: kind, fields: fields, address: shown, answer: "badAnswer"))
                    throw LookupFailure.badAnswer
                }
                sent(SentRequest(at: Date(), service: Self.service, kind: kind, fields: fields, address: shown, answer: "ok"))
                return value
            case 404 where notFound != nil:
                sent(SentRequest(at: Date(), service: Self.service, kind: kind, fields: fields, address: shown, answer: "nothing"))
                return notFound!
            case 503:
                sent(SentRequest(at: Date(), service: Self.service, kind: kind, fields: fields, address: shown, answer: "busy"))
                guard attempt < MusicBrainzRules.retries else { throw LookupFailure.busy }
                let after = response.headers["retry-after"].flatMap(Double.init) ?? 0
                extra = after > 0 ? min(after, 30) : MusicBrainzRules.backoff[min(attempt, MusicBrainzRules.backoff.count - 1)]
                attempt += 1
            default:
                sent(SentRequest(at: Date(), service: Self.service, kind: kind, fields: fields, address: shown,
                                 answer: "refused"))
                throw LookupFailure.refused(response.status)
            }
        }
    }

    // MARK: the query language (Lucene, as MusicBrainz's search documents it)

    /// A phrase inside double quotes: only `\` and `"` need escaping there.
    static func phrase(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
    }

    /// Free words, each escaped: `+ - && || ! ( ) { } [ ] ^ " ~ * ? : \ /` are Lucene's special characters.
    static func escapedWords(_ s: String) -> String {
        let special = Set("+-&|!(){}[]^\"~*?:\\/")
        var out = ""
        for c in s {
            if special.contains(c) { out.append("\\") }
            out.append(c)
        }
        return out
    }

    /// A title without a version in brackets at its end: "Night drive (extended mix)" is "Night drive".
    public static func bareTitle(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let last = t.last, last == ")" || last == "]" else { return t }
        let open: Character = last == ")" ? "(" : "["
        guard let i = t.lastIndex(of: open), i > t.startIndex else { return t }
        let bare = t[..<i].trimmingCharacters(in: .whitespaces)
        return bare.isEmpty ? t : bare
    }

    public static func lucene(_ q: RecordingQuery) -> String? {
        var parts: [String] = []
        if let title = q.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty {
            let bare = bareTitle(title)
            parts.append("+recording:\"\(phrase(bare))\"")
            if bare != title { parts.append("recording:\"\(phrase(title))\"") }
            if let a = q.artist?.trimmingCharacters(in: .whitespaces), !a.isEmpty { parts.append("+artist:\"\(phrase(a))\"") }
            if let r = q.release?.trimmingCharacters(in: .whitespaces), !r.isEmpty { parts.append("release:\"\(phrase(r))\"") }
            return parts.joined(separator: " ")
        }
        if let w = q.words?.trimmingCharacters(in: .whitespaces), !w.isEmpty {
            let words = escapedWords(w)
            return "recording:(\(words)) artist:(\(words))"
        }
        return nil
    }
}
