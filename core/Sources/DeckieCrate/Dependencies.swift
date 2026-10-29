import Foundation

/// `core/dependencies.json`: everything Deckie ships that it did not write itself, one entry per row of the apps'
/// acknowledgements screen. It is the source of that screen so that the apps read plain JSON, the way they read a
/// crate, and never have to parse Markdown. The table at the top of `DEPENDENCIES.md` is generated from it by
/// `core/Tools/render_dependencies_table.py`, and a test fails when the two differ; the sections of `DEPENDENCIES.md`
/// stay the evidence (licence quotes, hashes, training sets), written by hand. Keys are snake case and decoded with a
/// plain `JSONDecoder`, as the crate's files are.
public struct Dependencies: Codable, Equatable, Sendable {
    /// The file format this build reads. A later format is refused rather than shown half understood.
    public static let format = 1

    /// The file's format version.
    public var format: Int
    /// In the order they ship, which is the table's order.
    public var entries: [DependencyEntry]

    public init(format: Int = Dependencies.format, entries: [DependencyEntry]) {
        self.format = format
        self.entries = entries
    }

    /// Reads the file at `url`. A missing field or a wrong type throws the decoder's error, which names the field.
    public static func read(from url: URL) throws -> Dependencies {
        let read = try JSONDecoder().decode(Dependencies.self, from: Data(contentsOf: url))
        if read.format > Dependencies.format {
            throw CrateError([CrateProblem(file: url.lastPathComponent, path: "format", message:
                "is \(read.format); this build reads format \(Dependencies.format) and would miss what is new")])
        }
        return read
    }

    /// The acknowledgements table in Markdown, byte for byte what the script writes into `DEPENDENCIES.md`: the
    /// header row, the separator row and one row per entry, each line ending in a newline. A `|` inside a value is
    /// escaped as `\|` so it cannot split a cell, and a nil value is an empty cell. The script and this function
    /// must change together; the test compares their output through the committed file.
    public func markdownTable() -> String {
        func cell(_ value: String?) -> String {
            guard let value, !value.isEmpty else { return " " }
            return " " + value.replacingOccurrences(of: "|", with: "\\|") + " "
        }
        let header = ["Entry", "Version", "Licence", "Training sets and their terms (models)",
                      "Replacement path (models)"]
        var lines = ["|" + header.map(cell).joined(separator: "|") + "|",
                     "|" + header.map { _ in "---" }.joined(separator: "|") + "|"]
        for e in entries {
            let cells = [e.name, e.version, e.licence, e.trainingSets, e.replacementPath].map(cell)
            lines.append("|" + cells.joined(separator: "|") + "|")
        }
        return lines.map { $0 + "\n" }.joined()
    }
}

/// One shipped dependency: a row of the acknowledgements table.
public struct DependencyEntry: Codable, Equatable, Sendable {
    /// Stable and kebab case (`dr-mp3`, `beat-this`), so the apps can refer to an entry while its wording changes.
    public var id: String
    /// As the screen shows it (the table's Entry column).
    public var name: String
    public var version: String
    /// The licence as it names itself, with the section of `DEPENDENCIES.md` that quotes it.
    public var licence: String
    /// For a model, the data its weights were trained on and that data's terms; nil for code.
    public var trainingSets: String?
    /// For a model, what Deckie does without it; nil for code.
    public var replacementPath: String?

    public init(id: String, name: String, version: String, licence: String, trainingSets: String? = nil,
                replacementPath: String? = nil) {
        self.id = id
        self.name = name
        self.version = version
        self.licence = licence
        self.trainingSets = trainingSets
        self.replacementPath = replacementPath
    }

    enum CodingKeys: String, CodingKey {
        case id, name, version, licence, trainingSets = "training_sets", replacementPath = "replacement_path"
    }
}
