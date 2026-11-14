import Foundation

// MusicBrainz's answers in JSON (`fmt=json`), read leniently: every field may be missing, and fields Deckie does not
// use are not read. Deckie reads only the core data, which MusicBrainz licenses under CC0 ("The core data of the
// database is licensed under the CC0"): titles, artists, lengths, releases, dates, labels, ISRCs, disc ids. It does
// not read tags or genres: the MusicBrainz Database page lists "user submitted annotations, tags (including genre
// associations) and ratings" as supplementary data under CC BY-NC-SA 3.0, which a paid app may not keep.

/// An artist credit: the name as credited, and the words joining it to the next ("feat.", " & ").
public struct MBCredit: Decodable, Sendable, Equatable {
    public var name: String?
    public var joinphrase: String?
}

extension Array where Element == MBCredit {
    /// The credit as one line: "Daft Punk", "Artist A feat. Artist B".
    public var line: String? {
        let s = map { ($0.name ?? "") + ($0.joinphrase ?? "") }.joined().trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }
}

public struct MBReleaseGroup: Decodable, Sendable, Equatable {
    public var primaryType: String?
    public var secondaryTypes: [String]?
    enum CodingKeys: String, CodingKey { case primaryType = "primary-type", secondaryTypes = "secondary-types" }
}

public struct MBLabelInfo: Decodable, Sendable, Equatable {
    public struct Label: Decodable, Sendable, Equatable { public var name: String? }
    public var catalogNumber: String?
    public var label: Label?
    enum CodingKeys: String, CodingKey { case catalogNumber = "catalog-number", label }
}

public struct MBTrack: Decodable, Sendable, Equatable {
    public var title: String?
    public var length: Int?
    public var position: Int?
    public var number: String?
    public var artistCredit: [MBCredit]?
    public var recording: MBRecordingRef?
    enum CodingKeys: String, CodingKey { case title, length, position, number, recording, artistCredit = "artist-credit" }
}

/// The recording behind a track on a disc's release (only what is used).
public struct MBRecordingRef: Decodable, Sendable, Equatable {
    public var id: String?
    public var title: String?
    public var length: Int?
    public var disambiguation: String?
    public var firstReleaseDate: String?
    public var artistCredit: [MBCredit]?
    enum CodingKeys: String, CodingKey {
        case id, title, length, disambiguation, firstReleaseDate = "first-release-date", artistCredit = "artist-credit"
    }
}

public struct MBDiscRef: Decodable, Sendable, Equatable { public var id: String? }

public struct MBMedium: Decodable, Sendable, Equatable {
    public var position: Int?
    public var format: String?
    public var trackCount: Int?
    /// A lookup's songs (`tracks`); a search gives only the matching one (`track`).
    public var tracks: [MBTrack]?
    public var track: [MBTrack]?
    public var discs: [MBDiscRef]?
    enum CodingKeys: String, CodingKey { case position, format, tracks, track, discs, trackCount = "track-count" }
    public var songs: [MBTrack] { tracks ?? track ?? [] }
}

public struct MBRelease: Decodable, Sendable, Equatable {
    public var id: String?
    public var title: String?
    public var status: String?
    public var date: String?
    public var country: String?
    public var releaseGroup: MBReleaseGroup?
    public var labelInfo: [MBLabelInfo]?
    public var media: [MBMedium]?
    public var artistCredit: [MBCredit]?
    public var trackCount: Int?
    public var score: Int?
    enum CodingKeys: String, CodingKey {
        case id, title, status, date, country, media, score
        case releaseGroup = "release-group", labelInfo = "label-info", artistCredit = "artist-credit", trackCount = "track-count"
    }
    /// Its labels' names, each once, in order.
    public var labels: [String] {
        var out: [String] = []
        for l in labelInfo ?? [] {
            if let n = l.label?.name?.trimmingCharacters(in: .whitespaces), !n.isEmpty, n != "[no label]", !out.contains(n) { out.append(n) }
        }
        return out
    }
}

public struct MBRecording: Decodable, Sendable, Equatable {
    public var id: String?
    public var title: String?
    public var length: Int?
    public var disambiguation: String?
    public var firstReleaseDate: String?
    public var artistCredit: [MBCredit]?
    public var releases: [MBRelease]?
    public var isrcs: [String]?
    public var score: Int?
    public var video: Bool?
    enum CodingKeys: String, CodingKey {
        case id, title, length, disambiguation, releases, isrcs, score, video
        case firstReleaseDate = "first-release-date", artistCredit = "artist-credit"
    }
}

public struct MBRecordingList: Decodable, Sendable { public var count: Int?; public var recordings: [MBRecording]? }
public struct MBReleaseList: Decodable, Sendable { public var count: Int?; public var releases: [MBRelease]? }

/// The answer to a disc id: the disc (its id and the releases it is on) when MusicBrainz knows the id; otherwise the
/// releases its fuzzy search found from the table of contents (`release-count` set, no `id`).
public struct MBDiscAnswer: Decodable, Sendable, Equatable {
    public var id: String?
    public var releases: [MBRelease]?
    public var releaseCount: Int?
    enum CodingKeys: String, CodingKey { case id, releases, releaseCount = "release-count" }
    public init(id: String? = nil, releases: [MBRelease]? = nil, releaseCount: Int? = nil) {
        self.id = id; self.releases = releases; self.releaseCount = releaseCount
    }
    /// Whether MusicBrainz knew this exact disc (not a fuzzy match).
    public var exact: Bool { id != nil }
}
