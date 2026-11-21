import Foundation

/// The lab's data, which the parity tests compare the Swift ports against.
///
/// The lab (mixer/) analysed a personal music library, so its own data is private and is not in the repository:
/// `DECKIE_LAB_DATA` names the folder that holds it (features/<id>.json, candidates.json, recs.json, the per-track
/// sheets, and fixtures/ with the reference numbers core/Tools/make_fixtures.py, make_bench_fixtures.py and
/// make_key_fixtures.py write for it; mixer/README.md). Without it the tests read the public sample instead,
/// core/fixtures/lab-sample: twelve invented songs in the same shapes, whose decisions the lab's own code made
/// (core/Tools/make_lab_sample.py). The few tests whose numbers only the private data has run only when it is given.
public enum LabData {
    /// The repository's root, found from this file's place in it (core/Tests/DeckieTestSupport/).
    public static let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    /// The public sample of invented songs.
    public static let sample = repositoryRoot.appendingPathComponent("core/fixtures/lab-sample")
    /// The private data folder, when `DECKIE_LAB_DATA` gives one that holds feature files.
    public static let privateRoot: URL? = {
        guard let path = ProcessInfo.processInfo.environment["DECKIE_LAB_DATA"], !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("features").path) ? url : nil
    }()
    /// Whether the tests read the lab's own (private) data.
    public static var isPrivate: Bool { privateRoot != nil }
    /// The folder the tests read: the private data when given, else the sample.
    public static var root: URL { privateRoot ?? sample }
    public static var features: URL { root.appendingPathComponent("features") }
    public static var candidates: URL { root.appendingPathComponent("candidates.json") }
    public static var recs: URL { root.appendingPathComponent("recs.json") }
    /// The reference numbers made for this data by the fixture scripts.
    public static var fixtures: URL { root.appendingPathComponent("fixtures") }
    /// A file of the data folder (a per-track sheet such as key_parity_keys.tsv).
    public static func file(_ name: String) -> URL { root.appendingPathComponent(name) }
    /// The feature files' names, sorted.
    public static func featureNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: features.path).filter { $0.hasSuffix(".json") }.sorted()
    }
    /// The number of tracks in the data read.
    public static var trackCount: Int { (try? featureNames().count) ?? 0 }
    /// Decodes one of the reference files in `fixtures`.
    public static func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: fixtures.appendingPathComponent(name)))
    }
    /// The skip message of a test that needs the private data.
    public static let needsPrivate = "needs the lab's private data: set DECKIE_LAB_DATA to its folder (mixer/README.md)"
    /// The sample's feature file used as the reference for the lab's file shape (every key the lab writes, with an
    /// empty octave_fix).
    public static let shapeReference = "sample-01"
}
