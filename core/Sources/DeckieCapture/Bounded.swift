import Foundation

// The system's sound is reached through C calls that can block for good. On Linux, miniaudio's PulseAudio backend
// connects to the sound server and then waits in `pa_mainloop_iterate` with no time limit until the server says ready
// or failed (`ma_wait_for_pa_context_to_connect__pulse`), and opening a stream and every operation wait the same way;
// a server that is hung, or a socket left by one that died, holds them there. ALSA opens devices in blocking mode
// (`snd_pcm_open` without SND_PCM_NONBLOCK, also to describe each one while listing), so it waits on a device another
// program holds, and ALSA's "default" can be its PulseAudio plugin, which waits as PulseAudio does. On Windows, WASAPI's device enumerator
// and `Activate` wait on the Windows Audio service while it starts or restarts; on the Mac, Core Audio's HAL calls wait
// on coreaudiod while it restarts. With no sound system at all (no PulseAudio or ALSA library, a build machine) the calls
// fail at once and nothing waits.
//
// So every such call (the context made, the inputs listed, an input opened, started, closed) runs on a thread of its
// own and is waited for at most `SoundInputs.answerWithin` seconds. Past that the caller is told plainly (`noSystem`)
// and the thread is given up on: it runs on to its end by itself and tidies up after itself (closing an input it
// opened late), so a blocked call never holds up the engine's messages, the window or a stop.

/// Runs `work` on a thread of its own and waits for it at most `seconds`. Returns what it gave, or nil when it had not
/// finished by then; `late` then gets what it gives when it does finish (to close what it opened).
func bounded<T>(seconds: Double, _ work: @escaping @Sendable () -> T, late: @escaping @Sendable (T) -> Void = { _ in }) -> T? {
    let box = BoundedBox<T>()
    let t = Thread {
        let r = work()
        box.lock.lock()
        if box.gaveUp { box.lock.unlock(); late(r); return }
        box.result = r
        box.lock.unlock()
        box.done.signal()
    }
    t.stackSize = 1 << 20
    t.start()
    _ = box.done.wait(timeout: .now() + max(0, seconds))
    box.lock.lock(); defer { box.lock.unlock() }
    if let r = box.result { return r }
    box.gaveUp = true
    return nil
}

final class BoundedBox<T>: @unchecked Sendable {
    let lock = NSLock()
    var result: T?
    var gaveUp = false
    let done = DispatchSemaphore(value: 0)
}

/// A source whose `start` and `stop` are each waited for at most `seconds` (`SoundInputs.answerWithin`): a start that
/// has not answered by then throws `noSystem`, and a stop returns all the same. Nothing is delivered once `stop` has
/// returned or a start has been given up on, and an input that opens after its start was given up on (or after a stop
/// came meanwhile) is closed again at once. `Microphone` is the system's input through one of these.
public final class BoundedSource: SoundSource, @unchecked Sendable {
    public let inner: SoundSource
    public let seconds: Double
    private let lock = NSLock()
    private var gate: Gate?

    /// Lets sound through until closed.
    final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var open = true
        var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return open }
        func close() { lock.lock(); open = false; lock.unlock() }
    }

    public init(_ inner: SoundSource, within seconds: Double = SoundInputs.answerWithin) {
        self.inner = inner
        self.seconds = seconds
    }

    public var name: String { inner.name }

    public func start(sound: @escaping @Sendable ([Float], SoundFormat) -> Void,
                      ended: @escaping @Sendable (CaptureError) -> Void) throws -> SoundFormat {
        let g = Gate()
        lock.lock(); gate?.close(); gate = g; lock.unlock()
        let inner = self.inner
        let answer = bounded(seconds: seconds, { () -> Result<SoundFormat, Error> in
            let r = Result { try inner.start(sound: { s, f in if g.isOpen { sound(s, f) } },
                                             ended: { e in if g.isOpen { ended(e) } }) }
            // Given up on, or stopped while it opened: closed again at once.
            if case .success = r, !g.isOpen { inner.stop() }
            return r
        })
        guard let answer else {
            g.close()
            throw CaptureError("noSystem", "the system's sound did not open the input within \(Self.plain(seconds)) seconds")
        }
        return try answer.get()
    }

    public func stop() {
        lock.lock(); let g = gate; gate = nil; lock.unlock()
        guard let g else { return }   // never started, or stopped already
        g.close()
        let inner = self.inner
        _ = bounded(seconds: seconds, { inner.stop() })
    }

    static func plain(_ s: Double) -> String { s == s.rounded() ? String(Int(s)) : String(s) }
}
