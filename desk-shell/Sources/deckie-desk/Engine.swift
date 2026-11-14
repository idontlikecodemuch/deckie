import Foundation

/// The engine program (`deckie-desk-engine`) as a child of the window: requests written to its standard input, one
/// line each; each line it writes handed to `onLine` (on a thread of its own); its standard error passed through to
/// the shell's. It stops when its input is closed (docs/architecture/desk-protocol.md).
final class EngineProcess: @unchecked Sendable {
    let process = Process()
    private let input = Pipe(), output = Pipe(), errors = Pipe()
    private let writeLock = NSLock()

    init(executable: URL, environment: [String: String] = [:], onLine: @escaping @Sendable (String) -> Void,
         onExit: @escaping @Sendable (Int32) -> Void) throws {
        process.executableURL = executable
        var env = ProcessInfo.processInfo.environment
        for (k, v) in environment { env[k] = v }
        process.environment = env
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { p in onExit(p.terminationStatus) }
        try process.run()
        let out = output.fileHandleForReading
        Thread.detachNewThread {
            var buffer = Data()
            while true {
                let d = out.availableData
                if d.isEmpty { break }
                buffer.append(d)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    var line = Data(buffer[buffer.startIndex..<nl])
                    if line.last == 0x0D { line.removeLast() }
                    buffer = Data(buffer[(nl + 1)...])
                    onLine(String(decoding: line, as: UTF8.self))
                }
            }
        }
        let err = errors.fileHandleForReading
        Thread.detachNewThread {
            while true {
                let d = err.availableData
                if d.isEmpty { break }
                Notice.pass(d)
            }
        }
    }

    /// Sends one message (a JSON object as text, no line feed).
    func send(_ text: String) {
        writeLock.lock(); defer { writeLock.unlock() }
        guard process.isRunning else { return }
        var data = Data(text.utf8)
        data.append(0x0A)
        input.fileHandleForWriting.write(data)
    }

    /// Closes its input, so it ends; waits up to `seconds`, then stops it.
    func stop(seconds: Double = 5) {
        writeLock.lock()
        try? input.fileHandleForWriting.close()
        writeLock.unlock()
        let end = Date().addingTimeInterval(seconds)
        while process.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate() }
    }
}
