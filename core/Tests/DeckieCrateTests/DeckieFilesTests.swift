import Foundation
import Testing
@testable import DeckieCrate
#if os(Windows)
import WinSDK
#endif

/// DeckieFiles: a write, replace, move, copy or delete that meets a file another program holds for a moment tries
/// again and succeeds; one that meets a file held for good fails after about a second, saying which file.
@Suite(.serialized) struct DeckieFilesTests {
    struct Held: Error {}
    struct Real: Error {}

    func folder(_ name: String) throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-files-\(name)-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    // MARK: the rule, on every system (the held file is simulated by an error the rule is told is transient)

    @Test func aMomentaryHoldIsWaitedOut() throws {
        var calls = 0
        let v = try DeckieFiles.retrying("write", "/x/crate.json", pauses: [0.01, 0.01, 0.01], transient: { $0 is Held }) { () -> Int in
            calls += 1
            if calls < 3 { throw Held() }
            return 7
        }
        #expect(v == 7 && calls == 3)
    }

    @Test func aHoldThatNeverEndsFailsAfterTheLastTryNamingTheFile() throws {
        var calls = 0
        let start = Date()
        do {
            try DeckieFiles.retrying("write", "/x/crate.json", transient: { $0 is Held }) { calls += 1; throw Held() }
            Issue.record("no error")
        } catch let e as DeckieFiles.HeldError {
            #expect(e.path == "/x/crate.json" && e.attempts == DeckieFiles.pauses.count + 1)
            #expect(e.description.contains("/x/crate.json") && e.description.contains("another program kept the file open"))
        }
        #expect(calls == DeckieFiles.pauses.count + 1)
        let waited = Date().timeIntervalSince(start)
        #expect(waited >= DeckieFiles.pauses.reduce(0, +) * 0.9 && waited < 3, "waited \(waited) s")
    }

    @Test func anyOtherErrorIsThrownAtOnce() throws {
        var calls = 0
        #expect(throws: Real.self) {
            try DeckieFiles.retrying("write", "/x", transient: { $0 is Held }) { calls += 1; throw Real() }
        }
        #expect(calls == 1)
    }

    @Test func theOperationsDoWhatTheySay() throws {
        let f = try folder("ops")
        let a = f.appendingPathComponent("deep/a.json")
        try DeckieFiles.write(Data("one".utf8), to: a)
        try DeckieFiles.write(Data("two".utf8), to: a)
        #expect(try Data(contentsOf: a) == Data("two".utf8))
        try DeckieFiles.append(Data("x\n".utf8), to: f.appendingPathComponent("log.jsonl"))
        try DeckieFiles.append(Data("y\n".utf8), to: f.appendingPathComponent("log.jsonl"))
        #expect(try String(contentsOf: f.appendingPathComponent("log.jsonl"), encoding: .utf8) == "x\ny\n")
        try DeckieFiles.copy(f.appendingPathComponent("deep"), to: f.appendingPathComponent("copy"))
        #expect(try Data(contentsOf: f.appendingPathComponent("copy/a.json")) == Data("two".utf8))
        try DeckieFiles.move(f.appendingPathComponent("copy"), to: f.appendingPathComponent("moved"))
        #expect(FileManager.default.fileExists(atPath: f.appendingPathComponent("moved/a.json").path))
        try DeckieFiles.remove(f.appendingPathComponent("moved"))
        try DeckieFiles.remove(f.appendingPathComponent("moved"))   // gone already: nothing to do
        #expect(!FileManager.default.fileExists(atPath: f.appendingPathComponent("moved").path))
        try DeckieFiles.remove(f)
    }

    // MARK: a real hold, where the system has one

    #if os(Windows)
    /// Opens `url` sharing nothing, as a virus scanner may: until it is closed, no one else can replace, move or
    /// delete the file.
    final class Hold: @unchecked Sendable {
        let handle: HANDLE
        init(_ url: URL) throws {
            let h = url.withUnsafeFileSystemRepresentation { p in
                String(cString: p!).withCString(encodedAs: UTF16.self) {
                    CreateFileW($0, DWORD(GENERIC_READ), 0, nil, DWORD(OPEN_EXISTING), DWORD(FILE_ATTRIBUTE_NORMAL), nil)
                }
            }
            guard let h, h != INVALID_HANDLE_VALUE else { throw Real() }
            handle = h
        }
        func release() { CloseHandle(handle) }
    }

    @Test func aFileHeldOpenIsWrittenOnceItIsLetGo() throws {
        let f = try folder("held")
        let url = f.appendingPathComponent("crate.json")
        try DeckieFiles.write(Data("before".utf8), to: url)
        let hold = try Hold(url)
        // Without the helper the same write fails while the file is held.
        #expect(throws: (any Error).self) { try Data("plain".utf8).write(to: url, options: .atomic) }
        Thread.detachNewThread { Thread.sleep(forTimeInterval: 0.3); hold.release() }
        try DeckieFiles.write(Data("after".utf8), to: url)
        #expect(try Data(contentsOf: url) == Data("after".utf8))
        let hold2 = try Hold(url)
        Thread.detachNewThread { Thread.sleep(forTimeInterval: 0.3); hold2.release() }
        try DeckieFiles.remove(f)
        #expect(!FileManager.default.fileExists(atPath: f.path))
    }

    @Test func aFileHeldForGoodFailsCleanlyNamingIt() throws {
        let f = try folder("held-for-good")
        let url = f.appendingPathComponent("desk.json")
        try DeckieFiles.write(Data("before".utf8), to: url)
        let hold = try Hold(url)
        defer { hold.release() }
        do {
            try DeckieFiles.write(Data("after".utf8), to: url)
            Issue.record("the write went through a file held open")
        } catch let e as DeckieFiles.HeldError {
            #expect(e.path == url.path && e.description.contains("desk.json"))
        }
    }
    #else
    /// On the Mac and Linux an open file never stops a write that replaces it (there is no such hold), so the write
    /// goes through at once, with the file still open.
    @Test func aFileOpenElsewhereDoesNotStopAWriteHere() throws {
        let f = try folder("open")
        let url = f.appendingPathComponent("crate.json")
        try DeckieFiles.write(Data("before".utf8), to: url)
        let h = try FileHandle(forReadingFrom: url)
        defer { try? h.close() }
        let start = Date()
        try DeckieFiles.write(Data("after".utf8), to: url)
        #expect(Date().timeIntervalSince(start) < 0.5)
        #expect(try Data(contentsOf: url) == Data("after".utf8))
        #expect(!DeckieFiles.isTransient(CocoaError(.fileWriteNoPermission)))
    }
    #endif
}
