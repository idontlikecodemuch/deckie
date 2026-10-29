import Foundation
import COnnxRuntime

/// A float32 tensor: its shape and its values in row-major order (the last index varies fastest).
public struct OnnxTensor: Sendable, Equatable {
    public var shape: [Int]
    public var values: [Float]

    public init(shape: [Int], values: [Float]) {
        self.shape = shape
        self.values = values
    }

    /// The product of the shape: how many values the shape says there are.
    public var elementCount: Int { shape.reduce(1, *) }
}

/// What went wrong, with ONNX Runtime's own message where it gave one.
public enum OnnxRuntimeError: Error, Equatable, CustomStringConvertible {
    /// ONNX Runtime's error codes (`OrtErrorCode` in onnxruntime_c_api.h).
    public enum Code: Equatable, Sendable {
        case fail, invalidArgument, noSuchFile, noModel, engineError, runtimeException, invalidProtobuf, modelLoaded
        case notImplemented, invalidGraph, executionProviderFailed, modelLoadCanceled, modelRequiresCompilation
        case notFound, deviceReset
        case other(Int)

        init(_ raw: Int) {
            let known: [Code] = [.fail, .invalidArgument, .noSuchFile, .noModel, .engineError, .runtimeException,
                                 .invalidProtobuf, .modelLoaded, .notImplemented, .invalidGraph, .executionProviderFailed,
                                 .modelLoadCanceled, .modelRequiresCompilation, .notFound, .deviceReset]
            self = raw >= 1 && raw <= known.count ? known[raw - 1] : .other(raw)
        }
    }

    /// No library at any place looked (DECKIE_ONNXRUNTIME_LIB, or the checkout's core/.deps/onnxruntime/lib).
    case libraryNotFound(searched: [String])
    /// The file is there but could not be opened (the system loader's message).
    case libraryNotLoaded(path: String, reason: String)
    /// The file opened but is not ONNX Runtime (no OrtGetApiBase).
    case notOnnxRuntime(path: String, reason: String)
    /// ONNX Runtime is older than the vendored header and does not offer its API version.
    case apiVersionUnsupported(path: String, reason: String)
    /// ONNX Runtime returned an error status.
    case runtime(code: Code, message: String)
    /// The caller's tensors or names do not fit the model, found before calling ONNX Runtime.
    case invalidInput(String)
    /// An output is not a float32 tensor.
    case unsupportedOutput(String)

    public var description: String {
        switch self {
        case .libraryNotFound(let searched):
            return "ONNX Runtime not found (looked at: \(searched.joined(separator: ", "))); run core/Tools/fetch-onnxruntime.sh or set \(OnnxRuntime.libraryEnvironmentVariable)"
        case .libraryNotLoaded(let path, let reason): return "could not open ONNX Runtime at \(path): \(reason)"
        case .notOnnxRuntime(let path, let reason): return "\(path) is not ONNX Runtime: \(reason)"
        case .apiVersionUnsupported(let path, let reason): return "\(path): \(reason)"
        case .runtime(let code, let message): return "ONNX Runtime error (\(code)): \(message)"
        case .invalidInput(let message): return "invalid input: \(message)"
        case .unsupportedOutput(let message): return "unsupported output: \(message)"
        }
    }
}

/// ONNX Runtime (Microsoft's engine for trained models, MIT), opened at run time from its shared library.
///
/// Nothing is linked at build time, so the package builds everywhere without it; `load()` opens the library named
/// by the environment variable DECKIE_ONNXRUNTIME_LIB (a full path to libonnxruntime.so, libonnxruntime.dylib or
/// onnxruntime.dll) or, when that is not set, `core/.deps/onnxruntime/lib/<name>` in the checkout this was built
/// from, where core/Tools/fetch-onnxruntime.sh puts the pinned release. The C shim (COnnxRuntime) asks the library
/// for the function table of API version 31 (ONNX Runtime 1.31); an older library is refused with its version.
///
/// One `OnnxRuntime` per library file per process (later `load` calls return the same object), holding ONNX
/// Runtime's environment (its logging and shared state), with telemetry switched off. Nothing here touches the
/// network: it opens the library file and model files the caller names, and runs them on the CPU.
public final class OnnxRuntime: @unchecked Sendable {
    public static let libraryEnvironmentVariable = "DECKIE_ONNXRUNTIME_LIB"

