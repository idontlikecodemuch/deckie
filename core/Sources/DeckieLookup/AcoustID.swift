import Foundation

// AcoustID's rules, as its documentation stated them when this was written (acoustid.org/webservice, read Nov 14,
// 2026):
//   - The lookup is `https://api.acoustid.org/v2/lookup` with `client` ("your application's API key"), `duration`
//     ("length of the whole audio file in seconds"), `fingerprint` (Chromaprint's compressed form) and `meta`.
//   - GET and POST are both accepted; POST is preferred for long fingerprints.
//   - "Do not make more than 3 requests per second."
//   - "This service is provided for free for non-commercial use only"; a commercial product subscribes
//     (acoustid.biz; research letter AA).
// What it answers: AcoustID's own id for the fingerprint's track, a score from 0 to 1, and, with
// `meta=recordings+releasegroups+compress`, the MusicBrainz recordings linked to it with their titles, artists and
// release groups. Only the MusicBrainz ids and what MusicBrainz says of them are Deckie's to keep (that mapping is
// CC0; the rest of AcoustID's data is share-alike: research letter AA).
//
// What this code does about them:
//   - One gate for the whole program (`AcoustIDGate.shared`, the same kind as MusicBrainz's): two requests never
//     start less than a third of a second apart, from any thread.
//   - The key, the length and the fingerprint go in a POST's form body, never in the address. The key is read from
//     `DECKIE_ACOUSTID_KEY` for now; it is never printed, logged, written to a file or put in the sent list. Without
//     it the client says so and sends nothing.
//   - The same User-Agent as MusicBrainz's: "DeckieDesk/<version> ( https://deckie.io )", no person and no address.
//   - A 503 or 429 is waited out (Retry-After when given, else 2 then 4 seconds) and asked again at most twice.
//   - Nothing is sent but the fingerprint and the length: no file name, no path, no tags.

public enum AcoustIDRules {
    public static let lookup = "https://api.acoustid.org/v2/lookup"
    /// The least time between the starts of two requests: their "3 requests per second", with a little to spare.
    public static let interval = 0.34
    public static let retries = 2
    public static let backoff = [2.0, 4.0]
    public static let meta = "recordings+releasegroups+compress"
    /// Where the application's key is read from, for now.
    public static let keyVariable = "DECKIE_ACOUSTID_KEY"
}

/// The gate every AcoustID request goes through.
public enum AcoustIDGate {
    public static let shared = MusicBrainzGate(interval: AcoustIDRules.interval)
}

/// Why an AcoustID lookup could not be made, beyond the failures every lookup has (`LookupFailure`).
public enum AcoustIDFailure: Error, Equatable, Sendable, CustomStringConvertible {
    /// No application key on this computer: nothing was sent.
    case noKey
    /// The service answered with an error of its own (its code and words), such as a key it does not know.
    case service(code: Int, message: String)

    public var code: String {
        switch self {
        case .noKey: return "noKey"
        case .service: return "serviceError"
        }
    }
    public var description: String {
        switch self {
        case .noKey:
            return "There is no AcoustID application key on this computer (\(AcoustIDRules.keyVariable)), so nothing was sent."
        case let .service(code, message):
            return "AcoustID said no: \(message) (its code \(code))."
        }
    }
}

/// One MusicBrainz recording AcoustID links to a fingerprint.
public struct AcoustIDRecording: Sendable, Equatable, Codable {
    /// The MusicBrainz recording id.
    public var id: String
    public var title: String?
    /// The artists as credited, joined as MusicBrainz joins them.
    public var artist: String?
    public var seconds: Double?
    public var releaseGroups: [ReleaseGroup]

    public struct ReleaseGroup: Sendable, Equatable, Codable {
        public var id: String
        public var title: String?
        public var type: String?
        public var secondaryTypes: [String]
    }
}

/// One of AcoustID's answers for a fingerprint: its track id, how well the fingerprint matched it (0 to 1), and the
/// recordings linked to it (none when nobody has linked one yet).
public struct AcoustIDMatch: Sendable, Equatable, Codable {
    public var acoustID: String
    public var score: Double
    public var recordings: [AcoustIDRecording]
}

