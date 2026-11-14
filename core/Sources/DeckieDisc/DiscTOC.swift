import Foundation

/// A music CD's table of contents: how many songs it has, where each starts, and where the disc ends (research AA,
/// section 1.1: it names nothing by itself, but it is the disc's serial number on this computer and says exactly where
/// each song must be cut). Addresses are sectors (blocks) of 1/75 second, counted from the start of song 1's own
/// stretch of disc (LBA 0 is the time 00:02:00 on the disc).
public struct DiscTOC: Codable, Equatable, Sendable {
    public struct Track: Codable, Equatable, Sendable {
        public var number: Int
        /// Where the track starts (its index 1), in sectors.
        public var start: Int
        /// An audio track, or a data track (an enhanced CD's computer files).
        public var audio: Bool
        public var session: Int
        public init(number: Int, start: Int, audio: Bool, session: Int = 1) {
            self.number = number; self.start = start; self.audio = audio; self.session = session
        }
    }

    /// One song as Desk reads it: the stretch of disc the deck plays under that number.
    public struct Song: Codable, Equatable, Sendable {
        public var number: Int
        public var start: Int
        /// One past the last sector.
        public var end: Int
        public var sectors: Int { end - start }
        public var seconds: Double { Double(sectors) / 75 }
    }

    public var tracks: [Track]
    /// Where the (last audio session's) lead-out starts: the end of the music.
    public var leadOut: Int

    public init(tracks: [Track], leadOut: Int) {
        self.tracks = tracks.sorted { $0.number < $1.number }
        self.leadOut = leadOut
    }

    /// Sectors a second, and bytes a sector of CD audio (44,100 frames of two 16-bit channels a second).
    public static let sectorsPerSecond = 75
    public static let bytesPerSector = 2352

    /// The songs, in the table's order. Each runs from its start to the next track's (so the gap before a song is
    /// played at the end of the one before it, as a deck playing through does), and the last to the lead-out. A
    /// stretch before song 1's start (a hidden song in its pregap) belongs to song 1, which the deck plays it under.
    /// The audio before an enhanced CD's data session ends 11,400 sectors (the session's lead-out and lead-in)
    /// before the data track starts.
    public var songs: [Song] {
        var out: [Song] = []
        for (i, t) in tracks.enumerated() where t.audio {
            var end = leadOut
            if i + 1 < tracks.count {
                let next = tracks[i + 1]
                end = next.audio ? next.start : (next.start - 11_400 > t.start ? next.start - 11_400 : next.start)
            }
            let start = out.isEmpty && t.start > 0 && t.number == tracks.first?.number ? 0 : t.start
            if end > start { out.append(Song(number: t.number, start: start, end: end)) }
        }
        return out
    }

    public var audioSeconds: Double { songs.reduce(0) { $0 + $1.seconds } }

    /// The disc's own id on this computer: the same disc gives the same id, so Desk knows it when it comes back and
    /// keeps one copy of its songs. A 64-bit FNV-1a hash of the track numbers, kinds and starts and the lead-out.
    public var id: String {
        var h: UInt64 = 0xcbf29ce484222325
        func mix(_ v: Int) {
            for b in withUnsafeBytes(of: Int64(v).bigEndian, Array.init) { h ^= UInt64(b); h = h &* 0x100000001b3 }
        }
        for t in tracks { mix(t.number); mix(t.audio ? 1 : 0); mix(t.start) }
        mix(leadOut)
        return "cd-" + String(h, radix: 16).leftPadded(to: 16)
    }

    // MARK: reading a drive's answer

