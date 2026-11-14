import Foundation
import DeckieCore
import DeckieDecode

// DeckieChroma: a fingerprint of a song's sound in the form AcoustID reads, so that "Look up songs by sound" (the note
// on D30) can ask AcoustID which recording a file with no usable name is. Nothing here uses the network: it turns a
// file into numbers on the DJ's computer, and only DeckieLookup sends them, and only when the DJ asks.
//
// This is Chromaprint's published method, algorithm 2 (Chromaprint's "TEST2", the default and the one AcoustID
// indexes), ported to Swift from Chromaprint's MIT-licensed files (LICENSE-chromaprint beside this file names them and
// keeps their notice). The resampler is Deckie's own (Resampler.swift); the Fourier transform is DeckieCore's.
//
// The steps, each a file of Chromaprint's:
//   1. The first 120 seconds, mixed to one channel ((left + right) / 2), resampled to 11,025 samples a second and
//      rounded to 16-bit whole numbers, as `fpcalc` feeds them (src/cmd/fpcalc.cpp, src/audio/ffmpeg_audio_reader.h).
//   2. Frames of 4,096 samples, a new one every 1,365 (a third of a frame; fingerprinter_configuration.cpp), each
//      under a Hamming window scaled by 1 / 32,767 (fft_lib_*.cpp, utils.h), to its power spectrum.
//   3. Chroma: the power of every bin from 28 Hz to 3,520 Hz added into the one of the 12 notes of the octave its
//      frequency falls in, counted from A at 27.5 Hz, without spreading between notes (chroma.cpp, fingerprinter.cpp).
//   4. Each note smoothed over five frames with the weights 0.25, 0.75, 1, 0.75, 0.25 (chroma_filter.cpp), then each
//      frame's 12 values scaled to length 1, or all 0 when the length is under 0.01 (chroma_normalizer.h).
//   5. Those frames as rows of an image; 16 trained filters (rectangles compared in that image, as the log of the
//      ratio of their sums) each give a number that three trained thresholds cut into one of four steps, written as
//      two bits in Gray code, 32 bits a frame (classifier.h, filter.h, filter_utils.h, quantizer.h,
//      fingerprint_calculator.cpp, the table in fingerprinter_configuration.cpp).
//   6. The frames compressed and written in URL-safe base64 for the web service (fingerprint_compressor.cpp,
//      utils/pack_int3_array.h, utils/pack_int5_array.h, utils/base64.h); and read back (fingerprint_decompressor.cpp).

/// A song's sound fingerprint as AcoustID takes it.
public struct SoundFingerprint: Sendable, Equatable {
    /// 32 bits for every 1,365 samples at 11,025 a second (about 0.124 seconds), the "raw" fingerprint.
    public var frames: [UInt32]
    /// The length of the whole file in whole seconds, as the web service asks for it.
    public var duration: Int
    /// Chromaprint's algorithm number: 1 is "TEST2".
    public var algorithm: Int
    public init(frames: [UInt32], duration: Int, algorithm: Int = Chromaprint.algorithm) {
        self.frames = frames; self.duration = duration; self.algorithm = algorithm
    }
    /// The compressed form the web service takes (`fingerprint=`).
    public var compressed: String { Chromaprint.compress(frames, algorithm: algorithm) }
}

public enum Chromaprint {
    /// Algorithm 2 of Chromaprint, which its code numbers 1 (CHROMAPRINT_ALGORITHM_TEST2).
    public static let algorithm = 1
    public static let sampleRate = 11025
    public static let frameSize = 4096
    /// A new frame every third of a frame: 4096 - (4096 - 4096 / 3).
    public static let step = frameSize / 3
    /// How much of a file is fingerprinted, in seconds (fpcalc's default `-length`).
    public static let defaultSeconds = 120.0
    static let minFrequency = 28.0
    static let maxFrequency = 3520.0
    static let bands = 12
    static let chromaFilter: [Double] = [0.25, 0.75, 1.0, 0.75, 0.25]

    // MARK: whole files

    /// The fingerprint of an audio file Deckie can decode: its first `seconds`, and the whole file's length.
    public static func fingerprint(file url: URL, seconds: Double = defaultSeconds) throws -> SoundFingerprint {
        let buffer = try AudioDecoder.decode(url)
        return fingerprint(buffer, seconds: seconds)
    }

    /// The fingerprint of decoded audio: its first `seconds`, and its whole length.
    public static func fingerprint(_ buffer: AudioBuffer, seconds: Double = defaultSeconds) -> SoundFingerprint {
        let pcm = samples(buffer, seconds: seconds)
        return SoundFingerprint(frames: frames(pcm), duration: Int(buffer.duration))
    }

