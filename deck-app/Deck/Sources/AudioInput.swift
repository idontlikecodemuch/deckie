import AVFoundation
import Foundation

// The sound input's plumbing that can be tested without an iPad: which input channels are heard and recorded
// (`ChannelMap`), and what listening does when iPadOS takes the sound away or the input changes (`ListenGuard`). The
// microphone itself (`MicCapture`, Recognizer.swift) and the set recorder (SetRecorder.swift) use them.

/// A sound input's shape: its sample rate and how many channels it has.
struct AudioShape: Equatable, Sendable, CustomStringConvertible {
    var sampleRate: Double
    var channels: Int
    init(sampleRate: Double, channels: Int) { self.sampleRate = sampleRate; self.channels = channels }
    init(_ f: AVAudioFormat) { sampleRate = f.sampleRate; channels = Int(f.channelCount) }
    var description: String { "\(Int(sampleRate)) Hz, \(channels) ch" }
}

/// Which of the input's channels Deckie hears and records, and how they are mixed.
///
/// The choice: a mono input (the iPad's own microphone) is kept as it is; a stereo input is kept as it is; an input of
/// more channels (an audio interface with 4 or 8 inputs) is heard and recorded from its first pair, inputs 1 and 2,
/// which is where DJ mixers and interfaces put the master. The other inputs are not mixed in: on a DJ interface they
/// are usually a deck, a cue or a microphone, and mixing them into the set would put the cue in the recording.
/// So no sound is lost without a word, `CaptureSink` watches the inputs left out and says once, in the log and in the
/// set's log, when they carry sound.
///
/// Going the other way (the recording's channels, fixed when it began, and an input that changed since):
/// mono into a stereo recording puts the one channel on both sides; stereo into a mono recording averages the two.
enum ChannelMap {
    /// How many channels are kept from an input of `n`: 1 from a mono input, 2 from anything wider.
    static func kept(_ n: Int) -> Int { n <= 1 ? 1 : 2 }

    /// For each output channel (1 or 2), the input channels averaged into it (0-based).
    static func sources(input n: Int, output m: Int) -> [[Int]] {
        precondition(n >= 1 && (m == 1 || m == 2))
        if m == 1 { return [n == 1 ? [0] : [0, 1]] }
        return n == 1 ? [[0], [0]] : [[0], [1]]
    }

    /// The inputs (1-based, as an interface labels them) that are not heard: "3–4" of a 4-channel input; nil when
    /// every input is heard.
    static func leftOut(_ n: Int) -> ClosedRange<Int>? { n > 2 ? 3...n : nil }

    /// The one place channels are mixed. `channel(c)` points at input channel c's first sample and `stride` is the
    /// step from one frame to the next (1 for separate channels, the channel count for interleaved ones). Each output
    /// pointer gets `frames` samples.
    static func mix(frames: Int, inputChannels n: Int, stride: Int, channel: (Int) -> UnsafePointer<Float>,
                    into out: [UnsafeMutablePointer<Float>]) {
        let map = sources(input: n, output: out.count)
        for (o, ins) in map.enumerated() {
            let dst = out[o]
            if ins.count == 1 {
                let src = channel(ins[0])
                for i in 0..<frames { dst[i] = src[i * stride] }
            } else {
                let a = channel(ins[0]), b = channel(ins[1])
                for i in 0..<frames { dst[i] = 0.5 * (a[i * stride] + b[i * stride]) }
            }
        }
    }

