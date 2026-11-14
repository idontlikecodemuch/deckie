import Foundation
import Testing
import DeckieCrate
import DeckieRecognition
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

    /// A record keeps its fingerprint (D35): the bytes beside it, who made it when in the record. A record made
    /// before the fingerprint has none and can be given one; one whose bytes are gone reads as having none.
    @Test func keepsARecordsFingerprintBesideIt() throws {
        let folder = try temporaryFolder("work-store-print").appendingPathComponent("Test.deckiebuild")
        let store = try WorkStore(folder: folder, fresh: true)
        var t = Self.track()
        try store.save(.init(engine: "k", bpmTag: nil, track: t, bars: t.bars?.series, style: t.style?.values))
        #expect(store.record(t.id)?.track.fingerprint == nil)
        #expect(WorkRecords.fingerprint(t.id, in: store.recordsFolder) == nil)

        let landmarks = Landmarks(frames: [1, 5, 5, 400], pitches: [10, 0x4020, 0xC030, 7000], frameCount: 500)
        let print = CrateTrack.Fingerprint(landmarks, madeBy: "linux-x86_64", madeAt: "2026-11-14T10:00:00Z")
        #expect(try WorkRecords.keep(print, id: t.id, in: store.recordsFolder))
        #expect(try !WorkRecords.keep(print, id: "ffffffffffffffff", in: store.recordsFolder))
        t.fingerprint = print
        let back = try #require(store.record(t.id))
        #expect(back.crateTrack == t && back.track.fingerprint?.landmarks == landmarks)
        #expect(try Data(contentsOf: WorkRecords.fingerprintURL(t.id, in: store.recordsFolder)) == landmarks.encoded())
        let probe = CrateManifest(crateId: "x", name: "x", createdAt: "2026-10-28T12:00:00Z", devicesSeen: [])
        #expect(try CrateWriter.encode(Crate(manifest: probe, tracks: [back.crateTrack]))["prints/\(t.id).dkl"] == landmarks.encoded())

        // The bytes gone, or not the ones the record lists: no fingerprint, so the builder makes it again.
        try Data("DKL2".utf8).write(to: WorkRecords.fingerprintURL(t.id, in: store.recordsFolder))
        #expect(store.record(t.id) != nil && store.record(t.id)?.track.fingerprint == nil)
        try FileManager.default.removeItem(at: WorkRecords.fingerprintURL(t.id, in: store.recordsFolder))
        #expect(store.record(t.id)?.track.fingerprint == nil)
        // A line from before the fingerprint reads with no word on it.
        try store.append(.init(rel: "CD1/a.mp3", size: 10, modified: 2, status: "ok", engine: "k", id: t.id))
        try store.append(.init(rel: "CD1/b.mp3", size: 10, modified: 2, status: "ok", engine: "k", id: t.id, fingerprint: true))
        let again = try WorkStore(folder: folder, fresh: false)
        #expect(again.line(for: "CD1/a.mp3")?.fingerprint == nil && again.line(for: "CD1/b.mp3")?.fingerprint == true)
    }
}
