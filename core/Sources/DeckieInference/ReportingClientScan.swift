import Foundation

extension OnnxRuntime {
    /// Traces of Microsoft's usage-reporting client ("telemetry") in an ONNX Runtime library file.
    ///
    /// Microsoft's official builds report usage to Microsoft unless `ORT_DISABLE_TELEMETRY` is set before the library
    /// starts (`deckie_ort.c` sets it). That is enough for development, CI and the bench, but a shipped build must not
    /// trust the library to honour a setting: it carries a library Deckie builds from the pinned release with
    /// `--no_telemetry`, which leaves the client out, and the release test `shippedLibrariesCarryNoReportingClient`
    /// scans each shipped library with this (DEPENDENCIES.md, section 6; status log entry 12). The markers are text
    /// read from the official 1.31.1 libraries: the address reported to, the 1DS client's own names (the C++
    /// namespace `Microsoft::Applications::Events` as the compiler writes it, ONNX Runtime's source file names for
    /// the client), the libraries the client brings with it (curl, SQLite, mbedTLS) and, on Windows, the name of the
    /// event-tracing provider the Windows build reports through.
    public enum ReportingClientScan {
        public struct Marker: Sendable, Equatable {
            /// What the text is, in words.
            public let name: String
            /// The bytes looked for, as text.
            public let text: String
        }

        public static let markers: [Marker] = [
            .init(name: "the reporting address", text: "mobile.events.data.microsoft.com"),
            .init(name: "the 1DS client's namespace", text: "Microsoft12Applications6Events"),
            .init(name: "ONNX Runtime's 1DS source file", text: "telemetry_1ds"),
            .init(name: "ONNX Runtime's 1DS provider class", text: "OneDsTelemetry"),
            .init(name: "the 1DS client's curl transport", text: "CurlHttpOperation"),
            .init(name: "curl's documentation address", text: "https://curl.se/docs/"),
            .init(name: "SQLite's file header", text: "SQLite format 3"),
            .init(name: "mbedTLS's TLS functions", text: "mbedtls_ssl_"),
            .init(name: "the Windows event-tracing provider", text: "Microsoft.ML.ONNXRuntime"),
        ]

        /// The markers found in the file at `path`, in `markers` order; empty for a library without the client.
        public static func scan(libraryAt path: String) throws -> [Marker] {
            guard FileManager.default.fileExists(atPath: path) else {
                throw OnnxRuntimeError.libraryNotFound(searched: [path])
            }
            let bytes = try Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
            return markers.filter { contains(bytes, $0.text) }
        }

        /// Whether `bytes` contains `text`'s UTF-8, by a plain byte search (the libraries are tens of megabytes and
        /// there are a few markers, so a simple search is quick enough: well under a second).
        static func contains(_ bytes: Data, _ text: String) -> Bool {
            let needle = Array(text.utf8)
            guard let first = needle.first, bytes.count >= needle.count else { return false }
            return bytes.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
                let hay = raw.bindMemory(to: UInt8.self)
                let last = hay.count - needle.count
                var i = 0
                while i <= last {
                    if hay[i] == first {
                        var j = 1
                        while j < needle.count && hay[i + j] == needle[j] { j += 1 }
                        if j == needle.count { return true }
                    }
                    i += 1
                }
                return false
            }
        }
    }
}