    /// Separate channels (one array per channel) to `output` channels.
    static func mix(planar: [[Float]], output m: Int) -> [[Float]] {
        let n = planar.count, frames = planar.first?.count ?? 0
        var out = [[Float]](repeating: [Float](repeating: 0, count: frames), count: m)
        let ins = planar.map { a -> UnsafeMutablePointer<Float> in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: max(1, frames)); p.initialize(from: a, count: frames); return p
        }
        let outs = (0..<m).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: max(1, frames)) }
        defer { ins.forEach { $0.deallocate() }; outs.forEach { $0.deallocate() } }
        mix(frames: frames, inputChannels: n, stride: 1, channel: { UnsafePointer(ins[$0]) }, into: outs)
        for o in 0..<m { out[o] = Array(UnsafeBufferPointer(start: outs[o], count: frames)) }
        return out
    }

    /// Interleaved samples (frame by frame, `channels` to a frame) to `output` separate channels.
    static func mix(interleaved: [Float], channels n: Int, output m: Int) -> [[Float]] {
        let frames = interleaved.count / n
        let outs = (0..<m).map { _ in UnsafeMutablePointer<Float>.allocate(capacity: max(1, frames)) }
        defer { outs.forEach { $0.deallocate() } }
        interleaved.withUnsafeBufferPointer { src in
            mix(frames: frames, inputChannels: n, stride: n, channel: { src.baseAddress! + $0 }, into: outs)
        }
        return outs.map { Array(UnsafeBufferPointer(start: $0, count: frames)) }
    }

    /// The format of `m` separate 32-bit channels at `f`'s sample rate.
    static func format(_ f: AVAudioFormat, channels m: Int) -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: f.sampleRate, channels: AVAudioChannelCount(m), interleaved: false)
    }

    /// A new buffer of `m` separate channels (default: the channels kept from `b`), mixed from `b`, interleaved or
    /// not. Nil when `b` holds no 32-bit samples (the input tap always gives them).
    static func apply(_ b: AVAudioPCMBuffer, channels m: Int? = nil) -> AVAudioPCMBuffer? {
        let n = Int(b.format.channelCount), frames = Int(b.frameLength)
        guard n > 0, let data = b.floatChannelData else { return nil }
        let outCh = m ?? kept(n)
        guard let f = format(b.format, channels: outCh), let out = AVAudioPCMBuffer(pcmFormat: f, frameCapacity: max(1, b.frameLength)),
              let dst = out.floatChannelData else { return nil }
        out.frameLength = b.frameLength
        let outs = (0..<outCh).map { dst[$0] }
        if b.format.isInterleaved {
            let base = data[0]
            mix(frames: frames, inputChannels: n, stride: b.stride, channel: { UnsafePointer(base + $0) }, into: outs)
        } else {
            mix(frames: frames, inputChannels: n, stride: 1, channel: { UnsafePointer(data[$0]) }, into: outs)
        }
        return out
    }

    /// The loudest sample (absolute) on the inputs left out of `b` (channels 3 and on), 0 when none are.
    static func peakLeftOut(_ b: AVAudioPCMBuffer) -> Float {
        let n = Int(b.format.channelCount), frames = Int(b.frameLength)
        guard n > 2, let data = b.floatChannelData else { return 0 }
        var peak: Float = 0
        for c in 2..<n {
            let p: UnsafePointer<Float> = b.format.isInterleaved ? UnsafePointer(data[0] + c) : UnsafePointer(data[c])
            let s = b.format.isInterleaved ? b.stride : 1
            for i in 0..<frames { peak = max(peak, abs(p[i * s])) }
        }
        return peak
    }
}

