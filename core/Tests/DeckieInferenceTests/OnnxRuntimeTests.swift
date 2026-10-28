import Foundation
import Testing
import DeckieInference

/// What this machine has. ONNX Runtime is fetched per machine (core/Tools/fetch-onnxruntime.sh), so the tests that
/// need it are skipped, with the reason, where it is missing: a fresh checkout, and the Windows CI probe.
enum Available {
    static let library: String? = {
        let found = OnnxRuntime.locateLibrary()
        if found == nil {
            print("ONNX Runtime not found (looked at: \(OnnxRuntime.libraryCandidates().joined(separator: ", "))): the tests that run it are skipped; run core/Tools/fetch-onnxruntime.sh or set \(OnnxRuntime.libraryEnvironmentVariable)")
        }
        return found
    }()

    static var runtime: Bool { library != nil }

    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    /// Tools/make_onnx_fixture.py's model: scaled = 2 x, shifted = 2 x + bias, x of shape [n, 3].
    static let affine = fixtures.appendingPathComponent("affine.onnx").path
}

@Suite struct OnnxRuntimeLoadingTests {
    /// A library path that does not exist is reported as not found, with the path.
    @Test func missingLibraryIsReported() {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-dir/\(OnnxRuntime.libraryFileName)").path
        #expect(throws: OnnxRuntimeError.libraryNotFound(searched: [path])) { try OnnxRuntime.load(libraryPath: path) }
    }

    /// A file that is not a library is refused with the system loader's reason.
    @Test func aFileThatIsNotALibraryIsRefused() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-not-a-library-\(UUID().uuidString)").path
        try Data("not a shared library".utf8).write(to: URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            _ = try OnnxRuntime.load(libraryPath: path)
            Issue.record("loaded a text file as a library")
        } catch let OnnxRuntimeError.libraryNotLoaded(p, reason) {
            #expect(p == path)
            #expect(!reason.isEmpty)
            print("not a library: \(reason)")
        }
    }

    @Test(.enabled(if: Available.runtime, "ONNX Runtime not found: run core/Tools/fetch-onnxruntime.sh or set DECKIE_ONNXRUNTIME_LIB"))
    func libraryLoads() throws {
        let rt = try OnnxRuntime.load()
        print("ONNX Runtime \(rt.version) from \(rt.libraryPath), C API version \(rt.apiVersion)")
        #expect(rt.apiVersion == 31)
        #expect(rt.version.hasPrefix("1."))
        #expect(try OnnxRuntime.load() === rt, "one OnnxRuntime per library")
    }

    /// The release's helper library opens but has no OrtGetApiBase (Linux release layout only).
    @Test(.enabled(if: Available.library.map { FileManager.default.fileExists(atPath: Self.helper($0)) } ?? false,
                   "needs ONNX Runtime's Linux release, whose lib folder has libonnxruntime_providers_shared.so"))
    func aLibraryThatIsNotOnnxRuntimeIsRefused() {
        let path = Self.helper(Available.library!)
        do {
            _ = try OnnxRuntime.load(libraryPath: path)
            Issue.record("took \(path) for ONNX Runtime")
        } catch let OnnxRuntimeError.notOnnxRuntime(p, reason) {
            #expect(p == path)
            print("not ONNX Runtime: \(reason)")
        } catch {
            Issue.record("unexpected \(error)")
        }
    }

    static func helper(_ library: String) -> String {
        URL(fileURLWithPath: library).deletingLastPathComponent().appendingPathComponent("libonnxruntime_providers_shared.so").path
    }
}

@Suite(.enabled(if: Available.runtime, "ONNX Runtime not found: run core/Tools/fetch-onnxruntime.sh or set DECKIE_ONNXRUNTIME_LIB"))
struct OnnxSessionTests {
    func session(_ options: OnnxRuntime.SessionOptions = .init()) throws -> OnnxSession {
        try OnnxRuntime.load().makeSession(modelPath: Available.affine, options: options)
    }

    @Test func runsAModel() throws {
        let s = try session()
        #expect(s.inputNames == ["x", "bias"])
        #expect(s.outputNames == ["scaled", "shifted"])
        let x = OnnxTensor(shape: [2, 3], values: [0, 1, 2, 3, 4, 5])
        let out = try s.run(["x": x, "bias": OnnxTensor(shape: [3], values: [0.5, -1, 10])])
        #expect(out["scaled"] == OnnxTensor(shape: [2, 3], values: [0, 2, 4, 6, 8, 10]))
        #expect(out["shifted"] == OnnxTensor(shape: [2, 3], values: [0.5, 1, 14, 6.5, 7, 20]))
        // The first axis is free: four rows, and only one of the outputs.
        let four = try s.run(["x": OnnxTensor(shape: [4, 3], values: (0..<12).map(Float.init)),
                              "bias": OnnxTensor(shape: [3], values: [0, 0, 0])], outputs: ["shifted"])
        #expect(Array(four.keys) == ["shifted"])
        #expect(four["shifted"]?.shape == [4, 3])
        #expect(four["shifted"]?.values == (0..<12).map { Float(2 * $0) })
        // No rows at all.
        let none = try s.run(["x": OnnxTensor(shape: [0, 3], values: []), "bias": OnnxTensor(shape: [3], values: [1, 2, 3])])
        #expect(none["scaled"] == OnnxTensor(shape: [0, 3], values: []))
    }

