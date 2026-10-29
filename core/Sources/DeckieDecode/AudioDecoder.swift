import Foundation

/// The kinds of audio file DeckieDecode recognises from their first bytes, whether or not it can decode them yet.
public enum AudioFormat: String, Sendable, Equatable, CustomStringConvertible {
    /// RIFF/WAVE.
    case wav = "WAV"
    /// MPEG audio (MP3), with or without an ID3 tag in front.
    case mp3 = "MP3"
    /// AAC, in an MP4 container (.m4a, .mp4) or as a raw ADTS stream (.aac). An MP4 holding another codec, such as
    /// Apple Lossless, is reported as AAC too until the container is read.
    case aac = "AAC"
    /// AIFF or AIFF-C.
    case aiff = "AIFF"
    /// FLAC, native or in an Ogg container (Ogg-FLAC), with or without an ID3v2 tag in front.
    case flac = "FLAC"
    /// Nothing DeckieDecode recognises.
    case unknown = "unknown format"

    public var description: String { rawValue }

    /// The format the bytes start with.
    public static func sniff(_ data: Data) -> AudioFormat {
        let b = [UInt8](data.prefix(12))
        func ascii(_ at: Int, _ s: String) -> Bool { b.count >= at + s.utf8.count && Array(b[at..<(at + s.utf8.count)]) == Array(s.utf8) }
        if ascii(0, "RIFF") && ascii(8, "WAVE") { return .wav }
        if ascii(0, "FORM") && (ascii(8, "AIFF") || ascii(8, "AIFC")) { return .aiff }
        if ascii(0, "fLaC") { return .flac }
        if ascii(4, "ftyp") { return .aac }
        if ascii(0, "OggS") { return data.withUnsafeBytes { FLACReader.isOggFLAC($0) } ? .flac : .unknown }
        if ascii(0, "ID3") {
            // Some taggers put an ID3v2 tag in front of FLAC too: look behind the tags.
            let end = data.withUnsafeBytes { MP3Reader.id3v2End($0).end }
            return data.dropFirst(end).starts(with: "fLaC".utf8) ? .flac : .mp3
        }
        if b.count >= 2 && b[0] == 0xFF && b[1] & 0xE0 == 0xE0 {
            // Frame sync. The two "layer" bits are 00 for AAC in ADTS and nonzero for MPEG audio layers I to III.
            return b[1] & 0x06 == 0 ? .aac : .mp3
        }
        return .unknown
    }
}

/// Why a file could not be decoded: which file, what it looked like, and a plain explanation.
public struct AudioDecodeError: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Kind: Sendable, Equatable {
        /// The file is missing or could not be read.
        case cannotRead
        /// A format, or a variant of one, that DeckieDecode cannot decode on this platform yet.
        case unsupported
        /// The file starts like a known format, but its contents do not hold together.
        case damaged
        /// The file is locked by copy protection (DRM), such as an iTunes Store or Apple Music file: only the
        /// store's own player can play it, so no decoder will ever read it. Counted apart from `unsupported`.
        case protected
    }

    public var kind: Kind
    /// The file's path.
    public var file: String
    /// What the file's first bytes say it is (`.unknown` when it could not be read).
    public var format: AudioFormat
    public var message: String

    public init(kind: Kind, file: String, format: AudioFormat, message: String) {
        self.kind = kind
        self.file = file
        self.format = format
        self.message = message
    }

    public var description: String { "cannot decode \(file) (\(format)): \(message)" }
}

/// A frame of a file that was damaged and was decoded as silence instead (concealed), so the file still plays: an MP3
/// frame whose data runs past its own end, as on a damaged or badly spliced file (MP3Reader's comment). The file is
/// faulty but playable, and the frame's time lets the crate builder's import log point the DJ to it.
public struct DamagedFrame: Sendable, Equatable {
    /// Where the frame's output starts, in seconds from the start of the decoded audio.
    public var startSeconds: Double
    /// Its length: one MP3 frame, 1,152 samples (26.1 ms at 44.1 kHz), or 576 for MPEG-2 and 2.5.
    public var seconds: Double

    public init(startSeconds: Double, seconds: Double) {
        self.startSeconds = startSeconds
        self.seconds = seconds
    }
}