/// What listening does when the sound is taken away or the input changes under it: a phone call, Siri or an alarm
/// (iPadOS's interruptions), an audio interface plugged in or out (a route change), the audio engine's own
/// configuration change, or iPadOS's audio restarting. Fed events, it says what to do; it holds no audio itself, so it
/// is tested with made-up events (DeckTests/AudioInputTests). The Recognizer feeds it the real notifications.
///
/// - Interrupted: the microphone stops cleanly; when the interruption ends with "may resume", listening starts again at
///   once. Without it (another app still has the sound), and whenever a start fails, it tries again every
///   `retryEvery` seconds and whenever the app comes to the front (iPadOS does not always say an interruption ended).
/// - The input changed (an interface plugged in or out, a new format): the microphone is started again with the input
///   as it is now. A different format is passed on (`formatChanged`) so the recognisers start fresh with it; the set's
///   recording follows it in the same file.
/// - Every stretch without sound is a gap, said when it starts and when it ends, with how long it was.
struct ListenGuard: Equatable {
    enum State: Equatable {
        /// Not listening (the DJ's Stop, or not started).
        case off
        case running
        /// iPadOS took the sound (a call, Siri, an alarm).
        case interrupted
        /// Starting the microphone again.
        case restarting
        /// Cannot listen just now (no input, or the input will not start); tries again by itself.
        case stalled(String)
    }
    /// What a route change was, as far as listening cares.
    enum Route: Equatable { case deviceAdded, deviceRemoved, noInput, other }
    enum Event: Equatable {
        case started(AudioShape), stopped
        /// Listening was asked for but the microphone would not start (another app has the sound, no input).
        case startFailed(String)
        case interruptionBegan, interruptionEnded(shouldResume: Bool)
        case configurationChanged, routeChanged(Route), mediaReset
        case restarted(AudioShape), restartFailed(String)
        case appActive, tick
    }
    enum Action: Equatable {
        /// Stop the engine and its tap (the session is left to iPadOS).
        case pauseCapture
        /// Start the engine and its tap again, with the input as it is now.
        case restartCapture
        case gapBegan(why: String)
        case gapEnded(seconds: Double, why: String)
        case formatChanged(from: AudioShape, to: AudioShape)
    }
    static let retryEvery: TimeInterval = 5
    /// Why a gap began, in the log's words.
    static let whyInterrupted = "interrupted (a call, Siri or an alarm)"
    static let whyInputChanged = "the sound input changed"
    static let whyNoInput = "no sound input"
    static let whyReset = "the iPad's audio restarted"

    private(set) var state: State = .off
    private(set) var shape: AudioShape?
    private(set) var gapStart: Date?
    private(set) var gapWhy = ""
    private var lastTry: Date?

    /// Whether the sound is coming in now (false while off, too).
    var hearing: Bool { state == .running }

    mutating func handle(_ e: Event, now: Date) -> [Action] {
        if case .stopped = e { self = ListenGuard(); return [] }
        if case .started(let s) = e { self = ListenGuard(); state = .running; shape = s; return [] }
        if case .startFailed(let why) = e { self = ListenGuard(); state = .stalled(why); lastTry = now; return [] }
        switch (state, e) {
        case (.off, _):
            return []

        case (.interrupted, .interruptionBegan):
            return []
        case (_, .interruptionBegan):
            var out = beginGap(Self.whyInterrupted, now)
            state = .interrupted
            out.append(.pauseCapture)
            return out

        case (.interrupted, .interruptionEnded(let resume)), (.stalled, .interruptionEnded(let resume)):
            if resume { return restart(now) }
            state = .stalled(Self.whyInterrupted); lastTry = now
            return []
        case (_, .interruptionEnded):
            return []

        case (.running, .configurationChanged), (.running, .routeChanged(.deviceAdded)), (.running, .routeChanged(.deviceRemoved)):
            return beginGap(Self.whyInputChanged, now) + restart(now)
        case (.stalled, .routeChanged(.deviceAdded)), (.stalled, .configurationChanged):
            return restart(now)
        case (.running, .routeChanged(.noInput)):
            var out = beginGap(Self.whyNoInput, now)
            state = .stalled(Self.whyNoInput); lastTry = now
            out.append(.pauseCapture)
            return out
        case (_, .routeChanged), (_, .configurationChanged):
            return []      // interrupted: the start at its end takes the input as it is then; restarting: in hand

        case (.interrupted, .mediaReset):
            return []
        case (_, .mediaReset):
            return beginGap(Self.whyReset, now) + restart(now)

        case (.restarting, .restarted(let s)), (.stalled, .restarted(let s)), (.interrupted, .restarted(let s)):
            var out: [Action] = []
            if let g = gapStart { out.append(.gapEnded(seconds: now.timeIntervalSince(g), why: gapWhy)) }
            if let old = shape, old != s { out.append(.formatChanged(from: old, to: s)) }
            state = .running; shape = s; gapStart = nil; gapWhy = ""
            return out
        case (_, .restarted):
            return []
        case (.restarting, .restartFailed(let why)):
            state = .stalled(why)
            return []
        case (_, .restartFailed):
            return []

        case (.stalled, .tick):
            guard now.timeIntervalSince(lastTry ?? .distantPast) >= Self.retryEvery else { return [] }
            return restart(now)
        case (_, .tick):
            return []

        case (.interrupted, .appActive), (.stalled, .appActive):
            return restart(now)
        case (_, .appActive):
            return []

        case (_, .started), (_, .stopped), (_, .startFailed):
            return []      // handled above
        }
    }

