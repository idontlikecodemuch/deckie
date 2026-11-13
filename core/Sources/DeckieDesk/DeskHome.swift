import Foundation

/// Where a desk keeps everything it makes (D28): its crates, with their work folders, and what it worked out for each
/// file, shared by every crate. A DJ never chooses this place and never sees it; a crate file appears only when one
/// is sent or exported.
///
///   <home>/                          ~/Library/Application Support/Deckie Desk (or DECKIE_DESK_HOME)
///     desk.json                      the layout's format number
///     Crates/<id>/                   one folder per crate; <id> is a lowercase UUID made with the crate
///       crate.json                   the crate's name, when it was made and last opened, where its music was read
///       crate.deckiecrate/           the crate file itself, written as the DJ works (crate v1, unchanged)
///       crate.deckiebuild/           the builder's work folder: which file is which record, for a quick re-read
///       corrections.json             the DJ's name fixes, by entry id, put back after every read
///       places.json                  where each place's file was, below its source's top or the music folder
///       pending.json                 a run that started and has not finished (gone when it finishes)
///       runs.jsonl                   one line per finished run: counts and timings
///     Files/                         what was worked out for each file, by the file's id (its content's hash)
///       records/<id>.json            the analysis (the builder's work record)
///       signatures/<id>_<v>.*        a recognition signature and who made it when
///       prints/<id>.print            the print that finds copies of the same recording
///     Outbox/<name>.deckiecrate      the last crate file handed to the share sheet
public struct DeskHome: Sendable, Equatable {
    /// Overrides the place (tests and manual runs use it so nothing touches the real app storage).
    public static let environmentVariable = "DECKIE_DESK_HOME"
    /// The folder's name inside the system's application-support folder.
    public static let folderName = "Deckie Desk"
    public static let format = 1

    public let root: URL

    public init(root: URL) { self.root = root.standardizedFileURL }

    /// `DECKIE_DESK_HOME` when set, else `Deckie Desk` in the user's application-support folder.
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> DeskHome {
        if let p = environment[environmentVariable], !p.isEmpty {
            return DeskHome(root: URL(fileURLWithPath: (p as NSString).expandingTildeInPath, isDirectory: true))
        }
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return DeskHome(root: support.appendingPathComponent(folderName, isDirectory: true))
    }

    public var cratesFolder: URL { root.appendingPathComponent("Crates", isDirectory: true) }
    public var filesFolder: URL { root.appendingPathComponent("Files", isDirectory: true) }
    public var outbox: URL { root.appendingPathComponent("Outbox", isDirectory: true) }

    public var shelf: CrateShelf { CrateShelf(home: self) }
    public var store: FileStore { FileStore(folder: filesFolder) }

    /// Makes the folders and the format marker; refuses a folder made by a newer desk.
    public func prepare() throws {
        let fm = FileManager.default
        for u in [root, cratesFolder, filesFolder] { try fm.createDirectory(at: u, withIntermediateDirectories: true) }
        let marker = root.appendingPathComponent("desk.json")
        if let data = try? Data(contentsOf: marker),
           let f = (try? JSONDecoder().decode([String: Int].self, from: data))?["format"], f > Self.format {
            throw DeskError("\(root.path) was made by a newer Deckie Desk (format \(f)); this one reads format \(Self.format)")
        }
        try Data("{\"format\":\(Self.format)}\n".utf8).write(to: marker, options: .atomic)
    }
}

/// A desk's own failure, said in a sentence.
public struct DeskError: Error, CustomStringConvertible, LocalizedError {
    public let description: String
    public init(_ d: String) { description = d }
    public var errorDescription: String? { description }
}

enum JSONFile {
    static func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try e.encode(value).write(to: url, options: .atomic)
    }
}
