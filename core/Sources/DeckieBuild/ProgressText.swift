import Foundation
import DeckieCore

/// The build's progress as lines of text, one per event: the start, then one per file of the queue with the count,
/// the time since the start, an estimate of the time left and the file's own time.
///
///     4 audio files; 0 unchanged since the last run; 4 to look at, 4 at a time
///     [1/4]  0:00:00 elapsed               protected   locked.m4p: protected, cannot be read
///     [2/4]  0:00:06 elapsed  ~0:00:12 left  6.1 s       Track.wav
public enum ProgressText {
    public static func line(_ event: BuildEvent) -> String {
        switch event {
        case .started(let files, let unchanged, let queued, let jobs, let rekordbox):
            var s = "\(files) audio file\(files == 1 ? "" : "s"); \(unchanged) unchanged since the last run; "
                + (queued == 0 ? "nothing to analyse" : "\(queued) to look at, \(min(jobs, queued)) at a time")
            if let rb = rekordbox { s += "; rekordbox: \(rb.matched) of \(rb.tracks) collection tracks match a file" }
            return s
        case .file(let p):
            let width = String(p.total).count
            let count = "[" + String(repeating: " ", count: width - String(p.done).count) + "\(p.done)/\(p.total)]"
            let left = p.remaining.map { "~\(clock($0)) left" } ?? ""
            let head = "\(count)  \(clock(p.elapsed)) elapsed  " + left.padding(toLength: 13, withPad: " ", startingAt: 0)
            switch p.outcome {
            case .analysed(let seconds):
                return head + "  " + (Py.fixed(seconds, 1) + " s").padding(toLength: 10, withPad: " ", startingAt: 0)
                    + "  " + p.rel
            case .reused:
                return head + "  " + "reused".padding(toLength: 10, withPad: " ", startingAt: 0) + "  " + p.rel
                    + " (the same bytes were analysed before)"
            case .failed(let f):
                return head + "  " + f.reason.padding(toLength: 10, withPad: " ", startingAt: 0) + "  " + p.rel + ": "
                    + f.message
            }
        case .writing(let tracks):
            return "writing the crate: \(tracks) track\(tracks == 1 ? "" : "s")"
        }
    }
}
