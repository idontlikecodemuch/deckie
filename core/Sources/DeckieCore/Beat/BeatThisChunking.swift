/// Beat This!'s frame-wise output: one beat and one downbeat logit per spectrogram frame (a logit is the log-odds
/// log(p / (1 - p)) of the frame holding a beat; above 0 means more likely than not).
public struct BeatThisLogits: Sendable, Equatable {
    public var beat: [Float]
    public var downbeat: [Float]

    public init(beat: [Float], downbeat: [Float]) {
        precondition(beat.count == downbeat.count, "\(beat.count) beat and \(downbeat.count) downbeat logits")
        self.beat = beat
        self.downbeat = downbeat
    }

    public var frames: Int { beat.count }
}

/// How the Beat This! package runs its network over a piece longer than it was trained on (beat_this 1.1.0,
/// `inference.split_piece`, `aggregate_prediction` and `split_predict_aggregate`, called with chunk_size 1500,
/// border_size 6, overlap_mode "keep_first", avoid_short_end true):
///
/// - Chunks of 1,500 frames (30 s) start every 1,488 frames, the first at frame -6, so neighbours overlap by 12
///   frames. Where a chunk runs off the piece it is padded with zero frames, but by at most 6 at the end. The last
///   chunk is moved left to end 6 frames past the piece's end (when the piece is longer than 1,488 frames), so it is
///   a whole chunk too. A piece of at most 1,488 frames is one chunk: 6 zero frames, the piece, 6 zero frames.
/// - Each chunk's predictions lose 6 frames at each edge (the network was not trained on its input's edges), and
///   what remains is written into the piece's arrays at its place; where two chunks overlap, the earlier one's
///   values are kept. Frames no chunk covers (none, with these settings) stay at -1000.
public enum BeatThisChunking {
    public static let chunkSize = 1500
    public static let borderSize = 6

    public struct Chunk: Sendable, Equatable {
        /// The piece frame the chunk's first row stands for; negative for the first chunk.
        public let start: Int
        /// Zero frames before the piece's frames.
        public let leftPad: Int
        /// The piece's frames the chunk holds.
        public let source: Range<Int>
        /// Zero frames after them.
        public let rightPad: Int

        /// Rows in the chunk.
        public var length: Int { leftPad + source.count + rightPad }
    }

    /// The chunks for a piece of `frames` frames, in order (`split_piece`).
    public static func split(frames n: Int, chunkSize: Int = chunkSize, borderSize: Int = borderSize,
                             avoidShortEnd: Bool = true) -> [Chunk] {
        precondition(chunkSize > 2 * borderSize && borderSize >= 0)
        // np.arange(-border, n - border, chunk - 2 border)
        var starts: [Int] = []
        var s = -borderSize
        while s < n - borderSize { starts.append(s); s += chunkSize - 2 * borderSize }
        if avoidShortEnd && n > chunkSize - 2 * borderSize && !starts.isEmpty {
            starts[starts.count - 1] = n - (chunkSize - borderSize)
        }
        return starts.map { s in
            Chunk(start: s, leftPad: max(0, -s), source: max(s, 0)..<min(s + chunkSize, n),
                  rightPad: max(0, min(borderSize, s + chunkSize - n)))
        }
    }

    /// The chunk's rows as the network's input: `length` x 128 values, zero frames where padded.
    public static func input(_ chunk: Chunk, from spectrogram: BeatThisSpectrogram) -> [Float] {
        let bands = BeatThisSpectrogram.bands
        var out = [Float](repeating: 0, count: chunk.length * bands)
        if !chunk.source.isEmpty {
            let from = chunk.source.lowerBound * bands, count = chunk.source.count * bands
            out.replaceSubrange((chunk.leftPad * bands)..<(chunk.leftPad * bands + count),
                                with: spectrogram.values[from..<(from + count)])
        }
        return out
    }

    /// The piece's logits from each chunk's predictions (`aggregate_prediction` with "keep_first").
    public static func aggregate(frames n: Int, chunks: [Chunk], predictions: [BeatThisLogits],
                                 chunkSize: Int = chunkSize, borderSize: Int = borderSize) -> BeatThisLogits {
        precondition(chunks.count == predictions.count)
        var beat = [Float](repeating: -1000, count: n), downbeat = [Float](repeating: -1000, count: n)
        // Later chunks first, so the earlier ones overwrite them where they overlap.
        for (chunk, p) in zip(chunks, predictions).reversed() {
            precondition(p.frames == chunk.length, "a prediction of \(p.frames) frames for a chunk of \(chunk.length)")
            let kept = max(0, p.frames - 2 * borderSize)
            let first = chunk.start + borderSize  // >= 0: chunks start at -border at the earliest
            let count = min(kept, n - first)
            for i in 0..<max(0, count) {
                beat[first + i] = p.beat[borderSize + i]
                downbeat[first + i] = p.downbeat[borderSize + i]
            }
        }
        return BeatThisLogits(beat: beat, downbeat: downbeat)
    }

    /// Splits the spectrogram, runs `model` on each chunk's input (rows x 128 values, and the number of rows; it
    /// returns that many beat and downbeat logits), and assembles the piece's logits (`split_predict_aggregate`).
    public static func run(_ spectrogram: BeatThisSpectrogram,
                           model: (_ input: [Float], _ rows: Int) throws -> BeatThisLogits) rethrows -> BeatThisLogits {
        let chunks = split(frames: spectrogram.frames)
        var predictions: [BeatThisLogits] = []
        predictions.reserveCapacity(chunks.count)
        for chunk in chunks {
            predictions.append(try model(input(chunk, from: spectrogram), chunk.length))
        }
        return aggregate(frames: spectrogram.frames, chunks: chunks, predictions: predictions)
    }
}
