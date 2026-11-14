import Foundation
import DeckieCore

// TRIAL (docs/research/w2-own-recognition-trial.md). Song recognition that Deckie owns: nothing here ships without the
// owner's decision, and nothing outside this folder calls it.
//
// The method is the one published by Wang, "An Industrial-Strength Audio Search Algorithm" (ISMIR 2003), written from
// the paper: a song is reduced to its "constellation", the points of the spectrogram (time against frequency) that are
// louder than everything around them; points are hashed in pairs (the two frequencies and the time between them); a
// query's hashes are looked up and the matches that agree on one time offset into one song are counted.
//
// What is kept for a song is the constellation itself (`Landmarks`), not the hashes: the hashes are made from it when
// an index is built, so the way points are paired can change without touching a crate file.

/// The numbers the front end runs on. None is fitted to any library: each is from the paper, a first principle, or is
/// one of a few stated options chosen on half of an outside set (the research letter says which).
public struct LandmarkConfig: Sendable, Equatable, Codable {
    /// The analysis rate. 8 kHz keeps what a telephone keeps (to 4 kHz), which is the band a small speaker and a room
    /// pass reliably, and makes the transform cheap.
    public var sampleRate = 8000
    /// Transform length in samples (0.128 s at 8 kHz: 7.8 Hz between bins, so a held note is one narrow ridge).
    public var fftSize = 1024
    /// Samples from one frame to the next (16 ms).
    public var hop = 128
    /// The band points are taken from. 300 Hz is where Haitsma and Kalker's print starts (below it a booth is rumble and
    /// a small speaker is silent); 3600 Hz leaves the resampler's roll-off below 4 kHz out.
    public var lowHz = 300.0
    public var highHz = 3600.0
    /// A point must be the loudest within this many frames either side...
    public var timeReach = 6
    /// ...and within this fraction of its own frequency either side (so the neighbourhood is the same musical width
    /// everywhere, and the same points are chosen when the deck's speed moves every frequency by one factor).
    public var frequencyReach = 0.12
    /// Points this far below the loudest bin of the audio are not taken (silence and digital noise).
    public var floorDB = 60.0
    /// A point's strength is how far it stands above the average level of its own neighbourhood, in decibels (so a
    /// room's or a speaker's tone does not change it much); it is kept as one of four levels, cut at these values.
    /// The cuts are the quartiles measured on a sample of the benchmark's dev songs (13, 16 and 19 dB).
    /// The strongest points are the likeliest to survive noise (Wang 2003, 2.1), so hashes are built from them.
    public var strengthSteps: [Double] = [13, 16, 19]

    public init() {}

    public var frameSeconds: Double { Double(hop) / Double(sampleRate) }
    /// The band's width in octaves.
    public var octaves: Double { log2(highHz / lowHz) }
}

/// A song's constellation: its spectrogram peaks in time order.
public struct Landmarks: Sendable, Equatable {
    /// Frame of each point (16 ms steps), ascending.
    public var frames: [UInt32]
    /// Frequency of each point, in 1/4096 of an octave above the band's low edge (300 Hz), in the low 14 bits; the
    /// point's strength level (0 to 3) in the top two.
    public var packed: [UInt16]
    /// Each point's strength in decibels, as measured: only on a constellation just made from audio (a query's), not
    /// kept on disk and not part of equality.
    public var strengths: [Float] = []
    public static func == (a: Landmarks, b: Landmarks) -> Bool { a.frames == b.frames && a.packed == b.packed && a.frameCount == b.frameCount }
    @inline(__always) public func pitch(_ i: Int) -> UInt16 { packed[i] & 0x3fff }
    @inline(__always) public func level(_ i: Int) -> Int { Int(packed[i] >> 14) }
    /// Frames analysed (the audio's length).
    public var frameCount: Int

    public static let pitchUnitsPerOctave = 4096.0

    public init(frames: [UInt32], pitches packed: [UInt16], frameCount: Int) {
        precondition(frames.count == packed.count)
        self.frames = frames; self.packed = packed; self.frameCount = frameCount
    }

    public var count: Int { frames.count }

