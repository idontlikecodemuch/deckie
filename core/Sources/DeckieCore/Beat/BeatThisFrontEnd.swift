import Foundation

/// A log-mel spectrogram as Beat This! reads it: `frames` rows of 128 float32 values, row by row
/// (`values[t * 128 + band]`), band 0 the lowest; the layout of the model's input (1 x frames x 128).
public struct BeatThisSpectrogram: Sendable, Equatable {
    public static let bands = 128
    public let frames: Int
    public var values: [Float]

    public init(frames: Int, values: [Float]) {
        precondition(values.count == frames * Self.bands, "\(values.count) values for \(frames) frames of \(Self.bands)")
        self.frames = frames
        self.values = values
    }

    public subscript(t: Int, band: Int) -> Float { values[t * Self.bands + band] }

    /// The 128 values of frame `t`.
    public func frame(_ t: Int) -> ArraySlice<Float> { values[(t * Self.bands)..<((t + 1) * Self.bands)] }
}

/// The front end of the Beat This! beat tracker (Foscarin, Schlüter and Widmer, ISMIR 2024; the `beat_this` package,
/// MIT): the spectrogram its network reads, computed as the package's `LogMelSpect` computes it (beat_this 1.1.0 on
/// torchaudio 2.11), from mono audio at 22,050 Hz:
///
///   1. the STFT with a 1,024-sample periodic Hann window every 441 samples (50 frames a second), centred frames
///      with the signal mirrored at its ends (torch's reflect padding): 1 + n / 441 frames for n samples;
///   2. the magnitude of each bin, divided by sqrt(1024) (torchaudio's `normalized="frame_length"`);
///   3. 128 triangular mel filters on the Slaney scale from 30 Hz to 11 kHz, unnormalised (`TorchaudioMelFilterBank`);
///   4. log(1 + 1000 x each mel value), rounded to float32.
///
/// The package computes all of this in float32; here everything up to the final rounding is double precision, which
/// puts the values within about 1e-6 of the package's (Tests: BeatThisTests measure it). Frames are computed one at
/// a time, so four minutes never need the linear spectrogram in memory.
public struct BeatThisFrontEnd: Sendable {
    public static let sampleRate = 22050
    public static let fftSize = 1024
    public static let hop = 441
    public static let framesPerSecond = 50
    public static let fMin = 30.0
    public static let fMax = 11000.0
    public static let logMultiplier = 1000.0

    public let stft: STFT
    public let filterBank: TorchaudioMelFilterBank

    public init() {
        stft = STFT(fftSize: Self.fftSize, hop: Self.hop, padding: .reflect)
        filterBank = TorchaudioMelFilterBank(sampleRate: Self.sampleRate, fftSize: Self.fftSize, melCount: BeatThisSpectrogram.bands,
                                   fMin: Self.fMin, fMax: Self.fMax)
    }

    /// Frames for `samples` samples at 22,050 Hz: 1 + samples / 441.
    public func frameCount(samples: Int) -> Int { stft.frameCount(samples: samples) }

    /// The spectrogram of mono audio at 22,050 Hz.
    public func spectrogram(_ y: [Float]) -> BeatThisSpectrogram {
        let frames = frameCount(samples: y.count), bands = BeatThisSpectrogram.bands, bins = stft.bins
        var out = [Float](repeating: 0, count: frames * bands)
        let scale = 1.0 / Double(Self.fftSize).squareRoot(), mult = Self.logMultiplier
        let magnitude = UnsafeMutableBufferPointer<Double>.allocate(capacity: bins)
        let mel = UnsafeMutableBufferPointer<Double>.allocate(capacity: bands)
        defer { magnitude.deallocate(); mel.deallocate() }
        out.withUnsafeMutableBufferPointer { ob in
            stft.forEachPowerFrame(y) { t, power in
                var k = 0
                while k < bins { magnitude[k] = power[k].squareRoot() * scale; k += 1 }
                filterBank.apply(UnsafeBufferPointer(magnitude), into: mel)
                let row = t * bands
                var m = 0
                while m < bands { ob[row + m] = Float(log1p(mult * mel[m])); m += 1 }
            }
        }
        return BeatThisSpectrogram(frames: frames, values: out)
    }
}
