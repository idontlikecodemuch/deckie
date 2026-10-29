import Foundation
import Testing
import DeckieCrate
@testable import DeckieBuild

/// The work folder keeps a record whole, sidecar values included, and reads back its lines as the last one per path.
@Suite struct WorkStoreTests {
    static func track() -> CrateTrack {
        CrateTrack(
            id: "0123456789abcdef",
            file: .init(name: "a.mp3", rel: "CD1/a.mp3", bytes: 10, sha1Head: nil,
                        sha256: "0123456789abcdef" + String(repeating: "0", count: 48), durationS: 60),
            ident: .init(title: "a", source: "filename"),
            analysis: .init(engine: "deckie-0.1.0", analysedAt: "2026-10-28T12:00:00Z", device: "linux-x86_64", secs: 1.5,
                            level: 1),
            engine: .init(family: "deckie", version: "0.1.0", platform: "linux-x86_64", fidelity: 0,
                          models: [.init(name: "beat-this-final0")], decoder: .init(name: "dr_mp3", version: "0.7.4")),
            grid: .init(source: "beat-this-final0", confidence: 0.9, bpm: 124, firstDownbeatS: 0.5, nBars: 4,
                        fitMadMs: 2, bpmIn: 124, bpmOut: 124, inTrusted: true, outTrusted: true),
            flags: ["vocal_unknown"],
            style: .init(model: "yamnet", values: [0.1, -0.2, 0.3]),
            bars: BarSeries([BarSeries.lufs: [-10, -9.5, -9, -12]]))
    }

    @Test func keepsARecordWholeAndTheLastLinePerPath() throws {
        let folder = try temporaryFolder("work-store").appendingPathComponent("Test.deckiebuild")
        let store = try WorkStore(folder: folder, fresh: true)
        let t = Self.track()
        try store.save(.init(engine: "k", bpmTag: 124, track: t, bars: t.bars?.series, style: t.style?.values))
        let back = try #require(store.record(t.id))
        #expect(back.crateTrack == t && back.bpmTag == 124 && back.engine == "k")
        // The record is good for the crate as it is.
        let probe = CrateManifest(crateId: "x", name: "x", createdAt: "2026-10-28T12:00:00Z", devicesSeen: [])
        _ = try CrateWriter.encode(Crate(manifest: probe, tracks: [back.crateTrack]))

        try store.append(.init(rel: "CD1/a.mp3", size: 10, modified: 1, status: "failed", engine: "k", reason: "damaged",
                               message: "cut short"))
        try store.append(.init(rel: "CD1/a.mp3", size: 10, modified: 2, status: "ok", engine: "k", id: t.id, bpmTag: 124))
        // A line cut short by an interruption is ignored, and the next run starts on a fresh line.
        let handle = try FileHandle(forWritingTo: store.linesFile)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(#"{"rel":"CD1/b.mp3","si"#.utf8))
        try handle.close()
        let again = try WorkStore(folder: folder, fresh: false)
        #expect(again.line(for: "CD1/a.mp3")?.status == "ok" && again.line(for: "CD1/a.mp3")?.modified == 2)
        #expect(again.line(for: "CD1/b.mp3") == nil)
        try again.append(.init(rel: "CD1/c.mp3", size: 1, modified: 3, status: "ok", engine: "k", id: t.id))
        #expect(try WorkStore(folder: folder, fresh: false).line(for: "CD1/c.mp3")?.size == 1)
        // Something else with the work folder's name is not taken as one.
        let other = try temporaryFolder("work-store").appendingPathComponent("Other.deckiebuild")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: other.appendingPathComponent("notes.txt"))
        #expect(throws: BuildError.self) { _ = try WorkStore(folder: other, fresh: false) }
    }
}