    /// The constellation of mono audio at any rate.
    public init(mono: [Float], sampleRate rate: Int, config c: LandmarkConfig = LandmarkConfig()) {
        let x = rate == c.sampleRate ? mono : Resampler.resample(mono, from: rate, to: c.sampleRate)
        let N = c.fftSize, H = c.hop
        let frameCount = x.count / H
        guard frameCount > 2 * c.timeReach else { self.init(frames: [], pitches: [], frameCount: max(0, frameCount)); return }

        let binHz = Double(c.sampleRate) / Double(N)
        let kLo = Int((c.lowHz / binHz).rounded(.up)), kHi = min(N / 2 - 1, Int(c.highHz / binHz))
        // Each bin's reach in bins, and the bins kept (the band plus the reach beyond its edges).
        let reach = (0...(N / 2)).map { max(2, Int((Double($0) * c.frequencyReach).rounded())) }
        let b0 = max(1, kLo - reach[kLo]), b1 = min(N / 2, kHi + reach[kHi])
        let nb = b1 - b0 + 1

        // The spectrogram in decibels, frames centred on multiples of the hop (zeros beyond the ends).
        let fft = RealFFT(size: N)
        let window = Window.hann(N)
        var spec = [Float](repeating: -200, count: frameCount * nb)
        var buf = [Double](repeating: 0, count: N)
        var re = [Double](repeating: 0, count: fft.bins), im = [Double](repeating: 0, count: fft.bins)
        var loudest: Float = -200
        // Pointers and `while` throughout, so that a debug build (where Swift checks every array access) still makes
        // a song's constellation in about a second: the builders' tests run the engine unoptimised.
        x.withUnsafeBufferPointer { xs in
            window.withUnsafeBufferPointer { w in
                buf.withUnsafeMutableBufferPointer { b in
                    re.withUnsafeMutableBufferPointer { r in
                        im.withUnsafeMutableBufferPointer { m in
                            spec.withUnsafeMutableBufferPointer { s in
                                let count = xs.count
                                var t = 0
                                while t < frameCount {
                                    let start = t * H - N / 2
                                    var i = 0
                                    while i < N {
                                        let j = start + i
                                        b[i] = j >= 0 && j < count ? Double(xs[j]) * w[i] : 0
                                        i += 1
                                    }
                                    fft.forward(UnsafePointer(b.baseAddress!), real: r.baseAddress!, imag: m.baseAddress!)
                                    let row = s.baseAddress! + t * nb
                                    var k = b0
                                    while k <= b1 {
                                        let p = r[k] * r[k] + m[k] * m[k]
                                        let d = Float(10 * log10(p + 1e-20))
                                        row[k - b0] = d
                                        if d > loudest { loudest = d }
                                        k += 1
                                    }
                                    t += 1
                                }
                            }
                        }
                    }
                }
            }
        }
        let floor = loudest - Float(c.floorDB)

        var frames: [UInt32] = [], pitches: [UInt16] = [], strengths: [Float] = []
        let T = c.timeReach
        let top = c.octaves * Self.pitchUnitsPerOctave
        spec.withUnsafeBufferPointer { s in
            let base = s.baseAddress!
            for t in 0..<frameCount {
                let row = base + t * nb
                let t0 = max(0, t - T), t1 = min(frameCount - 1, t + T)
                for k in kLo...kHi {
                    let v = row[k - b0]
                    // Cheap tests first: above the floor and above both neighbours in its own frame.
                    if v < floor || v <= row[k - b0 - 1] || v < row[k - b0 + 1] { continue }
                    let lo = max(b0, k - reach[k]) - b0, hi = min(b1, k + reach[k]) - b0
                    var isPeak = true
                    // Ties go to the earlier frame and the lower bin, so exactly one of two equal points is kept.
                    var u = t0
                    while u <= t1 && isPeak {
                        let r = base + u * nb
                        var j = lo
                        if u < t {
                            while j <= hi { if r[j] >= v { isPeak = false; break }; j += 1 }
                        } else if u > t {
                            while j <= hi { if r[j] > v { isPeak = false; break }; j += 1 }
                        } else {
                            while j <= hi {
                                if j != k - b0 && (j < k - b0 ? r[j] >= v : r[j] > v) { isPeak = false; break }
                                j += 1
                            }
                        }
                        u += 1
                    }
                    if !isPeak { continue }
                    // The frequency between bins: the top of the parabola through the point and its two neighbours.
                    let a = Double(row[k - b0 - 1]), b = Double(v), cc = Double(row[k - b0 + 1])
                    let den = a - 2 * b + cc
                    let delta = den < 0 ? max(-0.5, min(0.5, 0.5 * (a - cc) / den)) : 0
                    let oct = log2((Double(k) + delta) * binHz / c.lowHz)
                    let units = (oct * Self.pitchUnitsPerOctave).rounded()
                    if units < 0 || units >= top { continue }
                    // Strength: decibels above the mean level of the neighbourhood (the floor stands in for silence).
                    var sum = 0.0, cells = 0
                    for u in t0...t1 {
                        let r = base + u * nb
                        for j in lo...hi { sum += Double(max(r[j], floor)); cells += 1 }
                    }
                    let strength = Double(v) - sum / Double(cells)
                    let level = c.strengthSteps.reduce(0) { $0 + (strength >= $1 ? 1 : 0) }
                    frames.append(UInt32(t)); pitches.append(UInt16(units) | UInt16(level) << 14)
                    strengths.append(Float(strength))
                }
            }
        }
        self.init(frames: frames, pitches: pitches, frameCount: frameCount)
        self.strengths = strengths
    }

