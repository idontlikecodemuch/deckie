import Foundation
import DeckieTestSupport

// The test track itself, `TestTrack`, is in DeckieTestSupport, shared with the crate builder's tests.

/// A folder of its own under the system's temporary folder, for the files a test writes (the track is 23 MB as WAV),
/// one per test process. The folders of earlier runs whose process has ended are removed the first time.
func temporaryFolder(_ name: String) throws -> URL {
    _ = removeEarlierRuns
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(temporaryPrefix)\(ProcessInfo.processInfo.processIdentifier)")
        .appendingPathComponent(name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private let temporaryPrefix = "deckie-engine-tests-"

private let removeEarlierRuns: Void = {
    #if !os(Windows)
    let fm = FileManager.default, tmp = fm.temporaryDirectory
    for name in (try? fm.contentsOfDirectory(atPath: tmp.path)) ?? [] where name.hasPrefix(temporaryPrefix) {
        // kill with signal 0 only asks whether the process is still there.
        if let pid = Int32(name.dropFirst(temporaryPrefix.count)), pid != getpid(), kill(pid, 0) != 0 {
            try? fm.removeItem(at: tmp.appendingPathComponent(name))
        }
    }
    #endif
}()

/// The ffmpeg program, if one is installed where programs usually are (used only to make the MP3 test file).
func findFFmpeg() -> String? { TestTrack.findFFmpeg() }

/// The repository's root, found from this file's place in it.
let repositoryRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent()
