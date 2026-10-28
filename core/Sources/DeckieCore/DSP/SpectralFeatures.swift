import Foundation

/// The lab's spectral features (mixer/analyze.py, "spectral features (22.05k)"), from mono audio at 22,050 Hz:
///
///   mel        `librosa.feature.melspectrogram(y, sr=22050, n_fft=2048, hop_length=512, n_mels=64)`: power, 64 bands
///   logMel     `librosa.power_to_db(mel)`: decibels, floored 80 dB below the loudest value
///   mfcc       `librosa.feature.mfcc(S=logmel, n_mfcc=13)`
///   rms        `librosa.feature.rms(y, frame_length=2048, hop_length=512)`
///   onsetEnvelope  `librosa.onset.onset_strength(S=logmel, sr=22050, hop_length=512)`
///
/// all on the same frames: frame t is centred on sample 512 t (43.07 frames a second), 1 + n / 512 of them. These
/// feed the structure novelty (`FooteNovelty`), the onset density (`OnsetDensity`) and the onset pattern
/// (`OnsetPattern`). Everything is double precision; the lab's are float32 (see each piece for what that changes).
/// The lab resamples its 44.1 kHz mono mix to 22,050 Hz with soxr first; this takes audio already at 22,050 Hz.
public struct SpectralFeatures: Sendable {
    public static let sampleRate = 22050
    public static let hop = 512
    public static let fftSize = 2048
    public static let melBands = 64
    public static let mfccCount = 13
    /// 22,050 / 512 = 43.06640625, exactly.
    public static let framesPerSecond = Double(sampleRate) / Double(hop)

    public let mel: FrameMatrix
    public let logMel: FrameMatrix
    public let mfcc: FrameMatrix
    public let rms: [Double]
    public let onsetEnvelope: [Double]

    /// Frames: 1 + samples / 512.
    public var frames: Int { mel.frames }

    /// The features of mono float audio at 22,050 Hz, the lab's input type.
    public init(_ y: [Float]) {
        self.init(mel: LibrosaMel.spectrogram(y, bank: .lab, hop: SpectralFeatures.hop),
                  rms: RMS.compute(y, frameLength: SpectralFeatures.fftSize, hop: SpectralFeatures.hop))
    }

    /// The features of mono audio at 22,050 Hz held in double precision.
    public init(_ y: [Double]) {
        self.init(mel: LibrosaMel.spectrogram(y, bank: .lab, hop: SpectralFeatures.hop),
                  rms: RMS.compute(y, frameLength: SpectralFeatures.fftSize, hop: SpectralFeatures.hop))
    }

    init(mel: FrameMatrix, rms: [Double]) {
        precondition(rms.count == mel.frames)
        self.mel = mel
        logMel = LibrosaMel.powerToDb(mel)
        mfcc = MFCC.compute(logMel: logMel, count: SpectralFeatures.mfccCount)
        self.rms = rms
        onsetEnvelope = OnsetStrength.compute(logMel: logMel, lag: 1, fftSize: SpectralFeatures.fftSize,
                                              hop: SpectralFeatures.hop)
    }

    /// The structure novelty and its peaks on the bar grid (`FooteNovelty`); `.peaks` goes to `Phrase(peaks:)`.
    public func novelty(grid: BarGrid) -> FooteNovelty {
        FooteNovelty(mfcc: mfcc, rms: rms, grid: grid, framesPerSecond: SpectralFeatures.framesPerSecond)
    }

    /// librosa's onset times in seconds (`OnsetDetect.times`).
    public func onsetTimes() -> [Double] {
        OnsetDetect.times(envelope: onsetEnvelope, sampleRate: SpectralFeatures.sampleRate, hop: SpectralFeatures.hop)
    }

    /// The per-bar onset density, onsets per beat (`OnsetDensity`).
    public func onsetDensity(grid: BarGrid) -> [Double] {
        OnsetDensity.perBar(onsetTimes: onsetTimes(), barTimes: grid.barTimes)
    }

    /// The 16-value onset pattern (`OnsetPattern`), given the per-bar loudness (`KWeighted.loudness` over each bar).
    public func onsetPattern(grid: BarGrid, barLoudness: [Double]) -> [Double] {
        OnsetPattern.pattern(onsetEnvelope: onsetEnvelope, grid: grid, barLoudness: barLoudness,
                             framesPerSecond: SpectralFeatures.framesPerSecond)
    }
}
