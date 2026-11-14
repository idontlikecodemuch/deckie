import Foundation
import Testing
import DeckieAudio
import DeckieCrate
import DeckieDisc
import DeckieTestSupport
@testable import DeckieDesk

/// `deckie-desk-engine` run as a child program, as Desk's window runs it, on every system the core builds on: one JSON
/// message a line in and out (docs/architecture/desk-protocol.md), with a scratch storage folder and generated songs.
final class EngineProcess: @unchecked Sendable {
    static let starting = NSLock()
    let process = Process()
    private let input = Pipe(), output = Pipe(), errors = Pipe()
    private let lock = NSLock()
    private var lines: [[String: Any]] = []
    private var buffer = Data()
    private var nextId = 1

    /// The engine program beside the test bundle (`swift test` builds it, as the test target depends on it), or
    /// `DECKIE_DESK_ENGINE`.
    static var executable: URL? {
        let name = "deckie-desk-engine" + ({ () -> String in
            #if os(Windows)
            return ".exe"
            #else
            return ""
            #endif
        })()
        var dirs: [URL] = []
        if let p = ProcessInfo.processInfo.environment["DECKIE_DESK_ENGINE"] { return URL(fileURLWithPath: p) }
        dirs.append(URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent())
        for b in Bundle.allBundles where b.bundlePath.hasSuffix(".xctest") { dirs.append(b.bundleURL.deletingLastPathComponent()) }
        let package = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        dirs.append(package.appendingPathComponent(".build/debug"))
        return dirs.map { $0.appendingPathComponent(name) }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    init(home: URL, environment extra: [String: String] = [:]) throws {
        guard let exe = Self.executable else { throw DeskError("deckie-desk-engine not built") }
        process.executableURL = exe
        var env = ProcessInfo.processInfo.environment
        env[DeskHome.environmentVariable] = home.path
        env[DeskLocalFacts.djHomeVariable] = home.appendingPathComponent("dj-home").path
        env["DECKIE_DESK_JOBS"] = "1"
        for (k, v) in extra { env[k] = v }
        process.environment = env
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        // One engine is started at a time. On Windows, Foundation in Swift 6.4.1 learns that a child has ended from
        // a socket the child holds, and every handle that can be inherited goes to whichever child is being started
        // at that moment: two engines started together by suites running side by side could each hold the other's
        // socket, and then `isRunning` stayed true for an engine that had left until the other one left too (seen
        // as "did not exit in 20 seconds" on the Windows runner). Foundation's own later versions start children
        // under a lock for the same reason. The other children these tests start are short-lived, so they do no harm.
        if ProcessInfo.processInfo.environment["DECKIE_TEST_UNLOCKED_STARTS"] == nil {
            Self.starting.lock()
            defer { Self.starting.unlock() }
            try process.run()
        } else {
            try process.run()  // for the check that shows the fault: EngineStartsTests
        }
        let handle = output.fileHandleForReading
        Thread.detachNewThread { [self] in
            while true {
                let d = handle.availableData
                if d.isEmpty { break }
                lock.lock()
                buffer.append(d)
                while let nl = buffer.firstIndex(of: 0x0A) {
                    let line = buffer[buffer.startIndex..<nl]
                    buffer = Data(buffer[(nl + 1)...])
                    if let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any] { lines.append(obj) }
                    else { lines.append(["unreadable": String(decoding: line, as: UTF8.self)]) }
                }
                lock.unlock()
            }
        }
        // Standard error is drained so the engine never blocks on it.
        let err = errors.fileHandleForReading
        Thread.detachNewThread { while !err.availableData.isEmpty {} }
    }

    var received: [[String: Any]] { lock.lock(); defer { lock.unlock() }; return lines }

    /// Sends a request; its id.
    @discardableResult
    func send(_ type: String, _ fields: [String: Any] = [:]) throws -> Int {
        lock.lock(); let id = nextId; nextId += 1; lock.unlock()
        var m = fields
        m["type"] = type; m["id"] = id
        var data = try JSONSerialization.data(withJSONObject: m)
        data.append(0x0A)
        input.fileHandleForWriting.write(data)
        return id
    }

    func sendRaw(_ text: String) { input.fileHandleForWriting.write(Data((text + "\n").utf8)) }