    /// The library's file name on this platform.
    public static var libraryFileName: String {
        #if os(Windows)
        return "onnxruntime.dll"
        #elseif canImport(Darwin)
        return "libonnxruntime.dylib"
        #else
        return "libonnxruntime.so"
        #endif
    }

    /// This checkout's core/ folder, found from this source file's path at build time (exists on a development
    /// machine; elsewhere the default path simply is not there).
    static let coreFolder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Where `load()` looks, in order: DECKIE_ONNXRUNTIME_LIB alone if it is set, else the checkout's default.
    public static func libraryCandidates() -> [String] {
        if let path = ProcessInfo.processInfo.environment[libraryEnvironmentVariable], !path.isEmpty { return [path] }
        return [coreFolder.appendingPathComponent(".deps/onnxruntime/lib").appendingPathComponent(libraryFileName).path]
    }

    /// The first candidate that exists, or nil: whether ONNX Runtime is available here.
    public static func locateLibrary() -> String? {
        libraryCandidates().first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Opens ONNX Runtime from `libraryPath`, or from the first of `libraryCandidates()` that exists.
    public static func load(libraryPath: String? = nil) throws -> OnnxRuntime {
        let path: String
        if let libraryPath {
            path = libraryPath
        } else {
            guard let found = locateLibrary() else { throw OnnxRuntimeError.libraryNotFound(searched: libraryCandidates()) }
            path = found
        }
        return try cache.runtime(for: path)
    }

    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var runtimes: [String: OnnxRuntime] = [:]

        func runtime(for path: String) throws -> OnnxRuntime {
            lock.lock()
            defer { lock.unlock() }
            if let r = runtimes[path] { return r }
            let r = try OnnxRuntime(path: path)
            runtimes[path] = r
            return r
        }
    }

    private static let cache = Cache()

    /// The file the library was opened from.
    public let libraryPath: String
    /// ONNX Runtime's own version, such as "1.31.1".
    public let version: String
    /// The C API version in use (the vendored header's).
    public let apiVersion: Int

    let api: UnsafePointer<OrtApi>
    let env: OpaquePointer

