import Foundation

/// A feature matrix over time: `frames` frames of `rows` values each (mel bands, MFCC coefficients), in double
/// precision, stored frame by frame (`values[t * rows + r]`). librosa's arrays are the transpose, `rows` x `frames`.
public struct FrameMatrix: Sendable, Equatable {
    public let frames: Int
    public let rows: Int
    public var values: [Double]

    public init(frames: Int, rows: Int, values: [Double]) {
        precondition(frames >= 0 && rows >= 0 && values.count == frames * rows,
                     "\(values.count) values for \(frames) frames of \(rows)")
        self.frames = frames
        self.rows = rows
        self.values = values
    }

    /// The value of row `r` in frame `t`.
    public subscript(t: Int, r: Int) -> Double { values[t * rows + r] }

    /// The `rows` values of frame `t`.
    public func frame(_ t: Int) -> [Double] { Array(values[(t * rows)..<(t * rows + rows)]) }

    /// Row `r` over all frames (one mel band or one coefficient through time, a row of librosa's array).
    public func row(_ r: Int) -> [Double] {
        precondition(r >= 0 && r < rows)
        return (0..<frames).map { values[$0 * rows + r] }
    }
}
