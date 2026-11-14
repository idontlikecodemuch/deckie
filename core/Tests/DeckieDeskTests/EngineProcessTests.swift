import Foundation
import Testing
import DeckieAudio
import DeckieCrate
import DeckieTestSupport
@testable import DeckieDesk

/// `deckie-desk-engine` run as a child program, as Desk's window runs it, on every system the core builds on: one JSON
/// message a line in and out (docs/architecture/desk-protocol.md), with a scratch storage folder and generated songs.
final class EngineProcess: @unchecked Sendable {
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
        try process.run()
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
        let after = try #require(e.wait(from: mark) { $0["event"] as? String == "songs" })
        let a = (after["songs"] as? [[String: Any]])?.first { $0["id"] as? String == "aaaa" }
        #expect(a?["title"] as? String == "Café 東京 — ü" && a?["artist"] as? String == "Zoë" && a?["nameFrom"] as? String == "user")
        #expect(e.wait(from: mark) { $0["event"] as? String == "state" }?["undo"] as? String == "undoNameFix")
        mark = e.received.count
        _ = try e.request("edit.undo")
        let undone = try #require(e.wait(from: mark) { $0["event"] as? String == "songs" })
        #expect((undone["songs"] as? [[String: Any]])?.first { $0["id"] as? String == "aaaa" }?["title"] as? String == "Song A")

        // Sources: rename, move, how many a removal takes.
        _ = try e.request("source.rename", ["source": "Stick 3", "name": "Stick Three"])
        _ = try e.request("song.move", ["song": "bbbb", "source": "Stick Three", "folder": "House", "by": -1])
        let moved = try #require(e.last("songs"))
        let folder = (((moved["sources"] as? [[String: Any]])?.first)?["folders"] as? [[String: Any]])?.first
        #expect((folder?["songs"] as? [[String: Any]])?.map { $0["id"] as? String } == ["bbbb", "aaaa"])
        #expect((try e.request("source.removeCount", ["source": "Stick Three"])["songs"] as? NSNumber)?.intValue == 2)

        // The crate menu: rename, a new crate, back.
        let renamed = try e.request("crate.rename", ["crate": info.id, "name": "Friday late"])
        #expect(renamed["name"] as? String == "Friday late")
        _ = try e.request("crate.new")
        #expect(e.last("state")?["current"] is NSNull)
        _ = try e.request("crate.show", ["crate": info.id])
        #expect((e.last("state")?["current"] as? [String: Any])?["name"] as? String == "Friday late")

        // Export, into a folder whose name is not English either.
        let out = root.appendingPathComponent("Export ö")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let exported = try e.request("crate.export", ["folder": out.path])
        let path = try #require(exported["path"] as? String)
        #expect(try CrateReader.read(from: URL(fileURLWithPath: path)).manifest.name == "Friday late")

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