    private init(path: String) throws {
        guard FileManager.default.fileExists(atPath: path) else { throw OnnxRuntimeError.libraryNotFound(searched: [path]) }
        var error = DECKIE_ORT_LOADED
        var versionPointer: UnsafePointer<CChar>? = nil
        var message = [CChar](repeating: 0, count: 1024)
        let table = message.withUnsafeMutableBufferPointer { m in
            deckie_ort_load(path, &error, &versionPointer, m.baseAddress, m.count)
        }
        let reason = String(decoding: message.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        guard let table else {
            switch error {
            case DECKIE_ORT_NO_ENTRY_POINT: throw OnnxRuntimeError.notOnnxRuntime(path: path, reason: reason)
            case DECKIE_ORT_API_UNSUPPORTED: throw OnnxRuntimeError.apiVersionUnsupported(path: path, reason: reason)
            default: throw OnnxRuntimeError.libraryNotLoaded(path: path, reason: reason)
            }
        }
        libraryPath = path
        version = versionPointer.map { String(cString: $0) } ?? "unknown"
        apiVersion = Int(deckie_ort_header_api_version())
        api = table
        var e: OpaquePointer? = nil
        try Self.check(table, table.pointee.CreateEnv(ORT_LOGGING_LEVEL_WARNING, "deckie", &e))
        guard let e else { throw OnnxRuntimeError.runtime(code: .fail, message: "CreateEnv returned no environment") }
        env = e
        // The real switch is ORT_DISABLE_TELEMETRY, which deckie_ort_load sets before opening the library (see
        // deckie_ort.c); this call is the C API's own, kept as a second layer.
        try Self.check(table, table.pointee.DisableTelemetryEvents(e))
    }

    /// The value of `ORT_DISABLE_TELEMETRY` in this process, the switch that stops ONNX Runtime's official builds
    /// reporting usage to Microsoft. `load` sets it to "1" before opening the library unless it is already set, so
    /// after a successful load it is never nil.
    public static var telemetrySetting: String? {
        deckie_ort_telemetry_setting().map { String(cString: $0) }
    }

    deinit { api.pointee.ReleaseEnv(env) }

    /// Throws ONNX Runtime's error for a non-null status (and releases the status).
    static func check(_ api: UnsafePointer<OrtApi>, _ status: OpaquePointer?) throws {
        guard let status else { return }
        let code = Int(api.pointee.GetErrorCode(status).rawValue)
        let message = api.pointee.GetErrorMessage(status).map { String(cString: $0) } ?? "(no message)"
        api.pointee.ReleaseStatus(status)
        throw OnnxRuntimeError.runtime(code: OnnxRuntimeError.Code(code), message: message)
    }

    func check(_ status: OpaquePointer?) throws { try Self.check(api, status) }

    /// How a session runs.
    public struct SessionOptions: Sendable, Equatable {
        /// How much ONNX Runtime may rewrite the graph before running it (fusing operations and the like).
        public enum GraphOptimization: Sendable, Equatable {
            case disabled, basic, extended, all
        }

        /// Threads for the work inside one operation; 0 lets ONNX Runtime choose (one per physical core).
        public var intraOpThreads: Int
        /// Threads for running independent operations at once; 0 lets ONNX Runtime choose. Only used when ONNX
        /// Runtime's parallel execution mode is on, which these sessions leave off (its default, sequential).
        public var interOpThreads: Int
        public var graphOptimization: GraphOptimization
        /// ONNX Runtime's CPU memory arena: on, the session keeps the memory of its first runs and grows it in regions
        /// that double in size, so it never returns it and can hold up to twice what a run needs; off, each run takes
        /// its memory from the system allocator and gives it back when it ends. Either way the same kernels run in the
        /// same order on the same values, so the outputs are the same.
        public var cpuMemoryArena: Bool
        /// ONNX Runtime's memory pattern: on, the session plans one block for a run's intermediate values from the
        /// shapes of an earlier run with the same input shapes; off, each value is allocated as it is made and freed
        /// after its last use. Allocation only; the outputs are the same.
        public var memoryPattern: Bool
        /// With the arena on, return the arena's unused regions to the system at the end of every run (ONNX Runtime's
        /// run option `memory.enable_memory_arena_shrinkage`). Without the arena it does nothing. On by default: without
        /// it the arena keeps what the largest run needed, 1.4 GB for Beat This!'s 30-second chunks, for the life of
        /// the session, and one analysis peaks at 1.9 GB instead of 1.1 GB (Linux, release build, measured with
        /// deckie-memprobe); with it the runs take the same time and give bit-identical outputs.
        public var arenaShrinkage: Bool
        /// At most this many runs of the session at once; further callers wait their turn. 0: no limit (the default).
        /// Each run of a large model holds its intermediate values while it runs (Beat This!'s 30-second chunk, about
        /// 0.7 GB), so this bounds the memory of many threads sharing one session, at a cost in speed: on a four-core
        /// machine, four analyses at once took 40 percent longer with two runs at a time and 80 percent with one,
        /// because one run does not use more cores well (deckie-memprobe --model-runs).
        public var concurrentRuns: Int

        public init(intraOpThreads: Int = 0, interOpThreads: Int = 0, graphOptimization: GraphOptimization = .all,
                    cpuMemoryArena: Bool = true, memoryPattern: Bool = true, arenaShrinkage: Bool = true,
                    concurrentRuns: Int = 0) {
            self.intraOpThreads = intraOpThreads
            self.interOpThreads = interOpThreads
            self.graphOptimization = graphOptimization
            self.cpuMemoryArena = cpuMemoryArena
            self.memoryPattern = memoryPattern
            self.arenaShrinkage = arenaShrinkage
            self.concurrentRuns = concurrentRuns
        }
    }

    /// Loads the model file at `modelPath` into a session.
    public func makeSession(modelPath: String, options: SessionOptions = SessionOptions()) throws -> OnnxSession {
        try OnnxSession(runtime: self, modelPath: modelPath, options: options)
    }
}

/// A model loaded into ONNX Runtime, ready to run. `run` may be called from several threads at once (ONNX Runtime's
/// sessions allow it).
public final class OnnxSession: @unchecked Sendable {
    public let runtime: OnnxRuntime
    public let modelPath: String
    public let options: OnnxRuntime.SessionOptions
    /// The model's input and output names, in the model's order.
    public let inputNames: [String]
    public let outputNames: [String]

    let session: OpaquePointer
    /// Holds back runs beyond `options.concurrentRuns`.
    let turns: DispatchSemaphore?

