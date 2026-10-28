import Foundation
import DeckieAudio

/// Where the sound starts and ends: the lab's first and last sound (mixer/analyze.py, "first / last sound (-60 dBFS)"),
/// which places bar 1 (`BarGrid`) and bounds the fade-out and the vocal mask:
///
///   thr = 10 ** (-60 / 20); fr = 441                      # 10 ms at 44.1 kHz
///   nf = n // fr
///   pk = np.abs(y[:nf * fr]).max(axis=1).reshape(nf, fr).max(axis=1)
///   loud = np.nonzero(pk > thr)[0]
///   first_sound = float(loud[0] * fr / SR) if len(loud) else 0.0
///   last_sound = float((loud[-1] + 1) * fr / SR) if len(loud) else duration
///
/// That is: 10 ms frames, each frame's peak over its samples and channels, and a frame counts as sound when its peak is
/// above -60 dBFS; the first sound is the start of the first such frame and the last sound the end of the last one.
/// A partial frame at the end is dropped. With no frame above the threshold the sound runs from 0 to the end.
/// The audio is float32, and numpy compares it with the threshold in float32 (a Python float next to a float32 array
/// takes the array's type), so the threshold is `Float(0.001)` and a sample exactly equal to it is not sound.
/// For rates other than the lab's 44.1 kHz the frame is `sampleRate / 100` samples (rounded down: 480 at 48 kHz, 220 at
/// 22.05 kHz); times are frame starts divided by the rate, in double precision, as numpy divides them. A NaN sample
/// makes its frame's peak NaN in numpy, which is not above the threshold; the same here.
public struct SoundBounds: Sendable, Equatable {
    /// The first sound in seconds: the start of the first frame above the threshold; 0 when there is none.
    public var firstSound: Double
    /// The last sound in seconds: the end of the last frame above the threshold; the duration when there is none.
    public var lastSound: Double
    /// The number of frames above the threshold (0 when the track never reaches it).
    public var loudFrames: Int

    /// The lab's threshold, -60 dBFS, as the float32 the comparison happens in.
    public static let threshold = Float(pow(10.0, -60.0 / 20.0))

    /// Samples per frame at a rate: 10 ms, rounded down (441 at 44.1 kHz).
    public static func frameLength(sampleRate: Int) -> Int { max(1, sampleRate / 100) }

    public init(firstSound: Double, lastSound: Double, loudFrames: Int) {
        self.firstSound = firstSound
        self.lastSound = lastSound
        self.loudFrames = loudFrames
    }

    /// The first and last sound of decoded audio (all its channels).
    public init(_ buffer: AudioBuffer) {
        let rate = buffer.sampleRate, ch = buffer.channelCount, n = buffer.frames
        let fr = SoundBounds.frameLength(sampleRate: rate)
        let nf = n / fr
        let thr = SoundBounds.threshold
        var first = -1, last = -1, count = 0
        buffer.samples.withUnsafeBufferPointer { sb in
            guard let base = sb.baseAddress else { return }
            var f = 0
            while f < nf {
                var p = base + f * fr * ch
                let end = p + fr * ch
                var peak: Float = 0
                var nan = false
                while p < end {
                    let v = abs(p.pointee)
                    if v > peak { peak = v } else if v.isNaN { nan = true }
                    p += 1
                }
                if !nan && peak > thr {
                    if first < 0 { first = f }
                    last = f
                    count += 1
                }
                f += 1
            }
        }
        if count > 0 {
            firstSound = Double(first * fr) / Double(rate)
            lastSound = Double((last + 1) * fr) / Double(rate)
        } else {
            firstSound = 0
            lastSound = Double(n) / Double(rate)
        }
        loudFrames = count
    }
}
