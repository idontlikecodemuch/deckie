import Foundation
import DeckieAudio
import DeckieCore

/// What went wrong before or after the model ran (ONNX Runtime's own errors are `OnnxRuntimeError`).
public enum BeatTrackerError: Error, Equatable, CustomStringConvertible {
    /// No model file at any place looked (DECKIE_BEAT_THIS_MODEL, or the checkout's core/.models).
    case modelNotFound(searched: [String])
    /// The model does not have Beat This!'s input and outputs.
    case unexpectedModel(String)

    public var description: String {
        switch self {
        case .modelNotFound(let searched):
            return "Beat This! model not found (looked at: \(searched.joined(separator: ", "))); run core/Tools/export_beat_this.py or set \(BeatTracker.modelEnvironmentVariable)"
        case .unexpectedModel(let message): return "not a Beat This! model: \(message)"
        }
    }
}

/// A piece's beats and downbeats, with the logits they came from and where the time went.
public struct BeatTrackerResult: Sendable {
    /// Beat and downbeat positions in frames (50 a second) and in seconds.
    public var beats: BeatThisBeats
    /// The network's frame-wise logits for the whole piece.
    public var logits: BeatThisLogits
    /// Seconds spent: mono and resampling, the spectrogram, the network (all chunks), the postprocessor.
    public var timing: (resampling: Double, spectrogram: Double, model: Double, postprocessing: Double)
}

/// The Beat This! beat tracker (final0 checkpoint, exported to ONNX by core/Tools/export_beat_this.py) on ONNX
/// Runtime: audio in, beat and downbeat times out, as the `beat_this` package's `Audio2Beats` computes them with its
/// "minimal" postprocessor (no DBN).
///
/// Steps: the channels are averaged (`AudioBuffer.mono`); audio at 22,050 Hz is used as it is, 44,100 Hz is halved
/// by `Decimator.halve` and any other rate is brought to 22,050 Hz by `Resampler`, which are soxr's "HQ" filter, as
/// the package's `soxr.resample` is (between 44.1 and 22.05 kHz the very same filter; from other rates soxr adds an
/// interpolating stage that `Resampler` does not, so there the audio agrees to about -60 dB, measured on noise by
/// the resampler's tests). Then `BeatThisFrontEnd` makes the spectrogram, `BeatThisChunking` runs the network over 1,500-frame chunks, and `BeatThisPostProcessor` picks the
/// peaks. Nothing touches the network: the model and ONNX Runtime are files on disk.
public final class BeatTracker: @unchecked Sendable {
    public static let modelEnvironmentVariable = "DECKIE_BEAT_THIS_MODEL"
    public static let modelFileName = "beat_this_final0.onnx"

    /// Where the model is looked for: DECKIE_BEAT_THIS_MODEL alone if it is set, else core/.models in the checkout
    /// this was built from (where the export script writes it).
    public static func modelCandidates() -> [String] {
        if let path = ProcessInfo.processInfo.environment[modelEnvironmentVariable], !path.isEmpty { return [path] }
        return [OnnxRuntime.coreFolder.appendingPathComponent(".models").appendingPathComponent(modelFileName).path]
    }

    /// The first candidate that exists, or nil.
    public static func locateModel() -> String? {
        modelCandidates().first { FileManager.default.fileExists(atPath: $0) }
    }

    public let session: OnnxSession
    public let frontEnd = BeatThisFrontEnd()

    /// When a piece's chunks give the arena's unused memory back (with `session.options.arenaShrinkage` on; off,
    /// never). Only memory moves; the logits are the same either way.
    public enum ArenaShrinking: Sendable, Equatable {
        /// After every chunk: each chunk takes its working memory (about 0.7 GB) from the system again.
        case everyChunk
        /// After a piece's first chunk and its last. The first run of a chunk shape allocates value by value and leaves
        /// the arena in pieces that cannot hold the one planned block the later runs ask for (ONNX Runtime's memory
        /// pattern), so without a shrink there the arena holds both, about twice what a chunk needs. After it, the
        /// planned block is kept from chunk to chunk and given back when the piece is done.
        case firstAndLastChunk
    }

