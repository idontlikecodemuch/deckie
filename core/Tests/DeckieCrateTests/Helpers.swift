import Foundation
import DeckieCrate

/// Where the lab's files and the example crate are, relative to this source file (core/Tests/DeckieCrateTests/).
enum Paths {
    static let testsDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    static let core = testsDir.deletingLastPathComponent().deletingLastPathComponent()
    static let root = core.deletingLastPathComponent()
    static let features = root.appendingPathComponent("mixer/features")
    static let candidates = root.appendingPathComponent("mixer/candidates.json")
    static let example = core.appendingPathComponent("fixtures/example.deckiecrate")
}

/// A crate with every block filled, two tracks, a style vector, key changes and one signature listed.
func sampleCrate() -> Crate {
    let engine = CrateTrack.Engine(family: CrateFormat.EngineFamily.deckie, version: "0.1", platform: "linux-x86_64", fidelity: 1,
                                   models: [.init(name: "beat-this-small", version: "1", weightsSha256: "ab12")],
                                   decoder: .init(name: "dr_mp3", version: "0.7.4"))
    func track(_ id: String, bars n: Int, title: String) -> CrateTrack {
        CrateTrack(
            id: id,
            file: .init(name: "\(title).mp3", rel: "CD1/\(title).mp3", bytes: 9_123_456, sha1Head: "f00d",
                        durationS: 224.0),
            ident: .init(title: title, artist: "Artist \u{e9}", version: nil, source: "tag", disc: "CD1",
                         folder: "3 - 120ish", track: 7, cutKey: "artist \(title)", isLongest: true, era: "90s",
                         kind: "remix", tags: ["halloween"]),
            analysis: .init(engine: "deckie-0.1", analysedAt: "2026-10-28T12:00:00Z", device: "linux-x86_64",
                            secs: 18.42, level: 1),
            engine: engine,
            grid: .init(source: "beat-this-small", confidence: 0.93, bpm: 125.0, firstDownbeatS: 0.0412, nBars: n,
                        fitMadMs: 9.1, bpmIn: 125.0, bpmOut: 124.82, inTrusted: true, outTrusted: false),
            tempoSegments: [.init(startBar: 1, startS: 0.0412, bpm: 125.0, beatsPerBar: 4, beatInBar: 1, confidence: 0.93),
                            .init(startBar: 33, startS: 61.4812, bpm: 124.5, beatsPerBar: 4, beatInBar: 1, confidence: nil)],
            key: .init(source: "votes", confidence: 0.65, camelot: "7A", key: "D", scale: "minor",
                       votes: ["apple-mu": "7A", "key-lite": "8A"],
                       changes: [.init(startBar: 1, endBar: 33, camelot: "7A"), .init(startBar: 33, endBar: n + 1, camelot: "8A")]),
            phrase: .init(source: "foote-novelty", confidence: 0.8, latticePhaseBar: 1, boundariesBars: [1, 9, 25, n + 1]),
            sections: [.init(startBar: 1, endBar: 9, label: "intro", energy: "low"),
                       .init(startBar: 9, endBar: n + 1, label: "main", energy: "high")],
            mixIn: .init(startBar: 1, endBar: 17, vocalFreeBars: 16),
            mixOut: .init(startBar: n - 15, endBar: n + 1, vocalFreeBars: nil),
            ends: .init(firstSoundS: 0.0, lastSoundS: 223.1, fadeOut: false, fadeStartBar: nil, steadyInBar: 1,
                        steadyOutBar: n + 1),
            loudness: .init(source: "deckie-core", confidence: nil, integratedLufs: -8.2, lra: 5.1, truePeakDb: -0.1),
            vocal: .init(source: "apple-mu", confidence: 0.75, mean: 0.6213, heavy: false),
            onsetPattern16: (0..<16).map { Double($0 % 4 == 0 ? 1 : $0) / 16 },
            flags: ["short_outro", "tempo_change"],
            style: .init(model: "style-v1", values: (0..<64).map { sin(Double($0)) }),
            signatures: ["o": .init(madeBy: "iPad13,1", madeAt: "2026-10-29T08:00:00Z")],
            bars: BarSeries([BarSeries.lufs: (0..<n).map { -20 + Double($0 % 7) * 0.37 },
                             BarSeries.vocal: (0..<n).map { Double($0 % 10) / 10 },
                             BarSeries.drum: (0..<n).map { Double($0 % 3) / 3 }]))
    }
    var second = track("b2", bars: 40, title: "Second")
    second.signatures = [:]
    second.style = nil
    second.key?.changes = nil
    return Crate(manifest: CrateManifest(crateId: "0f6c1e2a", name: "Sample", createdAt: "2026-10-28T12:00:00Z",
                                         devicesSeen: ["linux-x86_64"]),
                 tracks: [track("a1", bars: 115, title: "First"), second])
}

/// `files` with an empty stand-in for each signature the crate lists (the reader only checks the file is there).
func withSignatureFiles(_ files: [String: Data], _ crate: Crate) -> [String: Data] {
    var f = files
    for t in crate.tracks { for v in t.signatures.keys { f["signatures/\(t.id)_\(v).shazamsignature"] = Data([0]) } }
    return f
}

/// crate.json edited as JSON: `edit` gets the decoded object and changes it.
func editTracks(_ files: [String: Data], _ edit: (inout [String: Any]) -> Void) throws -> [String: Data] {
    var obj = try JSONSerialization.jsonObject(with: files["crate.json"]!) as! [String: Any]
    edit(&obj)
    var f = files
    f["crate.json"] = try JSONSerialization.data(withJSONObject: obj)
    return f
}

/// Sets `value` at a path of keys and list indexes inside a JSON object, `nil` removing the key.
func set(_ obj: inout [String: Any], _ path: [Any], _ value: Any?) {
    func go(_ node: Any, _ rest: ArraySlice<Any>) -> Any? {
        guard let head = rest.first else { return value }
        if var d = node as? [String: Any], let k = head as? String {
            d[k] = go(d[k] as Any, rest.dropFirst())
            return d
        }
        if var a = node as? [Any], let i = head as? Int {
            a[i] = go(a[i], rest.dropFirst()) as Any
            return a
        }
        preconditionFailure("bad path \(path)")
    }
    obj = go(obj, path[...]) as! [String: Any]
}

/// The problems a read gives, or none.
func readProblems(_ files: [String: Data]) -> [CrateProblem] {
    do {
        _ = try CrateReader.decode(files)
        return []
    } catch let e as CrateError {
        return e.problems
    } catch {
        return [CrateProblem(file: "?", path: "", message: "\(error)")]
    }
}

/// A fresh empty folder under the system's temporary folder.
func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-crate-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
