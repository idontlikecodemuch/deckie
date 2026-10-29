import Foundation
import DeckieAudio
import DeckieCore

/// What went wrong before or after PANNs ran (ONNX Runtime's own errors are `OnnxRuntimeError`).
public enum PANNsError: Error, Equatable, CustomStringConvertible {
    /// No model file at any place looked (DECKIE_PANNS_MODEL, or the checkout's core/.models).
    case modelNotFound(searched: [String])
    /// The model does not have the exported MobileNetV2's input and outputs.
    case unexpectedModel(String)

    public var description: String {
        switch self {
        case .modelNotFound(let searched):
            return "PANNs model not found (looked at: \(searched.joined(separator: ", "))); \(PANNs.remedy)"
        case .unexpectedModel(let message): return "not the exported PANNs model: \(message)"
        }
    }
}

/// One of the 527 classes PANNs scores: its index in the model's output and its name as the class list at the commit
/// core/Tools/fetch-panns.sh pins spells it (AudioSet's display names, which `VocalReadings` matches by). Only the
/// classes Deckie reads are named here, as for YAMNet; export_panns.py checks each against the list
/// (`NAMED_CLASSES`), and the tests against core/Tools/make_panns_fixtures.py's copy of those rows.
public struct PANNsClass: Sendable, Equatable, Hashable {
    public var index: Int
    public var name: String
    public init(_ index: Int, _ name: String) { self.index = index; self.name = name }

    public static let speech = PANNsClass(0, "Speech")
    public static let singing = PANNsClass(27, "Singing")
    public static let choir = PANNsClass(28, "Choir")
    public static let yodeling = PANNsClass(29, "Yodeling")
    public static let chant = PANNsClass(30, "Chant")
    public static let mantra = PANNsClass(31, "Mantra")
    public static let maleSinging = PANNsClass(32, "Male singing")
    public static let femaleSinging = PANNsClass(33, "Female singing")
    public static let childSinging = PANNsClass(34, "Child singing")
    public static let syntheticSinging = PANNsClass(35, "Synthetic singing")
    public static let rapping = PANNsClass(36, "Rapping")
    public static let humming = PANNsClass(37, "Humming")
    public static let music = PANNsClass(137, "Music")
    public static let musicalInstrument = PANNsClass(138, "Musical instrument")
    public static let vocalMusic = PANNsClass(254, "Vocal music")
    public static let aCappella = PANNsClass(255, "A capella")

    /// Every class named above, by index.
    public static let named: [PANNsClass] = [speech, singing, choir, yodeling, chant, mantra, maleSinging, femaleSinging,
                                             childSinging, syntheticSinging, rapping, humming, music, musicalInstrument,
                                             vocalMusic, aCappella]
}

/// PANNs' output for a run of windows: 527 class scores (0 to 1, after the network's sigmoid) and the 1,024-value
/// embedding before the classifier, per window.
public struct PANNsPatches: Sendable, Equatable {
    public static let classes = 527
    public static let embeddingSize = 1024
    public let count: Int
    /// `count` x 527, window by window.
    public let scores: [Float]
    /// `count` x 1024, window by window.
    public let embeddings: [Float]

    public init(count: Int, scores: [Float], embeddings: [Float]) {
        precondition(scores.count == count * Self.classes && embeddings.count == count * Self.embeddingSize)
        self.count = count
        self.scores = scores
        self.embeddings = embeddings
    }

    /// Window `k`'s score for `cls`.
    public func score(_ k: Int, _ cls: PANNsClass) -> Float { scores[k * Self.classes + cls.index] }

    /// Every window's score for `cls`.
    public func scores(_ cls: PANNsClass) -> [Double] { (0..<count).map { Double(score($0, cls)) } }

    /// The 527 columns' names as the readings see them: the name of each class `PANNsClass` names, empty for the
    /// others.
    public static let classNames: [String] = {
        var names = [String](repeating: "", count: classes)
        for c in PANNsClass.named { names[c.index] = c.name }
        return names
    }()

