import Foundation
import Testing
@testable import DeckieCrate

// core/dependencies.json, the source of the apps' acknowledgements screen, and the table in DEPENDENCIES.md that
// core/Tools/render_dependencies_table.py generates from it.

@Suite struct DependenciesTests {
    static let regenerate = "python3 core/Tools/render_dependencies_table.py"
    static let start = "<!-- dependencies-table: generated from core/dependencies.json by " +
        "core/Tools/render_dependencies_table.py; do not edit by hand -->\n"
    static let end = "<!-- /dependencies-table -->\n"

    @Test func everyEntryIsComplete() throws {
        let deps = try Dependencies.read(from: Paths.dependencies)
        #expect(deps.format == Dependencies.format)
        #expect(!deps.entries.isEmpty)
        for e in deps.entries {
            for (field, value) in [("id", e.id), ("name", e.name), ("version", e.version), ("licence", e.licence)] {
                #expect(!value.trimmingCharacters(in: .whitespaces).isEmpty, "\(e.id): \(field) is empty")
            }
            // A line break would end the table row early.
            for value in [e.id, e.name, e.version, e.licence, e.trainingSets ?? "", e.replacementPath ?? ""] {
                let oneLine = !value.contains { $0.isNewline }
                #expect(oneLine, "\(e.id): a value spans more than one line")
            }
            let words = e.id.split(separator: "-", omittingEmptySubsequences: false)
            let kebab = words.allSatisfy { word in
                !word.isEmpty && word.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) }
            }
            #expect(kebab, "\(e.id): an id is lower-case letters and digits in words joined by single hyphens")
        }
        let ids = deps.entries.map(\.id)
        #expect(Set(ids).count == ids.count, "an id is used twice: \(ids)")
    }

    @Test func theTableInDependenciesMdIsGenerated() throws {
        let deps = try Dependencies.read(from: Paths.dependencies)
        // GitHub's Windows machines check the repository out with Windows line endings (Git's autocrlf), which the
        // generated table, written with plain newlines, must not fail on: compare line by line, not byte by byte.
        let doc = try String(contentsOf: Paths.dependenciesDoc, encoding: .utf8).replacingOccurrences(of: "\r\n", with: "\n")
        let starts = doc.ranges(of: Self.start), ends = doc.ranges(of: Self.end)
        try #require(starts.count == 1 && ends.count == 1 && starts[0].upperBound <= ends[0].lowerBound,
                     "DEPENDENCIES.md needs one opening and one closing dependencies-table marker, in that order")
        let block = String(doc[starts[0].upperBound..<ends[0].lowerBound])
        #expect(block == "\n" + deps.markdownTable() + "\n",
                "DEPENDENCIES.md's acknowledgements table differs from core/dependencies.json; run \(Self.regenerate)")
    }

    @Test func theTableEscapesPipesAndLeavesNullsEmpty() {
        let deps = Dependencies(entries: [
            DependencyEntry(id: "a", name: "A | B", version: "1", licence: "MIT"),
            DependencyEntry(id: "m", name: "M", version: "2", licence: "Apache 2.0", trainingSets: "S",
                            replacementPath: "R"),
        ])
        #expect(deps.markdownTable() == """
            | Entry | Version | Licence | Training sets and their terms (models) | Replacement path (models) |
            |---|---|---|---|---|
            | A \\| B | 1 | MIT | | |
            | M | 2 | Apache 2.0 | S | R |

            """)
    }

    @Test func roundTripsThroughTheCrateEncoderWithSnakeCaseKeys() throws {
        let deps = try Dependencies.read(from: Paths.dependencies)
        let text = CanonicalJSON.text(try CanonicalJSON.tree(deps, decimals: [:]))
        #expect(text.contains(#""training_sets":null"#) && text.contains(#""replacement_path":"#))
        #expect(!text.contains("trainingSets") && !text.contains("replacementPath"))
        #expect(try JSONDecoder().decode(Dependencies.self, from: Data(text.utf8)) == deps)
    }

    @Test func aLaterFormatIsRefused() throws {
        let url = try temporaryFolder().appendingPathComponent("dependencies.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data(#"{"format": 2, "entries": []}"#.utf8).write(to: url)
        let refusal = CrateProblem(file: "dependencies.json", path: "format",
                                   message: "is 2; this build reads format 1 and would miss what is new")
        #expect(throws: CrateError([refusal])) { try Dependencies.read(from: url) }
    }
}
