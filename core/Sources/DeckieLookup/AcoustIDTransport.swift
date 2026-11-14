import Foundation

// Sending a form, for AcoustID's lookup (AcoustID.swift). MusicBrainz is asked by address alone (LookupRequest); an
// AcoustID lookup carries a fingerprint of a few kilobytes and the application's key, which go in the body of a POST,
// never in the address, so that neither is ever in a log of addresses. The same three ways out as MusicBrainz's, each
// given a `post`: the Mac's system transport (the same ephemeral session), the stand-in on Linux and Windows that
// says the lookup is not on this computer yet, and the recorded answers the tests use.

/// One form as it goes out: the address, the headers and the body (`application/x-www-form-urlencoded`).
public struct LookupPost: Sendable {
    public let url: URL
    public let headers: [String: String]
    public let body: Data
    /// A name for this request in recorded answers that leaves the key out (`RecordedTransport`).
    public let recordingKey: String
    public init(url: URL, headers: [String: String], body: Data, recordingKey: String) {
        self.url = url; self.headers = headers; self.body = body; self.recordingKey = recordingKey
    }
}

/// A transport that can also send a form.
public protocol LookupPostTransport: LookupTransport {
    func post(_ request: LookupPost) throws -> LookupResponse
}

extension LookupTransports.Unavailable: LookupPostTransport {
    func post(_ request: LookupPost) throws -> LookupResponse { throw LookupFailure.notOnThisComputer }
}

extension RecordedTransport: LookupPostTransport {
    /// Answers a form from the entry recorded under its `recordingKey` (which never holds the key).
    public func post(_ request: LookupPost) throws -> LookupResponse {
        log.add(LookupRequest(url: URL(string: request.url.absoluteString + "#" + request.recordingKey) ?? request.url,
                              headers: request.headers))
        guard let e = index[request.recordingKey],
              let body = try? Data(contentsOf: folder.appendingPathComponent(e.file)) else { throw LookupFailure.noConnection }
        return LookupResponse(status: e.status, body: body)
    }
}

#if canImport(Darwin)
extension SystemTransport: LookupPostTransport {
    func post(_ request: LookupPost) throws -> LookupResponse {
        var r = URLRequest(url: request.url)
        r.httpMethod = "POST"
        r.httpShouldHandleCookies = false
        r.httpBody = request.body
        for (k, v) in request.headers { r.setValue(v, forHTTPHeaderField: k) }
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: r) { data, response, _ in
            if let http = response as? HTTPURLResponse {
                var headers: [String: String] = [:]
                for (k, v) in http.allHeaderFields { headers["\(k)"] = "\(v)" }
                box.result = .success(LookupResponse(status: http.statusCode, headers: headers, body: data ?? Data()))
            } else {
                box.result = .failure(LookupFailure.noConnection)
            }
            done.signal()
        }
        task.resume()
        done.wait()
        return try box.result.get()
    }
}
#endif
