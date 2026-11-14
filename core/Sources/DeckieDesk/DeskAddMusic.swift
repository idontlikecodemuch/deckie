import Foundation
import DeckieCrate
import DeckieBuild

/// Adding music, the same everywhere a DJ can add it (research AE, findings 1 to 3; desk.md section 2): the three
/// ways in, a new crate's name, the rule for a big drive, and counting before reading anything large. The Mac's window
/// and the Windows and Linux window both take these from here, so the choices, their words and their icons cannot
/// drift apart (the pages receive `ways` in the engine's first message).
public enum DeskAddMusic {
    // MARK: the three ways in

    /// One way to add music: what it is, the word on its button, its line of help, and its icon in each window (an SF
    /// Symbol on the Mac; on the pages, the id of a drawing in index.html, `icon-<name>`).
    public struct Way: Codable, Equatable, Sendable {
        /// `drive`, `cd` or `folder`.
        public var id: String
        /// The word on its button and menu item (DeskWords).
        public var word: String
        /// Its line of help (DeskWords).
        public var help: String
        public var macSymbol: String
        public var pageIcon: String
    }

    /// The three ways, in the order every window shows them.
    public static let ways: [Way] = [
        Way(id: "drive", word: "addDrive", help: "addDriveHelp", macSymbol: "externaldrive", pageIcon: "drive"),
        Way(id: "cd", word: "addCD", help: "addCDHelp", macSymbol: "opticaldisc", pageIcon: "disc"),
        Way(id: "folder", word: "addFolder", help: "addFolderHelp", macSymbol: "folder", pageIcon: "folder"),
    ]

    // MARK: a new crate's name

    /// The name a new crate is given until the DJ types another (research AE, finding 2: never the first source's).
    public static var defaultCrateName: String { DeskWords.text("defaultCrateName") }

    /// The default name, numbered when a crate has it already ("My crate", "My crate 2", ...).
    public static func newCrateName(shelf: CrateShelf) -> String { shelf.unusedName(defaultCrateName) }

    // MARK: a big drive

    /// A drive bigger than this is read through a folder chosen inside it, not whole (research AE: sticks and cards are
    /// mostly 8 to 256 GB, a DJ's backup drive 500 GB and up). Size is the one signal used: the look-first question
    /// catches a stick that is really big, and a drive that is really a stick costs one extra choice.
    public static let bigDriveBytes: Int64 = 256 * 1_000_000_000
    /// Overrides `bigDriveBytes` (in bytes), so a test can stand a small disk image in for a big drive.
    public static let bigDriveVariable = "DECKIE_DESK_BIG_DRIVE_BYTES"

    public static func bigDriveLimit(environment: [String: String] = ProcessInfo.processInfo.environment) -> Int64 {
        environment[bigDriveVariable].flatMap(Int64.init).map { max(0, $0) } ?? bigDriveBytes
    }

    /// Whether a drive of `bytes` is big; a drive of unknown size is not.
    public static func isBig(bytes: Int64?, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        guard let bytes else { return false }
        return bytes > bigDriveLimit(environment: environment)
    }

    /// Whether `url`, chosen or dropped, is the top of a big drive (so Desk offers a folder inside it first).
    public static func isTopOfBigDrive(_ url: URL, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        DeskDrives.isTopOfDrive(url) && isBig(bytes: DeskDrives.size(of: url.path), environment: environment)
    }

    // MARK: count first, then ask

    /// Above this many songs Desk asks before reading (research AE: a stick never sees the question; a whole library
    /// does). The review's placeholder, until real first runs on ordinary laptops say where the line should be.
    public static let askAboveSongs = 1_000
    /// Overrides `askAboveSongs`, for tests.
    public static let askAboveVariable = "DECKIE_DESK_ASK_ABOVE_SONGS"

    public static func askAbove(environment: [String: String] = ProcessInfo.processInfo.environment) -> Int {
        environment[askAboveVariable].flatMap(Int.init).map { max(0, $0) } ?? askAboveSongs
    }

    /// The count is reported after every so many songs found while counting.
    public static let countReportEvery = 25
    /// Until Desk has timed a run on this computer, it estimates with this many songs read a minute (a cautious
    /// figure: research P's estimates for an ordinary laptop with two jobs).
    public static let defaultSongsPerMinute = 6.0
    /// A run counts for the estimate when at least this share of its songs were read, not taken from before.
    public static let timedRunShare = 0.5

    /// What counting found: songs (audio files, as the run would find them) and their bytes; `stopped` when the DJ
    /// cancelled the count.
    public struct Count: Codable, Equatable, Sendable {
        public var songs = 0
        public var bytes: Int64 = 0
        public var stopped = false
        public init(songs: Int = 0, bytes: Int64 = 0, stopped: Bool = false) {
            self.songs = songs; self.bytes = bytes; self.stopped = stopped
        }
    }

