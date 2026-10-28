import Foundation

/// Analysis windows, computed as scipy computes them.
public enum Window {
    /// `scipy.signal.get_window("hann", n, fftbins=True)`, the window `librosa.stft` uses by default: the periodic
    /// Hann window w[k] = 0.5 - 0.5 cos(2 pi k / n), k in 0..<n. scipy builds it as the symmetric window of n + 1
    /// points less its last, with the angles from `numpy.linspace(-pi, pi, n + 1)` (k (2 pi / n) - pi) and
    /// w = 0.5 + 0.5 cos(angle); the same operations are done here, so the values agree to the last bit.
    public static func hann(_ n: Int) -> [Double] {
        precondition(n >= 1)
        let step = (Double.pi - -Double.pi) / Double(n)
        return (0..<n).map { k in 0.5 + 0.5 * cos(Double(k) * step + -Double.pi) }
    }
}

/// The short-time Fourier transform as `librosa.stft(y, n_fft=fftSize, hop_length=hop)` computes it with its defaults
/// (librosa 1.0.0): the periodic Hann window over the whole frame, centred frames, and zero padding. Frame t covers
/// samples t hop - fftSize / 2 ..< t hop + fftSize / 2, with zeros where that runs off either end, so there are
/// 1 + n / hop frames for n samples (integer division). librosa pads the head and the tail separately to avoid
/// copying the signal; the frames are the same as padding the whole signal with fftSize / 2 zeros on each side.
///
/// Only the power (magnitude squared, librosa's `power=2`) is produced here, frame by frame, so four minutes of audio
/// never need the whole spectrogram in memory. Everything is in double precision. (librosa, given float32 audio as
/// the lab gives it, multiplies by the float64 window, transforms in float64 and then stores the result as complex64,
/// so its spectrogram carries single-precision rounding, about 1e-7 relative, that this one does not.)
public struct STFT: Sendable {
    public let fftSize: Int
    public let hop: Int
    public let window: [Double]
    let fft: RealFFT

    public init(fftSize: Int, hop: Int) {
        precondition(hop >= 1, "hop \(hop)")
        self.fftSize = fftSize
        self.hop = hop
        window = Window.hann(fftSize)
        fft = RealFFT(size: fftSize)
    }

    /// Frequency bins per frame: fftSize / 2 + 1, from 0 Hz to the Nyquist frequency.
    public var bins: Int { fftSize / 2 + 1 }

    /// Frames for a signal of `samples` samples: 1 + samples / hop.
    public func frameCount(samples: Int) -> Int { 1 + samples / hop }

    /// Calls `body(t, power)` for each frame t in order, with |X[k]|^2 for the bins k = 0..<bins. The buffer is
    /// reused for the next frame, so `body` must copy what it keeps.
    public func forEachPowerFrame(_ y: [Float], _ body: (_ frame: Int, _ power: UnsafeBufferPointer<Double>) -> Void) {
        y.withUnsafeBufferPointer { yb in
            window.withUnsafeBufferPointer { wb in
                let n = yb.count, size = fftSize
                run(samples: n, fill: { start, x in
                    let w = wb.baseAddress!
                    var j = 0
                    if start >= 0 && start + size <= n {
                        let s = yb.baseAddress! + start
                        while j < size { x[j] = Double(s[j]) * w[j]; j += 1 }
                        return
                    }
                    while j < size {
                        let i = start + j
                        x[j] = i >= 0 && i < n ? Double(yb[i]) * w[j] : 0
                        j += 1
                    }
                }, body)
            }
        }
    }

    /// `forEachPowerFrame` for a signal held in double precision.
    public func forEachPowerFrame(_ y: [Double], _ body: (_ frame: Int, _ power: UnsafeBufferPointer<Double>) -> Void) {
        y.withUnsafeBufferPointer { yb in
            window.withUnsafeBufferPointer { wb in
                let n = yb.count, size = fftSize
                run(samples: n, fill: { start, x in
                    let w = wb.baseAddress!
                    var j = 0
                    if start >= 0 && start + size <= n {
                        let s = yb.baseAddress! + start
                        while j < size { x[j] = s[j] * w[j]; j += 1 }
                        return
                    }
                    while j < size {
                        let i = start + j
                        x[j] = i >= 0 && i < n ? yb[i] * w[j] : 0
                        j += 1
                    }
                }, body)
            }
        }
    }

    /// The whole power spectrogram, frames of `bins` values: for tests and short signals.
    public func powerSpectrogram(_ y: [Double]) -> [[Double]] {
        var out: [[Double]] = []
        out.reserveCapacity(frameCount(samples: y.count))
        forEachPowerFrame(y) { _, p in out.append(Array(p)) }
        return out
    }

    /// Runs the frames: `fill(start, x)` writes the windowed frame that starts at sample `start` (negative for the
    /// first frames, past the end for the last, where the signal counts as zero) into x.
    private func run(samples n: Int, fill: (Int, UnsafeMutablePointer<Double>) -> Void,
                     _ body: (Int, UnsafeBufferPointer<Double>) -> Void) {
        let frames = frameCount(samples: n), size = fftSize, b = bins
        let x = UnsafeMutablePointer<Double>.allocate(capacity: size)
        let re = UnsafeMutablePointer<Double>.allocate(capacity: b)
        let im = UnsafeMutablePointer<Double>.allocate(capacity: b)
        defer { x.deallocate(); re.deallocate(); im.deallocate() }
        for t in 0..<frames {
            fill(t * hop - size / 2, x)
            fft.forward(x, real: re, imag: im)
            var k = 0
            while k < b { re[k] = re[k] * re[k] + im[k] * im[k]; k += 1 }
            body(t, UnsafeBufferPointer(start: re, count: b))
        }
    }
}
