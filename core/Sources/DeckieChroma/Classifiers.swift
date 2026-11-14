import Foundation

// The 16 trained filters and thresholds of Chromaprint's algorithm 2 ("TEST2"), with the filter shapes they use.
// Ported from Chromaprint's MIT-licensed files: the table `kClassifiersTest2` in src/fingerprinter_configuration.cpp,
// the shapes in src/filter_utils.h and src/filter.h, the thresholds in src/quantizer.h.
// Copyright (C) 2010-2016 Lukas Lalinsky; MIT licence, kept in LICENSE-chromaprint beside this file.

/// One filter and its thresholds. `kind` is the shape (0 to 5), `y` the first note, `height` how many notes, `width`
/// how many frames; `t0 <= t1 <= t2` cut the filter's value into 0, 1, 2 or 3.
struct Classifier: Sendable {
    let kind: Int, y: Int, height: Int, width: Int
    let t0: Double, t1: Double, t2: Double

    init(_ kind: Int, _ y: Int, _ height: Int, _ width: Int, _ t0: Double, _ t1: Double, _ t2: Double) {
        self.kind = kind; self.y = y; self.height = height; self.width = width
        self.t0 = t0; self.t1 = t1; self.t2 = t2
    }

    func quantize(_ v: Double) -> Int {
        if v < t1 { return v < t0 ? 0 : 1 }
        return v < t2 ? 2 : 3
    }

    /// The filter at frame `x` of an image read through `area(r1, c1, r2, c2)` (rows are frames, columns notes):
    /// log((1 + a) / (1 + b)) of the sums a and b of the shape's two parts.
    func apply(_ x: Int, _ area: (Int, Int, Int, Int) -> Double) -> Double {
        let w = width, h = height, y = y
        let a: Double, b: Double
        switch kind {
        case 0:
            a = area(x, y, x + w, y + h); b = 0
        case 1:
            let h2 = h / 2
            a = area(x, y + h2, x + w, y + h)
            b = area(x, y, x + w, y + h2)
        case 2:
            let w2 = w / 2
            a = area(x + w2, y, x + w, y + h)
            b = area(x, y, x + w2, y + h)
        case 3:
            let w2 = w / 2, h2 = h / 2
            a = area(x, y + h2, x + w2, y + h) + area(x + w2, y, x + w, y + h2)
            b = area(x, y, x + w2, y + h2) + area(x + w2, y + h2, x + w, y + h)
        case 4:
            let h3 = h / 3
            a = area(x, y + h3, x + w, y + 2 * h3)
            b = area(x, y, x + w, y + h3) + area(x, y + 2 * h3, x + w, y + h)
        case 5:
            let w3 = w / 3
            a = area(x + w3, y, x + 2 * w3, y + h)
            b = area(x, y, x + w3, y + h) + area(x + 2 * w3, y, x + w, y + h)
        default:
            return 0
        }
        return log((1 + a) / (1 + b))
    }
}

extension Chromaprint {
    /// Chromaprint's `kClassifiersTest2`, in its order: Filter(type, y, height, width), Quantizer(t0, t1, t2).
    static let classifiers: [Classifier] = [
        Classifier(0, 4, 3, 15, 1.98215, 2.35817, 2.63523),
        Classifier(4, 4, 6, 15, -1.03809, -0.651211, -0.282167),
        Classifier(1, 0, 4, 16, -0.298702, 0.119262, 0.558497),
        Classifier(3, 8, 2, 12, -0.105439, 0.0153946, 0.135898),
        Classifier(3, 4, 4, 8, -0.142891, 0.0258736, 0.200632),
        Classifier(4, 0, 3, 5, -0.826319, -0.590612, -0.368214),
        Classifier(1, 2, 2, 9, -0.557409, -0.233035, 0.0534525),
        Classifier(2, 7, 3, 4, -0.0646826, 0.00620476, 0.0784847),
        Classifier(2, 6, 2, 16, -0.192387, -0.029699, 0.215855),
        Classifier(2, 1, 3, 2, -0.0397818, -0.00568076, 0.0292026),
        Classifier(5, 10, 1, 15, -0.53823, -0.369934, -0.190235),
        Classifier(3, 6, 2, 10, -0.124877, 0.0296483, 0.139239),
        Classifier(2, 1, 1, 14, -0.101475, 0.0225617, 0.231971),
        Classifier(3, 5, 6, 4, -0.0799915, -0.00729616, 0.063262),
        Classifier(1, 9, 2, 12, -0.272556, 0.019424, 0.302559),
        Classifier(3, 4, 2, 14, -0.164292, -0.0321188, 0.0846339),
    ]
}
