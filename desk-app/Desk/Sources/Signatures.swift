import Foundation
import AVFoundation
import ShazamKit
import DeckieCore

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
        // Stop at the file's end by position: a read at the very end of an MP3 whose length is a whole number of
        // buffers fails with an empty error instead of returning no frames (three library tracks of exactly 192,
        // 200 and 224 s, Oct 30, 2026), and the signature was already complete.
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: frames)
            if buffer.frameLength == 0 { break }
            try gen.append(buffer, at: nil)
        }
        return try gen.signature().dataRepresentation
    }

    /// The print that finds copies of the same recording (`RecordingPrint`, D24), from the file's audio read with
    /// AVFoundation and mixed to mono. Nothing but the print is kept, and it stays on this Mac (not in the crate).
    static func recordingPrint(of url: URL) throws -> RecordingPrint {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames: AVAudioFrameCount = 44100 * 4
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw NSError(domain: "Signatures", code: 1, userInfo: [NSLocalizedDescriptionKey: "could not make an audio buffer"])
        }
        let channels = Int(format.channelCount)
        var mono: [Float] = []
        mono.reserveCapacity(Int(file.length))
        // Stop at the file's end by position, as `signature(of:)` does.
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: frames)
            let n = Int(buffer.frameLength)
            if n == 0 { break }
            guard let data = buffer.floatChannelData else { break }
            let g = 1 / Float(max(1, channels))
            for i in 0..<n {
                var sum: Float = 0
                for c in 0..<channels { sum += data[c][i] }
                mono.append(sum * g)
            }
        }
        return RecordingPrint(mono: mono, sampleRate: Int(format.sampleRate.rounded()))
    }

    static func utcNow() -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: Date())
    }
}
