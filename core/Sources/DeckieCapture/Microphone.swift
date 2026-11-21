import Foundation
import CMiniaudio

/// An input sound can be taken from: the computer's own microphone, a USB microphone, an audio interface, a mixer's
/// USB output. `id` is the system's own name for it, as bytes; `name` is what the system shows a person.
public struct SoundInput: Sendable, Equatable {
    public var name: String
    /// The input the system's sound settings choose.
    public var isDefault: Bool
    let id: [UInt8]
}

/// The inputs this computer has, through miniaudio (WASAPI on Windows, Core Audio on the Mac, PulseAudio or ALSA on
/// Linux). Listing opens no input and asks for no permission.
public enum SoundInputs {
    public struct Listed: Sendable {
        public var inputs: [SoundInput]
        /// The system's sound interface used: "WASAPI", "Core Audio", "PulseAudio", "ALSA".
        public var system: String
    }

    public static func list() throws -> Listed {
        var system = [CChar](repeating: 0, count: 64)
        var message = [CChar](repeating: 0, count: 256)
        let most = 64
        var raw = [deckie_capture_input](repeating: deckie_capture_input(), count: most)
        let n = raw.withUnsafeMutableBufferPointer { p in
            deckie_capture_list(p.baseAddress, Int32(most), &system, system.count, &message, message.count)
        }
        guard n >= 0 else { throw CaptureError("noSystem", Self.text(message)) }
        var out: [SoundInput] = []
        for i in 0..<min(Int(n), most) {
            var item = raw[i]
            let name = withUnsafeBytes(of: &item.name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let id = withUnsafeBytes(of: &item.id) { Array($0) }
            out.append(SoundInput(name: name, isDefault: item.is_default != 0, id: id))
        }
        // The system's default first, then as the system lists them.
        out.sort { $0.isDefault && !$1.isDefault }
        return Listed(inputs: out, system: Self.text(system))
    }

    static func text(_ c: [CChar]) -> String {
        String(decoding: c.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// The input of that name, else (for nil, empty, or a name no longer there) nil: the caller then takes the
    /// system's default.
    public static func named(_ name: String?, in listed: [SoundInput]) -> SoundInput? {
        guard let name, !name.isEmpty else { return nil }
        return listed.first { $0.name == name } ?? listed.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }
    }
}

/// A real input through miniaudio, opened in shared mode at its own rate and channel count, with no voice processing
/// asked for (`deckie_capture.c` says what each system allows). `input` nil is the system's default input.
public final class Microphone: SoundSource, @unchecked Sendable {
    public private(set) var name: String
    private let input: SoundInput?
    private let lock = NSLock()
    private var capture: OpaquePointer?
    private var box: Unmanaged<Callbacks>?

    final class Callbacks: @unchecked Sendable {
        let sound: @Sendable ([Float], SoundFormat) -> Void
        let ended: @Sendable (CaptureError) -> Void
        var format = SoundFormat(rate: 0, channels: 0)
        let lock = NSLock()
        var over = false
        init(sound: @escaping @Sendable ([Float], SoundFormat) -> Void, ended: @escaping @Sendable (CaptureError) -> Void) {
            self.sound = sound; self.ended = ended
        }
        /// Once only, and never after a stop.
        func end(_ e: CaptureError) {
            lock.lock(); let first = !over; over = true; lock.unlock()
            if first { ended(e) }
        }
        func silence() { lock.lock(); over = true; lock.unlock() }
    }

    public init(_ input: SoundInput? = nil) {
        self.input = input
        name = input?.name ?? ""
    }

    static func code(_ c: Int32) -> String {
        switch c {
        case DECKIE_CAPTURE_NO_SYSTEM: return "noSystem"
        case DECKIE_CAPTURE_NO_INPUT: return "noInput"
        case DECKIE_CAPTURE_NOT_ALLOWED: return "notAllowed"
        case DECKIE_CAPTURE_BUSY: return "busy"
        default: return "failed"
        }
    }

    public func start(sound: @escaping @Sendable ([Float], SoundFormat) -> Void,
                      ended: @escaping @Sendable (CaptureError) -> Void) throws -> SoundFormat {
        lock.lock(); defer { lock.unlock() }
        guard capture == nil else { throw CaptureError("busy", "already started") }
        let callbacks = Callbacks(sound: sound, ended: ended)
        let retained = Unmanaged.passRetained(callbacks)
        var rate: UInt32 = 0, channels: UInt32 = 0, error: Int32 = 0
        var message = [CChar](repeating: 0, count: 256)
        let onSound: deckie_capture_sound = { user, samples, frames, channels in
            guard let user, let samples else { return }
            let c = Unmanaged<Callbacks>.fromOpaque(user).takeUnretainedValue()
            let block = Array(UnsafeBufferPointer(start: samples, count: Int(frames) * Int(channels)))
            c.sound(block, c.format)
        }
        let onEvent: deckie_capture_event = { user, event in
            guard let user else { return }
            let c = Unmanaged<Callbacks>.fromOpaque(user).takeUnretainedValue()
            if event == DECKIE_CAPTURE_GONE { c.end(CaptureError("gone", "the input stopped")) }
        }
        let opened: OpaquePointer? = {
            if let input {
                return input.id.withUnsafeBufferPointer { id in
                    deckie_capture_open(id.baseAddress, onSound, onEvent, retained.toOpaque(), &rate, &channels, &error, &message, message.count)
                }
            }
            return deckie_capture_open(nil, onSound, onEvent, retained.toOpaque(), &rate, &channels, &error, &message, message.count)
        }()
        guard let opened else {
            retained.release()
            throw CaptureError(Self.code(error), SoundInputs.text(message))
        }
        let format = SoundFormat(rate: Int(rate), channels: Int(channels))
        callbacks.format = format
        var shown = [CChar](repeating: 0, count: 256)
        deckie_capture_name(opened, &shown, shown.count)
        let opensAs = SoundInputs.text(shown)
        if !opensAs.isEmpty { name = opensAs }
        let started = deckie_capture_start(opened)
        guard started == DECKIE_CAPTURE_OK else {
            deckie_capture_close(opened)
            retained.release()
            throw CaptureError(Self.code(started), "the input would not start")
        }
        capture = opened
        box = retained
        return format
    }

    public func stop() {
        lock.lock()
        let c = capture, b = box
        capture = nil; box = nil
        lock.unlock()
        b?.takeUnretainedValue().silence()
        if let c { deckie_capture_close(c) }   // no callback runs once this returns
        b?.release()
    }

    deinit { stop() }
}
