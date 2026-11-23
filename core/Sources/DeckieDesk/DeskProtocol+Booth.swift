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
//
// Nothing here waits on the system's sound while holding the message loop: `booth.inputs` is listed on a thread of its
// own and answered from there, and `booth.listen` finds and opens its input on the listener's thread. Each is waited
// for at most `soundWait` seconds (`SoundInputs.answerWithin`, Bounded.swift in DeckieCapture); past that the answer
// is a plain `no_sound` (`noSystem`) for the inputs, and `booth.state` `error` `noSystem` for listening.

extension DeskProtocol {
    /// The engine's stand-in for an input, for checks and pictures with no microphone: `DECKIE_BOOTH_SOUND` names an
    /// audio file, played as if it were heard, at the speed of sound; `booth.inputs` then lists it alone.
    public static let soundStandIn = "DECKIE_BOOTH_SOUND"

    /// The stand-in's sound: the file, played as if heard, at the speed of sound, named as the input list shows it.
    /// The Mac's window takes it too (Booth.swift), so its pictures need no microphone either.
    public static func standInSource(_ file: String) throws -> SoundSource {
        let b = try AudioDecoder.decode(URL(fileURLWithPath: file))
        return SampleSource(name: URL(fileURLWithPath: file).lastPathComponent, samples: b.samples,
                            format: SoundFormat(rate: b.sampleRate, channels: b.channelCount), pace: 1)
    }

    /// The inputs this computer has (the stand-in alone when the environment names one), waited for at most
    /// `soundWait` seconds.
    func boothInputs() throws -> (inputs: [[String: Any]], system: String) {
        if let file = environment[Self.soundStandIn] {
            return ([["name": URL(fileURLWithPath: file).lastPathComponent, "default": true]], "stand-in")
        }
        let listed = try SoundInputs.list(within: soundWait, using: listSoundInputs)
        return (listed.inputs.map { ["name": $0.name, "default": $0.isDefault] }, listed.system)
    }

    /// The source for an input by its name (nil or "": the system's default).
    func boothSource(_ name: String?) throws -> SoundSource {
        if let made = makeSoundSource { return try made(name) }
        if let file = environment[Self.soundStandIn] { return try Self.standInSource(file) }
        // Found by name as it starts, on the listener's thread, within the same time limit as its opening.
        return Microphone(named: name, within: soundWait)
    }

    /// Called with the lock held.
    func boothRequest(_ type: String, _ obj: [String: Any], _ id: Any?) throws {
        switch type {
        case "booth.inputs":
            // Off the loop: the answer comes from this thread when the system gives it, or when it is given up on.
            nonisolated(unsafe) let id = id   // the request's id, a JSON value, only read
            let t = Thread { [self] in
                do {
                    let (inputs, system) = try boothInputs()
                    reply(id, ["inputs": inputs, "system": system])
                } catch let e as CaptureError {
                    fail(id, "no_sound", e.code)
                } catch {
                    fail(id, "no_sound", "failed")
                }
            }
            t.start()
        case "booth.listen":
            guard let info = session.current, let crate = session.crate else { throw RequestError(code: "no_crate", detail: nil) }
            if let wanted = obj["crate"] as? String, wanted != info.id { throw RequestError(code: "bad_request", detail: "not the crate showing") }
            stopBooth()
            let source: SoundSource
            do { source = try boothSource(obj["input"] as? String) }
            catch let e as CaptureError { throw RequestError(code: "no_sound", detail: e.code) }
            let crateId = info.id
            // The Shuffle dial for the picks (added Nov 21, 2026; 0 to 1, the iPad's default 0.5 when not given).
            let shuffle = (obj["shuffle"] as? Double) ?? (obj["shuffle"] as? Int).map(Double.init) ?? 0.5
            let b = DeskBooth(crate: crate, indexAt: session.shelf.file(DeskBooth.indexFile, of: crateId), source: source,
                              shuffle: shuffle) { [weak self] e in
                self?.sendBooth(e, crate: crateId)
            }
            booth = b
            reply(id, ["crate": crateId, "songs": b.songCount])
            b.start()
        case "booth.shuffle":
            // Added Nov 21, 2026 (step 3): the Shuffle dial moved while listening; the picks for the song on screen are
            // rolled again with it (`booth.picks`). Not listening: nothing to roll, said in the reply (the page passes the
            // dial to its next `booth.listen`).
            guard let v = (obj["shuffle"] as? Double) ?? (obj["shuffle"] as? Int).map(Double.init), v.isFinite else {
                throw RequestError(code: "bad_request", detail: "shuffle")
            }
            if let b = booth {
                reply(id, ["shuffle": b.setShuffle(v), "listening": true])
            } else {
                reply(id, ["shuffle": min(1, max(0, v)), "listening": false])
            }
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
        case let .playing(p):
            // Added Nov 21, 2026 (step 2): the song the shared switching rule shows, the iPad's.
            var m: [String: Any] = ["event": "booth.playing", "crate": crate, "pitch": p.pitch, "pitchKind": p.pitchKind,
                                    "rate": (p.rate * 10000).rounded() / 10000, "notHeard": p.notHeard, "paused": p.paused,
                                    "confidence": (p.confidence * 100).rounded() / 100, "newSong": p.newSong]
            if let h = p.song {
                var song: [String: Any] = ["id": h.id, "title": h.title, "seconds": h.seconds]
                if let a = h.artist { song["artist"] = a }
                if let b = h.bpm { song["bpm"] = b }
                if let c = h.camelot { song["camelot"] = c }
                if let k = h.key { song["key"] = k }
                if let s = h.scale { song["scale"] = s }
                // Added Nov 21, 2026 (step 3): the song's wave and bars, for its place along it.
                if let w = h.wave { song["wave"] = w }
                if let n = h.bars { song["bars"] = n }
                m["song"] = song
                m["place"] = (h.place * 10).rounded() / 10
            } else {
                m["song"] = NSNull()
            }
            if let a = p.alsoHearing { m["alsoHearing"] = a }
            send(m)
        case let .picks(p):
            // Added Nov 21, 2026 (step 2): the picks for the song on screen, with the iPad's words.
            // Step 3 added `keysClash` to each pick and `morePicks` (the rest of the shortlist, the iPad's More).
            func pick(_ k: DeskBooth.Pick) -> [String: Any] {
                var o: [String: Any] = ["id": k.id, "title": k.title, "key": k.key, "kind": k.kind, "tags": k.tags,
                                        "bpmLine": k.bpmLine, "moveLine": k.moveLine, "keys": k.keys, "keysClash": k.keysClash]
                if let a = k.artist { o["artist"] = a }
                if let b = k.bpm { o["bpm"] = b }
                if let s = k.score { o["score"] = s }
                return o
            }
            send(["event": "booth.picks", "crate": crate, "for": p.forId, "shortlist": p.shortlist, "more": p.more,
                  "shuffle": p.shuffle, "picks": p.picks.map(pick), "morePicks": p.morePicks.map(pick)])
        case let .times(line):
            // Not a message: the engine's log (standard error), where the window passes it on, as before.
            FileHandle.standardError.write(Data("deckie-desk-engine: \(line)\n".utf8))
        }
    }
}