    /// The scores as a class-score matrix with `classNames` (the same storage, not a copy).
    public var classScores: ClassScoreMatrix { ClassScoreMatrix(patches: count, names: Self.classNames, scores: scores) }

    /// The embeddings averaged over the windows, then scaled to length 1 (all zeros if they average to zero).
    public func meanEmbedding() -> [Double] {
        var mean = [Double](repeating: 0, count: Self.embeddingSize)
        guard count > 0 else { return mean }
        for k in 0..<count {
            for j in 0..<Self.embeddingSize { mean[j] += Double(embeddings[k * Self.embeddingSize + j]) }
        }
        let norm = mean.reduce(0) { $0 + $1 * $1 }.squareRoot()
        return norm > 0 ? mean.map { $0 / norm } : mean
    }
}

/// PANNs' output for a piece of audio, with where the time went.
public struct PANNsResult: Sendable {
    public var patches: PANNsPatches
    /// Seconds spent: resampling to 32 kHz, the network (all windows, front end included).
    public var timing: (resampling: Double, model: Double)
}

/// The MobileNetV2 audio tagger of Kong et al.'s PANNs ("PANNs: Large-Scale Pretrained Audio Neural Networks for Audio
/// Pattern Recognition", IEEE/ACM TASLP 2020; github.com/qiuqiangkong/audioset_tagging_cnn, MIT; weights CC BY 4.0,
/// trained on AudioSet), exported to ONNX by core/Tools/export_panns.py, on ONNX Runtime: mono audio at 32 kHz in, 527
/// class scores and a 1,024-value embedding per window out. Deckie's second vocal opinion beside YAMNet
/// (`VocalPatchModel`), used only when its model file is there.
///
/// The front end is inside the graph (the export says how: an STFT of 1,024 samples every 320 with a periodic Hann
/// window, 64 Slaney mel bands from 50 to 14,000 Hz, 10 log10 of the mel power), so the Swift side only resamples and
/// cuts windows: audio at 32 kHz is used as it is, any other rate is brought to 32 kHz by `Resampler` (soxr's HQ
/// filter, as for YAMNet); windows of 2 s start every 0.48 s, the last one zero-padded so the end is covered.
///
/// Why 2 s and 0.48 s. The network is fully convolutional and pools globally at the end (mean over frequency, then max
/// plus mean over time), so it takes any length; it was trained on 10 s clips, and its time axis is 32 times coarser
/// than its 10 ms frames when it pools. A 0.96 s window (YAMNet's patch) leaves 3 steps for that pooling against the
/// 31 of training; 2 s leaves 6, and is the length the authors themselves run the tagger on for sound event detection
/// ("applying the audio tagging system on consecutive 2-second segments", the repository's README), and about the
/// lab's own vocal reference's patch (Discogs-EffNet, 2.048 s). The hop is YAMNet's 0.48 s, so a bar of about 2 s gets
/// four windows, as it gets four YAMNet patches. Window k spans `k hop ..< k hop + window` seconds, centred at
/// `1.0 + 0.48 k`.
public final class PANNs: @unchecked Sendable {
    public static let modelEnvironmentVariable = "DECKIE_PANNS_MODEL"
    public static let modelFileName = "panns_mobilenetv2.onnx"
    /// The model's name, as records give it.
    public static let modelName = "panns-mobilenetv2"
    /// The SHA-256 of the export recorded in DEPENDENCIES.md (core/Tools/export_panns.py's ONNX_SHA256): nil until the
    /// first CI export is recorded.
    public static let recordedExportSHA256: String? = nil
    /// What to do when the model is missing.
    public static let remedy = "run core/Tools/fetch-panns.sh or set \(modelEnvironmentVariable)"