    /// Waits for the first message after `from` that `match` accepts.
    func wait(from: Int = 0, seconds: Double = 30, _ match: ([String: Any]) -> Bool) -> [String: Any]? {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            let all = received
            if from < all.count, let m = all[from...].first(where: match) { return m }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    /// Sends a request and waits for its reply.
    func request(_ type: String, _ fields: [String: Any] = [:], seconds: Double = 30) throws -> [String: Any] {
        let id = try send(type, fields)
        guard let r = wait(seconds: seconds, { ($0["re"] as? NSNumber)?.intValue == id }) else {
            throw DeskError("no reply to \(type)")
        }
        return r
    }

    /// The latest event of a kind.
    func last(_ event: String) -> [String: Any]? { received.last { $0["event"] as? String == event } }

    func close() { try? input.fileHandleForWriting.close() }

    /// Waits for the program to end; its exit code, or nil when it did not end in time.
    func exitCode(seconds: Double = 20) -> Int32? {
        let end = Date().addingTimeInterval(seconds)
        while process.isRunning && Date() < end { Thread.sleep(forTimeInterval: 0.05) }
        if process.isRunning { process.terminate(); return nil }
        return process.terminationStatus
    }
}

@Suite(.serialized) struct EngineProcessTests {
    /// Everything the window does that needs no analysis: the first message, the crates, edits with undo, export,
    /// the drives, and the engine leaving when its input closes.
    @Test func speaksTheProtocolWithNoMusicRead() throws {
        let root = try scratch("engine-protocol")
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        var info = try home.shelf.make(name: "Friday")
        info.sourceRoots["Stick 3"] = root.appendingPathComponent("Stick 3").path
        try home.shelf.save(info)
        try CrateWriter.write(crate([
            entry("aaaa", "Song A", disc: "Stick 3", folder: "House", track: 1, rel: "House/01 Song A.mp3"),
            entry("bbbb", "Song B", disc: "Stick 3", folder: "House", track: 2, rel: "House/02 Song B.mp3"),
        ], name: "Friday"), to: home.shelf.package(info.id))

        let e = try EngineProcess(home: home.root)
        defer { if e.process.isRunning { e.process.terminate() } }
        let hello = try #require(e.wait { $0["event"] as? String == "hello" })
        #expect((hello["protocol"] as? NSNumber)?.intValue == DeskProtocol.version)
        #expect((hello["words"] as? [String: String])?["firstTitle"] == "Your crate starts here.")
        #expect(e.received.first?["event"] as? String == "hello")
        let state = try #require(e.wait { $0["event"] as? String == "state" })
        #expect((state["current"] as? [String: Any])?["name"] as? String == "Friday")
        let songs = try #require(e.wait { $0["event"] as? String == "songs" })
        #expect((songs["songs"] as? [[String: Any]])?.count == 2)
        #expect(((songs["sources"] as? [[String: Any]])?.first)?["name"] as? String == "Stick 3")

        // A name fix with letters from outside English, and its undo.
        var mark = e.received.count
        let fix = try e.request("song.fix", ["song": "aaaa", "title": "Café 東京 — ü", "artist": "Zoë"])
        #expect(fix["ok"] as? Bool == true)
        // Each change is waited for as the event that shows it, not as "the next event of that kind": on a busy
        // machine an event from the step before can still be on its way when the next request's reply has come.
        func songA(_ m: [String: Any]) -> [String: Any]? {
            guard m["event"] as? String == "songs" else { return nil }
            return (m["songs"] as? [[String: Any]])?.first { $0["id"] as? String == "aaaa" }
        }
        let after = try #require(e.wait(from: mark) { songA($0)?["title"] as? String == "Café 東京 — ü" })
        let a = songA(after)
        #expect(a?["artist"] as? String == "Zoë" && a?["nameFrom"] as? String == "user")
        #expect(e.wait(from: mark) { $0["event"] as? String == "state" && $0["undo"] as? String == "undoNameFix" } != nil)
        mark = e.received.count
        _ = try e.request("edit.undo")
        #expect(e.wait(from: mark) { songA($0)?["title"] as? String == "Song A" } != nil)

        // Sources: rename, move, how many a removal takes.
        mark = e.received.count
        _ = try e.request("source.rename", ["source": "Stick 3", "name": "Stick Three"])
        func firstFolder(_ m: [String: Any]) -> [String?]? {
            guard m["event"] as? String == "songs", let source = (m["sources"] as? [[String: Any]])?.first,
                  source["name"] as? String == "Stick Three" else { return nil }
            return ((source["folders"] as? [[String: Any]])?.first?["songs"] as? [[String: Any]])?.map { $0["id"] as? String }
        }
        #expect(e.wait(from: mark) { firstFolder($0) == ["aaaa", "bbbb"] } != nil)
        mark = e.received.count
        _ = try e.request("song.move", ["song": "bbbb", "source": "Stick Three", "folder": "House", "by": -1])
        #expect(e.wait(from: mark) { firstFolder($0) == ["bbbb", "aaaa"] } != nil)
        #expect((try e.request("source.removeCount", ["source": "Stick Three"])["songs"] as? NSNumber)?.intValue == 2)

        // The crate menu: rename, a new crate, back.
        let renamed = try e.request("crate.rename", ["crate": info.id, "name": "Friday late"])
        #expect(renamed["name"] as? String == "Friday late")
        // The state that follows each request is waited for, not read straight after the reply: the two travel on
        // the same pipe but a busy machine may hand the test the reply first.
        mark = e.received.count
        _ = try e.request("crate.new")
        #expect(e.wait(from: mark) { $0["event"] as? String == "state" && $0["current"] is NSNull } != nil)
        mark = e.received.count
        _ = try e.request("crate.show", ["crate": info.id])
        #expect(e.wait(from: mark) { $0["event"] as? String == "state"
            && ($0["current"] as? [String: Any])?["name"] as? String == "Friday late" } != nil)

