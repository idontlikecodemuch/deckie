import Foundation
import DeckieTestSupport

/// Where the fixtures are, relative to this source file (core/Tests/DeckieCoreTests/), and the lab's data
/// (`LabData`: the private folder DECKIE_LAB_DATA names, else the public sample of invented songs).
enum RepoPaths {
    static let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let fixtures = testsDir.appendingPathComponent("Fixtures")
    static let root = testsDir.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static var features: URL { LabData.features }
    static var candidates: URL { LabData.candidates }
    static var recs: URL { LabData.recs }

    static func fixture<T: Decodable>(_ name: String, as type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(contentsOf: fixtures.appendingPathComponent(name)))
    }
}

/// |a - b| <= tol, as a readable expression in test failures.
func near(_ a: Double, _ b: Double, _ tol: Double) -> Bool { abs(a - b) <= tol }