    public static let sampleRate = 32000
    public static let windowSamples = 64000
    public static let hopSamples = 15360
    public static let windowSeconds = Double(windowSamples) / Double(sampleRate)
    public static let hopSeconds = Double(hopSamples) / Double(sampleRate)
    /// Seconds from the start of the audio to the middle of window 0.
    public static let centreSeconds = windowSeconds / 2

    /// Where the model is looked for: DECKIE_PANNS_MODEL alone if it is set, else core/.models in the checkout this was
    /// built from (where core/Tools/fetch-panns.sh writes it).
    public static func modelCandidates() -> [String] {
        if let path = ProcessInfo.processInfo.environment[modelEnvironmentVariable], !path.isEmpty { return [path] }
        return [OnnxRuntime.coreFolder.appendingPathComponent(".models").appendingPathComponent(modelFileName).path]
    }

    /// The first candidate that exists, or nil.
    public static func locateModel() -> String? {
        modelCandidates().first { FileManager.default.fileExists(atPath: $0) }
    }

    /// The model from where it is looked for, or nil when it is not there. A model that is there but does not load is
    /// an error.
    public static func loadDefault(runtime: OnnxRuntime? = nil,
                                   options: OnnxRuntime.SessionOptions = OnnxRuntime.SessionOptions()) throws -> PANNs? {
        guard let path = locateModel() else { return nil }
        return try PANNs(modelPath: path, runtime: runtime, options: options)
    }

    /// Windows for `samples` samples at 32 kHz: one when they fit in a window, else enough for the last to reach the
    /// end.
    public static func patchCount(samples: Int) -> Int {
        samples <= windowSamples ? 1 : 1 + (samples - windowSamples + hopSamples - 1) / hopSamples
    }

    public let session: OnnxSession
    /// Windows per run of the network (bounds the memory: each is 64,000 samples in and its activations, about 4 MB
    /// in all for 16).
    public let batchSize: Int

    /// Loads the model (from `modelPath`, or the first of `modelCandidates()` that exists) into ONNX Runtime
    /// (`runtime`, or `OnnxRuntime.load()`).
    public init(modelPath: String? = nil, runtime: OnnxRuntime? = nil,
                options: OnnxRuntime.SessionOptions = OnnxRuntime.SessionOptions(), batchSize: Int = 16) throws {
        precondition(batchSize >= 1)
        let path: String
        if let modelPath {
            path = modelPath
        } else {
            guard let found = Self.locateModel() else { throw PANNsError.modelNotFound(searched: Self.modelCandidates()) }
            path = found
        }
        let rt = try runtime ?? OnnxRuntime.load()
        session = try rt.makeSession(modelPath: path, options: options)
        self.batchSize = batchSize
        guard session.inputNames == ["waveform"], Set(session.outputNames) == ["scores", "embeddings"] else {
            throw PANNsError.unexpectedModel("inputs \(session.inputNames), outputs \(session.outputNames); expected waveform in, scores and embeddings out")
        }
    }

    /// The network on the windows of `y` (mono at 32 kHz), `batchSize` windows at a time; each batch's windows are
    /// cut as it runs, so a long track never holds all its windows at once.
    public func run(signal y: [Float]) throws -> PANNsPatches {
        let count = Self.patchCount(samples: y.count), L = Self.windowSamples
        var scores: [Float] = [], embeddings: [Float] = []
        scores.reserveCapacity(count * PANNsPatches.classes)
        embeddings.reserveCapacity(count * PANNsPatches.embeddingSize)
        var start = 0
        var batch = [Float]()
        while start < count {
            let n = min(batchSize, count - start)
            batch.removeAll(keepingCapacity: true)
            batch.reserveCapacity(n * L)
            for k in start..<(start + n) {
                let a = k * Self.hopSamples, e = min(a + L, y.count)
                if a < e { batch += y[a..<e] }
                if e - a < L { batch += [Float](repeating: 0, count: L - max(e - a, 0)) }
            }
            let out = try session.run(["waveform": OnnxTensor(shape: [n, L], values: batch)])
            guard let s = out["scores"], let e = out["embeddings"], s.values.count == n * PANNsPatches.classes,
                  e.values.count == n * PANNsPatches.embeddingSize else {
                throw PANNsError.unexpectedModel("expected \(n) x \(PANNsPatches.classes) scores and \(n) x \(PANNsPatches.embeddingSize) embedding values")
            }
            scores += s.values
            embeddings += e.values
            start += n
        }
        return PANNsPatches(count: count, scores: scores, embeddings: embeddings)
    }

