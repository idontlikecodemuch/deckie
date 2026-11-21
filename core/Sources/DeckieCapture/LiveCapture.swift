import Foundation

/// How loud the input is, over the last stretch of sound (a fifth of a second of samples, counted, not timed).
public struct SoundLevel: Sendable, Equatable {
    /// The loudest sample, in dB below full scale (0 is full scale; -120 for digital silence).
    public var peakDB: Double
    /// The average power, in dB below full scale.
    public var rmsDB: Double
    /// A meter's position from 0 to 1: -60 dB to 0 dB of the average power, on a straight scale of dB.
    public var meter: Double
    /// Samples at or above full scale in this stretch (the input clipping: too loud, or its gain too high).
    public var clipped: Int
    /// True when the input has given nothing but exact zeros for `LiveCapture.silentAfter` seconds or more: no sound
    /// is arriving at all (on Windows, the privacy switch for microphones gives this; on a Mac, a refused permission).
    public var silent: Bool
    /// Frames heard since the start, at `rate`.
    public var frames: Int
    public var rate: Int
    /// Seconds heard since the start, by the samples counted.
    public var seconds: Double { rate > 0 ? Double(frames) / Double(rate) : 0 }
}

/// A sound source with its samples counted and its level measured: each block goes on to `sound` (on the source's
/// thread) and a level goes to `level` about `levelsPerSecond` times a second of sound, on a queue of its own so a
/// slow reader never holds the sound up. `ended` is the source's, passed on.
public final class LiveCapture: @unchecked Sendable {
    public let source: SoundSource
    public static let levelsPerSecond = 5
    /// Seconds of nothing but zeros before the level says `silent`.
    public static let silentAfter = 3.0
    /// What counts as full scale for `clipped` (a float input can pass 1.0; an integer one stops just under it).
    public static let fullScale: Float = 0.999

    private let lock = NSLock()
    private let levelQueue = DispatchQueue(label: "deckie.capture.level")
    private var frames = 0
    private var stretch = 0
    private var peak: Float = 0
    private var power: Double = 0
    private var clipped = 0
    private var zeros = 0
    public private(set) var format: SoundFormat?

    public init(_ source: SoundSource) { self.source = source }

    /// Frames heard since `start`.
    public var framesHeard: Int { lock.lock(); defer { lock.unlock() }; return frames }

    @discardableResult
    public func start(sound: @escaping @Sendable ([Float], SoundFormat) -> Void,
                      level: @escaping @Sendable (SoundLevel) -> Void,
                      ended: @escaping @Sendable (CaptureError) -> Void) throws -> SoundFormat {
        lock.lock(); frames = 0; stretch = 0; peak = 0; power = 0; clipped = 0; zeros = 0; lock.unlock()
        let queue = levelQueue
        let f = try source.start(sound: { [weak self] samples, format in
            guard let self else { return }
            if let l = self.measure(samples, format) { queue.async { for x in l { level(x) } } }
            sound(samples, format)
        }, ended: ended)
        lock.lock(); format = f; lock.unlock()
        return f
    }

    public func stop() { source.stop() }

    /// Counts and measures one block; the levels completed in it.
    func measure(_ samples: [Float], _ format: SoundFormat) -> [SoundLevel]? {
        let ch = max(1, format.channels)
        let every = max(1, format.rate / Self.levelsPerSecond)
        lock.lock(); defer { lock.unlock() }
        var out: [SoundLevel] = []
        var i = 0
        let n = samples.count / ch
        while i < n {
            let take = min(n - i, every - stretch)
            for f in i..<(i + take) {
                var allZero = true
                for c in 0..<ch {
                    let s = samples[f * ch + c]
                    let a = abs(s)
                    if a > peak { peak = a }
                    power += Double(s) * Double(s)
                    if a >= Self.fullScale { clipped += 1 }
                    if s != 0 { allZero = false }
                }
                zeros = allZero ? zeros + 1 : 0
            }
            i += take; stretch += take; frames += take
            if stretch >= every {
                let rms = (power / Double(stretch * ch)).squareRoot()
                func db(_ x: Double) -> Double { x > 1e-6 ? 20 * log10(x) : -120 }
                let rmsDB = db(rms)
                out.append(SoundLevel(peakDB: db(Double(peak)), rmsDB: rmsDB, meter: max(0, min(1, (rmsDB + 60) / 60)),
                                      clipped: clipped, silent: Double(zeros) >= Self.silentAfter * Double(format.rate),
                                      frames: frames, rate: format.rate))
                stretch = 0; peak = 0; power = 0; clipped = 0
            }
        }
        return out.isEmpty ? nil : out
    }

    /// Waits until every level measured so far has been handed on (tests).
    public func flushLevels() { levelQueue.sync {} }
}
