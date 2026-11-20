#if canImport(AVFoundation)
import AVFoundation
import Foundation
import Testing
import DeckieDecode
import DeckieTestSupport

/// The Mac's Desk makes the print that finds copies from a song read with AVFoundation; Desk's own decoder reads the
/// same AIFF to analyse it. For a music CD's songs (16-bit PCM AIFF, as the Mac shows them) the two must give the same
/// samples, bit for bit, so the Mac can make the print from the audio the analysis already decoded and read the disc
/// once (Nov 20, 2026). Checked here on 16-bit stereo AIFF at 44.1 kHz, loud and quiet, and on mono.
@Suite struct AppleReaderAgreementTests {
    static func avSamples(_ url: URL) throws -> (samples: [Float], channels: Int, rate: Double) {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let channels = Int(format.channelCount)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let n = Int(buffer.frameLength)
        let data = try #require(buffer.floatChannelData)
        var out = [Float](repeating: 0, count: n * channels)
        for i in 0..<n { for c in 0..<channels { out[i * channels + c] = data[c][i] } }
        return (out, channels, format.sampleRate)
    }

    @Test(arguments: [(2, Float(0.9)), (2, Float(0.05)), (1, Float(0.7))])
    func aCDsAIFFReadsTheSameBothWays(channels: Int, gain: Float) throws {
        let n = 44100 * 3
        var samples = [Float](repeating: 0, count: n * channels)
        var seed: UInt32 = 7
        for i in 0..<n {
            seed = seed &* 1664525 &+ 1013904223
            let noise = Float(Int32(bitPattern: seed)) / Float(Int32.max) * 0.1
            let v = (sin(Float(i) * 2 * .pi * 440 / 44100) + noise) * gain
            for c in 0..<channels { samples[i * channels + c] = c == 0 ? v : -v * 0.5 }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agree-\(UUID().uuidString).aiff")
        defer { try? FileManager.default.removeItem(at: url) }
        try TestTrack.aiff16(AudioBuffer(sampleRate: 44100, channelCount: channels, samples: samples)).write(to: url)
        let ours = try AudioDecoder.decode(url)
        let apple = try Self.avSamples(url)
        #expect(apple.channels == ours.channelCount && Int(apple.rate) == ours.sampleRate)
        #expect(apple.samples.count == ours.samples.count)
        #expect(apple.samples.map(\.bitPattern) == ours.samples.map(\.bitPattern))
    }
}
#endif