        // Export, into a folder whose name is not English either.
        let out = root.appendingPathComponent("Export ö")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let exported = try e.request("crate.export", ["folder": out.path])
        let path = try #require(exported["path"] as? String)
        #expect(try CrateReader.read(from: URL(fileURLWithPath: path)).manifest.name == "Friday late")
        // The engine program runs on Windows and Linux, where the crate file leaves as one file.
        #if os(Windows) || os(Linux)
        #expect(CrateArchive.isArchive(URL(fileURLWithPath: path)))
        #endif

        // Drives answer on every system (none is required to be plugged in).
        #expect(try e.request("drives.list")["drives"] is [Any])

        // Mistakes are answered, not fatal.
        e.sendRaw("this is not json")
        #expect(e.wait { ($0["error"] as? [String: Any])?["code"] as? String == "bad_request" } != nil)
        #expect((try e.request("no.such.thing")["error"] as? [String: Any])?["code"] as? String == "unknown_type")
        let notFolder = try e.request("run.add", ["path": root.appendingPathComponent("missing").path])
        #expect(notFolder["ok"] as? Bool == false)

        // The engine leaves when its input closes.
        e.close()
        #expect(e.exitCode() == 0)
    }

    /// The one run through the engine program: a folder of generated songs is added (D31: a source named after the
    /// folder), with progress, the finished report and the crate's songs after it.
    @Test(.enabled(if: Engine.available, "needs ONNX Runtime and the Beat This! model"))
    func addsAFolderOfGeneratedSongs() async throws {
        let root = try scratch("engine-run")
        let music = root.appendingPathComponent("Mix Tapes ü/House")
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let buffer = TestTrack.render()
        try TestTrack.wav(buffer).write(to: music.appendingPathComponent("01 Song X.wav"))
        try TestTrack.wav(AudioBuffer(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount,
                                      samples: buffer.samples.map { $0 * 0.5 })).write(to: music.appendingPathComponent("02 Sóng Y.wav"))
        try Data("not audio".utf8).write(to: music.appendingPathComponent("03 Broken.mp3"))

        let e = try EngineProcess(home: root.appendingPathComponent("home"))
        defer { if e.process.isRunning { e.process.terminate() } }
        let hello = try #require(e.wait { $0["event"] as? String == "hello" })
        #expect((hello["analysis"] as? [String: Any])?["ready"] as? Bool == true)
        #expect(e.wait { $0["event"] as? String == "state" }?["current"] is NSNull)

        let finished: [String: Any]? = try await CPUTurns.exclusive {
            let added = try e.request("run.add", ["path": root.appendingPathComponent("Mix Tapes ü").path])
            #expect(added["source"] as? String == "Mix Tapes ü")
            // A request that changes something waits for the run.
            #expect((try e.request("crate.new")["error"] as? [String: Any])?["code"] as? String == "busy")
            return e.wait(seconds: 600) { ["run.finished", "run.failed"].contains($0["event"] as? String ?? "") }
        }
        let done = try #require(finished)
        #expect(done["event"] as? String == "run.finished", "\(done)")
        let report = try #require(done["report"] as? [String: Any])
        #expect((report["songs_seen"] as? NSNumber)?.intValue == 3)
        #expect((report["went_in"] as? NSNumber)?.intValue == 2)
        #expect((report["read"] as? String) == "Mix Tapes ü")
        let progress = e.received.filter { $0["event"] as? String == "run.progress" }
        #expect(!progress.isEmpty)
        #expect(progress.contains { ($0["line"] as? [String: Any])?["kind"] as? String == "started" })
        let started = try #require(e.received.first { $0["event"] as? String == "run.started" })
        #expect(started["crateName"] as? String == "Mix Tapes ü")
        // The run screen (D37): each song that went in joined it once, with its wave and what Desk found, and the
        // totals count them; the first song and the end are moments.
        let screen = e.received.filter { $0["event"] as? String == "run.songs" }
        let shown = screen.flatMap { ($0["songs"] as? [[String: Any]]) ?? [] }
        #expect(shown.count == 2)
        #expect(Set(shown.compactMap { $0["title"] as? String }) == ["01 Song X", "02 Sóng Y"])
        #expect(shown.allSatisfy { ($0["wave"] as? [Any])?.count == RunSong.waveLength && $0["bpm"] is NSNumber })
        #expect(shown.allSatisfy { $0["place"] as? String == "Mix Tapes ü / House \($0["title"] as? String == "01 Song X" ? 1 : 2)" })
        #expect(shown.allSatisfy { (($0["key"] as? [String: Any])?["kind"] as? String).map { ["key", "home", "none"].contains($0) } == true })
        let figures = try #require(screen.last { $0["figures"] != nil }?["figures"] as? [String: Any])
        #expect((figures["songs"] as? NSNumber)?.intValue == 2 && (figures["notIn"] as? NSNumber)?.intValue == 1)
        let notes = screen.flatMap { ($0["notes"] as? [[String: Any]]) ?? [] }
        #expect(notes.contains { $0["code"] as? String == "first" && $0["kind"] as? String == "moment" })
        #expect(notes.last?["code"] as? String == "finished")
        let finishedAt = try #require(e.received.firstIndex { $0["event"] as? String == "run.finished" })
        #expect(e.received.lastIndex { $0["event"] as? String == "run.songs" }! < finishedAt)

        let songs = try #require(e.wait { $0["event"] as? String == "songs" })
        let rows = try #require(songs["songs"] as? [[String: Any]])
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0["bpm"] is NSNumber })
        #expect(rows.allSatisfy { (($0["places"] as? [[String: Any]])?.first)?["source"] as? String == "Mix Tapes ü" })
        #expect((songs["notIn"] as? NSNumber)?.intValue == 1)
        #expect((e.last("state")?["running"] as? Bool) == false)

        _ = try e.request("quit")
        #expect(e.exitCode() == 0)
    }
}

