import Foundation

/// Halving the sample rate, for the key estimator's 44.1 kHz input (it reads 22,050 Hz): now a call into `Resampler`
/// (44,100 to 22,050 Hz, soxr's "HQ" design), which is what the lab does (`librosa.resample(..., res_type="soxr_hq")`
/// in mixer/key_light.py's `load`).
///
/// It replaces a stopgap 65-tap half-band filter (Kaiser beta 5, -6 dB at the new Nyquist frequency, 48.5 dB down at
/// 12.1 kHz), which rolled off from 9.9 kHz and folded 11 to 12.5 kHz back into the band; the resampler is flat within
/// 1e-5 dB to 10 kHz, -6 dB at 10,549.5 Hz and at least 120 dB down from 11,025 Hz, and its output is within about
/// -115 dB of soxr's. The API is kept: `taps` is now the resampler's filter (389 taps, the centre one at `center`) and
/// `halve` its output.
public enum Decimator {
    /// The 44.1 to 22.05 kHz resampler.
    public static let resampler = Resampler(from: 44100, to: 22050)

    /// The filter, centred: `taps[m + center]` multiplies input sample 2k + m for output k (m = -center ... center).
    /// It sums to 1 (within float32 rounding).
    public static let taps: [Double] = {
        let r = resampler
        // One phase; tap j reads input 2k - leading + j. Drop the zero padding at the end.
        var h = r.coefficients.map(Double.init)
        while let last = h.last, last == 0 { h.removeLast() }
        return h
    }()

    /// The index of the centre tap in `taps` (output k is centred on input 2k).
    public static var center: Int { resampler.leading }

    /// `x` (at 44.1 kHz, say) resampled to half the rate: (count + 1) / 2 samples, sample k centred on input sample 2k,
    /// with the input taken as zero outside its ends (soxr's length, and librosa's, for a factor of 2).
    public static func halve(_ x: [Float]) -> [Float] { resampler.process(x) }
}
