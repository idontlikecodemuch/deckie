/// Turns on the processor for tests that keep every core busy: the beat tracker's tests, which run the model. Swift
/// Testing runs the tests of a process side by side, and two model runs at once each take about twice as long, which
/// makes the times they print meaningless; inside `CPUTurns.exclusive` they run one at a time, while every other
/// test carries on around them. Waiting suspends the test; it does not hold a thread.
public actor CPUTurns {
    public static let shared = CPUTurns()

    private var busy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if !busy {
            busy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        if waiting.isEmpty { busy = false } else { waiting.removeFirst().resume() }
    }

    /// Runs `body` when no other `exclusive` body is running.
    public static func exclusive<T>(_ body: () async throws -> T) async rethrows -> T {
        await shared.acquire()
        do {
            let result = try await body()
            await shared.release()
            return result
        } catch {
            await shared.release()
            throw error
        }
    }
}