    /// Thread counts and every graph optimisation level give the same answer.
    @Test func optionsAreApplied() throws {
        let input = ["x": OnnxTensor(shape: [2, 3], values: [1, 2, 3, 4, 5, 6]), "bias": OnnxTensor(shape: [3], values: [1, 1, 1])]
        let reference = try session().run(input)
        for level in [OnnxRuntime.SessionOptions.GraphOptimization.disabled, .basic, .extended, .all] {
            for threads in [1, 2] {
                let s = try session(.init(intraOpThreads: threads, interOpThreads: 1, graphOptimization: level))
                #expect(s.options.graphOptimization == level)
                #expect(try s.run(input) == reference, "\(level), \(threads) threads")
            }
        }
        #expect(throws: OnnxRuntimeError.self) { try session(.init(intraOpThreads: -1)) }
    }

    /// ONNX Runtime's own errors arrive as `.runtime` with its code and message; mistakes found before calling it
    /// arrive as `.invalidInput`.
    @Test func errorsCarryOnnxRuntimesMessage() throws {
        let s = try session()
        func runtimeError(_ body: () throws -> Void) -> (OnnxRuntimeError.Code, String)? {
            do { try body() } catch let OnnxRuntimeError.runtime(code, message) { return (code, message) } catch {
                Issue.record("unexpected \(error)")
            }
            return nil
        }
        // A wrong second dimension.
        let wrongShape = runtimeError {
            _ = try s.run(["x": OnnxTensor(shape: [2, 4], values: [Float](repeating: 0, count: 8)),
                           "bias": OnnxTensor(shape: [3], values: [0, 0, 0])])
        }
        #expect(wrongShape?.0 == .invalidArgument)
        #expect(wrongShape?.1.isEmpty == false)
        print("wrong shape: \(wrongShape.map { "\($0.0): \($0.1)" } ?? "no error")")
        // A missing input: ONNX Runtime 1.31 reports it as a plain failure of the node that needed it.
        let missing = runtimeError { _ = try s.run(["x": OnnxTensor(shape: [1, 3], values: [0, 0, 0])]) }
        #expect(missing?.1.contains("Missing Input: bias") == true)
        print("missing input: \(missing.map { "\($0.0): \($0.1)" } ?? "no error")")
        // No model file, and a file that is not a model.
        let rt = try OnnxRuntime.load()
        let noFile = runtimeError { _ = try rt.makeSession(modelPath: Available.fixtures.appendingPathComponent("absent.onnx").path) }
        #expect(noFile?.0 == .noSuchFile)
        print("no model file: \(noFile.map { "\($0.0): \($0.1)" } ?? "no error")")
        let junk = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-junk-\(UUID().uuidString).onnx")
        try Data("this is not a model".utf8).write(to: junk)
        defer { try? FileManager.default.removeItem(at: junk) }
        let notModel = runtimeError { _ = try rt.makeSession(modelPath: junk.path) }
        #expect(notModel?.0 == .invalidProtobuf)
        print("not a model: \(notModel.map { "\($0.0): \($0.1)" } ?? "no error")")
        // Caught before ONNX Runtime: an unknown name, a shape that does not fit the values, an unknown output.
        #expect(throws: OnnxRuntimeError.self) { try s.run(["y": OnnxTensor(shape: [1, 3], values: [0, 0, 0])]) }
        #expect(throws: OnnxRuntimeError.self) { try s.run(["x": OnnxTensor(shape: [2, 3], values: [0, 0, 0])]) }
        #expect(throws: OnnxRuntimeError.self) {
            try s.run(["x": OnnxTensor(shape: [1, 3], values: [0, 0, 0]), "bias": OnnxTensor(shape: [3], values: [0, 0, 0])],
                      outputs: ["nothing"])
        }
    }

    /// Sessions run from several threads at once.
    @Test func runsConcurrently() async throws {
        let s = try session()
        try await withThrowingTaskGroup(of: Bool.self) { group in
            for k in 0..<8 {
                group.addTask {
                    let v = Float(k)
                    let out = try s.run(["x": OnnxTensor(shape: [1, 3], values: [v, v, v]), "bias": OnnxTensor(shape: [3], values: [1, 1, 1])])
                    return out["shifted"]?.values == [2 * v + 1, 2 * v + 1, 2 * v + 1]
                }
            }
            for try await ok in group { #expect(ok) }
        }
    }
}