    public let arenaShrinking: ArenaShrinking

    /// Loads the model (from `modelPath`, or the first of `modelCandidates()` that exists) into ONNX Runtime
    /// (`runtime`, or `OnnxRuntime.load()`).
    public init(modelPath: String? = nil, runtime: OnnxRuntime? = nil,
                options: OnnxRuntime.SessionOptions = OnnxRuntime.SessionOptions(),
                arenaShrinking: ArenaShrinking = .firstAndLastChunk) throws {
        self.arenaShrinking = arenaShrinking
        let path: String
        if let modelPath {
            path = modelPath
        } else {
            guard let found = Self.locateModel() else { throw BeatTrackerError.modelNotFound(searched: Self.modelCandidates()) }
            path = found
        }
        let rt = try runtime ?? OnnxRuntime.load()
        session = try rt.makeSession(modelPath: path, options: options)
        guard session.inputNames == ["spect"], Set(session.outputNames) == ["beat", "downbeat"] else {
            throw BeatTrackerError.unexpectedModel("inputs \(session.inputNames), outputs \(session.outputNames); expected spect in, beat and downbeat out")
        }
    }

    /// The network's logits for one chunk of `rows` spectrogram frames (`input`: rows x 128 values).
    /// `shrinkArena` as `OnnxSession.run` takes it (nil: the session's setting).
    public func chunkLogits(_ input: [Float], rows: Int, shrinkArena: Bool? = nil) throws -> BeatThisLogits {
        let out = try session.run(["spect": OnnxTensor(shape: [1, rows, BeatThisSpectrogram.bands], values: input)],
                                  shrinkArena: shrinkArena)
        guard let beat = out["beat"], let downbeat = out["downbeat"], beat.values.count == rows,
              downbeat.values.count == rows else {
            throw BeatTrackerError.unexpectedModel("expected \(rows) beat and downbeat logits")
        }
        return BeatThisLogits(beat: beat.values, downbeat: downbeat.values)
    }

    /// The logits for a whole spectrogram, chunk by chunk.
    public func logits(_ spectrogram: BeatThisSpectrogram) throws -> BeatThisLogits {
        let count = BeatThisChunking.split(frames: spectrogram.frames).count
        let shrinking = session.options.arenaShrinkage
        var index = 0
        return try BeatThisChunking.run(spectrogram) { input, rows in
            defer { index += 1 }
            let shrink = shrinking && (arenaShrinking == .everyChunk || index == 0 || index == count - 1)
            return try chunkLogits(input, rows: rows, shrinkArena: shrink)
        }
    }

    /// Mono audio at 22,050 Hz, from mono audio at `sampleRate`.
    public static func modelRateSignal(_ mono: [Float], sampleRate: Int) -> [Float] {
        switch sampleRate {
        case BeatThisFrontEnd.sampleRate: return mono
        case 2 * BeatThisFrontEnd.sampleRate: return Decimator.halve(mono)
        default: return Resampler(from: sampleRate, to: BeatThisFrontEnd.sampleRate).process(mono)
        }
    }

    /// Beats and downbeats of `audio`.
    public func track(_ audio: AudioBuffer) throws -> BeatTrackerResult {
        let t0 = Date()
        let y = Self.modelRateSignal(audio.mono(), sampleRate: audio.sampleRate)
        let t1 = Date()
        let spectrogram = frontEnd.spectrogram(y)
        let t2 = Date()
        let logits = try logits(spectrogram)
        let t3 = Date()
        let beats = BeatThisPostProcessor.minimal(logits)
        let t4 = Date()
        return BeatTrackerResult(beats: beats, logits: logits,
                                 timing: (t1.timeIntervalSince(t0), t2.timeIntervalSince(t1), t3.timeIntervalSince(t2),
                                          t4.timeIntervalSince(t3)))
    }
}
