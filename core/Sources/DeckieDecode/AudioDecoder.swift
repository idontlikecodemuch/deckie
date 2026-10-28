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
        if ascii(0, "ID3") { return .mp3 }
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

/// Turns an audio file into float samples at the file's own sample rate. It decodes WAV in plain Swift and MP3
/// through the vendored dr_mp3, the same on every platform; AAC is recognised but reports that it is not supported
/// yet.
public enum AudioDecoder {
    /// Decodes the whole file into memory at its own sample rate (resampling is a later step). Mono stays mono,
    /// stereo stays stereo, more channels are cut to the first two.
    public static func decode(_ url: URL) throws(AudioDecodeError) -> AudioBuffer {
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
            return try WAVReader.decode(data, file: path)
        case .mp3:
            return try MP3Reader.decode(data, file: path)
        case .aac:
            throw unsupported(path, format, "AAC is not supported on this platform yet: it will use the platform's "
                              + "own decoder (AVFoundation on Apple, Media Foundation on Windows); Linux has no "
                              + "licence-safe AAC decoder in a distribution package")
        case .aiff, .flac:
            throw unsupported(path, format, "\(format) is not supported yet")
        case .unknown:
            throw unsupported(path, format, "not a format DeckieDecode recognises (WAV, MP3, AAC)")
        }
    }

    static func unsupported(_ file: String, _ format: AudioFormat, _ message: String) -> AudioDecodeError {
        AudioDecodeError(kind: .unsupported, file: file, format: format, message: message)
    }
}