/// The naming messages (research AA, route A) through the engine program: the rows' names and reasons, a tool's
/// preview and its apply as one step, "Looks right", splitting typed names, and Listen's sound handed over in chunks
/// on standard output with no path and no port.
@Suite(.serialized) struct EngineNamingTests {
    @Test func namesAndListenThroughTheProtocol() throws {
        let root = try scratch("engine-naming")
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        var info = try home.shelf.make(name: "Friday")
        let stick = root.appendingPathComponent("Stick 3")
        info.sourceRoots["Stick 3"] = stick.path
        try home.shelf.save(info)
        try FileManager.default.createDirectory(at: stick.appendingPathComponent("House"), withIntermediateDirectories: true)
        // Not music: Listen hands the file over as it is, and these bytes are easy to check end to end.
        var sound = Data()
        for i in 0..<(2_000_000) { sound.append(UInt8(truncatingIfNeeded: i &* 31)) }
        try sound.write(to: stick.appendingPathComponent("House/01 Track 01.mp3"))
        var a = entry("aaaa", "Track 01", disc: "Stick 3", folder: "House", track: 1, rel: "House/01 Track 01.mp3")
        a.ident.source = "filename"
        var b = entry("bbbb", "Night drive", disc: "Stick 3", folder: "House", track: 2, rel: "House/02 Night drive.mp3")
        b.ident.artist = "Artist A"; b.ident.source = "filename"
        try CrateWriter.write(crate([a, b], name: "Friday"), to: home.shelf.package(info.id))

        let e = try EngineProcess(home: home.root)
        defer { if e.process.isRunning { e.process.terminate() } }
        let songs = try #require(e.wait { $0["event"] as? String == "songs" })
        let rows = try #require(songs["songs"] as? [[String: Any]])
        #expect(rows.first { $0["id"] as? String == "aaaa" }?["nameReason"] as? String == "noTitle")
        let bRow = try #require(rows.first { $0["id"] as? String == "bbbb" })
        #expect(bRow["nameReason"] as? String == "guess")
        #expect(((bRow["names"] as? [String: Any])?["title"] as? [String: Any])?["from"] as? String == "filename")

        // Splitting what the DJ typed.
        let split = try e.request("name.split", ["text": "Zed - Sunrise (Dub)"])
        #expect(split["split"] as? Bool == true && split["artist"] as? String == "Zed" && split["version"] as? String == "Dub")
        #expect(try e.request("name.split", ["text": "Sunrise"])["split"] as? Bool == false)

        // A pasted list whose count is off is refused until fixed; then applied as one step.
        let short = try e.request("names.preview", ["tool": "paste", "source": "Stick 3", "text": "Zed - Sunrise"])
        #expect((short["preview"] as? [String: Any])?["problem"] as? String == "counts")
        #expect((try e.request("names.apply", [:])["error"] as? [String: Any])?["code"] as? String == "failed")
        let ok = try e.request("names.preview", ["tool": "paste", "source": "Stick 3", "text": "Zed - Sunrise\nArtist A - Night drive"])
        let changes = try #require((ok["preview"] as? [String: Any])?["changes"] as? [[String: Any]])
        #expect(changes.contains { $0["song"] as? String == "aaaa" && $0["after"] as? String == "Sunrise" && $0["tick"] as? Bool == true })
        var mark = e.received.count
        let applied = try e.request("names.apply", ["ticks": Array(changes.indices)])
        #expect((applied["songs"] as? NSNumber)?.intValue == 1)
        #expect(e.wait(from: mark) { $0["event"] as? String == "state" }?["undo"] as? String == "undoNames")
        // The apply's own songs event comes after its state; wait for it, so the next mark is past it.
        _ = e.wait(from: mark) { $0["event"] as? String == "songs" }
        mark = e.received.count
        let checked = try e.request("song.check", ["songs": ["bbbb"]])
        #expect((checked["songs"] as? NSNumber)?.intValue == 1)
        let after = try #require(e.wait(from: mark) { $0["event"] as? String == "songs" })
        #expect((after["songs"] as? [[String: Any]])?.allSatisfy { $0["needsName"] as? Bool == false } == true)

        // Listen: the reply, then the chunks, which put back together are the file.
        mark = e.received.count
        let audio = try e.request("song.audio", ["song": "aaaa"])
        #expect(audio["type"] as? String == "audio/mpeg")
        #expect((audio["bytes"] as? NSNumber)?.intValue == sound.count)
        let token = try #require(audio["token"] as? String)
        let count = try #require((audio["chunks"] as? NSNumber)?.intValue)
        #expect(count == 3)
        _ = e.wait(from: mark) { $0["event"] as? String == "audio.chunk" && ($0["index"] as? NSNumber)?.intValue == count - 1 }
        let parts = e.received[mark...].filter { $0["event"] as? String == "audio.chunk" && $0["token"] as? String == token }
            .sorted { (($0["index"] as? NSNumber)?.intValue ?? 0) < (($1["index"] as? NSNumber)?.intValue ?? 0) }
        var back = Data()
        for p in parts { back.append(Data(base64Encoded: p["data"] as? String ?? "") ?? Data()) }
        #expect(back == sound)
        #expect(audio["path"] == nil)
        // A song whose source is not here says which source to put back.
        let gone = try e.request("song.audio", ["song": "bbbb"])
        let err = try #require(gone["error"] as? [String: Any])
        #expect(err["code"] as? String == "not_here" && err["detail"] as? String == "Stick 3")

        e.close()
        #expect(e.exitCode() == 0)
    }