    init(runtime: OnnxRuntime, modelPath: String, options: OnnxRuntime.SessionOptions) throws {
        self.runtime = runtime
        self.modelPath = modelPath
        self.options = options
        let api = runtime.api.pointee
        guard options.intraOpThreads >= 0 && options.interOpThreads >= 0 && options.concurrentRuns >= 0 else {
            throw OnnxRuntimeError.invalidInput("thread and run counts cannot be negative")
        }
        turns = options.concurrentRuns > 0 ? DispatchSemaphore(value: options.concurrentRuns) : nil
        var so: OpaquePointer? = nil
        try runtime.check(api.CreateSessionOptions(&so))
        guard let so else { throw OnnxRuntimeError.runtime(code: .fail, message: "CreateSessionOptions returned nothing") }
        defer { api.ReleaseSessionOptions(so) }
        try runtime.check(api.SetIntraOpNumThreads(so, Int32(options.intraOpThreads)))
        try runtime.check(api.SetInterOpNumThreads(so, Int32(options.interOpThreads)))
        let level: GraphOptimizationLevel
        switch options.graphOptimization {
        case .disabled: level = ORT_DISABLE_ALL
        case .basic: level = ORT_ENABLE_BASIC
        case .extended: level = ORT_ENABLE_EXTENDED
        case .all: level = ORT_ENABLE_ALL
        }
        try runtime.check(api.SetSessionGraphOptimizationLevel(so, level))
        try runtime.check(options.cpuMemoryArena ? api.EnableCpuMemArena(so) : api.DisableCpuMemArena(so))
        try runtime.check(options.memoryPattern ? api.EnableMemPattern(so) : api.DisableMemPattern(so))
        var s: OpaquePointer? = nil
        try runtime.check(deckie_ort_create_session(runtime.api, runtime.env, modelPath, so, &s))
        guard let s else { throw OnnxRuntimeError.runtime(code: .fail, message: "CreateSession returned no session") }
        session = s
        do {
            var allocator: UnsafeMutablePointer<OrtAllocator>? = nil
            try runtime.check(api.GetAllocatorWithDefaultOptions(&allocator))
            func names(count: (OpaquePointer?, UnsafeMutablePointer<Int>?) -> OpaquePointer?,
                       name: (OpaquePointer?, Int, UnsafeMutablePointer<OrtAllocator>?,
                              UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> OpaquePointer?) throws -> [String] {
                var n = 0
                try runtime.check(count(s, &n))
                return try (0..<n).map { i in
                    var p: UnsafeMutablePointer<CChar>? = nil
                    try runtime.check(name(s, i, allocator, &p))
                    defer { _ = api.AllocatorFree(allocator, p) }
                    return p.map { String(cString: $0) } ?? ""
                }
            }
            inputNames = try names(count: { api.SessionGetInputCount($0, $1) }, name: { api.SessionGetInputName($0, $1, $2, $3) })
            outputNames = try names(count: { api.SessionGetOutputCount($0, $1) }, name: { api.SessionGetOutputName($0, $1, $2, $3) })
        } catch {
            api.ReleaseSession(s)
            throw error
        }
    }

    deinit { runtime.api.pointee.ReleaseSession(session) }

    /// Runs the model on float32 inputs, given by name, and returns the requested outputs (all of them by default),
    /// by name, as float32 tensors with their shapes.
    public func run(_ inputs: [String: OnnxTensor], outputs requested: [String]? = nil) throws -> [String: OnnxTensor] {
        let api = runtime.api.pointee
        for (name, tensor) in inputs {
            guard inputNames.contains(name) else {
                throw OnnxRuntimeError.invalidInput("the model has no input \"\(name)\" (its inputs: \(inputNames.joined(separator: ", ")))")
            }
            guard tensor.shape.allSatisfy({ $0 >= 0 }), tensor.elementCount == tensor.values.count else {
                throw OnnxRuntimeError.invalidInput("\"\(name)\": shape \(tensor.shape) for \(tensor.values.count) values")
            }
        }
        let outNames = requested ?? outputNames
        for name in outNames where !outputNames.contains(name) {
            throw OnnxRuntimeError.invalidInput("the model has no output \"\(name)\" (its outputs: \(outputNames.joined(separator: ", ")))")
        }
        let inNames = Array(inputs.keys).sorted()

        var memoryInfo: OpaquePointer? = nil
        try runtime.check(api.CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memoryInfo))
        defer { api.ReleaseMemoryInfo(memoryInfo) }

        // ONNX Runtime reads the inputs in place, so each gets a buffer that lives until the run is over.
        var buffers: [UnsafeMutableBufferPointer<Float>] = []
        var values: [OpaquePointer?] = []
        defer {
            for v in values { api.ReleaseValue(v) }
            for b in buffers { b.deallocate() }
        }
        for name in inNames {
            let tensor = inputs[name]!
            let buffer = UnsafeMutableBufferPointer<Float>.allocate(capacity: max(1, tensor.values.count))
            _ = buffer.initialize(from: tensor.values)
            buffers.append(buffer)
            var shape = tensor.shape.map { Int64($0) }
            var value: OpaquePointer? = nil
            try runtime.check(api.CreateTensorWithDataAsOrtValue(
                memoryInfo, buffer.baseAddress, tensor.values.count * MemoryLayout<Float>.stride, &shape, shape.count,
                ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &value))
            values.append(value)
        }

        let inC = inNames.map(Self.cString), outC = outNames.map(Self.cString)
        defer { for p in inC + outC { p.deallocate() } }
        let inPointers = inC.map { Optional(UnsafePointer($0)) }, outPointers = outC.map { Optional(UnsafePointer($0)) }
        var results = [OpaquePointer?](repeating: nil, count: outNames.count)
        defer { for r in results where r != nil { api.ReleaseValue(r) } }
        var runOptions: OpaquePointer? = nil
        defer { if runOptions != nil { api.ReleaseRunOptions(runOptions) } }
        if options.arenaShrinkage && options.cpuMemoryArena {
            try runtime.check(api.CreateRunOptions(&runOptions))
            try runtime.check(api.AddRunConfigEntry(runOptions, "memory.enable_memory_arena_shrinkage", "cpu:0"))
        }
        turns?.wait()
        defer { turns?.signal() }
        let status = inPointers.withUnsafeBufferPointer { ip in
            outPointers.withUnsafeBufferPointer { op in
                values.withUnsafeBufferPointer { vp in
                    results.withUnsafeMutableBufferPointer { rp in
                        api.Run(session, runOptions, ip.baseAddress, vp.baseAddress, inNames.count, op.baseAddress, outNames.count,
                                rp.baseAddress)
                    }
                }
            }
        }
        try runtime.check(status)

        var out: [String: OnnxTensor] = [:]
        for (name, value) in zip(outNames, results) {
            out[name] = try tensor(name, value)
        }
        return out
    }

