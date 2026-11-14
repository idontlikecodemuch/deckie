import Foundation
import CMediaFoundation

/// Audio decoded by Windows' own Media Foundation (the decoder the decisions name for AAC and Apple Lossless in
/// `.m4a` on a PC), through the C shim `CMediaFoundation`, which opens Media Foundation at run time. Not yet used by
/// `AudioDecoder`: first measured (`MediaFoundationTests`), because an AAC file starts with 1,024 to 2,112 samples of
/// encoder lead-in, and a decoder that leaves them in gives a beat grid that is late by up to 48 ms.
public enum MediaFoundationReader {
    /// What came back, as the decoder gave it: nothing trimmed.
    public struct Raw: Sendable {
        public var buffer: AudioBuffer
        /// The time stamp of the first block, in seconds.
        public var firstTimestamp: Double
        public var blocks: Int
    }

    public enum Failure: Error, Equatable, CustomStringConvertible {
        /// Not Windows, or a Windows without media features.
        case unavailable(String)
        case failed(String)
        public var description: String {
            switch self { case .unavailable(let m), .failed(let m): return m }
        }
    }

    public static func decodeRaw(_ url: URL) throws -> Raw {
        var audio = deckie_mf_audio()
        var message = [CChar](repeating: 0, count: 256)
        let path = Array(url.path.utf16) + [0]
        let code = path.withUnsafeBufferPointer { deckie_mf_decode($0.baseAddress, &audio, &message, message.count) }
        let text = String(decoding: message.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard code == 0 else { throw code == 1 ? Failure.unavailable(text) : Failure.failed(text) }
        defer { deckie_mf_free(&audio) }
        let count = Int(audio.frames) * Int(audio.channels)
        let samples = Array(UnsafeBufferPointer(start: audio.samples, count: count))
        return Raw(buffer: AudioBuffer(sampleRate: Int(audio.sample_rate), channelCount: Int(audio.channels), samples: samples),
                   firstTimestamp: Double(audio.first_timestamp) / 1e7, blocks: Int(audio.blocks))
    }
}