    /// A drive's answer to "read table of contents" in its format 0, with addresses as sectors (MMC READ TOC, MSF bit
    /// 0): a four-byte header (length, first track, last track), then eight bytes a track (reserved, ADR and CONTROL,
    /// track number, reserved, the start as a 32-bit big-endian sector number), the lead-out last as track 0xAA.
    /// Bit 2 of CONTROL marks a data track.
    public static func format0(_ bytes: [UInt8]) throws -> DiscTOC {
        guard bytes.count >= 12 else { throw DiscError("the table of contents is too short (\(bytes.count) bytes)") }
        let declared = Int(bytes[0]) << 8 | Int(bytes[1])
        let end = min(bytes.count, 2 + declared)
        var tracks: [Track] = []
        var leadOut: Int? = nil
        var i = 4
        while i + 8 <= end {
            let control = bytes[i + 1] & 0x0F
            let number = Int(bytes[i + 2])
            let lba = Int(Int32(bitPattern: UInt32(bytes[i + 4]) << 24 | UInt32(bytes[i + 5]) << 16 | UInt32(bytes[i + 6]) << 8 | UInt32(bytes[i + 7])))
            if number == 0xAA { leadOut = lba } else if (1...99).contains(number) {
                tracks.append(Track(number: number, start: lba, audio: control & 0x04 == 0))
            }
            i += 8
        }
        guard let leadOut, !tracks.isEmpty else { throw DiscError("the table of contents has no tracks or no lead-out") }
        return DiscTOC(tracks: tracks, leadOut: lastAudioLeadOut(tracks, leadOut))
    }

    /// A drive's answer in format 2 (the full table, as the Mac's DKIOCCDREADTOC gives it): a four-byte header
    /// (length, first session, last session), then eleven bytes an entry (session, ADR and CONTROL, TNO, POINT, the
    /// time, zero, PMIN, PSEC, PFRAME). POINT 1 to 99 is a track starting at PMIN:PSEC:PFRAME; POINT 0xA2 is the
    /// session's lead-out. Times are minutes, seconds and frames from the start of the disc, 150 frames ahead of
    /// sector 0.
    public static func format2(_ bytes: [UInt8]) throws -> DiscTOC {
        guard bytes.count >= 15 else { throw DiscError("the full table of contents is too short (\(bytes.count) bytes)") }
        let declared = Int(bytes[0]) << 8 | Int(bytes[1])
        let end = min(bytes.count, 2 + declared)
        var tracks: [Track] = []
        var leadOuts: [Int: Int] = [:]
        var i = 4
        while i + 11 <= end {
            let session = Int(bytes[i])
            let adr = bytes[i + 1] >> 4, control = bytes[i + 1] & 0x0F
            let point = Int(bytes[i + 3])
            let lba = (Int(bytes[i + 8]) * 60 + Int(bytes[i + 9])) * 75 + Int(bytes[i + 10]) - 150
            if adr == 1 {
                if (1...99).contains(point) { tracks.append(Track(number: point, start: lba, audio: control & 0x04 == 0, session: session)) }
                else if point == 0xA2 { leadOuts[session] = lba }
            }
            i += 11
        }
        guard !tracks.isEmpty, let lastAudio = tracks.filter(\.audio).max(by: { $0.number < $1.number }),
              let leadOut = leadOuts[lastAudio.session] ?? leadOuts.values.max() else {
            throw DiscError("the full table of contents has no audio tracks or no lead-out")
        }
        return DiscTOC(tracks: tracks, leadOut: leadOut)
    }

    /// The table from the songs' lengths in sectors, one after another from 0, when no table could be read (the Mac's
    /// music CD read as files, with the drive's own table out of reach): the songs and their order are right, the
    /// gaps between them are not known.
    public static func fromLengths(_ sectors: [Int]) -> DiscTOC {
        var tracks: [Track] = []
        var at = 0
        for (i, n) in sectors.enumerated() {
            tracks.append(Track(number: i + 1, start: at, audio: true))
            at += max(0, n)
        }
        return DiscTOC(tracks: tracks, leadOut: at)
    }

    /// Format 0 gives one lead-out, the disc's last; on an enhanced CD that is the data session's, past the music.
    /// The songs' end is worked out in `songs` from the data track's start, so this is kept as given.
    static func lastAudioLeadOut(_ tracks: [Track], _ leadOut: Int) -> Int { leadOut }
}

/// A failure reading a disc or a drive, said in a sentence.
public struct DiscError: Error, CustomStringConvertible, LocalizedError, Equatable {
    public let description: String
    public init(_ d: String) { description = d }
    public var errorDescription: String? { description }
}

extension String {
    func leftPadded(to n: Int) -> String { count >= n ? self : String(repeating: "0", count: n - count) + self }
}
