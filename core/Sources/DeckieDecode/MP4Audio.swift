import Foundation

/// What an MP4 audio file (`.m4a`, `.mp4`) says about where its sound starts and ends, read from its own boxes.
///
/// Why it matters. An AAC encoder puts a lead-in in front of the sound: 1,024 to 2,112 samples of nothing, 23 to 48
/// ms, which the decoder gives back with the rest. Windows' Media Foundation does not take it off (measured on the
/// test tone: the click 1,024 frames late, `MediaFoundationTests`), so a beat grid read from its output would be
/// that much late. The file says how much to drop, in one of two places: its edit list (`elst`: start the media at
/// this sample, play this long), which ffmpeg and most tools write; or the `iTunSMPB` tag, which iTunes and Apple's
/// encoders write (lead-in, padding at the end, the true sample count). Apple Lossless has no lead-in at all. A file
/// that states it nowhere is still read (D33), with its start marked uncertain.
struct MP4AudioInfo: Equatable, Sendable {
    /// The sample entry's type: `mp4a` (AAC and its relatives), `alac` (Apple Lossless), or what else it holds.
    var codec: String
    /// Units per second of the audio track's own clock (`mdhd`); for plain AAC, its sample rate.
    var mediaTimescale: Int
    /// The audio in the track, lead-in and padding included, in those units (the `stts` table summed).
    var mediaSamples: Int
    /// Units per second of the file's clock (`mvhd`), which an edit's length is counted in.
    var movieTimescale: Int
    /// The edit list's one real entry: where in the media to start (track units) and how long to play (file units).
    var edit: (start: Int, duration: Int)?
    /// The `iTunSMPB` tag: lead-in, padding and true length, in samples.
    var smpb: (leadIn: Int, padding: Int, samples: Int)?

    static func == (a: MP4AudioInfo, b: MP4AudioInfo) -> Bool {
        a.codec == b.codec && a.mediaTimescale == b.mediaTimescale && a.mediaSamples == b.mediaSamples
            && a.movieTimescale == b.movieTimescale && a.edit?.start == b.edit?.start
            && a.edit?.duration == b.edit?.duration && a.smpb?.leadIn == b.smpb?.leadIn
            && a.smpb?.padding == b.smpb?.padding && a.smpb?.samples == b.smpb?.samples
    }

    /// Reads the first audio track of an MP4; nil when the bytes are not an MP4 or hold no audio track.
    static func read(_ data: Data) -> MP4AudioInfo? { data.withUnsafeBytes { read($0) } }

    private static func read(_ b: UnsafeRawBufferPointer) -> MP4AudioInfo? {
        func u32(_ o: Int) -> Int { Int(UInt32(bigEndian: b.loadUnaligned(fromByteOffset: o, as: UInt32.self))) }
        func u64(_ o: Int) -> Int { Int(clamping: UInt64(bigEndian: b.loadUnaligned(fromByteOffset: o, as: UInt64.self))) }
        func fourCC(_ o: Int) -> String { String(decoding: b[o..<(o + 4)], as: UTF8.self) }
        // The boxes laid end to end in a range, as ProtectedMP4 reads them.
        func boxes(_ range: Range<Int>) -> [(type: String, body: Range<Int>)] {
            var found: [(type: String, body: Range<Int>)] = []
            var o = range.lowerBound
            while o + 8 <= range.upperBound {
                var size = u32(o), header = 8
                if size == 1 {
                    guard o + 16 <= range.upperBound else { break }
                    size = u64(o + 8); header = 16
                } else if size == 0 { size = range.upperBound - o }
                guard size >= header else { break }
                let end = o + min(size, range.upperBound - o)
                found.append((fourCC(o + 4), (o + header)..<end))
                o = end
            }
            return found
        }
        func first(_ range: Range<Int>, _ path: [String]) -> Range<Int>? {
            var r = range
            for name in path {
                guard let next = boxes(r).first(where: { $0.type == name }) else { return nil }
                r = next.body
            }
            return r
        }

        guard b.count >= 12, fourCC(4) == "ftyp", let moov = first(0..<b.count, ["moov"]) else { return nil }
        var movieTimescale = 0
        if let mvhd = first(moov, ["mvhd"]), mvhd.count >= 20 {
            movieTimescale = b[mvhd.lowerBound] == 1 && mvhd.count >= 32 ? u32(mvhd.lowerBound + 20) : u32(mvhd.lowerBound + 12)
        }
        for trak in boxes(moov) where trak.type == "trak" {
            guard let mdia = first(trak.body, ["mdia"]), let hdlr = first(mdia, ["hdlr"]), hdlr.count >= 12,
                  fourCC(hdlr.lowerBound + 8) == "soun", let mdhd = first(mdia, ["mdhd"]), mdhd.count >= 20,
                  let stbl = first(mdia, ["minf", "stbl"]) else { continue }
            let timescale = b[mdhd.lowerBound] == 1 && mdhd.count >= 32 ? u32(mdhd.lowerBound + 20) : u32(mdhd.lowerBound + 12)
            var codec = ""
            if let stsd = first(stbl, ["stsd"]), stsd.count >= 16 { codec = fourCC(stsd.lowerBound + 12) }
            var samples = 0
            if let stts = first(stbl, ["stts"]), stts.count >= 8 {
                let n = u32(stts.lowerBound + 4)
                var o = stts.lowerBound + 8
                for _ in 0..<n where o + 8 <= stts.upperBound {
                    samples += u32(o) * u32(o + 4)
                    o += 8
                }
            }
            // The edit list: entries of (length, media start, rate). An entry whose media start is -1 is an empty
            // stretch; the first other one is the edit.
            var edit: (start: Int, duration: Int)? = nil
            if let elst = first(trak.body, ["edts", "elst"]), elst.count >= 8 {
                let wide = b[elst.lowerBound] == 1, n = u32(elst.lowerBound + 4), step = wide ? 20 : 12
                var o = elst.lowerBound + 8
                for _ in 0..<n where o + step <= elst.upperBound {
                    let duration = wide ? u64(o) : u32(o)
                    let start = wide ? Int(Int64(bitPattern: UInt64(bigEndian: b.loadUnaligned(fromByteOffset: o + 8, as: UInt64.self))))
                                     : Int(Int32(bitPattern: UInt32(bigEndian: b.loadUnaligned(fromByteOffset: o + 4, as: UInt32.self))))
                    if start >= 0 { edit = (start, duration); break }
                    o += step
                }
            }
            // iTunSMPB: moov/udta/meta/ilst/----, with a "name" box saying iTunSMPB and a "data" box holding text such
            // as " 00000000 00000840 000001CA 00000000003F31F6 ...": zero, lead-in, padding, sample count, in hex.
            var smpb: (leadIn: Int, padding: Int, samples: Int)? = nil
            // (A file may hold more than one udta or meta box; each is looked into.)
            let metas = boxes(moov).filter { $0.type == "udta" }.flatMap { boxes($0.body).filter { $0.type == "meta" } }
            for meta in metas where meta.body.count > 4 {
                guard let ilst = first((meta.body.lowerBound + 4)..<meta.body.upperBound, ["ilst"]) else { continue }
                for item in boxes(ilst) where item.type == "----" {
                    let parts = boxes(item.body)
                    guard let name = parts.first(where: { $0.type == "name" })?.body, name.count > 4,
                          String(decoding: b[(name.lowerBound + 4)..<name.upperBound], as: UTF8.self) == "iTunSMPB",
                          let value = parts.first(where: { $0.type == "data" })?.body, value.count > 8 else { continue }
                    let fields = String(decoding: b[(value.lowerBound + 8)..<value.upperBound], as: UTF8.self)
                        .split(separator: " ").map { Int($0, radix: 16) }
                    if fields.count >= 4, let lead = fields[1], let pad = fields[2], let count = fields[3] {
                        smpb = (lead, pad, count)
                    }
                }
            }
            guard timescale > 0 else { continue }
            return MP4AudioInfo(codec: codec, mediaTimescale: timescale, mediaSamples: samples,
                                movieTimescale: movieTimescale, edit: edit, smpb: smpb)
        }
        return nil
    }
}

