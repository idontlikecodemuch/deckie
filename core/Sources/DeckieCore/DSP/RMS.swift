import Foundation

/// Root-mean-square energy per frame as the lab computes it: `librosa.feature.rms(y=y, frame_length=2048,
/// hop_length=512)` (librosa 1.0.0, mixer/analyze.py). librosa pads the signal with frame_length / 2 zeros at each
/// end (center=True, pad_mode="constant") and frames it, so frame t covers samples
/// t hop - frameLength / 2 ..< t hop + frameLength / 2, with zeros where that runs off either end; there are
/// 1 + (n + 2 (frameLength / 2) - frameLength) / hop frames (1 + n / hop for an even frame length), as many as the
/// STFT's. Each value is the square root of the frame's mean square: no window.
///
/// In double precision. librosa squares and averages in float32 by default (`dtype=np.float32`, even for float64
/// input), so its values carry about 1e-7 of relative rounding that these do not.
public enum RMS {
    public static func compute(_ y: [Float], frameLength: Int = 2048, hop: Int = 512) -> [Double] {
        compute(squares: y.map { Double($0) * Double($0) }, frameLength: frameLength, hop: hop)
    }

    public static func compute(_ y: [Double], frameLength: Int = 2048, hop: Int = 512) -> [Double] {
        compute(squares: y.map { $0 * $0 }, frameLength: frameLength, hop: hop)
    }

    static func compute(squares sq: [Double], frameLength: Int, hop: Int) -> [Double] {
        precondition(frameLength >= 1 && hop >= 1)
        let n = sq.count, half = frameLength / 2
        let frames = 1 + (n + 2 * half - frameLength) / hop
        var out = [Double](repeating: 0, count: max(frames, 0))
        sq.withUnsafeBufferPointer { s in
            var t = 0
            while t < frames {
                let start = t * hop - half
                var i = max(0, start)
                let end = min(n, start + frameLength)
                var sum = 0.0
                while i < end { sum += s[i]; i += 1 }
                out[t] = (sum / Double(frameLength)).squareRoot()
                t += 1
            }
        }
        return out
    }
}
