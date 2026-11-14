import Foundation
import DeckieCrate
import DeckieBuild
import DeckieEngine
import DeckieDecode
import DeckieDisc

/// The engine side of Desk's messages (docs/architecture/desk-protocol.md): requests in, one per line, replies and
/// events out, one per line. `deckie-desk-engine` is this with standard input and output; a test can drive it in the
/// same process or, as the protocol's tests do, as a child program.
///
/// Requests are handled one at a time on the caller's thread; a run goes on a thread of its own and sends its events
/// from there, so every output line goes through one lock.
public final class DeskProtocol: @unchecked Sendable {
    public static let version = 2

    /// Writes one message (a JSON object, no line feed).
    public typealias Output = @Sendable (Data) -> Void
    /// Makes the run for a crate and a request; the engine program's makes one with no signer (there is no
    /// recognition signature maker on Windows and Linux) and the portable print.
    public typealias RunMaker = @Sendable (DeskHome, String, RunRequest) -> DeskRun

    let session: DeskSession
    let output: Output
    let makeRun: RunMaker
    let environment: [String: String]
    let analysis: (ready: Bool, detail: String?)
    private let lock = NSLock()
    private let outLock = NSLock()
    private var running = false
    private var runThreadDone: DispatchSemaphore?
    /// The source a music CD's run is adding, while it goes (for the name the DJ gives it meanwhile).
    private var runningDisc: String?
    /// Opens a music CD by its location; a test gives a stand-in.
    public var openMusicCD: @Sendable (String) throws -> MusicCD = { try MusicCDs.open($0) }
    /// The drives holding a music CD now (the environment's stand-ins, when it names some).
    var listMusicCDs: () -> [MusicCDs.Found] { { [environment] in MusicCDs.list(environment: environment) } }

    public init(home: DeskHome, output: @escaping Output, makeRun: @escaping RunMaker,
                analysisCheck: () throws -> Void = { try Builder.checkEngine() },
                environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.session = DeskSession(home: home)
        self.output = output
        self.makeRun = makeRun
        self.environment = environment
        do { try analysisCheck(); analysis = (true, nil) } catch { analysis = (false, "\(error)") }
    }

    /// The jobs a run uses: half the cores, at most 4, or `DECKIE_DESK_JOBS`.
    public static func jobs(environment: [String: String] = ProcessInfo.processInfo.environment) -> Int {
        if let j = environment["DECKIE_DESK_JOBS"].flatMap(Int.init), j > 0 { return j }
        return max(1, min(ProcessInfo.processInfo.activeProcessorCount / 2, 4))
    }

    // MARK: out

    func send(_ object: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        outLock.lock(); defer { outLock.unlock() }
        output(data)
    }

