import Foundation
import DeckieAudio
import DeckieCore

/// What went wrong before or after YAMNet ran (ONNX Runtime's own errors are `OnnxRuntimeError`).
public enum YAMNetError: Error, Equatable, CustomStringConvertible {
    /// No model file at any place looked (DECKIE_YAMNET_MODEL, or the checkout's core/.models).
    case modelNotFound(searched: [String])
    /// The model does not have the exported YAMNet's input and outputs.
    case unexpectedModel(String)

    public var description: String {
        switch self {
        case .modelNotFound(let searched):
            return "YAMNet model not found (looked at: \(searched.joined(separator: ", "))); run core/Tools/fetch-vocal-models.sh or set \(YAMNet.modelEnvironmentVariable)"
        case .unexpectedModel(let message): return "not the exported YAMNet model: \(message)"
        }
    }
}

/// One of YAMNet's 521 classes: its index in the model's output, a short name in Deckie's own words, and its label, the
/// display name YAMNet's class map gives it (AudioSet's spelling, which another AudioSet model's list shares, so the
/// readings find a class by it in either: `VocalReadings`). Only the classes Deckie uses are named here: the class list
/// YAMNet was trained with comes from AudioSet's ontology, which is not copied here.
public struct YAMNetClass: Sendable, Equatable, Hashable {
    public var index: Int
    public var name: String
    public var label: String
    public init(_ index: Int, _ name: String, label: String) { self.index = index; self.name = name; self.label = label }

    // The indices and labels were read from the class list beside the model's code (tensorflow/models,
    // research/audioset/yamnet/yamnet_class_map.csv, at the commit core/Tools/fetch-vocal-models.sh pins; the file's
    // SHA-256 is cdf24d193e196d9e95912a2667051ae203e92a2ba09449218ccb40ef787c6df2). AudioSet's "Male singing" and
    // "Female singing" are not among its 521.
    public static let speech = YAMNetClass(0, "speech", label: "Speech")
    public static let singing = YAMNetClass(24, "singing", label: "Singing")
    public static let choir = YAMNetClass(25, "choir", label: "Choir")
    public static let yodelling = YAMNetClass(26, "yodelling", label: "Yodeling")
    public static let chant = YAMNetClass(27, "chant", label: "Chant")
    public static let mantra = YAMNetClass(28, "mantra", label: "Mantra")
    public static let childSinging = YAMNetClass(29, "child singing", label: "Child singing")
    public static let syntheticSinging = YAMNetClass(30, "synthetic singing", label: "Synthetic singing")
    public static let rapping = YAMNetClass(31, "rapping", label: "Rapping")
    public static let humming = YAMNetClass(32, "humming", label: "Humming")
    public static let music = YAMNetClass(132, "music", label: "Music")
    public static let musicalInstrument = YAMNetClass(133, "musical instrument", label: "Musical instrument")
    public static let vocalMusic = YAMNetClass(249, "vocal music", label: "Vocal music")
    public static let aCappella = YAMNetClass(250, "a cappella", label: "A capella")

    /// Every class named above, in index order.
    public static let named: [YAMNetClass] = [.speech, .singing, .choir, .yodelling, .chant, .mantra, .childSinging,
                                              .syntheticSinging, .rapping, .humming, .music, .musicalInstrument,
                                              .vocalMusic, .aCappella]
}

/// YAMNet's output for a run of patches: 521 class scores (0 to 1, after the network's sigmoid) and the 1,024-value
/// embedding before the classifier, per patch.
public struct YAMNetPatches: Sendable, Equatable {
    public static let classes = 521
    public static let embeddingSize = 1024
    public let count: Int
    /// `count` x 521, patch by patch.
    public let scores: [Float]
    /// `count` x 1024, patch by patch.
    public let embeddings: [Float]

    public init(count: Int, scores: [Float], embeddings: [Float]) {
        precondition(scores.count == count * Self.classes && embeddings.count == count * Self.embeddingSize)
        self.count = count
        self.scores = scores
        self.embeddings = embeddings
    }

