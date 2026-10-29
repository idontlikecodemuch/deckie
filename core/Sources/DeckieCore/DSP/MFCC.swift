import Foundation

/// Mel-frequency cepstral coefficients as the lab computes them: `librosa.feature.mfcc(S=logmel, n_mfcc=13)` on the
/// log-mel spectrogram (librosa 1.0.0, mixer/analyze.py). librosa applies `scipy.fft.dct(S, axis=-2, type=2,
/// norm="ortho")` down each frame's bands and keeps the first `n_mfcc` coefficients (no liftering by default).
public enum MFCC {
    /// The orthonormal DCT-II as scipy computes it (type 2, norm="ortho"), as a `count` x `size` matrix, row k first:
    ///
    ///   X_k = s_k sum over n = 0 ..< N of x_n cos(pi k (2n + 1) / (2N)),   s_0 = sqrt(1 / N), s_k = sqrt(2 / N)
    ///
    /// (scipy writes it 2 sum x_n cos(...) times sqrt(1 / (4N)) for k = 0 and sqrt(1 / (2N)) otherwise, the same
    /// thing). The angle is reduced to k (2n + 1) mod 4N before the cosine, so every entry is within an ulp or so.
    public static func dctMatrix(count: Int, size n: Int) -> [Double] {
        precondition(count >= 0 && count <= n && n >= 1)
        var m = [Double](repeating: 0, count: count * n)
        let s0 = (1.0 / Double(n)).squareRoot(), sk = (2.0 / Double(n)).squareRoot()
        for k in 0..<count {
            let s = k == 0 ? s0 : sk
            for j in 0..<n {
                let q = (k * (2 * j + 1)) % (4 * n)
                m[k * n + j] = s * cos(Double.pi * Double(q) / Double(2 * n))
            }
        }
        return m
    }

    /// `librosa.feature.mfcc(S=logMel, n_mfcc=count)`: the first `count` orthonormal DCT-II coefficients of each frame
    /// of the log-mel spectrogram (`LibrosaMel.powerToDb` of `LibrosaMel.spectrogram`). In double precision; the lab's
    /// log-mel is float32, so scipy ran its single-precision DCT there.
    public static func compute(logMel: FrameMatrix, count: Int = 13) -> FrameMatrix {
        let n = logMel.rows
        let d = dctMatrix(count: count, size: n)
        var out = [Double](repeating: 0, count: logMel.frames * count)
        d.withUnsafeBufferPointer { db in
            logMel.values.withUnsafeBufferPointer { xb in
                out.withUnsafeMutableBufferPointer { ob in
                    var t = 0
                    while t < logMel.frames {
                        let x = xb.baseAddress! + t * n
                        var k = 0
                        while k < count {
                            let row = db.baseAddress! + k * n
                            var s = 0.0, j = 0
                            while j < n { s += row[j] * x[j]; j += 1 }
                            ob[t * count + k] = s
                            k += 1
                        }
                        t += 1
                    }
                }
            }
        }
        return FrameMatrix(frames: logMel.frames, rows: count, values: out)
    }
}
