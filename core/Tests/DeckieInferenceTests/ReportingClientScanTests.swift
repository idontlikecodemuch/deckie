import Foundation
import Testing
import DeckieInference

/// The scan for Microsoft's usage-reporting client in an ONNX Runtime library (DEPENDENCIES.md section 6; status log
/// entry 12): the release test on the libraries a build ships, and the checks that the scan itself works.
@Suite struct ReportingClientScanTests {
    typealias Scan = OnnxRuntime.ReportingClientScan

    /// The libraries a build ships, named in DECKIE_SHIPPED_ONNXRUNTIME (paths separated by ":", or ";" on Windows).
    static let shipped: [String] = {
        guard let value = ProcessInfo.processInfo.environment["DECKIE_SHIPPED_ONNXRUNTIME"], !value.isEmpty else { return [] }
        #if os(Windows)
        let separator: Character = ";"
        #else
        let separator: Character = ":"
        #endif
        return value.split(separator: separator).map(String.init).filter { !$0.isEmpty }
    }()

    /// The release test: no library a build ships carries the client. Runs only where the shipped libraries are
    /// named; the development library is Microsoft's official build and does carry it (the next test). A Windows
    /// library's unregistered provider name is reported, not fatal (`Verdict`).
    @Test(.enabled(if: !shipped.isEmpty, "no shipped library named: set DECKIE_SHIPPED_ONNXRUNTIME to the library files a build ships"))
    func shippedLibrariesCarryNoReportingClient() throws {
        for path in Self.shipped {
            let v = try Scan.verdict(libraryAt: path)
            #expect(v.passes, "\(path) carries the usage-reporting client: \(v.fatal.map(\.name).joined(separator: ", "))")
            let reported = v.reported.isEmpty ? "" : "; reported, not fatal: \(v.reported.map(\.text).joined(separator: ", ")) (present, never registered)"
            print("shipped library \(path): \(v.passes ? "no reporting client" : "REPORTING CLIENT FOUND")\(reported)")
        }
    }

    /// The Windows rule: the provider's name alone passes a .dll and is reported; the same bytes fail any other
    /// file; any other marker fails a .dll too.
    @Test func theWindowsProviderNameIsReportedNotFatalInADll() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-verdict-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let provider = try #require(Scan.markers.first { $0.text == Scan.windowsProviderName })
        let sqlite = try #require(Scan.markers.first { $0.text == "SQLite format 3" })
        let filler = Data(count: 1000)
        let nameOnly = filler + Data(provider.text.utf8) + filler
        try nameOnly.write(to: dir.appendingPathComponent("onnxruntime.dll"))
        try nameOnly.write(to: dir.appendingPathComponent("libonnxruntime.so"))
        try (nameOnly + Data(sqlite.text.utf8)).write(to: dir.appendingPathComponent("both.DLL"))
        let dll = try Scan.verdict(libraryAt: dir.appendingPathComponent("onnxruntime.dll").path)
        #expect(dll.passes && dll.fatal.isEmpty && dll.reported == [provider])
        let so = try Scan.verdict(libraryAt: dir.appendingPathComponent("libonnxruntime.so").path)
        #expect(!so.passes && so.fatal == [provider] && so.reported.isEmpty)
        let both = try Scan.verdict(libraryAt: dir.appendingPathComponent("both.DLL").path)
        #expect(!both.passes && both.fatal == [sqlite] && both.reported == [provider])
    }

    /// The official 1.31.1 Linux library (29,345,384 bytes) is known to carry the client; the scan must say so, or the
    /// release test above would pass on anything. Skipped where the development library is another build.
    @Test(.enabled(if: Available.runtime, "ONNX Runtime not found: run core/Tools/fetch-onnxruntime.sh or set DECKIE_ONNXRUNTIME_LIB"))
    func theOfficialLinuxLibraryIsSeenToCarryTheClient() throws {
        // The default path is a symbolic link (libonnxruntime.so -> .so.1 -> .so.1.31.1); the size is the file's.
        let path = URL(fileURLWithPath: try #require(Available.library)).resolvingSymlinksInPath().path
        let size = try FileManager.default.attributesOfItem(atPath: path)[.size] as? Int
        guard size == 29_345_384 else {
            print("the library at \(path) is not the official 1.31.1 Linux build (\(size ?? -1) bytes): not checked")
            return
        }
        let clock = ContinuousClock()
        var found: [Scan.Marker] = []
        let t = clock.measure { found = try! Scan.scan(libraryAt: path) }
        print("official library: \(found.count) of \(Scan.markers.count) markers in \(t): \(found.map(\.name).joined(separator: "; "))")
        let names = Set(found.map(\.text))
        #expect(names.contains("mobile.events.data.microsoft.com"))
        #expect(names.contains("Microsoft12Applications6Events"))
        #expect(names.contains("telemetry_1ds") && names.contains("OneDsTelemetry"))
        #expect(names.contains("CurlHttpOperation") && names.contains("https://curl.se/docs/"))
        #expect(names.contains("SQLite format 3") && names.contains("mbedtls_ssl_"))
        #expect(!names.contains("Microsoft.ML.ONNXRuntime"), "the Windows provider name is not in the Linux library")
        #expect(t < .seconds(5))
    }

    /// The scan on files of known content: each marker alone is found, a marker split across the read is still found
    /// (the search is over the whole file), and a file of other bytes gives nothing.
    @Test func scanOnKnownFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var filler = Data(count: 100_000)
        for i in 0..<filler.count { filler[i] = UInt8(truncatingIfNeeded: i &* 31 &+ 7) }
        let clean = dir.appendingPathComponent("clean.so")
        try filler.write(to: clean)
        #expect(try Scan.scan(libraryAt: clean.path).isEmpty)
        for marker in Scan.markers {
            var bytes = filler
            bytes.append(Data(marker.text.utf8))
            bytes.append(filler)
            let path = dir.appendingPathComponent("\(marker.text.hashValue).so")
            try bytes.write(to: path)
            #expect(try Scan.scan(libraryAt: path.path) == [marker], Comment(rawValue: marker.name))
        }
        // A marker's prefix alone, and the marker at the very start and the very end of a file.
        try Data("mobile.events.data.microsoft".utf8).write(to: clean)
        #expect(try Scan.scan(libraryAt: clean.path).isEmpty)
        try Data("mobile.events.data.microsoft.com".utf8).write(to: clean)
        #expect(try Scan.scan(libraryAt: clean.path).map(\.text) == ["mobile.events.data.microsoft.com"])
        try (filler + Data("SQLite format 3".utf8)).write(to: clean)
        #expect(try Scan.scan(libraryAt: clean.path).map(\.text) == ["SQLite format 3"])
        #expect(throws: OnnxRuntimeError.libraryNotFound(searched: [dir.appendingPathComponent("missing").path])) {
            try Scan.scan(libraryAt: dir.appendingPathComponent("missing").path)
        }
    }
}