    /// Patch `k`'s score for `cls`.
    public func score(_ k: Int, _ cls: YAMNetClass) -> Float { scores[k * Self.classes + cls.index] }

    /// Every patch's score for `cls`.
    public func scores(_ cls: YAMNetClass) -> [Double] { (0..<count).map { Double(score($0, cls)) } }

    /// The 521 columns' names as the readings see them: the label of each class `YAMNetClass` names, empty for the
    /// others.
    public static let classNames: [String] = {
        var names = [String](repeating: "", count: classes)
        for c in YAMNetClass.named { names[c.index] = c.label }
        return names
    }()

    /// The scores as a class-score matrix with `classNames` (the same storage, not a copy).
    public var classScores: ClassScoreMatrix { ClassScoreMatrix(patches: count, names: Self.classNames, scores: scores) }

    /// Patch `k`'s embedding.
    public func embedding(_ k: Int) -> ArraySlice<Float> {
        embeddings[(k * Self.embeddingSize)..<((k + 1) * Self.embeddingSize)]
    }

    /// The embeddings averaged over the patches, then scaled to length 1 (all zeros if they average to zero).
    public func meanEmbedding() -> [Double] {
        var mean = [Double](repeating: 0, count: Self.embeddingSize)
        guard count > 0 else { return mean }
        embeddings.withUnsafeBufferPointer { e in
            for k in 0..<count {
                var j = 0
                while j < Self.embeddingSize { mean[j] += Double(e[k * Self.embeddingSize + j]); j += 1 }
            }
        }
        let norm = mean.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return norm > 0 ? mean.map { $0 / norm } : mean
    }
}

/// YAMNet's output for a piece of audio, with where the time went.
public struct YAMNetResult: Sendable {
    public var patches: YAMNetPatches
    /// Seconds spent: resampling to 16 kHz, the log-mel front end, the network (all patches).
    public var timing: (resampling: Double, frontEnd: Double, model: Double)
}

/// Google's YAMNet audio event tagger (tensorflow/models, research/audioset/yamnet; Apache 2.0; trained by Google on
/// AudioSet), exported to ONNX by core/Tools/export_yamnet.py, on ONNX Runtime: mono audio in, 521 class scores and a
/// 1,024-value embedding per 0.96 s patch out, a patch every 0.48 s.
///
/// Steps: audio at 16 kHz is used as it is, any other rate is brought to 16 kHz by `Resampler` (soxr's HQ filter, as
/// the lab resamples for its own vocal model); `YAMNetFrontEnd` pads it and cuts its log-mel spectrogram into patches;
/// the network runs on them `batchSize` at a time. Nothing touches the network: the model and ONNX Runtime are files
/// on disk.
public final class YAMNet: @unchecked Sendable {
    public static let modelEnvironmentVariable = "DECKIE_YAMNET_MODEL"
    public static let modelFileName = "yamnet.onnx"
    /// The model's name, as records give it.
    public static let modelName = "yamnet"
    /// The SHA-256 of the export recorded in DEPENDENCIES.md (core/Tools/export_yamnet.py).
    public static let recordedExportSHA256 = "96bb0dc54745dbbc95ef3f289830c94eec92a6914c4ab711a821bc8aa1c93cfd"

    /// Where the model is looked for: DECKIE_YAMNET_MODEL alone if it is set, else core/.models in the checkout this
    /// was built from (where core/Tools/fetch-vocal-models.sh writes it).
    public static func modelCandidates() -> [String] {
        if let path = ProcessInfo.processInfo.environment[modelEnvironmentVariable], !path.isEmpty { return [path] }
        return [OnnxRuntime.coreFolder.appendingPathComponent(".models").appendingPathComponent(modelFileName).path]
    }

    /// The first candidate that exists, or nil.
    public static func locateModel() -> String? {
        modelCandidates().first { FileManager.default.fileExists(atPath: $0) }
    }

