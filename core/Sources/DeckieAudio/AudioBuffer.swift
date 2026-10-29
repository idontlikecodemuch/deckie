/// Decoded audio held in memory: 32-bit float samples, full scale 1.0, channels interleaved (for stereo:
/// left, right, left, right, ...).
public struct AudioBuffer: Sendable, Equatable {
    /// Frames per second.
    public var sampleRate: Int
    /// 1 or 2: mono files stay mono; files with more channels keep their first two, as the lab does.
    public var channelCount: Int
    /// Samples per channel.
    public var frames: Int
    /// `frames * channelCount` values, interleaved.
    public var samples: [Float]

    public init(sampleRate: Int, channelCount: Int, samples: [Float]) {
        precondition(sampleRate > 0 && channelCount > 0 && samples.count % channelCount == 0)
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.frames = samples.count / channelCount
        self.samples = samples
    }

    /// Length in seconds.
    public var duration: Double { Double(frames) / Double(sampleRate) }

    /// One channel's samples, 0 for the first.
    public func channel(_ i: Int) -> [Float] {
        precondition(i >= 0 && i < channelCount, "channel \(i) of \(channelCount)")
        if channelCount == 1 { return samples }
        var out = [Float](repeating: 0, count: frames)
        for f in 0..<frames { out[f] = samples[f * channelCount + i] }
        return out
    }

    /// The mean of the channels, frame by frame, in Float like the lab's `y.mean(axis=1)` (mixer/analyze.py).
    public func mono() -> [Float] {
        if channelCount == 1 { return samples }
        var out = [Float](repeating: 0, count: frames)
        let n = Float(channelCount)
        for f in 0..<frames {
            var sum: Float = 0
            for c in 0..<channelCount { sum += samples[f * channelCount + c] }
            out[f] = sum / n
        }
        return out
    }
}