    /// A song's facts (D34) through the protocol: sent with each song, the shown four as fields with where each came
    /// from, the rest listed; `song.fix`'s `facts` makes them the DJ's, "" clears one, and undo takes it back.
    @Test func factsThroughTheProtocol() throws {
        let root = try scratch("engine-facts")
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        let info = try home.shelf.make(name: "Friday")
        var a = entry("aaaa", "Night drive", disc: nil, folder: nil, track: nil, rel: "a.mp3")
        a.ident.artist = "Artist A"
        a.ident.facts = ["release": .init("Friday Night", from: "tag"), "genre": .init(["House", "Garage"], from: "tag"),
                         "isrc": .init("USABC9900001", from: "tag")]
        a.file.otherTags = .init(formats: ["id3v2.4"], tags: ["TSSE": ["LAME"]], leftOut: ["picture": 1])
        try CrateWriter.write(crate([a], name: "Friday"), to: home.shelf.package(info.id))

        let e = try EngineProcess(home: home.root)
        defer { if e.process.isRunning { e.process.terminate() } }
        let songs = try #require(e.wait { $0["event"] as? String == "songs" })
        let names = try #require((songs["songs"] as? [[String: Any]])?.first?["names"] as? [String: Any])
        #expect((names["release"] as? [String: Any])?["value"] as? String == "Friday Night")
        #expect((names["genre"] as? [String: Any])?["value"] as? String == "House, Garage")
        #expect((names["genre"] as? [String: Any])?["from"] as? String == "tag")
        #expect((names["others"] as? [[String: Any]])?.first?["name"] as? String == "isrc")
        #expect((names["fileTags"] as? [[String: Any]])?.first?["name"] as? String == "TSSE")
        #expect((names["leftOut"] as? [String: Any])?["picture"] as? NSNumber == 1)

        var mark = e.received.count
        _ = try e.request("song.fix", ["song": "aaaa", "facts": ["label": "Nervous", "genre": "Deep House; Disco", "release": ""]])
        let after = try #require(e.wait(from: mark) { $0["event"] as? String == "songs" })
        let fixed = try #require((after["songs"] as? [[String: Any]])?.first?["names"] as? [String: Any])
        #expect((fixed["label"] as? [String: Any])?["from"] as? String == "user")
        #expect((fixed["genre"] as? [String: Any])?["value"] as? String == "Deep House, Disco")
        #expect((fixed["release"] as? [String: Any])?["value"] == nil || (fixed["release"] as? [String: Any])?["value"] is NSNull)
        // Saved in the crate file, as the DJ's.
        let saved = try CrateReader.read(from: home.shelf.package(info.id)).tracks[0].ident.facts
        #expect(saved["label"] == .init("Nervous", from: "user") && saved["release"] == nil)
        #expect((try e.request("song.fix", ["song": "aaaa", "facts": ["label": 3]])["error"] as? [String: Any])?["code"] as? String == "bad_request")
        mark = e.received.count
        _ = try e.request("edit.undo")
        let undone = try #require(e.wait(from: mark) { $0["event"] as? String == "songs" })
        let back = try #require((undone["songs"] as? [[String: Any]])?.first?["names"] as? [String: Any])
        #expect((back["release"] as? [String: Any])?["value"] as? String == "Friday Night")
        e.close()
        #expect(e.exitCode() == 0)
    }