    /// The points from `seconds` on, with time starting again there (the newest part of a window of sound).
    public func suffix(fromSeconds seconds: Double, frameSeconds: Double) -> Landmarks {
        let first = UInt32(max(0, (seconds / frameSeconds).rounded()))
        let at = frames.firstIndex { $0 >= first } ?? frames.count
        var out = Landmarks(frames: frames[at...].map { $0 - first }, pitches: Array(packed[at...]), frameCount: max(0, frameCount - Int(first)))
        if strengths.count == count { out.strengths = Array(strengths[at...]) }
        return out
    }

    // MARK: On disk

    /// The bytes kept for a song: "DKL2", the frame count and point count (little-endian UInt32 each), then for each
    /// point the frames since the point before as a varint (7 bits a byte, low first) and the pitch with its strength
    /// level as a little-endian UInt16. About three bytes a point.
    public func encoded() -> Data {
        var d = Data(capacity: 12 + 3 * count)
        d.append(contentsOf: Array("DKL2".utf8))
        func put32(_ v: UInt32) { for i in 0..<4 { d.append(UInt8((v >> (8 * UInt32(i))) & 0xff)) } }
        put32(UInt32(frameCount)); put32(UInt32(count))
        var last: UInt32 = 0
        for i in 0..<count {
            var delta = frames[i] - last
            last = frames[i]
            while delta >= 0x80 { d.append(UInt8(delta & 0x7f) | 0x80); delta >>= 7 }
            d.append(UInt8(delta))
            d.append(UInt8(packed[i] & 0xff)); d.append(UInt8(packed[i] >> 8))
        }
        return d
    }

    /// Reads `encoded()`'s bytes; nil when they are not a constellation.
    public init?(encoded d: Data) {
        let b = [UInt8](d)
        guard b.count >= 12, Array(b[0..<4]) == Array("DKL2".utf8) else { return nil }
        func get32(_ at: Int) -> UInt32 { (0..<4).reduce(UInt32(0)) { $0 | UInt32(b[at + $1]) << (8 * UInt32($1)) } }
        let frameCount = Int(get32(4)), n = Int(get32(8))
        var frames: [UInt32] = [], pitches: [UInt16] = []
        frames.reserveCapacity(n); pitches.reserveCapacity(n)
        var i = 12
        var last: UInt32 = 0
        for _ in 0..<n {
            var delta: UInt32 = 0, shift: UInt32 = 0
            while true {
                guard i < b.count, shift <= 28 else { return nil }
                let byte = b[i]; i += 1
                delta |= UInt32(byte & 0x7f) << shift
                if byte & 0x80 == 0 { break }
                shift += 7
            }
            guard i + 1 < b.count else { return nil }
            last += delta
            frames.append(last)
            pitches.append(UInt16(b[i]) | UInt16(b[i + 1]) << 8)
            i += 2
        }
        guard i == b.count else { return nil }
        self.init(frames: frames, pitches: pitches, frameCount: frameCount)
    }
}