    private mutating func beginGap(_ why: String, _ now: Date) -> [Action] {
        guard gapStart == nil else { return [] }
        gapStart = now; gapWhy = why
        return [.gapBegan(why: why)]
    }
    private mutating func restart(_ now: Date) -> [Action] {
        state = .restarting; lastTry = now
        return [.restartCapture]
    }
}

extension ListenGuard.Event {
    /// An interruption notification's event (nil for one it does not understand).
    static func interruption(_ info: [AnyHashable: Any]?) -> ListenGuard.Event? {
        guard let raw = info?[AVAudioSessionInterruptionTypeKey] as? UInt, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
        switch type {
        case .began: return .interruptionBegan
        case .ended:
            let opts = AVAudioSession.InterruptionOptions(rawValue: info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
            return .interruptionEnded(shouldResume: opts.contains(.shouldResume))
        @unknown default: return nil
        }
    }

    /// A route change notification's event, from its reason and whether the route has an input now.
    static func routeChange(_ info: [AnyHashable: Any]?, hasInput: Bool) -> ListenGuard.Event? {
        guard let raw = info?[AVAudioSessionRouteChangeReasonKey] as? UInt, let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return nil }
        if !hasInput { return .routeChanged(.noInput) }
        switch reason {
        case .newDeviceAvailable: return .routeChanged(.deviceAdded)
        case .oldDeviceUnavailable: return .routeChanged(.deviceRemoved)
        case .noSuitableRouteForCategory: return .routeChanged(.noInput)
        case .override, .routeConfigurationChange: return .routeChanged(.deviceAdded)   // the input may be another now
        default: return .routeChanged(.other)   // category change, wake from sleep, unknown: nothing to do
        }
    }
}

/// Where every buffer of sound goes, from the microphone's tap or a test file: the channels kept (`ChannelMap`), then
/// the recognisers and the set recorder. The recognisers can be swapped while it runs (a new input format).
final class CaptureSink: @unchecked Sendable {
    private let lock = NSLock()
    private var ears: [Ear]
    private let recorder: SetRecorder
    private var warnedShape: AudioShape?
    private let report: @Sendable (String) -> Void

    /// `report`: a line for the log, called on the audio thread, once for each input shape whose left-out inputs carry
    /// sound.
    init(ears: [Ear], recorder: SetRecorder, report: @escaping @Sendable (String) -> Void) {
        self.ears = ears; self.recorder = recorder; self.report = report
    }

    func setEars(_ e: [Ear]) { lock.lock(); ears = e; lock.unlock() }

    /// The level a left-out input must reach to be called sound (about -50 dBFS).
    static let leftOutSound: Float = 0.003

    func take(_ buf: AVAudioPCMBuffer, at when: AVAudioTime?) {
        let n = Int(buf.format.channelCount)
        if let left = ChannelMap.leftOut(n) {
            let shape = AudioShape(buf.format)
            lock.lock(); let warned = warnedShape == shape; lock.unlock()
            if !warned, ChannelMap.peakLeftOut(buf) > Self.leftOutSound {
                lock.lock(); warnedShape = shape; lock.unlock()
                let line = "inputs \(left.lowerBound)–\(left.upperBound) of \(n) carry sound; Deckie hears and records inputs 1–2 only"
                report(line); recorder.note(line)
            }
        }
        guard let kept = ChannelMap.apply(buf) else { recorder.skip("the input gave no samples Deckie can read"); return }
        lock.lock(); let es = ears; lock.unlock()
        for e in es { e.hear(kept, at: when) }
        recorder.append(kept)
    }
}
