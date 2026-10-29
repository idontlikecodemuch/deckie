import Foundation
import DeckieCore
import DeckieDecode

/// `deckie-build mp3-check <folder>`: checks the MP3 decoder's damaged-frame concealment on real files. Every MP3
/// below the folder is decoded as the engine decodes it and by dr_mp3's own pull reader (what the decoder gave before
/// the concealment, Oct 29, 2026), and the two are compared sample for sample (`MP3ConcealmentCheck`). It holds when
/// every file without a damaged frame gives the same samples, bit for bit, and every file with one differs only from
/// each damaged frame's start to the end of the frame after it (three frames' time is allowed, for the 576-sample
/// frames of MPEG-2); for those the true peak is given both ways. No model is needed.
public enum MP3Check {
    /// One MP3.
    public struct FileResult: Sendable {
        public var rel: String
        public var damagedFrames: [DamagedFrame] = []
        /// One stretch in which the samples differ from the pull reader's (`MP3ConcealmentCheck.DifferingSpan`), in
        /// seconds, with how many sample frames in it differ.
        public struct Span: Sendable, Equatable {
            public var seconds: ClosedRange<Double>
            public var count: Int
        }
        /// Where the samples differ from the pull reader's, span by span in order; empty when they are the same.
        public var spans: [Span] = []
        /// The first and last differing times; nil when the samples are the same.
        public var differing: ClosedRange<Double>? {
            guard let f = spans.first, let l = spans.last else { return nil }
            return f.seconds.lowerBound...l.seconds.upperBound
        }
        /// The true peak (dBTP) of the pull reader's samples and of the concealed ones, for a file with damaged frames.
        public var truePeakBefore: Double?, truePeakAfter: Double?
        /// Why the file could not be decoded, if it could not.
        public var error: String?

        /// Whether the concealment changed nothing it should not have: no difference at all, or every span of
        /// differences inside the reach of a damaged frame, from its start to three frames' time after it (the frame,
        /// the overlap into the next and the filter bank's delay), reaches that touch taken together. A span outside
        /// every reach, between two damaged frames included, fails: the decoder's state did not come back.
        public var holds: Bool {
            if spans.isEmpty { return true }
            var reaches: [ClosedRange<Double>] = []
            for f in damagedFrames {
                let lo = f.startSeconds - 1e-9, hi = f.startSeconds + 3 * f.seconds
                if let r = reaches.last, lo <= r.upperBound {
                    reaches[reaches.count - 1] = r.lowerBound...max(r.upperBound, hi)
                } else {
                    reaches.append(lo...hi)
                }
            }
            return spans.allSatisfy { s in
                reaches.contains { s.seconds.lowerBound >= $0.lowerBound && s.seconds.upperBound < $0.upperBound }
            }
        }
    }

    /// Checks every `.mp3` below `folder`, `jobs` at a time; `progress` gets a line for each file with damaged frames
    /// or a difference (called from the jobs' threads, one call at a time).
    public static func run(folder: URL, jobs: Int = processorCount,
                           progress: @escaping @Sendable (String) -> Void = { _ in }) throws -> [FileResult] {
        let files = try AudioFiles.find(in: folder).filter { $0.ext == "mp3" }
        final class Results: @unchecked Sendable {
            let lock = NSLock()
            var list: [FileResult?]
            init(_ n: Int) { list = Array(repeating: nil, count: n) }
        }
        let results = Results(files.count)
        runParallel(count: files.count, workers: jobs) { i in
            var r = FileResult(rel: files[i].rel)
            do {
                let c = try MP3ConcealmentCheck.check(files[i].url)
                let rate = Double(c.decoded.sampleRate)
                r.damagedFrames = c.damagedFrames
                r.spans = c.differingSpans.map {
                    .init(seconds: Double($0.frames.lowerBound) / rate...Double($0.frames.upperBound) / rate, count: $0.count)
                }
                if !c.damagedFrames.isEmpty {
                    r.truePeakBefore = TruePeak.decibels(c.pullReader)
                    r.truePeakAfter = TruePeak.decibels(c.decoded)
                }
            } catch {
                r.error = "\(error)"
            }
            results.lock.lock()
            defer { results.lock.unlock() }
            results.list[i] = r
            if !r.damagedFrames.isEmpty || r.differing != nil { progress(line(r)) }
        }
        return results.list.map { $0! }
    }

    /// One file's line: its damaged frames, each span where its samples differ (so a file with several damaged
    /// frames shows one span per frame, never one stretch from the first to the last) and its true peak both ways.
    public static func line(_ r: FileResult) -> String {
        if let e = r.error { return "\(r.rel): not decoded: \(e)" }
        var s = r.rel + ": "
        if r.damagedFrames.isEmpty {
            s += "no damaged frame"
        } else {
            s += r.damagedFrames.map { "damaged frame at \(Py.fixed($0.startSeconds, 3)) s (\(Py.fixed($0.seconds * 1000, 1)) ms)" }
                .joined(separator: ", ")
        }
        if !r.spans.isEmpty {
            let n = r.spans.count
            s += "; samples differ from dr_mp3's pull reader in \(n) span\(n == 1 ? "" : "s"): "
                + r.spans.map { "\(Py.fixed($0.seconds.lowerBound, 4)) to \(Py.fixed($0.seconds.upperBound, 4)) s "
                                + "(\($0.count) sample frames)" }.joined(separator: ", ")
        } else {
            s += "; samples as dr_mp3's pull reader"
        }
        if let b = r.truePeakBefore, let a = r.truePeakAfter {
            s += "; true peak \(Py.fixed(b, 2)) dBTP before, \(Py.fixed(a, 2)) concealed"
        }
        return s + (r.holds ? "" : "  <- NOT AS EXPECTED")
    }

    /// The summary, and whether the check holds for every file.
    public static func summary(_ results: [FileResult]) -> (text: String, holds: Bool) {
        let damaged = results.filter { !$0.damagedFrames.isEmpty }
        let failed = results.filter { $0.error != nil }
        let same = results.filter { $0.error == nil && $0.damagedFrames.isEmpty && $0.differing == nil }
        let wrong = results.filter { !$0.holds }
        var s = "\(results.count) MP3 file\(results.count == 1 ? "" : "s"): \(same.count) decode to exactly dr_mp3's own "
            + "samples (as before the concealment), \(damaged.count) with damaged frames, \(failed.count) not decoded\n"
        for r in damaged + failed { s += "  " + line(r) + "\n" }
        if !wrong.isEmpty {
            s += "\(wrong.count) file\(wrong.count == 1 ? "" : "s") changed where no damaged frame explains it:\n"
            for r in wrong { s += "  " + line(r) + "\n" }
        }
        return (s, wrong.isEmpty)
    }
}
