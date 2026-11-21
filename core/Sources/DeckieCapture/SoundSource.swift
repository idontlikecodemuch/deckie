import Foundation

// Sound in, for the booth inside Desk (research booth-in-desk, step 1: hearing). Where sound comes from is a
// `SoundSource`: the computer's microphone or another input (`Microphone`, through miniaudio), or, for tests and tools,
// samples played as if they were captured (`SampleSource`). `LiveCapture` sits on top of either: it counts samples,
// measures a level a few times a second and hands the sound on.

/// The format sound arrives in: the input's own rate and channel count (nothing is resampled or mixed down here).
public struct SoundFormat: Sendable, Equatable {
    public var rate: Int
    public var channels: Int
    public init(rate: Int, channels: Int) { self.rate = rate; self.channels = channels }
}

/// Why sound could not be had, or stopped coming. `code` is plain and stable, for the windows' words
/// (`boothError.<code>`); `detail` is the system's own reason, for a log.
public struct CaptureError: Error, Sendable, Equatable, CustomStringConvertible {
    /// `noSystem` (the system's sound could not be reached), `noInput` (no such input, or none at all),
    /// `notAllowed` (the system refused: a privacy switch or permission), `busy` (another program holds the input for
    /// itself), `gone` (the input stopped without being asked: unplugged, or the system's sound restarted), `failed`.
    public var code: String
    public var detail: String
    public init(_ code: String, _ detail: String = "") { self.code = code; self.detail = detail }
    public var description: String { detail.isEmpty ? code : "\(code): \(detail)" }
}

/// Where sound comes from. `start` returns the format and then calls `sound` with each block as it arrives (on a
/// thread of the source's own: copy or hand on, and return quickly), and `ended` once if the sound stops without
/// `stop` being called (with the reason), never after `stop` has returned.
public protocol SoundSource: AnyObject, Sendable {
    /// The input's name, as the system gives it (or a name for a stand-in).
    var name: String { get }
    func start(sound: @escaping @Sendable (_ samples: [Float], _ format: SoundFormat) -> Void,
               ended: @escaping @Sendable (CaptureError) -> Void) throws -> SoundFormat
    /// Stops the sound; nothing more is delivered once this returns. Safe to call twice, or before `start`.
    func stop()
}

/// Samples played as if they were captured, for tests and tools: interleaved floats at `format`, delivered in blocks of
/// `blockSeconds` on a thread of their own, as fast as they can be taken (`pace` 0) or at `pace` times the speed of
/// sound (1: as a microphone would). `endsWith` makes the source end on its own after the samples, as an input that was
/// unplugged does (nil: it just goes quiet, delivering nothing more). `opensAfter` makes `start` take that many seconds
/// before it answers, as a system's sound that is slow or stuck does (tests of the time limits, Bounded.swift).
public final class SampleSource: SoundSource, @unchecked Sendable {
    public let name: String
    private let samples: [Float]
    private let format: SoundFormat
    private let blockSeconds: Double
    private let pace: Double
    private let endsWith: CaptureError?
    private let failsToStart: CaptureError?
    private let opensAfter: Double
    private let lock = NSLock()
    private var running = false
    private var thread: Thread?
    private var done: DispatchSemaphore?
    /// Frames delivered so far.
    public private(set) var delivered = 0

    public init(name: String = "Test sound", samples: [Float], format: SoundFormat, blockSeconds: Double = 0.05,
                pace: Double = 0, endsWith: CaptureError? = nil, failsToStart: CaptureError? = nil, opensAfter: Double = 0) {
        self.name = name; self.samples = samples; self.format = format; self.blockSeconds = blockSeconds
        self.pace = pace; self.endsWith = endsWith; self.failsToStart = failsToStart; self.opensAfter = opensAfter
    }

    public func start(sound: @escaping @Sendable ([Float], SoundFormat) -> Void,
                      ended: @escaping @Sendable (CaptureError) -> Void) throws -> SoundFormat {
        if opensAfter > 0 { Thread.sleep(forTimeInterval: opensAfter) }
        if let failsToStart { throw failsToStart }
        lock.lock()
        guard !running else { lock.unlock(); throw CaptureError("busy", "already started") }
        running = true
        let finished = DispatchSemaphore(value: 0)
        done = finished
        lock.unlock()
        let ch = max(1, format.channels)
        let block = max(1, Int(blockSeconds * Double(format.rate))) * ch
        let all = samples, fmt = format, pace = pace, endsWith = endsWith
        let t = Thread { [weak self] in
            var at = 0
            let start = DispatchTime.now().uptimeNanoseconds
            while at < all.count {
                guard let self, self.isRunning else { break }
                let end = min(all.count, at + block)
                sound(Array(all[at..<end]), fmt)
                at = end
                self.lock.lock(); self.delivered = at / ch; self.lock.unlock()
                if pace > 0 {
                    let due = Double(at / ch) / Double(fmt.rate) / pace
                    let now = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
                    if due > now { Thread.sleep(forTimeInterval: due - now) }
                }
            }
            if let self, self.isRunning, let e = endsWith {
                self.lock.lock(); self.running = false; self.lock.unlock()
                ended(e)
            }
            finished.signal()
        }
        t.stackSize = 4 << 20
        thread = t
        t.start()
        return format
    }

    private var isRunning: Bool { lock.lock(); defer { lock.unlock() }; return running }

    public func stop() {
        lock.lock()
        running = false
        let d = done
        done = nil
        lock.unlock()
        // Signalled again once seen, as in waitUntilPlayed: either may be waiting on it, and each must wake.
        d?.wait(); d?.signal()
    }

    /// Waits until every sample has been delivered (or the source was stopped): at most `seconds` (nil: for as long as
    /// it takes). False when the time ran out first.
    @discardableResult
    public func waitUntilPlayed(within seconds: Double? = nil) -> Bool {
        lock.lock(); let d = done; lock.unlock()
        guard let d else { return true }
        if let seconds {
            guard d.wait(timeout: .now() + seconds) == .success else { return false }
        } else {
            d.wait()
        }
        d.signal()
        return true
    }
}