    /// A song's cover (D36) through the protocol: each song says whether it has one, and `song.cover` hands over
    /// exactly the bytes of `covers/<hash>.jpg` inside its reply, with no path and no hash told. No cover, a cover
    /// file that is gone or is not a cover, and an id that names no song are all answered plainly, and the engine
    /// goes on answering.
    @Test func coversThroughTheProtocol() throws {
        let root = try scratch("engine-covers")
        let home = DeskHome(root: root.appendingPathComponent("home"))
        try home.prepare()
        let info = try home.shelf.make(name: "Friday")
        let package = home.shelf.package(info.id)
        // Not pictures: the crate file's reader asks only that a cover starts as a JPEG does and is small, and bytes
        // of every value are easy to check end to end.
        let hashA = String(repeating: "ab", count: 32), hashC = String(repeating: "0c", count: 32)
        let pictureA = Data([0xFF, 0xD8, 0xFF, 0xE0] + (0..<3000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        let pictureC = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        let covers = package.appendingPathComponent(CrateFormat.coversFolder)
        try FileManager.default.createDirectory(at: covers, withIntermediateDirectories: true)
        let fileA = package.appendingPathComponent(CrateFormat.coverPath(hashA))
        let fileC = package.appendingPathComponent(CrateFormat.coverPath(hashC))
        try pictureA.write(to: fileA)
        try pictureC.write(to: fileC)
        var a = entry("aaaa", "Song A", disc: nil, folder: nil, track: nil, rel: "a.mp3")
        a.file.cover = hashA
        let b = entry("bbbb", "Song B", disc: nil, folder: nil, track: nil, rel: "b.mp3")
        var c = entry("cccc", "Song C", disc: nil, folder: nil, track: nil, rel: "c.mp3")
        c.file.cover = hashC
        // Two songs of one release share one picture.
        var d = entry("dddd", "Song D", disc: nil, folder: nil, track: nil, rel: "d.mp3")
        d.file.cover = hashA
        try CrateWriter.write(crate([a, b, c, d], name: "Friday"), to: package)

        let e = try EngineProcess(home: home.root)
        defer { if e.process.isRunning { e.process.terminate() } }
        let songs = try #require(e.wait { $0["event"] as? String == "songs" })
        let rows = try #require(songs["songs"] as? [[String: Any]])
        func says(_ id: String) -> Bool? { rows.first { $0["id"] as? String == id }?["cover"] as? Bool }
        #expect(says("aaaa") == true && says("bbbb") == false && says("cccc") == true && says("dddd") == true)
        // The rows tell neither the hash nor where anything is.
        let rowsText = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
        #expect(!rowsText.contains(hashA) && !rowsText.contains(hashC))

        // A song with a cover: the file's bytes, whole, in the reply.
        for id in ["aaaa", "dddd"] {
            let got = try e.request("song.cover", ["song": id])
            #expect(got["ok"] as? Bool == true && got["cover"] as? Bool == true)
            #expect(got["type"] as? String == "image/jpeg")
            #expect((got["bytes"] as? NSNumber)?.intValue == pictureA.count)
            #expect(Data(base64Encoded: got["data"] as? String ?? "") == pictureA)
            #expect(got["path"] == nil)
            let text = String(decoding: try JSONSerialization.data(withJSONObject: got), as: UTF8.self)
            #expect(!text.contains(hashA) && !text.contains("deckiecrate") && !text.contains(root.lastPathComponent))
        }
        #expect(Data(base64Encoded: try e.request("song.cover", ["song": "cccc"])["data"] as? String ?? "") == pictureC)

        /// A plain "no cover": answered, not refused, and nothing sent with it.
        func none(_ fields: [String: Any], _ why: Comment) throws {
            let r = try e.request("song.cover", fields)
            #expect(r["ok"] as? Bool == true && r["cover"] as? Bool == false && r["data"] == nil && r["error"] == nil, why)
        }
        try none(["song": "bbbb"], "a song without a cover")
        // An id that names no song, and ids shaped like paths, reach no file.
        for id in ["zzzz", "", "../crate.json", "../../crate.json", hashA, "covers/\(hashA).jpg", fileA.path] {
            try none(["song": id], "no song has the id \(id)")
        }
        // The cover file gone, then there but not a cover: not a JPEG, too large, and (where links exist) a link.
        try FileManager.default.removeItem(at: fileC)
        try none(["song": "cccc"], "the cover file is missing")
        try Data("not a picture".utf8).write(to: fileC)
        try none(["song": "cccc"], "the file is not a JPEG")
        try (Data([0xFF, 0xD8, 0xFF]) + Data(count: CrateFormat.coverMaxBytes)).write(to: fileC)
        try none(["song": "cccc"], "the file is larger than a cover may be")
        #if !os(Windows)
        try FileManager.default.removeItem(at: fileC)
        try FileManager.default.createSymbolicLink(at: fileC, withDestinationURL: fileA)
        try none(["song": "cccc"], "the file is a link")
        #endif
        // Put back, it is a cover again: nothing was remembered against it.
        try? FileManager.default.removeItem(at: fileC)
        try pictureC.write(to: fileC)
        #expect(try e.request("song.cover", ["song": "cccc"])["cover"] as? Bool == true)

        // A request with no song, or one that is not text, is refused like any request missing a field.
        #expect((try e.request("song.cover")["error"] as? [String: Any])?["code"] as? String == "bad_request")
        #expect((try e.request("song.cover", ["song": 7])["error"] as? [String: Any])?["code"] as? String == "bad_request")

        // With no crate showing there is no cover either, and the engine still answers.
        _ = try e.request("crate.new")
        try none(["song": "aaaa"], "no crate is showing")
        #expect(try e.request("state")["ok"] as? Bool == true)
        e.close()
        #expect(e.exitCode() == 0)
    }

    /// A music CD through the engine program, with the stand-in drive (`DECKIE_DESK_MUSIC_CD`): listed by
    /// drives.list, added with run.addMusicCD, named by the DJ while it is read.
    @Test(.enabled(if: Engine.available, "needs ONNX Runtime and the Beat This! model"))
    func aMusicCDWithNoNamesThroughTheEngine() async throws {
        let root = try scratch("engine-music-cd")
        let drives = root.appendingPathComponent("drives")
        try MusicCDRunTests.makeDisc(drives.appendingPathComponent("E"), names: false)
        let e = try EngineProcess(home: root.appendingPathComponent("home"),
                                  environment: [MusicCDs.standInVariable: drives.path])
        defer { if e.process.isRunning { e.process.terminate() } }
        _ = e.wait { $0["event"] as? String == "state" }
        let list = try e.request("drives.list")
        let cds = try #require(list["musicCDs"] as? [[String: Any]])
        #expect(cds.count == 1 && (cds.first?["songs"] as? NSNumber)?.intValue == 2)
        let location = try #require(cds.first?["location"] as? String)
        let finished: [String: Any]? = try await CPUTurns.exclusive {
            let added = try e.request("run.addMusicCD", ["location": location])
            let ask = try #require(added["askName"] as? String)
            #expect(ask.hasPrefix("Music CD, 2 songs, "))
            #expect(try e.request("run.nameDisc", ["name": "Friday night"])["ok"] as? Bool == true)
            return e.wait(seconds: 600) { ["run.finished", "run.failed"].contains($0["event"] as? String ?? "") }
        }
        let done = try #require(finished)
        #expect(done["event"] as? String == "run.finished", "\(done)")
        let disc = try #require((done["report"] as? [String: Any])?["disc"] as? [String: Any])
        #expect(disc["text"] as? String == "none")
        #expect(!e.received.contains { $0["stage"] as? String == "copying" })
        let state = try #require(e.wait { $0["event"] as? String == "state" && ($0["current"] as? [String: Any])?["sources"] as? [String] == ["Friday night"] })
        #expect(state["undo"] as? String == "undoRename")
        // None of the disc's music is in Desk's storage.
        let home = root.appendingPathComponent("home")
        #expect(musicFiles(under: home).isEmpty)
        // Listen reads the song off the disc, as WAV, handed over in chunks; nothing is written.
        // The songs event may arrive a moment after the state event on a slow machine: wait for one that has songs.
        let songsEvent = try #require(e.wait { $0["event"] as? String == "songs" && (($0["songs"] as? [[String: Any]])?.isEmpty == false) })
        let first = try #require((songsEvent["songs"] as? [[String: Any]])?.first?["id"] as? String)
        let mark = e.received.count
        let audio = try e.request("song.audio", ["song": first], seconds: 60)
        #expect(audio["type"] as? String == "audio/wav" && audio["kind"] as? String == "WAV")
        let bytes = try #require((audio["bytes"] as? NSNumber)?.intValue)
        let count = try #require((audio["chunks"] as? NSNumber)?.intValue)
        let token = try #require(audio["token"] as? String)
        _ = e.wait(from: mark) { $0["event"] as? String == "audio.chunk" && ($0["index"] as? NSNumber)?.intValue == count - 1 }
        let parts = e.received[mark...].filter { $0["event"] as? String == "audio.chunk" && $0["token"] as? String == token }
        let joined = parts.compactMap { ($0["data"] as? String).flatMap { Data(base64Encoded: $0) } }.reduce(Data(), +)
        #expect(joined.count == bytes && joined.prefix(4) == Data("RIFF".utf8))
        #expect(musicFiles(under: home).isEmpty)
        // The disc out: Desk says which to put back.
        try FileManager.default.moveItem(at: drives.appendingPathComponent("E"), to: root.appendingPathComponent("E-out"))
        let gone = try e.request("song.audio", ["song": first])
        #expect(gone["ok"] as? Bool == false)
        #expect((gone["error"] as? [String: Any])?["code"] as? String == "not_here")
        #expect((gone["error"] as? [String: Any])?["detail"] as? String == "Friday night")
        _ = try e.request("quit")
        #expect(e.exitCode() == 0)
    }
}

/// Engines started side by side each leave when their own input closes, and are seen to (the fault described in
/// `EngineProcess.init`). With `DECKIE_TEST_UNLOCKED_STARTS` set the starts are not kept apart, which on Windows
/// with Swift 6.4.1 shows the fault; the workflow runs it that way once, report only.
@Suite struct EngineStartsTests {
    @Test func enginesStartedTogetherAreEachSeenToLeave() throws {
        let root = try scratch("engine-starts")
        let lock = NSLock()
        nonisolated(unsafe) var late = 0, started = 0
        let group = DispatchGroup()
        for worker in 0..<6 {
            group.enter()
            Thread.detachNewThread {
                defer { group.leave() }
                for round in 0..<8 {
                    let home = DeskHome(root: root.appendingPathComponent("home-\(worker)-\(round)"))
                    guard (try? home.prepare()) != nil, let e = try? EngineProcess(home: home.root) else { continue }
                    // Its first message says it is up and reading (on a busy runner that alone can take seconds).
                    guard e.wait(seconds: 60, { $0["event"] as? String == "hello" }) != nil else { e.process.terminate(); continue }
                    lock.lock(); started += 1; lock.unlock()
                    // Odd rounds stay a while, so another worker's engine is started while this one is alive.
                    if round % 2 == 1 { Thread.sleep(forTimeInterval: 0.4) }
                    e.close()
                    if e.exitCode(seconds: 20) != 0 { lock.lock(); late += 1; lock.unlock() }
                }
            }
        }
        group.wait()
        print("EngineStartsTests: \(started) engines started, \(late) not seen to leave within 20 seconds")
        #expect(started == 48)
        #expect(late == 0)
    }
}