/// A decoded file and the damaged frames concealed in it.
public struct DecodedAudio: Sendable {
    public var buffer: AudioBuffer
    /// In order; empty for a file decoded as written, and always for WAV, AIFF and FLAC (dr_flac refuses a damaged
    /// FLAC file rather than concealing anything).
    public var damagedFrames: [DamagedFrame]

    public init(buffer: AudioBuffer, damagedFrames: [DamagedFrame] = []) {
        self.buffer = buffer
        self.damagedFrames = damagedFrames
    }
}

/// The damaged-frame concealment checked on one MP3 (`deckie-build mp3-check`): the file decoded as `AudioDecoder`
/// decodes it, beside the samples of dr_mp3's own pull reader, which is what the MP3 reader gave before the
/// concealment, both trimmed the same way. A file with no damaged frame must give the same samples, bit for bit; one
/// with damaged frames may differ only from each frame's start to the end of the frame after it.
public struct MP3ConcealmentCheck: Sendable {
    public var damagedFrames: [DamagedFrame]
    public var pullReader: AudioBuffer
    public var decoded: AudioBuffer
    /// The first and last sample frames where the two differ (by bit pattern), nil when they are the same.
    public var differing: ClosedRange<Int>?

    /// Decodes the MP3 at `url` both ways.
    public static func check(_ url: URL) throws(AudioDecodeError) -> MP3ConcealmentCheck {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AudioDecodeError(kind: .cannotRead, file: url.path, format: .unknown,
                                   message: "could not be read (\(error))")
        }
        guard AudioFormat.sniff(data) == .mp3 else {
            throw AudioDecoder.unsupported(url.path, AudioFormat.sniff(data), "not an MP3 file")
        }
        return try MP3Reader.concealmentCheck(data, file: url.path)
    }
}

/// Turns an audio file into float samples at the file's own sample rate. It decodes WAV and AIFF in plain Swift, MP3
/// through the vendored dr_mp3 and FLAC through the vendored dr_flac, the same on every platform; AAC is recognised
/// but reports that it is not supported yet, and a copy-protected MP4 (an iTunes Store or Apple Music file) that it
/// is protected.
public enum AudioDecoder {
    /// Decodes the whole file into memory at its own sample rate (resampling is a later step). Mono stays mono,
    /// stereo stays stereo, more channels are cut to the first two.
    public static func decode(_ url: URL) throws(AudioDecodeError) -> AudioBuffer {
        try decodeReporting(url).buffer
    }

    /// `decode`, with the damaged frames it concealed (MP3 only), for a report such as the crate builder's import log.
    public static func decodeReporting(_ url: URL) throws(AudioDecodeError) -> DecodedAudio {
        let path = url.path
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            let missing = !FileManager.default.fileExists(atPath: path)
            throw AudioDecodeError(kind: .cannotRead, file: path, format: .unknown,
                                   message: missing ? "no such file" : "could not be read (\(error))")
        }
        let format = AudioFormat.sniff(data)
        // One backend per format. A new decoder is a new file with a function like WAVReader.decode and one line
        // here; the public API does not change.
        switch format {
        case .wav:
            return DecodedAudio(buffer: try WAVReader.decode(data, file: path))
        case .aiff:
            return DecodedAudio(buffer: try AIFFReader.decode(data, file: path))
        case .mp3:
            return try MP3Reader.decodeReporting(data, file: path)
        case .flac:
            return DecodedAudio(buffer: try FLACReader.decode(data, file: path))
        case .aac:
            if let found = ProtectedMP4.check(data) {
                throw AudioDecodeError(kind: .protected, file: path, format: format, message: found.message)
            }
            throw unsupported(path, format, "AAC is not supported on this platform yet: it will use the platform's "
                              + "own decoder (AVFoundation on Apple, Media Foundation on Windows); Linux has no "
                              + "licence-safe AAC decoder in a distribution package")
        case .unknown:
            throw unsupported(path, format, "not a format DeckieDecode recognises (WAV, AIFF, MP3, FLAC, AAC)")
        }
    }

    static func unsupported(_ file: String, _ format: AudioFormat, _ message: String) -> AudioDecodeError {
        AudioDecodeError(kind: .unsupported, file: file, format: format, message: message)
    }
}
