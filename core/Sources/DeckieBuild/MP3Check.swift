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
        /// Where the samples differ from the pull reader's, in seconds; nil when they are the same.
        public var differing: ClosedRange<Double>?
        /// The true peak (dBTP) of the pull reader's samples and of the concealed ones, for a file with damaged frames.
        public var truePeakBefore: Double?, truePeakAfter: Double?
        /// Why the file could not be decoded, if it could not.
        public var error: String?

        /// Whether the concealment changed nothing it should not have: no difference at all, or differences only from
        /// the first damaged frame's start to three frames' time after the last one's.
        public var holds: Bool {
            guard let d = differing else { return true }
            guard let first = damagedFrames.first, let last = damagedFrames.last else { return false }
            return d.lowerBound >= first.startSeconds - 1e-9 && d.upperBound < last.startSeconds + 3 * last.seconds
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
                r.differing = c.differing.map { Double($0.lowerBound) / rate...Double($0.upperBound) / rate }
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

    /// One file's line: its damaged frames, where its samples differ and its true peak both ways.
    public static func line(_ r: FileResult) -> String {
        if let e = r.error { return "\(r.rel): not decoded: \(e)" }
        var s = r.rel + ": "
        if r.damagedFrames.isEmpty {
            s += "no damaged frame"
        } else {
            s += r.damagedFrames.map { "damaged frame at \(Py.fixed($0.startSeconds, 3)) s (\(Py.fixed($0.seconds * 1000, 1)) ms)" }
                .joined(separator: ", ")
        }
        if let d = r.differing {
            s += "; samples differ from dr_mp3's pull reader from \(Py.fixed(d.lowerBound, 4)) s to \(Py.fixed(d.upperBound, 4)) s"
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