    /// A count that can be stopped from another thread.
    public final class CountStop: @unchecked Sendable {
        private let lock = NSLock()
        private var asked = false
        public init() {}
        public func set() { lock.lock(); asked = true; lock.unlock() }
        public var isSet: Bool { lock.lock(); defer { lock.unlock() }; return asked }
    }

    /// Counts the audio files below `folder` the way a run finds them (by extension; hidden files, crate files and
    /// work folders left out; a link to a folder not followed), reporting the count as it rises. Nothing is decoded,
    /// so this is quick even on a big drive.
    public static func count(_ folder: URL, stop: CountStop? = nil, progress: (Int) -> Void = { _ in }) -> Count {
        var c = Count()
        let fm = FileManager.default
        func walk(_ dir: URL) {
            guard !c.stopped, let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return }
            for name in names {
                if stop?.isSet == true { c.stopped = true; return }
                if name.hasPrefix(".") { continue }
                let url = dir.appendingPathComponent(name)
                let ext = CratePath.fileExtension(of: name).lowercased()
                if ext == CrateFormat.packageExtension || ext == Builder.workExtension { continue }
                guard let attrs = try? fm.attributesOfItem(atPath: url.path), let type = attrs[.type] as? FileAttributeType else { continue }
                if type == .typeDirectory { walk(url); if c.stopped { return }; continue }
                guard AudioFiles.extensions.contains(ext) else { continue }
                var size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
                if type == .typeSymbolicLink {
                    guard let t = try? fm.attributesOfItem(atPath: url.resolvingSymlinksInPath().path),
                          t[.type] as? FileAttributeType == .typeRegular else { continue }
                    size = (t[.size] as? NSNumber)?.int64Value ?? 0
                } else if type != .typeRegular { continue }
                c.songs += 1; c.bytes += size
                if c.songs % countReportEvery == 0 { progress(c.songs) }
            }
        }
        walk(folder)
        progress(c.songs)
        return c
    }

    /// Songs read a minute on this computer, from the runs Desk has timed here (the median of the runs that mostly
    /// read songs rather than took them from before), else `defaultSongsPerMinute`.
    public static func songsPerMinute(home: DeskHome) -> Double {
        var rates: [Double] = []
        for c in home.shelf.list() {
            for r in DeskRun.runs(home: home, crateId: c.id) where r.seconds > 0 && r.songsSeen > 0 {
                guard Double(r.analysed) >= timedRunShare * Double(r.songsSeen) else { continue }
                rates.append(Double(r.songsSeen) / r.seconds * 60)
            }
        }
        guard !rates.isEmpty else { return defaultSongsPerMinute }
        let s = rates.sorted()
        return s.count % 2 == 1 ? s[s.count / 2] : (s[s.count / 2 - 1] + s[s.count / 2]) / 2
    }

    /// About how long reading `songs` takes on this computer, in seconds.
    public static func estimateSeconds(songs: Int, home: DeskHome) -> Double {
        Double(songs) / max(songsPerMinute(home: home), 0.1) * 60
    }

    /// What Desk says before a large read: the count, the estimate, and whether to ask (above `askAbove`).
    public struct Check: Codable, Equatable, Sendable {
        public var path: String
        public var songs: Int
        public var bytes: Int64
        public var seconds: Double
        public var ask: Bool
        public var stopped: Bool
    }

    public static func check(_ folder: URL, home: DeskHome, environment: [String: String] = ProcessInfo.processInfo.environment,
                             stop: CountStop? = nil, progress: (Int) -> Void = { _ in }) -> Check {
        let c = count(folder, stop: stop, progress: progress)
        return Check(path: folder.path, songs: c.songs, bytes: c.bytes, seconds: estimateSeconds(songs: c.songs, home: home),
                     ask: !c.stopped && c.songs > askAbove(environment: environment), stopped: c.stopped)
    }

    /// A drive's size in words, in the decimal units a drive's box uses: "512 MB", "16 GB", "2 TB" (DeskWords `size*`).
    public static func sizeWords(_ bytes: Int64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        if gb >= 1000 { return DeskWords.text("sizeTB", ["n": roundedText(gb / 1000)]) }
        if gb >= 1 { return DeskWords.text("sizeGB", ["n": roundedText(gb)]) }
        return DeskWords.text("sizeMB", ["n": roundedText(Double(bytes) / 1_000_000)])
    }

    /// A size's number: whole above 10, one decimal below (and none when it is .0).
    static func roundedText(_ v: Double) -> String {
        if v >= 10 { return String(Int(v.rounded())) }
        let one = (v * 10).rounded() / 10
        return one == one.rounded() ? String(Int(one)) : String(format: "%.1f", one)
    }

    /// "About 2 hours" or "About 40 minutes": the estimate in words (DeskWords `about*`).
    public static func aboutWords(_ seconds: Double) -> String {
        let minutes = max(1, Int((seconds / 60).rounded()))
        if minutes < 90 { return DeskWords.count("aboutMinutes", minutes) }
        return DeskWords.count("aboutHours", Int((Double(minutes) / 60).rounded()))
    }
}
