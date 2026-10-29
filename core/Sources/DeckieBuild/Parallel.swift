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
/// track peaks at about 1.1 GB, 0.2 GB of it the models, which the jobs share; each further job adds about 0.9 GB,
/// almost all of it the beat model's working memory for one 30-second chunk (measured on Linux in a release build
/// with deckie-memprobe: 1.1 GB for one job, 3.8 GB for four). So a job is given 1 GB and 2 GB are left for
/// everything else. (Before ONNX Runtime's arena was shrunk after each run, one job peaked at 1.9 GB and four at
/// 5.6 GB, and a job was given 2 GB.)
public var defaultJobs: Int {
    let gb = Double(ProcessInfo.processInfo.physicalMemory) / Double(1 << 30)
    return max(1, min(processorCount, Int(gb - 2)))
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