    /// A Codable value as JSON's plain values, for putting inside a message.
    static func plain<T: Encodable>(_ value: T) -> Any {
        guard let data = try? JSONEncoder().encode(value), let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return NSNull() }
        return any
    }

    /// The first message, then what is showing.
    public func start() {
        let words = (try? JSONSerialization.jsonObject(with: DeskWords.json)) ?? [:]
        send(["event": "hello", "protocol": Self.version, "engine": "deckie-desk-engine", "platform": Analysis.platform,
              "analysis": ["ready": analysis.ready, "detail": analysis.detail ?? NSNull()] as [String: Any],
              "deletesForGood": true, "wordsVersion": DeskWords.version, "words": words,
              "computer": DeskWords.computerKind])
        lock.lock(); defer { lock.unlock() }
        sendState(); sendSongs()
    }

    /// Called with the lock held.
    func sendState() {
        let crates = session.crates.map { ["id": $0.id, "name": $0.name] }
        var current: Any = NSNull()
        if let c = session.current {
            current = ["id": c.id, "name": c.name, "hasSongs": session.crate != nil, "songs": session.crate?.tracks.count ?? 0,
                       "sources": session.crate?.discPlan.map(\.name) ?? []] as [String: Any]
        }
        var pending: Any = NSNull()
        if let p = session.pending {
            pending = ["name": p.name, "folder": p.folder,
                       "here": DeskRun.canCarryOn(p, home: session.home, open: openMusicCD, musicCDs: listMusicCDs),
                       "musicCD": p.musicCD != nil] as [String: Any]
        }
        send(["event": "state", "crates": crates, "current": current, "pending": pending, "running": running,
              "undo": session.undoName ?? NSNull(), "redo": session.redoName ?? NSNull()])
    }

    /// Called with the lock held.
    func sendSongs() {
        guard let info = session.current, let crate = session.crate else { return }
        let log = DeskImportLog(crate)
        send(["event": "songs", "crate": info.id,
              "songs": Self.plain(session.rows),
              "sources": Self.plain(DeskSourceRow.outline(crate)),
              "musicFolderSongs": crate.tracks.contains { $0.ident.allPlaces.contains { $0.disc == nil } },
              "importLog": log.map { Self.plain($0) } ?? NSNull(),
              "notIn": log?.notInCount ?? 0,
              "unsigned": crate.tracks.filter { $0.signatures.isEmpty }.count])
    }

    func reply(_ id: Any?, _ fields: [String: Any] = [:]) {
        var m = fields
        m["re"] = id ?? NSNull(); m["ok"] = true
        send(m)
    }

    func fail(_ id: Any?, _ code: String, _ detail: String? = nil) {
        send(["re": id ?? NSNull(), "ok": false, "error": ["code": code, "detail": detail ?? NSNull()] as [String: Any]])
    }

    // MARK: in

    /// Handles one line. Returns false when the line asked the engine to quit.
    @discardableResult
    public func handle(line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8)) as? [String: Any],
              let type = obj["type"] as? String else {
            fail(nil, "bad_request", "each line must be a JSON object with a type")
            return true
        }
        let id = obj["id"]
        if type == "quit" { reply(id); return false }
        lock.lock(); defer { lock.unlock() }
        let readOnly: Set<String> = ["state", "drives.list", "crate.songs", "source.removeCount", "run.nameDisc", "name.split",
                                     "song.audio"]
        if running && !readOnly.contains(type) { fail(id, "busy", "a run is going"); return true }
        do {
            try dispatch(type, obj, id)
        } catch let e as RequestError {
            fail(id, e.code, e.detail)
        } catch {
            fail(id, "failed", (error as? LocalizedError)?.errorDescription ?? "\(error)")
            sendState(); sendSongs()
        }
        return true
    }

    struct RequestError: Error { let code: String; let detail: String? }

    static func string(_ obj: [String: Any], _ key: String) throws -> String {
        guard let s = obj[key] as? String else { throw RequestError(code: "bad_request", detail: "\(key) missing") }
        return s
    }

    /// Called with the lock held.
    func dispatch(_ type: String, _ obj: [String: Any], _ id: Any?) throws {
        let s = session
        func changed() { reply(id); sendState(); sendSongs() }
        func needCrate() throws { if s.crate == nil { throw RequestError(code: "no_crate", detail: nil) } }
        switch type {
        case "state":
            reply(id); sendState(); sendSongs()
        case "crate.show":
            guard s.show(try Self.string(obj, "crate")) else { throw RequestError(code: "bad_request", detail: "no such crate") }
            changed()
        case "crate.new":
            s.newCrate(); reply(id); sendState()
        case "crate.rename":
            let crateId = try Self.string(obj, "crate")
            try s.rename(crateId, to: try Self.string(obj, "name"))
            reply(id, ["name": s.shelf.info(crateId)?.name ?? NSNull()]); sendState(); sendSongs()
        case "crate.delete":
            try s.delete(try Self.string(obj, "crate")); changed()
        case "crate.import":
            try s.importCrate(URL(fileURLWithPath: try Self.string(obj, "path"))); changed()
        case "crate.songs":
            reply(id); sendSongs()
        case "crate.export":
            try needCrate()
            let path = try s.export(into: URL(fileURLWithPath: try Self.string(obj, "folder"), isDirectory: true))
            reply(id, ["path": path.path])
        case "drives.list":
            reply(id, ["drives": Self.plain(DeskDrives.list()), "musicCDs": Self.plain(MusicCDs.list(environment: environment))])
        case "run.addMusicCD":
            let location = try Self.string(obj, "location")
            let (request, ask) = try s.addMusicCDRequest(location, open: openMusicCD)
            try startRun(request, id, askName: ask)
        case "run.nameDisc":
            let name = try Self.string(obj, "name")
            let source = (obj["source"] as? String) ?? runningDisc
            guard let source else { throw RequestError(code: "bad_request", detail: "no music CD is being read") }
            if running && source == runningDisc {
                try s.nameDisc(source: source, to: name, running: true); reply(id)
            } else {
                try needCrate(); try s.nameDisc(source: source, to: name, running: false); changed()
            }
        case "name.split":
            if let r = DeskNaming.split(try Self.string(obj, "text")) {
                reply(id, ["split": true, "artist": r.artist ?? NSNull(), "title": r.title, "version": r.version ?? NSNull()])
            } else { reply(id, ["split": false]) }
        case "names.preview":
            try needCrate()
            let p = try s.makePreview(tool: try Self.string(obj, "tool"), source: obj["source"] as? String,
                                      ids: obj["songs"] as? [String], text: obj["text"] as? String,
                                      pattern: obj["pattern"] as? String,
                                      playlist: (obj["path"] as? String).map { URL(fileURLWithPath: $0) },
                                      onlyEmpty: (obj["onlyEmpty"] as? Bool) ?? true)
            reply(id, ["preview": Self.plain(p), "patterns": DeskNaming.patterns])
        case "names.apply":
            try needCrate()
            let ticks = (obj["ticks"] as? [NSNumber]).map { Set($0.map(\.intValue)) }
            let n = try s.applyPreview(ticks: ticks)
            reply(id, ["songs": n]); sendState(); sendSongs()
        case "song.check":
            try needCrate()
            let ids = try (obj["songs"] as? [String]) ?? [Self.string(obj, "song")]
            let n = try s.check(ids, field: obj["field"] as? String)
            reply(id, ["songs": n]); sendState(); sendSongs()
        case "song.audio":
            try needCrate()
            try sendAudio(try Self.string(obj, "song"), decoded: (obj["decoded"] as? Bool) ?? false, id)
        case "run.add":
            let path = try Self.string(obj, "path")
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
                throw RequestError(code: "bad_request", detail: "\(path) is not a folder")
            }
            try startRun(s.addRequest(URL(fileURLWithPath: path, isDirectory: true), name: obj["name"] as? String), id)
        case "run.carryOn":
            guard let p = s.pending else { throw RequestError(code: "bad_request", detail: "no run to carry on") }
            try startRun(p, id)
        case "song.fix":
            try needCrate()
            try s.fixName(try Self.string(obj, "song"), title: obj["title"] as? String, artist: obj["artist"] as? String,
                          version: obj["version"] as? String, tags: obj["tags"] as? [String])
            changed()
        case "source.rename":
            try needCrate()
            try s.renameSource(try Self.string(obj, "source"), to: try Self.string(obj, "name")); changed()
        case "folder.rename":
            try needCrate()
            try s.renameFolder(try Self.string(obj, "folder"), inSource: try Self.string(obj, "source"),
                               to: try Self.string(obj, "name"))
            changed()
        case "song.move":
            try needCrate()
            let by = (obj["by"] as? NSNumber)?.intValue ?? 0
            try s.move(try Self.string(obj, "song"), inSource: try Self.string(obj, "source"),
                       folder: try Self.string(obj, "folder"), by: by < 0 ? -1 : 1)
            changed()
        case "source.removeCount":
            reply(id, ["songs": s.songsOnlyOn(obj["source"] as? String)])
        case "source.remove":
            try needCrate()
            try s.removeSource(obj["source"] as? String); changed()
        case "edit.undo":
            try s.undo(); changed()
        case "edit.redo":
            try s.redo(); changed()
        case "lookAgain":
            try needCrate()
            let summary = try s.lookAgain(environment: environment)
            reply(id, ["summary": Self.plain(summary)]); sendState(); sendSongs()
        case "library.choose":
            let program = try s.chooseLibrary(URL(fileURLWithPath: try Self.string(obj, "path")))
            reply(id, ["program": program.rawValue])
        default:
            throw RequestError(code: "unknown_type", detail: type)
        }
    }

    // MARK: the run

    /// Called with the lock held.
    func startRun(_ request: RunRequest, _ id: Any?, askName: String? = nil) throws {
        guard analysis.ready else { throw RequestError(code: "engine_missing", detail: analysis.detail) }
        let info = try session.crateForRun(request)
        let carriedOn = session.pending == request
        running = true
        runningDisc = request.musicCD != nil ? request.source : nil
        reply(id, ["source": request.source ?? NSNull(), "crate": info.id, "askName": askName ?? NSNull()])
        send(["event": "run.started", "crate": info.id, "crateName": info.name, "read": request.name, "carriedOn": carriedOn,
              "musicCD": request.musicCD != nil, "askName": askName ?? NSNull()])
        sendState()
        let run = makeRun(session.home, info.id, request)
        run.openMusicCD = openMusicCD
        let env = environment
        run.findMusicCDs = { MusicCDs.list(environment: env) }
        let done = DispatchSemaphore(value: 0)
        runThreadDone = done
        let thread = Thread { [self] in
            let last = LastSent()
            do {
                let (_, report) = try run.run { p in
                    // Every line goes out; bare progress at most ten times a second.
                    if p.line == nil && p.done < p.total && !last.due(every: 0.1) { return }
                    var m: [String: Any] = ["event": "run.progress", "stage": p.stage.rawValue, "done": p.done,
                                            "total": p.total, "remaining": p.remaining ?? NSNull()]
                    if let line = p.line { m["line"] = Self.line(line) }
                    self.send(m)
                }
                self.lock.lock()
                self.running = false
                self.runningDisc = nil
                self.session.runEnded(info.id)
                self.send(["event": "run.finished", "report": Self.plain(report)])
                self.sendState(); self.sendSongs()
                self.lock.unlock()
            } catch {
                self.lock.lock()
                self.running = false
                self.runningDisc = nil
                self.session.runEnded(info.id)
                self.send(["event": "run.failed", "detail": (error as? LocalizedError)?.errorDescription ?? "\(error)"])
                self.sendState(); self.sendSongs()
                self.lock.unlock()
            }
            done.signal()
        }
        thread.stackSize = 8 << 20
        thread.start()
    }

    /// When bare progress was last sent; the run calls from more than one thread.
    final class LastSent: @unchecked Sendable {
        private let lock = NSLock()
        private var at = Date.distantPast
        func due(every seconds: Double) -> Bool {
            lock.lock(); defer { lock.unlock() }
            let now = Date()
            guard now.timeIntervalSince(at) >= seconds else { return false }
            at = now
            return true
        }
    }

    static func line(_ l: RunLine) -> [String: Any] {
        switch l {
        case let .started(files, unchanged, queued):
            return ["kind": "started", "files": files, "unchanged": unchanged, "queued": queued]
        case let .file(rel, outcome):
            switch outcome {
            case let .analysed(s): return ["kind": "read", "rel": rel, "seconds": s]
            case .reused: return ["kind": "reused", "rel": rel]
            case let .failed(f): return ["kind": "notRead", "rel": rel, "reason": f.reason]
            }
        case let .discDamaged(number, sectors):
            return ["kind": "discDamaged", "number": number, "sectors": sectors]
        }
    }

    // MARK: Listen (D33)

    /// Bytes of audio a chunk carries before base64 (768 KB, about 1 MB of text a line).
    static let audioChunk = 768 * 1024

    /// The media types the window's web view is told, by file ending.
    public static func mediaType(_ ext: String) -> String {
        switch ext.lowercased() {
        case "mp3": return "audio/mpeg"
        case "wav", "wave": return "audio/wav"
        case "flac": return "audio/flac"
        case "m4a", "aac", "mp4", "alac": return "audio/mp4"
        case "aif", "aiff", "aifc": return "audio/aiff"
        case "ogg", "oga": return "audio/ogg"
        case "opus": return "audio/ogg; codecs=opus"
        default: return "application/octet-stream"
        }
    }

    /// A song's sound for the window to play (docs/architecture/desk-protocol.md, "Listen"): the reply says its media
    /// type, size and where listening starts (a third of the way in, letter AA 3.7), then `audio.chunk` events carry
    /// it in order, base64, over the same standard output as every other message. With `decoded`, the shared decoder
    /// turns it into 16-bit WAV first, for a file type the web view cannot play. A song on a music CD is read off the
    /// disc now, as WAV, held only while it is sent (nothing is written). The page is never told a path. Called with
    /// the lock held.
    func sendAudio(_ song: String, decoded: Bool, _ id: Any?) throws {
        let sound: DeskAudio.Sound
        do { sound = try session.audio(song, open: openMusicCD, musicCDs: listMusicCDs) }
        catch let e as DeskAudio.NotHere { throw RequestError(code: "not_here", detail: e.source) }
        var data: Data
        let url: URL
        switch sound {
        case let .disc(cd, s):
            do { data = try DeskAudio.read(cd, s) }
            catch { throw RequestError(code: "not_here", detail: session.crate?.tracks.first { $0.id == song }?.ident.disc ?? "") }
            try sendChunks(song, data: data, type: "audio/wav", kind: "WAV", id)
            return
        case let .file(u): url = u
        }
        var type = Self.mediaType(url.pathExtension)
        if decoded {
            do {
                let b = try AudioDecoder.decode(url)
                data = Self.wav(b.samples, channels: b.channelCount, rate: b.sampleRate)
                type = "audio/wav"
            } catch { throw RequestError(code: "cannot_decode", detail: url.pathExtension.uppercased()) }
        } else {
            data = try Data(contentsOf: url, options: [.mappedIfSafe])
        }
        try sendChunks(song, data: data, type: type, kind: url.pathExtension.uppercased(), id)
    }

    /// The reply for `song.audio`, then the sound in `audio.chunk` events.
    func sendChunks(_ song: String, data: Data, type: String, kind: String, _ id: Any?) throws {
        let seconds = session.crate?.tracks.first { $0.id == song }?.file.durationS ?? 0
        let chunks = max(1, (data.count + Self.audioChunk - 1) / Self.audioChunk)
        let token = UUID().uuidString.lowercased()
        reply(id, ["type": type, "bytes": data.count, "chunks": chunks, "token": token, "seconds": seconds,
                   "start": DeskListen.start(seconds), "kind": kind])
        for i in 0..<chunks {
            let part = data.subdata(in: (i * Self.audioChunk)..<min(data.count, (i + 1) * Self.audioChunk))
            send(["event": "audio.chunk", "token": token, "song": song, "index": i, "of": chunks, "data": part.base64EncodedString()])
        }
    }

    /// Interleaved float samples as a 16-bit PCM WAV file.
    static func wav(_ samples: [Float], channels: Int, rate: Int) -> Data {
        var d = Data(capacity: 44 + samples.count * 2)
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(UInt16(channels)); u32(UInt32(rate))
        u32(UInt32(rate * channels * 2)); u16(UInt16(channels * 2)); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(bytes)
        var pcm = [Int16](repeating: 0, count: samples.count)
        for i in samples.indices { pcm[i] = Int16(max(-1, min(1, samples[i])) * 32767) }
        pcm.withUnsafeBufferPointer { d.append(Data(buffer: $0)) }
        return d
    }

    /// Waits for a run in progress to end (tests, and the engine's quit).
    public func waitForRun() {
        lock.lock(); let d = runThreadDone; lock.unlock()
        d?.wait()
        if let d { d.signal() }
    }
}
