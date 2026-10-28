import Foundation

/// Where the lab's files and the fixtures are, relative to this source file (core/Tests/DeckieCoreTests/).
enum RepoPaths {
    static let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let fixtures = testsDir.appendingPathComponent("Fixtures")
    static let root = testsDir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let mixer = root.appendingPathComponent("mixer")
    static let features = mixer.appendingPathComponent("features")
    static let candidates = mixer.appendingPathComponent("candidates.json")
    static let recs = mixer.appendingPathComponent("recs.json")

    static func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: fixtures.appendingPathComponent(name)))
    }
}

/// |a - b| <= tol, as a readable expression in test failures.
func near(_ a: Double, _ b: Double, _ tol: Double) -> Bool { abs(a - b) <= tol }