/// What to keep of the samples a decoder handed back whole, so the sound starts where the file says it does.
struct MP4Trim: Equatable, Sendable {
    /// Sample frames to drop from the start, and how many to keep after that.
    var drop: Int
    var keep: Int
    /// Set when the file states its lead-in nowhere: the reason, in words. Nothing is dropped then.
    var startUncertain: String?

    struct Refusal: Error, Equatable { var message: String }

    /// The trim for `decoded` sample frames at `rate`, given what the file says (`info`, nil when it is not an MP4,
    /// such as a raw `.aac` stream).
    ///
    /// The lead-in is taken from the edit list, else from iTunSMPB; Apple Lossless has none. It is dropped only when
    /// the decoder really handed back the whole track: the decoded length is compared with the track's own length.
    /// A decoder that had already taken the lead-in off (a Windows that behaves otherwise than the one measured)
    /// gives a shorter length, and then nothing more is dropped. A length that fits neither is refused rather than
    /// guessed at, since a wrong guess is a beat grid that is silently late or early.
    static func plan(info: MP4AudioInfo?, decoded: Int, rate: Int) throws(Refusal) -> MP4Trim {
        guard let info else {
            return MP4Trim(drop: 0, keep: decoded, startUncertain: "the file does not say how much lead-in its encoder added")
        }
        // Track units to output frames: 1 for plain AAC, 2 where the decoder doubles the rate (HE-AAC).
        let scale = Double(rate) / Double(info.mediaTimescale)
        func frames(_ units: Int) -> Int { Int((Double(units) * scale).rounded()) }
        let whole = frames(info.mediaSamples)
        var lead: Int, play: Int?
        if let e = info.edit {
            lead = frames(e.start)
            play = e.duration > 0 && info.movieTimescale > 0
                ? Int((Double(e.duration) * Double(rate) / Double(info.movieTimescale)).rounded()) : nil
        } else if let s = info.smpb {
            lead = frames(s.leadIn)
            play = frames(s.samples)
        } else if info.codec == "alac" {
            lead = 0
            play = whole > 0 ? whole : nil
        } else {
            return MP4Trim(drop: 0, keep: decoded, startUncertain: "the file does not say how much lead-in its encoder added")
        }
        // One encoder block of slack either way: decoders round the end to whole blocks.
        let slack = frames(4096)
        if whole > 0, decoded > whole + slack || decoded < whole - lead - slack {
            throw Refusal(message: "Windows decoded \(decoded) sample frames where the file holds \(whole); "
                          + "its start cannot be placed, so it is not read")
        }
        // The whole track came back (the measured behaviour: every block, so at least the track's own length) when
        // the length reaches the track's; a decoder that had dropped the lead-in gives less, even with its end
        // rounded up to a whole block.
        let untrimmed = whole > 0 ? decoded >= whole : decoded >= lead + (play ?? 0)
        let drop = untrimmed ? min(lead, decoded) : 0
        let keep = max(0, min(decoded - drop, play ?? (decoded - drop)))
        return MP4Trim(drop: drop, keep: keep, startUncertain: nil)
    }

    /// The samples kept, from interleaved `samples` of `channels`.
    func apply(_ samples: [Float], channels: Int) -> [Float] {
        drop == 0 && keep * channels == samples.count ? samples
            : Array(samples[(drop * channels)..<((drop + keep) * channels)])
    }
}
