import Foundation

/// core/Tests/DeckieCoreTests/Fixtures/beat_this.json, written by Tools/make_beat_fixtures.py from the Beat This!
/// package itself (beat_this 1.1.0 on torch, final0 checkpoint): its mel filter bank, its spectrogram of synthesised
/// drums, its chunking, its minimal postprocessor, and its logits and beats for whole synthesised pieces.
public struct BeatThisFixture: Decodable, Sendable {
    public struct SynthCheck: Decodable, Sendable {
        /// The exactly rounded sum of the float32 samples.
        public var sum: Double
        public var every1000th: [Float]
        enum CodingKeys: String, CodingKey { case sum, every1000th = "every_1000th" }
    }

    public struct Filter: Decodable, Sendable {
        public var first: Int
        /// torchaudio's float32 weights (the JSON holds their shortest decimal form, so read them as Float).
        public var weights: [Float]
    }

    public struct FrontEndSignal: Decodable, Sendable {
        public var name: String
        public var samples: Int
        public var seed: UInt64
        public var beats: [DrumPattern.Beat]
        public var synth: SynthCheck
        public var frames: Int
        public var index: [Int]
        public var values: [[Float]]
        /// The same frames from the package's steps run in float64.
        public var values64: [[Double]]
        public var frameSums: [Double]
        public var max: Float
        enum CodingKeys: String, CodingKey {
            case name, samples, seed, beats, synth, frames, index, values, values64, max
            case frameSums = "frame_sums"
        }
    }

    public struct ChunkCase: Decodable, Sendable {
        public var frames: Int
        public var starts: [Int]
        /// [left pad, right pad, rows] per chunk.
        public var pads: [[Int]]
        /// [first frame, end frame, start of the chunk those frames came from].
        public var segments: [[Int]]
    }

    public struct PostCase: Decodable, Sendable {
        public var name: String
        public var beat: [Float]
        public var downbeat: [Float]
        public var beats: [Double]
        public var downbeats: [Double]
        public var beatFrames: [Double]
        public var downbeatFrames: [Double]
        enum CodingKeys: String, CodingKey {
            case name, beat, downbeat, beats, downbeats
            case beatFrames = "beat_frames", downbeatFrames = "downbeat_frames"
        }
    }

    public struct Piece: Decodable, Sendable {
        public var name: String
        public var rate: Int
        public var seconds: Int
        public var seed: UInt64
        public var trueBeats: [DrumPattern.Beat]
        public var synth: SynthCheck
        public var frames: Int
        public var beatLogits: [Float]
        public var downbeatLogits: [Float]
        public var beats: [Double]
        public var downbeats: [Double]
        public var beatFrames: [Double]
        public var downbeatFrames: [Double]
        enum CodingKeys: String, CodingKey {
            case name, rate, seconds, seed, synth, frames, beats, downbeats
            case trueBeats = "true_beats", beatLogits = "beat_logits", downbeatLogits = "downbeat_logits"
            case beatFrames = "beat_frames", downbeatFrames = "downbeat_frames"
        }

        /// The piece's audio, synthesised again.
        public func render() -> [Float] { DrumPattern.render(rate: rate, samples: seconds * rate, beats: trueBeats, seed: seed) }
    }

    public var versions: [String: String]
    public var filterbank: [Filter]
    public var frontend: [FrontEndSignal]
    public var chunking: [ChunkCase]
    public var postprocessor: [PostCase]
    public var pieces: [Piece]

    /// core/Tests/DeckieCoreTests/Fixtures/beat_this.json, found from this file's path.
    public static let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("DeckieCoreTests/Fixtures/beat_this.json")

    public static let shared: BeatThisFixture = {
        do {
            return try JSONDecoder().decode(BeatThisFixture.self, from: Data(contentsOf: url))
        } catch {
            fatalError("could not read \(url.path): \(error)")
        }
    }()

    /// Whether a synthesised signal is the fixture's: every 1,000th sample identical, and the sum within 1e-9 of the
    /// sum of the samples' sizes (room for the rounding of adding them in order).
    public static func matches(_ y: [Float], _ check: SynthCheck) -> Bool {
        let every = stride(from: 0, to: y.count, by: 1000).map { y[$0] }
        let sum = y.reduce(0.0) { $0 + Double($1) }, size = y.reduce(0.0) { $0 + abs(Double($1)) }
        return every == check.every1000th && abs(sum - check.sum) <= 1e-9 * max(1, size)
    }
}

extension DrumPattern.Beat: Decodable {
    /// From the fixture's [time, accent].
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        self.init(time: try c.decode(Double.self), accent: try c.decode(Bool.self))
    }
}