    public let session: OnnxSession
    public let frontEnd = YAMNetFrontEnd()
    /// Patches per run of the network (bounds the memory a long track needs: about 25 MB of activations for 64).
    public let batchSize: Int

    /// Loads the model (from `modelPath`, or the first of `modelCandidates()` that exists) into ONNX Runtime
    /// (`runtime`, or `OnnxRuntime.load()`).
    public init(modelPath: String? = nil, runtime: OnnxRuntime? = nil,
                options: OnnxRuntime.SessionOptions = OnnxRuntime.SessionOptions(), batchSize: Int = 64) throws {
        precondition(batchSize >= 1)
        let path: String
        if let modelPath {
            path = modelPath
        } else {
            guard let found = Self.locateModel() else { throw YAMNetError.modelNotFound(searched: Self.modelCandidates()) }
            path = found
        }
        let rt = try runtime ?? OnnxRuntime.load()
        session = try rt.makeSession(modelPath: path, options: options)
        self.batchSize = batchSize
        guard session.inputNames == ["patches"], Set(session.outputNames) == ["scores", "embeddings"] else {
            throw YAMNetError.unexpectedModel("inputs \(session.inputNames), outputs \(session.outputNames); expected patches in, scores and embeddings out")
        }
    }

    /// The network on `count` patches (`values`: count x 96 x 64, as `YAMNetFrontEnd.patches` gives them).
    public func run(patches values: [Float], count: Int) throws -> YAMNetPatches {
        let size = YAMNetFrontEnd.patchFrames * YAMNetFrontEnd.bands
        precondition(values.count == count * size, "\(values.count) values for \(count) patches")
        var scores: [Float] = [], embeddings: [Float] = []
        scores.reserveCapacity(count * YAMNetPatches.classes)
        embeddings.reserveCapacity(count * YAMNetPatches.embeddingSize)
        var start = 0
        while start < count {
            let n = min(batchSize, count - start)
            let input = OnnxTensor(shape: [n, YAMNetFrontEnd.patchFrames, YAMNetFrontEnd.bands],
                                   values: Array(values[(start * size)..<((start + n) * size)]))
            let out = try session.run(["patches": input])
            guard let s = out["scores"], let e = out["embeddings"], s.values.count == n * YAMNetPatches.classes,
                  e.values.count == n * YAMNetPatches.embeddingSize else {
                throw YAMNetError.unexpectedModel("expected \(n) x \(YAMNetPatches.classes) scores and \(n) x \(YAMNetPatches.embeddingSize) embedding values")
            }
            scores += s.values
            embeddings += e.values
            start += n
        }
        return YAMNetPatches(count: count, scores: scores, embeddings: embeddings)
    }

    /// Mono audio at 16 kHz, from mono audio at `sampleRate`.
    public static func modelRateSignal(_ mono: [Float], sampleRate: Int) -> [Float] {
        sampleRate == YAMNetFrontEnd.sampleRate ? mono : Resampler(from: sampleRate, to: YAMNetFrontEnd.sampleRate).process(mono)
    }

    /// YAMNet's patches for mono audio at `sampleRate`.
    public func analyse(mono: [Float], sampleRate: Int) throws -> YAMNetResult {
        let t0 = Date()
        let y = Self.modelRateSignal(mono, sampleRate: sampleRate)
        let t1 = Date()
        let p = frontEnd.patches(y)
        let t2 = Date()
        let patches = try run(patches: p.values, count: p.count)
        let t3 = Date()
        return YAMNetResult(patches: patches, timing: (t1.timeIntervalSince(t0), t2.timeIntervalSince(t1),
                                                       t3.timeIntervalSince(t2)))
    }

    /// YAMNet's patches for `audio` (its channels averaged).
    public func analyse(_ audio: AudioBuffer) throws -> YAMNetResult {
        try analyse(mono: audio.mono(), sampleRate: audio.sampleRate)
    }
}
