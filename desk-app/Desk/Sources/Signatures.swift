import Foundation
import AVFoundation
import ShazamKit

/// Recognition signatures on the Mac: the audio file is read with AVFoundation and streamed into ShazamKit's
/// signature generator. Nothing but the signature (irreversible by Apple's statement) is kept.
enum Signatures {
    static func signature(of url: URL) throws -> Data {
        let file = try AVAudioFile(forReading: url)
        let gen = SHSignatureGenerator()
        let format = file.processingFormat
        let frames: AVAudioFrameCount = 44100 * 4
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw NSError(domain: "Signatures", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not make an audio buffer"])
        }
        while true {
            try file.read(into: buffer, frameCount: frames)
            if buffer.frameLength == 0 { break }
            try gen.append(buffer, at: nil)
            if buffer.frameLength < frames { break }
        }
        return try gen.signature().dataRepresentation
    }

    static func utcNow() -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }
}