    /// Step 1: the first `seconds` of `buffer` as one channel of 16-bit samples at 11,025 a second.
    public static func samples(_ buffer: AudioBuffer, seconds: Double = defaultSeconds) -> [Int16] {
        let limit = Int(seconds * Double(sampleRate))
        // Enough input for `limit` outputs plus the filter's reach past the last one.
        let need = Int((Double(limit) * Double(buffer.sampleRate) / Double(sampleRate)).rounded(.up)) + 256
        let frames = min(buffer.frames, need)
        var mono = [Float](repeating: 0, count: frames)
        let c = buffer.channelCount
        buffer.samples.withUnsafeBufferPointer { s in
            if c == 1 {
                for f in 0..<frames { mono[f] = s[f] }
            } else {
                for f in 0..<frames { mono[f] = (s[f * c] + s[f * c + 1]) * 0.5 }
            }
        }
        let resampled: [Double]
        if buffer.sampleRate == sampleRate {
            resampled = mono.prefix(limit).map(Double.init)
        } else {
            let r = Resampler(inRate: buffer.sampleRate, outRate: sampleRate)
            let count = min(limit, r.outputCount(buffer.frames))
            resampled = r.process(mono, limit: count)
        }
        return resampled.map { v in
            let x = (v * 32768).rounded(.toNearestOrEven)
            return Int16(max(-32768, min(32767, x)))
        }
    }

    // MARK: the fingerprint of samples

    /// Steps 2 to 5: the raw fingerprint of 16-bit samples at 11,025 a second.
    public static func frames(_ pcm: [Int16]) -> [UInt32] {
        chromaToFrames(chroma(pcm))
    }

    /// Steps 2 and 3: one row of 12 note powers for every frame.
    static func chroma(_ pcm: [Int16]) -> [[Double]] {
        guard pcm.count >= frameSize else { return [] }
        let count = (pcm.count - frameSize) / step + 1
        let fft = RealFFT(size: frameSize)
        // Hamming window, scaled so a full-scale sample is 1.
        let window = (0..<frameSize).map { i in
            (0.54 - 0.46 * cos(Double(i) * 2 * Double.pi / Double(frameSize - 1))) / 32767.0
        }
        let rate = Double(sampleRate), size = Double(frameSize)
        func index(_ f: Double) -> Int { Int((size * f / rate).rounded(.toNearestOrAwayFromZero)) }
        let lo = max(1, index(minFrequency)), hi = min(frameSize / 2, index(maxFrequency))
        var note = [Int](repeating: 0, count: frameSize / 2 + 1)
        for i in lo..<hi {
            let freq = Double(i) * rate / size
            let octave = log(freq / (440.0 / 16.0)) / log(2.0)
            note[i] = Int(Double(bands) * (octave - floor(octave)))
        }
        var rows: [[Double]] = []
        rows.reserveCapacity(count)
        var x = [Double](repeating: 0, count: frameSize)
        var re = [Double](repeating: 0, count: frameSize / 2 + 1), im = re
        for f in 0..<count {
            let start = f * step
            for i in 0..<frameSize { x[i] = Double(pcm[start + i]) * window[i] }
            x.withUnsafeBufferPointer { xb in
                re.withUnsafeMutableBufferPointer { rb in
                    im.withUnsafeMutableBufferPointer { ib in fft.forward(xb.baseAddress!, real: rb.baseAddress!, imag: ib.baseAddress!) }
                }
            }
            var row = [Double](repeating: 0, count: bands)
            for i in lo..<hi { row[note[i]] += re[i] * re[i] + im[i] * im[i] }
            rows.append(row)
        }
        return rows
    }

    /// Steps 4 and 5, from chroma rows.
    static func chromaToFrames(_ chroma: [[Double]]) -> [UInt32] {
        let taps = chromaFilter.count
        guard chroma.count >= taps else { return [] }
        // Smoothed and normalised rows, kept as an integral image: cell (r, c) is the sum of all rows before r and
        // columns before c, so a rectangle's sum is four look-ups.
        let rows = chroma.count - taps + 1
        var integral = [Double](repeating: 0, count: (rows + 1) * (bands + 1))
        let w = bands + 1
        for r in 0..<rows {
            var v = [Double](repeating: 0, count: bands)
            for j in 0..<taps {
                let row = chroma[r + j], c = chromaFilter[j]
                for b in 0..<bands { v[b] += row[b] * c }
            }
            var sq = 0.0
            for b in 0..<bands { sq += v[b] * v[b] }
            let norm = sq > 0 ? sq.squareRoot() : 0
            if norm < 0.01 { for b in 0..<bands { v[b] = 0 } } else { for b in 0..<bands { v[b] /= norm } }
            var running = 0.0
            for b in 0..<bands {
                running += v[b]
                integral[(r + 1) * w + b + 1] = integral[r * w + b + 1] + running
            }
        }
        func area(_ r1: Int, _ c1: Int, _ r2: Int, _ c2: Int) -> Double {
            integral[r2 * w + c2] - integral[r1 * w + c2] - integral[r2 * w + c1] + integral[r1 * w + c1]
        }
        let width = classifiers.map(\.width).max()!
        guard rows >= width else { return [] }
        var out: [UInt32] = []
        out.reserveCapacity(rows - width + 1)
        for x in 0...(rows - width) {
            var bits: UInt32 = 0
            for k in classifiers {
                bits = (bits << 2) | UInt32(gray[k.quantize(k.apply(x, area))])
            }
            out.append(bits)
        }
        return out
    }

    static let gray = [0, 1, 3, 2]

    // MARK: comparing

    /// The share of bits that differ between two raw fingerprints, over the frames both have (0 is the same).
    public static func bitDifference(_ a: [UInt32], _ b: [UInt32]) -> Double {
        let n = min(a.count, b.count)
        guard n > 0 else { return 1 }
        var d = 0
        for i in 0..<n { d += (a[i] ^ b[i]).nonzeroBitCount }
        return Double(d) / Double(n * 32)
    }
}