/// AcoustID's lookup by fingerprint.
public struct AcoustID: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public static let service = "acoustid"
    private let key: String
    public let userAgent: String
    let transport: LookupTransport
    let gate: MusicBrainzGate
    public var stopped: @Sendable () -> Bool = { false }
    /// Told of every request made: the length and a short head of the fingerprint, never the key.
    public var sent: @Sendable (SentRequest) -> Void = { _ in }

    /// A client with this key. Prefer `fromEnvironment`.
    public init(key: String, version: String, transport: LookupTransport = LookupTransports.system,
                gate: MusicBrainzGate = AcoustIDGate.shared) {
        self.key = key
        self.userAgent = MusicBrainzRules.userAgent(version: version)
        self.transport = transport
        self.gate = gate
    }

    /// A client with the key in `DECKIE_ACOUSTID_KEY`, or `.noKey` when there is none.
    public static func fromEnvironment(version: String, environment: [String: String] = ProcessInfo.processInfo.environment,
                                       transport: LookupTransport = LookupTransports.system,
                                       gate: MusicBrainzGate = AcoustIDGate.shared) -> Result<AcoustID, AcoustIDFailure> {
        let k = (environment[AcoustIDRules.keyVariable] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty else { return .failure(.noKey) }
        return .success(AcoustID(key: k, version: version, transport: transport, gate: gate))
    }

    // The key is never shown, whichever way the client is printed.
    public var description: String { "AcoustID client (\(userAgent))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }

    public var available: Bool { transport.available && transport is LookupPostTransport }

    /// The matches for a fingerprint (Chromaprint's compressed form) of a file `duration` seconds long, best first.
    public func lookup(fingerprint: String, duration: Int) throws -> [AcoustIDMatch] {
        guard let post = transport as? LookupPostTransport, transport.available else { throw LookupFailure.notOnThisComputer }
        let url = URL(string: AcoustIDRules.lookup)!
        let form = [("client", key), ("duration", "\(duration)"), ("fingerprint", fingerprint), ("meta", AcoustIDRules.meta),
                    ("format", "json")]
        let body = Data(form.map { "\($0.0)=\(MusicBrainz.encode($0.1, keepPlus: $0.0 == "meta"))" }.joined(separator: "&").utf8)
        let request = LookupPost(url: url, headers: ["User-Agent": userAgent, "Accept": "application/json",
                                                     "Content-Type": "application/x-www-form-urlencoded"],
                                 body: body, recordingKey: Self.recordingKey(fingerprint: fingerprint, duration: duration))
        let fields = [["duration", "\(duration)"],
                      ["fingerprint", String(fingerprint.prefix(16)) + "… (\(fingerprint.count) characters)"]]
        func report(_ answer: String) {
            sent(SentRequest(at: Date(), service: Self.service, kind: "fingerprintLookup", fields: fields,
                             address: AcoustIDRules.lookup, answer: answer))
        }
        var extra = 0.0, attempt = 0
        while true {
            try gate.wait(extra: extra, stopped: stopped)
            let response: LookupResponse
            do { response = try post.post(request) } catch let f as LookupFailure {
                report(f.code); throw f
            } catch {
                report("noConnection"); throw LookupFailure.noConnection
            }
            if response.status == 503 || response.status == 429 {
                report("busy")
                guard attempt < AcoustIDRules.retries else { throw LookupFailure.busy }
                let after = response.headers["retry-after"].flatMap(Double.init) ?? 0
                extra = after > 0 ? min(after, 30) : AcoustIDRules.backoff[min(attempt, AcoustIDRules.backoff.count - 1)]
                attempt += 1
                continue
            }
            let answer = try? JSONDecoder().decode(AcoustIDJSON.Answer.self, from: response.body)
            if let e = answer?.error, answer?.status != "ok" {
                report("refused")
                throw AcoustIDFailure.service(code: e.code ?? 0, message: e.message ?? "no reason given")
            }
            guard response.status == 200 else { report("refused"); throw LookupFailure.refused(response.status) }
            guard let answer, answer.status == "ok" else { report("badAnswer"); throw LookupFailure.badAnswer }
            let matches = (answer.results ?? []).map(Self.match).sorted { $0.score > $1.score }
            report(matches.isEmpty ? "nothing" : "ok")
            return matches
        }
    }

    /// The name a lookup is recorded under: the length and a hash of the fingerprint (FNV-1a, 64 bits); no key.
    public static func recordingKey(fingerprint: String, duration: Int) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in fingerprint.utf8 { h = (h ^ UInt64(b)) &* 0x100000001b3 }
        return "acoustid duration=\(duration) fingerprint=\(String(h, radix: 16))"
    }

    static func match(_ r: AcoustIDJSON.Result) -> AcoustIDMatch {
        AcoustIDMatch(acoustID: r.id, score: r.score ?? 0, recordings: (r.recordings ?? []).map { rec in
            let artist = rec.artists.map { list in
                list.enumerated().map { i, a in a.name + (i < list.count - 1 ? (a.joinphrase ?? ", ") : "") }.joined()
            }
            return AcoustIDRecording(id: rec.id, title: rec.title, artist: artist?.isEmpty == true ? nil : artist,
                                     seconds: rec.duration,
                                     releaseGroups: (rec.releasegroups ?? []).map {
                                         .init(id: $0.id, title: $0.title, type: $0.type, secondaryTypes: $0.secondarytypes ?? [])
                                     })
        })
    }
}

/// AcoustID's JSON, as much of it as Deckie reads.
enum AcoustIDJSON {
    struct Answer: Decodable {
        var status: String
        var results: [Result]?
        var error: Failure?
    }
    struct Failure: Decodable {
        var code: Int?
        var message: String?
    }
    struct Result: Decodable {
        var id: String
        var score: Double?
        var recordings: [Recording]?
    }
    struct Recording: Decodable {
        var id: String
        var title: String?
        var duration: Double?
        var artists: [Artist]?
        var releasegroups: [ReleaseGroup]?
    }
    struct Artist: Decodable {
        var id: String?
        var name: String
        var joinphrase: String?
    }
    struct ReleaseGroup: Decodable {
        var id: String
        var title: String?
        var type: String?
        var secondarytypes: [String]?
    }
}