    /// Mono audio at 32 kHz, from mono audio at `sampleRate`.
    public static func modelRateSignal(_ mono: [Float], sampleRate: Int) -> [Float] {
        sampleRate == Self.sampleRate ? mono : Resampler(from: sampleRate, to: Self.sampleRate).process(mono)
    }

    /// PANNs' windows for mono audio at `sampleRate`.
    public func analyse(mono: [Float], sampleRate: Int) throws -> PANNsResult {
        let t0 = Date()
        let y = Self.modelRateSignal(mono, sampleRate: sampleRate)
        let t1 = Date()
        let patches = try run(signal: y)
        return PANNsResult(patches: patches, timing: (t1.timeIntervalSince(t0), Date().timeIntervalSince(t1)))
    }

    /// PANNs' windows for `audio` (its channels averaged).
    public func analyse(_ audio: AudioBuffer) throws -> PANNsResult {
        try analyse(mono: audio.mono(), sampleRate: audio.sampleRate)
    }
}

/// A vocal model that says in words how its vocal score is made, for records to write beside the scores.
public protocol VocalRuleDescribing {
    var vocalRuleText: String { get }
}

extension PANNs: VocalPatchModel, VocalRuleDescribing {
    public var name: String { Self.modelName }

    /// The classes whose scores make the vocal score: YAMNet's eleven (every kind of singing, rapping, humming, vocal
    /// music, a cappella) and the two AudioSet has that YAMNet's list does not, male and female singing. Speech is left
    /// out, as for YAMNet, and recorded beside it (`speech`).
    public static let vocalClasses: [PANNsClass] = [.singing, .choir, .yodeling, .chant, .mantra, .maleSinging,
                                                    .femaleSinging, .childSinging, .syntheticSinging, .rapping, .humming,
                                                    .vocalMusic, .aCappella]

    /// The rule, in words, as records give it.
    public static let vocalRule = "max of the panns scores for " + vocalClasses.map(\.name).joined(separator: ", ")
    public var vocalRuleText: String { Self.vocalRule }

    /// A window's vocal score: the largest of its `vocalClasses` scores (YAMNet's rule, `YAMNet.vocalScore`).
    public static func vocalScore(_ p: PANNsPatches, patch k: Int) -> Double {
        vocalClasses.reduce(0.0) { max($0, Double(p.score(k, $1))) }
    }

    /// The vocal score per window, the singing, speech and music scores as the other series, the class scores under
    /// their AudioSet names (so they are read the four ways YAMNet's are, `VocalReadings`), and the mean embedding as
    /// the style vector.
    public func vocalPatches(mono: [Float], sampleRate: Int) throws -> VocalPatches {
        let r = try analyse(mono: mono, sampleRate: sampleRate)
        let t0 = Date()
        let p = r.patches
        let vocal = (0..<p.count).map { Self.vocalScore(p, patch: $0) }
        let series = ["singing": p.scores(.singing), "speech": p.scores(.speech), "music": p.scores(.music)]
        let style = p.meanEmbedding()
        let rules = Date().timeIntervalSince(t0)
        return VocalPatches(vocal: vocal, series: series, style: style, hopSeconds: Self.hopSeconds,
                            centreSeconds: Self.centreSeconds,
                            timing: [.init("resample", r.timing.resampling), .init("model", r.timing.model),
                                     .init("scores", rules)],
                            classScores: p.classScores)
    }
}
