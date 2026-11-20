import Foundation

/// Runs `body(i)` for every `i` in `0..<count` on `workers` threads of their own, each taking the next index as it
/// finishes one, and returns when all are done. Threads rather than Swift tasks, because each body is a long piece of
/// blocking computation (a track's analysis) that should not hold the shared task threads.
func runParallel(count: Int, workers: Int, _ body: @escaping @Sendable (Int) -> Void) {
    guard count > 0 else { return }
    final class Next: @unchecked Sendable {
        let lock = NSLock()
        var value = 0
        func take(below count: Int) -> Int? {
            lock.lock(); defer { lock.unlock() }
            guard value < count else { return nil }
            defer { value += 1 }
            return value
        }
    }
    let next = Next()
    let n = max(1, min(workers, count))
    if n == 1 {
        while let i = next.take(below: count) { body(i) }
        return
    }
    let group = DispatchGroup()
    for _ in 0..<n {
        group.enter()
        let thread = Thread {
            while let i = next.take(below: count) { body(i) }
            group.leave()
        }
        thread.stackSize = 16 << 20
        thread.start()
    }
    group.wait()
}

/// The machine's processor count.
public var processorCount: Int { max(1, ProcessInfo.processInfo.activeProcessorCount) }

/// The default number of jobs: the processor count, or fewer when memory is short. One analysis of a four-minute
/// track peaks at about 1.1 GB, 0.2 GB of it the models, which the jobs share; each further job adds about 1 GB,
/// almost all of it the beat model's working memory for one 30-second chunk (measured on Linux in a release build:
/// deckie-build peaked at 1.09 GB for one job and 4.4 GB for four). A job is given 1.5 GB and 2 GB are left for
/// everything else (`JobMemory`, which says why 1.5). (Before the beat model shrank ONNX Runtime's arena after a track's first and last chunk, one job
/// peaked at 1.9 GB and four at 5.5 GB, and a job was given 2 GB.) docs/research/p-machine-estimates.md estimates what
/// this gives on DJs' machines.
public var defaultJobs: Int {
    max(1, min(processorCount, JobMemory.jobsAllowed(physicalMemory: ProcessInfo.processInfo.physicalMemory)))
}

/// The jobs memory allows, the one rule `defaultJobs` (deckie-build) and Deckie Desk (`DeskJobs`) both use: a job is
/// given `gigabytesPerJob` and `gigabytesKept` are left for the system and other programs, never fewer than one job:
/// 4 GB gives 1 job, 6 GB 2, 8 GB 4. Why 1.5 GB a job and not the builder's 1 GB further a job measured above: Desk's
/// own measured peaks a job are 1.1 GB on Windows (two music CD runs in a virtual machine, Nov 20 2026) and 1.6 to
/// 1.8 GB on the Mac, for a four-minute song, growing about 37 MB a minute of song, so 1 GB a job leaves no margin.
/// It is a safety allowance from those measurements, not tuned to any machine; deckie-build's default follows it.
public enum JobMemory {
    public static let gigabytesPerJob = 1.5
    public static let gigabytesKept = 2.0

    /// The jobs `physicalMemory` bytes (`ProcessInfo.physicalMemory`) allow.
    public static func jobsAllowed(physicalMemory: UInt64) -> Int {
        let gb = Double(physicalMemory) / Double(1 << 30)
        return max(1, Int((gb - gigabytesKept) / gigabytesPerJob))
    }
}

/// Seconds as `0:04:07` (or `1:02:03:04` past a day, never needed).
public func clock(_ seconds: Double) -> String {
    let s = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
}

/// Now, UTC to the second, as the crate writes times.
func utcNow(_ date: Date = Date()) -> String {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(identifier: "UTC")
    f.formatOptions = [.withInternetDateTime]
    return f.string(from: date)
}

func median(_ v: [Double]) -> Double? {
    guard !v.isEmpty else { return nil }
    let s = v.sorted()
    return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
}

func mean(_ v: [Double]) -> Double? { v.isEmpty ? nil : v.reduce(0, +) / Double(v.count) }
