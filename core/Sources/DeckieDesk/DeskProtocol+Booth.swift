import Foundation
import DeckieCrate
import DeckieDecode
import DeckieCapture

// Listening inside Desk (research booth-in-desk, step 1): the `booth.*` requests and events
// (docs/architecture/desk-protocol.md, "Listening"). Additions only; the protocol stays 2.
//
// While a run reads music, listening waits: `booth.listen` is refused with `busy` (as every request that is not
// read-only is), and a run that starts while listening stops the listening first (`booth.state` `stopped`). Reading
// music and listening are never both going, so neither slows the other and only one thing holds the processor.

extension DeskProtocol {
    /// The engine's stand-in for an input, for checks and pictures with no microphone: `DECKIE_BOOTH_SOUND` names an
    /// audio file, played as if it were heard, at the speed of sound; `booth.inputs` then lists it alone.
    static let soundStandIn = "DECKIE_BOOTH_SOUND"

    /// The inputs this computer has (the stand-in alone when the environment names one).
    func boothInputs() throws -> (inputs: [[String: Any]], system: String) {
        if let file = environment[Self.soundStandIn] {
            return ([["name": URL(fileURLWithPath: file).lastPathComponent, "default": true]], "stand-in")
        }
        let listed = try SoundInputs.list()
        return (listed.inputs.map { ["name": $0.name, "default": $0.isDefault] }, listed.system)
    }

    /// The source for an input by its name (nil or "": the system's default).
    func boothSource(_ name: String?) throws -> SoundSource {
        if let made = makeSoundSource { return try made(name) }
        if let file = environment[Self.soundStandIn] {
            let b = try AudioDecoder.decode(URL(fileURLWithPath: file))
            return SampleSource(name: URL(fileURLWithPath: file).lastPathComponent, samples: b.samples,
                                format: SoundFormat(rate: b.sampleRate, channels: b.channelCount), pace: 1)
        }
        let listed = try SoundInputs.list()
        return Microphone(SoundInputs.named(name, in: listed.inputs))
    }

    /// Called with the lock held.
    func boothRequest(_ type: String, _ obj: [String: Any], _ id: Any?) throws {
        switch type {
        case "booth.inputs":
            do {
                let (inputs, system) = try boothInputs()
                reply(id, ["inputs": inputs, "system": system])
            } catch let e as CaptureError {
                throw RequestError(code: "no_sound", detail: e.code)
            }
        case "booth.listen":
            guard let info = session.current, let crate = session.crate else { throw RequestError(code: "no_crate", detail: nil) }
            if let wanted = obj["crate"] as? String, wanted != info.id { throw RequestError(code: "bad_request", detail: "not the crate showing") }
            stopBooth()
            let source: SoundSource
            do { source = try boothSource(obj["input"] as? String) }
            catch let e as CaptureError { throw RequestError(code: "no_sound", detail: e.code) }
            let crateId = info.id
            let b = DeskBooth(crate: crate, indexAt: session.shelf.file(DeskBooth.indexFile, of: crateId), source: source) { [weak self] e in
                self?.sendBooth(e, crate: crateId)
            }
            booth = b
            reply(id, ["crate": crateId, "songs": b.songCount])
            b.start()
        case "booth.stop":
            stopBooth()
            reply(id)
        default:
            throw RequestError(code: "unknown_type", detail: type)
        }
    }

    /// Stops listening, if it is going (leaving the mode, another crate, a run, the engine quitting). Called with the
    /// lock held, or before the engine exits.
    public func stopBooth() {
        let b = booth
        booth = nil
        b?.stop()
    }

    func sendBooth(_ e: DeskBooth.Event, crate: String) {
        switch e {
        case let .status(s):
            var m: [String: Any] = ["event": "booth.state", "crate": crate, "state": s.state]
            if let p = s.percent { m["percent"] = p }
            if let n = s.songs { m["songs"] = n }
            if let i = s.input { m["input"] = i }
            if let r = s.rate { m["rate"] = r }
            if let c = s.channels { m["channels"] = c }
            if let k = s.indexKept { m["indexKept"] = k }
            if let err = s.error { m["error"] = ["code": err.code, "detail": err.detail] }
            send(m)
        case let .level(l):
            send(["event": "booth.level", "meter": (l.meter * 1000).rounded() / 1000, "peakDb": (l.peakDB * 10).rounded() / 10,
                  "rmsDb": (l.rmsDB * 10).rounded() / 10, "clipped": l.clipped, "silent": l.silent,
                  "seconds": (l.seconds * 100).rounded() / 100])
        case let .heard(h):
            var song: [String: Any] = ["id": h.id, "title": h.title, "seconds": h.seconds]
            if let a = h.artist { song["artist"] = a }
            if let b = h.bpm { song["bpm"] = b }
            if let c = h.camelot { song["camelot"] = c }
            if let k = h.key { song["key"] = k }
            if let s = h.scale { song["scale"] = s }
            var m: [String: Any] = ["event": "booth.heard", "song": song, "place": (h.place * 10).rounded() / 10,
                                    "confidence": (h.confidence * 100).rounded() / 100, "reading": h.reading,
                                    "heardAt": (h.heardAt * 10).rounded() / 10, "ms": h.milliseconds.rounded()]
            if let s = h.speedPercent { m["speed"] = (s * 100).rounded() / 100 }
            if let k = h.keyLock { m["keyLock"] = k }
            send(m)
        }
    }
}