    /// A NUL-terminated copy of `s` (deallocate it when done).
    private static func cString(_ s: String) -> UnsafeMutablePointer<CChar> {
        let bytes = Array(s.utf8)
        let p = UnsafeMutablePointer<CChar>.allocate(capacity: bytes.count + 1)
        for (i, b) in bytes.enumerated() { p[i] = CChar(bitPattern: b) }
        p[bytes.count] = 0
        return p
    }

    /// Copies an output value out of ONNX Runtime.
    private func tensor(_ name: String, _ value: OpaquePointer?) throws -> OnnxTensor {
        let api = runtime.api.pointee
        var info: OpaquePointer? = nil
        try runtime.check(api.GetTensorTypeAndShape(value, &info))
        defer { api.ReleaseTensorTypeAndShapeInfo(info) }
        var type = ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED
        try runtime.check(api.GetTensorElementType(info, &type))
        guard type == ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT else {
            throw OnnxRuntimeError.unsupportedOutput("\"\(name)\" holds element type \(type.rawValue), not float32")
        }
        var rank = 0
        try runtime.check(api.GetDimensionsCount(info, &rank))
        var dims = [Int64](repeating: 0, count: rank)
        try runtime.check(api.GetDimensions(info, &dims, rank))
        var count = 0
        try runtime.check(api.GetTensorShapeElementCount(info, &count))
        var data: UnsafeMutableRawPointer? = nil
        try runtime.check(api.GetTensorMutableData(value, &data))
        let floats: [Float]
        if count == 0 {
            floats = []
        } else if let data {
            floats = Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self), count: count))
        } else {
            throw OnnxRuntimeError.unsupportedOutput("\"\(name)\" has no data")
        }
        return OnnxTensor(shape: dims.map { Int($0) }, values: floats)
    }
}
